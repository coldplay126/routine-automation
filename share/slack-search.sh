#!/usr/bin/env bash
# Both callers supply private work/share_dir directories and source orca.sh/gui-guard.sh.
# shellcheck disable=SC2154,SC2034 # Caller supplies work/share_dir and consumes slack_search_error.
poll_slack_target() {
  local filter=$1 attempt value
  shift
  for attempt in 1 2 3 4 5; do
    if "$orca" computer get-app-state --app com.tinyspeck.slackmacgap --no-screenshot --json > "$work/slack.state" &&
       value=$(jq -L "$share_dir" -er "$@" "$filter" "$work/slack.state" 2> "$work/slack-poll.error"); then
      printf '%s\n' "$value"
      return 0
    fi
    ((attempt == 5)) || sleep 1
  done
  [[ ! -f $work/slack-poll.error ]] || cat "$work/slack-poll.error" >&2
  return 1
}

slack_search_read() {
  local query=$1 output=$2 search_index combo_index suggestion focused
  slack_search_error='Slack search failed'
  orca=$(find_orca) || { slack_search_error='Orca is unavailable'; return 1; }
  ensure_orca_runtime "$orca" || { slack_search_error='Orca runtime did not start'; return 1; }
  auto_input_guard || return $?
  open -a Slack || return 1
  auto_gui_activity || return 1
  search_index=$(poll_slack_target 'include "slack"; tree_text | global_search_button') || { slack_format_notice '검색/검색 버튼' "$work/slack.state"; return 1; }
  auto_input_guard || return $?
  search_started=1
  "$orca" computer click --app com.tinyspeck.slackmacgap --element-index "$search_index" --no-screenshot --json >/dev/null ||
    { slack_format_notice '검색/검색 버튼 클릭' "$work/slack.state"; return 1; }
  auto_gui_activity || return 1
  combo_index=$(poll_slack_target 'include "slack"; tree_text | ax_index("^콤보 상자([ ,]|$)")') || { slack_format_notice '검색/콤보 상자' "$work/slack.state"; return 1; }
  auto_input_guard || return $?
  "$orca" computer set-value --app com.tinyspeck.slackmacgap --element-index "$combo_index" --value "$query" --no-screenshot --json >/dev/null ||
    { slack_format_notice '검색/검색어 입력' "$work/slack.state"; return 1; }
  auto_gui_activity || return 1
  # shellcheck disable=SC2016 # jq filter; $query is a jq variable
  if suggestion=$(poll_slack_target 'include "slack"; tree_text | ax_lines | [.[] | select(.body == ("메뉴 항목, Value: " + $query + " 검색")) | .index] | select(length==1) | .[0]' --arg query "$query"); then :
  else
    suggestion=$(jq -L "$share_dir" -r --arg query "$query" 'include "slack"; tree_text | ax_lines | [.[] | select(.body == ("메뉴 항목, Value: " + $query + " 검색")) | .index] | if length == 1 then .[0] elif length == 0 then empty else error("Ambiguous search suggestion") end' "$work/slack.state") || { slack_format_notice '검색/제안 메뉴' "$work/slack.state"; return 1; }
  fi
  if [[ -n $suggestion ]]; then
    auto_input_guard || return $?
    "$orca" computer click --app com.tinyspeck.slackmacgap --element-index "$suggestion" --no-screenshot --json >/dev/null ||
      { slack_format_notice '검색/제안 실행' "$work/slack.state"; return 1; }
    auto_gui_activity || return 1
  else
    # Return is confined to the freshly observed, focused search combo box.
    combo_index=$(jq -L "$share_dir" -er 'include "slack"; tree_text | ax_index("^콤보 상자([ ,]|$)")' "$work/slack.state") || { slack_format_notice '검색/확정 콤보 상자' "$work/slack.state"; return 1; }
    focused=$(jq -r '.result.snapshot.focusedElementId // .snapshot.focusedElementId // empty' "$work/slack.state") || return 1
    [[ $focused == "$combo_index" ]] || { slack_search_error='Slack search focus could not be verified'; return 1; }
    auto_input_guard || return $?
    "$orca" computer press-key --app com.tinyspeck.slackmacgap --key Return --no-screenshot --json >/dev/null ||
      { slack_format_notice '검색/검색 확정' "$work/slack.state"; return 1; }
    auto_gui_activity || return 1
  fi
  sleep 4
  auto_input_guard || return $?
  "$orca" computer get-app-state --app com.tinyspeck.slackmacgap --no-screenshot --json > "$work/slack.state" || return 1
  jq -L "$share_dir" 'include "slack"; tree_text | search_report' "$work/slack.state" > "$output" || { slack_format_notice '검색/결과 목록' "$work/slack.state"; return 1; }
}

# Clear the search term and close only the channel-search panel, never an
# unrelated dialog's close button. Preserve slack.state for failure diagnostics.
slack_search_reset() {
  local target
  "$orca" computer get-app-state --app com.tinyspeck.slackmacgap --no-screenshot --json > "$work/slack-reset.state" || return 1
  target=$(jq -L "$share_dir" -r 'include "slack"; tree_text|ax_lines|[.[]|select(.body=="버튼 검색 지우기")|.index]|
    if length==1 then .[0] elif length==0 then empty else error("Ambiguous search clear button") end' "$work/slack-reset.state") ||
    { slack_format_notice '검색/검색어 지우기' "$work/slack-reset.state"; return 1; }
  if [[ -n $target ]]; then
    auto_input_guard || return $?
    "$orca" computer click --app com.tinyspeck.slackmacgap --element-index "$target" --no-screenshot --json >/dev/null || return 1
    auto_gui_activity || return 1
  fi
  "$orca" computer get-app-state --app com.tinyspeck.slackmacgap --no-screenshot --json > "$work/slack-reset.state" || return 1
  target=$(jq -L "$share_dir" -r 'include "slack"; tree_text|ax_lines as $lines|
    [range(0;$lines|length)|select($lines[.].body=="container 채널 내에서 검색")] as $starts|
    if ($starts|length)==0 then empty elif ($starts|length)!=1 then error("Ambiguous channel search panel")
    else $starts[0] as $s|
      ([$lines[$s+1:]|to_entries[]|select(.value.indent<=$lines[$s].indent)|.key+$s+1][0] // ($lines|length)) as $end|
      [$lines[$s+1:$end][]|select(.body=="버튼 닫기")|.index]|
      if length==1 then .[0] else error("Missing channel search close button") end end' "$work/slack-reset.state") ||
    { slack_format_notice '검색/패널 닫기' "$work/slack-reset.state"; return 1; }
  if [[ -n $target ]]; then
    auto_input_guard || return $?
    "$orca" computer click --app com.tinyspeck.slackmacgap --element-index "$target" --no-screenshot --json >/dev/null || return 1
    auto_gui_activity || return 1
  fi
  auto_input_guard || return $?
  open "slack://channel?team=$(routine_get slack.team_id)&id=$(routine_get slack.channel_id)" || return 1
  auto_gui_activity || return 1
  sleep 3
}

# Keep collection/paste navigation and foreground restoration on one path.
# Input interruption is never followed by cleanup GUI mutations. Paste passes
# false because its existing EXIT cleanup owns restoration after all GUI work.
slack_search() {
  local orca='' status=0 reset_status=0 restore_status=0 search_started=0 restore=${3:-true}
  if slack_search_read "$1" "$2"; then :; else status=$?; fi
  ((status != 4)) || return 4
  if ((search_started)); then
    if slack_search_reset; then :; else reset_status=$?; fi
    ((reset_status != 4)) || return 4
    if ((status == 0 && reset_status != 0)); then
      slack_search_error='Slack search cleanup failed'
      status=$reset_status
    fi
  fi
  [[ $restore == true ]] || return "$status"
  # Restore immediately before collection's model call.
  if restore_previous_app; then :
  else
    restore_status=$?
    if [[ $restore_status != 4 && -n ${ROUTINE_GUI_ACTIVITY_FILE:-} ]]; then
      printf 'Slack 검색 후 전면 복원 확인 실패\n' > "$ROUTINE_GUI_ACTIVITY_FILE.focus-warning"
    fi
    return "$restore_status"
  fi
  return "$status"
}
