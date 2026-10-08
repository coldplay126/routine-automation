#!/usr/bin/env bash
set -euo pipefail
[[ $1 == -q ]] || exit 87
shift
auth='' out='' headers='' method='' url='' body=''
while (($#)); do
  arg=$1; shift
  case $arg in
    -K) auth=$1; shift ;; --output) out=$1; shift ;; --dump-header) headers=$1; shift ;;
    --request) method=$1; shift ;; --data-binary) body=${1#@}; shift ;;
    --proto) [[ $1 == '=https' ]] || exit 87; shift ;;
    --max-redirs) [[ $1 == 0 ]] || exit 87; shift ;;
    --connect-timeout|--max-time|--max-filesize|--header|--write-out) shift ;;
    https://example.atlassian.net/*|https://other.atlassian.net/*) url=${arg#https://}; url=/${url#*/} ;;
    *) exit 87 ;;
  esac
done
[[ -f $auth && $(stat -f %Lp "$auth") == 600 && $(wc -l < "$auth") -eq 1 ]] || exit 87
hash=''; [[ -z $body ]] || hash=$(shasum -a 256 "$body" | cut -d ' ' -f 1)
printf '%s %s %s\n' "$method" "$url" "$hash" >> "$JIRA_CALLS"
if [[ -n ${JIRA_REQUEST_LOG:-} && -n $body ]]; then jq -c --arg method "$method" --arg path "$url" '{method:$method,path:$path,body:.}' "$body" >> "$JIRA_REQUEST_LOG"; fi
printf 'HTTP/1.1 200 OK\r\nRetry-After: 0\r\n\r\n' > "$headers"
code=${JIRA_READ_CODE:-200}; exit_code=0
if [[ $method != GET && $url != /rest/api/3/search/jql ]]; then
  code=${JIRA_WRITE_CODE:-200}; exit_code=${JIRA_WRITE_EXIT:-0}
  if [[ -n ${JIRA_LEDGER:-} ]]; then jq -e 'any(.entries[];.state=="applying" and (.attempts|length)>0)' "$JIRA_LEDGER" >/dev/null || exit 87; fi
  if [[ ${JIRA_CRASH:-} == before ]]; then kill -TERM "$JIRA_PARENT_PID"; exit 143; fi
  if [[ ${JIRA_EFFECT:-1} == 1 ]]; then
    write_at=${JIRA_WRITE_AT:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}
    case $url in
      /rest/api/3/issue/*/comment)
        jq --slurpfile b "$body" --arg now "$write_at" '.comments += [{id:((.comments|length)+1|tostring),body:$b[0].body,author:{accountId:"fixture-account"},created:$now,property:$b[0].properties[0].value}]' "$JIRA_SERVER" > "$JIRA_SERVER.new" ;;
      /rest/api/3/issue/*/transitions)
        jq '.issue.fields.status={id:"3",statusCategory:{key:"indeterminate"}}' "$JIRA_SERVER" > "$JIRA_SERVER.new" ;;
      /rest/api/3/issue/*)
        jq --slurpfile b "$body" --arg now "$write_at" --arg race_at "${JIRA_RACE_AT:-$write_at}" --argjson race "${JIRA_RACE:-0}" '.issue.fields.description=$b[0].fields.description|.issue.fields.updated=$now|.history += (if $race==1 then [{created:$race_at,author:{accountId:"other"},items:[{field:"description",fromString:"human content"}]}] else [] end)+[{created:$now,author:{accountId:"fixture-account"},items:[{field:"description"}]}]' "$JIRA_SERVER" > "$JIRA_SERVER.new" ;;
      /rest/api/3/issue)
        jq --slurpfile b "$body" --arg now "$write_at" '.issue={id:"200",key:"ABC-2",fields:($b[0].fields+{created:$now,updated:$now,reporter:{accountId:"fixture-account"},issuetype:{id:"10",name:"작업",hierarchyLevel:0},status:{id:"1",statusCategory:{key:"new"}}}),properties:{"routine-automation":$b[0].properties[0].value}}|.created=true' "$JIRA_SERVER" > "$JIRA_SERVER.new" ;;
      *) exit 87 ;;
    esac
    mv "$JIRA_SERVER.new" "$JIRA_SERVER"
    if [[ $method == PUT && -n ${JIRA_ADF_MODE:-} ]]; then
      jq --arg mode "$JIRA_ADF_MODE" 'if $mode=="semantic" then .issue.fields.description.content[0].content[0].text="changed semantic text" else .issue.fields.description|=walk(if type=="object" then .attrs=((.attrs // {})+{localId:"ignored"}) else . end) end' "$JIRA_SERVER" > "$JIRA_SERVER.new"
      mv "$JIRA_SERVER.new" "$JIRA_SERVER"
    fi
    printf '%s\n' "$method $url" >> "$JIRA_EFFECTS"
    if [[ ${JIRA_CRASH:-} == after ]]; then kill -TERM "$JIRA_PARENT_PID"; exit 143; fi
  fi
fi
case "$method $url" in
  'GET /rest/api/3/myself') printf '{"accountId":"fixture-account"}\n' > "$out" ;;
  'GET /rest/api/3/issuetype/'*) printf '{"id":"10","name":"작업","hierarchyLevel":0}\n' > "$out" ;;
  'GET /rest/api/3/issue/createmeta/'*) printf '{"startAt":0,"maxResults":100,"total":2,"fields":[{"fieldId":"summary","required":true,"name":"요약"},{"fieldId":"assignee","required":false,"name":"담당자"}]}\n' > "$out" ;;
  'GET /rest/api/3/issue/'*'/transitions?'*) jq '{transitions:.transitions}' "$JIRA_SERVER" > "$out" ;;
  'GET /rest/api/3/issue/'*'/changelog?'*) jq '{startAt:0,isLast:true,values:.history}' "$JIRA_SERVER" > "$out" ;;
  'GET /rest/api/3/issue/'*'/comment?'*) jq '{startAt:0,total:(.comments|length),comments:.comments}' "$JIRA_SERVER" > "$out" ;;
  'GET /rest/api/3/comment/'*'/properties/routine-automation')
    id=${url#/rest/api/3/comment/}; id=${id%%/*}
    jq --arg id "$id" '[.comments[]|select(.id==$id and .property!=null)|{value:.property}]|first // {}' "$JIRA_SERVER" > "$out"
    [[ $(jq 'has("value")' "$out") == true ]] || code=404 ;;
  'GET /rest/api/3/issue/'*'/properties/routine-automation')
    jq '{value:.issue.properties["routine-automation"]}' "$JIRA_SERVER" > "$out"
    [[ $(jq '.value!=null' "$out") == true ]] || code=404 ;;
  'GET /rest/api/3/issue/'*'/comment/'*) id=${url##*/}; jq --arg id "$id" '.comments[]|select(.id==$id)' "$JIRA_SERVER" > "$out" ;;
  'GET /rest/api/3/issue/'*'?fields='*) jq .issue "$JIRA_SERVER" > "$out" ;;
  'POST /rest/api/3/search/jql')
    if [[ -n ${JIRA_CANDIDATES:-} ]] && jq -e '.jql|startswith("assignee = currentUser()") and contains("updated >= -")' "$body" >/dev/null; then
      jq --slurpfile b "$body" --slurpfile candidates "$JIRA_CANDIDATES" '{isLast:true,issues:[$candidates[0][]|.fields|=with_entries(select(.key as $key|$b[0].fields|index($key)!=null))]}' "$JIRA_SERVER" > "$out"
    elif [[ -n ${JIRA_DUPLICATES:-} ]] && jq -e '.jql|startswith("project = ")' "$body" >/dev/null; then
      jq --slurpfile b "$body" --slurpfile duplicates "$JIRA_DUPLICATES" '{isLast:true,issues:[$duplicates[0][]|.fields|=with_entries(select(.key as $key|$b[0].fields|index($key)!=null))]}' "$JIRA_SERVER" > "$out"
    else jq --slurpfile b "$body" '{isLast:true,issues:(if .created==true and ($b[0].jql|contains("reporter = currentUser()")) then [.issue] else [] end)}' "$JIRA_SERVER" > "$out"; fi ;;
  'POST /rest/api/3/issue/'*'/comment') jq '{id:(.comments|length|tostring)}' "$JIRA_SERVER" > "$out" ;;
  'POST /rest/api/3/issue') jq '.issue|{id,key}' "$JIRA_SERVER" > "$out" ;;
  'PUT /rest/api/3/issue/'*|'POST /rest/api/3/issue/'*'/transitions') printf '{}\n' > "$out" ;;
  *) exit 87 ;;
esac
if [[ ${JIRA_CRASH:-} == applied && $method == GET && $url == *'?fields='* ]] && jq -e 'any(.entries[];.state=="applied")' "$JIRA_LEDGER" >/dev/null; then kill -TERM "$JIRA_PARENT_PID"; exit 143; fi
if [[ -n ${JIRA_ROUTES:-} && -s $JIRA_ROUTES ]]; then
  route=$(jq -c --arg method "$method" --arg path "$url" --argjson request "$(if [[ -n $body ]]; then cat "$body"; else echo '{}'; fi)" '[.[]|. as $r|select(.method==$method and ($path|startswith($r.prefix)))|select((has("token")|not) or .token==$request.nextPageToken)|select((has("jql_contains")|not) or ($request.jql|contains($r.jql_contains)))]|first // null' "$JIRA_ROUTES")
  if [[ $route != null ]]; then
    jq .body <<< "$route" > "$out"; code=$(jq -r '.http // 200' <<< "$route"); exit_code=$(jq -r '.exit // 0' <<< "$route")
  fi
fi
printf '%s' "$code"
exit "$exit_code"
