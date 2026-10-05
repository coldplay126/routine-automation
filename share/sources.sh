#!/usr/bin/env bash
# shellcheck disable=SC2154 # share_dir and ROUTINE_SETTINGS are supplied by entrypoints.
# Timeout children (bash -c 'source sources.sh') only need the scan functions, not the UI.
# shellcheck source=ui.sh
if [[ -n ${share_dir:-} ]]; then source "$share_dir/ui.sh"; fi
# Print .git markers at repository depth 0..2; never recurse through git metadata.
routine_git_markers() {
  local root=$1 limit
  [[ -d $root ]] || { printf '%s: Repository root does not exist\n' "$root" >&2; return 1; }
  limit=$(command -v gtimeout || command -v timeout || true)
  if [[ -n $limit ]]; then
    "$limit" -k 5 20 ls -A "$root" >/dev/null 2>&1 || { printf '%s: Cannot list repository root (check Documents access for /bin/bash)\n' "$root" >&2; return 1; }
    "$limit" -k 5 20 find "$root" -maxdepth 3 -name .git \( -type d -o -type f \) -print0 -prune
  else
    ls -A "$root" >/dev/null 2>&1 || { printf '%s: Cannot list repository root (check Documents access for /bin/bash)\n' "$root" >&2; return 1; }
    find "$root" -maxdepth 3 -name .git \( -type d -o -type f \) -print0 -prune
  fi
}
routine_git_root_count() {
  local marker common seen='[]'
  while IFS= read -r -d '' marker; do
    common=$(git -C "${marker%/.git}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
    seen=$(command jq -c --arg common "$common" '.+[$common]|unique' <<< "$seen")
  done < <(routine_git_markers "$1" 2>/dev/null)
  command jq -r length <<< "$seen"
}
# Automatic session discovery stays inside HOME. Explicit roots may live on
# external volumes, but never scan HOME, its ancestors or disposable data.
routine_git_root_path() {
  local path=$1 mode=${2:-explicit} home base suffix=''
  [[ $path == /* ]] || { echo '절대 경로의 폴더가 필요합니다.' >&2; return 1; }
  home=$(cd -P "$HOME" && pwd -P) || return 1
  if [[ -d $path ]]; then path=$(cd -P "$path" && pwd -P) || return 1
  elif [[ $mode == saved && ! -e $path && ! -L $path ]]; then
    path=$(command jq -nr --arg path "$path" '$path|split("/")|reduce .[] as $part ([]; if $part==".." then .[:-1] elif $part=="" or $part=="." then . else .+[$part] end)|"/"+join("/")') || return 1
    base=$path
    while [[ ! -d $base ]]; do suffix="/${base##*/}$suffix"; base=${base%/*}; [[ -n $base ]] || base=/; done
    base=$(cd -P "$base" && pwd -P) || return 1
    path="${base%/}$suffix"; [[ -n $path ]] || path=/
  else echo '존재하는 폴더가 필요합니다.' >&2; return 1; fi
  if [[ $path == / || $path == "$home" || $home == "$path/"* ]]; then
    echo '홈 자체·홈의 상위 경로·전체 파일시스템은 사용할 수 없습니다.' >&2; return 1
  fi
  case $path in
    "$home/.omp/wt"|"$home/.omp/wt/"*|"$home/.cache"|"$home/.cache/"*|"$home/Library"|"$home/Library/"*) echo '캐시·Library·임시 worktree는 사용할 수 없습니다.' >&2; return 1 ;;
  esac
  if [[ $mode == auto && $path != "$home/"* ]]; then return 1; fi
  printf '%s\n' "$path"
}
routine_normalize_git_roots() {
  local roots=$1 root normalized result='[]'
  command jq -e 'type=="array" and all(.[];type=="string")' <<< "$roots" >/dev/null || { echo 'Git 위치는 문자열 배열이어야 합니다.' >&2; return 1; }
  while IFS= read -r -d '' root; do
    normalized=$(routine_git_root_path "$root") || return 1
    result=$(command jq -c --arg root "$normalized" '.+[$root]|unique' <<< "$result")
  done < <(command jq -j '.[]|.+"\u0000"' <<< "$roots")
  printf '%s\n' "$result"
}
# Executed in a timeout-bounded child. OMP reads only its session header;
# Claude stops at its first top-level cwd within 64KB / 50 records.
routine_git_session_roots() {
  local omp=$1 claude=$2 files file engine cwd top root cwds roots='[]'
  files=$(
    {
      [[ ! -d $omp || $omp == "$HOME" || $omp == / ]] || find "$omp" -type f -name '*.jsonl' -exec stat -f $'omp\t%m\t%N' {} + 2>/dev/null
      [[ ! -d $claude || $claude == "$HOME" || $claude == / ]] || find "$claude" -type f -name '*.jsonl' -exec stat -f $'claude\t%m\t%N' {} + 2>/dev/null
    } | command jq -Rn '[inputs|try capture("^(?<engine>omp|claude)\\t(?<mtime>[0-9]+)\\t(?<path>.*)$") catch empty]|sort_by(.mtime|tonumber)|reverse|.[:300]'
  ) || return 1
  cwds=$(
    while IFS= read -r -d '' engine && IFS= read -r -d '' file; do
      if [[ $engine == omp ]]; then
        head -n 1 "$file" | command jq -cR 'fromjson? | select(.type=="session") | .cwd | select(type=="string" and startswith("/"))' 2>/dev/null || true
      else
        head -c 65536 "$file" | head -n 50 |
          command jq -nc --stream 'first(inputs | select(.[0]==["cwd"] and (.[1]|type=="string" and startswith("/"))) | .[1]) // empty' 2>/dev/null || true
      fi
    done < <(command jq -j '.[]|.engine+"\u0000"+.path+"\u0000"' <<< "$files") |
      command jq -cs 'map(select(type=="string"))|unique'
  ) || return 1
  cwds=$(
    while IFS= read -r -d '' cwd; do
      cwd=$(routine_git_root_path "$cwd" auto) || continue
      printf '%s\0' "$cwd"
    done < <(command jq -j '.[]|.+"\u0000"' <<< "$cwds") |
      command jq -Rs 'split("\u0000")|map(select(length>0))|unique'
  ) || return 1
  while IFS= read -r -d '' cwd; do
    top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || continue
    root=$(routine_git_root_path "${top%/*}" auto) || continue
    roots=$(command jq -c --arg root "$root" '.+[$root]|unique' <<< "$roots")
  done < <(command jq -j '.[]|.+"\u0000"' <<< "$cwds")
  printf '%s\n' "$roots"
}
routine_git_candidates() {
  local dir root normalized limit sessions='[]' candidates='[]'
  while IFS= read -r -d '' root; do
    if normalized=$(routine_git_root_path "$root" saved 2>&1); then root=$normalized
    else printf '저장된 Git 위치 제외: %s — %s\n' "$root" "$normalized" >&2; continue; fi
    candidates=$(command jq -c --arg root "$root" '.+[$root]' <<< "$candidates")
  done < <(command jq -j '.sources.git.roots[]|.+"\u0000"' <<< "$ROUTINE_SETTINGS")
  for dir in Documents/GitHub GitHub Developer dev src code projects workspace repos; do
    root=$(routine_git_root_path "$HOME/$dir" auto 2>/dev/null) || continue
    candidates=$(command jq -c --arg root "$root" '.+[$root]' <<< "$candidates")
  done
  limit=$(command -v gtimeout || command -v timeout || true)
  if [[ -n $limit ]]; then
    # shellcheck disable=SC2016 # Expand positional parameters in the child, not here.
    sessions=$(ui_spin '세션 기록에서 저장소 위치 찾는 중…' "$limit" -k 1 15 /bin/bash -c 'source "$1"; routine_git_session_roots "$2" "$3"' _ "$share_dir/sources.sh" "$(routine_get sources.omp_sessions.dir)" "$(routine_get sources.claude_sessions.dir)" 2>/dev/null) || sessions='[]'
  fi
  command jq -cn --argjson candidates "$candidates" --argjson sessions "$sessions" '$candidates+$sessions|unique'
}
# First discovery preselects every candidate that has repositories. --keep (final "항목 고치기")
# starts from the current selection instead, so partial or empty choices survive a re-edit.
routine_select_git_roots() {
  local candidates root count number answer selected='[]' index path mark counts='{}' items result confirm_rc keep=0
  [[ ${1:-} != --keep ]] || keep=1
  candidates=$(routine_git_candidates)
  ui_output 'Git 저장소 위치 (각 위치 자체와 하위 깊이 2까지만 확인)'
  while IFS= read -r -d '' root; do
    if [[ ! -d $root ]]; then
      count=-1
      ((keep)) || [[ $root != /Volumes/* ]] || selected=$(command jq -c --arg root "$root" '.+[$root]' <<< "$selected")
    else
      count=$(routine_git_root_count "$root")
      if ((!keep && count>0)); then selected=$(command jq -c --arg root "$root" '.+[$root]' <<< "$selected"); fi
    fi
    counts=$(command jq -c --arg root "$root" --argjson count "$count" '.[$root]=$count' <<< "$counts")
  done < <(command jq -j '.[]|.+"\u0000"' <<< "$candidates")
  if ((keep)); then selected=$(command jq -c '.sources.git.roots // []' <<< "$ROUTINE_SETTINGS"); fi
  if ui_gum_available; then
    while :; do
      items=$(command jq -cn --argjson candidates "$candidates" --argjson counts "$counts" '
        [$candidates[]|. as $root|($counts[$root] // 0) as $count|
          {value:$root,label:($root+" — "+(if $count<0 then (if startswith("/Volumes/") then "연결 안 됨" else "경로 없음" end) else "저장소 \($count)개" end))}] +
        [{value:"+",label:"+ 위치 직접 추가"}]')
      if ! result=$(ui_choose_many 'Git 저장소 위치 (Space로 선택, Enter로 확정)' "$items" "$selected"); then return 0; fi
      selected=$(command jq -c 'map(select(.!="+"))' <<< "$result")
      if command jq -e 'index("+")!=null' <<< "$result" >/dev/null; then
        if ! path=$(ui_input 'Git 위치 직접 추가' '저장소가 있는 폴더의 절대 경로'); then return 0; fi
        path=$(routine_git_root_path "$path") || { ui_note 'Git 위치 추가 불가' '특정 저장소 폴더를 추가하세요 (홈 자체·상위·캐시·임시 worktree 제외).' error; continue; }
        candidates=$(command jq -c --arg root "$path" '.+[$root]|unique' <<< "$candidates")
        selected=$(command jq -c --arg root "$path" '.+[$root]|unique' <<< "$selected")
        count=$(routine_git_root_count "$path")
        counts=$(command jq -c --arg root "$path" --argjson count "$count" '.[$root]=$count' <<< "$counts")
        continue
      fi
      if [[ $selected == '[]' ]]; then
        confirm_rc=0
        ui_confirm '선택된 위치가 없어 git 커밋을 수집하지 않습니다. 이대로 진행할까요?' false || confirm_rc=$?
        if ((confirm_rc==2)); then return 0; fi
        if ((confirm_rc==1)); then continue; fi
      fi
      ROUTINE_SETTINGS=$(command jq -c --argjson roots "$selected" '.sources.git.roots=$roots' <<< "$ROUTINE_SETTINGS")
      return 0
    done
  fi
  # Show each location with its current selection so a number visibly toggles it on/off.
  print_roots() {
    number=0
    while IFS= read -r -d '' root; do
      number=$((number+1)); mark='[ ]'
      command jq -e --arg root "$root" 'index($root)!=null' <<< "$selected" >/dev/null && mark='[선택]'
      count=$(command jq -r --arg root "$root" '.[$root] // 0' <<< "$counts")
      if ((count<0)); then
        if [[ $root == /Volumes/* ]]; then printf '  %s) %s %s — 연결 안 됨\n' "$number" "$mark" "$root"
        else printf '  %s) %s %s — 경로 없음\n' "$number" "$mark" "$root"; fi
      else printf '  %s) %s %s — 저장소 %s개\n' "$number" "$mark" "$root" "$count"; fi
    done < <(command jq -j '.[]|.+"\u0000"' <<< "$candidates")
    while IFS= read -r -d '' root; do
      command jq -e --arg root "$root" 'index($root)!=null' <<< "$candidates" >/dev/null || printf '     [선택] %s — 직접 추가\n' "$root"
    done < <(command jq -j '.[]|.+"\u0000"' <<< "$selected")
  }
  print_roots
  printf '번호를 입력하면 선택/해제가 바뀝니다. +경로 로 위치를 추가하고, Enter로 확정합니다.\n'
  while :; do
    [[ -z ${prompt_app:-} ]] || ensure_prompt_focus "$prompt_app"
    # End of input (scripted/non-TTY) confirms the current selection instead of looping.
    printf 'Git 위치 선택: '; IFS= read -r answer || break
    if [[ -z $answer ]]; then
      [[ $selected == '[]' ]] || break
      printf '선택된 위치가 없어 git 커밋을 수집하지 않습니다. 이대로 진행할까요? [y/N] '; IFS= read -r answer || break
      [[ $answer != [yY] ]] || break
      print_roots; continue
    fi
    if [[ $answer == +* ]]; then
      path=${answer#+}
      path=$(routine_git_root_path "$path") || { printf '특정 저장소 폴더를 추가하세요 (홈 자체·상위·캐시·임시 worktree 제외).\n'; continue; }
      selected=$(command jq -c --arg root "$path" '.+[$root]|unique' <<< "$selected")
    else
      for index in $answer; do
        if [[ ! $index =~ ^[1-9][0-9]*$ ]] || ((index>number)); then printf '목록의 위치 번호를 입력하세요: %s\n' "$index"; continue; fi
        root=$(command jq -r --argjson index "$((index-1))" '.[$index]' <<< "$candidates")
        selected=$(command jq -c --arg root "$root" 'if index($root)!=null then map(select(.!=$root)) else .+[$root] end' <<< "$selected")
      done
    fi
    print_roots
  done
  ROUTINE_SETTINGS=$(command jq -c --argjson roots "$selected" '.sources.git.roots=$roots' <<< "$ROUTINE_SETTINGS")
}
routine_source_reason() {
  local source=$1 root available=0 apps=${ROUTINE_APPLICATIONS_DIR:-/Applications}
  case $source in
    git)
      if ! type -P git >/dev/null; then echo 'git 없음'; return; fi
      while IFS= read -r -d '' root; do [[ $(routine_git_root_count "$root") == 0 ]] || available=1; done < <(command jq -j '.sources.git.roots[]|.+"\u0000"' <<< "$ROUTINE_SETTINGS")
      ((available)) || echo '선택 위치에 Git 저장소 없음' ;;
    prs) if ! type -P gh >/dev/null || ! gh auth status >/dev/null 2>&1; then echo 'gh 로그인 필요'; fi ;;
    omp_sessions) [[ -d $(routine_get sources.omp_sessions.dir) ]] || echo 'omp 세션 폴더 없음' ;;
    claude_sessions) [[ -d $(routine_get sources.claude_sessions.dir) ]] || echo 'Claude 세션 폴더 없음' ;;
    jira)
      if [[ ! -d $apps/Google\ Chrome.app ]]; then echo 'Chrome 없음'
      elif [[ ! -d $(routine_get sources.jira.chrome_dir) ]]; then echo 'Chrome 프로필 없음'; fi ;;
    notion)
      if [[ ! -d $apps/Notion.app ]]; then echo 'Notion 앱 없음'
      elif [[ ! -r $(routine_get sources.notion.db) ]]; then echo 'Notion 기록 DB 없음'; fi ;;
    slack)
      if [[ $(routine_get delivery.mode) != gui-paste || ! -d $apps/Orca.app || ! -d $apps/Slack.app ]]; then echo '자동 붙여넣기(Orca) 필요'
      else
        # shellcheck source=orca.sh
        source "$share_dir/orca.sh"
        find_orca >/dev/null || echo '실행 가능한 Orca CLI 필요'
      fi ;;
  esac
  return 0
}
routine_source_label() {
  case $1 in
    git) printf 'git 커밋 (git) — 내 작성 커밋' ;;
    prs) printf 'GitHub PR (prs) — 내가 만든·리뷰한 PR' ;;
    omp_sessions) printf 'omp 세션 (omp_sessions) — AI 작업 보고' ;;
    claude_sessions) printf 'Claude Code 세션 (claude_sessions) — AI 작업 보고' ;;
    jira) printf 'Jira (Chrome 방문 기록) (jira)' ;;
    notion) printf 'Notion 편집 기록 (notion)' ;;
    slack) printf 'Slack 내 메시지 (slack) — 자동 붙여넣기 전용' ;;
  esac
}
routine_source_list() {
  local source reason selected label description status number=0 stdout_tty=0
  [[ ! -t 1 ]] || stdout_tty=1
  for source in git prs omp_sessions claude_sessions jira notion slack; do
    number=$((number+1)); reason=$(routine_source_reason "$source"); selected=$(ui_color hint '○' "$stdout_tty")
    if ((!stdout_tty)); then selected='[ ]'; fi
    label=$(routine_source_label "$source")
    description=''
    if [[ $label == *' — '* ]]; then
      description=" — ${label#* — }"; label=${label%% — *}
    fi
    [[ $(routine_get "sources.$source.enabled") != true ]] || selected=$(ui_color success '●' "$stdout_tty")
    if ((!stdout_tty)) && [[ $(routine_get "sources.$source.enabled") == true ]]; then selected='[선택]'; fi
    if [[ -z $reason ]]; then status="$(ui_color success '✓' "$stdout_tty") $(ui_color hint '사용 가능' "$stdout_tty")"
    else status="$(ui_color warning '⚠' "$stdout_tty") $(ui_color hint "필요 조건: $reason" "$stdout_tty")"; fi
    if ((!stdout_tty)) && [[ -n $reason ]]; then status="– 필요 조건: $reason"; fi
    printf '  %s) %s %s%s%s%s\n' "$number" "$selected" "$label" "$(ui_color hint "$description" "$stdout_tty")" "$(ui_color hint ' — ' "$stdout_tty")" "$status"
  done
}
routine_select_sources() {
  local source reason answer index enabled email items selected result refused original=$ROUTINE_SETTINGS
  local names=(git prs omp_sessions claude_sessions jira notion slack)
  for source in "${names[@]}"; do
    reason=$(routine_source_reason "$source")
    if [[ -n $reason ]]; then ROUTINE_SETTINGS=$(command jq -c --arg source "$source" '.sources[$source].enabled=false' <<< "$ROUTINE_SETTINGS"); fi
  done
  if ui_gum_available; then
    selected=$(command jq -c '[.sources|to_entries[]|select(.value.enabled)|.key]' <<< "$ROUTINE_SETTINGS")
    while :; do
      items='[]'
      for source in "${names[@]}"; do
        reason=$(routine_source_reason "$source")
        items=$(command jq -c --arg source "$source" --arg label "$(routine_source_label "$source")" --arg reason "$reason" '.+[{value:$source,label:$label,reason:$reason}]' <<< "$items")
      done
      if ! result=$(ui_choose_many '수집 소스 선택 (Space로 선택, Enter로 확정)' "$items" "$selected"); then
        ROUTINE_SETTINGS=$(command jq -c --argjson original "$original" '.sources|=with_entries(.value.enabled=$original.sources[.key].enabled)' <<< "$ROUTINE_SETTINGS")
        return 0
      fi
      refused=0
      while IFS= read -r -d '' source; do
        reason=$(routine_source_reason "$source")
        if [[ $source == git && $reason == '선택 위치에 Git 저장소 없음' ]]; then
          if ui_confirm 'Git 저장소 위치를 다시 고를까요?'; then routine_select_git_roots; reason=$(routine_source_reason git); fi
        fi
        if [[ -n $reason ]]; then
          ui_note '수집 소스 선택 불가' "$(routine_source_label "$source") 선택 불가: $reason" error
          result=$(command jq -c --arg source "$source" 'map(select(.!=$source))' <<< "$result")
          refused=1
        fi
      done < <(command jq -j '.[]|.+"\u0000"' <<< "$result")
      selected=$result
      ((refused)) && continue
      ROUTINE_SETTINGS=$(command jq -c --argjson selected "$selected" '.sources|=with_entries(.key as $key|.value.enabled=($selected|index($key)!=null))' <<< "$ROUTINE_SETTINGS")
      break
    done
  else
  printf '\n수집 소스 선택 (번호로 켜고 끄기, 예: 5 6; Enter로 확정)\n'
  while :; do
    routine_source_list
    [[ -z ${prompt_app:-} ]] || ensure_prompt_focus "$prompt_app"
    printf '수집 소스 선택: '; IFS= read -r answer
    [[ -n $answer ]] || break
    for index in $answer; do
      if [[ ! $index =~ ^[1-7]$ ]]; then printf '1~7 사이 소스 번호가 필요합니다: %s\n' "$index"; continue; fi
      source=${names[index-1]}; enabled=$(routine_get "sources.$source.enabled")
      if [[ $enabled == true ]]; then enabled=false
      else
        reason=$(routine_source_reason "$source")
        # The only fixable-in-place condition: no Git location selected. Offer the location step again.
        if [[ $source == git && $reason == '선택 위치에 Git 저장소 없음' ]]; then
          printf 'Git 저장소 위치를 다시 고를까요? [Y/n] '; IFS= read -r answer
          if [[ $answer != [nN] ]]; then routine_select_git_roots; reason=$(routine_source_reason git); fi
        fi
        if [[ -n $reason ]]; then printf '%s 선택 불가: %s\n' "$(routine_source_label "$source")" "$reason"; continue; fi
        enabled=true
      fi
      ROUTINE_SETTINGS=$(command jq -c --arg source "$source" --argjson enabled "$enabled" '.sources[$source].enabled=$enabled' <<< "$ROUTINE_SETTINGS")
    done
  done
  fi
  if [[ $(routine_get sources.notion.enabled) == true ]]; then
    email=$(routine_get identity.notion_email_like)
    [[ -n $email ]] || email=$(git config user.email 2>/dev/null || true)
    if ui_gum_available; then
      if answer=$(ui_input 'Notion 작성자 이메일/LIKE 패턴' 'Notion에서 쓰는 이메일 또는 LIKE 패턴' "$email"); then
        ROUTINE_SETTINGS=$(command jq -c --arg email "$answer" '.identity.notion_email_like=$email' <<< "$ROUTINE_SETTINGS")
      fi
    else
      [[ -z ${prompt_app:-} ]] || ensure_prompt_focus "$prompt_app"
      printf 'Notion 작성자 이메일/LIKE 패턴 [%s]: ' "$email"; IFS= read -r answer
      ROUTINE_SETTINGS=$(command jq -c --arg email "${answer:-$email}" '.identity.notion_email_like=$email' <<< "$ROUTINE_SETTINGS")
    fi
  fi
}
routine_manage_sources() {
  local action=${1:-} name=${2:-} reason enabled
  if (($#==0)); then routine_source_list; return; fi
  case $action in enable) enabled=true ;; disable) enabled=false ;; *) echo 'routine sources [enable|disable <이름>]' >&2; return 2 ;; esac
  (($#==2)) || { echo '소스 이름 하나를 지정하세요.' >&2; return 2; }
  case $name in git|prs|omp_sessions|claude_sessions|jira|notion|slack) ;; *) printf '알 수 없는 소스: %s\n' "$name" >&2; return 2 ;; esac
  if [[ $enabled == true ]]; then
    reason=$(routine_source_reason "$name")
    [[ -z $reason ]] || { printf '%s 선택 불가: %s\n' "$(routine_source_label "$name")" "$reason" >&2; return 2; }
  fi
  ROUTINE_SETTINGS=$(command jq -c --arg name "$name" --argjson enabled "$enabled" '.sources[$name].enabled=$enabled' <<< "$ROUTINE_SETTINGS")
  routine_require_config || return 2
  routine_save_config "$ROUTINE_SETTINGS" || return
  printf '%s: %s (설정 파일만 변경)\n' "$(routine_source_label "$name")" "$enabled"
}
