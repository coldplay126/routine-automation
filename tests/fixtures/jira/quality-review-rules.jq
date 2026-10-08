include "jira";
def check($name;$ok): if $ok then true else error($name) end;
. as $base |
"https://github.com/example-org/widget-server/pull/63" as $url |
{kind:"url",url:$url,ignored_words:[]} as $url_query |
{fields:{summary:"Docker image cache",description:null}} as $issue |
($base|.config.repos={example:{project:"ABC",prefix:"[BACK]"}}|.works[0].keys=[]|.works[0].flags=[]|
 .evidence[0].text="game quest type implementation"|.llm_valid=true|
 .llm={merge:[],attach:[],links:[],create:[{work:.works[0].id,summary:"game quest type implementation"}],sections:[]}|
 .llm.sections=[{target:.works[0].id,header:"작업 내용",lines:[{text:"game quest type implementation",evidence:.works[0].evidence}]}]|
 .create_meta.ABC={ok:true,name:"작업"}|.duplicates[.works[0].id]={complete:true,matches:[],possible:[]}) as $new |
def reports($text): {id:"rep:scope",kind:"report",repo:"example",ts:"2026-10-08T00:00:00Z",text:$text} as $report|
 {active:true,evidence:[$report.id]}|jira_events([$report]);
[
 check("PR identities normalize host/owner/repo, suffix, slash, query, fragment and Korean particles";
  all([$url,$url+"/",$url+"/files",$url+"/commits",$url+"?tab=files",$url+"#discussion_r1",$url+"에서",
   "https://GitHub.COM/EXAMPLE-ORG/WIDGET-SERVER/pull/63/files?tab=1#discussion"][];
   . as $variant|$issue|.fields.description={type:"doc",content:[{type:"inlineCard",attrs:{url:$variant}}]}|jira_duplicate_match("game quest implementation";$url_query))),
 check("Nested panel/table/codeBlock/blockquote split text preserves exact URLs";
  all(["panel","table","codeBlock","blockquote"][];. as $kind|$issue|
   .fields.description={type:"doc",content:[{type:$kind,content:[{type:"paragraph",content:[{type:"text",text:$url[:30]},{type:"text",text:$url[30:]}]}]}]}|
   jira_duplicate_match("game quest implementation";$url_query))),
 check("Adjacent codeBlock text joins, but different paragraph blocks cannot forge a URL";
  ($issue|.fields.description={type:"doc",content:[{type:"codeBlock",content:[{type:"text",text:$url[:30]},{type:"text",text:$url[30:]}]}]}|jira_duplicate_match("game quest implementation";$url_query)) and
  ($issue|.fields.description={type:"doc",content:[{type:"paragraph",content:[{type:"text",text:$url[:30]}]},{type:"paragraph",content:[{type:"text",text:$url[30:]}]}]}|jira_duplicate_match("game quest implementation";$url_query)|not)),
 check("Comment-only nested link marks prove exact PR identities";
  ($issue|.comments=[{body:{type:"doc",content:[{type:"panel",content:[{type:"paragraph",content:[{type:"text",text:"PR",marks:[{type:"link",attrs:{href:($url+"/files#discussion")}}]}]}]}]}}]|jira_duplicate_match("game quest implementation";$url_query))),
 check("Unproven URL hits remain visible and block creation";
  ($new|.duplicates[.works[0].id].possible=["ABC-10","ABC-11"]|jira_rules(.)|all(.proposals[];.kind!="create_issue" and .kind!="link") and any(.questions[];contains("ABC-10") and contains("URL 부분 일치")))),
 check("Too few useful words with a PR cannot permit creation";
  ($new|.duplicates[.works[0].id]={complete:false,reason:"insufficient_summary_words",matches:[],possible:[]}|jira_rules(.)|all(.proposals[];.kind!="create_issue") and any(.questions[];startswith("요약 고유 단어 부족")))),
 check("Single-word normalized exact title remains a strong match";
  {fields:{summary:"[BACK] Dockerfile 수정"}}|jira_duplicate_match("[widget-server] Dockerfile 수정";{kind:"summary",ignored_words:[],summary_tags:["[BACK]","[widget-server]"]})),
 check("Unrelated configured repositories do not erase domain words or weaken unrelated links";
  ("어드민 web 로그인 수정"|jira_words|length)==3 and (jira_new_queries("ABC";"어드민 web 로그인 수정";[];[];[])|all(.[];.word_count==3)) and (jira_weak("어드민 로그인";"어드민 로그인")|not)),
 check("Two keyed proof sentences reach both targets in either order with the same event identity";
  all(["ABC-1 운영 조회 확인했습니다. ABC-2 운영 조회 확인했습니다.","ABC-2 운영 조회 확인했습니다. ABC-1 운영 조회 확인했습니다."][];
   reports(.) as $events|all(["ABC-1","ABC-2"][];. as $key|$events|jira_events_for_key([$key];[])|
    length==1 and .[0]._identity==["event","report_verified","rep:scope"] and (.[0].text|startswith($key))))),
 check("Key-specific explicit proof is preferred to earlier inherited proof";
  reports("ABC-1 조사 정리했습니다. 운영 조회 확인했습니다. ABC-1 운영 정상 확인했습니다.")|jira_events_for_key(["ABC-1"];[])|.[0].text=="ABC-1 운영 정상 확인했습니다"),
 check("Unkeyed follow-up inherits the nearest preceding issue, not the other work key";
  reports("ABC-1 원인 조사 정리했습니다\nABC-2 운영 배포했습니다\n운영에서 정상 동작 확인했습니다") as $events|
  ($events|jira_events_for_key(["ABC-1"];[])|length)==0 and ($events|jira_events_for_key(["ABC-2"];[])|length)==2 and
  ($events|jira_events_for_key(["ABC-2"];[])|jira_comment_text|startswith("배포·확인 보고"))),
 check("Report naming only the other key is never assigned to the current work key";
  reports("ABC-2를 운영에 배포 완료했습니다\n운영 조회 확인했습니다")|jira_events_for_key(["ABC-1"];[])|length==0),
 check("Entirely unkeyed proof remains eligible, and an old requested key can identify the same target";
  (reports("운영 조회 확인했습니다")|jira_events_for_key(["ABC-1"];[])|length)==1 and
  (reports("OLD-1 운영 조회 확인했습니다")|jira_events_for_key(["ABC-1","OLD-1"];[])|length)==1),
 check("Model limits, omitted summaries and conflicting summaries retain distinct bounded work examples";
  ($new|.llm.create=[]|.model_evidence_ids=[]|.works=[range(0;8) as $i|$new.works[0]|.id=("w-budget-"+($i|tostring))]|jira_rules(.)|
   (.questions|length)==1 and any(.questions[];contains("모델 입력 상한 제외: 8건") and contains("w-budget-0") and contains("외 5건"))) and
  ($new|.llm.create=[]|.works[0].flags=["create_summary_conflict"]|jira_rules(.)|any(.questions[];contains("모델 요약 충돌") and contains($new.works[0].id)))),
 check("Only configured prefix/current repo tags strip and merge-only works cannot create";
  ("[BACK] [widget-server] game quest implementation"|jira_summary_text(["[BACK]","[widget-server]"]))=="game quest implementation" and
  jira_create_summary("[BACK]";"[긴급] [AOS] game quest implementation")=="[BACK] [긴급] [AOS] game quest implementation" and
  ("[other-repo] game quest implementation"|jira_summary_text(jira_summary_tags(["example"];$new.config)))=="[other-repo] game quest implementation" and
  ($new|.evidence[0].text="main → staging 백머지"|jira_rules(.)|all(.proposals[];.kind!="create_issue") and any(.questions[];contains("병합·백머지만"))) and
  ([{kind:"git",text:"main → staging 백머지"},{kind:"git",text:"feature implementation"}]|jira_merge_only|not))
,
 check("Branch-style keys and Korean particles retain full issue numbers without prefix/ASCII-suffix false hits";
  all(["Merge pull request #636 from org/ABC-398-quest-type","feature/ABC-398-quest","ABC-398에서"][];jira_key_tokens==["ABC-398"]) and
  ("ABC-3980"|jira_key_tokens)==["ABC-3980"] and all(["ABC-398_quest","ABC-398abc","xABC-398"][];jira_key_tokens==[])),
 check("PR member branch references retain the existing key even when the PR title has no key";
  [{id:"pr:branch",kind:"pr",repo:"example",keys:[],url:$url,number:63,text:"game quest implementation",state:"OPEN",commits_complete:true,commit_oids:["member"],activity:[],ts:"2026-10-08T00:00:00Z"},
   {id:"git:member",kind:"git",repo:"example",keys:("Merge pull request #636 from org/ABC-398-quest-type"|jira_key_tokens),sha:"member",merge:true,text:"Merge pull request #636 from org/ABC-398-quest-type",ts:"2026-10-08T00:00:00Z"}]|
  jira_works|length==1 and .[0].keys==["ABC-398"] and .[0].pr_member_evidence==["git:member"]),
 check("Duplicate rejection is scoped to site/account/PR-Git evidence and never removes proven matches";
  {possible:["ABC-10","ABC-11"],matches:["ABC-1"]} as $search|
  ($new|.links.rejections=[{kind:"duplicate",site:.site,account_id:.account_id,evidence_id:.works[0].evidence[0],key:"ABC-10"}]) as $rejected|
  ($search|jira_duplicate_visible($rejected;$rejected.works[0]))=={possible:["ABC-11"],matches:["ABC-1"]} and
  all([($rejected|.links.rejections[0].site="https://other.atlassian.net"),($rejected|.links.rejections[0].account_id="other-account"),($rejected|.links.rejections[0].evidence_id="git:other"),($rejected|.links.rejections[0].evidence_id="rep:report")][];. as $ctx|$search|jira_duplicate_visible($ctx;$ctx.works[0])|.possible==["ABC-10","ABC-11"])),
 check("Duplicate choice excludes exact matches and records only source-scoped selected candidates";
  {works:[{id:"w-one",evidence:["pr:url","git:sha","rep:report"]}],searches:{duplicates:[{work_id:"w-one",possible:["ABC-1","ABC-10"],matches:["ABC-1"]}]}}|
  jira_duplicate_choices as $choices|
  ($choices|length)==1 and $choices[0].key=="ABC-10" and $choices[0].evidence==["pr:url","git:sha"] and
  ({rejections:[]}|jira_duplicate_reject([];$choices;"site";"account";"now")|.rejections)==[] and
  ({rejections:[]}|jira_duplicate_reject([$choices[0].value];$choices;"site";"account";"now")|
   jira_duplicate_reject([$choices[0].value];$choices;"site";"account";"later")|.rejections|length)==2)
]|all(.[];.)
