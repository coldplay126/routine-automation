#!/usr/bin/env bash
# Anonymous public releases only; configuration cannot change the repository.
routine_release_repository() {
  local repository='coldplay126/routine-automation'
  # Deliberately test-only, not a ROUTINE_SETTINGS/config key.
  if [[ -n ${ROUTINE_TEST_RELEASE_REPO:-} ]]; then repository=$ROUTINE_TEST_RELEASE_REPO; fi
  [[ $repository =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$ ]] || return 1
  printf '%s\n' "$repository"
}
routine_release_url_allowed() {
  [[ $1 =~ ^https://(github\.com|objects\.githubusercontent\.com|release-assets\.githubusercontent\.com)/[^[:space:]\\]*$ && $1 != *$'\177'* ]]
}
# Emits the highest numeric tagged release, including prereleases. Exit 1 means
# availability failure (Downloads fallback); exit 2 means unsafe release data.
routine_release_query() (
  local timeout=${1:-15} repository temporary page=1 remaining start=$SECONDS response count release newest='null' http
  repository=$(routine_release_repository) || { echo 'GitHub 저장소 상수 오류' >&2; return 2; }
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/routine-release.XXXXXXXX") || return 1
  trap 'rm -rf -- "$temporary"' EXIT
  while :; do
    remaining=$((timeout-(SECONDS-start)))
    ((remaining>0)) || { echo 'GitHub 목록 조회 시간 초과' >&2; return 1; }
    http=$(curl -q --silent --show-error --proto '=https' --connect-timeout "$remaining" --max-time "$remaining" \
      --max-filesize 2097152 --header 'Accept: application/vnd.github+json' --output "$temporary/releases.json" \
      --write-out '%{http_code}' "https://api.github.com/repos/$repository/releases?per_page=100&page=$page" 2>/dev/null) || {
      echo 'GitHub 목록 네트워크 실패' >&2; return 1;
    }
    case $http in
      200) ;;
      403|429) echo "GitHub 목록 요청 제한 (HTTP $http)" >&2; return 1 ;;
      *) echo "GitHub 목록 조회 실패 (HTTP $http)" >&2; return 1 ;;
    esac
    response=$(command jq -ce 'select(type=="array")' "$temporary/releases.json") || { echo 'GitHub 목록 형식 오류' >&2; return 1; }
    count=$(command jq length <<< "$response") || return 1
    release=$(command jq -c '[.[]|select(.draft==false and (.tag_name|type)=="string")|
      select(.tag_name|test("^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"))]|
      sort_by(.tag_name[1:]|split(".")|map(tonumber))|last//null' <<< "$response") || return 1
    newest=$(command jq -nc --argjson old "$newest" --argjson next "$release" '[$old,$next]|map(select(.!=null))|
      sort_by(.tag_name[1:]|split(".")|map(tonumber))|last//null') || return 1
    ((count==100)) || break
    page=$((page+1))
  done
  [[ $newest != null ]] || { echo 'GitHub 공개 버전 목록이 비어 있습니다' >&2; return 1; }
  release=$(command jq -ce '.tag_name[1:] as $v|[.assets[]?|select(.name==("routine-automation-"+$v+".zip"))]|select(length==1)|
    .[0]|{version:$v,url:.browser_download_url,size:.size}' <<< "$newest") || {
    echo 'GitHub 최신 Release에 해당 버전 zip asset이 없습니다' >&2; return 2;
  }
  command jq -e '.size|type=="number" and .>0 and .<=67108864 and floor==.' <<< "$release" >/dev/null || {
    echo 'GitHub asset 크기 상한(64MiB) 또는 형식 오류' >&2; return 2;
  }
  routine_release_url_allowed "$(command jq -r .url <<< "$release")" || { echo 'GitHub asset URL 허용 호스트 오류' >&2; return 2; }
  printf '%s\n' "$release"
)
routine_release_download() {
  local url=$1 destination=$2 response http redirect attempt remaining start=$SECONDS
  # Inspect every redirect before requesting it: curl -L could contact an
  # untrusted redirect host even when the initial browser_download_url is safe.
  for ((attempt=0; attempt<5; attempt++)); do
    routine_release_url_allowed "$url" || { echo 'GitHub asset URL/리다이렉트 허용 호스트 오류' >&2; return 2; }
    remaining=$((60-(SECONDS-start)))
    ((remaining>0)) || { echo 'GitHub asset 다운로드 시간 초과' >&2; return 1; }
    response=$(curl -q --silent --show-error --proto '=https' --connect-timeout 5 --max-time "$remaining" \
      --max-filesize 67108864 --output "$destination" --write-out $'%{http_code}\n%{redirect_url}' "$url" 2>/dev/null) || {
      echo 'GitHub asset 다운로드 네트워크 실패 또는 64MiB 초과' >&2; return 1;
    }
    http=${response%%$'\n'*}; redirect=${response#*$'\n'}
    case $http in
      200)
        [[ -f $destination && $(stat -f %z "$destination") -le 67108864 ]] || return 2
        return 0 ;;
      301|302|303|307|308) url=$redirect ;;
      *) echo "GitHub asset 다운로드 실패 (HTTP $http)" >&2; return 1 ;;
    esac
  done
  echo 'GitHub asset 리다이렉트 횟수 초과' >&2; return 2
}
