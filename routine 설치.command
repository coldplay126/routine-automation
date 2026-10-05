#!/bin/bash
set -uo pipefail
status=0
script=${BASH_SOURCE[0]}
for ((links=0; links<40; links++)); do
  [[ -L $script ]] || break
  target=$(readlink "$script") || { status=1; break; }
  if [[ $target == /* ]]; then script=$target; else script="$(dirname -- "$script")/$target"; fi
done
if ((status==0)) && [[ ! -L $script ]] && CDPATH='' cd -P -- "$(dirname -- "$script")" >/dev/null; then
  /bin/bash ./install.sh "$@" || status=$?
else
  status=1
fi
printf '\n'
if ((status==0)); then
  printf '✓ routine 설치 완료\n다음 확인: routine status\n'
else
  printf '✗ routine 설치가 완료되지 않았습니다 (종료 코드 %s).\n위 안내를 확인하고 다시 실행하세요. 설치 방법.txt에 대안이 있습니다.\n' "$status"
fi
printf '\n아무 키나 누르면 창을 닫습니다.\n'
IFS= read -r -n 1 _ || true
exit "$status"
