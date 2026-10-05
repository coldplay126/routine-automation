include "slack";
def learn_unsafe_character:
  test("[\\p{Cc}\u115f\u1160\u3164\uffa0\u2028\u2029]|(?!\u200d)\\p{Cf}");
def learn_string_ok($multiline):
  type=="string" and
  (if $multiline then gsub("[\n\t]";"") else . end |
    (learn_unsafe_character|not)) and
  (contains("<!--") or contains("-->")|not) and
  (length==0 or test("[\\p{L}\\p{N}\\p{P}\\p{S}]"));
def learn_ok:
  type=="object" and keys==["suggestions"] and
  (.suggestions|type=="array" and length<=20 and all(.[];
    type=="object" and keys==["example_after","example_before","kind","text"] and
    (.kind|IN("style","exclude","rename","category")) and
    (.text|learn_string_ok(false) and length>0 and length<=300) and
    all(.example_before,.example_after; learn_string_ok(true) and length<=500)));
def learn_kind: {style:"표현",exclude:"제외 선호",rename:"용어",category:"분류 선호"}[.];
def learn_bullet: "- ["+(.kind|learn_kind)+"] "+.text;
def learn_example: gsub("\n";" ⏎ ")|gsub("\t";" ⇥ ");
def learn_hex:
  . as $n | if $n<16 then "0123456789ABCDEF"[$n:$n+1]
  else ($n/16|floor|learn_hex)+"0123456789ABCDEF"[$n%16:($n%16)+1] end;
def learn_preview:
  explode|map(. as $cp|[$cp]|implode|
    if $cp!=10 and $cp!=9 and learn_unsafe_character then
      ($cp|learn_hex) as $hex|"<U+"+(if ($hex|length)<4 then "0000"[0:4-($hex|length)]+$hex else $hex end)+">"
    else . end)|join("");
def learn_print:
  .suggestions|to_entries[]|"\(.key+1). [\(.value.kind|learn_kind)] \(.value.text)\n   초안: \(.value.example_before|learn_example)\n   보낸 글: \(.value.example_after|learn_example)";
def learn_root($dates):
  main_list_lines | map(.raw)|join("\n") | scrum_blocks_for($dates) |
  if length!=1 then error("대상 날짜 스크럼 글을 하나로 식별하지 못했습니다") else .[0] end;
def learn_open_root($dates):
  thread_lines|map(.raw)|join("\n")|scrum_blocks_for($dates)|
  if length!=1 then error("열린 대상 스레드 루트를 확인하지 못했습니다") else .[0] end;
def learn_root_url: .lines[].body|select(timestamp_link)|capture("\\((?<url>https?://[^)]+)\\)").url;
def learn_thread_identified($url;$dates):
  (try ((learn_open_root($dates)|learn_root_url)==$url) catch false) or thread_identified($url);
# Never navigate away from a thread with pending input, including an unknown editor.
def learn_navigation_safe:
  (ax_lines|any(.[];.body|contains(slack_labels.thread_panel))) as $panel |
  if $panel then (try (thread_editor.value=="") catch false) else true end;
def learn_reaction_button: test("^버튼 (반응( [^ ]+ [0-9]+)?|이모티콘 추가)$");
def learn_author_button:
  test("^버튼 ") and
  (test("^버튼 ([0-9]+개의 댓글|반응( [^ ]+ [0-9]+)?|이모티콘 추가|더보기|메뉴|전송|스레드에서 답장)$")|not);
def learn_body_stop:
  test("^(텍스트 엔트리 영역|체크상자|체크박스|체크 상자|checkbox|separator|구분선|날짜 구분선)([, ]|$)|^버튼 전송$|^(container|group|그룹)( |$)";"i");
# Unknown headers never inherit an author. Only consecutive replies in the same
# parent message container can inherit; any shallower line resets that proof.
# Body boundaries use accessibility roles and indentation, never prose keywords.
def learn_own_comments($url):
  ($ARGS.named.routine.identity.slack_display_name // "") as $name |
  thread_reply_urls($url) as $urls |
  thread_comment_list.lines as $lines |
  [range(0;$lines|length)|select($lines[.].body|reply_timestamp_link)] as $links |
  reduce range(0;$links|length) as $n ({author:"",comments:[]};
    $links[$n] as $i | ($links[$n-1] // -1) as $prev |
    (if $n==0 then 0 else $prev+1 end) as $gap_start |
    ([range($gap_start;$i)|select($lines[.].indent<$lines[$i].indent)]|last) as $parent |
    ($parent // ($gap_start-1)) as $header_start |
    .author as $previous_author |
    [$lines[$header_start+1:$i][]|
      select((.indent==$lines[$i].indent and (.body|startswith("container, Text:") or learn_reaction_button))|not)] as $header |
    (if ($header|length)==1 and $header[0].indent==$lines[$i].indent and ($header[0].body|learn_author_button)
      then $header[0].body|ltrimstr("버튼 ")
      elif ($header|length)==0 and $n>0 and $parent==null and $lines[$prev].indent==$lines[$i].indent
      then $previous_author else "" end) as $author |
    .author=$author |
    ($links[$n+1] // ($lines|length)) as $next |
    ([range($i+1;$next)|select(
      $lines[.].indent<$lines[$i].indent or
      ($lines[.].body|learn_body_stop))][0] // $next) as $end |
    ($lines[$i].body|capture("\\((?<url>https?://[^)]+)\\)").url|split("?")[0]) as $canonical |
    [$lines[$i+1:$end][]|
      select(.indent==$lines[$i].indent and (.body|startswith("container, Text:")))|
      .body|sub("^container, Text:[[:space:]]*";"")|select(length>0 and .!="(편집됨)")] as $text |
    if $name!="" and $author==$name and ($text|length)>0 and
      ($canonical|startswith($url|sub("/p[0-9]+$";"/p"))) and
      ($urls|index($canonical)!=null)
    then .comments+=[{url:$canonical,text:($text|join("\n"))}] else . end) |
  .comments|unique_by(.url);
def learn_comment_button_own($block):
  ($ARGS.named.routine.identity.slack_display_name // "") as $name |
  $block.lines as $lines |
  ([range(0;$lines|length)|select($lines[.].index==$block.reply)][0] // null) as $button |
  if $name=="" or $button==null then false else
    ([$lines[$button+1:]|to_entries[]|select(.value.indent<=$lines[$button].indent)|.key+$button+1][0] // ($lines|length)) as $end |
    any($lines[$button+1:$end][];.body=="버튼 "+$name) end;
def learn_paste_resolved($dates;$start;$end):
  def today_root:
    learn_root_url|capture("/archives/(?<channel>[CG][A-Z0-9]+)/p(?<stamp>[0-9]{10})[0-9]{6}$")|
    .channel==$ARGS.named.routine.slack.channel_id and (.stamp|tonumber)>=$start and (.stamp|tonumber)<$end;
  (try (learn_root($dates) as $root|($root|today_root) and learn_comment_button_own($root)) catch false) or
  (try (learn_open_root($dates) as $root|($root|today_root) and thread_editor.value=="") catch false);
def learn_click_allowed($block;$url;$dates):
  learn_comment_button_own($block) or
  (try (learn_thread_identified($url;$dates) and (learn_own_comments($url)|length>0)) catch false);
# Deduplicate across all learned-date sections, retaining the user's selection order.
def learn_style($day;$suggestions):
  . as $original | split("\n") as $lines |
  ("## 학습된 선호 ("+$day+")") as $heading |
  ($lines|index($heading)) as $start |
  (reduce $lines[] as $line ({learned:false,existing:[]};
    if $line|startswith("## ") then .learned=($line|test("^## 학습된 선호 \\([0-9]{4}-[0-9]{2}-[0-9]{2}\\)$"))
    elif .learned then .existing+=[$line] else . end)|.existing) as $existing |
  (reduce ($suggestions|map(learn_bullet))[] as $line ([];
    if ($existing|index($line))!=null or index($line)!=null then . else .+[$line] end)) as $new |
  if ($new|length)==0 then $original
  elif $start==null then $original+(if $original=="" then "" elif endswith("\n\n") then "" elif endswith("\n") then "\n" else "\n\n" end)+$heading+"\n"+($new|join("\n"))+"\n"
  else ($lines[:$start+1]+$new+$lines[$start+1:]|join("\n")) end;
