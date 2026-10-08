include "jira";
def check($name;$ok): if $ok then true else error($name) end;
. as $base |
"https://github.com/example-org/widget-server/pull/63" as $url |
(jira_new_queries("ABC";"[BACK] widget-server example-org game quest type implementation";[$url];["back"];["[BACK]","[widget-server]"])|map(select(.kind=="url"))[0]) as $url_query |
{kind:"words",ignored_words:$url_query.ignored_words,summary_tags:$url_query.summary_tags} as $word_query |
{fields:{summary:"[BACK] widget-server example-org Docker image cache",description:null}} as $docker |
{merge:[],attach:[],links:[],create:[],sections:[]} as $empty_llm |
($base|.config.repos={example:{project:"ABC",prefix:"[BACK]"}}|.works[0].keys=[]|.works[0].flags=[]|.evidence[0].text="game quest type implementation"|
 .llm_valid=true|.llm=$empty_llm|.llm.create=[{work:.works[0].id,summary:"game quest type implementation"}]|
 .duplicates[.works[0].id]={complete:true,matches:["ABC-1","ABC-2"]}|
 .issues["ABC-2"]=.issues["ABC-1"]|.issues["ABC-2"].key="ABC-2"|.issues["ABC-2"].requested_key="ABC-2"|.issues["ABC-2"].id="200") as $multiple |
[
 check("URL tokenized Docker search results are not exact PR matches";($docker|jira_duplicate_match("game quest type implementation";$url_query)|not)),
 check("URL numeric prefix and unrelated PR are not exact matches";all([($url+"0"),"https://github.com/example-org/widget-api/pull/86"][];. as $other|$docker|.fields.description={type:"doc",content:[{type:"inlineCard",attrs:{url:$other}}]}|jira_duplicate_match("game quest type implementation";$url_query)|not)),
 check("URL is exact in summary, split ADF text, link marks or cards";all([
   ($docker|.fields.summary="PR: "+$url),
   ($docker|.fields.description={type:"doc",content:[{type:"paragraph",content:[{type:"text",text:$url[:30]},{type:"text",text:$url[30:]}]}]}),
   ($docker|.fields.description={type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"PR",marks:[{type:"link",attrs:{href:$url}}]}]}]}),
   ($docker|.fields.description={type:"doc",content:[{type:"inlineCard",attrs:{url:$url}}]})
 ][];jira_duplicate_match("game quest type implementation";$url_query))),
 check("Repository, org and prefix overlap is not unique content";($docker|jira_duplicate_match("[BACK] widget-server example-org game quest type implementation";$word_query)|not)),
 check("Normalized exact titles remain strong even with common words";{fields:{summary:"[BACK] 스테이징 도메인 수정"}}|jira_duplicate_match("[widget-server] 스테이징 도메인 수정";$word_query)),
 check("Two words below half of the shorter side are not strong";{fields:{summary:"alpha beta other gamma delta epsilon"}}|jira_duplicate_match("alpha beta one two three four";$word_query)|not),
 check("Two words at half of the shorter side are strong";{fields:{summary:"alpha beta gamma delta"}}|jira_duplicate_match("alpha beta one two three four";$word_query)),
 check("One overlapping word is never strong";{fields:{summary:"alpha beta"}}|jira_duplicate_match("alpha gamma";$word_query)|not),
 check("Multiple strong duplicate issues produce only a question";($multiple|jira_rules(.)|all(.proposals[];.kind!="link" and .kind!="create_issue") and any(.questions[];startswith("중복 후보 여러 개:")))),
 check("One strong duplicate remains one link candidate";($multiple|.duplicates[.works[0].id].matches=["ABC-1"]|jira_rules(.)|[.proposals[]|select(.kind=="link" and .payload.origin=="duplicate")]|length)==1),
 check("Highest report label and one PR URL retain all eligible event IDs";
   ({id:"rep:one",kind:"report",repo:"example",ts:"2026-10-08T00:00:00Z",text:"ABC-1 운영 배포 완료했습니다 운영 조회 확인했습니다"} as $report |
    ({active:true,evidence:[$report.id]}|jira_events([$report])|to_entries|map(.value+{id:("ev-report-"+(.key|tostring))})) as $reports |
    ($reports+[{id:"ev-pr-link",kind:"pr_link",evidence_id:"pr:one",text:$url},{id:"ev-pr-merge",kind:"pr_merged",evidence_id:"pr:one",text:$url},{id:"ev-pr-other",kind:"pr_merged",evidence_id:"pr:other",text:$url}]) as $events |
    $base|.works[0].keys=["ABC-1","ABC-2"]|.works[0].events=$events|
    .issues["ABC-2"]=.issues["ABC-1"]|.issues["ABC-2"].key="ABC-2"|.issues["ABC-2"].requested_key="ABC-2"|.issues["ABC-2"].id="200"|jira_rules(.) as $rules |
    ($rules.proposals|map(select(.kind=="comment" and .key=="ABC-1"))[0]) as $first |
    ($rules.proposals|map(select(.kind=="comment" and .key=="ABC-2"))[0]) as $second |
    ($reports|length)==2 and ($first.payload.events|length)==5 and ($first.events|length)==5 and
    ($first.payload.text|split("\n")|map(select(startswith("확인 보고")))|length)==1 and
    ($first.payload.text|contains("배포 보고")|not) and ($first.payload.text|split("\n")|map(select(startswith("PR 병합:")))|length)==1 and
    ($second.payload.events|length)==3 and all($second.payload.events[];.evidence_id|startswith("rep:")|not) and ($second.payload.text|contains("보고(")|not) and
    (({entries:[{entry_id:"l-test",kind:"comment",key:"ABC-2",site:$base.site,account_id:$base.account_id,proposal:$second,attempts:[],result:{}}],markers:[]}|jira_ledger_state("l-test";"unknown";{};"";"";0;0;"2026-10-08T00:00:00Z"))|.markers[0].events|length)==3)),
 check("Full sentence issue keys remain scoped even beyond display truncation";
   ({id:"rep:long",kind:"report",ts:"2026-10-08T00:00:00Z",text:("운영 배포 완료했습니다 "+("상세 내용 "*40)+"ABC-1 운영 조회 확인했습니다")} as $report |
    {active:true,evidence:[$report.id]}|jira_events([$report])|length>0 and all(.[];all(.candidates[];.keys==["ABC-1"]) and (.text|contains("ABC-1")|not)) and (jira_events_for_key(["ABC-2"];[])|length)==0)),
 check("A report naming both keys or no issue key remains eligible";[{kind:"report_verified",text:"ABC-1 ABC-2 운영 확인"},{kind:"report_verified",text:"운영 확인"},{kind:"report_verified",text:"GPT-4 운영 확인"}]|jira_events_for_key(["ABC-2"];["GPT"])|length==3),
 check("Unmapped repositories and missing create summaries are aggregated without proposals";
   ($base|.llm_valid=true|.llm=$empty_llm|.links={links:[],rejections:[]}|
    .config.repos={example:{project:"ABC",prefix:"[BACK]"}}|
    .works=([range(0;103)|{id:("w-noise-"+(.|tostring)),anchors:[],repos:[(if .<76 then "private-repo" else "example" end)],evidence:["git:noise-"+(.|tostring)],keys:[],active:true,flags:[],events:[]}] )|
    .evidence=[.works[]|{id:.evidence[0],kind:"git",repo:.repos[0],text:"feature implementation"}]|
    jira_rules(.)|.proposals==[] and (.questions|length)==2 and any(.questions[];contains("private-repo 76건") and contains("외 73건") and contains("jira.repos.private-repo.project")) and any(.questions[];contains("모델이 요약 제안 안 함: 27건") and contains("w-noise-100") and contains("외 24건")) and (keys|sort)==["proposals","questions"])),
 check("Conflicting mapping questions are not hidden by aggregation";($multiple|.works[0].repos=["example","second"]|.config.repos.second={project:"DEF",prefix:"[OTHER]"}|jira_rules(.)|any(.questions[];startswith("저장소 프로젝트 매핑 확인 필요:"))))
] | all(.[];.)
