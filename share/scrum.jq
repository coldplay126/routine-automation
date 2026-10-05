include "redact";
def norm: gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "");
def active_claim($pattern):
  "("+$pattern+")(?![^[:space:][:punct:]]*[[:space:]]*(대기|후|전|여부|예정|필요|실패))";
def completed_clause($domain):
  active_claim("("+$domain+")[[:space:]]*((이|가|을|를|에|까지)[[:space:]]*)?(?>진행[[:space:]]*완료|처리[[:space:]]*완료|완료(됨|함)?|하였습니다|했어요|마쳤|성공|함|했다|했음|했고|했습니다|됨|된|됐|되었|되어|끝|마침|[✅✔☑]\\x{FE0F}?|\\(완\\)|\\[완\\]|(?:\\(|\\[)?(done|OK|complete(d)?|finished)(?:\\)|\\])?(?=$|[[:space:][:punct:]]))");
def deployed_claim:
  completed_clause("재배포|운영[[:space:]]*배포|배포|(운영|프로덕션|라이브|\\bprod(uction)?\\b)[[:space:]]*(에|까지)?[[:space:]]*(반영|적용)|릴리스|릴리즈|출시|런칭|go-live|라이브[[:space:]]*전환|\\b(deploy|deployment|release|ship|rollout)")+
  "|"+active_claim("\\b(deployed|released|shipped|went[[:space:]]+live|is[[:space:]]+live|rolled[[:space:]]+out)\\b|\\b(deploy|release|ship|rollout)([[:space:]]+(is|was))?[[:space:]]+(done|complete|completed|finished)\\b");
def merged_claim:
  completed_clause("머지|병합|\\bmerge")+"|"+active_claim("\\bmerged\\b|\\bmerge([[:space:]]+(is|was))?[[:space:]]+(done|complete|completed|finished)\\b");
def verified_claim: completed_clause("정상[[:space:]]*확인|검증|확인");
def work_claim:
  completed_clause("반영|적용|해결|수정|구현|개발|작업|정리|마무리")+"|"+active_claim("(^|[[:space:][:punct:]])(완료(됨|함)?|마무리)(?=$|[[:space:][:punct:]])");
def claim_classes:
  . as $text | deployed_claim as $deployed | merged_claim as $merged | verified_claim as $verified |
  [if $text|test($deployed;"i") then "deployed" else empty end,
   if $text|test($merged;"i") then "merged" else empty end,
   if $text|test($verified;"i") then "verified" else empty end,
   if ($text|gsub("("+$deployed+"|"+$merged+"|"+$verified+")";" ";"i") |
       test(work_claim;"i"))
   then "work" else empty end];
def complete_words($section): $section=="yesterday" and (claim_classes|length)>0;
def default_format: {bullets:["•","◦","▪","▪"],layout:"tree",max_items_per_section:null};
def draft_settings:
  ($ARGS.named.routine.draft // {project:"",markers:"none",categories:["현황 파악","배포","개발","인프라","업무 자동화","기타"],headers:{yesterday:"어제 작업한 내용",today:"오늘의 작업 계획"}}) |
  .format=(default_format * (.format // {}));
def category_order: draft_settings.categories;
def category_claim($section): norm as $category | (category_order|index($category))==null and ($category|complete_words($section));
def strings: type=="array" and all(.[]; type=="string");
def draft_ok:
  type=="object" and (.items|type=="array" and all(.[];
    (.section|IN("yesterday","today")) and (.path|strings and length==2 and all(.[]; norm|length>0)) and
    (.topic|type=="string" and (norm|length)>0) and (.level|IN("request","work","merged","deployed","verified")) and
    (.evidence|strings) and ((.held_ref // null)==null or (.held_ref|type=="number" and .==floor and .>=0))));
def delivery_counts:
  {delivered:([.items[]?|select(.omitted!=true and (.section!="today" or .held!=true))]|length),
   omitted:([.items[]?|select(.omitted==true)]|length)};
def notes_data:
  split("\n") | reduce .[] as $line ({section:"",held:[],today:[]};
    if $line|test("^#+[[:space:]]") then .section=($line|sub("^#+[[:space:]]*";""))
    elif $line|test("^[[:space:]]*[-*][[:space:]]+") then
      ($line|sub("^[[:space:]]*[-*][[:space:]]+(\\[[ xX]\\][[:space:]]*)?";"")|redact|norm) as $text |
      if ($text|length)==0 then .
      elif .section|test("보류") then .held += [$text]
      elif .section|test("오늘|추가") then .today += [$text] else . end
    else . end) | del(.section);
def session_evidence_id: .evidence_id // ((if .source=="claude" then "claude-session:" else "session:" end)+.id);
# PR status is current state; only timestamped personal activity proves the window.
def pr_activity($login;$since;$until):
  if (type!="object" or (.state|type)!="string" or (.createdAt|type)!="string" or
      (.commits|type)!="array" or (.reviews|type)!="array" or (.comments|type)!="array")
  then error("Invalid PR activity response") else . end |
  ((.commits|length)>=100) as $saturated |
  ($login|ascii_downcase) as $me |
  [((.author.login // ""|ascii_downcase)==$me) as $own |
   (if $own then {kind:"created",at:.createdAt} else empty end),
   (if .mergedAt!=null then
      {kind:(if (.mergedBy.login // ""|ascii_downcase)==$me then "merged" else "merged_by_other" end),at:.mergedAt}
    else empty end),
   (.commits[] | select(any(.authors[]?; (.login // ""|ascii_downcase)==$me)) | {kind:"commit",at:.authoredDate}),
   (.reviews[] | select((.author.login // ""|ascii_downcase)==$me) | {kind:"review",at:.submittedAt}),
   (.comments[] | select((.author.login // ""|ascii_downcase)==$me) | {kind:"comment",at:.createdAt})] |
  map(select(.at!=null) | (.at|sub("\\.[0-9]+Z$";"Z")|fromdateiso8601) as $at |
      select($at>=($since|fromdateiso8601) and $at<($until|fromdateiso8601))) |
  unique | sort_by(.at,.kind) |
  if all(.[];.kind=="merged_by_other") and $saturated then error("Saturated PR commits: the first 100 cannot prove absence") else . end;
def evidence_catalog($notes):
  [(.git[]? | {id:("git:"+.sha),kind:"git",repo:.repo,merge:(.merge==true or (.subject|test("^Merge (pull request|branch|remote-tracking branch)"))),text:.subject}),
   (.prs[]? | (.current.state // .state|ascii_upcase) as $state |
    {id:("pr:"+.url),kind:"pr",state:$state,in_window:(if has("in_window") then .in_window else "unknown" end),
     repo:(.repository|if type=="object" then .nameWithOwner // .name else . end),
     merge:($state=="MERGED" and any(.activity[]?;.kind|IN("merged","merged_by_other"))),text:.title}),
   (.sessions[]? | select(.id!=null) | {id:session_evidence_id,kind:"session",text:(.latest_report // "")}),
   (.sessions[]? | select(.id!=null) | . as $session | (.reports // []|to_entries[]) |
    {id:(.value.evidence_id // (($session|session_evidence_id)+"#"+(.key|tostring))),kind:"session",text:.value.text}),
   (.slack[]? | {id:("slack:"+.url),kind:"slack",text:.text}),
   (.jira[]? | {id:("jira:"+.key),kind:"jira",text:.title}),
   ($notes.today|to_entries[]|{id:("note:"+(.key|tostring)),kind:"note",text:.value})];
def report_proves($level):
  [split("\n")[] | splits("[.;!。]") | gsub("\\*\\*|__";"") | norm] | any(.[];
    (test("예정|계획|남은|다음|필요|미확인|실패|불가|안 됨|않|요청|검토|pending|failed|unhealthy|[?？]|나요|여부|부탁|주세요|알려|되면|하면|다면|으면|라면|이면|어야|여야|해야|예상|목표|대기|아님|모르|정상인지|정상인[[:space:]]*(경우|때)|정상일[[:space:]]*때|(완료|배포|반영|확인|정상)[[:space:]]*면|(완료|배포|반영|확인|발송|처리|종료|적용|Synced|Healthy)[[:space:]]*(전|후)([[:space:][:punct:]]|입니다|에는|의|에|$)";"i")|not) and
    (if $level=="deployed" then
       (test("운영.*(배포|반영)") and test("(완료했습니다|완료됨|배포했습니다|반영했습니다|확인했습니다)[[:space:]]*$")) or
       test("Argo.*Synced.*Healthy[[:space:]]*확인(했습니다)?[[:space:]]*$";"i")
     else
       (test("운영.*(조회|확인)") and test("(완료했습니다|완료됨|확인했습니다)[[:space:]]*$")) or
       (test("production.*(healthy|success|200)";"i") and test("(verified|confirmed)[[:space:]]*$";"i")) or
       test("(이상[[:space:]]*없이[[:space:]]*진행되었습니다|모두[[:space:]]*정상|정상입니다|정상[[:space:]]*확인)[[:space:]]*$") or
       (test("^(#+[[:space:]]+.*)?✅[[:space:]]*.+") and
        test("(발송|처리|종료|반영|적용|성공|통과|완료|확인)(했습니다|되었습니다|됐습니다|됨|완료)?[[:space:]]*$"))
     end));
def supported_level($level;$proof):
  if $level=="request" then any($proof[];.kind=="session" or .kind=="note")
  elif $level=="work" then any($proof[];.kind=="git" or .kind=="pr")
  elif $level=="merged" then any($proof[];.merge==true)
  else any($proof[];(.kind=="session" or .kind=="slack") and (.text|report_proves($level))) end;
def claims_supported($claims;$proof): all($claims[];supported_level(.;$proof));
def held_claims_allow($text;$memo):
  ($text|norm) as $text | ($memo|norm) as $memo |
  ($text|claim_classes) as $claims | ($memo|claim_classes) as $memo_claims |
  if ($claims|length)==0 then true
  # Keep codepoint coordinates: string index can count bytes, regex offsets do not.
  else ($memo|explode|index($text|explode)) as $start |
    $start!=null and all($claims[];. as $claim |
      ($memo_claims|index($claim))!=null and
      ((if $claim=="deployed" then deployed_claim elif $claim=="merged" then merged_claim
        elif $claim=="verified" then verified_claim else work_claim end) as $pattern |
       [$memo|match($pattern;"ig")|.offset+.length] as $ends |
       all($text|match($pattern;"ig"); (.offset+.length+$start) as $end | ($ends|index($end))!=null)))
  end;
def low_level($proof): if any($proof[];.kind=="git" or .kind=="pr") then "work" else "request" end;
def topic_connected($topic;$proof):
  ($topic|norm|split(" ")|map(select(length>1))) as $words |
  any($proof[]; .text as $text | any($words[]; . as $word | $text|contains($word)));
def held_connected($item;$term):
  ($item.topic|norm) as $topic | ($term|norm) as $term |
  $term!="" and (($topic|contains($term)) or ($term|contains($topic)) or
    (("("+deployed_claim+"|"+merged_claim+"|"+verified_claim+"|"+work_claim+")") as $claims |
     ([$term|gsub($claims;" ";"i")|norm|split(" ")[]|select(length>1)]|unique) as $words |
     ([$topic|gsub($claims;" ";"i")|norm|split(" ")[]|select(. as $word|$words|index($word)!=null)]|unique|length)>=2));
def held_index($item;$notes):
  if $item.held_ref!=null then
    if $item.held_ref>=0 and $item.held_ref<($notes.held|length) and held_connected($item;$notes.held[$item.held_ref]) then $item.held_ref else null end
  else ($item.topic|norm) as $topic |
    [$notes.held|to_entries[]|(.value|norm) as $term|select($term!="" and ($topic|contains($term)))|.key][0] // null end;
def level_marker($section;$level):
  if $section=="today" then "" else {request:"검토",work:"",merged:"병합",deployed:"운영 배포",verified:"확인"}[$level] end;
def build_trees_settings($settings):
  .items as $items |
  def uncertain_label($uncertain): if $uncertain and $settings.markers!="none" then " (확인 필요)" else "" end;
  def topics:
    group_by(.value.path[1]) | map(. as $group |
      [$group[]|select((.value.topic|norm)==(.value.path[1]|norm))|{item:.key}] +
      ([$group[]|select((.value.topic|norm)!=(.value.path[1]|norm))|{item:.key}] as $children |
       if ($children|length)>0 then [{label:($group[0].value.path[1]+uncertain_label(any($group[];.value.path_uncertain[1]==true))),children:$children}] else [] end)) | add // [];
  def tree($section):
    [$items|to_entries[]|select(.value.section==$section and .value.omitted!=true and ($section!="today" or .value.held!=true))] |
    if length==0 then [] else
      (if $settings.format.layout=="flat" then topics else
       group_by(.value.path[0]) |
       sort_by(.[0].value.path[0] as $category | [($settings.categories|index($category)//6),$category]) |
       map({label:(.[0].value.path[0]+uncertain_label(any(.[];.value.path_uncertain[0]==true))),children:topics}) end) as $nodes |
      if $settings.project=="" then $nodes else [{label:$settings.project,children:$nodes}] end end;
  .yesterday=tree("yesterday") | .today=tree("today");
def apply_format_settings($settings):
  ($settings | .format=(default_format * (.format // {}))) as $settings |
  .settings=$settings | .questions=((.questions // []) - (.format_questions // [])) |
  .items |= map(del(.omitted)) |
  reduce ["yesterday","today"][] as $section (.;
    [.items|to_entries[]|select(.value.section==$section and ($section!="today" or .value.held!=true))] as $eligible |
    if $settings.format.max_items_per_section==null then .
    else reduce $eligible[$settings.format.max_items_per_section:][] as $entry (.; .items[$entry.key].omitted=true) end) |
  .format_questions=[.items[]|select(.omitted==true)|.topic+": 생략됨 — "+(if .section=="yesterday" then "어제" else "오늘" end)+" 항목 수 상한, 검토 화면에서 확인하세요."] |
  .questions=(.questions+.format_questions|unique) | build_trees_settings($settings);
def validate_draft($source;$notes):
  ($source|evidence_catalog($notes)) as $catalog |
  {items:.items,settings:draft_settings,
   evidence_catalog:($catalog|map({id:(.id|redact),kind,text:(.text|redact|.[0:300])})),
   questions:[$source.prs[]?|select(has("in_window")|not)|"이전 버전 PR 근거 — 다시 routine collect 필요: "+.url]} |
  reduce range(0;.items|length) as $i (. ;
    .items[$i] as $item |
    [$item.evidence[] as $id|$catalog[]|select(.id==$id)] as $all_proof |
    [$all_proof[]|select(.kind!="pr" or (if $item.section=="yesterday" then .in_window==true else .state=="OPEN" end))] as $proof |
    [$all_proof[]|select($item.section=="yesterday" and .kind=="pr" and .in_window!=true)|.id] as $outside |
    [$item.evidence[]|. as $id|select(any($catalog[];.id==$id)|not)] as $missing |
    held_index($item;$notes) as $held |
    ($item.section=="yesterday") as $check_claim |
    supported_level($item.level;$proof) as $supported |
    any($proof[];.repo|select(type=="string")|.==$item.path[1] or (split("/")|last)==$item.path[1]) as $repo_path |
    ($item.topic|claim_classes) as $topic_claims |
    (if $held!=null then ($notes.held[$held]|norm) else "" end) as $held_memo |
    ($held!=null and held_claims_allow($item.topic;$held_memo)) as $held_exempt |
    any($proof[];(.kind|IN("git","pr")) and .text==$item.topic) as $original_topic |
    (if $original_topic or $held_exempt then [] else $topic_claims end) as $topic_required |
    ($item.path[1]|claim_classes) as $group_claims |
    (if $repo_path or ($original_topic and $item.path[1]==$item.topic) or ($held!=null and held_claims_allow($item.path[1];$held_memo)) then [] else $group_claims end) as $group_required |
    (if ($item.path[0]|category_claim($item.section)) then ($item.path[0]|claim_classes) else [] end) as $category_claims |
    (if $held!=null and held_claims_allow($item.path[0];$held_memo) then [] else $category_claims end) as $category_required |
    ($topic_required+$group_required+$category_required|unique) as $required |
    ($check_claim and (claims_supported($required;$proof)|not)) as $overclaim |
    ([$missing[]|"존재하지 않는 근거: "+.] + [$outside[]|"기간 내 내 활동이 확인되지 않은 PR: "+.] +
     (if $supported or ($check_claim|not) or $held_exempt then [] else ["수준 "+$item.level+"의 최소 근거 또는 완료 결과가 없습니다"] end) +
     (if $overclaim then ["주제에 완료·배포 표현이 있습니다"] else [] end)) as $reasons |
    .items[$i].reasons=$reasons |
    .items[$i].path[0]|=norm |
    .items[$i].path_uncertain=[($check_claim and (claims_supported($category_required;$proof)|not)),($check_claim and (claims_supported($group_required;$proof)|not))] |
    if $supported|not then .items[$i].level=low_level($proof) else . end |
    .questions += [$reasons[]|$item.topic+": "+.] |
    # An item left with no valid proof (e.g. it cited only out-of-window PRs) is not deliverable:
    # keep it in the question list only. A user-declared hold in notes.md still shows as (보류).
    if ($proof|length)==0 and $held==null then .items[$i].drop=true | .items[$i].reasons += ["유효한 근거가 없어 초안에서 제외"] | .questions += [$item.topic+": 유효한 근거가 없어 초안에서 제외"] else . end |
    if $overclaim then
      .items[$i].drop=true | .items[$i].reasons += ["완료 표현이 근거보다 강해 초안에서 제외"] | .questions += ["완료 표현이 근거보다 강해 초안에서 제외 — 원문: "+$item.topic]
    else . end |
    ($check_claim and ($held_exempt|not) and ($item.level|IN("deployed","verified")) and (topic_connected($item.topic;$proof)|not)) as $unconnected |
    if $unconnected then .items[$i].reasons += ["증거 주제 확인"] | .questions += [$item.topic+": 증거 주제 확인"] else . end |
    .items[$i].held=($held!=null and ($item.section!="today" or ($item.topic|norm)==$held_memo)) |
    if $held==null and ($item.held_ref!=null or any($notes.held[]; . as $term | ($term|split(" ")|any(.[]; . as $word|($word|length)>1 and ($item.topic|norm|contains($word)))))) then .items[$i].reasons += ["보류 항목 매칭 확인"] | .questions += [$item.topic+": 보류 항목 매칭 확인"] else . end |
    .items[$i].text=($item.topic+([(if draft_settings.markers=="all" then level_marker($item.section;.items[$i].level) else "" end),
      (if draft_settings.markers!="none" and (($reasons|length)>0 or $unconnected) then "확인 필요" else "" end),
      (if $held!=null and $item.section=="yesterday" then "보류" else "" end)] |
      map(select(length>0)) | if length>0 then " ("+join(", ")+")" else "" end))) |
  # Review-only candidates remain excluded from every delivery renderer.
  .excluded_items=[.items[]|select(.drop==true)|del(.drop)] |
  .items |= map(select(.drop!=true) | select(.section!="today" or ((.evidence|length)>0 and all(.evidence[]; . as $id|any($catalog[];.id==$id and .kind=="pr" and .state!="OPEN"))|not))) |
  apply_format_settings(draft_settings);
def summary_draft($notes):
  {items:[(.git[]?|{section:"yesterday",path:["개발",.repo],topic:.subject,
      level:(if .merge==true or (.subject|test("^Merge (pull request|branch|remote-tracking branch)")) then "merged" else "work" end),evidence:["git:"+.sha]}),
    (.prs[]?|select(.in_window==true)|{section:"yesterday",path:["개발",.title],topic:.title,
      level:(if (.current.state // .state|ascii_upcase)=="MERGED" and any(.activity[]?;.kind|IN("merged","merged_by_other")) then "merged" else "work" end),evidence:["pr:"+.url]}),
    (.sessions[]?|{section:"yesterday",path:["현황 파악",.title],topic:.title,level:"request",evidence:[session_evidence_id]}),
    (.prs[]?|select((.current.state // .state|ascii_upcase)=="OPEN")|{section:"today",path:["개발",.title],topic:.title,level:"work",evidence:["pr:"+.url]}),
    (.sessions[]?|. as $session|(.reports // []|to_entries[])|. as $report|(.value.text|split("\n")[])|select(test("남은[[:space:]]*일|다음[[:space:]]*(단계|:)"))|{section:"today",path:["개발",$session.title],topic:.,level:"request",evidence:[($session|session_evidence_id)+"#"+($report.key|tostring)]}),
    ($notes.today|to_entries[]|{section:"today",path:["업무 자동화",.value],topic:.value,level:"request",evidence:["note:"+(.key|tostring)]})]};
def html_escape: gsub("&";"&amp;")|gsub("<";"&lt;")|gsub(">";"&gt;");
def format_bullet($settings;$depth):
  ($settings.format.bullets // default_format.bullets) as $bullets |
  $bullets[([$depth,($bullets|length)-1]|min)];
def render_html_settings($settings):
  .items as $items |
  (($settings.format.bullets // default_format.bullets)!=default_format.bullets) as $custom |
  def nodes:
    "<ul>"+(map("<li>"+(if has("item") then $items[.item].text|html_escape else (.label|html_escape)+(.children|nodes) end)+"</li>")|join(""))+"</ul>";
  def lines($depth):
    .[] | (("&nbsp;"*($depth*2))+(format_bullet($settings;$depth)|html_escape)+" "+
      (if has("item") then $items[.item].text|html_escape else .label|html_escape end)),
    (if has("children") then .children|lines($depth+1) else empty end);
  def section:
    if $custom then "<div data-routine-bullets=\"custom\">"+([lines(0)]|join("<br>"))+"</div>" else nodes end;
  "<b>"+($settings.headers.yesterday|html_escape)+"</b>"+(.yesterday|section)+"\n<b>"+($settings.headers.today|html_escape)+"</b>"+(.today|section);
def render_html: render_html_settings(.settings // (draft_settings|.format=default_format));
def render_text_settings($settings):
  .items as $items |
  def nodes($depth): .[]|(("  "*$depth)+format_bullet($settings;$depth)+" "+(if has("item") then $items[.item].text else .label end)),(if has("children") then .children|nodes($depth+1) else empty end);
  $settings.headers.yesterday,(.yesterday|nodes(0)),"",$settings.headers.today,(.today|nodes(0));
def render_text: render_text_settings(.settings // (draft_settings|.format=default_format));
