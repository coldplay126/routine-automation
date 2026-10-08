#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2153,SC2034,SC2016,SC2030,SC2031 # Sourced helpers consume the dynamic context and isolated fixtures.
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
  routine_jira_approve "$(cat "$sandbox/fill-proposal.json")" "$sandbox/base-proposals.json" false
  for kind in comment transition; do routine_jira_approve "$(command jq -c --arg kind "$kind" '.proposals[]|select(.kind==$kind)' "$sandbox/base-proposals.json")" "$sandbox/base-proposals.json" false; done
  before=$(wc -l < "$JIRA_EFFECTS")
  routine_jira_apply_locked
  jq_check 'T40 all approved operations verified' 'all(.entries[];.state=="verified")' "$jira_dir/ledger.json"
  command jq -Rn --argjson before "$before" '[inputs]|.[$before:]' "$JIRA_EFFECTS" > "$jira_work/write-order.json"
  jq_check 'T40 fill then comment then transition' '.[0]=="PUT /rest/api/3/issue/ABC-1" and .[1]=="POST /rest/api/3/issue/ABC-1/comment" and .[2]=="POST /rest/api/3/issue/ABC-1/transitions"' "$jira_work/write-order.json"
)
cat > "$sandbox/crash-client.sh" <<'CLIENT'
#!/bin/bash
set -euo pipefail
share_dir="$JIRA_SHARE"
source "$share_dir/config.sh"; source "$share_dir/jira.sh"
routine_load_config; routine_jira_session; routine_jira_lock apply; routine_jira_authenticate
ui_interactive() { return 0; }
export JIRA_PARENT_PID=$$
routine_jira_apply_one "$1"
CLIENT
for boundary in before after applied; do
  (
    cp "$sandbox/server-initial.json" "$JIRA_SERVER"
    routine_jira_session; routine_jira_lock review; routine_jira_authenticate; reset_jira_ledger
    routine_jira_approve "$(cat "$sandbox/fill-proposal.json")" "$sandbox/base-proposals.json" false
  )
  id=$(command jq -r .entries[0].entry_id "$JIRA_LEDGER")
  before=$(call_count 'PUT *')
  if JIRA_CRASH=$boundary /bin/bash "$sandbox/crash-client.sh" "$id"; then fail 'T70 crash boundary did not interrupt'; fi
  (
    routine_jira_session; routine_jira_lock apply; routine_jira_authenticate
    jq_check 'T70 fill marker committed before transport' '.markers[0].kind=="fill" and (.entries[0].state|IN("applying","applied"))' "$jira_dir/ledger.json"
    routine_jira_reconcile "$id" || true
    if [[ $boundary == before ]]; then jq_check 'T70 pre-send crash stays unknown' '.entries[0].state=="unknown"' "$jira_dir/ledger.json"
    else jq_check 'T70 post-send crash recovered read-only' '.entries[0].state=="verified"' "$jira_dir/ledger.json"; fi
    check 'T70 interrupted entry never re-PUTs' test "$(call_count 'PUT *')" = "$((before+1))"
    command jq '.issue.fields.description={type:"doc",content:[]}' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
    routine_jira_approve "$(cat "$sandbox/fill-proposal.json")" "$sandbox/base-proposals.json" false
    check 'T70 alternate approval never sends a second PUT' test "$(call_count 'PUT *')" = "$((before+1))"
  )
done
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
  create=$(cat "$sandbox/create-proposal.json")
  routine_jira_approve "$create" "$sandbox/create-source.json" false
  id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
  export JIRA_ROUTES="$jira_work/late-duplicate.json"
  command jq -n --slurpfile server "$JIRA_SERVER" '[{method:"POST",prefix:"/rest/api/3/search/jql",body:{isLast:true,issues:[$server[0].issue]}}]' > "$JIRA_ROUTES"
  before=$(call_count 'POST /rest/api/3/issue *'); routine_jira_apply_one "$id"
  jq_check 'T57 concurrent strong duplicate blocks creation' '.entries[0].state=="blocked"' "$jira_dir/ledger.json"
  check 'T57 preflight re-search no create' test "$(call_count 'POST /rest/api/3/issue *')" = "$before"
)
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
  create=$(cat "$sandbox/create-proposal.json"); routine_jira_approve "$create" "$sandbox/create-source.json" false
  id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
  export JIRA_WRITE_EXIT=28; routine_jira_apply_one "$id"; unset JIRA_WRITE_EXIT
  command jq '.issue.fields.reporter.accountId="other"' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
  routine_jira_reconcile "$id"
  jq_check 'T58 reporter mismatch not verified' '.entries[0].state=="verify_failed"' "$jira_dir/ledger.json"
)
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
  comment=$(command jq -c '.proposals[]|select(.kind=="comment")' "$sandbox/base-proposals.json")
  routine_jira_approve "$comment" "$sandbox/base-proposals.json" false
  cp "$jira_dir/ledger.json" "$jira_work/site-a.json"
  ROUTINE_SETTINGS=$(command jq -c '.jira.site="https://other.atlassian.net"' <<< "$ROUTINE_SETTINGS"); jira_site=https://other.atlassian.net
  routine_jira_authenticate
  routine_jira_apply_locked
  check 'T64 other site entries untouched' cmp "$jira_work/site-a.json" "$jira_dir/ledger.json"
  ROUTINE_SETTINGS=$(command jq -c '.jira.site="https://example.atlassian.net"' <<< "$ROUTINE_SETTINGS"); jira_site=https://example.atlassian.net
  routine_jira_authenticate; routine_jira_apply_locked
  jq_check 'T64 returning to same context applies' '.entries[0].state=="verified"' "$jira_dir/ledger.json"
)
# Four actual unknown writes, then close without any proposal file.
(
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
  printf '{"version":1,"links":[],"rejections":[]}\n' > "$jira_work/links-reset.json"; routine_jira_store "$jira_work/links-reset.json" "$jira_dir/links.json"
  export JIRA_WRITE_EXIT=28 JIRA_EFFECT=0
  for kind in comment transition fill_description create_issue; do
    case $kind in
      comment|transition) proposal=$(command jq -c --arg kind "$kind" '.proposals[]|select(.kind==$kind)' "$sandbox/base-proposals.json"); source_file="$sandbox/base-proposals.json" ;;
      fill_description) proposal=$(cat "$sandbox/fill-proposal.json"); source_file="$sandbox/base-proposals.json" ;;
      create_issue) proposal=$(cat "$sandbox/create-proposal.json"); source_file="$sandbox/create-source.json" ;;
    esac
    routine_jira_approve "$proposal" "$source_file" false
    id=$(command jq -r '.entries[-1].entry_id' "$jira_dir/ledger.json"); routine_jira_apply_one "$id"
  done
  jq_check 'T72 all four unknown write types' '(.entries|length)==4 and all(.entries[];.state=="unknown") and (.markers|length)==4' "$jira_dir/ledger.json"
)
rm -f "$proposal_file"
before=$(call_count 'PUT *')
check 'T72 actual terminal close without daily proposal' /usr/bin/expect "$repo/tests/fixtures/jira/pty.exp" "$sandbox/pty-wrapper.sh" "$sandbox/close-pty.log" close close
jq_check 'T72 closed entries only' 'all(.entries[];.state=="closed_by_user")' "$JIRA_LEDGER"
check 'T72 close is read-only' test "$(call_count 'PUT *')" = "$before"
(
  routine_jira_session; routine_jira_lock propose
  at=$(date -u -v-91d '+%Y-%m-%dT%H:%M:%SZ')
  command jq --arg at "$at" '.entries|=map(.terminated_at=$at)|.markers|=map(.at=$at)' "$jira_dir/ledger.json" > "$jira_work/old.json"; routine_jira_store "$jira_work/old.json" "$jira_dir/ledger.json"
  routine_jira_expire
  jq_check 'T72 detailed entries expire but permanent suppressors remain' '(.entries|length)==0 and (.markers|length)==4' "$jira_dir/ledger.json"
)
"$repo/bin/jira-propose" --no-llm
jq_check 'T72 same event/fill/transition suppressed after 91 days' '.proposals|length==0' "$proposal_file"
echo 'PASS: Jira 반영 순서·종료 경계·중복 재검색·사이트 격리·4종 결과 불명 닫기 (W008–W010)'
(
  ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="none"|.morning.extra_steps.jira_propose=true|.identity.git_authors=["fixture@example.com"]|.slack.team_id="T00001"|.slack.channel_id="C00001"|.slack.workspace_domain="example"' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  export JIRA_NOTIFY_FILE="$sandbox/notifications"
  command jq '.git[0].sha="2222222222222222222222222222222222222222"' "$sandbox/raw.json" > "$sandbox/morning-raw.json"
  export JIRA_RAW="$sandbox/morning-raw.json"
  before_put=$(call_count 'PUT *'); before_comment=$(call_count 'POST */comment *'); before_create=$(call_count 'POST /rest/api/3/issue *'); before_transition=$(call_count 'POST */transitions *')
  check 'T66 scheduled morning proposal' "$repo/bin/morning" --only jira-propose
  check 'T66 morning zero PUT' test "$(call_count 'PUT *')" = "$before_put"
  check 'T66 morning zero comment' test "$(call_count 'POST */comment *')" = "$before_comment"
  check 'T66 morning zero create' test "$(call_count 'POST /rest/api/3/issue *')" = "$before_create"
  check 'T66 morning zero transition' test "$(call_count 'POST */transitions *')" = "$before_transition"
  notification=$(cat "$JIRA_NOTIFY_FILE")
  [[ $notification == *'— Jira 제안 1건 — 검토: routine jira review'* ]] || fail 'T78 exact morning notification count and command'
  before=$(wc -l < "$JIRA_CALLS")
  "$repo/bin/routine" doctor > "$sandbox/doctor" 2>&1 || true
  check 'T78 doctor network zero' test "$(wc -l < "$JIRA_CALLS")" = "$before"
  while IFS= read -r security_record; do last_security_record=$security_record; done < "$JIRA_SECURITY_CALLS"
  [[ ${last_security_record:-} == metadata ]] || fail 'T78 doctor read Keychain token'
  "$repo/bin/routine" status > "$sandbox/status"
  check 'T78 status network zero' test "$(wc -l < "$JIRA_CALLS")" = "$before"
  ROUTINE_SETTINGS=$(command jq -c '.jira.site=""' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  if "$repo/bin/routine" jira; then fail 'T77 missing site accepted'; else [[ $? == 2 ]] || fail 'T77 exit code'; fi
  check 'T77 invalid Jira does not block scrum draft' "$repo/bin/routine" draft --date 2026-10-08 --out "$sandbox/real-collect" --no-llm
  ROUTINE_SETTINGS=$(command jq -c '.jira.enabled=false' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  check 'T77 disabled Jira scheduled step skipped' "$repo/bin/morning" --only jira-propose
)
(
  routine_jira_session; routine_jira_lock links
  printf '{"version":1,"links":[{"site":"https://example.atlassian.net","account_id":"fixture-account","evidence_id":"git:one","key":"ABC-1"},{"site":"https://other.atlassian.net","account_id":"fixture-account","evidence_id":"git:two","key":"ABC-2"}],"rejections":[]}\n' > "$jira_work/links-fixture.json"; routine_jira_store "$jira_work/links-fixture.json" "$jira_dir/links.json"
  routine_jira_links > "$jira_work/links-list"
  if routine_jira_links 1; then fail 'T74 nested links remove lock'; else [[ $? == 4 ]] || fail 'T74 links lock exit'; fi
)
(
  routine_jira_session
  routine_jira_links 1
  jq_check 'T79 remove under lock preserves other-site link' '(.links|length)==1 and .links[0].site=="https://other.atlassian.net"' "$jira_dir/links.json"
)
echo 'PASS: Jira morning·doctor·status·설정 격리·links 잠금/삭제 (W010/W011)'
