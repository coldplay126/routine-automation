#!/usr/bin/env bash
set -euo pipefail
if [[ $# == 1 && $1 == +%s && -n ${JIRA_CLOCK:-} ]]; then cat "$JIRA_CLOCK"; else exec /bin/date "$@"; fi
