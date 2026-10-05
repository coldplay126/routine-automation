#!/usr/bin/env bash
routine_install_paths() {
  installed_root="$HOME/.local/share/routine-automation"
  bin_dir=${ROUTINE_BIN_DIR:-$HOME/.local/bin}
  agent_dir=${ROUTINE_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}
  copy_app="${ROUTINE_USER_APPLICATIONS_DIR:-$HOME/Applications}/스크럼 초안 복사.app"
  review_app="${ROUTINE_USER_APPLICATIONS_DIR:-$HOME/Applications}/스크럼 초안 검토.app"
  manifest="$installed_root/manifest.json"
}
routine_installation_pending() {
  local transaction
  [[ ! -e $installed_root.previous && ! -L $installed_root.previous ]] || return 0
  for transaction in "${installed_root%/*}"/.routine-transaction.*; do
    [[ ! -e $transaction && ! -L $transaction ]] || return 0
  done
  return 1
}
routine_installation_idle() {
  local lock owner modified
  for lock in "$HOME/Library/Logs/routine-automation/.morning.lock" "$HOME/Library/Application Support/routine-automation/scrum/.scrum-paste.lock"; do
    [[ -d $lock ]] || continue
    owner=$(cat "$lock/pid" 2>/dev/null || true)
    modified=$(stat -f %m "$lock" 2>/dev/null || date +%s)
    if { [[ $owner =~ ^[0-9]+$ ]] && kill -0 "$owner" 2>/dev/null; } ||
       { [[ -z $owner ]] && (($(date +%s)-modified<10)); }; then
      echo '아침 루틴 또는 스크럼 붙여넣기 실행 중 — 작업 종료 후 업데이트하세요.' >&2
      return 1
    fi
  done
}
routine_use_install_config() {
  local storage=$installed_root stored
  [[ -f $storage/manifest.json ]] || storage="$installed_root.previous"
  routine_verify_ownership '' "$storage" 1 || return 1
  stored=$(jq -er '.configuration_path|select(type=="string" and length>0)' "$storage/manifest.json") || {
    echo '설치 기록의 설정 경로가 없습니다. 새 패키지의 설치 런처로 설정을 확인하세요.' >&2; return 1;
  }
  if [[ -n ${ROUTINE_CONFIG:-} && $(routine_config_path) != "$stored" ]]; then
    printf '설정 경로가 설치 기록과 다릅니다. 기존 설정 경로를 명시해 다시 실행하세요.\nROUTINE_CONFIG=%q\n' "$stored" >&2
    return 1
  fi
  export ROUTINE_CONFIG="$stored"
}
routine_allowed_path() {
  [[ $1 != *'/../'* && $1 != */.. && $1 != *'/./'* ]] || return 1
  case $1 in "$installed_root/"*|"$bin_dir/routine"|"$agent_dir/"*.plist|"$copy_app/"*|"$review_app/"*) return 0 ;; *) return 1 ;; esac
}
routine_verify_ownership() {
  local id=${1:-} storage=${2:-$installed_root} root_only=${3:-0} entry path actual_path hash target actual app
  local manifest=${4:-$storage/manifest.json}
  [[ -d $storage && ! -L $storage && -f $manifest && ! -L $manifest ]] || { echo '소유하지 않은 설치 루트/manifest' >&2; return 1; }
  if [[ -z $id ]]; then
    [[ -f $storage/install-id && ! -L $storage/install-id ]] || return 1
    id=$(<"$storage/install-id")
  fi
  if [[ ! $id =~ ^[A-Za-z0-9-]+$ ]] || ! jq -e --arg id "$id" '.install_id==$id and (.files|type=="array") and (.links|type=="array")' "$manifest" >/dev/null; then echo '설치 식별자/manifest 불일치' >&2; return 1; fi
  while IFS= read -r entry; do
    path=$(jq -r '.path' <<< "$entry"); hash=$(jq -r '.sha256' <<< "$entry")
    routine_allowed_path "$path" && [[ $hash =~ ^[a-f0-9]{64}$ ]] || return 1
    actual_path=$path
    if [[ $path == "$installed_root/"* ]]; then actual_path="$storage/${path#"$installed_root/"}"
    elif ((root_only)); then continue; fi
    [[ -e $actual_path || -L $actual_path ]] || continue
    [[ -f $actual_path && ! -L $actual_path ]] || { echo "소유 검증 실패: $path" >&2; return 1; }
    actual=$(shasum -a 256 "$actual_path"); actual=${actual%% *}
    [[ $actual == "$hash" ]] || { echo "관리 파일이 변경되어 거부: $path" >&2; return 1; }
  done < <(jq -c '.files[]' "$manifest")
  while IFS= read -r entry; do
    path=$(jq -r '.path' <<< "$entry"); target=$(jq -r '.target' <<< "$entry")
    [[ $path == "$bin_dir/routine" && $target == "$installed_root/bin/routine" ]] || return 1
    if ((root_only)); then continue; fi
    [[ -e $path || -L $path ]] || continue
    [[ -L $path && $(readlink "$path") == "$target" ]] || { echo "링크 소유 검증 실패: $path" >&2; return 1; }
  done < <(jq -c '.links[]' "$manifest")
  while IFS= read -r actual_path; do
    case $actual_path in "$storage/manifest.json"|"$storage/install-id") continue ;; esac
    path="$installed_root/${actual_path#"$storage/"}"
    jq -e --arg path "$path" 'any(.files[];.path==$path)' "$manifest" >/dev/null || { echo "소유하지 않은 파일: $path" >&2; return 1; }
  done < <(find "$storage" -type f -o -type l)
  for app in "$copy_app" "$review_app"; do
    if ((!root_only)) && [[ -e $app || -L $app ]]; then
      [[ -d $app && ! -L $app ]] || return 1
      while IFS= read -r path; do
        jq -e --arg path "$path" 'any(.files[];.path==$path)' "$manifest" >/dev/null || { echo "소유하지 않은 앱 파일: $path" >&2; return 1; }
      done < <(find "$app" -type f -o -type l)
    fi
  done
}
routine_record_file() {
  local hash path=${2:-$1}
  hash=$(shasum -a 256 "$1"); hash=${hash%% *}
  jq -nc --arg path "$path" --arg sha256 "$hash" '{path:$path,sha256:$sha256}' >> "$records"
}
routine_legacy_migrate() {
  local entry name path program records candidate id
  [[ -f $installed_root/.source-repo && -f $installed_root/.files && ! -L $installed_root/.source-repo && ! -L $installed_root/.files && ! -e $manifest ]] || return 1
  records=$(mktemp "${TMPDIR:-/tmp}/routine-legacy.XXXXXXXX")
  candidate=$(mktemp "${TMPDIR:-/tmp}/routine-legacy-manifest.XXXXXXXX")
  while IFS= read -r entry; do
    name=${entry#*/}; [[ -n $name && $name != */* && $name != . && $name != .. ]] || { rm -f "$records" "$candidate"; return 1; }
    case $entry in
      bin/*|share/*)
        path="$installed_root/$entry"
        [[ -e $path || -L $path ]] || continue
        [[ -f $path && ! -L $path ]] || { rm -f "$records" "$candidate"; return 1; }
        routine_record_file "$path" ;;
      launchd/*.plist)
        path="$agent_dir/$name"
        [[ -e $path || -L $path ]] || continue
        [[ -f $path && ! -L $path ]] || { rm -f "$records" "$candidate"; return 1; }
        program=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$path" 2>/dev/null || true)
        [[ $program == "$installed_root/bin/morning" || $program == "$installed_root/bin/scrum-paste" ]] || { rm -f "$records" "$candidate"; return 1; }
        routine_record_file "$path" ;;
      *) rm -f "$records" "$candidate"; return 1 ;;
    esac
  done < "$installed_root/.files"
  routine_record_file "$installed_root/.source-repo"; routine_record_file "$installed_root/.files"
  id=$(uuidgen)
  jq -s --arg id "$id" '{install_id:$id,files:.,links:[]}' "$records" > "$candidate"
  if ! routine_verify_ownership "$id" "$installed_root" 0 "$candidate"; then rm -f "$records" "$candidate"; return 1; fi
  printf '%s\n' "$id" > "$installed_root/install-id"
  mv "$candidate" "$manifest"; chmod 600 "$manifest" "$installed_root/install-id"
  rm -f "$records"
  # Legacy metadata stays tracked until the verified installation is replaced or removed.
}
routine_plist_label() {
  local label=${1##*/}
  label=${label%.plist}
  [[ $label =~ ^[A-Za-z0-9][A-Za-z0-9._-]+$ ]] || return 1
  printf '%s\n' "$label"
}
routine_receipt_file_matches() {
  local receipt=$1 section=$2 logical=$3 actual=$4 hash
  [[ -f $actual && ! -L $actual ]] || return 1
  hash=$(shasum -a 256 "$actual"); hash=${hash%% *}
  jq -e --arg section "$section" --arg path "$logical" --arg hash "$hash" \
    '(if $section=="either" then [.before,.after] else [.[$section]] end)|any(.[]?.files[]?;.path==$path and .sha256==$hash)' "$receipt" >/dev/null
}
routine_verify_transaction() {
  local transaction=$1 receipt="$1/receipt.json" id stage row path saved rel logical section hash app
  [[ -d $transaction && ! -L $transaction && -f $receipt && ! -L $receipt ]] || return 1
  jq -e --arg root "$installed_root" '.root==$root and (.install_id|type=="string" and test("^[A-Za-z0-9-]+$")) and (.owner_pid|type=="number" and .>0 and .==floor) and (.after.install_id==.install_id) and (.before==null or .before.install_id==.install_id)' "$receipt" >/dev/null || return 1
  if [[ -f $transaction/committed ]]; then
    [[ -f $manifest ]] && jq -e --slurpfile receipt "$receipt" '.==$receipt[0].after' "$manifest" >/dev/null || return 1
  fi
  id=$(jq -r '.install_id' "$receipt"); stage=$(jq -r '.stage' "$receipt")
  [[ ${stage%/*} == "${installed_root%/*}" && ${stage##*/} =~ ^\.routine-install\.[A-Za-z0-9]+$ && ! -L $stage ]] || return 1
  while IFS= read -r row; do
    path=$(jq -r '.path' <<< "$row"); hash=$(jq -r '.sha256' <<< "$row")
    routine_allowed_path "$path" && [[ $hash =~ ^[a-f0-9]{64}$ ]] || return 1
  done < <(jq -c '.before.files[]?,.after.files[]' "$receipt")
  hash=$(printf '%s\n' "$id" | shasum -a 256); hash=${hash%% *}
  jq -e --arg path "$installed_root/install-id" --arg hash "$hash" 'any(.after.files[];.path==$path and .sha256==$hash)' "$receipt" >/dev/null || return 1
  for path in "$installed_root" "$installed_root.previous" "$stage"; do
    [[ -e $path || -L $path ]] || continue
    routine_verify_ownership "$id" "$path" 1 || return 1
    jq -e --slurpfile receipt "$receipt" '.==$receipt[0].before or .==$receipt[0].after' "$path/manifest.json" >/dev/null || return 1
  done
  for path in "$transaction/backups" "$transaction/created" "$transaction/services" "$transaction/records"; do [[ -f $path && ! -L $path ]] || return 1; done
  jq -se --slurpfile receipt "$receipt" '.==$receipt[0].after.files' "$transaction/records" >/dev/null || return 1
  if [[ -f $transaction/owner.json ]]; then
    jq -e --slurpfile receipt "$receipt" '. as $owner|all(["install_id","root","stage","owner_pid","link_before"][];. as $key|$owner[$key]==$receipt[0][$key])' "$transaction/owner.json" >/dev/null || return 1
  fi
  while IFS= read -r row; do
    path=$(jq -r '.path' <<< "$row"); saved=$(jq -r '.backup' <<< "$row")
    [[ $path == "$agent_dir/"*.plist && ${saved%/*} == "$transaction" && ${saved##*/} =~ ^old-agent-[0-9]+\.plist$ ]] || return 1
    jq -e --arg path "$path" 'any(.before.files[]?;.path==$path)' "$receipt" >/dev/null || return 1
  done < "$transaction/backups"
  while IFS= read -r row; do
    path=$(jq -r '.path' <<< "$row")
    [[ $path == "$agent_dir/"*.plist ]] && jq -e --arg path "$path" 'any(.after.files[];.path==$path)' "$receipt" >/dev/null || return 1
  done < "$transaction/created"
  while IFS= read -r row; do
    path=$(jq -r '.path' <<< "$row")
    [[ $path == "$agent_dir/"*.plist && $(jq -r '.label' <<< "$row") == "$(routine_plist_label "$path")" ]] || return 1
    jq -e '.loaded==true' <<< "$row" >/dev/null && jq -e --arg path "$path" 'any(.before.files[]?;.path==$path)' "$receipt" >/dev/null || return 1
  done < "$transaction/services"
  if [[ -e $bin_dir/routine || -L $bin_dir/routine ]]; then
    [[ -L $bin_dir/routine ]] || return 1
    saved=$(readlink "$bin_dir/routine")
    [[ $saved == "$installed_root/bin/routine" || $saved == "$(jq -r '.link_before' "$receipt")" ]] || return 1
  fi
  while IFS= read -r path; do
    [[ ! -e $path && ! -L $path ]] || routine_receipt_file_matches "$receipt" either "$path" "$path" || return 1
  done < <(jq -r --arg prefix "$agent_dir/" '[.before.files[]?,.after.files[]]|map(.path)|unique[]|select(startswith($prefix))' "$receipt")
  for app in "$copy_app" "$review_app"; do
    if [[ -e $app || -L $app ]]; then
      [[ -d $app && ! -L $app ]] || return 1
      while IFS= read -r path; do routine_receipt_file_matches "$receipt" either "$path" "$path" || return 1; done < <(find "$app" -type f -o -type l)
    fi
  done
  while IFS= read -r path; do
    rel=${path#"$transaction/"}; section=''; logical=''
    case $rel in
      receipt.json|owner.json|backups|created|services|records) [[ -f $path && ! -L $path ]] || return 1; continue ;;
      committed) [[ -f $path && ! -L $path && ! -s $path ]] || return 1; continue ;;
      old-link) [[ -L $path && $(readlink "$path") == "$(jq -r '.link_before' "$receipt")" ]] || return 1; continue ;;
      routine-link) [[ -L $path && $(readlink "$path") == "$installed_root/bin/routine" ]] || return 1; continue ;;
      old-copy.app/*) section=before; logical="$copy_app/${rel#old-copy.app/}" ;;
      new-copy.app/*) section=after; logical="$copy_app/${rel#new-copy.app/}" ;;
      old-review.app/*) section=before; logical="$review_app/${rel#old-review.app/}" ;;
      new-review.app/*) section=after; logical="$review_app/${rel#new-review.app/}" ;;
      old-agent-*.plist)
        logical=$(jq -sr --arg backup "$path" '.[]|select(.backup==$backup)|.path' "$transaction/backups"); section=before ;;
      new-agent.plist)
        [[ -f $path && ! -L $path ]] || return 1
        hash=$(shasum -a 256 "$path"); hash=${hash%% *}
        jq -e --arg prefix "$agent_dir/" --arg hash "$hash" 'any(.after.files[];(.path|startswith($prefix)) and .sha256==$hash)' "$receipt" >/dev/null || return 1; continue ;;
      *) return 1 ;;
    esac
    routine_receipt_file_matches "$receipt" "$section" "$logical" "$path" || return 1
  done < <(find "$transaction" -type f -o -type l)
}
routine_restore_services() {
  local transaction=$1 row path label candidate
  [[ ${ROUTINE_SKIP_LAUNCHCTL:-0} != 1 ]] || return 0
  while IFS= read -r row; do
    path=$(jq -r '.path' <<< "$row"); label=$(jq -r '.label' <<< "$row")
    launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 && continue
    if [[ ! -f $path ]]; then
      candidate="$installed_root/launchd/${label##*.}.plist"
      if routine_receipt_file_matches "$transaction/receipt.json" before "$path" "$candidate"; then cp "$candidate" "$path" || return 1; fi
    fi
    if [[ ! -f $path ]] || ! launchctl bootstrap "gui/$(id -u)" "$path"; then echo "이전 LaunchAgent 재로드 실패: $label" >&2; return 1; fi
  done < "$transaction/services"
}
# Before restoring a generation, unload any agents from the uncommitted one.
# The receipt's validated paths and hashes remain the ownership boundary.
routine_stop_new_services() {
  local transaction=$1 path label
  [[ ${ROUTINE_SKIP_LAUNCHCTL:-0} != 1 ]] || return 0
  while IFS= read -r path; do
    [[ -f $path ]] || continue
    routine_receipt_file_matches "$transaction/receipt.json" after "$path" "$path" || continue
    label=$(routine_plist_label "$path") || return 1
    if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
      launchctl bootout "gui/$(id -u)/$label" || return 1
    fi
  done < <(jq -r --arg prefix "$agent_dir/" '.after.files[].path|select(startswith($prefix))' "$transaction/receipt.json")
}
routine_recover_installation() {
  local mode=${1:-install} transaction receipt owner stage pid row path saved backup="$installed_root.previous" root_new before
  for transaction in "${installed_root%/*}"/.routine-transaction.*; do
    [[ -d $transaction && ! -L $transaction ]] || continue
    receipt="$transaction/receipt.json"
    owner="$transaction/owner.json"
    if [[ -f $owner && ! -L $owner ]] && jq -e --arg root "$installed_root" '.root==$root and (.owner_pid|type=="number" and .>0 and .==floor)' "$owner" >/dev/null; then
      pid=$(jq -r '.owner_pid' "$owner")
      if kill -0 "$pid" 2>/dev/null; then echo '다른 설치 작업이 진행 중입니다.' >&2; return 1; fi
      stage=$(jq -r '.stage' "$owner")
      if ! jq -e . "$receipt" >/dev/null 2>&1 && [[ ${stage%/*} == "${installed_root%/*}" && ${stage##*/} =~ ^\.routine-install\.[A-Za-z0-9]+$ ]] &&
         [[ -f $stage/manifest.json && ! -s $transaction/backups && ! -s $transaction/created && ! -s $transaction/services ]] &&
         routine_verify_ownership "$(jq -r '.install_id' "$owner")" "$stage" 1; then
        before=null; [[ ! -f $manifest ]] || before=$(jq -c . "$manifest")
        jq --argjson before "$before" --slurpfile after "$stage/manifest.json" '.+{before:$before,after:$after[0]}' "$owner" > "$receipt"
      fi
    fi
    [[ -f $receipt ]] || { echo "소유 미검증 임시 디렉터리 보존: ${transaction##*/}" >&2; continue; }
    if ! routine_verify_transaction "$transaction"; then
      echo "소유 미검증 임시 디렉터리 보존: ${transaction##*/}" >&2
      if [[ ! -L $receipt ]] && jq -e --arg root "$installed_root" '.root==$root' "$receipt" >/dev/null 2>&1; then return 1; fi
      continue
    fi
    pid=$(jq -r '.owner_pid' "$receipt")
    if kill -0 "$pid" 2>/dev/null; then echo '다른 설치 작업이 진행 중입니다.' >&2; return 1; fi
    stage=$(jq -r '.stage' "$receipt"); root_new=0
    if [[ -f $manifest ]] && jq -e --slurpfile receipt "$receipt" '.==$receipt[0].after' "$manifest" >/dev/null; then
      if [[ -d $backup ]] || jq -e '.before==null' "$receipt" >/dev/null; then root_new=1; fi
    fi
    if [[ ! -f $transaction/committed ]]; then
      if ((root_new)); then
        routine_stop_new_services "$transaction" || return 1
        while IFS= read -r row; do path=$(jq -r '.path' <<< "$row"); rm -f "$path"; done < "$transaction/created"
        rm -rf "$installed_root"
        [[ ! -d $backup ]] || mv "$backup" "$installed_root"
        [[ ! -d $copy_app ]] || rm -rf "$copy_app"
        [[ ! -d $review_app ]] || rm -rf "$review_app"
      elif [[ ! -e $installed_root && -d $backup ]]; then mv "$backup" "$installed_root"; fi
      if [[ -d $transaction/old-copy.app ]]; then
        [[ ! -d $copy_app ]] || rm -rf "$copy_app"
        mv "$transaction/old-copy.app" "$copy_app"
      fi
      if [[ -d $transaction/old-review.app ]]; then
        [[ ! -d $review_app ]] || rm -rf "$review_app"
        mv "$transaction/old-review.app" "$review_app"
      fi
      if [[ -L $transaction/old-link ]]; then rm -f "$bin_dir/routine"; mv "$transaction/old-link" "$bin_dir/routine"
      elif ((root_new)) && jq -e '.link_before==""' "$receipt" >/dev/null; then rm -f "$bin_dir/routine"; fi
      while IFS= read -r row; do
        path=$(jq -r '.path' <<< "$row"); saved=$(jq -r '.backup' <<< "$row")
        [[ ! -f $saved ]] || mv "$saved" "$path"
      done < "$transaction/backups"
      [[ $mode == uninstall ]] || routine_restore_services "$transaction" || return 1
    fi
    [[ ! -d $stage ]] || rm -rf "$stage"
    rm -rf "$transaction"
    echo '✓ 중단된 설치의 소유 확인된 임시 파일 복구·정리'
  done
  if [[ -e $backup || -L $backup ]]; then
    if [[ ! -e $installed_root && ! -L $installed_root ]]; then routine_verify_ownership '' "$backup" || return 1; mv "$backup" "$installed_root" || return 1
    else
      routine_verify_ownership || return 1
      [[ $(<"$backup/install-id") == "$(<"$installed_root/install-id")" ]] && routine_verify_ownership '' "$backup" 1 || return 1
      rm -rf "$backup"
    fi
  fi
  for stage in "${installed_root%/*}"/.routine-install.*; do
    [[ -d $stage && ! -L $stage ]] || continue
    if routine_verify_ownership '' "$stage" 1 >/dev/null 2>&1; then rm -rf "$stage"
    else echo "소유 미검증 임시 디렉터리 보존: ${stage##*/}" >&2; fi
  done
}
routine_install_files() (
  local source_root=$1 stage='' transaction='' backup id path source target template content schedule hour minute plist service old config_digest current records='' committed=0 root_replaced=0 app_replaced=0 review_replaced=0 link_replaced=0 index=0 before link_before app command_name
  routine_install_paths
  backup="$installed_root.previous"
  routine_installation_idle || return 1
  routine_recover_installation || return 1
  config_digest=$(jq -cS . <<< "$ROUTINE_SETTINGS" | shasum -a 256); config_digest=${config_digest%% *}
  if [[ -e $installed_root || -L $installed_root ]]; then
    [[ -f $installed_root/install-id && -f $manifest ]] || routine_legacy_migrate || { echo '소유하지 않은 설치 디렉터리' >&2; return 1; }
    routine_verify_ownership || return 1
    id=$(<"$installed_root/install-id")
  else id=$(uuidgen); fi
  target="$bin_dir/routine"
  if [[ -e $target || -L $target ]]; then
    [[ -L $target && ( $(readlink "$target") == "$installed_root/bin/routine" || $(readlink "$target") == "$source_root/bin/routine" ) ]] || { echo "덮어쓰기 거부: $target" >&2; return 1; }
  fi
  if [[ -f $manifest ]] && jq -e --arg hash "$config_digest" --arg config_path "$(routine_config_path)" '.configuration_sha256==$hash and .configuration_path==$config_path' "$manifest" >/dev/null; then
    current=1
    for source in "$source_root"/bin/* "$source_root"/share/* "$source_root"/launchd/*.in "$source_root/VERSION" "$source_root/uninstall.sh"; do
      path=${source#"$source_root/"}; cmp -s "$source" "$installed_root/$path" || current=0
    done
    if [[ -f $source_root/CHANGELOG.md || -f $installed_root/CHANGELOG.md ]]; then
      cmp -s "$source_root/CHANGELOG.md" "$installed_root/CHANGELOG.md" || current=0
    fi
    for source in "$installed_root"/bin/* "$installed_root"/share/* "$installed_root"/launchd/*.in; do
      path=${source#"$installed_root/"}; [[ -f $source_root/$path ]] || current=0
    done
    [[ -L $target && -d $copy_app && -d $review_app ]] || current=0
    while IFS= read -r path; do [[ -f $path ]] || current=0; done < <(jq -r '.files[].path' "$manifest")
    if [[ ${ROUTINE_SKIP_LAUNCHCTL:-0} != 1 ]]; then
      for service in morning scrum-paste; do
        [[ $service != scrum-paste || $(routine_get delivery.mode) == gui-paste ]] || continue
        launchctl print "gui/$(id -u)/$(routine_get launchd.label_prefix).$service" >/dev/null 2>&1 || current=0
      done
    fi
    if ((current)); then echo '✓ 설치·LaunchAgent 이미 충족 — 건너뜀'; return 0; fi
  fi
  mkdir -p "${installed_root%/*}" "$bin_dir" "$agent_dir" "${copy_app%/*}"
  stage=$(mktemp -d "${installed_root%/*}/.routine-install.XXXXXXXX")
  transaction=$(mktemp -d "${installed_root%/*}/.routine-transaction.XXXXXXXX")
  : > "$transaction/backups"; : > "$transaction/created"; : > "$transaction/services"
  link_before=''; [[ ! -L $target ]] || link_before=$(readlink "$target")
  jq -nc --arg id "$id" --arg root "$installed_root" --arg stage "$stage" --argjson pid "$$" --arg link "$link_before" '{install_id:$id,root:$root,stage:$stage,owner_pid:$pid,link_before:$link}' > "$transaction/owner.json" || return 1
  cleanup_install() {
    local status=$1 row original saved
    trap - EXIT
    if ((!committed)); then
      if ((root_replaced)) && ! routine_stop_new_services "$transaction"; then
        echo '새 LaunchAgent 중단 실패 — 소유 확인된 설치 journal을 보존합니다.' >&2
        exit 1
      fi
      if ((root_replaced)); then rm -rf "$installed_root"; fi
      if [[ -d $backup ]]; then mv "$backup" "$installed_root"; fi
      if ((app_replaced)); then rm -rf "$copy_app"; fi
      [[ ! -d $transaction/old-copy.app ]] || mv "$transaction/old-copy.app" "$copy_app"
      if ((review_replaced)); then rm -rf "$review_app"; fi
      [[ ! -d $transaction/old-review.app ]] || mv "$transaction/old-review.app" "$review_app"
      if ((link_replaced)); then rm -f "$target"; fi
      [[ ! -L $transaction/old-link ]] || mv "$transaction/old-link" "$target"
      while IFS= read -r row; do original=$(jq -r '.path' <<< "$row"); rm -f "$original"; done < "$transaction/created"
      while IFS= read -r row; do
        original=$(jq -r '.path' <<< "$row"); saved=$(jq -r '.backup' <<< "$row")
        [[ ! -f $saved ]] || mv "$saved" "$original"
      done < "$transaction/backups"
      if ! routine_restore_services "$transaction"; then
        echo '이전 LaunchAgent 복원 실패 — 소유 확인된 설치 journal을 보존합니다.' >&2
        exit 1
      fi
    fi
    [[ -z $stage || ! -d $stage ]] || rm -rf "$stage"
    rm -rf "$transaction"
    exit "$status"
  }
  trap 'cleanup_install "$?"' EXIT
  cp -R "$source_root/bin" "$source_root/share" "$source_root/launchd" "$stage/" || return 1
  cp "$source_root/VERSION" "$source_root/uninstall.sh" "$stage/" || return 1
  [[ ! -f $source_root/CHANGELOG.md ]] || cp "$source_root/CHANGELOG.md" "$stage/" || return 1
  chmod 755 "$stage/bin/"* "$stage/uninstall.sh"
  printf '%s\n' "$id" > "$stage/install-id"
  hour=$(routine_get morning.time); minute=${hour#*:}; hour=${hour%:*}
  schedule=$(jq -r --argjson hour "$((10#$hour))" --argjson minute "$((10#$minute))" '.morning.weekdays|map("<dict><key>Weekday</key><integer>\(. % 7)</integer><key>Hour</key><integer>\($hour)</integer><key>Minute</key><integer>\($minute)</integer></dict>")|join("")' <<< "$ROUTINE_SETTINGS")
  for service in morning scrum-paste; do
    [[ $service != scrum-paste || $(routine_get delivery.mode) == gui-paste ]] || continue
    plist="$agent_dir/$(routine_get launchd.label_prefix).$service.plist"
    if [[ -e $plist || -L $plist ]]; then
      if [[ ! -f $manifest ]] || ! jq -e --arg path "$plist" 'any(.files[];.path==$path)' "$manifest" >/dev/null; then echo "덮어쓰기 거부: $plist" >&2; return 1; fi
    fi
    template=$(<"$source_root/launchd/routine.$service.plist.in")
    content=${template//__LABEL__/$(routine_get launchd.label_prefix)}
    path=$(jq -nr --arg p "$installed_root/bin/routine" '$p|@html'); content=${content//__ROUTINE_PATH__/$path}
    path=$(jq -nr --arg p "$HOME/Library/Logs/routine-automation" '$p|@html'); content=${content//__LOG_DIR__/$path}
    # /usr/sbin holds ioreg (screen-lock and idle checks); launchd starts agents without it.
    # ~/.bun/bin precedes Homebrew like bin/morning, so every scheduled step uses the same omp install.
    path=$(jq -nr --arg p "$HOME/.local/bin:$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" '$p|@html'); content=${content//__EXEC_PATH__/$path}
    path=$(jq -nr --arg p "$(routine_config_path)" '$p|@html'); content=${content//__CONFIG_PATH__/$path}
    content=${content//__SCHEDULE__/$schedule}
    printf '%s\n' "$content" > "$stage/launchd/$service.plist"
    plutil -lint "$stage/launchd/$service.plist" >/dev/null || return 1
  done
  for command_name in copy review; do
    app=$copy_app; [[ $command_name != review ]] || app=$review_app
    if [[ -e $app || -L $app ]]; then
      if [[ ! -f $manifest ]] || ! jq -e --arg prefix "$app/" 'any(.files[];.path|startswith($prefix))' "$manifest" >/dev/null; then echo "덮어쓰기 거부: $app" >&2; return 1; fi
    fi
    path=$(printf "'%s'" "${installed_root//\'/\'\\\'\'}/bin/routine")
    path="PATH='/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin' $path $command_name"
    content=$(routine_config_path)
    content=$(jq -nr --arg path "$content" '$path|@sh')
    path="ROUTINE_CONFIG=$content $path"
    path=${path//\\/\\\\}; path=${path//\"/\\\"}
    osacompile -o "$transaction/new-$command_name.app" -e "do shell script \"$path\"" || return 1
  done
  xattr -dr com.apple.quarantine "$stage" 2>/dev/null || true
  xattr -dr com.apple.quarantine "$transaction/new-copy.app" 2>/dev/null || true
  xattr -dr com.apple.quarantine "$transaction/new-review.app" 2>/dev/null || true
  records="$transaction/records"; : > "$records"
  while IFS= read -r path; do routine_record_file "$path" "$installed_root/${path#"$stage/"}"; done < <(find "$stage" -type f)
  while IFS= read -r path; do routine_record_file "$path" "$copy_app/${path#"$transaction/new-copy.app/"}"; done < <(find "$transaction/new-copy.app" -type f)
  while IFS= read -r path; do routine_record_file "$path" "$review_app/${path#"$transaction/new-review.app/"}"; done < <(find "$transaction/new-review.app" -type f)
  for service in morning scrum-paste; do
    [[ ! -f $stage/launchd/$service.plist ]] || routine_record_file "$stage/launchd/$service.plist" "$agent_dir/$(routine_get launchd.label_prefix).$service.plist"
  done
  jq -s --arg id "$id" --arg configuration_sha256 "$config_digest" --arg configuration_path "$(routine_config_path)" --arg path "$target" --arg target "$installed_root/bin/routine" '{install_id:$id,configuration_sha256:$configuration_sha256,configuration_path:$configuration_path,files:.,links:[{path:$path,target:$target}]}' "$records" > "$stage/manifest.json" || return 1
  chmod 600 "$stage/manifest.json" "$stage/install-id"
  before=null; [[ ! -f $manifest ]] || before=$(jq -c . "$manifest")
  link_before=''; [[ ! -L $target ]] || link_before=$(readlink "$target")
  jq -nc --arg id "$id" --arg root "$installed_root" --arg stage "$stage" --argjson pid "$$" --argjson before "$before" --slurpfile after "$stage/manifest.json" --arg link "$link_before" '{install_id:$id,root:$root,stage:$stage,owner_pid:$pid,before:$before,after:$after[0],link_before:$link}' > "$transaction/receipt.json" || return 1
  if [[ -f $manifest ]]; then
    while IFS= read -r old; do
      if [[ $old == "$agent_dir/"*.plist ]]; then
        service=$(routine_plist_label "$old") || return 1
        if [[ ${ROUTINE_SKIP_LAUNCHCTL:-0} != 1 ]] && launchctl print "gui/$(id -u)/$service" >/dev/null 2>&1; then
          jq -nc --arg path "$old" --arg label "$service" '{path:$path,label:$label,loaded:true}' >> "$transaction/services"
          launchctl bootout "gui/$(id -u)/$service" || return 1
        fi
        if [[ -f $old ]]; then
          path="$transaction/old-agent-$index.plist"; index=$((index+1))
          jq -nc --arg path "$old" --arg backup "$path" '{path:$path,backup:$backup}' >> "$transaction/backups"
          mv "$old" "$path" || return 1
        fi
      fi
    done < <(jq -r '.files[].path' "$manifest")
  fi
  [[ ! -d $copy_app ]] || mv "$copy_app" "$transaction/old-copy.app" || return 1
  [[ ! -d $review_app ]] || mv "$review_app" "$transaction/old-review.app" || return 1
  [[ ! -d $installed_root ]] || mv "$installed_root" "$backup" || return 1
  # The new generation already contains its complete manifest before the root rename.
  mv "$stage" "$installed_root" || return 1
  root_replaced=1
  mv "$transaction/new-copy.app" "$copy_app" || return 1
  app_replaced=1
  mv "$transaction/new-review.app" "$review_app" || return 1
  review_replaced=1
  for service in morning scrum-paste; do
    [[ -f $installed_root/launchd/$service.plist ]] || continue
    plist="$agent_dir/$(routine_get launchd.label_prefix).$service.plist"
    jq -nc --arg path "$plist" '{path:$path}' >> "$transaction/created"
    cp "$installed_root/launchd/$service.plist" "$transaction/new-agent.plist" && mv "$transaction/new-agent.plist" "$plist" || return 1
  done
  ln -s "$installed_root/bin/routine" "$transaction/routine-link"
  [[ ! -L $target ]] || mv "$target" "$transaction/old-link" || return 1
  mv -f "$transaction/routine-link" "$target" || return 1
  link_replaced=1
  routine_verify_ownership || return 1
  mkdir -p "$HOME/Library/Logs/routine-automation"
  if [[ ${ROUTINE_SKIP_LAUNCHCTL:-0} != 1 ]]; then
    for service in morning scrum-paste; do
      plist="$agent_dir/$(routine_get launchd.label_prefix).$service.plist"
      [[ -f $plist ]] || continue
      if ! launchctl bootstrap "gui/$(id -u)" "$plist"; then sleep 2; launchctl bootstrap "gui/$(id -u)" "$plist" || return 1; fi
    done
  fi
  : > "$transaction/committed"
  committed=1
  [[ ! -d $backup ]] || rm -rf "$backup"
  for service in morning scrum-collect scrum-draft scrum-paste; do
    path="$bin_dir/$service"
    if [[ -L $path && ( $(readlink "$path") == "$installed_root/bin/$service" || $(readlink "$path") == "$source_root/bin/$service" ) ]]; then rm "$path"; fi
  done
  echo '✓ routine 설치·업데이트 완료 (설정·데이터·로그 보존)'
  cleanup_install 0
)
