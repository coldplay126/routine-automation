#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2016,SC2030,SC2031,SC2254 # Isolated subshells; jq literals; intentional call-pattern globs.
reset_jira_ledger() {
  printf '{"version":1,"entries":[],"dismissed":[],"markers":[]}\n' > "$jira_work/reset.json"
  routine_jira_store "$jira_work/reset.json" "$jira_dir/ledger.json"
}
call_count() {
  local pattern=$1 line count=0
  while IFS= read -r line; do case $line in $pattern) count=$((count+1));; esac; done < "$JIRA_CALLS"
  printf '%s\n' "$count"
}
(
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate
  export JIRA_ROUTES="$jira_work/routes.json"
  printf '{"jql":"project = ABC","maxResults":100}\n' > "$jira_work/query.json"
  command jq -n '[{method:"POST",prefix:"/rest/api/3/search/jql",token:null,body:{isLast:false,nextPageToken:"second",issues:[{key:"ABC-10"}]}},{method:"POST",prefix:"/rest/api/3/search/jql",token:"second",body:{isLast:false,nextPageToken:"third",issues:[{key:"ABC-11"}]}},{method:"POST",prefix:"/rest/api/3/search/jql",token:"third",body:{isLast:true,issues:[{id:"99",key:"ABC-99",fields:{summary:"feature implementation"}}]}}]' > "$JIRA_ROUTES"
  check 'T51 third search page' routine_jira_pages search /rest/api/3/search/jql "$jira_work/query.json" "$jira_work/results.json"
  jq_check 'T51 late page retained' '.[-1].key=="ABC-99"' "$jira_work/results.json"
  for failure in 500 429; do
    command jq --argjson failure "$failure" '.[1].http=$failure' "$JIRA_ROUTES" > "$JIRA_ROUTES.new"; mv "$JIRA_ROUTES.new" "$JIRA_ROUTES"
    if routine_jira_pages search /rest/api/3/search/jql "$jira_work/query.json" "$jira_work/results.json"; then fail 'T52 partial search treated as complete'; fi
  done
  for body in '{"issues":[]}' '{"isLast":false,"nextPageToken":"same","issues":[]}'; do
    command jq -n --argjson body "$body" '[{method:"POST",prefix:"/rest/api/3/search/jql",body:$body}]' > "$JIRA_ROUTES"
    if routine_jira_pages search /rest/api/3/search/jql "$jira_work/query.json" "$jira_work/results.json" 2; then fail 'T53 incomplete/repeated-token search accepted'; fi
  done
  command jq -n '[{method:"GET",prefix:"/rest/api/3/issue/createmeta/ABC/issuetypes/10?startAt=0",body:{startAt:0,maxResults:1,total:2,fields:[{fieldId:"summary",required:true,name:"요약"}]}},{method:"GET",prefix:"/rest/api/3/issue/createmeta/ABC/issuetypes/10?startAt=1",body:{startAt:1,maxResults:1,total:2,fields:[{fieldId:"custom",required:true,name:"추가 필수"}]}}]' > "$JIRA_ROUTES"
  if routine_jira_meta ABC 10 "$jira_work/meta.json"; then fail 'T62 second-page required field'; fi
  command jq '.[1].http=500' "$JIRA_ROUTES" > "$JIRA_ROUTES.new"; mv "$JIRA_ROUTES.new" "$JIRA_ROUTES"
  if routine_jira_meta ABC 10 "$jira_work/meta.json"; then fail 'T62 partial metadata accepted'; fi
  command jq -n '[{method:"GET",prefix:"/rest/api/3/issuetype/10",body:{hierarchyLevel:1,name:"epic"}}]' > "$JIRA_ROUTES"
  if routine_jira_meta ABC 10 "$jira_work/meta.json"; then fail 'T62 epic creation'; fi
  command jq -n '[{method:"GET",prefix:"/rest/api/3/issue/ABC-1/changelog?startAt=0",body:{startAt:0,isLast:false,values:[{created:"2026-10-01T00:00:00Z",items:[]}]}},{method:"GET",prefix:"/rest/api/3/issue/ABC-1/changelog?startAt=1",body:{startAt:1,isLast:true,values:[{created:"2026-10-02T00:00:00Z",author:{accountId:"other"},items:[{field:"description",fromString:"human content"}]}]}}]' > "$JIRA_ROUTES"
  check 'T39 changelog all pages' routine_jira_pages changelog /rest/api/3/issue/ABC-1/changelog '' "$jira_work/history.json"
  jq_check 'T39 prior human content on final page' 'include "jira"; jira_history("fixture-account")|.prior_content and .last_by_me==false' "$jira_work/history.json"
  printf '%s\n' 'wrong-start-time' > "$jira_dir/.lock/lstart"
  if routine_jira_lock_live "$jira_dir/.lock"; then fail 'T74 reused pid considered live'; fi
  printf '%s\n' "$jira_lstart" > "$jira_dir/.lock/lstart"
  if routine_jira_lock review; then fail 'T74 nested review accepted'; else [[ $? == 4 ]] || fail 'T74 nested lock exit'; fi
)
echo 'PASS: Jira 전체 페이지·부분 실패·생성 메타·잠금 회귀 (W003/W007)'
for change in description updated assignee id project hierarchy; do
  (
    cp "$sandbox/server-initial.json" "$JIRA_SERVER"
    routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
    fill=$(cat "$sandbox/fill-proposal.json")
    routine_jira_approve "$fill" "$proposal_file" false
    id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
    command jq --arg change "$change" 'if $change=="description" then .issue.fields.description={type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"[사전조건]"}]}]} elif $change=="updated" then .issue.fields.updated="2026-10-03T00:00:00Z" elif $change=="assignee" then .issue.fields.assignee.accountId="other" elif $change=="id" then .issue.id="999" elif $change=="project" then .issue.fields.project.key="DEF" else .issue.fields.issuetype.hierarchyLevel=1 end' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
    before=$(call_count 'PUT *')
    check "T27/T35/T36 fill conflict $change" routine_jira_apply_one "$id"
    jq_check "T27/T35/T36 no overwritten $change" '.entries[0].state=="conflict"' "$jira_dir/ledger.json"
    check 'T35 PUT zero' test "$(call_count 'PUT *')" = "$before"
  )
done
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock review; routine_jira_authenticate; reset_jira_ledger
  fill=$(cat "$sandbox/fill-proposal.json")
  command jq '.issue.fields.updated="2026-10-03T00:00:00Z"' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
  routine_jira_approve "$fill" "$proposal_file" false
  jq_check 'T34 changed proposal cannot approve' '.entries|length==0' "$jira_dir/ledger.json"
)
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
  routine_jira_approve "$(cat "$sandbox/fill-proposal.json")" "$proposal_file" false
  id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
  export JIRA_RACE=1
  check 'T37 race-detection apply' routine_jira_apply_one "$id" > "$jira_work/race-output"
  jq_check 'T37 race is not verified' '.entries[0].state=="verify_failed" and (.entries[0].message|contains("확인·복구")) and .markers[0].confirmed' "$jira_dir/ledger.json"
  jq_check 'T37 race warning visible with URL and manual restoration' 'contains("https://example.atlassian.net/browse/ABC-1") and contains("복구")' -Rs "$jira_work/race-output"
)
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
  comment=$(command jq -c '.proposals[]|select(.kind=="comment")' "$proposal_file")
  dependent=$(command jq -c '.depends_on=["p-missing-link"]|.dependency_evidence=.evidence' <<< "$comment")
  routine_jira_approve "$dependent" "$proposal_file" false
  jq_check 'T21 final declined link prevents approval' '.entries|length==0' "$jira_dir/ledger.json"
  routine_jira_link_save "$dependent" review ABC-1
  routine_jira_approve "$dependent" "$proposal_file" false
  id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
  printf '{"version":1,"links":[],"rejections":[]}\n' > "$jira_work/empty-links.json"; routine_jira_store "$jira_work/empty-links.json" "$jira_dir/links.json"
  check 'T21 removed dependency blocks apply' routine_jira_apply_one "$id"
  jq_check 'T21 removed dependency state' '.entries[0].state=="blocked"' "$jira_dir/ledger.json"
)
for code in 500 429 7 28; do
  (
    cp "$sandbox/server-initial.json" "$JIRA_SERVER"
    routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
    comment=$(command jq -c '.proposals[]|select(.kind=="comment")' "$proposal_file")
    routine_jira_approve "$comment" "$proposal_file" false
    id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
    export JIRA_EFFECT=0 JIRA_WRITE_CODE=200 JIRA_WRITE_EXIT=0
    if ((code>=100)); then JIRA_WRITE_CODE=$code; else JIRA_WRITE_EXIT=$code; fi
    before=$(call_count 'POST /rest/api/3/issue/ABC-1/comment *')
    check 'T69 one transport attempt' routine_jira_apply_one "$id"
    check 'T69 no transport retry' test "$(call_count 'POST /rest/api/3/issue/ABC-1/comment *')" = "$((before+1))"
    if [[ $code == 429 || $code == 7 ]]; then
      jq_check 'T69 definitely not sent' '.entries[0].state=="approved" and .entries[0].attempts[0].outcome=="not_sent"' "$jira_dir/ledger.json"
    else
      jq_check 'T49/T69 ambiguous transport unknown' '.entries[0].state=="unknown"' "$jira_dir/ledger.json"
      unset JIRA_WRITE_CODE JIRA_WRITE_EXIT
      for retry in 1 2 3; do check "T49 read-only recovery $retry" routine_jira_reconcile "$id"; done
      jq_check 'T49 absent effect remains unknown' '.entries[0].state=="unknown"' "$jira_dir/ledger.json"
      check 'T49 unknown never resent' test "$(call_count 'POST /rest/api/3/issue/ABC-1/comment *')" = "$((before+1))"
    fi
  )
done
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
  comment=$(command jq -c '.proposals[]|select(.kind=="comment")' "$proposal_file")
  routine_jira_approve "$comment" "$proposal_file" false
  id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
  command jq --arg at "$(date -u -v-25H '+%Y-%m-%dT%H:%M:%SZ')" '.entries[0].approved_at=$at' "$jira_dir/ledger.json" > "$jira_work/old.json"; routine_jira_store "$jira_work/old.json" "$jira_dir/ledger.json"
  before=$(call_count 'POST /rest/api/3/issue/ABC-1/comment *')
  routine_jira_apply_one "$id"
  jq_check 'T71 stale approval void' '.entries[0].state=="void"' "$jira_dir/ledger.json"
  check 'T71 void not sent' test "$(call_count 'POST /rest/api/3/issue/ABC-1/comment *')" = "$before"
)
echo 'PASS: Jira 변경 충돌·경쟁 감지·의존 연결·결과 불명 회귀 (W008/W009)'
export JIRA_OMP_STUB="$repo/tests/fixtures/jira/omp.sh" JIRA_PROMPT="$sandbox/jira-prompt" JIRA_COLLECTION_CALLS="$sandbox/collect-calls"
ln -s "$JIRA_OMP_STUB" "$sandbox/stubs/omp"
ln -s "$JIRA_OMP_STUB" "$HOME/.local/bin/omp"
omp() { "$JIRA_OMP_STUB" "$@"; }; export -f omp
# Replace the suite's collector wrapper with the same controlled fixture, including virtual-time support.
rm -f "$sandbox/stubs/gtimeout"; ln -s "$repo/tests/fixtures/jira/gtimeout.sh" "$sandbox/stubs/gtimeout"
for mode in normal unknown; do
  (
    cp "$sandbox/server-initial.json" "$JIRA_SERVER"
    command jq '.git[0].subject="feature implementation"' "$sandbox/raw.json" > "$sandbox/create-raw.json"
    export JIRA_RAW="$sandbox/create-raw.json"
    routine_jira_session; routine_jira_lock apply; reset_jira_ledger
    printf '{"version":1,"links":[],"rejections":[]}\n' > "$jira_work/empty-links.json"; routine_jira_store "$jira_work/empty-links.json" "$jira_dir/links.json"
  )
  (
    ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="omp"' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
    export JIRA_RAW="$sandbox/create-raw.json"
    before=$(call_count 'POST /rest/api/3/issue *')
    check "T59/T42 create proposal $mode" "$repo/bin/jira-propose"
    jq_check 'T59 create proposal and typed model output' '.llm.valid and any(.proposals[];.kind=="create_issue" and (.payload.summary|startswith("[BACK] ")))' "$proposal_file"
    routine_jira_session; routine_jira_lock apply; routine_jira_authenticate
    create=$(command jq -c '.proposals[]|select(.kind=="create_issue")' "$proposal_file")
    printf '%s\n' "$create" > "$sandbox/create-proposal.json"; cp "$proposal_file" "$sandbox/create-source.json"
    routine_jira_approve "$create" "$proposal_file" false
    id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
    jq_check 'T59 account assigned only in approved request' '.entries[0].request.body.fields.assignee.accountId=="fixture-account"' "$jira_dir/ledger.json"
    [[ $mode != unknown ]] || export JIRA_WRITE_EXIT=28
    check "T42 creation apply $mode" routine_jira_apply_one "$id"
    if [[ $mode == unknown ]]; then
      jq_check 'T58 unknown create marker before recovery' '.entries[0].state=="unknown" and .markers[0].kind=="create" and .markers[0].issue_id==null and .markers[0].confirmed==false' "$jira_dir/ledger.json"
      unset JIRA_WRITE_EXIT
      check 'T58 real read reconciliation' routine_jira_reconcile "$id"
    fi
    jq_check 'T42 created marker reconciled and confirmed' '.entries[0].state=="verified" and .markers[0].kind=="create" and .markers[0].issue_id=="200" and .markers[0].key=="ABC-2" and .markers[0].confirmed==true' "$jira_dir/ledger.json"
    jq_check 'T58 evidence links persisted without ses ids' '.links|length>0 and all(.[];.key=="ABC-2" and (.evidence_id|startswith("ses:")|not))' "$jira_dir/links.json"
    check 'T42 create POST exactly one' test "$(call_count 'POST /rest/api/3/issue *')" = "$((before+1))"
  )
  command jq '.issue.fields.description={type:"doc",content:[]}' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
  command jq '.git=[]|.prs=[]|.sessions=[]' "$sandbox/raw.json" > "$sandbox/empty-raw.json"
  (
    export JIRA_RAW="$sandbox/empty-raw.json"
    before_history=$(call_count 'GET */changelog?*'); before_writes=$(call_count 'PUT *')
    check "T42 first complete propose after $mode creation" "$repo/bin/jira-propose" --no-llm
    jq_check 'T42 first creation notice once and no fill/create' '(.notices|length)==1 and all(.proposals[];.kind!="fill_description" and .kind!="create_issue")' "$proposal_file"
    check "T42 second complete propose after $mode creation" "$repo/bin/jira-propose" --no-llm
    jq_check 'T42 next propose suppresses notice' '(.notices|length)==0 and all(.proposals[];.kind!="fill_description" and .kind!="create_issue")' "$proposal_file"
    check 'T42 notices never need changelog' test "$(call_count 'GET */changelog?*')" = "$before_history"
    check 'T42 notices never PUT' test "$(call_count 'PUT *')" = "$before_writes"
    jq_check 'T42 creation notified hash persisted' '.markers[0].notified_hash!=null and .markers[0].confirmed' "$JIRA_LEDGER"
  )
done
(
  export JIRA_TOKEN_ERROR=1
  before=$(wc -l < "$JIRA_COLLECTION_CALLS")
  if "$repo/bin/jira-propose" --no-llm; then fail 'T76 bad authentication accepted'; fi
  check 'T76 authentication before collection' test "$(wc -l < "$JIRA_COLLECTION_CALLS")" = "$before"
)
(
  export JIRA_CLOCK="$sandbox/clock" JIRA_MODEL_TIMEOUT=1 JIRA_MODEL_CALLS="$sandbox/model-timeouts" JIRA_DATE_STUB="$repo/tests/fixtures/jira/date.sh"
  /bin/date +%s > "$JIRA_CLOCK"; start=$(cat "$JIRA_CLOCK")
  ln -s "$JIRA_DATE_STUB" "$sandbox/stubs/date"
  export JIRA_RAW="$sandbox/raw.json"
  check 'T75 bounded nonresponding model' "$repo/bin/jira-propose"
  check 'T75 persisted before 540-second deadline' test "$(($(cat "$JIRA_CLOCK")-start))" -le 540
  jq_check 'T75 no-LLM fallback persisted' '.llm.valid==false and any(.errors[];.message|contains("LLM"))' "$proposal_file"
  /bin/date +%s > "$JIRA_CLOCK"; : > "$JIRA_MODEL_CALLS"
  JIRA_MODEL_CLOCK_JUMP=125 check 'MODEL clock jump exhausts retry deadline' "$repo/bin/jira-propose"
  jq_check 'MODEL deadline skips a call with null exit code and safe classification' 'any(.errors[];.source=="llm" and .reason=="deadline" and .exit_code==null and (.message|contains("호출 없음")))' "$proposal_file"
  check 'MODEL exhausted retry deadline makes no second model call' test "$(wc -l < "$JIRA_MODEL_CALLS" | tr -d ' ')" = 1
  rm -f "$sandbox/stubs/date"
)
echo 'PASS: Jira 생성·읽기 조정·생성 본문 알림 전체 통합·LLM 마감 (W007/W008/W011b)'
