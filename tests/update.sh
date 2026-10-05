#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
real_jq=${TEST_JQ_BIN:-$(type -P jq)}
real_node=$(type -P node)
while IFS= read -r name; do [[ $name != ROUTINE_* ]] || unset "$name"; done < <(compgen -v)
sandbox=$(mktemp -d /tmp/routine-update-tests.XXXXXXXX)
cleanup() {
  local status=$?
  if ((status)); then
    [[ ! -f $sandbox/failure ]] || cat "$sandbox/failure" >&2
    for output in "$sandbox"/highest "$sandbox"/command "$sandbox"/rollback "$sandbox"/updated "$sandbox"/schema-zip-guide "$sandbox"/incompatible-package; do
      [[ ! -f $output ]] || { printf '\n%s:\n' "${output##*/}" >&2; cat "$output" >&2; }
    done
  fi
  rm -rf -- "$sandbox"
}
trap cleanup EXIT
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" USER=fixture
export STUB_ROOT="$sandbox/stubs" RECORD="$sandbox/calls"
export PATH="$STUB_ROOT:/usr/bin:/bin"
export ROUTINE_CONFIG="$HOME/team/config.json" ROUTINE_NOW='2026-09-28T09:00:00+09:00'
mkdir -p "$STUB_ROOT" "$TMPDIR" "$HOME/.local/bin" "$HOME/Downloads"
ln -s "$real_jq" "$STUB_ROOT/jq"
# shellcheck source=network.sh
source "$repo/tests/network.sh"
cat > "$STUB_ROOT/launchctl" <<'STUB'
#!/bin/bash
printf 'launchctl %s\n' "$*" >> "$RECORD"
case $1 in
  print) [[ -f $RECORD.loaded.${2##*/} ]] ;;
  bootout) rm -f "$RECORD.loaded.${2##*/}" ;;
  bootstrap)
    [[ $(cat "$HOME/.local/share/routine-automation/VERSION") != "${FAIL_VERSION:-never}" ]] || exit 5
    label=${3##*/}; : > "$RECORD.loaded.${label%.plist}" ;;
  *) exit 87 ;;
esac
STUB
cat > "$STUB_ROOT/osacompile" <<'STUB'
#!/bin/bash
printf 'osacompile %s\n' "$*" >> "$RECORD"
[[ $1 == -o ]] || exit 87
mkdir -p "$2/Contents/MacOS"
printf 'fixture app\n' > "$2/Contents/MacOS/applet"
STUB
cat > "$STUB_ROOT/osascript" <<'STUB'
#!/bin/bash
printf 'osascript %s\n' "$*" >> "$RECORD"
printf '%s\n' "${!#}" > "$RECORD.notice"
STUB
cat > "$STUB_ROOT/xattr" <<'STUB'
#!/bin/bash
printf 'xattr %s\n' "$*" >> "$RECORD"
STUB
cat > "$STUB_ROOT/gh" <<'STUB'
#!/bin/bash
[[ "$*" == 'api user' ]] || exit 87
printf '{"id":42,"login":"fixture"}\n'
STUB
cat > "$STUB_ROOT/git" <<'STUB'
#!/bin/bash
if [[ "$*" == 'config user.email' ]]; then echo fixture@example.com; else exec /usr/bin/git "$@"; fi
STUB
cat > "$STUB_ROOT/gtimeout" <<'STUB'
#!/bin/bash
shift 3
exec "$@"
STUB
for cmd in brew open orca omp claude gum; do
  # shellcheck disable=SC2016 # The generated stub reads its own exported environment.
  printf '#!/bin/bash\nprintf "forbidden %%s\\n" "$0" >> "$RECORD"\nexit 87\n' > "$STUB_ROOT/$cmd"
done
chmod +x "$STUB_ROOT/"*
for cmd in jq launchctl osacompile osascript xattr gh git gtimeout brew open orca omp claude gum; do ln -s "$STUB_ROOT/$cmd" "$HOME/.local/bin/$cmd"; done
# Both PATH and exported functions protect subprocesses that rebuild PATH.
launchctl() {
  if [[ ${1:-} == bootstrap && $(cat "$HOME/.local/share/routine-automation/VERSION") == "${CRASH_VERSION:-never}" ]]; then
    exec /bin/sh -c 'kill -KILL "$$"'
  fi
  "$STUB_ROOT/launchctl" "$@"
}
osacompile() { "$STUB_ROOT/osacompile" "$@"; }
osascript() { "$STUB_ROOT/osascript" "$@"; }
xattr() { "$STUB_ROOT/xattr" "$@"; }
brew() { "$STUB_ROOT/brew" "$@"; }
open() { "$STUB_ROOT/open" "$@"; }
orca() { "$STUB_ROOT/orca" "$@"; }
omp() { "$STUB_ROOT/omp" "$@"; }
claude() { "$STUB_ROOT/claude" "$@"; }
gum() { "$STUB_ROOT/gum" "$@"; }
ditto() {
  if [[ ${4:-} == "$TMPDIR"/routine-update.* ]]; then
    [[ $(stat -f %Lp "$4") == 700 ]] || { echo '업데이트 임시 디렉터리가 공개됨' >&2; return 86; }
  fi
  /usr/bin/ditto "$@"
}
type() {
  if [[ ${1:-} == -P && ${2:-} == gum ]]; then return 1; fi
  if [[ ${1:-} == -P && ${2:-} == jq && ${MISSING_JQ:-0} == 1 ]]; then return 1; fi
  builtin type "$@"
}
export -f launchctl osacompile osascript xattr brew open orca omp claude gum ditto type
routine="$repo/bin/routine"
"$routine" init --non-interactive --slack-link https://example.slack.com/archives/CEXAMPLE/p1790895609247049 --slack-team-id TEXAMPLE --sources-git-enabled false --draft-llm-engine none > "$sandbox/init"
# An omitted new key is filled by the new code's defaults, not by rewriting config.
jq '.morning.time="07:15"|del(.draft.format)' "$ROUTINE_CONFIG" > "$sandbox/config"; mv "$sandbox/config" "$ROUTINE_CONFIG"
mkdir -p "$HOME/.config/routine-automation"
jq '.morning.time="09:45"' "$ROUTINE_CONFIG" > "$HOME/.config/routine-automation/config.json"
mkdir -p "$HOME/Library/Application Support/routine-automation/scrum" "$HOME/Library/Logs/routine-automation"
printf '보존할 수집 데이터\n' > "$HOME/Library/Application Support/routine-automation/scrum/saved.json"
printf '보존할 로그\n' > "$HOME/Library/Logs/routine-automation/saved.log"
source_dir="$sandbox/source/routine-automation"
mkdir -p "$source_dir"
cp -R "$repo/bin" "$repo/share" "$repo/launchd" "$source_dir/"
cp "$repo/install.sh" "$repo/uninstall.sh" "$repo/CHANGELOG.md" "$repo/routine 설치.command" "$source_dir/"
printf '# 변경 내역\n\n## 0.1.1 — fixture\n\n- 새 배포 fixture\n\n## 0.0.1\n\n- 이전 fixture\n' > "$source_dir/CHANGELOG.md"
printf '0.0.1\n' > "$source_dir/VERSION"
install_args=(--yes --non-interactive --skip platform --skip dependencies --skip github --skip llm --skip slack --skip orca --skip disk-access --skip config --skip first-run)
printf '\n' | /bin/bash "$source_dir/routine 설치.command" "${install_args[@]}" > "$sandbox/command"
grep -q 'routine 설치 완료' "$sandbox/command" || fail '더블클릭 런처의 설치 결과 누락'
installed="$HOME/.local/share/routine-automation"
# Use the actual configured prefix rather than a test-only default.
plist="$HOME/Library/LaunchAgents/$(jq -r '.launchd.label_prefix' "$ROUTINE_CONFIG").morning.plist"
[[ -f $installed/manifest.json && -f $plist ]] || fail '런처가 설치·LaunchAgent 등록을 실행하지 않음'
snapshot() {
  find "$installed" -type f -exec shasum -a 256 {} + | LC_ALL=C sort
  shasum -a 256 "$ROUTINE_CONFIG" "$plist" "$HOME/Library/Application Support/routine-automation/scrum/saved.json" "$HOME/Library/Logs/routine-automation/saved.log"
  readlink "$HOME/.local/bin/routine"
}
snapshot > "$sandbox/before"
id_before=$(cat "$installed/install-id")
config_before=$(shasum -a 256 "$ROUTINE_CONFIG")
plist_before=$(shasum -a 256 "$plist")
# Every normal update candidate is built by the real package command. In particular,
# git archive's short FAT directory attributes must not be mistaken for missing entries.
package_repo="$sandbox/package"
git init -q -b main "$package_repo"
cp -R "$source_dir/bin" "$source_dir/share" "$source_dir/launchd" "$package_repo/"
cp "$source_dir/VERSION" "$source_dir/install.sh" "$source_dir/uninstall.sh" "$source_dir/CHANGELOG.md" "$source_dir/routine 설치.command" "$repo/설치 방법.txt" "$repo/.gitignore" "$package_repo/"
cp "$repo/README.md" "$repo/LICENSE" "$package_repo/"
git -C "$package_repo" add -A .
git -C "$package_repo" -c user.name=Fixture -c user.email=fixture@example.com commit -qm '팀 배포 fixture'
make_zip() {
  local version=$1 destination=$2
  printf '%s\n' "$version" > "$source_dir/VERSION"
  printf '%s\n' "$version" > "$package_repo/VERSION"
  cp "$source_dir/launchd/routine.morning.plist.in" "$package_repo/launchd/"
  git -C "$package_repo" add VERSION launchd/routine.morning.plist.in
  git -C "$package_repo" -c user.name=Fixture -c user.email=fixture@example.com commit -qm "배포 $version" --allow-empty
  "$package_repo/bin/routine" package > "$sandbox/package-$version"
  cp "$package_repo/dist/routine-automation-$version.zip" "$destination"
}
# Filenames lie; 0.10.0 must beat 0.9.0 by the archived numeric VERSION.
make_zip 0.0.1 "$HOME/Downloads/routine-automation-999.0.0.zip"
printf '\n<!-- 새 배포 예약 템플릿 -->\n' >> "$source_dir/launchd/routine.morning.plist.in"
make_zip 0.1.1 "$HOME/Downloads/routine-automation-current.zip"
make_zip 0.9.0 "$HOME/Downloads/routine-automation-z.zip"
make_zip 0.10.0 "$HOME/Downloads/routine-automation-a.zip"
mkdir -p "$HOME/Downloads/routine-automation-99.0.0"
printf '99.0.0\n' > "$HOME/Downloads/routine-automation-99.0.0/VERSION"
printf 'not a zip\n' > "$HOME/Downloads/routine-automation-broken.zip"
"$real_node" "$repo/tests/zip-fixtures.cjs" "$sandbox/edge"
for kind in missing-high crc-high version-33 size-over; do cp "$sandbox/edge/$kind.zip" "$HOME/Downloads/routine-automation-$kind.zip"; done
"$installed/bin/routine" update --check > "$sandbox/highest" </dev/null
grep -q '0.0.1 → 0.10.0' "$sandbox/highest" || fail '내부 VERSION 최고 수치 버전 선택 실패'
grep -q '^## 0.1.1' "$sandbox/highest" || fail '현재→새 버전 변경 내역 누락'
! grep -q '^## 0.0.1' "$sandbox/highest" || fail '현재 버전 내역까지 표시'
snapshot > "$sandbox/after"; cmp -s "$sandbox/before" "$sandbox/after" || fail '--check가 설치본을 변경'
for kind in korean no-directories version-32 controls; do
  "$installed/bin/routine" update "$sandbox/edge/$kind.zip" --check > "$sandbox/accept-$kind" 2>&1 || fail "정상 zip 거부: $kind"
  grep -q '✓ zip 검증' "$sandbox/accept-$kind" || fail "정상 zip 검증 완료 누락: $kind"
done
! grep -q $'\033\\|\007\\|\177' "$sandbox/accept-controls" || fail 'CHANGELOG 제어문자 출력'
mkdir "$TMPDIR/escaped"; printf '보존\n' > "$TMPDIR/escaped/payload"
for kind in duplicate case-alias normalization-alias local-name local-double-slash missing-high crc-high version-33 size-over symlink-host-0 symlink-host-3 symlink-host-10 symlink-write; do
  if "$installed/bin/routine" update "$sandbox/edge/$kind.zip" --check > "$sandbox/reject-$kind" 2>&1; then
    cp "$sandbox/reject-$kind" "$sandbox/failure"; fail "잘못된 실제 zip 허용: $kind"
  fi
  grep -Fq "$sandbox/edge/$kind.zip" "$sandbox/reject-$kind" || fail "거부 zip 경로 누락: $kind"
  ! grep -q '✓ zip 검증' "$sandbox/reject-$kind" || fail "검증 전 성공 표시: $kind"
done
[[ $(cat "$TMPDIR/escaped/payload") == 보존 ]] || fail 'FAT 링크를 통한 임시 디렉터리 밖 쓰기'
snapshot > "$sandbox/after"; cmp -s "$sandbox/before" "$sandbox/after" || fail 'ZIP 검증이 설치본 변경'
rm "$HOME/Downloads/routine-automation-a.zip" "$HOME/Downloads/routine-automation-z.zip"
# Read-only status and real morning entrypoint notify; no installer/first-run.
"$installed/bin/routine" status > "$sandbox/status"
grep -q '새 버전 0.1.1 — routine update' "$sandbox/status" || fail 'status 새 버전 안내 누락'
"$installed/bin/morning" --only omp-update > "$sandbox/morning" </dev/null
grep -q '새 버전 0.1.1 — routine update' "$sandbox/morning" || fail 'morning 요약 새 버전 안내 누락'
grep -q '새 버전 0.1.1 — routine update' "$RECORD.notice" || fail 'morning 알림 새 버전 안내 누락'
snapshot > "$sandbox/after"; cmp -s "$sandbox/before" "$sandbox/after" || fail '알림이 자동 설치'
"$installed/bin/routine" update > "$sandbox/non-tty" </dev/null
snapshot > "$sandbox/after"; cmp -s "$sandbox/before" "$sandbox/after" || fail '비TTY 무동의 업데이트 실행'
grep -q -- '--yes' "$sandbox/non-tty" || fail '비TTY 업데이트 동의 안내 누락'
printf 'n\n' | /usr/bin/script -q "$sandbox/tty-update" "$installed/bin/routine" update > "$sandbox/tty-output"
snapshot > "$sandbox/after"; cmp -s "$sandbox/before" "$sandbox/after" || fail 'TTY 확인 거절 후 업데이트 실행'
# Real malicious ZIPs, not mocked unzip output. bsdtar preserves hostile names with -P.
printf '경로 탈출 fixture\n' > "$source_dir/payload"
make_zip 2.0.0 "$sandbox/base.zip"
for kind in traversal absolute missing symlink multiple; do
  malicious="$sandbox/$kind.zip"
  case $kind in
    traversal|absolute)
      target='routine-automation/../../../escaped'; [[ $kind != absolute ]] || target="$sandbox/escaped"
      (cd "$sandbox/source" && /usr/bin/tar -P --format zip -cf "$malicious" -s "|^routine-automation/payload$|$target|" routine-automation) ;;
    missing)
      cp "$sandbox/base.zip" "$malicious"; /usr/bin/zip -qd "$malicious" routine-automation-2.0.0/bin/routine ;;
    symlink)
      mv "$source_dir/install.sh" "$sandbox/install.saved"
      ln -s "$sandbox/install.saved" "$source_dir/install.sh"
      (cd "$sandbox/source" && /usr/bin/zip -qry "$malicious" routine-automation)
      rm "$source_dir/install.sh"; mv "$sandbox/install.saved" "$source_dir/install.sh" ;;
    multiple)
      cp "$sandbox/base.zip" "$malicious"
      mkdir -p "$sandbox/source/another"; printf '2.0.0\n' > "$sandbox/source/another/VERSION"
      (cd "$sandbox/source" && /usr/bin/zip -qr "$malicious" another) ;;
  esac
  if "$installed/bin/routine" update "$malicious" --yes > "$sandbox/reject-$kind" 2>&1; then fail "악성 zip 허용: $kind"; fi
  snapshot > "$sandbox/after"; cmp -s "$sandbox/before" "$sandbox/after" || fail "악성 zip이 설치본 변경: $kind"
  [[ ! -e $sandbox/escaped ]] || fail 'zip 경로 탈출'
done
# Failed new LaunchAgent loading must roll back the complete owned generation.
if ROUTINE_CONFIG="$HOME/.config/routine-automation/config.json" "$installed/bin/routine" update --check > "$sandbox/mismatched-config" 2>&1; then fail '다른 설정 경로로 업데이트 허용'; fi
grep -Fq "$HOME/team/config.json" "$sandbox/mismatched-config" || fail '기존 설정 경로 안내 누락'
for lock in "$HOME/Library/Logs/routine-automation/.morning.lock" "$HOME/Library/Application Support/routine-automation/scrum/.scrum-paste.lock"; do
  mkdir "$lock"; printf '%s\n' "$$" > "$lock/pid"
  if "$installed/bin/routine" update --yes > "$sandbox/active-lock" 2>&1; then fail '실행 중 파일 교체 허용'; fi
  snapshot > "$sandbox/after"; cmp -s "$sandbox/before" "$sandbox/after" || fail '실행 중 설치본 변경'
  rm -rf "$lock"
done
if FAIL_VERSION=0.1.1 "$installed/bin/routine" update --yes > "$sandbox/rollback" 2>&1; then fail '예약 등록 실패를 성공 처리'; fi
snapshot > "$sandbox/after"; cmp -s "$sandbox/before" "$sandbox/after" || fail '설치 실패 롤백이 기존 자산 변경'
launchctl print "gui/$(id -u)/$(jq -r '.launchd.label_prefix' "$ROUTINE_CONFIG").morning" >/dev/null || fail '이전 LaunchAgent 복원 실패'
/usr/bin/env -u ROUTINE_CONFIG "$installed/bin/routine" update --yes > "$sandbox/updated" </dev/null
[[ $(cat "$installed/VERSION") == 0.1.1 && $(cat "$installed/install-id") == "$id_before" ]] || fail '업데이트 버전/설치 신원 보존 실패'
[[ $(shasum -a 256 "$ROUTINE_CONFIG") == "$config_before" ]] || fail '업데이트가 설정 파일 변경'
[[ $(shasum -a 256 "$plist") != "$plist_before" ]] || fail '새 LaunchAgent 템플릿 미반영'
[[ $(cat "$HOME/Library/Application Support/routine-automation/scrum/saved.json") == '보존할 수집 데이터' && $(cat "$HOME/Library/Logs/routine-automation/saved.log") == '보존할 로그' ]] || fail '업데이트 데이터/로그 유실'
grep -q '✓ 0.1.1으로 업데이트' "$sandbox/updated" || fail '업데이트 성공 버전 누락'
[[ -f $HOME/Downloads/routine-automation-current.zip ]] || fail '사용한 zip 자동 삭제'
[[ $("$installed/bin/routine" config get draft.format.layout) == tree ]] || fail '누락된 새 설정 키 기본값 미적용'
[[ $(jq -r '.configuration_path' "$installed/manifest.json") == "$HOME/team/config.json" &&
   $(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:0:Hour' "$plist") == 7 &&
   $(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:0:Minute' "$plist") == 15 ]] || fail '기존 사용자 지정 설정 경로·예약 시간 변경'
snapshot > "$sandbox/updated-before"
for zip in "$HOME/Downloads/routine-automation-current.zip" "$HOME/Downloads/routine-automation-999.0.0.zip"; do
  "$installed/bin/routine" update "$zip" --yes > "$sandbox/not-newer" </dev/null
  grep -q '이미 최신' "$sandbox/not-newer" || fail '같거나 낮은 버전 안내 누락'
  snapshot > "$sandbox/after"; cmp -s "$sandbox/updated-before" "$sandbox/after" || fail '같거나 낮은 버전 재설치'
done
"$installed/bin/routine" status > "$sandbox/status-current"
! grep -q '새 버전' "$sandbox/status-current" || fail '같은 버전을 새 버전으로 알림'
# Alternate download location and explicit paths do not depend on cwd.
mkdir "$sandbox/downloads"
make_zip 0.2.0 "$sandbox/downloads/routine-automation-next.zip"
ROUTINE_DOWNLOADS_DIR="$sandbox/downloads" "$installed/bin/routine" update --check > "$sandbox/alternate" </dev/null
grep -q '0.1.1 → 0.2.0' "$sandbox/alternate" || fail '다운로드 경로 환경 변수 무시'
(CDPATH="$sandbox" && cd "$sandbox" && /bin/bash home/.local/share/routine-automation/bin/routine update downloads/routine-automation-next.zip --check) > "$sandbox/cdpath"
grep -q '0.1.1 → 0.2.0' "$sandbox/cdpath" || fail 'CDPATH가 상대 zip 경로 손상'
if CRASH_VERSION=0.2.0 /usr/bin/env -u ROUTINE_CONFIG "$installed/bin/routine" update "$sandbox/downloads/routine-automation-next.zip" --yes > "$sandbox/killed" 2>&1; then fail 'SIGKILL 업데이트를 성공 처리'; fi
[[ -d $installed.previous && $(cat "$installed/VERSION") == 0.2.0 ]] || fail 'SIGKILL이 새 세대·복구 기록을 남기지 않음'
"$installed/bin/routine" status > "$sandbox/status-pending"
if ! grep -q '미완료 설치' "$sandbox/status-pending" || ! grep -q '예약 실행 미등록' "$sandbox/status-pending"; then fail '미완료 설치·미등록 예약 상태 누락'; fi
snapshot > "$sandbox/pending-before"
"$installed/bin/routine" update "$sandbox/downloads/routine-automation-next.zip" --check > "$sandbox/pending-check"
snapshot > "$sandbox/after"; cmp -s "$sandbox/pending-before" "$sandbox/after" || fail '미완료 설치 --check가 복구 실행'
if ! grep -q '복구' "$sandbox/pending-check" || grep -q '이미 최신' "$sandbox/pending-check"; then fail '미완료 설치를 최신 상태로 안내'; fi
/usr/bin/env -u ROUTINE_CONFIG "$installed/bin/routine" update "$sandbox/downloads/routine-automation-next.zip" --yes > "$sandbox/recovered"
[[ ! -e $installed.previous && $(cat "$installed/VERSION") == 0.2.0 && $(cat "$installed/install-id") == "$id_before" ]] || fail '같은 ZIP 재실행 중단 복구 실패'
launchctl print "gui/$(id -u)/$(jq -r '.launchd.label_prefix' "$ROUTINE_CONFIG").morning" >/dev/null || fail '중단 복구 후 예약 실행 미등록'
"$installed/bin/routine" status > "$sandbox/status-healthy"
if grep -q '예약 실행 미등록\|미완료 설치' "$sandbox/status-healthy"; then fail '정상 설치에서 미등록·미완료 경고'; fi
[[ $(shasum -a 256 "$ROUTINE_CONFIG") == "$config_before" ]] || fail '중단 복구가 기존 설정 변경'
snapshot > "$sandbox/recovered-before"
if MISSING_JQ=1 /bin/bash "$source_dir/install.sh" --update > "$sandbox/no-jq" 2>&1; then fail 'jq 없는 업데이트 허용'; fi
grep -q 'jq 1.7 이상' "$sandbox/no-jq" || fail 'jq 최소 버전 안내 누락'
cp -R "$source_dir" "$sandbox/new-schema"
printf '\ndef required_errors: [\"새필수키\"];\n' >> "$sandbox/new-schema/share/config.jq"
if /usr/bin/env -u ROUTINE_CONFIG /bin/bash "$sandbox/new-schema/install.sh" --update > "$sandbox/schema-guide" 2>&1; then fail '새 필수 키 누락 업데이트 허용'; fi
if ! grep -Fq "$sandbox/new-schema/bin/routine setup" "$sandbox/schema-guide" || ! grep -q '새 패키지의 routine 설치.command' "$sandbox/schema-guide"; then fail '새 패키지 설정 도구 안내 누락'; fi
if ROUTINE_UPDATE_ZIP_PATH="$sandbox/downloads/routine-automation-next.zip" /bin/bash "$sandbox/new-schema/install.sh" --update > "$sandbox/schema-zip-guide" 2>&1; then fail 'ZIP 새 필수 키 누락 업데이트 허용'; fi
if ! grep -Fq "$sandbox/downloads/routine-automation-next.zip" "$sandbox/schema-zip-guide" || grep -Fq "$sandbox/new-schema/bin/routine setup" "$sandbox/schema-zip-guide"; then fail '지워질 임시 폴더 대신 원본 ZIP 안내 누락'; fi
snapshot > "$sandbox/after"; cmp -s "$sandbox/recovered-before" "$sandbox/after" || fail '설정 검사 실패가 설치본 변경'
for leftover in "$TMPDIR"/routine-update.* "$HOME/.local/share"/.routine-install.* "$HOME/.local/share"/.routine-transaction.*; do [[ ! -e $leftover ]] || fail '업데이트 임시 디렉터리 미정리'; done
! grep -q '^forbidden\|launchctl kickstart' "$RECORD" || fail '금지 명령 또는 업데이트 첫 실행'
# Observe the packaged launcher's permission and execute it without a GUI.
make_zip 0.1.1 "$sandbox/final-package.zip"
mkdir "$sandbox/unpacked"
ditto -x -k "$sandbox/final-package.zip" "$sandbox/unpacked"
[[ -x $sandbox/unpacked/routine-automation-0.1.1/routine\ 설치.command && -f $sandbox/unpacked/routine-automation-0.1.1/CHANGELOG.md && -f $sandbox/unpacked/routine-automation-0.1.1/설치\ 방법.txt ]] || fail '배포 zip 런처 권한/문서 누락'
ln -s ../unpacked/routine-automation-0.1.1/routine\ 설치.command "$sandbox/source/런처.command"
ln -s source/런처.command "$sandbox/설치.command"
printf '\n' | "$sandbox/설치.command" "${install_args[@]}" > "$sandbox/packaged-command"
[[ $(cat "$installed/VERSION") == 0.1.1 && $(cat "$installed/install-id") == "$id_before" ]] || fail '배포 zip 런처 비GUI 설치 실패'
# Archived validators are optional, but a stored public consumer must also pass.
mkdir -p "$package_repo/tools/legacy-validators"
cat > "$package_repo/tools/legacy-validators/previous.sh" <<'VALIDATOR'
routine_validate_zip() { ! unzip -Z1 "$1" | grep -q '/unsupported-fixture.txt$'; }
VALIDATOR
printf '이전 소비자가 지원하지 않는 파일\n' > "$package_repo/unsupported-fixture.txt"
git -C "$package_repo" add tools unsupported-fixture.txt
git -C "$package_repo" -c user.name=Fixture -c user.email=fixture@example.com commit -qm '이전 공개 검증기 fixture'
if "$package_repo/bin/routine" package > "$sandbox/incompatible-package" 2>&1; then fail '보관된 이전 검증기가 거부하는 ZIP 생성'; fi
[[ ! -e $package_repo/dist/routine-automation-0.1.1.zip ]] || fail '호환성 실패한 ZIP 배포 가능 상태로 남음'
rm "$package_repo/unsupported-fixture.txt"
git -C "$package_repo" add -u
git -C "$package_repo" -c user.name=Fixture -c user.email=fixture@example.com commit -qm '이전 공개 소비자 호환 fixture'
"$package_repo/bin/routine" package > "$sandbox/compatible-package"
# shellcheck source=release-scenarios.sh
source "$repo/tests/release-scenarios.sh"
printf 'PASS: 실제 ZIP 경계·한국어 이름·검증 후보 선택·설정 경로 보존·SIGKILL 복구·실행 잠금·런처 링크·공개 Release\n'
