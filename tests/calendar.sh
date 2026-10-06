#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
sandbox=$(mktemp -d /tmp/routine-calendar.XXXXXXXX)
trap 'rm -rf -- "$sandbox"' EXIT
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" PATH="$sandbox/home/.local/bin:/opt/homebrew/bin:/usr/bin:/bin"
export ROUTINE_CONFIG="$HOME/.config/routine-automation/config.json" ROUTINE_NOW='2026-10-06T08:00:00+09:00'
unset ROUTINE_CLI_OVERRIDES ROUTINE_PUBLIC_HOLIDAYS ROUTINE_DAYS_OFF ROUTINE_WORK_DAYS ROUTINE_COLLECT_MAX_DAYS
export ROUTINE_TZ=Asia/Seoul ROUTINE_LLM_ENGINE=none ROUTINE_DELIVERY_MODE=clipboard
unset ROUTINE_REPO_ROOT ROUTINE_GIT_ROOTS ROUTINE_GIT_AUTHORS ROUTINE_COLLECT_UNTIL ROUTINE_OMP_SESSIONS ROUTINE_CLAUDE_SESSIONS ROUTINE_CHROME_DIR ROUTINE_NOTION_DB
unset ROUTINE_GIT_ENABLED ROUTINE_PRS_ENABLED ROUTINE_OMP_SESSIONS_ENABLED ROUTINE_CLAUDE_SESSIONS_ENABLED ROUTINE_JIRA_ENABLED ROUTINE_NOTION_ENABLED ROUTINE_SLACK_ENABLED
unset ROUTINE_OMP_UPDATE ROUTINE_CLAUDE_UPDATE ROUTINE_NPM_UPDATE ROUTINE_AWS_SESSION
mkdir -p "$HOME/.local/bin" "$TMPDIR" "${ROUTINE_CONFIG%/*}"
ln -s "${TEST_JQ_BIN:-$(type -P jq)}" "$HOME/.local/bin/jq"
# shellcheck source=network.sh
source "$repo/tests/network.sh"
export CALLS="$sandbox/calls"
: > "$CALLS"
blocked() { printf 'blocked %s\n' "$*" >> "$CALLS"; return 87; }
for cmd in launchctl gh open pbcopy pbpaste; do
  cat > "$HOME/.local/bin/$cmd" <<'STUB'
#!/bin/bash
printf 'blocked %s\n' "$*" >> "$CALLS"
exit 87
STUB
  eval "$cmd() { blocked $cmd \"\$@\"; }"
  export -f "${cmd?}"
done
export -f blocked
osascript() { printf 'notify %s\n' "$*" >> "$CALLS"; }
aws-session-check() { echo aws-session >> "$CALLS"; }
gtimeout() { [[ ${1:-} != -k ]] || shift 2; shift; "$@"; }
export -f osascript gtimeout aws-session-check
cat > "$HOME/.local/bin/osascript" <<'STUB'
#!/bin/bash
printf 'notify %s\n' "$*" >> "$CALLS"
STUB
cat > "$HOME/.local/bin/aws-session-check" <<'STUB'
#!/bin/bash
echo aws-session >> "$CALLS"
STUB
cat > "$HOME/.local/bin/gtimeout" <<'STUB'
#!/bin/bash
[[ ${1:-} != -k ]] || shift 2
shift
exec "$@"
STUB
chmod +x "$HOME/.local/bin/"{launchctl,gh,open,pbcopy,pbpaste,osascript,aws-session-check,gtimeout}
local_repo="$sandbox/repos/example"
git init -q "$local_repo"
printf 'first\n' > "$local_repo/work"
git -C "$local_repo" add work
GIT_AUTHOR_DATE='2026-10-02T09:00:00+0900' GIT_COMMITTER_DATE='2026-10-02T09:00:00+0900' git -C "$local_repo" -c user.name=Fixture -c user.email=fixture@example.com commit -qm '금요일 작업'
printf 'holiday\n' >> "$local_repo/work"
git -C "$local_repo" add work
GIT_AUTHOR_DATE='2026-10-05T09:00:00+0900' GIT_COMMITTER_DATE='2026-10-05T09:00:00+0900' git -C "$local_repo" -c user.name=Fixture -c user.email=fixture@example.com commit -qm '휴일 작업'
share_dir="$repo/share"
# shellcheck source=../share/config.sh
source "$share_dir/config.sh"
base=$(command jq -L "$share_dir" -nc --arg root "${local_repo%/*}" 'include "config"; defaults("/fixture";"fixture") | .timezone="Asia/Seoul" | .slack.team_id="TEXAMPLE" | .slack.workspace_domain="example" | .slack.channel_id="CEXAMPLE" | .identity.git_authors=["fixture@example.com"] | .sources |= with_entries(.value.enabled=(.key=="git")) | .sources.git.roots=[$root] | .draft.llm.engine="none" | .morning.extra_steps.aws_session=true')
routine_save_config "$base"
routine_load_config
check_since() {
  local day=$1 expected=$2 actual
  actual=$(routine_collect_since "$day")
  [[ $actual == "$expected" ]] || fail "$day since=$actual (예상 $expected)"
  printf '날짜 표: %s → %s PASS\n' "$day" "$actual"
}
check_since 2026-10-06 2026-10-02
check_since 2026-10-08 2026-10-07
check_since 2026-10-12 2026-10-08
check_since 2026-05-04 2026-04-30
check_since 2026-02-19 2026-02-13
check_since 2027-05-04 2027-04-30
check_since 2027-07-20 2027-07-16
check_since 2027-12-28 2027-12-24
routine="$repo/bin/routine"
"$routine" off '10-07~10-08' '연차' > "$sandbox/off"
"$routine" off 10-07 > /dev/null
routine_load_config
check_since 2026-10-12 2026-10-06
command jq -e '.calendar.days_off==["2026-10-07","2026-10-08"] and .calendar.day_off_notes["2026-10-07"]=="연차"' "$ROUTINE_CONFIG" >/dev/null || fail '범위·중복·메모 저장'
"$routine" work 10-09 > /dev/null
routine_load_config
routine_calendar_info 2026-10-09 | command jq -e '.workday and .override' >/dev/null || fail '한글날 예외 근무'
check_since 2026-10-12 2026-10-09
"$routine" off > "$sandbox/list"
command jq -Rse 'contains("10-07") and contains("연차") and contains("한글날") and contains("예외 근무일")' "$sandbox/list" >/dev/null || fail '60일 일정 목록'
"$routine" work --remove 10-09 > /dev/null
"$routine" off --remove '10-07~10-08' > /dev/null
"$routine" off today '회사 휴무' > /dev/null
"$routine" off tomorrow > /dev/null
"$routine" off --remove 'today~tomorrow' > /dev/null
"$routine" work today > /dev/null
"$routine" work --remove today > /dev/null
"$routine" work 10-10 > "$sandbox/weekend"
command jq -Rse 'contains("launchd") and contains("routine run")' "$sandbox/weekend" >/dev/null || fail '주말 수동 실행 안내'
"$routine" off 10-10 '휴무 겹침' > /dev/null
routine_load_config
routine_calendar_info 2026-10-10 | command jq -e '.workday and .override and .off and (.scheduled|not)' >/dev/null || fail '주말·휴무보다 근무 예외 우선'
"$routine" work --remove 10-10 > /dev/null
"$routine" off --remove 10-10 > /dev/null
before=$(shasum -a 256 "$ROUTINE_CONFIG")
for spec in 2026-02-30 2026-10-05 10-1 '10-08~10-07' '10-06~12-05' '10-07~garbage~10-08' '10-07~' '../2026-10-07'; do
  if "$routine" off "$spec" > /dev/null 2>&1; then fail "잘못된 날짜 허용: $spec"; fi
done
if "$routine" work tomorrow > /dev/null 2>&1; then fail 'work tomorrow 허용'; fi
[[ $(shasum -a 256 "$ROUTINE_CONFIG") == "$before" && $(stat -f %Lp "$ROUTINE_CONFIG") == 600 ]] || fail '입력 오류로 설정 변경·0600 손실'
"$routine" off '10-06~12-04' > /dev/null
command jq -e '.calendar.days_off|length==60' "$ROUTINE_CONFIG" >/dev/null || fail '정확히 60일 범위 경계'
"$routine" off --remove '10-06~12-04' > /dev/null
ROUTINE_NOW='2026-12-20T08:00:00+09:00' "$routine" off '12-31~2027-01-02' > /dev/null
command jq -e '.calendar.days_off==["2026-12-31","2027-01-01","2027-01-02"]' "$ROUTINE_CONFIG" >/dev/null || fail '연도 경계 범위'
routine_save_config "$base"
"$routine" collect --sources git > /dev/null
out="$HOME/Library/Application Support/routine-automation/scrum"
command jq -e '.window.since=="2026-10-01T15:00:00Z" and .window.until=="2026-10-05T15:00:00Z" and (.git|map(.subject)|sort)==["금요일 작업","휴일 작업"]' "$out/2026-10-06.json" >/dev/null || fail '10/6 수집 실제 금요일·휴일 작업 포함'
"$routine" draft --no-llm > /dev/null
command jq -Rse 'startswith("어제 작업한 내용\n") and contains("금요일 작업") and contains("휴일 작업")' "$out/2026-10-06.draft.txt" >/dev/null || fail '기간 확장 시 팀 머리글·근거 보존'
"$routine" review --no-open > "$sandbox/review"
[[ -s $out/2026-10-06.review.html ]] || fail '변경된 기간 초안 검토 생성'
# Three weeks off: the cap remains visible in collection, questions, and status.
ROUTINE_NOW='2026-10-06T08:00:00+09:00' "$routine" off '10-06~10-26' > /dev/null
routine_load_config
check_since 2026-10-27 2026-10-13
routine_collect_window 2026-10-27 | command jq -e '.limited and .notices==["수집 기간을 14일로 제한"]' >/dev/null || fail '14일 제한 안내'
ROUTINE_NOW='2026-10-27T08:00:00+09:00' "$routine" draft --no-llm > /dev/null
command jq -e 'any(.questions[];.=="수집 기간을 14일로 제한")' "$out/2026-10-27.draft.json" >/dev/null || fail '초안 질문 제한 경고'
ROUTINE_NOW='2026-10-27T08:00:00+09:00' "$routine" status > "$sandbox/status-limit"
command jq -Rse 'contains("수집 기간을 14일로 제한")' "$sandbox/status-limit" >/dev/null || fail 'status 수집 제한 경고'
ROUTINE_NOW='2026-10-27T08:00:00+09:00' "$routine" collect --since 2026-10-01 --sources git > /dev/null
command jq -e '.window.since=="2026-09-30T15:00:00Z" and (.window.limited|not)' "$out/2026-10-27.json" >/dev/null || fail '명시적 since 기간 상한 우선'
routine_save_config "$base"
ROUTINE_NOW='2026-10-07T09:00:00+09:00' "$routine" status > "$sandbox/status"
command jq -Rse 'contains("다음 예약: 2026-10-08(목) 08:00 — 10-09 한글날 건너뜀")' "$sandbox/status" >/dev/null || fail '다음 근무일 예약·곧 건너뛸 휴일'
ROUTINE_NOW='2026-10-08T09:00:00+09:00' "$routine" status > "$sandbox/status-friday"
command jq -Rse 'contains("다음 예약: 2026-10-12(월)")' "$sandbox/status-friday" >/dev/null || fail '한글날 예약 제외'
ROUTINE_NOW='2026-12-24T09:00:00+09:00' ROUTINE_WEEKDAYS='[5]' "$routine" status > "$sandbox/status-two-holidays"
command jq -Rse 'contains("다음 예약: 2027-01-08(금)")' "$sandbox/status-two-holidays" >/dev/null || fail '연속 두 주 공휴일 예약 제외'
ROUTINE_NOW='2028-01-04T08:00:00+09:00' "$routine" status > "$sandbox/status-2028"
command jq -Rse 'contains("공휴일 표 없음(2028) — 업데이트 필요")' "$sandbox/status-2028" >/dev/null || fail '표 없는 연도 status 경고'
ROUTINE_NOW='2028-01-04T08:00:00+09:00' "$repo/bin/morning" --only aws-session > "$sandbox/morning-2028"
command jq -Rse 'contains("공휴일 표 없음(2028) — 업데이트 필요")' "$sandbox/morning-2028" >/dev/null || fail '표 없는 연도 아침 경고'
ROUTINE_NOW='2026-10-09T08:00:00+09:00' "$repo/bin/morning" > "$sandbox/holiday-morning"
command jq -Rse 'contains("scrum-collect:skipped(공휴일 한글날)") and contains("scrum-draft:skipped(공휴일 한글날)") and contains("scrum-paste:skipped(공휴일 한글날)") and contains("스크럼:skipped(공휴일 한글날)") and contains("aws-session:ok")' "$sandbox/holiday-morning" >/dev/null || fail '공휴일 scrum skip·extra_steps 실행·사유'
[[ ! -f $out/2026-10-09.json ]] || fail '공휴일에 실제 스크럼 수집'
calls_before_auto=$(shasum -a 256 "$CALLS")
ROUTINE_NOW='2026-10-09T08:30:00+09:00' ROUTINE_DELIVERY_MODE=gui-paste "$repo/bin/scrum-paste" --auto > "$sandbox/paste-skip"
[[ $(shasum -a 256 "$CALLS") == "$calls_before_auto" && ! -e $HOME/Library/Logs/routine-automation/scrum-paste-2026-10-09.log ]] || fail 'auto 공휴일에 GUI·클립보드 접근 또는 실행 로그 생성'
"$routine" work 10-09 > /dev/null
ROUTINE_NOW='2026-10-09T08:00:00+09:00' "$repo/bin/morning" > "$sandbox/work-morning"
command jq -Rse 'contains("scrum-collect:ok") and contains("scrum-draft:ok") and contains("scrum-paste:clipboard")' "$sandbox/work-morning" >/dev/null || fail '예외 근무일 morning 실행'
[[ -f $out/2026-10-09.draft.txt ]] || fail '예외 근무일 초안 누락'
routine_save_config "$base"
routine_load_config
ROUTINE_PUBLIC_HOLIDAYS=none routine_load_config
check_since 2026-10-06 2026-10-05
[[ -z $(routine_calendar_warning 2028-01-04) ]] || fail 'none에 공휴일 표 경고'
# Cached learn uses the same holiday-aware date without GUI/model/clipboard access.
cp "$out/2026-10-06.draft.json" "$out/2026-10-08.draft.json"
mkdir -p "$out/learn"
printf '{"suggestions":[]}\n' > "$out/learn/2026-10-08.json"
ROUTINE_NOW='2026-10-12T08:00:00+09:00' ROUTINE_LLM_ENGINE=omp "$routine" learn </dev/null > "$sandbox/learn"
command jq -Rse 'contains("저장된 제안만 출력")' "$sandbox/learn" >/dev/null || fail 'learn 직전 근무일 기본 날짜'
# Loading legacy settings migrates in memory, not on disk.
command jq 'del(.calendar,.collect.max_days)' <<< "$base" > "$ROUTINE_CONFIG"
legacy_hash=$(shasum -a 256 "$ROUTINE_CONFIG")
routine_load_config
[[ $(routine_get calendar.public_holidays) == kr && $(routine_get collect.max_days) == 14 && $(shasum -a 256 "$ROUTINE_CONFIG") == "$legacy_hash" ]] || fail '기존 config 기본값 무변경 로드'
command jq -Rse 'contains("blocked ")|not' "$CALLS" >/dev/null || fail '실제 외부/GUI 금지 경계 접근'
printf 'PASS: 근무일 날짜 표·공휴일·휴가 CLI·수집 실제 경로·morning·auto skip·status (%s)\n' "$(command jq --version)"
