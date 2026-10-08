#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2016,SC2030,SC2031 # Parent owns isolated paths/helpers; jq literals and subshell settings are intentional.
check 'QUALITY exact URLs, useful-word threshold, unique comment display, issue scope and question aggregation' jq -L "$share_dir" -e -f "$repo/tests/fixtures/jira/quality-rules.jq" "$sandbox/rules-context.json"
(
  ROUTINE_SETTINGS=$(command jq -c '.jira.repos["unrelated-admin-web"]={project:"ABC",prefix:"[어드민]"}' <<< "$ROUTINE_SETTINGS")
  check 'QUALITY review boundaries, normalized proof, attribution and cause examples' jq -L "$share_dir" -e -f "$repo/tests/fixtures/jira/quality-review-rules.jq" "$sandbox/rules-context.json"
)
for mode in tokenized exact multiple nested comments clean prefix semantic short short-empty; do
  (
    cp "$sandbox/server-initial.json" "$JIRA_SERVER"
    (
      routine_jira_session; routine_jira_lock apply; reset_jira_ledger
      printf '{"version":1,"links":[],"rejections":[]}\n' > "$jira_work/empty-links.json"
      routine_jira_store "$jira_work/empty-links.json" "$jira_dir/links.json"
    )
    unset JIRA_ROUTES JIRA_CANDIDATES JIRA_MODEL_RESULT
    export JIRA_DUPLICATES="$sandbox/quality-search-rows.json" JIRA_REQUEST_LOG="$sandbox/quality-search-requests" JIRA_MODEL_SUMMARY='game quest type implementation'
    case $mode in prefix) JIRA_MODEL_SUMMARY='[BACK] [widget-server] game quest type implementation' ;; semantic) JIRA_MODEL_SUMMARY='[긴급] [AOS] game quest type implementation' ;; short|short-empty) JIRA_MODEL_SUMMARY='Dockerfile 수정' ;; esac
    : > "$JIRA_REQUEST_LOG"
    ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="omp"|.jira.repos={"widget-server":{project:"ABC",prefix:"[BACK]"}}' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
    command jq --arg mode "$mode" '.git=[]|.sessions=[]|.prs=[{roles:["author"],repository:"widget-server",url:"https://github.com/example-org/widget-server/pull/63",number:63,state:"OPEN",title:(if $mode|startswith("short") then "Dockerfile 수정" else "game quest type implementation" end),commits_complete:true,commit_oids:[],activity:[{kind:"created",at:"2026-10-08T00:00:00Z"}]}]' "$sandbox/raw.json" > "$sandbox/quality-raw.json"
    export JIRA_RAW="$sandbox/quality-raw.json"
    command jq --arg mode "$mode" '
      .issue as $issue |
      if $mode|IN("clean","prefix","semantic","short-empty") then [] else
      [range(10;14) as $i|$issue|.key=("ABC-"+($i|tostring))|.fields.summary="[BACK] widget-server example-org Docker image cache"|
        .fields.description={type:"doc",content:[{type:"inlineCard",attrs:{url:"https://github.com/example-org/widget-api/pull/86"}}]}] +
      (if $mode=="tokenized" then [] else [$issue|.fields.summary=(if $mode=="short" then "[BACK] Dockerfile 수정" else "Docker image cache" end)|
        .fields.description=(if $mode|IN("comments","short") then null elif $mode=="nested" then
          {type:"doc",content:[{type:"panel",content:[{type:"codeBlock",content:[{type:"text",text:"https://GitHub.COM/EXAMPLE-ORG/"},{type:"text",text:"WIDGET-SERVER/pull/63/files?tab=1#discussion"}]}]}]}
        else {type:"doc",content:[{type:"inlineCard",attrs:{url:"https://github.com/example-org/widget-server/pull/63"}}]} end)] end) +
      (if $mode=="multiple" then [$issue|.key="ABC-2"|.id="200"|.fields.summary="Docker build cache"|.fields.description={type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"PR",marks:[{type:"link",attrs:{href:"https://github.com/example-org/widget-server/pull/63"}}]}]}]}] else [] end) end
      ' "$JIRA_SERVER" > "$JIRA_DUPLICATES"
    if [[ $mode == comments ]]; then
      export JIRA_ROUTES="$sandbox/quality-comment-only-routes.json"
      command jq -n '[{method:"GET",prefix:"/rest/api/3/issue/ABC-1/comment?",body:{startAt:0,total:1,comments:[{id:"comment-url",body:{type:"doc",content:[{type:"table",content:[{type:"tableRow",content:[{type:"tableCell",content:[{type:"paragraph",content:[{type:"text",text:"PR",marks:[{type:"link",attrs:{href:"https://github.com/example-org/widget-server/pull/63/commits#discussion"}}]}]}]}]}]}]}}]}}]' > "$JIRA_ROUTES"
    fi
    before=$(wc -l < "$JIRA_EFFECTS")
    check "QUALITY $mode production proposal" "$repo/bin/routine" jira propose
    jq_check 'QUALITY only URL duplicate queries request original ADF description' 'any(.[];(.body.jql // "")|contains(" AND text ~ ")) and all(.[]|select((.body.jql // "")|startswith("project = "));((.body.fields|index("description"))!=null)==(.body.jql|contains(" AND text ~ ")))' -s "$JIRA_REQUEST_LOG"
    case $mode in
      tokenized) jq_check 'QUALITY unproven Docker URL hits cannot link or silently allow creation' '.llm.valid and all(.searches.duplicates[];.complete and .matches==[] and (.possible|length)==4) and all(.proposals[];.kind!="link" and .kind!="create_issue") and any(.questions[];contains("URL 부분 일치") and contains("ABC-10"))' "$proposal_file" ;;
      exact|nested|comments|short) jq_check "QUALITY $mode proven citation or normalized identical title creates exactly one duplicate link" '.llm.valid and ([.proposals[]|select(.kind=="link" and .payload.origin=="duplicate")]|length)==1 and all(.proposals[];.kind!="create_issue")' "$proposal_file" ;;
      multiple) jq_check 'QUALITY multiple exact citations create only ambiguity question, never links or create' '.llm.valid and all(.proposals[];.kind!="link" and .kind!="create_issue") and any(.questions[];startswith("중복 후보 여러 개:"))' "$proposal_file" ;;
      clean|prefix) jq_check "QUALITY $mode clean creation strips model prefix and repository brackets" '.llm.valid and any(.proposals[];.kind=="create_issue" and .payload.summary=="[BACK] game quest type implementation")' "$proposal_file"; [[ $mode != clean ]] || cp "$proposal_file" "$sandbox/quality-clean-proposals.json" ;;
      semantic) jq_check 'QUALITY meaningful leading bracket labels survive deterministic summary cleanup' '.llm.valid and any(.proposals[];.kind=="create_issue" and .payload.summary=="[BACK] [긴급] [AOS] game quest type implementation")' "$proposal_file" ;;
      short-empty) jq_check 'QUALITY short PR summary keeps search incomplete and creation blocked without fake HTTP error' '.llm.valid and all(.searches.duplicates[];.complete==false and .reason=="insufficient_summary_words") and all(.proposals[];.kind!="create_issue") and any(.questions[];startswith("요약 고유 단어 부족")) and all(.errors[];.message|contains("중복 검색 응답")|not)' "$proposal_file" ;;
    esac
    check "QUALITY $mode keeps propose write effects at zero" test "$(wc -l < "$JIRA_EFFECTS")" = "$before"
    if [[ $mode == tokenized ]]; then
      check 'QUALITY non-TTY review cannot dismiss duplicate possibilities' "$repo/bin/routine" jira review
      jq_check 'QUALITY non-TTY review records no duplicate rejection' '.rejections==[]' "$HOME/Library/Application Support/routine-automation/jira/links.json"
      (
        routine_jira_session
        # shellcheck disable=SC2329 # Invoked indirectly by production routine_jira_review.
        ui_choose_many() {
          [[ $3 == '[]' ]] || return 5
          if [[ $1 == '중복 아님 '* ]]; then command jq -nc --argjson choices "$2" '[$choices[].value]'
          else printf '[]\n'; fi
        }
        check 'QUALITY interactive review explicitly releases only unproven candidates' routine_jira_review 2026-10-08 > "$sandbox/duplicate-review-output"
        check 'QUALITY recorded rejection tells the user to propose again' grep -q '중복 아님 기록 — routine jira propose를 다시 실행하면 생성 제안을 다시 판단합니다' "$sandbox/duplicate-review-output"
        jq_check 'QUALITY duplicate rejections retain site account PR evidence candidate tuple' '(.rejections|length)==4 and all(.rejections[];.kind=="duplicate" and .site=="https://example.atlassian.net" and .account_id=="fixture-account" and (.evidence_id|startswith("pr:"))) and (.rejections|map(.key)|sort)==["ABC-10","ABC-11","ABC-12","ABC-13"]' "$jira_dir/links.json"
        check 'QUALITY duplicate rejection file remains private' test "$(stat -f %Lp "$jira_dir/links.json")" = 600
      )
      check 'QUALITY next propose stops repeating dismissed candidates and permits normal creation' "$repo/bin/routine" jira propose
      jq_check 'QUALITY dismissed possibilities are absent from questions and published searches' 'all(.searches.duplicates[];.matches==[] and .possible==[]) and any(.proposals[];.kind=="create_issue") and all(.questions[];contains("URL 부분 일치")|not)' "$proposal_file"
      (
        routine_jira_session; routine_jira_lock review; routine_jira_authenticate
        create=$(command jq -c '.proposals[]|select(.kind=="create_issue")' "$proposal_file")
        routine_jira_approve "$create" "$proposal_file" false
        command jq '.entries[0]' "$jira_dir/ledger.json" > "$jira_work/rejected-entry.json"
        status=0; routine_jira_preflight "$jira_work/rejected-entry.json" apply || status=$?
        check 'QUALITY NEW-16 honors the same scoped rejection' test "$status" = 0
        command jq '.[0].fields.description={type:"doc",content:[{type:"inlineCard",attrs:{url:"https://github.com/example-org/widget-server/pull/63"}}]}' "$JIRA_DUPLICATES" > "$jira_work/proven-rows.json"; mv "$jira_work/proven-rows.json" "$JIRA_DUPLICATES"
        status=0; routine_jira_preflight "$jira_work/rejected-entry.json" apply || status=$?
        check 'QUALITY exact PR proof still blocks after a previous possible rejection' test "$status" = 5
        command jq '.[0].fields.description=null' "$JIRA_DUPLICATES" > "$jira_work/unproven-rows.json"; mv "$jira_work/unproven-rows.json" "$JIRA_DUPLICATES"
        reset_jira_ledger
      )
      check 'QUALITY links removal restores a dismissed duplicate candidate' "$repo/bin/routine" jira links --remove 1
      check 'QUALITY removed rejection is considered on the next proposal' "$repo/bin/routine" jira propose
      jq_check 'QUALITY restored possibility blocks creation and returns exactly its question' 'all(.searches.duplicates[];.possible==["ABC-10"]) and all(.proposals[];.kind!="create_issue") and any(.questions[];contains("URL 부분 일치") and contains("ABC-10"))' "$proposal_file"
      check 'QUALITY rejection review and duplicate preflights send no Jira writes' test "$(wc -l < "$JIRA_EFFECTS")" = "$before"
    fi
  )
done
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  (
    routine_jira_session; routine_jira_lock apply; reset_jira_ledger
    printf '{"version":1,"links":[],"rejections":[]}\n' > "$jira_work/empty-links.json"
    routine_jira_store "$jira_work/empty-links.json" "$jira_dir/links.json"
  )
  unset JIRA_DUPLICATES JIRA_CANDIDATES JIRA_MODEL_RESULT JIRA_MODEL_SUMMARY
  ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="none"|.jira.repos={example:{project:"ABC",prefix:"[BACK]"}}' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  command jq '.git[0].subject="ABC-1 ABC-2 feature implementation"|
    .sessions=[{id:"scoped-report",source:"omp",last_ts:"2026-10-08T02:00:00Z",title:"release check",reports:[{ts:"2026-10-08T02:00:00Z",text:"ABC-1 운영 배포 완료했습니다 운영 조회 확인했습니다.\nABC-2 다음 계획."}]}]' "$sandbox/raw.json" > "$sandbox/quality-comment-raw.json"
  export JIRA_RAW="$sandbox/quality-comment-raw.json" JIRA_ROUTES="$sandbox/quality-comment-routes.json"
  command jq '[{method:"GET",prefix:"/rest/api/3/issue/ABC-2?fields=",body:(.issue|.key="ABC-2"|.id="200")}]' "$JIRA_SERVER" > "$JIRA_ROUTES"
  before=$(wc -l < "$JIRA_EFFECTS")
  check 'QUALITY production multi-key comments use sentence-specific issue keys' "$repo/bin/routine" jira propose --no-llm
  jq_check 'QUALITY target comment displays highest report once while recording both report event IDs' '[.proposals[]|select(.kind=="comment" and .key=="ABC-1")][0]|([.payload.events[]|select(.kind|startswith("report_"))]|length)==2 and (.payload.text|split("\n")|map(select(startswith("확인 보고")))|length)==1 and (.payload.text|contains("배포 보고")|not)' "$proposal_file"
  jq_check 'QUALITY other-key comment contains no foreign report text or event IDs' '[.proposals[]|select(.kind=="comment" and .key=="ABC-2")][0]|.!=null and all(.payload.events[];.kind|startswith("report_")|not) and (.payload.text|contains("보고(")|not) and (.events|length)==1' "$proposal_file"
  check 'QUALITY scoped comments remain read-only proposals' test "$(wc -l < "$JIRA_EFFECTS")" = "$before"
)
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  (
    routine_jira_session; routine_jira_lock apply; reset_jira_ledger
    printf '{"version":1,"links":[],"rejections":[]}\n' > "$jira_work/empty-links.json"
    routine_jira_store "$jira_work/empty-links.json" "$jira_dir/links.json"
  )
  unset JIRA_DUPLICATES JIRA_CANDIDATES JIRA_ROUTES JIRA_MODEL_RESULT
  ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="omp"|.jira.repos={example:{project:"ABC",prefix:"[BACK]"}}' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  command jq '.git[0].subject="main → staging 백머지"|.prs=[]|.sessions=[]' "$sandbox/raw.json" > "$sandbox/quality-backmerge-raw.json"
  export JIRA_RAW="$sandbox/quality-backmerge-raw.json" JIRA_MODEL_SUMMARY='main → staging 백머지'
  before=$(wc -l < "$JIRA_EFFECTS")
  check 'QUALITY production merge-only work cannot become a new issue even if the model proposes it' "$repo/bin/routine" jira propose
  jq_check 'QUALITY merge-only exclusion precedes duplicate requests and creation' '.llm.valid and .searches.duplicates==[] and all(.proposals[];.kind!="create_issue") and any(.questions[];startswith("병합·백머지만 있는 작업"))' "$proposal_file"
  check 'QUALITY merge-only proposal remains read-only' test "$(wc -l < "$JIRA_EFFECTS")" = "$before"
)
(
  ROUTINE_SETTINGS=$(command jq -c '.jira.repos={"widget-server":{project:"ABC",prefix:"[BACK]"}}' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  routine_jira_session; routine_jira_lock review; routine_jira_authenticate; reset_jira_ledger
  create=$(command jq -c '.proposals[]|select(.kind=="create_issue")' "$sandbox/quality-clean-proposals.json")
  check 'QUALITY production clean proposal can be approved locally' routine_jira_approve "$create" "$sandbox/quality-clean-proposals.json" false
  command jq '.entries[0]' "$jira_dir/ledger.json" > "$jira_work/quality-entry.json"
  export JIRA_DUPLICATES="$sandbox/quality-preflight-rows.json"
  before=$(wc -l < "$JIRA_EFFECTS")
  for mode in possible nested comments; do
    unset JIRA_ROUTES
    command jq --arg mode "$mode" '[.issue|.fields.summary="Docker image cache"|.fields.description=(if $mode=="nested" then {type:"doc",content:[{type:"blockquote",content:[{type:"paragraph",content:[{type:"text",text:"https://GitHub.COM/EXAMPLE-ORG/WIDGET-SERVER/pull/63/commits#discussion"}]}]}]} else null end)]' "$JIRA_SERVER" > "$JIRA_DUPLICATES"
    if [[ $mode == comments ]]; then export JIRA_ROUTES="$sandbox/quality-comment-only-routes.json"; fi
    status=0; routine_jira_preflight "$jira_work/quality-entry.json" apply || status=$?
    check "QUALITY NEW-16 $mode duplicate blocks the same production create before send" test "$status" = 5
  done
  check 'QUALITY NEW-16 never sends a write while resolving duplicate candidates' test "$(wc -l < "$JIRA_EFFECTS")" = "$before"
  command jq '.entries[0].proposal.payload.duplicate_input|=del(.repos)' "$jira_dir/ledger.json" > "$jira_work/legacy-ledger.json"
  routine_jira_store "$jira_work/legacy-ledger.json" "$jira_dir/ledger.json"
  id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
  routine_jira_apply_one "$id" > "$jira_work/legacy-apply-output"
  jq_check 'QUALITY pre-release create entries without repo metadata fail safely with repropose guidance' '.entries[0].state=="conflict" and (.entries[0].message|contains("다시 propose"))' "$jira_dir/ledger.json"
  check 'QUALITY legacy apply rejection explicitly tells the user to propose again' grep -q 'routine jira propose' "$jira_work/legacy-apply-output"
  check 'QUALITY legacy apply rejection never reaches Jira write transport' test "$(wc -l < "$JIRA_EFFECTS")" = "$before"
)
printf 'PASS: Jira URL 검색 오탐·요약 고유 단어/비율·다중 중복 후보·댓글 중복/이슈 귀속·질문 집계\n'
