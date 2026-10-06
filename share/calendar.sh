#!/usr/bin/env bash
# shellcheck disable=SC2154 # share_dir is supplied by each entrypoint.
routine_calendar_info() {
  command jq -L "$share_dir" -nc --arg day "$1" --argjson settings "$ROUTINE_SETTINGS" --slurpfile holidays "$share_dir/holidays-kr.json" 'include "calendar"; calendar_day($day;$settings;$holidays[0])'
}
routine_workday_reason() {
  routine_calendar_info "$1" | command jq -r 'select(.workday|not)|.reason'
}
routine_calendar_warning() {
  command jq -L "$share_dir" -nr --arg day "$1" --argjson settings "$ROUTINE_SETTINGS" --slurpfile holidays "$share_dir/holidays-kr.json" 'include "calendar"; calendar_warning($day;$settings;$holidays[0])'
}
routine_calendar_label() {
  if [[ $(routine_get calendar.public_holidays) == kr ]]; then echo '한국(내장 2026–2027)'; else echo '없음'; fi
}
routine_collect_window() {
  command jq -L "$share_dir" -nc --arg day "$1" --argjson settings "$ROUTINE_SETTINGS" --slurpfile holidays "$share_dir/holidays-kr.json" 'include "calendar"; collect_window($day;$settings;$holidays[0])'
}
routine_calendar_list() {
  local today
  today=$(routine_day)
  printf '앞으로 60일의 공휴일·개인 휴무·예외 근무일 (%s부터)\n' "$today"
  command jq -L "$share_dir" -nr --arg today "$today" --argjson settings "$ROUTINE_SETTINGS" --slurpfile holidays "$share_dir/holidays-kr.json" '
    include "calendar";
    [range(0;60) as $offset | ($today|calendar_shift($offset)) as $day | calendar_day($day;$settings;$holidays[0]) |
      select(.override or .off or .holiday!="") |
      "\(.day)(\(["","월","화","수","목","금","토","일"][.weekday])) — "+
      ([if .holiday!="" then "공휴일 "+.holiday else empty end,
        if .off then "개인 휴무"+(if ($settings.calendar.day_off_notes[.day] // "")!="" then " "+$settings.calendar.day_off_notes[.day] else "" end) else empty end,
        if .override then "예외 근무일 (스크럼 작성)" else empty end]|join(" / "))] |
    if length==0 then "등록된 일정 없음" else .[] end'
  routine_calendar_warning "$today"
}
routine_calendar_date() {
  local value=$1 today=$2
  case $value in
    today) value=$today ;;
    tomorrow) value=$(date -j -v+1d -f '%Y-%m-%d %H:%M:%S' "$today 12:00:00" '+%Y-%m-%d') ;;
    *) if [[ $value =~ ^[0-9]{2}-[0-9]{2}$ ]]; then value="${today:0:4}-$value"; fi ;;
  esac
  command jq -L "$share_dir" -ner --arg value "$value" 'include "config"; $value|select(calendar_date)' 2>/dev/null || { echo '날짜는 유효한 YYYY-MM-DD 또는 MM-DD, today/tomorrow 형식이어야 합니다.' >&2; return 2; }
}
routine_manage_calendar() {
  local kind=$1 remove=0 spec today start end dates memo='' settings weekday
  shift
  if [[ $kind == off && $# == 0 ]]; then routine_calendar_list; return; fi
  if [[ ${1:-} == --remove ]]; then remove=1; shift; fi
  (($#>=1)) || { echo "routine $kind 날짜가 필요합니다." >&2; return 2; }
  spec=$1; shift
  if [[ $kind == work || $remove == 1 ]]; then
    (($#==0)) || { echo '이 명령은 메모를 받지 않습니다.' >&2; return 2; }
  else memo="$*"; fi
  today=$(routine_day)
  if [[ $kind == work && ( $spec == *'~'* || $spec == tomorrow ) ]]; then echo 'routine work는 날짜 하나 또는 today만 받습니다.' >&2; return 2; fi
  start=$(routine_calendar_date "${spec%%~*}" "$today") || return 2
  end=$(routine_calendar_date "${spec##*~}" "$today") || return 2
  [[ $start > $today || $start == "$today" ]] || { echo '과거 날짜는 등록·삭제할 수 없습니다.' >&2; return 2; }
  [[ $spec =~ ^[^~]+(~[^~]+)?$ ]] || { echo '날짜 범위 형식 오류' >&2; return 2; }
  dates=$(command jq -L "$share_dir" -nec --arg start "$start" --arg end "$end" '
    include "calendar"; ($start|calendar_epoch) as $a | ($end|calendar_epoch) as $b |
    select($b>=$a and ($b-$a)/86400<60) | [range(0;($b-$a)/86400+1) as $offset | $start|calendar_shift($offset)]') || { echo '날짜 범위는 시작일부터 최대 60일이며 끝 날짜가 시작일보다 빠를 수 없습니다.' >&2; return 2; }
  settings=$(command jq -c --arg kind "$kind" --argjson remove "$remove" --argjson dates "$dates" --arg memo "$memo" '
    (if $kind=="off" then "days_off" else "work_days" end) as $key |
    .calendar[$key] |= (if $remove==1 then .-$dates else .+$dates|unique end) |
    if $kind=="off" then reduce $dates[] as $day (.;
      if $remove==1 then del(.calendar.day_off_notes[$day])
      elif $memo!="" then .calendar.day_off_notes[$day]=$memo else . end) else . end' <<< "$ROUTINE_FILE_SETTINGS") || return 2
  routine_save_config "$settings" || return 2
  printf '%s %s: %s%s\n' "$kind" "$(if ((remove)); then echo 삭제; else echo 등록; fi)" "$start" "$(if [[ $end != "$start" ]]; then printf '~%s' "$end"; fi)"
  if [[ $kind == work && $remove == 0 ]]; then
    weekday=$(date -j -f '%Y-%m-%d %H:%M:%S' "$start 12:00:00" '+%u')
    if ! command jq -e --argjson day "$weekday" '.morning.weekdays|index($day)!=null' <<< "$settings" >/dev/null; then
      echo '예약 요일 밖의 예외 근무일은 launchd가 실행되지 않습니다. 그날 routine run으로 스크럼을 작성하세요.'
    fi
  fi
}
