#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034 # Entrypoints supply dynamically scoped session values and consume helper outputs.
# shellcheck source=ui.sh
source "$share_dir/ui.sh"

routine_jira_require() {
  local errors
  [[ $(routine_get jira.enabled) == true ]] || { echo 'Jira 동기화가 꺼져 있습니다: routine config set jira.enabled true' >&2; return 2; }
  errors=$(command jq -L "$share_dir" -r 'include "config"; jira_required_errors|join(", ")' <<< "$ROUTINE_SETTINGS") || return 2
  [[ -z $errors ]] || { printf 'Jira 설정 오류: %s\n' "$errors" >&2; return 2; }
}
routine_jira_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
routine_jira_random() { od -An -N8 -tx1 /dev/urandom | tr -d ' \n'; }
routine_jira_safe_file() { [[ ! -L $1 && ( ! -e $1 || ( -f $1 && -O $1 ) ) ]]; }
routine_jira_directory() {
  local path=$1
  [[ ! -L $path && ( ! -e $path || ( -d $path && -O $path ) ) ]] || return 2
  mkdir -p "$path" && chmod 700 "$path"
}
routine_jira_store() {
  local source=$1 target=$2 temp
  routine_jira_safe_file "$target" || { echo 'Jira 저장 파일이 안전하지 않습니다.' >&2; return 2; }
  temp=$(mktemp "${target%/*}/.jira.XXXXXXXX") || return 2
  if command jq -L "$share_dir" 'include "redact"; walk(if type=="string" then redact else . end)' "$source" > "$temp" && chmod 600 "$temp" && mv -f "$temp" "$target"; then return 0; fi
  rm -f -- "$temp"; return 1
}
routine_jira_lock_live() {
  local path=$1 pid start current age
  [[ -d $path && ! -L $path ]] || return 1
  pid=$(cat "$path/pid" 2>/dev/null || true)
  if [[ -z $pid ]]; then
    age=$(($(date +%s)-$(stat -f %m "$path" 2>/dev/null || echo 0)))
    ((age<10)); return
  fi
  [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null || return 1
  start=$(cat "$path/lstart" 2>/dev/null || true)
  current=$(ps -o lstart= -p "$pid" 2>/dev/null || true)
  [[ -n $start && $start == "$current" ]]
}
routine_jira_lock_owned() {
  [[ -d $jira_dir/.lock && ! -L $jira_dir/.lock && $(cat "$jira_dir/.lock/pid" 2>/dev/null) == "$$" && $(cat "$jira_dir/.lock/lstart" 2>/dev/null) == "$jira_lstart" ]]
}
routine_jira_lock_message() {
  local kind=확인중 pid=미확인 value
  if routine_jira_safe_file "$jira_dir/.lock/kind"; then
    value=$(cat "$jira_dir/.lock/kind" 2>/dev/null || true)
    case $value in propose|review|apply|links|close) kind=$value ;; esac
  fi
  if routine_jira_safe_file "$jira_dir/.lock/pid"; then
    value=$(cat "$jira_dir/.lock/pid" 2>/dev/null || true)
    [[ ! $value =~ ^[1-9][0-9]*$ ]] || pid=$value
  fi
  printf '다른 Jira 작업(%s, pid %s) 실행 중 — 끝난 뒤 다시 실행하세요.\n' "$kind" "$pid" >&2
}
routine_jira_lock() {
  local kind=$1 recovery="$jira_dir/.recovery.lock" age
  if ! mkdir "$jira_dir/.lock" 2>/dev/null; then
    if routine_jira_lock_live "$jira_dir/.lock"; then routine_jira_lock_message; return 4; fi
    if ! mkdir "$recovery" 2>/dev/null; then
      age=$(($(date +%s)-$(stat -f %m "$recovery" 2>/dev/null || echo 0)))
      if ((age<60)) || ! rmdir "$recovery" 2>/dev/null || ! mkdir "$recovery" 2>/dev/null; then routine_jira_lock_message; return 4; fi
    fi
    if routine_jira_lock_live "$jira_dir/.lock"; then rmdir "$recovery"; routine_jira_lock_message; return 4; fi
    [[ ! -L $jira_dir/.lock ]] || { rmdir "$recovery"; return 2; }
    rm -f -- "$jira_dir/.lock/pid" "$jira_dir/.lock/lstart" "$jira_dir/.lock/kind"
    if ! rmdir "$jira_dir/.lock" 2>/dev/null || ! mkdir "$jira_dir/.lock" 2>/dev/null; then rmdir "$recovery"; routine_jira_lock_message; return 4; fi
    rmdir "$recovery"
  fi
  jira_lstart=$(ps -o lstart= -p "$$") || return 2
  printf '%s\n' "$$" > "$jira_dir/.lock/pid"
  printf '%s\n' "$jira_lstart" > "$jira_dir/.lock/lstart"
  printf '%s\n' "$kind" > "$jira_dir/.lock/kind"
}
routine_jira_cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n ${jira_auth:-} ]]; then rm -f -- "$jira_auth"; fi
  if [[ -n ${jira_lstart:-} ]] && routine_jira_lock_owned; then
    rm -f -- "$jira_dir/.lock/pid" "$jira_dir/.lock/lstart" "$jira_dir/.lock/kind"; rmdir "$jira_dir/.lock"
  fi
  [[ -z ${jira_work:-} ]] || rm -rf -- "$jira_work"
  exit "$status"
}
routine_jira_cleanup_orphans() {
  local path pid start current
  for path in "${TMPDIR:-/tmp}"/routine-jira.*; do
    [[ -d $path && ! -L $path && -O $path && $(stat -f %Lp "$path") == 700 ]] || continue
    [[ -f $path/kind && ! -L $path/kind && -O $path/kind && $(cat "$path/kind") == routine-jira-work-v1 ]] || continue
    if ! routine_jira_safe_file "$path/pid" || ! routine_jira_safe_file "$path/lstart"; then continue; fi
    [[ -f $path/pid && -f $path/lstart ]] || continue
    pid=$(cat "$path/pid"); start=$(cat "$path/lstart")
    [[ $pid =~ ^[1-9][0-9]*$ && -n $start ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      current=$(ps -o lstart= -p "$pid" 2>/dev/null || true)
      [[ -n $current && $current != "$start" ]] || continue
    fi
    rm -rf -- "$path"
  done
}
routine_jira_session() {
  jira_dir="$HOME/Library/Application Support/routine-automation/jira"
  routine_jira_directory "$jira_dir" || return 2
  routine_jira_cleanup_orphans
  jira_work=$(mktemp -d "${TMPDIR:-/tmp}/routine-jira.XXXXXXXX") || return 2
  chmod 700 "$jira_work"
  jira_auth="$jira_work/auth.conf"; jira_lstart=''; jira_abort=0
  jira_site=$(routine_get jira.site); jira_account=''; jira_deadline=0
  [[ ${1:-interactive} != propose ]] || jira_deadline=$(($(date +%s)+540))
  trap routine_jira_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  printf '%s\n' "$$" > "$jira_work/pid"
  ps -o lstart= -p "$$" > "$jira_work/lstart"
  printf '%s\n' routine-jira-work-v1 > "$jira_work/kind"
  chmod 600 "$jira_work/pid" "$jira_work/lstart" "$jira_work/kind"
  local file
  for file in ledger links; do
    routine_jira_safe_file "$jira_dir/$file.json" || return 2
    if [[ ! -e $jira_dir/$file.json ]]; then
      local initial
      initial=$(mktemp "$jira_dir/.jira.XXXXXXXX") || return 2
      if [[ $file == ledger ]]; then printf '{"version":1,"entries":[],"dismissed":[],"markers":[]}\n' > "$initial"
      else printf '{"version":1,"links":[],"rejections":[]}\n' > "$initial"; fi
      chmod 600 "$initial"
      ln "$initial" "$jira_dir/$file.json" 2>/dev/null || routine_jira_safe_file "$jira_dir/$file.json" || { rm -f "$initial"; return 2; }
      rm -f "$initial"
    fi
  done
}
routine_jira_token_help() {
  cat >&2 <<'HELP'
터미널(zsh)에서 숨김 입력으로 등록하세요. -w 대화형 물음은 128자에서 잘립니다. <이메일>은 jira.email 값입니다.
read -rs 't?Jira API 토큰: ' && [[ -n $t ]] && echo && printf 'add-generic-password -U -s routine-automation.jira -a %s -w %s\n' '<이메일>' "$t" | security -i; unset t
HELP
}
routine_jira_authenticate() {
  local email token limit trace=0 status=0
  email=$(routine_get jira.email)
  [[ $email =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ && $jira_site =~ ^https://[a-z0-9][a-z0-9-]*\.atlassian\.net$ ]] || return 2
  limit=$(command -v gtimeout || command -v timeout || true)
  [[ -n $limit ]] || { echo 'Keychain 조회 시간 제한에 gtimeout 또는 timeout이 필요합니다.' >&2; return 2; }
  case $- in *x*) trace=1; set +x ;; esac
  token=$("$limit" -k 2 10 security find-generic-password -s routine-automation.jira -a "$email" -w 2>/dev/null) || status=2
  if [[ $token =~ ^[A-Za-z0-9_=+/.-]+$ ]] && ((status==0)); then
    (umask 077; printf 'user = "%s:%s"\n' "$email" "$token" > "$jira_auth") || status=2
    chmod 600 "$jira_auth" || status=2
  else status=2; fi
  unset token
  ((trace==0)) || set -x
  ((status==0)) || { echo 'Keychain 토큰 없음 또는 읽기 실패 — 시간 제한·접근 권한·허용 문자·인증 파일 권한을 확인하세요.' >&2; routine_jira_token_help; return 2; }
  routine_jira_http GET /rest/api/3/myself '' "$jira_work/myself.json" || { printf 'Jira 연결 실패(HTTP %s / curl %s) — 네트워크·Keychain을 확인한 뒤 다시 실행하세요.\n' "$jira_http" "$jira_curl_exit" >&2; return 1; }
  jira_account=$(command jq -er '.accountId|select(type=="string" and length>0)' "$jira_work/myself.json" 2>/dev/null) || { echo 'Jira 인증 응답 형식 오류 — 네트워크·Keychain을 확인한 뒤 다시 실행하세요.' >&2; return 1; }
}
# One invocation batches all hashes; JSON serialization never adds a newline.
# input is an identity string array; value is a canonical JSON body (HASH-6).
routine_jira_hash_map() (
  local source=$1 dir ref index=0 digest file
  dir=$(mktemp -d "${TMPDIR:-/tmp}/routine-jira-hash.XXXXXXXX") || return 2
  trap 'rm -rf -- "$dir"' EXIT
  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
  local files=()
  while IFS= read -r ref; do
    file="$dir/$index"
    command jq -cSj --argjson index "$index" '.[$index]|if has("value") then .value else .input end' "$source" > "$file" || return 1
    files+=("$file"); index=$((index+1))
  done < <(command jq -r '.[]|.ref' "$source")
  if ((index==0)); then echo '{}'; return; fi
  shasum -a 256 "${files[@]}" > "$dir/sums" || return 1
  : > "$dir/rows"
  index=0
  while read -r digest file; do
    ref=$(command jq -r --argjson index "$index" '.[$index].ref' "$source")
    command jq -nc --arg ref "$ref" --arg hash "$digest" '{key:$ref,value:$hash}' >> "$dir/rows"
    index=$((index+1))
  done < "$dir/sums"
  command jq -s 'from_entries' "$dir/rows"
)
routine_jira_hash_value() {
  command jq -n --slurpfile value "$1" '[{ref:"value",value:$value[0]}]' > "$jira_work/hash-input.json" || return 1
  routine_jira_hash_map "$jira_work/hash-input.json" | command jq -r '.value'
}
routine_jira_adf_hash() {
  jq -L "$share_dir" 'include "jira"; jira_adf_canon' "$1" > "$jira_work/canon.json" || return 1
  printf 'sha256:%s\n' "$(routine_jira_hash_value "$jira_work/canon.json")"
}
routine_jira_read_allowed() {
  local method=$1 path=$2 key='[A-Z][A-Z0-9]{1,9}-[1-9][0-9]*'
  [[ $method == POST && $path == /rest/api/3/search/jql ]] && return 0
  [[ $method == GET ]] || return 1
  [[ $path == /rest/api/3/myself || $path =~ ^/rest/api/3/issuetype/[0-9]+$ || $path =~ ^/rest/api/3/comment/[0-9]+/properties/routine-automation$ || $path =~ ^/rest/api/3/issue/createmeta/[A-Z][A-Z0-9]{1,9}/issuetypes/[0-9]+(\?startAt=[0-9]+\&maxResults=100)?$ ]] && return 0
  [[ $path =~ ^/rest/api/3/issue/$key\?fields=summary,status,issuetype,project,description,updated,created,assignee,reporter$ || $path =~ ^/rest/api/3/issue/$key/transitions\?expand=transitions.fields$ || $path =~ ^/rest/api/3/issue/$key/comment/[0-9]+$ || $path =~ ^/rest/api/3/issue/$key/properties/routine-automation$ || $path =~ ^/rest/api/3/issue/$key/comment\?orderBy=created\&startAt=[0-9]+\&maxResults=100$ || $path =~ ^/rest/api/3/issue/$key/changelog\?startAt=[0-9]+\&maxResults=100$ ]]
}
routine_jira_curl() {
  local method=$1 path=$2 body=$3 out=$4 remaining cap=30
  jira_http=000; jira_curl_exit=0; jira_transport_started=0; jira_stop_reason=''
  if ! routine_jira_read_allowed "$method" "$path"; then
    [[ ${jira_write_transport:-0} == 1 ]] && routine_jira_lock_owned && ui_interactive || return 2
  fi
  ((jira_abort==0)) || { jira_stop_reason=authentication; return 3; }
  if ((jira_deadline>0)); then
    remaining=$((jira_deadline-$(date +%s)))
    ((remaining>0)) || { jira_stop_reason=deadline; echo 'Jira 읽기 시간 초과 — 필요한 제안은 다시 실행하세요.' >&2; return 3; }
    ((remaining>=cap)) || cap=$remaining
  fi
  local args=(-q --proto '=https' --max-redirs 0 --connect-timeout 10 --max-time "$cap" --max-filesize 8388608 -K "$jira_auth" --request "$method" --header 'Accept: application/json' --output "$out" --dump-header "$jira_work/headers" --write-out '%{http_code}')
  [[ -z $body ]] || args+=(--header 'Content-Type: application/json' --data-binary "@$body")
  jira_transport_started=1
  jira_http=$(curl "${args[@]}" "$jira_site$path" 2>/dev/null) || jira_curl_exit=$?
  [[ $jira_http =~ ^[0-9]{3}$ ]] || jira_http=000
  [[ $jira_http != 401 ]] || { jira_abort=1; echo 'Jira 인증 실패(HTTP 401) — 이메일·토큰을 확인하고 다시 등록하세요.' >&2; routine_jira_token_help; }
  ((jira_curl_exit==0)) && [[ $jira_http == 2?? ]]
}
routine_jira_http() {
  local method=$1 path=$2 body=$3 out=$4 attempt delay
  routine_jira_read_allowed "$method" "$path" || { echo '허용되지 않은 Jira 읽기 요청' >&2; return 2; }
  for attempt in 1 2 3; do
    if routine_jira_curl "$method" "$path" "$body" "$out"; then
      command jq -e . "$out" >/dev/null 2>&1 || return 1
      return 0
    fi
    ((jira_abort==0)) || return 1
    [[ $jira_http == 429 || $jira_http == 5?? ]] || return 1
    ((attempt<3)) || return 1
    delay=$attempt
    if [[ $jira_http == 429 ]]; then
      delay=$(command jq -Rrs 'split("\n")|map(select(test("^Retry-After:";"i"))|capture(": * (?<n>[0-9]+)";"x").n|tonumber)|first // 1|[.,30]|min' "$jira_work/headers" 2>/dev/null) || delay=1
    fi
    ((jira_deadline==0 || $(date +%s)+delay<jira_deadline)) || { jira_stop_reason=deadline; return 1; }
    sleep "$delay"
  done
}
routine_jira_pages() {
  local mode=$1 path=$2 body=$3 out=$4 max=${5:-20} page=0 offset=0 token='' seen='[]' count total next done_page=0
  printf '[]\n' > "$out"
  jira_pages_complete=false; jira_pages_count=0
  while ((page<max)); do
    if [[ $mode == search ]]; then
      command jq --arg token "$token" '.maxResults=100|if $token=="" then del(.nextPageToken) else .nextPageToken=$token end' "$body" > "$jira_work/page-request.json"
      routine_jira_http POST "$path" "$jira_work/page-request.json" "$jira_work/page.json" || return 1
      command jq -e '(.issues|type=="array") and (.isLast|type=="boolean")' "$jira_work/page.json" >/dev/null || return 1
      next=$(command jq -r '.nextPageToken // ""' "$jira_work/page.json")
      [[ $(command jq -r .isLast "$jira_work/page.json") != true ]] || done_page=1
      count=$(command jq '.issues|length' "$jira_work/page.json")
      command jq --slurpfile p "$jira_work/page.json" '.+$p[0].issues' "$out" > "$jira_work/page-merged.json"
    else
      if [[ $mode == comments ]]; then next="$path?orderBy=created&startAt=$offset&maxResults=100"
      else next="$path?startAt=$offset&maxResults=100"; fi
      routine_jira_http GET "$next" '' "$jira_work/page.json" || return 1
      command jq -e --arg mode "$mode" '(if $mode=="comments" then .comments elif $mode=="meta" then .fields else .values end|type=="array") and (.startAt|type=="number") and (if $mode=="changelog" then .isLast|type=="boolean" else .total|type=="number" end)' "$jira_work/page.json" >/dev/null || return 1
      [[ $(command jq -r .startAt "$jira_work/page.json") == "$offset" ]] || return 1
      count=$(command jq --arg mode "$mode" 'if $mode=="comments" then .comments|length elif $mode=="meta" then .fields|length else .values|length end' "$jira_work/page.json")
      total=$(command jq -r '.total // 0' "$jira_work/page.json")
      if [[ $mode == changelog ]]; then [[ $(command jq -r .isLast "$jira_work/page.json") != true ]] || done_page=1
      elif ((offset+count>=total)); then done_page=1; fi
      command jq --arg mode "$mode" --slurpfile p "$jira_work/page.json" '.+(if $mode=="comments" then $p[0].comments elif $mode=="meta" then $p[0].fields else $p[0].values end)' "$out" > "$jira_work/page-merged.json"
    fi
    mv "$jira_work/page-merged.json" "$out"
    page=$((page+1)); jira_pages_count=$page
    if ((done_page)); then jira_pages_complete=true; return 0; fi
    ((count>0)) || return 1
    if [[ $mode == search ]]; then
      [[ -n $next ]] && ! command jq -e --arg token "$next" 'index($token)!=null' <<< "$seen" >/dev/null || return 1
      seen=$(command jq -c --arg token "$next" '.+[$token]' <<< "$seen"); token=$next
    else offset=$((offset+count)); fi
  done
  return 1
}
routine_jira_cwd_repos() {
  local source=$1 cwd root origin repo limit
  limit=$(command -v gtimeout || command -v timeout || true)
  [[ -n $limit ]] || { echo '{}'; return 0; }
  : > "$jira_work/cwd.rows"
  while IFS= read -r cwd; do
    repo=''
    if [[ -n $cwd ]] && root=$("$limit" -k 1 5 git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
      origin=$("$limit" -k 1 5 git -C "$root" config --get remote.origin.url 2>/dev/null || true)
      if [[ -n $origin ]]; then repo=${origin##*/}; repo=${repo##*:}; repo=${repo%.git}; else repo=${root##*/}; fi
    fi
    command jq -nc --arg cwd "$cwd" --arg repo "$repo" '{key:$cwd,value:(if $repo=="" then null else $repo end)}' >> "$jira_work/cwd.rows"
  done < <(command jq -r '[.sessions[]?.cwd]|unique[]' "$source")
  command jq -s 'from_entries' "$jira_work/cwd.rows"
}
routine_jira_fetch_issue() {
  local key=$1 out=$2 hash
  [[ $key =~ ^[A-Z][A-Z0-9]{1,9}-[1-9][0-9]*$ ]] || return 2
  routine_jira_http GET "/rest/api/3/issue/$key?fields=summary,status,issuetype,project,description,updated,created,assignee,reporter" '' "$out" || return 1
  command jq -e '(.id|type=="string") and (.key|type=="string") and (.fields|type=="object") and (.fields.project.key|type=="string") and (.fields.issuetype.hierarchyLevel|type=="number") and (.fields.status.id|type=="string")' "$out" >/dev/null || return 1
  command jq '.fields.description' "$out" > "$jira_work/description.json"
  hash=$(routine_jira_adf_hash "$jira_work/description.json") || return 1
  jira_fetched_hash=$hash
}
routine_jira_comments() {
  local key=$1 out=$2 comment id property has_property
  routine_jira_pages comments "/rest/api/3/issue/$key/comment" '' "$out" || return 1
  : > "$jira_work/comments.rows"
  while IFS= read -r comment; do
    property='[]'; has_property=false
    if [[ $(command jq -r '.author.accountId' <<< "$comment") == "$jira_account" ]]; then
      id=$(command jq -r .id <<< "$comment")
      if command jq -e --arg id "$id" --arg site "$jira_site" --arg account "$jira_account" --arg key "$key" 'any(.entries[];.site==$site and .account_id==$account and .kind=="comment" and .key==$key and .result.comment_id==$id)' "$jira_dir/ledger.json" >/dev/null; then
        property=$(command jq -c --arg id "$id" --arg site "$jira_site" --arg account "$jira_account" '[.entries[]|select(.site==$site and .account_id==$account and .result.comment_id==$id)|.events[]]|unique' "$jira_dir/ledger.json"); has_property=true
      elif routine_jira_http GET "/rest/api/3/comment/$id/properties/routine-automation" '' "$jira_work/property.json"; then
        property=$(command jq -ec '.value.events // []|select(type=="array" and all(.[];type=="string"))' "$jira_work/property.json") || return 1
        has_property=true
      elif [[ $jira_http != 404 ]]; then return 1; fi
    fi
    command jq -c --argjson events "$property" --argjson present "$has_property" '.+{_events:$events,_has_property:$present}' <<< "$comment" >> "$jira_work/comments.rows"
  done < <(command jq -c '.[]' "$out")
  command jq -s . "$jira_work/comments.rows" > "$out"
}
routine_jira_duplicate_search() {
  local project=$1 summary=$2 evidence=$3 out=$4 query key kind max complete=true pages=0 reason='' query_pages
  local deadline_saved=$jira_deadline
  max=$(routine_get jira.duplicate_max_pages)
  jq -L "$share_dir" -n --arg project "$project" --arg summary "$summary" --slurpfile evidence "$evidence" '
    include "jira";
    [$evidence[0][]|select(.kind=="pr")|.url] as $urls |
    ([$evidence[0][].repo // empty]|unique) as $repos |
    ([$repos[]|.,(jira_settings.repos[.].prefix // "")]|map(jira_tokens)|add // []) as $scope |
    jira_new_queries($project;$summary;$urls;$scope;jira_summary_tags($repos;jira_settings))' > "$jira_work/queries.json"
  if ! command jq -e 'any(.[];.kind=="summary" and .word_count>=2)' "$jira_work/queries.json" >/dev/null; then complete=false; reason=insufficient_summary_words; fi
  printf '[]\n' > "$jira_work/matches.json"
  printf '[]\n' > "$jira_work/possible.json"
  printf '{}\n' > "$jira_work/duplicate-comment-cache.json"
  while IFS= read -r query; do
    kind=$(command jq -r .kind <<< "$query")
    command jq -n --argjson query "$query" --slurpfile ledger "$jira_dir/ledger.json" --arg site "$jira_site" --arg account "$jira_account" --arg now "$(routine_jira_now)" '
      {jql:$query.jql,fields:(["summary","status","issuetype","project","assignee","created"]+(if $query.kind=="url" then ["description"] else [] end)),maxResults:100,properties:["routine-automation"],
       reconcileIssues:[$ledger[0].entries[]|select(.site==$site and .account_id==$account and .kind=="create_issue" and .result.issue_id!=null and ((.approved_at|fromdateiso8601)>=($now|fromdateiso8601)-604800))|.result.issue_id|tonumber]}' > "$jira_work/search-request.json"
    if routine_jira_pages search /rest/api/3/search/jql "$jira_work/search-request.json" "$jira_work/search-results.json" "$max"; then
      query_pages=$jira_pages_count
      jq -L "$share_dir" --arg summary "$summary" --argjson query "$query" 'include "jira"; [.[]|select(jira_duplicate_match($summary;$query))|.key]' "$jira_work/search-results.json" > "$jira_work/query-matches.json"
      command jq --slurpfile matches "$jira_work/query-matches.json" '.+$matches[0]|unique' "$jira_work/matches.json" > "$jira_work/matches-new.json"
      mv "$jira_work/matches-new.json" "$jira_work/matches.json"
      if [[ $kind == url ]]; then
        command jq --slurpfile exact "$jira_work/query-matches.json" '[.[]|.key|select(. as $key|$exact[0]|index($key)==null)]|unique' "$jira_work/search-results.json" > "$jira_work/url-possible.json"
        command jq --slurpfile possible "$jira_work/url-possible.json" '.+$possible[0]|unique' "$jira_work/possible.json" > "$jira_work/possible-new.json"
        mv "$jira_work/possible-new.json" "$jira_work/possible.json"
        while IFS= read -r key; do
          if ! command jq -e --arg key "$key" 'has($key)' "$jira_work/duplicate-comment-cache.json" >/dev/null; then
            if routine_jira_pages comments "/rest/api/3/issue/$key/comment" '' "$jira_work/duplicate-comments.json"; then
              command jq --arg key "$key" --slurpfile comments "$jira_work/duplicate-comments.json" '.[$key]=$comments[0]' "$jira_work/duplicate-comment-cache.json" > "$jira_work/cache-new.json"
              mv "$jira_work/cache-new.json" "$jira_work/duplicate-comment-cache.json"
            else complete=false; reason=read_incomplete; fi
          fi
          if jq -L "$share_dir" -e --arg key "$key" --arg summary "$summary" --argjson query "$query" '
            include "jira"; {fields:{},comments:(.[$key] // [])}|jira_duplicate_match($summary;$query)' "$jira_work/duplicate-comment-cache.json" >/dev/null; then
            command jq --arg key "$key" '.+[$key]|unique' "$jira_work/matches.json" > "$jira_work/matches-new.json"
            mv "$jira_work/matches-new.json" "$jira_work/matches.json"
          fi
          ((jira_abort==0)) || break
        done < <(command jq -r --slurpfile matches "$jira_work/matches.json" '.[]|select(. as $key|$matches[0]|index($key)==null)' "$jira_work/url-possible.json")
      fi
    else query_pages=$jira_pages_count; complete=false; reason=read_incomplete; fi
    pages=$((pages+query_pages))
    ((jira_abort==0)) || break
  done < <(command jq -c '.[]' "$jira_work/queries.json")
  jira_deadline=$deadline_saved
  command jq -n --argjson complete "$complete" --argjson pages "$pages" --arg reason "$reason" --slurpfile queries "$jira_work/queries.json" --slurpfile matches "$jira_work/matches.json" --slurpfile possible "$jira_work/possible.json" --arg checked "$(routine_jira_now)" '{complete:$complete,reason:(if $reason=="" then null else $reason end),pages:$pages,queries:($queries[0]|length),matches:$matches[0],possible:($possible[0]-$matches[0]),checked_at:$checked}' > "$out"
}
routine_jira_meta() {
  local project=$1 type=$2 out=$3
  routine_jira_http GET "/rest/api/3/issuetype/$type" '' "$jira_work/type.json" || return 1
  command jq -e '.hierarchyLevel==0' "$jira_work/type.json" >/dev/null || return 1
  routine_jira_pages meta "/rest/api/3/issue/createmeta/$project/issuetypes/$type" '' "$jira_work/fields.json" 10 || return 1
  command jq -e 'all(.[];.required!=true or .hasDefaultValue==true or .defaultValue!=null or ((.fieldId // .key)|IN("project","issuetype","summary","description","reporter","assignee")))' "$jira_work/fields.json" >/dev/null || return 1
  command jq '{ok:true,name:.name}' "$jira_work/type.json" > "$out"
}
routine_jira_read_context() {
  command jq -n --arg site "$jira_site" --arg account "$jira_account" --argjson config "$(routine_get jira)" --slurpfile ledger "$jira_dir/ledger.json" --slurpfile links "$jira_dir/links.json" '{site:$site,account_id:$account,config:$config,ledger:$ledger[0],links:$links[0],evidence:[],works:[],issues:{},issue_reads:{},errors:[],comments:{},transitions:{},llm:{merge:[],attach:[],links:[],create:[],sections:[]},llm_valid:false,allowed_keys:[],duplicates:{},create_meta:{}}' > "$1"
}
routine_jira_read_failure() {
  local context=$1 key=$2 stage=$3 message
  if [[ ${jira_stop_reason:-} == deadline ]]; then message="$stage 읽기 시간 초과"
  elif [[ $jira_http == 404 && $stage == 이슈 ]]; then message='이슈 없음 또는 권한 없음'
  elif [[ $jira_http == 2?? && $jira_curl_exit == 0 ]]; then message="$stage 응답 형식·내용 확인 실패"
  else message="$stage 읽기 실패: HTTP $jira_http / curl $jira_curl_exit"; fi
  [[ -z $key ]] || message="$key — $message"
  command jq --arg key "$key" --arg stage "$stage" --arg message "$message" --argjson http "$jira_http" --argjson curl "$jira_curl_exit" '
    .errors=((.errors+[{source:"jira",message:$message}])|unique)|
    if $stage=="이슈" then .issue_reads[$key]={status:"failed",http:$http,curl_exit:$curl,message:$message} else . end' "$context" > "$jira_work/ctx-new.json"
  mv "$jira_work/ctx-new.json" "$context"
}
routine_jira_propose_issue() {
  local key=$1 context=$2 mode=${3:-fresh} reads='{"transitions":"skipped","changelog":"skipped","comments":"skipped"}' transition_needed fill_needed comment_needed
  if [[ $mode == needed ]] && command jq -e --arg key "$key" '.issues[$key]!=null' "$context" >/dev/null; then
    command jq --arg key "$key" '.issues[$key]' "$context" > "$jira_work/normalized-issue.json"
    reads=$(command jq -c .reads "$jira_work/normalized-issue.json")
  else
    command jq --arg key "$key" 'del(.issues[$key],.transitions[$key],.comments[$key])' "$context" > "$jira_work/ctx-new.json"; mv "$jira_work/ctx-new.json" "$context"
    if ! routine_jira_fetch_issue "$key" "$jira_work/raw-issue.json"; then routine_jira_read_failure "$context" "$key" 이슈; return 1; fi
    jq -L "$share_dir" --arg key "$key" --arg account "$jira_account" --arg hash "$jira_fetched_hash" --argjson reads "$reads" 'include "jira"; jira_issue($key;$account;$hash;[];$reads)' "$jira_work/raw-issue.json" > "$jira_work/normalized-issue.json" || return 1
  fi
  jq -L "$share_dir" -n --slurpfile issue "$jira_work/normalized-issue.json" --slurpfile ctx "$context" --arg key "$key" '
    include "jira"; $issue[0] as $i|$ctx[0] as $ctx|
    [$ctx.works[]|. as $w|select((.keys|index($key)!=null) or any($ctx.links.links[];jira_context($ctx.site;$ctx.account_id) and .key==$key and (.evidence_id as $id|$w.evidence|index($id)!=null)) or any($ctx.llm.links[];.key==$key and .work==$w.id) or any($ctx.duplicates[$w.id].matches[]?;.==$key))] as $linked|
    {transition:(any($linked[];.active) and $i.assignee_is_me and ($ctx.config.projects[$i.project].statuses.start_from|index($i.status.id)!=null)),
     fill:(any($linked[];.active) and $i.assignee_is_me and ($i.description.state|IN("empty","template_only")) and (jira_fill_blocked($ctx;{id:$i.id};null)|not)),
     comment:(($linked|length)>0)}' > "$jira_work/read-needs.json"
  transition_needed=$(command jq -r .transition "$jira_work/read-needs.json")
  fill_needed=$(command jq -r .fill "$jira_work/read-needs.json")
  comment_needed=$(command jq -r .comment "$jira_work/read-needs.json")
  if [[ ( $transition_needed == true || $fill_needed == true ) && $(command jq -r .changelog <<< "$reads") == skipped ]]; then
    if routine_jira_pages changelog "/rest/api/3/issue/$key/changelog" '' "$jira_work/changelog.json"; then
      reads=$(command jq -c '.changelog="ok"' <<< "$reads")
      jq -L "$share_dir" --arg account "$jira_account" --slurpfile history "$jira_work/changelog.json" 'include "jira"; .status.id as $status|.status.entered_at as $entered|.description_history=($history[0]|jira_history($account))|.status.entered_at=([$history[0][]|select(any(.items[]?;(.field=="status" or .fieldId=="status") and .to==$status))|.created]|sort|last // $entered)' "$jira_work/normalized-issue.json" > "$jira_work/normalized-new.json"
      mv "$jira_work/normalized-new.json" "$jira_work/normalized-issue.json"
    else reads=$(command jq -c '.changelog="partial"' <<< "$reads"); routine_jira_read_failure "$context" "$key" 변경기록; fi
  fi
  if [[ $transition_needed == true && $(command jq -r .transitions <<< "$reads") == skipped ]]; then
    if routine_jira_http GET "/rest/api/3/issue/$key/transitions?expand=transitions.fields" '' "$jira_work/transitions.json" && command jq -e '.transitions|type=="array"' "$jira_work/transitions.json" >/dev/null; then
      reads=$(command jq -c '.transitions="ok"' <<< "$reads")
      command jq --arg key "$key" --slurpfile transitions "$jira_work/transitions.json" '.transitions[$key]=$transitions[0].transitions' "$context" > "$jira_work/ctx-new.json"; mv "$jira_work/ctx-new.json" "$context"
    else reads=$(command jq -c '.transitions="partial"' <<< "$reads"); routine_jira_read_failure "$context" "$key" 전환목록; fi
  fi
  if [[ $comment_needed == true && $(command jq -r .comments <<< "$reads") == skipped ]]; then
    if routine_jira_comments "$key" "$jira_work/issue-comments.json"; then
      reads=$(command jq -c '.comments="ok"' <<< "$reads")
      command jq --arg key "$key" --slurpfile comments "$jira_work/issue-comments.json" '.comments[$key]=$comments[0]' "$context" > "$jira_work/ctx-new.json"; mv "$jira_work/ctx-new.json" "$context"
    else reads=$(command jq -c '.comments="partial"' <<< "$reads"); routine_jira_read_failure "$context" "$key" 댓글; fi
  fi
  command jq --arg key "$key" --argjson reads "$reads" --slurpfile issue "$jira_work/normalized-issue.json" '.issues[$key]=($issue[0]+{reads:$reads})|.issue_reads[$key]={status:"ok",http:200,curl_exit:0}' "$context" > "$jira_work/ctx-new.json"; mv "$jira_work/ctx-new.json" "$context"
}
routine_jira_notices() {
  local marker key hash entry
  printf '[]\n' > "$jira_work/notices.json"
  printf '[]\n' > "$jira_work/notice-updates.json"
  while IFS= read -r marker; do
    key=$(command jq -r .key <<< "$marker"); entry=$(command jq -r .entry_id <<< "$marker")
    routine_jira_fetch_issue "$key" "$jira_work/notice-issue.json" || continue
    hash=$jira_fetched_hash
    if [[ $hash != "$(command jq -r .sent_canon_hash <<< "$marker")" && $hash != "$(command jq -r .notified_hash <<< "$marker")" ]]; then
      command jq --arg message "$(if [[ $(command jq -r .kind <<< "$marker") == fill ]]; then printf '채운 본문'; else printf '만든 이슈의 본문'; fi)이 바뀌었습니다 — $jira_site/browse/$key" '.+[$message]' "$jira_work/notices.json" > "$jira_work/notices-new.json"; mv "$jira_work/notices-new.json" "$jira_work/notices.json"
      command jq --arg entry "$entry" --arg hash "$hash" '.+[{entry_id:$entry,hash:$hash}]' "$jira_work/notice-updates.json" > "$jira_work/notice-updates-new.json"
      mv "$jira_work/notice-updates-new.json" "$jira_work/notice-updates.json"
    fi
  done < <(command jq -c --arg site "$jira_site" --arg account "$jira_account" --arg now "$(routine_jira_now)" '.markers[]|select(.site==$site and .account_id==$account and (.kind|IN("fill","create")) and .confirmed==true and .key!=null and ((.at|fromdateiso8601)>=($now|fromdateiso8601)-7776000))' "$jira_dir/ledger.json")
}
routine_jira_state() {
  local id=$1 state=$2 result=${3:-'{}'} message=${4:-} outcome=${5:-}
  jq -L "$share_dir" --arg id "$id" --arg state "$state" --argjson result "$result" --arg message "$message" --arg outcome "$outcome" --argjson http "${jira_http:-0}" --argjson curl "${jira_curl_exit:-0}" --arg now "$(routine_jira_now)" 'include "jira"; jira_ledger_state($id;$state;$result;$message;$outcome;$http;$curl;$now)' "$jira_dir/ledger.json" > "$jira_work/ledger-new.json" || return 1
  routine_jira_store "$jira_work/ledger-new.json" "$jira_dir/ledger.json"
}
routine_jira_entry() { command jq -e --arg id "$1" '.entries[]|select(.entry_id==$id)' "$jira_dir/ledger.json"; }
routine_jira_context_entry() {
  [[ $(command jq -r .site "$1") == "$jira_site" && $(command jq -r .account_id "$1") == "$jira_account" ]]
}
routine_jira_target() {
  local entry=$1 raw=$2
  jq -L "$share_dir" -e --slurpfile entry "$entry" 'include "jira"; .key==$entry[0].key and .id==$entry[0].issue_id and (.fields.project.key as $p|jira_settings.projects[$p]!=null) and .fields.issuetype.hierarchyLevel<1' "$raw" >/dev/null
}
routine_jira_preflight() {
  local entry=$1 phase=${2:-apply} kind key hash from to transition
  kind=$(command jq -r .kind "$entry"); key=$(command jq -r .key "$entry")
  routine_jira_read_context "$jira_work/check-context.json"
  if ! jq -L "$share_dir" -e --slurpfile ctx "$jira_work/check-context.json" 'include "jira"; .proposal|jira_dependencies_ok($ctx[0])' "$entry" >/dev/null; then return 5; fi
  if [[ $kind == create_issue ]]; then
    if jq -L "$share_dir" -e --slurpfile ctx "$jira_work/check-context.json" 'include "jira"; jira_create_blocked($ctx[0];{evidence:.proposal.evidence};.entry_id)' "$entry" >/dev/null; then return 5; fi
    if [[ $phase == review ]]; then return 0; fi
    command jq '[.proposal.payload.duplicate_input.urls[]|{kind:"pr",url:.}]+[.proposal.payload.duplicate_input.repos[]|{kind:"repo",repo:.}]' "$entry" > "$jira_work/check-evidence.json"
    routine_jira_duplicate_search "$(command jq -r .project "$entry")" "$(command jq -r .proposal.payload.duplicate_input.summary "$entry")" "$jira_work/check-evidence.json" "$jira_work/check-search.json" || return 1
    jq -L "$share_dir" --slurpfile ctx "$jira_work/check-context.json" --slurpfile entry "$entry" 'include "jira"; jira_duplicate_visible($ctx[0];{evidence:$entry[0].proposal.evidence})' "$jira_work/check-search.json" > "$jira_work/check-search-new.json" || return 1
    mv "$jira_work/check-search-new.json" "$jira_work/check-search.json"
    if [[ $(command jq '(.matches+.possible)|length' "$jira_work/check-search.json") != 0 ]]; then
      command jq -r -L "$share_dir" 'include "jira"; "중복 후보 확인 필요 — 생성 반영 안 함: "+((.matches+.possible)|jira_id_examples)' "$jira_work/check-search.json"
      return 5
    fi
    [[ $(command jq -r .complete "$jira_work/check-search.json") == true ]] || return 1
    return 0
  fi
  routine_jira_fetch_issue "$key" "$jira_work/check-issue.json" || return 1
  hash=$jira_fetched_hash
  routine_jira_target "$entry" "$jira_work/check-issue.json" || return 3
  if [[ $kind == link ]]; then return 0; fi
  if [[ $kind == fill_description || $kind == transition ]]; then
    [[ $(command jq -r '.fields.assignee.accountId' "$jira_work/check-issue.json") == "$jira_account" ]] || return 3
    [[ $(command jq -r '.fields.status.statusCategory.key' "$jira_work/check-issue.json") != 'done' ]] || return 3
  fi
  case $kind in
    fill_description)
      if jq -L "$share_dir" -e --slurpfile ctx "$jira_work/check-context.json" 'include "jira"; jira_fill_blocked($ctx[0];{id:.issue_id};.entry_id)' "$entry" >/dev/null; then return 5; fi
      [[ $hash != "$(command jq -r .proposal.payload.adf_canon_hash "$entry")" ]] || return 6
      [[ $hash == "$(command jq -r .snapshot.description_canon_hash "$entry")" && $(command jq -r .fields.updated "$jira_work/check-issue.json") == "$(command jq -r .snapshot.updated "$entry")" ]] || return 3
      ;;
    transition)
      from=$(command jq -r .proposal.payload.from.id "$entry"); to=$(command jq -r .proposal.payload.to.id "$entry")
      if [[ $(command jq -r .fields.status.id "$jira_work/check-issue.json") == "$to" ]]; then [[ $phase == apply ]] && return 6 || return 3; fi
      [[ $(command jq -r .fields.status.id "$jira_work/check-issue.json") == "$from" ]] || return 3
      if command jq -e --arg id "$(command jq -r .proposal_id "$entry")" --arg site "$jira_site" --arg account "$jira_account" 'any(.markers[];.kind=="transition" and .site==$site and .account_id==$account and .proposal_id==$id)' "$jira_dir/ledger.json" >/dev/null; then return 5; fi
      routine_jira_http GET "/rest/api/3/issue/$key/transitions?expand=transitions.fields" '' "$jira_work/check-transitions.json" || return 1
      transition=$(command jq -r .proposal.payload.transition_id "$entry")
      command jq -e --arg id "$transition" --arg to "$to" 'any(.transitions[];.id==$id and .to.id==$to and all(.fields[]?;.required!=true or .hasDefaultValue==true or .defaultValue!=null))' "$jira_work/check-transitions.json" >/dev/null || return 3
      routine_jira_pages changelog "/rest/api/3/issue/$key/changelog" '' "$jira_work/check-history.json" || return 1
      [[ $(jq -L "$share_dir" -r --slurpfile history "$jira_work/check-history.json" 'include "jira"; jira_status_entered($history[0])' "$jira_work/check-issue.json") == "$(command jq -r .snapshot.status_entered_at "$entry")" ]] || return 3
      ;;
    comment)
      routine_jira_comments "$key" "$jira_work/check-comments.json" || return 1
      command jq --arg key "$key" --slurpfile comments "$jira_work/check-comments.json" '.comments[$key]=$comments[0]' "$jira_work/check-context.json" > "$jira_work/check-context-new.json"
      jq -L "$share_dir" --slurpfile ctx "$jira_work/check-context-new.json" 'include "jira"; jira_recorded($ctx[0];.key;.proposal.payload.events;.entry_id)' "$entry" > "$jira_work/check-recorded.json"
      if [[ $(command jq length "$jira_work/check-recorded.json") != 0 ]]; then
        [[ $(command jq length "$jira_work/check-recorded.json") == "$(command jq '.events|length' "$entry")" && $phase == apply ]] && return 6
        return 3
      fi
      ;;
    *) return 2 ;;
  esac
  return 0
}
# This is the only write transport. Both the lock and fresh attempt are checked again.
routine_jira_send() {
  local id=$1 attempt=$2 entry="$jira_work/send-entry.json" method path status=0
  jira_transport_started=0; jira_http=000; jira_curl_exit=0; jira_stop_reason=''
  routine_jira_lock_owned || return 4
  ui_interactive || return 2
  [[ ${jira_authorized_entry:-} == "$id" && ${jira_authorized_attempt:-} == "$attempt" ]] || return 4
  routine_jira_entry "$id" > "$entry" || return 1
  routine_jira_context_entry "$entry" || return 2
  command jq -e --arg attempt "$attempt" --argjson pid "$$" --arg start "$jira_lstart" '.state=="applying" and .attempts[-1].id==$attempt and .attempts[-1].pid==$pid and .attempts[-1].lstart==$start' "$entry" >/dev/null || return 4
  jq -L "$share_dir" -e --argjson config "$(routine_get jira)" 'include "jira"; jira_request_ok($config)' "$entry" >/dev/null || return 2
  command jq '.request.body' "$entry" > "$jira_work/send-body.json"
  [[ $(routine_jira_hash_value "$jira_work/send-body.json") == "$(command jq -r .request_sha256 "$entry")" ]] || return 2
  method=$(command jq -r .request.method "$entry"); path=$(command jq -r .request.path "$entry")
  jira_write_transport=1
  routine_jira_curl "$method" "$path" "$jira_work/send-body.json" "$jira_work/send-response.json" || status=$?
  unset jira_write_transport
  return "$status"
}
routine_jira_apply_one() {
  local id=$1 entry="$jira_work/apply-entry.json" status=0 attempt kind result='{}' next outcome message=''
  routine_jira_lock_owned || return 4
  ui_interactive || return 2
  routine_jira_entry "$id" > "$entry" || return 1
  [[ $(command jq -r .state "$entry") == approved ]] || return 4
  routine_jira_context_entry "$entry" || return 2
  if ! command jq -e --arg now "$(routine_jira_now)" '(.approved_at|fromdateiso8601)>=($now|fromdateiso8601)-86400' "$entry" >/dev/null; then routine_jira_state "$id" void '{}' '승인 후 24시간 경과'; return; fi
  jq -L "$share_dir" -e --argjson config "$(routine_get jira)" 'include "jira"; jira_request_ok($config)' "$entry" >/dev/null || { routine_jira_state "$id" conflict '{}' '승인 요청 허용 목록 불일치 — 다시 propose 필요'; echo '승인 요청 허용 목록 불일치 — routine jira propose를 다시 실행하세요.'; return; }
  command jq .request.body "$entry" > "$jira_work/request-check.json"
  [[ $(routine_jira_hash_value "$jira_work/request-check.json") == "$(command jq -r .request_sha256 "$entry")" ]] || { routine_jira_state "$id" conflict '{}' '승인 요청 해시 불일치'; return; }
  routine_jira_preflight "$entry" apply || status=$?
  case $status in
    0) ;; 3) routine_jira_state "$id" conflict '{}' '반영 직전 대상·스냅샷 불일치'; return ;;
    5) routine_jira_state "$id" blocked '{}' '의존 연결·영구 표지·중복 검사 차단'; return ;;
    6) routine_jira_state "$id" verified '{}' '이미 반영됨 (전송 없음)'; return ;;
    *) return "$status" ;;
  esac
  attempt="a-$(routine_jira_random)"; kind=$(command jq -r .kind "$entry")
  command jq --arg id "$id" --arg attempt "$attempt" --argjson pid "$$" --arg start "$jira_lstart" --arg now "$(routine_jira_now)" '
    .entries|=map(if .entry_id==$id then .state="applying"|.attempts+=[{id:$attempt,pid:$pid,lstart:$start,started_at:$now}] else . end) |
    [.entries[]|select(.entry_id==$id)][0] as $e |
    if $e.kind=="fill_description" then .markers += [{kind:"fill",site:$e.site,account_id:$e.account_id,issue_id:$e.issue_id,key:$e.key,entry_id:$id,sent_canon_hash:$e.proposal.payload.adf_canon_hash,confirmed:false,notified_hash:null,at:$now}] else . end' "$jira_dir/ledger.json" > "$jira_work/ledger-new.json"
  routine_jira_store "$jira_work/ledger-new.json" "$jira_dir/ledger.json" || return 1
  jira_authorized_entry=$id; jira_authorized_attempt=$attempt
  status=0
  routine_jira_send "$id" "$attempt" || status=$?
  unset jira_authorized_entry jira_authorized_attempt
  if ((status!=0 && jira_transport_started==0)); then
    message='네트워크 전송 전 중단 — 시간 제한·터미널·잠금을 확인한 뒤 다시 실행하세요.'
    routine_jira_state "$id" approved '{}' "$message" not_sent
    printf '%s\n' "$message" >&2
    return "$status"
  fi
  if ((jira_curl_exit==6 || jira_curl_exit==7 || jira_curl_exit==35)) || [[ $jira_http == 401 || $jira_http == 429 ]]; then next=approved; outcome=not_sent
  elif ((jira_curl_exit!=0)) || [[ $jira_http == 3?? || $jira_http == 5?? || $jira_http == 000 ]]; then next=unknown; outcome=unknown
  elif [[ $jira_http == 2?? ]]; then
    next=applied; outcome=sent
    if [[ $kind == comment ]]; then result=$(command jq -ec 'select(.id|type=="string" and test("^[0-9]+$"))|{comment_id:.id}' "$jira_work/send-response.json" 2>/dev/null) || { next=unknown; outcome=unknown; }
    elif [[ $kind == create_issue ]]; then result=$(command jq -ec 'select((.id|type=="string") and (.key|type=="string"))|{issue_id:.id,issue_key:.key}' "$jira_work/send-response.json" 2>/dev/null) || { next=unknown; outcome=unknown; }; fi
  else
    outcome=sent
    case $jira_http in
      403|422) next=blocked ;; 409) next=conflict ;;
      400) if [[ $kind == transition || $kind == fill_description ]]; then next=blocked; else next=failed; fi ;;
      404) next=failed ;; *) next=unknown; outcome=unknown ;;
    esac
  fi
  if [[ $next != applied ]]; then
    message="HTTP $jira_http / curl $jira_curl_exit"
    if [[ -s $jira_work/send-response.json ]]; then
      message+=" $(jq -L "$share_dir" -r 'include "redact"; [.errorMessages[]?,(.errors // {}|.[])]|map(tostring)|join("; ")|redact|.[:300]' "$jira_work/send-response.json" 2>/dev/null || true)"
    fi
  fi
  routine_jira_state "$id" "$next" "$result" "$message" "$outcome" || return 1
  if [[ $next == applied ]]; then routine_jira_verify "$id" || true; fi
  ((jira_abort==0))
}
routine_jira_link_save() {
  local proposal=$1 confirmed=$2 key=$3
  command jq --argjson p "$proposal" --arg site "$jira_site" --arg account "$jira_account" --arg key "$key" --arg confirmed "$confirmed" --arg now "$(routine_jira_now)" '
    [$p.evidence[]|select(test("^(pr|git|rep):"))] as $ids|
    .links=([.links[]|select((.site==$site and .account_id==$account and (.evidence_id as $id|$ids|index($id)!=null))|not)]+
      [$ids[]|{site:$site,account_id:$account,evidence_id:.,key:$key,confirmed_by:$confirmed,confirmed_at:$now}])' "$jira_dir/links.json" > "$jira_work/links-new.json"
  routine_jira_store "$jira_work/links-new.json" "$jira_dir/links.json"
}
routine_jira_verify() {
  local id=$1 entry="$jira_work/verify-entry.json" kind key comment hash property status=verified message=''
  routine_jira_entry "$id" > "$entry" || return 1
  routine_jira_context_entry "$entry" || return 2
  [[ $(command jq -r .state "$entry") == applied ]] || return 4
  kind=$(command jq -r .kind "$entry"); key=$(command jq -r '.result.issue_key // .key' "$entry")
  if [[ $kind == comment ]]; then
    comment=$(command jq -r .result.comment_id "$entry")
    routine_jira_http GET "/rest/api/3/issue/$key/comment/$comment" '' "$jira_work/verify-comment.json" || return 1
    command jq .body "$jira_work/verify-comment.json" > "$jira_work/verify-adf.json"; hash=$(routine_jira_adf_hash "$jira_work/verify-adf.json")
    routine_jira_http GET "/rest/api/3/comment/$comment/properties/routine-automation" '' "$jira_work/verify-property.json" || return 1
    if [[ $hash != "$(command jq -r .proposal.payload.adf_canon_hash "$entry")" || $(command jq -r .author.accountId "$jira_work/verify-comment.json") != "$jira_account" || $(command jq -r .value.entry_id "$jira_work/verify-property.json") != "$id" ]]; then status=verify_failed; fi
  else
    routine_jira_fetch_issue "$key" "$jira_work/verify-issue.json" || return 1
    hash=$jira_fetched_hash
    if [[ $kind == create_issue ]]; then
      if ! jq -L "$share_dir" -e --slurpfile entry "$entry" --arg account "$jira_account" --arg hash "$hash" 'include "jira"; jira_created_matches($entry[0];$account;$hash)' "$jira_work/verify-issue.json" >/dev/null; then status=verify_failed; fi
      routine_jira_http GET "/rest/api/3/issue/$key/properties/routine-automation" '' "$jira_work/verify-property.json" || return 1
      [[ $(command jq -r .value.entry_id "$jira_work/verify-property.json") == "$id" ]] || status=verify_failed
    else
      routine_jira_target "$entry" "$jira_work/verify-issue.json" || status=verify_failed
      if [[ $kind == transition ]]; then
        [[ $(command jq -r .fields.status.id "$jira_work/verify-issue.json") == "$(command jq -r .proposal.payload.to.id "$entry")" ]] || status=verify_failed
      else
        [[ $hash == "$(command jq -r .proposal.payload.adf_canon_hash "$entry")" ]] || status=verify_failed
        routine_jira_pages changelog "/rest/api/3/issue/$key/changelog" '' "$jira_work/verify-history.json" || return 1
        if ! command jq -L "$share_dir" -e --arg updated "$(command jq -r .snapshot.updated "$entry")" --arg account "$jira_account" '
          include "jira"; [.[]|select((.created|jira_epoch)>($updated|jira_epoch))|. as $change|.items[]|select(.field=="description" or .fieldId=="description")|{author:$change.author.accountId}]|length==1 and .[0].author==$account' "$jira_work/verify-history.json" >/dev/null; then
          status=verify_failed; message="반영 직전 다른 변경이 있었을 수 있음 — 이슈 기록에서 이전 본문 확인·복구: $jira_site/browse/$key"
        fi
      fi
    fi
  fi
  routine_jira_state "$id" "$status" "$(command jq -nc --arg hash "${hash:-}" '{canon_hash_after:$hash}')" "$message"
  if [[ $status == verify_failed && -n $message ]]; then ui_note 'Jira 본문 경쟁 경고·수동 복구' "$message"; fi
  if [[ $kind == create_issue && $status == verified ]]; then routine_jira_link_save "$(command jq -c .proposal "$entry")" create "$key"; fi
}
routine_jira_reconcile() {
  local id=$1 entry="$jira_work/reconcile-entry.json" kind key hash comment property found=0 match_id='' issue_id='' match_key='' minutes
  routine_jira_entry "$id" > "$entry" || return 1
  routine_jira_context_entry "$entry" || return 2
  if [[ $(command jq -r .state "$entry") == applying ]]; then routine_jira_state "$id" unknown '{}' '이전 실행 결과 불명' unknown; routine_jira_entry "$id" > "$entry"; fi
  if [[ $(command jq -r .state "$entry") == applied ]]; then routine_jira_verify "$id"; return; fi
  [[ $(command jq -r .state "$entry") == unknown ]] || return 4
  kind=$(command jq -r .kind "$entry"); key=$(command jq -r .key "$entry")
  case $kind in
    transition|fill_description)
      routine_jira_fetch_issue "$key" "$jira_work/reconcile-issue.json" || return 1
      routine_jira_target "$entry" "$jira_work/reconcile-issue.json" || return 1
      hash=$jira_fetched_hash
      if [[ $kind == transition ]]; then [[ $(command jq -r .fields.status.id "$jira_work/reconcile-issue.json") == "$(command jq -r .proposal.payload.to.id "$entry")" ]] || return 0
      else [[ $hash == "$(command jq -r .proposal.payload.adf_canon_hash "$entry")" ]] || return 0; fi
      ;;
    comment)
      routine_jira_pages comments "/rest/api/3/issue/$key/comment" '' "$jira_work/reconcile-comments.json" || return 1
      while IFS= read -r comment; do
        match_id=$(command jq -r .id <<< "$comment")
        if routine_jira_http GET "/rest/api/3/comment/$match_id/properties/routine-automation" '' "$jira_work/reconcile-property.json"; then
          property=$(command jq -r .value.entry_id "$jira_work/reconcile-property.json")
          if [[ $property == "$id" ]]; then
            found=$((found+1)); command jq .body <<< "$comment" > "$jira_work/reconcile-adf.json"; hash=$(routine_jira_adf_hash "$jira_work/reconcile-adf.json")
            [[ $hash == "$(command jq -r .proposal.payload.adf_canon_hash "$entry")" ]] || { routine_jira_state "$id" verify_failed '{}' '댓글 표지 본문 불일치'; return; }
            issue_id=$match_id
          fi
        elif [[ $jira_http != 404 ]]; then return 1; fi
      done < <(jq -L "$share_dir" -c --arg account "$jira_account" --slurpfile entry "$entry" 'include "jira"; .[]|select(.author.accountId==$account and (.created|jira_epoch)>=($entry[0].attempts[-1].started_at|jira_epoch)-300)' "$jira_work/reconcile-comments.json")
      ((found!=0)) || return 0
      ((found==1)) || { routine_jira_state "$id" verify_failed '{}' '댓글 표지 중복'; return; }
      ;;
    create_issue)
      minutes=$(command jq -r --arg now "$(routine_jira_now)" '((($now|fromdateiso8601)-(.attempts[-1].started_at|fromdateiso8601))/60|ceil)+10' "$entry")
      command jq -n --arg project "$(command jq -r .project "$entry")" --arg minutes "$minutes" '{jql:("project = \""+$project+"\" AND reporter = currentUser() AND created >= -"+$minutes+"m"),fields:["summary","status","issuetype","project","assignee","created"],properties:["routine-automation"],maxResults:100}' > "$jira_work/reconcile-search.json"
      routine_jira_pages search /rest/api/3/search/jql "$jira_work/reconcile-search.json" "$jira_work/reconcile-results.json" || return 1
      while IFS= read -r key; do
        found=$((found+1)); match_key=$key
        routine_jira_fetch_issue "$key" "$jira_work/reconcile-issue.json" || return 1
        hash=$jira_fetched_hash; issue_id=$(command jq -r .id "$jira_work/reconcile-issue.json")
        if ! jq -L "$share_dir" -e --slurpfile entry "$entry" --arg account "$jira_account" --arg hash "$hash" 'include "jira"; jira_created_matches($entry[0];$account;$hash)' "$jira_work/reconcile-issue.json" >/dev/null; then routine_jira_state "$id" verify_failed '{}' '생성 표지 이슈 불일치'; return; fi
      done < <(command jq -r --arg id "$id" '.[]|select(.properties["routine-automation"].entry_id==$id)|.key' "$jira_work/reconcile-results.json")
      ((found!=0)) || return 0
      ((found==1)) || { routine_jira_state "$id" verify_failed '{}' '생성 표지 중복'; return; }
      ;;
  esac
  if [[ $kind == comment ]]; then routine_jira_state "$id" applied "$(command jq -nc --arg id "$issue_id" '{comment_id:$id}')"
  elif [[ $kind == create_issue ]]; then routine_jira_state "$id" applied "$(command jq -nc --arg id "$issue_id" --arg key "$match_key" '{issue_id:$id,issue_key:$key}')"
  else routine_jira_state "$id" applied; fi
  routine_jira_verify "$id"
}
routine_jira_url() {
  if [[ $(command jq -r .kind "$1") != create_issue ]]; then printf '%s/browse/%s\n' "$jira_site" "$(command jq -r .key "$1")"
  else printf '%s/issues/?jql=%s\n' "$jira_site" "$(command jq -r '("project = \""+.project+"\" AND reporter = currentUser() AND created >= \""+(.attempts[-1].started_at[0:10])+"\"")|@uri' "$1")"; fi
}
routine_jira_unknowns() {
  local entry
  while IFS= read -r entry; do
    printf '%s\n' "$entry" > "$jira_work/url-entry.json"
    printf 'Jira에서 직접 확인하세요 — %s (%s)\n' "$(routine_jira_url "$jira_work/url-entry.json")" "$(command jq -r .entry_id <<< "$entry")" | jq -L "$share_dir" -Rr 'include "jira"; jira_display'
  done < <(command jq -c --arg site "$jira_site" --arg account "$jira_account" '.entries[]|select(.site==$site and ($account=="" or .account_id==$account) and (.state|IN("unknown","applying")))' "$jira_dir/ledger.json")
}
routine_jira_recovery_notices() {
  local messages
  messages=$(jq -L "$share_dir" -r --arg site "$jira_site" --arg account "$jira_account" 'include "jira"; [.entries[]|select(.site==$site and ($account=="" or .account_id==$account) and .kind=="fill_description" and .state=="verify_failed" and (.message // "")!="")|.message|jira_display]|unique|join("\n")' "$jira_dir/ledger.json")
  [[ -z $messages ]] || ui_note 'Jira 본문 경쟁 경고·수동 복구' "$messages"
}
routine_jira_apply_summary() {
  jq -L "$share_dir" -r --argjson ids "$1" 'include "jira"; [.entries[]|select(.entry_id as $id|$ids|index($id)!=null)]|group_by(.state)|map((.[0].state|jira_state_text)+" "+(length|tostring))|join(" · ")|jira_display' "$jira_dir/ledger.json"
}
routine_jira_apply_locked() {
  local id choices run_entries
  routine_jira_lock_owned || return 4
  run_entries=$(command jq -c --arg site "$jira_site" --arg account "$jira_account" '[.entries[]|select(.site==$site and .account_id==$account and (.state|IN("approved","applying","unknown","applied")))|.entry_id]' "$jira_dir/ledger.json")
  while IFS= read -r id; do routine_jira_reconcile "$id" || true; ((jira_abort==0)) || return 1; done < <(command jq -r --arg site "$jira_site" --arg account "$jira_account" '.entries[]|select(.site==$site and .account_id==$account and (.state|IN("applying","unknown","applied")))|.entry_id' "$jira_dir/ledger.json")
  while IFS= read -r id; do routine_jira_state "$id" void '{}' '승인 후 24시간 경과'; done < <(command jq -r --arg site "$jira_site" --arg account "$jira_account" --arg now "$(routine_jira_now)" '.entries[]|select(.site==$site and .account_id==$account and .state=="approved" and (.approved_at|fromdateiso8601)<($now|fromdateiso8601)-86400)|.entry_id' "$jira_dir/ledger.json")
  routine_jira_unknowns
  routine_jira_recovery_notices
  choices=$(jq -L "$share_dir" -c --arg site "$jira_site" --arg account "$jira_account" 'include "jira"; [.entries[]|select(.site==$site and .account_id==$account and .state=="approved")|{value:.entry_id,label:jira_proposal_label}]' "$jira_dir/ledger.json")
  [[ $choices != '[]' ]] || { echo '반영할 승인 항목 없음'; routine_jira_apply_summary "$run_entries"; return 0; }
  ui_note '승인 대기' "$(command jq -r '.[].label' <<< "$choices")"
  ui_confirm '승인한 항목을 지금 반영할까요?' false || { routine_jira_apply_summary "$run_entries"; return 0; }
  while IFS= read -r id; do
    routine_jira_apply_one "$id" || true
    ((jira_abort==0)) || return 1
  done < <(command jq -r --arg site "$jira_site" --arg account "$jira_account" '[.entries[]|select(.site==$site and .account_id==$account and .state=="approved")]|sort_by(.key,(if .kind=="fill_description" then 0 elif .kind=="comment" then 1 elif .kind=="transition" then 2 else 3 end))|.[].entry_id' "$jira_dir/ledger.json")
  routine_jira_apply_summary "$run_entries"
  routine_jira_unknowns
}
routine_jira_summary_file() {
  local proposal=$1
  if [[ -f $proposal ]] && routine_jira_safe_file "$proposal"; then
    jq -L "$share_dir" -e 'include "jira"; jira_proposals_ok' "$proposal" >/dev/null 2>&1 || { echo 'Jira 제안 파일 형식 오류 — routine jira propose를 다시 실행하세요.' >&2; return 1; }
    jq -L "$share_dir" -r --arg site "$(routine_get jira.site)" 'include "jira"; select(.site==$site)|"Jira 제안 \(.proposals|length)건 · 질문 \(.questions|length)건",(.issues|to_entries[]|select(.value.confirmed_link==true)|.key+" — "+(.value.conditions|jira_condition_text))|jira_display' "$proposal"
  else echo '오늘 Jira 제안 없음 — routine jira propose'; fi
}
routine_jira_preview() {
  local proposal=$1 file=$2
  jq -L "$share_dir" -nr --argjson p "$proposal" --slurpfile file "$file" 'include "jira";
   (($p.kind|jira_kind_text)+" "+($p.key // $p.payload.project // ""))+"\n"+
   (if $p.kind=="create_issue" then "제목: "+$p.payload.summary+"\n프로젝트: "+$p.payload.project+"\n유형: "+$p.payload.issuetype_name+" ("+$p.payload.issuetype_id+")\n담당자: 나\n" else "" end)+
   (if ($p.preview // "")!="" then $p.preview elif $p.kind=="transition" then "상태 "+($p.payload.from.name // $p.payload.from.id)+" ("+$p.payload.from.id+") → "+($p.payload.to.name // $p.payload.to.id)+" ("+$p.payload.to.id+") (transition.id="+$p.payload.transition_id+")" elif $p.kind=="link" then $p.payload.reason else "" end)+"\n근거: "+($p.evidence|join(", "))+
   ([$p.warnings[]?]|map("\n⚠ "+.)|join(""))+
   (if $p.key!=null and $file[0].issues[$p.key]!=null then "\n"+($file[0].issues[$p.key].conditions|jira_condition_text)+
    (if $p.kind=="fill_description" then "\n본문 변경: "+($file[0].issues[$p.key].description_history.last_at // "기록 없음")+" · "+(if $file[0].issues[$p.key].description_history.last_by_me==true then "나" else "타인 또는 미확인" end) else "" end) else "" end)|jira_display'
}
routine_jira_approve() {
  local proposal=$1 source=$2 edited=$3 id kind key project status=0 hash snapshot
  id="l-$(routine_jira_random)"
  kind=$(command jq -r .kind <<< "$proposal"); key=$(command jq -r .key <<< "$proposal")
  project=$(command jq -r --argjson p "$proposal" 'if $p.kind=="create_issue" then $p.payload.project else .issues[$p.key].project end' "$source")
  command jq -n --argjson p "$proposal" --arg id "$id" --arg project "$project" --arg site "$jira_site" --arg account "$jira_account" --arg now "$(routine_jira_now)" --argjson edited "$edited" '
    {entry_id:$id,proposal_id:$p.id,kind:$p.kind,key:$p.key,issue_id:$p.issue_id,project:$project,site:$site,account_id:$account,approved_at:$now,edited:$edited,depends_on:$p.depends_on,proposal:$p,snapshot:$p.snapshot,events:$p.events,state:"approved",attempts:[],result:{comment_id:null,issue_id:null,issue_key:null,canon_hash_after:null},verified_at:null,message:null}' > "$jira_work/approve-entry.json"
  if command jq -e --arg id "$(command jq -r .id <<< "$proposal")" --arg site "$jira_site" --arg account "$jira_account" 'any(.entries[];.site==$site and .account_id==$account and .proposal_id==$id and (.state|IN("approved","applying","unknown","applied","verified","verify_failed","closed_by_user")))' "$jira_dir/ledger.json" >/dev/null; then echo '이미 승인했거나 결과 불명인 항목은 다시 승인하지 않습니다.'; return 0; fi
  if [[ $kind == create_issue ]]; then
    command jq -e --arg now "$(routine_jira_now)" '(.generated_at|fromdateiso8601)>=($now|fromdateiso8601)-86400' "$source" >/dev/null || { echo '제안 생성 후 24시간 경과'; return 0; }
  fi
  routine_jira_preflight "$jira_work/approve-entry.json" review || status=$?
  ((status==0)) || { echo "승인 직전 확인 실패 ($status): 다시 propose 필요"; return 0; }
  if [[ $kind != create_issue ]]; then
    snapshot=$(jq -L "$share_dir" -c --arg hash "$jira_fetched_hash" --arg account "$jira_account" --arg now "$(routine_jira_now)" --slurpfile entry "$jira_work/approve-entry.json" 'include "redact"; include "jira"; {fetched_at:$now,updated:.fields.updated,status_id:.fields.status.id,status_entered_at:$entry[0].snapshot.status_entered_at,assignee_is_me:(.fields.assignee.accountId==$account),description_canon_hash:$hash,description_excerpt:(.fields.description|jira_adf_text|redact|.[:1000])}' "$jira_work/check-issue.json") || return 1
    command jq --argjson snapshot "$snapshot" '.snapshot=$snapshot' "$jira_work/approve-entry.json" > "$jira_work/approve-new.json"; mv "$jira_work/approve-new.json" "$jira_work/approve-entry.json"
  fi
  ui_confirm '이 항목을 승인할까요?' false || { echo '승인하지 않았습니다.'; return 0; }
  if [[ $kind == link ]]; then routine_jira_link_save "$proposal" review "$key"; return; fi
  jq -L "$share_dir" --arg id "$id" --arg account "$jira_account" 'include "jira"; .proposal|jira_request($id;$account)' "$jira_work/approve-entry.json" > "$jira_work/approved-request.json"
  command jq '.body' "$jira_work/approved-request.json" > "$jira_work/approved-body.json"; hash=$(routine_jira_hash_value "$jira_work/approved-body.json")
  command jq --slurpfile request "$jira_work/approved-request.json" --arg hash "$hash" '.request=$request[0]|.request_sha256=$hash' "$jira_work/approve-entry.json" > "$jira_work/approve-new.json"
  command jq --slurpfile entry "$jira_work/approve-new.json" '.entries+=$entry' "$jira_dir/ledger.json" > "$jira_work/ledger-new.json"
  routine_jira_store "$jira_work/ledger-new.json" "$jira_dir/ledger.json"
}
routine_jira_edit() {
  local proposal=$1 output=$2 template sections hash
  template=$(jq -L "$share_dir" -nc --argjson p "$proposal" 'include "jira"; (jira_settings.templates[$p.payload.template] // [jira_settings.templates[]|select(.headers==($p.payload.sections|map(.header)))][0])|.headers=($p.payload.sections|map(.header))') || return 1
  command jq -r --argjson p "$proposal" -n '$p.payload.sections[]|"## "+.header, (.lines[]|"- "+.text)' > "$jira_work/edit.md"
  /bin/sh -c "$EDITOR \"\$1\"" sh "$jira_work/edit.md" 3<&- </dev/tty >/dev/tty || return 1
  sections=$(jq -L "$share_dir" -Rrs --argjson template "$template" 'include "jira"; jira_editor_sections($template)' "$jira_work/edit.md") || return 1
  jq -L "$share_dir" -n --argjson sections "$sections" --argjson template "$template" 'include "jira"; include "redact"; $sections|jira_sections_adf($template)|walk(if type=="string" then redact else . end)' > "$jira_work/edited-adf.json"
  hash=$(routine_jira_adf_hash "$jira_work/edited-adf.json")
  jq -L "$share_dir" -nc --argjson p "$proposal" --argjson sections "$sections" --slurpfile adf "$jira_work/edited-adf.json" --arg hash "$hash" 'include "jira"; $p|.payload.sections=$sections|.payload.adf=$adf[0]|.payload.adf_canon_hash=$hash|.preview=($adf[0]|jira_adf_text)|.warnings+=["편집 줄은 근거 인용을 면제합니다. 주장을 직접 확인하세요."]' > "$output"
}
routine_jira_review() {
  local day=$1 file="$jira_dir/$1.proposals.json" choices selected proposal kind edited id unselected hidden rejected p
  routine_jira_safe_file "$file" && [[ -f $file ]] || { echo 'Jira 제안 파일 없음: routine jira propose'; return 1; }
  if ! ui_interactive; then routine_jira_summary_file "$file"; echo '비TTY에서는 요약만 출력했습니다. 승인·Jira 쓰기 없음.'; return 0; fi
  routine_jira_lock review || return $?
  routine_jira_authenticate || return $?
  jq -L "$share_dir" -e 'include "jira"; jira_proposals_ok' "$file" >/dev/null 2>&1 || { echo 'Jira 제안 파일 형식 오류 — routine jira propose를 다시 실행하세요.' >&2; return 1; }
  [[ $(command jq -r .site "$file") == "$jira_site" && $(command jq -r .account_id "$file") == "$jira_account" ]] || { echo '사이트·계정이 바뀌었습니다 — 다시 propose 필요'; return 2; }
  ui_note 'Jira 질문·알림·오류' "$(jq -L "$share_dir" -r 'include "jira"; (.questions[],.notices[],(.errors[]|.message))|jira_display' "$file")"
  routine_jira_summary_file "$file"
  routine_jira_unknowns
  routine_jira_recovery_notices
  choices=$(jq -L "$share_dir" -c 'include "jira"; .proposals|map({value:.id,label:jira_proposal_label})' "$file")
  while :; do
    selected=$(ui_choose_many '검토할 항목을 선택하세요 (선택은 승인이 아님)' "$choices" '[]') || return 4
    routine_jira_read_context "$jira_work/review-context.json"
    if jq -L "$share_dir" -e --argjson selected "$selected" --slurpfile ctx "$jira_work/review-context.json" 'include "jira"; all(.proposals[]|select(.id as $id|$selected|index($id)!=null);. as $p|all(.depends_on[];. as $id|($selected|index($id)!=null) or ($p|jira_dependencies_ok($ctx[0]))))' "$file" >/dev/null; then break; fi
    echo '의존 연결도 함께 선택해야 합니다.'
  done
  while IFS= read -r -u 3 proposal; do
    kind=$(command jq -r .kind <<< "$proposal"); edited=false
    ui_note '최종 미리보기' "$(routine_jira_preview "$proposal" "$file")"
    if [[ ( $kind == fill_description || $kind == create_issue ) && ${EDITOR:-} =~ [^[:space:]] ]] && ui_confirm '본문을 편집할까요?' false; then
      routine_jira_edit "$proposal" "$jira_work/edited-proposal.json" || { echo '편집 형식이 유효하지 않습니다. 승인하지 않습니다.'; continue; }
      proposal=$(cat "$jira_work/edited-proposal.json")
      edited=true; ui_note '편집 후 최종 미리보기' "$(routine_jira_preview "$proposal" "$file")"
    fi
    routine_jira_approve "$proposal" "$file" "$edited" || return $?
    ((jira_abort==0)) || return 1
  done 3< <(command jq -c --argjson selected "$selected" '[.proposals[]|select(.id as $id|$selected|index($id)!=null)]|sort_by(if .kind=="link" then 0 elif .kind=="fill_description" then 1 elif .kind=="comment" then 2 elif .kind=="transition" then 3 else 4 end)|.[]' "$file")
  unselected=$(jq -L "$share_dir" -c --argjson selected "$selected" 'include "jira"; [.proposals[]|select(.id as $id|$selected|index($id)==null)|{value:.id,label:jira_proposal_label}]' "$file")
  hidden=$(ui_choose_many '다시 보지 않을 제안 (기본 미선택)' "$unselected" '[]') || return 4
  command jq --argjson hidden "$hidden" --slurpfile file "$file" --arg site "$jira_site" --arg account "$jira_account" --arg now "$(routine_jira_now)" '.dismissed += [$file[0].proposals[]|select(.id as $id|$hidden|index($id)!=null)|{site:$site,account_id:$account,proposal_id:.id,kind:.kind,evidence:.evidence,events:.events,at:$now}]' "$jira_dir/ledger.json" > "$jira_work/ledger-new.json"
  routine_jira_store "$jira_work/ledger-new.json" "$jira_dir/ledger.json"
  choices=$(jq -L "$share_dir" -c --argjson selected "$selected" 'include "jira"; [.proposals[]|select(.kind=="link" and .payload.origin!="duplicate" and (.id as $id|$selected|index($id)==null))|{value:.id,label:jira_proposal_label}]' "$file")
  rejected=$(ui_choose_many '연결 후보 아님 (기본 미선택)' "$choices" '[]') || return 4
  command jq --argjson rejected "$rejected" --slurpfile file "$file" --arg site "$jira_site" --arg account "$jira_account" --arg now "$(routine_jira_now)" '.rejections += [$file[0].proposals[]|select(.id as $id|$rejected|index($id)!=null)|. as $p|.evidence[]|select(test("^(pr|git|rep):"))|{site:$site,account_id:$account,evidence_id:.,key:$p.key,rejected_at:$now}]' "$jira_dir/links.json" > "$jira_work/links-new.json"
  routine_jira_store "$jira_work/links-new.json" "$jira_dir/links.json"
  jq -L "$share_dir" 'include "jira"; jira_duplicate_choices' "$file" > "$jira_work/duplicate-choices.json"
  choices=$(jq -L "$share_dir" -c 'include "jira"; map({value,label:(.label|jira_display)})' "$jira_work/duplicate-choices.json")
  if [[ $choices != '[]' ]]; then
    rejected=$(ui_choose_many '중복 아님 (확인되지 않은 URL 후보, 기본 미선택)' "$choices" '[]') || return 4
    jq -L "$share_dir" --argjson rejected "$rejected" --slurpfile choices "$jira_work/duplicate-choices.json" --arg site "$jira_site" --arg account "$jira_account" --arg now "$(routine_jira_now)" 'include "jira"; jira_duplicate_reject($rejected;$choices[0];$site;$account;$now)' "$jira_dir/links.json" > "$jira_work/links-new.json"
    routine_jira_store "$jira_work/links-new.json" "$jira_dir/links.json" || return $?
    if [[ $rejected != '[]' ]]; then
      echo '중복 아님 기록 — routine jira propose를 다시 실행하면 생성 제안을 다시 판단합니다'
    fi
  fi
  routine_jira_apply_locked
}
routine_jira_close() {
  local id choices selected
  ui_interactive || { echo 'routine jira close는 대화형 터미널이 필요합니다. 네트워크·쓰기 없음.' >&2; return 2; }
  routine_jira_lock close || return $?
  routine_jira_authenticate || return $?
  while IFS= read -r id; do routine_jira_reconcile "$id" || true; ((jira_abort==0)) || return 1; done < <(command jq -r --arg site "$jira_site" --arg account "$jira_account" '.entries[]|select(.site==$site and .account_id==$account and (.state|IN("unknown","applying")))|.entry_id' "$jira_dir/ledger.json")
  routine_jira_unknowns
  choices=$(jq -L "$share_dir" -c --arg site "$jira_site" --arg account "$jira_account" 'include "jira"; [.entries[]|select(.site==$site and .account_id==$account and .state=="unknown")|{value:.entry_id,label:jira_proposal_label}]' "$jira_dir/ledger.json")
  selected=$(ui_choose_many '닫을 결과 불명 항목 (기본 미선택)' "$choices" '[]') || return 4
  [[ $selected != '[]' ]] || return 0
  ui_confirm "고른 $(command jq length <<< "$selected")건을 닫을까요? 도구는 이 항목을 다시 보내지 않습니다." false || return 0
  while IFS= read -r id; do routine_jira_state "$id" closed_by_user '{}' '사용자가 Jira에서 직접 확인·처리'; done < <(command jq -r '.[]' <<< "$selected")
}
routine_jira_links() {
  local remove=${1:-} count
  if [[ -n $remove ]]; then
    [[ $remove =~ ^[1-9][0-9]*$ ]] || { echo 'Jira 연결 삭제 번호는 양의 정수여야 합니다: routine jira links --remove N' >&2; return 2; }
    routine_jira_lock links || return $?
    count=$(command jq '[.links[],.rejections[]]|length' "$jira_dir/links.json")
    ((remove<=count)) || { echo 'Jira 연결 삭제 번호가 목록 범위를 벗어났습니다 — routine jira links로 확인하세요.' >&2; return 2; }
    command jq --argjson index "$((remove-1))" 'if $index<(.links|length) then del(.links[$index]) else del(.rejections[$index-(.links|length)]) end' "$jira_dir/links.json" > "$jira_work/links-new.json"
    routine_jira_store "$jira_work/links-new.json" "$jira_dir/links.json"
  fi
  jq -L "$share_dir" -r --arg site "$jira_site" 'include "jira"; [(.links[]|.+{kind:"연결"}),(.rejections[]|.+{kind:(if .kind=="duplicate" then "중복 아님" else "거절" end)})]|to_entries[]|"\(.key+1). \(.value.kind) \(.value.evidence_id) → \(.value.key)"+(if .value.site!=$site then " [다른 사이트]" else "" end)|jira_display' "$jira_dir/links.json"
}
routine_jira_help() { echo 'routine jira [propose [--no-llm] | review [--date YYYY-MM-DD] | apply | links [--remove N] | close]'; echo '제안은 읽기 전용. 승인은 터미널에서 항목별로. 결과 불명은 close로 닫기만, 재전송 없음.'; }
routine_jira() (
  local action=${1:-show} day remove='' status=0
  (($#==0)) || shift
  if [[ $action == -h || $action == --help || ${1:-} == -h || ${1:-} == --help ]]; then routine_jira_help; return 0; fi
  day=$(routine_day)
  case $action in
    propose) exec "$share_dir/../bin/jira-propose" "$@" ;;
    review) if [[ ${1:-} == --date && $# == 2 ]]; then day=$2; shift 2; fi ;;
    links) if [[ ${1:-} == --remove && $# == 2 ]]; then remove=$2; shift 2; fi ;;
    show|apply|close) ;;
    *) routine_jira_help >&2; return 2 ;;
  esac
  (($#==0)) || { routine_jira_help >&2; return 2; }
  routine_jira_require || return $?
  if [[ $action == apply || $action == close ]] && ! ui_interactive; then echo "routine jira ${action}는 대화형 터미널이 필요합니다. 네트워크·쓰기 없음." >&2; return 2; fi
  command jq -L "$share_dir" -ne --arg day "$day" 'include "config"; $day|calendar_date' >/dev/null || { echo 'Jira 날짜 형식 오류 — YYYY-MM-DD 달력 날짜로 지정하세요.' >&2; return 2; }
  routine_jira_session || return $?
  case $action in
    show) routine_jira_status || echo 'Jira 동기화: 상태 파일 확인 필요'; routine_jira_summary_file "$jira_dir/$day.proposals.json"; jira_account=$(command jq -r '.account_id // ""' "$jira_dir/$day.proposals.json" 2>/dev/null || true); routine_jira_unknowns; routine_jira_recovery_notices ;;
    review) routine_jira_review "$day" ;;
    apply) routine_jira_lock apply || return $?; routine_jira_authenticate || return $?; routine_jira_apply_locked ;;
    close) routine_jira_close ;;
    links) routine_jira_links "$remove" ;;
  esac
)
routine_jira_status() {
  local dir="$HOME/Library/Application Support/routine-automation/jira" day site proposals ledger
  day=$(routine_day); site=$(routine_get jira.site)
  proposals="$dir/$day.proposals.json"; ledger="$dir/ledger.json"
  [[ -f $proposals && ! -L $proposals ]] || proposals=/dev/null
  [[ -f $ledger && ! -L $ledger ]] || ledger=/dev/null
  if [[ $proposals != /dev/null ]] && ! jq -L "$share_dir" -e 'include "jira"; jira_proposals_ok' "$proposals" >/dev/null 2>&1; then
    echo 'Jira 제안 파일 형식 오류 — routine jira propose를 다시 실행하세요.'
    proposals=/dev/null
  fi
  if [[ $ledger != /dev/null ]] && ! command jq -e 'type=="object" and .version==1 and (.entries|type=="array" and all(.[];type=="object"))' "$ledger" >/dev/null 2>&1; then
    echo 'Jira ledger 파일 형식 오류 — 파일을 보존하고 내용을 확인하세요.'
    ledger=/dev/null
  fi
  command jq -nr --arg site "$site" --slurpfile p "$proposals" --slurpfile l "$ledger" '
    (($p[0]|select(.site==$site)) // {proposals:[],questions:[],notices:[],site:$site,account_id:null}) as $p|
    ($l[0] // {entries:[]}) as $l|
    [$l.entries[]|select(.site==$site and ($p.account_id==null or .account_id==$p.account_id))] as $own|
    "Jira 동기화: 제안 \(if $p.site==$site then $p.proposals|length else 0 end) · 승인 대기 \([$own[]|select(.state=="approved")]|length) · 결과 불명 \([$own[]|select(.state|IN("unknown","applying"))]|length) · 다른 사이트 \([$l.entries[]|select(.site!=$site or ($p.account_id!=null and .account_id!=$p.account_id))]|length) · 질문 \($p.questions|length) · 알림 \($p.notices|length)"+
    (if any($own[];.state|IN("unknown","applying")) then " — 확인 URL·닫기: routine jira close" else "" end)'
}
routine_jira_expire() {
  local file date_name
  routine_jira_lock_owned || return 4
  command jq --arg now "$(routine_jira_now)" '
   (($now|fromdateiso8601)-7776000) as $cutoff|
   .entries|=map(select((.state|IN("verified","verify_failed","conflict","blocked","failed","void","closed_by_user")|not) or
     ((.terminated_at // .verified_at // .attempts[-1].ended_at // .approved_at|fromdateiso8601)>=$cutoff)))|
   .dismissed|=map(select((.at|fromdateiso8601)>=$cutoff))' "$jira_dir/ledger.json" > "$jira_work/ledger-new.json" || return 1
  routine_jira_store "$jira_work/ledger-new.json" "$jira_dir/ledger.json" || return 1
  for file in "$jira_dir"/*.proposals.json; do
    [[ -f $file && ! -L $file && -O $file ]] || continue
    date_name=${file##*/}; date_name=${date_name%.proposals.json}
    if command jq -L "$share_dir" -ne --arg day "$date_name" --arg now "$(routine_jira_now)" 'include "config"; ($day|calendar_date) and (($day+"T00:00:00Z"|fromdateiso8601)<($now|fromdateiso8601)-2592000)' >/dev/null; then rm -f -- "$file"; fi
  done
}
