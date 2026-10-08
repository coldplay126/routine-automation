#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2016,SC2030,SC2031 # Isolated fixtures; literal jq programs.
(
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate
  command jq .base "$repo/tests/fixtures/jira/bodies/semantic-diff.json" > "$jira_work/base.json"
  baseline=$(routine_jira_adf_hash "$jira_work/base.json")
  while IFS= read -r variant; do
    command jq --argjson variant "$variant" 'setpath($variant.path;$variant.value)' "$jira_work/base.json" > "$jira_work/variant.json"
    check 'T38 semantic body difference affects hash' test "$(routine_jira_adf_hash "$jira_work/variant.json")" != "$baseline"
  done < <(command jq -c '.variants[]' "$repo/tests/fixtures/jira/bodies/semantic-diff.json")
  check 'T38 localId ignored by canonical hash' test "$(routine_jira_adf_hash "$repo/tests/fixtures/jira/bodies/nonsemantic-attrs.json")" = "$baseline"
  # shellcheck disable=SC2329 # Called indirectly by the production hash helper.
  shasum() { echo hash >> "$JIRA_SHASUM_CALLS"; /usr/bin/shasum "$@"; }
  export JIRA_SHASUM_CALLS="$sandbox/shasum-calls"
  printf '[{"ref":"one","input":["한국어","quote\\\"","line\\n"]},{"ref":"two","input":["work","a","b"]}]\n' > "$jira_work/ids.json"
  routine_jira_hash_map "$jira_work/ids.json" > "$jira_work/ids-hashed.json"
  check 'T82 exactly one shasum per batch' test "$(wc -l < "$JIRA_SHASUM_CALLS")" -eq 1
)
for mode in semantic nonsemantic; do
  (
    cp "$sandbox/server-initial.json" "$JIRA_SERVER"
    routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
    routine_jira_approve "$(cat "$sandbox/fill-proposal.json")" "$proposal_file" false
    id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
    export JIRA_ADF_MODE=$mode
    routine_jira_apply_one "$id"
    if [[ $mode == semantic ]]; then expected=verify_failed; else expected=verified; fi
    jq_check "T38 real PUT response $mode" ".entries[0].state==\"$expected\"" "$jira_dir/ledger.json"
  )
done
for variant in late forbidden double wrong-body; do
  (
    cp "$sandbox/server-initial.json" "$JIRA_SERVER"
    routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
    comment=$(command jq -c '.proposals[]|select(.kind=="comment")' "$sandbox/base-proposals.json")
    routine_jira_approve "$comment" "$sandbox/base-proposals.json" false
    id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
    export JIRA_WRITE_EXIT=28
    routine_jira_apply_one "$id"; unset JIRA_WRITE_EXIT
    before=$(call_count 'POST /rest/api/3/issue/ABC-1/comment *')
    case $variant in
      late|forbidden)
        export JIRA_ROUTES="$jira_work/properties.json"
        code=404; [[ $variant != forbidden ]] || code=403
        command jq -n --argjson code "$code" '[{method:"GET",prefix:"/rest/api/3/comment/1/properties",http:$code,body:{}}]' > "$JIRA_ROUTES"
        routine_jira_reconcile "$id" || true
        jq_check 'T50 missing/forbidden marker remains unknown' '.entries[0].state=="unknown"' "$jira_dir/ledger.json"
        if [[ $variant == late ]]; then unset JIRA_ROUTES; routine_jira_reconcile "$id"; jq_check 'T50 late marker verified' '.entries[0].state=="verified"' "$jira_dir/ledger.json"; fi ;;
      double)
        command jq '.comments+=[.comments[0]|.id="2"]' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
        routine_jira_reconcile "$id"; jq_check 'T50 double marker fails verification' '.entries[0].state=="verify_failed"' "$jira_dir/ledger.json" ;;
      wrong-body)
        command jq '.comments[0].body.content[0].content[0].text="human edit"' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
        routine_jira_reconcile "$id"; jq_check 'T50 marked body mismatch' '.entries[0].state=="verify_failed"' "$jira_dir/ledger.json" ;;
    esac
    check 'T50 property reconciliation never resends' test "$(call_count 'POST /rest/api/3/issue/ABC-1/comment *')" = "$before"
  )
done
for age in 91 89-self 89-other; do
  (
    cp "$sandbox/server-initial.json" "$JIRA_SERVER"
    routine_jira_session; routine_jira_lock apply; routine_jira_authenticate; reset_jira_ledger
    printf '{"version":1,"links":[],"rejections":[]}\n' > "$jira_work/empty-links.json"; routine_jira_store "$jira_work/empty-links.json" "$jira_dir/links.json"
    routine_jira_approve "$(cat "$sandbox/fill-proposal.json")" "$sandbox/base-proposals.json" false
    id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json"); routine_jira_apply_one "$id"
    days=89; [[ $age != 91 ]] || days=91
    at=$(date -u -v-"${days}"d '+%Y-%m-%dT%H:%M:%SZ')
    command jq --arg at "$at" '.markers[0].at=$at' "$jira_dir/ledger.json" > "$jira_work/age.json"; routine_jira_store "$jira_work/age.json" "$jira_dir/ledger.json"
  )
  if [[ $age == 89-self ]]; then description='{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"my additional content"}]}]}'
  else description='{"type":"doc","content":[]}'; fi
  command jq --argjson description "$description" '.issue.fields.description=$description' "$JIRA_SERVER" > "$JIRA_SERVER.new"; mv "$JIRA_SERVER.new" "$JIRA_SERVER"
  (
    export JIRA_RAW="$sandbox/empty-raw.json"
    before_issue=$(call_count 'GET *?fields=*'); before_history=$(call_count 'GET */changelog?*'); before_write=$(call_count 'PUT *')
    "$repo/bin/jira-propose" --no-llm
    expected=1; [[ $age != 91 ]] || expected=0
    jq_check "T42 first fill notice $age" "(.notices|length)==$expected and all(.proposals[];.kind!=\"fill_description\")" "$proposal_file"
    "$repo/bin/jira-propose" --no-llm
    jq_check 'T42 second fill notice suppressed' '(.notices|length)==0 and all(.proposals[];.kind!="fill_description")' "$proposal_file"
    check 'T42 fill notices need no changelog' test "$(call_count 'GET */changelog?*')" = "$before_history"
    check 'T42 fill notices do not re-PUT' test "$(call_count 'PUT *')" = "$before_write"
    if [[ $age == 91 ]]; then check 'T42 permanent old marker needs no issue read' test "$(call_count 'GET *?fields=*')" = "$before_issue"
    else check 'T42 exactly two recent-marker GET issue reads' test "$(call_count 'GET *?fields=*')" = "$((before_issue+2))"; fi
    jq_check 'T42 fill marker permanent after retention' '.markers|length==1 and .[0].kind=="fill" and .[0].confirmed' "$JIRA_LEDGER"
  )
done
echo 'PASS: Jira 정규형 본문·늦은 댓글 표지·89/91일 채우기 알림 통합 (W008/W011b)'
# Real collection over seven days, still confined to a repository inside the stub HOME.
mkdir -p "$sandbox/repos/example/subdir" "$sandbox/outside"
/usr/bin/git init -q "$sandbox/repos/example"
/usr/bin/git -C "$sandbox/repos/example" config user.name Fixture
/usr/bin/git -C "$sandbox/repos/example" config user.email fixture@example.com
/usr/bin/git -C "$sandbox/repos/example" config remote.origin.url https://github.com/example/example.git
printf old > "$sandbox/repos/example/changes"; /usr/bin/git -C "$sandbox/repos/example" add changes
GIT_AUTHOR_DATE='2026-09-30T00:00:00Z' GIT_COMMITTER_DATE='2026-09-30T00:00:00Z' /usr/bin/git -C "$sandbox/repos/example" commit -qm 'eight days ago'
printf recent >> "$sandbox/repos/example/changes"; /usr/bin/git -C "$sandbox/repos/example" add changes
GIT_AUTHOR_DATE='2026-10-02T00:00:00Z' GIT_COMMITTER_DATE='2026-10-02T00:00:00Z' /usr/bin/git -C "$sandbox/repos/example" commit -qm 'six days ago'
(
  ROUTINE_SETTINGS=$(command jq -c --arg root "$sandbox/repos" '.sources.git.roots=[$root]|.identity.git_authors=["fixture@example.com"]' <<< "$ROUTINE_SETTINGS"); routine_save_config "$ROUTINE_SETTINGS"
  export JIRA_REAL_COLLECT=1
  "$repo/bin/scrum-collect" --since 2026-10-01 --until 2026-10-08T12:00:00Z --sources git --out "$sandbox/real-collect" >/dev/null
  jq_check 'T14 real collector includes six not eight days ago' '(.git|length)==1 and .git[0].subject=="six days ago"' "$sandbox/real-collect/2026-10-08.json"
  routine_jira_session; routine_jira_lock propose
  command jq -n --arg inside "$sandbox/repos/example/subdir" --arg outside "$sandbox/outside" '{sessions:[{cwd:$inside},{cwd:$outside}]}' > "$jira_work/cwds.json"
  routine_jira_cwd_repos "$jira_work/cwds.json" > "$jira_work/cwd-map.json"
  jq_check 'T10 shell repository adapter inside/outside' ".[\"$sandbox/repos/example/subdir\"]==\"example\" and .[\"$sandbox/outside\"]==null" "$jira_work/cwd-map.json"
)
(
  routine_jira_session; routine_jira_lock propose
  (set -x; routine_jira_authenticate; set +x) 2> "$sandbox/xtrace"
  while IFS= read -r line; do [[ $line != *ATATTfixture* ]] || fail 'T67 token in xtrace'; done < "$sandbox/xtrace"
)
for signal in INT TERM; do
  cat > "$sandbox/signal-test.sh" <<'SCRIPT'
#!/bin/bash
set -euo pipefail
share_dir="$JIRA_SHARE"
source "$share_dir/config.sh"; source "$share_dir/jira.sh"
routine_load_config; routine_jira_session; routine_jira_lock propose; routine_jira_authenticate
printf '%s\n' "$jira_auth" > "$JIRA_AUTH_PATH"
kill -"$1" "$$"
SCRIPT
  export JIRA_SHARE="$share_dir" JIRA_AUTH_PATH="$sandbox/auth-path"
  if /bin/bash "$sandbox/signal-test.sh" "$signal"; then fail 'T67 signal not delivered'; fi
  check 'T67 signal removes token auth file' test ! -e "$(cat "$JIRA_AUTH_PATH")"
done
# Exercise actual text UI in a PTY; gum is deliberately unavailable, not a mocked UI function.
cat > "$sandbox/editor.sh" <<'EDITOR'
#!/bin/bash
[[ -t 0 && -t 1 ]] || exit 97
printf 'EDITOR_TTY_READY: '
IFS= read -r input
[[ $input == editor-input ]] || exit 98
printf '## 확인사항\n## 작업 내용\n- 운영 배포 완료\n## 완료 조건\n## 관련 링크\n' > "$1"
EDITOR
chmod +x "$sandbox/editor.sh"
cat > "$sandbox/pty-wrapper.sh" <<'WRAPPER'
#!/bin/bash
set -uo pipefail
type() { if [[ ${2:-} == gum ]]; then return 1; else builtin type "$@"; fi; }
export -f type
"$JIRA_ROUTINE" jira "$1"
printf 'JIRA_PTY_RC=%s\n' "$?"
WRAPPER
export JIRA_ROUTINE="$repo/bin/routine" EDITOR="$sandbox/editor.sh"
for mode in decline edit-decline approve edit-approve; do
  (
    cp "$sandbox/server-initial.json" "$JIRA_SERVER"
    routine_jira_session; routine_jira_lock apply; reset_jira_ledger
    command jq --slurpfile fill "$sandbox/fill-proposal.json" '.proposals=$fill' "$sandbox/base-proposals.json" > "$jira_work/fill-only.json"; routine_jira_store "$jira_work/fill-only.json" "$proposal_file"
  )
  before=$(call_count 'PUT *')
  check "T73 actual PTY $mode" /usr/bin/expect "$repo/tests/fixtures/jira/pty.exp" "$sandbox/pty-wrapper.sh" "$sandbox/pty-$mode.log" "$mode" review
  if [[ $mode == decline || $mode == edit-decline ]]; then jq_check 'T73 refused final approval has no ledger entry' '.entries|length==0' "$JIRA_LEDGER"
  else jq_check 'T73 terminal approval persists only approved' '(.entries|length)==1 and .entries[0].state=="approved"' "$JIRA_LEDGER"; fi
  if [[ $mode == edit-approve ]]; then jq_check 'T41 edited assertion remains in approved body' '.entries[0].edited and (.entries[0].request.body.fields.description|tostring|contains("운영 배포 완료"))' "$JIRA_LEDGER"; fi
  check 'T73 final apply declined writes zero' test "$(call_count 'PUT *')" = "$before"
done
(
  routine_jira_session; routine_jira_lock apply; routine_jira_authenticate
  id=$(command jq -r .entries[0].entry_id "$jira_dir/ledger.json")
  routine_jira_apply_one "$id"
  jq_check 'T41 edited body sent unchanged and verified' '.entries[0].state=="verified" and .entries[0].edited' "$jira_dir/ledger.json"
  jq_check 'T41 edited assertion reaches server without citations' '.issue.fields.description|tostring|contains("운영 배포 완료")' "$JIRA_SERVER"
)
echo 'PASS: Jira 실제 7일 수집·저장소 어댑터·xtrace/신호 정리·PTY 선택/편집/승인 (W003/W007/W009)'
