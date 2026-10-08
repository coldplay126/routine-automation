#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
real_jq=${TEST_JQ_BIN:-$(type -P jq)}
real_node=$(type -P node || true)
while IFS= read -r name; do [[ $name != ROUTINE_* ]] || unset "$name"; done < <(compgen -v)
sandbox=$(mktemp -d /tmp/routine-project-tests.XXXXXXXX)
trap 'rm -rf -- "$sandbox"' EXIT
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" PATH="$sandbox/stubs:/usr/bin:/bin" USER=fixture
export ROUTINE_CONFIG="$sandbox/config/config.json" ROUTINE_NOW='2026-09-28T09:00:00Z'
export MODEL_JSON="$sandbox/model.json" PROMPT="$sandbox/prompt" OMP_CALLS="$sandbox/model-calls"
mkdir -p "$HOME/.local/bin" "$TMPDIR" "$sandbox/stubs"
# shellcheck source=network.sh
source "$repo/tests/network.sh"
ln -s "$real_jq" "$sandbox/stubs/jq"
ln -s "$sandbox/stubs/jq" "$HOME/.local/bin/jq"
for cmd in gh omp claude open orca brew launchctl osascript; do
  printf '#!/bin/sh\nexit 87\n' > "$sandbox/stubs/$cmd"; chmod +x "$sandbox/stubs/$cmd"
  ln -s "$sandbox/stubs/$cmd" "$HOME/.local/bin/$cmd"
done
cat > "$sandbox/stubs/omp" <<'MODEL'
#!/bin/bash
cat > "$PROMPT"
printf 'call\n' >> "$OMP_CALLS"
cat "$MODEL_JSON"
MODEL
cat > "$sandbox/stubs/claude" <<'MODEL'
#!/bin/bash
while (($#)); do
  if [[ $1 == --json-schema ]]; then printf '%s\n' "$2" > "$SCHEMA"; shift; fi
  shift
done
cat > "$PROMPT"
printf 'call\n' >> "$OMP_CALLS"
jq -n --slurpfile model "$MODEL_JSON" '{structured_output:$model[0]}'
MODEL
export SCHEMA="$sandbox/claude-schema"
chmod +x "$sandbox/stubs/claude"
cat > "$sandbox/stubs/gtimeout" <<'TIMEOUT'
#!/bin/bash
shift 3
exec "$@"
TIMEOUT
chmod +x "$sandbox/stubs/omp" "$sandbox/stubs/gtimeout"
ln -s "$sandbox/stubs/gtimeout" "$HOME/.local/bin/gtimeout"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
routine="$repo/bin/routine"; share_dir="$repo/share"
projects='[{"label":"예제 A","owners":["alpha-org"],"keywords":["alpha","알파"]},{"label":"예제 B","owners":["beta-org"],"keywords":["beta","베타"]},{"label":"빈 프로젝트","owners":["empty-org"],"keywords":["never-match"]}]'
"$routine" init --non-interactive --slack-link https://example.slack.com/archives/CEXAMPLE/p1790895609247049 --slack-team-id TEXAMPLE --sources-git-enabled false --sources-prs-enabled false --sources-omp-sessions-enabled true --sources-claude-sessions-enabled false --draft-llm-engine none --timezone UTC --draft-projects "$projects" > /dev/null
jq -e --argjson projects "$projects" '.draft.projects==$projects and (.draft|has("project")|not)' "$ROUTINE_CONFIG" > /dev/null || fail '배열 초기화·정규형 저장'
if "$routine" config get draft.project > /dev/null 2>&1; then fail '다중 프로젝트를 단일 문자열로 조용히 축약'; fi
cp "$ROUTINE_CONFIG" "$sandbox/config-before"
for value in '[{"label":" "}]' '[{"label":"A"},{"label":"A"}]' '[{"label":"A","owners":"alpha-org"}]' '[{"label":"A","keywords":[""]}]' '[{"label":"A","owner":["alpha-org"]}]' '[{"label":"A","keyword":["alpha"]}]' '[{"label":1}]' '"A"'; do
  if "$routine" config set draft.projects "$value" > /dev/null 2>&1; then fail "잘못된 프로젝트 배열: $value"; fi
  cmp -s "$ROUTINE_CONFIG" "$sandbox/config-before" || fail '거부한 설정이 파일 변경'
done
out="$HOME/Library/Application Support/routine-automation/scrum"
mkdir -p "$out"
printf '## 오늘 추가\n- alpha 후속 검토\n- beta 후속 검토\n' > "$out/notes.md"
cat > "$out/2026-09-28.json" <<'DATA'
{"git":[{"sha":"abc123","repo":"service","owner":"ALPHA-ORG","subject":"기능 점검"}],"prs":[{"url":"https://github.com/beta-org/service/pull/1","repository":{"nameWithOwner":"beta-org/service"},"title":"저장소 검토","state":"OPEN","in_window":true,"activity":[{"kind":"created"}],"commit_oids":["private-commit-list"],"commits_complete":true}],"sessions":[{"id":"shared","latest_report":"요청: 자료 검토 부탁","reports":[]},{"id":"keyword","latest_report":"beta 운영 항목 검토 요청","reports":[]}],"errors":[]}
DATA
cat > "$MODEL_JSON" <<'MODEL'
{"items":[
 {"section":"yesterday","path":["개발","서비스"],"topic":"저장소 검토","project":"예제 A","level":"work","evidence":["pr:https://github.com/beta-org/service/pull/1"]},
 {"section":"yesterday","path":["개발","서비스"],"topic":"기능 점검","level":"work","evidence":["git:abc123"]},
 {"section":"yesterday","path":["인프라","베타 데이터 인계"],"topic":"회사 이름 없는 권한 점검","project":"예제 A","level":"request","evidence":["session:shared"]},
 {"section":"yesterday","path":["현황 파악","alpha beta 비교"],"topic":"양쪽 자료 검토","project":"예제 B","level":"request","evidence":["session:shared"]},
 {"section":"yesterday","path":["기타","자료"],"topic":"세션 분류","project":"예제 B","level":"request","evidence":["session:shared"]},
 {"section":"yesterday","path":["기타","자료"],"topic":"근거 키워드 분류","level":"request","evidence":["session:keyword"]},
 {"section":"yesterday","path":["기타","자료"],"topic":"기본 분류","level":"request","evidence":["session:shared"]},
 {"section":"yesterday","path":["개발","beta 자료"],"topic":"owner 우선 검토","project":"예제 B","level":"work","evidence":["git:abc123"]},
 {"section":"yesterday","path":["기타","자료"],"topic":"저장소 혼합 검토","project":"예제 B","level":"work","evidence":["git:abc123","pr:https://github.com/beta-org/service/pull/1"]},
 {"section":"yesterday","path":["beta 분류","자료"],"topic":"첫 경로 키워드","project":"예제 A","level":"request","evidence":["session:shared"]},
 {"section":"today","path":["개발","후속"],"topic":"alpha 후속 검토","level":"request","evidence":["note:0"]},
 {"section":"today","path":["개발","후속"],"topic":"beta 후속 검토","level":"request","evidence":["note:1"]}
]}
MODEL
settings=$(<"$ROUTINE_CONFIG")
for value in '"목록 밖"' 'false' '1' '""'; do
  jq -L "$share_dir" --argjson routine "$settings" --argjson value "$value" -e 'include "scrum"; .items[0].project=$value | draft_ok' "$MODEL_JSON" > /dev/null || fail '프로젝트 필드 오류만으로 유효 초안 전체 거부'
done
if jq -L "$share_dir" --argjson routine "$settings" -e 'include "scrum"; .items[0].project="목록 밖"|.settings={projects:[{label:"목록 밖"}]}|{settings:$ARGS.named.routine.draft,items:.items}|saved_draft_ok' "$MODEL_JSON" > /dev/null; then fail '저장 초안 허용 목록 밖 프로젝트 허용'; fi
jq -L "$share_dir" -ne 'include "scrum"; ["git@github.com:alpha-org/service.git","https://github.com/alpha-org/service.git","ssh://git@github.com/alpha-org/service.git","alpha-org/service","service"]|map(repository_owner)==["alpha-org","alpha-org","alpha-org","alpha-org",""]' > /dev/null || fail '저장소 owner 프로토콜 해석'
"$routine" draft --date 2026-09-28 --engine omp > /dev/null
jq -e '
 .items|INDEX(.topic) as $items |
 $items["저장소 검토"].project=="예제 B" and $items["기능 점검"].project=="예제 A" and
 $items["회사 이름 없는 권한 점검"].project=="예제 B" and $items["양쪽 자료 검토"].project=="예제 B" and
 $items["세션 분류"].project=="예제 B" and $items["근거 키워드 분류"].project=="예제 B" and
 $items["기본 분류"].project=="예제 A" and $items["owner 우선 검토"].project=="예제 A" and
 $items["저장소 혼합 검토"].project=="예제 B" and $items["첫 경로 키워드"].project=="예제 B"
' "$out/2026-09-28.draft.json" > /dev/null || fail 'owner > 모든 path/근거 keywords > LLM > 첫 프로젝트'
jq -e '
 [.yesterday[].label]==["예제 A","예제 B"] and [.today[].label]==["예제 A","예제 B"] and
 (.questions|index("회사 이름 없는 권한 점검: 프로젝트 판정 충돌(예제 B vs 예제 A)"))!=null and
 (.questions|index("저장소 검토: 프로젝트 판정 충돌(예제 B vs 예제 A)"))!=null and
 (.questions|index("owner 우선 검토: 프로젝트 판정 충돌(예제 A vs 예제 B)"))!=null and
 any(.questions[];startswith("양쪽 자료 검토: 프로젝트 판정 모호(키워드:")) and
 any(.questions[];startswith("저장소 혼합 검토: 프로젝트 판정 모호(저장소:"))
' "$out/2026-09-28.draft.json" > /dev/null || fail '결정적 충돌·모호 질문·순서·빈 프로젝트 제외'
jq -Rse 'split("\nROUTINE_DATA_BEGIN\n") as $blocks | ($blocks[0]|contains("[\"예제 A\",\"예제 B\",\"빈 프로젝트\"]")) and ($blocks[1]|split("\nROUTINE_DATA_END\n")[0]|fromjson|.evidence.prs[0]|has("commit_oids") or has("commits_complete")|not)' "$PROMPT" > /dev/null || fail '프로젝트 라벨 프롬프트·commit_oids 미전달'
for layout in tree flat; do
  "$routine" config set draft.format.layout "\"$layout\"" > /dev/null
  "$routine" draft --date 2026-09-28 --engine omp > /dev/null
  html=$("$routine" review --date 2026-09-28 --no-open)
  jq -Rse 'contains("<li>프로젝트 판정 충돌(예제 B vs 예제 A)</li>") and contains("<li>프로젝트 판정 모호(키워드:") and contains("<span class=\"badge attention\">확인 필요</span>")' "$html" > /dev/null || fail "검토 HTML 카드에서 프로젝트 충돌·모호 이유/표지 누락: $layout"
  if [[ -n $real_node ]]; then "$real_node" "$repo/tests/review-render.cjs" "$html" "$out/2026-09-28.draft.txt" "$out/2026-09-28.draft.html"; fi
  jq -Rse 'contains("• 예제 A") and contains("• 예제 B") and (contains("• 빈 프로젝트")|not)' "$out/2026-09-28.draft.txt" > /dev/null || fail "텍스트 프로젝트 루트: $layout"
  jq '.items|=map(.reasons=[])' "$out/2026-09-28.draft.json" > "$sandbox/legacy-reasons.json"
  cp "$sandbox/legacy-reasons.json" "$out/2026-09-28.draft.json"
  html=$("$routine" review --date 2026-09-28 --no-open)
  jq -Rse 'contains("<summary>수집·초안 안내</summary>") and contains("<li>회사 이름 없는 권한 점검: 프로젝트 판정 충돌(예제 B vs 예제 A)</li>") and contains("양쪽 자료 검토: 프로젝트 판정 모호(키워드:")' "$html" > /dev/null || fail "이전 빈 reasons 초안의 전역 프로젝트 질문 복원: $layout"
  jq 'del(.excluded_items)' "$out/2026-09-28.draft.json" > "$sandbox/legacy-reasons.json"
  cp "$sandbox/legacy-reasons.json" "$out/2026-09-28.draft.json"
  html=$("$routine" review --date 2026-09-28 --no-open)
  jq -Rse 'contains("<li>회사 이름 없는 권한 점검: 프로젝트 판정 충돌(예제 B vs 예제 A)</li>")' "$html" > /dev/null || fail "제외 메타 없는 이전 프로젝트 질문의 전역 안내 복원: $layout"
done
"$routine" config set draft.projects '[{"label":"이후 설정"}]' > /dev/null
html=$("$routine" review --date 2026-09-28 --no-open)
jq -Rse 'capture("<script id=\"review-data\" type=\"application/json\">(?<data>[^\\n]+)</script>").data|fromjson|.settings.projects|map(.label)==["예제 A","예제 B","빈 프로젝트"]' "$html" > /dev/null || fail '검토 프로젝트 스냅샷 변경'
"$routine" style preview --date 2026-09-28 > "$sandbox/snapshot-preview"
jq -Rse 'contains("• 예제 A") and contains("• 예제 B") and (contains("이후 설정")|not)' "$sandbox/snapshot-preview" > /dev/null || fail '형식 미리보기 프로젝트 스냅샷 변경'
"$routine" config set draft.projects "$projects" > /dev/null
"$routine" config set draft.format.layout '"tree"' > /dev/null
jq '.items[0].project="목록 밖"' "$MODEL_JSON" > "$sandbox/invalid-model.json"
mv "$MODEL_JSON" "$sandbox/valid-model.json"; mv "$sandbox/invalid-model.json" "$MODEL_JSON"
: > "$OMP_CALLS"
"$routine" draft --date 2026-09-28 --engine omp > /dev/null
[[ $(wc -l < "$OMP_CALLS" | tr -d ' ') == 1 ]] || fail '프로젝트 필드 오류만으로 초안 재호출'
jq -e 'all(.items[];.project=="예제 A" or .project=="예제 B") and any(.items[];.topic=="저장소 검토" and .project=="예제 B" and any(.reasons[];contains("프로젝트 라벨 확인 필요"))) and any(.questions[];contains("프로젝트 라벨 확인 필요"))' "$out/2026-09-28.draft.json" > /dev/null || fail '잘못된 프로젝트만 제거·owner 유지·확인 질문'
"$routine" draft --date 2026-09-28 --engine claude > /dev/null
jq -e '.properties.items.items.properties.project.enum==["예제 A","예제 B","빈 프로젝트",null]' "$SCHEMA" > /dev/null || fail 'Claude 설정 라벨 스키마'
"$routine" config set draft.projects '[]' > /dev/null
"$routine" draft --date 2026-09-28 --engine claude > /dev/null
jq -e '.properties.items.items.properties.project.enum==[null]' "$SCHEMA" > /dev/null || fail '프로젝트 없는 Claude 스키마'
jq -e 'all(.items[];.project==null) and any(.questions[];contains("프로젝트 라벨 확인 필요")) and (.items|length)>0' "$out/2026-09-28.draft.json" > /dev/null || fail '기존 프로젝트 없는 사용자 초안 보존'
"$routine" config set draft.projects "$projects" > /dev/null
# Exercise real local Git collection; the remote is metadata only and never contacted.
mkdir -p "$sandbox/repos/local"
git -C "$sandbox/repos/local" init -q
git -C "$sandbox/repos/local" config user.name fixture
git -C "$sandbox/repos/local" config user.email fixture@example.com
git -C "$sandbox/repos/local" remote add origin git@github.com:beta-org/worker.git
printf 'fixture\n' > "$sandbox/repos/local/file"
git -C "$sandbox/repos/local" add file
GIT_AUTHOR_DATE='2026-09-25T10:00:00Z' GIT_COMMITTER_DATE='2026-09-25T10:00:00Z' git -C "$sandbox/repos/local" commit -qm '저장소 점검'
"$routine" config set sources.git.roots "$(jq -nc --arg root "$sandbox/repos" '[$root]')" > /dev/null
"$routine" config set identity.git_authors '["fixture@example.com"]' > /dev/null
"$routine" config set sources.git.enabled true > /dev/null
"$routine" collect --sources git --since 2026-09-25T00:00:00Z --until 2026-09-26T00:00:00Z --out "$sandbox/git-out" > /dev/null
git_day=2026-09-26 # Explicit until determines the collector filename.
jq -e '(.git|length)==1 and .git[0].owner=="beta-org" and .git[0].repo=="worker"' "$sandbox/git-out/$git_day.json" > /dev/null || fail '실제 collector owner 저장'
"$routine" draft --date "$git_day" --out "$sandbox/git-out" --no-llm > /dev/null
jq -e '[.yesterday[].label]==["예제 B"] and .items[0].project=="예제 B"' "$sandbox/git-out/$git_day.draft.json" > /dev/null || fail '모델 없는 Git owner 분류'
# Legacy files migrate in memory only; explicit saves persist only the new array.
jq 'del(.draft.projects)|.draft.project="이전 프로젝트"' "$ROUTINE_CONFIG" > "$sandbox/legacy.json"
cp "$sandbox/legacy.json" "$ROUTINE_CONFIG"
[[ $("$routine" config get draft.project) == '이전 프로젝트' ]] || fail '이전 문자열 설정 읽기'
cmp -s "$ROUTINE_CONFIG" "$sandbox/legacy.json" || fail '읽기 중 설정 파일 변경'
"$routine" config set draft.headers.today '"오늘 계획"' > /dev/null
jq -e '.draft.projects==[{label:"이전 프로젝트",owners:[],keywords:[]}] and (.draft|has("project")|not)' "$ROUTINE_CONFIG" > /dev/null || fail '이전 문자열 정규형 저장'
"$routine" draft --date "$git_day" --out "$sandbox/git-out" --no-llm > /dev/null
jq -e '[.yesterday[].label]==["이전 프로젝트"]' "$sandbox/git-out/$git_day.draft.json" > /dev/null || fail '단일 문자열 동일 계층'
"$routine" config set draft.project '""' > /dev/null
"$routine" draft --date "$git_day" --out "$sandbox/git-out" --no-llm > /dev/null
jq -e '.settings.projects==[] and [.yesterday[].label]==["개발"]' "$sandbox/git-out/$git_day.draft.json" > /dev/null || fail '이전 빈 문자열 분류 루트'
settings=$(<"$ROUTINE_CONFIG")
jq -L "$share_dir" --argjson routine "$settings" -e 'include "scrum"; saved_draft_ok and all(.items[];.project==null)' "$sandbox/git-out/$git_day.draft.json" > /dev/null || fail '프로젝트 없는 저장 초안 스키마'
printf 'PASS: 다중 프로젝트 owner/모든 경로 keywords/LLM/기본 순서·충돌/모호 질문·라벨 검증·실제 Git 수집·tree/flat JS 복사·이전 설정 이관\n'
