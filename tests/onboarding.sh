#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
real_jq=${TEST_JQ_BIN:-$(type -P jq)}
# Do not inherit the parent suite's morning-only gtimeout stub.
real_timeout=$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin builtin type -P gtimeout || PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin builtin type -P timeout)
while IFS= read -r name; do [[ $name != ROUTINE_* ]] || unset "$name"; done < <(compgen -v)
sandbox=$(mktemp -d /tmp/routine-onboarding-tests.XXXXXXXX)
sandbox=$(cd -- "$sandbox" && pwd -P)
trap 'chmod -R u+rwx "$sandbox"; rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" PATH="$sandbox/stubs:/usr/bin:/bin" USER=fixture
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null RECORD="$sandbox/calls"
export ROUTINE_CONFIG="$HOME/.config/routine-automation/config.json" ROUTINE_APPLICATIONS_DIR="$sandbox/apps" ROUTINE_ORCA_APP_CLI="$sandbox/stubs/orca"
mkdir -p "$HOME/.local/bin" "$TMPDIR" "$sandbox/stubs" "$ROUTINE_APPLICATIONS_DIR"
# shellcheck source=network.sh
source "$repo/tests/network.sh"
ln -s "$real_jq" "$sandbox/stubs/jq"; ln -s "$sandbox/stubs/jq" "$HOME/.local/bin/jq"
ln -s "$real_timeout" "$sandbox/stubs/gtimeout"
ln -s "$sandbox/stubs/gtimeout" "$HOME/.local/bin/gtimeout"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
# All GUI/auth/model entrypoints are private sentinels. Only git/date/SQLite operate on fixtures.
for cmd in claude omp open orca brew launchctl osascript osacompile xattr; do
  cat > "$sandbox/stubs/$cmd" <<'STUB'
#!/bin/sh
printf 'forbidden %s %s\n' "${0##*/}" "$*" >> "$RECORD"
exit 87
STUB
  chmod +x "$sandbox/stubs/$cmd"; ln -s "$sandbox/stubs/$cmd" "$HOME/.local/bin/$cmd"
done
cat > "$sandbox/stubs/gh" <<'STUB'
#!/bin/bash
if [[ "$*" == 'auth status' && ${GH_AVAILABLE:-0} == 1 ]]; then exit; fi
exit 1
STUB
chmod +x "$sandbox/stubs/gh"; ln -s "$sandbox/stubs/gh" "$HOME/.local/bin/gh"
cat > "$sandbox/stubs/git" <<'STUB'
#!/bin/bash
if [[ ${1:-} == -C && " $* " == *' log '* ]]; then printf '%s\n' "$2" >> "$RECORD.git-logs"; fi
if [[ ${1:-} == -C && " $* " == *' --show-toplevel '* ]]; then printf '%s\n' "$2" >> "$RECORD.git-discovery"; fi
exec /usr/bin/git "$@"
STUB
chmod +x "$sandbox/stubs/git"; ln -s "$sandbox/stubs/git" "$HOME/.local/bin/git"
primary="$sandbox/roots/primary" grouped="$sandbox/roots/grouped" nested="$grouped/group/nested"
mkdir -p "$primary" "$nested" "$grouped/deep/level/skipped"
for dir in "$primary" "$nested" "$grouped/deep/level/skipped"; do git init -q "$dir"; done
commit() {
  local dir=$1 stamp=$2 subject=$3
  printf '%s\n' "$subject" >> "$dir/changes"; git -C "$dir" add changes
  GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" git -C "$dir" -c user.name=Fixture -c user.email=fixture@example.com commit -qm "$subject"
}
commit "$primary" '2026-09-25T00:00:01+0900' 'Friday work'
commit "$primary" '2026-09-27T23:59:59+0900' 'Sunday work'
commit "$primary" '2026-09-28T00:00:00+0900' 'Midnight work'
commit "$primary" '2026-09-28T08:00:00+0900' 'Monday work'
commit "$nested" '2026-09-26T12:00:00+0900' 'Nested work'
commit "$grouped/deep/level/skipped" '2026-09-26T12:00:00+0900' 'Too deep'
git -C "$primary" worktree add -q --detach "$grouped/worktree"
roots=$(jq -nc --arg first "$primary" --arg second "$grouped" --arg duplicate "$grouped/worktree" '[$first,$second,$duplicate]')
routine="$repo/bin/routine"
"$routine" init --non-interactive --slack-link https://example.slack.com/archives/CEXAMPLE/p1790895609247049 --slack-team-id TEXAMPLE --identity-git-authors '["fixture@example.com"]' --sources-git-roots "$roots" --sources-prs-enabled false --draft-llm-engine none --timezone Asia/Seoul > /dev/null
export ROUTINE_NOW='2026-09-28T09:00:00+09:00'
out="$HOME/Library/Application Support/routine-automation/scrum"; : > "$RECORD.git-logs"
"$routine" collect --sources git --out "$out"
jq -e '.window.since=="2026-09-24T15:00:00Z" and .window.until=="2026-09-27T15:00:00Z" and (.git|map(.subject)|sort)==["Friday work","Nested work","Sunday work"] and .errors==[]' "$out/2026-09-28.json" >/dev/null || fail 'Monday cutoff included today or missed a depth-two repository'
jq -Rse 'split("\n")|map(select(length>0))|length==2' "$RECORD.git-logs" >/dev/null || fail 'Common-dir/worktree dedup repeated repository reads'
"$routine" draft --date 2026-09-28 --no-llm --out "$sandbox/implicit-draft"
jq -e '.window.since=="2026-09-24T15:00:00Z" and .window.until=="2026-09-27T15:00:00Z" and (.git|map(.subject)|sort)==["Friday work","Nested work","Sunday work"]' "$sandbox/implicit-draft/2026-09-28.json" >/dev/null || fail 'Implicit draft collection ignored the configured cutoff'
"$routine" collect --sources git --out "$out" --until '2026-09-28T09:00:00+09:00'
jq -e '(.git|map(.subject)|sort)==["Friday work","Midnight work","Monday work","Nested work","Sunday work"] and .window.until=="2026-09-28T00:00:00Z"' "$out/2026-09-28.json" >/dev/null || fail 'Explicit --until did not override the midnight policy'
"$routine" config set collect.until '"now"'
"$routine" collect --sources git --out "$out"
jq -e 'any(.git[];.subject=="Monday work")' "$out/2026-09-28.json" >/dev/null || fail 'Now policy dropped current morning work'
"$routine" config set collect.until '"today_start"'
"$routine" config set timezone '"America/New_York"'
ROUTINE_NOW='2026-03-09T00:30:00-04:00' "$routine" collect --sources git --out "$out"
jq -e '.window.since=="2026-03-06T05:00:00Z" and .window.until=="2026-03-09T04:00:00Z"' "$out/2026-03-09.json" >/dev/null || fail 'Local calendar bounds drifted across DST'
ROUTINE_NOW='2026-03-09T00:30:00-04:00' "$routine" draft --date 2026-03-09 --no-llm --out "$sandbox/dst-draft"
jq -e '.window.since=="2026-03-06T05:00:00Z" and .window.until=="2026-03-09T04:00:00Z"' "$sandbox/dst-draft/2026-03-09.json" >/dev/null || fail 'Implicit draft used a fixed-second workday across DST'
"$routine" config set timezone '"Asia/Seoul"'
locked="$HOME/Documents/locked"; mkdir -p "$locked"; chmod 000 "$locked"
ROUTINE_GIT_ROOTS=$(jq -nc --arg root "$primary" --arg locked "$locked" '[$root,$locked]') "$routine" collect --sources git --out "$out"
chmod 700 "$locked"
jq -e --arg root "$locked" 'any(.git[];.subject=="Friday work") and any(.errors[];.source=="git" and (.message|contains($root)) and (.message|contains("Documents access")))' "$out/2026-09-28.json" >/dev/null || fail 'Protected-root error lost the root name or readable-root activity'
missing="$HOME/roots/missing"
ROUTINE_GIT_ROOTS=$(jq -nc --arg root "$primary" --arg missing "$missing" '[$root,$missing]') "$routine" collect --sources git --out "$out"
jq -e --arg root "$missing" 'any(.errors[];.source=="git" and (.message|contains($root)) and (.message|contains("does not exist")) and (.message|contains("Documents access")|not))' "$out/2026-09-28.json" >/dev/null || fail 'Missing root was incorrectly diagnosed as a privacy-permission failure'
# A legacy root is consumed once, removed, and saved as roots on the next edit.
jq --arg root "$primary" '.sources.git.root=$root|del(.sources.git.roots)' "$ROUTINE_CONFIG" > "$sandbox/legacy"; mv "$sandbox/legacy" "$ROUTINE_CONFIG"
"$routine" config set collect.until '"today_start"'
jq -e --arg root "$primary" '.sources.git.roots==[$root] and (.sources.git|has("root")|not)' "$ROUTINE_CONFIG" >/dev/null || fail 'Legacy root did not cut over to roots'
# Session cwd proposals are read only and stay inside explicit session folders/common candidates.
session_repo="$HOME/session-roots/repo"; claude_repo="$HOME/claude-roots/group/repo"
mkdir -p "$HOME/.omp/agent/sessions" "$HOME/.claude/projects/example" "$session_repo/subdir" "$claude_repo" "$HOME/dev"
git init -q "$session_repo"; git init -q "$claude_repo"
jq -nc --arg cwd "$session_repo/subdir" '{type:"session",cwd:$cwd}' > "$HOME/.omp/agent/sessions/one.jsonl"
jq -nc --arg cwd "$primary" '{type:"session",cwd:$cwd}' > "$HOME/.omp/agent/sessions/external.jsonl"
printf '%s\n' '{"type":"last-prompt","text":"fixture"}' '{"type":"mode","mode":"fixture"}' '{"type":"permission-mode","mode":"fixture"}' > "$HOME/.claude/projects/example/one.jsonl"
jq -nc --arg cwd "$claude_repo" '{type:"user",cwd:$cwd}' >> "$HOME/.claude/projects/example/one.jsonl"
extra="$HOME/surprise/repo"; mkdir -p "$extra"; git init -q "$extra"
jq -nc --arg cwd "$extra" '{type:"user",cwd:$cwd}' >> "$HOME/.claude/projects/example/one.jsonl"
# Neither the 51st record nor bytes beyond 64KB may provide a discovery cwd.
for ((i=0;i<50;i++)); do printf '%s\n' '{"type":"mode"}'; done > "$HOME/.claude/projects/example/late-record.jsonl"
jq -nc --arg cwd "$extra" '{type:"user",cwd:$cwd}' >> "$HOME/.claude/projects/example/late-record.jsonl"
printf -v padding '%066000d' 0
jq -nc --arg text "$padding" '{type:"last-prompt",text:$text}' > "$HOME/.claude/projects/example/late-bytes.jsonl"
jq -nc --arg cwd "$extra" '{type:"user",cwd:$cwd}' >> "$HOME/.claude/projects/example/late-bytes.jsonl"
share_dir="$repo/share"
# shellcheck source=../share/config.sh
source "$share_dir/config.sh"
routine_load_config file
# shellcheck source=../share/sources.sh
source "$share_dir/sources.sh"
candidates=$(routine_git_candidates)
jq -e --arg first "${session_repo%/*}" --arg second "${claude_repo%/*}" --arg known "$HOME/dev" --arg explicit "$primary" --arg external "${primary%/*}" 'index($first)!=null and index($second)!=null and index($known)!=null and index($explicit)!=null and index($external)==null' <<< "$candidates" >/dev/null || fail 'Explicit external root was lost or external session cwd was automatically proposed'
[[ $(routine_git_root_count "$grouped") == 2 ]] || fail 'Proposal count included depth-three repos or duplicate worktrees'
jq -e --arg excluded "${extra%/*}" 'index($excluded)==null' <<< "$candidates" >/dev/null || fail 'Claude discovery read later cwd fields instead of the first'
mkdir -p "$HOME/.omp/wt/repo" "$HOME/.cache/repo" "$HOME/Library/repo"
ln -s "$HOME" "$HOME/home-alias"
for blocked in "$HOME" "$HOME/" "$HOME/." "$HOME/.." "$HOME/home-alias/." "$HOME/.omp/wt/repo" "$HOME/.cache/repo" "$HOME/Library/repo" /; do
  if routine_git_root_path "$blocked" >/dev/null; then fail "Unsafe repository candidate accepted: $blocked"; fi
done
for outside in "$primary" /tmp /var /private; do
  if routine_git_root_path "$outside" auto >/dev/null 2>&1; then fail 'Automatic session discovery escaped HOME'; fi
done
ln -s "$primary" "$HOME/code"
external_roots=$(command jq -nc --arg alias "$HOME/code/." --arg second "$nested" '[$alias,$second]')
"$routine" config set sources.git.roots "$external_roots"
command jq -e --arg first "$primary" --arg second "$nested" '.sources.git.roots|sort==([$first,$second]|sort)' "$ROUTINE_CONFIG" >/dev/null || fail 'Config set did not preserve/canonicalize external-volume roots'
"$routine" init --non-interactive --sources-git-roots "$external_roots" >/dev/null
command jq -e --arg root "$primary" '.sources.git.roots|index($root)!=null' "$ROUTINE_CONFIG" >/dev/null || fail 'Batch init lost an external symlink root'
for blocked in "$HOME/." "$HOME/.." "$HOME/.cache" "$HOME/.omp/wt" "$HOME/Library"; do
  bad_roots=$(command jq -nc --arg root "$blocked" '[$root]')
  before=$(shasum -a 256 "$ROUTINE_CONFIG")
  if "$routine" config set sources.git.roots "$bad_roots" >/dev/null 2>&1; then fail 'Config set accepted a forbidden root'; fi
  if "$routine" init --non-interactive --sources-git-roots "$bad_roots" >/dev/null 2>&1; then fail 'Batch init accepted a forbidden root'; fi
  [[ $(shasum -a 256 "$ROUTINE_CONFIG") == "$before" ]] || fail 'Rejected root validation changed saved settings'
done
ROUTINE_SETTINGS=$(command jq --argjson roots "$external_roots" '.sources.git.roots=$roots' <<< "$ROUTINE_SETTINGS")
candidates=$(routine_git_candidates)
command jq -e --arg first "$primary" --arg second "$nested" 'index($first)!=null and index($second)!=null' <<< "$candidates" >/dev/null || fail 'Saved external roots disappeared from the candidate list'
bad_settings=$(command jq --arg root "$HOME/." '.sources.git.roots=[$root]' <<< "$ROUTINE_SETTINGS")
remaining=$(ROUTINE_SETTINGS="$bad_settings" routine_git_candidates 2> "$sandbox/rejected-root")
command jq -e --arg forbidden "$HOME" 'index($forbidden)==null' <<< "$remaining" >/dev/null || fail 'Forbidden saved root survived candidate validation'
cat "$sandbox/rejected-root"
[[ $(routine_git_root_path "$primary/.") == "$primary" ]] || fail 'Repository candidate was not physically normalized'
saved_settings=$ROUTINE_SETTINGS
ROUTINE_SETTINGS=$(command jq --arg absent "$sandbox/absent" '.sources.git.roots=[]|.sources.omp_sessions.dir=$absent|.sources.claude_sessions.dir=$absent' <<< "$ROUTINE_SETTINGS")
answers=$(printf '+%s/\n+%s/.\n+%s/..\n+%s/.cache/.\n+%s/.omp/wt/repo\n+%s/code/.\n\n' "$HOME" "$HOME" "$HOME" "$HOME" "$HOME" "$HOME")
routine_select_git_roots <<< "$answers"$'\n' > "$sandbox/root-selection"
command jq -e --arg root "$primary" '.sources.git.roots==[$root]' <<< "$ROUTINE_SETTINGS" >/dev/null || fail 'Manual root entry bypassed normalized HOME/cache boundaries'
ROUTINE_SETTINGS=$saved_settings
offline="/Volumes/RoutineFixture-${sandbox##*/}/repos"
deleted="$HOME/deleted-projects"
ROUTINE_SETTINGS=$(command jq --arg root "$offline" --arg deleted "$deleted" --arg absent "$sandbox/absent" '.sources.git.roots=[$root,$deleted]|.sources.omp_sessions.dir=$absent|.sources.claude_sessions.dir=$absent' <<< "$saved_settings")
routine_select_git_roots <<< '' > "$sandbox/offline-kept"
command jq -e --arg root "$offline" --arg deleted "$deleted" '.sources.git.roots|index($root)!=null and index($deleted)==null' <<< "$ROUTINE_SETTINGS" >/dev/null || fail 'Disconnected volume was lost or deleted local root stayed selected'
command jq -Rse --arg root "$deleted" 'contains($root+" — 경로 없음")' "$sandbox/offline-kept" >/dev/null || fail 'Deleted local root was labeled as a disconnected volume'
cat "$sandbox/offline-kept"
candidates=$(routine_git_candidates)
index=$(command jq --arg root "$offline" 'index($root)+1' <<< "$candidates")
routine_select_git_roots <<< "$index"$'\n' > "$sandbox/offline-removed"
command jq -e --arg root "$offline" '.sources.git.roots|index($root)==null' <<< "$ROUTINE_SETTINGS" >/dev/null || fail 'Disconnected root could not be explicitly deselected'
if routine_git_root_path "$HOME/.cache/disconnected" saved >/dev/null 2>&1; then fail 'Missing cached root bypassed saved-root safety'; fi
ROUTINE_SETTINGS=$saved_settings
# Both IDE/terminal defaults and a saved extension participate in focus safety.
# shellcheck source=../share/gui-guard.sh
source "$share_dir/gui-guard.sh"
for bundle in com.microsoft.VSCode com.todesktop.230313mzl4w4u com.jetbrains.intellij org.alacritty com.github.wez.wezterm net.kovidgoyal.kitty com.mitchellh.ghostty com.stablyai.orca; do
  prompt_terminal_app "$bundle" || fail 'Supported terminal bundle was treated as a browser'
done
if prompt_terminal_app com.google.Chrome; then fail 'Browser was treated as a terminal'; fi
terminal_ids=$(command jq -c '.ui.terminal_bundle_ids+["dev.fixture.terminal"]' <<< "$ROUTINE_SETTINGS")
"$routine" config set ui.terminal_bundle_ids "$terminal_ids"
routine_load_config file
prompt_terminal_app dev.fixture.terminal || fail 'Saved terminal extension was not used'
if "$routine" config set ui.terminal_bundle_ids '["not a bundle"]' >/dev/null 2>&1; then fail 'Malformed terminal bundle ID was saved'; fi
ROUTINE_SETTINGS=$saved_settings
# 2,000 logs share one header cwd. Message bodies and old files must not widen
# discovery, and git must be queried once, before proposing a unique root.
cat > "$sandbox/stubs/head" <<'STUB'
#!/bin/bash
printf 'header\n' >> "$RECORD.headers"
exec /usr/bin/head "$@"
STUB
chmod +x "$sandbox/stubs/head"
header=$(jq -nc --arg cwd "$session_repo/subdir" '{type:"session",cwd:$cwd}')
alias_header=$(jq -nc --arg cwd "$session_repo/subdir/." '{type:"session",cwd:$cwd}')
body=$(jq -nc --arg cwd "$extra" '{type:"assistant",cwd:$cwd,message:{content:"not a session header"}}')
for ((i=0;i<2000;i++)); do
  if ((i%2)); then first=$alias_header; else first=$header; fi
  printf '%s\n%s\n' "$first" "$body" > "$HOME/.omp/agent/sessions/many-$i.jsonl"
done
touch -t 202001010000 "$HOME/.claude/projects/example/"*.jsonl "$HOME/.omp/agent/sessions/one.jsonl" "$HOME/.omp/agent/sessions/external.jsonl"
: > "$RECORD.headers"; : > "$RECORD.git-discovery"; start=$(date +%s)
candidates=$(routine_git_candidates); elapsed=$(($(date +%s)-start))
command jq -e --arg required "${session_repo%/*}" --arg excluded "${extra%/*}" --arg old "${claude_repo%/*}" 'index($required)!=null and index($excluded)==null and index($old)==null' <<< "$candidates" >/dev/null || fail 'Bounded discovery read bodies or old session files'
command jq -Rse 'split("\n")|map(select(length>0))|length==300' "$RECORD.headers" >/dev/null || fail 'Recent session-file bound is not 300'
command jq -Rse 'split("\n")|map(select(length>0))|length==1' "$RECORD.git-discovery" >/dev/null || fail 'Duplicate session cwd triggered repeated git lookups'
((elapsed<8)) || fail "2,000-file discovery exceeded seconds-scale budget: $elapsed"
printf 'Synthetic session discovery: 2000 files, 300 headers, 1 git lookup, %ss\n' "$elapsed"
# A timeout or parser failure falls back to normal/configured candidates without
# aborting init under set -e.
rm "$sandbox/stubs/gtimeout"
cat > "$sandbox/stubs/gtimeout" <<'STUB'
#!/bin/bash
exit 124
STUB
chmod +x "$sandbox/stubs/gtimeout"
candidates=$(routine_git_candidates)
command jq -e --arg configured "$primary" --arg standard "$HOME/dev" --arg session "${session_repo%/*}" 'index($configured)!=null and index($standard)!=null and index($session)==null' <<< "$candidates" >/dev/null || fail 'Discovery timeout lost configured/default candidates'
cat > "$sandbox/stubs/gtimeout" <<'STUB'
#!/bin/bash
shift 3
[[ $1 != find ]] || exit 124
exec "$@"
STUB
ROUTINE_GIT_ROOTS=$(command jq -nc --arg root "$primary" '[$root]') "$routine" collect --sources git --out "$sandbox/scan-timeout" >/dev/null || true
command jq -e --arg root "$primary" 'any(.errors[];.source=="git" and (.message|contains($root)) and (.message|contains("timed out"))) and all(.errors[];.message!="")' "$sandbox/scan-timeout/2026-09-28.json" >/dev/null || fail 'Timed-out Git scan produced an empty error'
rm "$sandbox/stubs/gtimeout"; ln -s "$real_timeout" "$sandbox/stubs/gtimeout"
# Source commands persist only explicit changes; unavailable enable does not rewrite config.
before=$(shasum -a 256 "$ROUTINE_CONFIG")
if "$routine" sources enable prs > "$sandbox/unavailable" 2>&1; then fail 'Unavailable PR source enabled'; fi
[[ $(shasum -a 256 "$ROUTINE_CONFIG") == "$before" ]] || fail 'Rejected source enable changed config'
GH_AVAILABLE=1 "$routine" sources enable prs
ROUTINE_PRS_ENABLED=true "$routine" sources disable prs
jq -e '.sources.prs.enabled==false' "$ROUTINE_CONFIG" >/dev/null || fail 'Transient source override leaked into persistence'
"$routine" sources enable claude_sessions
jq -e '.sources.claude_sessions.enabled' "$ROUTINE_CONFIG" >/dev/null || fail 'Available session source could not be enabled'
if "$routine" sources enable slack > /dev/null 2>&1; then fail 'Clipboard mode enabled the Orca-only source'; fi
# Slack alone cannot feed the unattended collect step: disabling the last other source is refused,
# and a hand-edited Slack-only config fails before collect with a clear message.
only_slack=$(jq '.sources|=with_entries(.value.enabled=(.key=="slack")) | .delivery.mode="gui-paste" | .identity.slack_display_name="테스트" | .slack.channel_name="daily" | .slack.post_title="스크럼"' "$ROUTINE_CONFIG")
printf '%s\n' "$only_slack" > "$sandbox/slack-only.json"
if ROUTINE_CONFIG="$sandbox/slack-only.json" "$routine" collect --out "$sandbox/slack-only-out" > "$sandbox/slack-only.log" 2>&1; then fail 'Slack-only config reached collect'; fi
grep -q 'Slack 외 수집 소스 최소 1개' "$sandbox/slack-only.log" || fail 'Slack-only config error was not explained'
for name in git prs omp_sessions jira notion; do "$routine" sources disable "$name" >/dev/null 2>&1 || true; done
before=$(shasum -a 256 "$ROUTINE_CONFIG")
if "$routine" sources disable claude_sessions > "$sandbox/last-source" 2>&1; then fail 'Disabled the last non-Slack source'; fi
[[ $(shasum -a 256 "$ROUTINE_CONFIG") == "$before" ]] || fail 'Rejected last-source disable changed config'
"$routine" sources enable git >/dev/null 2>&1 || true
# Rendering modes alter visible suffixes, never evidence downgrade/questions or held notes.
jq -n '{git:[],prs:[{url:"https://example/pull/1",state:"MERGED",in_window:true,activity:[{kind:"merged",at:"2026-09-25T00:00:00Z"}],title:"응답 정리"}],sessions:[],slack:[],jira:[]}' > "$sandbox/evidence.json"
jq -n '{items:[{section:"yesterday",path:["개발","정산"],topic:"정산 개선",level:"verified",evidence:["session:missing"],held_ref:0},{section:"yesterday",path:["개발","응답"],topic:"응답 정리",level:"merged",evidence:["pr:https://example/pull/1"]}]}' > "$sandbox/model.json"
for mode in none uncertain all; do
  settings=$(command jq -L "$share_dir" -nc --arg mode "$mode" 'include "config"; defaults("/fixture";"fixture")|.draft.markers=$mode')
  command jq -L "$share_dir" --argjson routine "$settings" --slurpfile source "$sandbox/evidence.json" 'include "scrum"; validate_draft($source[0];{held:["정산"],today:[]})' "$sandbox/model.json" > "$sandbox/$mode.json"
  command jq -L "$share_dir" -r --argjson routine "$settings" 'include "scrum"; render_text' "$sandbox/$mode.json" > "$sandbox/$mode.txt"
  command jq -L "$share_dir" -r --argjson routine "$settings" 'include "scrum"; render_html' "$sandbox/$mode.json" > "$sandbox/$mode.html"
  case $mode in none) held='정산 개선 (보류)'; merged='응답 정리' ;; uncertain) held='정산 개선 (확인 필요, 보류)'; merged='응답 정리' ;; all) held='정산 개선 (검토, 확인 필요, 보류)'; merged='응답 정리 (병합)' ;; esac
  jq -e --arg held "$held" --arg merged "$merged" '.items[0].level=="request" and .items[0].text==$held and .items[1].level=="merged" and .items[1].text==$merged and any(.questions[];contains("존재하지 않는 근거")) and .yesterday[0].label=="개발"' "$sandbox/$mode.json" >/dev/null || fail "Marker validation drifted: $mode"
  if ! grep -Fq "<li>$held</li>" "$sandbox/$mode.html" || ! grep -Fq "<li>$merged</li>" "$sandbox/$mode.html"; then fail "HTML marker mode failed: $mode"; fi
  if ! grep -q '^• 개발$' "$sandbox/$mode.txt" || ! grep -Fq "$held" "$sandbox/$mode.txt"; then fail "Empty project added a blank level: $mode"; fi
done
jq -se 'map({levels:[.items[].level],questions}) as $states | all($states[];.==$states[0])' "$sandbox/none.json" "$sandbox/uncertain.json" "$sandbox/all.json" >/dev/null || fail 'Marker modes changed internal levels/questions'
settings=$(command jq -L "$share_dir" -nc 'include "config"; defaults("/fixture";"fixture")|.draft.project="예제 프로젝트"')
command jq -L "$share_dir" --argjson routine "$settings" --slurpfile source "$sandbox/evidence.json" 'include "scrum"; validate_draft($source[0];{held:["정산"],today:[]})|{html:render_html,text:([render_text]|join("\n"))}' "$sandbox/model.json" > "$sandbox/project.json"
jq -e '.html|contains("<li>예제 프로젝트<ul><li>개발<ul>")' "$sandbox/project.json" >/dev/null || fail 'Explicit project lost its HTML hierarchy'
jq -e '.text|contains("• 예제 프로젝트\n  ◦ 개발") and (contains("(병합)")|not)' "$sandbox/project.json" >/dev/null || fail 'Explicit project/default marker rendering drifted'
"$routine" status > "$sandbox/status"
grep -q '수집 기간: 2026-09-24T15:00:00Z ~ 2026-09-27T15:00:00Z' "$sandbox/status" || fail 'Status did not show the actual collection window'
! grep -q '^forbidden ' "$RECORD" 2>/dev/null || fail 'Onboarding scenarios reached a GUI or model command'
echo 'PASS: 격리된 Git 다중 위치·소스 상태/설정·로컬 자정 기간·프로젝트/표지 렌더'
