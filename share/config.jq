def defaults($home; $user):
 {identity:{slack_display_name:"",git_authors:[],notion_email_like:""},
  slack:{team_id:"",workspace_domain:"",channel_id:"",channel_name:"",post_title:"",post_time_prefix:"오전 8:0"},
  draft:{project:"",markers:"none",headers:{yesterday:"어제 작업한 내용",today:"오늘의 작업 계획"},categories:["현황 파악","배포","개발","인프라","업무 자동화","기타"],format:{bullets:["•","◦","▪","▪"],layout:"tree",max_items_per_section:null},llm:{engine:"auto",model:null}},
  sources:{git:{enabled:true,roots:[($home+"/Documents/GitHub")]},prs:{enabled:true},omp_sessions:{enabled:true,dir:($home+"/.omp/agent/sessions")},claude_sessions:{enabled:true,dir:($home+"/.claude/projects")},jira:{enabled:false,chrome_dir:($home+"/Library/Application Support/Google/Chrome")},notion:{enabled:false,db:($home+"/Library/Application Support/Notion/notion.db")},slack:{enabled:false}},
  collect:{until:"today_start",max_days:14},
  calendar:{public_holidays:"kr",days_off:[],work_days:[],day_off_notes:{}},
  ui:{terminal_bundle_ids:["com.apple.Terminal","com.googlecode.iterm2","net.kovidgoyal.kitty","com.mitchellh.ghostty","org.alacritty","com.github.wez.wezterm","com.microsoft.VSCode","com.microsoft.VSCodeInsiders","com.todesktop.230313mzl4w4u","com.jetbrains.intellij","com.jetbrains.intellij.ce","com.jetbrains.pycharm","com.jetbrains.pycharm.ce","com.jetbrains.WebStorm","com.jetbrains.goland","com.jetbrains.CLion","com.jetbrains.rider","com.jetbrains.rubymine","com.jetbrains.PhpStorm","com.jetbrains.datagrip","dev.warp.Warp-Stable","com.cmuxterm.app","com.stablyai.orca"]},
  delivery:{mode:"clipboard",window:{start:"08:10",end:"11:30"},no_post_after:"09:00",idle_seconds:180,daily_attempts:6},
  morning:{time:"08:00",weekdays:[1,2,3,4,5],extra_steps:{omp_update:false,claude_update:false,npm_update:false,aws_session:false}},
  launchd:{label_prefix:("com."+$user+".routine")},timezone:null};
def migrate_config:
  if .sources.git|has("root") then
    (if .sources.git|has("roots") then . else .sources.git.roots=[.sources.git.root] end) | del(.sources.git.root)
  else . end;
def nonempty: type=="string" and test("[^[:space:]]");
def texts: type=="array" and all(.[];nonempty);
def clock: type=="string" and test("^([01][0-9]|2[0-3]):[0-5][0-9]$");
def calendar_date:
 type=="string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") and
 (try ((.+ "T00:00:00Z"|fromdateiso8601|strftime("%Y-%m-%d"))==.) catch false);
def calendar_dates: type=="array" and all(.[];calendar_date) and length==(unique|length);
def format_errors:
 [(if (.draft.format|type)!="object" then "draft.format"
   else
     (if (.draft.format.bullets|texts and length>=1 and length<=6)|not then "draft.format.bullets" else empty end),
     (if (.draft.format.layout|IN("tree","flat"))|not then "draft.format.layout" else empty end),
     (if (.draft.format.max_items_per_section|.==null or (type=="number" and .==floor and .>0))|not then "draft.format.max_items_per_section" else empty end)
   end)];
def config_ok:
 type=="object" and
 (.identity.slack_display_name|type=="string") and (.identity.git_authors|texts) and (.identity.notion_email_like|type=="string") and
 ([.slack.team_id,.slack.workspace_domain,.slack.channel_id,.slack.channel_name,.slack.post_title,.slack.post_time_prefix,.draft.project,.draft.headers.yesterday,.draft.headers.today]|all(.[];type=="string")) and
 (.slack.post_time_prefix|nonempty and test("^(오전|오후) (0?[1-9]|1[0-2]):[0-5][0-9]?$")) and
 (.draft.categories|texts and length>0 and length==(unique|length)) and (.draft.llm.engine|IN("auto","claude","omp","none")) and (.draft.llm.model|.==null or nonempty) and
 (.draft.markers|IN("none","uncertain","all")) and
 (format_errors|length==0) and
 (.sources|type=="object" and all(.[];type=="object" and (.enabled|type=="boolean"))) and
 (.sources.git.roots|texts and length==(unique|length)) and (.collect.until|IN("now","today_start")) and
 (.collect.max_days|type=="number" and .==floor and .>=1) and
 (.calendar|type=="object") and (.calendar.public_holidays|IN("kr","none")) and
 (.calendar.days_off|calendar_dates) and (.calendar.work_days|calendar_dates) and
 (.calendar.day_off_notes|type=="object" and all(to_entries[];(.key|calendar_date) and (.value|type=="string"))) and
 (.ui.terminal_bundle_ids|texts and all(.[];test("^[A-Za-z0-9][A-Za-z0-9._-]+$")) and length==(unique|length)) and
 ([.sources.omp_sessions.dir,.sources.claude_sessions.dir,.sources.jira.chrome_dir,.sources.notion.db]|all(.[];nonempty)) and
 (.delivery.mode|IN("clipboard","gui-paste")) and ([.delivery.window.start,.delivery.window.end,.delivery.no_post_after,.morning.time]|all(.[];clock)) and (.delivery.window.start<=.delivery.window.end) and
 (.delivery.idle_seconds|type=="number" and .==floor and .>=60) and (.delivery.daily_attempts|type=="number" and .==floor and .>0) and
 (.morning.weekdays|type=="array" and length>0 and all(.[];type=="number" and .==floor and .>=1 and .<=7) and length==(unique|length)) and
 (.morning.extra_steps|all(.[];type=="boolean")) and (.launchd.label_prefix|type=="string" and test("^[A-Za-z0-9][A-Za-z0-9._-]+$")) and (.timezone|.==null or nonempty);
def required_errors:
 [((["slack.team_id","slack.workspace_domain","slack.channel_id"] +
    (if .delivery.mode=="gui-paste" then ["identity.slack_display_name","slack.channel_name","slack.post_title"] else [] end))[] as $key |
    select(getpath($key|split("."))|nonempty|not)|$key),
  (if .sources.git.enabled and (.identity.git_authors|length)==0 then "identity.git_authors" else empty end),
  # Slack is only searched right before a GUI paste; the unattended collect step needs another source.
  (if ([.sources|to_entries[]|select(.key!="slack" and .value.enabled)]|length)==0 then "sources(Slack 외 수집 소스 최소 1개)" else empty end),
  (if .sources.git.enabled and (.sources.git.roots|length)==0 then "sources.git.roots" else empty end),
  (if .sources.notion.enabled and (.identity.notion_email_like|nonempty|not) then "identity.notion_email_like" else empty end)] + format_errors +
 (if (.slack.team_id|test("^T[A-Z0-9]+$")) and (.slack.channel_id|test("^[CG][A-Z0-9]+$")) and (.slack.workspace_domain|test("^[a-z0-9][a-z0-9-]*$")) then [] else ["slack IDs/domain 형식"] end);
