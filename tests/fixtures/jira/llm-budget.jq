include "jira";
def context($evidence):
  {site:"https://example.atlassian.net",account_id:"fixture-account",config:{templates:{}},links:{links:[]},issues:{},
   evidence:$evidence,works:($evidence|jira_works|map(.id=._ref))};
def link($id;$key): {site:"https://example.atlassian.net",account_id:"fixture-account",evidence_id:$id,key:$key};
[range(0;30) as $i |
 {id:("pr:https://example/pull/"+($i|tostring)),kind:"pr",repo:"example",number:($i+1),keys:[],text:"feature implementation",ts:"2026-10-08T00:00:00Z",activity:[{kind:"created"}],commit_oids:["sha-"+($i|tostring)],commits_complete:true},
 {id:("git:sha-"+($i|tostring)),kind:"git",repo:"example",keys:[],sha:("sha-"+($i|tostring)),text:"feature implementation",ts:"2026-10-08T00:00:00Z",merge:false}] as $pairs |
($pairs|context(.)) as $pair_ctx |
($pair_ctx|jira_llm_input([];[])) as $paired |
($pair_ctx|.works=.works[:1]|.evidence|=map(if .kind=="git" then .ts="2026-10-08T01:00:00Z" else . end)|.links.links=[link(.works[0].anchors[0];"ABC-7")]|.issues={"ABC-7":{key:"ABC-7",summary:"feature implementation"}}) as $saved_ctx |
($saved_ctx|jira_llm_input([];[])) as $saved |
([range(0;40) as $i|{id:("git:"+($i|tostring)),kind:"git",repo:"example",keys:(if $i<35 then [] else ["ABC-"+($i+1|tostring)] end),sha:($i|tostring),text:"feature implementation",ts:"2026-10-08T00:00:00Z",merge:false}]|context(.)|.issues=([range(36;41)|"ABC-"+tostring|{key:.,value:{key:.,summary:"feature implementation"}}]|from_entries)) as $quota_ctx |
($quota_ctx|jira_llm_input([];[])) as $quota |
([range(0;30) as $i|{id:("git:"+($i|tostring)),kind:"git",repo:"example",keys:[],sha:($i|tostring),text:"feature implementation",ts:"2026-10-08T00:00:00Z",merge:false},
  (if $i<10 then {id:("rep:"+($i|tostring)),kind:"report",repo:"example",keys:[],text:"feature report",ts:"2026-10-08T00:00:00Z"} else empty end)]|context(.)|
 .links.links=[.evidence[]|link(.id;"ABC-1")]|.issues={"ABC-1":{key:"ABC-1",summary:"feature implementation"}}) as $order_ctx |
($order_ctx|jira_llm_input([];["ABC-99","ABC-7","ABC-99","ABC-2"])) as $forward |
($order_ctx|.links.links|=reverse|.works|=reverse|.evidence|=reverse|jira_llm_input([];["ABC-99","ABC-7","ABC-99","ABC-2"])) as $reverse |
([{id:"git:one",kind:"git",repo:"example",keys:[],sha:"one",merge:false,ts:"2026-10-08T00:00:00Z",text:"widget implementation"},
  {id:"rep:one",kind:"report",repo:"example",keys:[],ts:"2026-10-08T00:00:00Z",text:"widget feature report"}]|context(.)|
 .links.links=[link("rep:one";"ABC-9")]|.issues={"ABC-9":{key:"ABC-9",summary:"widget",description:{excerpt:"task details"}}}) as $report_ctx |
($report_ctx|jira_llm_input([];[])) as $report_input |
($report_ctx|.evidence[0].keys=[range(1;31)|"ABC-"+tostring]|.works=(.evidence|jira_works|map(.id=._ref))|
 .links.links=[link("rep:one";"ABC-99")]|.issues=([range(1;31)|"ABC-"+tostring|{key:.,value:{key:.,summary:"widget"}}]|from_entries)+{"ABC-99":{key:"ABC-99",summary:"widget"}}) as $report_budget_ctx |
($report_budget_ctx|jira_llm_input([];[])) as $report_full_budget |
($report_budget_ctx|.evidence[0].keys|=.[0:29]|.works=(.evidence|jira_works|map(.id=._ref))|jira_llm_input([];[])) as $report_spare_budget |
([
 {case:"E1 production PR/Git 30-work representative guarantee",pass:(($paired.works|length)==30 and ($paired.evidence|length)==50 and all($paired.works[];(.evidence|length)>=1))},
 {case:"E2 stored PR connection, representative and target issue retained",pass:($saved.works[0].evidence==[$saved_ctx.works[0].anchors[0]] and $saved.stored_links==[{evidence_id:$saved_ctx.works[0].anchors[0],key:"ABC-7"}] and ($saved.issues|has("ABC-7")))},
 {case:"QV linked quota with 35 unlinked and five connected works",pass:(($quota.works|length)==30 and ([$quota.works[]|select((.keys|length)>0)]|length)==5 and ($quota.issues|length)==5)},
 {case:"E4 all selected work connections beat report hints and input ordering",pass:($forward==$reverse and ($forward.stored_links|length)==30 and all($forward.stored_links[];.evidence_id|startswith("git:")))},
 {case:"QV visits retain recent input order with stable deduplication",pass:($forward.visit_hints==["ABC-99","ABC-7","ABC-2"])},
 {case:"N1 unassigned report connection carries its target issue",pass:(($report_input.works|length)==1 and ($report_input.unattached_reports|length)==1 and $report_input.stored_links==[{evidence_id:"rep:one",key:"ABC-9"}] and $report_input.issues["ABC-9"].description_excerpt=="task details")},
 {case:"N1 full issue budget omits report connection and target together",pass:(($report_full_budget.issues|length)==30 and $report_full_budget.stored_links==[] and ($report_full_budget.issues|has("ABC-99")|not))},
 {case:"N1 spare issue budget preserves report connection and target together",pass:(($report_spare_budget.issues|length)==30 and $report_spare_budget.stored_links==[{evidence_id:"rep:one",key:"ABC-99"}] and ($report_spare_budget.issues|has("ABC-99")))},
 {case:"All model link evidence and target issues have backing context",pass:([ $saved,$forward,$report_input,$report_full_budget,$report_spare_budget ]|all(.[];. as $input|all(.stored_links[];. as $link|any($input.evidence[];.id==$link.evidence_id) and ($input.issues|has($link.key))))) }
]) | . as $checks | if all(.[];.pass) then true else error($checks|map(select(.pass|not))|tostring) end
