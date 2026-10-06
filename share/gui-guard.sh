#!/usr/bin/env bash
# shellcheck disable=SC2034 # failure_reason is consumed by caller cleanup.
# $2 (optional): the Orca state file that failed to parse. Its accessibility *structure* is kept for
# diagnosis with text, values, names and organisation identifiers masked (share/slack.jq structure_dump).
# $3 (optional): a step trace (one line per poll; no screen text) appended to the capture.
slack_format_notice() {
  local message="Slack/Orca 화면 형식 변경 의심 — $1" state=${2:-} trace=${3:-} dir stamp old captures
  printf '%s\n' "$message" >&2
  failure_reason=$message
  if [[ -n $state && -r $state ]]; then
    dir="$HOME/Library/Logs/routine-automation/slack-format"
    stamp="$(date '+%Y%m%d-%H%M%S')-$$"
    if (umask 077 && mkdir -p "$dir" && chmod 700 "$dir" &&
        jq -L "${share_dir:?}" -r --arg what "$1" \
          'include "slack"; [tree_text|structure_dump] | if length==0 then error("empty") else
            "# routine \($what) — 화면 구조만 저장(본문·값·이름·조직 식별자 가림, 로컬 진단용)", .[] end' \
          "$state" > "$dir/$stamp.tmp" &&
        { [[ -z $trace || ! -r $trace ]] || { printf '# 폴링 추적\n'; cat "$trace"; } >> "$dir/$stamp.tmp"; } &&
        mv -f "$dir/$stamp.tmp" "$dir/$stamp.txt") 2>/dev/null; then
      printf '진단용 화면 구조: %s\n' "$dir/$stamp.txt" >&2
      # Keep the 20 most recent captures (our own names only; never recurse or follow other files).
      captures=("$dir"/[0-9]*-[0-9]*-[0-9]*.txt)
      if ((${#captures[@]} > 20)); then
        for old in "${captures[@]:0:${#captures[@]}-20}"; do [[ -f $old ]] && rm -f -- "$old"; done
      fi
    else rm -f -- "$dir/$stamp.tmp" 2>/dev/null; fi
  fi
  [[ ${ROUTINE_SLACK_FORMAT_DEFERRED:-0} != 1 ]] || return 0
  if command -v osascript >/dev/null; then
    osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "routine"' -e 'end run' "$message" || true
  fi
  return 0
}
# A shared activity file propagates our last GUI action across draft/collect children.
hid_idle_ns() {
  local hid
  hid=$(ioreg -c IOHIDSystem) || return 1
  [[ $hid =~ \"HIDIdleTime\"[[:space:]]*=[[:space:]]*([0-9]+) ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}
console_unlocked() {
  local root remaining session matched uid
  root=$(ioreg -n Root -d1) || return 1
  [[ $root =~ \"IOConsoleLocked\"[[:space:]]*=[[:space:]]*No ]] || return 1
  uid=$(id -u)
  remaining=$root
  while [[ $remaining =~ \{([^{}]*)\} ]]; do
    session=${BASH_REMATCH[1]}; matched=${BASH_REMATCH[0]}
    remaining=${remaining#*"$matched"}
    if [[ $session =~ \"kCGSSessionUserIDKey\"[[:space:]]*=[[:space:]]*([0-9]+) && ${BASH_REMATCH[1]} == "$uid" &&
          $session =~ \"kCGSSessionOnConsoleKey\"[[:space:]]*=[[:space:]]*Yes ]]; then return 0; fi
  done
  return 1
}
epoch_ms() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000'; }
auto_gui_activity() {
  [[ -n ${ROUTINE_GUI_ACTIVITY_FILE:-} ]] || return 0
  epoch_ms > "$ROUTINE_GUI_ACTIVITY_FILE"
}
auto_input_guard() {
  [[ -n ${ROUTINE_GUI_ACTIVITY_FILE:-} ]] || return 0
  local idle last elapsed
  console_unlocked || { failure_reason='사용자 입력/잠금 감지'; echo '화면이 잠겼거나 현재 사용자의 콘솔 세션이 아닙니다.' >&2; return 4; }
  idle=$(hid_idle_ns) || { failure_reason='사용자 입력/잠금 감지'; echo '사용자 입력 상태를 확인하지 못했습니다.' >&2; return 4; }
  last=$(cat "$ROUTINE_GUI_ACTIVITY_FILE")
  elapsed=$(($(epoch_ms) - last))
  # Our own input may reset HID idle. Millisecond timing limits the sampling
  # tolerance to 100ms; input during an action itself cannot be distinguished.
  if ((elapsed < 0 || idle < (elapsed - 100) * 1000000)); then
    failure_reason='사용자 입력/잠금 감지'
    : > "$ROUTINE_GUI_ACTIVITY_FILE.input"
    echo '자체 GUI 조작 이후 사용자 입력이 감지되어 다음 조작 전에 중단합니다.' >&2
    return 4
  fi
  # A signal can arrive while open/Orca is running, before activity is recorded.
  : > "$ROUTINE_GUI_ACTIVITY_FILE.started"
}
# Activation can lag; poll the frontmost app for up to ~1.5s. Prints the last observed bundle id.
await_not_slack() {
  local front _
  for _ in 1 2 3 4 5 6; do
    sleep 0.25
    front=$(osascript -l JavaScript "$ROUTINE_FOCUS_HELPER" capture) || return 1
    [[ $front == com.tinyspeck.slackmacgap ]] || break
  done
  printf '%s\n' "$front"
}
prompt_terminal_app() {
  command jq -e --arg bundle "$1" 'index($bundle)!=null' <<< "$(routine_get ui.terminal_bundle_ids)" >/dev/null
}
# Init must not ask for terminal input while its read-only Slack navigation
# still owns focus. Match the captured app, not merely "anything but Slack".
ensure_prompt_focus() {
  local original=$1 front attempt answer
  front=$(osascript -l JavaScript "$ROUTINE_FOCUS_HELPER" capture) || front=''
  [[ $front != "$original" ]] || return 0
  osascript -l JavaScript "$ROUTINE_FOCUS_HELPER" restore "$original" >/dev/null 2>&1 || true
  for attempt in 1 2 3 4 5 6; do
    front=$(osascript -l JavaScript "$ROUTINE_FOCUS_HELPER" capture) || front=''
    [[ $front != "$original" ]] || return 0
    sleep 0.25
  done
  if declare -F ui_output >/dev/null; then
    ui_output '터미널을 클릭한 뒤 Enter를 눌러 계속하세요 (Slack에는 입력하지 마세요).'
  else
    printf '터미널을 클릭한 뒤 Enter를 눌러 계속하세요 (Slack에는 입력하지 마세요).\n'
  fi
  while :; do
    front=$(osascript -l JavaScript "$ROUTINE_FOCUS_HELPER" capture) || front=''
    if [[ $front == "$original" ]]; then
      IFS= read -r answer < /dev/tty
      front=$(osascript -l JavaScript "$ROUTINE_FOCUS_HELPER" capture) || front=''
      [[ $front != "$original" ]] || break
    fi
    sleep 0.25
  done
}
# A delayed deep-link activation must settle before the first input prompt.
stabilize_prompt_focus() {
  local attempt
  for attempt in 1 2 3 4 5 6; do ensure_prompt_focus "$1"; sleep 0.25; done
  ensure_prompt_focus "$1"
}
restore_previous_app() {
  [[ -n ${ROUTINE_GUI_ACTIVITY_FILE:-} && -f $ROUTINE_GUI_ACTIVITY_FILE.started &&
     -n ${ROUTINE_ORIGINAL_APP:-} && -n ${ROUTINE_FOCUS_HELPER:-} ]] || return 0
  local front
  [[ ! -e $ROUTINE_GUI_ACTIVITY_FILE.input ]] || return 4
  auto_input_guard || return $?
  front=$(osascript -l JavaScript "$ROUTINE_FOCUS_HELPER" capture) || return 1
  [[ $front == com.tinyspeck.slackmacgap ]] || return 0
  osascript -l JavaScript "$ROUTINE_FOCUS_HELPER" restore "$ROUTINE_ORIGINAL_APP" || true
  auto_gui_activity || return 1
  front=$(await_not_slack) || return 1
  if [[ $front == com.tinyspeck.slackmacgap ]] && [[ -n $(lsappinfo find "bundleid=$ROUTINE_ORIGINAL_APP" 2>/dev/null) ]]; then
    # A cooperative activation request can be ignored on recent macOS. Use the
    # LaunchServices fallback only for a running app (open -b would relaunch it).
    auto_input_guard || return $?
    open -b "$ROUTINE_ORIGINAL_APP" || true
    auto_gui_activity || return 1
    front=$(await_not_slack) || return 1
  fi
  if [[ $front == com.tinyspeck.slackmacgap ]]; then
    printf 'Slack이 전면에 남음 — 키 입력 주의\n' > "$ROUTINE_GUI_ACTIVITY_FILE.focus-warning"
    return 1
  fi
  rm -f -- "$ROUTINE_GUI_ACTIVITY_FILE.focus-warning"
}
