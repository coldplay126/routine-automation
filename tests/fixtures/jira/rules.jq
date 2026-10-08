include "jira";
include "scrum";
def check($id;predicate): try (if predicate then {id:$id,pass:true} else error("rule regression") end) catch error("Jira "+$id+": "+.);
def kinds: .proposals|map(.kind);
def rules: jira_rules(.);
. as $base |
($base|.works[0].keys=[]|.evidence[0].text="feature implementation"|.config.repos={example:{project:"ABC",prefix:"[BACK]"}}|.llm_valid=true|.llm.create=[{work:.works[0].id,summary:"feature implementation"}]|.llm.sections[0].target=.works[0].id|.duplicates[.works[0].id]={complete:true,matches:[],queries:2}|.create_meta.ABC={ok:true,name:"작업"}) as $new |
[
 check("T09";($base.works+[$base.works[0]|.id="second"|.anchors=["second"]|.evidence=["rep:second"]]|jira_apply_llm([{id:"rep:attached",kind:"report",repo:"example",keys:[]}];{merge:[[$base.works[0].id,"second"]],attach:[{evidence:"rep:attached",work:"second"}],links:[{work:"second",key:"ABC-1",reason:"specific"}],create:[],sections:[]})|(.works|length)==1 and (.works[0].evidence|index("rep:attached")!=null) and .llm.links[0].work==.works[0].id)),
 check("T11";([{id:"pr:https://example/pull/1",kind:"pr",repo:"example",keys:[],number:1,commit_oids:[],commits_complete:true,activity:[{kind:"commit"}]},{id:"git:x",kind:"git",repo:"example",keys:[],sha:"x",text:"Merge pull request #1",merge:true},{id:"git:y",kind:"git",repo:"example",keys:[],sha:"y",text:"Merge branch other",merge:true}]|jira_works|length==1 and (.[0].evidence|index("git:x")!=null))),
 check("T12";([{id:"pr:one",kind:"pr",repo:"example",keys:[],number:1,commit_oids:[],commits_complete:false,activity:[]},{id:"git:x",kind:"git",repo:"example",keys:[],sha:"x",text:"feature",merge:false}]|jira_works|any(.[];.flags|index("pr_membership_unknown")!=null))),
 check("T15";jira_weak("스테이징 도메인 수정";"도메인 스테이징 설정")),
 check("T16";($base|.works[0].keys=[]|.llm.links=[{work:.works[0].id,key:"DEF-99",reason:"invented"}]|rules|(.proposals|length)==0 and (.questions|length)>0)),
 check("T17";($base|.works[0].keys=[]|.links.links=[{site:.site,account_id:.account_id,evidence_id:.works[0].evidence[0],key:"ABC-1"}]|.issues["ABC-1"].assignee_is_me=false|.issues["ABC-1"].status.category="done"|. as $ctx|.works[0]|jira_links_for($ctx)|.[0].basis=="stored")),
 check("T18";($base|.works[0].keys=[]|.links.links=[{site:"https://other.atlassian.net",account_id:.account_id,evidence_id:.works[0].evidence[0],key:"ABC-1"}]|. as $ctx|.works[0]|jira_links_for($ctx)|length==0)),
 check("T19";($base|.works[0].keys=[]|.works[0].evidence+=["rep:overlap"]|.links.links=[{site:.site,account_id:.account_id,evidence_id:"rep:overlap",key:"ABC-1"}]|. as $ctx|.works[0]|jira_links_for($ctx)|.[0].basis=="candidate" and .[0].origin=="report_overlap")),
 check("T20";($base|.works[0].keys=["ABC-1","ABC-2"]|.issues["ABC-2"]=.issues["ABC-1"]|.issues["ABC-2"].key="ABC-2"|rules|kinds|all(.[];.=="comment"))),
 check("T22";($base|.issues["ABC-1"].type.hierarchy_level=1|rules|(.proposals|length)==0 and any(.questions[];contains("에픽 키")))),
 check("T23";($base|.issues["ABC-1"].assignee_is_me=false|rules|kinds|all(.[];.=="comment"))),
 check("T24";($base|.transitions["ABC-1"]=[{id:"20",to:{id:"3"},fields:{custom:{required:true}}}]|rules|kinds|index("transition")==null)),
 check("T25";($base|.issues["ABC-1"].status.entered_at="2026-10-09T00:00:00Z"|rules|.proposals[]|select(.kind=="transition")|._identity[-1]=="2026-10-09T00:00:00Z")),
 check("T26";($base|.config.projects={DEF:{statuses:{start_from:["90"],in_progress:"30"},create_type:"10"}}|rules|kinds|index("transition")==null)),
 check("T27";($base|.issues["ABC-1"].key="DEF-1"|rules|(.proposals|length)==0 and any(.questions[];contains("이슈 키 변경됨")))),
 check("T28";($base|.issues["ABC-1"].reads.changelog="partial"|rules|kinds|index("transition")==null)),
 check("T29";($base|.issues["ABC-1"].status={id:"3",category:"indeterminate",entered_at:"2026-10-08T00:00:00Z"}|rules|kinds|index("transition")==null)),
 check("T30";($base|.llm_valid=false|rules|kinds|all(.[];IN("comment","transition")))),
 check("T31";($base|.works=[]|.llm_valid=true|rules|.proposals|length==0)),
 check("T32";($base|.works[0].active=false|.llm_valid=true|rules|kinds|index("fill_description")==null)),
 check("T33";([{kind:"report",text:"운영 조회 확인했습니다"}]|jira_claim_proof) as $proof|("운영 확인 완료"|claim_classes|claims_supported(.;$proof))),
 check("T38";({type:"doc",version:1,attrs:{localId:"old"},content:[{type:"heading",attrs:{level:2,localId:"old"},content:[{type:"text",text:"한글"}]}]}|jira_adf_canon)==({type:"doc",content:[{type:"heading",attrs:{level:2},content:[{type:"text",text:"한글"}]}]}|jira_adf_canon)),
 check("T39";([{created:"2026-10-01T00:00:00Z",author:{accountId:"other"},items:[{field:"description",fromString:"h2. 완료 조건\n*확인사항*\n\\[사전조건\\]"}]}]|jira_history("fixture-account")|.prior_content==false)),
 check("T44";($base|.comments["ABC-1"]=[{body:("PR: https://example/pull/1"|jira_text_adf)}]|jira_recorded(.;"ABC-1";[{id:"e1",kind:"pr_link",text:"https://example/pull/1"},{id:"e2",kind:"pr_merged",text:"https://example/pull/1"}];null)|.==["e1"])),
 check("T45";($base|.ledger.entries=[{entry_id:"old",site:.site,account_id:.account_id,kind:"comment",key:"ABC-1",state:"verified",events:["e1"]}]|jira_recorded(.;"ABC-1";[{id:"e1",kind:"pr_link"},{id:"e2",kind:"pr_merged"}];null)|.==["e1"])),
 check("T46";($base|.issues["ABC-1"].reads.comments="partial"|rules|kinds|index("comment")==null)),
 check("T47";($base|.comments["ABC-1"]=[{_events:["e1"]}]|jira_recorded(.;"ABC-1";[{id:"e1",kind:"report_verified"}];null)|.==["e1"])),
 check("T48";($base|.ledger.entries=[{entry_id:"self",site:.site,account_id:.account_id,kind:"comment",key:"ABC-1",state:"approved",events:["e1"]}]|jira_recorded(.;"ABC-1";[{id:"e1",kind:"report_verified"}];"self")|length==0)),
 check("T54";($new|.evidence[0].text="DEF-99 feature"|rules|kinds|index("create_issue")==null)),
 check("T55";jira_new_queries("ABC";"fix update";[];[];[])|all(.[];.word_count<2)),
 check("T56";($new|.ledger.markers=[{kind:"create",site:.site,account_id:.account_id,entry_id:"old",evidence:.works[0].evidence}]|rules|kinds|index("create_issue")==null)),
 check("T59";($new|rules|.proposals[]|select(.kind=="create_issue")|.payload.summary=="[BACK] feature implementation")),
 check("T60";($new|.config.repos={}|rules|kinds|index("create_issue")==null)),
 check("T61";jira_new_queries("ABC";"feature \") AND other ~";[];[];[])|all(.[];.jql|startswith("project = \"ABC\" AND "))),
 check("T64";($new|.ledger.markers=[{kind:"create",site:"https://other.atlassian.net",account_id:.account_id,entry_id:"old",evidence:.works[0].evidence}]|rules|kinds|index("create_issue")!=null)),
 check("T72";($base|.ledger.markers=[{kind:"comment",site:.site,account_id:.account_id,key:"ABC-1",events:[{id:"e1",kind:"pr_link",evidence_id:"pr:one"}]}]|jira_recorded(.;"ABC-1";[{id:"e1",kind:"pr_link"}];null)|.==["e1"])),
 check("T80";($base|.ledger.dismissed=[{site:.site,account_id:.account_id,kind:"comment",events:["e1"]}]|jira_recorded(.;"ABC-1";[{id:"e1",kind:"report_verified"},{id:"e2",kind:"report_verified"}];null)|.==["e1"])),
 check("T81";([{id:"pr:one",kind:"pr",number:1,repo:"example",keys:[],commits_complete:true,commit_oids:["x"],state:"OPEN",url:"https://example/pull/1",activity:[{kind:"commit",at:"2026-10-08T00:00:00Z"}],ts:"2026-10-08T00:00:00Z"},{id:"git:x",kind:"git",repo:"example",keys:[],sha:"x",merge:false,text:"feature"}] as $e|$e|jira_works|.[0]|jira_events($e)|map(.kind)==["pr_link"])),
 check("T83";($base|.llm_valid=true|.llm.sections=[{target:"ABC-1",header:"완료 조건",lines:[{text:"운영 배포 완료",evidence:.works[0].evidence}]},{target:"ABC-1",header:"작업 내용",lines:[{text:"운영 배포 완료",evidence:.works[0].evidence}]}]|rules|.proposals[]|select(.kind=="fill_description")|any(.payload.sections[];.header=="완료 조건" and (.lines|length)==1) and all(.payload.sections[];.header!="작업 내용" or (.lines|length)==0))),
 check("T84";{header:"완료 조건",items:[{text:"one",marked_done:true},{text:"two",marked_done:false},{text:"three",marked_done:false}]}|jira_condition_text|contains("완료 조건 3개 · 남은 2개"))
] | all(.[];.pass)
