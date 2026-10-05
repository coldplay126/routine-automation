#!/usr/bin/env bash
# Anonymous public releases only; configuration cannot change the repository.
routine_release_repository() {
  local repository='coldplay126/routine-automation'
  # Source-tree fixtures only; installed clients cannot change update origin.
  if [[ ! -f ${share_dir:-.}/../manifest.json && -n ${ROUTINE_TEST_RELEASE_REPO:-} ]]; then repository=$ROUTINE_TEST_RELEASE_REPO; fi
  [[ $repository =~ ^[A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || return 1
  printf '%s\n' "$repository"
}
routine_release_endpoint() {
  local repository=$1
  if [[ $repository == coldplay126/routine-automation ]]; then
    printf 'https://api.github.com/repositories/1405988374/releases'
  else printf 'https://api.github.com/repos/%s/releases' "$repository"; fi
}
routine_release_asset_url() {
  printf 'https://github.com/%s/releases/download/v%s/routine-automation-%s.zip' "$1" "$2" "$2"
}
routine_release_url_allowed() {
  [[ $1 =~ ^https://(objects\.githubusercontent\.com|release-assets\.githubusercontent\.com)/[^[:space:]\\]*$ && $1 != *$'\177'* ]]
}
# Emits the highest numeric tagged release, including prereleases. Exit 1 means
# availability failure; exit 2 means unsafe release data. Neither falls back.
routine_release_query() (
  local timeout=${1:-15} repository endpoint temporary page=1 remaining start=$SECONDS response count release newest='null' http
  repository=$(routine_release_repository) || { echo 'GitHub 저장소 상수 오류' >&2; return 2; }
  endpoint=$(routine_release_endpoint "$repository")
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/routine-release.XXXXXXXX") || return 1
  trap 'rm -rf -- "$temporary"' EXIT
  while :; do
    remaining=$((timeout-(SECONDS-start)))
    ((remaining>0)) || { echo 'GitHub 목록 조회 시간 초과' >&2; return 1; }
    http=$(curl -q --silent --show-error --proto '=https' --connect-timeout "$remaining" --max-time "$remaining" \
      --max-filesize 2097152 --header 'Accept: application/vnd.github+json' --output "$temporary/releases.json" \
      --write-out '%{http_code}' "$endpoint?per_page=100&page=$page" 2>/dev/null) || {
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
  release=$(command jq -ce '.tag_name[1:] as $v|[.assets[]?|select(.name==("routine-automation-"+$v+".zip") and .state=="uploaded")]|select(length==1)|
    .[0]|{version:$v,url:.browser_download_url,size:.size,digest:.digest}' <<< "$newest") || {
    echo 'GitHub 최신 Release에 업로드 완료된 해당 버전 zip asset이 없습니다' >&2; return 2;
  }
  command jq -e '.size|type=="number" and .>0 and .<=67108864 and floor==.' <<< "$release" >/dev/null || {
    echo 'GitHub asset 크기 상한(64MiB) 또는 형식 오류' >&2; return 2;
  }
  command jq -e '.digest|type=="string" and test("^sha256:[0-9a-f]{64}$")' <<< "$release" >/dev/null || {
    echo 'GitHub asset SHA-256 digest 누락 또는 형식 오류' >&2; return 2;
  }
  [[ $(command jq -r .url <<< "$release") == "$(routine_release_asset_url "$repository" "$(command jq -r .version <<< "$release")")" ]] || {
    echo 'GitHub asset URL 저장소·태그·파일명 불일치' >&2; return 2;
  }
  printf '%s\n' "$release"
)
routine_release_download() {
  local release=$1 destination=$2 url version repository expected_size expected_digest actual_digest response http redirect attempt remaining start=$SECONDS status
  url=$(command jq -r .url <<< "$release"); version=$(command jq -r .version <<< "$release")
  repository=$(routine_release_repository) || return 2
  [[ $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ &&
     $url == "$(routine_release_asset_url "$repository" "$version")" ]] || { echo 'GitHub asset 최초 URL 불일치' >&2; return 2; }
  expected_size=$(command jq -r .size <<< "$release")
  expected_digest=$(command jq -r .digest <<< "$release")
  # Inspect each redirect before requesting it; the first URL is exact.
  for ((attempt=0; attempt<5; attempt++)); do
    if ((attempt>0)); then
      routine_release_url_allowed "$url" || { echo 'GitHub asset 리다이렉트 허용 호스트 오류' >&2; return 2; }
    fi
    remaining=$((60-(SECONDS-start)))
    ((remaining>0)) || { echo 'GitHub asset 다운로드 시간 초과' >&2; return 1; }
    status=0
    response=$(curl -q --silent --show-error --proto '=https' --connect-timeout 5 --max-time "$remaining" \
      --max-filesize 67108864 --output "$destination" --write-out $'%{http_code}\n%{redirect_url}' "$url" 2>/dev/null) || status=$?
    if ((status)); then
      if ((status==63)); then echo 'GitHub asset 다운로드 크기 상한(64MiB) 초과' >&2; return 2; fi
      echo 'GitHub asset 다운로드 네트워크 실패' >&2; return 1
    fi
    http=${response%%$'\n'*}; redirect=${response#*$'\n'}
    case $http in
      200)
        [[ -f $destination && $(stat -f %z "$destination") -le 67108864 ]] || {
          echo 'GitHub asset 다운로드 크기 상한(64MiB) 초과 또는 파일 누락' >&2; return 2;
        }
        [[ $(stat -f %z "$destination") == "$expected_size" ]] || { echo 'GitHub asset 실제 크기와 API size 불일치' >&2; return 2; }
        actual_digest=$(shasum -a 256 "$destination"); actual_digest=${actual_digest%% *}
        [[ sha256:$actual_digest == "$expected_digest" ]] || { echo 'GitHub asset SHA-256 digest 불일치' >&2; return 2; }
        return 0 ;;
      301|302|303|307|308) url=$redirect ;;
      *) echo "GitHub asset 다운로드 실패 (HTTP $http)" >&2; return 1 ;;
    esac
  done
  echo 'GitHub asset 리다이렉트 횟수 초과' >&2; return 2
}
