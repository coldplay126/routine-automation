#!/usr/bin/env bash
# shellcheck disable=SC2154 # share_dir is supplied by the routine entrypoint.
routine_next_schedule() {
  local today now clock stamp first_offset
  today=$(routine_day); now=$(date +%s)
  if [[ -n ${ROUTINE_NOW:-} ]]; then
    stamp=${ROUTINE_NOW/Z/+0000}; stamp=$(printf '%s' "$stamp" | sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/')
    now=$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "$stamp" '+%s')
  fi
  clock=$(routine_get morning.time)
  first_offset=0
  if (( $(date -j -f '%Y-%m-%d %H:%M:%S' "$today $clock:00" '+%s') <= now )); then first_offset=1; fi
  command jq -L "$share_dir" -nr --arg today "$today" --arg clock "$clock" --argjson offset "$first_offset" --argjson settings "$ROUTINE_SETTINGS" --slurpfile holidays "$share_dir/holidays-kr.json" '
    include "calendar";
    ([$settings.calendar.days_off[],(if $settings.calendar.public_holidays=="kr" then $holidays[0].years[]|keys[] else empty end),$today]|max|calendar_epoch) as $last |
    first(range($offset;($last-($today|calendar_epoch))/86400+8) as $n | ($today|calendar_shift($n)) as $day | calendar_day($day;$settings;$holidays[0]) | select(.scheduled and .workday)) as $next |
    ([range($offset;60) as $n | ($today|calendar_shift($n)) as $day | calendar_day($day;$settings;$holidays[0]) | select(.scheduled and (.workday|not))][0] // null) as $skip |
    "\($next.day)(\(["","월","화","수","목","금","토","일"][$next.weekday])) \($clock)"+
    (if $skip!=null then " — \($skip.day[5:]) \($skip.reason|ltrimstr("공휴일 ")) 건너뜀" else "" end)'
}
routine_disk_access_report() {
  local result="$HOME/Library/Application Support/routine-automation/.setup-first-run-result.json" status=unverified
  [[ ! -f $result ]] || status=$(jq -r '.full_disk_access.status // "unverified"' "$result")
  case $status in
    readable) echo '✓ 최근 first-run morning /bin/bash 보호 경로 읽기 가능' ;;
    denied) echo '⚠ /bin/bash에 전체 디스크 접근 허용 필요 — 설정 후 setup 재실행 (권한 단계를 건너뛰려면 --skip disk-access)' ;;
    *) echo '– first-run morning /bin/bash 전체 디스크 접근: 미검증 (보호 경로 없음 또는 첫 실행 전)' ;;
  esac
}
routine_status() {
  local day out log marker source agent label status_manifest
  day=$(routine_day); out="$HOME/Library/Application Support/routine-automation/scrum/$day"; log="$HOME/Library/Logs/routine-automation/morning-$day.log"
  printf '오늘: %s\n' "$day"
  printf '공휴일: %s\n' "$(routine_calendar_label)"
  routine_calendar_warning "$day"
  if [[ -f $out.json ]]; then command jq -r '.window.notices[]?' "$out.json"
  else routine_collect_window "$day" | command jq -r '.notices[]|select(startswith("수집 기간을"))'; fi
  if [[ -f $out.json ]]; then
    jq -r '"수집 기간: \(.window.since) ~ \(.window.until) (\(.window.tz // "시스템 시간대"), 상한 제외)","수집:",(["git","prs","jira","notion","slack"][] as $s|"  \($s): \(.[$s]|length)건"),"  omp_sessions: \([.sessions[]?|select(.source!="claude")]|length)건","  claude_sessions: \([.sessions[]?|select(.source=="claude")]|length)건",(.errors[]?|"  오류 [\(.source)]: \(.message)")' "$out.json"
  else echo '수집: 미실행'; fi
  if [[ -f $out.draft.json ]]; then jq -L "$share_dir" -r 'include "scrum"; delivery_counts as $counts | "초안: 전달 \($counts.delivered) · 생략 \($counts.omitted) / 확인 필요 \(.questions|length)건"' "$out.draft.json"; else echo '초안: 미실행'; fi
  if [[ $(routine_get jira.enabled) == true ]]; then
    # shellcheck source=jira.sh
    source "$share_dir/jira.sh"
    routine_jira_status || echo 'Jira 동기화: 상태 파일 확인 필요'
  fi
  echo "전달 방식: $(routine_get delivery.mode)"
  for marker in pasted paste-attention paste-skipped copied; do
    if [[ -f $out.$marker ]]; then printf '전달 [%s]: ' "$marker"; cat "$out.$marker"; fi
  done
  if [[ -f $log ]]; then
    for source in omp-update claude-update npm-update aws-session; do
      printf 'extra_steps %s: ' "$source"
      grep -E "^$source:" "$log" | tail -n 1 || echo '기록 없음'
    done
  else echo 'extra_steps: 실행 로그 없음'; fi
  printf '다음 예약: %s\n' "$(routine_next_schedule)"
  routine_disk_access_report
  # shellcheck source=share/install.sh
  source "$share_dir/install.sh"
  routine_install_paths
  if routine_installation_pending; then
    echo '⚠ 미완료 설치 — routine update --yes 또는 새 패키지의 install.sh --update로 복구하세요.'
  fi
  status_manifest=$manifest
  [[ -f $status_manifest ]] || status_manifest="$installed_root.previous/manifest.json"
  if [[ -f $status_manifest ]]; then
    while IFS= read -r agent; do
      label=${agent##*/}; label=${label%.plist}
      if ! launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
        printf '⚠ 예약 실행 미등록: %s — 새 패키지의 install.sh --update로 복구하세요.\n' "$label"
      fi
    done < <(command jq -r --arg dir "$agent_dir/" '.files[]?|.path|select(startswith($dir) and endswith(".plist"))' "$status_manifest")
  fi
  # shellcheck source=style.sh
  source "$share_dir/style.sh"
  routine_style_migration_notice
  # shellcheck source=update.sh
  source "$share_dir/update.sh"
  routine_update_notice || true
}
routine_doctor() {
  local cmd errors=0 engine version service orca visible check label present required
  for cmd in jq git sqlite3 gh osascript; do
    if type -P "$cmd" >/dev/null; then
      case $cmd in sqlite3) version=$(sqlite3 -version) ;; osascript) version='macOS 내장' ;; *) version=$("$cmd" --version 2>/dev/null || true) ;; esac
      printf '✓ %s: %s\n' "$cmd" "${version%%$'\n'*}"
    else printf '✗ 의존성 누락: %s\n' "$cmd"; errors=$((errors+1)); fi
  done
  if ! routine_jq_supported; then echo '✗ jq 1.7 이상 필요 (brew install jq)'; errors=$((errors+1)); fi
  routine_disk_access_report
  if type -P gtimeout >/dev/null; then version=$(gtimeout --version); printf '✓ gtimeout: %s\n' "${version%%$'\n'*}"; else echo '✗ 의존성 누락: gtimeout'; errors=$((errors+1)); fi
  if [[ -d ${ROUTINE_APPLICATIONS_DIR:-/Applications}/Slack.app ]]; then echo '✓ Slack 앱'; else echo '✗ Slack 앱 누락'; errors=$((errors+1)); fi
  if routine_require_config; then echo '✓ 설정 스키마·필수값'; else errors=$((errors+1)); fi
  if [[ $(routine_get jira.enabled) == true ]]; then
    required=$(command jq -L "$share_dir" -r 'include "config"; jira_required_errors|join(", ")' <<< "$ROUTINE_SETTINGS")
    if [[ -z $required ]]; then echo '✓ Jira 설정'; else printf '✗ Jira 설정: %s\n' "$required"; errors=$((errors+1)); fi
    if security find-generic-password -s routine-automation.jira -a "$(routine_get jira.email)" >/dev/null 2>&1; then echo '✓ Jira Keychain 항목 (토큰 미조회)'
    else echo '✗ Jira Keychain 항목 없음'; errors=$((errors+1)); fi
  fi
  if gh auth status >/dev/null 2>&1; then echo '✓ gh 로그인'; else echo '✗ gh 로그인'; errors=$((errors+1)); fi
  engine=$(routine_get draft.llm.engine)
  if [[ $engine == auto ]]; then if command -v claude >/dev/null; then engine=claude; elif command -v omp >/dev/null; then engine=omp; else engine=none; fi; fi
  case $engine in
    claude) if command -v claude >/dev/null && claude auth status 2>/dev/null | jq -e '.loggedIn==true' >/dev/null; then printf '✓ claude 로그인: %s\n' "$(claude --version)"; else echo '✗ claude 로그인'; errors=$((errors+1)); fi ;;
    omp) if command -v omp >/dev/null; then printf '✓ omp: %s\n' "$(omp --version)"; else echo '✗ omp 누락'; errors=$((errors+1)); fi ;;
    none) echo '– LLM none' ;;
  esac
  for service in morning scrum-paste; do
    if [[ $service == scrum-paste && $(routine_get delivery.mode) != gui-paste ]]; then
      if launchctl print "gui/$(id -u)/$(routine_get launchd.label_prefix).$service" >/dev/null 2>&1; then echo '⚠ clipboard 모드에 paste LaunchAgent 잔존 — setup으로 제거하세요 (자동 GUI 가드는 계속 적용됨)'
      else echo '– paste LaunchAgent (clipboard)'; fi
      continue
    fi
    if launchctl print "gui/$(id -u)/$(routine_get launchd.label_prefix).$service" >/dev/null 2>&1; then printf '✓ LaunchAgent %s 로드\n' "$service"; else printf '✗ LaunchAgent %s 미로드\n' "$service"; errors=$((errors+1)); fi
  done
  if [[ $(routine_get delivery.mode) == gui-paste ]]; then
    # shellcheck source=orca.sh
    source "$share_dir/orca.sh"
    if orca=$(find_orca) && visible=$("$orca" computer get-app-state --app com.tinyspeck.slackmacgap --no-screenshot --json 2>/dev/null) &&
       jq -L "$share_dir" -e 'include "slack"; tree_text|ax_lines|any(.[];.index!=null)' <<< "$visible" >/dev/null; then
      echo '✓ Orca 런타임·ax_lines 인덱스'
      while IFS= read -r check; do
        label=$(jq -r '.key' <<< "$check"); present=$(jq -r '.present' <<< "$check"); required=$(jq -r '.required' <<< "$check")
        if [[ $present == true ]]; then printf '✓ 현재 화면 라벨: %s\n' "$label"
        elif [[ $required == true ]]; then printf '✗ 보이는 화면의 라벨 누락: %s\n' "$label"; errors=$((errors+1))
        else printf '– 현재 화면 라벨 %s: 미검증 (닫힌 화면 포함)\n' "$label"; fi
      done < <(jq -L "$share_dir" -c 'include "slack"; visible_label_checks[]' <<< "$visible")
    elif [[ -n ${orca:-} ]] && ! "$orca" computer capabilities --json >/dev/null 2>&1 </dev/null; then
      # doctor is read-only and does not launch Orca; scrum-paste starts it when needed.
      echo '– Orca 앱 꺼짐: 자동 붙여넣기 때 자동 시작 (런타임·라벨 미검증)'
    else echo '✗ Orca 런타임/출력 형식'; errors=$((errors+1)); fi
  else echo '– Orca·Slack 라벨: 미검증 (clipboard, UI 접근 안 함)'; fi
  ((errors==0))
}
