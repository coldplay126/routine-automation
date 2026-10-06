#!/usr/bin/env bash
# shellcheck disable=SC2154 # share_dir is supplied by the entrypoint.
# shellcheck source=releases.sh
source "$share_dir/releases.sh"
routine_version_valid() { [[ $1 =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; }
routine_version_newer() {
  command jq -ne --arg new "$1" --arg old "$2" '($new|split(".")|map(tonumber)) > ($old|split(".")|map(tonumber))' >/dev/null
}
routine_terminal_text() {
  command jq -nr --arg text "$1" '$text|gsub("[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]";"")'
}
routine_zip_reject() {
  local path
  path=$(routine_terminal_text "$1")
  printf 'zip 거부: %s — %s\n' "$(routine_terminal_text "$2")" "$path" >&2
}
# The listing is used only for path safety and size/count bounds. macOS unzip
# loses non-ASCII filename bytes, so identities/required files come from the tree.
routine_validate_zip() (
  local zip=$1 destination=${2:-} entries metadata stats attributes archive_root actual_files actual_dirs member version non_regular license license_line
  [[ -f $zip && ! -L $zip ]] || { routine_zip_reject "$zip" '일반 zip 파일이 아닙니다'; return 1; }
  entries=$(unzip -Z1 "$zip" 2>/dev/null) || { routine_zip_reject "$zip" '목록 읽기 실패'; return 1; }
  command jq -Rse 'split("\n")|map(select(length>0))|
    length>0 and all(.[]; (startswith("/")|not) and
      (test("[\\\\:^\u0000-\u001f\u007f]")|not) and
      (split("/")|.[0:-1]|all(.[];.!="" and .!="." and .!="..")) and
      (split("/")|last|.!="." and .!=".."))' <<< "$entries" >/dev/null || {
    routine_zip_reject "$zip" '절대경로·상위 경로·빈 경로 또는 제어문자'; return 1;
  }
  metadata=$(unzip -Z -l "$zip" 2>/dev/null) || { routine_zip_reject "$zip" '속성 읽기 실패'; return 1; }
  stats=$(command jq -Rsc '
    split("\n")|map(select(test("^[^ ]+ +[0-9]+\\.[0-9]+ +[^ ]+ +")) |
      . as $line | capture("^(?<mode>[^ ]+) +[0-9]+\\.[0-9]+ +(?<origin>[^ ]+) +(?<size>[0-9]+) +") |
      .size|=tonumber | .type=(if .mode[0:1]=="l" then "l"
        elif .origin=="fat" then (if $line|endswith("/") then "d" else "-" end)
        else .mode[0:1] end) | .version=($line|test("(^|/)VERSION$";"i"))) |
    {count:length,files:([.[]|select(.type=="-")]|length),dirs:([.[]|select(.type=="d")]|length),
     bytes:([.[].size]|add//0),safe:all(.[];.type=="-" or .type=="d"),
     version_size_ok:all(.[]|select(.version);.size<=32)}' <<< "$metadata") || {
    routine_zip_reject "$zip" '속성 해석 실패'; return 1;
  }
  command jq -e --argjson count "$(command jq -Rsr 'split("\n")|map(select(length>0))|length' <<< "$entries")" \
    '.count==$count and .safe' <<< "$stats" >/dev/null || { routine_zip_reject "$zip" '지원하지 않는 파일 항목'; return 1; }
  command jq -e '.bytes<=67108864 and .version_size_ok' <<< "$stats" >/dev/null || {
    routine_zip_reject "$zip" 'VERSION은 32바이트, 압축 해제 총량은 64MiB 이하여야 합니다'; return 1;
  }
  # FAT/NTFS listings can hide S_IFLNK behind a regular-file-looking row. Inspect
  # the raw type bits as well, before ditto can follow a link during extraction.
  attributes=$(unzip -Z -v "$zip" 2>/dev/null) || return 1
  command jq -Rse --argjson count "$(command jq -r .count <<< "$stats")" '
    split("\n")|map(
      if test("^  Unix file attributes \\([0-7]+ octal\\):") then
        (capture("\\((?<mode>[0-7]+) octal\\)").mode|tonumber/10000|floor) as $type|
        ($type==0 or $type==4 or $type==10)
      elif test("^  non-MSDOS external file attributes: +[0-9a-fA-F]+ hex$") then
        capture(": +(?<hex>[0-9a-fA-F]+) hex$").hex|
        ("000000"+.)[-6:]|.[0:1]|test("^[048]$")
      else empty end) | length==$count and all(.[];.)' <<< "$attributes" >/dev/null || {
    routine_zip_reject "$zip" '심볼릭 링크 또는 비정규 외부 속성'; return 1;
  }
  unzip -tq "$zip" >/dev/null 2>&1 || { routine_zip_reject "$zip" '무결성 검사 실패'; return 1; }
  if [[ -z $destination ]]; then
    destination=$(mktemp -d "${TMPDIR:-/tmp}/routine-update.XXXXXXXX") || return 1
    trap 'rm -rf -- "$destination"' EXIT
  fi
  chmod 700 "$destination" || return 1
  ditto -x -k "$zip" "$destination" >/dev/null 2>&1 || { routine_zip_reject "$zip" '압축 해제 실패'; return 1; }
  non_regular=$(find "$destination" -mindepth 1 ! -type f ! -type d -print 2>/dev/null) || return 1
  [[ -z $non_regular ]] || { routine_zip_reject "$zip" '심볼릭 링크 또는 비정규 파일'; return 1; }
  archive_root=$(find "$destination" -mindepth 1 -maxdepth 1 -print0 | command jq -Rser \
    'split("\u0000")|map(select(length>0))|select(length==1)|.[0]') || {
    routine_zip_reject "$zip" '실제 트리는 단일 최상위 폴더여야 합니다'; return 1;
  }
  [[ -d $archive_root ]] || { routine_zip_reject "$zip" '최상위 항목은 폴더여야 합니다'; return 1; }
  find "$destination" -mindepth 1 -print0 | iconv -f UTF-8 -t UTF-8-MAC | \
    LC_ALL=en_US.UTF-8 tr '[:upper:]' '[:lower:]' | command jq -Rse '
      split("\u0000")|map(select(length>0))|. as $paths|
      length==(unique|length) and all($paths[];(test("[\u0000-\u001f\u007f]")|not))' >/dev/null || {
    routine_zip_reject "$zip" '실제 트리의 대소문자·정규화 중복 또는 잘못된 이름'; return 1;
  }
  actual_files=$(find "$destination" -type f -print0 | command jq -Rsr 'split("\u0000")|map(select(length>0))|length') || return 1
  actual_dirs=$(find "$destination" -mindepth 1 -type d -print0 | command jq -Rsr 'split("\u0000")|map(select(length>0))|length') || return 1
  command jq -e --argjson files "$actual_files" --argjson dirs "$actual_dirs" \
    '.files==$files and .dirs<=$dirs' <<< "$stats" >/dev/null || {
    routine_zip_reject "$zip" '압축 해제 중 중복 항목이 덮어써졌습니다'; return 1;
  }
  for member in VERSION install.sh bin/routine; do
    [[ -f $archive_root/$member && ! -L $archive_root/$member ]] || { routine_zip_reject "$zip" "필수 일반 파일 누락: $member"; return 1; }
  done
  license=$(find "$archive_root" -mindepth 1 -maxdepth 1 -name LICENSE -type f -print -quit)
  [[ -n $license && -s $license && ! -L $license ]] || {
    routine_zip_reject "$zip" '공개 빌드가 아닌 개발판 zip — 정확한 루트 LICENSE 누락 또는 비어 있음'; return 1;
  }
  IFS= read -r license_line < "$license" || [[ -n $license_line ]]
  [[ $license_line == 'MIT License' ]] || { routine_zip_reject "$zip" '루트 LICENSE 첫 줄은 MIT License여야 합니다'; return 1; }
  [[ $(stat -f %z "$archive_root/VERSION") -le 32 ]] || { routine_zip_reject "$zip" 'VERSION 32바이트 초과'; return 1; }
  version=$(<"$archive_root/VERSION")
  routine_version_valid "$version" || { routine_zip_reject "$zip" 'VERSION 형식 오류'; return 1; }
  printf '%s\n' "${archive_root##*/}"
)
routine_zip_version() (
  local zip=$1 directory archive_root version
  directory=$(mktemp -d "${TMPDIR:-/tmp}/routine-update.XXXXXXXX") || return 1
  trap 'rm -rf -- "$directory"' EXIT
  archive_root=$(routine_validate_zip "$zip" "$directory") || return 1
  version=$(<"$directory/$archive_root/VERSION")
  printf '%s\n' "$version"
)
routine_cached_zip_version() (
  local zip=$1 directory=$2 key stamp cache cached temporary version='' reason=''
  stamp=$(stat -f '%z:%.9Fm:%.9Fc:%i' "$zip") || return 1
  key=$(printf '%s' "$zip" | shasum -a 256); key=${key%% *}
  cache="$directory/$key.json"
  [[ ! -L $cache ]] || return 1
  cached=$(command jq -ce --arg path "$zip" --arg stamp "$stamp" \
    'select(.path==$path and .stamp==$stamp and (.version|type)=="string" and (.reason|type)=="string")' "$cache" 2>/dev/null) || cached=''
  if [[ -n $cached ]]; then
    version=$(command jq -r .version <<< "$cached")
    if routine_version_valid "$version"; then printf '%s\n' "$version"; return 0; fi
    printf '%s\n' "$(command jq -r .reason <<< "$cached")" >&2
    return 1
  fi
  temporary=$(mktemp "${TMPDIR:-/tmp}/.downloads.XXXXXXXX") || return 1
  trap 'rm -f -- "$temporary" "$temporary.reason"' EXIT
  version=$(routine_zip_version "$zip" 2>"$temporary.reason") || { version=''; reason=$(<"$temporary.reason"); }
  command jq -n --arg path "$zip" --arg stamp "$stamp" --arg version "$version" --arg reason "$reason" \
    '{path:$path,stamp:$stamp,version:$version,reason:$reason}' > "$temporary" &&
    chmod 600 "$temporary" && mv -f "$temporary" "$cache" || return 1
  if routine_version_valid "$version"; then printf '%s\n' "$version"; return 0; fi
  printf '%s\n' "$reason" >&2
  return 1
)
routine_find_update_cached() {
  local downloads=$1 directory=$2 zip version selected='' newest=''
  for zip in "$downloads"/routine-automation-*.zip; do
    [[ -e $zip || -L $zip ]] || continue
    version=$(routine_cached_zip_version "$zip" "$directory") || continue
    if [[ -z $newest ]] || routine_version_newer "$version" "$newest"; then selected=$zip newest=$version; fi
  done
  command jq -n --arg zip "$selected" '{zip:$zip}'
}
routine_find_update() {
  local limit selected status=0 downloads=${ROUTINE_DOWNLOADS_DIR:-$HOME/Downloads}
  local directory="$HOME/Library/Caches/routine-automation/downloads" temporary
  ROUTINE_UPDATE_ZIP=''
  limit=$(command -v gtimeout || command -v timeout || true)
  [[ -n $limit ]] || { echo 'Downloads 탐색에는 gtimeout 또는 timeout이 필요합니다. ZIP 경로를 직접 지정하세요.' >&2; return 1; }
  [[ ! -L ${directory%/*} && ! -L $directory ]] || return 1
  mkdir -p "$directory" && chmod 700 "${directory%/*}" "$directory" || return 1
  temporary=$(mktemp -d "$directory/.scan.XXXXXXXX") || return 1
  # The parent owns this whole scratch tree, even when timeout kills child traps.
  # shellcheck disable=SC2016 # The child receives the actual library and folders.
  selected=$(TMPDIR="$temporary" "$limit" -k 1 15 /bin/bash -c 'share_dir=$1; source "$share_dir/update.sh"; routine_find_update_cached "$2" "$3"' _ "$share_dir" "$downloads" "$directory") || status=$?
  rm -rf -- "$temporary"
  if ((status)); then echo 'Downloads 검증 실패 또는 전체 탐색 시간 상한(15초) 초과 — 설치하지 않습니다.' >&2; return 1; fi
  ROUTINE_UPDATE_ZIP=$(command jq -r .zip <<< "$selected")
}
routine_downloads_provenance() {
  local zip=$1 digest quarantine origins
  digest=$(shasum -a 256 "$zip"); digest=${digest%% *}
  quarantine=$(xattr -p com.apple.quarantine "$zip" 2>/dev/null) || quarantine='없음'
  origins=$(mdls -raw -name kMDItemWhereFroms "$zip" 2>/dev/null) || origins='조회 실패'
  printf 'Downloads ZIP — 출처 미검증\n경로: %s\nsha256: %s\nquarantine: %s\nkMDItemWhereFroms: %s\n' \
    "$(routine_terminal_text "$zip")" "$digest" "$(routine_terminal_text "$quarantine")" "$(routine_terminal_text "$origins")"
}
routine_update_notice() (
  local current day repository cache directory cached version='' release temporary
  [[ -f $share_dir/../VERSION ]] || return 0
  current=$(<"$share_dir/../VERSION")
  routine_version_valid "$current" || return 0
  day=$(routine_day) || return 0
  repository=$(routine_release_repository) || return 0
  directory="$HOME/Library/Caches/routine-automation"
  cache="$directory/releases.json"
  [[ ! -L $directory && ! -L $cache ]] || return 0
  mkdir -p "$directory" && chmod 700 "$directory" || return 0
  cached=$(command jq -ce --arg day "$day" --arg repo "$repository" \
    'select(.day==$day and .repository==$repo and (.version|type)=="string")' "$cache" 2>/dev/null) || cached=''
  if [[ -n $cached ]]; then
    version=$(command jq -r .version <<< "$cached")
  else
    if release=$(routine_release_query 5 2>/dev/null); then version=$(command jq -r .version <<< "$release"); fi
    temporary=$(mktemp "$directory/.releases.XXXXXXXX") || return 0
    trap 'rm -f -- "$temporary"' EXIT
    command jq -n --arg day "$day" --arg repo "$repository" --arg version "$version" \
      '{day:$day,repository:$repo,version:$version}' > "$temporary" &&
      chmod 600 "$temporary" && mv -f "$temporary" "$cache" || return 0
  fi
  if routine_version_valid "$version" && routine_version_newer "$version" "$current"; then
    printf '새 버전 %s — routine update\n' "$version"
  fi
  return 0
)
routine_show_changes() {
  local file=$1 current=$2 next=$3
  [[ -f $file ]] || { echo '변경 내역: 이 zip에는 CHANGELOG.md가 없습니다.'; return 0; }
  command jq -Rnr --arg current "$current" --arg next "$next" '
    def version: split(".")|map(tonumber);
    reduce inputs as $raw ({show:false,lines:[]};
      ($raw|gsub("[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]";"")) as $line |
      if ($line|test("^## [0-9]+\\.[0-9]+\\.[0-9]+($| — )")) then
        ($line|capture("^## (?<v>[0-9]+\\.[0-9]+\\.[0-9]+)").v|version) as $v |
        .show=($v>($current|version) and $v<=($next|version)) |
        if .show then .lines+=[$line] else . end
      elif .show then .lines+=[$line] else . end) | .lines[]' < "$file"
}
routine_package_verify() (
  local repository=$1 package_zip=$2 validator
  routine_validate_zip "$package_zip" >/dev/null || return 1
  for validator in "$repository"/tools/legacy-validators/*.sh; do
    [[ -e $validator ]] || continue
    [[ -f $validator && ! -L $validator ]] || { echo '이전 공개 버전 검증기는 일반 파일이어야 합니다.' >&2; return 1; }
    # shellcheck disable=SC2016 # Archived validators run only in this child.
    /bin/bash -c 'share_dir=$3; source "$1"; routine_validate_zip "$2" >/dev/null' _ "$validator" "$package_zip" "$repository/share" || {
      printf '이전 공개 버전 검증기가 이 zip을 거부합니다: %s\n' "${validator##*/}" >&2; return 1;
    }
  done
  echo 'zip 자기 검증: 현재·보관된 이전 공개 버전 검증기 통과'
)
routine_update() (
  local zip='' check=0 yes=0 current next archive_root temporary='' pending=0 from=auto release expected='' github_directory='' status reason downloads_source=0 downloads_root folder
  trap '[[ -z $temporary ]] || rm -rf -- "$temporary"; [[ -z $github_directory ]] || rm -rf -- "$github_directory"' EXIT
  while (($#)); do
    case $1 in
      --check) check=1 ;;
      --yes) yes=1 ;;
      --from) shift; from=${1:-}; [[ $from == downloads || $from == github ]] || { echo '--from github|downloads' >&2; return 2; } ;;
      -h|--help) echo 'routine update [ZIP경로] [--check] [--yes] [--from github|downloads] — 공개 Release 또는 Downloads zip으로 설정 보존 업데이트'; return 0 ;;
      --*) echo 'routine update [ZIP경로] [--check] [--yes] [--from github|downloads]' >&2; return 2 ;;
      *) [[ -z $zip ]] || { echo 'zip 경로는 하나만 지정하세요.' >&2; return 2; }; zip=$1 ;;
    esac
    shift
  done
  [[ -z $zip || $from == auto ]] || { echo 'ZIP경로와 --from은 함께 지정하지 마세요.' >&2; return 2; }
  routine_jq_supported || { echo '업데이트에는 jq 1.7 이상이 필요합니다. 새 패키지의 routine 설치.command로 의존성을 준비하세요.' >&2; return 1; }
  # shellcheck source=share/install.sh
  source "$share_dir/install.sh"
  routine_install_paths
  if [[ -f $manifest || -f $installed_root.previous/manifest.json ]]; then routine_use_install_config || return 1; fi
  routine_installation_pending && pending=1
  if ((pending)); then
    echo '⚠ 미완료 설치가 있습니다. 버전 비교만으로 최신 상태를 확정할 수 없습니다.'
    if ((!check && !yes)); then
      echo '복구하려면 routine update --yes를 실행하세요. 기존 설치·설정 변경 없음'
      return 0
    fi
    if ((check)); then echo '복구: routine update --yes (또는 새 패키지의 install.sh --update)'; fi
  fi
  if [[ -z $zip ]]; then
    if [[ $from != downloads ]]; then
      github_directory=$(mktemp -d "${TMPDIR:-/tmp}/routine-github-update.XXXXXXXX") || return 1
      status=0
      release=$(routine_release_query 15 2>"$github_directory/reason") || status=$?
      if ((status==0)); then
        expected=$(command jq -r .version <<< "$release")
        zip="$github_directory/routine-automation-$expected.zip"
        routine_release_download "$release" "$zip" 2>"$github_directory/reason" || status=$?
      fi
      if ((status!=0)); then
        reason=$(routine_terminal_text "$(<"$github_directory/reason")")
        printf '%s\n' "$reason" >&2
        echo '자동 Downloads 대체는 하지 않습니다. routine update --from downloads 또는 신뢰한 ZIP을 풀어 install.sh --update를 실행하세요.' >&2
        return 1
      else printf '출처: GitHub 공개 Release v%s\n' "$expected"; fi
    fi
    if [[ -z $zip ]]; then
      routine_find_update || return 1
      zip=$ROUTINE_UPDATE_ZIP
      [[ -n $zip ]] || { echo '검증을 통과한 업데이트 zip이 없습니다. 새 zip을 Downloads에 두거나 경로를 지정하세요.'; return 0; }
    fi
  fi
  [[ -f $zip && ! -L $zip ]] || { routine_zip_reject "$zip" '일반 zip 파일 경로를 지정하세요'; return 1; }
  zip=$(CDPATH='' cd -P -- "$(dirname -- "$zip")" >/dev/null && printf '%s/%s\n' "$PWD" "${zip##*/}") || return 1
  if [[ $from == downloads ]]; then downloads_source=1; fi
  if [[ -z $expected ]]; then
    for folder in "${ROUTINE_DOWNLOADS_DIR:-$HOME/Downloads}" "$HOME/Downloads"; do
      downloads_root=$(CDPATH='' cd -P -- "$folder" 2>/dev/null && pwd) || continue
      [[ $zip != "$downloads_root/"* ]] || downloads_source=1
    done
  fi
  if ((downloads_source)); then routine_downloads_provenance "$zip"; fi
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/routine-update.XXXXXXXX") || return 1
  archive_root=$(routine_validate_zip "$zip" "$temporary") || return 1
  next=$(<"$temporary/$archive_root/VERSION")
  [[ -z $expected || $next == "$expected" ]] || { echo 'GitHub Release 태그와 zip VERSION 불일치 — 설치 거부' >&2; return 1; }
  [[ -f $share_dir/../VERSION ]] || { echo '현재 설치 VERSION이 없습니다.' >&2; return 1; }
  current=$(<"$share_dir/../VERSION")
  routine_version_valid "$current" || { echo '현재 설치 VERSION 오류' >&2; return 1; }
  printf '✓ zip 검증\n%s → %s\n' "$current" "$next"
  if ((pending && check)); then echo '확인만 완료 — 미완료 설치 복구는 아직 실행하지 않았습니다'; return 0; fi
  if ((!pending)) && ! routine_version_newer "$next" "$current"; then
    echo '이미 최신입니다. 같은 버전 또는 낮은 버전은 설치하지 않습니다.'
    if [[ $next != "$current" ]]; then echo '롤백은 docs/install.md의 제거 후 이전 패키지 설치 절차를 따르세요.'; fi
    return 0
  fi
  echo '✓ 새 버전 확인'
  routine_show_changes "$temporary/$archive_root/CHANGELOG.md" "$current" "$next"
  (( !check )) || { echo '확인만 완료 — 설치본·설정 변경 없음'; return 0; }
  # shellcheck source=ui.sh
  source "$share_dir/ui.sh"
  if ((downloads_source)); then
    if [[ ! -t 0 || ! -t 1 ]]; then echo 'Downloads 설치는 --yes여도 TTY 확인이 필수입니다. 터미널에서 routine update --from downloads를 실행하세요. 변경 없음' >&2; return 1; fi
    ui_confirm "출처 미검증 Downloads ZIP을 신뢰하고 $next 버전으로 업데이트할까요?" false || { echo '업데이트 취소 — 기존 설치 유지'; return 0; }
  elif ((!yes)); then
    if [[ ! -t 0 || ! -t 1 ]]; then echo '설치하려면 터미널에서 routine update 또는 --yes를 사용하세요. 변경 없음'; return 0; fi
    ui_confirm "$next 버전으로 업데이트할까요?" || { echo '업데이트 취소 — 기존 설치 유지'; return 0; }
  fi
  if ((pending)); then
    routine_installation_idle || return 1
    routine_recover_installation || return 1
    if routine_installation_pending; then echo '소유 확인되지 않은 복구 기록을 보존했습니다. 새 패키지의 설치 도구로 확인하세요.' >&2; return 1; fi
    current=$(<"$share_dir/../VERSION")
    if ! routine_version_newer "$next" "$current"; then echo '중단 설치 복구 완료 — 이미 최신입니다.'; return 0; fi
  fi
  routine_installation_idle || return 1
  export ROUTINE_UPDATE_ZIP_PATH="$zip"
  ui_spin '파일 교체·예약 실행 갱신 중' /bin/bash "$temporary/$archive_root/install.sh" --update || return
  ui_output "$(ui_color success '✓') ${next}으로 업데이트"
  if [[ -n $expected ]]; then echo 'GitHub 다운로드 임시 zip은 종료 시 정리합니다.'
  else printf '사용한 zip (그대로 보관): %s\n' "$zip"; fi
)
