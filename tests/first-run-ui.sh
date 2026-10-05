#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
real_jq=${TEST_JQ_BIN:-$(type -P jq)}
while IFS= read -r name; do [[ $name != ROUTINE_* ]] || unset "$name"; done < <(compgen -v)
sandbox=$(mktemp -d /tmp/routine-first-run-ui.XXXXXXXX)
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" PATH="$sandbox/stubs:/usr/bin:/bin" TZ=Asia/Seoul
export ROUTINE_CONFIG="$HOME/.config/routine-automation/config.json" RECORD="$sandbox/record"
export PTY_TTY_STATE="$repo/tests/fixtures/tty-state.sh"
export FIRST_RUN_FIXTURE="$sandbox/morning" FIRST_RUN_DAY=2026-09-28 ROUTINE_NOW='2026-09-28T09:00:00+09:00'
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
cleanup() {
  local pid
  if [[ -f $RECORD.morning-pid ]]; then IFS= read -r pid < "$RECORD.morning-pid"; kill "$pid" 2>/dev/null || true; fi
  rm -rf "$sandbox"
}
trap cleanup EXIT
mkdir -p "$sandbox/stubs" "$TMPDIR" "$sandbox/repos" "$HOME/.local/share/routine-automation" "$HOME/Library/Logs/routine-automation"
ln -s "$real_jq" "$sandbox/stubs/jq"
cp "$repo/VERSION" "$HOME/.local/share/routine-automation/VERSION"
for cmd in brew open osascript orca claude omp gh; do
  printf '#!/bin/bash\nexit 87\n' > "$sandbox/stubs/$cmd"
done
# No interactive input uses gum here; still isolate optional success-box styling.
printf '#!/bin/bash\nexit 1\n' > "$sandbox/stubs/gum"
cat > "$sandbox/stubs/launchctl" <<'STUB'
#!/bin/bash
[[ $1 == kickstart ]] || exit 87
printf '%s\n' "$PPID" > "$RECORD.setup-pid"
stty -a < /dev/tty > "$RECORD.spinner-mode"
# Model a LaunchAgent, which survives closure of setup's controlling terminal.
/usr/bin/nohup /bin/bash "$FIRST_RUN_FIXTURE" < /dev/null > "$RECORD.morning-output" 2>&1 &
printf '%s\n' "$!" > "$RECORD.morning-pid"
STUB
cat > "$FIRST_RUN_FIXTURE" <<'MORNING'
#!/bin/bash
set -euo pipefail
root="$HOME/Library/Application Support/routine-automation"
log="$HOME/Library/Logs/routine-automation/morning-$(date '+%Y-%m-%d').log"
request=$(cat "$root/.setup-first-run")
printf '%s START scrum-collect\n' "$(date '+%FT%T%z')" >> "$log"
printf 'COLLECT %s START git\n' "$(date '+%FT%T%z')" >> "$log"
sleep 1
printf 'COLLECT %s END git ok\nCOLLECT %s START prs\n' "$(date '+%FT%T%z')" "$(date '+%FT%T%z')" >> "$log"
sleep 1
printf 'COLLECT %s END prs ok\nCOLLECT %s START sessions\n' "$(date '+%FT%T%z')" "$(date '+%FT%T%z')" >> "$log"
sleep 1
printf 'COLLECT %s END sessions ok\n%s END scrum-collect ok 68s exit=0\n' "$(date '+%FT%T%z')" "$(date '+%FT%T%z')" >> "$log"
# Write a START across two appends to exercise regular-file EOF buffering.
printf '%s START scrum-' "$(date '+%FT%T%z')" >> "$log"
sleep 0.4
printf 'draft\n' >> "$log"
sleep 2
printf '%s END scrum-draft ok 45s exit=0\n' "$(date '+%FT%T%z')" >> "$log"
mkdir -p "$root/scrum"
printf '{}\n' > "$root/scrum/$FIRST_RUN_DAY.draft.json"
jq -n --arg request "$request" '{request_id:$request,exit_code:0,full_disk_access:{status:"unverified"}}' > "$root/.setup-first-run-result.json.tmp"
mv "$root/.setup-first-run-result.json.tmp" "$root/.setup-first-run-result.json"
rm "$root/.setup-first-run"
printf '완료\n' > "$RECORD.morning-finished"
MORNING
cat > "$sandbox/tty-command" <<'HELPER'
#!/bin/bash
stty rows 30 cols "${FIRST_RUN_COLUMNS:-110}"
for ((line=0; line<35; line++)); do printf '기존 터미널 출력 %s\n' "$line"; done
tty > "$RECORD.tty-path"
/bin/bash "$PTY_TTY_STATE" > "$RECORD.before"
"$@"; status=$?
/bin/bash "$PTY_TTY_STATE" > "$RECORD.after"
if cmp -s "$RECORD.before" "$RECORD.after"; then printf 'TTY_RESTORED=1\n'; fi
printf 'SETUP_RC=%s\n' "$status"
exit "$status"
HELPER
chmod +x "$sandbox/stubs/"*
"$repo/bin/routine-init" --non-interactive --slack-link https://example.slack.com/archives/CEXAMPLE/p1790895609247049 --slack-team-id TEXAMPLE --identity-git-authors '["fixture@example.com"]' --sources-git-roots "$(jq -nc --arg root "$sandbox/repos" '[$root]')" --sources-prs-enabled false --sources-omp-sessions-enabled false --sources-claude-sessions-enabled false --sources-jira-enabled false --sources-notion-enabled false --draft-llm-engine none > /dev/null
log="$HOME/Library/Logs/routine-automation/morning-$(date '+%Y-%m-%d').log"
for mode in success narrow skip int term quit hup tstp; do
  rm -f "$HOME/Library/Logs/routine-automation/setup-state.json" "$RECORD.morning-finished"
  # A stale stage and a partial old line must not enter this request's progress.
  printf '%s START aws-session\n%s END scrum-collect ok 999s exit=0\nold partial ' "$(date '+%FT%T%z')" "$(date '+%FT%T%z')" > "$log"
  export FIRST_RUN_COLUMNS=110
  [[ $mode != narrow ]] || FIRST_RUN_COLUMNS=48
  /usr/bin/expect "$repo/tests/fixtures/first-run-pty.exp" "$repo/bin/routine-setup" "$sandbox/tty-command" "$sandbox/$mode.tty" "$mode" > /dev/null || { cat "$sandbox/$mode.tty" "$RECORD.before" "$RECORD.after" >&2; fail "첫 실행 PTY: $mode"; }
  grep -q -- '-icanon' "$RECORD.spinner-mode" || fail '스피너가 비밀번호 입력 모드(icanon)를 유지함'
  jq -Rse 'gsub("\u001b\\[[0-9;]*m";"")|contains("보통 1~3분 · s 키:") and contains("TTY_RESTORED=1") and (contains("AWS 세션 확인 중")|not) and (contains("999s")|not) and (rindex("\u001b[?25h") > rindex("\u001b[?25l"))' "$sandbox/$mode.tty" >/dev/null || fail "진행 안내·기존 로그 격리·커서 복원: $mode"
  if [[ $mode == tstp ]]; then cmp -s "$RECORD.before" "$RECORD.suspended" || fail '일시정지 중 입력 상태 미복원'; fi
  if [[ $mode == success || $mode == narrow || $mode == skip ]]; then
    jq -Rsf "$repo/tests/terminal-screen.jq" "$sandbox/$mode.tty" > "$sandbox/$mode.screen"
    jq -L "$repo/tests" -e 'include "setup-screen"; setup_once and all(.[];contains("보통 1~3분")|not)' "$sandbox/$mode.screen" >/dev/null || fail "최종 체크리스트 중복·대기 안내 잔여: $mode"
  fi
  if [[ $mode == success ]]; then
    jq -Rse 'gsub("\u001b\\[[0-9;]*m";"")|test("git ✓ · PR ✓ · omp 세션 …") and test("수집 68s · 초안 작성 중 \\(LLM\\) · 0:[0-9]{2}")' "$sandbox/$mode.tty" >/dev/null || fail '수집 소스·초안 단계 전환 또는 완료 시간 누락'
  elif [[ $mode == narrow ]]; then
    jq -Rse 'gsub("\u001b\\[[0-9;]*m";"")|test("첫 실행[^\\r\\n]*초안 작성 중 \\(LLM\\) · 0:[0-9]{2}") and (test("수집 68s · 초안 작성 중")|not)' "$sandbox/$mode.tty" >/dev/null || fail '좁은 화면에서 현재 단계만 표시하지 않음'
  fi
  if [[ $mode == skip ]]; then
    jq -L "$repo/tests" -e 'include "setup-screen"; any(setup_rows[];.label=="첫 실행" and .marker=="–")' "$sandbox/$mode.screen" >/dev/null || fail 's 키가 첫 실행 대기를 건너뛰지 않음'
    IFS= read -r pid < "$RECORD.morning-pid"
    kill -0 "$pid" || fail 's 키가 진행 중 서비스를 중단함'
    for ((attempt=0; attempt<40; attempt++)); do [[ ! -f $RECORD.morning-finished ]] || break; sleep 0.2; done
    [[ -f $RECORD.morning-finished ]] || fail '대기 건너뛰기 뒤 서비스가 완료되지 않음'
  fi
  IFS= read -r pid < "$RECORD.morning-pid"; kill "$pid" 2>/dev/null || true
  rm -f "$RECORD.morning-pid"
done
printf 'PASS: 첫 실행 단계·소스 진행, 좁은 화면, s 키, 비정규 입력·커서/신호 복원\n'
