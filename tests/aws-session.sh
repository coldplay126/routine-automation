#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
sandbox=$(mktemp -d '/tmp/aws-session-tests.XXXXXXXX')
trap 'rm -rf -- "$sandbox"' EXIT
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" XDG_CONFIG_HOME="$sandbox/config"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export ROUTINE_NOW='2026-09-28T08:00:00+09:00' ROUTINE_TZ=Asia/Seoul
export AWS_RECORD="$sandbox/aws-calls" AWS_TIMEOUT_RECORD="$sandbox/timeouts" AWS_NOTICES="$sandbox/notices" AWS_LOGIN_STATE="$sandbox/login-state"
mkdir -p "$HOME/.local/bin" "$TMPDIR" "$XDG_CONFIG_HOME" "$AWS_LOGIN_STATE"
ln -s "${TEST_JQ_BIN:-$(type -P jq)}" "$HOME/.local/bin/jq"
# shellcheck source=common.sh
source "$repo/tests/common.sh"
cat > "$HOME/.local/bin/aws" <<'AWS'
#!/usr/bin/env bash
set -euo pipefail
printf 'aws %s\n' "$*" >> "$AWS_RECORD"
profile=''
for ((i=1;i<=$#;i++)); do
  if [[ ${!i} == --profile ]]; then next=$((i+1)); profile=${!next}; break; fi
done
[[ ${1:-} != --profile ]] || shift 2
case ${1:-} in
  login) touch "$AWS_LOGIN_STATE/$profile"; exit 0 ;;
  sts)
    [[ ${2:-} == get-caller-identity ]] || exit 87
    case ${AWS_STUB_MODE:-valid} in
      expired) [[ -f $AWS_LOGIN_STATE/$profile ]] || { echo 'session has expired' >&2; exit 1; } ;;
      error) echo 'network unavailable' >&2; exit 1 ;;
      mismatch) echo 'other-account other-arn'; exit 0 ;;
      mixed)
        if [[ $profile == fixture-alpha ]]; then echo 'session has expired' >&2; exit 1
        else echo 'other-account other-arn'; exit 0; fi ;;
    esac
    echo 'fixture-account fixture-arn' ;;
  *) exit 87 ;;
esac
AWS
# The outside checker owns profiles and expected identities; morning must reuse it unchanged.
cat > "$HOME/.local/bin/aws-session-check" <<'CHECK'
#!/bin/zsh
set -u
exit_status=0
profiles=(fixture-alpha fixture-beta)
[[ ${AWS_CHECKER_MODE:-} != profile-value ]] || profiles=(login)
for profile in "${profiles[@]}"; do
  identity_command=(aws sts get-caller-identity --profile "$profile" --query '[Account,Arn]' --output text)
  if [[ ${AWS_CHECKER_MODE:-} == query-value ]]; then identity_command=(aws sts get-caller-identity --profile "$profile" --query login --output text); fi
  if [[ ${AWS_CHECKER_MODE:-} == profile-value ]]; then identity_command=(aws --profile "$profile" sts get-caller-identity --query '[Account,Arn]' --output text); fi
  if ! identity="$("${identity_command[@]}" 2>&1)"; then
    if [[ $identity != *'session has expired'* ]]; then
      print -u2 -r -- "$profile: $identity"
      exit_status=1
      continue
    fi
    print -r -- "$profile: session expired; starting aws login"
    if [[ ${AWS_CHECKER_MODE:-} == bypass ]]; then print -r -- 'starting aws login'; continue; fi
    login_command=(aws login --profile "$profile")
    if [[ ${AWS_CHECKER_MODE:-} == global-options ]]; then login_command=(aws --region fixture-region --profile="$profile" login); fi
    if [[ ${AWS_CHECKER_MODE:-} == positional-prefix ]]; then login_command=(aws --unknown-option fixture-value login --profile "$profile"); fi
    if [[ ${AWS_CHECKER_MODE:-} == profile-prefix ]]; then login_command=(aws --profile "$profile" login); fi
    if [[ ${AWS_CHECKER_MODE:-} == boolean-prefix ]]; then login_command=(aws --debug login --profile "$profile"); fi
    if [[ ${AWS_CHECKER_MODE:-} == binary-format-prefix ]]; then login_command=(aws --cli-binary-format raw-in-base64-out login --profile "$profile"); fi
    if ! "${login_command[@]}"; then
      print -u2 -r -- "$profile: aws login failed"
      exit_status=1
      continue
    fi
    identity="$(aws sts get-caller-identity --profile "$profile" --query '[Account,Arn]' --output text)" || { exit_status=1; continue; }
  fi
  if [[ $identity != 'fixture-account fixture-arn' ]]; then
    print -u2 -r -- "$profile: unexpected identity: $identity"
    exit_status=1
    continue
  fi
  print -r -- "$profile: valid (fixture-account)"
done
exit "$exit_status"
CHECK
cat > "$HOME/.local/bin/gtimeout" <<'TIMEOUT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$AWS_TIMEOUT_RECORD"
[[ ( $1 == -k && $2 == 2 && ( $3 == 15 || $3 == 60 ) ) || ( $1 == -k && $2 == 30 && $3 == 600 ) ]] || exit 87
limit=$3
shift 3
if [[ ${AWS_STUB_MODE:-} == query-timeout && $limit == 15 ]]; then exit 124; fi
exec "$@"
TIMEOUT
cat > "$HOME/.local/bin/osascript" <<'NOTIFY'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWS_NOTICES"
NOTIFY
chmod +x "$HOME/.local/bin/"{aws,aws-session-check,gtimeout,osascript}
[[ $(type -P aws) == "$HOME/.local/bin/aws" && $(type -P aws-session-check) == "$HOME/.local/bin/aws-session-check" ]] || fail 'Refusing real AWS tools'
checker_hash=$(shasum -a 256 "$HOME/.local/bin/aws-session-check")
reset() { : > "$AWS_RECORD"; : > "$AWS_TIMEOUT_RECORD"; : > "$AWS_NOTICES"; }
reset
start=$(date +%s)
AWS_STUB_MODE=expired "$repo/bin/morning" --only aws-session > "$sandbox/expired"
[[ $(($(date +%s)-start)) -lt 10 ]] || fail 'Expired AWS check did not finish promptly'
grep -Fq 'aws-session:로그인 필요(' "$sandbox/expired" || fail 'Expired AWS was not marked login-needed'
! grep -q '^aws login ' "$AWS_RECORD" || fail 'Unattended AWS opened login'
[[ $(grep -c '^aws sts get-caller-identity ' "$AWS_RECORD") == 2 ]] || fail 'Outside checker profiles were not reused'
grep -Fq 'AWS 로그인 필요: fixture-alpha, fixture-beta — 터미널에서 aws-session-check 실행' "$AWS_NOTICES" || fail 'Login-needed notice omitted profiles/manual action'
! grep -Eq '실패:|모든 단계 완료' "$AWS_NOTICES" || fail 'Login-needed counted as failure or completed work'
[[ $(grep -c '^-k 2 15 ' "$AWS_TIMEOUT_RECORD") == 2 && $(grep -c '^-k 2 60 ' "$AWS_TIMEOUT_RECORD") == 1 ]] || fail 'AWS calls or stage lack short timeout'
[[ $(shasum -a 256 "$HOME/.local/bin/aws-session-check") == "$checker_hash" ]] || fail 'Outside checker was modified'
leftovers=("$TMPDIR"/routine-aws-session.*)
[[ ! -e ${leftovers[0]} ]] || fail 'Temporary AWS wrapper was not removed'
for mode in global-options positional-prefix profile-prefix boolean-prefix binary-format-prefix; do
  reset
  AWS_STUB_MODE=expired AWS_CHECKER_MODE=$mode "$repo/bin/morning" --only aws-session > "$sandbox/$mode"
  grep -Fq 'aws-session:로그인 필요(' "$sandbox/$mode" || fail "Login token was not blocked/classified: $mode"
  [[ $(grep -c '^aws ' "$AWS_RECORD") == 2 && $(grep -c '^aws sts get-caller-identity ' "$AWS_RECORD") == 2 ]] || fail "Login token bypassed the AWS wrapper: $mode"
  grep -Fq 'AWS 로그인 필요: fixture-alpha, fixture-beta — 터미널에서 aws-session-check 실행' "$AWS_NOTICES" || fail "Login token block lost profile names: $mode"
done
for mode in query-value profile-value; do
  reset
  AWS_STUB_MODE=valid AWS_CHECKER_MODE=$mode "$repo/bin/morning" --only aws-session > "$sandbox/$mode"
  grep -Fq 'aws-session:ok(' "$sandbox/$mode" || fail "Option value login was blocked: $mode"
  ! grep -Fq 'AWS 로그인 필요' "$AWS_NOTICES" || fail "Option value login was marked login-needed: $mode"
  if [[ $mode == query-value ]]; then
    [[ $(grep -c '^aws sts get-caller-identity .*--query login ' "$AWS_RECORD") == 2 ]] || fail 'Query value login was not delegated unchanged'
  else
    [[ $(grep -c '^aws --profile login sts get-caller-identity ' "$AWS_RECORD") == 1 ]] || fail 'Profile value login was not delegated unchanged'
  fi
  [[ $(grep -c '^-k 2 15 ' "$AWS_TIMEOUT_RECORD") == $(grep -c '^aws ' "$AWS_RECORD") ]] || fail "Delegated identity check lost its timeout: $mode"
done
# A user's zsh startup file must not replace the wrapper PATH for the external checker.
export AWS_ZSHENV_MARKER="$sandbox/zshenv-read" AWS_BYPASS_BIN="$sandbox/bypass-bin"
mkdir "$AWS_BYPASS_BIN"
cat > "$HOME/.zshenv" <<'ZSHENV'
print -r -- loaded > "$AWS_ZSHENV_MARKER"
export PATH="$AWS_BYPASS_BIN:$PATH"
ZSHENV
cat > "$AWS_BYPASS_BIN/aws" <<'BYPASS'
#!/usr/bin/env bash
printf 'bypass %s\n' "$*" >> "$AWS_RECORD"
exit 87
BYPASS
chmod +x "$AWS_BYPASS_BIN/aws"
reset
AWS_STUB_MODE=expired "$repo/bin/morning" --only aws-session > "$sandbox/zshenv"
[[ ! -e $AWS_ZSHENV_MARKER ]] || fail 'External checker loaded user zsh startup file'
grep -Fq 'aws-session:로그인 필요(' "$sandbox/zshenv" || fail 'zsh PATH isolation lost login-needed classification'
! grep -q '^bypass ' "$AWS_RECORD" || fail 'zsh startup bypassed the AWS wrapper'
rm "$HOME/.zshenv"
reset
if AWS_STUB_MODE=expired AWS_CHECKER_MODE=bypass "$repo/bin/morning" --only aws-session > "$sandbox/bypass"; then fail 'Unmarked login attempt was successful'; fi
grep -Fq 'aws-session:fail(' "$sandbox/bypass" || fail 'Unmarked login attempt was not a failure'
grep -Fq '실패: aws-session' "$AWS_NOTICES" || fail 'Unmarked login attempt omitted failure count'
grep -Fq 'AWS 로그인 차단 우회 의심' "$AWS_NOTICES" || fail 'Unmarked login attempt lacks bypass warning'
! grep -q '^aws login ' "$AWS_RECORD" || fail 'Bypass diagnostic fixture invoked login'
reset
AWS_STUB_MODE=valid "$repo/bin/morning" --only aws-session > "$sandbox/valid"
grep -Fq 'aws-session:ok(' "$sandbox/valid" || fail 'Valid AWS check did not succeed'
! grep -q '^aws login ' "$AWS_RECORD" || fail 'Valid AWS check opened login'
! grep -Fq 'AWS 로그인 필요' "$AWS_NOTICES" || fail 'Valid AWS check claimed login-needed'
for mode in error mismatch query-timeout mixed; do
  reset
  if AWS_STUB_MODE=$mode "$repo/bin/morning" --only aws-session > "$sandbox/$mode"; then fail "AWS error was hidden: $mode"; fi
  grep -Fq 'aws-session:fail(' "$sandbox/$mode" || fail "AWS error was misclassified: $mode"
  grep -Fq '실패: aws-session' "$AWS_NOTICES" || fail "AWS failure count omitted: $mode"
  ! grep -q '^aws login ' "$AWS_RECORD" || fail "AWS error started login: $mode"
done
# AWS's manual action stays on the final line, separate from scrum's send prohibition.
mkdir -p "$sandbox/morning-copy/bin"
cp "$repo/bin/morning" "$sandbox/morning-copy/bin/morning"
ln -s "$repo/share" "$sandbox/morning-copy/share"
cat > "$sandbox/morning-copy/bin/scrum-draft" <<'DRAFT'
#!/usr/bin/env bash
exit 0
DRAFT
cat > "$sandbox/morning-copy/bin/scrum-paste" <<'PASTE'
#!/usr/bin/env bash
mkdir -p "$HOME/Library/Application Support/routine-automation/scrum"
touch "$HOME/Library/Application Support/routine-automation/scrum/2026-09-28.paste-attention"
exit 3
PASTE
chmod +x "$sandbox/morning-copy/bin/"{scrum-draft,scrum-paste}
reset
AWS_STUB_MODE=expired "$sandbox/morning-copy/bin/morning" --only scrum-draft --only scrum-paste --only aws-session > "$sandbox/notice-order"
grep -Fq 'aws-session:로그인 필요(' "$sandbox/notice-order" || fail 'Combined scrum/AWS run lost login-needed status'
! grep -Fq '실패:' "$AWS_NOTICES" || fail 'Combined scrum/AWS run counted blocked login as a failure'
jq -Rse 'split("\n")|map(select(length>0))|
  .[-1]=="AWS 로그인 필요: fixture-alpha, fixture-beta — 터미널에서 aws-session-check 실행" and
  (.[0:-1]|any(.[];contains("스크럼") and contains("전송 금지")))' "$AWS_NOTICES" >/dev/null || fail 'AWS manual-action line was not last/separate from scrum notice'
leftovers=("$TMPDIR"/routine-aws-session.*)
[[ ! -e ${leftovers[0]} ]] || fail 'AWS wrapper survived completion of the stage'
# Manual use keeps the existing login behavior and still verifies the expected identities.
reset
AWS_STUB_MODE=expired "$HOME/.local/bin/aws-session-check" > "$sandbox/manual"
[[ $(grep -c '^aws login ' "$AWS_RECORD") == 2 && ! -s $AWS_TIMEOUT_RECORD ]] || fail 'Manual checker behavior changed'
reset
mv "$HOME/.local/bin/aws-session-check" "$sandbox/removed-checker"
if "$repo/bin/morning" --only aws-session > "$sandbox/missing"; then fail 'Missing checker was successful'; fi
grep -Eq 'aws-session:fail\(.*exit 127\)' "$sandbox/missing" || fail 'Missing checker handling changed'
grep -Fq '실패: aws-session' "$AWS_NOTICES" || fail 'Missing checker no longer counted as failure'
[[ ! -s $AWS_RECORD ]] || fail 'Missing checker invoked AWS'
echo 'PASS: morning AWS no-login/global-options/zsh isolation/bypass detection, short identity checks, final-line notices, unchanged manual checker, failures and missing checker'
