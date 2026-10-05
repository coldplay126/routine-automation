#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail() { echo "FAIL: $1" >&2; exit 1; }
real_jq=${TEST_JQ_BIN:-$(type -P jq)}
# Remove inherited fixture/operator configuration before installing a private PATH.
while IFS= read -r name; do [[ $name != ROUTINE_* ]] || unset "$name"; done < <(compgen -v)
sandbox=$(mktemp -d /tmp/routine-package-tests.XXXXXXXX)
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" USER=fixture
export PATH="$sandbox/stubs:/usr/bin:/bin"
export ROUTINE_CONFIG="$HOME/.config/routine-automation/config.json" ROUTINE_TZ=Asia/Seoul ROUTINE_NOW='2026-09-28T09:00:00+09:00'
export ROUTINE_APPLICATIONS_DIR="$sandbox/apps" ROUTINE_BIN_DIR="$HOME/.local/bin" ROUTINE_LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
# Never reach the real Orca app bundle: point the fallback at a sentinel that records and fails.
export ROUTINE_ORCA_APP_CLI="$sandbox/orca-app-cli"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 1\n' "$sandbox/orca-app-calls" > "$ROUTINE_ORCA_APP_CLI"
chmod +x "$ROUTINE_ORCA_APP_CLI"
export RECORD="$sandbox/calls" CLAUDE_ARGS="$sandbox/claude-args" CLAUDE_CWD="$sandbox/claude-cwd" CLAUDE_INPUT="$sandbox/claude-input" CLAUDE_COUNT="$sandbox/claude-count"
export PTY_TTY_STATE="$repo/tests/fixtures/tty-state.sh"
board_name="routine-test-package-$$-$RANDOM"
export ROUTINE_PASTEBOARD_NAME="$board_name"
cleanup() {
  local status=$? log
  if ((status!=0)); then
    for log in "$HOME/Library/Logs/routine-automation"/setup-*.log; do [[ ! -f $log ]] || { printf '\n%s:\n' "$log" >&2; cat "$log" >&2; }; done
  fi
  /usr/bin/osascript -l JavaScript "$repo/tests/pasteboard.js" clear >/dev/null
  rm -rf "$sandbox"; exit "$status"
}
trap cleanup EXIT
mkdir -p "$sandbox/stubs" "$HOME/.local/bin" "$TMPDIR" "$ROUTINE_APPLICATIONS_DIR/Slack.app" "$ROUTINE_APPLICATIONS_DIR/Orca.app"
# shellcheck source=network.sh
source "$repo/tests/network.sh"
ln -s "$real_jq" "$sandbox/stubs/jq"
cat > "$sandbox/stubs/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  'api user') echo '{"id":42,"login":"fixture"}' ;;
  'auth status') [[ ${GH_AUTH_FAIL:-0} != 1 ]] ;;
  'search prs') echo '[]' ;;
  'pr view') echo '{"state":"OPEN"}' ;;
  *) echo 'gh fixture version' ;;
esac
STUB
cat > "$sandbox/stubs/git" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == 'config user.email' ]]; then echo fixture@example.com; else exec /usr/bin/git "$@"; fi
STUB
cat > "$sandbox/stubs/claude" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == 'auth status' ]]; then [[ ${CLAUDE_AUTH_FAIL:-0} != 1 ]] || exit 1; echo '{"loggedIn":true}'; exit; fi
[[ ${1:-} != --version ]] || { echo 'Claude fixture version'; exit; }
[[ ${CLAUDE_EXEC_FAIL:-0} != 1 ]] || exit 33
printf '%s\n' "$@" > "$CLAUDE_ARGS"
printf '%s\n' "$PWD" > "$CLAUDE_CWD"
[[ -z $(find . -mindepth 1 -print) ]] || exit 87
cat > "$CLAUDE_INPUT"
count=$(cat "$CLAUDE_COUNT" 2>/dev/null || echo 0); count=$((count+1)); echo "$count" > "$CLAUDE_COUNT"
if [[ ${CLAUDE_BAD:-} == always || ( ${CLAUDE_BAD:-} == once && $count == 1 ) ]]; then echo '{"structured_output":{"items":[{"section":"wrong"}]}}'
elif [[ ${CLAUDE_RESULT:-0} == 1 ]]; then echo '{"result":"{\"items\":[]}"}'
else echo '{"structured_output":{"items":[]}}'; fi
STUB
cat > "$sandbox/stubs/gtimeout" <<'STUB'
#!/usr/bin/env bash
[[ ${1:-} != --version ]] || { echo 'gtimeout fixture'; exit; }
printf 'gtimeout %s\n' "$*" >> "$RECORD"
shift 3
exec "$@"
STUB
cat > "$sandbox/stubs/open" <<'STUB'
#!/usr/bin/env bash
printf 'open %s\n' "$*" >> "$RECORD"
if [[ ${1:-} == -g && ${2:-} == slack://* ]]; then
  : > "$RECORD.navigation"
  [[ ${FOCUS_STEAL:-0} != 1 ]] || echo com.tinyspeck.slackmacgap > "$RECORD.foreground"
  if [[ -n ${FOCUS_STEAL_DELAY:-} ]]; then
    (/bin/sleep "$FOCUS_STEAL_DELAY"; echo com.tinyspeck.slackmacgap > "$RECORD.foreground"; echo delayed-focus > "$RECORD.focus-delay") &
  fi
fi
STUB
cat > "$sandbox/stubs/osascript" <<'STUB'
#!/usr/bin/env bash
printf 'osascript %s\n' "$*" >> "$RECORD"
if [[ ${3:-} == */clipboard.js ]]; then
  [[ $ROUTINE_PASTEBOARD_NAME == routine-test-* ]] || exit 87
  exec /usr/bin/osascript "$@"
fi
if [[ ${3:-} == */app-focus.js ]]; then
  case ${4:-} in
    capture)
      count=$(cat "$RECORD.focus-captures" 2>/dev/null || echo 0); count=$((count+1)); echo "$count" > "$RECORD.focus-captures"
      if [[ $count == ${FOCUS_STEAL_CAPTURE:-0} ]]; then echo com.tinyspeck.slackmacgap > "$RECORD.foreground"; fi
      cat "$RECORD.foreground" ;;
    restore) [[ ${FOCUS_RESTORE_FAIL:-0} != 1 ]] || exit 91; echo "$5" > "$RECORD.foreground" ;;
    *) exit 87 ;;
  esac
fi
STUB
cat > "$sandbox/stubs/osacompile" <<'STUB'
#!/usr/bin/env bash
[[ $1 == -o ]] || exit 87
mkdir -p "$2/Contents/MacOS"
printf 'fixture app\n' > "$2/Contents/MacOS/applet"
printf 'osacompile\n' >> "$RECORD"
STUB
cat > "$sandbox/stubs/xattr" <<'STUB'
#!/usr/bin/env bash
printf 'xattr %s\n' "$*" >> "$RECORD"
STUB
cat > "$sandbox/stubs/brew" <<'STUB'
#!/usr/bin/env bash
printf 'brew %s\n' "$*" >> "$RECORD"
if [[ $1 == install ]]; then
  [[ -z ${SAVED_GH:-} ]] || ln -sf "$SAVED_GH" "$STUB_DIR/gh"
  [[ -z ${SAVED_JQ:-} ]] || ln -sf "$SAVED_JQ" "$STUB_DIR/jq"
  [[ -z ${MISSING_RESOLVED:-} ]] || touch "$MISSING_RESOLVED"
fi
STUB
cat > "$sandbox/stubs/launchctl" <<'STUB'
#!/usr/bin/env bash
printf 'launchctl %s\n' "$*" >> "$RECORD"
case $1 in
  print) [[ ${LAUNCH_NOT_LOADED:-0} != 1 && ! -f $RECORD.unloaded.${2##*/} ]] ;;
  bootout)
    [[ ${LAUNCH_BOOTOUT_FAIL:-0} != 1 ]] || exit 5
    : > "$RECORD.unloaded.${2##*/}" ;;
  bootstrap)
    if [[ ${LAUNCH_FAIL_FIRST:-0} == 1 && ! -e $RECORD.bootstrap-first ]]; then : > "$RECORD.bootstrap-first"; exit 5; fi
    [[ ${LAUNCH_BOOTSTRAP_FAIL:-0} != 1 ]] || exit 5
    label=${3##*/}; rm -f "$RECORD.unloaded.${label%.plist}"
    [[ -z ${SETUP_SPINNER_DELAY:-} ]] || sleep "$SETUP_SPINNER_DELAY" ;;
  kickstart)
    if [[ ${MORNING_DENY_FDA:-0} == 1 ]]; then chmod 000 "$HOME/Library/Mail"; fi
    if [[ ${LAUNCH_RUN_ASYNC:-0} == 1 ]]; then /bin/bash "$HOME/.local/share/routine-automation/bin/routine" run > "$RECORD.morning" 2>&1 &
    else /bin/bash "$HOME/.local/share/routine-automation/bin/routine" run; fi
    if [[ ${MORNING_DENY_FDA:-0} == 1 ]]; then chmod 700 "$HOME/Library/Mail"; fi ;;
esac
STUB
cat > "$sandbox/stubs/orca" <<'STUB'
#!/usr/bin/env bash
if [[ $1 == --help ]]; then exit; fi
printf 'orca %s\n' "$*" >> "$RECORD"
case "$1 ${2:-}" in
  'computer capabilities') [[ ${ORCA_SETUP:-0} == 1 ]] || exit 87; echo '{}'; exit ;;
  'computer permissions') touch "$RECORD.permission-${4:-missing}"; exit ;;
esac
[[ "$1 ${2:-}" == 'computer get-app-state' ]] || exit 87
if [[ ${ORCA_PERMISSION_MODE:-} == locked ]]; then exit 1; fi
# Slack running with its window closed: Orca reports window_not_found until the window reappears.
if [[ ${ORCA_PERMISSION_MODE:-} == window ]]; then
  count=$(cat "$RECORD.window-probes" 2>/dev/null || echo 0); count=$((count+1)); echo "$count" > "$RECORD.window-probes"
  if ((count < 3)); then echo '{"ok":false,"error":{"code":"window_not_found","message":"app has no accessibility window"}}'; exit 1; fi
fi
if [[ ${ORCA_PERMISSION_MODE:-} == auto ]]; then
  count=$(cat "$RECORD.probes" 2>/dev/null || echo 0); count=$((count+1)); echo "$count" > "$RECORD.probes"
  [[ -f $RECORD.permission-screenshots && $count -ge 3 ]] || exit 1
fi
if [[ -n ${ORCA_INIT_TREE:-} ]]; then
  if [[ -e $RECORD.navigation && ( ${ORCA_INIT_DELAY:-0} != 0 || ${ORCA_INIT_MISSING:-0} == 1 ) ]]; then
    count=$(cat "$RECORD.init-probes" 2>/dev/null || echo 0); count=$((count+1)); echo "$count" > "$RECORD.init-probes"
    if [[ $count -le ${ORCA_INIT_DELAY:-0} || ${ORCA_INIT_MISSING:-0} == 1 ]]; then
      echo '{"result":{"snapshot":{"treeText":"0 표준 윈도우 wrong-channel(채널) - 예제 워크스페이스\n15 팝업 버튼 사용자: 이전 사용자\n20 container 이전 제목: 예제팀\n21 link [오늘, 오전 8:00:00](https://example.slack.com/archives/COTHER/p1790895600000000)"}}}'
      exit
    fi
  fi
  cat "$ORCA_INIT_TREE"; exit
fi
if [[ ${DOCTOR_DRIFT:-0} == 1 ]]; then echo '{"result":{"snapshot":{"treeText":"12 버튼 새 검색\n15 팝업 버튼 사용자: 테스트 사용자"}}}'; exit; fi
echo '{"result":{"snapshot":{"treeText":"12 버튼 검색\n15 팝업 버튼 사용자: 테스트 사용자"}}}'
STUB
cat > "$sandbox/stubs/omp" <<'STUB'
#!/usr/bin/env bash
[[ ${1:-} == --version ]] || exit 87
echo 'omp fixture version'
STUB
chmod +x "$sandbox/stubs/"*
for cmd in jq gh git claude omp gtimeout open osascript osacompile xattr brew launchctl orca; do ln -s "$sandbox/stubs/$cmd" "$HOME/.local/bin/$cmd"; done
for cmd in claude gh brew launchctl open osascript orca; do [[ $(command -v "$cmd") == "$sandbox/stubs/$cmd" ]] || fail "Real command selected: $cmd"; done
routine="$repo/bin/routine"
type() {
  # Text PTY regressions must not discover a real Homebrew gum via routine's PATH.
  if [[ ${1:-} == -P && ${2:-} == gum ]]; then return 1; fi
  if [[ ${1:-} == -P && ${2:-} == "${MISSING_DEPENDENCY:-}" && ! -f ${MISSING_RESOLVED:-/nonexistent} ]]; then return 1; fi
  if [[ ${1:-} == -P && ${2:-} == claude && ${CLAUDE_MISSING:-0} == 1 ]]; then return 1; fi
  builtin type "$@"
}
export -f type
for cmd in init draft collect paste run copy doctor status sources config package uninstall; do
  ROUTINE_CONFIG="$sandbox/no-config.json" "$routine" "$cmd" --help > "$sandbox/help-$cmd"
done
grep -q -- '--identity-slack-display-name' "$sandbox/help-init" || fail 'Init help missing real identity flag'
init_args=(--non-interactive --slack-link https://example.slack.com/archives/CEXAMPLE/p1790895609247049 --identity-slack-display-name '테스트 사용자' --slack-team-id TEXAMPLE --slack-channel-name daily-scrum --slack-post-title '예제 스크럼' --project '예제 프로젝트' --draft-llm-engine claude --sources-jira-enabled false --sources-notion-enabled false --sources-omp-sessions-enabled false --sources-claude-sessions-enabled false --sources-prs-enabled false --sources-git-roots "$(jq -nc --arg root "$sandbox/repos" '[$root]')")
mkdir -p "$sandbox/repos"
if "$routine" init --non-interactive > "$sandbox/missing" 2>&1; then fail 'Missing init values accepted'; fi
"$routine" init "${init_args[@]}"
[[ $(stat -f %Lp "$ROUTINE_CONFIG") == 600 ]] || fail 'Config not private'
jq -e '.slack.workspace_domain=="example" and .slack.channel_id=="CEXAMPLE" and .identity.git_authors==["42+fixture@users.noreply.github.com","fixture@example.com"] and .delivery.mode=="clipboard" and (.morning.extra_steps|all(.[];not))' "$ROUTINE_CONFIG" >/dev/null || fail 'Init parsing/detection/defaults'
minimal_config="$sandbox/clipboard-minimal.json"
ROUTINE_CONFIG="$minimal_config" "$routine" init --non-interactive --slack-link https://example.slack.com/archives/CEXAMPLE/p1790895609247049 --slack-team-id TEXAMPLE --sources-git-enabled false --draft-llm-engine none > /dev/null
if ROUTINE_CONFIG="$minimal_config" "$routine" init --non-interactive --delivery-mode gui-paste > "$sandbox/gui-missing" 2>&1; then fail 'GUI mode accepted missing safety identities'; fi
for key in identity.slack_display_name slack.channel_name slack.post_title; do grep -q "$key" "$sandbox/gui-missing" || fail "Missing GUI field not reported: $key"; done
# Re-linking to another workspace/channel must not keep the old team ID, display name, channel name
# or post title (mixed Slack configuration). The new team ID comes from Slack's local state.
mixed_config="$sandbox/mixed-link.json"
ROUTINE_CONFIG="$mixed_config" "$routine" init --non-interactive --slack-link https://oldspace.slack.com/archives/COLD/p1790895609247049 --slack-team-id TOLD --identity-slack-display-name '이전 사용자' --slack-channel-name old-channel --slack-post-title '이전 제목' --sources-git-enabled false --draft-llm-engine none > /dev/null
printf '{"workspaces":{"TNEW":{"domain":"newspace","name":"New"}}}\n' > "$sandbox/new-slack-state.json"
ROUTINE_SLACK_STATE="$sandbox/new-slack-state.json" ROUTINE_CONFIG="$mixed_config" "$routine" init --non-interactive --slack-link https://newspace.slack.com/archives/CNEW/p1790895609247049 > /dev/null
jq -e '.slack.workspace_domain=="newspace" and .slack.team_id=="TNEW" and .slack.channel_id=="CNEW" and .slack.channel_name=="" and .slack.post_title=="" and .identity.slack_display_name==""' "$mixed_config" >/dev/null || { jq -c '{slack,identity}' "$mixed_config" >&2; fail 'Re-linking kept values from the previous workspace/channel'; }
before=$(shasum -a 256 "$mixed_config")
if ROUTINE_SLACK_STATE="$sandbox/no-slack-state" ROUTINE_CONFIG="$mixed_config" "$routine" init --non-interactive --slack-link https://thirdspace.slack.com/archives/CTHIRD/p1790895609247049 > /dev/null 2>&1; then fail 'Unknown workspace kept the previous team ID'; fi
[[ $(shasum -a 256 "$mixed_config") == "$before" ]] || fail 'Rejected re-link changed the saved configuration'
ROUTINE_SLACK_STATE="$sandbox/new-slack-state.json" ROUTINE_CONFIG="$mixed_config" "$routine" init --non-interactive --slack-link https://newspace.slack.com/archives/CNEW/p1790895609247049 --slack-channel-name kept --slack-post-title '유지 제목' > /dev/null
ROUTINE_CONFIG="$mixed_config" "$routine" init --non-interactive --slack-link https://newspace.slack.com/archives/CNEW/p1790899200000000 > /dev/null
jq -e '.slack.channel_name=="kept" and .slack.post_title=="유지 제목" and .slack.team_id=="TNEW"' "$mixed_config" >/dev/null || fail 'Same-channel link cleared channel values'
# Explicit Slack values in the same invocation must survive invalidation of saved values.
explicit_link_config="$sandbox/explicit-link.json"
cp "$mixed_config" "$explicit_link_config"
ROUTINE_SLACK_STATE="$sandbox/no-slack-state" ROUTINE_CONFIG="$explicit_link_config" "$routine" init --non-interactive --slack-link https://thirdspace.slack.com/archives/CTHIRD/p1790895609247049 --slack-team-id TTHIRD --identity-slack-display-name '지정 사용자' --slack-channel-name explicit-channel --slack-post-title '지정 제목' > /dev/null
jq -e '.slack.workspace_domain=="thirdspace" and .slack.channel_id=="CTHIRD" and .slack.team_id=="TTHIRD" and .identity.slack_display_name=="지정 사용자" and .slack.channel_name=="explicit-channel" and .slack.post_title=="지정 제목"' "$explicit_link_config" >/dev/null || fail 'Re-linking cleared explicit Slack CLI values without local state'
if "$routine" init "${init_args[@]}" --slack-link https://evil.example/archives/C1/p123 > /dev/null 2>&1; then fail 'Bad Slack URL accepted'; fi
[[ $("$routine" config get draft.project) == '예제 프로젝트' ]] || fail 'Config read'
[[ $(ROUTINE_PROJECT=환경 "$routine" config get draft.project) == 환경 ]] || fail 'Environment precedence'
[[ $(ROUTINE_PROJECT=환경 "$routine" --set draft.project '"플래그"' config get draft.project) == 플래그 ]] || fail 'CLI precedence'
"$routine" config set draft.headers.today '"오늘 계획 & 점검"'
[[ $("$routine" config get draft.headers.today) == '오늘 계획 & 점검' ]] || fail 'Config set'
if "$routine" config set delivery.daily_attempts 0 > /dev/null 2>&1; then fail 'Invalid config boundary accepted'; fi
for value in 0 59; do if "$routine" config set delivery.idle_seconds "$value" > /dev/null 2>&1; then fail 'Unsafe idle lower bound accepted'; fi; done
for value in '""' '"아무 글"' '"오전 1"'; do if "$routine" config set slack.post_time_prefix "$value" > /dev/null 2>&1; then fail 'Unsafe today timestamp prefix accepted'; fi; done
ROUTINE_DELIVERY_MODE=gui-paste ROUTINE_TZ=UTC "$routine" --set morning.time '"06:00"' config set draft.project '"예제 프로젝트"'
jq -e '.delivery.mode=="clipboard" and .timezone!="UTC" and .morning.time=="08:00"' "$ROUTINE_CONFIG" >/dev/null || fail 'Transient overrides leaked into config set'
ROUTINE_DELIVERY_MODE=gui-paste ROUTINE_TZ=UTC ROUTINE_CHROME_DIR="$sandbox/transient-chrome" "$routine" init "${init_args[@]}" > /dev/null
jq -e --arg chrome "$HOME/Library/Application Support/Google/Chrome" '.sources.jira.chrome_dir==$chrome and .delivery.mode=="clipboard" and .timezone!="UTC"' "$ROUTINE_CONFIG" >/dev/null || fail 'Environment leaked into init'
# Legacy-but-structural settings remain repairable; only the saved result is validated.
jq '.delivery.idle_seconds=0' "$ROUTINE_CONFIG" > "$sandbox/legacy-config"; mv "$sandbox/legacy-config" "$ROUTINE_CONFIG"
"$routine" config set delivery.idle_seconds 60
jq '.slack.post_time_prefix=""' "$ROUTINE_CONFIG" > "$sandbox/legacy-config"; mv "$sandbox/legacy-config" "$ROUTINE_CONFIG"
"$routine" config set slack.post_time_prefix '"오전 8:0"'
jq '.delivery.idle_seconds="invalid" | .slack.post_time_prefix="오전 1"' "$ROUTINE_CONFIG" > "$sandbox/legacy-config"; mv "$sandbox/legacy-config" "$ROUTINE_CONFIG"
"$routine" init --non-interactive --delivery-idle-seconds 60 --slack-post-time-prefix '오전 8:0' > /dev/null
jq -e '.delivery.idle_seconds==60 and .slack.post_time_prefix=="오전 8:0"' "$ROUTINE_CONFIG" >/dev/null || fail 'Batch init failed to repair schema types/bounds'
cp "$ROUTINE_CONFIG" "$sandbox/config-before-tty"
cat > "$sandbox/tty-command" <<'STUB'
#!/bin/bash
if [[ ${SPINNER_PRESEED:-0} == 1 ]]; then
  stty rows 30 cols 110
  for ((line=0;line<35;line++)); do printf 'Existing terminal output %s\n' "$line"; done
fi
/bin/bash "$PTY_TTY_STATE" > "$RECORD.tty-before"
if [[ ${SPINNER_SIGNAL:-0} == 1 ]]; then
  "$@" & child=$!
  echo "$child" > "$RECORD.setup-pid"
  wait "$child"; status=$?
else "$@"; status=$?; fi
/bin/bash "$PTY_TTY_STATE" > "$RECORD.tty-after"
if cmp -s "$RECORD.tty-before" "$RECORD.tty-after"; then restored=1; else restored=0; fi
printf '\nTTY_RESTORED=%s\nSETUP_RC=%s\n' "$restored" "$status"
exit "$status"
STUB
rm "$ROUTINE_CONFIG"
slack_storage="$HOME/Library/Application Support/Slack/storage"; mkdir -p "$slack_storage"
echo '{"workspaces":{"TEXAMPLE":{"domain":"example","name":"예제 워크스페이스"}}}' > "$slack_storage/root-state.json"
# A root-only /usr/local/bin/orca symlink prints an error and exits 1; init must ignore it.
mkdir -p "$sandbox/broken-orca"
printf '#!/bin/sh\necho "Unable to determine Orca.app path from symlink: /usr/local/bin/orca"\nexit 1\n' > "$sandbox/broken-orca/orca"
chmod +x "$sandbox/broken-orca/orca"
# routine now prioritizes ~/.local/bin. Replace its private target too, rather
# than relying on a temporary PATH prefix to mask that executable.
mv "$sandbox/stubs/orca" "$sandbox/orca-good"
cp "$sandbox/broken-orca/orca" "$sandbox/stubs/orca"
PATH="$sandbox/broken-orca:$PATH" /usr/bin/expect "$repo/tests/fixtures/setup-pty.exp" "$routine" "$sandbox/tty-command" "$sandbox/tty-success" valid > /dev/null || true
mv "$sandbox/orca-good" "$sandbox/stubs/orca"
if ! grep -q 'SETUP_RC=0' "$sandbox/tty-success" || ! grep -q '설정 완료' "$sandbox/tty-success"; then cat "$sandbox/tty-success" >&2; fail 'Interactive setup failed (bash 3.2 empty array or broken orca on PATH)'; fi
jq -e '.draft.project=="" and .slack.workspace_domain=="example" and .slack.channel_id=="CEXAMPLE" and .slack.team_id=="TEXAMPLE" and .identity.slack_display_name=="" and .slack.channel_name=="" and .slack.post_title=="" and (.sources.omp_sessions.enabled|not) and (.sources.claude_sessions.enabled|not)' "$ROUTINE_CONFIG" >/dev/null || fail 'Clipboard interactive setup did not keep only needed identity values'
jq -Rse 'contains("설정 1/4 · Slack 글 링크") and contains("설정 4/4 · 확인")' "$sandbox/tty-success" >/dev/null || fail 'Text onboarding stage total failed'
# The app-bundle fallback may only be probed (--help); it must never read Slack state.
! grep -qv '^--help$' "$sandbox/orca-app-calls" 2>/dev/null || fail 'Init used the Orca app bundle beyond the --help probe'
rm "$ROUTINE_CONFIG"
ROUTINE_SLACK_STATE="$sandbox/no-slack-state" /usr/bin/expect "$repo/tests/fixtures/setup-pty.exp" "$routine" "$sandbox/tty-command" "$sandbox/tty-failure" invalid > /dev/null
grep -q 'SETUP_RC=1' "$sandbox/tty-failure" || fail 'Setup EXIT trap hid interactive failure'
jq -Rsf "$repo/tests/terminal-screen.jq" "$sandbox/tty-failure" > "$sandbox/failure-screen.json"
jq -L "$repo/tests" -e 'include "setup-screen"; setup_once and any(setup_rows[];.marker=="✗" and .label=="설정 저장")' "$sandbox/failure-screen.json" >/dev/null || fail 'Interactive failure was not reflected in the final checklist'
cp "$sandbox/config-before-tty" "$ROUTINE_CONFIG"
# --overwrite-config with init flags keeps the remaining interactive link/source prompts.
/usr/bin/expect "$repo/tests/fixtures/setup-pty.exp" "$routine" "$sandbox/tty-command" "$sandbox/tty-overwrite" overwrite > /dev/null || fail 'Overwrite setup with flags skipped interactive prompts'
jq -e '.draft.project=="예제 프로젝트" and .delivery.mode=="clipboard" and .sources.prs.enabled' "$ROUTINE_CONFIG" >/dev/null || fail 'Overwrite lost the explicit PR selection or changed an unprompted project/delivery choice'
jq -Rsf "$repo/tests/terminal-screen.jq" "$sandbox/tty-overwrite" > "$sandbox/final-screen.json"
jq -L "$repo/tests" -e 'include "setup-screen"; setup_once' "$sandbox/final-screen.json" >/dev/null || fail 'Scrolled terminal retained multiple checklists'
# Only the closest directly enclosing message container can supply the prefix.
command jq -L "$repo/share" -ne 'include "slack"; {treeText:"0 내용 목록 daily-scrum (채널)\n\t1 container 공지: 이전 글\n\t\t2 container 작성 사용자: 내용\n\t\t\t3 link [오늘, 오전 8:00](https://example.slack.com/archives/CEXAMPLE/p1790895609247049)"} | init_proposals("1790895609247049") | .["slack.post_title"]=="작성 사용자"' >/dev/null || fail 'Title prefix was not taken from the nearest enclosing container'
command jq -L "$repo/share" -ne 'include "slack"; [{treeText:"0 내용 목록 daily-scrum (채널)\n\t1 container 공지: 이전 글\n\t\t2 container\n\t\t\t3 link [오늘, 오전 8:00](https://example.slack.com/archives/CEXAMPLE/p1790895609247049)"},{treeText:"[0] 내용 목록 daily-scrum (채널)\n[1] container 공지: 이전 글\n[2] link [오늘, 오전 7:00](https://example.slack.com/archives/CEXAMPLE/p1790892000000000)\n[3] link [오늘, 오전 8:00](https://example.slack.com/archives/CEXAMPLE/p1790895609247049)"}] | all(.[]; init_proposals("1790895609247049") | .["slack.post_title"]=="")' >/dev/null || fail 'Unwrapped/anonymous linked message borrowed a previous post title'
# Without the linked post, the channel is confirmed only from the main message list; a search pane or
# thread panel showing target-channel links inside another channel's window must not count.
command jq -L "$repo/share" -ne 'include "slack";
  {treeText:"0 표준 윈도우 daily-scrum(채널) - 예제\n\t1 내용 목록 daily-scrum (채널)\n\t\t2 link [오늘, 오전 9:00](https://example.slack.com/archives/CEXAMPLE/p1790900000000000)\n\t\t3 link [오늘, 오전 9:10](https://example.slack.com/archives/CEXAMPLE/p1790900600000000)"} as $same |
  {treeText:"0 표준 윈도우 other(채널) - 예제\n\t1 내용 목록 other (채널)\n\t\t2 link [오늘, 오전 9:00](https://example.slack.com/archives/COTHER/p1790900000000000)\n\t1 검색 결과\n\t\t3 link [오늘, 오전 9:10](https://example.slack.com/archives/CEXAMPLE/p1790900600000000)"} as $search |
  {treeText:"0 표준 윈도우 other(채널) - 예제\n\t1 내용 목록 other (채널)\n\t1 내용 목록 other의 스레드 (채널, 1개의 댓글)\n\t\t3 link [오늘, 오전 9:10. 채널에서 열기](https://example.slack.com/archives/CEXAMPLE/p1790900600000000?thread_ts=1.2)"} as $thread |
  {treeText:"0 표준 윈도우 daily-scrum(채널) - 예제\n\t1 link [오늘, 오전 9:00](https://example.slack.com/archives/CEXAMPLE/p1790900000000000)"} as $nolist |
  {treeText:"0 표준 윈도우 daily-scrum(채널) - 예제\n\t1 내용 목록 daily-scrum (채널)\n\t\t2 link [오늘, 오전 9:00](https://example.slack.com/archives/CEXAMPLE/p1790900000000000)\n\t1 내용 목록 daily-scrum의 스레드 (채널, 1개의 댓글)\n\t\t3 link [오늘, 오전 9:10. 채널에서 열기](https://example.slack.com/archives/CEXAMPLE/p1790900600000000?thread_ts=1.2)"} as $withthread |
  ($same|channel_visible("CEXAMPLE")) and ($withthread|channel_visible("CEXAMPLE")) and ($search|channel_visible("CEXAMPLE")|not) and ($thread|channel_visible("CEXAMPLE")|not) and ($nolist|channel_visible("CEXAMPLE")|not)' >/dev/null || fail 'Channel confirmation without the linked post'
# The exact permalink in a search pane/thread of another channel must not unlock proposals; the channel
# name comes from the main list only (thread list "…의 스레드" and the unread "*" title marker ignored).
command jq -L "$repo/share" -ne 'include "slack";
  {treeText:"0 표준 윈도우 other(채널) - 예제\n\t1 내용 목록 other (채널)\n\t\t2 link [오늘, 오전 9:00](https://example.slack.com/archives/COTHER/p1790900000000000)\n\t1 검색 결과\n\t\t3 container 감지 스크럼: 본문\n\t\t\t4 link [오늘, 오전 8:00:09](https://example.slack.com/archives/CEXAMPLE/p1790895609247049)"} as $searchlink |
  {treeText:"0 표준 윈도우 * daily-scrum(채널) - 예제\n\t1 내용 목록 daily-scrum (채널)\n\t\t2 link [오늘, 오전 9:00](https://example.slack.com/archives/CEXAMPLE/p1790900000000000)\n\t1 내용 목록 daily-scrum의 스레드 (채널, 1개의 댓글)\n\t\t3 link [오늘, 오전 9:10. 채널에서 열기](https://example.slack.com/archives/CEXAMPLE/p1790900600000000?thread_ts=1.2)"} as $withthread |
  ($searchlink|linked_post_visible("1790895609247049")|not) and ($searchlink|init_proposals("1790895609247049")|.["slack.post_title"]=="") and
  ($withthread|init_proposals("")|.["slack.channel_name"]=="daily-scrum")' >/dev/null || fail 'Search/thread permalink or thread list leaked into init proposals'
for mode in gui-ready gui-grant gui-window gui-skip clipboard-choice gui-delayed gui-missing gui-focus gui-focus-failed gui-late-focus gui-timed-focus gui-vscode gui-custom gui-browser; do
  rm "$ROUTINE_CONFIG"; : > "$RECORD"
  rm -f "$RECORD.probes" "$RECORD.window-probes" "$RECORD.permission-accessibility" "$RECORD.permission-screenshots"
  rm -f "$RECORD.navigation" "$RECORD.init-probes" "$RECORD.focus-captures" "$RECORD.focus-delay"
  terminal=com.apple.Terminal
  [[ $mode != gui-vscode ]] || terminal=com.microsoft.VSCode
  [[ $mode != gui-custom ]] || terminal=dev.fixture.terminal
  echo "$terminal" > "$RECORD.foreground"
  [[ $mode != gui-browser ]] || echo com.google.Chrome > "$RECORD.foreground"
  delay=0 missing=0 steal=0 restore_fail=0 steal_capture=0 focus_delay=''
  [[ $mode != gui-timed-focus ]] || focus_delay=0.75
  [[ $mode != gui-late-focus ]] || steal_capture=3
  [[ $mode != gui-delayed ]] || delay=2
  [[ $mode != gui-missing ]] || missing=1
  [[ $mode != gui-focus && $mode != gui-focus-failed ]] || steal=1
  [[ $mode != gui-focus-failed ]] || restore_fail=1
  permission=''; [[ $mode != gui-grant ]] || permission=auto; [[ $mode != gui-skip ]] || permission=locked; [[ $mode != gui-window ]] || permission=window
  TERMINAL_BUNDLE="$terminal" FOCUS_STEAL_DELAY="$focus_delay" ORCA_SETUP=1 ORCA_INIT_TREE="$repo/tests/fixtures/slack-init.json" ORCA_PERMISSION_MODE="$permission" ORCA_INIT_DELAY="$delay" ORCA_INIT_MISSING="$missing" FOCUS_STEAL="$steal" FOCUS_RESTORE_FAIL="$restore_fail" FOCUS_STEAL_CAPTURE="$steal_capture" /usr/bin/expect "$repo/tests/fixtures/setup-pty.exp" "$routine" "$sandbox/tty-command" "$sandbox/tty-$mode" "$mode" > /dev/null || fail "Orca PTY path failed: $mode"
  if [[ $mode == gui-window ]]; then
    # A closed Slack window must not be mistaken for missing permissions.
    grep -q 'Slack 창이 닫혀 있어' "$sandbox/tty-$mode" || fail 'Closed Slack window was not explained'
    ! grep -q 'Orca의 접근성 권한이 필요합니다' "$sandbox/tty-$mode" || fail 'Closed Slack window was reported as a permission problem'
  fi
  if [[ $mode == gui-missing || $mode == gui-browser ]]; then
    jq -e '.slack.channel_name=="manual-channel" and .identity.slack_display_name=="수동 사용자" and .slack.post_title=="수동 스크럼"' "$ROUTINE_CONFIG" >/dev/null || fail 'Wrong-channel proposals escaped the linked-post check'
    if [[ $mode == gui-missing ]]; then [[ $(cat "$RECORD.init-probes") == 5 ]] || fail 'Init snapshot polling did not stop at five attempts'
    else ! grep -q '^open -g slack://' "$RECORD" || fail 'Non-terminal foreground navigated Slack'; fi
  elif [[ $mode == gui-* && $mode != gui-skip ]]; then
    jq -e '.delivery.mode=="gui-paste" and .slack.channel_name=="daily-scrum" and .identity.slack_display_name=="감지 사용자" and .slack.post_title=="감지 스크럼" and .draft.project==""' "$ROUTINE_CONFIG" >/dev/null || fail 'Linked channel identity/title detection failed'
    if [[ $mode == gui-ready ]]; then
      jq -Rse 'contains("설정 2/5 · Slack 정보") and contains("설정 5/5 · 확인")' "$sandbox/tty-$mode" >/dev/null || fail 'Text GUI stage total is wrong'
    fi
    grep -q '^open -g slack://channel?team=TEXAMPLE&id=CEXAMPLE$' "$RECORD" || fail 'Init navigation stole focus instead of using -g'
    grep -q 'app-focus.js capture' "$RECORD" || fail 'Init did not capture/confirm terminal focus'
    ! grep -q '^orca computer get-app-state .*--no-screenshot' "$RECORD" || fail 'Permission proof skipped the screenshot'
  else jq -e '.delivery.mode=="clipboard"' "$ROUTINE_CONFIG" >/dev/null || fail 'Orca skip/decline did not persist clipboard'; fi
  if [[ $mode == gui-grant || $mode == gui-skip ]]; then
    [[ -f $RECORD.permission-accessibility && -f $RECORD.permission-screenshots ]] || fail 'Permission panels were not requested'
  else ! grep -q '^orca computer permissions' "$RECORD" || fail 'Already granted/declined setup requested permissions'; fi
  ! grep -Eq '^orca computer (click|set-value|press-key)' "$RECORD" || fail 'Setup/init changed Slack input'
  if [[ $mode == gui-delayed ]]; then [[ $(cat "$RECORD.init-probes") == 3 ]] || fail 'Delayed linked message was not polled'; fi
  if [[ $mode == gui-focus || $mode == gui-focus-failed || $mode == gui-late-focus || $mode == gui-timed-focus ]]; then
    grep -q "app-focus.js restore $terminal" "$RECORD" || fail 'Slack focus was not restored before terminal questions'
    [[ $(cat "$RECORD.foreground") == "$terminal" ]] || fail 'Questions started with Slack foreground'
  fi
  if [[ $mode == gui-timed-focus ]]; then [[ -f $RECORD.focus-delay ]] || fail 'Timed deep-link focus steal was not exercised'; fi
  if [[ $mode == gui-focus-failed ]]; then grep -q '터미널을 클릭한 뒤 Enter' "$sandbox/tty-$mode" || fail 'Failed focus restoration did not wait for terminal confirmation'; fi
done
rm "$ROUTINE_CONFIG"
mv "$sandbox/stubs/orca" "$sandbox/orca-good"
cp "$sandbox/broken-orca/orca" "$sandbox/stubs/orca"
PATH="$sandbox/broken-orca:$PATH" ORCA_SETUP=1 /usr/bin/expect "$repo/tests/fixtures/setup-pty.exp" "$routine" "$sandbox/tty-command" "$sandbox/tty-orca-unavailable" gui-unavailable > /dev/null || fail 'Unavailable Orca PTY proof failed'
mv "$sandbox/orca-good" "$sandbox/stubs/orca"
[[ $(grep -c '실행 가능한 Orca CLI가 없습니다' "$sandbox/tty-orca-unavailable") == 1 ]] || fail 'Visible setup message was duplicated'
rm -f "$ROUTINE_CONFIG"
mkdir -p "$ROUTINE_APPLICATIONS_DIR/Google Chrome.app" "$ROUTINE_APPLICATIONS_DIR/Notion.app" "$HOME/Library/Application Support/Google/Chrome"
export PTY_NOTION_DB="$sandbox/selected-notion.db"; touch "$PTY_NOTION_DB"
/usr/bin/expect "$repo/tests/fixtures/setup-pty.exp" "$routine" "$sandbox/tty-command" "$sandbox/tty-sources" sources-on > /dev/null || fail 'Interactive source selection failed'
jq -e '.sources.jira.enabled and .sources.notion.enabled and .identity.notion_email_like=="fixture@example.com"' "$ROUTINE_CONFIG" >/dev/null || fail 'Source toggles or Notion email proposal not saved'
"$routine" sources > "$sandbox/source-labels"
jq -Rse '. as $text|all(["git 커밋 (git) — 내 작성 커밋","GitHub PR (prs) — 내가 만든·리뷰한 PR","omp 세션 (omp_sessions) — AI 작업 보고","Claude Code 세션 (claude_sessions) — AI 작업 보고","Jira (Chrome 방문 기록) (jira)","Notion 편집 기록 (notion)","Slack 내 메시지 (slack) — 자동 붙여넣기 전용"][]; . as $label|$text|contains($label))' "$sandbox/source-labels" >/dev/null || fail 'routine sources did not use the same Korean source names'
unset PTY_NOTION_DB
# Deselecting the only Git location must be recoverable from the source step (not a dead end).
rm -f "$ROUTINE_CONFIG"
mkdir -p "$HOME/Documents/GitHub/sample" && /usr/bin/git -C "$HOME/Documents/GitHub/sample" init -q
/usr/bin/expect "$repo/tests/fixtures/setup-pty.exp" "$routine" "$sandbox/tty-command" "$sandbox/tty-git-recover" git-recover > /dev/null || fail 'Git location recovery PTY failed'
grep -q 'Git 저장소 위치를 다시 고를까요' "$sandbox/tty-git-recover" || fail 'Unavailable git did not offer location selection'
jq -e --arg root "$(cd -P "$HOME/Documents/GitHub" && pwd -P)" '.sources.git.enabled and (.sources.git.roots|index($root)!=null)' "$ROUTINE_CONFIG" >/dev/null || fail 'Recovered Git location/source was not saved'
jq -Rse '[match("설정 ([0-9]+)/([0-9]+)";"g")|.captures[0].string|tonumber]==[1,2,3,4]' "$sandbox/tty-git-recover" >/dev/null || fail 'Git recovery repeated a source stage in the initial wizard'
rm -rf "$HOME/Documents/GitHub/sample"
cp "$sandbox/config-before-tty" "$ROUTINE_CONFIG"
# Dozens of real spinner redraws after a full screen must retain one checklist.
SPINNER_PRESEED=1 SETUP_SPINNER_DELAY=6 /usr/bin/expect "$repo/tests/fixtures/setup-pty.exp" "$routine" "$sandbox/tty-command" "$sandbox/tty-spinner" spinner > /dev/null || fail 'Actual setup spinner smoke failed'
grep -q 'TTY_RESTORED=1' "$sandbox/tty-spinner" || fail 'Spinner did not restore terminal echo'
jq -Rsf "$repo/tests/terminal-screen.jq" "$sandbox/tty-spinner" > "$sandbox/spinner-screen.json"
jq -L "$repo/tests" -e 'include "setup-screen"; setup_once' "$sandbox/spinner-screen.json" >/dev/null || fail 'Spinner scrolling duplicated the final checklist'
"$routine" uninstall >/dev/null
rm -f "$RECORD".unloaded.*
SPINNER_PRESEED=1 SPINNER_SIGNAL=1 SETUP_SPINNER_DELAY=2 /usr/bin/expect "$repo/tests/fixtures/setup-pty.exp" "$routine" "$sandbox/tty-command" "$sandbox/tty-spinner-signal" spinner-signal > /dev/null || fail 'Signal cleanup did not restore terminal mode'
grep -q 'TTY_RESTORED=1' "$sandbox/tty-spinner-signal" || fail 'Signal left terminal echo disabled'
"$routine" uninstall >/dev/null
rm -f "$RECORD".unloaded.*
out="$HOME/Library/Application Support/routine-automation/scrum"
mkdir -p "$out"
echo '{"version":1,"window":{"since":"2026-09-25T00:00:00Z","until":"2026-09-28T00:00:00Z"},"git":[],"prs":[],"sessions":[],"jira":[],"notion":[],"slack":[],"errors":[]}' > "$out/2026-09-28.json"
"$routine" draft --model fixture-model
jq -Rse 'split("\n") as $a | ($a|index("--tools")) as $t | ($a|index("--setting-sources")) as $s | all(["-p","--strict-mcp-config","--disable-slash-commands","--no-session-persistence","--output-format","json","--json-schema","--model","fixture-model"][];. as $f|$a|index($f)!=null) and $a[$t+1]=="" and $a[$s+1]=="" and ($a|index("--bare"))==null and ($a|index("--safe-mode"))==null' "$CLAUDE_ARGS" >/dev/null || fail 'Claude isolation arguments'
[[ $(cat "$CLAUDE_CWD") == "$TMPDIR"/scrum-draft.*/model-cwd ]] || fail 'Claude cwd not isolated'
[[ $(cat "$CLAUDE_INPUT") == *'예제 프로젝트'* ]] || fail 'Configured prompt missing'
rm "$CLAUDE_COUNT"
CLAUDE_BAD=once "$routine" draft > /dev/null
[[ $(cat "$CLAUDE_COUNT") == 2 ]] || fail 'Schema failure not retried'
rm "$CLAUDE_COUNT"
if CLAUDE_BAD=always "$routine" draft > /dev/null 2>&1; then fail 'Invalid Claude schema accepted'; fi
[[ $(cat "$CLAUDE_COUNT") == 2 ]] || fail 'Unbounded Claude retries'
CLAUDE_RESULT=1 "$routine" draft > /dev/null
# Real named pasteboard smoke: an unattended run leaves it unchanged, copy sets rich/plain data.
echo '[[{"type":"public.utf8-plain-text","data":"b3JpZ2luYWw="}]]' > "$sandbox/seed.json"
/usr/bin/osascript -l JavaScript "$repo/tests/pasteboard.js" seed "$sandbox/seed.json"
: > "$RECORD"
"$routine" run --only scrum-draft --only scrum-paste > "$sandbox/morning"
/usr/bin/osascript -l JavaScript "$repo/tests/pasteboard.js" read > "$sandbox/board.json"
jq -e '.[0][0].data=="b3JpZ2luYWw="' "$sandbox/board.json" >/dev/null || fail 'Unattended clipboard changed'
! grep -q 'orca\|clipboard.js\|open ' "$RECORD" || fail 'Unattended clipboard mode touched UI'
: > "$RECORD"
ROUTINE_NOW='2026-09-28T08:30:00+09:00' "$routine" paste --auto --no-draft > "$sandbox/clipboard-auto"
[[ ! -s $RECORD ]] || fail 'Clipboard auto paste called GUI/clipboard commands'
"$routine" copy
/usr/bin/osascript -l JavaScript "$repo/tests/pasteboard.js" read > "$sandbox/board.json"
jq -e 'any(.[0][];.type=="public.html") and any(.[0][];.type=="public.utf8-plain-text")' "$sandbox/board.json" >/dev/null || fail 'Copy rich formats missing'
grep -Fq 'open slack://channel?team=TEXAMPLE&id=CEXAMPLE' "$RECORD" || fail 'Copy missing deeplink'
! grep -q 'orca' "$RECORD" || fail 'Copy manipulated editor'
# Claude Code records: same window and bounded selection, independent evidence identities.
base="$sandbox/claude-projects/project"; mkdir -p "$base"
printf '%s\n' '{"type":"user","sessionId":"same","timestamp":"2026-09-25T01:00:00.000Z","cwd":"/fixture","message":{"role":"user","content":"예제 작업"}}' > "$base/session.jsonl"
printf -v padding '%01200d' 0
for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13; do
  printf -v minute '%02d' "$i"
  text="최근 대화$i"; ((i>=10)) || text="확인 결과 보고$i"
  jq -nc --arg ts "2026-09-25T02:$minute:00.000Z" --arg text "$text $padding ASIAABCDEFGHIJKLMNOP https://example.com/file?X-Amz-Signature=secret" '{type:"assistant",sessionId:"same",timestamp:$ts,message:{role:"assistant",content:[{type:"text",text:$text},{type:"tool_use",input:{secret:"ignore"}}]}}' >> "$base/session.jsonl"
done
printf '%s\n' '{"type":"assistant","sessionId":"same","timestamp":"2026-09-29T01:00:00Z","message":{"role":"assistant","content":[{"type":"text","text":"창 밖"}]}}' >> "$base/session.jsonl"
"$routine" --set sources.claude_sessions.dir "\"$sandbox/claude-projects\"" collect --sources claude_sessions --since 2026-09-25 --until 2026-09-28T09:00:00+09:00 --out "$sandbox/claude-out"
jq -e '.sessions|length==1 and .[0].id=="same" and .[0].source=="claude" and .[0].evidence_id=="claude-session:same" and (.[0].reports|length)==10 and (.[0].reports|map(.text|length)|add)<=6000 and all(.[0].reports[];(.text|length)<=1000 and (.text|test("ASIA|Signature|창 밖")|not)) and (.[0].latest_report|length)<=1000' "$sandbox/claude-out/2026-09-28.json" >/dev/null || fail 'Claude session window/budget/redaction'
# The same raw OMP ID cannot provide the same evidence identity.
jq -L "$repo/share" -e 'include "scrum"; .sessions += [{id:"same",source:"omp",latest_report:"OMP only"}] | evidence_catalog({today:[]}) | any(.[];.id=="session:same" and .text=="OMP only") and any(.[];.id=="claude-session:same")' "$sandbox/claude-out/2026-09-28.json" >/dev/null || fail 'Session evidence namespace collision'
meta="$sandbox/claude-meta/project"; mkdir -p "$meta"
cp "$repo/tests/fixtures/claude-session-meta.jsonl" "$meta/session.jsonl"
for i in {10..39}; do
  jq -nc --arg ts "2026-09-25T00:$i:00.000Z" --arg text "API 추가 요청 $i" '{type:"user",sessionId:"meta-session",timestamp:$ts,message:{role:"user",content:[{type:"text",text:$text}]}}' >> "$meta/session.jsonl"
done
"$routine" --set sources.claude_sessions.dir "\"$sandbox/claude-meta\"" collect --sources claude_sessions --since 2026-09-25 --until 2026-09-28T09:00:00+09:00 --out "$sandbox/meta-out"
jq -e '.sessions[0] | .title=="API 상태 확인" and (.user_messages|length)==20 and .user_messages[0].text=="API 상태 확인" and .user_messages[-1].text=="API 추가 요청 39" and all(.user_messages[];.text|test("^(API 상태 확인|API 추가 요청 [0-9]+)$")) and (.reports|length)==1 and .reports[0].evidence_id=="claude-session:meta-session#0"' "$sandbox/meta-out/2026-09-28.json" >/dev/null || fail 'Claude metadata/empty text/command filtering or message cap'
# Setup's non-TTY failure/resume and confirmation boundary use only private stubs.
"$routine" setup --non-interactive --skip disk-access --skip launchd --skip first-run > "$sandbox/setup-one"
grep -q '✓ platform' "$sandbox/setup-one" || fail 'Non-TTY progress absent'
"$routine" setup --non-interactive --skip disk-access --skip launchd --skip first-run > "$sandbox/setup-two"
grep -q '✓ dependencies' "$sandbox/setup-two" || fail 'Idempotent setup'
if GH_AUTH_FAIL=1 "$routine" setup --non-interactive --skip disk-access --skip launchd --skip first-run > "$sandbox/setup-fail"; then fail 'Setup passed failed auth'; fi
grep -q '✗ github' "$sandbox/setup-fail" || fail 'Setup failure step absent'
! grep -q '진행 llm' "$sandbox/setup-fail" || fail 'Setup continued after failure'
"$routine" setup --non-interactive --skip disk-access --skip launchd --skip first-run > "$sandbox/setup-resume"
# Mask dependency resolution without exposing an operator's Homebrew gh.
export MISSING_DEPENDENCY=gh MISSING_RESOLVED="$sandbox/gh-resolved" STUB_DIR="$sandbox/stubs"
: > "$RECORD"
if "$routine" setup --non-interactive --skip disk-access --skip launchd --skip first-run > "$sandbox/setup-no-consent"; then fail 'Setup installed without consent'; fi
! grep -q 'brew install' "$RECORD" || fail 'Missing --yes executed brew'
"$routine" setup --yes --non-interactive --skip disk-access --skip launchd --skip first-run > "$sandbox/setup-consent"
grep -q 'brew install jq coreutils gh' "$RECORD" || fail 'Confirmed dependency installation not exercised'
unset MISSING_DEPENDENCY MISSING_RESOLVED
# jq 1.6 is insufficient even when an executable exists; brew remains consent-gated.
mv "$sandbox/stubs/jq" "$sandbox/jq-good"
cat > "$sandbox/stubs/jq" <<'STUB'
#!/usr/bin/env bash
if [[ ${1:-} == --version ]]; then echo 'jq-1.6'; else exec "$SAVED_JQ" "$@"; fi
STUB
chmod +x "$sandbox/stubs/jq"
export SAVED_JQ="$real_jq"
if "$routine" doctor > "$sandbox/doctor-old-jq"; then fail 'Doctor accepted jq 1.6'; fi
: > "$RECORD"
if "$routine" setup --non-interactive --skip disk-access --skip launchd --skip first-run > "$sandbox/setup-old-jq"; then fail 'Old jq dependency bypassed consent'; fi
! grep -q 'brew install' "$RECORD" || fail 'Old jq upgraded without consent'
"$routine" setup --yes --non-interactive --skip disk-access --skip launchd --skip first-run > "$sandbox/setup-upgrade-jq"
grep -q 'brew install jq coreutils gh' "$RECORD" || fail 'Old jq upgrade not offered/executed by stub'
mv -f "$sandbox/jq-good" "$sandbox/stubs/jq"; unset SAVED_JQ
# Engine fallback and explicit setup choices persist instead of changing only this process.
CLAUDE_MISSING=1 "$routine" setup --non-interactive --skip disk-access --skip launchd --skip first-run > "$sandbox/setup-omp"
jq -e '.draft.llm.engine=="omp"' "$ROUTINE_CONFIG" >/dev/null || fail 'Setup omp fallback not persisted'
"$routine" setup --non-interactive --draft-llm-engine claude --delivery-mode clipboard --skip disk-access --skip launchd --skip first-run > "$sandbox/setup-explicit"
jq -e '.draft.llm.engine=="claude" and .delivery.mode=="clipboard"' "$ROUTINE_CONFIG" >/dev/null || fail 'Explicit setup choices not persisted'
if "$routine" --set morning.time '"06:00"' setup --non-interactive > /dev/null 2>&1; then fail 'Setup accepted transient global settings'; fi
# A genuinely jq-free PATH runs dependencies before loading config; only private stubs are executable.
minimal="$sandbox/minimal"; mkdir "$minimal"
for cmd in bash dirname uname date mkdir chmod mktemp mv rm sleep ln touch; do ln -s "$(command -v "$cmd")" "$minimal/$cmd"; done
for cmd in brew gh gtimeout; do ln -s "$sandbox/stubs/$cmd" "$minimal/$cmd"; done
PATH="$minimal" SAVED_JQ="$real_jq" STUB_DIR="$minimal" /bin/bash "$repo/bin/routine-setup" --yes --non-interactive --skip platform --skip github --skip llm --skip slack --skip orca --skip disk-access --skip config --skip launchd --skip first-run > "$sandbox/setup-no-jq"
if [[ ! -x $minimal/jq ]] || ! grep -q '✓ dependencies' "$sandbox/setup-no-jq"; then fail 'jq-free dependency bootstrap failed'; fi
: > "$RECORD"
if "$routine" setup --yes --non-interactive --skip platform --skip dependencies --skip github --skip llm --skip slack --skip orca --skip config --skip launchd --skip first-run > "$sandbox/fda"; then fail '--yes confirmed FDA without evidence'; fi
! grep -q '^open ' "$RECORD" || fail 'Non-TTY FDA opened system panel'
jq -e '.disk_access_confirmation!="explicit"' "$HOME/Library/Logs/routine-automation/setup-state.json" >/dev/null || fail 'FDA silently persisted confirmation'
/usr/bin/expect "$repo/tests/fixtures/setup-pty.exp" "$routine" "$sandbox/tty-command" "$sandbox/tty-fda" disk > /dev/null
jq -e '.disk_access_confirmation!="explicit"' "$HOME/Library/Logs/routine-automation/setup-state.json" >/dev/null || fail '--yes bypassed explicit TTY FDA confirmation'
setup_state="$HOME/Library/Logs/routine-automation/setup-state.json"
mkdir "$HOME/Library/Mail"; chmod 000 "$HOME/Library/Mail"
/usr/bin/expect "$repo/tests/fixtures/setup-pty.exp" "$routine" "$sandbox/tty-command" "$sandbox/tty-fda-yes-denied" disk-yes > /dev/null
jq -e '.disk_access_confirmation=="explicit"' "$setup_state" >/dev/null || fail 'Terminal denial blocked explicit FDA confirmation'
chmod 700 "$HOME/Library/Mail"
# Terminal readability alone is not launchd /bin/bash permission proof.
jq 'del(.disk_access_confirmation)' "$setup_state" > "$sandbox/no-disk-confirmation"; mv "$sandbox/no-disk-confirmation" "$setup_state"
: > "$RECORD"
if "$routine" setup --yes --non-interactive --skip platform --skip dependencies --skip github --skip llm --skip slack --skip orca --skip config --skip launchd --skip first-run > "$sandbox/fda-readable"; then fail 'Terminal readability bypassed explicit confirmation'; fi
! grep -q '^open ' "$RECORD" || fail 'Non-TTY readable probe opened panel'
rmdir "$HOME/Library/Mail"
# Doctor only checks visible state. Closed combo/editor labels are unverified, not failures.
"$routine" config set delivery.mode '"gui-paste"'
"$routine" doctor > "$sandbox/doctor"
grep -q 'combo: 미검증' "$sandbox/doctor" || fail 'Doctor failed closed labels'
if DOCTOR_DRIFT=1 "$routine" doctor > "$sandbox/doctor-drift"; then fail 'Doctor accepted visible main-screen label drift'; fi
MISSING_DEPENDENCY=gtimeout MISSING_RESOLVED="$sandbox/no-gtimeout" "$routine" doctor > "$sandbox/doctor-missing" && fail 'Doctor accepted missing dependency'
"$routine" config set delivery.mode '"clipboard"'
"$routine" doctor > "$sandbox/doctor-clipboard"
grep -q 'paste LaunchAgent 잔존' "$sandbox/doctor-clipboard" || fail 'Doctor omitted residual GUI agent warning'
# Package from committed fixture worktrees, then update across differently named extraction folders.
worktree="$sandbox/package-repo"
git clone -q --no-hardlinks --no-checkout "$repo" "$worktree"
cp -R "$repo/bin" "$repo/share" "$repo/launchd" "$repo/tests" "$worktree/"
cp "$repo/VERSION" "$repo/install.sh" "$repo/uninstall.sh" "$repo/.gitignore" "$repo/LICENSE" "$worktree/"
printf '1.0.0\n' > "$worktree/VERSION"
git -C "$worktree" add -A .
git -C "$worktree" -c user.name=Fixture -c user.email=fixture@example.com commit -qm v1
"$worktree/bin/routine" package > "$sandbox/package-one"
mkdir "$sandbox/A" "$sandbox/B"
unzip -q "$worktree/dist/routine-automation-1.0.0.zip" -d "$sandbox/A"
echo '1.0.1' > "$worktree/VERSION"
if "$worktree/bin/routine" package > /dev/null 2>&1; then fail 'Dirty package accepted'; fi
git -C "$worktree" add VERSION
git -C "$worktree" -c user.name=Fixture -c user.email=fixture@example.com commit -qm v2
"$worktree/bin/routine" package > "$sandbox/package-two"
private_marker='private-fixture-'; private_marker+='secret-123'
printf '%s\n' "$private_marker" > "$worktree/.personal-patterns"
printf '%s\n' "$private_marker" > "$worktree/private-fixture.txt"
git -C "$worktree" add private-fixture.txt
git -C "$worktree" -c user.name=Fixture -c user.email=fixture@example.com commit -qm 'private fixture'
if "$worktree/bin/routine" package > "$sandbox/package-private" 2>&1; then fail 'Package exported matching private content'; fi
[[ ! -e $worktree/dist/routine-automation-1.0.1.zip ]] || fail 'Rejected private archive remained distributable'
! grep -Fq "$private_marker" "$sandbox/package-private" || fail 'Package printed private pattern/content'
printf 'public fixture\n' > "$worktree/private-fixture.txt"
git -C "$worktree" add private-fixture.txt
git -C "$worktree" -c user.name=Fixture -c user.email=fixture@example.com commit -qm 'public fixture'
"$worktree/bin/routine" package > "$sandbox/package-scanned"
unzip -q "$worktree/dist/routine-automation-1.0.1.zip" -d "$sandbox/B"
install_args=(--non-interactive --skip platform --skip dependencies --skip github --skip llm --skip slack --skip orca --skip disk-access --skip config --skip first-run)
printf 'foreign\n' > "$ROUTINE_BIN_DIR/routine"
if "$sandbox/A/routine-automation-1.0.0/bin/routine" setup "${install_args[@]}" > /dev/null 2>&1; then fail 'Foreign link overwritten'; fi
[[ $(cat "$ROUTINE_BIN_DIR/routine") == foreign ]] || fail 'Foreign file modified'
rm "$ROUTINE_BIN_DIR/routine"
mkdir -p "$ROUTINE_LAUNCH_AGENTS_DIR"
foreign_plist="$ROUTINE_LAUNCH_AGENTS_DIR/com.fixture.routine.morning.plist"
printf 'foreign plist\n' > "$foreign_plist"
if "$sandbox/A/routine-automation-1.0.0/bin/routine" setup "${install_args[@]}" > /dev/null 2>&1; then fail 'Foreign plist overwritten'; fi
[[ $(cat "$foreign_plist") == 'foreign plist' && ! -e $ROUTINE_BIN_DIR/routine ]] || fail 'Plist preflight changed foreign files'
rm "$foreign_plist"
foreign_app="$HOME/Applications/스크럼 초안 복사.app"
mkdir -p "$foreign_app"; printf 'foreign app\n' > "$foreign_app/user-file"
if "$sandbox/A/routine-automation-1.0.0/bin/routine" setup "${install_args[@]}" > /dev/null 2>&1; then fail 'Foreign app overwritten'; fi
[[ $(cat "$foreign_app/user-file") == 'foreign app' ]] || fail 'Foreign app modified'
rm "$foreign_app/user-file"; rmdir "$foreign_app"
"$sandbox/A/routine-automation-1.0.0/bin/routine" setup "${install_args[@]}" > "$sandbox/install-one"
installed="$HOME/.local/share/routine-automation"
[[ -L $ROUTINE_BIN_DIR/routine && ! -e $ROUTINE_BIN_DIR/morning && -d $HOME/Applications/스크럼\ 초안\ 복사.app ]] || fail 'Unified link/copy app cutover'
config_before=$(shasum -a 256 "$ROUTINE_CONFIG")
id_before=$(cat "$installed/install-id")
before_manifest=$(shasum -a 256 "$installed/manifest.json")
# shellcheck disable=SC2329 # Exported fault injection is invoked in the install subprocess.
mv() {
  if [[ ${FAIL_ROOT_RENAME:-0} == 1 && ${1:-} == "$HOME/.local/share"/.routine-install.* && ${2:-} == "$HOME/.local/share/routine-automation" ]]; then return 71; fi
  if [[ ${CRASH_AT:-} == root-before && ${1:-} == "$HOME/.local/share"/.routine-install.* && ${2:-} == "$HOME/.local/share/routine-automation" ]] ||
     [[ ${CRASH_AT:-} == root-after && ${1:-} == "$HOME/.local/share"/.routine-transaction.*/new-copy.app && ${2:-} == "$HOME/Applications/스크럼 초안 복사.app" ]]; then exec /bin/sh -c 'kill -KILL "$$"'; fi
  if [[ ${CRASH_AT:-} == review-after && ${1:-} == "$HOME/.local/share"/.routine-transaction.*/new-review.app && ${2:-} == "$HOME/Applications/스크럼 초안 검토.app" ]]; then
    builtin command mv "$@"; exec /bin/sh -c 'kill -KILL "$$"'
  fi
  if [[ ${CRASH_AT:-} == link-after && ${1:-} == -f && ${2:-} == "$HOME/.local/share"/.routine-transaction.*/routine-link ]]; then
    builtin command mv "$@"; exec /bin/sh -c 'kill -KILL "$$"'
  fi
  command mv "$@"
}
export -f mv
rollback_bootstraps=$(grep -c '^launchctl bootstrap' "$RECORD")
if FAIL_ROOT_RENAME=1 "$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > /dev/null 2>&1; then fail 'Failed atomic root rename passed'; fi
[[ $(cat "$installed/VERSION") == 1.0.0 && $(shasum -a 256 "$installed/manifest.json") == "$before_manifest" && -d $foreign_app && -f $foreign_plist ]] || fail 'Failed root replacement did not restore complete installation'
[[ $(grep -c '^launchctl bootstrap' "$RECORD") == "$((rollback_bootstraps+1))" ]] || fail 'Rollback did not reload previously loaded morning agent'
# Real SIGKILL of only the private install subprocess leaves K2/K3/K4 journals.
# shellcheck source=../share/install.sh
source "$repo/share/install.sh"
routine_install_paths
for crash in root-before root-after review-after link-after; do
  if CRASH_AT="$crash" "$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > "$sandbox/crash-$crash" 2>&1; then fail 'Killed install reported success'; fi
  [[ -d $installed.previous ]] || fail 'Crash did not leave the prior generation'
  if [[ $crash == root-after ]]; then
    for receipt_dir in "$HOME/.local/share"/.routine-transaction.*; do [[ -f $receipt_dir/receipt.json ]] || continue; break; done
    printf 'keep user data\n' > "$receipt_dir/user-note"
    if routine_recover_installation > /dev/null 2>&1; then fail 'Recovery accepted user data added to owned transaction'; fi
    [[ -f $receipt_dir/user-note && -d $installed.previous ]] || fail 'Failed ownership proof discarded prior generation/user data'
    rm "$receipt_dir/user-note"
  fi
  routine_recover_installation > "$sandbox/recover-$crash"
  [[ $(cat "$installed/VERSION") == 1.0.0 && -f $foreign_plist && -d $foreign_app && -L $ROUTINE_BIN_DIR/routine && ! -e $installed.previous ]] || fail 'Crash recovery lost prior root/external assets'
  if [[ ! -d $review_app ]] || ! routine_verify_ownership; then fail 'Crash recovery lost owned review app'; fi
  launchctl print "gui/$(id -u)/com.fixture.routine.morning" >/dev/null || fail 'Crash recovery did not restore loaded service'
  for leftover in "$HOME/.local/share"/.routine-install.* "$HOME/.local/share"/.routine-transaction.*; do [[ ! -e $leftover ]] || fail 'Proven stale install/transaction directory survived'; done
done
# Matching names alone never confer ownership.
mkdir "$HOME/.local/share/.routine-install.Unowned" "$HOME/.local/share/.routine-transaction.Unowned"
printf 'keep user data\n' > "$HOME/.local/share/.routine-install.Unowned/user-note"
printf 'keep user data\n' > "$HOME/.local/share/.routine-transaction.Unowned/user-note"
routine_recover_installation > /dev/null 2>&1
[[ -f $HOME/.local/share/.routine-install.Unowned/user-note && -f $HOME/.local/share/.routine-transaction.Unowned/user-note ]] || fail 'Unowned temporary-directory contents deleted'
rm -r "$HOME/.local/share/.routine-install.Unowned" "$HOME/.local/share/.routine-transaction.Unowned"
unset -f mv
ln -s "$installed/bin/morning" "$ROUTINE_BIN_DIR/morning"
ln -s "$sandbox/unrelated" "$ROUTINE_BIN_DIR/scrum-draft"
"$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > "$sandbox/install-two"
[[ $(cat "$installed/install-id") == "$id_before" && $(cat "$installed/VERSION") == 1.0.1 && $(shasum -a 256 "$ROUTINE_CONFIG") == "$config_before" ]] || fail 'Cross-folder update/config preservation'
[[ ! -L $ROUTINE_BIN_DIR/morning && $(readlink "$ROUTINE_BIN_DIR/scrum-draft") == "$sandbox/unrelated" ]] || fail 'Legacy link ownership cutover'
effects_before=$(grep -cE '^launchctl (bootout|bootstrap)|^osacompile' "$RECORD")
"$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > "$sandbox/install-current"
[[ $(grep -cE '^launchctl (bootout|bootstrap)|^osacompile' "$RECORD") == "$effects_before" ]] || fail 'Idempotent setup reinstalled satisfied files/agents'
plist="$ROUTINE_LAUNCH_AGENTS_DIR/com.fixture.routine.morning.plist"
[[ $(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$plist") == run && $(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:0:Hour' "$plist") == 8 ]] || fail 'Scheduled routine run contract'
# launchd runs agents with only the plist PATH; the GUI guard needs ioreg (/usr/sbin) and lsappinfo.
agent_path=$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PATH' "$plist")
for tool in ioreg lsappinfo osascript; do
  env -i PATH="$agent_path" /bin/bash -c "command -v $tool" > /dev/null || fail "Scheduled agent PATH cannot find $tool"
done
# The paste agent regenerates drafts with the LLM engine; with omp installed only via bun (~/.bun/bin)
# and an older copy in Homebrew, it must pick the bun one like morning does.
[[ ! -e $HOME/.local/bin/omp ]] || mv "$HOME/.local/bin/omp" "$sandbox/omp.local-stub"
mkdir -p "$HOME/.bun/bin"; printf '#!/bin/sh\nexit 0\n' > "$HOME/.bun/bin/omp"; chmod +x "$HOME/.bun/bin/omp"
resolved_omp=$(env -i PATH="$agent_path" /bin/bash -c 'command -v omp')
[[ $resolved_omp == "$HOME/.bun/bin/omp" ]] || fail "Scheduled agent PATH resolves a different omp than morning: $resolved_omp"
rm -rf "$HOME/.bun"
[[ ! -e $sandbox/omp.local-stub ]] || mv "$sandbox/omp.local-stub" "$HOME/.local/bin/omp"
[[ ! -e $ROUTINE_LAUNCH_AGENTS_DIR/com.fixture.routine.scrum-paste.plist ]] || fail 'Clipboard installed GUI agent'
mv "$foreign_app" "$sandbox/removed-copy.app"
rm "$ROUTINE_BIN_DIR/routine" "$installed/share/items-schema.json" "$plist"
missing_bootouts=$(grep -c '^launchctl bootout' "$RECORD")
"$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > "$sandbox/install-repair"
[[ -d $foreign_app && -L $ROUTINE_BIN_DIR/routine && -f $installed/share/items-schema.json && -f $plist && $(cat "$installed/install-id") == "$id_before" ]] || fail 'Missing managed assets were not repaired'
[[ $(grep -c '^launchctl bootout' "$RECORD") == "$((missing_bootouts+1))" ]] || fail 'Missing plist hid a loaded agent from update bootout'
mv "$installed" "$installed.previous"
"$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > "$sandbox/install-recover"
[[ -f $installed/manifest.json && ! -e $installed.previous && $(cat "$installed/install-id") == "$id_before" ]] || fail 'Interrupted root rename recovery failed'
echo foreign > "$installed/user-note"
if "$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > /dev/null 2>&1; then fail 'Unowned root file accepted'; fi
[[ $(cat "$installed/user-note") == foreign ]] || fail 'Unowned root file deleted'
rm "$installed/user-note"
printf '# modified by user\n' >> "$installed/bin/morning"
if "$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > /dev/null 2>&1; then fail 'Modified managed file overwritten'; fi
cp "$sandbox/B/routine-automation-1.0.1/bin/morning" "$installed/bin/morning"
printf 'foreign-id\n' > "$installed/install-id"
if "$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > /dev/null 2>&1; then fail 'Foreign install ID accepted'; fi
printf '%s\n' "$id_before" > "$installed/install-id"
"$routine" config set delivery.mode '"gui-paste"'
"$routine" config set morning.time '"07:45"'
"$routine" config set morning.weekdays '[2,4,7]'
bootstraps_before=$(grep -c '^launchctl bootstrap' "$RECORD")
LAUNCH_FAIL_FIRST=1 "$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > "$sandbox/install-gui"
[[ $(grep -c '^launchctl bootstrap' "$RECORD") == "$((bootstraps_before+3))" ]] || fail 'LaunchAgent bootstrap retry regression'
paste_plist="$ROUTINE_LAUNCH_AGENTS_DIR/com.fixture.routine.scrum-paste.plist"
[[ $(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$paste_plist") == paste && $(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:3' "$paste_plist") == --auto ]] || fail 'GUI agent entrypoint contract'
[[ $(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:0:Hour' "$plist") == 7 && $(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:0:Minute' "$plist") == 45 && $(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:2:Weekday' "$plist") == 0 ]] || fail 'Configured time/weekdays not scheduled'
"$routine" config set delivery.mode '"clipboard"'
"$routine" config set morning.time '"08:00"'
"$routine" config set morning.weekdays '[1,2,3,4,5]'
"$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > "$sandbox/install-clipboard"
ROUTINE_MORNING_TIME=06:00 ROUTINE_DELIVERY_MODE=gui-paste "$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > "$sandbox/install-transient"
jq -e '.morning.time=="08:00" and .delivery.mode=="clipboard"' "$ROUTINE_CONFIG" >/dev/null || fail 'Setup environment leaked into permanent config'
[[ $(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:0:Hour' "$plist") == 8 && ! -e $paste_plist ]] || fail 'Transient environment leaked into permanent LaunchAgents'
[[ ! -e $paste_plist ]] || fail 'Obsolete owned GUI agent survived clipboard cutover'
# First-run launchd smoke executes copied routine with real collect/draft and stubbed LLM, no GUI.
mkdir "$HOME/Library/Mail"
MORNING_DENY_FDA=1 "$sandbox/B/routine-automation-1.0.1/bin/routine" setup --non-interactive --skip platform --skip dependencies --skip github --skip llm --skip slack --skip orca --skip disk-access --skip config --skip launchd > "$sandbox/first-run-fda-warning"
first_result="$HOME/Library/Application Support/routine-automation/.setup-first-run-result.json"
jq -e '.exit_code==0 and .full_disk_access.status=="denied"' "$first_result" >/dev/null || fail 'First-run protected-path denial did not remain a recorded warning'
"$routine" status > "$sandbox/status-fda"; "$routine" doctor > "$sandbox/doctor-fda"
for output in first-run-fda-warning status-fda doctor-fda; do grep -q '/bin/bash에 전체 디스크 접근 허용 필요' "$sandbox/$output" || fail 'Recorded FDA warning missing from setup/status/doctor'; done
"$sandbox/B/routine-automation-1.0.1/bin/routine" setup --non-interactive --skip platform --skip dependencies --skip github --skip llm --skip slack --skip orca --skip disk-access --skip config --skip launchd > "$sandbox/first-run"
grep -q '결과 파일:' "$sandbox/first-run" || fail 'First-run result absent'
jq -e '.full_disk_access.status=="readable"' "$first_result" >/dev/null || fail 'Denied first-run FDA result was not rechecked after granting access'
! grep -q 'orca computer click\|orca computer hotkey' "$RECORD" || fail 'Setup first run manipulated GUI'
kickstarts_before=$(grep -c '^launchctl kickstart' "$RECORD")
"$sandbox/B/routine-automation-1.0.1/bin/routine" setup --non-interactive --skip platform --skip dependencies --skip github --skip llm --skip slack --skip orca --skip disk-access --skip config --skip launchd > "$sandbox/first-run-current"
[[ $(grep -c '^launchctl kickstart' "$RECORD") == "$kickstarts_before" ]] || fail 'Idempotent setup repeated verified first run'
rmdir "$HOME/Library/Mail"
start=$SECONDS
if LAUNCH_RUN_ASYNC=1 CLAUDE_EXEC_FAIL=1 ROUTINE_NOW='2026-09-29T09:00:00+09:00' "$sandbox/B/routine-automation-1.0.1/bin/routine" setup --non-interactive --skip platform --skip dependencies --skip github --skip llm --skip slack --skip orca --skip disk-access --skip config --skip launchd > "$sandbox/first-run-failure"; then fail 'Failed morning reported setup success'; fi
[[ $((SECONDS-start)) -lt 20 && ! -e $HOME/Library/Application\ Support/routine-automation/.setup-first-run ]] || fail 'First-run failure was not immediate or left stale marker'
jq -e '.exit_code!=0' "$HOME/Library/Application Support/routine-automation/.setup-first-run-result.json" >/dev/null || fail 'Morning failure result absent'
grep -q '✗ first-run' "$sandbox/first-run-failure" || fail 'First-run failure not displayed'
cp "$sandbox/claude-out/2026-09-28.json" "$out/2026-09-28.json"
"$routine" status > "$sandbox/status"
grep -q '다음 예약: 2026-09-29 08:00' "$sandbox/status" || fail 'Status next schedule'
grep -q 'claude_sessions: 1건' "$sandbox/status" || fail 'Status source count'
grep -q '전달 \[copied\]:' "$sandbox/status" || fail 'Status delivery marker'
ROUTINE_TZ=UTC "$routine" status > "$sandbox/status-utc"
grep -q '다음 예약: 2026-09-28 08:00' "$sandbox/status-utc" || fail 'Schedule ignored absolute now offset'
if LAUNCH_BOOTOUT_FAIL=1 "$routine" uninstall > /dev/null 2>&1; then fail 'Uninstall removed active failed-bootout service'; fi
[[ -f $plist ]] || fail 'Failed bootout removed plist'
cp "$ROUTINE_CONFIG" "$sandbox/config-before-uninstall"
printf '{broken' > "$ROUTINE_CONFIG"
mv "$foreign_app" "$sandbox/removed-again.app"
rm "$installed/share/items-schema.json" "$ROUTINE_BIN_DIR/routine"
rm "$plist"
missing_uninstall_bootouts=$(grep -c '^launchctl bootout' "$RECORD")
mv "$installed" "$installed.previous"
"$routine" uninstall
[[ ! -e $installed && ! -e $ROUTINE_BIN_DIR/routine && ! -e $plist && -f $ROUTINE_CONFIG && -f $out/2026-09-28.draft.json ]] || fail 'Uninstall ownership/data preservation'
[[ ! -e $installed.previous && $(grep -c '^launchctl bootout' "$RECORD") == "$((missing_uninstall_bootouts+1))" ]] || fail 'Previous-only root/missing plist bypassed owned uninstall'
[[ -L $ROUTINE_BIN_DIR/scrum-draft ]] || fail 'Uninstall removed unowned legacy link'
cp "$sandbox/config-before-uninstall" "$ROUTINE_CONFIG"
# Legacy format migration verifies first, then replaces both old agents and owned CLI links.
mkdir -p "$installed/bin" "$installed/share"
for name in morning scrum-collect scrum-draft scrum-paste; do cp "$repo/bin/$name" "$installed/bin/$name"; done
cp "$repo/share/scrum.jq" "$installed/share/scrum.jq"
printf '%s\n' "$sandbox/old-release-folder" > "$installed/.source-repo"
printf '%s\n' bin/morning bin/scrum-collect bin/scrum-draft bin/scrum-paste share/scrum.jq launchd/com.fixture.routine.morning.plist launchd/com.fixture.routine.scrum-paste.plist > "$installed/.files"
for service in morning scrum-paste; do
  printf '<plist version="1.0"><dict><key>Label</key><string>com.fixture.routine.%s</string><key>ProgramArguments</key><array><string>/bin/bash</string><string>%s/bin/%s</string></array></dict></plist>\n' "$service" "$installed" "$service" > "$ROUTINE_LAUNCH_AGENTS_DIR/com.fixture.routine.$service.plist"
  launchctl bootstrap "gui/$(id -u)" "$ROUTINE_LAUNCH_AGENTS_DIR/com.fixture.routine.$service.plist"
done
mv "$ROUTINE_BIN_DIR/scrum-draft" "$sandbox/unowned-link"
for name in morning scrum-collect scrum-draft scrum-paste; do ln -s "$installed/bin/$name" "$ROUTINE_BIN_DIR/$name"; done
echo 'user note' > "$installed/user-note"
if "$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > /dev/null 2>&1; then fail 'Legacy migration accepted untracked file'; fi
[[ -f $installed/.source-repo && -f $installed/.files && ! -e $installed/manifest.json && ! -e $installed/install-id ]] || fail 'Rejected legacy migration changed ownership metadata'
rm "$installed/user-note"
legacy_bootouts=$(grep -c '^launchctl bootout' "$RECORD")
"$sandbox/B/routine-automation-1.0.1/bin/routine" setup "${install_args[@]}" > "$sandbox/legacy-migrate"
[[ $(grep -c '^launchctl bootout' "$RECORD") == "$((legacy_bootouts+2))" && -f $installed/manifest.json && ! -e $installed/.source-repo && ! -e $installed/.files && ! -e $paste_plist ]] || fail 'Legacy agents/metadata not migrated'
for name in morning scrum-collect scrum-draft scrum-paste; do [[ ! -L $ROUTINE_BIN_DIR/$name ]] || fail 'Owned legacy CLI link survived'; done
mv "$sandbox/unowned-link" "$ROUTINE_BIN_DIR/scrum-draft"
"$routine" uninstall > /dev/null
"$routine" uninstall --purge
[[ ! -e $ROUTINE_CONFIG && ! -e $out ]] || fail 'Purge left settings/data'
if [[ -f $repo/.personal-patterns ]]; then
  if git -C "$repo" grep -qIE -f "$repo/.personal-patterns" -- .; then fail 'Personal patterns remain in tracked files'; fi
else echo 'SKIP: 로컬 개인 패턴 파일 없음'; fi
echo 'PASS: config/init, Claude isolation/sessions, clipboard, setup/doctor/status, zip cross-folder update/uninstall'
