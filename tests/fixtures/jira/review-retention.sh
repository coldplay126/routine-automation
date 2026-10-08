#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2153,SC2030,SC2031,SC2016,SC2329 # Shared suite fixtures and deliberate isolated overrides.
(
  review_boot apply
  command jq '.errors=[]|.sessions=[]|.git[0].subject="feature implementation"|.prs=[{url:"https://github.com/example/example/pull/12",number:12,title:"feature implementation",repository:{nameWithOwner:"example/example"},roles:["author"],createdAt:"2026-09-18T00:00:00Z",current:{state:"OPEN"},activity:[{kind:"commit",at:"2026-10-08T00:00:00Z"}],commit_oids:["1111111111111111111111111111111111111111"],commits_complete:true}]' "$sandbox/raw.json" > "$sandbox/retention-unlinked-raw.json"
  review_context "$sandbox/retention-unlinked-raw.json" "$jira_work/context.json"
  routine_jira_duplicate_search ABC 'feature implementation' "$jira_work/review-evidence.json" "$jira_work/search.json"
  routine_jira_meta ABC 10 "$jira_work/meta.json"
  command jq --slurpfile search "$jira_work/search.json" --slurpfile meta "$jira_work/meta.json" '.works[0].id as $id|.llm.create=[{work:$id,summary:"feature implementation"}]|.duplicates[$id]=$search[0]|.create_meta.ABC=$meta[0]' "$jira_work/context.json" > "$jira_work/context.new.json"; mv "$jira_work/context.new.json" "$jira_work/context.json"
  review_proposals "$jira_work/context.json" "$sandbox/retention-create-source.json"
  jq_check 'T72 same PR genuinely had an eligible creation before unknown marker' 'any(.proposals[];.kind=="create_issue")' "$sandbox/retention-create-source.json"
  command jq '.git[0].subject="ABC-1 feature implementation"|.prs[0].title="ABC-1 feature implementation"' "$sandbox/retention-unlinked-raw.json" > "$sandbox/retention-linked-raw.json"
  review_context "$sandbox/retention-linked-raw.json" "$jira_work/context.json"
  review_proposals "$jira_work/context.json" "$sandbox/retention-linked-source.json"
  export JIRA_WRITE_EXIT=28 JIRA_EFFECT=0
  for kind in comment transition fill_description create_issue; do
    source_file="$sandbox/retention-linked-source.json"; [[ $kind != create_issue ]] || source_file="$sandbox/retention-create-source.json"
    proposal=$(command jq -c --arg kind "$kind" '.proposals[]|select(.kind==$kind)' "$source_file")
    [[ -n $proposal ]] || fail "T72 missing real $kind proposal"
    routine_jira_approve "$proposal" "$source_file" false
    id=$(command jq -r '.entries[-1].entry_id' "$jira_dir/ledger.json"); routine_jira_apply_one "$id"
  done
  jq_check 'T72 four real unknown types share the OPEN PR' '(.entries|length)==4 and all(.entries[];.state=="unknown") and (.markers|length)==4' "$jira_dir/ledger.json"
)
rm -f "$proposal_file"
before=$(wc -l < "$JIRA_EFFECTS")
/usr/bin/expect "$repo/tests/fixtures/jira/pty.exp" "$sandbox/pty-wrapper.sh" "$sandbox/retention-close.log" close close
jq_check 'T72 no daily proposal needed to close four unknown types' '(.entries|length)==4 and all(.entries[];.state=="closed_by_user")' "$JIRA_LEDGER"
jq_check 'T72 close shows issue and create search confirmation URLs' 'contains("https://example.atlassian.net/browse/ABC-1") and contains("https://example.atlassian.net/issues/?jql=")' -Rs "$sandbox/retention-close.log"
for age in immediate after-retention; do
  if [[ $age == after-retention ]]; then
    (
      routine_jira_session; routine_jira_lock propose
      at=$(date -u -v-91d '+%Y-%m-%dT%H:%M:%SZ')
      command jq --arg at "$at" '.entries|=map(.terminated_at=$at)|.markers|=map(.at=$at)' "$jira_dir/ledger.json" > "$jira_work/old.json"; routine_jira_store "$jira_work/old.json" "$jira_dir/ledger.json"
      routine_jira_expire
      jq_check 'T72 detailed entries expire but all four suppressors remain' '.entries==[] and (.markers|length)==4' "$jira_dir/ledger.json"
    )
    command jq '.git+=[.git[0]|.sha="2222222222222222222222222222222222222222"]|.prs[0].commit_oids+=["2222222222222222222222222222222222222222"]' "$sandbox/retention-linked-raw.json" > "$sandbox/retention-new-raw.json"
  else cp "$sandbox/retention-linked-raw.json" "$sandbox/retention-new-raw.json"; fi
  (
    export JIRA_RAW="$sandbox/retention-new-raw.json"
    "$repo/bin/jira-propose"
    jq_check "T72 $age suppresses the same pr_link/fill/status-entry with actual LLM" '.llm.valid and (.proposals|length)==0' "$proposal_file"
    command jq '.git|=map(.subject="feature implementation")|.prs[0].title="feature implementation"' "$JIRA_RAW" > "$sandbox/retention-create-again.json"
    export JIRA_RAW="$sandbox/retention-create-again.json"
    "$repo/bin/jira-propose"
    jq_check "T72 $age new commits do not reopen unknown-closed PR creation" '.llm.valid and all(.proposals[];.kind!="create_issue")' "$proposal_file"
  )
done
check 'T72 close and both proposal windows cause no server effects' test "$(wc -l < "$JIRA_EFFECTS")" = "$before"
(
  review_boot apply
  comment=$(command jq -c '.proposals[]|select(.kind=="comment")' "$sandbox/base-proposals.json")
  routine_jira_approve "$comment" "$sandbox/base-proposals.json" false
  id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
  export JIRA_WRITE_EXIT=28
  routine_jira_apply_one "$id"; unset JIRA_WRITE_EXIT
  at=$(command jq -r '.entries[0].attempts[-1].started_at|fromdateiso8601-32400|strftime("%Y-%m-%dT%H:%M:%S.000-0900")' "$jira_dir/ledger.json")
  command jq --arg at "$at" '.comments[0].created=$at' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
  before=$(call_count 'POST */comment *'); routine_jira_reconcile "$id"
  jq_check 'QM6 actual offset comment reconciliation verifies by epoch not lexical date' '.entries[0].state=="verified"' "$jira_dir/ledger.json"
  check 'QM6 timezone adjustment never rePOSTs' test "$(call_count 'POST */comment *')" = "$before"
  export JIRA_ROUTES="$jira_work/forbidden-property.json"
  printf '[{"method":"GET","prefix":"/rest/api/3/comment/1/properties","http":403,"body":{}}]\n' > "$JIRA_ROUTES"
  before=$(call_count 'GET /rest/api/3/comment/*/properties*')
  review_context "$sandbox/raw.json" "$jira_work/context.json"
  jq_check 'QM5 ledger-owned comment requires no property GET' '.issues["ABC-1"].reads.comments=="ok" and .comments["ABC-1"][0]._has_property==true' "$jira_work/context.json"
  check 'QM5 known comment property request count stays unchanged' test "$(call_count 'GET /rest/api/3/comment/*/properties*')" = "$before"
)
(
  review_boot propose
  export JIRA_SECURITY_TIMEOUT_LOG="$jira_work/security-cap" JIRA_SECURITY_TIMEOUT=1
  before=$(wc -l < "$JIRA_CALLS")
  if routine_jira_authenticate; then fail 'QL2 unresponsive Keychain accepted'; fi
  check 'QL2 Keychain read bounded at ten seconds' test "$(cat "$JIRA_SECURITY_TIMEOUT_LOG")" = 10
  check 'QL2 stalled token read causes zero Jira network' test "$(wc -l < "$JIRA_CALLS")" = "$before"
)
(
  review_boot propose
  for name in orphan live unmarked; do mkdir "$TMPDIR/routine-jira.$name"; chmod 700 "$TMPDIR/routine-jira.$name"; done
  printf '%s\n' routine-jira-work-v1 > "$TMPDIR/routine-jira.orphan/kind"
  printf '%s\n' 999999 > "$TMPDIR/routine-jira.orphan/pid"; printf '%s\n' dead > "$TMPDIR/routine-jira.orphan/lstart"
  printf '%s\n' routine-jira-work-v1 > "$TMPDIR/routine-jira.live/kind"
  printf '%s\n' "$$" > "$TMPDIR/routine-jira.live/pid"; ps -o lstart= -p "$$" > "$TMPDIR/routine-jira.live/lstart"
  routine_jira_cleanup_orphans
  check 'QL10 dead owned marked directory cleaned' test ! -e "$TMPDIR/routine-jira.orphan"
  check 'QL10 live session never removed' test -d "$TMPDIR/routine-jira.live"
  check 'QL10 unmarked directory never removed' test -d "$TMPDIR/routine-jira.unmarked"
)
(
  review_boot propose
  ROUTINE_SETTINGS=$(command jq -c '.morning.extra_steps.jira_propose=true|.identity.git_authors=["fixture@example.com"]|.slack.team_id="T00001"|.slack.channel_id="C00001"|.slack.workspace_domain="example"' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  printf '%s\n' fixture-first-run > "$HOME/Library/Application Support/routine-automation/.setup-first-run"
  before=$(wc -l < "$JIRA_CALLS")
  "$repo/bin/morning" --only jira-propose > "$jira_work/setup-output"
  jq_check 'QH1 first setup morning skips Jira even when opted in' 'contains("jira-propose:skipped")' -Rs "$jira_work/setup-output"
  check 'QH1 first setup morning reads/writes no Jira' test "$(wc -l < "$JIRA_CALLS")" = "$before"
)
cat > "$sandbox/gum-one-item.sh" <<'GUM'
#!/bin/bash
set -euo pipefail
share_dir="$JIRA_SHARE"
source "$share_dir/config.sh"; routine_load_config; source "$share_dir/jira.sh"
ui_gum_available() { return 0; }
ui_gum() { while [[ $1 != -- ]]; do shift; done; shift; printf '%s\n' "$2"; }
items=$(jq -L "$share_dir" -nc 'include "jira"; [{id:"p-0000000000000001",kind:"create_issue",payload:{project:"ABC",summary:"first feature"}},{id:"p-0000000000000002",kind:"create_issue",payload:{project:"ABC",summary:"second feature"}}]|map({value:.id,label:jira_proposal_label})')
ui_choose_many 'Jira 항목' "$items" '[]' > "$JIRA_GUM_SELECTION"
GUM
export JIRA_GUM_SELECTION="$sandbox/gum-selection.json"
/usr/bin/script -q "$sandbox/gum-choice.log" /bin/bash "$sandbox/gum-one-item.sh" </dev/null
jq_check 'QM1 actual gum mapping approves exactly the selected same-project item' '.==["p-0000000000000002"]' "$JIRA_GUM_SELECTION"
echo 'PASS: Jira unknown 4종 영구 표지·91일 새 PR 커밋·LLM 생성 억제·타임존·Keychain 기한·orphan·setup·gum 선택'
# shellcheck source=review-contracts.sh
source "$repo/tests/fixtures/jira/review-contracts.sh"
