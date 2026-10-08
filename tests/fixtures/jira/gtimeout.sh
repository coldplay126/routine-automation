#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == --version ]]; then echo 'fixture timeout'; exit 0; fi
[[ ${1:-} == -k && ${2:-} =~ ^[0-9]+$ ]] || exit 87
grace=$2; cap=$3; shift 3
if [[ ${1:-} == security ]]; then
  [[ $grace == 2 && $cap == 10 ]] || exit 87
  [[ -z ${JIRA_SECURITY_TIMEOUT_LOG:-} ]] || printf '%s\n' "$cap" >> "$JIRA_SECURITY_TIMEOUT_LOG"
  [[ ${JIRA_SECURITY_TIMEOUT:-0} == 0 ]] || exit 124
  exec "$JIRA_SECURITY_STUB" "${@:2}"
fi
if [[ ${JIRA_REAL_COLLECT:-0} == 1 ]]; then exec /opt/homebrew/bin/gtimeout -k "$grace" "$cap" "$@"; fi
if [[ ${1:-} == env && ${3:-} == */scrum-collect ]]; then
  [[ $2 == ROUTINE_ALLOW_GUI=0 ]] || exit 87
  printf 'collect\n' >> "$JIRA_COLLECTION_CALLS"
  shift 3
  out=''; until=''
  while (($#)); do case $1 in --out) out=$2; shift 2 ;; --until) until=$2; shift 2 ;; *) shift 2 ;; esac; done
  mkdir -p "$out"; cp "$JIRA_RAW" "$out/${until:0:10}.json"
  exit "${JIRA_COLLECT_EXIT:-0}"
elif [[ ${JIRA_MODEL_TIMEOUT:-0} == 1 && ${1:-} == omp ]]; then
  printf '%s\n' "$(( $(cat "$JIRA_CLOCK") + cap + ${JIRA_MODEL_CLOCK_JUMP:-0} ))" > "$JIRA_CLOCK"
  printf 'timeout\n' >> "$JIRA_MODEL_CALLS"
  exit 124
else exec "$@"; fi
