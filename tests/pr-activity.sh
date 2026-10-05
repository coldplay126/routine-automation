#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
real_jq=${TEST_JQ_BIN:-$(type -P jq)}
real_timeout=$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin builtin type -P gtimeout || PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin builtin type -P timeout)
while IFS= read -r name; do [[ $name != ROUTINE_* ]] || unset "$name"; done < <(compgen -v)
sandbox=$(mktemp -d /tmp/routine-pr-activity.XXXXXXXX)
trap 'rm -rf -- "$sandbox"' EXIT
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" PATH="$sandbox/stubs:/usr/bin:/bin" USER=fixture
export ROUTINE_CONFIG="$HOME/.config/routine-automation/config.json" ROUTINE_ORCA_APP_CLI=/nonexistent/orca
export PR_CLOCK="$sandbox/clock"
export PR_CANDIDATES="$sandbox/candidates.json" PR_DETAILS="$sandbox/details.json" PR_CALLS="$sandbox/views" MODEL_INPUT="$sandbox/prompt"
mkdir -p "$HOME/.local/bin" "$TMPDIR" "$sandbox/stubs"
ln -s "$real_jq" "$sandbox/stubs/jq"; ln -s "$real_timeout" "$sandbox/stubs/gtimeout"
ln -s "$sandbox/stubs/jq" "$HOME/.local/bin/jq"
ln -s "$sandbox/stubs/gtimeout" "$HOME/.local/bin/gtimeout"
for cmd in gh omp claude open orca brew launchctl osascript; do
  printf '#!/bin/sh\nexit 87\n' > "$sandbox/stubs/$cmd"; chmod +x "$sandbox/stubs/$cmd"
  ln -s "$sandbox/stubs/$cmd" "$HOME/.local/bin/$cmd"
done
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
cat > "$sandbox/stubs/gh" <<'GH'
#!/bin/bash
case "$1 ${2:-}" in
  'api user') [[ ${GH_IDENTITY_FAIL:-0} != 1 ]] || exit 1; echo '{"id":42,"login":"fixture"}' ;;
  'search prs')
    if [[ -n ${PR_ROLE_RESULTS:-} ]]; then
      role=commenter
      [[ " $* " != *' --author=@me '* ]] || role=author
      [[ " $* " != *' --reviewed-by=@me '* ]] || role=reviewed-by
      cat "$PR_ROLE_RESULTS/$role.json"
    else cat "$PR_CANDIDATES"; fi ;;
  'pr view')
    number=${3##*/}; printf '%s\n' "$number" >> "$PR_CALLS"
    [[ ${PR_DEADLINE_TEST:-0} != 1 ]] || echo 1120 > "$PR_CLOCK"
    [[ $number != 6 ]] || exit 1
    jq --arg key "$number" --arg field "${PR_SATURATED_FIELD:-}" '
      (.[$key] // {state:"OPEN",title:"Older open PR",baseRefName:"main",author:{login:"fixture"},createdAt:"2026-08-01T00:00:00Z",mergedAt:null,closedAt:null,commits:[],reviews:[],comments:[]}) |
      if $field!="" and ($key=="1" or $key=="2") then
        .[$field]=[range(0;100)|if $field=="commits" then {authoredDate:"2026-08-01T00:00:00Z",authors:[{login:"other"}]}
          elif $field=="reviews" then {submittedAt:"2026-08-01T00:00:00Z",author:{login:"other"}}
          else {createdAt:"2026-08-01T00:00:00Z",author:{login:"other"}} end]
      else . end' "$PR_DETAILS" ;;
  *) exit 87 ;;
esac
GH
cat > "$sandbox/stubs/omp" <<'OMP'
#!/bin/bash
cat > "$MODEL_INPUT"
printf '%s\n' '{"items":[{"section":"yesterday","path":["개발","지난 작업"],"topic":"오래된 PR 작업","level":"work","evidence":["pr:https://example/pull/1"]},{"section":"today","path":["개발","열린 작업"],"topic":"오래된 PR 이어가기","level":"work","evidence":["pr:https://example/pull/1"]}]}'
OMP
jq -n '[range(1;12)|{repository:{nameWithOwner:"fixture/repo"},number:.,title:("PR "+tostring),state:"OPEN",createdAt:"2026-08-01T00:00:00Z",updatedAt:"2026-09-20T00:00:00Z",url:("https://example/pull/"+tostring)}]' > "$PR_CANDIDATES"
jq -n '
  def base: {state:"OPEN",title:"Historical PR",baseRefName:"main",author:{login:"fixture"},createdAt:"2026-08-01T00:00:00Z",mergedAt:null,closedAt:null,commits:[],reviews:[],comments:[]};
  {"1":base,
   "2":(base + {author:{login:"other"},commits:[{authoredDate:"2026-09-03T00:00:00Z",authors:[{login:"FiXtUrE"}]}],reviews:[{submittedAt:"2026-09-04T00:00:00Z",author:{login:"fixture"}},{submittedAt:"2026-09-06T00:00:00Z",author:{login:"other"}}],comments:[{createdAt:"2026-09-01T00:00:00Z",author:{login:"fixture"}},{createdAt:"2026-09-08T00:00:00Z",author:{login:"fixture"}}]}),
   "3":(base + {state:"MERGED",mergedBy:{login:"fixture"},mergedAt:"2026-09-05T00:00:00Z",closedAt:"2026-09-05T00:00:00Z"}),
   "4":(base + {createdAt:"2026-09-08T00:00:00Z"}),
   "5":(base + {state:"CLOSED",author:{login:"other"},closedAt:"2026-09-04T00:00:00Z",reviews:[{submittedAt:"2026-09-04T00:00:00Z",author:{login:"other"}}],comments:[{createdAt:"2026-09-04T00:00:00Z",author:{login:"other"}}]}),
   "7":(base + {createdAt:"invalid"}),
   "8":(base + {state:"MERGED",mergedBy:{login:"fixture"},mergedAt:"2026-09-20T00:00:00Z",closedAt:"2026-09-20T00:00:00Z",reviews:[{submittedAt:"2026-09-04T00:00:00Z",author:{login:"fixture"}}]}),
   "9":(base + {state:"CLOSED",closedAt:"2026-09-03T00:00:00Z",comments:[{createdAt:"2026-09-03T00:00:00Z",author:{login:"stale-bot"}}]}),
   "10":(base + {state:"MERGED",mergedBy:{login:"other"},mergedAt:"2026-09-04T00:00:00Z"}),
   "11":(base + {state:"MERGED",mergedBy:{login:"other"},mergedAt:"2026-09-04T00:00:00Z",reviews:[{submittedAt:"2026-09-03T00:00:00Z",author:{login:"fixture"}}]})}
' > "$PR_DETAILS"
routine="$repo/bin/routine"
"$routine" init --non-interactive --slack-link https://example.slack.com/archives/CEXAMPLE/p1790895609247049 --slack-team-id TEXAMPLE --sources-git-enabled false --sources-prs-enabled true --draft-llm-engine none --timezone UTC >/dev/null
out="$sandbox/out"
"$routine" collect --sources prs --since 2026-09-01 --until 2026-09-08 --out "$out"
result="$out/2026-09-08.json"
jq -e '(.errors|map(.message)) as $errors | (.prs|map(select(.in_window==true)|.number)|sort)==[2,3,8,11] and (.prs|map(select(.in_window==false)|.number)|sort)==[1,4,5,9,10] and (.prs|map(select(.in_window=="unknown")|.number)|sort)==[6,7] and all([6,7][];. as $number|any($errors[];contains("https://example/pull/"+($number|tostring))))' "$result" >/dev/null || fail 'Historical activity, stale closure or per-PR unknown error attribution failed'
jq -e '.prs[]|select(.number==2)|(.activity|map(.kind)|sort)==["comment","commit","review"] and all(.activity[];.at>="2026-09-01T00:00:00Z" and .at<"2026-09-08T00:00:00Z")' "$result" >/dev/null || fail 'Personal authorship or inclusive/exclusive activity boundary failed'
jq -L "$repo/share" -ne 'include "scrum"; {state:"CLOSED",author:{login:"fixture"},createdAt:"2026-09-01T00:00:00Z",mergedAt:null,closedAt:"2026-09-02T00:00:00Z",commits:[],reviews:[],comments:[]} | pr_activity("fixture";"2026-09-01T00:00:00Z";"2026-09-08T00:00:00Z") == [{kind:"created",at:"2026-09-01T00:00:00Z"}]' >/dev/null || fail 'Creation or unattributed closure activity was misclassified'
"$routine" draft --date 2026-09-08 --out "$out" --no-llm
jq -e '(.items|map(select(.section=="yesterday")|.evidence[0])|sort)==["pr:https://example/pull/11","pr:https://example/pull/2","pr:https://example/pull/3","pr:https://example/pull/8"] and any(.items[];.section=="today" and .evidence==["pr:https://example/pull/1"]) and any(.items[];.evidence==["pr:https://example/pull/11"] and .level=="merged") and all(.items[];if .evidence==["pr:https://example/pull/8"] then .level=="work" else true end)' "$out/2026-09-08.draft.json" >/dev/null || fail 'Current state contaminated yesterday or personal review plus another merger lost its result'
"$routine" draft --date 2026-09-08 --out "$out" --engine omp
jq -Rse 'capture("ROUTINE_DATA_BEGIN\n(?<data>[\\s\\S]*?)\nROUTINE_DATA_END").data|fromjson|(.evidence.prs|map(.number)|sort)==[2,3,8,11] and any(.current_prs[];.number==1 and .in_window==false)' "$MODEL_INPUT" >/dev/null || fail 'LLM yesterday evidence was not separated from current OPEN plans'
# A yesterday item citing only an out-of-window PR must leave the deliverable draft (text and tree)
# and survive only as a question; the OPEN PR keeps its today plan.
jq -e 'all(.items[];.topic!="오래된 PR 작업") and any(.items[];.section=="today" and .topic=="오래된 PR 이어가기") and any(.questions[];contains("오래된 PR 작업") and contains("초안에서 제외"))' "$out/2026-09-08.draft.json" >/dev/null || fail 'Out-of-window-only item stayed in the draft or lost its question'
! grep -q '오래된 PR 작업' "$out/2026-09-08.draft.txt" "$out/2026-09-08.draft.html" || fail 'Out-of-window-only item rendered in deliverable draft'
grep -q '오래된 PR 작업' "$out/2026-09-08.draft.questions.md" || fail 'Dropped item missing from questions'
GH_IDENTITY_FAIL=1 "$routine" collect --sources prs --since 2026-09-01 --until 2026-09-08 --out "$sandbox/no-identity"
jq -e 'all(.prs[];.in_window=="unknown") and any(.errors[];.source=="prs")' "$sandbox/no-identity/2026-09-08.json" >/dev/null || fail 'Missing identity became known personal activity'
for field in commits reviews comments; do
  PR_SATURATED_FIELD="$field" "$routine" collect --sources prs --since 2026-09-01 --until 2026-09-08 --out "$sandbox/saturated-$field"
  saturated="$sandbox/saturated-$field/2026-09-08.json"
  expected=false; [[ $field != commits ]] || expected=unknown
  jq -e --arg expected "$expected" 'any(.prs[];.number==1 and .in_window==(if $expected=="unknown" then "unknown" else false end)) and any(.prs[];.number==2 and .in_window==true) and (if $expected=="unknown" then any(.errors[];.source=="prs" and (.message|contains("https://example/pull/1"))) else all(.errors[];.message|contains("https://example/pull/1")|not) end)' "$saturated" >/dev/null || fail "Commit export cap or paginated $field was misclassified"
  "$routine" draft --date 2026-09-08 --out "$sandbox/saturated-$field" --no-llm
  jq -e 'all(.items[];if .evidence==["pr:https://example/pull/1"] then .section=="today" else true end) and any(.items[];.section=="today" and .evidence==["pr:https://example/pull/1"])' "$sandbox/saturated-$field/2026-09-08.draft.json" >/dev/null || fail 'Saturated unknown PR contaminated yesterday or lost its OPEN plan'
done
# A large bot response crosses macOS ARG_MAX; it must stay out of argv.
cp "$PR_DETAILS" "$sandbox/details-original"
jq '."1".createdAt="2026-09-03T00:00:00Z"|."1".comments=[range(0;25)|{createdAt:"2026-08-01T00:00:00Z",author:{login:"bot"},body:("x"*48000)}]' "$sandbox/details-original" > "$PR_DETAILS"
"$routine" collect --sources prs --since 2026-09-01 --until 2026-09-08 --out "$sandbox/large"
jq -e 'any(.prs[];.number==1 and .in_window==true) and all(.errors[];.message|contains("https://example/pull/1")|not)' "$sandbox/large/2026-09-08.json" >/dev/null || fail '1.2MB PR response disappeared or became unknown'
cp "$sandbox/details-original" "$PR_DETAILS"
mkdir "$sandbox/legacy"
jq '.prs |= map(del(.in_window))' "$result" > "$sandbox/legacy/2026-09-08.json"
"$routine" draft --date 2026-09-08 --out "$sandbox/legacy" --no-llm
jq -e 'all(.items[];.section!="yesterday") and any(.questions[];contains("routine collect") and contains("https://example/pull/1"))' "$sandbox/legacy/2026-09-08.draft.json" >/dev/null || fail 'Legacy PR evidence omitted recollection guidance'
# Move the clock to the stage deadline after the first view; remaining rows
# must be retained as unknown without issuing more network calls.
cat > "$sandbox/stubs/date" <<'DATE'
#!/bin/bash
if [[ ${PR_DEADLINE_TEST:-0} == 1 && $# == 1 && $1 == +%s ]]; then cat "$PR_CLOCK"; else exec /bin/date "$@"; fi
DATE
chmod +x "$sandbox/stubs/date"; echo 1000 > "$PR_CLOCK"; : > "$PR_CALLS"
ln -s "$sandbox/stubs/date" "$HOME/.local/bin/date"
PR_DEADLINE_TEST=1 "$routine" collect --sources prs --since 2026-09-01 --until 2026-09-08 --out "$sandbox/deadline"
jq -e '(.prs|length)==11 and any(.prs[];.in_window=="unknown") and any(.errors[];.source=="prs" and (.message|contains("deadline")))' "$sandbox/deadline/2026-09-08.json" >/dev/null || fail 'Stage deadline discarded candidates or omitted its error'
jq -Rse 'split("\n")|map(select(length>0))|length==1' "$PR_CALLS" >/dev/null || fail 'PR network calls continued past the 120-second stage deadline'
mkdir "$sandbox/role-results"
jq -n '[range(1;4)|{number:.,title:"My PR",state:"OPEN",createdAt:(if .==1 then "2026-09-03T00:00:00Z" else "2026-08-01T00:00:00Z" end),updatedAt:"2026-09-02T00:00:00Z",url:("https://example/pull/"+tostring)}]' > "$sandbox/role-results/author.json"
jq -n '[range(100;150)|{number:.,title:"Reviewed PR",state:"OPEN",createdAt:"2026-08-01T00:00:00Z",updatedAt:"2026-09-20T00:00:00Z",url:("https://example/pull/"+tostring)}]' > "$sandbox/role-results/reviewed-by.json"
echo '[]' > "$sandbox/role-results/commenter.json"; : > "$PR_CALLS"
jq '."1".createdAt="2026-09-03T00:00:00Z"' "$sandbox/details-original" > "$PR_DETAILS"
PR_ROLE_RESULTS="$sandbox/role-results" "$routine" collect --sources prs --since 2026-09-01 --until 2026-09-08 --out "$sandbox/priority"
jq -e '. as $s | all([1,2,3][];. as $n|any($s.prs[];.number==$n)) and any(.prs[];.number==1 and .in_window==true) and (.prs|length)==50 and any(.errors[];.source=="prs")' "$sandbox/priority/2026-09-08.json" >/dev/null || fail 'Recent reviewed PRs displaced my authored candidates without a saturation warning'
jq -Rse 'split("\n")|map(select(length>0)|tonumber)|.[0]==1 and (.[0:3]|sort)==[1,2,3]' "$PR_CALLS" >/dev/null || fail 'Authored window creation did not lead the candidate priority'
jq -n '[range(1;66)|{repository:{nameWithOwner:"fixture/repo"},number:.,title:("PR "+tostring),state:"OPEN",createdAt:"2026-08-01T00:00:00Z",updatedAt:"2026-09-20T00:00:00Z",url:("https://example/pull/"+tostring)}]' > "$PR_CANDIDATES"
: > "$PR_CALLS"
"$routine" collect --sources prs --since 2026-09-01 --until 2026-09-08 --out "$sandbox/capped"
jq -Rse 'split("\n")|map(select(length>0))|length==50 and (unique|length)==50' "$PR_CALLS" >/dev/null || fail 'Candidate cap or per-PR deduplication failed'
printf 'PASS: PR personal activity window, current-state plans, unknown failures and 50-candidate bound\n'
