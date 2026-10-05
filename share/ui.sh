#!/usr/bin/env bash
# Input/result functions write only their result to stdout. Prompts and gum's
# screen use the controlling terminal, including setup's FIFO/tee config path.
# Capture stdin's TTY status before callers enter JSON/process-substitution
# loops; prompts inside those loops still belong to the same terminal.
ui_tty=0
if [[ -t 0 && -r /dev/tty && -w /dev/tty ]]; then ui_tty=1; fi
ui_interactive() {
  [[ ${non_interactive:-0} == 0 && $ui_tty == 1 && -r /dev/tty && -w /dev/tty ]]
}
ui_gum_available() {
  ui_interactive && type -P gum >/dev/null
}
ui_color_enabled() {
  ui_gum_available && [[ ! ${NO_COLOR+x} ]]
}
# Palette: text (questions, titles, labels, values) stays in the terminal's own foreground, bold where it
# matters, so it reads on light and dark themes. Color marks only symbols: accent (blue) for interactive
# markers, green/yellow/red for state, gray for hints. "strong" = bold default foreground.
ui_color() {
  local role=$1 text=$2 color bright target_tty=${3:-1} bold=${4:-0}
  if (( !target_tty )) || ! ui_color_enabled; then printf '%s' "$text"; return; fi
  case $role in
    strong) printf '\033[1m%s\033[0m' "$text"; return ;;
    accent) color='38;5;75'; bright=75 ;; success) color=32; bright=114 ;;
    warning) color=33; bright=221 ;; error) color=31; bright=203 ;; hint) color='38;5;245'; bright=245 ;;
    *) printf '%s' "$text"; return ;;
  esac
  (( !bold )) || color="1;38;5;$bright"
  printf '\033[%sm%s\033[0m' "$color" "$text"
}
# Keep all gum controls on one palette, without overriding NO_COLOR.
# Selected: 231 on 25 (#005faf), WCAG contrast 6.45:1. Unselected: 252 on 237, 7.37:1.
ui_gum() (
  local accent=75 hint=245 item=252 white=231 selected_bg=25 unselected_bg=237 bold=true
  if ! ui_color_enabled; then
    accent='' hint='' item='' white='' selected_bg='' unselected_bg='' bold=false
  fi
  # Headers/prompts use the default foreground (bold); only the input marker and cursor are accent.
  export GUM_INPUT_HEADER_FOREGROUND='' GUM_INPUT_PROMPT_FOREGROUND="$accent" GUM_INPUT_PROMPT='› '
  export GUM_INPUT_HEADER_BOLD="$bold"
  export GUM_INPUT_CURSOR_FOREGROUND="$accent" GUM_INPUT_PLACEHOLDER_FOREGROUND="$hint"
  export GUM_CHOOSE_HEADER_FOREGROUND='' GUM_CHOOSE_HEADER_BOLD="$bold"
  # gum's cursor/selected styles include the item text. Style the prefixes
  # separately so only the cursor/checkmark changes color, never the whole row.
  export GUM_CHOOSE_CURSOR_FOREGROUND='' GUM_CHOOSE_SELECTED_FOREGROUND=''
  export GUM_CHOOSE_ITEM_FOREGROUND=''
  GUM_CHOOSE_CURSOR=$(ui_color accent '› ' 1 1)
  GUM_CHOOSE_CURSOR_PREFIX=$(ui_color hint '○ ')
  GUM_CHOOSE_SELECTED_PREFIX=$(ui_color success '● ')
  GUM_CHOOSE_UNSELECTED_PREFIX=$GUM_CHOOSE_CURSOR_PREFIX
  export GUM_CHOOSE_CURSOR GUM_CHOOSE_CURSOR_PREFIX GUM_CHOOSE_SELECTED_PREFIX GUM_CHOOSE_UNSELECTED_PREFIX
  export GUM_CONFIRM_PROMPT_FOREGROUND='' GUM_CONFIRM_PROMPT_BOLD="$bold"
  export GUM_CONFIRM_SELECTED_BACKGROUND="$selected_bg" GUM_CONFIRM_SELECTED_FOREGROUND="$white"
  export GUM_CONFIRM_SELECTED_BOLD="$bold"
  export GUM_CONFIRM_UNSELECTED_BACKGROUND="$unselected_bg" GUM_CONFIRM_UNSELECTED_FOREGROUND="$item"
  export GUM_CONFIRM_UNSELECTED_BOLD=false
  export GUM_SPIN_SPINNER_FOREGROUND="$accent" GUM_SPIN_TITLE_FOREGROUND='' GUM_SPIN_TITLE_BOLD="$bold"
  if ui_color_enabled; then env CLICOLOR_FORCE=1 gum "$@"
  else env NO_COLOR=1 CLICOLOR_FORCE=0 FORCE_COLOR=0 gum "$@"; fi
)
# Fit plain text to terminal cells without jq, so setup's dependency bootstrap
# can use the same columns before jq is installed.
ui_fit_text() {
  local text=$1 limit=$2 LC_ALL=en_US.UTF-8 index char code byte offset count cells column=0 result=''
  for ((index=0; index<${#text}; index++)); do
    char=${text:index:1}
    LC_ALL=C
    printf -v code '%d' "'${char:0:1}"; code=$((code&255)); count=1
    if ((code>=240)); then code=$((code&7)); count=4
    elif ((code>=224)); then code=$((code&15)); count=3
    elif ((code>=192)); then code=$((code&31)); count=2; fi
    for ((offset=1; offset<count; offset++)); do
      printf -v byte '%d' "'${char:offset:1}"
      code=$(((code<<6)|(byte&63)))
    done
    LC_ALL=en_US.UTF-8
    if (( (code>=4448 && code<=4607) || (code>=768 && code<=879) ||
          (code>=65024 && code<=65039) || (code>=8203 && code<=8207) )); then cells=0
    elif (( (code>=4352 && code<=4447) || (code>=11904 && code<=42191) ||
            (code>=44032 && code<=55203) || (code>=65281 && code<=65376) ||
            (code>=127744 && code<=129791) || (code>=9728 && code<=10175) )); then cells=2
    else cells=1; fi
    ((column+cells<=limit)) || break
    result+="$char"; column=$((column+cells))
  done
  printf '%s%*s' "$result" "$((limit-column))" ''
}
# Keep persistent init output within the terminal width ourselves. Counting the
# emitted lines (rather than terminal auto-wrap estimates) bounds later erasure.
ui_terminal_size() {
  local size
  ui_rows=30 ui_columns=80
  [[ -r /dev/tty && -w /dev/tty ]] || return 0
  size=$(stty size < /dev/tty 2>/dev/null) || size=''
  if [[ $size =~ ^([1-9][0-9]*)[[:space:]]+([1-9][0-9]*)$ ]]; then
    ui_rows=${BASH_REMATCH[1]} ui_columns=${BASH_REMATCH[2]}
  fi
}
ui_output() {
  local message=$1 rendered rows=0 previous=0
  if ! ui_interactive; then printf '%s\n' "$message"; return; fi
  ui_terminal_size
  # SGR has zero width. Hangul medial/final jamo and combining marks also
  # occupy zero cells, including macOS's NFD filenames.
  rendered=$(command jq -nr --arg text "$message" --argjson width "$((ui_columns>1 ? ui_columns-1 : 1))" '
    def cells:
      if (.>=4448 and .<=4607) or (.>=768 and .<=879) or
         (.>=65024 and .<=65039) or (.>=8203 and .<=8207) then 0
      elif (.>=4352 and .<=4447) or (.>=11904 and .<=42191) or
           (.>=44032 and .<=55203) or (.>=65281 and .<=65376) or
           (.>=127744 and .<=129791) or (.>=9728 and .<=10175) then 2 else 1 end;
    $text|split("\n")|map(
      [scan("\u001b\\[[0-9;]*m|[^\u001b]";"s")]|
      reduce .[] as $part ({line:"",lines:[],column:0};
        ($part|if startswith("\u001b") then 0 else explode[0]|cells end) as $cells |
        if .column+$cells>$width and .column>0 then
          .lines+=[.line]|.line=""|.column=0 else . end |
        .line+=$part|.column+=$cells)|.lines+[.line])|add|join("\n")')
  printf '%s\n' "$rendered" > /dev/tty
  if [[ -n ${ui_stage_counter:-} ]]; then
    rows=$(command jq -nr --arg text "$rendered" '$text|split("\n")|length')
    IFS= read -r previous < "$ui_stage_counter" || previous=0
    printf '%s\n' "$((previous+rows))" > "$ui_stage_counter"
  fi
}
ui_clear_stage() {
  local lines=0 line
  if ui_gum_available && [[ -n ${ui_stage_counter:-} ]]; then
    IFS= read -r lines < "$ui_stage_counter" || lines=0
    ui_terminal_size
    # Only the visible owned span can be erased; scrolled-off output is never
    # a reason to move above the terminal viewport or into an earlier stage.
    ((lines<ui_rows)) || lines=$((ui_rows-1))
    if ((lines>0)); then
      printf '\033[%sA' "$lines" > /dev/tty
      for ((line=0; line<lines; line++)); do printf '\r\033[2K\n' > /dev/tty; done
      printf '\033[%sA' "$lines" > /dev/tty
    fi
    printf '0\n' > "$ui_stage_counter"
  fi
}
ui_stage() {
  local number=$1 total=$2 name=$3 header width divider
  ui_clear_stage
  if [[ -n $number ]]; then header="설정 $number/$total"
  else header="고치기"; fi
  ui_terminal_size
  width=$((ui_columns-2)); ((width<=48)) || width=48; ((width>0)) || width=1
  printf -v divider '%*s' "$width" ''
  divider=${divider// /─}
  ui_output "
$(ui_color hint "$header · ")$(ui_color strong "$name")
$(ui_color hint "$divider")"
}
# Run the command once. Capture its stdout outside gum's PTY so bytes and a
# failing command's output survive unchanged; never retry after a gum failure.
ui_spin() {
  local title=$1 output rc=0
  shift
  if ! ui_gum_available; then ui_output "$title" >&2; "$@"; return; fi
  output=$(mktemp "${TMPDIR:-/tmp}/routine-spin.XXXXXXXX") || return
  ui_focus
  # shellcheck disable=SC2016 # The command and output path are child positional arguments.
  ui_gum spin --title "$title" -- /bin/bash -c 'output=$1; shift; "$@" > "$output"' _ "$output" "$@" < /dev/tty > /dev/tty 2> /dev/tty || rc=$?
  ui_focus
  cat "$output"; rm -f "$output"
  ui_abort_on_interrupt "$rc"
  return "$rc"
}
# label, [{value,label}]. gum Esc/unknown output and text EOF cancel;
# text input mistakes are retried, never interpreted as a new default or cancel.
ui_choose_one() {
  local label=$1 items=$2 answer rc=0 index=0 value display
  local options=()
  ui_interactive || return 2
  while IFS= read -r -d '' display; do options+=("$display"); done < <(command jq -j '.[]|.label+"\u0000"' <<< "$items")
  ui_focus
  if ui_gum_available; then
    answer=$(ui_gum choose --header "$label" -- "${options[@]}" < /dev/tty 2> /dev/tty) || rc=$?
    ui_focus
    ui_abort_on_interrupt "$rc"
    ((rc==0)) || return 2
    value=$(command jq -r --arg answer "$answer" '.[]|select(.label==$answer)|.value' <<< "$items")
    [[ -n $value ]] || return 2
    printf '%s\n' "$value"; return 0
  fi
  for display in "${options[@]}"; do index=$((index+1)); printf '  %s) %s\n' "$index" "$display" > /dev/tty; done
  while :; do
    printf '%s (번호): ' "$label" > /dev/tty
    IFS= read -r answer < /dev/tty || return 2
    if [[ $answer =~ ^[1-9][0-9]*$ ]] && ((answer<=index)); then
      command jq -r --argjson index "$((answer-1))" '.[$index].value' <<< "$items"
      return 0
    fi
    ui_output '목록의 번호를 입력하세요. 취소하려면 취소 항목의 번호를 고르세요.'
  done
}
ui_focus() {
  [[ -z ${prompt_app:-} ]] || ensure_prompt_focus "$prompt_app" > /dev/tty
}
ui_cancelled() {
  ui_output '대화형 화면이 취소되었거나 종료되었습니다. 기존 값은 유지합니다.'
}
# gum handles Ctrl-C in raw mode and exits 130. Treat it like Ctrl-C in the text prompts:
# stop the whole setup/init (the caller of a $(…) wrapper is signalled too), never continue.
ui_abort_on_interrupt() {
  (($1 == 130)) || return 0
  printf '\n중단했습니다 (Ctrl-C). 변경 사항은 저장하지 않았습니다.\n' > /dev/tty
  kill -INT "$$" 2>/dev/null || true
  exit 130
}
# label, hint, default; exit 2 means gum failed/cancelled, not a new answer.
ui_input() {
  local label=$1 hint=${2:-} current=${3:-} answer rc=0
  if ! ui_interactive; then printf '%s\n' "$current"; return 0; fi
  ui_focus
  if ui_gum_available; then
    # Show the existing value as the placeholder instead of pre-filling it: a pasted link must not be
    # appended to a display value, and an empty answer keeps the existing value (as in text mode).
    local placeholder=$hint
    [[ -z $current ]] || placeholder="$current (Enter로 유지)"
    answer=$(ui_gum input --header "$label" --placeholder="$placeholder" --char-limit 0 < /dev/tty 2> /dev/tty) || rc=$?
    ui_focus
    ui_abort_on_interrupt "$rc"
    if ((rc)); then ui_cancelled; printf '%s\n' "$current"; return 2; fi
  else
    printf '%s\n   %s\n   [%s]: ' "$label" "$hint" "$current" > /dev/tty
    IFS= read -r answer < /dev/tty || answer=''
  fi
  printf '%s\n' "${answer:-$current}"
}
# label, default (true/false); exit 0=yes, 1=no, 2=gum failed/cancelled.
ui_confirm() {
  local label=$1 default=${2:-true} answer rc=0
  ui_interactive || return 1
  ui_focus
  if ui_gum_available; then
    ui_gum confirm --default="$default" --affirmative '예' --negative '아니요' "$label" < /dev/tty > /dev/tty 2> /dev/tty || rc=$?
    ui_focus
    ui_abort_on_interrupt "$rc"
    if ((rc>1)); then ui_cancelled; return 2; fi
    return "$rc"
  fi
  if [[ $default == true ]]; then
    printf '%s [Y/n] ' "$label" > /dev/tty
    IFS= read -r answer < /dev/tty || return 1
    [[ $answer != [nN] ]]
  else
    printf '%s [y/N] ' "$label" > /dev/tty
    IFS= read -r answer < /dev/tty || return 1
    [[ $answer == [yY] ]]
  fi
}
# label, [{value,label,reason?}], selected values (JSON array).
# Callers validate reasons before applying values so Git can offer root repair.
ui_choose_many() {
  local label=$1 items=$2 selected=$3 value display answer result index number=0 rc=0
  local options=() preselected=() args=()
  if ! ui_interactive; then printf '%s\n' "$selected"; return 0; fi
  items=$(command jq -c --arg warning "$(ui_color warning '⚠')" '
    map(.label+=(if (.reason // "")=="" then "" else " — "+$warning+" 필요 조건: "+.reason end))' <<< "$items")
  while IFS= read -r -d '' value && IFS= read -r -d '' display; do
    options+=("$display")
    if command jq -e --arg value "$value" 'index($value)!=null' <<< "$selected" >/dev/null; then preselected+=("$display"); fi
  done < <(command jq -j '.[]|.value+"\u0000"+.label+"\u0000"' <<< "$items")
  ui_focus
  if ui_gum_available; then
    # Kong accepts repeated slice flags and backslash-escaped commas.
    for display in ${preselected[@]+"${preselected[@]}"}; do
      display=${display//,/\\,}
      args+=(--selected "$display")
    done
    answer=$(ui_gum choose --no-limit --header "$label" ${args[@]+"${args[@]}"} -- "${options[@]}" < /dev/tty 2> /dev/tty) || rc=$?
    ui_focus
    ui_abort_on_interrupt "$rc"
    # gum choose: Enter (even with nothing selected) exits 0; Esc exits 1. Only 0 is an answer.
    if ((rc!=0)); then ui_cancelled; printf '%s\n' "$selected"; return 2; fi
    result=$(command jq -cn --arg output "$answer" --argjson items "$items" '
      ($output|split("\n")|map(select(length>0))) as $labels |
      [$items[]|.label as $label|select($labels|index($label)!=null)|.value]')
    # Unexpected output is not an intentional empty selection.
    if [[ -n $answer ]] && ! command jq -en --arg output "$answer" --argjson items "$items" '
      [$items[].label] as $labels |
      all($output|split("\n")[]|select(length>0); . as $line|$labels|index($line)!=null)' >/dev/null; then
      ui_cancelled; printf '%s\n' "$selected"; return 2
    fi
    printf '%s\n' "$result"
    return 0
  fi
  while :; do
    number=0
    while IFS= read -r -d '' value && IFS= read -r -d '' display; do
      number=$((number+1)); answer='[ ]'
      command jq -e --arg value "$value" 'index($value)!=null' <<< "$selected" >/dev/null && answer='[선택]'
      printf '  %s) %s %s\n' "$number" "$answer" "$display" > /dev/tty
    done < <(command jq -j '.[]|.value+"\u0000"+.label+"\u0000"' <<< "$items")
    printf '%s (번호로 선택/해제, Enter로 확정): ' "$label" > /dev/tty
    IFS= read -r answer < /dev/tty || break
    [[ -n $answer ]] || break
    for index in $answer; do
      if [[ ! $index =~ ^[1-9][0-9]*$ ]] || ((index>number)); then printf '목록의 번호를 입력하세요: %s\n' "$index" > /dev/tty; continue; fi
      value=$(command jq -r --argjson index "$((index-1))" '.[$index].value' <<< "$items")
      selected=$(command jq -c --arg value "$value" 'if index($value)!=null then map(select(.!=$value)) else .+[$value] end' <<< "$selected")
    done
  done
  printf '%s\n' "$selected"
}
ui_note() {
  local title=$1 message=$2 kind=${3:-info} icon='💡' icon_role=warning rc=0 output border=240
  case $kind in
    warning) icon='⚠️'; border=221 ;;
    error) icon='⛔'; icon_role=error; border=203 ;;
    success) icon='✅'; icon_role=success; border=114 ;;
    complete) icon='✓'; icon_role=success; border=114 ;;
    summary) icon='📋'; icon_role=hint ;;
    permission) icon='🔐'; border=221 ;;
  esac
  title="$(ui_color "$icon_role" "$icon") $(ui_color strong "$title")"
  ui_terminal_size
  if ui_gum_available && ((ui_columns>=72)) && { [[ $kind != error && $kind != complete ]] || [[ ! ${NO_COLOR+x} ]]; }; then
    if ! ui_color_enabled; then border=''; fi
    ui_focus
    output=$(ui_gum style --border rounded --border-foreground "$border" --foreground '' --padding '1 2' --width "$((ui_columns-8))" -- "$title" "$message" < /dev/tty 2> /dev/tty) || rc=$?
    ui_focus
    if ((rc==0)); then ui_output "$output"; return 0; fi
    ui_abort_on_interrupt "$rc"
  fi
  ui_output "$title
$message"
}
