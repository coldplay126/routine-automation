#!/usr/bin/env bash
# shellcheck disable=SC2154 # Sourced by the isolated tests/update.sh fixture.
# shellcheck disable=SC2031 # Per-command/subshell configuration never changes the caller's fixture environment.
export RELEASE_LIST="$sandbox/releases.json" RELEASE_SECOND="$sandbox/releases-second.json"
export RELEASE_ZIP="$sandbox/release.zip" CURL_RECORD="$sandbox/curl-calls"
cat > "$STUB_ROOT/curl" <<'CURL'
#!/bin/bash
set -eu
output='' url=''
while (($#)); do
  case $1 in
    --output) output=$2; shift ;;
    --header|--write-out|--proto|--max-time|--connect-timeout|--max-filesize) shift ;;
    https://*) url=$1 ;;
  esac
  shift
done
printf '%s\n' "$url" >> "$CURL_RECORD"
[[ ${CURL_FAIL:-0} == 0 ]] || exit "$CURL_FAIL"
case $url in
  https://api.github.com/repos/coldplay126/routine-automation/releases\?per_page=100\&page=*)
    if [[ $url == *'page=2' ]]; then cp "$RELEASE_SECOND" "$output"; else cp "$RELEASE_LIST" "$output"; fi
    printf '%s' "${CURL_HTTP:-200}" ;;
  https://github.com/coldplay126/routine-automation/releases/download/*)
    if [[ -n ${CURL_REDIRECT:-} ]]; then printf '302\n%s' "$CURL_REDIRECT"
    else cp "$RELEASE_ZIP" "$output"; printf '200\n'; fi ;;
  https://objects.githubusercontent.com/fixture.zip)
    if [[ -n ${OBJECT_REDIRECT:-} ]]; then printf '302\n%s' "$OBJECT_REDIRECT"
    else cp "$RELEASE_ZIP" "$output"; printf '200\n'; fi ;;
  https://release-assets.githubusercontent.com/fixture.zip\?signature=*)
    if [[ -n ${CURL_EXPIRED_SIGNATURE:-} && $url == *"signature=$CURL_EXPIRED_SIGNATURE" ]]; then printf '410\n'
    else cp "$RELEASE_ZIP" "$output"; printf '200\n'; fi ;;
  *) printf 'forbidden curl URL\n' >> "$RECORD"; exit 87 ;;
esac
CURL
chmod +x "$STUB_ROOT/curl"
rm "$HOME/.local/bin/curl"; ln -s "$STUB_ROOT/curl" "$HOME/.local/bin/curl"
curl() { "$STUB_ROOT/curl" "$@"; }
export -f curl
share_dir="$installed/share"
# shellcheck source=../share/config.sh
source "$share_dir/config.sh"
# shellcheck source=../share/update.sh
source "$share_dir/update.sh"
release_list() {
  command jq -n --arg version "$1" --argjson size "$(stat -f %z "$RELEASE_ZIP")" '
    [{draft:false,prerelease:true,tag_name:("v"+$version),assets:[
      {name:("routine-automation-"+$version+".zip"),size:$size,
       browser_download_url:("https://github.com/coldplay126/routine-automation/releases/download/v"+$version+"/routine-automation-"+$version+".zip")}]}]' > "$RELEASE_LIST"
}
make_zip 1.3.0 "$RELEASE_ZIP"
# Prerelease-only repositories and numeric comparison; drafts cannot win.
release_list 0.10.0
command jq '. + [ (.[0]|.tag_name="v0.9.0"), (.[0]|.tag_name="v9.0.0"|.draft=true), (.[0]|.tag_name="latest") ]' "$RELEASE_LIST" > "$sandbox/list"; mv "$sandbox/list" "$RELEASE_LIST"
selected=$(routine_release_query 5)
[[ $(command jq -r .version <<< "$selected") == 0.10.0 ]] || fail 'prerelease 전용 목록·draft 제외·숫자 버전 비교 실패'
# Numeric ordering is across pages, not just GitHub's creation-time first page.
cp "$RELEASE_LIST" "$RELEASE_SECOND"
command jq -n '[range(100)|{draft:false,prerelease:true,tag_name:"v0.9.0",assets:[]}]' > "$RELEASE_LIST"
selected=$(routine_release_query 5)
[[ $(command jq -r .version <<< "$selected") == 0.10.0 ]] || fail '두 번째 목록 페이지의 최신 버전 누락'
release_list 1.4.0
snapshot > "$sandbox/release-before"
if "$installed/bin/routine" update --from github --check > "$sandbox/tag-mismatch" 2>&1; then fail 'Release 태그와 VERSION 불일치 허용'; fi
snapshot > "$sandbox/release-after"; cmp -s "$sandbox/release-before" "$sandbox/release-after" || fail '태그 불일치가 설치본 변경'
for boundary in missing host size; do
  release_list 1.3.0
  case $boundary in
    missing) command jq '.[0].assets=[]' "$RELEASE_LIST" ;;
    host) command jq '.[0].assets[0].browser_download_url="https://untrusted.example/fixture.zip"' "$RELEASE_LIST" ;;
    size) command jq '.[0].assets[0].size=67108865' "$RELEASE_LIST" ;;
  esac > "$sandbox/list"
  mv "$sandbox/list" "$RELEASE_LIST"
  if "$installed/bin/routine" update --check > "$sandbox/release-$boundary" 2>&1; then fail "잘못된 Release 허용: $boundary"; fi
  snapshot > "$sandbox/release-after"; cmp -s "$sandbox/release-before" "$sandbox/release-after" || fail "잘못된 Release가 설치본 변경: $boundary"
done
release_list 1.3.0
for redirect in https://untrusted.example/fixture.zip https://evil.githubusercontent.com/fixture.zip http://github.com/fixture.zip https://github.com.evil.example/fixture.zip; do
  if CURL_REDIRECT=$redirect "$installed/bin/routine" update --check > "$sandbox/redirect-host" 2>&1; then fail "허용 외 리다이렉트 URL 허용: $redirect"; fi
done
if CURL_REDIRECT=https://objects.githubusercontent.com/fixture.zip OBJECT_REDIRECT=https://evil.githubusercontent.com/fixture.zip "$installed/bin/routine" update --check > "$sandbox/redirect-second-hop" 2>&1; then fail '두 번째 리다이렉트 호스트 검사 누락'; fi
! grep -Eq 'untrusted\.example|evil\.githubusercontent\.com|http://github\.com|github\.com\.evil\.example' "$CURL_RECORD" || fail '허용 외 호스트/HTTP에 curl 요청'
CURL_REDIRECT=https://objects.githubusercontent.com/fixture.zip "$installed/bin/routine" update --check > "$sandbox/redirect-safe"
grep -q '0.1.1 → 1.3.0' "$sandbox/redirect-safe" || fail '허용 object 호스트 리다이렉트 다운로드 실패'
for signature in first-signature rotated-signature; do
  expired=''; [[ $signature != rotated-signature ]] || expired=first-signature
  CURL_EXPIRED_SIGNATURE=$expired CURL_REDIRECT="https://release-assets.githubusercontent.com/fixture.zip?signature=$signature" "$installed/bin/routine" update --from github --check > "$sandbox/redirect-release-assets"
  grep -q '0.1.1 → 1.3.0' "$sandbox/redirect-release-assets" || fail '공개 asset 서명 URL 리다이렉트 다운로드 실패'
done
redirect_before=$(wc -l < "$CURL_RECORD")
if CURL_REDIRECT=https://github.com/coldplay126/routine-automation/releases/download/v1.3.0/routine-automation-1.3.0.zip "$installed/bin/routine" update --check > "$sandbox/redirect-loop" 2>&1; then fail '리다이렉트 상한 없이 반복'; fi
[[ $(wc -l < "$CURL_RECORD") -eq $((redirect_before+6)) ]] || fail '리다이렉트 5단계 상한 실패'
# Availability failures fall back, with the reason visible, but never install.
for failure in network 403 429 empty; do
  release_list 1.3.0
  case $failure in
    network) CURL_FAIL=7 "$installed/bin/routine" update --check > "$sandbox/fallback-$failure" 2>&1 ;;
    403|429) CURL_HTTP=$failure "$installed/bin/routine" update --check > "$sandbox/fallback-$failure" 2>&1 ;;
    empty) printf '[]\n' > "$RELEASE_LIST"; "$installed/bin/routine" update --check > "$sandbox/fallback-$failure" 2>&1 ;;
  esac
  grep -q 'Downloads 방식으로 대체' "$sandbox/fallback-$failure" || fail "Downloads 대체 이유 누락: $failure"
  snapshot > "$sandbox/release-after"; cmp -s "$sandbox/release-before" "$sandbox/release-after" || fail "대체 확인이 자동 설치: $failure"
done
release_list 1.3.0
cache="$HOME/Library/Caches/routine-automation/releases.json"
rm -f "$cache"
: > "$CURL_RECORD"
"$installed/bin/routine" status > "$sandbox/release-status"
"$installed/bin/morning" --only omp-update > "$sandbox/release-morning" </dev/null
for output in "$sandbox/release-status" "$sandbox/release-morning" "$RECORD.notice"; do
  grep -q '새 버전 1.3.0 — routine update' "$output" || fail 'status/morning 공개 새 버전 안내 누락'
done
[[ $(wc -l < "$CURL_RECORD") -eq 1 ]] || fail '하루 1회 목록 캐시 실패'
[[ $(stat -f %Lp "$cache") == 600 ]] || fail '공개 목록 캐시 권한 오류'
command jq -e '[..|strings]|all(.[]; (contains("first-signature") or contains("rotated-signature"))|not)' "$cache" >/dev/null || fail '공개 목록 캐시에 만료되는 서명 URL 저장'
snapshot > "$sandbox/release-after"; cmp -s "$sandbox/release-before" "$sandbox/release-after" || fail 'status/morning 자동 설치'
ROUTINE_NOW='2026-09-29T09:00:00+09:00' "$installed/bin/routine" status > "$sandbox/release-next-day"
[[ $(wc -l < "$CURL_RECORD") -eq 2 ]] || fail '다음 날 목록 캐시 갱신 실패'
CURL_FAIL=7 ROUTINE_NOW='2026-09-30T09:00:00+09:00' "$installed/bin/routine" status > "$sandbox/release-failed-day"
CURL_FAIL=7 ROUTINE_NOW='2026-09-30T09:00:00+09:00' "$installed/bin/morning" --only omp-update > "$sandbox/release-failed-morning" </dev/null
[[ $(wc -l < "$CURL_RECORD") -eq 3 ]] || fail '실패한 조회를 같은 날 반복'
# Download and consume the real package output through the real update path.
"$installed/bin/routine" update --check > "$sandbox/release-check"
grep -q '0.1.1 → 1.3.0' "$sandbox/release-check" || fail '공개 Release 실제 package 확인 실패'
"$installed/bin/routine" update --yes > "$sandbox/release-installed" </dev/null
[[ $(cat "$installed/VERSION") == 1.3.0 && $(cat "$installed/install-id") == "$id_before" ]] || fail '공개 Release 실제 package 업데이트 실패'
[[ $(shasum -a 256 "$ROUTINE_CONFIG") == "$config_before" ]] || fail '공개 Release 업데이트가 설정 변경'
ROUTINE_NOW='2026-09-29T09:00:00+09:00' "$installed/bin/routine" status > "$sandbox/release-current"
! grep -q '새 버전' "$sandbox/release-current" || fail '설치본 VERSION 대신 개발 VERSION 비교'
# A private ZIP without the public build marker must not upgrade the beta.
mkdir "$sandbox/cutover-downloads" "$sandbox/cutover"
make_zip 1.1.3 "$sandbox/cutover-downloads/routine-automation-1.1.3.zip"
/usr/bin/zip -qd "$sandbox/cutover-downloads/routine-automation-1.1.3.zip" routine-automation-1.1.3/LICENSE
make_zip 0.1.0 "$sandbox/cutover.zip"
ditto -x -k "$sandbox/cutover.zip" "$sandbox/cutover"
/bin/bash "$sandbox/cutover/routine-automation-0.1.0/install.sh" --update > "$sandbox/public-cutover"
[[ $(cat "$installed/VERSION") == 0.1.0 && $(cat "$installed/install-id") == "$id_before" ]] || fail '명시적 공개 베타 전환 실패'
snapshot > "$sandbox/cutover-before"
CURL_FAIL=7 ROUTINE_DOWNLOADS_DIR="$sandbox/cutover-downloads" "$installed/bin/routine" update --yes > "$sandbox/private-only" 2>&1
grep -q '공개 빌드가 아닌 개발판 zip' "$sandbox/private-only" || fail 'LICENSE 없는 개발판 거부 안내 누락'
grep -Fq "$sandbox/cutover-downloads/routine-automation-1.1.3.zip" "$sandbox/private-only" || fail 'LICENSE 없는 개발판 경로 안내 누락'
snapshot > "$sandbox/cutover-after"; cmp -s "$sandbox/cutover-before" "$sandbox/cutover-after" || fail '원격 실패 후 LICENSE 없는 개발판 자동 설치'
if "$installed/bin/routine" update "$sandbox/cutover-downloads/routine-automation-1.1.3.zip" --yes > "$sandbox/private-explicit" 2>&1; then fail '명시한 LICENSE 없는 개발판 ZIP 설치'; fi
for entrypoint in status morning; do
  if [[ $entrypoint == status ]]; then
    CURL_FAIL=7 ROUTINE_NOW='2026-10-01T09:00:00+09:00' ROUTINE_DOWNLOADS_DIR="$sandbox/cutover-downloads" "$installed/bin/routine" status > "$sandbox/private-status"
  else
    CURL_FAIL=7 ROUTINE_NOW='2026-10-01T09:00:00+09:00' ROUTINE_DOWNLOADS_DIR="$sandbox/cutover-downloads" "$installed/bin/morning" --only omp-update > "$sandbox/private-morning" </dev/null
  fi
  ! grep -q '새 버전' "$sandbox/private-$entrypoint" || fail 'LICENSE 없는 개발판 새 버전 알림'
done
snapshot > "$sandbox/cutover-after"; cmp -s "$sandbox/cutover-before" "$sandbox/cutover-after" || fail 'LICENSE 없는 개발판 알림이 설치'
make_zip 0.1.1 "$sandbox/cutover-downloads/routine-automation-0.1.1.zip"
CURL_FAIL=7 ROUTINE_DOWNLOADS_DIR="$sandbox/cutover-downloads" "$installed/bin/routine" update --check > "$sandbox/private-with-public" 2>&1
grep -q '0.1.0 → 0.1.1' "$sandbox/private-with-public" || fail 'LICENSE 없는 개발판 대신 새 공개 베타 선택 실패'
snapshot > "$sandbox/cutover-after"; cmp -s "$sandbox/cutover-before" "$sandbox/cutover-after" || fail '개발판과 공개 베타 비교가 설치'
CURL_FAIL=7 ROUTINE_DOWNLOADS_DIR="$sandbox/cutover-downloads" "$installed/bin/routine" update --yes > "$sandbox/public-fallback-installed" 2>&1
[[ $(cat "$installed/VERSION") == 0.1.1 && $(cat "$installed/install-id") == "$id_before" ]] || fail '공개 베타 Downloads 대체 설치 실패'
# Former development numbers remain valid for future public stable releases.
for public_version in 1.0.0 1.1.3; do
  /bin/bash "$sandbox/cutover/routine-automation-0.1.0/install.sh" --update > "$sandbox/stable-reset"
  [[ $(cat "$installed/VERSION") == 0.1.0 ]] || fail '공개 정식판 회귀의 시작 버전 오류'
  make_zip "$public_version" "$RELEASE_ZIP"
  release_list "$public_version"
  command jq '.[0].prerelease=false' "$RELEASE_LIST" > "$sandbox/stable-list"; mv "$sandbox/stable-list" "$RELEASE_LIST"
  selected=$(routine_release_query 5)
  [[ $(command jq -r .version <<< "$selected") == "$public_version" ]] || fail "공개 정식판 Release 후보 제외: $public_version"
  "$installed/bin/routine" update --from github --check > "$sandbox/stable-check"
  grep -q "0.1.0 → $public_version" "$sandbox/stable-check" || fail "공개 베타→정식판 비교 실패: $public_version"
  "$installed/bin/routine" update --from github --yes > "$sandbox/stable-installed" </dev/null
  [[ $(cat "$installed/VERSION") == "$public_version" && $(cat "$installed/install-id") == "$id_before" ]] || fail "공개 베타→정식판 설치 실패: $public_version"
  [[ $(shasum -a 256 "$ROUTINE_CONFIG") == "$config_before" ]] || fail "공개 정식판 업데이트가 설정 변경: $public_version"
done
for leftover in "$TMPDIR"/routine-github-update.* "$TMPDIR"/routine-release.* "$TMPDIR"/routine-update.*; do [[ ! -e $leftover ]] || fail 'GitHub 임시 파일 미정리'; done
! grep -q '^forbidden' "$RECORD" || fail '실제 네트워크 또는 금지 명령 진입'
printf 'PASS: curl 스텁만 사용한 prerelease·draft·수치 비교·페이지·asset/호스트/크기·태그 일치·대체·일일 캐시·수동 업데이트·공개 빌드 판별·정식판 전환\n'
