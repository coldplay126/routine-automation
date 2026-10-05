#!/usr/bin/env bash
# shellcheck disable=SC2154 # Sourced by the isolated tests/update.sh fixture.
# shellcheck disable=SC2031 # Per-command settings do not change the fixture.
export RELEASE_LIST="$sandbox/releases.json" RELEASE_SECOND="$sandbox/releases-second.json"
export RELEASE_ZIP="$sandbox/release.zip" CURL_RECORD="$sandbox/curl-calls"
cat > "$STUB_ROOT/curl" <<'CURL'
#!/bin/bash
set -eu
reject() { printf 'forbidden curl options or URL\n' >> "$RECORD"; exit 87; }
[[ ${1:-} == -q ]] || reject
shift
output='' url='' proto='' maximum='' seconds='' connect=''
while (($#)); do
  case $1 in
    --output) output=$2; shift ;;
    --proto) proto=$2; shift ;;
    --max-filesize) maximum=$2; shift ;;
    --max-time) seconds=$2; shift ;;
    --connect-timeout) connect=$2; shift ;;
    --header|--write-out) shift ;;
    --silent|--show-error) ;;
    https://*) url=$1 ;;
    *) reject ;;
  esac
  shift
done
[[ $proto == '=https' && $seconds =~ ^[1-9][0-9]*$ && $connect =~ ^[1-9][0-9]*$ && -n $output ]] || reject
printf '%s\n' "$url" >> "$CURL_RECORD"
[[ ${CURL_FAIL:-0} == 0 ]] || exit "$CURL_FAIL"
case $url in
  https://api.github.com/repositories/1405988374/releases\?per_page=100\&page=*|https://api.github.com/repos/coldplay126/routine-automation/releases\?per_page=100\&page=*)
    [[ $maximum == 2097152 ]] || reject
    if [[ $url == *'page=2' ]]; then cp "$RELEASE_SECOND" "$output"; else cp "$RELEASE_LIST" "$output"; fi
    printf '%s' "${CURL_HTTP:-200}" ;;
  https://github.com/coldplay126/routine-automation/releases/download/*)
    [[ $maximum == 67108864 ]] || reject
    [[ ${CURL_ASSET_FAIL:-0} == 0 ]] || exit "$CURL_ASSET_FAIL"
    printf '302\n%s' "${CURL_REDIRECT:-https://release-assets.githubusercontent.com/fixture.zip?signature=default-signature}" ;;
  https://objects.githubusercontent.com/fixture.zip)
    [[ $maximum == 67108864 ]] || reject
    if [[ -n ${OBJECT_REDIRECT:-} ]]; then printf '302\n%s' "$OBJECT_REDIRECT"
    else cp "$RELEASE_ZIP" "$output"; printf '200\n'; fi ;;
  https://release-assets.githubusercontent.com/fixture.zip\?signature=*)
    [[ $maximum == 67108864 ]] || reject
    if [[ -n ${CURL_EXPIRED_SIGNATURE:-} && $url == *"signature=$CURL_EXPIRED_SIGNATURE" ]]; then printf '410\n'
    else cp "$RELEASE_ZIP" "$output"; printf '200\n'; fi ;;
  *) reject ;;
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
  local digest
  digest=$(shasum -a 256 "$RELEASE_ZIP"); digest=${digest%% *}
  command jq -n --arg version "$1" --arg digest "sha256:$digest" --argjson size "$(stat -f %z "$RELEASE_ZIP")" '
    [{draft:false,prerelease:true,tag_name:("v"+$version),assets:[
      {name:("routine-automation-"+$version+".zip"),size:$size,state:"uploaded",digest:$digest,
       browser_download_url:("https://github.com/coldplay126/routine-automation/releases/download/v"+$version+"/routine-automation-"+$version+".zip")}]}]' > "$RELEASE_LIST"
}
make_zip 1.3.0 "$RELEASE_ZIP"
release_list 0.10.0
command jq '. + [ (.[0]|.tag_name="v0.9.0"), (.[0]|.tag_name="v9.0.0"|.draft=true), (.[0]|.tag_name="latest") ]' "$RELEASE_LIST" > "$sandbox/list"; mv "$sandbox/list" "$RELEASE_LIST"
selected=$(routine_release_query 5)
[[ $(command jq -r .version <<< "$selected") == 0.10.0 ]] || fail 'prerelease·draft·숫자 버전 비교 실패'
cp "$RELEASE_LIST" "$RELEASE_SECOND"
command jq -n '[range(100)|{draft:false,prerelease:true,tag_name:"v0.9.0",assets:[]}]' > "$RELEASE_LIST"
selected=$(routine_release_query 5)
[[ $(command jq -r .version <<< "$selected") == 0.10.0 ]] || fail '두 번째 페이지 최신 버전 누락'
release_list 1.4.0
snapshot > "$sandbox/release-before"
if "$installed/bin/routine" update --from github --check > "$sandbox/tag-mismatch" 2>&1; then fail '태그/VERSION 불일치 허용'; fi
for boundary in missing host repository state size actual-size digest; do
  release_list 1.3.0
  case $boundary in
    missing) command jq '.[0].assets=[]' "$RELEASE_LIST" ;;
    host) command jq '.[0].assets[0].browser_download_url="https://untrusted.example/fixture.zip"' "$RELEASE_LIST" ;;
    repository) command jq '.[0].assets[0].browser_download_url="https://github.com/attacker/other/releases/download/v1.3.0/routine-automation-1.3.0.zip"' "$RELEASE_LIST" ;;
    state) command jq '.[0].assets[0].state="open"' "$RELEASE_LIST" ;;
    size) command jq '.[0].assets[0].size=67108865' "$RELEASE_LIST" ;;
    actual-size) command jq '.[0].assets[0].size+=1' "$RELEASE_LIST" ;;
    digest) command jq '.[0].assets[0].digest=("sha256:"+("0"*64))' "$RELEASE_LIST" ;;
  esac > "$sandbox/list"
  mv "$sandbox/list" "$RELEASE_LIST"
  if "$installed/bin/routine" update --check > "$sandbox/release-$boundary" 2>&1; then fail "잘못된 Release 허용: $boundary"; fi
  grep -q -- '--from downloads' "$sandbox/release-$boundary" || fail '거부 시 수동 경로 안내 누락'
  snapshot > "$sandbox/release-after"; cmp -s "$sandbox/release-before" "$sandbox/release-after" || fail "잘못된 Release가 설치본 변경: $boundary"
done
release_list 1.3.0
if CURL_ASSET_FAIL=63 "$installed/bin/routine" update --yes > "$sandbox/oversized-download" 2>&1; then fail 'curl 63 크기 초과를 허용'; fi
grep -q '64MiB' "$sandbox/oversized-download" || fail '크기 초과 이유 누락'
for redirect in https://untrusted.example/fixture.zip https://evil.githubusercontent.com/fixture.zip http://github.com/fixture.zip https://github.com.evil.example/fixture.zip https://github.com/coldplay126/routine-automation/releases/download/v1.3.0/routine-automation-1.3.0.zip; do
  if CURL_REDIRECT=$redirect "$installed/bin/routine" update --check > "$sandbox/redirect-host" 2>&1; then fail "허용 외 리다이렉트: $redirect"; fi
done
if CURL_REDIRECT=https://objects.githubusercontent.com/fixture.zip OBJECT_REDIRECT=https://evil.githubusercontent.com/fixture.zip "$installed/bin/routine" update --check > "$sandbox/redirect-second-hop" 2>&1; then fail '두 번째 호스트 검사 누락'; fi
! grep -Eq 'untrusted\.example|evil\.githubusercontent\.com|http://github\.com|github\.com\.evil\.example|github\.com/attacker' "$CURL_RECORD" || fail '허용 외 URL에 curl 요청'
CURL_REDIRECT=https://objects.githubusercontent.com/fixture.zip "$installed/bin/routine" update --check > "$sandbox/redirect-safe"
grep -q '0.1.1 → 1.3.0' "$sandbox/redirect-safe" || fail 'object 리다이렉트 실패'
for signature in first-signature rotated-signature; do
  expired=''; [[ $signature != rotated-signature ]] || expired=first-signature
  CURL_EXPIRED_SIGNATURE=$expired CURL_REDIRECT="https://release-assets.githubusercontent.com/fixture.zip?signature=$signature" "$installed/bin/routine" update --from github --check > "$sandbox/redirect-release-assets"
  grep -q '0.1.1 → 1.3.0' "$sandbox/redirect-release-assets" || fail '서명 URL 재해석 실패'
done
redirect_before=$(wc -l < "$CURL_RECORD")
if CURL_REDIRECT=https://objects.githubusercontent.com/fixture.zip OBJECT_REDIRECT=https://objects.githubusercontent.com/fixture.zip "$installed/bin/routine" update --check > "$sandbox/redirect-loop" 2>&1; then fail '리다이렉트 무한 반복'; fi
[[ $(wc -l < "$CURL_RECORD") -eq $((redirect_before+6)) ]] || fail '5회 요청 상한 실패'
ROUTINE_TEST_RELEASE_REPO=attacker/other "$installed/bin/routine" update --check > "$sandbox/installed-override"
! grep -q 'attacker' "$CURL_RECORD" || fail '설치본의 테스트 저장소 재정의 허용'
# No availability failure may lower the trust boundary to Downloads.
mkdir "$sandbox/unverified-downloads"
make_zip 9.9.9 "$sandbox/unverified-downloads/routine-automation-9.9.9.zip"
for failure in network 403 429 empty; do
  release_list 1.3.0
  status=0
  case $failure in
    network) CURL_FAIL=7 ROUTINE_DOWNLOADS_DIR="$sandbox/unverified-downloads" "$installed/bin/routine" update --yes > "$sandbox/unavailable-$failure" 2>&1 || status=$? ;;
    403|429) CURL_HTTP=$failure ROUTINE_DOWNLOADS_DIR="$sandbox/unverified-downloads" "$installed/bin/routine" update --yes > "$sandbox/unavailable-$failure" 2>&1 || status=$? ;;
    empty) printf '[]\n' > "$RELEASE_LIST"; ROUTINE_DOWNLOADS_DIR="$sandbox/unverified-downloads" "$installed/bin/routine" update --yes > "$sandbox/unavailable-$failure" 2>&1 || status=$? ;;
  esac
  ((status)) || fail 'GitHub 실패를 자동 설치 성공으로 처리'
  ! grep -q '9.9.9' "$sandbox/unavailable-$failure" || fail 'auto가 Downloads 후보를 탐색'
  snapshot > "$sandbox/release-after"; cmp -s "$sandbox/release-before" "$sandbox/release-after" || fail '원격 실패 후 Downloads 자동 설치'
done
CURL_HTTP=403 ROUTINE_NOW='2026-10-02T09:00:00+09:00' ROUTINE_DOWNLOADS_DIR="$sandbox/unverified-downloads" "$installed/bin/routine" status > "$sandbox/unverified-status"
CURL_HTTP=403 ROUTINE_NOW='2026-10-02T09:00:00+09:00' ROUTINE_DOWNLOADS_DIR="$sandbox/unverified-downloads" "$installed/bin/morning" --only omp-update > "$sandbox/unverified-morning" </dev/null
! grep -q '새 버전' "$sandbox/unverified-status" "$sandbox/unverified-morning" || fail 'GitHub 403이 Downloads 9.9.9을 알림'
if ROUTINE_DOWNLOADS_DIR="$sandbox/unverified-downloads" "$installed/bin/routine" update --from downloads --yes > "$sandbox/downloads-yes" 2>&1 </dev/null; then fail 'Downloads --yes 비TTY 허용'; fi
for field in '경로:' 'sha256:' 'quarantine:' 'kMDItemWhereFroms:'; do grep -q "$field" "$sandbox/downloads-yes" || fail 'Downloads 출처 표시 누락'; done
snapshot > "$sandbox/release-after"; cmp -s "$sandbox/release-before" "$sandbox/release-after" || fail 'Downloads 비TTY 설치 실행'
release_list 1.3.0
cache="$HOME/Library/Caches/routine-automation/releases.json"
rm -f "$cache"; : > "$CURL_RECORD"
"$installed/bin/routine" status > "$sandbox/release-status"
"$installed/bin/morning" --only omp-update > "$sandbox/release-morning" </dev/null
for output in "$sandbox/release-status" "$sandbox/release-morning" "$RECORD.notice"; do grep -q '새 버전 1.3.0 — routine update' "$output" || fail '공개 새 버전 안내 누락'; done
[[ $(wc -l < "$CURL_RECORD") -eq 1 && $(stat -f %Lp "$cache") == 600 ]] || fail '하루 1회 0600 캐시 실패'
command jq -e '[..|strings]|all(.[]; contains("signature=")|not)' "$cache" >/dev/null || fail '서명 URL 캐시'
ROUTINE_NOW='2026-09-29T09:00:00+09:00' "$installed/bin/routine" status > "$sandbox/release-next-day"
[[ $(wc -l < "$CURL_RECORD") -eq 2 ]] || fail '다음 날 갱신 실패'
CURL_FAIL=7 ROUTINE_NOW='2026-09-30T09:00:00+09:00' "$installed/bin/routine" status > "$sandbox/release-failed-day"
CURL_FAIL=7 ROUTINE_NOW='2026-09-30T09:00:00+09:00' "$installed/bin/morning" --only omp-update > "$sandbox/release-failed-morning" </dev/null
[[ $(wc -l < "$CURL_RECORD") -eq 3 ]] || fail '실패 조회를 같은 날 반복'
"$installed/bin/routine" update --check > "$sandbox/release-check"
grep -q '0.1.1 → 1.3.0' "$sandbox/release-check" || fail '실제 package 공개 확인 실패'
"$installed/bin/routine" update --yes > "$sandbox/release-installed" </dev/null
[[ $(cat "$installed/VERSION") == 1.3.0 && $(cat "$installed/install-id") == "$id_before" ]] || fail '공개 실제 업데이트 실패'
[[ $(shasum -a 256 "$ROUTINE_CONFIG") == "$config_before" ]] || fail '설정 변경'
ROUTINE_NOW='2026-09-29T09:00:00+09:00' "$installed/bin/routine" status > "$sandbox/release-current"
! grep -q '새 버전' "$sandbox/release-current" || fail '개발 VERSION과 비교'
# Marker validation and explicit TTY approval remain independent of version numbers.
mkdir "$sandbox/cutover-downloads" "$sandbox/cutover"
make_zip 1.1.3 "$sandbox/cutover-downloads/routine-automation-1.1.3.zip"
/usr/bin/zip -qd "$sandbox/cutover-downloads/routine-automation-1.1.3.zip" routine-automation-1.1.3/LICENSE
make_zip 0.1.0 "$sandbox/cutover.zip"
ditto -x -k "$sandbox/cutover.zip" "$sandbox/cutover"
/bin/bash "$sandbox/cutover/routine-automation-0.1.0/install.sh" --update > "$sandbox/public-cutover"
ROUTINE_DOWNLOADS_DIR="$sandbox/cutover-downloads" "$installed/bin/routine" update --from downloads --check > "$sandbox/private-only" 2>&1
grep -q '공개 빌드가 아닌 개발판 zip' "$sandbox/private-only" || fail '개발판 거부 안내 누락'
grep -Fq "$sandbox/cutover-downloads/routine-automation-1.1.3.zip" "$sandbox/private-only" || fail '개발판 경로 누락'
make_zip 0.1.1 "$sandbox/cutover-downloads/routine-automation-0.1.1.zip"
ROUTINE_DOWNLOADS_DIR="$sandbox/cutover-downloads" "$installed/bin/routine" update --from downloads --check > "$sandbox/private-with-public" 2>&1
grep -q '0.1.0 → 0.1.1' "$sandbox/private-with-public" || fail '정상 공개 후보 선택 실패'
ROUTINE_DOWNLOADS_DIR="$sandbox/cutover-downloads" /usr/bin/expect -f "$repo/tests/fixtures/update-pty.exp" "$installed/bin/routine" "$sandbox/tty-approved" y --from downloads --yes > "$sandbox/public-downloads-installed"
[[ $(cat "$installed/VERSION") == 0.1.1 && $(cat "$installed/install-id") == "$id_before" ]] || fail 'Downloads TTY 명시 동의 설치 실패'
# A changed candidate must invalidate the cached version, not hide the next ZIP.
printf 'invalidated zip\n' > "$sandbox/cutover-downloads/routine-automation-0.1.1.zip"
make_zip 0.1.2 "$sandbox/cutover-downloads/routine-automation-0.1.2.zip"
ROUTINE_DOWNLOADS_DIR="$sandbox/cutover-downloads" "$installed/bin/routine" update --from downloads --check > "$sandbox/cache-invalidation" 2>&1
grep -q '0.1.1 → 0.1.2' "$sandbox/cache-invalidation" || fail '변경 ZIP 캐시 무효화 실패'
for public_version in 1.0.0 1.1.3; do
  /bin/bash "$sandbox/cutover/routine-automation-0.1.0/install.sh" --update > "$sandbox/stable-reset"
  make_zip "$public_version" "$RELEASE_ZIP"; release_list "$public_version"
  command jq '.[0].prerelease=false' "$RELEASE_LIST" > "$sandbox/stable-list"; mv "$sandbox/stable-list" "$RELEASE_LIST"
  "$installed/bin/routine" update --from github --yes > "$sandbox/stable-installed" </dev/null
  [[ $(cat "$installed/VERSION") == "$public_version" && $(cat "$installed/install-id") == "$id_before" ]] || fail '공개 정식판 전환 실패'
done
# Install the frozen public 0.1.0 tree, not current sources labelled 0.1.0.
mkdir "$sandbox/frozen-client"
ditto -x -k "$repo/tests/fixtures/public-0.1.0.zip" "$sandbox/frozen-client"
/bin/bash "$sandbox/frozen-client/routine-automation-0.1.0/install.sh" --update > "$sandbox/frozen-installed"
[[ $(cat "$installed/VERSION") == 0.1.0 ]] || fail '보관된 실제 공개 클라이언트 설치 실패'
client_target=0.1.1
if [[ -n ${TEST_HEAD_PACKAGE_ZIP:-} ]]; then
  [[ -f $TEST_HEAD_PACKAGE_ZIP ]] || fail '실제 HEAD package ZIP 입력 없음'
  client_target=$(<"$repo/VERSION")
  cp "$TEST_HEAD_PACKAGE_ZIP" "$RELEASE_ZIP"
else make_zip "$client_target" "$RELEASE_ZIP"; fi
release_list "$client_target"
"$installed/bin/routine" update --from github --yes > "$sandbox/frozen-updated" </dev/null
[[ $(cat "$installed/VERSION") == "$client_target" && $(cat "$installed/install-id") == "$id_before" && $(shasum -a 256 "$ROUTINE_CONFIG") == "$config_before" ]] || fail '공개 0.1.0 클라이언트→현재 실제 package 업데이트 실패'
for leftover in "$TMPDIR"/routine-github-update.* "$TMPDIR"/routine-release.* "$TMPDIR"/routine-update.*; do [[ ! -e $leftover ]] || fail '임시 파일 미정리'; done
! grep -q '^forbidden' "$RECORD" || fail '실제 네트워크 또는 금지 명령 진입'
printf 'PASS: 정확 URL·저장소 ID·uploaded·digest/size·302·curl 옵션·원격 실패 설치/알림 0·Downloads TTY·캐시·보관 0.1.0 실제 업데이트\n'
