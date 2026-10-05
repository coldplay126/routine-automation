#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
export PATH='/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin'
jq_bin=${TEST_JQ_BIN:-$(command -v jq)}
sandbox=$(mktemp -d '/tmp/routine-sqlite-lock.XXXXXXXX')
writer=''
cleanup() {
  local status=$?
  if [[ -n $writer ]]; then
    printf 'ROLLBACK;\n.quit\n' >&9 || true
    exec 9>&-
    wait "$writer" || true
  fi
  rm -rf -- "$sandbox"
  exit "$status"
}
trap cleanup EXIT
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" XDG_CONFIG_HOME="$sandbox/config"
export ROUTINE_CHROME_DIR="$sandbox/chrome" ROUTINE_NOW='2026-09-28T12:00:00+09:00' ROUTINE_TZ=Asia/Seoul
mkdir -p "$HOME/.local/bin" "$TMPDIR" "$XDG_CONFIG_HOME" "$ROUTINE_CHROME_DIR/Default"
ln -s "$jq_bin" "$HOME/.local/bin/jq"
export PATH="$HOME/.local/bin:$PATH"
# shellcheck source=common.sh
source "$repo/tests/common.sh"
history="$ROUTINE_CHROME_DIR/Default/History"
/usr/bin/sqlite3 "$history" <<'SQL'
CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT, title TEXT);
CREATE TABLE visits(url INTEGER, visit_time INTEGER);
CREATE TABLE padding(v BLOB);
INSERT INTO urls VALUES (1,'https://example.atlassian.net/browse/LOCK-1','LOCK-1 committed');
INSERT INTO visits VALUES (1,(unixepoch('2026-09-25 01:00:00')+11644473600)*1000000);
INSERT INTO padding VALUES (zeroblob(4194304));
SQL
# Keep the connection and a spilling write transaction open in another process.
# The copied hot journal must restore committed data, not expose the new title.
mkfifo "$sandbox/input"
/usr/bin/sqlite3 "$history" < "$sandbox/input" > "$sandbox/writer.log" 2>&1 &
writer=$!
exec 9> "$sandbox/input"
printf '%s\n' 'PRAGMA locking_mode=EXCLUSIVE;' 'PRAGMA cache_size=1;' 'PRAGMA cache_spill=1;' 'BEGIN EXCLUSIVE;' "UPDATE urls SET title='LOCK-1 uncommitted';" 'UPDATE padding SET v=zeroblob(8388608);' ".shell touch '$sandbox/ready'" >&9
for _ in $(seq 1 100); do
  [[ ! -e $sandbox/ready ]] || break
  kill -0 "$writer" 2>/dev/null || fail 'Exclusive fixture writer exited'
  /bin/sleep 0.05
done
[[ -e $sandbox/ready && -s $history-journal ]] || fail 'Exclusive lock and journal were not ready'
# A valid header proves this is a hot journal rather than an empty PERSIST log.
[[ $(od -An -tx1 -N8 "$history-journal" | tr -d ' \n') == d9d505f920a163d7 ]] || fail 'Fixture did not spill a hot journal'
shasum -a 256 "$history" "$history-journal" > "$sandbox/before"
start=$SECONDS
status=0
"$repo/bin/scrum-collect" --out "$sandbox/out" --sources jira > "$sandbox/collector.log" 2>&1 || status=$?
elapsed=$((SECONDS-start))
shasum -a 256 "$history" "$history-journal" > "$sandbox/after"
cmp -s "$sandbox/before" "$sandbox/after" || fail 'Collector changed the locked History or journal'
result="$sandbox/out/2026-09-28.json"
printf 'Exclusive History: rc=%s elapsed=%ss source_hashes=unchanged ' "$status" "$elapsed"
jq -c '{jira,errors}' "$result"
[[ $status == 0 ]] || fail 'Collector failed while Chrome held an exclusive lock'
jq -e '.jira == [{ts:"2026-09-25T01:00:00Z",key:"LOCK-1",title:"LOCK-1 committed",url:"https://example.atlassian.net/browse/LOCK-1"}] and .errors == []' "$result" >/dev/null || fail 'Hot-journal recovery lost committed rows or exposed uncommitted data'
(( elapsed <= 15 )) || fail 'Exclusive lock collection exceeded 15 seconds'
for leftover in "$TMPDIR"/scrum-collect.*; do [[ ! -e $leftover ]] || fail 'Locked collection left temporary copies'; done
printf 'PASS: exclusive Chrome History and hot journal (%ss)\n' "$elapsed"
