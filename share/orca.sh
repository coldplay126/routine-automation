# shellcheck shell=bash
# Shared Orca helpers for GUI-driving scripts.

# Print the first Orca CLI that actually runs. A PATH entry wins (tests put stubs
# there), but an unrunnable one such as a root-only /usr/local/bin/orca symlink is
# skipped in favour of the app bundle.
find_orca() {
  local candidate
  for candidate in "$(type -P orca 2>/dev/null || true)" "${ROUTINE_ORCA_APP_CLI:-/Applications/Orca.app/Contents/Resources/bin/orca}"; do
    [[ -n $candidate && -x $candidate ]] || continue
    if "$candidate" --help >/dev/null 2>&1 </dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# The CLI needs the Orca app runtime. Start it in the background when absent and
# wait up to ~15s for computer-use to answer.
ensure_orca_runtime() {
  local orca=$1 _
  "$orca" computer capabilities --json >/dev/null 2>&1 </dev/null && return 0
  open -g -a Orca >/dev/null 2>&1 || return 1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1.5
    "$orca" computer capabilities --json >/dev/null 2>&1 </dev/null && return 0
  done
  return 1
}

# A screenshot-bearing Slack snapshot proves both accessibility and screen access.
# Never treat a runtime/capabilities response as evidence of those permissions.
# Returns 3 when Slack is running without a window (closed window, not a permission problem).
orca_slack_state() {
  local snapshot
  if ! snapshot=$("$1" computer get-app-state --app com.tinyspeck.slackmacgap --json 2>/dev/null); then
    command jq -e '.error.code=="window_not_found"' <<< "$snapshot" >/dev/null 2>&1 && return 3
    return 1
  fi
  command jq -e '(.result.snapshot.treeText // .snapshot.treeText // .treeText // null)|type=="string" and length>0' <<< "$snapshot" >/dev/null 2>&1 || return 1
  printf '%s\n' "$snapshot"
}
