# Korean Slack accessibility vocabulary lives here, not in user configuration.
def slack_labels: {search:"버튼 검색",combo:"콤보 상자",editor:"텍스트 엔트리 영역",list:"내용 목록 ",thread_panel:" 채널의 스레드",thread_list:"의 스레드",open_channel:"채널에서 열기",comments:"개의 댓글",user_menu:"팝업 버튼 사용자:",today:"오늘, ",reply:"버튼 스레드에서 답장",broadcast:"(으)로도 전송",toolbar:"도구 막대",search_panel:"검색 결과",search_dialog:"대화상자, Title: 검색"};
def slack_settings: $ARGS.named.routine.slack // {channel_name:"",post_title:"",post_time_prefix:"오전 8:0"};
def today_timestamp: contains("link ["+slack_labels.today+slack_settings.post_time_prefix);
# The hover action that opens a post's thread; Slack has labelled it both ways.
def reply_action: test("^"+slack_labels.reply+"$") or test("^버튼 스레드의 댓글$");
def tree_text: .result.snapshot.treeText // .snapshot.treeText // .treeText // error("Missing treeText");
# Orca prints element indexes as "[12] role" (older) or "12 role" (current).
def ax_lines:
  split("\n")|map(. as $raw|(try capture("^(?<space>[[:space:]]*)(\\[(?<index>[0-9]+)\\]|(?<bare>[0-9]+)[[:space:]])[[:space:]]*(?<body>.*)$") catch null) as $m|
    {raw:$raw,index:($m.index // $m.bare // null|if .==null then null else tonumber end),indent:($m.space // ""|length),body:($m.body // $raw)});
# The channel's main message list ("내용 목록 <name> (채널)", not "<name>의 스레드" or a search pane).
# Every init check and the channel-name proposal use only these lines.
def main_list_lines:
  ax_lines as $lines |
  [range(0;$lines|length)|select($lines[.].body|test("^내용 목록 .+ \\(채널(?:[,)]|$)") and (test("의 스레드 \\(")|not))] as $starts |
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
def timestamp_link: test("^link \\[(오늘|어제|[0-9]{1,2}월 [0-9]{1,2}일), (오전|오후) [0-9]{1,2}:[0-9]{2}(:[0-9]{2})?\\]\\(https?://[^)]+\\)$");
def search_results:
  ax_lines as $lines |
  [range(0;$lines|length) as $i|$lines[$i]|select(.body|test("link \\[.*\\]\\(https?://"))|
   (.body|capture("link \\[(?<ts_text>[^]]+)\\]\\((?<url>https?://[^)]+)\\)")) as $link |
   ($lines[$i+1:]|.[:(map(.body|test("link \\[.*\\]\\(https?://"))|index(true) // length)]) as $tail |
   [$tail[]|select(.body|startswith("container, Text:"))|.body|sub("^container, Text:[[:space:]]*";"")] as $text |
   select($text|length>0)|$link+{channel:([$tail[]|.body|select(test("스레드:"))|sub("^.*스레드:[[:space:]]*";"")][0] // ""),text:($text|join("\n"))}][:50];
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
def thread_list_index:
  thread_lines | [.[]|select(.index!=null and (.body|startswith(slack_labels.list+slack_settings.channel_name+slack_labels.thread_list)))] |
  if length==1 then .[0].index else error("스크롤할 댓글 목록을 확인하지 못했습니다") end;
# A reply identity is its canonical message URL, after verifying its thread_ts.
# Query variations must not let the same reply count twice across scroll pages.
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
# All N comments are on screen (comment links carry thread_ts; the root link does not).
def thread_complete:
  try (thread_comment_list as $list | [$list.lines[]|.body|select(reply_timestamp_link and test("[?&]thread_ts="))]|length==$list.count) catch false;
# $complete: also require every comment visible (before the duplicate check; a long pasted draft
# later pushes comments out of view, so post-paste guards only re-identify the thread).
def thread_matches_root($url; $complete):
  thread_identified($url) and (($complete|not) or thread_complete);
# Ignore the account menu when looking for the configured user's own comments.
def own_comment: ($ARGS.named.routine.identity.slack_display_name // "") as $name | thread_lines|any(.[]; ($name|length)>0 and (.body|contains($name) and (startswith(slack_labels.user_menu)|not)));
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
