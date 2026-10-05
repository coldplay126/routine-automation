#!/usr/bin/env bash
set -euo pipefail
umask 077
repository=coldplay126/routine-automation
source_root=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
usage() { echo 'tools/release.sh VERSION [PUBLIC_REPO] [--publish] — archive로 로컬 준비; --publish만 push·draft Release 게시'; }
fail() { printf '릴리스 거부: %s (개인 값 내용은 출력하지 않음)\n' "$1" >&2; exit 1; }
version=${1:-}; (($#)) || { usage >&2; exit 2; }; shift
[[ $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { usage >&2; exit 2; }
public_path="$source_root/../routine-automation-public"; publish=0
while (($#)); do
  case $1 in
    --publish) publish=1 ;;
    --*) usage >&2; exit 2 ;;
    *) public_path=$1 ;;
  esac
  shift
done
[[ -z ${GIT_DIR:-}${GIT_WORK_TREE:-}${GIT_INDEX_FILE:-}${GIT_COMMON_DIR:-} ]] || fail 'Git 경로 환경 변수는 해제하세요'
[[ ! -f $source_root/manifest.json && -d $source_root/.git ]] || fail '개발 Git 레포에서만 실행하세요'
[[ -z $(git -C "$source_root" remote) ]] || fail '개발 레포에는 원격을 추가할 수 없습니다'
[[ -z $(git -C "$source_root" status --porcelain) ]] || fail '개발 HEAD를 먼저 깨끗하게 커밋하세요'
[[ $(<"$source_root/VERSION") == "$version" ]] || fail 'VERSION과 요청 버전 불일치'
patterns="$source_root/.personal-patterns"
[[ -f $patterns && ! -L $patterns ]] || fail '개발 .personal-patterns 필요'
git -C "$source_root" check-ignore -q -- .personal-patterns || fail '개발 개인 패턴은 추적되지 않고 ignore되어야 합니다'
pattern_status=0
LC_ALL=C grep -aE -f "$patterns" /dev/null >/dev/null 2>&1 || pattern_status=$?
((pattern_status==1)) || fail '개인 패턴 문법 오류'
check_private() {
  local status=0
  LC_ALL=C grep -aE -f "$patterns" "$@" >/dev/null 2>&1 || status=$?
  ((status==1)) || fail '개인 패턴 일치 또는 검사 오류'
}
check_private < <(printf '%s\n' coldplay126 coldplay126@gmail.com "$repository" "release $version")
status=0; git -C "$source_root" grep -qIE -f "$patterns" HEAD -- . || status=$?
((status==1)) || fail '개발 HEAD 트리 개인 값'
mkdir -p -- "$(dirname -- "$public_path")"
public_parent=$(CDPATH='' cd -P -- "$(dirname -- "$public_path")" && pwd)
public_root="$public_parent/${public_path##*/}"
[[ $public_root != / && $public_root != "$HOME" && $public_root != "$source_root" &&
   $public_root != "$source_root/"* && $source_root != "$public_root/"* && ! -L $public_root ]] || fail '공개 레포 경로 경계'
[[ ! -L $public_root/.personal-patterns && ( ! -e $public_root/.personal-patterns || -f $public_root/.personal-patterns ) ]] || fail '공개 개인 패턴은 일반 파일이어야 합니다'
if [[ -e $public_root ]]; then
  [[ -d $public_root/.git && ! -L $public_root/.git ]] || fail '기존 공개 경로는 독립 Git 레포여야 합니다'
  [[ $(git -C "$public_root" rev-parse --show-toplevel) == "$public_root" ]] || fail '공개 Git 루트 불일치'
  [[ $(git -C "$public_root" branch --show-current) == main && -z $(git -C "$public_root" status --porcelain) ]] || fail '공개 main 작업 트리 변경을 먼저 보존하세요'
else mkdir "$public_root"; git -C "$public_root" init -q -b main; fi
[[ ! -L $public_root/.git/config && ! -L $public_root/.git/hooks ]] || fail '공개 Git 설정·hooks 경계는 링크일 수 없습니다'
for remote in $(git -C "$public_root" remote); do
  [[ $remote == origin ]] || fail '공개 원격은 origin 하나만 허용합니다'
  for direction in '' --push; do
    # shellcheck disable=SC2086 # Empty or the single literal --push option.
    while IFS= read -r url; do
      case $url in
        https://github.com/coldplay126/routine-automation.git|git@github.com:coldplay126/routine-automation.git|ssh://git@github.com/coldplay126/routine-automation.git) ;;
        *) fail '공개 계정·저장소·원격 이름 변경 금지' ;;
      esac
    done < <(git -C "$public_root" remote get-url $direction --all "$remote")
  done
done
scratch=$(mktemp -d "${TMPDIR:-/tmp}/routine-release-preparation.XXXXXXXX")
previous_account=''; switched=0
cleanup() {
  local status=$?
  trap - EXIT
  if ((switched)); then
    gh auth switch --hostname github.com --user "$previous_account" >/dev/null 2>&1 || { echo '기존 GitHub 계정 복귀 실패 — 직접 확인하세요.' >&2; status=1; }
  fi
  rm -rf -- "$scratch"
  exit "$status"
}
trap cleanup EXIT
mkdir "$scratch/tree"
git -C "$source_root" archive --format=tar HEAD | tar -xf - -C "$scratch/tree"
source_tree=$(git -C "$source_root" rev-parse 'HEAD^{tree}')
tag="v$version"
if git -C "$public_root" rev-parse --verify "$tag" >/dev/null 2>&1; then
  [[ $(git -C "$public_root" cat-file -t "$tag") == tag &&
     $(git -C "$public_root" rev-parse "$tag^{commit}") == "$(git -C "$public_root" rev-parse HEAD)" &&
     $(git -C "$public_root" rev-parse "$tag^{tree}") == "$source_tree" &&
     $(git -C "$public_root" log -1 --format='%an|%ae|%cn|%ce|%s') == "coldplay126|coldplay126@gmail.com|coldplay126|coldplay126@gmail.com|release $version" ]] || fail '기존 태그와 준비 내용 불일치 — 새 버전이 필요합니다'
else
  while IFS= read -r -d '' path; do
    parent=${path%/*}
    while [[ $parent != "$path" && $parent != . ]]; do
      [[ ! -L $public_root/$parent ]] || fail '공개 작업 트리의 링크 경로'
      [[ $parent == */* ]] || break
      parent=${parent%/*}
    done
    if [[ -e $public_root/$path || -L $public_root/$path ]]; then
      git -C "$public_root" ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || fail '새 추적 파일과 비추적 파일 충돌'
    fi
  done < <(git -C "$source_root" ls-tree -rz --name-only HEAD)
  while IFS= read -r -d '' path; do rm -f -- "$public_root/$path"; done < <(git -C "$public_root" ls-files -z)
  cp -R "$scratch/tree/." "$public_root/"
  cp "$patterns" "$public_root/.personal-patterns"
  git -C "$public_root" check-ignore -q -- .personal-patterns || fail '공개 .personal-patterns gitignore 필요'
  git -C "$public_root" add -u
  while IFS= read -r -d '' path; do git -C "$public_root" add -- "$path"; done < <(git -C "$source_root" ls-tree -rz --name-only HEAD)
  [[ $(git -C "$public_root" write-tree) == "$source_tree" ]] || fail 'archive와 공개 index 트리 불일치'
  git -C "$public_root" config --local user.name coldplay126
  git -C "$public_root" config --local user.email coldplay126@gmail.com
  GIT_AUTHOR_NAME=coldplay126 GIT_AUTHOR_EMAIL=coldplay126@gmail.com GIT_COMMITTER_NAME=coldplay126 GIT_COMMITTER_EMAIL=coldplay126@gmail.com \
    git -C "$public_root" -c commit.gpgsign=false commit -qm "release $version" --allow-empty
  GIT_COMMITTER_NAME=coldplay126 GIT_COMMITTER_EMAIL=coldplay126@gmail.com \
    git -C "$public_root" -c tag.gpgsign=false tag -a "$tag" -m "release $version"
fi
# Refresh the ignored local policy even when reusing an already prepared tag.
cp "$patterns" "$public_root/.personal-patterns"
git -C "$public_root" check-ignore -q -- .personal-patterns || fail '공개 패턴 파일 ignore 누락'
status=0; git -C "$public_root" grep -qIE -f "$patterns" HEAD -- . || status=$?
((status==1)) || fail '공개 트리 개인 값'
git -C "$public_root" log --all -p --format='%an%n%ae%n%cn%n%ce%n%B' | check_private
git -C "$public_root" for-each-ref --format='%(refname)%0a%(taggername)%0a%(taggeremail)%0a%(contents)' refs/tags | check_private
cat > "$scratch/pre-push" <<'HOOK'
#!/bin/bash
# routine-automation public pre-push guard
set -euo pipefail
root=$(git rev-parse --show-toplevel)
patterns="$root/.personal-patterns"
reject() { echo 'push 거부: 개인 값 또는 검사 오류 (내용 비출력)' >&2; exit 1; }
[[ -f $patterns && ! -L $patterns ]] || reject
status=0; LC_ALL=C grep -aE -f "$patterns" /dev/null >/dev/null 2>&1 || status=$?
((status==1)) || reject
check() { local status=0; LC_ALL=C grep -aE -f "$patterns" >/dev/null 2>&1 || status=$?; ((status==1)) || reject; }
while read -r local_ref local_oid remote_ref remote_oid; do
  [[ ! $local_oid =~ ^0+$ ]] || continue
  printf '%s\n%s\n' "$local_ref" "$remote_ref" | check
  if [[ ! $remote_oid =~ ^0+$ ]] && git cat-file -e "$remote_oid^{commit}" 2>/dev/null; then range="$remote_oid..$local_oid"
  else range=$local_oid; fi
  git log -p --format='%an%n%ae%n%cn%n%ce%n%B' "$range" | check
  git for-each-ref --format='%(refname)%0a%(taggername)%0a%(taggeremail)%0a%(contents)' "$local_ref" | check
  status=0; git grep -qIE -f "$patterns" "$local_oid" -- . || status=$?
  ((status==1)) || reject
done
HOOK
hook="$public_root/.git/hooks/pre-push"
[[ ! -L $public_root/.git/hooks ]] || fail '공개 hooks 디렉터리는 링크일 수 없습니다'
mkdir -p "$public_root/.git/hooks"
[[ ! -L $hook ]] || fail 'pre-push hook은 링크일 수 없습니다'
if [[ -e $hook ]]; then
  LC_ALL=C grep -qFx '# routine-automation public pre-push guard' "$hook" || fail '기존 사용자 pre-push hook을 보존하세요'
fi
hook_path=$(git -C "$public_root" config --get core.hooksPath || true)
[[ -z $hook_path || $hook_path == .git/hooks ]] || fail '기존 사용자 hooksPath를 먼저 보존하세요'
git -C "$public_root" config --local core.hooksPath .git/hooks
cp "$scratch/pre-push" "$hook"; chmod 700 "$hook"
"$public_root/bin/routine" package
notes="$public_root/dist/release-$version.md"
command jq -Rser --arg header "## $version" '
  split("\n")|reduce .[] as $line ({take:false,sections:0,lines:[]};
    ($line|gsub("[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]";"")) as $line|
    if ($line|startswith("## ")) then
      .take=($line==$header or ($line|startswith($header+" — ")))|
      if .take then .sections+=1|.lines+=[$line] else . end
    elif .take then .lines+=[$line] else . end)|
  select(.sections==1 and (.lines|length)>1)|.lines|join("\n")' "$public_root/CHANGELOG.md" > "$notes" || fail 'CHANGELOG의 해당 버전 절 필요'
check_private "$notes"
IFS= read -r title < "$notes"; title=${title#'## '}
check_private < <(printf '%s\n' "$title")
zip="$public_root/dist/routine-automation-$version.zip"
digest=$(shasum -a 256 "$zip"); digest=${digest%% *}; size=$(stat -f %z "$zip")
printf '개발 HEAD: %s\n공개 HEAD: %s\nZIP sha256: %s\n노트: %s\n' "$(git -C "$source_root" rev-parse HEAD)" "$(git -C "$public_root" rev-parse HEAD)" "$digest" "$notes"
release_flags=(); [[ $version != 0.* ]] || release_flags=(--prerelease --latest=false)
shell_quote() {
  local value=$1
  value=${value//\'/\'\\\'\'}
  printf "'%s'" "$value"
}
printf '게시 명령(--publish가 있을 때만 실행): tools/release.sh %s %s --publish\n' "$(shell_quote "$version")" "$(shell_quote "$public_root")"
printf 'gh auth switch --hostname github.com --user coldplay126\n'
printf 'git -C %s push origin refs/heads/main:refs/heads/main %s\n' "$(shell_quote "$public_root")" "$(shell_quote "refs/tags/$tag:refs/tags/$tag")"
printf 'gh release create %s --repo %s --draft --verify-tag --title %s --notes-file %s' "$(shell_quote "$tag")" "$(shell_quote "$repository")" "$(shell_quote "$title")" "$(shell_quote "$notes")"
for flag in ${release_flags[@]+"${release_flags[@]}"}; do printf ' %s' "$(shell_quote "$flag")"; done
printf '\n'
printf 'gh release upload %s %s --repo %s\n' "$(shell_quote "$tag")" "$(shell_quote "$zip")" "$(shell_quote "$repository")"
printf '# draft 제목·노트·asset URL/state/size/digest 검증 후에만 공개\n'
printf 'gh release edit %s --repo %s --draft=false\n' "$(shell_quote "$tag")" "$(shell_quote "$repository")"
printf "gh auth switch --hostname github.com --user \"\$previous_account\" # 성공·실패 모두 기존 계정 복귀\n"
((publish)) || exit 0
[[ -z ${GH_TOKEN:-}${GITHUB_TOKEN:-}${GH_HOST:-} ]] || fail '계정 전환을 무시하는 GitHub 토큰·호스트 환경 변수를 해제하세요'
previous_account=$(gh api --hostname github.com user --jq .login)
[[ -n $previous_account ]] || fail '현재 GitHub 계정 확인 실패'
switched=1
gh auth switch --hostname github.com --user coldplay126 >/dev/null
[[ $(gh api --hostname github.com user --jq .login) == coldplay126 ]] || fail '공개 GitHub 계정 확인 실패'
[[ $(gh api --hostname github.com "repos/$repository" --jq .id) == 1405988374 ]] || fail '공개 저장소 ID 불일치'
if ! git -C "$public_root" remote get-url origin >/dev/null 2>&1; then git -C "$public_root" remote add origin "https://github.com/$repository.git"; fi
git -C "$public_root" push origin refs/heads/main:refs/heads/main "refs/tags/$tag:refs/tags/$tag"
gh release create "$tag" --repo "$repository" --draft --verify-tag --title "$title" --notes-file "$notes" ${release_flags[@]+"${release_flags[@]}"} >/dev/null
gh release upload "$tag" "$zip" --repo "$repository" >/dev/null
gh api --hostname github.com "repos/$repository/releases/tags/$tag" > "$scratch/uploaded.json"
check_private "$scratch/uploaded.json"
command jq -e --arg tag "$tag" --arg title "$title" --rawfile body "$notes" --arg name "routine-automation-$version.zip" --arg digest "sha256:$digest" --argjson size "$size" --arg url "https://github.com/$repository/releases/download/$tag/routine-automation-$version.zip" '
  .draft==true and .tag_name==$tag and .name==$title and .body==$body and
  ([.assets[]|select(.name==$name and .state=="uploaded" and .size==$size and .digest==$digest and .browser_download_url==$url)]|length)==1' "$scratch/uploaded.json" >/dev/null || fail 'draft 제목·노트·asset 업로드 무결성 불일치 — 공개하지 않습니다'
gh release edit "$tag" --repo "$repository" --draft=false >/dev/null
echo '공개 완료 — Immutable Release의 asset·태그는 수정할 수 없습니다. 수정은 새 버전으로 배포하세요.'
