include "scrum";
include "redact";
def review_escape: @html;
def review_question($topic):
  startswith($topic+": ") or .==("완료 표현이 근거보다 강해 초안에서 제외 — 원문: "+$topic);
def review_data($source;$day):
  walk(if type=="string" then redact else . end) as $draft |
  (($draft.evidence_catalog // ($source|evidence_catalog({today:[],held:[]}))) |
    map(.id|=redact | .text|=(redact|.[0:300]))) as $catalog |
  ($draft.items + ($draft.excluded_items // [])) as $known |
  ($draft.questions // []) as $questions |
  [if ($draft|has("excluded_items")|not) then $questions[] else empty end |
    . as $q | select(any($known[]; . as $item | $q|review_question($item.topic))|not) |
    {section:"today",path:["기타","확인 필요"],topic:.,text:.,level:"request",evidence:[],question_only:true}] as $legacy |
  {day:$day,settings:($draft.settings // (draft_settings|.format=default_format)),
   channel:("slack://channel?team="+($ARGS.named.routine.slack.team_id // ""|@uri)+"&id="+($ARGS.named.routine.slack.channel_id // ""|@uri)),
   yesterday:$draft.yesterday,today:$draft.today,
   notices:(if $draft|has("excluded_items") then
     [$questions[]|. as $q|select(any($known[];. as $item|$q|review_question($item.topic))|not)] else [] end),
   items:(([$draft.items[] | .+{selected:(.omitted!=true and (.section!="today" or .held!=true)),question_only:(.omitted==true)}] +
     [($draft.excluded_items // [])[] | .+{selected:false,question_only:true}] + [$legacy[] | .+{selected:false}]) |
     map(. as $item | (.section=="today" and .held==true) as $disabled |
       . + {text:(.text // .topic),disabled:$disabled,
       direct:((.topic|norm)==(.path[1]|norm)),
       reasons:((.reasons // [$questions[]|select(review_question($item.topic))]) +
         (if .omitted then ["생략됨 — 항목 수 상한입니다. 다른 항목을 해제하거나 상한 설정을 바꿔 확인하세요."] else [] end) +
         (if .question_only and .omitted!=true then ["초안에서 제외된 항목입니다. 근거와 문구를 확인한 뒤 선택하세요."] else [] end) +
         (if $disabled then ["보류 중인 오늘 계획은 초안에 포함하지 않습니다."] else [] end)|unique),
       proof:[(.evidence // [])[] | . as $id | {id:$id,text:([$catalog[]|select(.id==$id)|.text][0] // "초안에 저장된 발췌가 없고 수집 파일에서도 찾지 못했습니다.")}]}))};
def review_cards:
  def card:
    .key as $id | .value as $item |
    "<article class=\"card\" data-item=\"\($id)\"><div class=\"item-heading\"><label><input type=\"checkbox\" data-select=\"\($id)\""+(if $item.selected then " checked" else "" end)+(if $item.disabled then " disabled aria-describedby=\"reasons-\($id)\"" else "" end)+" aria-controls=\"preview\"> 포함</label><span class=\"badge\">"+
    ({request:"요청·검토",work:"작업",merged:"병합",deployed:"배포",verified:"확인"}[$item.level]|review_escape)+"</span>"+
    (if ($item.reasons|length)>0 then "<span class=\"badge attention\">확인 필요</span>" else "" end)+
    (if $item.held then "<span class=\"badge held\">보류</span>" else "" end)+
    (if $item.omitted then "<span class=\"badge attention\">생략됨</span>" else "" end)+"</div><p class=\"path\">"+
    ((if $item.section=="yesterday" then "어제" else "오늘" end)+" / "+($item.path|join(" / "))|review_escape)+"</p>"+
    "<div id=\"edit-\($id)\" class=\"editable\" contenteditable=\"true\" role=\"textbox\" aria-multiline=\"true\" aria-label=\"항목 \($id+1) 문구 편집\" data-edit=\"\($id)\">"+($item.text|review_escape)+"</div>"+
    (if ($item.reasons|length)>0 then "<ul id=\"reasons-\($id)\" class=\"reasons\">"+($item.reasons|map("<li>"+(.|review_escape)+"</li>")|join(""))+"</ul>" else "" end)+
    "<details><summary>근거 보기</summary><ul>"+($item.proof|map("<li><code>"+(.id|review_escape)+"</code><p class=\"excerpt\">"+(.text|review_escape)+"</p></li>")|join(""))+
    (if ($item.proof|length)==0 then "<li>연결된 근거가 없습니다.</li>" else "" end)+"</ul></details></article>";
  .notices as $notices | .items|to_entries as $entries |
  "<h2>초안 항목</h2>"+([$entries[]|select(.value.question_only!=true)|card]|join(""))+
  "<h2>확인 필요</h2><p>제외된 항목은 기본 해제되어 있습니다. 확인 후 체크하면 미리보기에 포함됩니다.</p>"+
  ([$entries[]|select(.value.question_only==true)|card]|join(""))+
  (if ($notices|length)>0 then "<details><summary>수집·초안 안내</summary><ul>"+($notices|map("<li>"+(.|review_escape)+"</li>")|join(""))+"</ul></details>" else "" end);
def review_page($source;$day;$template):
  . as $draft | review_data($source;$day) as $data |
  ($draft|walk(if type=="string" then redact else . end)|render_html_settings($data.settings)) as $preview |
  ($data|review_cards) as $cards |
  ($data|tojson|gsub("&";"\\u0026")|gsub("<";"\\u003c")|gsub(">";"\\u003e")) as $json |
  $template | split("@@REVIEW_") | map(
    if startswith("DAY@@") then ($day|review_escape)+.[5:]
    elif startswith("CHANNEL@@") then ($data.channel|review_escape)+.[9:]
    elif startswith("PREVIEW@@") then $preview+.[9:]
    elif startswith("ITEMS@@") then $cards+.[7:]
    elif startswith("DATA@@") then $json+.[6:]
    else . end) | join("");
