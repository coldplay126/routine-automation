#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
sandbox=$(mktemp -d '/tmp/scrum-tests.XXXXXXXX')
board_name=''
cleanup() {
  local status=$?
  if [[ $board_name == routine-test-* ]]; then /usr/bin/osascript -l JavaScript "$repo/tests/pasteboard.js" clear >/dev/null; fi
  rm -rf -- "$sandbox"
  exit "$status"
}
trap cleanup EXIT
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" PATH="$sandbox/home/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export ROUTINE_NOW='2026-09-28T12:00:00+09:00' ROUTINE_TZ=Asia/Seoul
export ROUTINE_REPO_ROOT="$sandbox/repos" ROUTINE_OMP_SESSIONS="$sandbox/sessions" ROUTINE_CHROME_DIR="$sandbox/chrome" ROUTINE_NOTION_DB="$sandbox/notion.db"
export CALLS="$sandbox/calls" STAGE="$sandbox/stage" CLIPBOARD="$sandbox/clipboard" OMP_COUNT="$sandbox/omp-count" OMP_INPUT="$sandbox/omp-input"
export FOREGROUND="$sandbox/foreground" HID_RESET_EPOCH="$sandbox/hid-reset" AUTO_EPOCH_FILE="$sandbox/auto-epoch" TIMEOUT_CALLS="$sandbox/timeout-calls"
export AUTO_MS_FILE="$sandbox/auto-ms" FIXTURES="$repo/tests/fixtures"
mkdir -p "$HOME/.local/bin" "$TMPDIR" "$ROUTINE_REPO_ROOT" "$ROUTINE_OMP_SESSIONS/one"
ln -s "${TEST_JQ_BIN:-$(type -P jq)}" "$HOME/.local/bin/jq"
# shellcheck source=common.sh
source "$repo/tests/common.sh"
out="$HOME/Library/Application Support/routine-automation/scrum"
mkdir -p "$out"
cat > "$out/2026-09-28.json" <<'JSON'
{"version":1,"window":{"since":"2026-09-24T15:00:00Z","until":"2026-09-28T03:00:00Z"},"git":[{"sha":"abc123","repo":"제품","subject":"개발"}],"prs":[{"url":"https://example/pull/1","state":"MERGED","in_window":true,"activity":[{"kind":"merged","at":"2026-09-25T00:00:00Z"}],"title":"제품"},{"url":"https://example/pull/2","state":"OPEN","in_window":true,"activity":[{"kind":"review","at":"2026-09-25T01:00:00Z"}],"title":"보류 기능"},{"url":"https://example/pull/3","state":"OPEN","in_window":false,"activity":[],"title":"다음 기능"},{"url":"https://example/pull/4","state":"OPEN","in_window":true,"activity":[{"kind":"commit","at":"2026-09-25T02:00:00Z"}],"title":"feat: 서포트  알림 슬랙 연동"}],"sessions":[{"id":"request","title":"요청","latest_report":"다음: 검토","user_messages":[{"text":"검토 요청"}]},{"id":"deploy","title":"운영","latest_report":"결제 API 운영 배포 완료했습니다. Argo sync Synced Healthy 확인\n결제 API 운영 조회 결과 200 정상 확인했습니다","user_messages":[]}],"slack":[],"jira":[],"notion":[],"errors":[]}
JSON
cat > "$sandbox/model.json" <<'JSON'
{"items":[
 {"section":"yesterday","path":["개발","요청"],"topic":"요청 대응","level":"request","evidence":["session:request"]},
 {"section":"yesterday","path":["배포","제품"],"topic":"제품","level":"deployed","evidence":["pr:https://example/pull/1"]},
 {"section":"yesterday","path":["개발","없는 근거"],"topic":"원문 주제","level":"work","evidence":["git:missing"]},
 {"section":"yesterday","path":["배포","결제 API"],"topic":"결제 API","level":"deployed","evidence":["session:deploy"]},
 {"section":"yesterday","path":["배포","결제 API"],"topic":"결제 API","level":"verified","evidence":["session:deploy"]},
 {"section":"yesterday","path":["배포","요청"],"topic":"요청","level":"verified","evidence":["session:request"]},
 {"section":"yesterday","path":["개발","동의어"],"topic":"프로덕션 반영 완료","level":"request","evidence":["session:request"]},
 {"section":"yesterday","path":["개발","제품"],"topic":"리뷰 대응","level":"merged","evidence":["pr:https://example/pull/1"]}]}
JSON
export MODEL_JSON="$sandbox/model.json"
cat > "$HOME/.local/bin/gh" <<'GH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$CALLS"
exit 87
GH
cat > "$HOME/.local/bin/omp" <<'OMP'
#!/usr/bin/env bash
printf 'omp %s\n' "$*" >> "$CALLS"
if [[ -n ${ROUTINE_GUI_ACTIVITY_FILE:-} && $(cat "$FOREGROUND") == com.tinyspeck.slackmacgap ]]; then echo unsafe-model-focus >> "$CALLS"; exit 87; fi
for flag in --no-session --no-title --no-tools --no-lsp --no-pty --no-extensions --no-skills --no-rules; do
  [[ " $* " == *" $flag "* ]] || { echo unsafe-model >> "$CALLS"; exit 87; }
done
[[ " $* " == *' --approval-mode always-ask '* && " $* " == *' --max-time 240 '* && " $* " == *' --config '* ]] || exit 87
[[ $PWD == "$TMPDIR"/scrum-draft.*/model-cwd ]] || { echo unsafe-cwd >> "$CALLS"; exit 87; }
cat > "$OMP_INPUT"
[[ -s $OMP_INPUT ]] || exit 87
count=$(cat "$OMP_COUNT" 2>/dev/null || echo 0); count=$((count+1)); echo "$count" > "$OMP_COUNT"
if [[ ${OMP_BAD:-} == always || ( ${OMP_BAD:-} == once && $count == 1 ) ]]; then echo '{broken'; else cat "$MODEL_JSON"; fi
OMP
cat > "$HOME/.local/bin/open" <<'OPEN'
#!/usr/bin/env bash
printf 'open %s\n' "$*" >> "$CALLS"
if [[ ${1-} == -b ]]; then
  [[ ${FOCUS_OPEN_FAIL:-0} != 1 ]] || exit 92
  echo "$2" > "$FOREGROUND"
  exit 0
fi
echo com.tinyspeck.slackmacgap > "$FOREGROUND"
if [[ ${AUTO_SELF_RESET:-0} == 1 ]]; then perl -MTime::HiRes=time -e 'printf "%.0f\n", time*1000' > "$HID_RESET_EPOCH"; fi
[[ ${PASTE_MODE:-} != signal-open ]] || kill -TERM "$PPID"
if [[ ${1-} == -a ]]; then echo search > "$STAGE"; else echo channel > "$STAGE"; fi
rm -f -- "$STAGE.polls" "$STAGE.pasted"
if [[ ${1-} == -a ]]; then rm -f -- "$STAGE".*.polls "$STAGE.cleared"; fi
OPEN
cat > "$HOME/.local/bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
exit 0
SLEEP
cat > "$HOME/.local/bin/pbpaste" <<'PASTE'
#!/usr/bin/env bash
cat "$CLIPBOARD"
PASTE
cat > "$HOME/.local/bin/pbcopy" <<'COPY'
#!/usr/bin/env bash
cat > "$CLIPBOARD"
COPY
cat > "$HOME/.local/bin/osascript" <<'JXA'
#!/usr/bin/env bash
if [[ ${1-} == -e ]]; then printf 'notification %s\n' "$*" >> "$CALLS"; exit 0; fi
if [[ ${3-} == */app-focus.js ]]; then
  printf 'focus %s\n' "${4-}" >> "$CALLS"
  case ${4-} in
    capture) cat "$FOREGROUND" ;;
    restore)
      [[ ${FOCUS_RESTORE_FAIL:-0} != 1 ]] || exit 91
      if [[ ${FOCUS_RESTORE_IGNORED:-0} != 1 && $(cat "$FOREGROUND") == com.tinyspeck.slackmacgap ]]; then echo "$5" > "$FOREGROUND"; fi ;;
    *) exit 87 ;;
  esac
  exit 0
fi
if [[ ${3-} == */slack-frontmost.js ]]; then [[ ${PASTE_MODE:-} != background ]]; exit; fi
printf 'clipboard %s\n' "${4-}" >> "$CALLS"
case ${4-} in
  backup) pbpaste > "$5" ;;
  set) pbcopy < "$6" ;;
  restore) pbcopy < "$5" ;;
  *) exit 87 ;;
esac
JXA
cat > "$HOME/.local/bin/orca" <<'ORCA'
#!/usr/bin/env bash
[[ $1 == --help || "$1 ${2:-}" == 'computer capabilities' ]] && exit 0
printf 'orca %s\n' "$*" >> "$CALLS"
[[ $1 == computer ]] || exit 87
stage=$(cat "$STAGE")
action=$2
case $2 in
  click)
    index=''
    while (($#)); do if [[ $1 == --element-index ]]; then index=$2; break; fi; shift; done
    case $index in
      5|10) echo combo > "$STAGE" ;;
      6) touch "$STAGE.cleared" ;;
      17) echo results > "$STAGE" ;;
      21) echo channel > "$STAGE" ;;
      31|33|61) echo thread > "$STAGE" ;;
      30) echo reveal > "$STAGE" ;;
      44) echo focused > "$STAGE" ;;
      *) exit 87 ;;
    esac ;;
  set-value)
    while (($#)); do if [[ $1 == --value ]]; then printf '%s\n' "$2" > "$STAGE.query"; break; fi; shift; done
    [[ ${PASTE_MODE:-} != search-fail ]] || exit 89
    [[ $2 != *' on:'* ]] || touch "$STAGE.searched"
    echo query > "$STAGE" ;;
  press-key) [[ $stage == query && ${SEARCH_MODE:-} == fallback ]] || exit 88; echo results > "$STAGE" ;;
  hotkey)
    if [[ ${PASTE_MODE:-} == fail-v ]]; then exit 89; fi
    [[ ${PASTE_MODE:-} != child-three ]] || exit 3
    [[ $stage == focused ]] || exit 88
    [[ " $* " != *' Cmd+V '* ]] || touch "$STAGE.pasted" ;;
  get-app-state)
    focus=null
    case $stage in
      search)
        tree='[5] 버튼 검색'
        if [[ ${SEARCH_MODE:-} == prior ]]; then tree=$'[5] 버튼 검색: from:@테스트_사용자 on:2026-09-27\n[6] 버튼 검색 지우기\n[7] 버튼 채널 내에서 검색'; fi
        if [[ ${SEARCH_MODE:-} == loading || ${SEARCH_MODE:-} == never-search ]]; then
          polls=$(cat "$STAGE.search.polls" 2>/dev/null || echo 0); polls=$((polls+1)); echo "$polls" > "$STAGE.search.polls"
          fixture=slack-search-loading.json
          if [[ $SEARCH_MODE == loading && $polls -ge 3 ]]; then fixture=slack-search-ready.json; fi
          tree=$(jq -r '.result.snapshot.treeText' "$FIXTURES/$fixture")
        fi ;;
      combo)
        tree='[11] 콤보 상자, Value: '
        if [[ ${SEARCH_MODE:-} == loading ]]; then
          polls=$(cat "$STAGE.combo.polls" 2>/dev/null || echo 0); polls=$((polls+1)); echo "$polls" > "$STAGE.combo.polls"
          fixture=slack-search-loading.json
          if ((polls>=3)); then fixture=slack-search-combo.json; fi
          tree=$(jq -r '.result.snapshot.treeText' "$FIXTURES/$fixture")
        fi ;;
      query)
        query=$(cat "$STAGE.query")
        focus=15; tree="[15] 콤보 상자, Value: $query"
        case ${SEARCH_MODE:-} in
          fallback) ;;
          unsafe) focus=99 ;;
          loading)
            polls=$(cat "$STAGE.query.polls" 2>/dev/null || echo 0); polls=$((polls+1)); echo "$polls" > "$STAGE.query.polls"
            if ((polls>=3)); then tree=$(jq -r --arg query "$query" '.result.snapshot.treeText|gsub("from:me after:2026-09-24";$query)' "$FIXTURES/slack-search-suggestion.json"); fi ;;
          *) tree+=$'\n'"[17] 메뉴 항목, Value: $query 검색" ;;
        esac ;;
      results)
        query=$(cat "$STAGE.query")
        if [[ $query == *' on:'* ]]; then
          tree=$(jq -r '.result.snapshot.treeText' "$FIXTURES/slack-duplicate-results.json")
          case ${PASTE_MODE:-} in
            search-own) ;;
            search-own-incomplete) tree=${tree/$'\t22 텍스트, Value: 1'/$'\t22 텍스트, Value: 12'} ;;
            search-other|search-incomplete)
              tree=${tree//thread_ts=1790895609.247049/thread_ts=1790895608.539999}
              extra=$'\n\t\t35 container 다른 채널 댓글\n\t\t\t36 container\n\t\t\t\t37 버튼 테스트_사용자\n\t\t\t\t38 link [오늘, 오전 10:10](https://example.slack.com/archives/COTHER/p1790903400000000?thread_ts=1790895609.247049)\n\t\t\t\t39 텍스트, Value: 다른 채널 댓글'
              tree=${tree/$'\n\t34 버튼 피드백 제공'/$extra$'\n\t34 버튼 피드백 제공'}
              total=2; [[ ${PASTE_MODE:-} != search-incomplete ]] || total=12
              tree=${tree/$'\t22 텍스트, Value: 1'/$'\t22 텍스트, Value: '"$total"} ;;
            search-other-author) tree=${tree/$'\t\t\t\t\t28 버튼 테스트_사용자'/$'\t\t\t\t\t28 버튼 테스트_사용자_동명이인'} ;;
            search-unknown-author) tree=${tree/$'\t\t\t\t\t28 버튼 테스트_사용자'/$'\t\t\t\t\t28 텍스트, Value: 테스트_사용자'} ;;
            search-bad-url) tree=${tree//thread_ts=1790895609.247049/thread_ts=unknown} ;;
            search-format) tree=${tree/내용 목록 채널의 메시지 결과/내용 목록 바뀐 결과} ;;
            *)
              tree=${tree%%$'\n\t22'*}
              tree+=$'\n\t24 내용 목록 채널의 메시지 결과\n\t\t25 container\n\t\t\t26 텍스트, Value: 찾은 결과가 없습니다' ;;
          esac
        else
          tree=$(jq -r '.result.snapshot.treeText' "$FIXTURES/slack-search-results.json")
          if [[ ${SEARCH_MODE:-} == cutoff || ${SEARCH_MODE:-} == malformed-url ]]; then
            url='https://slack.example/archives/C1/p1790521200000000'; text='오늘 자정 작업'
            if [[ $SEARCH_MODE == malformed-url ]]; then url='https://slack.example/archives/C1/not-a-timestamp'; text='해석할 수 없는 메시지'; fi
            extra=$'\n\t\t\t40 container 테스트_사용자: 추가 작업\n\t\t\t\t41 container\n\t\t\t\t\t42 버튼 테스트_사용자\n\t\t\t\t\t43 link [오늘, 오전 12:00]('"$url"$')\n\t\t\t\t\t44 container, Text: '"$text"
            tree=${tree/$'\n\t\t37 버튼 피드백 제공'/$extra$'\n\t\t37 버튼 피드백 제공'}
          fi
          if [[ ${SEARCH_MODE:-} == empty ]]; then tree=$'[5] 버튼 검색: from:@테스트_사용자 after:2026-09-24\n[6] 버튼 검색 지우기\n18 container 검색\n\t21 내용 목록 메시지 결과, 1/1페이지\n\t\t22 container\n\t\t\t23 텍스트, Value: 찾은 결과가 없습니다'; fi
          if [[ ${SEARCH_MODE:-} == no-channel-label ]]; then tree=${tree//$'\t\t\t\t\t28 스레드: #제품'/}; tree=${tree//$'\t\t\t\t\t36 스레드: #개발'/}; fi
        fi
        [[ ! -f $STAGE.cleared ]] || tree=${tree/$'\n6 버튼 검색 지우기'/} ;;
      channel|reveal)
        day=오늘; [[ ${PASTE_MODE:-} == old ]] && day=어제
        if [[ ${PASTE_MODE:-} == workflow ]]; then
          # Workflow posts repeat the title as an author button, and Slack's hover action now reads
          # "스레드의 댓글": both must resolve to the single post and its reply action.
          tree=$'[30] container 스크럼-예제팀: 예제팀 일일 업무\n\t[34] container\n\t\t[35] 버튼 스크럼-예제팀\n\t\t[36] 텍스트, Value: 워크플로\n\t\t[32] link [오늘, 오전 8:00:01](https://slack.example/today)\n\t\t[37] container, Text: 예제팀 일일 업무'
          [[ $stage != reveal ]] || tree+=$'\n\t\t[38] container 메시지 작업\n\t\t\t[33] 버튼 스레드의 댓글'
          tree=${tree//https:\/\/slack.example\/today/https:\/\/example.slack.com\/archives\/CEXAMPLE\/p1790895609247049}
        else
          tree="[30] container, Text: 스크럼-예제팀: 예제팀"$'\n'"[32] link [$day, 오전 8:00:01](https://example.slack.com/archives/CEXAMPLE/p1790895609247049)"
          if [[ ${PASTE_MODE:-} == search-root-changed && -f $STAGE.searched ]]; then tree=${tree//p1790895609247049/p1790895608539999}; fi
          if [[ ${PASTE_MODE:-} == zero || ${PASTE_MODE:-} == reply-label || ${PASTE_MODE:-} == no-reply ]]; then
            if [[ $stage == reveal ]]; then
              [[ ${PASTE_MODE:-} != zero ]] || tree+=$'\n[33] 버튼 스레드에서 답장'
              [[ ${PASTE_MODE:-} != reply-label ]] || tree+=$'\n[33] 버튼 스레드에 댓글 달기'
            fi
          elif [[ ${PASTE_MODE:-} == partial* || ${PASTE_MODE:-} == search-* ]]; then
            tree+=$'\n[31] 버튼 12개의 댓글'
          else tree+=$'\n[31] 버튼 2개의 댓글'; fi
          if [[ -f $STAGE.searched ]]; then tree=${tree/$'\n[31]'/$'\n[61]'}; fi
          if [[ ${PASTE_MODE:-} == multi ]]; then tree+=$'\n[50] container, Text: 스크럼-예제팀: 예제팀\n[51] link [오늘, 오전 8:02:01](https://slack.example/other)\n[52] 버튼 5개의 댓글'; fi
        fi
        tree+=$'\n[39] container, Text: 공지\n[53] link [오늘, 오전 9:00:01](https://slack.example/notice)\n[52] 버튼 5개의 댓글' ;;
      thread|focused)
        tree=$'[40] container, Text: daily-scrum 채널의 스레드\n[45] container, Text: 스크럼-예제팀: 예제팀\n[46] link [오늘, 오전 8:03:01](https://slack.example/today)\n[42] 내용 목록 daily-scrum의 스레드 (채널)'
        tree=${tree//https:\/\/slack.example\/today/https:\/\/example.slack.com\/archives\/CEXAMPLE\/p1790895609247049}
        [[ ${PASTE_MODE:-} != workflow ]] || tree=${tree/$'\n[46]'/$'\n[49] 버튼 스크럼-예제팀\n[46]'}
        [[ ${PASTE_MODE:-} != wrong-root ]] || tree=$'[40] container, Text: daily-scrum 채널의 스레드\n[45] container, Text: 공지\n[46] link [오늘, 오전 9:00:01](https://slack.example/notice)'
        polls=$(cat "$STAGE.polls" 2>/dev/null || echo 0); polls=$((polls+1)); echo "$polls" > "$STAGE.polls"
        if [[ ${PASTE_MODE:-} == loading && $polls -le 2 || ${PASTE_MODE:-} == never-ready ]]; then tree='[40] container, Text: 스레드 불러오는 중'; fi
        [[ ${PASTE_MODE:-} != wrong-url ]] || tree=$'[40] container, Text: daily-scrum 채널의 스레드\n[45] container, Text: 스크럼-예제팀: 예제팀\n[46] link [오늘, 오전 8:03:01](https://slack.example/other)'
        if [[ ${PASTE_MODE:-} == duplicate || ( ${PASTE_MODE:-} == delayed-duplicate && $polls -ge 2 ) ]]; then tree+=$'\n[41] container, Text: 테스트_사용자: 기존 댓글'; fi
        value=''; [[ ${PASTE_MODE:-} != nonempty ]] || value='기존 입력'
        if [[ ${PASTE_MODE:-} == changed-target && $stage == thread && $polls -ge 4 ]]; then
          tree+=$'\n[44] 체크상자 새 요소, Value: 0\n[48] 텍스트 엔트리 영역 댓글, Value: '
        else tree+=$'\n'"[44] 텍스트 엔트리 영역 댓글, Value: $value"; fi
        checked=0; [[ ${PASTE_MODE:-} != checkbox-click || $stage != focused ]] || checked=1
        [[ ${PASTE_MODE:-} != checkbox-paste || ! -e $STAGE.pasted ]] || checked=1
        [[ ${PASTE_MODE:-} != initially-checked ]] || checked=1
        tree+=$'\n'"[47] 체크상자 #daily-scrum(으)로도 전송, Value: $checked"
        if [[ ${PASTE_MODE:-} == partial* || ${PASTE_MODE:-} == search-* ]]; then
          tree=$(jq -r '.result.snapshot.treeText' "$FIXTURES/slack-thread-partial.json")
          [[ ${PASTE_MODE:-} != partial-nonempty ]] || tree=${tree//스레드에 댓글 남기기/스레드에 댓글 남기기, Value: 기존 초안}
          [[ ${PASTE_MODE:-} != partial-own ]] || tree=${tree//동료_사용자/테스트_사용자}
        fi
        [[ $stage != focused ]] || focus=44 ;;
      *) exit 87 ;;
    esac
    if [[ ${PASTE_MODE:-} == query-special ]]; then tree=${tree//daily-scrum/$ROUTINE_SLACK_CHANNEL_NAME}; fi
    if [[ " $* " != *' --no-screenshot '* ]]; then
      [[ ${PASTE_MODE:-} != screenshot-fail ]] || exit 90
      jq -nc --arg tree "$tree" --argjson focus "$focus" '{result:{snapshot:{treeText:$tree,focusedElementId:$focus},screenshot:{path:"/tmp/stub-screenshot.png"}}}'
    else jq -nc --arg tree "$tree" --argjson focus "$focus" '{result:{snapshot:{treeText:$tree,focusedElementId:$focus}}}'; fi ;;
  *) exit 87 ;;
esac
case $action in
  click|set-value|press-key|hotkey)
    if [[ ${AUTO_SELF_RESET:-0} == 1 ]]; then perl -MTime::HiRes=time -e 'printf "%.0f\n", time*1000' > "$HID_RESET_EPOCH"; fi ;;
esac
ORCA
cat > "$HOME/.local/bin/gtimeout" <<'TIMEOUT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TIMEOUT_CALLS"
shift 3
exec "$@"
TIMEOUT
# lsappinfo: the original app counts as running unless ORIGINAL_APP_GONE=1.
cat > "$HOME/.local/bin/lsappinfo" <<'LSAPP'
#!/usr/bin/env bash
[[ ${ORIGINAL_APP_GONE:-0} == 1 ]] || printf 'ASN:0x0-0x1-"stub":\n'
LSAPP
chmod +x "$HOME/.local/bin/"{gh,omp,orca,open,sleep,osascript,pbcopy,pbpaste,gtimeout,lsappinfo}
# Exported functions also keep fixed-PATH children away from GUI/LLM/network.
open() { "$HOME/.local/bin/open" "$@"; }
osascript() { "$HOME/.local/bin/osascript" "$@"; }
pbcopy() { "$HOME/.local/bin/pbcopy" "$@"; }
pbpaste() { "$HOME/.local/bin/pbpaste" "$@"; }
orca() { "$HOME/.local/bin/orca" "$@"; }
omp() { "$HOME/.local/bin/omp" "$@"; }
gh() { "$HOME/.local/bin/gh" "$@"; }
export -f open osascript pbcopy pbpaste orca omp gh
require_gh_stub() { [[ $(type -P gh) == "$HOME/.local/bin/gh" ]] || fail 'Refusing real gh'; }
require_omp_stub() { [[ $(type -P omp) == "$HOME/.local/bin/omp" ]] || fail 'Refusing real omp'; }
require_gui_stubs() {
  local cmd
  for cmd in orca open osascript pbcopy pbpaste; do [[ $(type -P "$cmd") == "$HOME/.local/bin/$cmd" ]] || fail "Refusing real $cmd"; done
}
require_gh_stub; require_omp_stub; require_gui_stubs
# Run production JXA against a private named board, never the general clipboard.
board_name="routine-test-$$-$RANDOM"
export ROUTINE_PASTEBOARD_NAME="$board_name"
[[ $ROUTINE_PASTEBOARD_NAME == routine-test-* ]] || fail 'Refusing real general pasteboard'
jq -n '[
  [{type:"public.utf8-plain-text",data:("첫 항목"|@base64)},{type:"public.html",data:("<i>첫 항목</i>"|@base64)},{type:"public.rtf",data:("{\\rtf1\\ansi first}"|@base64)}],
  [{type:"public.data",data:"AAEC/w=="}],
  [{type:"org.nspasteboard.ConcealedType",data:""},{type:"public.utf8-plain-text",data:"c2VjcmV0"}],
  [{type:"org.nspasteboard.TransientType",data:""},{type:"public.utf8-plain-text",data:"ZXBoZW1lcmFs"}]
]' > "$sandbox/seed.json"
/usr/bin/osascript -l JavaScript "$repo/tests/pasteboard.js" seed "$sandbox/seed.json"
/usr/bin/osascript -l JavaScript "$repo/share/clipboard.js" backup "$sandbox/board-backup.json"
jq -e 'length==2 and all(.[][]; .type!="org.nspasteboard.ConcealedType" and .type!="org.nspasteboard.TransientType")' "$sandbox/board-backup.json" >/dev/null || fail 'Protected clipboard item backed up'
jq -e --slurpfile seed "$sandbox/seed.json" '. as $saved | all(range(0;2); . as $i | all($seed[0][$i][]; . as $entry | any($saved[$i][]; .==$entry)))' "$sandbox/board-backup.json" >/dev/null || fail 'Readable clipboard format lost during backup'
printf '<b>새 내용</b>' > "$sandbox/board.html"; printf '새 내용' > "$sandbox/board.txt"
/usr/bin/osascript -l JavaScript "$repo/share/clipboard.js" set "$sandbox/board.html" "$sandbox/board.txt"
/usr/bin/osascript -l JavaScript "$repo/tests/pasteboard.js" read > "$sandbox/board-read.json"
jq -e 'length==1 and any(.[0][];.type=="public.html" and (.data|@base64d)=="<b>새 내용</b>") and any(.[0][];.type=="public.utf8-plain-text" and (.data|@base64d)=="새 내용")' "$sandbox/board-read.json" >/dev/null || fail 'Real JXA rich pasteboard write missing'
/usr/bin/osascript -l JavaScript "$repo/share/clipboard.js" restore "$sandbox/board-backup.json"
/usr/bin/osascript -l JavaScript "$repo/tests/pasteboard.js" read > "$sandbox/board-read.json"
clipboard_bytes_match() {
  jq -e --slurpfile saved "$sandbox/board-backup.json" '. as $actual | $saved[0] as $expected | length==($expected|length) and all(range(0;$expected|length); . as $i | all($expected[$i][]; . as $entry | any($actual[$i][]; .==$entry)))' "$sandbox/board-read.json" >/dev/null
}
clipboard_bytes_match || fail 'Real JXA clipboard bytes not restored'
if /usr/bin/osascript -l JavaScript "$repo/share/clipboard.js" set "$sandbox/missing" "$sandbox/board.txt" > /dev/null 2>&1; then fail 'JXA missing input accepted'; fi
[[ -f $sandbox/board-backup.json ]] || fail 'Clipboard backup removed on failure'
printf '%s' '[[{"type":"public.data","data":"%%%"}]]' > "$sandbox/bad-backup.json"
if /usr/bin/osascript -l JavaScript "$repo/share/clipboard.js" restore "$sandbox/bad-backup.json" > /dev/null 2> "$sandbox/restore-error"; then fail 'Invalid clipboard restore accepted'; fi
grep -Fq "$sandbox/bad-backup.json" "$sandbox/restore-error" || fail 'Restore failure omitted backup path'
[[ -f $sandbox/bad-backup.json ]] || fail 'Failed restore discarded backup'
/usr/bin/osascript -l JavaScript "$repo/tests/pasteboard.js" read > "$sandbox/board-read.json"
clipboard_bytes_match || fail 'Preparation failure changed clipboard'
echo 'PASS: actual JXA named pasteboard rich writes and binary restoration'
# Render a depth-four tree; the model never controls markup.
cat > "$sandbox/render.json" <<'JSON'
{"yesterday":[{"label":"예제 프로젝트","children":[{"label":"A & B","children":[{"label":"<주제>","children":[{"item":0}]}]}]}],"today":[],"items":[{"text":"A < B > C & D"}]}
JSON
jq -L "$repo/share" -r 'include "scrum"; render_html' "$sandbox/render.json" > "$sandbox/html"
printf '%s\n' '<b>어제 작업한 내용</b><ul><li>예제 프로젝트<ul><li>A &amp; B<ul><li>&lt;주제&gt;<ul><li>A &lt; B &gt; C &amp; D</li></ul></li></ul></li></ul></li></ul>' '<b>오늘의 작업 계획</b><ul></ul>' > "$sandbox/expected-html"
cmp -s "$sandbox/html" "$sandbox/expected-html" || fail 'HTML tree escaping or nesting'
jq -L "$repo/share" -r 'include "scrum"; render_text' "$sandbox/render.json" > "$sandbox/text"
printf '%s\n' '어제 작업한 내용' '• 예제 프로젝트' '  ◦ A & B' '    ▪ <주제>' '      ▪ A < B > C & D' '' '오늘의 작업 계획' > "$sandbox/expected-text"
cmp -s "$sandbox/text" "$sandbox/expected-text" || fail 'Plain tree indentation'
# Equal normalized topic/path collapses one level in both rich and plain output.
jq -n '{items:[{section:"yesterday",path:["개발"," A  & B "],topic:"A & B",level:"work",evidence:["git:abc123"]},{section:"today",path:["업무 자동화","오늘 계획"],topic:"오늘 계획",level:"request",evidence:["note:0"]}]}' > "$sandbox/fold-model.json"
jq -L "$repo/share" --slurpfile source "$out/2026-09-28.json" 'include "scrum"; validate_draft($source[0];{held:[],today:["오늘 계획"]})' "$sandbox/fold-model.json" > "$sandbox/fold.json"
jq -L "$repo/share" -r 'include "scrum"; render_html' "$sandbox/fold.json" > "$sandbox/fold.html"
printf '%s\n' '<b>어제 작업한 내용</b><ul><li>예제 프로젝트<ul><li>개발<ul><li>A &amp; B</li></ul></li></ul></li></ul>' '<b>오늘의 작업 계획</b><ul><li>예제 프로젝트<ul><li>업무 자동화<ul><li>오늘 계획</li></ul></li></ul></li></ul>' > "$sandbox/fold-expected.html"
cmp -s "$sandbox/fold.html" "$sandbox/fold-expected.html" || fail 'Normalized subject repeated in HTML'
jq -L "$repo/share" -r 'include "scrum"; render_text' "$sandbox/fold.json" > "$sandbox/fold.txt"
printf '%s\n' '어제 작업한 내용' '• 예제 프로젝트' '  ◦ 개발' '    ▪ A & B' '' '오늘의 작업 계획' '• 예제 프로젝트' '  ◦ 업무 자동화' '    ▪ 오늘 계획' > "$sandbox/fold-expected.txt"
cmp -s "$sandbox/fold.txt" "$sandbox/fold-expected.txt" || fail 'Normalized subject repeated in plain text'
jq -L "$repo/share" --slurpfile source "$out/2026-09-28.json" -ne 'include "scrum"; {items:(["지원","기타","개발","Alpha","업무 자동화","인프라","배포","현황 파악","고객"] | map({section:"yesterday",path:[.,"묶음"],topic:"구체 작업",level:"work",evidence:["git:abc123"]}))} | validate_draft($source[0];{held:[],today:[]}) | [.yesterday[0].children[].label]==["현황 파악","배포","개발","인프라","업무 자동화","기타","Alpha","고객","지원"]' >/dev/null || fail 'Fixed categories or alphabetical remainder reordered'
jq -L "$repo/share" --slurpfile source "$out/2026-09-28.json" -ne 'include "scrum"; {items:[{section:"yesterday",path:["릴리즈 완료","설정"],topic:"설정 점검",level:"work",evidence:["git:abc123"]}]} | validate_draft($source[0];{held:[],today:[]}) | .items==[] and any(.questions[];contains("설정 점검"))' >/dev/null || fail 'Unsupported category completion remained deliverable'
jq -L "$repo/share" --slurpfile source "$out/2026-09-28.json" -ne 'include "scrum"; ($source[0] | .prs[1].current={state:"MERGED"} | .prs[2].state="MERGED" | .prs[2].current={state:"OPEN"}) as $s | {items:[{section:"today",path:["개발","지난 리뷰"],topic:"닫힌 계획",level:"work",evidence:["pr:https://example/pull/2"]},{section:"today",path:["개발","열린 리뷰"],topic:"현재 열린 작업",level:"work",evidence:["pr:https://example/pull/3"]},{section:"today",path:["업무 자동화","추가 일정"],topic:"사용자 추가 일정",level:"request",evidence:["pr:https://example/pull/2","note:0"]}]} | validate_draft($s;{held:[],today:["사용자 추가 일정"]}) | (.items|map(.topic))==["현재 열린 작업","사용자 추가 일정"] and ([render_text]|join("\n") | contains("현재 열린 작업") and contains("사용자 추가 일정") and (contains("닫힌 계획")|not))' >/dev/null || fail 'Merged-only plan retained or surviving tree references corrupted'
require_gh_stub; require_omp_stub
"$repo/bin/scrum-draft" --date 2026-09-28
result="$out/2026-09-28.draft.json"
# "원문 주제" cites only a nonexistent commit: it leaves the draft and survives as questions.
jq -e 'def it($t): [.items[]|select(.topic==$t)]; it("요청 대응")[0].text=="요청 대응 (검토)" and it("요청 대응")[0].level=="request" and it("제품")[0].text=="제품 (확인 필요)" and it("제품")[0].level=="work" and (it("원문 주제")|length)==0 and any(.questions[];contains("원문 주제") and contains("존재하지 않는 근거")) and any(.questions[];contains("원문 주제") and contains("초안에서 제외")) and (it("결제 API")|map(.level)|sort)==["deployed","verified"] and (it("결제 API")|map(.text)|sort)==["결제 API (운영 배포)","결제 API (확인)"] and it("요청")[0].level=="request" and it("프로덕션 반영 완료")==[] and any(.questions[];contains("프로덕션 반영 완료")) and it("리뷰 대응")[0].text=="리뷰 대응 (병합)"' "$result" >/dev/null || fail 'Evidence levels or unsupported completion filtering regressed'
# Current state overrides stale merged state.
jq '.items=[{section:"yesterday",path:["개발","PR"],topic:"PR",level:"merged",evidence:["pr:https://example/pull/1"]}]' "$MODEL_JSON" > "$sandbox/current-model.json"
cp "$out/2026-09-28.json" "$sandbox/collected.json"
jq '.prs[0].current={state:"OPEN"}' "$sandbox/collected.json" > "$out/2026-09-28.json"
MODEL_JSON="$sandbox/current-model.json" "$repo/bin/scrum-draft" --date 2026-09-28
jq -e '.items[0].level=="work" and (.items[0].text|endswith("(확인 필요)"))' "$result" >/dev/null || fail 'Stale PR merge promoted'
cp "$sandbox/collected.json" "$out/2026-09-28.json"
rm "$OMP_COUNT"
OMP_BAD=once "$repo/bin/scrum-draft" --date 2026-09-28
[[ $(cat "$OMP_COUNT") == 2 ]] || fail 'Malformed JSON not retried exactly once'
rm "$OMP_COUNT"
if OMP_BAD=always "$repo/bin/scrum-draft" --date 2026-09-28 > /dev/null 2>&1; then fail 'Invalid JSON accepted twice'; fi
[[ $(cat "$OMP_COUNT") == 2 ]] || fail 'JSON failure retry limit'
cat > "$out/notes.md" <<'NOTES'
## 보류
- 보류 기능
- 서포트 알림
-   
## 오늘 추가
- 메모 계획
- 보류 기능
## 표현 선호
- 짧은 명사형
NOTES
: > "$CALLS"
"$repo/bin/scrum-draft" --date 2026-09-28 --no-llm
[[ ! -s $CALLS ]] || fail '--no-llm called an external source'
jq -e '. as $d | any(.items[];.held==true and (.text|endswith("보류)"))) and all(.today[]|..|objects|select(has("item")); $d.items[.item].text|contains("보류")|not)' "$result" >/dev/null || fail 'Held items remained in today'
jq -e 'any(.items[];.topic=="메모 계획" and .text=="메모 계획") and (.yesterday[0].children|map(.label)|length)==(.yesterday[0].children|map(.label)|unique|length)' "$result" >/dev/null || fail 'Notes text lost or duplicate categories'
jq -e '. as $d | any(.items[];.section=="yesterday" and .topic=="feat: 서포트  알림 슬랙 연동" and .held==true and (.text|endswith("보류)"))) and any(.today[]|..|objects|select(has("item")); $d.items[.item] | (.topic|contains("서포트")) and .held==false) and all(.questions[];startswith("feat: 서포트")|not)' "$result" >/dev/null || fail 'Full-memo yesterday hold or non-exact today visibility regressed'
# Unknown top-level fields are discarded; only validated items determine the rendered tree.
jq '. + {yesterday:[{label:"가짜 운영 배포 완료",children:[]}],questions:["모델 질문"]}' "$MODEL_JSON" > "$sandbox/unsafe-tree.json"
MODEL_JSON="$sandbox/unsafe-tree.json" "$repo/bin/scrum-draft" --date 2026-09-28 > /dev/null
if grep -Eq '가짜 운영 배포 완료|모델 질문' "$out"/2026-09-28.draft.*; then fail 'Unknown model keys affected the rendered draft'; fi
jq '.items=[{section:"yesterday",path:["개발","정보"],topic:"token=output-secret",level:"work",evidence:["git:abc123"]}]' "$MODEL_JSON" > "$sandbox/secret-model.json"
MODEL_JSON="$sandbox/secret-model.json" "$repo/bin/scrum-draft" --date 2026-09-28 > /dev/null
if grep -Fq 'output-secret' "$out"/2026-09-28.draft.*; then fail 'Model output secret leaked'; fi
jq -n '{items:[{section:"yesterday",path:["개발","동의어"],topic:"프로덕션 반영 완료",level:"request",evidence:["session:request"]},{section:"yesterday",path:["개발","운영 반영 완료"],topic:"작업 메모",level:"work",evidence:["git:abc123"]},{section:"yesterday",path:["릴리즈 완료","설정"],topic:"설정 점검",level:"work",evidence:["git:abc123"]},{section:"yesterday",path:["개발","서비스"],topic:"구현 진행",level:"work",evidence:["git:abc123"]}]}' > "$sandbox/claim-model.json"
for mode in none uncertain all; do
  ROUTINE_DRAFT_MARKERS="$mode" MODEL_JSON="$sandbox/claim-model.json" "$repo/bin/scrum-draft" --date 2026-09-28 > /dev/null
  jq -e '. as $draft | (.items|map(.topic))==["구현 진행"] and all(["프로덕션 반영 완료","작업 메모","설정 점검"][];. as $topic|any($draft.questions[];contains($topic)))' "$result" >/dev/null || fail "Unsupported completion leaked in $mode mode"
  jq -Rse 'contains("프로덕션 반영 완료") or contains("운영 반영 완료") or contains("릴리즈 완료") | not' "$out/2026-09-28.draft.txt" "$out/2026-09-28.draft.html" >/dev/null || fail 'Dropped completion remained in the delivery text/HTML'
done
jq -L "$repo/share" -ne 'include "scrum"; ["운영 배포 완료되면 공유 부탁드려요","운영 배포 완료됐나요?","운영 배포 완료 여부 아직 모름","Argo sync 후 Healthy 되면 알려주세요","운영 배포 완료 전입니다","운영 배포 완료 후 공유하겠습니다","운영 배포 완료 예상 시각 15시","운영 배포 완료 목표: 금요일","Argo Synced 아님","Argo OutOfSync에서 Synced 대기 중","운영 배포 완료라고 들었습니다"] | all(.[]; report_proves("deployed")|not)' >/dev/null || fail 'Deployment request or incomplete status accepted as result'
jq -L "$repo/share" -ne 'include "scrum"; ["운영 확인 결과 공유 부탁드립니다","운영에서 조회 결과 이상 없는지 봐주세요","운영 조회 결과 200이 아님","운영 확인 결과 정상인지 모르겠음","운영 조회 결과 정상 응답 대기","운영 확인 결과 정상인지 확인했습니다","✅ 서포트 알림: 정상인지 확인","✅ 서포트 알림: 정상 응답 대기","✅ 서비스가 정상이라면 4건 모두 발송","✅ 정상인 경우 발송 완료","✅ 교착 없어야 4건 모두 발송","✅ 검증 완료면 4건 모두 발송","✅ 서포트 알림"] | all(.[]; report_proves("verified")|not)' >/dev/null || fail 'Uncertain, conditional or incomplete result accepted'
jq -L "$repo/share" -ne 'include "scrum"; ["운영 배포 완료했습니다. 화면 정상","운영 배포 완료됨","운영 배포했습니다","운영 반영했습니다","운영 배포 확인했습니다","Argo sync Synced Healthy 확인"] | all(.[]; report_proves("deployed"))' >/dev/null || fail 'Explicit deployment result rejected'
jq -L "$repo/share" -ne 'include "scrum"; ["운영 조회 결과 200 정상 확인했습니다","운영 확인 완료됨","운영 조회 완료했습니다","운영 확인 결과 정상입니다","서비스가 이상 없이 진행되었습니다","서포트 알림 모두 정상","서포트 알림 정상 확인","**서포트 알림 정상입니다**","## ✅ 9월 랭킹 투표 종료, 10월 오픈, 미션 반영 모두 정상","## 16:00 동시 오픈 — ✅ 교착 없이 4건 모두 발송"] | all(.[]; report_proves("verified"))' >/dev/null || fail 'Asserted normal or checkmarked result rejected'
jq '.items=[{section:"today",path:["배포","배포 준비"],topic:"다음: 배포 준비",level:"request",evidence:["session:request"]}]' "$MODEL_JSON" > "$sandbox/today-deploy.json"
MODEL_JSON="$sandbox/today-deploy.json" "$repo/bin/scrum-draft" --date 2026-09-28 > /dev/null
jq -e '.items[0].text=="다음: 배포 준비" and .today[0].children[0].children[0].label=="배포 준비" and .questions==[]' "$result" >/dev/null || fail 'Today deployment plan mistaken for completion'
jq '.items=[{section:"yesterday",path:["배포","다른 기능"],topic:"다른 기능",level:"verified",evidence:["session:deploy"]}]' "$MODEL_JSON" > "$sandbox/unrelated.json"
MODEL_JSON="$sandbox/unrelated.json" "$repo/bin/scrum-draft" --date 2026-09-28 > /dev/null
jq -e '.items[0].level=="verified" and (.items[0].text|contains("확인 필요")) and any(.questions[];contains("증거 주제 확인"))' "$result" >/dev/null || fail 'Unrelated evidence lacked visible qualification'
jq -L "$repo/share" -ne 'include "scrum"; "## 보류\n-   \n- 정산  개선 작업"|notes_data|.held==["정산 개선 작업"]' >/dev/null || fail 'Blank held note retained'
jq -L "$repo/share" --slurpfile source "$out/2026-09-28.json" -ne 'include "scrum"; {items:[{section:"yesterday",path:["개발","정산"],topic:"정산 개선 작업",level:"request",evidence:["note:0"],held_ref:0},{section:"today",path:["개발","정산"],topic:"정산 개선 작업",level:"request",evidence:["note:0"],held_ref:0}]} | validate_draft($source[0];{held:["정산 개선 작업"],today:["정산 개선 작업"]}) | .today==[] and any(.items[];.section=="yesterday" and .held==true) and .questions==[]' >/dev/null || fail 'Explicit neutral hold was excluded or questioned'
jq -L "$repo/share" --slurpfile source "$out/2026-09-28.json" -ne 'include "scrum"; {items:[{section:"today",path:["개발","서포트"],topic:"서포트 슬랙 버그",level:"request",evidence:["session:request"]}]} | validate_draft($source[0];{held:["서포트 알림"],today:[]}) | .items[0].held==false and (.today|length)==1 and any(.questions[];contains("보류 항목 매칭 확인"))' >/dev/null || fail 'Ambiguous partial held match silently excluded'
chmod 644 "$out"/2026-09-28.draft.*
"$repo/bin/scrum-draft" --date 2026-09-28 --no-llm > /dev/null
for suffix in json html txt questions.md; do [[ $(stat -f %Lp "$out/2026-09-28.draft.$suffix") == 600 ]] || fail 'Existing draft remained world-readable'; done
# Timestamp-before-body and body-before-timestamp both select only the current message.
cat > "$sandbox/mixed-tree" <<'TREE'
[10] link [어제, 오전 8:00:01](https://slack.example/yesterday)
[11] container, Text: 스크럼-예제팀: 예제팀
[12] 버튼 3개의 댓글
[20] link [오늘, 오전 8:03:01](https://slack.example/today)
[21] container, Text: 스크럼-예제팀: 예제팀
[22] 버튼 2개의 댓글
[30] link [오늘, 오전 9:00:01](https://slack.example/notice)
[31] container, Text: 공지
[32] 버튼 5개의 댓글
TREE
jq -L "$repo/share" -Rse 'include "slack"; scrum_block|.reply==22' "$sandbox/mixed-tree" >/dev/null || fail 'Mixed date messages selected wrong reply'
cat > "$sandbox/ambiguous-tree" <<'TREE'
[10] container, Text: 스크럼-예제팀: 예제팀
[11] link [오늘, 오전 8:01:01](https://slack.example/today)
[12] 버튼 3개의 댓글
[13] 버튼 4개의 댓글
TREE
if jq -L "$repo/share" -Rs 'include "slack"; scrum_block' "$sandbox/ambiguous-tree" > /dev/null 2>&1; then fail 'Multiple reply buttons accepted'; fi
# Current Orca prints bare indexes ("212 container"); the hovered post wraps its body in a titled container.
printf '%s\n' \
  '\t\t\t196 container' '\t\t\t\t200 link [오늘, 오전 8:00:08](https://slack.example/design)' '\t\t\t\t202 버튼 3개의 댓글' \
  '\t\t\t212 container 스크럼-예제팀: 예제팀 일일 업무를 작성해주세요.' '\t\t\t\t213 container' \
  '\t\t\t\t\t217 link [오늘, 오전 8:00:09](https://slack.example/product)' '\t\t\t\t\t219 버튼 3개의 댓글' \
  '\t221 container' | sed 's/\\t/\t/g' > "$sandbox/bare-index-tree"
jq -L "$repo/share" -Rse 'include "slack"; scrum_block|.reply==219 and .container==212' "$sandbox/bare-index-tree" >/dev/null || fail 'Bare-index Orca tree not recognized'
# The root may be off screen, but every visible reply must carry its thread_ts.
printf '%s\n' \
  '\t266 container daily-scrum 채널의 스레드' '\t\t273 내용 목록 daily-scrum의 스레드 (채널, 12개의 댓글)' \
  '\t\t\t276 버튼 동료_사용자' '\t\t\t278 link [오늘, 오전 9:15:07. 채널에서 열기](https://slack.example/archives/C1/p1790900107945519?thread_ts=1790895609.247049&cid=C1)' \
  '\t\t\t310 link [오늘, 오전 9:50:50. 채널에서 열기](https://slack.example/archives/C1/p1790902250238009?thread_ts=1790895609.247049&cid=C1)' \
  '\t\t412 텍스트 엔트리 영역 (settable) daily-scrum 스레드에 댓글 남기기' \
  '\t\t416 체크박스 (settable) daily-scrum(으)로도 전송, Value: 0' '\t430 팝업 버튼 사용자: 테스트_사용자' | sed 's/\\t/\t/g' > "$sandbox/hidden-root-thread"
for root in p1790895609247049 p1790895608539999; do
  expected=true; [[ $root != p1790895608539999 ]] || expected=false
  jq -L "$repo/share" -Rse --arg root "$root" --argjson expected "$expected" 'include "slack"; thread_identified("https://slack.example/archives/C1/"+$root)==$expected' "$sandbox/hidden-root-thread" >/dev/null || fail 'Visible reply thread_ts did not identify the correct root'
done
jq -L "$repo/share" -Rse 'include "slack"; sub("daily-scrum\\(으\\)로도 전송";"(으)로도 전송 daily-scrum") | (try broadcast_checkbox catch null)==null' "$sandbox/hidden-root-thread" >/dev/null || fail 'Reordered channel broadcast label accepted'
jq -L "$repo/share" -Rse 'include "slack"; (own_comment|not) and thread_editor.value==""' "$sandbox/hidden-root-thread" >/dev/null || fail 'Account menu taken as own comment or empty settable editor rejected'
sed 's/버튼 동료_사용자/버튼 테스트_사용자/' "$sandbox/hidden-root-thread" | jq -L "$repo/share" -Rse 'include "slack"; own_comment' >/dev/null || fail 'Own visible comment missed'
jq -L "$repo/share" -e 'include "slack"; tree_text|thread_identified("https://example.slack.com/archives/CEXAMPLE/p1790895609247049")' "$FIXTURES/slack-thread-partial.json" >/dev/null || fail 'Root-visible partial thread rejected'
jq -L "$repo/share" -ne 'include "slack"; ["link [오늘, 오전 8:00](https://slack.example/p1)","link [어제, 오후 10:03:01](https://slack.example/p2)","link [9월 28일, 오전 8:01](https://slack.example/p3)"]|all(.[];timestamp_link)' >/dev/null || fail 'Exact timestamp link rejected'
jq -L "$repo/share" -ne 'include "slack"; ["link [오늘 배포 오전 8:00](https://slack.example/task)","link [작업 8:00](https://slack.example/task)","link [금요일, 오전 8:00](https://slack.example/task)"]|all(.[];timestamp_link|not)' >/dev/null || fail 'Arbitrary time mention treated as message timestamp'
# Prioritize result reports, preserve recent context and isolate each indexed proof.
cat > "$ROUTINE_OMP_SESSIONS/one/report.jsonl" <<'SESSION'
{"type":"session","id":"report","timestamp":"2026-09-25T00:00:00Z","cwd":"/fixture"}
{"type":"message","timestamp":"2026-09-25T01:00:00Z","message":{"role":"user","content":"요청"}}
{"type":"message","timestamp":"2026-09-25T02:00:00Z","message":{"role":"assistant","content":[{"type":"text","text":"오래된 보고"}]}}
SESSION
printf -v padding '%01495d' 0
jq -nc --arg text "$padding AKIAIOSFODNN7EXAMPLE tail" '{type:"message",timestamp:"2026-09-25T03:00:00Z",message:{role:"assistant",content:[{type:"text",text:$text},{type:"toolCall",name:"ignored"},{type:"text",text:"끝"}]}}' >> "$ROUTINE_OMP_SESSIONS/one/report.jsonl"
printf -v report_padding '%0995d' 0
jq -nc --arg text "$report_padding AKIAIOSFODNN7EXAMPLE tail" '{type:"message",timestamp:"2026-09-25T02:30:00Z",message:{role:"assistant",content:$text}}' >> "$ROUTINE_OMP_SESSIONS/one/report.jsonl"
cat > "$ROUTINE_OMP_SESSIONS/one/history.jsonl" <<'SESSION'
{"type":"session","id":"history","title":"운영 현황","timestamp":"2026-09-25T00:00:00Z","cwd":"/fixture"}
{"type":"message","timestamp":"2026-09-25T02:10:00Z","message":{"role":"assistant","content":"## 16:00 동시 오픈 — ✅ 교착 없이 4건 모두 발송\n\n| 서포트 | 대상 |\n|---|---|\n| 알림 A | 4 |\n\n- **4건 모두 시도 1회로 완료**, 교착 0건\n남은 일: 운영 로그 정리"}}
{"type":"message","timestamp":"2026-09-25T02:10:00Z","message":{"role":"assistant","content":"## ✅ 9월 랭킹 투표 종료, 10월 오픈, 미션 반영 모두 정상"}}
{"type":"message","timestamp":"2026-09-25T02:40:00Z","message":{"role":"assistant","content":"다음 단계: 모니터링 자료 정리"}}
SESSION
printf '%s\n' '{"type":"session","id":"budget","timestamp":"2026-09-25T00:00:00Z","cwd":"/fixture"}' > "$ROUTINE_OMP_SESSIONS/one/budget.jsonl"
printf -v report_padding '%01200d' 0
for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13; do
  printf -v minute '%02d' "$i"
  label="최근 대화$i"; ((i>=10)) || label="확인 결과 보고$i"
  jq -nc --arg ts "2026-09-25T12:$minute:00Z" --arg text "$label $report_padding" '{type:"message",timestamp:$ts,message:{role:"assistant",content:$text}}' >> "$ROUTINE_OMP_SESSIONS/one/budget.jsonl"
done
printf '%s\n' '{"type":"message","timestamp":"2026-09-25T12:14:00Z","message":{"role":"assistant","content":[{"type":"toolCall","name":"ignored"}]}}' >> "$ROUTINE_OMP_SESSIONS/one/budget.jsonl"
printf '%s\n' '{"type":"message","timestamp":"2026-09-29T00:00:00Z","message":{"role":"assistant","content":"창 밖 보고"}}' >> "$ROUTINE_OMP_SESSIONS/one/report.jsonl"
"$repo/bin/scrum-collect" --sources sessions --out "$sandbox/collect"
collected="$sandbox/collect/2026-09-28.json"
jq -e '.sessions[]|select(.id=="report")|(.latest_report|length)==1500 and (.latest_report|endswith("[RED")) and (.latest_report|contains("AKIA")|not) and (.reports|length)==3 and .reports[0].text=="오래된 보고" and (.reports[1].text|length)==1000 and (.reports[1].text|endswith("[RED")) and all(.reports[];.text|contains("AKIA")|not) and all(.reports[];.text|contains("창 밖")|not)' "$collected" >/dev/null || fail 'Reports window or redact-before-truncate contract'
jq -e '.sessions[]|select(.id=="budget")|(.reports|length)==10 and ([.reports[].text|length]|add)==6000 and all(.reports[];(.text|length)<=1000) and (.reports[0].text|startswith("확인 결과 보고4 ")) and (.reports[5].text|startswith("확인 결과 보고9 ")) and (.reports[6].text|startswith("최근 대화10 ")) and (.reports[9].text|startswith("최근 대화13 ")) and (.latest_report|startswith("최근 대화13 "))' "$collected" >/dev/null || fail 'Prioritized result reports or recent context lost'
jq -e '.sessions[]|select(.id=="history")|(.reports|length)==3 and .reports[0].ts==.reports[1].ts and .reports[0].text!=.reports[1].text' "$collected" >/dev/null || fail 'Selection duplicated a report or discarded a distinct same-time message'
jq -L "$repo/share" --slurpfile source "$collected" -ne 'include "scrum"; {items:[{section:"yesterday",path:["현황 파악","서포트"],topic:"서포트 알림",level:"verified",evidence:["session:history#0"]},{section:"yesterday",path:["배포","랭킹"],topic:"랭킹 투표",level:"verified",evidence:["session:history#1"]},{section:"yesterday",path:["개발","검토 자료"],topic:"서포트 알림 상태",level:"verified",evidence:["session:history#2"]}]} | validate_draft($source[0];{held:[],today:[]}) | .items[0].text=="서포트 알림 (확인)" and .items[1].text=="랭킹 투표 (확인)" and .items[2].level=="request" and .items[2].text=="서포트 알림 상태 (검토, 확인 필요)"' >/dev/null || fail 'Indexed report borrowed another message or buried completed result'
jq -L "$repo/share" --slurpfile source "$collected" -ne 'include "scrum"; {items:[{section:"yesterday",path:["배포","랭킹"],topic:"랭킹 투표 종료",level:"verified",evidence:["session:history#1"]}]} | validate_draft($source[0];{held:[],today:[]}) | .items[0].topic=="랭킹 투표 종료" and .items[0].level=="verified" and .questions==[]' >/dev/null || fail 'Supported completion topic downgraded or created redundant question'
jq -L "$repo/share" -e 'include "scrum"; . as $source | {held:[],today:[]} as $notes | summary_draft($notes) | validate_draft($source;$notes) | [.items[]|select(.section=="today")|{topic,evidence,text}]==[{topic:"남은 일: 운영 로그 정리",evidence:["session:history#0"],text:"남은 일: 운영 로그 정리"},{topic:"다음 단계: 모니터링 자료 정리",evidence:["session:history#2"],text:"다음 단계: 모니터링 자료 정리"}]' "$collected" >/dev/null || fail 'Today plan did not use per-report next steps'
: > "$CALLS"
if ROUTINE_ALLOW_GUI=0 "$repo/bin/scrum-collect" --sources slack --out "$sandbox/collect"; then fail 'Skipped-only GUI source should fail'; fi
jq -e '.sources.slack==false and .slack==[] and .errors==[{source:"slack",message:"GUI source skipped"}]' "$sandbox/collect/2026-09-28.json" >/dev/null || fail 'GUI skip not recorded'
[[ ! -s $CALLS ]] || fail 'GUI skip invoked a command'
require_gui_stubs
ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-collect" --sources slack --since 2026-09-25 --out "$sandbox/collect"
jq -e '.slack==[{ts_text:"금요일, 오전 9:00",url:"https://slack.example/archives/C1/p1790294400000000",channel:"#제품",text:"운영 배포 완료 [REDACTED]"},{ts_text:"금요일, 오전 9:05",url:"https://slack.example/archives/C1/p1790294700000000",channel:"#개발",text:"다음 작업"}] and .errors==[]' "$sandbox/collect/2026-09-28.json" >/dev/null || fail 'Slack first page parse or redact'
! grep -q 'press-key' "$CALLS" || fail 'Preferred suggestion sent Return'
[[ $(cat "$STAGE.query") == 'from:me after:2026-09-24' ]] || fail 'Collection query changed'
SEARCH_MODE=no-channel-label ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-collect" --sources slack --out "$sandbox/collect"
jq -e '.sources.slack==true and (.slack|map(.channel))==["",""] and (.slack|map(.text))==["운영 배포 완료 [REDACTED]","다음 작업"]' "$sandbox/collect/2026-09-28.json" >/dev/null || fail 'Absent search channel labels failed collection'
: > "$CALLS"
SEARCH_MODE=prior ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-collect" --sources slack --out "$sandbox/collect"
jq -e '.sources.slack==true and (.slack|map(.url))==["https://slack.example/archives/C1/p1790294400000000","https://slack.example/archives/C1/p1790294700000000"]' "$sandbox/collect/2026-09-28.json" >/dev/null || fail 'Prior search or background channel contaminated collection'
grep -q 'click .*--element-index 6 ' "$CALLS" || fail 'Search term not cleared'
[[ $(cat "$STAGE") == channel ]] || fail 'Collection did not return to channel'
SEARCH_MODE=cutoff ROUTINE_COLLECT_UNTIL=today_start ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-collect" --sources slack --out "$sandbox/collect"
jq -e '(.slack|map(.url))==["https://slack.example/archives/C1/p1790294400000000","https://slack.example/archives/C1/p1790294700000000"] and .window.until=="2026-09-27T15:00:00Z" and .errors==[]' "$sandbox/collect/2026-09-28.json" >/dev/null || fail 'Slack search leaked today-midnight activity into yesterday'
SEARCH_MODE=malformed-url ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-collect" --sources slack --out "$sandbox/collect"
jq -e '(.slack|map(.text))==["운영 배포 완료 [REDACTED]","다음 작업"] and (.errors|map(.source))==["slack"]' "$sandbox/collect/2026-09-28.json" >/dev/null || fail 'Malformed Slack timestamp was silently discarded or valid messages were lost'
: > "$CALLS"
SEARCH_MODE=fallback ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-collect" --sources slack --out "$sandbox/collect"
grep -q 'press-key.*Return' "$CALLS" || fail 'Focused search fallback not exercised'
: > "$CALLS"
if SEARCH_MODE=unsafe ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-collect" --sources slack --out "$sandbox/collect"; then fail 'Unsafe search fallback succeeded'; fi
! grep -q 'press-key' "$CALLS" || fail 'Unsafe search focus sent Return'
SEARCH_MODE=empty ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-collect" --sources slack --out "$sandbox/collect"
jq -e '.sources.slack==true and .slack==[] and .errors==[]' "$sandbox/collect/2026-09-28.json" >/dev/null || fail 'Empty Slack success treated as absent evidence'
: > "$CALLS"
SEARCH_MODE=loading ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-collect" --sources slack --out "$sandbox/collect"
[[ $(cat "$STAGE.search.polls") == 3 && $(cat "$STAGE.combo.polls") == 3 && $(cat "$STAGE.query.polls") == 3 ]] || fail 'Delayed search/combo/suggestion not polled'
jq -e '.sources.slack==true and (.slack|length)==2' "$sandbox/collect/2026-09-28.json" >/dev/null || fail 'Delayed Slack UI discarded collected activity'
: > "$CALLS"
if SEARCH_MODE=never-search ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-collect" --sources slack --out "$sandbox/collect"; then fail 'Missing search target succeeded'; fi
[[ $(cat "$STAGE.search.polls") == 5 && $(grep -c '^orca computer click' "$CALLS") == 0 ]] || fail 'Search polling exceeded bound or clicked missing target'
# Missing daily JSON in --no-llm collects only local sources, never gh/GUI/omp.
: > "$CALLS"
"$repo/bin/scrum-draft" --date 2026-09-28 --out "$sandbox/local-only" --no-llm
[[ ! -s $CALLS ]] || fail 'Missing JSON local mode called external tools'
# The paste path backs up and restores even when paste or screenshot fails.
for mode in normal zero reply-label workflow loading fail-v screenshot-fail; do
  printf 'original clipboard\n' > "$CLIPBOARD"; cp "$CLIPBOARD" "$sandbox/original"
  : > "$CALLS"
  require_gui_stubs
  if PASTE_MODE=$mode ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-paste" --no-draft > "$sandbox/paste-output" 2> "$sandbox/paste-error"; then
    [[ $mode == normal || $mode == zero || $mode == reply-label || $mode == workflow || $mode == loading ]] || fail 'Expected paste failure'
  else [[ $mode == fail-v || $mode == screenshot-fail ]] || { cat "$sandbox/paste-error" >&2; fail "Paste failed: $mode"; }; fi
  cmp -s "$CLIPBOARD" "$sandbox/original" || fail "Clipboard not restored: $mode"
  ! grep -Eq 'press-key|--element-index (99|100)' "$CALLS" || fail 'Paste sent a key or clicked Send'
  jq -Rn '[inputs] | (map(test("click.*--element-index (31|33|61)"))|index(true)) as $reply | (map(test("click.*--element-index 44"))|index(true)) as $editor | (map(test("hotkey.*Cmd\\+V"))|index(true)) as $paste | $reply!=null and $editor!=null and $paste!=null and $reply<$editor and $editor<$paste' < "$CALLS" | grep -Fxq true || fail 'Reply/editor/paste action sequence missing'
  if [[ $mode == zero || $mode == reply-label ]]; then ! grep -q 'set-value' "$CALLS" || fail 'Zero-comment post searched'; fi
done
for mode in old duplicate delayed-duplicate nonempty no-reply multi wrong-root wrong-url never-ready initially-checked checkbox-click checkbox-paste background changed-target; do
  printf 'original clipboard\n' > "$CLIPBOARD"; cp "$CLIPBOARD" "$sandbox/original"; : > "$CALLS"
  if PASTE_MODE=$mode ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-paste" --no-draft > "$sandbox/abort-output" 2> "$sandbox/abort-error"; then fail "Unsafe target accepted: $mode"; fi
  cmp -s "$CLIPBOARD" "$sandbox/original" || fail "Abort touched clipboard: $mode"
  if [[ $mode != checkbox-paste ]]; then ! grep -q 'hotkey' "$CALLS" || fail "Abort pasted: $mode"; fi
  if [[ $mode == wrong-root || $mode == wrong-url || $mode == never-ready ]]; then [[ $(cat "$STAGE.polls") == 8 ]] || fail "Unready thread was not retried until timeout: $mode"; fi
done
# Unrecognised Slack screens leave a redacted structure capture plus the per-poll trace.
capture_dir="$HOME/Library/Logs/routine-automation/slack-format"
rm -rf -- "$capture_dir"; mkdir -p "$capture_dir"
# 25 older captures and a user file: only our 20 newest names survive, the user file is untouched.
for n in $(seq -w 1 25); do printf 'old\n' > "$capture_dir/20200101-0000$n-1.txt"; done
printf 'mine\n' > "$capture_dir/notes.txt"
if PASTE_MODE=wrong-url ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-paste" --no-draft > /dev/null 2>&1; then fail 'Unrecognised thread accepted'; fi
new_capture=$(grep -L '^old$' "$capture_dir"/[0-9]*-[0-9]*-[0-9]*.txt)
[[ -n $new_capture && $new_capture != *$'\n'* ]] || fail 'Format failure left no single structure capture'
[[ $(stat -f %Lp "$new_capture") == 600 && $(stat -f %Lp "$capture_dir") == 700 ]] || fail 'Structure capture permissions'
captures=("$capture_dir"/[0-9]*-[0-9]*-[0-9]*.txt)
[[ ${#captures[@]} == 20 && ! -e $capture_dir/20200101-000001-1.txt && -e $capture_dir/20200101-000025-1.txt && -e $capture_dir/notes.txt ]] || fail 'Structure capture retention'
! grep -q '예제팀: 예제팀' "$new_capture" || fail 'Structure capture kept message text'
grep -q '^\[46\] link \[오늘' "$new_capture" || fail 'Structure capture dropped thread links'
if ! grep -q '^# 폴링 추적' "$new_capture" || ! grep -q '^poll 8: state=성공 root_match=' "$new_capture"; then fail 'Structure capture lacks the poll trace'; fi
[[ -z $(find "$capture_dir" -name '*.tmp') ]] || fail 'Structure capture left a temporary file'
# Masking is the default: names, non-timestamp links, URL secrets, other hosts/channels, unknown roles
# and wrapped values never survive; organisation identifiers become placeholders.
sensitive='{"result":{"snapshot":{"treeText":"0 표준 윈도우 ch(채널) - 회사명 - Slack\n\t1 container 홍길동: 작업 비밀내용\n\t2 link [회사 비밀 문서](https://x.example/doc?token=abc)\n\t3 link [오늘, 오전 8:00:10](https://acme.slack.com/archives/C1/p1?thread_ts=1.2&cid=C1&secret=z)\n\t3 link [오늘, 오전 8:00](https://evil.example/홍길동/비밀#frag)\n\t4 버튼 홍길동\n\t5 버튼 3개의 댓글\n\t6 팝업 버튼 사용자: 홍길동\n\t7 텍스트, Value: 워크플로\n\t8 체크박스 (settable) ch(으)로도 전송, Value: 0\n\t9 container, Text: 비밀 본문\n\t10 container 스크럼-팀: 팀 일일 업무 비밀\n\t11 내용 목록 ch의 스레드 (채널, 12개의 댓글)\n\t11 내용 목록 ch (채널 홍길동 비밀문서 (채널)\n\t12 텍스트 엔트리 영역 (settable) ch 스레드에 댓글 남기기, Value: 비밀 초안\n\t13 알수없는역할 홍길동\n\t\t010 1234 홍길동 연락처\n\t14 내용 목록 다른채널 (채널)"}}}'
dump=$(command jq -L "$repo/share" -nr --argjson routine '{"slack":{"channel_name":"ch","post_title":"스크럼-팀","workspace_domain":"acme","channel_id":"C1"}}' --argjson s "$sensitive" 'include "slack"; $s|tree_text|structure_dump' 2>&1) || fail "Structure dump failed: $dump"
! grep -qE '홍길동|비밀|회사명|token|secret|워크플로|다른채널|acme|C1|evil|1234|010' <<< "$dump" || fail 'Structure dump leaked text, names, identifiers or URL secrets'
for kept in '버튼 3개의 댓글' 'link [오늘, 오전 8:00:10](https://⟨workspace⟩.slack.com/archives/⟨channel⟩/p1?thread_ts=1.2)' 'Value: 0' 'container ⟨post_title⟩: ' '내용 목록 ⟨channel_name⟩의 스레드 (채널, 12개의 댓글)'; do
  grep -qF "$kept" <<< "$dump" || fail "Structure dump lost structure: $kept"
done
for option in force replace; do
  mode=duplicate; [[ $option != replace ]] || mode=nonempty
  printf 'original clipboard\n' > "$CLIPBOARD"; : > "$CALLS"
  PASTE_MODE=$mode ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-paste" --no-draft "--$option" > /dev/null
  [[ $(cat "$CLIPBOARD") == 'original clipboard' ]] || fail 'Override lost clipboard'
  if [[ $option == replace ]]; then grep -q 'hotkey.*Cmd+A' "$CALLS" || fail 'Replacement did not select input'; fi
done
: > "$CALLS"
"$repo/bin/scrum-paste" --dry-run > "$sandbox/dry"
[[ ! -s $CALLS && $(cat "$sandbox/dry") == *'계획:'* ]] || fail 'Dry paste touched GUI'
# Default paste finishes Slack search before accessing the thread composer.
: > "$CALLS"; printf 'original clipboard\n' > "$CLIPBOARD"
SEARCH_MODE=fallback ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-paste" > "$sandbox/default-paste"
jq -Rn '[inputs] | (map(test("click.*--element-index 44"))|index(true)) as $composer | $composer!=null and any(.[:$composer][];test("press-key.*Return")) and all(.[$composer:][];test("press-key.*Return|전송")|not)' < "$CALLS" | grep -Fxq true || fail 'Return reached composer phase'
[[ $(cat "$CLIPBOARD") == 'original clipboard' ]] || fail 'Default paste lost clipboard'
# Unattended runs use deterministic ioreg/date and the existing GUI/model stubs.
cat > "$HOME/.local/bin/date" <<'DATE'
#!/usr/bin/env bash
if [[ ${1-} == -r && ${3-} == '+%H%M' && -n ${AUTO_CLOCK:-} ]]; then echo "$AUTO_CLOCK"
elif [[ ${1-} == +%s && -f $AUTO_EPOCH_FILE ]]; then cat "$AUTO_EPOCH_FILE"
else exec /bin/date "$@"; fi
DATE
cat > "$HOME/.local/bin/perl" <<'PERL'
#!/usr/bin/env bash
[[ ${1-} == -MTime::HiRes=time ]] || exit 87
cat "$AUTO_MS_FILE"
PERL
cat > "$HOME/.local/bin/ioreg" <<'IOREG'
#!/usr/bin/env bash
if [[ $* == '-n Root -d1' ]]; then
  printf '"IOConsoleLocked" = %s\n"IOConsoleUsers" = ({"kCGSSessionUserIDKey"=%s,"kCGSSessionOnConsoleKey"=%s},{"kCGSSessionUserIDKey"=999999,"kCGSSessionOnConsoleKey"=Yes})\n' "${AUTO_LOCKED:-No}" "$(id -u)" "${AUTO_CONSOLE:-Yes}"
elif [[ $* == '-c IOHIDSystem' ]]; then
  count=$(cat "$IDLE_COUNT" 2>/dev/null || echo 0); count=$((count+1)); echo "$count" > "$IDLE_COUNT"
  [[ ${AUTO_BAD_IDLE:-0} != 1 ]] || exit 0
  stamp=$(cat "$AUTO_MS_FILE"); stamp=$((stamp + ${AUTO_TICK_MS:-3000})); echo "$stamp" > "$AUTO_MS_FILE"
  echo "$((stamp/1000))" > "$AUTO_EPOCH_FILE"
  idle=${AUTO_IDLE:-600000000000}
  if [[ ${AUTO_SELF_RESET:-0} == 1 && -f $HID_RESET_EPOCH ]]; then idle=$(((stamp - $(cat "$HID_RESET_EPOCH")) * 1000000)); fi
  if [[ -n ${AUTO_INPUT_AT:-} ]] && ((count >= AUTO_INPUT_AT)); then
    idle=0
    if [[ ! -e $IDLE_COUNT.input ]]; then
      printf 'input-at %s\n' "$count" >> "$CALLS"
      : > "$IDLE_COUNT.input"
    fi
    [[ -z ${AUTO_SWITCH_APP:-} ]] || echo "$AUTO_SWITCH_APP" > "$FOREGROUND"
  fi
  if [[ -n ${AUTO_INPUT_SEARCH_STAGE:-} && $(cat "$STAGE" 2>/dev/null) == "$AUTO_INPUT_SEARCH_STAGE" ]]; then
    idle=0
    if [[ ! -e $IDLE_COUNT.input ]]; then
      printf 'input-in-search %s\n' "$AUTO_INPUT_SEARCH_STAGE" >> "$CALLS"
      : > "$IDLE_COUNT.input"
    fi
  fi
  printf '"HIDIdleTime" = %s\n' "$idle"
else exit 87; fi
IOREG
chmod +x "$HOME/.local/bin/"{date,ioreg,perl}
export IDLE_COUNT="$sandbox/idle-count"
export ROUTINE_NOW='2026-09-28T09:00:00+09:00'
[[ $(command -v ioreg) == "$HOME/.local/bin/ioreg" && $(command -v date) == "$HOME/.local/bin/date" ]] || fail 'Refusing real auto preflight commands'
cp "$result" "$sandbox/auto-draft.json"
auto_reset() {
  rm -f -- "$out"/2026-09-28.paste* "$out/2026-09-28.draft-refresh-attempted" "$IDLE_COUNT" "$HID_RESET_EPOCH"
  rm -f "$IDLE_COUNT.input" "$STAGE.searched" "$STAGE.cleared"
  rm -rf -- "$out/.scrum-paste.lock" "$out/.scrum-paste.recovery.lock"
  cp "$sandbox/auto-draft.json" "$result"
  printf 'original clipboard\n' > "$CLIPBOARD"
  echo com.apple.Terminal > "$FOREGROUND"
  echo channel > "$STAGE"
  /bin/date +%s > "$AUTO_EPOCH_FILE"
  echo "$(($(cat "$AUTO_EPOCH_FILE") * 1000))" > "$AUTO_MS_FILE"
  : > "$CALLS"; : > "$TIMEOUT_CALLS"
}
run_auto() {
  require_gui_stubs; require_omp_stub
  if "$repo/bin/scrum-paste" --auto </dev/null > "$sandbox/auto.stdout" 2> "$sandbox/auto.stderr"; then auto_code=0; else auto_code=$?; fi
  [[ ! -s $sandbox/auto.stdout && ! -s $sandbox/auto.stderr ]] || fail 'Auto output escaped daily log'
}
no_auto_gui() {
  ! grep -Eq '^(orca |open |clipboard |omp |focus )' "$CALLS" || fail "Auto skip touched GUI/model: $1"
  [[ $auto_code == 0 ]] || fail "Auto skip failed: $1"
}
for condition in locked nonconsole idle bad-idle weekend early late pasted skipped attention disabled no-html no-text morning initializing-lock active-lock; do
  auto_reset
  case $condition in
    locked) export AUTO_LOCKED=Yes ;;
    nonconsole) export AUTO_CONSOLE=No ;;
    idle) export AUTO_IDLE=179999999999 ;;
    bad-idle) export AUTO_BAD_IDLE=1 ;;
    weekend) export ROUTINE_NOW='2026-10-10T09:00:00+09:00' ;;
    early) export AUTO_CLOCK=0809 ;;
    late) export AUTO_CLOCK=1131 ;;
    pasted) touch "$out/2026-09-28.pasted" ;;
    skipped) touch "$out/2026-09-28.paste-skipped" ;;
    attention) touch "$out/2026-09-28.paste-attention" ;;
    disabled) touch "$out/../autopaste.disabled" ;;
    no-html) mv "$out/2026-09-28.draft.html" "$sandbox/auto.html" ;;
    no-text) mv "$out/2026-09-28.draft.txt" "$sandbox/auto.txt" ;;
    morning) mkdir -p "$HOME/Library/Logs/routine-automation/.morning.lock"; echo "$$" > "$HOME/Library/Logs/routine-automation/.morning.lock/pid" ;;
    initializing-lock) mkdir "$out/.scrum-paste.lock" ;;
    active-lock) mkdir "$out/.scrum-paste.lock"; echo "$$" > "$out/.scrum-paste.lock/pid" ;;
  esac
  run_auto; no_auto_gui "$condition"
  case $condition in
    no-html) mv "$sandbox/auto.html" "$out/2026-09-28.draft.html" ;;
    no-text) mv "$sandbox/auto.txt" "$out/2026-09-28.draft.txt" ;;
    morning) rm -rf -- "$HOME/Library/Logs/routine-automation/.morning.lock" ;;
    disabled) rm "$out/../autopaste.disabled" ;;
    weekend) export ROUTINE_NOW='2026-09-28T09:00:00+09:00' ;;
  esac
  unset AUTO_LOCKED AUTO_CONSOLE AUTO_IDLE AUTO_BAD_IDLE AUTO_CLOCK
done
# Outside-hours calls do not create an ever-growing daily log.
auto_reset
auto_log="$HOME/Library/Logs/routine-automation/scrum-paste-2026-09-28.log"
rm -f -- "$auto_log"
ROUTINE_NOW='2026-10-10T09:00:00+09:00' run_auto; AUTO_CLOCK=0809 run_auto; AUTO_CLOCK=1131 run_auto
[[ ! -e $auto_log ]] || fail 'Outside-hours calls created a daily log'
auto_reset
echo com.tinyspeck.slackmacgap > "$FOREGROUND"
run_auto
[[ $auto_code == 0 && ! -e $out/2026-09-28.pasted && ! -e $out/2026-09-28.paste-attempts ]] || fail 'Initially foreground Slack was manipulated/completed'
! grep -Eq '^open |^orca |^focus restore' "$CALLS" || fail 'Initially foreground Slack triggered GUI manipulation'
for clock in 0810 1130; do
  auto_reset
  AUTO_CLOCK=$clock AUTO_IDLE=180000000000 AUTO_SELF_RESET=1 run_auto
  [[ $auto_code == 0 && -s $out/2026-09-28.pasted && ! -e $out/.scrum-paste.lock ]] || fail "Self-reset-safe success missing at boundary $clock"
  grep -Fq 'screenshot=/tmp/stub-screenshot.png' "$out/2026-09-28.pasted" || fail 'Success omitted screenshot'
  grep -Fq '확인 후 전송하세요' "$CALLS" || fail 'Success notice missing'
  [[ $(cat "$CLIPBOARD") == 'original clipboard' && $(cat "$FOREGROUND") == com.apple.Terminal ]] || fail 'Auto success lost clipboard/foreground'
  ! grep -Eq 'press-key|--element-index (99|100)' "$CALLS" || fail 'Auto paste sent message'
  grep -q '^-k 30 900 /bin/bash .*scrum-paste --auto$' "$TIMEOUT_CALLS" || fail 'Complete auto execution lacks 900-second timeout'
  : > "$CALLS"; run_auto; no_auto_gui completed
done
for mode in duplicate nonempty; do
  auto_reset
  PASTE_MODE=$mode run_auto
  [[ $auto_code == 3 && -s $out/2026-09-28.paste-skipped && ! -e $out/2026-09-28.pasted ]] || fail "Terminal result not recorded: $mode"
  ! grep -Eq 'hotkey|notification .*--(force|replace)' "$CALLS" || fail 'Auto terminal pasted or suggested unavailable override'
  [[ $(grep -c '^notification ' "$CALLS") == 1 && $(cat "$FOREGROUND") == com.apple.Terminal ]] || fail 'Terminal notice/focus restore incorrect'
  : > "$CALLS"; PASTE_MODE=$mode run_auto; no_auto_gui terminal
  [[ ! -s $CALLS ]] || fail 'Terminal repeat notified again'
done
# Prove each guard precedes the mutation, not merely Cmd+V.
for input_at in 2 3 4 5 6; do
  auto_reset
  AUTO_SELF_RESET=1 AUTO_INPUT_AT=$input_at run_auto
  [[ $auto_code == 4 && ! -e $out/2026-09-28.pasted && ! -e $out/2026-09-28.paste-skipped && ! -e $out/2026-09-28.paste-attention ]] || fail "Input intervention not retryable: $input_at"
  jq -Rse --arg marker "input-at $input_at" 'split("\n") as $calls | ($calls|index($marker)) as $input | $input!=null and all($calls[$input+1:][]; test("^open |^orca computer (click|hotkey|set-value|press-key)")|not)' "$CALLS" >/dev/null || fail "Mutation ran after input guard: $input_at"
  ! grep -q 'hotkey.*Cmd+V' "$CALLS" || fail "Pasted after input intervention: $input_at"
  expected_front=com.tinyspeck.slackmacgap
  if ((input_at == 2)); then expected_front=com.apple.Terminal; fi
  [[ $(cat "$CLIPBOARD") == 'original clipboard' && $(cat "$FOREGROUND") == "$expected_front" && ! -e $out/.scrum-paste.lock ]] || fail 'Input interruption changed user focus/clipboard/lock'
  ! grep -Eq '^focus restore|^open -b' "$CALLS" || fail 'Input interruption stole focus'
done
auto_reset
AUTO_TICK_MS=150 AUTO_INPUT_AT=2 run_auto
[[ $auto_code == 4 && $(grep -c '^open ' "$CALLS") == 0 ]] || fail 'Sub-second input reset not detected with millisecond timing'
auto_reset
AUTO_INPUT_AT=3 run_auto
[[ $auto_code == 4 && -f $out/2026-09-28.paste-notified-input ]] || fail 'Input notification used a generic phase key'
echo com.apple.Terminal > "$FOREGROUND"; : > "$CALLS"; PASTE_MODE=wrong-root run_auto
[[ $auto_code == 1 && $(grep -c '^notification ' "$CALLS") == 1 ]] || fail 'Input notice suppressed later real thread failure'
auto_reset
AUTO_INPUT_AT=3 AUTO_SWITCH_APP=com.apple.TextEdit run_auto
[[ $auto_code == 4 && $(cat "$FOREGROUND") == com.apple.TextEdit ]] || fail 'Cleanup stole focus from user-switched app'
auto_reset
PASTE_MODE=signal-open run_auto
[[ $auto_code == 143 && $(cat "$FOREGROUND") == com.apple.Terminal && ! -e $out/.scrum-paste.lock ]] || fail 'Signal interruption did not restore foreground/lock'
auto_reset
for _ in 1 2; do PASTE_MODE=wrong-root run_auto; [[ $auto_code == 1 ]] || fail 'Retryable thread failure succeeded'; done
[[ $(grep -c '^notification ' "$CALLS") == 1 && ! -e $out/2026-09-28.paste-skipped ]] || fail 'Same-day same-phase failure notification repeated'
PASTE_MODE=initially-checked run_auto
[[ $auto_code == 1 && $(grep -c '^notification ' "$CALLS") == 2 ]] || fail 'Different failure phase notice suppressed'
grep -q 'notification .*체크박스.*전송 금지' "$CALLS" || fail 'Pre-paste checkbox failure reason missing from notice'
AUTO_CLOCK=1131 run_auto; AUTO_CLOCK=1400 run_auto
[[ $auto_code == 0 && -f $out/2026-09-28.paste-notified-deadline && $(grep -c '^notification ' "$CALLS") == 3 ]] || fail 'Deadline notice repeated or missing'
for mode in checkbox-paste screenshot-fail fail-v child-three; do
  auto_reset
  PASTE_MODE=$mode run_auto
  [[ $auto_code == 3 && -s $out/2026-09-28.paste-attention && ! -e $out/2026-09-28.pasted && ! -e $out/2026-09-28.paste-skipped ]] || fail "Post-paste failure not attention terminal: $mode"
  grep -q 'notification .*붙여넣기 됐을 수 있음.*전송 금지' "$CALLS" || fail "Post-paste warning missing: $mode"
  [[ $(cat "$FOREGROUND") == com.apple.Terminal ]] || fail 'Attention path lost foreground'
  : > "$CALLS"; PASTE_MODE=$mode run_auto; no_auto_gui attention
done
for ignored in 0 1; do
  auto_reset
  FOCUS_RESTORE_FAIL=$((1-ignored)) FOCUS_RESTORE_IGNORED=$ignored run_auto
  [[ $auto_code == 0 && -f $out/2026-09-28.pasted && $(cat "$FOREGROUND") == com.apple.Terminal ]] || fail 'LaunchServices fallback did not verify focus restoration'
  grep -q '^open -b com.apple.Terminal' "$CALLS" || fail 'Failed cooperative restore did not use open -b'
done
# A quit original app must not be relaunched by the open -b fallback.
auto_reset
FOCUS_RESTORE_IGNORED=1 ORIGINAL_APP_GONE=1 run_auto
! grep -q '^open -b' "$CALLS" || fail 'open -b relaunched a quit original app'
[[ -f $out/2026-09-28.pasted ]] || fail 'Focus warning overrode paste success'
for mode in normal duplicate; do
  auto_reset
  FOCUS_RESTORE_IGNORED=1 FOCUS_OPEN_FAIL=1 PASTE_MODE=$mode run_auto
  if [[ $mode == normal ]]; then [[ $auto_code == 0 && -f $out/2026-09-28.pasted && ! -e $out/2026-09-28.paste-attention ]] || fail 'Restore failure overwrote successful paste'
  else [[ $auto_code == 3 && -f $out/2026-09-28.paste-skipped ]] || fail 'Restore failure overwrote terminal result'; fi
  grep -q 'notification .*Slack이 전면에 남음 — 키 입력 주의' "$CALLS" || fail 'Unrestored Slack lacked attention warning'
done
auto_reset
for _ in 1 2 3 4 5; do PASTE_MODE=wrong-root run_auto; [[ $auto_code == 1 ]] || fail 'Retry cap triggered too early'; done
PASTE_MODE=wrong-root run_auto
[[ $auto_code == 3 && $(cat "$out/2026-09-28.paste-attempts") == 6 && -f $out/2026-09-28.paste-skipped ]] || fail 'Daily retry cap missing'
grep -q 'notification .*일일 GUI 시도 6회 소진' "$CALLS" || fail 'Daily final failure notice missing'
: > "$CALLS"; run_auto; no_auto_gui retry-cap
auto_reset
mkdir "$out/.scrum-paste.lock" "$out/.scrum-paste.recovery.lock"
echo 99999999 > "$out/.scrum-paste.lock/pid"
touch -t "$(/bin/date -r "$(($(/bin/date +%s) - 61))" '+%Y%m%d%H%M.%S')" "$out/.scrum-paste.recovery.lock"
run_auto
[[ $auto_code == 0 && -f $out/2026-09-28.pasted && ! -e $out/.scrum-paste.recovery.lock ]] || fail 'Auto stale lock recovery failed'
for stage in inherited paste-done; do
  auto_reset
  mkdir -p "$HOME/Library/Logs/routine-automation/.morning.lock"
  echo "$$" > "$HOME/Library/Logs/routine-automation/.morning.lock/pid"
  if [[ $stage == inherited ]]; then ROUTINE_MORNING_LOCK_PID=$$ run_auto
  else echo paste-done > "$HOME/Library/Logs/routine-automation/.morning.lock/stage"; run_auto; fi
  [[ $auto_code == 0 && -f $out/2026-09-28.pasted ]] || fail "Morning lock bypass incorrect: $stage"
  rm -rf -- "$HOME/Library/Logs/routine-automation/.morning.lock"
done
# A draft sources field is authoritative; collect metadata is legacy fallback only.
for source in ready collect-ready absent failed draft-false refresh-fail; do
  auto_reset
  case $source in
    ready) ;;
    collect-ready) jq 'del(.sources)' "$result" > "$sandbox/change.json"; mv "$sandbox/change.json" "$result" ;;
    absent) jq 'del(.sources)' "$result" > "$sandbox/change.json"; mv "$sandbox/change.json" "$result" ;;
    failed|draft-false|refresh-fail) jq '.sources.slack=false' "$result" > "$sandbox/change.json"; mv "$sandbox/change.json" "$result" ;;
  esac
  if [[ $source == collect-ready || $source == draft-false ]]; then
    cp "$out/2026-09-28.json" "$sandbox/collect-before.json"
    jq '.sources.slack=true' "$out/2026-09-28.json" > "$sandbox/change.json"; mv "$sandbox/change.json" "$out/2026-09-28.json"
  fi
  if [[ $source == refresh-fail ]]; then OMP_BAD=always run_auto; else AUTO_SELF_RESET=1 run_auto; fi
  [[ $auto_code == 0 && -e $out/2026-09-28.pasted ]] || fail "Slack refresh did not paste: $source"
  if [[ $source == ready || $source == collect-ready ]]; then
    ! grep -Eq '^omp |set-value.*--value from:me after:' "$CALLS" || fail 'Slack-ready draft regenerated'
  else
    [[ $(grep -c 'set-value.*--value from:me after:' "$CALLS") == 1 && -f $out/2026-09-28.draft-refresh-attempted ]] || fail 'Slack refresh count/marker not one'
    if [[ $source != refresh-fail ]]; then jq -e '.sources.slack==true' "$result" >/dev/null || fail 'Slack success metadata absent'; fi
  fi
  if [[ $source == collect-ready || $source == draft-false ]]; then mv "$sandbox/collect-before.json" "$out/2026-09-28.json"; fi
done
auto_reset
jq '.sources.slack=false' "$result" > "$sandbox/change.json"; mv "$sandbox/change.json" "$result"
for _ in 1 2 3; do OMP_BAD=always PASTE_MODE=wrong-root run_auto; [[ $auto_code == 1 ]] || fail 'Retryable model/thread failure changed'; done
[[ $(grep -c 'set-value.*--value from:me after:' "$CALLS") == 1 && $(grep -c '^omp ' "$CALLS") == 2 ]] || fail 'Slack regeneration exceeded daily one-attempt cap'
# Input detection in collect propagates exit 4 and never spends an LLM call.
for input_at in 2 3 4 5; do
  auto_reset
  jq '.sources.slack=false' "$result" > "$sandbox/change.json"; mv "$sandbox/change.json" "$result"
  AUTO_SELF_RESET=1 AUTO_INPUT_AT=$input_at SEARCH_MODE=fallback run_auto
  [[ $auto_code == 4 && ! -e $out/2026-09-28.pasted && ! -e $out/2026-09-28.paste-skipped ]] || fail 'Refresh user input was not retryable'
  [[ $(grep -Ec '^open -a Slack|^orca computer (click|set-value|press-key)' "$CALLS") == $((input_at - 2)) ]] || fail 'Search mutation occurred before HID guard'
  ! grep -Eq 'hotkey.*Cmd\+V|^omp ' "$CALLS" || fail 'Refresh input interruption still pasted or called LLM'
  [[ ! -e $out/2026-09-28.draft-refresh-attempted ]] || fail 'Input-aborted collection consumed daily regeneration'
done
[[ $(stat -f %Lp "$auto_log") == 600 && $(stat -f %Lp "$out/2026-09-28.paste-notified-input") == 600 ]] || fail 'Auto log/state permissions'
# Resume the same daily run after input, without clearing the available refresh.
echo "$(( $(cat "$AUTO_MS_FILE") + 200000 ))" > "$AUTO_MS_FILE"
echo "$(( $(cat "$AUTO_MS_FILE") / 1000 ))" > "$AUTO_EPOCH_FILE"
echo com.apple.Terminal > "$FOREGROUND"; : > "$CALLS"
AUTO_SELF_RESET=1 SEARCH_MODE=loading run_auto
[[ $auto_code == 0 && -f $out/2026-09-28.draft-refresh-attempted && -f $out/2026-09-28.pasted ]] || fail 'Interrupted daily refresh could not resume'
[[ $(grep -c '^omp ' "$CALLS") == 1 && $(cat "$STAGE.search.polls") == 3 ]] || fail 'Resumed refresh skipped delayed Slack or model'
auto_reset
jq '.sources.slack=false' "$result" > "$sandbox/change.json"; mv "$sandbox/change.json" "$result"
FOCUS_RESTORE_IGNORED=1 FOCUS_OPEN_FAIL=1 run_auto
[[ $auto_code == 3 && -f $out/2026-09-28.paste-attention && ! -e $out/2026-09-28.draft-refresh-attempted ]] || fail 'Failed pre-model focus restoration not attention terminal'
! grep -Eq '^omp |hotkey' "$CALLS" || fail 'Model/paste ran while collection left Slack foreground'
auto_reset
ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-paste" --no-draft > "$sandbox/manual-paste"
[[ -f $out/2026-09-28.pasted ]] || fail 'Manual success did not record completion'
: > "$CALLS"; run_auto; no_auto_gui manual-completed
# Search catches an off-screen own reply before the thread opens; partial visible
# replies no longer require traversal. Exact author/channel/root comparisons matter.
for mode in search-own search-own-incomplete search-other search-other-author search-unknown-author search-incomplete search-fail search-format search-bad-url search-root-changed partial partial-own partial-nonempty; do
  auto_reset
  if [[ $mode == search-incomplete || $mode == search-fail || $mode == search-format || $mode == search-bad-url || $mode == search-other-author || $mode == search-unknown-author ]]; then rm -rf -- "$capture_dir"; fi
  AUTO_SELF_RESET=1 PASTE_MODE=$mode run_auto
  [[ $(cat "$STAGE.query") == 'from:me in:#daily-scrum on:2026-09-28' ]] || fail "Wrong duplicate search query: $mode"
  ! grep -Eq 'computer scroll|press-key|--element-index (99|100)' "$CALLS" || fail 'Duplicate check scrolled or sent a message'
  [[ $(cat "$CLIPBOARD") == 'original clipboard' ]] || fail "Duplicate path changed clipboard: $mode"
  case $mode in
    search-own|search-own-incomplete)
      [[ $auto_code == 3 && -f $out/2026-09-28.paste-skipped && ! -e $out/2026-09-28.pasted ]] || fail 'Search missed off-screen own reply'
      grep -Fq 'reason=이미 본인 댓글이 있습니다' "$out/2026-09-28.paste-skipped" || fail 'Search duplicate reason missing'
      ! grep -Eq 'hotkey|click .*--element-index (31|61)' "$CALLS" || fail 'Duplicate search opened thread or pasted' ;;
    # A from:me result whose author is unreadable or different is a read failure, not "no own reply".
    search-other|partial)
      [[ $auto_code == 0 && -f $out/2026-09-28.pasted ]] || fail "Unrelated search result prevented safe paste: $mode"
      grep -q 'click .*--element-index 61 ' "$CALLS" || fail 'Search did not re-identify the changed reply index'
      grep -q 'click .*--element-index 6 ' "$CALLS" || fail 'Search query not cleared'
      grep -q 'click .*--element-index 21 ' "$CALLS" || fail 'Channel search panel not closed' ;;
    partial-own|partial-nonempty)
      [[ $auto_code == 3 && -f $out/2026-09-28.paste-skipped && ! -e $out/2026-09-28.pasted ]] || fail 'Visible duplicate/pending input bypassed'
      ! grep -q 'hotkey' "$CALLS" || fail 'Visible duplicate or pending input pasted' ;;
    *)
      [[ $auto_code == 1 && ! -e $out/2026-09-28.pasted ]] || fail "Unverifiable search/root accepted: $mode"
      ! grep -Eq 'hotkey|click .*--element-index (31|61)' "$CALLS" || fail 'Failed search/root opened thread or pasted'
      if [[ $mode != search-root-changed && $mode != search-other-author && $mode != search-unknown-author ]]; then
        captures=("$capture_dir"/[0-9]*-[0-9]*-[0-9]*.txt)
        grep -q '^# routine 검색/' "${captures[@]}" || fail 'Search failure did not save masked diagnostic'
        ! grep -Eq '테스트_사용자|기존 댓글|내 댓글 본문|from:@' "${captures[@]}" || fail 'Search diagnostic leaked author/body/query'
      fi ;;
  esac
done
for search_stage in search combo query results; do
  auto_reset
  AUTO_SELF_RESET=1 AUTO_INPUT_SEARCH_STAGE=$search_stage PASTE_MODE=partial run_auto
  [[ $auto_code == 4 && ! -e $out/2026-09-28.pasted && ! -e $out/2026-09-28.paste-skipped ]] || fail "Search input did not interrupt: $search_stage"
  jq -Rse --arg marker "input-in-search $search_stage" 'split("\n") as $calls | ($calls|index($marker)) as $input | $input!=null and all($calls[$input+1:][]; test("^orca computer (scroll|click|hotkey|set-value|press-key)")|not)' "$CALLS" >/dev/null || fail 'GUI mutation followed search input'
done
auto_reset
PASTE_MODE=search-other ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-paste" --no-draft > "$sandbox/manual-search"
[[ -f $out/2026-09-28.pasted && $(cat "$CLIPBOARD") == 'original clipboard' ]] || fail 'Manual search path lost completion/clipboard'
for override in force replace; do
  auto_reset
  mode=search-own
  [[ $override != replace ]] || mode=partial-nonempty
  PASTE_MODE=$mode ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-paste" --no-draft "--$override" > "$sandbox/manual-$override-search"
  [[ -f $out/2026-09-28.pasted && $(cat "$CLIPBOARD") == 'original clipboard' ]] || fail "Explicit manual --$override failed on partial thread"
done
auto_reset
ROUTINE_SLACK_CHANNEL_NAME='daily "scrum"\ops:danger' PASTE_MODE=query-special ROUTINE_ALLOW_GUI=1 "$repo/bin/scrum-paste" --no-draft > "$sandbox/manual-query"
[[ $(cat "$STAGE.query") == 'from:me in:"#daily \"scrum\"\\ops:danger" on:2026-09-28' && -f $out/2026-09-28.pasted ]] || fail 'Channel search modifier was not safely quoted'
auto_reset
PASTE_MODE=old AUTO_CLOCK=0859 run_auto
[[ $auto_code == 1 && ! -e $out/2026-09-28.paste-skipped ]] || fail 'Missing scrum post terminated before 09:00'
PASTE_MODE=old AUTO_CLOCK=0900 run_auto
[[ $auto_code == 3 && -f $out/2026-09-28.paste-skipped ]] || fail 'Missing scrum post not terminal after 09:00'
grep -Fq 'reason=오늘 스크럼 글 없음' "$out/2026-09-28.paste-skipped" || fail 'Missing post terminal reason incorrect'
: > "$CALLS"; run_auto; no_auto_gui missing-post
# Retention removes only our state/logs older than seven days, never drafts.
auto_reset
touch "$out/2026-09-20.pasted" "$out/2026-09-20.paste-notified-thread" "$out/2026-09-20.draft-refresh-attempted" "$out/2026-09-21.pasted" "$out/2026-09-20.draft.txt"
touch "$HOME/Library/Logs/routine-automation/scrum-paste-2026-09-20.log" "$HOME/Library/Logs/routine-automation/scrum-paste-2026-09-21.log"
AUTO_WEEKDAY=6 run_auto
[[ ! -e $out/2026-09-20.pasted && ! -e $out/2026-09-20.paste-notified-thread && ! -e $out/2026-09-20.draft-refresh-attempted && -e $out/2026-09-21.pasted && -e $out/2026-09-20.draft.txt ]] || fail 'State retention boundary or draft preservation wrong'
[[ ! -e "$HOME/Library/Logs/routine-automation/scrum-paste-2026-09-20.log" && -e "$HOME/Library/Logs/routine-automation/scrum-paste-2026-09-21.log" ]] || fail 'Log retention boundary wrong'
auto_reset
echo 'PASS: unattended self-action/input guards, focus restoration, terminal attention, daily caps and safe paste'
# Run the actual morning orchestrator with stubbed steps to observe ordering/args.
morning_copy="$sandbox/morning-bin"
mkdir "$morning_copy"; cp "$repo/bin/morning" "$morning_copy/morning"
cp -R "$repo/share" "$sandbox/share"
cp "$HOME/.local/bin/omp" "$sandbox/omp-stub"
for step in scrum-collect scrum-draft scrum-paste; do
  cat > "$morning_copy/$step" <<'STEP'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "$CALLS"
if [[ ${0##*/} == scrum-paste ]]; then
  [[ $1 == --auto && $(cat "$HOME/Library/Logs/routine-automation/.morning.lock/pid") == "$ROUTINE_MORNING_LOCK_PID" ]] || exit 87
  exit "${MORNING_PASTE_EXIT:-0}"
fi
STEP
  chmod +x "$morning_copy/$step"
done
for step in omp claude npm aws-session-check; do
  cat > "$HOME/.local/bin/$step" <<'STEP'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "$CALLS"
if [[ ${0##*/} == aws-session-check ]]; then
  [[ $(cat "$HOME/Library/Logs/routine-automation/.morning.lock/stage") == paste-done ]] || exit 87
fi
STEP
  chmod +x "$HOME/.local/bin/$step"
done
: > "$CALLS"
bash "$morning_copy/morning" > "$sandbox/morning-order"
grep -v '^notification ' "$CALLS" > "$sandbox/actual-order"
printf '%s\n' 'omp update' 'claude update' 'npm update -g' 'scrum-collect ' 'scrum-draft ' 'scrum-paste --auto' 'aws-session-check ' > "$sandbox/expected-order"
cmp -s "$sandbox/actual-order" "$sandbox/expected-order" || fail 'Morning actual stage order or --auto differs'
: > "$CALLS"
MORNING_PASTE_EXIT=3 bash "$morning_copy/morning" > "$sandbox/morning-terminal"
grep -q 'scrum-paste:ok(.*exit 3)' "$sandbox/morning-terminal" || fail 'Morning counted terminal paste as failure'
[[ $(grep -c '^notification ' "$CALLS") == 1 ]] || fail 'Morning terminal result duplicated notification'
: > "$CALLS"
MORNING_PASTE_EXIT=4 bash "$morning_copy/morning" > "$sandbox/morning-deferred"
grep -q 'scrum-paste:ok(.*exit 4)' "$sandbox/morning-deferred" || fail 'Morning counted input deferral as failure'
bash "$morning_copy/morning" --skip scrum-paste > "$sandbox/morning-skipped"
[[ ! -e "$HOME/Library/Logs/routine-automation/.morning.lock" ]] || fail 'Morning stage file leaked its lock'
# Restore the model/PR stubs for the existing real-draft morning smoke below.
rm "$HOME/.local/bin/omp"
cp "$sandbox/omp-stub" "$HOME/.local/bin/omp"
export ROUTINE_NOW='2026-09-28T12:00:00+09:00'
# Isolated morning execution uses a real draft with stubbed model and PR reads.
cat > "$HOME/.local/bin/gtimeout" <<'TIMEOUT'
#!/usr/bin/env bash
shift 3
exec "$@"
TIMEOUT
cat > "$HOME/.local/bin/osascript" <<'NOTIFY'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
NOTIFY
chmod +x "$HOME/.local/bin/"{gtimeout,osascript}
require_gh_stub; require_omp_stub
: > "$CALLS"
ROUTINE_ALLOW_GUI=1 "$repo/bin/morning" --only scrum-collect --only scrum-draft > "$sandbox/morning"
grep -q 'scrum-collect:ok' "$sandbox/morning" || fail 'Morning collection stage missing'
grep -q 'scrum-draft:ok' "$sandbox/morning" || fail 'Morning draft stage missing'
! grep -q 'orca\|open ' "$CALLS" || fail 'Morning invoked GUI'
echo 'PASS: isolated scrum draft, evidence, Slack search and safe paste behavior'
