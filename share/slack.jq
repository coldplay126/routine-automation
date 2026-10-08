# Korean Slack accessibility vocabulary lives here, not in user configuration.
def slack_labels: {search:"버튼 검색",combo:"콤보 상자",editor:"텍스트 엔트리 영역",list:"내용 목록 ",thread_panel:" 채널의 스레드",thread_list:"의 스레드",open_channel:"채널에서 열기",comments:"개의 댓글",user_menu:"팝업 버튼 사용자:",today:"오늘, ",reply:"버튼 스레드에서 답장",broadcast:"(으)로도 전송",toolbar:"도구 막대",search_panel:"검색 결과",search_dialog:"대화상자, Title: 검색"};
def slack_settings: $ARGS.named.routine.slack // {channel_name:"",post_title:"",post_time_prefix:"오전 8:0"};
def today_timestamp: contains("link ["+slack_labels.today+slack_settings.post_time_prefix);
# The action that opens a post's thread, available in the message toolbar or after selection.
def reply_action: test("^버튼 (스레드에서 답장|스레드의 댓글|스레드에 댓글 달기)$");
def tree_text: .result.snapshot.treeText // .snapshot.treeText // .treeText // error("Missing treeText");
# Orca prints element indexes as "[12] role" (older) or "12 role" (current).
def ax_lines:
  split("\n")|map(. as $raw|(try capture("^(?<space>[[:space:]]*)(\\[(?<index>[0-9]+)\\]|(?<bare>[0-9]+)[[:space:]])[[:space:]]*(?<body>.*)$") catch null) as $m|
    {raw:$raw,index:($m.index // $m.bare // null|if .==null then null else tonumber end),indent:($m.space // ""|length),body:($m.body // $raw)});
# The channel's main message list ("내용 목록 <name> (채널)", not "<name>의 스레드" or a search pane).
# Every init check and the channel-name proposal use only these lines.
def main_list_lines:
  ax_lines as $lines |
  [range(0;$lines|length)|select($lines[.].body|test("^내용 목록 .+ \\((?:비공개[[:space:]]+)?채널(?:[,)]|$)") and (test("의 스레드 \\(")|not))] as $starts |
  ([$starts[]|select(($lines[.].body|capture("^내용 목록 (?<name>.+?)[[:space:]]+\\((?:비공개[[:space:]]+)?채널").name|sub("^\\*[[:space:]]*";"")|ltrimstr("#"))==slack_settings.channel_name)]) as $named |
  (if ($named|length)>0 then $named else $starts end) as $starts |
  if ($starts|length)!=1 then [] else $starts[0] as $s |
    ([$lines[$s+1:]|to_entries[]|select(.value.indent<=$lines[$s].indent)|.key+$s+1][0] // ($lines|length)) as $end |
    $lines[$s:$end] end;
# Names are proposed only after the linked message has actually appeared in the main list.
def linked_post_visible($post):
  $post!="" and (tree_text|main_list_lines|any(.[];.body|test("^link \\[.*\\]\\(https?://[^)]+/p"+$post+"(?:[?)]|$)")));
# The linked post may have scrolled away (or the saved link has no timestamp). The channel itself is
# confirmed when every message link inside the main list points into the channel ID.
def channel_visible($channel):
  $channel!="" and ([tree_text|main_list_lines|.[1:][]|.body|select(test("^link \\[.*\\]\\(https?://[^)]+/archives/"))|
    capture("/archives/(?<id>[CG][A-Z0-9]+)/").id] as $ids | ($ids|length)>0 and all($ids[]; .==$channel));
def init_proposals($post):
  tree_text | ax_lines as $lines |
  def unique_value: map(select(length>0)) | unique | if length==1 then .[0] else "" end;
  { "slack.channel_name":
      ([(main_list_lines|.[0:1][]|.body|try capture("^내용 목록 (?<name>.+?)[[:space:]]+\\(채널(?:[,)]|$)").name catch ""),
        ($lines[].body|try capture("^표준 윈도우(?:, Title:)?[[:space:]]+(?<name>.+?)[[:space:]]*\\(채널\\)[[:space:]]*- ").name catch "") |
        sub("^\\*[[:space:]]+";"") | sub("[[:space:]]+$";"") | ltrimstr("#")] | unique_value),
    "identity.slack_display_name":
      ([$lines[].body | try capture("^팝업 버튼 사용자: (?<name>.+)$").name catch ""] | unique_value),
    "slack.post_title":
      (main_list_lines as $main |
       [range(0;$main|length) as $i |
        select($post!="" and ($main[$i].body|test("^link \\[.*\\]\\(https?://[^)]+/p"+$post+"(?:[?)]|$)"))) |
        ([range(0;$i) as $heading |
          select($main[$heading].indent<$main[$i].indent and ($main[$heading].body|startswith("container"))) |
          select(all($main[$heading+1:$i][]; .index==null or .indent>$main[$heading].indent)) |
          $heading] | last // null) as $heading |
        select($heading!=null) |
        $main[$heading].body |
        (try capture("^container(?:, Text:)?[[:space:]]+(?<title>[^:]+):").title catch "") |
        select(contains(slack_labels.comments)|not) |
        select(.!=slack_labels.reply and .!=slack_labels.open_channel)] | unique_value)
  };
def visible_label_checks:
  tree_text as $tree | slack_labels as $labels |
  ($tree|contains($labels.user_menu) or contains($labels.toolbar)) as $main |
  ($tree|contains($labels.search_panel) or contains($labels.search_dialog)) as $search |
  ($tree|contains($labels.thread_panel)) as $thread |
  ["search","combo","editor","list","broadcast"] | map(. as $key |
    {key:$key,present:($tree|contains($labels[$key])),
     required:(if $key=="search" then $main elif $key=="combo" then $search else $thread end)});
def ax_index($pattern): [ax_lines[]|select(.index!=null and (.body|test($pattern)))|.index]|if length==1 then .[0] else error("Ambiguous or missing accessibility target: "+$pattern) end;
# The workspace search button lives in the window's first toolbar (top bar). Pages such as
# activity or files have their own "검색" buttons further down; after a search the top button
# reads "검색: <query>". With several candidates, only the one in the top bar counts.
def global_search_button:
  ax_lines as $lines |
  [range(0;$lines|length)|select($lines[.].index!=null and ($lines[.].body|test("^버튼 검색(: .*)?$")))] as $hits |
  if ($hits|length)==1 then $lines[$hits[0]].index
  else
    ([range(0;$lines|length)|select($lines[.].index!=null and ($lines[.].body|test("^툴바( |$)")))][0]) as $t |
    (if $t==null then [] else
      ([$lines[$t+1:]|to_entries[]|select(.value.indent<=$lines[$t].indent)|.key+$t+1][0] // ($lines|length)) as $end |
      [$hits[]|select(.>$t and .<$end)] end) as $top |
    if ($top|length)==1 then $lines[$top[0]].index else error("Ambiguous or missing accessibility target: 상단 검색 버튼") end end;
# A post's own time link. Inside the thread panel Slack labels the root "…. 채널에서 열기" too.
def timestamp_link: test("^link \\[(오늘|어제|[0-9]{1,2}월 [0-9]{1,2}일), (오전|오후) [0-9]{1,2}:[0-9]{2}(:[0-9]{2})?(\\. 채널에서 열기)?\\]\\(https?://[^)]+\\)$");
# Never parse links from the channel/thread panes behind the search surface.
def search_list_label: test("^내용 목록 (채널의 메시지 결과|메시지 결과(?:, [0-9]+/[0-9]+페이지)?)$");
def search_surface_lines:
  ax_lines as $lines |
  [range(0;$lines|length)|select($lines[.].body|search_list_label)] as $starts |
  if ($starts|length)!=1 then error("검색 결과 목록을 하나로 식별하지 못했습니다") else $starts[0] as $s |
    [range(0;$s) as $h |
      select($lines[$h].body|test("^container (채널 내에서 검색|검색)$")) |
      select($lines[$h].indent<$lines[$s].indent) |
      select(all($lines[$h+1:$s][];.indent>$lines[$h].indent)) | $h] as $parents |
    if ($parents|length)==0 then error("검색 패널 경계를 확인하지 못했습니다") else $parents[-1] as $start |
      ([$lines[$start+1:]|to_entries[]|select(.value.indent<=$lines[$start].indent)|.key+$start+1][0] // ($lines|length)) as $end |
      $lines[$start:$end] end end;
def search_result_lines:
  search_surface_lines as $lines |
  [range(0;$lines|length)|select($lines[.].body|search_list_label)][0] as $s |
  ([$lines[$s+1:]|to_entries[]|select(.value.indent<=$lines[$s].indent)|.key+$s+1][0] // ($lines|length)) as $end |
  $lines[$s:$end];
# Each result message carries exactly one permalink labelled with its time; links inside the message
# (mentions, files, previews) are body content, not results.
def search_result_link: test("^link \\[(오늘|어제|[0-9]{1,2}월 [0-9]{1,2}일|[0-9]{4}년 [0-9]{1,2}월 [0-9]{1,2}일|[월화수목금토일]요일), (오전|오후) [0-9]{1,2}:[0-9]{2}(:[0-9]{2})?\\]\\(https?://[^/)]+/archives/[^)]+\\)$");
def search_results:
  search_result_lines as $lines |
  [range(1;$lines|length) as $i | $lines[$i] |
   select(.body|search_result_link) |
   (.body|capture("^link \\[(?<ts_text>[^]]+)\\]\\((?<url>https?://[^)]+)\\)$")) as $link |
   [range(1;$i) as $h |
    select($lines[$h].body|test("^container(?:[, ]|$)")) |
    select($lines[$h].indent<$lines[$i].indent) |
    select(all($lines[$h+1:$i][];.indent>$lines[$h].indent)) | $h] as $parents |
   if ($parents|length)==0 then error("검색 결과 메시지 경계를 확인하지 못했습니다") else
     $parents[0] as $start | $parents[-1] as $header |
     ([$lines[$start+1:]|to_entries[]|select(.value.indent<=$lines[$start].indent)|.key+$start+1][0] // ($lines|length)) as $end |
     [$lines[$header+1:$i][]|.body|select(startswith("버튼 "))|ltrimstr("버튼 ")] as $authors |
     [$lines[$start+1:$end][]|.body|
       if startswith("container, Text:") then sub("^container, Text:[[:space:]]*";"")
       elif startswith("텍스트, Value:") then sub("^텍스트, Value:[[:space:]]*";"") else empty end] as $text |
     $link+{author:(if ($authors|length)==1 then $authors[0] else "" end),
       channel:([$lines[$start+1:$end][]|.body|select(test("스레드:"))|sub("^.*스레드:[[:space:]]*";"")][0] // ""),
       text:($text|join("\n"))} end];
def search_report:
  . as $tree | search_result_lines as $list |
  ($list|any(.[];.body=="텍스트, Value: 찾은 결과가 없습니다")) as $empty |
  ($tree|search_surface_lines) as $lines |
  ([range(1;$lines|length) as $i |
    select($lines[$i].body=="텍스트, Value: 개의 결과를 찾음") |
    $lines[$i-1].body|capture("^텍스트, Value: (?<n>[0-9]+)$").n|tonumber] +
   [$lines[].body|capture("^텍스트, Value: 결과 (?<n>[0-9]+)건$").n|tonumber]) as $counts |
  ($tree|search_results) as $items |
  if $empty and ($items|length)>0 then error("검색 결과의 빈 상태가 모순됩니다")
  elif ($items|length)==0 and ($empty|not) then error("검색 결과/빈 상태를 확인하지 못했습니다")
  else {items:$items,total:(if $empty then 0 elif ($counts|length)==1 then $counts[0] else null end)} end;
# The query is from:me, so every result must read as the configured author. An unreadable or
# different author is a read failure (stop), never "no own reply".
def search_has_own_reply($ts):
  ($ARGS.named.routine.identity.slack_display_name // "") as $name |
  ($ARGS.named.routine.slack.channel_id // "") as $channel |
  if $name=="" then error("표시 이름 설정이 없어 검색 결과 작성자를 확인할 수 없습니다")
  elif any(.items[]; .author!=$name) then error("검색 결과 작성자를 확인하지 못했습니다")
  else
  [.items[]|
    ([.url|capture("^https?://[^/]+/archives/(?<channel>[CGD][A-Z0-9]+)/p[0-9]{16}(?:\\?(?<query>[^#]+))?$")][0]) as $url |
    if $url==null then {duplicate:false,valid:false}
    elif $url.channel!=$channel then {duplicate:false,valid:true}
    else [($url.query // "")|split("&")[]|select(startswith("thread_ts="))|ltrimstr("thread_ts=")] as $threads |
      if ($threads|length)==0 then {duplicate:false,valid:true}
      elif ($threads|length)!=1 or ($threads[0]|test("^[0-9]{10}\\.[0-9]{6}$")|not) then {duplicate:false,valid:false}
      else {duplicate:($threads[0]==$ts),valid:true} end end] as $matches |
  if any($matches[];.duplicate) then true
  elif any($matches[];.valid|not) then error("검색 결과 메시지 URL/thread_ts를 해석하지 못했습니다")
  elif .total==null or .total!=(.items|length) then error("전체 검색 결과를 확인하지 못했습니다")
  else false end end;
def scrum_blocks_for($dates):
  ax_lines as $lines |
  [range(0;$lines|length) as $heading | select(slack_settings.post_title|length>0) | select($lines[$heading].body|contains(slack_settings.post_title)) |
   ($heading>0 and ($lines[$heading-1].body|timestamp_link)) as $before |
   ([$lines[$heading+1:]|to_entries[]|select((.value.body|startswith("container")) and .value.indent<=$lines[$heading].indent)|.key+$heading+1][0] // ($lines|length)) as $container_end |
   ([$lines[$heading+1:]|to_entries[]|select(.value.body|timestamp_link)|.key+$heading+1]) as $links |
   (if $before then ($links[0] // ($lines|length)) else ($links[1] // ($lines|length)) end) as $time_end |
   $lines[(if $before then $heading-1 else $heading end):([$container_end,$time_end]|min)] as $block |
   [$block[]|select(.body|timestamp_link)] as $times |
   select(($times|length)==1 and ($times[0].body as $body | any($dates[]; . as $date | $body|contains("link ["+$date+", "+slack_settings.post_time_prefix)))) |
   [$block[]|select(.body|test("버튼 [0-9]+"+slack_labels.comments))|.index] as $replies |
   if ($replies|length)>1 then error("같은 글의 댓글 버튼이 여러 개입니다") else
     {reply:($replies[0] // null),container:$lines[$heading].index,lines:$block,
      url:($times[0].body|capture("\\((?<url>https?://[^)]+)\\)").url)} end] |
  # A post's title can match more than one line (the message container and, for workflow posts,
  # the author button). Matches sharing one permalink are the same post: keep the outermost block.
  group_by(.url) | map(sort_by(.container) as $same |
    ([$same[].reply|select(.!=null)]|unique) as $replies |
    if ($replies|length)>1 then error("같은 글의 댓글 버튼이 여러 개입니다") else
      $same[0]+{reply:($replies[0] // null)} end) | sort_by(.container) | map(del(.url));
def scrum_blocks: scrum_blocks_for(["오늘"]);
def scrum_block: scrum_blocks |
  if length==1 then .[0] else error("오늘 스크럼 글을 하나로 식별하지 못했습니다") end;
# Channel navigation never borrows the duplicated root or actions from an open thread panel.
def channel_scrum_blocks: main_list_lines |
  if length==0 then error("채널 본문 목록을 확인하지 못했습니다") else map(.raw)|join("\n")|scrum_blocks end;
def channel_scrum_block: channel_scrum_blocks |
  if length==1 then .[0] else error("채널 본문에서 오늘 스크럼 글을 하나로 식별하지 못했습니다") end;
def thread_lines:
  ax_lines as $lines | [range(0;$lines|length)|select(slack_settings.channel_name|length>0)|select($lines[.].body|contains(slack_settings.channel_name+slack_labels.thread_panel))] as $starts |
  if ($starts|length)!=1 then error("스크럼 스레드 패널을 확인하지 못했습니다") else $lines[$starts[0]:] end;
def thread_root:
  thread_lines | map(.raw)|join("\n")|scrum_block;
def reply_timestamp_link: test("^link \\[(오늘|어제|[0-9]{1,2}월 [0-9]{1,2}일), (오전|오후) [0-9]{1,2}:[0-9]{2}(:[0-9]{2})?\\. "+slack_labels.open_channel+"\\]\\(https?://[^)]+\\)$");
# Comment list of the currently open, configured channel's thread.
def thread_comment_list:
  thread_lines as $lines | [range(0;$lines|length)|select($lines[.].body|startswith(slack_labels.list+slack_settings.channel_name+slack_labels.thread_list))] |
  if length!=1 then error("스레드 댓글 목록을 확인하지 못했습니다") else .[0] as $i |
    ([$lines[$i].body|capture("(?<n>[0-9]+)"+slack_labels.comments).n|tonumber][0] // 0) as $count |
    ([$lines[$i+1:]|to_entries[]|select(.value.indent<=$lines[$i].indent)|.key+$i+1][0] // ($lines|length)) as $end |
    {count:$count,lines:$lines[$i+1:$end]} end;
# A reply identity is its canonical message URL, after verifying its thread_ts.
# Also used by learning to extract only replies belonging to the selected root.
def thread_reply_urls($url):
  ([$url|capture("/p(?<a>[0-9]{10})(?<b>[0-9]{6})$")|"\(.a).\(.b)"][0]) as $ts |
  if $ts==null then [] else
    [thread_comment_list.lines[]|.body|select(reply_timestamp_link)|
      capture("\\((?<url>https?://[^)]+)\\)").url|
      select(([capture("[?&]thread_ts=(?<ts>[0-9.]+)").ts][0])==$ts)|
      split("?")[0]]|unique
  end;
# Identify the open thread: the root post link matches, or (Slack scrolls the root out of a long
# panel) every visible comment link carries the expected root's thread_ts.
def thread_identified($url):
  (try (thread_root|[.lines[]|.body|select(timestamp_link)|capture("\\((?<url>https?://[^)]+)\\)").url]==[$url]) catch false) or
  ([$url|capture("/p(?<a>[0-9]{10})(?<b>[0-9]{6})$")|"\(.a).\(.b)"][0] as $ts | $ts!=null and
    (try (thread_comment_list as $list | [$list.lines[]|.body|select(reply_timestamp_link)] as $links |
      [$links[]|capture("[?&]thread_ts=(?<ts>[0-9.]+)").ts] as $tss |
      $list.count>0 and ($links|length)>0 and ($tss|length)==($links|length) and all($tss[];.==$ts)) catch false));
# Own comment = the configured name in an author position (author button, or a message container
# headed "<name>:"). A bare substring also hits the account menu and search remnants such as
# "채널에서 검색: from:@<name> …" left after a search.
def own_comment: ($ARGS.named.routine.identity.slack_display_name // "") as $name |
  ($name|length)>0 and (thread_lines|any(.[]; .body as $b |
    $b==("버튼 "+$name) or ($b|startswith("container "+$name+":")) or ($b|startswith("container, Text: "+$name+":"))));
def thread_editor:
  thread_lines as $lines | [$lines[]|select(.index!=null and (.body|test(slack_labels.editor+".*(스레드|댓글)")))] |
  if length!=1 then error("스레드 입력창을 하나로 식별할 수 없습니다") else
    # Current Orca omits ", Value:" for an empty settable text area.
    .[0]|.+{value:([.body|capture("(?:Value|값):[[:space:]]*(?<value>.*)$").value][0] // (if .body|test("\\(settable\\)") then "" else null end))} |
    if .value==null then error("입력창의 빈 값 여부를 확인할 수 없습니다") else . end end;
def broadcast_checkbox:
  thread_lines | [.[]|select((.body|test("(체크상자|체크박스|체크 상자|checkbox)";"i")) and (.body|contains(" #"+slack_settings.channel_name+slack_labels.broadcast) or contains(" "+slack_settings.channel_name+slack_labels.broadcast)))] |
  if length!=1 then error("채널 동시 전송 체크박스를 확인할 수 없습니다") else
    .[0].body | try capture("(?:Value|값|Checked|선택됨):[[:space:]]*(?<value>.*)$").value catch error("채널 동시 전송 상태가 없습니다") end;
def thread_fingerprint:
  {root:(try (thread_root.lines|map(.body)) catch null),thread:(thread_lines|map(.body))};
# Accessibility outline for diagnosing Slack format changes. Everything is masked by default
# (replaced by its length); only roles, indexes, exactly known control labels and 0/1 checkbox values
# stay. Organisation identifiers become placeholders that still show whether they match the settings:
# workspace host → ⟨workspace⟩, channel ID → ⟨channel⟩/⟨other⟩, channel name → ⟨channel_name⟩,
# post title → ⟨post_title⟩. Timestamp links keep only that shape plus a numeric thread_ts.
def structure_dump:
  def masked: "⟨\(length)자⟩";
  slack_settings as $s |
  ($ARGS.named.routine.slack.workspace_domain // "") as $domain |
  ($ARGS.named.routine.slack.channel_id // "") as $channel_id |
  def control: test("^([0-9]+개의 댓글|스레드의 댓글|스레드에서 답장|스레드에 댓글 달기|스레드 요약|반응 추가\\.\\.\\.|메시지 전달\\.\\.\\.|나중을 위해 저장|추가 작업|닫기|검색|전송|채널 작업 더 보기|메시지 작업|이모티콘 추가|더보기)$");
  def roles: "표준 윈도우|HTML 콘텐츠|팝업 버튼|전환 버튼|버튼|텍스트 엔트리 영역|내용 목록|윤곽체 행|탭 그룹|탭|툴바|체크박스|체크상자|메뉴 항목|콤보 상자|이미지|텍스트|link|container|그룹|정적 텍스트";
  def link_out:
    ([capture("^link \\[(?<label>(오늘|어제|[0-9]{1,2}월 [0-9]{1,2}일), (오전|오후) [0-9]{1,2}:[0-9]{2}(:[0-9]{2})?(\\. 채널에서 열기)?)\\]\\((?<url>[^)]*)\\)$")][0]) as $m |
    if $m==null then "link "+(sub("^link ";"")|masked)
    else ([$m.url|capture("^https://(?<host>[a-z0-9-]+)\\.slack\\.com/archives/(?<ch>[A-Z0-9]+)/p(?<p>[0-9]+)(\\?(?<q>[^#]*))?$")][0]) as $u |
      if $u==null then "link [\($m.label)](\($m.url|masked))"
      else ([($u.q // "")|split("&")[]|select(test("^thread_ts=[0-9]+\\.[0-9]+$"))][0]) as $ts |
        "link [\($m.label)](https://\(if $u.host==$domain and $domain!="" then "⟨workspace⟩" else "⟨other_workspace⟩" end).slack.com/archives/\(if $u.ch==$channel_id and $channel_id!="" then "⟨channel⟩" else "⟨other:\($u.ch[0:1])⟩" end)/p\($u.p)\(if $ts then "?"+$ts else "" end))" end end;
  # Text before a ", Text:"/", Value:" field or after the role: kept only when it is a known control
  # or the configured channel/post structure (as placeholders); "(settable)" survives, the rest is masked.
  def head_out($role):
    if .=="" then ""
    elif (($role|test("버튼$")) or $role=="container") and control then " "+.
    elif $role=="container" and ($s.channel_name|length)>0 and .==($s.channel_name+slack_labels.thread_panel) then " ⟨channel_name⟩"+slack_labels.thread_panel
    elif $role=="container" and ($s.post_title|length)>0 and startswith($s.post_title+":") then " ⟨post_title⟩: "+(.[($s.post_title|length)+1:]|masked)
    elif $role=="내용 목록" and ($s.channel_name|length)>0 and startswith($s.channel_name) and (.[($s.channel_name|length):]|test("^(의 스레드)? \\(채널(, [0-9]+개의 댓글)?\\)$")) then " ⟨channel_name⟩"+.[($s.channel_name|length):]
    elif startswith("(settable)") then " (settable)"+(sub("^\\(settable\\) ?";"") | if .=="" then "" else " "+masked end)
    else " "+masked end;
  # A line whose role is not recognised may be a wrapped value; its leading number is not trusted
  # as an index and is masked with the rest.
  ax_lines[] | .raw as $raw |
  ($raw|capture("^(?<i>[[:space:]]*)").i) as $indent |
  .body as $body |
  ([$body|capture("^(?<role>("+roles+"))(?=[ ,]|$)(?<rest>.*)$")][0]) as $m |
  if .index==null or $m==null then $indent+($raw|ltrimstr($indent)|masked)
  else ($raw|capture("^(?<p>[[:space:]]*(\\[[0-9]+\\]|[0-9]+)[[:space:]]*)").p) + (
    if $m.role=="link" then $body|link_out
    else ($m.rest|sub("^ ";"")) as $rest |
      ([$rest|capture("^(?<head>.*?),? ?(?<k>Text|Value|값):[[:space:]]*(?<v>.*)$")][0]) as $f |
      if $f!=null then "\($m.role)\($f.head|sub(",$";"")|head_out($m.role)), \($f.k): \(if ($f.v|test("^[01]$")) then $f.v else ($f.v|masked) end)"
      else $m.role+($rest|head_out($m.role)) end end) end;
