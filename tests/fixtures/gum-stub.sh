#!/bin/bash
set -euo pipefail
# Never delegate to an installed gum. All selections are deterministic fixtures.
args=$(jq -nc --args '$ARGS.positional' -- "$@")
jq -nc --argjson args "$args" --argjson tty "$([[ -t 0 && -t 2 ]] && echo true || echo false)" '{args:$args,tty:$tty}' >> "$GUM_RECORD"
printf 'gum\n' >> "$GUM_RECORD.focus"
cmd=$1; shift
if [[ ${GUM_MODE:-} == cancel ]]; then exit 130; fi
if [[ ${GUM_MODE:-} == abnormal ]]; then exit 42; fi
# gum choose/input Esc: exit 1 with empty output (must not be read as an empty selection).
if [[ ${GUM_MODE:-} == escape && ( $cmd == choose || $cmd == input ) ]]; then exit 1; fi
header='' current='' options=() preselected=()
while (($#)); do
  case $1 in
    --header) header=$2; shift 2 ;;
    --value) current=$2; shift 2 ;;
    --selected) preselected+=("${2//\\,/,}"); shift 2 ;;
    --placeholder|--char-limit|--affirmative|--negative|--title|--border|--border-foreground|--foreground|--padding|--width) shift 2 ;;
    --default=*|--no-limit|--show-output) shift ;;
    --) shift; options=("$@"); break ;;
    *) options+=("$1"); shift ;;
  esac
done
case $cmd in
  input)
    if [[ $header == 'git 작성자' && ${GUM_MODE:-} == edit ]]; then echo 'edited@example.com, second@example.com'; exit; fi
    if [[ $header == 'git 작성자' && ${GUM_MODE:-} == repair-authors ]]; then echo 'repaired@example.com'; exit; fi
    if [[ $header == 'Git 위치 직접 추가' ]]; then echo "$GUM_EXTRA_ROOT"
    elif [[ ${GUM_MODE:-} == unit ]]; then echo '수동 입력 결과'
    else echo "$current"; fi ;;
  choose)
    if [[ $header == '저장 전 최종 확인' ]]; then
      count=0; [[ ! -f $GUM_RECORD.final ]] || read -r count < "$GUM_RECORD.final"
      count=$((count+1)); echo "$count" > "$GUM_RECORD.final"
      case ${GUM_MODE:-} in
        final-cancel) echo '취소' ;;
        final-escape) exit 1 ;;
        final-interrupt) exit 130 ;;
        edit|edit-roots|edit-empty-roots|keep-authors) if ((count==1)); then echo '항목 고치기'; else echo '저장'; fi ;;
        repair-authors) if ((count==2)); then echo '항목 고치기'; else echo '저장'; fi ;;
        unknown) echo '목록에 없는 결과' ;;
        *) echo '저장' ;;
      esac
      exit
    fi
    if [[ $header == '고칠 항목 선택' ]]; then echo "${GUM_EDIT_TARGET:-git 작성자}"; exit; fi
    if [[ ${GUM_MODE:-} == unknown ]]; then echo '목록에 없는 결과'; exit; fi
    if [[ ${GUM_MODE:-} == unit ]]; then printf '%s\n' '항목 둘'; exit; fi
    kind=roots; [[ $header != '수집 소스 선택'* ]] || kind=sources
    file="$GUM_RECORD.$kind"
    count=0; [[ ! -f $file ]] || read -r count < "$file"
    count=$((count+1)); echo "$count" > "$file"
    if [[ $kind == roots ]]; then
      case ${GUM_MODE:-} in
        add)
          if ((count==1)); then
            for option in "${options[@]}"; do [[ $option != "$GUM_PRIMARY_ROOT — "* && $option != '+ 위치 직접 추가' ]] || echo "$option"; done
          else
            for option in "${options[@]}"; do [[ $option != "$GUM_EXTRA_ROOT — "* ]] || echo "$option"; done
          fi ;;
        recover|empty)
          if ((count>1)); then
            for option in "${options[@]}"; do [[ $option != "$GUM_PRIMARY_ROOT — "* ]] || echo "$option"; done
          fi ;;
        # edit-roots: first pass picks only the primary; the re-edit just presses Enter, keeping
        # whatever the wrapper preselected.
        edit-roots)
          if ((count==1)); then for option in "${options[@]}"; do [[ $option != "$GUM_PRIMARY_ROOT — "* ]] || echo "$option"; done
          else for option in ${preselected[@]+"${preselected[@]}"}; do echo "$option"; done; fi ;;
        edit-empty-roots)
          if ((count>1)); then for option in ${preselected[@]+"${preselected[@]}"}; do echo "$option"; done; fi ;;
        *) for option in "${options[@]}"; do [[ $option != "$GUM_PRIMARY_ROOT — "* ]] || echo "$option"; done ;;
      esac
    else
      if [[ ${GUM_MODE:-} == edit-empty-roots ]]; then
        for option in "${options[@]}"; do [[ $option != 'omp 세션 (omp_sessions) — AI 작업 보고' ]] || echo "$option"; done
        exit
      fi
      for option in "${options[@]}"; do
        if [[ $option == 'git 커밋 (git) — 내 작성 커밋' || $option == 'omp 세션 (omp_sessions) — AI 작업 보고' ]]; then echo "$option"
        elif [[ $option == *'(prs)'* && ${GUM_MODE:-} == add && $count == 1 ]]; then echo "$option"
        elif [[ $option == *'(git)'* && ${GUM_MODE:-} == recover ]]; then echo "$option"; fi
      done
    fi ;;
  confirm)
    if [[ ${GUM_MODE:-} == empty && "${options[*]}" == '선택된 위치가 없어'* ]]; then exit 1; fi
    exit 0 ;;
  style) printf '%s\n' "${options[@]}" ;;
  spin) "${options[@]}" ;;
  *) exit 91 ;;
esac
