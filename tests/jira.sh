#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2030,SC2031 # jq programs are literals; subshell fixtures intentionally isolate settings.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
real_jq=${TEST_JQ_BIN:-$(type -P jq)}
sandbox=$(mktemp -d /tmp/routine-jira-tests.XXXXXXXX)
trap 'rm -rf -- "$sandbox"' EXIT
while IFS= read -r name; do [[ $name != ROUTINE_* ]] || unset "$name"; done < <(compgen -v)
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" XDG_CONFIG_HOME="$sandbox/config" PATH="$sandbox/stubs:/usr/bin:/bin" USER=fixture
mkdir -p "$HOME/.local/bin" "$TMPDIR" "$sandbox/stubs" "$XDG_CONFIG_HOME"
ln -s "$real_jq" "$sandbox/stubs/jq"
ln -s "$real_jq" "$HOME/.local/bin/jq"
share_dir="$repo/share"
# shellcheck source=../share/config.sh
source "$share_dir/config.sh"
fail() { printf 'FAIL: Jira %s\n' "$1" >&2; exit 1; }
check() { local name=$1; shift; "$@" || fail "$name"; }
jq_check() { local name=$1 filter=$2; shift 2; jq -L "$share_dir" -e "$filter" "$@" >/dev/null || fail "$name"; }
routine_load_config
jq_check 'T77 default settings remain valid' 'include "config"; config_ok and (.jira.enabled==false) and (.morning.extra_steps.jira_propose==false)' <<< "$ROUTINE_SETTINGS"
jq_check 'T77 required Jira settings independent from scrum' 'include "config"; .jira.enabled=true|jira_required_errors|index("jira.site")!=null' <<< "$ROUTINE_SETTINGS"
check 'T67 expanded token alphabet redaction' test "$(jq -L "$share_dir" -nr 'include "redact"; "ATATTfixture-=+/._end"|redact')" = '[REDACTED]'
jq_check 'T43 existing proof behavior' 'include "scrum"; "운영 배포 완료했습니다"|report_proves("deployed")' <<< 'null'
jq_check 'T43 conservative deployment proof' 'include "scrum"; "스테이징 배포 완료"|report_proves("deployed")|not' <<< 'null'
jq_check 'T43 proving sentences extraction' 'include "scrum"; "운영 조회 확인했습니다\n확인했습니다"|proving_sentences("verified")|length==1' <<< 'null'
echo 'PASS: Jira 설정·redact·스크럼 proof 계약 (W001–W002)'
# shellcheck source=../share/jira.sh
source "$share_dir/jira.sh"
export JIRA_SECURITY_STUB="$repo/tests/fixtures/jira/security.sh" JIRA_SECURITY_CALLS="$sandbox/security-calls"
export JIRA_GIT_ROOT="$sandbox/repos" JIRA_FORBIDDEN_CALLS="$sandbox/forbidden-calls"
ln -s "$JIRA_SECURITY_STUB" "$sandbox/stubs/security"
for stub in claude gum open osascript git gh ps; do ln -s "$repo/tests/fixtures/jira/command.sh" "$sandbox/stubs/$stub"; done
ln -s "$repo/tests/fixtures/jira/gtimeout.sh" "$sandbox/stubs/gtimeout"
claude() { "$HOME/../stubs/claude" "$@"; }; gum() { "$HOME/../stubs/gum" "$@"; }
open() { "$HOME/../stubs/open" "$@"; }; osascript() { "$HOME/../stubs/osascript" "$@"; }
git() { "$HOME/../stubs/git" "$@"; }; gh() { "$HOME/../stubs/gh" "$@"; }; ps() { "$HOME/../stubs/ps" "$@"; }
export -f claude gum open osascript git gh ps
# Production authentication is reached only through these exported double stubs.
export JIRA_CALLS="$sandbox/calls" JIRA_RESPONSE="$sandbox/response.json"
security() { "$JIRA_SECURITY_STUB" "$@"; }
curl() {
  local auth='' out='' headers='' method='' url='' body='' arg
  [[ $1 == -q ]] || return 87
  shift
  while (($#)); do
    arg=$1; shift
    case $arg in
      -K) auth=$1; shift ;; --output) out=$1; shift ;; --dump-header) headers=$1; shift ;;
      --request) method=$1; shift ;; --data-binary) body=$1; shift ;;
      --proto|--max-redirs|--connect-timeout|--max-time|--max-filesize|--header|--write-out) shift ;;
      https://example.atlassian.net/*) url=$arg ;;
      *) return 87 ;;
    esac
  done
  [[ -f $auth && $(stat -f %Lp "$auth") == 600 && $(wc -l < "$auth") -eq 1 ]] || return 87
  printf '%s %s %s\n' "$method" "$url" "$body" >> "$JIRA_CALLS"
  printf 'HTTP/1.1 200 OK\r\n\r\n' > "$headers"
  cp "$JIRA_RESPONSE" "$out"
  printf '%s' 200
}
export -f security curl
ROUTINE_SETTINGS=$(command jq -c '.jira.enabled=true|.jira.site="https://example.atlassian.net"|.jira.email="fixture@example.com"|.jira.projects={ABC:{statuses:{start_from:["1"],in_progress:"3"},create_type:"10"}}' <<< "$ROUTINE_SETTINGS")
printf '{"accountId":"fixture-account"}\n' > "$JIRA_RESPONSE"
(
  routine_jira_session
  check 'T74 lock acquisition' routine_jira_lock review
  check 'T74 ownership' routine_jira_lock_owned
  check 'T74 live process start' routine_jira_lock_live "$jira_dir/.lock"
  check 'T67 authentication file' routine_jira_authenticate
  check 'T68 invalid account' test "$(routine_get jira.email)" = fixture@example.com
  printf '[{"ref":"a","input":["한국어","quote \\"","newline\\n"]},{"ref":"b","input":["event","commit","git:sha"]}]\n' > "$jira_work/identities.json"
  first=$(routine_jira_hash_map "$jira_work/identities.json")
  second=$(routine_jira_hash_map "$jira_work/identities.json")
  check 'T82 deterministic batched hash' test "$first" = "$second"
  jq_check 'T82 SHA256 values' 'all(.[];test("^[0-9a-f]{64}$"))' <<< "$first"
  if routine_jira_read_allowed PUT /rest/api/3/issue/ABC-1; then fail 'T63 write accepted by read client'; fi
  if routine_jira_read_allowed GET https://other.atlassian.net/rest/api/3/myself; then fail 'T65 external URL'; fi
  ROUTINE_SETTINGS=$(command jq -c '.jira.email="bad\\nuser@example.com"' <<< "$ROUTINE_SETTINGS")
  if routine_jira_authenticate; then fail 'T68 unsafe email accepted'; fi
)
jq_check 'T01 link-card body preserved' 'include "jira"; {type:"doc",content:[{type:"paragraph",content:[{type:"inlineCard",attrs:{url:"https://example.com"}}]}]}|jira_adf_state|.state=="content"' <<< null
jq_check 'T02 template strong headings' 'include "jira"; {type:"doc",content:[jira_settings.templates.task.headers[]|{type:"paragraph",content:[{type:"text",text:.,marks:[{type:"strong"}]}]}]}|jira_adf_state|.state=="template_only"' <<< null
jq_check 'T03 report sentence prevents overwrite' 'include "jira"; {type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"[사전조건]"}]},{type:"paragraph",content:[{type:"text",text:"사람이 쓴 제보"}]}]}|jira_adf_state|.state=="content"' <<< null
jq_check 'T04 unsupported nodes conservative' 'include "jira"; ["mention","media","table","unknown"]|all(.[];{type:"doc",content:[{type:.,attrs:{type:"text"}}]}|jira_adf_state|.state|IN("content","undetermined"))' <<< null
jq_check 'T05 empty variants' 'include "jira"; [null,{type:"doc",content:[]},{type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"  "},{type:"hardBreak"}]}]}]|all(.[];jira_adf_state|.state=="empty")' <<< null
jq_check 'T06 nested conditions and cards' 'include "jira"; {type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"완료 조건"}]},{type:"bulletList",content:[{type:"listItem",content:[{type:"paragraph",content:[{type:"inlineCard",attrs:{url:"https://example.com"}}]},{type:"bulletList",content:[{type:"listItem",content:[{type:"paragraph",content:[{type:"text",text:"중첩"}]}]}]}]}]}]}|jira_conditions(jira_settings.templates.task)|(.items|length)==1 and (.items[0].text|contains("[카드]"))' <<< null
jq_check 'T07 display-only marked conditions' 'include "jira"; {type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"완료 조건"}]},{type:"taskList",content:[{type:"taskItem",attrs:{state:"DONE"},content:[{type:"text",text:"하나"}]},{type:"taskItem",content:[{type:"text",text:"둘",marks:[{type:"strike"}]}]},{type:"taskItem",content:[{type:"text",text:"셋"}]}]}]}|jira_conditions(jira_settings.templates.task)|jira_condition_text|contains("남은 1개")' <<< null
echo 'PASS: Jira 잠금·인증·해시·원본 ADF 회귀 (W003–W004)'
export JIRA_SERVER="$sandbox/server.json" JIRA_EFFECTS="$sandbox/effects" JIRA_LEDGER="$HOME/Library/Application Support/routine-automation/jira/ledger.json"
: > "$JIRA_EFFECTS"
export JIRA_CURL_STUB="$repo/tests/fixtures/jira/curl.sh"
curl() { "$JIRA_CURL_STUB" "$@"; }
ln -s "$JIRA_CURL_STUB" "$sandbox/stubs/curl"
export -f curl
command jq -n '{issue:{id:"100",key:"ABC-1",fields:{summary:"feature implementation",project:{key:"ABC"},issuetype:{id:"10",name:"작업",hierarchyLevel:0},status:{id:"1",statusCategory:{key:"new"}},assignee:{accountId:"fixture-account"},reporter:{accountId:"fixture-account"},description:null,updated:"2026-10-01T00:00:00Z",created:"2026-10-01T00:00:00Z"}},transitions:[{id:"20",to:{id:"3"},fields:{}}],comments:[],history:[]}' > "$JIRA_SERVER"
command jq -n '{git:[{sha:"1111111111111111111111111111111111111111",repo:"example",subject:"ABC-1 feature implementation",author_ts:"2026-10-08T00:00:00Z"}],prs:[],sessions:[],jira:[],errors:[],window:{since:"2026-10-01T00:00:00Z",until:"2026-10-08T12:00:00Z"}}' > "$sandbox/raw.json"
export JIRA_RAW="$sandbox/raw.json"
(
  routine_jira_session; routine_jira_lock propose; routine_jira_authenticate
  jq -L "$share_dir" 'include "jira"; jira_evidence({})|jira_works' "$JIRA_RAW" > "$jira_work/works-unhashed.json"
  jq -L "$share_dir" 'include "jira"; jira_id_inputs' "$jira_work/works-unhashed.json" > "$jira_work/identities.json"
  routine_jira_hash_map "$jira_work/identities.json" > "$jira_work/hashes.json"
  jq -L "$share_dir" --slurpfile hashes "$jira_work/hashes.json" 'include "jira"; jira_with_ids($hashes[0])' "$jira_work/works-unhashed.json" > "$jira_work/works.json"
  jq_check 'T20 deterministic key grouping' 'length==1 and .[0].keys==["ABC-1"] and .[0].active==true' "$jira_work/works.json"
  jq_check 'T10 repository normalization' 'include "jira"; {git:[],prs:[{roles:["author"],repository:{nameWithOwner:"org/example"},url:"https://github.com/example/example/pull/1",state:"OPEN",title:"feature",activity:[],commits_complete:true}],sessions:[]}|jira_evidence({})|.[0].repo=="example"' <<< null
  jq_check 'T08 report identity excludes report numbering' 'include "jira"; {git:[],prs:[],sessions:[{id:"s",source:"omp",reports:[{ts:"2026-10-08T00:00:00Z",text:"text",evidence_id:"session:s#9"}]}]}|jira_evidence({})|last|._identity==["rep","omp","s","2026-10-08T00:00:00Z"]' <<< null
  routine_jira_read_context "$jira_work/context.json"
  jq -L "$share_dir" --slurpfile raw "$JIRA_RAW" --slurpfile works "$jira_work/works.json" 'include "jira"; .evidence=($raw[0]|jira_evidence({}))|.works=$works[0]' "$jira_work/context.json" > "$jira_work/ctx.json"
  routine_jira_propose_issue ABC-1 "$jira_work/ctx.json"
  jq -L "$share_dir" 'include "jira"; jira_rules(.)' "$jira_work/ctx.json" > "$jira_work/rules.json"
  jq_check 'T23 in-progress transition uses transition id' '.proposals|any(.[];.kind=="transition" and .payload.transition_id=="20" and .payload.to.id=="3")' "$jira_work/rules.json"
  jq_check 'T29 no resolved or closed' '.proposals|all(.[];.kind!="transition" or .payload.to.id=="3")' "$jira_work/rules.json"
  jq_check 'T30 no-LLM never fills or creates' '.proposals|all(.[];.kind!="fill_description" and .kind!="create_issue")' "$jira_work/rules.json"
  jq_check 'T33 actual evidence claim adapter' 'include "scrum"; include "jira"; .evidence=[{id:"rep:x",kind:"report",text:"운영 조회 확인했습니다"}]|(.evidence|jira_claim_proof) as $proof|("운영 확인 완료"|claim_classes|claims_supported(.;$proof))' "$jira_work/ctx.json"
  jq_check 'T43 event verification context' 'include "jira"; {id:"w",anchors:[],evidence:["rep:a","rep:b"],active:false}|jira_events([{id:"rep:a",kind:"report",text:"운영 정상 확인",ts:"2026-10-08T00:00:00Z"},{id:"rep:b",kind:"report",text:"✅ 테스트 통과",ts:"2026-10-08T00:00:00Z"}])|length==1 and .[0].kind=="report_verified"' <<< null
  jq_check 'T61 JQL quoting' 'include "jira"; jira_new_queries("ABC";"feature \") AND secret ~";[];[];[])|all(.[];.jql|startswith("project = \"ABC\" AND "))' <<< null
  jq -L "$share_dir" '. as $ctx|.works|=map(.events=[{id:"ev-fixture",kind:"commit",evidence_id:.evidence[0],at:"2026-10-08T00:00:00Z",text:"example 11111111"}])|.llm_valid=true|.llm.sections=[{target:"ABC-1",header:"작업 내용",lines:[{text:"feature implementation",evidence:$ctx.works[0].evidence}]}]' "$jira_work/ctx.json" > "$sandbox/rules-context.json"
  check 'T09–T84 production rule matrix' jq -L "$share_dir" -e -f "$repo/tests/fixtures/jira/rules.jq" "$sandbox/rules-context.json"
)
echo 'PASS: Jira 근거·작업·규칙 계약 (W005–W006)'
ln -s "$sandbox/stubs/gtimeout" "$HOME/.local/bin/gtimeout"
export JIRA_COLLECTION_CALLS="$sandbox/collect-calls"
export ROUTINE_CONFIG="$XDG_CONFIG_HOME/config.json"
ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="none"|.jira.repos={example:{project:"ABC",prefix:"[BACK]"}}' <<< "$ROUTINE_SETTINGS")
routine_save_config "$ROUTINE_SETTINGS"
export ROUTINE_NOW='2026-10-08T12:00:00Z'
check 'T66 read-only scheduled CLI proposal' "$repo/bin/routine" jira propose --no-llm
proposal_file="$HOME/Library/Application Support/routine-automation/jira/2026-10-08.proposals.json"
cp "$proposal_file" "$sandbox/base-proposals.json"
jq_check 'T66 persisted proposal schema' 'include "jira"; jira_proposals_ok' "$proposal_file"
check 'T66 artifact permission' test "$(stat -f %Lp "$proposal_file")" = 600
check 'T66 help' "$repo/bin/routine" jira --help
check 'T66 non-TTY summary review' "$repo/bin/routine" jira review
if "$repo/bin/routine" jira apply; then fail 'T66 unattended apply'; else [[ $? == 2 ]] || fail 'T66 apply exit'; fi
if "$repo/bin/routine" jira close; then fail 'T72 unattended close'; else [[ $? == 2 ]] || fail 'T72 close exit'; fi
check 'T79 non-TTY links' "$repo/bin/routine" jira links
check 'T84 default issue condition summary' "$repo/bin/routine" jira
while IFS= read -r request; do
  case $request in
    "PUT "*|"DELETE "*|"POST /rest/api/3/issue "*|"POST /rest/api/3/issue/"*"/comment "*|"POST /rest/api/3/issue/"*"/transitions "*) fail 'T66 non-TTY command sent a Jira write' ;;
  esac
done < "$JIRA_CALLS"
check 'T66 non-TTY command set has zero server effects' test "$(wc -l < "$JIRA_EFFECTS")" -eq 0
echo 'PASS: Jira propose·도움말·비TTY 쓰기 차단 (W007–W010)'
cp "$JIRA_SERVER" "$sandbox/server-initial.json"
ui_interactive() { return 0; }
ui_confirm() { [[ ${JIRA_APPROVE:-1} == 1 ]]; }
ui_note() { printf '%s\n%s\n' "$1" "$2"; }
ui_choose_many() { command jq -nc --argjson choices "$2" '[$choices[].value]'; }
(
  routine_jira_session; routine_jira_lock review; routine_jira_authenticate
  comment=$(command jq -c '.proposals[]|select(.kind=="comment")' "$proposal_file")
  JIRA_APPROVE=0 routine_jira_approve "$comment" "$proposal_file" false
  jq_check 'T73 selection is not approval' '.entries|length==0' "$jira_dir/ledger.json"
  routine_jira_approve "$comment" "$proposal_file" false
  id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
  check 'T48 normal approved comment' routine_jira_apply_one "$id"
  jq_check 'T48 verified response and property' '.entries[0].state=="verified"' "$jira_dir/ledger.json"
  effects=$(wc -l < "$JIRA_EFFECTS")
  if routine_jira_apply_one "$id"; then fail 'T63 verified resent'; fi
  check 'T63 one server side effect' test "$(wc -l < "$JIRA_EFFECTS")" = "$effects"
  jq_check 'T65 strict request body' 'include "jira"; .entries[0]|.request.body.summary="injected"|jira_request_ok(jira_settings)|not' "$jira_dir/ledger.json"
)
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate
  printf '{"version":1,"entries":[],"dismissed":[],"markers":[]}\n' > "$jira_work/reset.json"
  routine_jira_store "$jira_work/reset.json" "$jira_dir/ledger.json"
  comment=$(command jq -c '.proposals[]|select(.kind=="comment")' "$proposal_file")
  routine_jira_approve "$comment" "$proposal_file" false
  id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
  export JIRA_WRITE_EXIT=28 JIRA_EFFECT=1
  check 'T49 unknown comment transport' routine_jira_apply_one "$id"
  jq_check 'T49 permanent unknown event marker' '.entries[0].state=="unknown" and .markers[0].kind=="comment"' "$jira_dir/ledger.json"
  effects=$(wc -l < "$JIRA_EFFECTS")
  unset JIRA_WRITE_EXIT
  check 'T49 read-only recovery' routine_jira_reconcile "$id"
  jq_check 'T49 recovered and verified' '.entries[0].state=="verified"' "$jira_dir/ledger.json"
  check 'T49 POST count remains one' test "$(wc -l < "$JIRA_EFFECTS")" = "$effects"
)
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock review; routine_jira_authenticate
  printf '{"version":1,"entries":[],"dismissed":[],"markers":[]}\n' > "$jira_work/reset.json"; routine_jira_store "$jira_work/reset.json" "$jira_dir/ledger.json"
  routine_jira_read_context "$jira_work/ctx.json"
  command jq --slurpfile p "$proposal_file" '.works=$p[0].works|.evidence=$p[0].evidence|.issues=$p[0].issues|.llm_valid=true|.llm.sections=[{target:"ABC-1",header:"작업 내용",lines:[{text:"feature implementation",evidence:$p[0].works[0].evidence}]}]' "$jira_work/ctx.json" > "$jira_work/fill-context.json"
  jq -L "$share_dir" 'include "jira"; jira_rules(.)' "$jira_work/fill-context.json" > "$jira_work/rules.json"
  jq -L "$share_dir" 'include "jira"; .proposals|jira_id_inputs' "$jira_work/rules.json" > "$jira_work/identities.json"
  routine_jira_hash_map "$jira_work/identities.json" > "$jira_work/hashes.json"
  jq -L "$share_dir" --slurpfile ctx "$jira_work/fill-context.json" --slurpfile hashes "$jira_work/hashes.json" 'include "jira"; jira_proposals_finish($ctx[0];$hashes[0])' "$jira_work/rules.json" > "$jira_work/final.json"
  fill=$(command jq -c '.proposals[]|select(.kind=="fill_description")' "$jira_work/final.json")
  [[ -n $fill ]] || fail 'T31 evidence-backed fill missing'
  command jq .payload.adf <<< "$fill" > "$jira_work/fill-adf.json"; hash=$(routine_jira_adf_hash "$jira_work/fill-adf.json")
  fill=$(command jq -c --arg hash "$hash" '.payload.adf_canon_hash=$hash' <<< "$fill")
  printf '%s\n' "$fill" > "$sandbox/fill-proposal.json"
  routine_jira_approve "$fill" "$proposal_file" false
  id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
  export JIRA_WRITE_CODE=401 JIRA_EFFECT=0
  routine_jira_apply_one "$id" || true
  jq_check 'T85 rejected authentication retains no fill marker' '.entries[0].state=="approved" and .markers==[] and all(.entries[0].attempts[];.outcome=="not_sent")' "$jira_dir/ledger.json"
  jira_abort=0; JIRA_WRITE_CODE=429
  check 'T69 no same-run retry' routine_jira_apply_one "$id"
  jq_check 'T85 rate rejection retains no fill marker' '.entries[0].state=="approved" and .markers==[] and (.entries[0].attempts|length)==2' "$jira_dir/ledger.json"
  JIRA_WRITE_CODE=403
  check 'T85 server rejection consumes fill once' routine_jira_apply_one "$id"
  jq_check 'T85 permanent marker after server rejection' '.entries[0].state=="blocked" and .markers[0].kind=="fill" and .entries[0].attempts[-1].outcome=="sent"' "$jira_dir/ledger.json"
  jq_check 'T70 second fill blocked regardless of id' 'include "jira"; . as $l|jira_fill_blocked({ledger:$l,site:"https://example.atlassian.net",account_id:"fixture-account"};{id:"100"};"other")' "$jira_dir/ledger.json"
)
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate
  printf '{"version":1,"entries":[],"dismissed":[],"markers":[]}\n' > "$jira_work/reset.json"; routine_jira_store "$jira_work/reset.json" "$jira_dir/ledger.json"
  fill=$(cat "$sandbox/fill-proposal.json")
  routine_jira_approve "$fill" "$proposal_file" false
  id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
  check 'T38 successful fill' routine_jira_apply_one "$id"
  jq_check 'T38 body and race validation' '.entries[0].state=="verified" and .markers[0].confirmed==true' "$jira_dir/ledger.json"
  # A later human description change yields one notice without a changelog read.
  command jq '.issue.fields.description={type:"doc",version:1,content:[]}' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
)
(
  command jq '.git=[]' "$sandbox/raw.json" > "$sandbox/notice-raw.json"
  export JIRA_RAW="$sandbox/notice-raw.json" JIRA_CALLS="$sandbox/notice-calls"
  : > "$JIRA_CALLS"
  check 'T42 production CLI publishes notice before its marker' "$repo/bin/routine" jira propose --no-llm
  jq_check 'T42 notice emitted once' '.notices|length==1' "$proposal_file"
  jq_check 'T42 notified hash persisted' '.markers[0].notified_hash!=null' "$JIRA_LEDGER"
  check 'T42 second production CLI notice run' "$repo/bin/routine" jira propose --no-llm
  jq_check 'T42 repeated change suppressed' '.notices|length==0' "$proposal_file"
  issue_reads=0
  while IFS= read -r request; do
    case $request in
      "GET /rest/api/3/issue/ABC-1?fields="*) issue_reads=$((issue_reads+1)) ;;
      "GET "*"/changelog?"*|"PUT "*|"DELETE "*|"POST /rest/api/3/issue "*|"POST /rest/api/3/issue/"*"/comment "*|"POST /rest/api/3/issue/"*"/transitions "*) fail 'T42 notification used a changelog or write transport' ;;
    esac
  done < "$JIRA_CALLS"
  check 'T42 two GET issue reads only' test "$issue_reads" -eq 2
)
cp "$sandbox/base-proposals.json" "$proposal_file"
echo 'PASS: Jira 승인·단일 쓰기 계약·조정·fill 표지·변경 알림 (W008–W011)'
# shellcheck source=fixtures/jira/scenarios.sh
source "$repo/tests/fixtures/jira/scenarios.sh"
# shellcheck source=fixtures/jira/followups.sh
source "$repo/tests/fixtures/jira/followups.sh"
# shellcheck source=fixtures/jira/finish.sh
source "$repo/tests/fixtures/jira/finish.sh"
# shellcheck source=fixtures/jira/final-regressions.sh
source "$repo/tests/fixtures/jira/final-regressions.sh"
# shellcheck source=fixtures/jira/review-regressions.sh
source "$repo/tests/fixtures/jira/review-regressions.sh"
# shellcheck source=fixtures/jira/scale-regressions.sh
source "$repo/tests/fixtures/jira/scale-regressions.sh"
# shellcheck source=fixtures/jira/llm-responses.sh
source "$repo/tests/fixtures/jira/llm-responses.sh"
# shellcheck source=fixtures/jira/quality-regressions.sh
source "$repo/tests/fixtures/jira/quality-regressions.sh"
