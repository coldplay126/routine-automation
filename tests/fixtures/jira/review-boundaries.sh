#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2153,SC2034,SC2030,SC2031,SC2016,SC2329 # Shared fixtures, isolated overrides, literal jq.
for state in approved unknown verified wrong-attempt no-lock applying; do
  (
    review_boot apply
    routine_jira_approve "$(command jq -c '.proposals[]|select(.kind=="comment")' "$sandbox/base-proposals.json")" "$sandbox/base-proposals.json" false
    id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
    actual=$state; [[ $state != wrong-attempt && $state != no-lock ]] || actual=applying
    command jq --arg state "$actual" --argjson pid "$$" --arg start "$jira_lstart" --arg now "$(routine_jira_now)" '.entries[0].state=$state|.entries[0].attempts=[{id:"a-matching",pid:$pid,lstart:$start,started_at:$now}]' "$jira_dir/ledger.json" > "$jira_work/send-state.json"; routine_jira_store "$jira_work/send-state.json" "$jira_dir/ledger.json"
    attempt=a-matching; [[ $state != wrong-attempt ]] || attempt=a-different
    jira_authorized_entry=$id; jira_authorized_attempt=$attempt
    if [[ $state == no-lock ]]; then rm -f -- "$jira_dir/.lock/pid" "$jira_dir/.lock/lstart" "$jira_dir/.lock/kind"; rmdir "$jira_dir/.lock"; fi
    before=$(call_count 'POST */comment *'); effects=$(wc -l < "$JIRA_EFFECTS")
    if [[ $state == applying ]]; then
      check 'T63 normal direct send requires applying and matching live attempt' routine_jira_send "$id" "$attempt"
      check 'T63 normal contract issues one write' test "$(call_count 'POST */comment *')" = "$((before+1))"
    else
      if routine_jira_send "$id" "$attempt"; then fail "T63 bypass $state"; fi
      check "T63 rejects $state without write transport" test "$(call_count 'POST */comment *')" = "$before"
      check 'T63 rejected contract has no server effect' test "$(wc -l < "$JIRA_EFFECTS")" = "$effects"
    fi
  )
done
for change in project host summary hash; do
  (
    review_boot apply
    routine_jira_approve "$(command jq -c '.proposals[]|select(.kind=="comment")' "$sandbox/base-proposals.json")" "$sandbox/base-proposals.json" false
    id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
    command jq --arg change "$change" 'if $change=="project" then .entries[0].key="DEF-1"|.entries[0].request.path="/rest/api/3/issue/DEF-1/comment" elif $change=="host" then .entries[0].request.path="https://other.atlassian.net/rest/api/3/issue/ABC-1/comment" elif $change=="summary" then .entries[0].request.body.summary="unexpected field" else .entries[0].request_sha256="wrong-hash" end' "$jira_dir/ledger.json" > "$jira_work/tampered.json"; routine_jira_store "$jira_work/tampered.json" "$jira_dir/ledger.json"
    before=$(call_count 'POST */comment *'); effects=$(wc -l < "$JIRA_EFFECTS")
    routine_jira_apply_one "$id"
    jq_check "T65 actual apply rejects ledger $change mutation" '.entries[0].state=="conflict" and .entries[0].attempts==[]' "$jira_dir/ledger.json"
    check 'T65 mutated approved request never sent' test "$(call_count 'POST */comment *')" = "$before"
    check 'T65 mutation causes no server effect' test "$(wc -l < "$JIRA_EFFECTS")" = "$effects"
  )
done
for mode in disappeared already-target valid; do
  (
    review_boot apply
    transition=$(command jq -c '.proposals[]|select(.kind=="transition")' "$sandbox/base-proposals.json")
    routine_jira_approve "$transition" "$sandbox/base-proposals.json" false
    id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
    if [[ $mode == disappeared ]]; then command jq '.transitions=[]' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
    elif [[ $mode == already-target ]]; then command jq '.issue.fields.status.id="3"' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"; fi
    before=$(call_count 'POST */transitions *'); routine_jira_apply_one "$id"
    if [[ $mode == valid ]]; then
      jq_check 'T24 transition ID is not the status ID in the actual request' '.entries[0].state=="verified" and .entries[0].request.body.transition.id=="20" and .entries[0].proposal.payload.to.id=="3"' "$jira_dir/ledger.json"
      check 'T24 allowed transition sends once' test "$(call_count 'POST */transitions *')" = "$((before+1))"
    else
      expected=conflict; [[ $mode != already-target ]] || expected=verified
      jq_check "T24 $mode stops before transition POST" ".entries[0].state==\"$expected\"" "$jira_dir/ledger.json"
      check 'T24 disappeared or already-target transition sends zero' test "$(call_count 'POST */transitions *')" = "$before"
    fi
  )
done
(
  review_boot apply
  export JIRA_REQUEST_LOG="$jira_work/requests.jsonl"
  printf '[]\n' > "$jira_work/no-evidence.json"
  routine_jira_duplicate_search ABC 'artist ") AND secret ~ path' "$jira_work/no-evidence.json" "$jira_work/search.json"
  expected='project = "ABC" AND summary ~ "\"artist \\\") AND secret ~ path\""'
  jq_check 'T61 exact production summary query keeps quote, parenthesis, AND and tilde inside data' '[.[]|select(.path=="/rest/api/3/search/jql")|.body.jql]|index($expected)!=null' --arg expected "$expected" -s "$JIRA_REQUEST_LOG"
  create=$(cat "$sandbox/create-proposal.json")
  routine_jira_approve "$create" "$sandbox/create-source.json" false
  id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
  routine_jira_apply_one "$id"
  jq_check 'QH4 preflight reuses persisted prefixless proposal duplicate summary' '[.[]|select(.path=="/rest/api/3/search/jql")|.body.jql]|any(contains("summary ~") and contains("feature implementation")) and all(.[];contains("BACK")|not)' -s "$JIRA_REQUEST_LOG"
  routine_jira_duplicate_search ABC 'new implementation module' "$jira_work/no-evidence.json" "$jira_work/recent-search.json"
  jq_check 'T57 production duplicate request includes recently created current-context issue IDs' 'any(.[];.path=="/rest/api/3/search/jql" and .body.reconcileIssues==[200])' -s "$JIRA_REQUEST_LOG"
)
# All four cross-context states are preserved byte-for-byte in B, then reconciled in A.
(
  review_boot apply
  for n in 1 2 3 4; do
    command jq --arg sha "${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}${n}" '.git[0].sha=$sha|.errors=[]' "$sandbox/raw.json" > "$jira_work/site-raw.json"
    review_context "$jira_work/site-raw.json" "$jira_work/context.json"; review_proposals "$jira_work/context.json" "$jira_work/source.json"
    routine_jira_approve "$(command jq -c '.proposals[]|select(.kind=="comment")' "$jira_work/source.json")" "$jira_work/source.json" false
  done
  command jq --arg now "$(routine_jira_now)" '.entries[1].state="applying"|.entries[1].attempts=[{id:"a-dead",pid:999999,lstart:"dead",started_at:$now}]|.entries[2].state="unknown"|.entries[2].attempts=[{id:"a-unknown",pid:999999,lstart:"dead",started_at:$now,outcome:"unknown"}]|.entries[3].state="applied"|.entries[3].result={comment_id:"2"}' "$jira_dir/ledger.json" > "$jira_work/states.json"; routine_jira_store "$jira_work/states.json" "$jira_dir/ledger.json"
  command jq --slurpfile ledger "$jira_dir/ledger.json" --arg now "$(routine_jira_now)" '.comments=[($ledger[0].entries[1]|{id:"1",body:.request.body.body,author:{accountId:.account_id},created:$now,property:.request.body.properties[0].value}),($ledger[0].entries[3]|{id:"2",body:.request.body.body,author:{accountId:.account_id},created:$now,property:.request.body.properties[0].value})]' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
  cp "$jira_dir/ledger.json" "$jira_work/site-a.json"
  before=$(wc -l < "$JIRA_EFFECTS")
  ROUTINE_SETTINGS=$(command jq -c '.jira.site="https://other.atlassian.net"' <<< "$ROUTINE_SETTINGS"); jira_site=https://other.atlassian.net
  command jq '.questions=["old-site question"]|.notices=["old-site notice"]' "$sandbox/base-proposals.json" > "$jira_work/site-proposals.json"; routine_jira_store "$jira_work/site-proposals.json" "$proposal_file"
  status=$(routine_jira_status)
  [[ $status == 'Jira 동기화: 제안 0 · 승인 대기 0 · 결과 불명 0 · 다른 사이트 4 · 질문 0 · 알림 0' ]] || fail 'T64 cached other-site questions and notices leaked into current status'
  routine_jira_authenticate; routine_jira_apply_locked
  check 'T64 A approved/applying/unknown/applied preserved unchanged in B' cmp "$jira_work/site-a.json" "$jira_dir/ledger.json"
  check 'T64 B has no writes or effects' test "$(wc -l < "$JIRA_EFFECTS")" = "$before"
  ROUTINE_SETTINGS=$(command jq -c '.jira.site="https://example.atlassian.net"' <<< "$ROUTINE_SETTINGS"); jira_site=https://example.atlassian.net
  routine_jira_authenticate; routine_jira_apply_locked
  jq_check 'T64 A return processes approved/applying/applied while retaining absent unknown' '[.entries[].state]==["verified","verified","unknown","verified"]' "$jira_dir/ledger.json"
)
for kind in transition fill_description; do
  (
    review_boot apply
    if [[ $kind == transition ]]; then proposal=$(command jq -c '.proposals[]|select(.kind=="transition")' "$sandbox/base-proposals.json"); else proposal=$(cat "$sandbox/fill-proposal.json"); fi
    routine_jira_approve "$proposal" "$sandbox/base-proposals.json" false
    id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
    before=$(wc -l < "$JIRA_EFFECTS")
    if [[ $kind == transition ]]; then writes=$(call_count 'POST */transitions *'); else writes=$(call_count 'PUT *'); fi
    export JIRA_EFFECT=0 JIRA_WRITE_EXIT=28
    routine_jira_apply_one "$id"; unset JIRA_WRITE_EXIT
    routine_jira_reconcile "$id"
    jq_check "T70 delayed $kind first adjustment is unknown" '.entries[0].state=="unknown"' "$jira_dir/ledger.json"
    if [[ $kind == transition ]]; then command jq '.issue.fields.status={id:"3",statusCategory:{key:"indeterminate"}}' "$JIRA_SERVER" > "$JIRA_SERVER.new"
    else command jq --argjson proposal "$proposal" --arg now "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg account "$jira_account" '
      .issue.fields.description=$proposal.payload.adf|.issue.fields.updated=$now|
      .history += [{created:$now,author:{accountId:$account},items:[{field:"description"}]}]' "$JIRA_SERVER" > "$JIRA_SERVER.new"; fi
    mv "$JIRA_SERVER.new" "$JIRA_SERVER"
    printf '%s\n' "$kind delayed effect" >> "$JIRA_EFFECTS"
    routine_jira_reconcile "$id"
    jq_check "T70 delayed $kind next read is verified without resend" '.entries[0].state=="verified"' "$jira_dir/ledger.json"
    check 'T70 delayed reconciliation observes exactly one server effect' test "$(wc -l < "$JIRA_EFFECTS")" -eq "$((before+1))"
    jq_check 'T70 one attempt only' '.entries[0].attempts|length==1' "$jira_dir/ledger.json"
    if [[ $kind == transition ]]; then count=$(call_count 'POST */transitions *'); else count=$(call_count 'PUT *'); fi
    check 'T70 delayed transport attempted exactly once' test "$count" = "$((writes+1))"
  )
done
# Independent approved fill IDs are produced from two genuine, distinct empty-body snapshots.
(
  review_boot review
  routine_jira_approve "$(cat "$sandbox/fill-proposal.json")" "$sandbox/base-proposals.json" false
  first=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
  jq -L "$share_dir" 'include "jira"; .issue.fields.description=("확인사항\n작업 내용\n완료 조건\n관련 링크"|jira_text_adf)' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
  review_context "$sandbox/raw.json" "$jira_work/context.json"; review_proposals "$jira_work/context.json" "$jira_work/alternate.json"
  alternate=$(command jq -c '.proposals[]|select(.kind=="fill_description")' "$jira_work/alternate.json")
  routine_jira_approve "$alternate" "$jira_work/alternate.json" false
  jq_check 'T70 alternate fill was independently approved before the crash' '(.entries|length)==2 and ([.entries[].proposal_id]|unique|length)==2 and all(.entries[];.state=="approved")' "$jira_dir/ledger.json"
  cp "$jira_work/alternate.json" "$sandbox/review-alternate-source.json"
  printf '%s\n' "$first" > "$sandbox/review-crash-id"
  cp "$sandbox/server-initial.json" "$JIRA_SERVER"
)
before=$(call_count 'PUT *')
if JIRA_CRASH=after /bin/bash "$sandbox/crash-client.sh" "$(cat "$sandbox/review-crash-id")"; then fail 'T70 independent-fill crash did not interrupt'; fi
jq -L "$share_dir" 'include "jira"; .issue.fields.description=("사전조건\n증상\n재현 방법\n확인사항"|jira_text_adf)' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
(
  ROUTINE_SETTINGS=$(command jq -c '.draft.llm.engine="omp"' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  "$repo/bin/jira-propose"
  jq_check 'T70 crash plus human template change emits no new fill' 'all(.proposals[];.kind!="fill_description")' "$proposal_file"
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate
  alternative=$(command jq -r '.entries[]|select(.state=="approved")|.entry_id' "$jira_dir/ledger.json")
  routine_jira_apply_one "$alternative"
  jq_check 'T70 distinct previously approved fill is blocked by permanent attempt marker' '.entries|any(.state=="blocked" and .kind=="fill_description")' "$jira_dir/ledger.json"
  alternative_proposal=$(command jq -c '.proposals[]|select(.kind=="fill_description")' "$sandbox/review-alternate-source.json")
  routine_jira_approve "$alternative_proposal" "$sandbox/review-alternate-source.json" false
  jq_check 'T70 marker also blocks a fresh review of the distinct inactive fill ID' '(.entries|length)==2 and (.markers|map(select(.kind=="fill"))|length)==1' "$jira_dir/ledger.json"
  check 'T70 exactly one PUT across crash and other approved fill' test "$(call_count 'PUT *')" = "$((before+1))"
)
(
  review_boot apply
  # A guard that becomes false only at send must be a definite pre-network cancellation.
  routine_jira_approve "$(cat "$sandbox/fill-proposal.json")" "$sandbox/base-proposals.json" false
  id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
  ui_interactive() { ! command jq -e 'any(.entries[];.state=="applying")' "$jira_dir/ledger.json" >/dev/null; }
  before=$(call_count 'PUT *')
  routine_jira_apply_one "$id" || true
  jq_check 'QH2/QL6 pre-send terminal loss is approved/not_sent with no fill marker' '.entries[0].state=="approved" and .entries[0].attempts[-1].outcome=="not_sent" and .markers==[]' "$jira_dir/ledger.json"
  check 'QH2 no transport at guard failure' test "$(call_count 'PUT *')" = "$before"
)
(
  review_boot apply
  check 'QH2 interactive session has no propose-wide deadline' test "$jira_deadline" -eq 0
  jira_deadline=$(($(date +%s)-1)); before=$(wc -l < "$JIRA_CALLS")
  if routine_jira_curl GET /rest/api/3/myself '' "$jira_work/expired.json"; then fail 'QH2 expired request accepted'; else [[ $? == 3 ]] || fail 'QH2 deadline signal'; fi
  check 'QH2 expired request never reaches curl' test "$(wc -l < "$JIRA_CALLS")" = "$before"
  check 'QH2 deadline classified before network' test "$jira_stop_reason" = deadline
  jira_deadline=0
  create=$(cat "$sandbox/create-proposal.json")
  routine_jira_preview "$create" "$sandbox/create-source.json" > "$jira_work/preview"
  jq_check 'QH5 creation preview includes exact title/project/type/assignee' 'contains("[BACK] feature implementation") and contains("프로젝트: ABC") and contains("유형: 작업 (10)") and contains("담당자: 나")' -Rs "$jira_work/preview"
  command jq '.issue.fields.summary="bad\u001b[31m\u0007\u202e summary"' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
  routine_jira_fetch_issue ABC-1 "$jira_work/issue.json"
  jq -L "$share_dir" --arg hash "$jira_fetched_hash" 'include "jira"; jira_issue("ABC-1";"fixture-account";$hash;[];{comments:"ok",changelog:"ok",transitions:"ok"})' "$jira_work/issue.json" > "$jira_work/normalized.json"
  jq_check 'QM2 no terminal control bytes survive normalized display' '.summary|contains("\u001b")|not' "$jira_work/normalized.json"
  jq_check 'QM2 original ADF hash semantics remain separate from display' '.summary|contains("\u0007")|not' "$jira_work/normalized.json"
  jq_check 'QM6 numeric timezone comparison respects actual time' 'include "jira"; ("2026-10-08T09:00:00.000+0900"|jira_epoch)==("2026-10-08T00:00:00Z"|jira_epoch)' <<< null
)
for scenario in fractional-race fractional-normal; do
  (
    review_boot apply
    command jq '.issue.fields.updated="2026-10-08T00:00:00.100+0000"' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
    review_context "$sandbox/raw.json" "$jira_work/fractional-context.json"
    review_proposals "$jira_work/fractional-context.json" "$jira_work/fractional-proposals.json"
    proposal=$(command jq -c '.proposals[]|select(.kind=="fill_description")' "$jira_work/fractional-proposals.json")
    routine_jira_approve "$proposal" "$jira_work/fractional-proposals.json" false
    id=$(command jq -r '.entries[0].entry_id' "$jira_dir/ledger.json")
    jq_check 'F9 production approval preserves fractional snapshot' '.entries[0].snapshot.updated=="2026-10-08T00:00:00.100+0000"' "$jira_dir/ledger.json"
    expected=verified
    export JIRA_WRITE_AT='2026-10-08T00:00:00.900Z'
    if [[ $scenario == fractional-race ]]; then
      export JIRA_RACE=1 JIRA_RACE_AT='2026-10-08T00:00:00.500+0000' JIRA_WRITE_AT='2026-10-08T00:00:01.100+0000'
      expected=verify_failed
    fi
    before=$(call_count 'PUT *'); effects=$(wc -l < "$JIRA_EFFECTS")
    check "F9 production $scenario apply" routine_jira_apply_one "$id" > "$jira_work/fractional-output"
    jq_check "F9 $scenario validates same-second history" ".entries[0].state==\"$expected\" and (.entries[0].attempts|length)==1 and .markers[0].confirmed" "$jira_dir/ledger.json"
    if [[ $scenario == fractional-race ]]; then
      jq_check 'F9 fractional race visibly reports URL and manual restoration' 'contains("https://example.atlassian.net/browse/ABC-1") and contains("이슈 기록에서 이전 본문 확인·복구")' -Rs "$jira_work/fractional-output"
    fi
    if routine_jira_apply_one "$id"; then fail 'F9 verified or raced fill accepted a second apply'; fi
    check 'F9 fractional fill sends exactly once with no automatic restoration' test "$(call_count 'PUT *')" -eq "$((before+1))"
    check 'F9 fractional fill has exactly one server effect' test "$(wc -l < "$JIRA_EFFECTS")" -eq "$((effects+1))"
  )
done
jq_check 'F9 fractional timestamps preserve timezone equivalence and seconds-based windows' 'include "jira";
  ("2026-10-08T09:00:00.100+0900"|jira_epoch)==("2026-10-08T00:00:00.100Z"|jira_epoch) and
  ("2026-10-07T15:00:00.100-09:00"|jira_epoch)==("2026-10-08T00:00:00.100+0000"|jira_epoch) and
  (("2026-10-08T00:00:00.900Z"|jira_epoch)-("2026-10-08T00:00:00.100Z"|jira_epoch)>0.7) and
  (("2026-10-08T00:00:00.100Z"|jira_epoch)-300)==("2026-10-07T23:55:00.100Z"|jira_epoch)' <<< null
echo 'PASS: Jira F9 동일 초 경쟁 감지·밀리초 정상 PUT·타임존·초 단위 조정 창'
(
  review_boot apply
  routine_jira_approve "$(command jq -c '.proposals[]|select(.kind=="comment")' "$sandbox/base-proposals.json")" "$sandbox/base-proposals.json" false
  command jq '.entries=[.entries[0],.entries[0],(.entries[0]|.state="unknown"),(.entries[0]|.state="applying"),(.entries[0]|.site="https://other.atlassian.net") ]' "$jira_dir/ledger.json" > "$jira_work/counts.json"; routine_jira_store "$jira_work/counts.json" "$jira_dir/ledger.json"
  command jq '.proposals=.proposals[0:2]|.questions=["fixture question"]|.notices=["fixture notice"]' "$sandbox/base-proposals.json" > "$jira_work/status-proposals.json"; routine_jira_store "$jira_work/status-proposals.json" "$proposal_file"
  before=$(wc -l < "$JIRA_CALLS")
  status=$("$repo/bin/routine" status)
  [[ $status == *'Jira 동기화: 제안 2 · 승인 대기 2 · 결과 불명 2 · 다른 사이트 1 · 질문 1 · 알림 1 — 확인 URL·닫기: routine jira close'* ]] || fail 'T78 exact status counts'
  check 'T78 cached status performs zero network' test "$(wc -l < "$JIRA_CALLS")" = "$before"
  printf '{broken\n' > "$proposal_file"; printf '{broken\n' > "$jira_dir/ledger.json"
  status=$("$repo/bin/routine" status)
  [[ $status == *'형식 오류'* && $status == *'전달 방식:'* ]] || fail 'QL1 corrupt Jira files broke ordinary status'
)
# Real editor reads and writes its terminal while a second selected item still receives approval.
(
  review_boot review
  command jq --slurpfile fill "$sandbox/fill-proposal.json" '.proposals=($fill+[.proposals[]|select(.kind=="comment")])' "$sandbox/base-proposals.json" > "$jira_work/multiple.json"; routine_jira_store "$jira_work/multiple.json" "$proposal_file"
)
before=$(wc -l < "$JIRA_EFFECTS")
/usr/bin/expect "$repo/tests/fixtures/jira/pty.exp" "$sandbox/pty-wrapper.sh" "$sandbox/multi-editor.log" multi-edit review
jq_check 'QH3 editor terminal and fd3 leave both selected items approved' '(.entries|length)==2 and all(.entries[];.state=="approved") and any(.entries[];.edited==true) and any(.entries[];.kind=="comment")' "$JIRA_LEDGER"
check 'QH3 editor stdout never corrupts proposal JSON or causes a write' test "$(wc -l < "$JIRA_EFFECTS")" = "$before"
# shellcheck source=review-retention.sh
source "$repo/tests/fixtures/jira/review-retention.sh"
echo 'PASS: Jira 실제 send 상태행렬·ledger 변조·JQL 요청·4상태 사이트 격리·독립 fill 종료 경계·PTY 편집'
