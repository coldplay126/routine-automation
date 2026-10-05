#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
real_jq=${TEST_JQ_BIN:-$(type -P jq)}
real_node=$(type -P node || true)
while IFS= read -r name; do [[ $name != ROUTINE_* ]] || unset "$name"; done < <(compgen -v)
sandbox=$(mktemp -d /tmp/routine-review-tests.XXXXXXXX)
trap 'rm -rf -- "$sandbox"' EXIT
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" PATH="$sandbox/stubs:/usr/bin:/bin" USER=fixture
export ROUTINE_CONFIG="$HOME/.config/routine-automation/config.json" ROUTINE_NOW='2026-09-28T09:00:00Z' ROUTINE_TZ=UTC
export RECORD="$sandbox/calls" ROUTINE_SKIP_LAUNCHCTL=1
mkdir -p "$HOME/.local/bin" "$TMPDIR" "$sandbox/stubs"
ln -s "$real_jq" "$sandbox/stubs/jq"
ln -s "$sandbox/stubs/jq" "$HOME/.local/bin/jq"
ln -s "$sandbox/stubs/gtimeout" "$HOME/.local/bin/gtimeout"
for cmd in gh omp claude orca brew launchctl osascript; do
  printf '#!/bin/sh\nexit 87\n' > "$sandbox/stubs/$cmd"; chmod +x "$sandbox/stubs/$cmd"
  ln -s "$sandbox/stubs/$cmd" "$HOME/.local/bin/$cmd"
done
export MODEL_JSON="$sandbox/model.json"
cat > "$sandbox/stubs/omp" <<'MODEL'
#!/bin/bash
cat > /dev/null
cat "$MODEL_JSON"
MODEL
cat > "$sandbox/stubs/gtimeout" <<'TIMEOUT'
#!/bin/bash
shift 3
exec "$@"
TIMEOUT
cat > "$sandbox/stubs/open" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$RECORD"
STUB
cat > "$sandbox/stubs/osacompile" <<'STUB'
#!/bin/bash
[[ $1 == -o && $3 == -e ]] || exit 87
mkdir -p "$2/Contents/MacOS"
printf '%s\n' "$4" > "$2/Contents/MacOS/applet"
STUB
printf '#!/bin/sh\nexit 0\n' > "$sandbox/stubs/xattr"
cat > "$sandbox/stubs/osascript" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" > "$RECORD.clipboard"
STUB
chmod +x "$sandbox/stubs/"*
for cmd in open osacompile xattr; do ln -s "$sandbox/stubs/$cmd" "$HOME/.local/bin/$cmd"; done
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
routine="$repo/bin/routine"
if ROUTINE_CONFIG="$sandbox/missing-config.json" "$routine" review --no-open > /dev/null 2>&1; then fail '필수 설정 없이 검토를 열었습니다'; fi
"$routine" init --non-interactive --slack-link https://example.slack.com/archives/CEXAMPLE/p1790895609247049 --slack-team-id TEXAMPLE --sources-git-enabled false --draft-llm-engine none --timezone UTC --draft-project '예제 프로젝트' > /dev/null
out="$HOME/Library/Application Support/routine-automation/scrum"
mkdir -p "$out"
if "$routine" review --no-open > "$sandbox/missing" 2>&1; then fail '초안 없는 검토가 성공했습니다'; fi
for day in ../2026-09-28 2026-02-30; do
  if "$routine" review --date "$day" --no-open > /dev/null 2>&1; then fail '잘못된 날짜를 허용했습니다'; fi
done
jq -n '{git:[{sha:"abc123",repo:"서비스",subject:"기능 점검"}],prs:[{url:"https://example.test/pull/1",title:"리뷰 계획",state:"OPEN",in_window:true},{url:"https://example.test/pull/legacy",title:"이전 수집",state:"OPEN"}],sessions:[{id:"report",source:"omp",latest_report:("token=fixture-secret <!--<script> 예시 <script>bad()</script> \"인용\" "+("가"*340)),reports:[]}],slack:[{url:"https://example.slack.com/archives/CEXAMPLE/p123",text:"Slack 근거"}],errors:[]}' > "$out/2026-09-28.json"
jq -n '{items:[
 {section:"yesterday",path:["개발","서비스"],topic:"기능 점검",level:"work",evidence:["git:abc123","session:report","slack:https://example.slack.com/archives/CEXAMPLE/p123"]},
 {section:"yesterday",path:["기타","인용"],topic:"<script>window.fixtureAttack=1</script> \"따옴표\" & @@REVIEW_DATA@@ <!--<script>",level:"request",evidence:["session:report"]},
 {section:"yesterday",path:["개발","보류"],topic:"보류 점검",level:"request",evidence:[],held_ref:0},
 {section:"today",path:["개발","리뷰 계획"],topic:"리뷰 계획",level:"request",evidence:["pr:https://example.test/pull/1"]},
 {section:"yesterday",path:["배포","제외 후보"],topic:"결제 API 배포 완료",level:"deployed",evidence:["git:missing"]},
 {section:"yesterday",path:["개발","결제"],topic:"결제",level:"work",evidence:["git:abc123"]},
 {section:"today",path:["업무 자동화","오늘 메모 작업"],topic:"오늘 메모 작업",level:"request",evidence:["note:0"]},
 {section:"today",path:["개발","보류"],topic:"보류 점검",level:"request",evidence:["note:1"],held_ref:0},
 {section:"yesterday",path:["기타","FEFF 주제"],topic:"FEFF 주제\uFEFF",level:"request",evidence:["session:report"]},
 {section:"yesterday",path:["기타","NEL 주제"],topic:"NEL 주제\u0085",level:"request",evidence:["session:report"]}
]}' > "$sandbox/model.json"
printf '%s\n' '## 오늘 추가' '- 오늘 메모 작업' '- 보류 점검' '## 보류' '- 보류 점검' > "$out/notes.md"
"$routine" draft --date 2026-09-28 --engine omp > /dev/null
expected_text="$out/2026-09-28.draft.txt"; expected_html="$out/2026-09-28.draft.html"
mv "$out/2026-09-28.json" "$sandbox/removed-source.json"
"$routine" config set draft.project '"나중 프로젝트"' > /dev/null
"$routine" config set draft.headers.today '"변경된 오늘 머리글"' > /dev/null
"$routine" config set draft.categories '["기타","개발","배포","업무 자동화"]' > /dev/null
"$routine" config set draft.markers '"all"' > /dev/null
html=$("$routine" review --no-open)
[[ $html == "$out/2026-09-28.review.html" && $(stat -f %Lp "$html") == 600 && ! -e $RECORD ]] || fail '검토 경로·권한·no-open 경계'
jq -Rrs 'capture("<script id=\"review-data\" type=\"application/json\">(?<data>[^\\n]+)</script>").data|fromjson' "$html" > "$sandbox/data.json"
jq -Rse --slurpfile data "$sandbox/data.json" '
  [match("<input type=\"checkbox\" data-select=\"[0-9]+\"[^>]*>";"g").string |
    capture("data-select=\"(?<id>[0-9]+)\"(?<attributes>[^>]*)") |
    {id:(.id|tonumber),checked:(.attributes|test(" checked(?: |$)"))}] as $checkboxes |
  all($checkboxes[];.checked==$data[0].items[.id].selected) and
  any($checkboxes[];.checked==true) and any($checkboxes[];.checked==false)
' "$html" > /dev/null || fail '체크박스 실제 기본 선택 상태'
jq -e '
  all(.items[]|select(.question_only!=true and .disabled!=true);.selected==true) and
  all(.items[]|select(.question_only==true);.selected==false) and
  any(.items[];.topic=="결제 API 배포 완료" and .section=="yesterday" and .path==["배포","제외 후보"] and .selected==false) and
  any(.items[];.held==true) and
  any(.items[];.topic=="결제" and .reasons==[]) and
  any(.items[];.section=="today" and .held and .disabled and .selected==false and (.reasons|index("보류 중인 오늘 계획은 초안에 포함하지 않습니다.")!=null)) and
  any(.items[].proof[];.id=="note:0" and .text=="오늘 메모 작업") and
  all(.items[];(.topic|startswith("이전 버전 PR 근거")|not)) and
  .settings.project=="예제 프로젝트" and .settings.headers.today=="오늘의 작업 계획" and
  any(.items[].proof[];.id=="session:report" and (.text|length)==300 and (.text|contains("[REDACTED]"))) and
  any(.items[].proof[];.id=="git:abc123") and
  any(.items[].proof[];.id=="pr:https://example.test/pull/1") and
  any(.items[].proof[];.id=="slack:https://example.slack.com/archives/CEXAMPLE/p123") and
  all(.items[].proof[];(.text|length)<=300) and
  .channel=="slack://channel?team=TEXAMPLE&id=CEXAMPLE"
' "$sandbox/data.json" > /dev/null || fail '근거·보류·제외 후보·redact·300자 경계'
cp "$out/2026-09-28.draft.json" "$sandbox/snapshot.json"
cp "$ROUTINE_CONFIG" "$sandbox/legacy-config.json"
jq --slurpfile snapshot "$sandbox/snapshot.json" '.draft=$snapshot[0].settings' "$sandbox/legacy-config.json" > "$ROUTINE_CONFIG"
jq 'del(.settings)' "$sandbox/snapshot.json" > "$out/2026-09-28.draft.json"
"$routine" config set draft.format '{"bullets":["+"],"layout":"flat","max_items_per_section":1}' > /dev/null
"$routine" review --no-open > /dev/null
if [[ -n $real_node ]]; then "$real_node" "$repo/tests/review-render.cjs" "$html" "$expected_text" "$expected_html"; fi
jq -Rse 'capture("<script id=\"review-data\" type=\"application/json\">(?<data>[^\\n]+)</script>").data|fromjson|.settings.format=={bullets:["•","◦","▪","▪"],layout:"tree",max_items_per_section:null}' "$html" > /dev/null || fail '스냅샷 없는 초안의 기본 형식'
cp "$sandbox/snapshot.json" "$out/2026-09-28.draft.json"
cp "$sandbox/legacy-config.json" "$ROUTINE_CONFIG"
"$routine" review --no-open > /dev/null
jq -Rse '
  contains("default-src '\''none'\''; style-src '\''unsafe-inline'\''; script-src '\''unsafe-inline'\''; img-src data:") and
  (test("(?i)(src|href)=[\\\"'\'']https?://")|not) and
  contains("&lt;script&gt;window.fixtureAttack=1&lt;/script&gt; &quot;따옴표&quot;") and
  (capture("<script id=\"review-data\" type=\"application/json\">(?<data>[^\\n]+)</script>").data|test("[<>&]")|not) and
  (contains("fixture-secret")|not) and
  (sub("<script id=\"review-data\" type=\"application/json\">[^\\n]+</script>";"")|contains("<script>window.fixtureAttack")|not)
' "$html" > /dev/null || fail 'CSP·외부 리소스·악성 HTML·redact 경계'
# Parse the actual initial preview markup into renderer bullet lines, not its JSON copy.
jq -Rrs '
  def decode: gsub("&lt;";"<")|gsub("&gt;";">")|gsub("&quot;";"\"")|gsub("&#39;";"'\''")|gsub("&amp;";"&");
  capture("<div id=\"preview\">(?<html>[\\s\\S]*?)</div>").html |
  [scan("<[^>]+>|[^<]+")]|reduce .[] as $token ({depth:0,lines:[],header:false};
    if $token=="<ul>" then .depth+=1
    elif $token=="</ul>" then .depth-=1
    elif $token=="<b>" then (if (.lines|length)>0 then .lines+=[""] else . end)|.header=true
    elif $token=="</b>" then .header=false
    elif $token=="<li>" then .lines += [("  "*(.depth-1))+(["•","◦","▪"][([.depth-1,2]|min)])+" "]
    elif $token=="</li>" or $token=="\n" then .
    elif .header then .lines += [($token|decode)]
    else .lines[-1]+=($token|decode) end) | .lines|join("\n")
' "$html" > "$sandbox/preview.txt"
cmp -s "$sandbox/preview.txt" "$expected_text" || fail '초기 미리보기가 저장된 draft.txt와 다릅니다'
chmod 644 "$html"
"$routine" review > /dev/null
[[ $(stat -f %Lp "$html") == 600 && $(cat "$RECORD") == "$html" ]] || fail 'open 동작·기존 파일 권한 복원'
cp "$out/2026-09-28.draft.json" "$out/2026-09-25.draft.json"
"$routine" review --date 2026-09-25 --no-open > /dev/null
[[ -f $out/2026-09-25.review.html ]] || fail '--date 파일 선택'
# Legacy drafts have questions but no excluded metadata: retain a selectable candidate.
jq 'del(.excluded_items) | .questions=["옛 질문 후보: 유효한 근거가 없어 초안에서 제외"]' "$out/2026-09-25.draft.json" > "$sandbox/legacy.json"
cp "$sandbox/legacy.json" "$out/2026-09-25.draft.json"
"$routine" review --date 2026-09-25 --no-open > /dev/null
jq -Rse 'capture("<script id=\"review-data\" type=\"application/json\">(?<data>[^\\n]+)</script>").data|fromjson|any(.items[];.question_only==true and .selected==false and (.text|contains("옛 질문 후보")))' "$out/2026-09-25.review.html" > /dev/null || fail '이전 초안 질문 전용 후보 누락'
if [[ -n $real_node ]]; then
  browser_status=0
  "$real_node" "$repo/tests/review-browser.cjs" "$html" "$expected_text" "$expected_html" || browser_status=$?
  if ((browser_status!=0 && browser_status!=77)); then fail '실제 검토 브라우저 회귀'; fi
else echo 'SKIP: node 없음 — 선택 검토 브라우저 회귀'; fi
# A custom config path must survive app launch without inherited ROUTINE_CONFIG.
custom_config="$sandbox/custom config's.json"
mv "$ROUTINE_CONFIG" "$custom_config"; export ROUTINE_CONFIG="$custom_config"
# Installation runs only stub osacompile; no launchctl, brew, GUI, or model calls.
share_dir="$repo/share"
# shellcheck source=../share/config.sh
source "$share_dir/config.sh"
# shellcheck source=../share/install.sh
source "$share_dir/install.sh"
routine_load_config
routine_install_paths
# App commands replace PATH; exported Bash functions keep their GUI calls isolated.
open() { "$HOME/.local/bin/open" "$@"; }
osascript() { "$HOME/.local/bin/osascript" "$@"; }
export -f open osascript
mkdir -p "$review_app"; printf '소유하지 않은 앱\n' > "$review_app/foreign"
if routine_install_files "$repo" > /dev/null 2>&1; then fail '미소유 검토 앱을 덮어썼습니다'; fi
[[ $(cat "$review_app/foreign") == '소유하지 않은 앱' ]] || fail '미소유 앱을 변경했습니다'
rm "$review_app/foreign"; rmdir "$review_app"
routine_install_files "$repo" > /dev/null
[[ -d $copy_app && -d $review_app ]] || fail '복사·검토 앱 생성'
jq -e --arg prefix "$review_app/" 'any(.files[];.path|startswith($prefix))' "$manifest" > /dev/null || fail '검토 앱 manifest 소유 누락'
shell_command=$(jq -Rr 'sub("^do shell script ";"")|fromjson' "$review_app/Contents/MacOS/applet")
env -u ROUTINE_CONFIG /bin/bash -c "$shell_command" > "$sandbox/app-review"
[[ $(cat "$sandbox/app-review") == "$html" ]] || fail '설치한 검토 앱의 사용자 지정 설정 경로 전달'
shell_command=$(jq -Rr 'sub("^do shell script ";"")|fromjson' "$copy_app/Contents/MacOS/applet")
env -u ROUTINE_CONFIG /bin/bash -c "$shell_command" > "$sandbox/app-copy"
[[ -f $RECORD.clipboard && -f $out/2026-09-28.copied ]] || fail '설치한 복사 앱의 사용자 지정 설정 경로 전달'
# An equal configuration at a new path still needs a newly compiled app command.
mv "$ROUTINE_CONFIG" "$sandbox/second config.json"; export ROUTINE_CONFIG="$sandbox/second config.json"
routine_load_config
routine_install_files "$repo" > /dev/null
shell_command=$(jq -Rr 'sub("^do shell script ";"")|fromjson' "$review_app/Contents/MacOS/applet")
env -u ROUTINE_CONFIG /bin/bash -c "$shell_command" > "$sandbox/app-review-moved"
[[ $(cat "$sandbox/app-review-moved") == "$html" ]] || fail '설정 내용이 같아도 검토 앱 설정 경로를 갱신해야 합니다'
shell_command=$(jq -Rr 'sub("^do shell script ";"")|fromjson' "$copy_app/Contents/MacOS/applet")
env -u ROUTINE_CONFIG /bin/bash -c "$shell_command" > "$sandbox/app-copy-moved"
[[ -f $RECORD.clipboard && -f $out/2026-09-28.copied ]] || fail '설정 경로 이동 뒤 복사 앱 실행'
cp "$review_app/Contents/MacOS/applet" "$sandbox/owned-applet"
printf '변경됨\n' >> "$review_app/Contents/MacOS/applet"
if "$routine" uninstall > /dev/null 2>&1; then fail '변경된 검토 앱을 제거했습니다'; fi
[[ -d $review_app && -f $manifest ]] || fail '소유 검사 실패 뒤 설치가 제거되었습니다'
cp "$sandbox/owned-applet" "$review_app/Contents/MacOS/applet"
"$routine" uninstall > /dev/null
[[ ! -e $copy_app && ! -e $review_app && ! -e $installed_root && -f $html ]] || fail '소유한 앱 제거·검토 데이터 보존'
echo 'PASS: 검토 화면·근거·보안·앱 소유 회귀'
