#!/usr/bin/env bash
# Optional, explicit smoke: gum alone is real; app/install/model commands are stubs.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
gum_bin=${REAL_GUM_BIN:-$(type -P gum || true)}
if [[ -z $gum_bin || ! -x $gum_bin ]]; then echo 'SKIP: 실제 gum 바이너리 없음'; exit 0; fi
real_jq=${TEST_JQ_BIN:-$(type -P jq)}
while IFS= read -r name; do [[ $name != ROUTINE_* && $name != GUM_* ]] || unset "$name"; done < <(compgen -v)
sandbox=$(mktemp -d /tmp/routine-real-gum.XXXXXXXX)
sandbox=$(cd -- "$sandbox" && pwd -P)
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" PATH="$sandbox/stubs:/usr/bin:/bin" USER=fixture
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export ROUTINE_CONFIG="$HOME/.config/routine-automation/config.json" ROUTINE_APPLICATIONS_DIR="$sandbox/apps"
export GUARD_RECORD="$sandbox/external.calls" REAL_GUM_SHARE="$repo/share"
unset NO_COLOR BASH_ENV
mkdir -p "$sandbox/stubs" "$TMPDIR" "$ROUTINE_APPLICATIONS_DIR" "$HOME/Documents/GitHub/repo" "$HOME/.omp/agent/sessions"
ln -s "$real_jq" "$sandbox/stubs/jq"
ln -s "$gum_bin" "$sandbox/stubs/gum"
for cmd in brew launchctl open osascript orca claude omp gh; do
  cat > "$sandbox/stubs/$cmd" <<'STUB'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >> "$GUARD_RECORD"
exit 87
STUB
  chmod +x "$sandbox/stubs/$cmd"
done
cat > "$sandbox/stubs/gtimeout" <<'TIMEOUT'
#!/bin/bash
shift 3
exec "$@"
TIMEOUT
chmod +x "$sandbox/stubs/gtimeout"
/usr/bin/git init -q "$HOME/Documents/GitHub/repo"
roots=$(jq -nc --arg root "$HOME/Documents/GitHub" '[$root]')
"$repo/bin/routine-init" --non-interactive --slack-link https://example.slack.com/archives/CEXAMPLE/p1790895609247049 --slack-team-id TEXAMPLE --identity-git-authors '["fixture@example.com"]' --sources-git-roots "$roots" --sources-prs-enabled false --draft-llm-engine none --timezone Asia/Seoul > /dev/null
cp "$ROUTINE_CONFIG" "$sandbox/original.json"
cat > "$sandbox/command" <<'COMMAND'
#!/bin/bash
stty rows 30 cols "${REAL_GUM_COLUMNS:-110}"
before=$(stty -g)
source "$REAL_GUM_SHARE/ui.sh"
ui_confirm '버튼 대비 확인'
"$@"
rc=$?
after=$(stty -g)
[[ $before != "$after" ]] || echo 'TTY_RESTORED=1'
printf 'PTY_RC=%s\n' "$rc"
COMMAND
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
if [[ -n ${REAL_GUM_SHOTS:-} ]]; then mkdir -p "$REAL_GUM_SHOTS"; fi
args=(--skip platform --skip dependencies --skip github --skip llm --skip slack --skip orca --skip disk-access --skip launchd --skip first-run --overwrite-config --slack-channel-name pending-change)
for mode in color no-color narrow success; do
  cp "$sandbox/original.json" "$ROUTINE_CONFIG"
  export REAL_GUM_COLUMNS=110
  export REAL_GUM_CAPTURE=0 REAL_GUM_SUCCESS=0
  [[ $mode != success ]] || REAL_GUM_SUCCESS=1
  [[ $mode != color && $mode != success ]] || REAL_GUM_CAPTURE=1
  [[ $mode != narrow ]] || REAL_GUM_COLUMNS=60
  if [[ $mode == no-color ]]; then export NO_COLOR=1; else unset NO_COLOR; fi
  /usr/bin/expect "$repo/tests/fixtures/real-gum-pty.exp" "$sandbox/command" "$sandbox/$mode.tty" "$repo/bin/routine-setup" "${args[@]}" > /dev/null || { cat "$sandbox/$mode.tty" >&2; fail '실제 gum PTY 구동'; }
  if [[ $mode == success ]]; then
    jq -e '.slack.channel_name=="pending-change"' "$ROUTINE_CONFIG" >/dev/null || fail '최종 저장 값이 반영되지 않음'
  else cmp -s "$sandbox/original.json" "$ROUTINE_CONFIG" || fail '최종 취소가 설정 파일을 변경함'; fi
  jq -Rsf "$repo/tests/terminal-screen.jq" "$sandbox/$mode.tty" > "$sandbox/$mode.screen"
  jq -L "$repo/tests" --arg mode "$mode" -e '
    include "setup-screen";
    setup_once and
    any(setup_rows[];.label=="설정 저장" and .marker==(if $mode=="success" then "✓" else "✗" end)) and
    all(.[];test("스크럼 글 링크|Git 저장소 위치 \\(Space|수집 소스 선택 \\(Space|│  *(워크스페이스|채널|표시 이름|글 제목|git 작성자|Git 위치|수집 소스|LLM|전달 방식|예약 시각)")|not)' "$sandbox/$mode.screen" >/dev/null || fail '이전 질문/요약 잔여 또는 최종 체크리스트 중복/저장 상태 오류'
  jq -Rse --arg rc "$([[ $mode == success ]] && echo 0 || echo 1)" 'gsub("\u001b\\[[0-9;]*m";"")|contains("설정 1/4 · Slack 글 링크") and contains("설정 2/4 · Git 저장소 위치") and contains("설정 3/4 · 수집 소스") and contains("설정 4/4 · 확인") and contains("PTY_RC="+$rc) and contains("TTY_RESTORED=1")' "$sandbox/$mode.tty" >/dev/null || fail '단계 전환·최종 종료/TTY 복원 오류'
  if [[ $mode == no-color ]]; then
    jq -Rse '[match("\u001b\\[[0-9;]*m";"g")]|length==0' "$sandbox/$mode.tty" >/dev/null || fail 'NO_COLOR에서 SGR 색 코드 출력'
  elif [[ $mode == color ]]; then
    jq -Rse 'test("\u001b\\[[0-9;]*m╭")' "$sandbox/$mode.tty" >/dev/null || fail 'gum style 박스의 테두리 색 프로필이 사라짐'
    jq -Rsr 'split("저장 전 최종 확인")[0]' "$sandbox/$mode.tty" > "$sandbox/review.tty"
    jq --argjson cell_screen true -Rsf "$repo/tests/terminal-screen.jq" "$sandbox/review.tty" > "$sandbox/review.cells"
    jq -e '[.[]|[to_entries[]|select(.value=="│")|.key]|select(length==3)|.[1]]|group_by(.)|length==1' "$sandbox/review.cells" >/dev/null || fail '실제 요약 카드의 라벨/값 구분선 셀 열이 일치하지 않음'
    # lipgloss may emit background and foreground in separate SGR sequences.
    # Assert their active state on the label, not one particular escape layout.
    jq -Rse '
      reduce scan("\u001b\\[[0-9;]*m|[^\u001b]+";"s") as $part
        ({fg:null,bg:null,bold:false,spans:[]};
        if $part|startswith("\u001b[") then
          ($part|ltrimstr("\u001b[")|rtrimstr("m")|
           split(";")|map(if .=="" then 0 else tonumber end)) as $codes |
          .skip=0 | reduce range(0;$codes|length) as $i (.;
            if $i<.skip then .
            elif $codes[$i]==0 then .fg=null|.bg=null|.bold=false
            elif $codes[$i]==1 then .bold=true
            elif $codes[$i]==22 then .bold=false
            elif ($codes[$i]==38 or $codes[$i]==48) then
              (if $codes[$i+1]==5 then $codes[$i+2] else "rgb" end) as $color |
              if $codes[$i]==38 then .fg=$color else .bg=$color end |
              .skip=($i+if $codes[$i+1]==5 then 3 else 5 end)
            elif $codes[$i]==39 then .fg=null
            elif $codes[$i]==49 then .bg=null
            elif ($codes[$i]>=30 and $codes[$i]<=37) or ($codes[$i]>=90 and $codes[$i]<=97) then .fg=$codes[$i]
            else . end)
        else .spans+=[{text:$part,fg:.fg,bg:.bg,bold:.bold}] end) |
      any(.spans[];.fg==231 and .bg==25 and .bold and (.text|contains("예"))) and
      any(.spans[];.fg==252 and .bg==237 and (.text|contains("아니요")))' "$sandbox/$mode.tty" >/dev/null || fail 'confirm 버튼의 글자/배경 대비가 사라짐'
  fi
done
if [[ -n ${REAL_GUM_SHOTS:-} ]]; then
  cat > "$sandbox/static-command" <<'STATIC'
#!/bin/bash
stty rows 30 cols 110
surface=$1; share=$2; routine=$3
source "$share/ui.sh"
case $surface in
  stage-header)
    ui_stage_counter="$TMPDIR/banner.rows"
    printf '0\n' > "$ui_stage_counter"
    ui_stage 2 4 'Git 저장소 위치'
    [[ $(cat "$ui_stage_counter") == 3 ]] || exit 1 ;;
  warning-box)
    ui_note '저장 전 확인 필요' 'git 작성자가 비어 있습니다.
항목 고치기로 수정하세요. 입력한 값은 그대로 유지됩니다.' warning ;;
  routine-sources) "$routine" sources ;;
esac
printf 'STATIC_RC=%s\n' "$?"
STATIC
  for surface in stage-header warning-box routine-sources; do
    REAL_GUM_CAPTURE=1 REAL_GUM_STATIC=$surface /usr/bin/expect "$repo/tests/fixtures/real-gum-pty.exp" "$sandbox/static-command" "$sandbox/$surface.tty" "$surface" "$repo/share" "$repo/bin/routine" > /dev/null || fail '추가 UI 시각 증거 캡처'
  done
fi
if [[ -f $GUARD_RECORD ]]; then
  jq -Rse 'all(split("\n")[]|select(length>0);startswith("gh auth status"))' "$GUARD_RECORD" >/dev/null || fail '불필요한 외부 앱/설치/LLM 명령 호출'
fi
echo 'PASS: 실제 gum 저장/취소·정렬된 요약 셀·한글 체크리스트 1벌+결과·질문/요약 정리·NO_COLOR·TTY 복원'
