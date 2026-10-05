#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
real_jq=${TEST_JQ_BIN:-$(type -P jq)}
while IFS= read -r name; do [[ $name != ROUTINE_* ]] || unset "$name"; done < <(compgen -v)
sandbox=$(mktemp -d /tmp/routine-gum-tests.XXXXXXXX)
sandbox=$(cd -- "$sandbox" && pwd -P)
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" PATH="$sandbox/stubs:/usr/bin:/bin" USER=fixture
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export ROUTINE_CONFIG="$HOME/.config/routine-automation/config.json" ROUTINE_APPLICATIONS_DIR="$sandbox/apps"
export GUM_PRIMARY_ROOT="$HOME/Documents/GitHub" GUM_EXTRA_ROOT="$HOME/manual, repositories"
export GUM_RECORD="$sandbox/gum.calls" GUARD_RECORD="$sandbox/guard.calls"
mkdir -p "$sandbox/stubs" "$TMPDIR" "$ROUTINE_APPLICATIONS_DIR" "$GUM_PRIMARY_ROOT/repo" "$GUM_EXTRA_ROOT/repo" "$HOME/.omp/agent/sessions"
mkdir -p "$HOME/.local/bin"
ln -s "$real_jq" "$sandbox/stubs/jq"
ln -s "$sandbox/stubs/jq" "$HOME/.local/bin/jq"
ln -s "$sandbox/stubs/gtimeout" "$HOME/.local/bin/gtimeout"
ln -s "$sandbox/stubs/gum" "$HOME/.local/bin/gum"
for root in "$GUM_PRIMARY_ROOT" "$GUM_EXTRA_ROOT"; do /usr/bin/git init -q "$root/repo"; done
for cmd in gh brew open orca claude omp launchctl osascript; do
  cat > "$sandbox/stubs/$cmd" <<'STUB'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >> "$GUARD_RECORD"
exit 87
STUB
  chmod +x "$sandbox/stubs/$cmd"
  ln -s "$sandbox/stubs/$cmd" "$HOME/.local/bin/$cmd"
done
cat > "$sandbox/stubs/gtimeout" <<'STUB'
#!/bin/bash
shift 3
exec "$@"
STUB
chmod +x "$sandbox/stubs/gtimeout"
cp "$repo/tests/fixtures/gum-stub.sh" "$sandbox/stubs/gum"
cat > "$sandbox/pty-command" <<'HELPER'
#!/bin/bash
before=$(stty -g)
"$@"
rc=$?
after=$(stty -g)
if [[ $before == "$after" ]]; then echo 'TTY_RESTORED=1'; else echo 'TTY_RESTORED=0'; fi
printf 'PTY_RC=%s\n' "$rc"
HELPER
chmod +x "$sandbox/pty-command"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pty() { /usr/bin/expect "$repo/tests/fixtures/gum-pty.exp" "$sandbox/pty-command" "$sandbox/$1.tty" "$1" "${@:2}" > /dev/null || { cat "$sandbox/$1.tty" >&2; fail "gum PTY: $1"; }; }
# Prepare valid saved values using batch init; gum must not run without a TTY.
roots=$(jq -nc --arg root "$GUM_PRIMARY_ROOT" '[$root]')
"$repo/bin/routine-init" --non-interactive --slack-link https://example.slack.com/archives/CEXAMPLE/p1790895609247049 --slack-team-id TEXAMPLE --identity-git-authors '["fixture@example.com"]' --sources-git-roots "$roots" --sources-prs-enabled false --draft-llm-engine none --timezone Asia/Seoul > /dev/null
[[ ! -e $GUM_RECORD ]] || fail 'Batch init invoked gum'
cp "$ROUTINE_CONFIG" "$sandbox/original.json"
share_dir="$repo/share"
# shellcheck source=../share/ui.sh
source "$share_dir/ui.sh"
[[ $(ui_input '질문 금지' '힌트' '기존 값') == '기존 값' ]] || fail 'Non-TTY input discarded the default'
[[ $(ui_choose_many '질문 금지' '[{"value":"git","label":"git"}]' '["git"]') == '["git"]' ]] || fail 'Non-TTY selection changed saved values'
if ui_confirm '질문 금지'; then fail 'Non-TTY confirmation was silently granted'; fi
[[ ! -e $GUM_RECORD ]] || fail 'Non-TTY wrappers invoked gum'
setup_args=(--skip platform --skip dependencies --skip github --skip llm --skip slack --skip orca --skip disk-access --skip launchd --skip first-run --overwrite-config)
# This executes setup's real config FIFO/tee branch. Add a comma/space path, then
# deselect the old location, reject unauthenticated PRs and explicitly reselect.
export GUM_MODE=add
pty add "$repo/bin/routine-setup" "${setup_args[@]}"
jq -e --arg root "$GUM_EXTRA_ROOT" '.sources.git.roots==[$root] and .sources.git.enabled and .sources.omp_sessions.enabled and (.sources.prs.enabled|not)' "$ROUTINE_CONFIG" >/dev/null || fail 'Gum choices/addition were not saved'
jq -se 'all(.[];.tty)' "$GUM_RECORD" >/dev/null || fail 'Gum 화면이 제어 터미널이 아닌 FIFO/stdout으로 출력됨'
# Empty root selection keeps the existing explicit confirmation and Git repair.
for mode in recover empty; do
  cp "$sandbox/original.json" "$ROUTINE_CONFIG"; rm -f "$GUM_RECORD" "$GUM_RECORD.roots" "$GUM_RECORD.sources"
  export GUM_MODE=$mode
  pty "$mode" "$repo/bin/routine-setup" "${setup_args[@]}"
  jq -e --arg root "$GUM_PRIMARY_ROOT" '.sources.git.roots==[$root] and .sources.git.enabled' "$ROUTINE_CONFIG" >/dev/null || fail "Root confirmation/repair lost Git: $mode"
  jq -se 'any(.[];.args[0]=="confirm" and (.args|any(.[];startswith("선택된 위치가 없어"))))' "$GUM_RECORD" >/dev/null || fail 'Empty roots bypassed explicit confirmation'
  if [[ $mode == recover ]]; then
    jq -se 'any(.[];.args[0]=="confirm" and (.args|index("Git 저장소 위치를 다시 고를까요?")!=null))' "$GUM_RECORD" >/dev/null || fail 'Unavailable Git did not offer root repair'
  fi
done
# Esc or invalid output in a question preserves that value; at final confirmation
# it cancels the whole save. Ctrl-C always stops setup.
for mode in cancel escape abnormal unknown; do
  cp "$sandbox/original.json" "$ROUTINE_CONFIG"; rm -f "$GUM_RECORD" "$GUM_RECORD.roots" "$GUM_RECORD.sources"
  export GUM_MODE=$mode
  pty "$mode" "$repo/bin/routine-setup" "${setup_args[@]}"
  cmp -s "$sandbox/original.json" "$ROUTINE_CONFIG" || fail "Gum failure changed saved configuration: $mode"
  if [[ $mode == cancel ]]; then
    jq -Rse 'contains("중단했습니다 (Ctrl-C)") and (contains("설정 완료")|not) and contains("PTY_RC=130") and contains("TTY_RESTORED=1")' "$sandbox/$mode.tty" >/dev/null || fail 'Gum Ctrl-C did not stop setup'
  else
    jq -Rse '(contains("설정 완료")|not) and contains("PTY_RC=1") and contains("TTY_RESTORED=1")' "$sandbox/$mode.tty" >/dev/null || fail "Final gum failure did not cancel setup: $mode"
  fi
done
# Final cancellation must discard pending changes, not merely identical answers.
for mode in final-cancel final-escape final-interrupt; do
  cp "$sandbox/original.json" "$ROUTINE_CONFIG"; rm -f "$GUM_RECORD" "$GUM_RECORD.final"
  export GUM_MODE=$mode
  pty "$mode" "$repo/bin/routine-setup" "${setup_args[@]}" --slack-channel-name pending-change
  cmp -s "$sandbox/original.json" "$ROUTINE_CONFIG" || fail "Final cancellation changed file bytes: $mode"
  if [[ $mode != final-interrupt ]]; then
    jq -Rsf "$repo/tests/terminal-screen.jq" "$sandbox/$mode.tty" > "$sandbox/$mode.screen"
    jq -L "$repo/tests" -e 'include "setup-screen"; setup_once and any(setup_rows[];.marker=="✗" and .label=="설정 저장") and all(setup_rows[]|select(.label=="예약 실행 등록" or .label=="첫 실행");.marker=="·" and (.detail|contains("실행 안 함")))' "$sandbox/$mode.screen" >/dev/null || fail '취소 뒤 실패 단계/미실행 단계 또는 단일 체크리스트가 잘못 표시됨'
  fi
done
cp "$sandbox/original.json" "$ROUTINE_CONFIG"; rm -f "$GUM_RECORD" "$GUM_RECORD.final"
export GUM_MODE=edit
pty edit "$repo/bin/routine-setup" "${setup_args[@]}"
jq -e '.identity.git_authors==["edited@example.com","second@example.com"]' "$ROUTINE_CONFIG" >/dev/null || fail 'Edited authors were not saved'
jq -se '
  ([.[]|select(.args[0]=="input" and (.args|index("스크럼 글 링크")!=null))]|length)==1 and
  ([.[]|select(.args[0]=="input" and (.args|index("git 작성자")!=null))]|length)==1 and
  ([.[]|select(.args[0]=="choose" and (.args|index("수집 소스 선택 (Space로 선택, Enter로 확정)")!=null))]|length)==1 and
  ([.[]|select(.args[0]=="choose" and (.args|index("저장 전 최종 확인")!=null))]|length)==2' "$GUM_RECORD" >/dev/null || fail 'Editing replayed unrelated steps or bypassed confirmation'
jq -Rse 'gsub("\u001b\\[[0-9;]*m";"")|contains("설정 1/4 · Slack 글 링크") and contains("설정 2/4 · Git 저장소 위치") and contains("설정 3/4 · 수집 소스") and contains("설정 4/4 · 확인") and contains("예약 시각")' "$sandbox/edit.tty" >/dev/null || fail 'Stage count or review schedule is missing'
jq -Rsf "$repo/tests/terminal-screen.jq" "$sandbox/edit.tty" > "$sandbox/edit.screen"
jq -L "$repo/tests" -e 'include "setup-screen"; setup_once and any(setup_rows[];.marker=="✓" and .label=="설정 저장")' "$sandbox/edit.screen" >/dev/null || fail '저장 뒤 체크리스트가 중복되거나 설정 저장 완료가 누락됨'
# Re-editing Git locations from the final review keeps the current (partial) selection. Two automatic
# candidates (~/Documents/GitHub, ~/dev) both hold repositories; the first pass picks only the primary
# and the re-edit presses Enter without changes.
mkdir -p "$HOME/dev/second" && /usr/bin/git init -q "$HOME/dev/second"
cp "$sandbox/original.json" "$ROUTINE_CONFIG"; rm -f "$GUM_RECORD" "$GUM_RECORD.final" "$GUM_RECORD.roots" "$GUM_RECORD.sources"
GUM_EDIT_TARGET='Git 저장소 위치' GUM_MODE=edit-roots pty edit-roots "$repo/bin/routine-setup" "${setup_args[@]}"
jq -se 'any(.[]; .args[0]=="choose" and (.args|any(.[]; endswith("/dev — 저장소 1개"))))' "$GUM_RECORD" >/dev/null || fail 'Second automatic root was not offered'
jq -e --arg root "$GUM_PRIMARY_ROOT" '.sources.git.roots==[$root]' "$ROUTINE_CONFIG" >/dev/null || { jq -c .sources.git.roots "$ROUTINE_CONFIG" >&2; fail 'Re-editing Git locations re-selected every candidate'; }
[[ $(cat "$GUM_RECORD.roots") == 2 ]] || fail 'Git location edit did not reopen the chooser'
# Empty choices are deliberate too: agree to no locations, re-edit, and press Enter.
cp "$sandbox/original.json" "$ROUTINE_CONFIG"; rm -f "$GUM_RECORD" "$GUM_RECORD.final" "$GUM_RECORD.roots" "$GUM_RECORD.sources"
GUM_EDIT_TARGET='Git 저장소 위치' GUM_MODE=edit-empty-roots pty edit-empty-roots "$repo/bin/routine-setup" "${setup_args[@]}"
jq -e '.sources.git.roots==[] and (.sources.git.enabled|not) and .sources.omp_sessions.enabled' "$ROUTINE_CONFIG" >/dev/null || fail 'Re-editing empty roots silently selected repositories or left Git enabled'
[[ $(cat "$GUM_RECORD.roots") == 2 ]] || fail 'Empty roots did not return to their chooser'
# A failed save stays in the final menu and keeps unrelated pending input.
cp "$sandbox/original.json" "$ROUTINE_CONFIG"; rm -f "$GUM_RECORD" "$GUM_RECORD.final"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.email GIT_CONFIG_VALUE_0='' GUM_EDIT_TARGET='git 작성자' GUM_MODE=repair-authors pty repair-authors "$repo/bin/routine-setup" "${setup_args[@]}" --identity-git-authors '[]' --slack-channel-name pending-kept
jq -e '.identity.git_authors==["repaired@example.com"] and .slack.channel_name=="pending-kept"' "$ROUTINE_CONFIG" >/dev/null || fail 'Required-value repair lost pending settings'
[[ $(cat "$GUM_RECORD.final") == 3 ]] || fail 'Invalid save did not return to final confirmation'
# Enter on author repair preserves order and the existing identity.
cp "$sandbox/original.json" "$ROUTINE_CONFIG"; rm -f "$GUM_RECORD" "$GUM_RECORD.final"
GUM_EDIT_TARGET='git 작성자' GUM_MODE=keep-authors pty keep-authors "$repo/bin/routine-setup" "${setup_args[@]}" --identity-git-authors '["z@example.com","a@example.com"]'
jq -e '.identity.git_authors==["z@example.com","a@example.com"]' "$ROUTINE_CONFIG" >/dev/null || fail 'Enter on author repair reordered identities'
rm -rf "${HOME:?}/dev"
cp "$sandbox/original.json" "$ROUTINE_CONFIG"; rm -f "$GUM_RECORD" "$GUM_RECORD.final"
export GUM_MODE=save NO_COLOR=1
pty no-color "$repo/bin/routine-setup" "${setup_args[@]}"
jq -Rse '[match("\u001b\\[[0-9;]*m";"g")]|length==0' "$sandbox/no-color.tty" >/dev/null || fail 'NO_COLOR emitted ANSI color'
unset NO_COLOR
# The plain-text path has the same save/edit/cancel transaction.
rm "$sandbox/stubs/gum"
for mode in text-save text-edit text-cancel text-retry; do
  cp "$sandbox/original.json" "$ROUTINE_CONFIG"
  pty "$mode" "$repo/bin/routine-setup" "${setup_args[@]}"
  if [[ $mode == text-cancel ]]; then cmp -s "$sandbox/original.json" "$ROUTINE_CONFIG" || fail 'Text cancellation wrote configuration'
  elif [[ $mode == text-edit ]]; then jq -e '.identity.git_authors==["text-edited@example.com"]' "$ROUTINE_CONFIG" >/dev/null || fail 'Text editing was not saved'; fi
  if [[ $mode == text-retry ]]; then
    [[ $(cat "$sandbox/text-final-attempts") == 4 ]] || fail 'Text final menu cancelled on Enter, an out-of-range number, or a typo'
  fi
  jq -Rse 'contains("GitHub PR (prs)") and contains(" │ ") and ([match("\u001b\\[[0-9;]*m";"g")]|length==0)' "$sandbox/$mode.tty" >/dev/null || fail 'Text labels or color fallback failed'
done
cp "$repo/tests/fixtures/gum-stub.sh" "$sandbox/stubs/gum"
# Exercise public wrappers under a real PTY, including focus checks on both
# sides of gum. This helper never activates an actual app or calls a real GUI.
cat > "$sandbox/spin-command" <<'SPIN'
#!/bin/bash
printf 'run\n' >> "$GUM_RECORD.executions"
printf 'raw output\nsecond line\n'
exit "$1"
SPIN
cat > "$sandbox/unit" <<'UNIT'
#!/bin/bash
set -euo pipefail
source "$1/ui.sh"
prompt_app=fixture
ensure_prompt_focus() { printf 'focus\n' >> "$GUM_RECORD.focus"; }
[[ $(ui_input '수동 값' '힌트' '기존 값') == '수동 입력 결과' ]]
[[ $(ui_choose_many '복수 선택' '[{"value":"one","label":"항목 하나"},{"value":"two","label":"항목 둘"}]' '["one"]') == '["two"]' ]]
ui_confirm '확인'
ui_note '안내' '박스 본문'
printf 'raw output\nsecond line\n' > "$GUM_RECORD.expected"
ui_spin '성공 대기' /bin/bash "$2" 0 > "$GUM_RECORD.success"
rc=0; ui_spin '실패 대기' /bin/bash "$2" 7 > "$GUM_RECORD.failure" || rc=$?
[[ $rc == 7 ]]
cmp -s "$GUM_RECORD.expected" "$GUM_RECORD.success"
cmp -s "$GUM_RECORD.expected" "$GUM_RECORD.failure"
"$3/bin/routine" sources | cat > "$GUM_RECORD.sources.stdout"
rc=0
"$3/bin/routine-setup" --skip platform --skip dependencies --skip github --skip llm --skip orca --skip disk-access --skip config --skip launchd --skip first-run > "$GUM_RECORD.setup.stdout" || rc=$?
[[ $rc == 1 ]]
jq -Rse 'contains("[선택]") and contains("[ ]") and contains("– 필요 조건:") and (test("[○●⚠]")|not) and ([match("\u001b\\[[0-9;]*m";"g")]|length==0)' "$GUM_RECORD.sources.stdout"
jq -Rse 'contains("✗ slack") and ([match("\u001b\\[[0-9;]*m";"g")]|length==0)' "$GUM_RECORD.setup.stdout"
non_interactive=1
[[ $(ui_input '질문 금지' '' '기존 값') == '기존 값' ]]
[[ $(ui_choose_many '질문 금지' '[{"value":"one","label":"하나"}]' '["one"]') == '["one"]' ]]
if ui_confirm '질문 금지'; then exit 1; fi
UNIT
rm -f "$GUM_RECORD" "$GUM_RECORD.focus"
export GUM_MODE=unit
pty unit /bin/bash "$sandbox/unit" "$repo/share" "$sandbox/spin-command" "$repo"
jq -Rse 'split("\n")|map(select(length>0)) as $events|all(range(0;6); . as $i|$events[$i*3:$i*3+3]==["focus","gum","focus"]) and ($events|length)==18' "$GUM_RECORD.focus" >/dev/null || fail 'Gum bypassed before/after terminal focus checks'
jq -Rse 'split("\n")|map(select(length>0))==["run","run"]' "$GUM_RECORD.executions" >/dev/null || fail 'Spinner reran a successful or failing command'
# Typed notices color only their icon, never the title or body text.
cat > "$sandbox/notices" <<'NOTICES'
#!/bin/bash
set -euo pipefail
source "$1/ui.sh"
for kind in info warning error success summary permission; do
  ui_note "설명 $kind" "BODY-$kind 기본 글자" "$kind"
done
NOTICES
for profile in notices-color notices-no-color; do
  if [[ $profile == notices-no-color ]]; then export NO_COLOR=1; else unset NO_COLOR; fi
  GUM_MODE=notices GUM_RECORD="$sandbox/$profile.calls" pty "$profile" /bin/bash "$sandbox/notices" "$repo/share"
  jq -Rse '
    split("\n") as $lines |
    [{kind:"info",icon:"💡"},{kind:"warning",icon:"⚠️"},{kind:"error",icon:"⛔"},
     {kind:"success",icon:"✅"},{kind:"summary",icon:"📋"},{kind:"permission",icon:"🔐"}] |
    all(.[]; . as $notice |
      any($lines[]; gsub("\u001b\\[[0-9;]*m";"")|startswith($notice.icon+" 설명 "+$notice.kind)) and
      any($lines[]; contains("BODY-"+$notice.kind) and (test("\u001b\\[[0-9;]*m")|not)))' "$sandbox/$profile.tty" >/dev/null || fail 'Notice icon or default-color body was lost'
  if [[ $profile == notices-color ]]; then
    jq -Rse '
      split("\n")|map(select(contains("설명 "))) |
      all(.[]; test("\u001b\\[1m설명 ") and
        (split("설명 ")[1]|test("\u001b\\[(?:3[0-9]|9[0-7]|38)[0-9;]*m")|not))' "$sandbox/$profile.tty" >/dev/null || fail 'Notice title uses a foreground color instead of only bold'
  else
    jq -Rse '[match("\u001b\\[[0-9;]*m";"g")]|length==0' "$sandbox/$profile.tty" >/dev/null || fail 'NO_COLOR notices emitted styling'
  fi
done
unset NO_COLOR
cat > "$sandbox/width" <<'WIDTH'
#!/bin/bash
set -euo pipefail
source "$1/ui.sh"
stty rows 30 cols 20
ui_stage_counter="$GUM_RECORD.stage"
printf '0\n' > "$ui_stage_counter"
printf 'MARKER-ABOVE-1\nMARKER-ABOVE-2\n'
ui_stage 1 2 '위치'
nfd="$HOME/$(jq -nr '[range(0;20)|"\u1100\u1161\u11a8"]|join("")')"
ui_output "$nfd"
ui_stage 2 2 '확인'
WIDTH
GUM_MODE=width pty width /bin/bash "$sandbox/width" "$repo/share"
jq -Rsf "$repo/tests/terminal-screen.jq" "$sandbox/width.tty" > "$sandbox/width.screen"
jq -e 'any(.[];.=="MARKER-ABOVE-1") and any(.[];.=="MARKER-ABOVE-2")' "$sandbox/width.screen" >/dev/null || fail 'NFD width over-count erased output above init'
# Optional installation is consent-only even with --yes; refusal or Homebrew
# failure cannot fail dependencies. No real brew runs in any scenario.
rm "$sandbox/stubs/gum"
for mode in decline install-failure; do
  export GUM_MODE=$mode
  pty "$mode" "$repo/bin/routine-setup" --yes --skip platform --skip github --skip llm --skip slack --skip orca --skip disk-access --skip config --skip launchd --skip first-run
  jq -Rse 'contains("텍스트 방식으로 계속 진행") and contains("설정 완료")' "$sandbox/$mode.tty" >/dev/null || fail 'Optional gum refusal/failure stopped dependencies'
done
jq -Rse 'split("\n")|map(select(startswith("brew ")))==["brew install gum"]' "$GUARD_RECORD" >/dev/null || fail 'Optional gum installation ran without consent or more than once'
cp "$repo/tests/fixtures/gum-stub.sh" "$sandbox/stubs/gum"
rm -f "$GUM_RECORD"
pty batch "$repo/bin/routine-setup" --yes --non-interactive --skip platform --skip github --skip llm --skip slack --skip orca --skip disk-access --skip config --skip launchd --skip first-run
[[ ! -e $GUM_RECORD ]] || fail 'Non-interactive setup invoked gum'
jq -Rse 'split("\n")|map(select(test("^(open|orca|claude|omp|launchctl|osascript) ")))==[]' "$GUARD_RECORD" >/dev/null || fail 'Gum tests reached a GUI or model command'
# A recorded launchd denial remains visible even when this setup skips first-run.
fda_result="$HOME/Library/Application Support/routine-automation/.setup-first-run-result.json"
mkdir -p "${fda_result%/*}"
printf '%s\n' '{"exit_code":0,"full_disk_access":{"status":"denied"}}' > "$fda_result"
pty fda-warning "$repo/bin/routine-setup" --skip platform --skip dependencies --skip github --skip llm --skip slack --skip orca --skip disk-access --skip config --skip launchd --skip first-run
jq -Rse 'contains("전체 디스크 접근") and contains("거부") and contains("PTY_RC=0")' "$sandbox/fda-warning.tty" >/dev/null || fail 'TTY completion hid the recorded protected-path denial'
# GUI detection below uses only these read-only stubs. No actual app is opened.
export GUM_SNAPSHOT="$repo/tests/fixtures/slack-init.json"
printf 'com.apple.Terminal\n' > "$GUARD_RECORD.foreground"
cat > "$sandbox/stubs/orca" <<'ORCA'
#!/bin/bash
printf 'orca %s\n' "$*" >> "$GUARD_RECORD.gui"
case "$*" in
  --help) exit 0 ;;
  'computer get-app-state --app com.tinyspeck.slackmacgap --json') cat "$GUM_SNAPSHOT" ;;
  *) exit 87 ;;
esac
ORCA
cat > "$sandbox/stubs/open" <<'OPEN'
#!/bin/bash
printf 'open %s\n' "$*" >> "$GUARD_RECORD.gui"
printf 'com.tinyspeck.slackmacgap\n' > "$GUARD_RECORD.foreground"
OPEN
cat > "$sandbox/stubs/osascript" <<'FOCUS'
#!/bin/bash
printf 'osascript %s\n' "$*" >> "$GUARD_RECORD.gui"
case ${4:-} in
  capture) cat "$GUARD_RECORD.foreground" ;;
  restore) printf '%s\n' "$5" > "$GUARD_RECORD.foreground" ;;
  *) exit 87 ;;
esac
FOCUS
cp "$sandbox/original.json" "$ROUTINE_CONFIG"; rm -f "$GUM_RECORD" "$GUM_RECORD.final"
export GUM_MODE=gui
pty gui "$repo/bin/routine-setup" "${setup_args[@]}" --delivery-mode gui-paste --slack-link https://example.slack.com/archives/CEXAMPLE/p1790895609247049
jq -e '.slack.channel_name=="daily-scrum" and .identity.slack_display_name=="감지 사용자" and .slack.post_title=="감지 스크럼"' "$ROUTINE_CONFIG" >/dev/null || fail 'GUI spinner lost detected Slack proposals'
jq -Rse 'gsub("\u001b\\[[0-9;]*m";"")|contains("설정 1/5 · Slack 글 링크") and contains("설정 2/5 · Slack 정보") and contains("설정 3/5 · Git 저장소 위치") and contains("설정 4/5 · 수집 소스") and contains("설정 5/5 · 확인")' "$sandbox/gui.tty" >/dev/null || fail 'GUI stage total is wrong'
jq -Rse 'test("\u001b\\[1m표시 이름\u001b\\[0m") and test("\u001b\\[0m 감지 사용자  \u001b\\[[0-9;]*m·\u001b\\[0m \u001b\\[[0-9;]*m감지\u001b\\[0m")' "$sandbox/gui.tty" >/dev/null || fail 'Summary label/value did not keep the default foreground'
jq -se '([.[]|select(.args[0]=="spin" and (.args|index("Slack 화면 이동")!=null))]|length)==1' "$GUM_RECORD" >/dev/null || fail 'Slack navigation did not use one spinner'
jq -Rse 'split("\n")|map(select(startswith("open ")))|length==1' "$GUARD_RECORD.gui" >/dev/null || fail 'Slack spinner executed navigation more than once'
[[ $(cat "$GUARD_RECORD.foreground") == com.apple.Terminal ]] || fail 'Slack spinner left focus outside the terminal'
# The failing first-run uses the launchctl sentinel, never an actual service.
cat > "$sandbox/fda-failure" <<'FDA'
#!/bin/bash
rc=0
"$1/bin/routine-setup" --skip platform --skip dependencies --skip github --skip llm --skip slack --skip orca --skip disk-access --skip config --skip launchd || rc=$?
[[ $rc == 1 ]]
FDA
pty fda-failure /bin/bash "$sandbox/fda-failure" "$repo"
jq -Rse 'contains("/bin/bash") and contains("전체 디스크 접근") and contains("허용 필요") and contains("PTY_RC=0")' "$sandbox/fda-failure.tty" >/dev/null || fail 'TTY first-run failure hid the disk-access report'
echo 'PASS: gum 스텁·setup PTY/FIFO·단계/요약·저장/단일 항목 수정/취소·텍스트/NO_COLOR·단일 실행 스피너·포커스·선택 의존성 동의'
