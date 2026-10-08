#!/usr/bin/env bash
set -euo pipefail
input=$(cat)
printf '%s\n' "$input" > "$JIRA_PROMPT"
# Refuse tools/network access flags becoming permissive.
if [[ ${0##*/} == claude ]]; then
  [[ " $* " == *' --tools '* && " $* " == *' --strict-mcp-config '* && " $* " == *' --no-session-persistence '* && " $* " == *' --json-schema '* ]] || exit 87
else [[ " $* " == *' --no-tools '* && " $* " == *' --no-session '* ]] || exit 87; fi
[[ -z ${JIRA_MODEL_CALLS:-} ]] || printf 'model\n' >> "$JIRA_MODEL_CALLS"
case ${JIRA_MODEL_RESULT:-} in
  timeout) printf 'token=fixture-model-secret\n' >&2; exit 124 ;;
  exit) printf 'token=fixture-model-secret\n' >&2; exit 17 ;;
  empty) exit 0 ;;
  non-json) printf 'token=fixture-model-secret 원문\n'; exit 0 ;;
  schema) printf '{"unexpected":"token=fixture-model-secret"}\n'; exit 0 ;;
  llm-error) printf '{"is_error":true,"result":"token=fixture-model-secret"}\n'; exit 0 ;;
esac
case ${JIRA_MODEL_RESULT:-} in
  observed-works|observed-ids|fenced|fenced-string|fenced-upper|fenced-spaced|fenced-crlf|explained-fenced|explained|two-objects|two-fences|malformed-object|broken-object|broken-array|unknown-shape|foreign-ids|claude-valid|claude-string)
    model=$(jq -Rrs --arg mode "$JIRA_MODEL_RESULT" '
      capture("ROUTINE_DATA_BEGIN\\n(?<data>[\\s\\S]*)\\nROUTINE_DATA_END").data|fromjson|. as $d|
      $d.works[0].id as $a|$d.works[1].id as $b|$d.unattached_reports[0].id as $report|
      {merge:[[$a,$b]],attach:[{work:$a,evidence:$report}],
       links:[{work:$a,key:"ABC-1",reason:"feature implementation"}],
       create:[{work:$a,summary:"feature implementation"}],sections:[]} |
      if $mode=="observed-works" then
        .merge|=map({works:.,reason:"same repository and keys"})|
        .attach|=map({work,report:.evidence,reason:"same implementation"})|
        .links|=map(.evidence=[$report])|.create|=map(.evidence=[$report])
      elif $mode=="observed-ids" then
        .merge|=map({ids:.,reason:"same repository and keys"})|
        .attach|=map({work,report:.evidence,reason:"same implementation"})
      elif $mode=="unknown-shape" then .merge|=map({members:.,reason:"unknown alias"})
      elif $mode=="foreign-ids" then .merge[0][1]="w-missing"|.attach[0].evidence="rep:missing"
      elif $mode=="fenced-string" then .links[0].reason="code \u0060\u0060\u0060 example"
      else . end' <<< "$input")
    case $JIRA_MODEL_RESULT in
      fenced|fenced-string) printf '\140\140\140json\n%s\n\140\140\140\n' "$model" ;;
      fenced-upper) printf '\140\140\140JSON\n%s\n\140\140\140\n' "$model" ;;
      fenced-spaced) printf '\140\140\140 json\n%s\n\140\140\140\n' "$model" ;;
      fenced-crlf) printf ' \t\140\140\140 JsOn\t\r\n%s\r\n \t\140\140\140\t\r\n' "$model" ;;
      explained) printf '제안 JSON입니다.\n%s\n위 내용은 승인 전 제안입니다.\n' "$model" ;;
      explained-fenced) printf '제안 JSON입니다.\n\140\140\140json\n%s\n\140\140\140\n위 내용은 승인 전 제안입니다.\n' "$model" ;;
      malformed-object) printf '설명\n{"result":%s\n' "$model" ;;
      broken-object) printf '{"result":%s,broken}\n' "$model" ;;
      broken-array) printf '[broken,%s]\n' "$model" ;;
      two-objects) printf '%s\n%s\n' "$model" "$model" ;;
      two-fences) printf '\140\140\140json\n%s\n\140\140\140\n\140\140\140json\n%s\n\140\140\140\n' "$model" "$model" ;;
      claude-valid) jq -n --argjson model "$model" '{structured_output:$model}' ;;
      claude-string) jq -n --arg model "$(printf '설명\n\140\140\140json\n%s\n\140\140\140\n끝\n' "$model")" '{result:$model}' ;;
      *) printf '%s\n' "$model" ;;
    esac
    exit 0 ;;
esac
jq -Rrs --arg summary "${JIRA_MODEL_SUMMARY:-feature implementation}" 'capture("ROUTINE_DATA_BEGIN\\n(?<data>[\\s\\S]*)\\nROUTINE_DATA_END").data|fromjson|. as $d|{merge:[],attach:[],links:[],create:[$d.works[]|select(.keys|length==0)|{work:.id,summary:$summary}],sections:[$d.works[]|{target:(if (.keys|length)>0 then .keys[0] else .id end),header:"작업 내용",lines:[{text:$summary,evidence:.evidence}]}]}' <<< "$input"
