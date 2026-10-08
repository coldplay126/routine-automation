#!/usr/bin/env bash
set -euo pipefail
name=${0##*/}
if [[ $name == osascript && -n ${JIRA_NOTIFY_FILE:-} ]]; then printf '%s\n' "$*" >> "$JIRA_NOTIFY_FILE"; exit 0; fi
case $name in
  ps) [[ ${1:-} == -o && ${2:-} == lstart= && ${3:-} == -p && ${4:-} =~ ^[0-9]+$ ]] || exit 87; exec /bin/ps "$@" ;;
  git) [[ ${1:-} == -C && ${2:-} == "$JIRA_GIT_ROOT"/* ]] || exit 87; exec /usr/bin/git "$@" ;;
  *) printf '%s\n' "$name" >> "$JIRA_FORBIDDEN_CALLS"; exit 87 ;;
esac
