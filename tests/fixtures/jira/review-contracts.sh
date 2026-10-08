#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2153,SC2034,SC2030,SC2031,SC2016 # Shared suite fixtures and literal jq.
for kind in comment transition fill_description; do
  for change in id project epic assignee; do
    (
      review_boot apply
      if [[ $kind == fill_description ]]; then proposal=$(cat "$sandbox/fill-proposal.json"); else proposal=$(command jq -c --arg kind "$kind" '.proposals[]|select(.kind==$kind)' "$sandbox/base-proposals.json"); fi
      routine_jira_approve "$proposal" "$sandbox/base-proposals.json" false
      id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
      command jq --arg change "$change" 'if $change=="id" then .issue.id="101" elif $change=="project" then .issue.fields.project.key="DEF" elif $change=="epic" then .issue.fields.issuetype.hierarchyLevel=1 else .issue.fields.assignee.accountId="other" end' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
      effects=$(wc -l < "$JIRA_EFFECTS")
      routine_jira_apply_one "$id"
      if [[ $kind == comment && $change == assignee ]]; then
        jq_check 'T27 ownership change still permits progress comment' '.entries[0].state=="verified"' "$jira_dir/ledger.json"
        check 'T27 allowed comment has exactly one effect' test "$(wc -l < "$JIRA_EFFECTS")" -eq "$((effects+1))"
      else
        jq_check "T27 $kind rejects $change target drift" '.entries[0].state=="conflict"' "$jira_dir/ledger.json"
        check 'T27 scope drift has zero server effect' test "$(wc -l < "$JIRA_EFFECTS")" = "$effects"
      fi
    )
  done
done
for evidence_kind in git pr; do
  (
    review_boot apply
    source_file="$sandbox/retention-create-source.json"
    create=$(command jq -c '.proposals[]|select(.kind=="create_issue")' "$source_file")
    routine_jira_approve "$create" "$source_file" false
    id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
    link=$(command jq -c --arg kind "$evidence_kind" '.evidence=[.evidence[]|select(startswith($kind+":"))]' <<< "$create")
    routine_jira_link_save "$link" review ABC-999
    before=$(call_count 'POST /rest/api/3/issue *')
    routine_jira_apply_one "$id"
    jq_check "F2 actual preflight blocks saved $evidence_kind overlap despite missing target" '.entries[0].state=="blocked" and .entries[0].attempts==[]' "$jira_dir/ledger.json"
    check 'F2 no create POST for filtered saved connection' test "$(call_count 'POST /rest/api/3/issue *')" = "$before"
  )
done
for mode in required second-page-failed epic; do
  (
    review_boot propose
    export JIRA_ROUTES="$jira_work/meta-routes.json"
    command jq -n --arg mode "$mode" '[{method:"GET",prefix:"/rest/api/3/issue/createmeta/ABC/issuetypes/10?startAt=0",body:{startAt:0,maxResults:1,total:2,fields:[{fieldId:"summary",required:true}]}},{method:"GET",prefix:"/rest/api/3/issue/createmeta/ABC/issuetypes/10?startAt=1",http:(if $mode=="second-page-failed" then 500 else 200 end),body:{startAt:1,maxResults:1,total:2,fields:[{fieldId:"custom-required",required:true}]}}]+(if $mode=="epic" then [{method:"GET",prefix:"/rest/api/3/issuetype/10",body:{id:"10",name:"에픽",hierarchyLevel:1}}] else [] end)' > "$JIRA_ROUTES"
    before=$(call_count 'POST /rest/api/3/issue *')
    if routine_jira_meta ABC 10 "$jira_work/meta.json"; then fail "T62 $mode allowed creation"; fi
    check "T62 official fields schema blocks $mode without creation" test "$(call_count 'POST /rest/api/3/issue *')" = "$before"
  )
done
(
  review_boot apply
  old=$(command jq -c '.proposals[]|select(.kind=="transition")' "$sandbox/base-proposals.json")
  routine_jira_approve "$old" "$sandbox/base-proposals.json" false
  id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json"); routine_jira_apply_one "$id"
  command jq --arg now "$(routine_jira_now)" '.issue.fields.status={id:"1",name:"미해결",statusCategory:{key:"new"}}|.history+=[{created:$now,items:[{field:"status",from:"3",to:"1"}]}]' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
  review_context "$sandbox/raw.json" "$jira_work/context.json"; review_proposals "$jira_work/context.json" "$jira_work/returned.json"
  jq_check 'T25 new status entry creates a new transition identity after verified' 'any(.proposals[];.kind=="transition")' "$jira_work/returned.json"
  next=$(command jq -c '.proposals[]|select(.kind=="transition")' "$jira_work/returned.json")
  check 'T25 status reentry is not permanently suppressed by prior verified ID' test "$(command jq -r .id <<< "$next")" != "$(command jq -r .id <<< "$old")"
  routine_jira_approve "$next" "$jira_work/returned.json" false
  id=$(command jq -r '.entries[-1].entry_id' "$jira_dir/ledger.json"); routine_jira_apply_one "$id"
  jq_check 'T25 new entry can actually transition again' '(.entries|length)==2 and all(.entries[];.state=="verified")' "$jira_dir/ledger.json"
)
(
  review_boot propose
  review_context "$sandbox/raw.json" "$jira_work/context.json"
  for mode in holding in-progress other unassigned; do
    command jq --arg mode "$mode" '.llm_valid=false|if $mode=="holding" then .issues["ABC-1"].status.id="2" elif $mode=="in-progress" then .issues["ABC-1"].status.id="3" else .issues["ABC-1"].assignee_is_me=false end' "$jira_work/context.json" > "$jira_work/status-context.json"
    jq_check "T23 $mode emits progress comment but no transition" 'include "jira"; jira_rules(.)|any(.proposals[];.kind=="comment") and all(.proposals[];.kind=="comment")' "$jira_work/status-context.json"
  done
  command jq '.works[0].keys=[]|.evidence[0].text="CVE-2024-1 GPT-4 feature implementation"|.works[0].id as $id|.llm.create=[{work:$id,summary:"feature implementation"}]|.llm.sections[0].target=$id|.duplicates[$id]={complete:true,matches:[],queries:2}|.create_meta.ABC={ok:true,name:"작업"}' "$jira_work/context.json" > "$jira_work/nonissue-tokens.json"
  jq_check 'T54 CVE and GPT tokens alone do not falsely block a real creation candidate' 'include "jira"; jira_rules(.)|any(.proposals[];.kind=="create_issue")' "$jira_work/nonissue-tokens.json"
)
(
  review_boot propose
  command jq '.issue.fields.status={id:"3",name:"진행 중",statusCategory:{key:"indeterminate"}}|.issue.fields.description={type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"완료 조건"}]},{type:"taskList",content:[{type:"taskItem",attrs:{state:"DONE"},content:[{type:"text",text:"one"}]},{type:"taskItem",attrs:{state:"DONE"},content:[{type:"text",text:"two"}]}]}]}' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
  command jq '.errors=[]|.sessions=[{source:"omp",id:"ops",cwd:"/fixture/example",last_ts:"2026-10-08T00:00:00Z",reports:[{ts:"2026-10-08T00:00:00Z",text:"ABC-1 운영 배포 완료했습니다. 운영 조회 확인했습니다."}]}]|.prs=[{url:"https://github.com/example/example/pull/12",number:12,title:"ABC-1 feature implementation",repository:{nameWithOwner:"example/example"},roles:["author"],current:{state:"MERGED"},createdAt:"2026-10-01T00:00:00Z",activity:[{kind:"merged",at:"2026-10-08T00:00:00Z"}],commit_oids:["1111111111111111111111111111111111111111"],commits_complete:true}]' "$sandbox/raw.json" > "$jira_work/done-looking.json"
  review_context "$jira_work/done-looking.json" "$jira_work/context.json"; review_proposals "$jira_work/context.json" "$jira_work/proposals.json"
  jq_check 'T29 merged PR plus operational proofs and all DONE conditions still permits comments only' 'any(.proposals[];.kind=="comment") and all(.proposals[];.kind=="comment") and (.issues["ABC-1"].conditions.items|all(.marked_done==true))' "$jira_work/proposals.json"
)
for code in 404 500; do
  (
    review_boot propose
    export JIRA_ROUTES="$jira_work/failure.json"
    command jq -n --argjson code "$code" '[{method:"GET",prefix:"/rest/api/3/issue/ABC-1?fields=",http:$code,body:{}}]' > "$JIRA_ROUTES"
    review_context "$sandbox/raw.json" "$jira_work/context.json" || true
    if [[ $code == 404 ]]; then expected='이슈 없음 또는 권한 없음'; else expected='이슈 읽기 실패: HTTP 500 / curl 0'; fi
    jq_check "QM4 $code retains actual read error rather than assuming absence" ".errors|any(.message|contains(\"$expected\"))" "$jira_work/context.json"
  )
done
(
  review_boot apply
  routine_jira_approve "$(cat "$sandbox/fill-proposal.json")" "$sandbox/base-proposals.json" false
  id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json"); routine_jira_apply_one "$id"
  cp "$JIRA_SERVER" "$sandbox/notice-first-filled.json"
  command jq '.issue.id="200"|.issue.key="ABC-2"|.issue.fields.description=null|.issue.fields.updated="2026-10-02T00:00:00Z"|.history=[]|.comments=[]' "$sandbox/server-initial.json" > "$JIRA_SERVER"
  command jq '.git=[.git[0]|.subject="ABC-2 feature implementation"|.oid="2222222222222222222222222222222222222222"]|.prs=[]|.reports=[]' "$sandbox/raw.json" > "$jira_work/second-notice-raw.json"
  review_context "$jira_work/second-notice-raw.json" "$jira_work/second-notice-context.json"
  review_proposals "$jira_work/second-notice-context.json" "$jira_work/second-notice-proposals.json"
  proposal=$(command jq -c '.proposals[]|select(.kind=="fill_description" and .key=="ABC-2")' "$jira_work/second-notice-proposals.json")
  routine_jira_approve "$proposal" "$jira_work/second-notice-proposals.json" false
  id=$(command jq -r '.entries[-1].entry_id' "$jira_dir/ledger.json"); routine_jira_apply_one "$id"
  jq_check 'QL5 two real successful fills produce confirmed notice markers' '(.markers|length)==2 and all(.markers[];.confirmed==true and .notified_hash==null)' "$jira_dir/ledger.json"
  command jq '.issue.fields.description=null' "$sandbox/notice-first-filled.json" > "$JIRA_SERVER"
  cp "$jira_dir/ledger.json" "$sandbox/before-notice-401-ledger.json"
  routine_jira_store "$sandbox/base-proposals.json" "$proposal_file"
  cp "$proposal_file" "$sandbox/before-notice-401.json"
)
(
  export JIRA_RAW="$sandbox/empty-raw.json" JIRA_ROUTES="$sandbox/notice-401.json"
  printf '[{"method":"GET","prefix":"/rest/api/3/issue/ABC-2?fields=","http":401,"body":{}}]\n' > "$JIRA_ROUTES"
  if "$repo/bin/jira-propose" --no-llm; then fail 'QL5 notice 401 did not abort proposal'; fi
  check 'QL5 notices 401 preserves prior proposal instead of publishing partial output' cmp "$sandbox/before-notice-401.json" "$proposal_file"
  check 'QL5 later notice 401 does not consume an earlier unpublished change' cmp "$sandbox/before-notice-401-ledger.json" "$JIRA_LEDGER"
)
echo 'PASS: Jira T23/T25/T27/T29/T54/T62 대상·재진입·1단계 범위·공식 metadata·읽기 오류·알림 401 계약'
(
  review_boot review
  ROUTINE_SETTINGS=$(command jq -c '.jira.projects.DEF={statuses:{start_from:["90"],holding:["91"],in_progress:"93"},create_type:"10"}' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  command jq '.issue.id="300"|.issue.key="DEF-1"|.issue.fields.project.key="DEF"|.issue.fields.status={id:"90",name:"미해결",statusCategory:{key:"new"}}|.transitions=[{id:"920",to:{id:"93",name:"진행 중"},fields:{}}]' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
  command jq '.git[0].subject="DEF-1 feature implementation"|.errors=[]' "$sandbox/raw.json" > "$jira_work/project-raw.json"
  review_context "$jira_work/project-raw.json" "$jira_work/context.json"; review_proposals "$jira_work/context.json" "$jira_work/project.json"
  transition=$(command jq -c '.proposals[]|select(.kind=="transition")' "$jira_work/project.json")
  routine_jira_preview "$transition" "$jira_work/project.json" > "$jira_work/transition-preview"
  jq_check 'QH5 transition preview shows human names and separate IDs' 'contains("미해결 (90)") and contains("진행 중 (93)") and contains("transition.id=920")' -Rs "$jira_work/transition-preview"
  routine_jira_approve "$transition" "$jira_work/project.json" false
  jq_check 'T26 configured second project uses its own status and transition IDs' '.entries[0].project=="DEF" and .entries[0].key=="DEF-1" and .entries[0].proposal.payload.to.id=="93" and .entries[0].request.body.transition.id=="920"' "$jira_dir/ledger.json"
  ROUTINE_SETTINGS=$(command jq -c 'del(.jira.projects.DEF)' <<< "$ROUTINE_SETTINGS")
  review_context "$jira_work/project-raw.json" "$jira_work/unconfigured.json"; review_proposals "$jira_work/unconfigured.json" "$jira_work/unconfigured-proposals.json"
  jq_check 'T26 absent project settings do not borrow another project statuses' 'all(.proposals[];.kind!="transition")' "$jira_work/unconfigured-proposals.json"
)
echo 'PASS: Jira 프로젝트별 상태 매핑·미설정 프로젝트 차단·전환 이름/ID 미리보기'
