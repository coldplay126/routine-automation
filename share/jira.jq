include "redact";
include "scrum";
include "learn";
def jira_display: split("\n")|map(gsub("\t";" ")|learn_preview)|join("\n");
# Epoch seconds retain fractional seconds; caller windows are also measured in seconds.
def jira_epoch:
 capture("^(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(?:\\.(?<fraction>[0-9]+))?(?<zone>Z|[+-][0-9]{2}:?[0-9]{2})$") as $t |
 ($t.date+"Z"|fromdateiso8601) -
 (if $t.zone=="Z" then 0 else ($t.zone|gsub(":";"")) as $z|
   ((($z[1:3]|tonumber)*3600+($z[3:5]|tonumber)*60)*(if $z[0:1]=="-" then -1 else 1 end)) end) + ("0."+($t.fraction // "0")|tonumber);
def jira_kind_text: {link:"연결",comment:"댓글",transition:"진행 중",fill_description:"본문 채우기",create_issue:"새 이슈"}[.] // .;
def jira_state_text: {approved:"승인 대기",applying:"반영 중",unknown:"결과 불명",applied:"반영",verified:"검증",verify_failed:"검증 실패",conflict:"충돌",blocked:"차단",failed:"실패",void:"무효",closed_by_user:"사용자 닫음"}[.] // .;
def jira_proposal_label:
 . as $record|(.proposal // .) as $p|
 (($p.kind|jira_kind_text)+" "+($p.key // $p.payload.project // "")+
 (if ($p.payload.summary // $p.payload.reason // "")!="" then " — "+($p.payload.summary // $p.payload.reason|jira_display|.[0:80]) else "" end)+
 " ["+($record.entry_id // $p.id)+"]")|jira_display;
def jira_settings: $ARGS.named.routine.jira;
def jira_headers: [jira_settings.templates[].headers[]]|unique;
def jira_nodes: ., (.content[]? | jira_nodes);
def jira_adf_text:
 if .==null then ""
 elif .type=="text" then .text // ""
 elif .type=="hardBreak" then "\n"
 elif .type|IN("inlineCard","blockCard","embedCard") then "[카드]"
 elif .type=="mention" then "[멘션]"
 elif .type|IN("doc","paragraph","heading","bulletList","orderedList","listItem","taskList","taskItem") then
   (if .type|IN("doc","bulletList","orderedList","listItem","taskList") then "\n" else "" end) as $separator |
   [.content[]?|jira_adf_text]|join($separator)
 else "[노드:"+(.type // "unknown")+"]" end;
def jira_adf_lines:
 if .==null then [] else
 [jira_nodes|select(.type|IN("paragraph","heading"))|[.content[]?|jira_adf_text]|join("")|split("\n")[]|norm|select(length>0)] end;
def jira_adf_state:
 if .==null then {state:"empty",reasons:[]} else
 [jira_nodes|select((.type|IN("doc","paragraph","text","hardBreak","bulletList","orderedList","listItem","heading"))|not)|.type // "unknown"] as $bad |
 [jira_nodes|.marks[]?|select((.type|IN("strong","em","underline"))|not)|.type] as $marks |
 if ($bad|length)>0 then
   {state:(if all($bad[];IN("inlineCard","blockCard","embedCard","mention","media","mediaSingle","mediaGroup","table","tableRow","tableCell","tableHeader","codeBlock","panel","emoji","rule","taskList","taskItem","date","status","extension","bodiedExtension","inlineExtension")) then "content" else "undetermined" end),reasons:($bad|unique)}
 elif ($marks|length)>0 then {state:"content",reasons:($marks|unique)}
 else jira_adf_lines as $lines | {state:(if ($lines|length)==0 then "empty" elif all($lines[];. as $l|jira_headers|index($l)!=null) then "template_only" else "content" end),reasons:[]} end end;
def jira_adf_canon:
 if .==null then null else
 {type:.type} + (if has("text") then {text:.text} else {} end) +
 (if has("content") then {content:[.content[]|jira_adf_canon]} else {} end) +
 (if has("marks") then {marks:[.marks[]|{type:.type}+(if .type=="link" then {attrs:{href:.attrs.href}} else {} end)]} else {} end) +
 (if .type=="heading" then {attrs:{level:.attrs.level}}
  elif .type|IN("inlineCard","blockCard","embedCard") then {attrs:{url:.attrs.url}} else {} end)
 end;
def jira_template($type): [jira_settings.templates|to_entries[]|select(.value.match|index($type)!=null)|.value+{name:.key}][0] // null;
def jira_conditions($template):
 if $template.conditions_header==null then {header:null,items:[]} else
 reduce (.content // [])[] as $block ({collect:false,items:[]};
   ($block|jira_adf_text|norm) as $text |
   if $text==$template.conditions_header then .collect=true
   elif $template.headers|index($text)!=null then .collect=false
   elif .collect then
     .items += [(if $block.type|IN("bulletList","orderedList","taskList") then $block.content[] else $block end) |
       . as $item | [jira_nodes|select(.type=="text" and (.text|norm|length)>0)] as $texts |
       {text:(jira_adf_text|redact|norm|jira_display),marked_done:(($item.type=="taskItem" and $item.attrs.state=="DONE") or (($texts|length)>0 and all($texts[];any(.marks[]?;.type=="strike"))))}|select(.text!="")]
   else . end) | {header:$template.conditions_header,items:.items} end;
def jira_condition_text:
 if .header==null then "완료 조건 칸 없음(버그 양식)"
 elif (.items|length)==0 then "완료 조건 없음"
 else "완료 조건 \(.items|length)개 · 남은 \([.items[]|select(.marked_done!=true)]|length)개 (Jira 표시 기준, 자동 판정 아님)" +
   ([.items[]|select(.marked_done!=true)|"\n- "+.text]|join("")) end;
def jira_history($account):
 . as $history | [.[].items[]?|select(.field=="description" or .fieldId=="description")|.fromString // "" |
 split("\n")[]|gsub("\\\\(?<b>[\\[\\]])";"\(.b)")|sub("^[[:space:]]*(h[1-6]\\.|[#*+-]+)[[:space:]]*";"")|gsub("[*_+]";"")|norm|select(length>0)|select(. as $l|jira_headers|index($l)==null)] as $prior |
 [$history[]|select(any(.items[]?;.field=="description" or .fieldId=="description"))]|sort_by(.created)|last as $last |
 {complete:true,prior_content:(($prior|length)>0),last_by_me:($last.author.accountId==$account),last_at:$last.created};
def jira_status_entered($history):
 . as $issue|.fields.status.id as $status | ([$history[]|select(any(.items[]?;(.field=="status" or .fieldId=="status") and .to==$status))|.created]|sort|last) // $issue.fields.created;
def jira_issue($key;$account;$hash;$history;$reads):
 . as $raw | jira_template(.fields.issuetype.name) as $template |
 {id:.id,key:.key,requested_key:$key,summary:(.fields.summary|redact|jira_display),project:.fields.project.key,assignee_is_me:(.fields.assignee.accountId==$account),
 type:{id:.fields.issuetype.id,name:(.fields.issuetype.name|jira_display),hierarchy_level:(.fields.issuetype.hierarchyLevel // (if .fields.issuetype.subtask==true then -1 else 0 end))},
 status:{id:.fields.status.id,name:(.fields.status.name // .fields.status.id|jira_display),category:.fields.status.statusCategory.key,entered_at:($raw|jira_status_entered($history))},updated:.fields.updated,
 description:((.fields.description|jira_adf_state)+{canon_hash:$hash,headers:(.fields.description|jira_adf_lines),excerpt:(.fields.description|jira_adf_text|redact|jira_display|.[:500])}),
 description_history:(if $reads.changelog=="ok" then $history|jira_history($account) else {complete:false,prior_content:false} end),
 conditions:(.fields.description|jira_conditions($template)),reads:$reads};
def jira_key_tokens: [scan("\\b[A-Z][A-Z0-9]{1,9}-[0-9]+(?![A-Za-z0-9_])")]|unique;
def jira_keys:
 [jira_key_tokens[]|. as $key|select(($key|capture("^(?<p>.+)-[0-9]+$").p) as $p|jira_settings.projects[$p]!=null)|select(test("-[1-9][0-9]*$"))]|sort;
def jira_id_inputs: [.[]|select(._identity!=null)|{ref:._ref,input:._identity}];
def jira_with_ids($hashes):
 map(if ._identity!=null then .id=((._prefix // "")+$hashes[._ref][0:16])|del(._ref,._prefix,._identity) else . end);
def jira_evidence($cwd):
 [(.git[]?|{id:("git:"+.sha),kind:"git",ts:.author_ts,repo:.repo,text:.subject,sha:.sha,keys:(.subject|jira_keys),merge:(.subject|test("^Merge (pull request|branch|remote-tracking branch)"))}),
  (.prs[]?|select(.roles|index("author")!=null)|{id:("pr:"+.url),kind:"pr",ts:((.activity|map(.at)|max) // .createdAt),repo:(.repository|if type=="object" then .nameWithOwner // .name else . end|split("/")|last),text:.title,url:.url,number:.number,
   keys:(.title|jira_keys),state:(.current.state // .state|ascii_upcase),activity:(.activity // []),commit_oids:(.commit_oids // []),commits_complete:(.commits_complete // false)}),
  (.sessions[]?|. as $session|(.source // "omp") as $engine|
   {id:("ses:"+$engine+":"+.id),kind:"session",ts:.last_ts,repo:$cwd[.cwd // ""],text:.title,keys:[],session_id:.id,engine:$engine},
   (.reports[]?|{id:null,_ref:("rep:"+$engine+":"+$session.id+":"+ .ts),_prefix:"rep:",_identity:["rep",$engine,$session.id,.ts],
    kind:"report",ts:.ts,repo:$cwd[$session.cwd // ""],text:.text,keys:(.text|jira_keys),session_id:$session.id,engine:$engine}))];
def jira_work($evidence;$anchors):
 {id:null,anchors:($anchors|unique|sort),repos:([$evidence[].repo|select(.!=null)]|unique),evidence:($evidence|map(.id)|unique|sort),
 keys:([$evidence[].keys[]]|unique|sort),
 active:any($evidence[];.kind=="git" or (.kind=="pr" and any(.activity[]?;.kind|IN("created","commit","merged","merged_by_other")))),flags:[],pr_member_evidence:[]};
def jira_work_ids:
 to_entries|map(.value+{_ref:("work:"+(.key|tostring)),_prefix:"w-",_identity:(["work"]+.value.anchors)});
def jira_works:
 . as $evidence | [ .[]|select(.kind=="pr")] as $prs |
 (reduce ($prs|sort_by(.id))[] as $pr ({works:[],seen:[]};
  .seen as $seen |
  ([$pr]+[$evidence[]|select(.kind=="git" and .repo==$pr.repo)|select(
    (.sha as $sha|$pr.commit_oids|index($sha)!=null) or
    (.text|test("^Merge pull request #"+($pr.number|tostring)+"\\b|\\(#"+($pr.number|tostring)+"\\)$")))|
    select(.id as $id|$seen|index($id)==null)]) as $members |
  .works+=[jira_work($members;[$pr.id])|.pr_member_evidence=[$members[]|select(.kind=="git")|.id]]|.seen+=[$members[].id])|.works) as $prworks |
 [$evidence[]|select(.kind|IN("git","report"))|. as $e|
  select(all($prworks[];.evidence|index($e.id)==null))|select(.merge!=true)] as $remaining |
 ($prworks +
  ([$remaining[]|select((.keys|length)>0)]|group_by(.keys)|map(jira_work(.;["keys:"+(.[0].keys|join(","))]))) +
  [$remaining[]|select(.kind=="git" and (.keys|length)==0)|jira_work([.];[.sha])]) |
 map(. as $w|if (.anchors|all(.[];startswith("pr:")|not)) and any($prs[];.commits_complete==false and (.repo as $r|$w.repos|index($r)!=null)) then .flags+=["pr_membership_unknown"] else . end) |
 jira_work_ids;
# Accept a whole JSON object or one explicitly delimited JSON fence, never scan containers.
def jira_llm_json:
 . as $text |
 (try fromjson catch (
  ($text|split("\n")|map(sub("\r$";""))) as $lines |
  [range(0;$lines|length)|select($lines[.]|test("^\\s*```"))] as $fences |
  if ($fences|length)!=2 then error("Expected one JSON object or fence")
  elif ($lines[$fences[0]]|test("^\\s*```[\\t ]*([Jj][Ss][Oo][Nn])?[\\t ]*$")|not) then error("Invalid opening JSON fence")
  elif ($lines[$fences[1]]|test("^\\s*```[\\t ]*$")|not) then error("Invalid closing JSON fence")
  elif any([($lines[:$fences[0]]|join("\n")),($lines[$fences[1]+1:]|join("\n"))][];try (fromjson|true) catch false) then error("Unexpected JSON outside fence")
  else $lines[$fences[0]+1:$fences[1]]|join("\n")|fromjson end)) |
 if type=="object" then . else error("Expected one JSON object") end;
def jira_summary_tags($repos;$config):
 [$repos[]|. as $repo|("["+$repo+"]"),("["+($repo|split("/")[-1])+"]"),($config.repos[$repo].prefix // "")]|map(select(length>0))|unique;
def jira_summary_text($tags):
 norm as $text|((try ($text|capture("^(?<tag>\\[[^\\]\\r\\n]*\\])(?<rest>.*)$")) catch null) // null) as $head |
 if $head!=null and ($tags|map(ascii_downcase)|index($head.tag|ascii_downcase)!=null) then $head.rest|jira_summary_text($tags) else $text end;
def jira_merge_subject:
 test("^Merge (pull request|branch|remote-tracking branch)";"i") or
 (jira_summary_text([jira_settings.repos // {}|to_entries[]|.value.prefix,("["+.key+"]")])|test("^(\\S+[[:space:]]*(→|->|=>)[[:space:]]*\\S+[[:space:]]+)?(백[[:space:]]*머지|back[[:space:]-]*merge)([[:space:]]*[:(].*)?$";"i"));
def jira_merge_only:
 [.[]|select(.kind|IN("git","pr"))] as $proof |
 ($proof|length)>0 and all($proof[];(.kind=="git" and .merge==true) or (.text|jira_merge_subject));
# Only observed aliases and known surplus metadata are accepted before strict validation.
def jira_llm_normalize:
 if type!="object" then . else
 .merge|=(if type=="array" then map(if type=="object" then
   del(.reason,.evidence) |
   if keys==["works"] and (.works|type=="array") then .works
   elif keys==["ids"] and (.ids|type=="array") then .ids else . end
   else . end) else . end) |
 .attach|=(if type=="array" then map(if type=="object" then
   del(.reason) | if has("report") and (has("evidence")|not) then .evidence=.report|del(.report) else . end
   else . end) else . end) |
 .links|=(if type=="array" then map(if type=="object" then del(.evidence) else . end) else . end) |
 .create|=(if type=="array" then map(if type=="object" then del(.reason,.evidence) else . end) else . end)
 end;
def jira_llm_ok:
 type=="object" and (keys|sort)==(["merge","attach","links","create","sections"]|sort) and
 (.merge|type=="array" and length<=20 and all(.[];type=="array" and length>=2 and all(.[];learn_string_ok(false)))) and
 (.attach|type=="array" and length<=100 and all(.[];(keys|sort)==["evidence","work"] and (.evidence|learn_string_ok(false)) and (.work|learn_string_ok(false)))) and
 (.links|type=="array" and length<=30 and all(.[];(keys|sort)==["key","reason","work"] and (.work|learn_string_ok(false)) and (.key|learn_string_ok(false)) and (.reason|learn_string_ok(false)))) and
 (.create|type=="array" and length<=30 and all(.[];(keys|sort)==["summary","work"] and (.work|learn_string_ok(false)) and (.summary|learn_string_ok(false) and length<=120))) and
 (.sections|type=="array" and all(.[];(keys|sort)==["header","lines","target"] and (.target|learn_string_ok(false)) and (.header|learn_string_ok(false)) and (.lines|type=="array" and length<=10 and all(.[];(keys|sort)==["evidence","text"] and (.text|learn_string_ok(false) and length<=300) and (.evidence|type=="array" and all(.[];learn_string_ok(false)))))));
# Bound only model input, never the collected evidence or deterministic rule context.
# Reserve connected context and a representative proof before spending extra evidence slots.
def jira_llm_input($candidates;$visits):
 def recent: -(try (.ts|jira_epoch) catch 0);
 . as $ctx | (.evidence|INDEX(.id)) as $by_id |
 ([.links.links[]|select(.site==$ctx.site and .account_id==$ctx.account_id)|{evidence_id,key}]|unique_by([.key,.evidence_id])) as $stored |
 [.works[]|. as $work|
   [$stored[]|select(.evidence_id as $id|$work.evidence|index($id)!=null)] as $links |
   ($work.evidence|map($by_id[.]|select(.!=null))|sort_by([
     (if .id as $id|any($links[];.evidence_id==$id) then 0 else 1 end),
     (if .kind=="pr" then 0 else 1 end),recent,.id])) as $proof |
   select(($proof|length)>0) |
   {work:$work,links:$links,proof:$proof,keys:($work.keys+[$links[].key]|unique),
    linked:(($work.keys|length)>0 or ($links|length)>0),
    latest:([$proof[]|try (.ts|jira_epoch) catch 0]|max // 0)}] |
 sort_by([.linked,-.latest,.work.id]) as $ranked |
 ([$ranked[]|select(.linked|not)] as $unlinked | [$ranked[]|select(.linked)] as $linked |
  $unlinked[:20]+$linked[:10]+$unlinked[20:]+$linked[10:]) as $priority |
 (reduce $priority[] as $row ({works:[],keys:[]};
   (.keys+$row.keys|unique) as $keys |
   if (.works|length)<30 and ($keys|length)<=30 then .works+=[$row]|.keys=$keys else . end)) as $selection |
 $selection.works as $selected |
 [$selected[].proof[0]]|unique_by(.id) as $representatives |
 [$selected[]|select(.linked|not)|.proof[1]?|select(.!=null)]|unique_by(.id)|
   map(select(.id as $id|all($representatives[];.id!=$id)))|sort_by([recent,.id])[:(50-($representatives|length))] as $extra |
 ($representatives+$extra|unique_by(.id)) as $proof |
 [$ctx.evidence[]|select(.kind=="report")|. as $report|
   select(all($ctx.works[];.evidence|index($report.id)==null))]|sort_by([recent,.id])[:10] as $reports |
 ($proof+$reports|unique_by(.id)) as $evidence |
 ($evidence|map(.id)) as $ids |
 [$selected[].work|.evidence|=map(select(. as $id|$ids|index($id)!=null))|
   {id,repos,keys,evidence,active,flags}] as $works |
 [$selected[]|. as $row|($row.links|map(select(.evidence_id==$row.proof[0].id))|.[0])|select(.!=null)]|unique_by([.key,.evidence_id]) as $primary_links |
 ($primary_links+[$selected[].links[]|select(.evidence_id as $id|$ids|index($id)!=null)]+[$stored[]|select(.evidence_id as $id|$reports|any(.[];.id==$id))]|
   reduce .[] as $link ({links:[],keys:$selection.keys};
     (.keys+[$link.key]|unique) as $keys |
     if (.links|length)<30 and ($keys|length)<=30 and $ctx.issues[$link.key]!=null and (.links|index($link)==null)
     then .links+=[$link]|.keys=$keys else . end)) as $link_context |
 {works:$works,evidence:[$evidence[]|{id,kind,ts,repo,text:.text[:400]}],
  unattached_reports:[$reports[]|{id,repo,text:.text[:400]}],
  session_hints:([$ctx.evidence[]|select(.kind=="session")]|sort_by([recent,.id])[:10]|map({id,repo,text:.text[:400]})),
  stored_links:$link_context.links,
  issues:($ctx.issues|to_entries|map(select(.key as $key|$link_context.keys|index($key)!=null))|sort_by(.key)|
    map({key,value:(.value|{key,summary:.summary[:120],type,status,description_excerpt:(.description.excerpt // "")[:400]})})|from_entries),
  candidates:($candidates|sort_by([-(try (.fields.updated|jira_epoch) catch 0),.key])[:20]|
    map({key,summary:.fields.summary[:120],type:.fields.issuetype.name,status:.fields.status.name,description_excerpt:(.fields.description|jira_adf_text|.[:400])})),
  templates:$ctx.config.templates,visit_hints:($visits|reduce .[] as $key ([];if index($key)==null then .+[$key] else . end)|.[:20])};
def jira_apply_llm($evidence;$llm):
 . as $initial |
 reduce $llm.merge[] as $group ({works:map(.aliases=[.id]),questions:[],used:[]};
   [$initial[]|select(.id as $id|$group|index($id)!=null)] as $members |
   if ($members|length)!=($group|unique|length) or
      any($group[];. as $id|$initial|all(.[];.id!=$id)) or
      ($members|map(.repos)|unique|length)!=1 or any($members[];(.repos|length)!=1) or ($members|map(.keys)|unique|length)!=1 or
      any(.used[];. as $id|$group|index($id)!=null)
   then .questions+=["작업 merge 무효: "+($group|join(", "))]
   else .used+=$group |
     .works=([.works[]|select(.aliases as $ids|all($ids[];. as $id|$group|index($id)==null))]+
      [($members|{id:.[0].id,aliases:map(.id),anchors:(map(.anchors[])|unique|sort),repos:.[0].repos,evidence:(map(.evidence[])|unique|sort),keys:.[0].keys,active:any(.[];.active),flags:(map(.flags[])|unique),pr_member_evidence:(map(.pr_member_evidence[]?)|unique|sort)})])
   end) |
 .questions as $questions | .works as $merged |
 [$llm.attach[]|. as $a|[$merged[]|select(.aliases|index($a.work)!=null)|.id][0] as $target|
  $a+{work:$target}] as $attachments |
 {works:$merged,questions:$questions,attachments:$attachments} as $mapped |
 reduce ($attachments|group_by(.evidence))[] as $group ($mapped;
  $group[0].evidence as $id|[$evidence[]|select(.id==$id and .kind=="report")][0] as $report|
  ($group|map(.work)|unique) as $targets |
  if ($targets|length)!=1 or $targets[0]==null or $report==null or
     any(.works[];.evidence|index($id)!=null) or
     any(.works[]; .id==$targets[0] and $report.repo!=null and (.repos|index($report.repo)==null))
  then .questions+=["보고 attach 무효: "+$id]
  else .works|=map(if .id==$targets[0] then .evidence+=[$id]|.keys=(.keys+$report.keys|unique|sort) else . end) end) |
 .llm=($llm|.attach=[]|.merge=[]) |
 .works as $works |
 .llm.links|=map(. as $l|.work=([$works[]|select(.aliases|index($l.work)!=null)|.id][0])) |
 .llm.create|=map(. as $c|.work=([$works[]|select(.aliases|index($c.work)!=null)|.id][0])) |
 .llm.sections|=map(. as $s|.target=([$works[]|select(.aliases|index($s.target)!=null)|.id][0] // $s.target)) |
 .llm.links as $links|.llm.links=[]|
 reduce ($links|group_by(.work))[] as $group (.;
  if $group[0].work==null or ($group|map(.key)|unique|length)>1 then
   .questions+=["연결 충돌 또는 없는 작업"] |
   .works|=map(if .id==$group[0].work then .flags+=["link_ambiguous"] else . end)
  else .llm.links+=[$group[0]] end) |
 .llm.create as $creates|.llm.create=[]|.works as $summary_works|jira_settings as $summary_config|
 reduce ($creates|map(. as $create|.summary|=jira_summary_text(jira_summary_tags(([$summary_works[]|select(.id==$create.work)|.repos][0] // []);$summary_config)))|group_by(.work))[] as $group (.;
  if $group[0].work==null or ($group|map(.summary)|unique|length)>1 then
   .questions+=["생성 요약 충돌 또는 없는 작업"] |
   .works|=map(if .id==$group[0].work then .flags+=["create_summary_conflict"] else . end)
  else .llm.create+=[$group[0]] end) |
 .works|=(map(del(.aliases))|jira_work_ids);
def jira_remap_final($before;$after;$llm):
 [range(0;$before|length)|{key:$before[.].id,value:$after[.].id}]|from_entries as $map |
 $llm|.links|=map(.work=$map[.work])|.create|=map(.work=$map[.work])|.sections|=map(.target=($map[.target] // .target));
def jira_report_candidates($report;$level):
 def keys: jira_key_tokens|map(. as $key|select(($key|split("-")[0]) as $prefix|(jira_settings.key_like_ignore // [])|index($prefix)==null));
 ($report.text|proving_sentences($level)|map(select($level!="verified" or test("운영|프로덕션|라이브|스테이징|배포|반영|prod|staging|live";"i")))) as $valid |
 ($report.text|keys) as $all_keys |
 reduce ($report.text|split("\n")[]|splits("[.;!。]")|gsub("\\*\\*|__";"")|norm) as $sentence ({last:[],candidates:[]};
  ($sentence|keys) as $explicit |
  if ($explicit|length)>0 then .last=$explicit else . end |
  if ($valid|index($sentence))!=null then
   .candidates+=[{text:($sentence|redact|.[:120]),explicit_keys:$explicit,
    keys:(if ($explicit|length)>0 then $explicit elif (.last|length)>0 then .last else $all_keys end),
    ambiguous:(($explicit|length)==0 and (.last|length)==0 and ($all_keys|length)>1)}]
  else . end)|.candidates;
def jira_events($evidence):
 . as $work | [$evidence[]|select(.id as $id|$work.evidence|index($id)!=null)] |
 [ .[] |
 if .kind=="pr" then . as $pr |
   (if $work.active then {kind:"pr_link",evidence_id:.id,at:.ts,text:.url} else empty end),
   (if .state=="MERGED" and any(.activity[]?;.kind|IN("merged","merged_by_other")) then {kind:"pr_merged",evidence_id:.id,at:([.activity[]|select(.kind|IN("merged","merged_by_other"))|.at]|max),text:.url} else empty end)
 elif .kind=="git" and (.id as $id|($work.pr_member_evidence // [])|index($id)==null) and .merge!=true then
   {kind:"commit",evidence_id:.id,at:.ts,text:((.repo // "")+" "+.sha[0:8])}
 elif .kind=="report" then . as $report |
   ("deployed","verified") as $level | jira_report_candidates($report;$level) as $candidates |
   if ($candidates|length)>0 then {kind:("report_"+$level),evidence_id:.id,at:.ts,text:$candidates[0].text,candidates:$candidates} else empty end
 else empty end] | to_entries | map(.value+{_ref:("event:"+.value.kind+":"+.value.evidence_id),_prefix:"ev-",_identity:["event",.value.kind,.value.evidence_id]});
def jira_tokens: ascii_downcase|[scan("[0-9a-z가-힣]{2,}")]|unique;
def jira_stopwords: ["도메인","스테이징","운영","배포","빌드","수정","추가","작업","확인","검토","개선","적용","정리","처리","fix","update","add","the","and","for","to","or","not","order","by","asc","desc","in","is","null","empty","github","com","http","https","pull","pr","merge","merged"]+(jira_settings.stopwords // []);
def jira_words: jira_stopwords as $ignored|jira_tokens|map(. as $word|select($ignored|index($word)==null));
def jira_url_words($urls):
 [$urls[]|capture("^https?://[^/]+/(?<owner>[^/]+)/(?<repo>[^/]+)/")|.owner,.repo]|map(jira_tokens)|add // [];
def jira_urls: [scan("https?://[^[:space:]<>\"\\[\\](),;]+")|sub("[.!]+$";"")]|unique;
def jira_url_identity:
 norm|sub("[.!]+$";"") as $raw |
 ((try ($raw|capture("^https?://(?<host>[^/?#]+)/(?<owner>[^/?#]+)/(?<repo>[^/?#]+)/pull/(?<number>[0-9]+)(?<tail>.*)$";"i")) catch null) // null) as $pr |
 if $pr!=null and ($pr.tail|test("^$|^/$|^/(files|commits)(/|[?#]|$)|^[?#]|^(에서|으로|을|를|은|는|에|와|과|도|의|로|까지|부터)$")) then
  "https://"+($pr.host|ascii_downcase)+"/"+($pr.owner|ascii_downcase)+"/"+($pr.repo|ascii_downcase)+"/pull/"+($pr.number|tonumber|tostring)
 else $raw end;
# This traversal is only for URL proof; the conservative empty-ADF classifier is unchanged.
def jira_adf_url_text:
 if .==null then "" elif .type=="text" then .text // "" elif .type=="hardBreak" then "\n"
 else [.content[]?|if .type=="text" then .text // "" else "\n"+jira_adf_url_text+"\n" end]|join("") end;
def jira_adf_urls:
 [(jira_adf_url_text|jira_urls[]),(jira_nodes|
  (if .type|IN("inlineCard","blockCard","embedCard") then .attrs.url // empty else empty end),
  (.marks[]?|select(.type=="link")|.attrs.href // empty))]|map(jira_url_identity)|unique;
def jira_weak($text;$summary):
 ($text|jira_words) as $words|($summary|jira_words)|all(.[];. as $w|$words|index($w)==null);
def jira_claim_proof:
 map(if .kind=="git" then {kind:"git",merge:(.merge // false),text:.text}
 elif .kind=="pr" then {kind:"pr",merge:(.state=="MERGED" and any(.activity[]?;.kind|IN("merged","merged_by_other"))),text:.text}
 elif .kind=="report" then {kind:"session",text:.text} else {kind:.kind,text:.text} end);
def jira_active_state: IN("approved","applying","unknown","applied","verified","verify_failed","closed_by_user");
def jira_context($site;$account): .site==$site and .account_id==$account;
def jira_fill_blocked($ctx;$issue;$exclude):
 any($ctx.ledger.markers[]?;jira_context($ctx.site;$ctx.account_id) and .issue_id==$issue.id and (.kind|IN("fill","create"))) or
 any($ctx.ledger.entries[]?;jira_context($ctx.site;$ctx.account_id) and .entry_id!=$exclude and .kind=="fill_description" and .issue_id==$issue.id and (.state|IN("applying","unknown")));
def jira_stored_strong_overlap($ctx;$work):
 any($ctx.links.links[]?;jira_context($ctx.site;$ctx.account_id) and (.evidence_id|test("^(pr|git):")) and (.evidence_id as $id|$work.evidence|index($id)!=null));
def jira_create_blocked($ctx;$work;$exclude):
 [$work.evidence[]|select(startswith("ses:")|not)] as $ids |
 jira_stored_strong_overlap($ctx;$work) or
 any($ctx.ledger.entries[]?;jira_context($ctx.site;$ctx.account_id) and .entry_id!=$exclude and .kind=="create_issue" and (.state|jira_active_state) and any(.proposal.evidence[]?;. as $id|$ids|index($id)!=null)) or
 any($ctx.ledger.dismissed[]?;jira_context($ctx.site;$ctx.account_id) and .kind=="create_issue" and any(.evidence[]?;. as $id|$ids|index($id)!=null)) or
 any($ctx.ledger.markers[]?;jira_context($ctx.site;$ctx.account_id) and .kind=="create" and .entry_id!=$exclude and any(.evidence[]?;. as $id|$ids|index($id)!=null));
def jira_links_for($ctx):
 . as $work |
 [$ctx.links.links[]?|select(jira_context($ctx.site;$ctx.account_id))|select(.evidence_id as $id|$work.evidence|index($id)!=null)] as $stored |
 [$stored[]|select(.evidence_id|test("^(pr|git):"))] as $strong |
 [$ctx.llm.links[]?|select(.work==$work.id)] as $llm |
 (if (.keys|length)>0 then [.keys[]|{key:.,basis:"key",origin:"key"}]
  elif ($strong|length)>0 then [$strong[].key]|unique|map({key:.,basis:"stored",origin:"stored"})
  elif ($stored|length)>0 then [$stored[].key]|unique|map({key:.,basis:"candidate",origin:"report_overlap"})
  elif ($llm|map(.key)|unique|length)==1 then [$llm[0]|{key:.key,basis:"candidate",origin:"llm",reason:.reason}]
  else [] end) |
 map(. as $link|$ctx.issues[.key] as $issue|
 select($issue!=null and $issue.key==$link.key and $ctx.config.projects[$issue.project]!=null and $issue.type.hierarchy_level<1)|
 select($link.origin!="llm" or ($ctx.allowed_keys|index($link.key)!=null))|
 select($link.basis!="candidate" or all($ctx.links.rejections[]?|select(.kind!="duplicate"); (jira_context($ctx.site;$ctx.account_id) and .key==$link.key and (.evidence_id as $id|$work.evidence|index($id)!=null))|not))|
 .weak=(if .basis=="candidate" then ([$ctx.evidence[]|select(.id as $id|$work.evidence|index($id)!=null)|.text]|join(" ")|jira_weak(.;$issue.summary)) else false end)|
 .overlap=[$stored[]|select(.key==$link.key)|.evidence_id]);
def jira_events_for_key($targets;$ignored):
 map((if .kind|IN("report_deployed","report_verified") then
  (.candidates // [{text:.text,keys:(.text|jira_key_tokens),explicit_keys:(.text|jira_key_tokens),ambiguous:false}]) |
  map(select(.ambiguous!=true)|.keys|=map(. as $key|select(($key|split("-")[0]) as $prefix|$ignored|index($prefix)==null))|
   . as $candidate|select((.keys|length)==0 or any($targets[];. as $key|$candidate.keys|index($key)!=null))) |
  sort_by(if any(.explicit_keys[];. as $key|$targets|index($key)!=null) then 0 else 1 end) | .[0]
 else {text:.text} end) as $chosen |
 select($chosen!=null)|.text=$chosen.text);
def jira_recorded($ctx;$key;$events;$exclude):
 ([($ctx.ledger.entries[]?|select(jira_context($ctx.site;$ctx.account_id) and .kind=="comment" and .key==$key and .entry_id!=$exclude and (.state|jira_active_state))|.events[]?),
   ($ctx.ledger.dismissed[]?|select(jira_context($ctx.site;$ctx.account_id) and .kind=="comment")|.events[]?),
   ($ctx.ledger.markers[]?|select(jira_context($ctx.site;$ctx.account_id) and .kind=="comment" and .key==$key)|.events[]?.id),
   ($ctx.comments[$key][]?|._events[]?)]|unique) as $ids |
 [$events[]|. as $event|
  select(($ids|index($event.id)!=null) or
   (if .kind|IN("pr_link","pr_merged","commit") then
     any($ctx.comments[$key][]?|select(._has_property!=true);
      (.body as $body|[$body|jira_nodes|select(.type=="paragraph")]|if length==0 then [$body] else . end) as $paragraphs |
      any($paragraphs[];
       ([jira_nodes|(.text // ""),(.attrs.href // ""),(.attrs.url // ""),(.marks[]?.attrs.href // "")]|join(" ")) as $text |
       if $event.kind=="commit" then $text|contains($event.evidence_id[4:12])
       else ($text|jira_urls|map(jira_url_identity)|index($event.text|jira_url_identity)!=null) and ($event.kind!="pr_merged" or ($text|test("병합|머지|merged";"i"))) end))
    else false end))|.id];
def jira_comment_text:
 . as $events|[.[]|select(.kind=="commit")|.text] as $commits|
 ([$events|to_entries[]|select(.value.kind!="commit")|
   .value+{_order:.key,_rank:({pr_link:1,pr_merged:2,report_deployed:3,report_verified:4}[.value.kind] // 0),
     _group:(if .value.kind|IN("pr_link","pr_merged") then ["pr",(.value.text|jira_url_identity)] else ["report",(.value.evidence_id // .value.id)] end)}]|
  group_by(._group)|map(. as $group|sort_by([-._rank,._order])[0]|
   if .kind|IN("pr_link","pr_merged") then .text|=jira_url_identity
   elif any($group[];.kind=="report_deployed") and any($group[];.kind=="report_verified") and ($group|map(.text)|unique|length)>1 then
    .both=true|.text=([$group[]|select(.kind=="report_deployed")|.text][0]+" / "+[$group[]|select(.kind=="report_verified")|.text][0])
   else . end)|sort_by(._order)) as $display |
 [(if ($commits|length)>0 then "커밋 \($commits|length)건: "+($commits|join(", ")) else empty end),
  ($display[]|
   if .kind=="pr_link" then "PR: "+.text
   elif .kind=="pr_merged" then "PR 병합: "+.text
   elif .kind=="report_deployed" then "배포 보고("+.at[0:10]+"): "+.text
   else (if .both==true then "배포·확인 보고(" else "확인 보고(" end)+.at[0:10]+"): "+.text end)]|reduce .[] as $line ([];if index($line)==null then .+[$line] else . end)|join("\n");
def jira_text_adf:
 {type:"doc",version:1,content:[split("\n")[]|{type:"paragraph",content:[{type:"text",text:.}]}]};
def jira_section_questions($ctx;$work;$target;$template):
 [$ctx.llm.sections[]?|select(.target==$target and .header!=$template.conditions_header)|. as $s|
  .lines[]|. as $line|
  [$ctx.evidence[]|select(.id as $id|$line.evidence|index($id)!=null)]|jira_claim_proof as $proof|
  select(($line.text|claim_classes|claims_supported(.;$proof))|not)|"본문 줄의 주장 확인 필요: "+$target+" / "+$s.header];
def jira_sections($ctx;$work;$target;$template):
 [$ctx.llm.sections[]?|select(.target==$target)|. as $section|
  select($template.headers|index($section.header)!=null)|
  .lines[]|. as $line|
  select((.evidence|length)>0 and all(.evidence[];. as $id|$work.evidence|index($id)!=null))|
  [$ctx.evidence[]|select(.id as $id|$line.evidence|index($id)!=null)]|jira_claim_proof as $proof|
  select($section.header==$template.conditions_header or ($line.text|claim_classes|claims_supported(.;$proof)))|
  $line+{header:$section.header}] as $lines |
 [$template.headers[] as $header|{header:$header,lines:([$lines[]|select(.header==$header)|del(.header)]|reduce .[] as $line ([];if any(.[];.text==$line.text) then . else .+[$line] end)|.[:10])}|
 if .header==$template.links_header then .lines += [$ctx.evidence[]|select(.kind=="pr" and (.id as $id|$work.evidence|index($id)!=null))|{text:.url,evidence:[.id]}] else . end];
def jira_sections_adf($template):
 {type:"doc",version:1,content:[.[]|
  {type:"paragraph",content:[{type:"text",text:.header}+(if $template.header_style=="strong" then {marks:[{type:"strong"}]} else {} end)]},
  (if (.lines|length)>0 then {type:"bulletList",content:[.lines[]|{type:"listItem",content:[{type:"paragraph",content:[{type:"text",text:.text}]}]}]} else empty end)]};
def jira_create_summary($prefix;$summary): (if $prefix=="" then "" else $prefix+" " end)+($summary|jira_summary_text([$prefix]));
def jira_proposal($kind;$work;$issue;$payload;$identity;$depends):
 {id:null,_ref:("proposal:"+$kind+":"+($issue.key // "")+":"+$work.id),_prefix:"p-",_identity:(["proposal",$kind]+$identity),
 kind:$kind,key:($issue.key // null),issue_id:($issue.id // null),work_id:$work.id,evidence:$work.evidence,events:[],
 depends_on:$depends,dependency_evidence:(if ($depends|length)>0 then [$work.evidence[]|select(test("^(pr|git|rep):"))] else [] end),basis_text:($work.evidence|join(", ")),warnings:[],preview:"",payload:$payload,
 snapshot:{updated:$issue.updated,status_id:$issue.status.id,status_entered_at:$issue.status.entered_at,description_canon_hash:$issue.description.canon_hash}};
def jira_transition($ctx;$issue):
 [$ctx.transitions[$issue.key][]?|select(.to.id==$ctx.config.projects[$issue.project].statuses.in_progress)|
 select(all(.fields[]?;.required!=true or .hasDefaultValue==true or .defaultValue!=null))][0] // null;
def jira_new_queries($project;$summary;$urls;$scope;$tags):
 ($summary|jira_summary_text($tags)) as $text | ($urls|map(jira_url_identity)|unique) as $pr_urls |
 (jira_url_words($pr_urls)+$scope|unique) as $ignored |
 ($text|jira_words|map(. as $word|select($ignored|index($word)==null))) as $all_words |
 ($all_words[:3]) as $words |
 def quote: gsub("\\\\";"\\\\")|gsub("\"";"\\\"");
 [ (if ($words|length)>0 then {kind:"words",jql:("project = \""+$project+"\" AND ("+([$words[]|"summary ~ \""+(quote)+"\""]|join(" OR "))+") ORDER BY created DESC")} else empty end),
   ($pr_urls[]|{kind:"url",url:.,jql:("project = \""+$project+"\" AND text ~ \"\\\""+(quote|quote)+"\\\"\"")}),
   (if ($text|length)>0 then {kind:"summary",jql:("project = \""+$project+"\" AND summary ~ \"\\\""+($text|quote|quote)+"\\\"\"")} else empty end)] |
 map(.ignored_words=$ignored|.summary_tags=$tags|.word_count=($all_words|length));
def jira_duplicate_match($summary;$query):
 if $query.kind=="url" then
   [(.fields.summary // ""|jira_urls|map(jira_url_identity)[]),(.fields.description|jira_adf_urls[]),
    (.comments[]?|.body|jira_adf_urls[])]|index($query.url|jira_url_identity)!=null
 elif $query.kind|IN("words","summary") then
   def words: jira_words|map(. as $word|select(($query.ignored_words // [])|index($word)==null));
   (.fields.summary // ""|jira_summary_text($query.summary_tags // [])|ascii_downcase) as $candidate_text |
   ($summary|jira_summary_text($query.summary_tags // [])|ascii_downcase) as $wanted_text |
   ($candidate_text|words) as $candidate | ($wanted_text|words) as $wanted |
   [$candidate[]|. as $word|select($wanted|index($word)!=null)] as $overlap |
   ($wanted_text!="" and $candidate_text==$wanted_text) or
   (($overlap|length)>=2 and ($overlap|length)*2>=([$candidate|length,$wanted|length]|min))
 else false end;
def jira_duplicate_visible($ctx;$work):
 .possible=(.possible // []|map(. as $key|select(
  any($ctx.links.rejections[]?|select(.kind=="duplicate");
   jira_context($ctx.site;$ctx.account_id) and .key==$key and
   (.evidence_id as $id|($id|test("^(pr|git):")) and ($work.evidence|index($id)!=null)))|not)));
def jira_duplicate_choices:
 .works as $works|[.searches.duplicates[]?|. as $search|
  $works[]|select(.id==$search.work_id)|. as $work|
  ($work.evidence|map(select(test("^(pr|git):")))) as $evidence|select(($evidence|length)>0)|
  (($search.possible // [])-($search.matches // []))[]|
  {value:($work.id+":"+.),label:("중복 아님? "+.+" — "+$work.id),key:.,evidence:$evidence}]|unique_by(.value);
def jira_duplicate_reject($selected;$choices;$site;$account;$now):
 reduce ($choices[]|select(.value as $value|$selected|index($value)!=null)|. as $choice|.evidence[]|
  {kind:"duplicate",site:$site,account_id:$account,evidence_id:.,key:$choice.key,rejected_at:$now}) as $record (.;
  if any(.rejections[]; .kind==$record.kind and .site==$record.site and .account_id==$record.account_id and .evidence_id==$record.evidence_id and .key==$record.key) then . else .rejections+=[$record] end);
def jira_group_proposals:
 group_by(if .kind|IN("link","create_issue") then [.kind,.work_id,.key] else [.kind,.key] end) |
 map(if .[0].kind=="comment" then
   . as $group|.[0]|.evidence=($group|map(.evidence[])|unique|sort)|.events=($group|map(.events[])|unique|sort)|
   .depends_on=($group|map(.depends_on[])|unique)|.dependency_evidence=($group|map(.dependency_evidence[])|unique|sort)|.payload.events=($group|map(.payload.events[])|unique_by(.id))|
   .payload.text=(.payload.events|jira_comment_text)|.payload.adf=(.payload.text|jira_text_adf)|
   ._identity=(["proposal","comment",.key]+.events)
 else .[0] end);
def jira_id_examples:
 unique|sort as $ids|($ids[:3]|join(", "))+(if ($ids|length)>3 then " 외 \((($ids|length)-3))건" else "" end);
def jira_rules($ctx):
 reduce $ctx.works[] as $work ({proposals:[],questions:[],unmapped_repos:[],missing_summaries:[],merge_only_works:[]};
 ($work|jira_links_for($ctx)) as $links |
 if ($work.flags|index("create_summary_conflict"))!=null then .missing_summaries+=[{cause:"모델 요약 충돌",work:$work.id}] else . end |
 ([($work.events // [])[]|select(any(.candidates[]?;.ambiguous==true))|.evidence_id]|unique) as $ambiguous |
 .questions += [$ambiguous[]|"보고 문장 귀속 확인 필요: "+.] |
 if ($work.keys|length)>1 then .questions+=["여러 키 — 상태·본문 제안 안 함: "+$work.id] else . end |
 if ($ctx.llm.links|map(select(.work==$work.id))|map(.key)|unique|length)>1 then .questions+=["연결 모호: "+$work.id] else . end |
 .questions += [$ctx.llm.links[]|select(.work==$work.id)|.key as $key|
   select(all($links[];.key!=$key))|"연결 검증 탈락: "+$work.id+" → "+$key] |
 .questions += [$ctx.links.links[]|select(jira_context($ctx.site;$ctx.account_id))|select(.evidence_id as $id|$work.evidence|index($id)!=null)|
   select(($work.keys|length)>0 and (.key as $key|$work.keys|index($key)==null))|"키 연결과 저장 연결이 다름: "+$work.id] |
 .questions += [$ctx.links.links[]?|select(jira_context($ctx.site;$ctx.account_id) and (.evidence_id|test("^(pr|git):")))|select(.evidence_id as $id|$work.evidence|index($id)!=null)|.key as $key|
   select(all($links[];.key!=$key))|"저장된 근거 연결 확인 필요: "+$key] |
 .questions += [$work.keys[] as $key|$ctx.issues[$key] as $i|
   if $i==null then (if $ctx.issue_reads[$key].http==404 then "이슈 없음 또는 권한 없음: " else "이슈 읽기 미완료: " end)+$key
   elif $i.key!=$key then "이슈 키 변경됨: "+$key+" → "+$i.key
   elif $i.type.hierarchy_level>=1 then "에픽 키 — 하위 이슈 확인 필요: "+$key else empty end] |
 reduce $links[] as $link (.;
  $ctx.issues[$link.key] as $issue |
  (if $link.basis=="candidate" then ["proposal:link:"+$issue.key+":"+$work.id] else [] end) as $depends |
  if $link.basis=="candidate" then
   .proposals += [jira_proposal("link";$work;$issue;{key:$issue.key,work_id:$work.id,evidence:$work.evidence,origin:$link.origin,weak:$link.weak,overlap:$link.overlap,reason:($link.reason // "저장 근거 겹침")};[$issue.key]+($work.evidence|sort);[])|
   .warnings=(if $link.weak then ["흔한 단어만 일치"] else [] end)]
  else . end |
 (($work.events // [])|jira_events_for_key([$issue.key,$issue.requested_key,$link.key]|map(select(.!=null))|unique;($ctx.config.key_like_ignore // []))) as $events | jira_recorded($ctx;$issue.key;$events;null) as $recorded |
  [$events[]|select(.id as $id|$recorded|index($id)==null)] as $fresh |
  if ($fresh|length)>0 and $issue.reads.comments=="ok" then
   ($fresh|jira_comment_text) as $text |
   .proposals += [jira_proposal("comment";$work;$issue;{events:$fresh,text:$text,adf:($text|jira_text_adf)};[$issue.key]+($fresh|map(.id)|sort);$depends)|.events=($fresh|map(.id))]
  else . end |
  if $work.active and ($links|length)==1 and ($work.keys|length)<2 and $issue.assignee_is_me and $issue.status.category!="done" then
   ($ctx.config.projects[$issue.project].statuses) as $statuses |
   if ($statuses.start_from|index($issue.status.id)!=null) and $issue.reads.changelog=="ok" and $issue.reads.transitions=="ok" then
    jira_transition($ctx;$issue) as $transition|
    if $transition==null then .questions+=["전환 불가 또는 Jira에서 직접 전환 필요(필수 입력): "+$issue.key]
    else .proposals += [jira_proposal("transition";$work;$issue;{from:{id:$issue.status.id,name:$issue.status.name},to:{id:$statuses.in_progress,name:($transition.to.name // $statuses.in_progress)},transition_id:$transition.id};[$issue.key,$issue.status.id,$statuses.in_progress,$issue.status.entered_at];$depends)] end
   else . end |
   if $issue.description.state=="undetermined" then .questions+=["본문 판정 보류: "+$issue.key]
   elif ($issue.description.state|IN("empty","template_only")) and $ctx.llm_valid and (jira_fill_blocked($ctx;$issue;null)|not) then
    jira_template($issue.type.name) as $template |
    if $template!=null then
     (if $issue.description.state=="template_only" then $template|.headers=$issue.description.headers else $template end) as $template |
     .questions+=jira_section_questions($ctx;$work;$issue.key;$template) |
     jira_sections($ctx;$work;$issue.key;$template) as $sections|
     if any($sections[];(.lines|length)>0) then
      .proposals += [jira_proposal("fill_description";$work;$issue;{template:$template.name,state_before:$issue.description.state,sections:$sections,adf:($sections|jira_sections_adf($template)),adf_canon_hash:null};[$issue.key,$issue.description.canon_hash,$template.name];$depends)|
       .warnings=([if $issue.description_history.complete!=true then "기록 확인 불가" elif $issue.description_history.prior_content then "이전 본문이 있었음" else empty end,
         if any($sections[];.header==$template.conditions_header and (.lines|length)>0) then "제안된 완료 조건 — 확인 후 승인" else empty end])]
     else . end else . end else . end
  else . end) |
 if ($links|length)==0 and $ctx.llm_valid and $work.active and all($ctx.llm.links[];.work!=$work.id) and (jira_create_blocked($ctx;$work;null)|not) then
  [$ctx.evidence[]|select(.id as $id|$work.evidence|index($id)!=null)] as $proof |
  [$proof[].text|jira_key_tokens[]|select((split("-")[0]) as $prefix|$ctx.config.key_like_ignore|index($prefix)==null)] as $tokens |
  ([$work.repos[]|$ctx.config.repos[.].project]|unique) as $projects |
  [$ctx.llm.create[]?|select(.work==$work.id)] as $creates |
  if ($proof|jira_merge_only) then .merge_only_works+=[$work.id]
  elif ($tokens|length)>0 or ($work.flags-["create_summary_conflict"]|length)>0 or any($proof[];.kind=="git" and (.text|test("\\(#[0-9]+\\)$"))) then .questions+=["기존 키·PR 소속 확인 필요: "+$work.id]
  elif ($projects|length)!=1 or $projects[0]==null then
   [$work.repos[]|select($ctx.config.repos[.].project==null)] as $unmapped |
   if ($unmapped|length)>0 then .unmapped_repos+=[$unmapped[]|{repo:.,work:$work.id}] else .questions+=["저장소 프로젝트 매핑 확인 필요: "+$work.id] end
  elif ($creates|length)==0 then
   if ($work.flags|index("create_summary_conflict"))!=null then .
   else .missing_summaries+=[{work:$work.id,cause:(if any($work.evidence[];. as $id|($ctx.model_evidence_ids // [$ctx.evidence[].id])|index($id)!=null) then "모델이 요약 제안 안 함" else "모델 입력 상한 제외" end)}] end
  elif ($creates|map(.summary)|unique|length)!=1 then .questions+=["생성 요약 충돌 확인 필요: "+$work.id]
  else $projects[0] as $project|$ctx.config.repos[$work.repos[0]].prefix as $prefix|jira_create_summary($prefix;$creates[0].summary) as $summary|
   (($ctx.duplicates[$work.id] // {complete:false})|jira_duplicate_visible($ctx;$work)) as $search |
   .questions += [if ($search.possible // []|length)>0 then "URL 부분 일치 후보 확인 — 새 이슈 제안 안 함: "+$work.id+" — "+($search.possible|jira_id_examples) else empty end] |
   if $search.complete!=true and $search.reason!="insufficient_summary_words" then .questions+=["중복 검색 미완료: "+$work.id]
   elif ($search.matches|unique|length)>1 then .questions+=["중복 후보 여러 개: "+$work.id+" — "+($search.matches|unique|join(", "))]
   elif ($search.matches|length)>0 then
    .proposals += [$search.matches[] as $key|$ctx.issues[$key] as $issue|select($issue!=null and $issue.key==$key and $issue.type.hierarchy_level<1)|
     jira_proposal("link";$work;$issue;{key:$key,work_id:$work.id,evidence:$work.evidence,origin:"duplicate",weak:false,overlap:[],reason:"중복 검색 강한 일치"};[$key]+($work.evidence|sort);[])]
   elif ($search.possible // []|length)>0 then .
   elif $search.complete!=true then .questions+=["요약 고유 단어 부족 — 새 이슈 제안 안 함: "+$work.id+" — 요약을 구체화하고 다시 propose"]
   elif $ctx.create_meta[$project].ok!=true then .questions+=["생성 유형·필수 필드 확인 필요: "+$project]
   elif ($summary|learn_string_ok(false) and length<=255) and ($summary|claim_classes|claims_supported(.;($proof|jira_claim_proof))) then
    jira_template($ctx.create_meta[$project].name) as $template |
    if $template==null then .questions+=["생성 양식 확인 필요: "+$project]
    else jira_sections($ctx;$work;$work.id;$template) as $sections |
     .questions+=jira_section_questions($ctx;$work;$work.id;$template) |
     if any($sections[];(.lines|length)>0) then
      .proposals += [jira_proposal("create_issue";$work;null;{project:$project,issuetype_id:$ctx.config.projects[$project].create_type,issuetype_name:$ctx.create_meta[$project].name,prefix:$prefix,summary:$summary,sections:$sections,adf:($sections|jira_sections_adf($template)),duplicate_search:$search,duplicate_input:{summary:$creates[0].summary,repos:$work.repos,urls:([$proof[]|select(.kind=="pr")|.url]|unique|sort)}};[$project]+($work.evidence|sort);[])]
     else .questions+=["생성 본문 근거 확인 필요: "+$work.id] end
    end
   else .questions+=["생성 요약 주장 확인 필요: "+$work.id] end
  end else . end) |
 .questions += [.unmapped_repos|sort_by(.repo)|group_by(.repo)[]|
  "매핑 없는 저장소 — 새 이슈 제안 안 함: "+.[0].repo+" \(length)건 ("+([.[].work]|jira_id_examples)+") — jira.repos."+.[0].repo+".project 설정"] |
 .questions += [.missing_summaries|sort_by(.cause)|group_by(.cause)[]|
  "생성 요약 없음 — "+.[0].cause+": \(length)건 ("+([.[].work]|jira_id_examples)+") — 요약/모델 입력 확인"] |
 .questions += [if (.merge_only_works|length)>0 then "병합·백머지만 있는 작업 — 새 이슈 제안 안 함: "+(.merge_only_works|jira_id_examples) else empty end] |
 del(.unmapped_repos,.missing_summaries,.merge_only_works)|.questions|=unique|.proposals|=jira_group_proposals;
def jira_proposals_finish($ctx;$hashes):
 .proposals|=map(. as $p|.id=("p-"+$hashes[._ref][0:16])|
 .depends_on|=map("p-"+$hashes[.][0:16])|
 del(._ref,._identity,._prefix)) |
 .proposals|=map(. as $p|.warnings += [$ctx.ledger.entries[]?|select(jira_context($ctx.site;$ctx.account_id) and .proposal_id==$p.id and (.state|IN("conflict","blocked","failed","void")))|"이전 결과: "+.state+" — "+(.message // "")]) |
 .proposals|=map(. as $p|select(
 all($ctx.ledger.entries[]?; (jira_context($ctx.site;$ctx.account_id) and .proposal_id==$p.id and (.state|jira_active_state))|not) and
 all($ctx.ledger.dismissed[]?;(jira_context($ctx.site;$ctx.account_id) and .proposal_id==$p.id)|not) and
 all($ctx.ledger.markers[]?;(jira_context($ctx.site;$ctx.account_id) and .kind=="transition" and .proposal_id==$p.id)|not)));
def jira_request($entry;$account):
 . as $p |
 if .kind=="transition" then {method:"POST",path:("/rest/api/3/issue/"+.key+"/transitions"),body:{transition:{id:.payload.transition_id}}}
 elif .kind=="fill_description" then {method:"PUT",path:("/rest/api/3/issue/"+.key),body:{fields:{description:.payload.adf}}}
 elif .kind=="comment" then {method:"POST",path:("/rest/api/3/issue/"+.key+"/comment"),body:{body:.payload.adf,properties:[{key:"routine-automation",value:{v:1,entry_id:$entry,proposal_id:.id,events:.events}}]}}
 elif .kind=="create_issue" then {method:"POST",path:"/rest/api/3/issue",body:{fields:{project:{key:.payload.project},issuetype:{id:.payload.issuetype_id},summary:.payload.summary,description:.payload.adf,assignee:{accountId:$account}},properties:[{key:"routine-automation",value:{v:1,entry_id:$entry,proposal_id:.id,evidence:.evidence}}]}}
 else null end;
def jira_request_ok($config):
 . as $entry|(.proposal|jira_request($entry.entry_id;$entry.account_id)) as $expected|
 .request==$expected and $config.projects[.project]!=null and
 (.kind=="create_issue" or (.key|test("^"+$entry.project+"-[1-9][0-9]*$"))) and
 (if .kind=="create_issue" then .proposal.payload.project==.project and .proposal.payload.issuetype_id==$config.projects[.project].create_type and
   .proposal.payload.summary==jira_create_summary(.proposal.payload.prefix;.proposal.payload.duplicate_input.summary) and
   .proposal.payload.duplicate_input.urls==([.proposal.evidence[]|select(startswith("pr:"))|ltrimstr("pr:")]|unique|sort) and
   (.proposal.payload.duplicate_input.repos|type=="array" and length>0 and all(.[];. as $repo|$config.repos[$repo].project==$entry.project))
  elif .kind=="transition" then .proposal.payload.to.id==$config.projects[.project].statuses.in_progress and ($config.projects[$entry.project].statuses.start_from|index($entry.proposal.payload.from.id)!=null)
  else true end) and
 (.request.body|type=="object") and (.request.path|startswith("/rest/api/3/")) and
 (.proposal.kind==.kind and .proposal.key==.key and .proposal.issue_id==.issue_id);
def jira_proposals_ok:
 type=="object" and .version==1 and (.site|test("^https://[a-z0-9][a-z0-9-]*\\.atlassian\\.net$")) and (.account_id|learn_string_ok(false)) and
 ([.evidence,.works,.proposals,.questions,.notices,.errors]|all(.[];type=="array")) and (.issues|type=="object") and
 (.proposals|all(.[];(.id|test("^p-[0-9a-f]{16}$")) and (.kind|IN("link","comment","transition","fill_description","create_issue")) and
 (.depends_on|type=="array") and (.evidence|type=="array") and (.payload|type=="object"))) and
 ([.proposals[].id]|length==(unique|length));
def jira_ledger_state($id;$state;$result;$message;$outcome;$http;$curl;$now):
 .entries|=map(if .entry_id==$id then .state=$state|.result=(.result*$result)|.message=$message|
   (if $outcome!="" and (.attempts|length)>0 then .attempts[-1]+={ended_at:$now,http:$http,curl_exit:$curl,outcome:$outcome} else . end)|
   (if $state|IN("verified","verify_failed") then .verified_at=$now else . end)|
   (if $state|IN("verified","verify_failed","conflict","blocked","failed","void","closed_by_user") then .terminated_at=$now else . end)
 else . end) |
 [.entries[]|select(.entry_id==$id)][0] as $entry |
 (if $entry.kind=="fill_description" and $state=="approved" and all($entry.attempts[];.outcome=="not_sent") then
   .markers|=map(select(.entry_id!=$id or .kind!="fill"))
  elif $entry.kind=="fill_description" and $state=="applied" then .markers|=map(if .entry_id==$id and .kind=="fill" then .confirmed=true else . end)
  elif $entry.kind=="create_issue" and ($state|IN("unknown","applied")) then
   ([.markers[]|select(.entry_id==$id and .kind=="create")][0] // {kind:"create",site:$entry.site,account_id:$entry.account_id,entry_id:$id,evidence:$entry.proposal.evidence,issue_id:null,key:null,sent_canon_hash:$entry.proposal.payload.adf_canon_hash,confirmed:false,notified_hash:null,at:$now}) as $marker |
   .markers=([.markers[]|select(.entry_id!=$id or .kind!="create")]+[$marker|
     if $state=="applied" then .issue_id=$entry.result.issue_id|.key=$entry.result.issue_key|.confirmed=true else . end])
  elif $state=="unknown" and ($entry.kind|IN("comment","transition")) then
   .markers=([.markers[]|select(.entry_id!=$id)]+[{kind:$entry.kind,site:$entry.site,account_id:$entry.account_id,entry_id:$id,issue_id:$entry.issue_id,key:$entry.key,at:$now}+
     (if $entry.kind=="comment" then {events:[$entry.proposal.payload.events[]|{id,kind,evidence_id}]} else {proposal_id:$entry.proposal_id} end)])
  else . end);
def jira_dependencies_ok($ctx):
 . as $p|(.depends_on|length)==0 or
 ((.dependency_evidence|type=="array" and length>0) and all(.dependency_evidence[];. as $id|
  any($ctx.links.links[];jira_context($ctx.site;$ctx.account_id) and .key==$p.key and .evidence_id==$id)));
def jira_created_matches($entry;$account;$hash):
 .fields.project.key==$entry.project and .fields.issuetype.id==$entry.proposal.payload.issuetype_id and
 .fields.summary==$entry.proposal.payload.summary and $hash==$entry.proposal.payload.adf_canon_hash and .fields.reporter.accountId==$account;
def jira_editor_sections($template):
 split("\n") as $lines |
 reduce $lines[] as $line ({sections:[],header:null,last:-1,valid:true};
  if $line=="" then .
  elif $line|startswith("## ") then
    ($line[3:]) as $header|($template.headers|index($header)) as $index |
    if $index==null or $index<=.last then .valid=false else .header=$header|.last=$index|.sections+=[{header:$header,lines:[]}] end
  elif ($line|startswith("- ")) and .header!=null and ($line[2:]|learn_string_ok(false) and length<=300) then .sections[-1].lines+=[{text:$line[2:],evidence:[]}]
  else .valid=false end) |
 if .valid then .sections else error("편집 형식 오류: ## 머리글과 - 문장만, 양식 순서 유지") end;
