#!/usr/bin/env bash
set -euo pipefail
repo=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)
if [[ ${1:-} == --update ]]; then
  (($#==1)) || { echo 'install.sh --update는 다른 인자를 받지 않습니다.' >&2; exit 2; }
  export PATH="$HOME/.local/bin:$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  share_dir="$repo/share"
  # shellcheck source=share/config.sh
  source "$share_dir/config.sh"
  # shellcheck source=share/install.sh
  source "$share_dir/install.sh"
  routine_jq_supported || { echo '업데이트에는 jq 1.7 이상이 필요합니다. 새 패키지의 routine 설치.command로 의존성을 준비하세요.' >&2; exit 1; }
  [[ -f $HOME/.local/share/routine-automation/manifest.json || -f $HOME/.local/share/routine-automation.previous/manifest.json ]] || {
    echo '기존 설치가 없습니다. 첫 설치는 routine 설치.command를 실행하세요.' >&2; exit 1;
  }
  routine_install_paths
  routine_use_install_config || exit 1
  [[ -f $(routine_config_path) ]] || { echo '기존 설정이 없습니다. 새 패키지의 routine 설치.command를 실행하세요.' >&2; exit 1; }
  if ! routine_load_config persisted || ! routine_require_config '새 패키지의 routine 설치.command'; then
    if [[ -n ${ROUTINE_UPDATE_ZIP_PATH:-} ]]; then
      printf '업데이트 설정 확인이 필요합니다. 사용한 새 ZIP을 직접 풀고 그 폴더의 routine 설치.command 또는 /bin/bash ./bin/routine setup을 실행하세요.\nZIP: %s\n' "$(command jq -nr --arg path "$ROUTINE_UPDATE_ZIP_PATH" '$path|gsub("[\u0000-\u001f\u007f]";"")')" >&2
    else
      printf '업데이트 설정 확인이 필요합니다. 기존 routine init이 아니라 새 패키지의 설정 도구를 실행하세요:\n  /bin/bash %q/bin/routine setup\n또는 새 패키지의 routine 설치.command를 실행하세요.\n' "$repo" >&2
    fi
    echo '기존 설정·설치본은 변경하지 않았습니다.' >&2
    exit 1
  fi
  # config.jq supplies compatible defaults/migrations without rewriting the saved file.
  routine_install_files "$repo"
  exit
fi
exec "$repo/bin/routine" setup "$@"
