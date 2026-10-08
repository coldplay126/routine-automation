#!/usr/bin/env bash
routine_review() (
  local day='' no_open=0 out input source_file target_tmp='' midnight
  local review_share
  review_share=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  while (($#)); do
    case $1 in
      --date)
        (($#>=2)) || { echo '--date 날짜가 필요합니다.' >&2; return 2; }
        day=$2; shift 2 ;;
      --no-open) no_open=1; shift ;;
      *) printf '알 수 없는 검토 옵션: %s\n' "$1" >&2; return 2 ;;
    esac
  done
  [[ -n $day ]] || day=$(routine_day)
  [[ $day =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo '날짜는 YYYY-MM-DD 형식이어야 합니다.' >&2; return 2; }
  midnight=$(date -j -f '%Y-%m-%d %H:%M:%S' "$day 00:00:00" '+%s' 2>/dev/null) || { echo '유효하지 않은 날짜입니다.' >&2; return 2; }
  [[ $(date -r "$midnight" '+%Y-%m-%d') == "$day" ]] || { echo '유효하지 않은 날짜입니다.' >&2; return 2; }
  out="$HOME/Library/Application Support/routine-automation/scrum"
  input="$out/$day.draft.json"
  [[ -f $input ]] || { printf '%s 초안이 없습니다. routine draft --date %s를 실행하세요.\n' "$day" "$day" >&2; return 1; }
  source_file="$out/$day.json"
  [[ -f $source_file ]] || source_file=/dev/null
  jq -L "$review_share" -e 'include "scrum"; saved_draft_ok and (.yesterday|type=="array") and (.today|type=="array")' "$input" >/dev/null || { echo '초안 JSON이 유효하지 않습니다. 초안을 다시 생성하세요.' >&2; return 1; }
  target_tmp=$(mktemp "$out/.$day.review.XXXXXXXX")
  trap '[[ -z $target_tmp ]] || rm -f -- "$target_tmp"' EXIT
  jq -L "$review_share" -r --arg day "$day" --slurpfile source "$source_file" --rawfile template "$review_share/review.html" 'include "review"; review_page($source[0] // {}; $day; $template)' "$input" > "$target_tmp"
  chmod 600 "$target_tmp"
  mv -f "$target_tmp" "$out/$day.review.html"
  target_tmp=''
  printf '%s\n' "$out/$day.review.html"
  ((no_open)) || open "$out/$day.review.html"
)
