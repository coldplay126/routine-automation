#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2153,SC2034,SC2016,SC2030,SC2031 # Parent defines effects and transport flags dynamically; literal jq programs.
(
  routine_jira_session; routine_jira_lock review; routine_jira_authenticate
  before=$(call_count 'PUT *')
  if routine_jira_curl PUT /rest/api/3/issue/ABC-1 '' "$jira_work/unauthorized.json"; then fail 'T63 low-level transport bypass'; fi
  check 'T63 transport cannot bypass send' test "$(call_count 'PUT *')" = "$before"
  touch -t 202001010000 "$jira_dir/.lock"
  check 'T74 old live review lock remains live' routine_jira_lock_live "$jira_dir/.lock"
  # shellcheck source=../../../share/install.sh
  source "$share_dir/install.sh"
  if routine_installation_idle; then fail 'T74 update allowed during live Jira review'; fi
  jq_check 'T09 wrong-repository merge rejected' 'include "jira"; .works as $w|($w+[$w[0]|.id="second"|.repos=["different"]])|jira_apply_llm([];{merge:[[$w[0].id,"second"]],attach:[],links:[],create:[],sections:[]})|(.works|length)==2 and (.questions|length)>0' "$sandbox/rules-context.json"
  jq_check 'T09 conflicting mapped links and create summaries discarded' 'include "jira"; .works as $w|($w+[$w[0]|.id="second"|.anchors=["second"]|.evidence=["git:second"]])|jira_apply_llm([];{merge:[[$w[0].id,"second"]],attach:[],links:[{work:$w[0].id,key:"ABC-1",reason:"a"},{work:"second",key:"ABC-2",reason:"b"}],create:[{work:$w[0].id,summary:"one"},{work:"second",summary:"two"}],sections:[]})|(.llm.links|length)==0 and (.llm.create|length)==0 and (.questions|length)==2 and (.works[0].flags|index("link_ambiguous")!=null)' "$sandbox/rules-context.json"
  jq_check 'T09 one report cannot attach twice' 'include "jira"; .works as $w|($w+[$w[0]|.id="second"|.anchors=["second"]|.evidence=["git:second"]])|jira_apply_llm([{id:"rep:one",kind:"report",repo:null,keys:[]}];{merge:[],attach:[{evidence:"rep:one",work:$w[0].id},{evidence:"rep:one",work:"second"}],links:[],create:[],sections:[]})|all(.works[];.evidence|index("rep:one")==null) and (.questions|length)>0' "$sandbox/rules-context.json"
  jq_check 'T22 subtasks remain eligible' 'include "jira"; .issues["ABC-1"].type.hierarchy_level=-1|jira_rules(.)|any(.proposals[];.kind=="transition")' "$sandbox/rules-context.json"
  jq_check 'T19 rejected report overlap permits a fresh create candidate' 'include "jira"; .works[0].keys=[]|.works[0].evidence=["rep:one"]|.evidence[0].id="rep:one"|.evidence[0].text="feature implementation"|.links={links:[{site:.site,account_id:.account_id,evidence_id:"rep:one",key:"ABC-1"}],rejections:[{site:.site,account_id:.account_id,evidence_id:"rep:one",key:"ABC-1"}]}|.config.repos={example:{project:"ABC",prefix:"[BACK]"}}|.llm.create=[{work:.works[0].id,summary:"feature implementation"}]|.llm.sections[0].target=.works[0].id|.llm.sections[0].lines[0].evidence=["rep:one"]|.duplicates[.works[0].id]={complete:true,matches:[],queries:2}|.create_meta.ABC={ok:true,name:"작업"}|jira_rules(.)|any(.proposals[];.kind=="create_issue")' "$sandbox/rules-context.json"
  jq_check 'FILL-9 original template heading order' 'include "jira"; .issues["ABC-1"].description.state="template_only"|.issues["ABC-1"].description.headers=["완료 조건","작업 내용","확인사항","관련 링크"]|jira_rules(.)|.proposals[]|select(.kind=="fill_description")|.payload.sections|map(.header)==["완료 조건","작업 내용","확인사항","관련 링크"]' "$sandbox/rules-context.json"
  jq_check 'WRK-9 shared PR commit belongs to one work' 'include "jira"; [{id:"pr:one",kind:"pr",number:1,repo:"example",keys:[],commit_oids:["x"],commits_complete:true,activity:[{kind:"commit"}]},{id:"pr:two",kind:"pr",number:2,repo:"example",keys:[],commit_oids:["x"],commits_complete:true,activity:[{kind:"commit"}]},{id:"git:x",kind:"git",sha:"x",repo:"example",keys:[],text:"feature",merge:false}]|jira_works|map(.evidence[])|length==(unique|length)' <<< null
  link=$(command jq -c '.proposals[]|select(.kind=="comment")|.evidence+=["ses:fixture"]' "$sandbox/base-proposals.json")
  routine_jira_link_save "$link" review ABC-1
  jq_check 'T18 confirmed links never save session hints' 'all(.links[];.evidence_id|startswith("ses:")|not)' "$jira_dir/links.json"
)
# The condition summary is visible even when every write proposal is suppressed.
command jq '.issue.fields.description={type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"완료 조건"}]},{type:"taskList",content:[{type:"taskItem",attrs:{state:"DONE"},content:[{type:"text",text:"one"}]},{type:"taskItem",content:[{type:"text",text:"two"}]},{type:"taskItem",content:[{type:"text",text:"three"}]}]}]}' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
(
  ROUTINE_SETTINGS=$(command jq -c '.jira.enabled=true|.draft.llm.engine="none"' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  "$repo/bin/jira-propose" --no-llm
  summary=$("$repo/bin/routine" jira)
  review=$("$repo/bin/routine" jira review)
  [[ $summary == *'완료 조건 3개 · 남은 2개'* && $review == *'완료 조건 3개 · 남은 2개'* ]] || fail 'T84 summary missing conditions with no proposals'
)
for rejection in 401 403 28; do
  (
    cp "$sandbox/server-initial.json" "$JIRA_SERVER"
    routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
    ROUTINE_SETTINGS=$(command jq -c '.jira.enabled=true|.draft.llm.engine="omp"' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
    routine_jira_approve "$(cat "$sandbox/fill-proposal.json")" "$sandbox/base-proposals.json" false
    id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
    export JIRA_EFFECT=0 JIRA_WRITE_CODE=200 JIRA_WRITE_EXIT=0
    if [[ $rejection == 401 ]]; then JIRA_WRITE_CODE=401
    elif [[ $rejection == 403 ]]; then JIRA_WRITE_CODE=429
    else JIRA_WRITE_EXIT=28; fi
    effects=$(wc -l < "$JIRA_EFFECTS")
    routine_jira_apply_one "$id" || true
    if [[ $rejection == 401 ]]; then
      jq_check 'T85 all attempts definitely not sent have no marker' '.markers==[] and all(.entries[0].attempts[];.outcome=="not_sent")' "$jira_dir/ledger.json"
      command jq --arg at "$(date -u -v-25H '+%Y-%m-%dT%H:%M:%SZ')" '.entries[0].approved_at=$at' "$jira_dir/ledger.json" > "$jira_work/old.json"; routine_jira_store "$jira_work/old.json" "$jira_dir/ledger.json"
      jira_abort=0; routine_jira_apply_one "$id"
      jq_check 'T85 definitely not sent approval can expire' '.entries[0].state=="void" and .markers==[]' "$jira_dir/ledger.json"
    elif [[ $rejection == 403 ]]; then
      JIRA_WRITE_CODE=403; routine_jira_apply_one "$id"
      jq_check 'T85 server rejection consumes permanent fill marker' '.entries[0].state=="blocked" and (.markers|length)==1' "$jira_dir/ledger.json"
    else jq_check 'T85 ambiguous PUT consumes permanent fill marker' '.entries[0].state=="unknown" and (.markers|length)==1' "$jira_dir/ledger.json"; fi
    check 'T85 rejected writes have zero server effects' test "$(wc -l < "$JIRA_EFFECTS")" = "$effects"
  )
  if [[ $rejection == 28 ]]; then /usr/bin/expect "$repo/tests/fixtures/jira/pty.exp" "$sandbox/pty-wrapper.sh" "$sandbox/close-fill.log" close-one close; fi
  "$repo/bin/jira-propose"
  if [[ $rejection == 401 ]]; then jq_check 'T85 never-sent fill proposed again after void' '[.proposals[]|select(.kind=="fill_description")]|length==1' "$proposal_file"
  else jq_check 'T85 sent-or-unknown fill never reproposed' 'all(.proposals[];.kind!="fill_description")' "$proposal_file"; fi
done
echo 'PASS: Jira merge/attach 충돌·조건 요약·갱신 유휴·확정 미전송 회귀'
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock propose; routine_jira_authenticate; reset_jira_ledger
  routine_jira_read_context "$jira_work/ctx.json"
  jq -L "$share_dir" --slurpfile base "$sandbox/base-proposals.json" 'include "jira"; .evidence=($base[0].evidence+[$base[0].evidence[0]|.id="git:2222222222222222222222222222222222222222"|.text="ABC-2 feature implementation"])|.works=($base[0].works+[$base[0].works[0]|.anchors=["keys:ABC-2"]|.keys=["ABC-2"]|.evidence=["git:2222222222222222222222222222222222222222"]|.events=[]]|jira_work_ids)' "$jira_work/ctx.json" > "$jira_work/context.json"
  jq -L "$share_dir" 'include "jira"; .works|jira_id_inputs' "$jira_work/context.json" > "$jira_work/ids.json"
  routine_jira_hash_map "$jira_work/ids.json" > "$jira_work/hashes.json"
  jq -L "$share_dir" --slurpfile hashes "$jira_work/hashes.json" 'include "jira"; .works|=jira_with_ids($hashes[0])' "$jira_work/context.json" > "$jira_work/ctx-new.json"; mv "$jira_work/ctx-new.json" "$jira_work/context.json"
  export JIRA_ROUTES="$jira_work/routes.json"
  command jq -n --slurpfile server "$JIRA_SERVER" '[{method:"GET",prefix:"/rest/api/3/issue/ABC-2?fields=",body:($server[0].issue|.id="101"|.key="ABC-2")},{method:"GET",prefix:"/rest/api/3/issue/ABC-1/changelog?startAt=0",body:{startAt:0,isLast:false,values:[{created:"2026-10-01T00:00:00Z",items:[]}]}},{method:"GET",prefix:"/rest/api/3/issue/ABC-1/changelog?startAt=1",body:{startAt:1,isLast:false,values:[{created:"2026-10-02T00:00:00Z",items:[]}]}},{method:"GET",prefix:"/rest/api/3/issue/ABC-1/changelog?startAt=2",http:500,body:{}}]' > "$JIRA_ROUTES"
  routine_jira_propose_issue ABC-1 "$jira_work/context.json"
  routine_jira_propose_issue ABC-2 "$jira_work/context.json"
  jq_check 'T28 failed third history page does not suppress other issue' 'include "jira"; jira_rules(.)|[.proposals[]|select(.kind=="transition")|.key]==["ABC-2"]' "$jira_work/context.json"
  command jq -n '[{method:"GET",prefix:"/rest/api/3/issue/ABC-1/comment?orderBy=created&startAt=0",body:{startAt:0,total:2,comments:[{id:"1",author:{accountId:"other"},body:{type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"unrelated"}]}]}}]}},{method:"GET",prefix:"/rest/api/3/issue/ABC-1/comment?orderBy=created&startAt=1",body:{startAt:1,total:2,comments:[{id:"2",author:{accountId:"other"},body:{type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"example 11111111"}]}]}}]}}]' > "$JIRA_ROUTES"
  command jq --slurpfile base "$sandbox/base-proposals.json" '.works=[$base[0].works[0]]' "$jira_work/context.json" > "$jira_work/ctx-new.json"; mv "$jira_work/ctx-new.json" "$jira_work/context.json"
  routine_jira_propose_issue ABC-1 "$jira_work/context.json"
  jq_check 'T46 duplicate commit on second comment page suppressed' 'include "jira"; jira_rules(.)|all(.proposals[];.kind!="comment")' "$jira_work/context.json"
  command jq '.[1].http=500' "$JIRA_ROUTES" > "$JIRA_ROUTES.new"; mv "$JIRA_ROUTES.new" "$JIRA_ROUTES"
  routine_jira_propose_issue ABC-1 "$jira_work/context.json"
  jq_check 'T46 partial comments suppress comment only' 'include "jira"; jira_rules(.)|all(.proposals[];.kind!="comment") and any(.proposals[];.kind=="transition")' "$jira_work/context.json"
  for code in 404 403; do
    command jq -n --argjson code "$code" '[{method:"GET",prefix:"/rest/api/3/issue/ABC-1/comment?",body:{startAt:0,total:1,comments:[{id:"1",author:{accountId:"fixture-account"},body:{type:"doc",content:[]}}]}},{method:"GET",prefix:"/rest/api/3/comment/1/properties",http:$code,body:{}}]' > "$JIRA_ROUTES"
    routine_jira_propose_issue ABC-1 "$jira_work/context.json"
    if [[ $code == 404 ]]; then jq_check 'T47 missing property is definitive absence' 'include "jira"; jira_rules(.)|any(.proposals[];.kind=="comment")' "$jira_work/context.json"
    else jq_check 'T47 forbidden property prevents comment' 'include "jira"; jira_rules(.)|all(.proposals[];.kind!="comment")' "$jira_work/context.json"; fi
  done
)
echo 'PASS: Jira 이슈별 changelog 격리·댓글 전체 페이지·표지 404/403 회귀'
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  ( routine_jira_session; routine_jira_lock review; routine_jira_authenticate; reset_jira_ledger )
  ROUTINE_SETTINGS=$(command jq '.jira.enabled=true|.jira.model_engine="none"' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  command jq '.errors+=[{source:"sessions",message:"fixture partial collection"}]' "$JIRA_RAW" > "$sandbox/partial-raw.json"; mv "$sandbox/partial-raw.json" "$JIRA_RAW"
  export JIRA_COLLECT_EXIT=1
  effects=$(wc -l < "$JIRA_EFFECTS")
  "$repo/bin/routine" jira propose --no-llm
  check 'T14 partial collection retains valid source evidence and diagnostics' command jq -e '(.evidence|any(.kind=="git")) and (.errors|any(.source=="sessions" and .message=="fixture partial collection")) and (.proposals|length>0)' "$proposal_file"
  check 'T14 partial collection has no Jira writes' test "$(wc -l < "$JIRA_EFFECTS")" = "$effects"
)
echo 'PASS: Jira 원본 ADF·단일 쓰기·unknown·fill·부분 수집 회귀'
