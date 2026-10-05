#!/usr/bin/env bash
set -euo pipefail
umask 077
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
share_dir="$repo/share"
# shellcheck source=share/config.sh
source "$share_dir/config.sh"
# shellcheck source=share/install.sh
source "$share_dir/install.sh"
purge=0
while (($#)); do
  case $1 in --purge) purge=1 ;; -h|--help) echo 'routine uninstall [--purge] — 기본은 설정·데이터·로그 보존'; exit 0 ;; *) echo "알 수 없는 옵션: $1" >&2; exit 2 ;; esac
  shift
done
routine_install_paths
routine_recover_installation uninstall
if [[ -e $installed_root || -L $installed_root ]]; then
  [[ -f $installed_root/install-id ]] || routine_legacy_migrate || { echo '소유하지 않은 설치 루트 제거 거부' >&2; exit 1; }
  routine_verify_ownership
  while IFS= read -r path; do
    if [[ $path == "$agent_dir/"*.plist ]]; then
      label=$(routine_plist_label "$path")
      service="gui/$(id -u)/$label"
      if [[ ${ROUTINE_SKIP_LAUNCHCTL:-0} != 1 ]] && launchctl print "$service" >/dev/null 2>&1; then
        if ! launchctl bootout "$service" && launchctl print "$service" >/dev/null 2>&1; then echo "로드된 LaunchAgent 제거 거부: $label" >&2; exit 1; fi
      fi
    fi
  done < <(jq -r '.files[].path' "$manifest")
  # All ownership checks finish before the first removal.
  while IFS= read -r path; do rm -f "$path"; done < <(jq -r '.files[].path,.links[].path' "$manifest")
  rm -f "$manifest" "$installed_root/install-id"
  if [[ -d $copy_app ]]; then find "$copy_app" -depth -type d -exec rmdir '{}' \;; fi
  if [[ -d $review_app ]]; then find "$review_app" -depth -type d -exec rmdir '{}' \;; fi
  find "$installed_root" -depth -type d -exec rmdir '{}' \;
fi
if ((purge)); then
  config=$(routine_config_path)
  [[ ! -L $config ]] || { echo '설정 링크 삭제 거부' >&2; exit 1; }
  rm -f "$config"
  rm -rf "$HOME/Library/Application Support/routine-automation" "$HOME/Library/Logs/routine-automation"
fi
if ((purge)); then echo 'routine 제거 완료 (설정·데이터·로그까지 삭제)'; else echo 'routine 제거 완료 (설정·데이터·로그 보존)'; fi
