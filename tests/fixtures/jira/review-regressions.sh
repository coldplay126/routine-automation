#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2153,SC2030,SC2031,SC2016 # Suite fixtures and literal jq programs.
# These helpers build fixtures through the shipping evidence, identity, rules and request functions.
review_boot() {
  ROUTINE_SETTINGS=$(command jq -c '.jira.enabled=true|.jira.site="https://example.atlassian.net"|.draft.llm.engine="omp"' <<< "$ROUTINE_SETTINGS")
  routine_save_config "$ROUTINE_SETTINGS"
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock "$1"; routine_jira_authenticate; reset_jira_ledger
  printf '{"version":1,"links":[],"rejections":[]}\n' > "$jira_work/empty-links.json"
  routine_jira_store "$jira_work/empty-links.json" "$jira_dir/links.json"
}
review_hash_array() {
  local input=$1 output=$2
  jq -L "$share_dir" 'include "jira"; jira_id_inputs' "$input" > "$jira_work/review-ids.json"
  routine_jira_hash_map "$jira_work/review-ids.json" > "$jira_work/review-hashes.json"
  jq -L "$share_dir" --slurpfile hashes "$jira_work/review-hashes.json" 'include "jira"; jira_with_ids($hashes[0])' "$input" > "$output"
}
review_context() {
  local raw=$1 context=$2 key
  routine_jira_read_context "$context"
  jq -L "$share_dir" 'include "jira"; jira_evidence({"/fixture/example":"example"})' "$raw" > "$jira_work/review-evidence-raw.json"
  review_hash_array "$jira_work/review-evidence-raw.json" "$jira_work/review-evidence.json"
  jq -L "$share_dir" 'include "jira"; jira_works' "$jira_work/review-evidence.json" > "$jira_work/review-works-raw.json"
  review_hash_array "$jira_work/review-works-raw.json" "$jira_work/review-works.json"
  jq --slurpfile evidence "$jira_work/review-evidence.json" --slurpfile works "$jira_work/review-works.json" '.evidence=$evidence[0]|.works=$works[0]|.allowed_keys=["ABC-1","ABC-2"]|.llm_valid=true|.llm={merge:[],attach:[],links:[],create:[],sections:[]}' "$context" > "$context.new"; mv "$context.new" "$context"
  review_events "$context"
  command jq '.llm.sections=[.works[]|{target:(.keys[0] // .id),header:"작업 내용",lines:[{text:"feature implementation",evidence:[.evidence[0]]}]}]' "$context" > "$context.new"; mv "$context.new" "$context"
  while IFS= read -r key; do routine_jira_propose_issue "$key" "$context"; done < <(command jq -r '[.works[].keys[]]|unique[]' "$context")
}
review_events() {
  local context=$1
  jq -L "$share_dir" 'include "jira"; .evidence as $e|.works|=map(.events=jira_events($e))' "$context" > "$context.new"; mv "$context.new" "$context"
  jq -L "$share_dir" 'include "jira"; [.works[].events[]]|jira_id_inputs' "$context" > "$jira_work/review-ids.json"
  routine_jira_hash_map "$jira_work/review-ids.json" > "$jira_work/review-hashes.json"
  jq -L "$share_dir" --slurpfile hashes "$jira_work/review-hashes.json" 'include "jira"; .works|=map(.events|=jira_with_ids($hashes[0]))' "$context" > "$context.new"; mv "$context.new" "$context"
}
review_proposals() {
  local context=$1 output=$2
  jq -L "$share_dir" 'include "jira"; jira_rules(.)' "$context" > "$jira_work/review-rules.json"
  jq -L "$share_dir" 'include "jira"; .proposals|jira_id_inputs' "$jira_work/review-rules.json" > "$jira_work/review-ids.json"
  routine_jira_hash_map "$jira_work/review-ids.json" > "$jira_work/review-hashes.json"
  jq -L "$share_dir" --slurpfile context "$context" --slurpfile hashes "$jira_work/review-hashes.json" 'include "jira"; jira_proposals_finish($context[0];$hashes[0])' "$jira_work/review-rules.json" > "$jira_work/review-finished.json"
  jq -L "$share_dir" 'include "jira"; [.proposals[]|select(.payload.adf!=null)|{ref:.id,value:(.payload.adf|jira_adf_canon)}]' "$jira_work/review-finished.json" > "$jira_work/review-ids.json"
  routine_jira_hash_map "$jira_work/review-ids.json" > "$jira_work/review-hashes.json"
  command jq --slurpfile context "$context" --slurpfile finished "$jira_work/review-finished.json" --slurpfile hashes "$jira_work/review-hashes.json" '.evidence=$context[0].evidence|.works=$context[0].works|.issues=$context[0].issues|.proposals=($finished[0].proposals|map(if .payload.adf!=null then .payload.adf_canon_hash=("sha256:"+$hashes[0][.id]) else . end))|.questions=$finished[0].questions|.notices=[]|.errors=$context[0].errors' "$sandbox/base-proposals.json" > "$output"
}
(
  review_boot propose
  command jq '.git[0].subject="feature implementation"|.errors=[]' "$sandbox/raw.json" > "$jira_work/unlinked.json"
  review_context "$jira_work/unlinked.json" "$jira_work/context.json"
  routine_jira_duplicate_search ABC 'feature implementation' "$jira_work/review-evidence.json" "$jira_work/duplicate.json"
  routine_jira_meta ABC 10 "$jira_work/meta.json"
  command jq --slurpfile search "$jira_work/duplicate.json" --slurpfile meta "$jira_work/meta.json" '.works[0].id as $id|.llm.create=[{work:$id,summary:"feature implementation"}]|.duplicates[$id]=$search[0]|.create_meta.ABC=$meta[0]' "$jira_work/context.json" > "$jira_work/new-context.json"
  jq_check 'F1 official fields metadata permits normal creation' '.ok==true' "$jira_work/meta.json"
  for target in missing moved epic outside; do
    command jq --arg variant "$target" --slurpfile issue "$sandbox/rules-context.json" '.links.links=[{site:.site,account_id:.account_id,evidence_id:.works[0].evidence[0],key:"ABC-1"}]|.issues=$issue[0].issues|if $variant=="missing" then .issues={} elif $variant=="moved" then .issues["ABC-1"].key="ABC-9" elif $variant=="epic" then .issues["ABC-1"].type.hierarchy_level=1 else .issues["ABC-1"].project="DEF" end' "$jira_work/new-context.json" > "$jira_work/strong-context.json"
    jq_check "F2 strong stored overlap blocks create after $target target filtering" 'include "jira"; jira_rules(.)|all(.proposals[];.kind!="create_issue") and (.questions|length)>0' "$jira_work/strong-context.json"
  done
  # A report overlap is a candidate, never an automatically confirmed stored connection.
  command jq '.sessions=[{source:"omp",id:"same-session",cwd:"/fixture/example",last_ts:"2026-10-08T02:00:00Z",reports:[{ts:"2026-10-07T02:00:00Z",text:"first feature report"},{ts:"2026-10-08T02:00:00Z",text:"different feature report"}]}]' "$jira_work/unlinked.json" > "$jira_work/reports.json"
  review_context "$jira_work/reports.json" "$jira_work/report-context.json"
  command jq '.evidence|map(select(.kind=="report"))' "$jira_work/report-context.json" > "$jira_work/reports-evidence.json"
  for same in true false; do
    jq -L "$share_dir" --argjson same "$same" --slurpfile issue "$sandbox/rules-context.json" --slurpfile reports "$jira_work/reports-evidence.json" 'include "jira"; .evidence as $e|(.works|jira_apply_llm($e;{merge:[],attach:[{evidence:$reports[0][if $same then 0 else 1 end].id,work:.[0].id}],links:[],create:[],sections:[]})) as $attached|.works=$attached.works|.links.links=[{site:.site,account_id:.account_id,evidence_id:$reports[0][0].id,key:"ABC-1"}]|.issues=$issue[0].issues|.works[0].id as $id|.llm.create=[{work:$id,summary:"feature implementation"}]|.duplicates[$id]={complete:true,matches:[],queries:2}|.create_meta.ABC={ok:true,name:"작업"}' "$jira_work/report-context.json" > "$jira_work/overlap.json"
    if [[ $same == true ]]; then
      jq_check 'T19 same report on next-day commit work requires report_overlap approval' 'include "jira"; . as $ctx|.works[0]|jira_links_for($ctx)|.[0].basis=="candidate" and .[0].origin=="report_overlap"' "$jira_work/overlap.json"
      command jq '.links.rejections=.links.links' "$jira_work/overlap.json" > "$jira_work/rejected.json"
      jq_check 'T19 rejecting overlap suppresses the repeated link and permits creation' 'include "jira"; jira_rules(.)|all(.proposals[];.kind!="link") and any(.proposals[];.kind=="create_issue")' "$jira_work/rejected.json"
    else jq_check 'T19 different report from same session is not stored' 'include "jira"; . as $ctx|.works[0]|jira_links_for($ctx)|length==0' "$jira_work/overlap.json"; fi
  done
)
(
  review_boot apply
  command jq '.git+=[.git[0]|.sha="2222222222222222222222222222222222222222"|.subject="feature implementation"]|.errors=[]' "$sandbox/raw.json" > "$jira_work/mixed.json"
  review_context "$jira_work/mixed.json" "$jira_work/context.json"
  command jq '.llm.links=[.works[]|select(.keys==[])|{work:.id,key:"ABC-1",reason:"specific shared feature"}]' "$jira_work/context.json" > "$jira_work/context.new.json"; mv "$jira_work/context.new.json" "$jira_work/context.json"
  review_proposals "$jira_work/context.json" "$jira_work/mixed-proposals.json"
  jq_check 'F4 grouped key plus candidate comment keeps only candidate dependency evidence' '[.proposals[]|select(.kind=="comment")]|length==1 and (.[0].evidence|length)==2 and .[0].dependency_evidence==["git:2222222222222222222222222222222222222222"]' "$jira_work/mixed-proposals.json"
  link=$(command jq -c '.proposals[]|select(.kind=="link")' "$jira_work/mixed-proposals.json")
  routine_jira_approve "$link" "$jira_work/mixed-proposals.json" false
  comment=$(command jq -c '.proposals[]|select(.kind=="comment")' "$jira_work/mixed-proposals.json")
  routine_jira_approve "$comment" "$jira_work/mixed-proposals.json" false
  id=$(command jq -r '.entries[]|select(.kind=="comment")|.entry_id' "$jira_dir/ledger.json")
  before=$(call_count 'POST */comment *'); routine_jira_apply_one "$id"
  jq_check 'F4 candidate-only saved link permits grouped comment write' '.entries|any(.kind=="comment" and .state=="verified")' "$jira_dir/ledger.json"
  check 'F4 grouped comment sends once' test "$(call_count 'POST */comment *')" = "$((before+1))"
  jq_check 'F4 key basis is not incorrectly persisted as dependency' '.links|length==1 and .[0].evidence_id=="git:2222222222222222222222222222222222222222"' "$jira_dir/links.json"
)
(
  review_boot propose
  command jq '.sessions=[{source:"omp",id:"claims",cwd:"/fixture/example",last_ts:"2026-10-08T03:00:00Z",reports:[{ts:"2026-10-08T02:00:00Z",text:"운영 조회 확인했습니다"},{ts:"2026-10-08T03:00:00Z",text:"스테이징 배포 완료했습니다"}]}]|.errors=[]' "$sandbox/raw.json" > "$jira_work/claims.json"
  review_context "$jira_work/claims.json" "$jira_work/context.json"
  command jq '[.evidence[]|select(.kind=="report")]|sort_by(.ts)' "$jira_work/context.json" > "$jira_work/claim-reports.json"
  command jq --slurpfile reports "$jira_work/claim-reports.json" '.works[0].evidence+=[$reports[0][].id]|.llm.sections=[{target:"ABC-1",header:"작업 내용",lines:[{text:"운영 확인 완료",evidence:[$reports[0][0].id]},{text:"배포 완료",evidence:[.evidence[0].id]},{text:"스테이징 배포 완료",evidence:[$reports[0][1].id]}]}]' "$jira_work/context.json" > "$jira_work/claim-context.json"
  jq_check 'T33 actual jira_evidence reports retain only supported operational confirmation' 'include "jira"; jira_rules(.)|[.proposals[]|select(.kind=="fill_description")|.payload.sections[]|select(.header=="작업 내용")|.lines[].text]==["운영 확인 완료"]' "$jira_work/claim-context.json"
)
for variant in property exact-url; do
  (
    review_boot apply
    command jq '.git=[]|.sessions=[]|.errors=[]|.prs=[{url:"https://github.com/example/example/pull/12",number:12,title:"ABC-1 feature implementation",repository:{nameWithOwner:"example/example"},roles:["author"],createdAt:"2026-09-18T00:00:00Z",current:{state:"OPEN"},activity:[{kind:"commit",at:"2026-10-08T00:00:00Z"}],commit_oids:[],commits_complete:true}]' "$sandbox/raw.json" > "$jira_work/pr.json"
    url=https://github.com/example/example/pull/123; account=other
    if [[ $variant == property ]]; then url=https://github.com/example/example/pull/12; account=fixture-account; fi
    jq -L "$share_dir" --arg url "$url" --arg account "$account" --arg variant "$variant" 'include "jira"; .comments=[{id:"1",created:"2026-10-08T00:00:00Z",author:{accountId:$account},body:($url|jira_text_adf)}+(if $variant=="property" then {property:{v:1,entry_id:"old",events:["unrelated-event"]}} else {} end)]' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
    review_context "$jira_work/pr.json" "$jira_work/context.json"
    review_proposals "$jira_work/context.json" "$jira_work/proposals.json"
    jq_check "F6 $variant does not suppress the genuine PR-12 event" 'any(.proposals[];.kind=="comment" and (.payload.events|any(.kind=="pr_link")))' "$jira_work/proposals.json"
    comment=$(command jq -c '.proposals[]|select(.kind=="comment")' "$jira_work/proposals.json")
    routine_jira_approve "$comment" "$jira_work/proposals.json" false
    id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
    before=$(call_count 'POST */comment *'); routine_jira_apply_one "$id"
    jq_check "F6 $variant apply preflight shares the correct matcher" '.entries[0].state=="verified"' "$jira_dir/ledger.json"
    check 'F6 new event posts exactly once' test "$(call_count 'POST */comment *')" = "$((before+1))"
  )
done
(
  review_boot apply
  command jq '.git+=[.git[0]|.sha="2222222222222222222222222222222222222222"]|.sessions=[]|.errors=[]|.prs=[{url:"https://github.com/example/example/pull/12",number:12,title:"ABC-1 feature implementation",repository:{nameWithOwner:"example/example"},roles:["author"],createdAt:"2026-10-01T00:00:00Z",current:{state:"OPEN"},activity:[{kind:"commit",at:"2026-10-08T00:00:00Z"}],commit_oids:["1111111111111111111111111111111111111111"],commits_complete:true}]' "$sandbox/raw.json" > "$jira_work/pr-merge.json"
  review_context "$jira_work/pr-merge.json" "$jira_work/context.json"
  jq -L "$share_dir" 'include "jira"; .evidence as $e|(.works|map(.id)) as $ids|(.works|jira_apply_llm($e;{merge:[$ids],attach:[],links:[],create:[],sections:[]})) as $merged|.works=$merged.works' "$jira_work/context.json" > "$jira_work/context.new.json"; mv "$jira_work/context.new.json" "$jira_work/context.json"
  review_events "$jira_work/context.json"
  jq_check 'F7 LLM merge keeps member suppression but emits unrelated git commit' '[.works[].events[]|select(.kind=="commit")|.evidence_id]==["git:2222222222222222222222222222222222222222"] and .works[0].pr_member_evidence==["git:1111111111111111111111111111111111111111"]' "$jira_work/context.json"
  review_proposals "$jira_work/context.json" "$jira_work/proposals.json"
  comment=$(command jq -c '.proposals[]|select(.kind=="comment")' "$jira_work/proposals.json")
  routine_jira_approve "$comment" "$jira_work/proposals.json" false
  id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json"); routine_jira_apply_one "$id"
  jq_check 'F7 shipping comment request contains independent commit, not member commit' '.entries[0].state=="verified" and (.entries[0].request.body.body|tostring|contains("example 22222222")) and (.entries[0].request.body.body|tostring|contains("example 11111111")|not)' "$jira_dir/ledger.json"
)
(
  review_boot propose
  command jq '.git+=[.git[0]|.sha="2222222222222222222222222222222222222222"|.subject="ABC-2 feature implementation"]|.errors=[]' "$sandbox/raw.json" > "$jira_work/two-issues.json"
  export JIRA_ROUTES="$jira_work/routes.json"
  command jq -n --slurpfile server "$JIRA_SERVER" '[{method:"GET",prefix:"/rest/api/3/issue/ABC-2?fields=",body:($server[0].issue|.id="101"|.key="ABC-2")}]' > "$JIRA_ROUTES"
  review_context "$jira_work/two-issues.json" "$jira_work/context.json"
  before=$(wc -l < "$JIRA_CALLS"); routine_jira_propose_issue ABC-1 "$jira_work/context.json" needed
  check 'QM5 completed known issue needs no redundant second-pass GETs' test "$(wc -l < "$JIRA_CALLS")" = "$before"
  command jq '.+[{method:"GET",prefix:"/rest/api/3/issue/ABC-1/transitions?",http:500,body:{}}]' "$JIRA_ROUTES" > "$JIRA_ROUTES.new"; mv "$JIRA_ROUTES.new" "$JIRA_ROUTES"
  routine_jira_propose_issue ABC-1 "$jira_work/context.json"
  jq_check 'F8 failed fresh transitions invalidate the previous success' 'include "jira"; .transitions["ABC-1"]==null and (jira_rules(.)|[.proposals[]|select(.kind=="transition")|.key])==["ABC-2"]' "$jira_work/context.json"
  command jq '.[1]={method:"GET",prefix:"/rest/api/3/issue/ABC-1?fields=",http:500,body:{}}' "$JIRA_ROUTES" > "$JIRA_ROUTES.new"; mv "$JIRA_ROUTES.new" "$JIRA_ROUTES"
  routine_jira_propose_issue ABC-1 "$jira_work/context.json" || true
  jq_check 'F8 failed fresh issue GET removes stale issue and records a partial-read error' 'include "jira"; .issues["ABC-1"]==null and .issue_reads["ABC-1"].status=="failed" and (.errors|any(.message=="ABC-1 — 이슈 읽기 실패: HTTP 500 / curl 0")) and (jira_rules(.)|[.proposals[]|select(.kind=="transition")|.key])==["ABC-2"]' "$jira_work/context.json"
)
# shellcheck source=review-boundaries.sh
source "$repo/tests/fixtures/jira/review-boundaries.sh"
echo 'PASS: Jira 독립 검토 F1–F8·승인 경계·공식 metadata·보수 근거 회귀'
