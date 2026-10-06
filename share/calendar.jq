# Date-only arithmetic uses UTC; local timestamps are converted by the shell boundary.
def calendar_epoch: .+"T00:00:00Z" | fromdateiso8601;
def calendar_shift($days): calendar_epoch + $days*86400 | strftime("%Y-%m-%d");
def calendar_weekday: calendar_epoch | gmtime[6] | if .==0 then 7 else . end;
def calendar_day($day;$settings;$holidays):
  ($day|calendar_weekday) as $weekday |
  ($settings.morning.weekdays|index($weekday)!=null) as $scheduled |
  ($settings.calendar.work_days|index($day)!=null) as $override |
  ($settings.calendar.days_off|index($day)!=null) as $off |
  (if $settings.calendar.public_holidays=="kr" then $holidays.years[$day[:4]][$day] // "" else "" end) as $holiday |
  {day:$day,weekday:$weekday,scheduled:$scheduled,override:$override,off:$off,holiday:$holiday,
   workday:($override or ($scheduled and ($off|not) and $holiday=="")),
   reason:(if $override then "예외 근무일" elif $off then "개인 휴무"+(if ($settings.calendar.day_off_notes[$day] // "")!="" then " "+$settings.calendar.day_off_notes[$day] else "" end)
           elif $holiday!="" then "공휴일 "+$holiday elif $scheduled|not then "예약 요일 아님" else "근무일" end)};
def calendar_warning($day;$settings;$holidays):
  if $settings.calendar.public_holidays=="kr" and ($holidays.years|has($day[:4])|not)
  then "공휴일 표 없음("+$day[:4]+") — 업데이트 필요" else empty end;
def collect_window($day;$settings;$holidays):
  $settings.collect.max_days as $max |
  first(range(1;$max+1) as $days | ($day|calendar_shift(-$days)) as $candidate |
    calendar_day($candidate;$settings;$holidays) |
    select(.workday or $days==$max) |
    {since:$candidate,limited:(.workday|not),max_days:$max}) |
  .notices=[(if .limited then "수집 기간을 \($max)일로 제한" else empty end),
    calendar_warning($day;$settings;$holidays),calendar_warning(.since;$settings;$holidays)] |
  .notices |= unique;
