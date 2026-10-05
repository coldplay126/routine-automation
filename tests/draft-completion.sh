#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
real_jq=${TEST_JQ_BIN:-$(type -P jq)}
while IFS= read -r name; do [[ $name != ROUTINE_* ]] || unset "$name"; done < <(compgen -v)
sandbox=$(mktemp -d /tmp/routine-draft-completion.XXXXXXXX)
trap 'rm -rf -- "$sandbox"' EXIT
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" PATH="$sandbox/stubs:/usr/bin:/bin" USER=fixture
export ROUTINE_CONFIG="$HOME/.config/routine-automation/config.json" ROUTINE_ORCA_APP_CLI=/nonexistent/orca
export MODEL_JSON="$sandbox/model.json"
mkdir -p "$HOME/.local/bin" "$TMPDIR" "$sandbox/stubs" "$sandbox/out"
ln -s "$real_jq" "$sandbox/stubs/jq"
ln -s "$sandbox/stubs/jq" "$HOME/.local/bin/jq"
for cmd in gh omp claude open orca brew launchctl osascript; do
  printf '#!/bin/sh\nexit 87\n' > "$sandbox/stubs/$cmd"; chmod +x "$sandbox/stubs/$cmd"
  ln -s "$sandbox/stubs/$cmd" "$HOME/.local/bin/$cmd"
done
cat > "$sandbox/stubs/omp" <<'OMP'
#!/bin/bash
cat > /dev/null
cat "$MODEL_JSON"
OMP
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
routine="$repo/bin/routine"
"$routine" init --non-interactive --slack-link https://example.slack.com/archives/CEXAMPLE/p1790895609247049 --slack-team-id TEXAMPLE --sources-git-enabled false --draft-llm-engine none --timezone UTC > /dev/null
out="$sandbox/out"
# Exact source2 fixture from ClosureReview's 19-item c9d17f4 --no-llm probe.
cat > "$out/2026-09-08.json" <<'JSON'
{"version":1,"window":{"since":"2026-09-01T00:00:00Z","until":"2026-09-08T00:00:00Z"},"git":[
{"sha":"aaa111","repo":"svc","subject":"fix: 로그인 버그 해결"},
{"sha":"bbb222","repo":"svc","subject":"Merge pull request #12 from org/feature-x"},
{"sha":"ccc333","repo":"svc","subject":"feat: membership 화면 개발"},
{"sha":"ddd444","repo":"svc","subject":"chore: 리뷰 코멘트 반영"},
{"sha":"eee555","repo":"svc","subject":"feat: Product 목록 API 추가"},
{"sha":"fff666","repo":"svc","subject":"feat: 결제 API 추가"},
{"sha":"ggg777","repo":"deploy-scripts","subject":"feat: 스크립트 옵션 추가"},
{"sha":"hhh888","repo":"infra-prod","subject":"chore: 노드 그룹 조정"}],
"prs":[
{"url":"https://example/pull/1","title":"결제 API 머지","state":"MERGED","current":{"state":"MERGED"},"in_window":true,"activity":[{"kind":"merged","at":"2026-09-02T00:00:00Z"}]},
{"url":"https://example/pull/2","title":"Release v1.2 준비","state":"OPEN","current":{"state":"OPEN"},"in_window":true,"activity":[{"kind":"review","at":"2026-09-02T00:00:00Z"}]},
{"url":"https://example/pull/3","title":"prod 설정 적용","state":"OPEN","current":{"state":"OPEN"},"in_window":false,"activity":[]},
{"url":"https://example/pull/4","title":"merge conflict 해결","state":"OPEN","current":{"state":"OPEN"},"in_window":false,"activity":[]}],
"sessions":[{"id":"s1","source":"omp","title":"결제 배포","latest_report":"운영 배포 완료했습니다","reports":[{"text":"결제 API 운영 배포 완료했습니다"},{"text":"결제 API 운영 조회 결과 모두 정상"},{"text":"남은 일: 리뷰 반영 후 머지"}]}],"errors":[]}
JSON
notes="$HOME/Library/Application Support/routine-automation/scrum/notes.md"
mkdir -p "$(dirname -- "$notes")"
cat > "$notes" <<'NOTES'
## 오늘 추가
- 결제 API 리뷰 반영
- 운영 설정 적용
- 정산 배치 마무리
- 결제 API 운영 배포
NOTES
"$routine" draft --date 2026-09-08 --out "$out" --no-llm > /dev/null
result="$out/2026-09-08.draft.json"
# All 19 work/plan identities must survive; release preparation is not deployment.
# Pin the identities and merge proof rather than merely a total count.
jq -e '
  (.items|map([.section,.topic])|sort)==([
    ["yesterday","fix: 로그인 버그 해결"],
    ["yesterday","Merge pull request #12 from org/feature-x"],
    ["yesterday","feat: membership 화면 개발"],
    ["yesterday","chore: 리뷰 코멘트 반영"],
    ["yesterday","feat: Product 목록 API 추가"],
    ["yesterday","feat: 결제 API 추가"],
    ["yesterday","feat: 스크립트 옵션 추가"],
    ["yesterday","chore: 노드 그룹 조정"],
    ["yesterday","결제 API 머지"],
    ["yesterday","결제 배포"],
    ["yesterday","Release v1.2 준비"],
    ["today","Release v1.2 준비"],
    ["today","prod 설정 적용"],
    ["today","merge conflict 해결"],
    ["today","남은 일: 리뷰 반영 후 머지"],
    ["today","결제 API 리뷰 반영"],
    ["today","운영 설정 적용"],
    ["today","정산 배치 마무리"],
    ["today","결제 API 운영 배포"]]|sort) and
  any(.items[];.topic=="Merge pull request #12 from org/feature-x" and .level=="merged") and
  any(.items[];.topic=="결제 API 머지" and .level=="merged") and
  .questions==[]
' "$result" > /dev/null || fail '19-item baseline lost legitimate work/plans'
# Exercise copied titles, missing IDs, independent facts and explicit holds.
jq '.sessions += [{id:"request",source:"omp",title:"운영 요청",latest_report:"프로덕션 반영을 검토해 주세요",reports:[]}] | .prs[0].repository={nameWithOwner:"fixture/deploy-scripts"} | .git += [{sha:"explicitmerge",repo:"svc",subject:"분기 통합",merge:true},{sha:"rootclaim",repo:"운영배포완료",subject:"루트 이름 정리"}]' "$out/2026-09-08.json" > "$sandbox/source.json"
cp "$sandbox/source.json" "$out/2026-09-08.json"
cat >> "$notes" <<'NOTES'
## 보류
- 정산 배치 마무리
NOTES
cat > "$MODEL_JSON" <<'JSON'
{"items":[
{"section":"yesterday","path":["개발","결제 API"],"topic":"PR 머지","level":"work","evidence":["pr:https://example/pull/1"]},
{"section":"yesterday","path":["개발","결제 API"],"topic":"결제 API 병합 완료","level":"merged","evidence":["pr:https://example/pull/1","git:missing"]},
{"section":"yesterday","path":["개발","배포 근거"],"topic":"결제 API 운영 배포 완료","level":"work","evidence":["session:s1#0"]},
{"section":"yesterday","path":["현황 파악","결제 API"],"topic":"결제 API 정상 확인 완료","level":"verified","evidence":["session:s1#1"]},
{"section":"yesterday","path":["개발","Product API"],"topic":"membership 화면 개발","level":"work","evidence":["git:ccc333"]},
{"section":"yesterday","path":["개발","deploy-scripts"],"topic":"PR 정리","level":"work","evidence":["pr:https://example/pull/1"]},
{"section":"yesterday","path":["개발","fixture/deploy-scripts"],"topic":"검토 기록","level":"work","evidence":["pr:https://example/pull/1"]},
{"section":"yesterday","path":["개발","명시적 병합"],"topic":"병합 완료","level":"work","evidence":["git:explicitmerge"]},
{"section":"yesterday","path":["개발","운영배포완료"],"topic":"루트 이름 점검","level":"work","evidence":["git:rootclaim"]},
{"section":"yesterday","path":["개발","정산"],"topic":"마무리","level":"request","evidence":[],"held_ref":0},
{"section":"yesterday","path":["배포","잘못된 병합 배포"],"topic":"병합만으로 운영 배포 완료","level":"merged","evidence":["pr:https://example/pull/1"]},
{"section":"yesterday","path":["배포","잘못된 확인 배포"],"topic":"확인만으로 운영 배포 완료","level":"verified","evidence":["session:s1#1"]},
{"section":"yesterday","path":["배포","운영 요청"],"topic":"프로덕션 반영 완료","level":"request","evidence":["session:request"]},
{"section":"yesterday","path":["개발","ship"],"topic":"단어 경계 검사","level":"work","evidence":["git:aaa111"]},
{"section":"today","path":["릴리스 완료","릴리스"],"topic":"Release v1.2 준비","level":"work","evidence":["pr:https://example/pull/2"]},
{"section":"today","path":["개발","설정"],"topic":"prod 설정 적용","level":"work","evidence":["pr:https://example/pull/3"]},
{"section":"today","path":["개발","충돌"],"topic":"merge conflict 해결","level":"work","evidence":["pr:https://example/pull/4"]},
{"section":"today","path":["개발","리뷰"],"topic":"남은 일: 리뷰 반영 후 머지","level":"request","evidence":["session:s1#2"]},
{"section":"today","path":["개발","추가 리뷰"],"topic":"결제 API 리뷰 반영","level":"request","evidence":["note:0"]},
{"section":"today","path":["개발","추가 설정"],"topic":"운영 설정 적용","level":"request","evidence":["note:1"]},
{"section":"today","path":["개발","추가 정산"],"topic":"정산 배치 마무리","level":"request","evidence":["note:2"]}
]}
JSON
for mode in none uncertain all; do
  ROUTINE_DRAFT_MARKERS="$mode" "$routine" draft --date 2026-09-08 --out "$out" --engine omp > /dev/null
  jq -e '
    . as $draft |
    all(["병합만으로 운영 배포 완료","확인만으로 운영 배포 완료","프로덕션 반영 완료"][];. as $topic|
      all($draft.items[];.topic!=$topic) and any($draft.questions[];.==("완료 표현이 근거보다 강해 초안에서 제외 — 원문: "+$topic))) and
    any(.items[];.topic=="PR 머지" and .level=="work" and (.text|contains("확인 필요")|not)) and
    any(.items[];.topic=="결제 API 병합 완료" and .level=="merged") and
    any(.questions[];contains("존재하지 않는 근거: git:missing")) and
    any(.items[];.topic=="결제 API 운영 배포 완료") and
    any(.items[];.topic=="결제 API 정상 확인 완료" and .level=="verified") and
    any(.items[];.topic=="membership 화면 개발") and
    any(.items[];.topic=="PR 정리") and any(.items[];.topic=="검토 기록") and
    any(.items[];.topic=="병합 완료") and
    any(.items[];.topic=="단어 경계 검사") and
    any(.items[];.topic=="루트 이름 점검" and (.text|contains("확인 필요")|not)) and
    any(..|objects; .label?=="운영배포완료") and
    any(.items[];.topic=="마무리" and .held==true) and
    all($draft.questions[];startswith("마무리:")|not) and
    all(["Release v1.2 준비","prod 설정 적용","merge conflict 해결","남은 일: 리뷰 반영 후 머지","결제 API 리뷰 반영","운영 설정 적용","정산 배치 마무리"][];. as $topic|
      any($draft.items[];.section=="today" and .topic==$topic) and all($draft.questions[];startswith($topic+":")|not))
  ' "$result" > /dev/null || fail "Completion facts, actual proof, today or hold semantics regressed in $mode"
  jq -Rse 'test("병합만으로 운영 배포 완료|확인만으로 운영 배포 완료|프로덕션 반영 완료")|not' "$out/2026-09-08.draft.txt" "$out/2026-09-08.draft.html" > /dev/null || fail 'Unsupported stronger claims leaked into delivery text/HTML'
done
# Exact 12 git + 1 PR + 2 session fixture from CompletionRuleReview's c9d17f4 probe.
# Ordinary action nouns and verbatim source titles must survive both draft paths.
cp "$out/2026-09-08.json" "$sandbox/proof-source.json"
printf '' > "$notes"
cat > "$out/2026-09-08.json" <<'JSON'
{"version":1,"window":{"since":"2026-09-01T00:00:00Z","until":"2026-09-08T00:00:00Z"},"git":[
{"sha":"a1","repo":"svc","subject":"feat: 배포 스크립트 추가"},
{"sha":"a2","repo":"svc","subject":"ci: deploy workflow 캐시 수정"},
{"sha":"a3","repo":"svc","subject":"chore(release): v1.2.0"},
{"sha":"a4","repo":"svc","subject":"fix: prod 설정 오류 수정"},
{"sha":"a5","repo":"svc","subject":"fix: 머지 충돌 해결"},
{"sha":"a6","repo":"svc","subject":"docs: 릴리스 노트 작성"},
{"sha":"a7","repo":"svc","subject":"feat: 정상 확인 헬스체크 추가"},
{"sha":"a8","repo":"svc","subject":"feat: 결제 API 추가"},
{"sha":"b1","repo":"svc","subject":"fix: 운영배포 완료"},
{"sha":"b2","repo":"svc","subject":"chore: 재배포 완료"},
{"sha":"b3","repo":"svc","subject":"chore: 운영에 반영 완료"},
{"sha":"b4","repo":"svc","subject":"release: 운영 배포했음"}],
"prs":[{"url":"https://example/pull/7","title":"배포 파이프라인 개선","state":"MERGED","current":{"state":"MERGED"},"in_window":true,"activity":[{"kind":"commit","at":"2026-09-02T00:00:00Z"}]}],
"sessions":[{"id":"s1","source":"omp","title":"prod 배포 상태 확인해줘","latest_report":"확인 부탁드립니다","reports":[]},
{"id":"s2","source":"omp","title":"결제 API 리팩터링","latest_report":"정리했습니다","reports":[]}],"errors":[]}
JSON
jq -L "$repo/share" 'include "scrum"; summary_draft({today:[]}) | .items|=map(.path[1]=.topic)' "$out/2026-09-08.json" > "$MODEL_JSON"
for engine in none omp; do
  "$routine" draft --date 2026-09-08 --out "$out" --engine "$engine" > /dev/null
  jq -e --slurpfile source "$out/2026-09-08.json" '
    (.items|map(.topic)|sort)==([$source[0].git[].subject,$source[0].prs[].title,$source[0].sessions[].title]|sort) and
    any(.items[];.topic=="배포 파이프라인 개선" and .level=="work") and .questions==[]
  ' "$result" > /dev/null || fail "15-item noun/original-title fixture lost valid source items in $engine"
done
# A copied title does not excuse a separately invented completed group.
jq '.items=[.items[]|select(.topic=="fix: 운영배포 완료")|.path[1]="새로운 릴리스 완료"]' "$MODEL_JSON" > "$sandbox/model-next.json"
cp "$sandbox/model-next.json" "$MODEL_JSON"
"$routine" draft --date 2026-09-08 --out "$out" --engine omp > /dev/null
jq -e '.items==[] and any(.questions[];.=="완료 표현이 근거보다 강해 초안에서 제외 — 원문: fix: 운영배포 완료")' "$result" > /dev/null || fail 'Raw title exemption leaked into a fabricated completed group'
cp "$sandbox/proof-source.json" "$out/2026-09-08.json"
cases="$repo/tests/fixtures/completion-claims.json"
# The review probe table also restores inflected synonyms and compound claims.
# Run each expression through the actual command with sufficient/insufficient proof.
for proof in sufficient insufficient; do
  jq -n --slurpfile cases "$cases" --arg proof "$proof" '
    {items:[$cases[0][]|{section:"yesterday",path:["개발","표현 분류"],topic:.text,level:"request",
      evidence:(if $proof=="sufficient" then ["git:explicitmerge","session:s1#0","session:s1#1"] else ["session:request"] end)}]}
  ' > "$MODEL_JSON"
  "$routine" draft --date 2026-09-08 --out "$out" --engine omp > /dev/null
  jq -e -L "$repo/share" --slurpfile cases "$cases" --arg proof "$proof" '
    include "scrum"; . as $draft |
    all($cases[0][];. as $case |
      ($case.text|claim_classes)==$case.claims and
      (if $proof=="sufficient" or ($case.claims|length)==0 then
        any($draft.items[];.topic==$case.text) and all($draft.questions[];startswith($case.text+":")|not)
       else
        all($draft.items[];.topic!=$case.text) and
        any($draft.questions[];.==("완료 표현이 근거보다 강해 초안에서 제외 — 원문: "+$case.text)) end))
  ' "$result" > /dev/null || fail "Completion expression table did not respect $proof proof"
done
# Merge, deployment and verification are separate facts, not an ordered ceiling.
# Only the three diagonal cells in this evidence-kind × claim-kind matrix survive.
jq -n '
  [{name:"병합",level:"merged",evidence:"pr:https://example/pull/1",text:"머지 완료"},
   {name:"배포",level:"deployed",evidence:"session:s1#0",text:"운영 배포 완료"},
   {name:"검증",level:"verified",evidence:"session:s1#1",text:"정상 확인 완료"}] as $kinds |
  {items:[$kinds[] as $claim | $kinds[] as $proof |
    {section:"yesterday",path:["개발","결제 API"],topic:("결제 API "+$claim.text+" ("+$proof.name+" 근거)"),
     level:$claim.level,evidence:[$proof.evidence]}]}
' > "$MODEL_JSON"
for mode in none uncertain all; do
  ROUTINE_DRAFT_MARKERS="$mode" "$routine" draft --date 2026-09-08 --out "$out" --engine omp > /dev/null
  jq -e --slurpfile model "$MODEL_JSON" --arg mode "$mode" '
    . as $draft |
    (.items|map(.topic)|sort)==(["결제 API 머지 완료 (병합 근거)","결제 API 운영 배포 완료 (배포 근거)","결제 API 정상 확인 완료 (검증 근거)"]|sort) and
    all(.items[];(.text|contains("확인 필요")|not)) and
    all($model[0].items[];. as $item |
      if any($draft.items[];.topic==$item.topic) then any($draft.items[];.topic==$item.topic and .level==$item.level)
      else any($draft.questions[];.==("완료 표현이 근거보다 강해 초안에서 제외 — 원문: "+$item.topic)) end) and
    (if $mode=="all" then
      any(.items[];.level=="merged" and (.text|endswith(" (병합)"))) and
      any(.items[];.level=="deployed" and (.text|endswith(" (운영 배포)"))) and
      any(.items[];.level=="verified" and (.text|endswith(" (확인)")))
     else true end)
  ' "$result" > /dev/null || fail "Orthogonal 3x3 completion matrix or markers regressed in $mode"
done
# Every fact in a compound statement needs its own proof, including general work.
jq -n '
  {items:([range(1;8) as $mask |
    {section:"yesterday",path:["개발","결제 API"],
     topic:("결제 API 머지 완료, 운영 배포 완료, 정상 확인 완료 (근거 "+($mask|tostring)+")"),level:"work",
     evidence:([if ($mask%2)==1 then "pr:https://example/pull/1" else empty end,
                if (($mask/2|floor)%2)==1 then "session:s1#0" else empty end,
                if ($mask/4|floor)==1 then "session:s1#1" else empty end])}] +
    [{section:"yesterday",path:["개발","결제 API"],topic:"결제 API 구현 완료 및 운영 배포 완료 (배포만)",level:"work",evidence:["session:s1#0"]},
     {section:"yesterday",path:["개발","결제 API"],topic:"결제 API 구현 완료 및 운영 배포 완료 (커밋과 배포)",level:"work",evidence:["git:aaa111","session:s1#0"]},
     {section:"yesterday",path:["개발","결제 API"],topic:"결제 API 구현 완료 (검증만)",level:"work",evidence:["session:s1#1"]},
     {section:"yesterday",path:["개발","결제 API"],topic:"결제 API 구현 완료 (커밋)",level:"work",evidence:["git:aaa111"]}])}
' > "$MODEL_JSON"
"$routine" draft --date 2026-09-08 --out "$out" --engine omp > /dev/null
jq -e --slurpfile model "$MODEL_JSON" '
  . as $draft |
  (.items|map(.topic)|sort)==(["결제 API 머지 완료, 운영 배포 완료, 정상 확인 완료 (근거 7)","결제 API 구현 완료 및 운영 배포 완료 (커밋과 배포)","결제 API 구현 완료 (커밋)"]|sort) and
  all($model[0].items[];. as $item | any($draft.items[];.topic==$item.topic) or
    any($draft.questions[];.==("완료 표현이 근거보다 강해 초안에서 제외 — 원문: "+$item.topic)))
' "$result" > /dev/null || fail 'A compound claim borrowed proof from a different fact'
# LLM levels and visible markers likewise cannot borrow an unrelated fact.
cat > "$MODEL_JSON" <<'JSON'
{"items":[
{"section":"yesterday","path":["개발","결제 API"],"topic":"결제 API 검토 기록","level":"merged","evidence":["session:s1#0"]},
{"section":"yesterday","path":["개발","결제 API"],"topic":"결제 API 변경 기록","level":"verified","evidence":["pr:https://example/pull/1"]},
{"section":"yesterday","path":["개발","결제 API"],"topic":"결제 API 점검 기록","level":"deployed","evidence":["session:s1#1"]}]}
JSON
ROUTINE_DRAFT_MARKERS=all "$routine" draft --date 2026-09-08 --out "$out" --engine omp > /dev/null
jq -e '
  any(.items[];.topic=="결제 API 검토 기록" and .level=="request" and (.text|contains("병합")|not)) and
  any(.items[];.topic=="결제 API 변경 기록" and .level=="work" and (.text|contains("(확인,")|not)) and
  any(.items[];.topic=="결제 API 점검 기록" and .level=="request" and (.text|contains("운영 배포")|not))
' "$result" > /dev/null || fail 'LLM level or rendered marker treated unrelated proof as a higher tier'
# Holds excuse only connected, author-written claims, never arbitrary held_ref.
cat > "$notes" <<'NOTES'
## 보류
- 정산 배치 마무리
- 정산 운영 배포 완료
- 정산 정상 확인 완료
- 서포트 알림 작업
- 정산 코드 운영 배포 완료
NOTES
cat > "$MODEL_JSON" <<'JSON'
{"items":[
{"section":"yesterday","path":["개발","정산"],"topic":"정산 배치 마무리","level":"work","evidence":[],"held_ref":0},
{"section":"yesterday","path":["배포","정산"],"topic":"정산 운영 배포 완료","level":"deployed","evidence":[],"held_ref":1},
{"section":"yesterday","path":["배포","정산"],"topic":"정산 배치 운영 배포 완료","level":"deployed","evidence":["pr:https://example/pull/1"],"held_ref":0},
{"section":"yesterday","path":["배포","결제"],"topic":"결제 API 운영 배포 완료","level":"deployed","evidence":["pr:https://example/pull/1"],"held_ref":0},
{"section":"yesterday","path":["배포","정산"],"topic":"정산 API 운영 배포 완료","level":"deployed","evidence":["pr:https://example/pull/1"]},
{"section":"yesterday","path":["배포","정산"],"topic":"정산 정상 확인 완료 및 운영 배포 완료","level":"deployed","evidence":["pr:https://example/pull/1"],"held_ref":2},
{"section":"yesterday","path":["개발","서포트"],"topic":"서포트 알림 마무리","level":"work","evidence":["session:request"],"held_ref":3},
{"section":"yesterday","path":["개발","정산"],"topic":"정산 코드 구현 완료","level":"work","evidence":["session:request"],"held_ref":4}]}
JSON
for mode in none uncertain all; do
  ROUTINE_DRAFT_MARKERS="$mode" "$routine" draft --date 2026-09-08 --out "$out" --engine omp > /dev/null
  jq -e --slurpfile model "$MODEL_JSON" '
    . as $draft |
    (.items|map(.topic)|sort)==(["정산 배치 마무리","정산 운영 배포 완료"]|sort) and
    all(.items[];.held==true and (.text|contains("확인 필요")|not)) and
    all($model[0].items[2:][];. as $item | any($draft.questions[];.==("완료 표현이 근거보다 강해 초안에서 제외 — 원문: "+$item.topic))) and
    any(.questions[];.=="결제 API 운영 배포 완료: 보류 항목 매칭 확인") and
    any(.questions[];.=="정산 API 운영 배포 완료: 보류 항목 매칭 확인")
  ' "$result" > /dev/null || fail "Arbitrary, partial or inflated hold exemption bypassed proof in $mode"
done
# A single same-project hold must not mark seven normal yesterday items or hide
# four today plans. Assert the delivered text, not only the intermediate items.
cat > "$out/2026-09-08.json" <<'JSON'
{"version":1,"window":{"since":"2026-09-01T00:00:00Z","until":"2026-09-08T00:00:00Z"},
"git":[{"sha":"n1","repo":"svc","subject":"feat: 결제 API 추가"},{"sha":"n2","repo":"svc","subject":"feat: 결제 API 리팩터링"}],
"prs":[
{"url":"https://example/pull/n1","title":"결제 API 머지","state":"MERGED","in_window":true,"activity":[{"kind":"merged","at":"2026-09-02T00:00:00Z"}]},
{"url":"https://example/pull/n2","title":"결제 API 리뷰 반영","state":"OPEN","in_window":true,"activity":[{"kind":"review","at":"2026-09-02T00:00:00Z"}]},
{"url":"https://example/pull/n3","title":"결제 API 리뷰만 한 PR","state":"MERGED","in_window":true,"activity":[{"kind":"review","at":"2026-09-02T00:00:00Z"}]}],
"sessions":[
{"id":"n1","source":"omp","title":"결제 API 개발 검토","latest_report":"결제 API 개발 검토 요청","reports":[{"text":"남은 일: 결제 API 테스트 점검"},{"text":"다음 단계: 결제 API 배포 계획"}]},
{"id":"n2","source":"omp","title":"결제 API 배포 검토","latest_report":"결제 API 설정 검토 요청","reports":[]}],"errors":[]}
JSON
cat > "$notes" <<'NOTES'
## 보류
- 결제 API 운영 배포 (QA 대기)
## 오늘 추가
- 결제 API 테스트 보강
NOTES
header_today=$(jq -er '.draft.headers.today' "$ROUTINE_CONFIG")
for mode in none uncertain all; do
  ROUTINE_DRAFT_MARKERS="$mode" "$routine" draft --date 2026-09-08 --out "$out" --no-llm > /dev/null
  jq -Rse --arg header "$header_today" '
    . as $text | ($text|split($header+"\n")|last) as $today |
    all(["feat: 결제 API 추가","feat: 결제 API 리팩터링","결제 API 머지","결제 API 리뷰 반영","결제 API 리뷰만 한 PR","결제 API 개발 검토","결제 API 배포 검토"][];. as $topic|$text|contains($topic)) and
    all(["결제 API 리뷰 반영","남은 일: 결제 API 테스트 점검","다음 단계: 결제 API 배포 계획","결제 API 테스트 보강"][];. as $topic|$today|contains($topic)) and
    ($text|contains("(보류)")|not)
  ' "$out/2026-09-08.draft.txt" > /dev/null || fail "Same-project hold changed delivered yesterday/today content in $mode"
  jq -e '
    (.items|map(select(.section=="yesterday"))|length)==7 and
    (.today|[..|objects|select(has("item"))]|length)==4 and
    all(.items[];.held==false) and
    any(.questions[];.=="결제 API 리뷰 반영: 보류 항목 매칭 확인") and
    any(.questions[];.=="결제 API 테스트 보강: 보류 항목 매칭 확인")
  ' "$result" > /dev/null || fail 'Automatic hold used partial overlap instead of the full memo'
done
# The LLM path must also leave an overlapping OPEN-PR plan visible.
cat > "$MODEL_JSON" <<'JSON'
{"items":[{"section":"today","path":["개발","결제 API"],"topic":"결제 API 리뷰 반영","level":"work","evidence":["pr:https://example/pull/n2"]}]}
JSON
"$routine" draft --date 2026-09-08 --out "$out" --engine omp > /dev/null
jq -Rse 'contains("결제 API 리뷰 반영") and (contains("(보류)")|not)' "$out/2026-09-08.draft.txt" > /dev/null || fail 'Partial hold hid the LLM OPEN-PR plan'
# Even a connected explicit reference or a full-memo prefix only hides today
# when its normalized topic is exactly the memo.
for ref in automatic explicit; do
  jq -n --arg ref "$ref" '
    {items:[{section:"today",path:["개발","결제 API"],topic:"결제 API 운영 배포 (QA 대기) 이후 테스트",level:"request",evidence:["note:0"]}]} |
    if $ref=="explicit" then .items[0].held_ref=0 else . end
  ' > "$MODEL_JSON"
  "$routine" draft --date 2026-09-08 --out "$out" --engine omp > /dev/null
  jq -Rse 'contains("결제 API 운영 배포 (QA 대기) 이후 테스트")' "$out/2026-09-08.draft.txt" > /dev/null || fail "Non-exact $ref hold hid today"
done
cat > "$MODEL_JSON" <<'JSON'
{"items":[{"section":"today","path":["개발","결제 API"],"topic":"결제   API 운영 배포 (QA 대기)","level":"request","evidence":["note:0"],"held_ref":0}]}
JSON
"$routine" draft --date 2026-09-08 --out "$out" --engine omp > /dev/null
jq -Rse 'contains("QA 대기")|not' "$out/2026-09-08.draft.txt" > /dev/null || fail 'Normalized exact held task remained in today delivery'
# Review cases (a), (b), (c): pending/conditional memo tails and a different
# target connected only by words must never excuse a completed topic.
cp "$sandbox/proof-source.json" "$out/2026-09-08.json"
cat > "$notes" <<'NOTES'
## 보류
- 결제 API 운영 배포 완료 대기
- 정산 머지 완료 후 배포
- 정산 코드 운영 배포 완료
NOTES
for ref in automatic explicit; do
  jq -n --arg ref "$ref" '
    {items:[
      {section:"yesterday",path:["배포","결제 API"],topic:"결제 API 운영 배포 완료",level:"deployed",evidence:["session:request"]},
      {section:"yesterday",path:["개발","정산"],topic:"정산 머지 완료",level:"merged",evidence:[]},
      {section:"yesterday",path:["배포","결제 API"],topic:"정산 코드 리뷰 및 결제 API 운영 배포 완료",level:"deployed",evidence:[]}]} |
    if $ref=="explicit" then .items|=(to_entries|map(.value + {held_ref:.key})) else . end
  ' > "$MODEL_JSON"
  for mode in none uncertain all; do
    ROUTINE_DRAFT_MARKERS="$mode" "$routine" draft --date 2026-09-08 --out "$out" --engine omp > /dev/null
    jq -e --slurpfile model "$MODEL_JSON" '
      . as $draft | .items==[] and
      all($model[0].items[];. as $item|any($draft.questions[];.==("완료 표현이 근거보다 강해 초안에서 제외 — 원문: "+$item.topic)))
    ' "$result" > /dev/null || fail "Pending/conditional or word-overlap hold excused a claim in $ref/$mode"
    jq -Rse 'test("운영 배포 완료|머지 완료|\\(보류\\)")|not' "$out/2026-09-08.draft.txt" > /dev/null || fail 'Held completed claim leaked into rendered delivery'
  done
done
printf '%s\n' 'PASS: predicate claims, independent proofs, literal/context-safe holds and rendered 19/15/7+4-item baselines'
