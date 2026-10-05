#!/usr/bin/env bash
set -euo pipefail
repo=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
real_jq=${TEST_JQ_BIN:-$(type -P jq)}
sandbox=$(mktemp -d /tmp/routine-release-tests.XXXXXXXX)
trap 'rm -rf -- "$sandbox"' EXIT
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
unset GH_TOKEN GITHUB_TOKEN GH_HOST GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
export HOME="$sandbox/home" TMPDIR="$sandbox/tmp" STUB_ROOT="$sandbox/stubs" RECORD="$sandbox/calls"
export PATH="$STUB_ROOT:/usr/bin:/bin"
mkdir -p "$HOME/.local/bin" "$TMPDIR" "$STUB_ROOT"
ln -s "$real_jq" "$STUB_ROOT/jq"; ln -s "$STUB_ROOT/jq" "$HOME/.local/bin/jq"
# shellcheck source=network.sh
source "$repo/tests/network.sh"
export GH_ACCOUNT="$sandbox/account" GH_STATE="$sandbox/state" GH_NOTES="$sandbox/notes" GH_TITLE="$sandbox/title" GH_ZIP="$sandbox/zip"
printf 'fixture-owner\n' > "$GH_ACCOUNT"
cat > "$STUB_ROOT/git" <<'GIT'
#!/bin/bash
set -euo pipefail
if [[ ${1:-} == -C && ${3:-} == push ]]; then
  [[ ${ALLOW_PUBLISH_STUB:-0} == 1 && ${4:-} == origin && ${5:-} == refs/heads/main:refs/heads/main && ${6:-} == refs/tags/v0.1.1:refs/tags/v0.1.1 ]] || { echo 'forbidden push' >> "$RECORD"; exit 87; }
  root=$2
  (cd "$root" && printf 'refs/heads/main %s refs/heads/main %040d\n' "$(/usr/bin/git rev-parse HEAD)" 0 | "$root/.git/hooks/pre-push" origin https://github.com/coldplay126/routine-automation.git)
  printf 'push\n' >> "$RECORD"
else exec /usr/bin/git "$@"; fi
GIT
cat > "$STUB_ROOT/gh" <<'GH'
#!/bin/bash
set -euo pipefail
if [[ -n ${PREVIEW_CAPTURE:-} ]]; then
  command jq -n --args '$ARGS.positional' -- "$@" > "$PREVIEW_CAPTURE"
  exit 0
fi
[[ ${ALLOW_PUBLISH_STUB:-0} == 1 ]] || { echo 'forbidden gh' >> "$RECORD"; exit 87; }
case "$1 ${2:-}" in
  'api --hostname')
    [[ $3 == github.com ]] || exit 87
    case $4 in
      user) cat "$GH_ACCOUNT" ;;
      repos/coldplay126/routine-automation) printf '1405988374\n' ;;
      repos/coldplay126/routine-automation/releases/tags/v0.1.1)
        [[ $(cat "$GH_STATE") == uploaded ]] || exit 87
        zip=$(cat "$GH_ZIP"); digest=$(shasum -a 256 "$zip"); digest=${digest%% *}
        [[ ${BAD_UPLOAD_DIGEST:-0} == 0 ]] || digest=$(printf '%064d' 0)
        jq -n --rawfile title "$GH_TITLE" --rawfile body "$(cat "$GH_NOTES")" --arg digest "sha256:$digest" --argjson size "$(stat -f %z "$zip")" '
          {draft:true,tag_name:"v0.1.1",name:$title,body:$body,assets:[{name:"routine-automation-0.1.1.zip",state:"uploaded",size:$size,digest:$digest,browser_download_url:"https://github.com/coldplay126/routine-automation/releases/download/v0.1.1/routine-automation-0.1.1.zip"}]}' ;;
      *) exit 87 ;;
    esac ;;
  'auth switch')
    [[ $3 == --hostname && $4 == github.com && $5 == --user ]] || exit 87
    printf '%s\n' "$6" > "$GH_ACCOUNT" ;;
  'release create')
    [[ $3 == v0.1.1 ]] || exit 87
    draft=0; verified=0; notes=''; title=''
    shift 3
    while (($#)); do
      case $1 in
        --draft) draft=1 ;;
        --verify-tag) verified=1 ;;
        --notes-file) notes=$2; shift ;;
        --title) title=$2; shift ;;
        --repo) [[ $2 == coldplay126/routine-automation ]] || exit 87; shift ;;
        --prerelease|--latest=false) ;;
        *) exit 87 ;;
      esac
      shift
    done
    ((draft && verified)) && [[ -f $notes && -n $title ]] || exit 87
    printf '%s' "$notes" > "$GH_NOTES"; printf '%s' "$title" > "$GH_TITLE"
    printf 'draft\n' > "$GH_STATE"; echo draft >> "$RECORD" ;;
  'release upload')
    [[ $3 == v0.1.1 && $(cat "$GH_STATE") == draft && -f $4 && $5 == --repo && $6 == coldplay126/routine-automation ]] || exit 87
    printf '%s' "$4" > "$GH_ZIP"; printf 'uploaded\n' > "$GH_STATE"; echo uploaded >> "$RECORD" ;;
  'release edit')
    [[ $3 == v0.1.1 && $4 == --repo && $5 == coldplay126/routine-automation && $6 == --draft=false && $(cat "$GH_STATE") == uploaded ]] || exit 87
    printf 'published\n' > "$GH_STATE"; echo published >> "$RECORD" ;;
  *) echo 'forbidden gh' >> "$RECORD"; exit 87 ;;
esac
GH
chmod +x "$STUB_ROOT/git" "$STUB_ROOT/gh"
ln -s "$STUB_ROOT/git" "$HOME/.local/bin/git"; ln -s "$STUB_ROOT/gh" "$HOME/.local/bin/gh"
git() { "$STUB_ROOT/git" "$@"; }; gh() { "$STUB_ROOT/gh" "$@"; }
export -f git gh
development="$sandbox/development"
mkdir "$development"
cp -R "$repo/bin" "$repo/share" "$repo/launchd" "$repo/tools" "$development/"
cp "$repo/install.sh" "$repo/uninstall.sh" "$repo/routine 설치.command" "$repo/LICENSE" "$repo/.gitignore" "$repo/README.md" "$repo/설치 방법.txt" "$development/"
printf '0.1.1\n' > "$development/VERSION"
printf "# 변경 내역\n\n## 0.1.1 — 공개 '배포' fixture\n\n- 공개 변경\n\n## 0.1.0 — 이전 버전\n\n- 이전 변경\n" > "$development/CHANGELOG.md"
printf 'hidden-author@example.test\nHIDDEN_RELEASE_VALUE\n' > "$development/.personal-patterns"
git init -q -b main "$development"
printf 'HIDDEN_RELEASE_VALUE\n' > "$development/historical.txt"
git -C "$development" add -A .
git -C "$development" -c user.name=Fixture -c user.email=hidden-author@example.test -c commit.gpgsign=false commit -qm '비공개 과거 fixture'
rm "$development/historical.txt"; git -C "$development" add -u
git -C "$development" -c user.name=Fixture -c user.email=hidden-author@example.test -c commit.gpgsign=false commit -qm '공개 트리 fixture'
public="$sandbox/공개 repo's"
"$development/tools/release.sh" 0.1.1 "$public" > "$sandbox/prepared"
[[ $(git -C "$public" log -1 --format='%an|%ae|%cn|%ce|%s') == 'coldplay126|coldplay126@gmail.com|coldplay126|coldplay126@gmail.com|release 0.1.1' ]] || fail '공개 신원·메시지 실패'
[[ $(git -C "$public" rev-list --all --count) == 1 && $(git -C "$public" cat-file -t v0.1.1) == tag && -x $public/.git/hooks/pre-push ]] || fail '단일 archive 커밋·태그·hook 실패'
[[ $(git -C "$public" rev-parse 'HEAD^{tree}') == "$(git -C "$development" rev-parse 'HEAD^{tree}')" ]] || fail 'archive 트리 불일치'
! grep -q '이전 변경' "$public/dist/release-0.1.1.md" || fail '노트에 다른 버전 포함'
[[ ! -e $RECORD ]] || fail '로컬 준비가 네트워크 명령 실행'
# Consume the copyable command with the actual Bash parser, not another encoder.
iconv -f UTF-8 -t UTF-8 "$sandbox/prepared" >/dev/null || fail '게시 명령 미리보기 UTF-8 손상'
preview=$(grep '^gh release create ' "$sandbox/prepared")
PREVIEW_CAPTURE="$sandbox/preview.json" /bin/bash -c "$preview"
command jq -e --arg title "0.1.1 — 공개 '배포' fixture" --arg notes "$(CDPATH='' cd -P -- "$public" && pwd)/dist/release-0.1.1.md" '
  .[0:3]==["release","create","v0.1.1"] and
  (index("--title") as $i|.[$i+1]==$title) and
  (index("--notes-file") as $i|.[$i+1]==$notes)' "$sandbox/preview.json" >/dev/null || fail '복사한 명령에서 UTF-8·공백·작은따옴표 인자 손상'
prepared_head=$(git -C "$public" rev-parse HEAD)
"$development/tools/release.sh" 0.1.1 "$public" > "$sandbox/reused"
[[ $(git -C "$public" rev-parse HEAD) == "$prepared_head" ]] || fail '게시 전 준비 재실행이 커밋·태그 변경'
# Ignored policy and hook links must not redirect writes outside the public tree.
protected="$sandbox/protected"; printf '사용자 파일 보존\n' > "$protected"
cp "$protected" "$sandbox/protected-before"
mv "$public/.personal-patterns" "$sandbox/saved-patterns"
ln -s "$protected" "$public/.personal-patterns"
if "$development/tools/release.sh" 0.1.1 "$public" > "$sandbox/pattern-link" 2>&1; then fail '개인 패턴 링크를 통한 외부 파일 쓰기'; fi
cmp -s "$protected" "$sandbox/protected-before" || fail '외부 사용자 파일 손상'
rm "$public/.personal-patterns"; mv "$sandbox/saved-patterns" "$public/.personal-patterns"
mv "$public/.git/hooks" "$sandbox/saved-hooks"; mkdir "$sandbox/protected-hooks"
ln -s "$sandbox/protected-hooks" "$public/.git/hooks"
if "$development/tools/release.sh" 0.1.1 "$public" > "$sandbox/hooks-link" 2>&1; then fail 'hooks 링크를 통한 외부 디렉터리 쓰기'; fi
[[ -z $(find "$sandbox/protected-hooks" -mindepth 1 -print -quit) ]] || fail '외부 hooks 디렉터리 변경'
rm "$public/.git/hooks"; mv "$sandbox/saved-hooks" "$public/.git/hooks"
git -C "$public" -c user.name=Fixture -c user.email=fixture@example.test -c commit.gpgsign=false tag -a HIDDEN_RELEASE_VALUE -m 'public tag message'
if (cd "$public" && printf 'refs/tags/HIDDEN_RELEASE_VALUE %s refs/tags/HIDDEN_RELEASE_VALUE %040d\n' "$(git rev-parse HIDDEN_RELEASE_VALUE)" 0 | .git/hooks/pre-push origin https://github.com/coldplay126/routine-automation.git) > "$sandbox/hook-tag-output" 2>&1; then fail '개인 태그 이름 push 허용'; fi
! grep -q 'HIDDEN_RELEASE_VALUE' "$sandbox/hook-tag-output" || fail 'hook가 개인 태그 이름 출력'
# Actual hook: private outgoing author/message/patch is rejected without printing.
printf 'HIDDEN_RELEASE_VALUE\n' > "$public/leak.txt"
git -C "$public" add leak.txt
git -C "$public" -c user.name=Fixture -c user.email=fixture@example.test -c commit.gpgsign=false commit -qm 'hook fixture'
if (cd "$public" && printf 'refs/heads/main %s refs/heads/main %s\n' "$(git rev-parse HEAD)" "$prepared_head" | .git/hooks/pre-push origin https://github.com/coldplay126/routine-automation.git) > "$sandbox/hook-output" 2>&1; then fail '개인 값 나가는 patch 허용'; fi
! grep -q 'HIDDEN_RELEASE_VALUE' "$sandbox/hook-output" || fail 'hook가 일치 내용 출력'
export ALLOW_PUBLISH_STUB=1
"$development/tools/release.sh" 0.1.1 "$sandbox/public-success" --publish > "$sandbox/published"
[[ $(cat "$GH_STATE") == published && $(cat "$GH_ACCOUNT") == fixture-owner ]] || fail '검증 후 공개·계정 복귀 실패'
public_success="$sandbox/public-success"
safe_head=$(git -C "$public_success" rev-parse HEAD)
printf 'public content\n' > "$public_success/safe.txt"
git -C "$public_success" add safe.txt
git -C "$public_success" -c user.name=Fixture -c user.email=hidden-author@example.test -c commit.gpgsign=false commit -qm 'private author fixture'
if (cd "$public_success" && printf 'refs/heads/main %s refs/heads/main %s\n' "$(git rev-parse HEAD)" "$safe_head" | .git/hooks/pre-push origin https://github.com/coldplay126/routine-automation.git) > "$sandbox/hook-author-output" 2>&1; then fail '개인 작성자 메타데이터 push 허용'; fi
! grep -q 'hidden-author@example.test' "$sandbox/hook-author-output" || fail 'hook가 개인 작성자 출력'
rm -f "$GH_STATE"
if BAD_UPLOAD_DIGEST=1 "$development/tools/release.sh" 0.1.1 "$sandbox/public-mismatch" --publish > "$sandbox/digest-mismatch" 2>&1; then fail '업로드 digest 불일치 공개'; fi
[[ $(cat "$GH_STATE") == uploaded && $(cat "$GH_ACCOUNT") == fixture-owner ]] || fail '불일치 draft 보존·계정 복귀 실패'
! grep -q '^forbidden' "$RECORD" || fail '실제 네트워크 또는 금지 명령 진입'
printf 'PASS: 실제 archive·공개 신원/태그·노트 절·준비 재실행·개인 값 pre-push 거부·스텁 draft 업로드 검증/공개·계정 복귀\n'
