#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
if [[ ${1:-} == --all-jq ]]; then
  primary=$(type -P jq)
  "$0" --jq "$primary"
  if [[ -x /usr/bin/jq && $primary != /usr/bin/jq ]]; then "$0" --jq /usr/bin/jq
  else echo 'SKIP: 별도 /usr/bin/jq 없음'; fi
  exit 0
fi
if [[ ${1:-} == --jq ]]; then
  (($#==2)) && [[ -x $2 ]] || { echo 'tests/run.sh --jq /absolute/path'; exit 2; }
  export TEST_JQ_BIN=$2
elif (($#==0)); then TEST_JQ_BIN=$(type -P jq); export TEST_JQ_BIN
else echo 'tests/run.sh [--all-jq | --jq PATH]'; exit 2; fi
printf '검증 jq: %s (%s)\n' "$TEST_JQ_BIN" "$("$TEST_JQ_BIN" --version)"
sandbox=$(mktemp -d '/tmp/routine-tests.XXXXXXXX')
trap 'rm -rf -- "$sandbox"' EXIT
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" XDG_CONFIG_HOME="$sandbox/config"
mkdir -p "$HOME/.local/bin" "$TMPDIR" "$XDG_CONFIG_HOME"
ln -s "$TEST_JQ_BIN" "$HOME/.local/bin/jq"
# shellcheck source=network.sh
source "$repo/tests/network.sh"
shellcheck -x -P SCRIPTDIR "$repo"/bin/* "$repo"/share/*.sh "$repo"/install.sh "$repo"/uninstall.sh "$repo/routine 설치.command" "$repo"/tests/*.sh
export PATH="$HOME/.local/bin:$PATH"
export ROUTINE_REPO_ROOT="$sandbox/repos" ROUTINE_OMP_SESSIONS="$sandbox/sessions"
export ROUTINE_CHROME_DIR="$sandbox/chrome" ROUTINE_NOTION_DB="$sandbox/notion.db"
export ROUTINE_NOW='2026-09-28T12:00:00+09:00'
mkdir -p "$ROUTINE_REPO_ROOT" "$ROUTINE_OMP_SESSIONS/one/subagent" "$ROUTINE_OMP_SESSIONS/two" "$ROUTINE_CHROME_DIR/Default" "$ROUTINE_CHROME_DIR/Profile 1"
export ROUTINE_TZ=Asia/Seoul
# shellcheck source=common.sh
source "$repo/tests/common.sh"

commit() {
  local dir=$1 stamp=$2 email=$3 subject=$4
  printf '%s\n' "$subject" >> "$dir/changes"
  git -C "$dir" add changes
  GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" git -C "$dir" -c user.name=Fixture -c user.email="$email" commit -qm "$subject"
}
for name in one two; do git init -q "$ROUTINE_REPO_ROOT/$name"; done
commit "$ROUTINE_REPO_ROOT/one" '2026-09-25T09:00:00+0900' 'fixture@example.com' 'Implemented feature'
git -C "$ROUTINE_REPO_ROOT/one" branch second-branch
commit "$ROUTINE_REPO_ROOT/one" '2026-09-25T10:00:00+0900' 'other@example.com' 'Another author'
commit "$ROUTINE_REPO_ROOT/two" '2026-09-24T09:00:00+0900' 'fixture@example.com' 'Outside window'
commit "$ROUTINE_REPO_ROOT/two" '2026-09-25T11:00:00+0900' 'fixture@example.com' 'Reviewed implementation'
git -C "$ROUTINE_REPO_ROOT/one" remote add origin git@github.com:example/project.git
git -C "$ROUTINE_REPO_ROOT/one" worktree add -q --detach "$ROUTINE_REPO_ROOT/one-copy" second-branch
cat > "$HOME/.local/bin/gh" <<'GH'
#!/usr/bin/env bash
[[ ${GH_FAIL:-0} != 1 ]] || exit 1
case "$1 ${2:-}" in
  'api user') echo '{"id":42,"login":"fixture"}'; exit ;;
  'pr view') echo '{"state":"OPEN","title":"Current PR","baseRefName":"main","author":{"login":"fixture"},"createdAt":"2026-09-24T01:00:00Z","mergedAt":null,"closedAt":null,"commits":[{"authoredDate":"2026-09-25T01:00:00Z","authors":[{"login":"fixture"}]}],"reviews":[],"comments":[]}'; exit ;;
esac
case " $* " in *' --updated=>=2026-09-24T15:00:00Z '*) ;; *) exit 3 ;; esac
title='First PR'
[[ ${GH_SECRET:-0} == 1 ]] && title='github_pat_prSecret98765432109876543210'
case " $* " in
  *' --author=@me '*) printf '[{"repository":{"name":"one"},"number":1,"title":"%s","state":"open","createdAt":"2026-09-24T01:00:00Z","updatedAt":"2026-09-25T01:00:00Z","url":"https://github.com/example/one/pull/1"}]\n' "$title" ;;
  *' --reviewed-by=@me '*) printf '%s\n' '[{"repository":{"name":"one"},"number":1,"title":"First PR","state":"open","createdAt":"2026-09-24T01:00:00Z","updatedAt":"2026-09-25T01:00:00Z","url":"https://github.com/example/one/pull/1"}]' ;;
  *' --commenter=@me '*) printf '%s\n' '[{"repository":{"name":"one"},"number":1,"title":"First PR","state":"open","createdAt":"2026-09-24T01:00:00Z","updatedAt":"2026-09-25T01:00:00Z","url":"https://github.com/example/one/pull/1"}]' ;;
  *) exit 2 ;;
esac
GH
chmod +x "$HOME/.local/bin/gh"
cp "$repo/tests/fixtures/session.jsonl" "$ROUTINE_OMP_SESSIONS/one/a.jsonl"
cp "$repo/tests/fixtures/session.jsonl" "$ROUTINE_OMP_SESSIONS/two/mirror.jsonl"
touch -t 202609271200.00 "$ROUTINE_OMP_SESSIONS/one/a.jsonl"
printf '%s\n' '{"type":"message","timestamp":"2026-09-25T09:15:00Z","message":{"role":"user","attribution":"user","content":"Newer mirror message"}}' >> "$ROUTINE_OMP_SESSIONS/two/mirror.jsonl"
printf '%s\n' '{"type":"session","id":"nested"}' > "$ROUTINE_OMP_SESSIONS/one/subagent/nested.jsonl"
sqlite3 "$ROUTINE_CHROME_DIR/Default/History" <<'SQL'
CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT, title TEXT);
CREATE TABLE visits(url INTEGER, visit_time INTEGER);
INSERT INTO urls VALUES (1,'https://example.atlassian.net/browse/ABC-42?secret=discard','ABC-42 sprint work');
INSERT INTO visits VALUES (1,(unixepoch('2026-09-25 01:00:00')+11644473600)*1000000);
INSERT INTO visits VALUES (1,(unixepoch('2026-09-25 02:00:00')+11644473600)*1000000);
SQL
sqlite3 "$ROUTINE_CHROME_DIR/Profile 1/History" <<'SQL'
CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT, title TEXT);
CREATE TABLE visits(url INTEGER, visit_time INTEGER);
INSERT INTO urls VALUES (1,'https://example.atlassian.net/browse/DEF-9','DEF-9 review');
INSERT INTO visits VALUES (1,(unixepoch('2026-09-25 04:00:00')+11644473600)*1000000);
SQL
sqlite3 "$ROUTINE_NOTION_DB" <<'SQL'
CREATE TABLE notion_user(id TEXT, email TEXT);
CREATE TABLE block(id TEXT, parent_id TEXT, type TEXT, properties TEXT, last_edited_time INTEGER, last_edited_by_id TEXT);
INSERT INTO notion_user VALUES ('me','fixture@example.com');
INSERT INTO block VALUES ('page',NULL,'page','{"title":[["Weekly planning"]]}',1790300000000,NULL);
INSERT INTO block VALUES ('a','page','text',NULL,(unixepoch('2026-09-25 04:00:00')*1000),'me');
INSERT INTO block VALUES ('b','page','text',NULL,(unixepoch('2026-09-25 05:00:00')*1000),'me');
INSERT INTO block VALUES ('c','page','text',NULL,(unixepoch('2026-09-24 05:00:00')*1000),'me');
SQL
export SQLITE_RECORD="$sandbox/sqlite.calls"
cat > "$HOME/.local/bin/sqlite3" <<'SQLITE'
#!/usr/bin/env bash
# SQLite may open originals only for read-only backup; cp/stat may only read them.
for arg in "$@"; do
  case $arg in
    "$ROUTINE_NOTION_DB"|"file:$ROUTINE_NOTION_DB"*|"$ROUTINE_CHROME_DIR/"*|"file:$ROUTINE_CHROME_DIR/"*)
      if [[ $1 != -readonly || $2 != "$arg" || $2 != *'?mode=ro' || ${4:-} != '.backup main '* ]]; then
        echo 'Collector opened an original database outside a read-only backup' >&2
        : > "$SQLITE_RECORD.guard"
        exit 86
      fi ;;
  esac
done
printf '%s\n' "$*" >> "$SQLITE_RECORD"
history_fails() {
  case $HISTORY_MODE in
    default) [[ $1 == Default ]] ;;
    profile) [[ $1 == 'Profile 1' ]] ;;
    recover) [[ $1 == Default && $2 -le 3 ]] ;;
    all) return 0 ;;
    *) return 1 ;;
  esac
}
if [[ -n ${HISTORY_MODE:-} ]]; then
  if [[ $1 == -readonly && $2 == "file:$ROUTINE_CHROME_DIR/"* ]]; then
    path=${2#file:}; path=${path%\?mode=ro}; profile=${path%/History}; profile=${profile##*/}
    count=$(cat "$HISTORY_COUNTS/$profile" 2>/dev/null || echo 0); count=$((count+1))
    echo "$count" > "$HISTORY_COUNTS/$profile"
    echo "$profile" > "$HISTORY_COUNTS/current"
    if [[ $HISTORY_MODE == locked ]] || history_fails "$profile" "$count"; then
      echo 'Error: database is locked' >&2
      exit 5
    fi
  elif [[ ${2:-} == 'PRAGMA quick_check;' && -f $HISTORY_COUNTS/current ]]; then
    profile=$(cat "$HISTORY_COUNTS/current"); count=$(cat "$HISTORY_COUNTS/$profile")
    if history_fails "$profile" "$count"; then echo 'fixture corrupt copy'; exit 0; fi
  fi
fi
if [[ ${SQLITE_FORCE_COPY:-0} == 1 && $1 == -readonly ]]; then
  echo 'Error: database is locked' >&2
  exit 5
fi
exec /usr/bin/sqlite3 "$@"
SQLITE
chmod +x "$HOME/.local/bin/sqlite3"

shasum -a 256 "$ROUTINE_CHROME_DIR/Default/History" "$ROUTINE_NOTION_DB" > "$sandbox/source.before"
out="$sandbox/out"
"$repo/bin/scrum-collect" --out "$out"
result="$out/2026-09-28.json"
jq -e '.version == 1 and .window.since == "2026-09-24T15:00:00Z" and (.git | length) == 2 and .git[0].repo == "project" and (.git | all(.rebased == false)) and (.prs | length) == 1 and .prs[0].roles == ["author","commenter","reviewed-by"] and (.sessions | length) == 1 and [.sessions[0].user_messages[].text] == ["Reviewed sprint scope","Newer mirror message"] and (.jira | length) == 2 and (.jira[0].url | contains("?secret") | not) and (.notion | length) == 1 and .notion[0].count == 2 and .notion[0].page_title == "Weekly planning" and .errors == []' "$result" >/dev/null || fail 'Baseline collection contract'
grep -Fq "$TMPDIR/scrum-collect." "$SQLITE_RECORD" || fail 'Collector bypassed copied-database guard'
[[ $(stat -f %Lp "$out") == 700 && $(stat -f %Lp "$result") == 600 ]] || fail 'Output permissions'
[[ -f "$out/2026-09-28.md" ]] || fail 'Missing Markdown'
shasum -a 256 "$ROUTINE_CHROME_DIR/Default/History" "$ROUTINE_NOTION_DB" > "$sandbox/source.after"
cmp -s "$sandbox/source.before" "$sandbox/source.after" || fail 'Source databases changed'
for leftover in "$TMPDIR"/scrum-collect.*; do [[ ! -e $leftover ]] || fail 'Collector left temporary files'; done
# A corrupt/busy profile must neither discard earlier rows nor prevent later profiles.
export HISTORY_COUNTS="$sandbox/history-counts"
cat > "$HOME/.local/bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
exit 0
SLEEP
chmod +x "$HOME/.local/bin/sleep"
for mode in locked default profile recover all; do
  rm -rf -- "$HISTORY_COUNTS"; mkdir "$HISTORY_COUNTS"
  if HISTORY_MODE=$mode "$repo/bin/scrum-collect" --out "$out" --sources jira; then
    [[ $mode != all ]] || fail 'All failed History profiles reported success'
  else [[ $mode == all ]] || fail "Readable History profile discarded: $mode"; fi
  case $mode in
    locked)
      jq -e '(.jira|map(.key))==["ABC-42","DEF-9"] and .errors==[]' "$result" >/dev/null || fail 'Locked backups did not fall back to private copies'
      [[ $(cat "$HISTORY_COUNTS/Default") == 1 && $(cat "$HISTORY_COUNTS/Profile 1") == 1 ]] || fail 'Locked backup unnecessarily retried' ;;
    default)
      jq -e '(.jira|map(.key))==["DEF-9"] and any(.errors[];.source=="jira" and (.message|startswith("Default:")))' "$result" >/dev/null || fail 'Later healthy profile lost after snapshot failure'
      [[ $(cat "$HISTORY_COUNTS/Default") == 4 ]] || fail 'Busy profile retry bound changed' ;;
    profile)
      jq -e '(.jira|map(.key))==["ABC-42"] and any(.errors[];.source=="jira" and (.message|startswith("Profile 1:")))' "$result" >/dev/null || fail 'Earlier healthy profile lost after snapshot failure' ;;
    recover)
      jq -e '(.jira|map(.key))==["ABC-42","DEF-9"] and .errors==[]' "$result" >/dev/null || fail 'Transient snapshot failure did not recover'
      [[ $(cat "$HISTORY_COUNTS/Default") == 4 ]] || fail 'Recovery did not exercise three retries' ;;
    all)
      jq -e '.jira==[] and any(.errors[];.message|startswith("Default:")) and any(.errors[];.message|startswith("Profile 1:"))' "$result" >/dev/null || fail 'Failed profiles omitted their identities' ;;
  esac
done
rm -rf -- "$HISTORY_COUNTS"; mkdir "$HISTORY_COUNTS"
HISTORY_MODE=default "$repo/bin/scrum-collect" --out "$out" --sources jira --since 2026-10-10 --until 2026-10-11
jq -e '.jira==[] and any(.errors[];.message|startswith("Default:"))' "$out/2026-10-11.json" >/dev/null || fail 'Readable empty profile treated as source failure'
rm "$HOME/.local/bin/sleep"
mkdir "$ROUTINE_CHROME_DIR/Bad Schema"
/usr/bin/sqlite3 "$ROUTINE_CHROME_DIR/Bad Schema/History" 'CREATE TABLE unrelated(v INTEGER);'
"$repo/bin/scrum-collect" --out "$out" --sources jira
jq -e '(.jira|map(.key))==["ABC-42","DEF-9"] and any(.errors[];.message|startswith("Bad Schema:"))' "$result" >/dev/null || fail 'Invalid profile schema discarded healthy rows'
rm -rf -- "$ROUTINE_CHROME_DIR/Bad Schema"
mkdir "$ROUTINE_CHROME_DIR/Bad Check"
/usr/bin/sqlite3 "$ROUTINE_CHROME_DIR/Bad Check/History" 'CREATE TABLE broken(v INTEGER CHECK(v>0)); PRAGMA ignore_check_constraints=ON; INSERT INTO broken VALUES(-1);'
shasum -a 256 "$ROUTINE_CHROME_DIR/Bad Check/History" > "$sandbox/bad-check.before"
"$repo/bin/scrum-collect" --out "$out" --sources jira
jq -e '(.jira|map(.key))==["ABC-42","DEF-9"] and any(.errors[];.message|startswith("Bad Check: Cannot snapshot"))' "$result" >/dev/null || { jq '{jira,errors}' "$result" >&2; fail 'Failed quick_check did not report a snapshot error'; }
shasum -a 256 "$ROUTINE_CHROME_DIR/Bad Check/History" > "$sandbox/bad-check.after"
cmp -s "$sandbox/bad-check.before" "$sandbox/bad-check.after" || fail 'Corrupt original was changed'
rm -rf -- "$ROUTINE_CHROME_DIR/Bad Check"
"$repo/tests/sqlite-lock.sh"
chmod 755 "$out"
# Snapshot a committed row while SQLite is still open: it exists in the WAL,
# not the database file. The collector must read only copies of all three files.
mkdir -p "$sandbox/wal"
cp "$ROUTINE_NOTION_DB" "$sandbox/wal-live.db"
sqlite3 "$sandbox/wal-live.db" > "$sandbox/wal-setup.log" <<SQL
PRAGMA journal_mode=WAL;
PRAGMA wal_autocheckpoint=0;
INSERT INTO block VALUES ('wal-only','page','text',NULL,(unixepoch('2026-09-25 06:00:00')*1000),'me');
.shell cp "$sandbox/wal-live.db" "$sandbox/wal/notion.db"
.shell cp "$sandbox/wal-live.db-wal" "$sandbox/wal/notion.db-wal"
.shell cp "$sandbox/wal-live.db-shm" "$sandbox/wal/notion.db-shm"
SQL
[[ -s $sandbox/wal/notion.db-wal && -s $sandbox/wal/notion.db-shm ]] || fail 'Missing WAL fixture sidecars'
cp "$sandbox/wal/notion.db" "$sandbox/base-only.db"
[[ $(sqlite3 "file:$sandbox/base-only.db?immutable=1" "SELECT COUNT(*) FROM block WHERE id='wal-only'") == 0 ]] || fail 'Fixture row was checkpointed'
# -shm is SQLite's shared-memory wal-index that every reader (read-only included)
# updates for locking; database pages and the WAL itself must stay untouched.
shasum -a 256 "$sandbox/wal/notion.db" "$sandbox/wal/notion.db-wal" > "$sandbox/wal.before"
for backend in backup copy; do
  force_copy=0; [[ $backend != copy ]] || force_copy=1
  SQLITE_FORCE_COPY=$force_copy ROUTINE_NOTION_DB="$sandbox/wal/notion.db" "$repo/bin/scrum-collect" --out "$out" --sources notion
  jq -e '.notion == [{"last_edited_ts":"2026-09-25T06:00:00Z","count":3,"page_title":"Weekly planning"}] and .errors == []' "$result" >/dev/null || { jq '{notion,errors}' "$result" >&2; fail "WAL-only edit missing: $backend"; }
  shasum -a 256 "$sandbox/wal/notion.db" "$sandbox/wal/notion.db-wal" > "$sandbox/wal.after"
  cmp -s "$sandbox/wal.before" "$sandbox/wal.after" || fail "Original WAL database or log was changed: $backend"
done
[[ $(sqlite3 "file:$sandbox/base-only.db?immutable=1" "SELECT COUNT(*) FROM block WHERE id='wal-only'") == 0 && $(/usr/bin/sqlite3 "file:$sandbox/wal/notion.db?immutable=1" "SELECT COUNT(*) FROM block WHERE id='wal-only'") == 0 ]] || fail 'Collector checkpointed the original WAL'
[[ $(stat -f %Lp "$out") == 755 ]] || fail 'Existing output directory permissions changed'
# A live writer commits balanced pairs (+n, -n) and checkpoints the WAL between
# commits. Every snapshot must be a single committed state: quick_check ok, an
# even row count, and a zero sum. Sequential cp of db/-wal/-shm can violate this.
eval "$(sed -n '/^snapshot_sqlite() {/,/^}/p' "$repo/bin/scrum-collect")"
live="$sandbox/live-writer.db"
/usr/bin/sqlite3 "$live" 'PRAGMA journal_mode=WAL; CREATE TABLE t(v INTEGER);' >/dev/null
stop_writer="$sandbox/stop-writer"
(
  n=0
  while [[ ! -e $stop_writer ]]; do
    n=$((n + 1))
    batch="BEGIN;"
    for _ in 1 2 3 4 5 6 7 8; do n=$((n + 1)); batch+="INSERT INTO t VALUES ($n),(-$n);"; done
    batch+="COMMIT;"
    if (( n % 5 == 0 )); then batch+="PRAGMA wal_checkpoint(TRUNCATE);"; fi
    /usr/bin/sqlite3 "$live" ".timeout 5000" "$batch" >/dev/null 2>&1 || true
  done
) &
writer=$!
snapshots=0
for i in $(seq 1 25); do
  snap="$sandbox/snap-$i.db"
  snapshot_sqlite "$live" "$snap" || { touch "$stop_writer"; wait "$writer"; fail "Snapshot $i failed under a live writer"; }
  read -r rows total < <(/usr/bin/sqlite3 -separator ' ' "file:$snap?mode=ro" 'SELECT COUNT(*), COALESCE(SUM(v),0) FROM t;')
  (( rows % 2 == 0 && total == 0 )) || { touch "$stop_writer"; wait "$writer"; fail "Torn snapshot $i: rows=$rows sum=$total"; }
  snapshots=$((snapshots + 1))
  rm -f -- "$snap"
done
touch "$stop_writer"; wait "$writer"
final_rows=$(/usr/bin/sqlite3 "$live" 'SELECT COUNT(*) FROM t;')
(( snapshots == 25 && final_rows > 0 )) || fail 'Concurrent snapshot test did not exercise a writer'
corrupt="$sandbox/corrupt.db"; printf 'not a database' > "$corrupt"
if snapshot_sqlite "$corrupt" "$sandbox/corrupt-snap.db"; then fail 'Corrupt source produced a snapshot'; fi
[[ ! -e $SQLITE_RECORD.guard ]] || fail 'Collector attempted a writable SQLite open of an original'
GH_FAIL=1 "$repo/bin/scrum-collect" --out "$out" --sources git,prs
jq -e '(.errors|map(.source))==["prs"] and (.git | length) == 2 and .prs == []' "$result" >/dev/null || fail 'Source failure isolation'
if GH_FAIL=1 "$repo/bin/scrum-collect" --out "$out" --sources prs >/dev/null 2>&1; then echo 'Expected all-sources-failed exit' >&2; exit 1; fi
ROUTINE_NOW='2026-09-28T12:00:00+09:00' "$repo/bin/scrum-collect" --out "$out" --since 2026-09-27 --sources notion
jq -e '.notion == [] and .errors == []' "$result" >/dev/null || fail 'Empty Notion results'
locked_root="$sandbox/locked-repos"
mkdir "$locked_root"
chmod 000 "$locked_root"
ROUTINE_REPO_ROOT="$locked_root" "$repo/bin/scrum-collect" --out "$out" --sources git,sessions
chmod 700 "$locked_root"
jq -e '.git == [] and (.sessions | length) == 1 and (any(.errors[]; .source == "git" and (.message | contains("Documents access"))))' "$result" >/dev/null || fail 'Unreadable repository root was silent'
mkdir "$ROUTINE_REPO_ROOT/broken" "$ROUTINE_REPO_ROOT/denied"
printf 'gitdir: /missing-worktree\n' > "$ROUTINE_REPO_ROOT/broken/.git"
printf 'gitdir: /missing-denied-worktree\n' > "$ROUTINE_REPO_ROOT/denied/.git"
cat > "$HOME/.local/bin/git" <<'GIT'
#!/usr/bin/env bash
if [[ ${1-} == -C && ${2-} == */denied && " $* " == *' log '* ]]; then
  echo 'fatal: Operation not permitted' >&2
  exit 1
fi
exec /usr/bin/git "$@"
GIT
chmod +x "$HOME/.local/bin/git"
cat > "$ROUTINE_OMP_SESSIONS/one/broken.jsonl" <<'SESSION'
{"type":"session","id":"damaged-session","timestamp":"2026-09-25T08:00:00Z","cwd":"/fixture/damaged"}
{"type":"message","timestamp":"2026-09-25T08:01:00Z","message":{"role":"user","content":"Valid line after damage"}}
{"type":"message","broken":
{"type":"message","timestamp":"2026-09-25T08:02:00Z","message":{"role":"user","content":"  <system_notice>Injected"}}
SESSION
"$repo/bin/scrum-collect" --out "$out" --sources git,sessions
jq -e '(.git | length) == 2 and (.sessions | length) == 2 and (any(.sessions[]; any(.user_messages[]; .text == "Valid line after damage"))) and (all(.sessions[].user_messages[].text; contains("Injected") | not)) and (any(.errors[]; .source == "git" and (.message | contains("broken:")))) and (any(.errors[]; .source == "git" and (.message | contains("denied: Operation not permitted"))))' "$result" >/dev/null || fail 'Broken worktree or JSONL isolation'
for leftover in "$TMPDIR"/scrum-collect.*; do [[ ! -e $leftover ]] || fail 'Collector left temporary files after partial failure'; done
printf 'rebased\n' >> "$ROUTINE_REPO_ROOT/one/changes"
git -C "$ROUTINE_REPO_ROOT/one" add changes
GIT_AUTHOR_DATE='2026-09-10T09:00:00+0900' GIT_COMMITTER_DATE='2026-09-25T12:00:00+0900' git -C "$ROUTINE_REPO_ROOT/one" -c user.name=Fixture -c user.email=fixture@example.com commit -qm 'Rebased older work'
commit "$ROUTINE_REPO_ROOT/two" '2026-09-25T13:00:00+0900' 'fixture@example.com' 'AKIAABCDEFGHIJKLMNOP'
cp "$repo/tests/fixtures/secrets.jsonl" "$ROUTINE_OMP_SESSIONS/one/secrets.jsonl"
printf -v padding '%0290d' 0
jq -nc --arg text "$padding AKIAIOSFODNN7EXAMPLE" '{type:"message",timestamp:"2026-09-25T08:09:00Z",message:{role:"user",attribution:"user",content:$text}}' >> "$ROUTINE_OMP_SESSIONS/one/secrets.jsonl"
/usr/bin/sqlite3 "$ROUTINE_CHROME_DIR/Default/History" <<'SQL'
INSERT INTO urls VALUES (2,'https://example.atlassian.net/browse/GHI-3','xoxb-jiraSecret987');
INSERT INTO visits VALUES (2,(unixepoch('2026-09-25 03:00:00')+11644473600)*1000000);
INSERT INTO urls VALUES (3,'https://example.atlassian.net/browse/NULL-7',NULL);
INSERT INTO visits VALUES (3,(unixepoch('2026-09-25 03:10:00')+11644473600)*1000000);
INSERT INTO urls VALUES (4,'https://example.atlassian.net/wiki/spaces/ENG','UTF-8 overview');
INSERT INTO visits VALUES (4,(unixepoch('2026-09-25 03:20:00')+11644473600)*1000000);
INSERT INTO urls VALUES (5,'https://example.atlassian.net/secure/Dashboard.jspa?selectedIssue=JKL-4','Dashboard');
INSERT INTO visits VALUES (5,(unixepoch('2026-09-25 03:30:00')+11644473600)*1000000);
SQL
/usr/bin/sqlite3 "$ROUTINE_NOTION_DB" <<'SQL'
INSERT INTO block VALUES ('secret-page',NULL,'page','{"title":[["token=notionSecret987"]]}',(unixepoch('2026-09-25 03:00:00')*1000),'me');
SQL
GH_SECRET=1 "$repo/bin/scrum-collect" --out "$out"
jq -e '(.git | length) == 4 and (any(.git[]; .rebased == true and (.author_ts | startswith("2026-09-10")))) and (.sessions | length) == 3 and (.jira | length) == 5 and (any(.jira[]; .key == "NULL-7" and .title == "")) and (all(.jira[].key; . != "UTF-8")) and (.notion | length) == 2 and .errors != []' "$result" >/dev/null || fail 'Redacted activity contract'
for secret in ASIAPRESIGNED0001 presignedToken987 presignedSig987 jsonsecret001 awssecret001 AKIAABCDEFGHIJKLMNOP AKIAIOSFO github_pat_example123 github_pat_prSecret987 xoxb-example123 ATATTexample123 eyJheader.eyJpayload.signature123 person:pass123@ titleSecret987 notionSecret987 jiraSecret987 pw123 ghp_example123 sk-ant-example123 PEMBODYLEAK123 PEMBODYWITHOUTEND321 '-----BEGIN OPENSSH PRIVATE KEY-----' '-----BEGIN RSA PRIVATE KEY-----'; do
  if grep -Fq -- "$secret" "$result" "$out/2026-09-28.md"; then fail "Secret leaked: $secret"; fi
done
jq -e 'any(.sessions[]; .cwd == "/workspace/example-task-wt/risk-based/disk-usage" and any(.user_messages[]; .text == "primary key: user_id; risk-based disk-usage")) and all(.git[]; (.sha | test("^[0-9a-f]{40}$"))) and .prs[0].url == "https://github.com/example/one/pull/1"' "$result" >/dev/null || fail 'Benign strings, SHA or URL changed'
if "$repo/bin/scrum-collect" --out "$out" --sources '' >/dev/null 2>&1; then fail 'Empty sources accepted'; else [[ $? == 2 ]] || fail 'Empty sources did not exit 2'; fi
if "$repo/bin/scrum-collect" --out "$out" --sources ',,' >/dev/null 2>&1; then fail 'Comma-only sources accepted'; else [[ $? == 2 ]] || fail 'Comma-only sources did not exit 2'; fi
if ROUTINE_GIT_AUTHORS=' ' "$repo/bin/scrum-collect" --out "$out" --sources git >/dev/null 2>&1; then fail 'Empty authors accepted'; else [[ $? == 2 ]] || fail 'Empty authors did not exit 2'; fi

cat > "$HOME/.local/bin/gtimeout" <<'TIMEOUT'
#!/usr/bin/env bash
[[ $1 == -k && $2 == 30 && $3 == 600 ]] || exit 99
printf '%s\n' "$(umask)" >> "$UMASK_RECORD"
shift 3
"$@"
TIMEOUT
cat > "$HOME/.local/bin/omp" <<'OMP'
#!/usr/bin/env bash
echo omp >> "$STEP_RECORD"
case ${OMP_TIMEOUT:-0} in 1) exit 124 ;; 137) exit 137 ;; esac
exit 7
OMP
cat > "$HOME/.local/bin/claude" <<'CLAUDE'
#!/usr/bin/env bash
echo claude >> "$STEP_RECORD"
CLAUDE
cat > "$HOME/.local/bin/osascript" <<'NOTIFY'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NOTIFICATION_RECORD"
NOTIFY
chmod +x "$HOME/.local/bin/"{gtimeout,omp,claude,osascript}
export STEP_RECORD="$sandbox/steps" NOTIFICATION_RECORD="$sandbox/notifications" UMASK_RECORD="$sandbox/step-umasks"
expected_umask=$(umask)
dry=$({ "$repo/bin/morning" --dry-run --only omp-update --only claude-update --skip omp-update; })
[[ $dry == *'omp-update: skipped'* && $dry == *'claude-update: claude update'* && ! -e $STEP_RECORD && ! -e $NOTIFICATION_RECORD ]] || fail 'Dry-run effects or selection'
if "$repo/bin/morning" --only omp-update --only claude-update > "$sandbox/morning-output"; then echo 'Expected failed step' >&2; exit 1; fi
[[ -f $STEP_RECORD && -f $NOTIFICATION_RECORD ]] || fail 'Missing step or notification evidence'
[[ $(cat "$STEP_RECORD") == $'omp\nclaude' ]] || fail 'Step order'
[[ $(cat "$UMASK_RECORD") == "$expected_umask"$'\n'"$expected_umask" ]] || fail 'CLI steps inherited restricted log umask'
[[ $(wc -l < "$NOTIFICATION_RECORD") -eq 1 ]] || fail 'Expected exactly one notification'
[[ $(cat "$sandbox/morning-output") == *'omp-update:fail('*'exit 7)'* && $(cat "$sandbox/morning-output") == *'claude-update:ok'* ]] || fail 'Missing step exit 7 or continuation'
grep -Fq 'omp-update' "$NOTIFICATION_RECORD" || fail 'Failure notification omitted step name'
log_dir="$HOME/Library/Logs/routine-automation"
[[ $(stat -f %Lp "$log_dir") == 700 && $(stat -f %Lp "$log_dir"/morning-*.log) == 600 ]] || fail 'Log permissions'
lock="$log_dir/.morning.lock"
mkdir "$lock"
printf '%s\n' "$$" > "$lock/pid"
"$repo/bin/morning" --only claude-update > "$sandbox/locked"
[[ $(cat "$sandbox/locked") == 'morning: already running' && $(wc -l < "$STEP_RECORD") -eq 2 && $(wc -l < "$NOTIFICATION_RECORD") -eq 2 ]] || fail 'Active lock notification'
rm "$lock/pid"
rmdir "$lock"
mkdir "$lock"
printf '99999999\n' > "$lock/pid"
"$repo/bin/morning" --only claude-update > "$sandbox/recovered"
[[ $(cat "$sandbox/recovered") == *'recovered stale lock'* && $(wc -l < "$STEP_RECORD") -eq 3 && ! -e $lock ]] || fail 'Stale lock recovery'
mkdir "$lock"
printf '%s\n' "$$" > "$lock/pid"
old_epoch=$(($(date +%s) - 4201))
touch -t "$(date -r "$old_epoch" '+%Y%m%d%H%M.%S')" "$lock"
"$repo/bin/morning" --only claude-update > "$sandbox/expired"
[[ $(cat "$sandbox/expired") == *'recovered stale lock'* && $(wc -l < "$STEP_RECORD") -eq 4 && ! -e $lock ]] || fail '70-minute lock was not reclaimed'
mkdir "$lock" "$log_dir/.morning.recovery.lock"
printf '99999999\n' > "$lock/pid"
recovery_epoch=$(($(date +%s) - 61))
touch -t "$(date -r "$recovery_epoch" '+%Y%m%d%H%M.%S')" "$log_dir/.morning.recovery.lock"
"$repo/bin/morning" --only claude-update > "$sandbox/recovery-lock"
[[ $(cat "$sandbox/recovery-lock") == *'recovered stale lock'* && $(wc -l < "$STEP_RECORD") -eq 5 && ! -e $lock && ! -e "$log_dir/.morning.recovery.lock" ]] || fail 'Aged recovery lock was not reclaimed'
if OMP_TIMEOUT=1 "$repo/bin/morning" --only omp-update > "$sandbox/timed-out"; then fail 'Timeout reported success'; fi
[[ $(cat "$sandbox/timed-out") == *'omp-update:fail(timeout, '*'exit 124)'* ]] || fail 'Timeout result not distinguished'
if OMP_TIMEOUT=137 "$repo/bin/morning" --only omp-update > "$sandbox/killed-timeout"; then fail 'Forced timeout reported success'; fi
[[ $(cat "$sandbox/killed-timeout") == *'omp-update:fail(timeout, '*'exit 137)'* ]] || fail 'Forced timeout not distinguished'

"$repo/tests/scrum.sh"
"$repo/tests/team-package.sh"
"$repo/tests/update.sh"
"$repo/tests/onboarding.sh"
"$repo/tests/gum-ui.sh"
"$repo/tests/first-run-ui.sh"
"$repo/tests/pr-activity.sh"
"$repo/tests/draft-completion.sh"
"$repo/tests/review.sh"
"$repo/tests/style.sh"
"$repo/tests/learn.sh"
echo 'PASS: shellcheck, collector/morning/scrum 안전 회귀, 팀 패키지 계약'
