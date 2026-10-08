#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2016,SC2030,SC2031 # Parent fixture supplies paths, helpers and settings; literal jq programs.
(
  check 'BUDGET production PR/Git, connection, quotas, stable links and recent visits' jq -L "$share_dir" -ne -f "$repo/tests/fixtures/jira/llm-budget.jq"
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  (
    routine_jira_session; routine_jira_lock apply; reset_jira_ledger
    printf '{"version":1,"links":[],"rejections":[]}\n' > "$jira_work/empty-links.json"
    routine_jira_store "$jira_work/empty-links.json" "$jira_dir/links.json"
  )
  ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="omp"' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  command jq '
    .git=[]|.prs=[range(0;126) as $i|{roles:["author"],repository:"example",url:("https://example/pull/"+($i|tostring)),number:($i+1),state:"OPEN",commits_complete:true,commit_oids:[],
      title:((if $i<110 then "ABC-1 " else "" end)+"feature implementation "+("x"*2000)),
      activity:[{kind:"created",at:("2026-10-08T00:00:00."+($i+1000|tostring)+"Z")}]}]|
    .sessions=[range(0;77) as $i|{id:("scale-session-"+($i|tostring)),source:"omp",title:("session "+("x"*2000)),last_ts:"2026-10-08T00:00:00Z",
      reports:[range(0;(if $i<38 then 2 else 1 end)) as $r|{ts:("2026-10-08T00:00:00."+($i*2+$r+1000|tostring)+"Z"),text:("report "+("x"*2000))}]}]
    ' "$sandbox/raw.json" > "$sandbox/scale-raw.json"
  export JIRA_RAW="$sandbox/scale-raw.json"
  before=$(wc -l < "$JIRA_EFFECTS")
  check 'SCALE production large-input proposal' "$repo/bin/jira-propose"
  jq_check 'SCALE full evidence and works survive prompt-only reduction' '(.works|length)==126 and (.evidence|length)==318 and .llm.valid' "$proposal_file"
  command jq -Rrs 'capture("ROUTINE_DATA_BEGIN\\n(?<data>[\\s\\S]*)\\nROUTINE_DATA_END").data|fromjson' "$JIRA_PROMPT" > "$sandbox/scale-input.json"
  jq_check 'SCALE deterministic work/evidence/report/session bounds and 400-character excerpts' '
    (.works|length)==30 and (.evidence|length)<=60 and (.unattached_reports|length)==10 and (.session_hints|length)==10 and
    all(.evidence[],.unattached_reports[],.session_hints[];(.text|length)<=400) and
    (.works[:16]|all(.[];(.keys|length)==0)) and (.works[16:]|all(.[];(.keys|length)>0)) and
    (.works[0].evidence==["pr:https://example/pull/125"]) and
    all(.works[16:][];(.evidence|length)<=1)
    ' "$sandbox/scale-input.json"
  # Candidates, visits and source ordering are checked against the same production helper.
  jq_check 'SCALE candidate/visit bounds and input-order independence' 'include "jira";
    . as $p|{site:.site,account_id:.account_id,config:$ARGS.named.routine.jira,links:{links:[]},works:.works,evidence:.evidence,issues:.issues} as $ctx|
    [range(0;40)|{key:("ABC-"+(.+1|tostring)),fields:{summary:("x"*300),created:"2026-10-08T00:00:00Z",updated:"2026-10-08T00:00:00Z",issuetype:{name:"작업"},status:{name:"시작"},description:null}}] as $c|
    [range(0;40)|"ABC-"+(.+1|tostring)] as $v|
    ($ctx|jira_llm_input($c;$v)) as $input|
    ($input.candidates|length)==20 and ($input.visit_hints|length)==20 and all($input.candidates[];(.summary|length)<=120) and
    $input==($ctx|.works|=reverse|.evidence|=reverse|jira_llm_input(($c|reverse);$v)) and $input.visit_hints==$v[:20]
    ' "$proposal_file"
  check 'SCALE propose still produces no write effects' test "$(wc -l < "$JIRA_EFFECTS")" = "$before"
)
(
  export JIRA_CANDIDATES="$sandbox/model-candidates" JIRA_REQUEST_LOG="$sandbox/model-candidate-requests"
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  : > "$JIRA_REQUEST_LOG"
  command jq -n '[range(0;21) as $i|{key:("ABC-"+($i+99|tostring)),fields:{summary:(if $i==0 then "feature implementation" else "unrelated catalog item "+($i|tostring) end),created:(if $i==0 then "2020-01-01T00:00:00Z" else "2026-10-07T00:00:00Z" end),updated:(if $i==0 then "2026-10-08T00:00:00Z" else "2026-10-07T00:00:00Z" end),issuetype:{name:"작업"},status:{name:"시작"},description:null}}]' > "$JIRA_CANDIDATES"
  ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="omp"' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  before=$(wc -l < "$JIRA_EFFECTS")
  check 'CANDIDATE production HTTP candidate field selection' "$repo/bin/jira-propose"
  jq_check 'CANDIDATE production request explicitly includes updated' 'any(.[];.body.jql|startswith("assignee = currentUser()")) and all(.[]|select(.body.jql|startswith("assignee = currentUser()"));.body.fields|index("updated")!=null)' -s "$JIRA_REQUEST_LOG"
  jq_check 'CANDIDATE old-created newest-updated issue retained above the 20-item cutoff' 'capture("ROUTINE_DATA_BEGIN\\n(?<data>[\\s\\S]*)\\nROUTINE_DATA_END").data|fromjson|(.candidates|length)==20 and .candidates[0].key=="ABC-99"' -Rrs "$JIRA_PROMPT"
  check 'CANDIDATE selection has no write effects' test "$(wc -l < "$JIRA_EFFECTS")" = "$before"
)
(
  export JIRA_GUIDE_CALLS="$sandbox/guide-security-calls" JIRA_GUIDE_INPUT="$sandbox/guide-security-input"
  routine_jira_token_help 2> "$sandbox/token-help"
  guide=$(command jq -Rrs 'split("\n")|map(select(startswith("read -rs ")))[0]' "$sandbox/token-help")
  : > "$JIRA_GUIDE_CALLS"
  printf '\n' | /bin/zsh -fc "security() { printf 'call\\n' >> \"\$JIRA_GUIDE_CALLS\"; cat > \"\$JIRA_GUIDE_INPUT\"; }; $guide" > /dev/null
  check 'TOKEN empty hidden input never invokes security interactive mode' test ! -s "$JIRA_GUIDE_CALLS"
  token=$(printf '%0190d' 0)
  printf '%s\n' "$token" | /bin/zsh -fc "security() { printf 'call\\n' >> \"\$JIRA_GUIDE_CALLS\"; cat > \"\$JIRA_GUIDE_INPUT\"; }; $guide" > /dev/null
  check 'TOKEN inline guide preserves all 190 fixture characters through standard input' test "$(cat "$JIRA_GUIDE_INPUT")" = "add-generic-password -U -s routine-automation.jira -a <이메일> -w $token"
  jq_check 'TOKEN guide names account setting and empty-input guard without requiring installed docs' 'contains("jira.email") and contains("[[ -n $t ]]") and contains("security -i")' -Rrs "$sandbox/token-help"
)
(
  # A merged PR renders once while both event identities and suppression markers remain intact.
  jq_check 'COMMENT merged PR is one line without dropping event identities' 'include "jira";
    .works[0].events=[{id:"ev-link",kind:"pr_link",evidence_id:"pr:merged",at:"2026-10-08T00:00:00Z",text:"https://example/pull/7"},{id:"ev-merged",kind:"pr_merged",evidence_id:"pr:merged",at:"2026-10-08T00:00:00Z",text:"https://example/pull/7"}]|
    jira_rules(.)|.proposals[]|select(.kind=="comment")|
    .payload.text=="PR 병합: https://example/pull/7" and (.events|sort)==["ev-link","ev-merged"] and (.payload.events|length)==2
    ' "$sandbox/rules-context.json"
)
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  (
    routine_jira_session; routine_jira_lock apply; reset_jira_ledger
    printf '{"version":1,"links":[],"rejections":[]}\n' > "$jira_work/empty-links.json"
    routine_jira_store "$jira_work/empty-links.json" "$jira_dir/links.json"
  )
  ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="omp"|.jira.repos.example.prefix=""' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  jq_check 'PREFIX empty mapping is valid but null and whitespace are not' 'include "config"; (jira_required_errors|index("jira.repos.example")==null) and all([null," ","\t"][];. as $value|$ARGS.named.routine|.jira.repos.example.prefix=$value|jira_required_errors|index("jira.repos.example")!=null)' <<< "$ROUTINE_SETTINGS"
  command jq '.git[0].subject="feature implementation"' "$sandbox/raw.json" > "$sandbox/prefixless-raw.json"
  export JIRA_RAW="$sandbox/prefixless-raw.json"
  check 'PREFIX production prefixless creation proposal' "$repo/bin/jira-propose"
  jq_check 'PREFIX proposal has no leading whitespace' 'any(.proposals[];.kind=="create_issue" and .payload.prefix=="" and .payload.summary=="feature implementation")' "$proposal_file"
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate
  create=$(command jq -c '.proposals[]|select(.kind=="create_issue")' "$proposal_file")
  routine_jira_approve "$create" "$proposal_file" false
  id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
  routine_jira_apply_one "$id"
  jq_check 'PREFIX single-write contract accepts the exact prefixless title' '.entries[0].state=="verified" and .entries[0].request.body.fields.summary=="feature implementation"' "$jira_dir/ledger.json"
)
for result in timeout exit empty non-json schema llm-error; do
  (
    export JIRA_MODEL_RESULT=$result JIRA_MODEL_CALLS="$sandbox/scale-model-calls" JIRA_RAW="$sandbox/raw.json"
    : > "$JIRA_MODEL_CALLS"
    ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="omp"' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
    if [[ $result == llm-error ]]; then
      rm "$sandbox/stubs/claude"; ln -s "$repo/tests/fixtures/jira/omp.sh" "$sandbox/stubs/claude"
      trap 'rm -f "$sandbox/stubs/claude"; ln -s "$repo/tests/fixtures/jira/command.sh" "$sandbox/stubs/claude"' EXIT
      unset -f claude
      ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="claude"' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
    fi
    before=$(wc -l < "$JIRA_EFFECTS")
    "$repo/bin/jira-propose" > "$sandbox/model-failure-output" 2>&1
    reason=$result; code=0
    case $result in timeout) code=124 ;; exit) reason=process_exit; code=17 ;; empty) reason=empty_output ;; non-json) reason=non_json ;; schema) reason=schema_mismatch ;; llm-error) reason=llm_error ;; esac
    jq_check "MODEL $result persists safe structured failure reasons for both attempts" '.llm.valid==false and ([.errors[]|select(.source=="llm" and .reason==$reason and .exit_code==$code)]|map(.attempt))==[1,2]' --arg reason "$reason" --argjson code "$code" "$proposal_file"
    check "MODEL $result stays bounded to two calls" test "$(wc -l < "$JIRA_MODEL_CALLS" | tr -d ' ')" = 2
    if [[ $result == non-json || $result == schema ]]; then
      jq_check 'MODEL malformed JSON retry includes one-object guidance' 'contains("JSON 객체 하나만 다시 출력하세요.")' -Rrs "$JIRA_PROMPT"
    else jq_check 'MODEL execution failure retry does not claim invalid JSON' 'contains("이전 응답")|not' -Rrs "$JIRA_PROMPT"; fi
    if grep -q 'fixture-model-secret' "$proposal_file" "$sandbox/model-failure-output"; then fail 'MODEL failure leaked stderr/stdout content'; fi
    check "MODEL $result causes no writes" test "$(wc -l < "$JIRA_EFFECTS")" = "$before"
  )
done
printf 'PASS: Jira 대규모 프롬프트 상한·최근/미연결 우선·LLM 실패 원인/재시도·PR 병합 단일 줄·빈 제목 머리말\n'
