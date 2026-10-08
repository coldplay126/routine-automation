#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2016,SC2030,SC2031 # Parent supplies isolated paths/helpers; jq programs and subshell settings are intentional.
check 'MODEL prompt examples, unchanged Claude schema, narrow normalization and strict JSON/fence forms' jq -L "$share_dir" -ne --rawfile prompt "$share_dir/jira-prompt.md" --slurpfile schema "$share_dir/jira-schema.json" -f "$repo/tests/fixtures/jira/llm-responses.jq"
for result in observed-works observed-ids fenced fenced-string fenced-upper fenced-spaced fenced-crlf explained-fenced explained two-objects two-fences malformed-object broken-object broken-array unknown-shape foreign-ids claude-valid claude-string; do
  (
    cp "$sandbox/server-initial.json" "$JIRA_SERVER"
    (
      routine_jira_session; routine_jira_lock apply; reset_jira_ledger
      printf '{"version":1,"links":[],"rejections":[]}\n' > "$jira_work/empty-links.json"
      routine_jira_store "$jira_work/empty-links.json" "$jira_dir/links.json"
    )
    command jq '.git[0] as $git|
      .git=[($git|.subject="feature implementation alpha"),($git|.sha="2222222222222222222222222222222222222222"|.subject="feature implementation beta"|.author_ts="2026-10-08T01:00:00Z")]|
      .sessions=[{id:"model-session",source:"omp",title:"implementation report",last_ts:"2026-10-08T02:00:00Z",reports:[{ts:"2026-10-08T02:00:00Z",text:"feature implementation report"}]}]
      ' "$sandbox/raw.json" > "$sandbox/model-response-raw.json"
    export JIRA_RAW="$sandbox/model-response-raw.json" JIRA_MODEL_RESULT=$result JIRA_MODEL_CALLS="$sandbox/model-response-calls"
    : > "$JIRA_MODEL_CALLS"
    ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="omp"' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
    if [[ $result == claude-* ]]; then
      rm "$sandbox/stubs/claude"; ln -s "$repo/tests/fixtures/jira/omp.sh" "$sandbox/stubs/claude"
      trap 'rm -f "$sandbox/stubs/claude"; ln -s "$repo/tests/fixtures/jira/command.sh" "$sandbox/stubs/claude"' EXIT
      unset -f claude
      ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="claude"' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
    fi
    before=$(wc -l < "$JIRA_EFFECTS")
    check "MODEL $result production proposal" "$repo/bin/jira-propose"
    case $result in
      explained|two-objects|two-fences|malformed-object|broken-object|broken-array|unknown-shape)
        reason=non_json; [[ $result != unknown-shape ]] || reason=schema_mismatch
        jq_check "MODEL $result remains invalid without changing works" '.llm.valid==false and (.works|length)==2 and ([.errors[]|select(.source=="llm" and .reason==$reason)]|map(.attempt))==[1,2]' --arg reason "$reason" "$proposal_file"
        check "MODEL $result retains the two-attempt limit" test "$(wc -l < "$JIRA_MODEL_CALLS" | tr -d ' ')" = 2 ;;
      foreign-ids)
        jq_check 'MODEL normalization does not bypass original input-ID guards' '.llm.valid and (.works|length)==2 and all(.works[];.evidence|index("rep:missing")==null) and any(.questions[];contains("작업 merge 무효")) and any(.questions[];contains("보고 attach 무효"))' "$proposal_file"
        check 'MODEL foreign IDs do not trigger an extra call' test "$(wc -l < "$JIRA_MODEL_CALLS" | tr -d ' ')" = 1 ;;
      *)
        jq_check "MODEL $result is valid and really merges/attaches input IDs" '.llm.valid and (.works|length)==1 and (.works[0].anchors|length)==2 and ([.works[0].evidence[]|select(startswith("git:"))]|length)==2 and ([.works[0].evidence[]|select(startswith("rep:"))]|length)==1 and all(.errors[];.source!="llm")' "$proposal_file"
        check "MODEL $result succeeds on the first attempt" test "$(wc -l < "$JIRA_MODEL_CALLS" | tr -d ' ')" = 1 ;;
    esac
    check "MODEL $result keeps Jira server write effects at zero" test "$(wc -l < "$JIRA_EFFECTS")" = "$before"
  )
done
printf 'PASS: Jira 실제 모델 모양 정규화·펜스/설명문·단일 JSON·엄격 스키마·입력 ID·Claude 계약\n'
