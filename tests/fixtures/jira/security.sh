#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == find-generic-password ]] || exit 87
case " $* " in *' -w '*) echo token ;; *) echo metadata ;; esac >> "$JIRA_SECURITY_CALLS"
[[ ${JIRA_TOKEN_ERROR:-0} == 0 ]] || exit 44
case " $* " in *' -w '*) printf '%s\n' 'ATATTfixture-=+/._end' ;; esac
