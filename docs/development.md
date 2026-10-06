# 개발·검증·공개 배포

개발 레포의 과거 이력은 공개하지 않습니다.
공개 배포는 검증한 현재 파일만 `tools/release.sh`로 옮깁니다.
아래 개발 명령은 저장소 루트에서 실행합니다.

- [패키지·버전 규칙](#패키지버전-규칙)
- [공개 배포](#공개-배포)
- [격리 검증](#격리-검증)

[README](../README.md) · [설치](install.md) · [안전과 한계](safety.md) · [변경 내역](../CHANGELOG.md)

## 패키지·버전 규칙

```bash
./tests/run.sh --all-jq     # 기본 jq + 별도 /usr/bin/jq가 있으면 두 버전
./tests/real-gum.sh         # 선택 실행: 실제 gum PTY, 없으면 SKIP (전체 테스트에 포함하지 않음)
bin/routine package
```

현재 버전은 루트 `VERSION` 파일에 있습니다.
새 zip을 배포하기 전에 반드시 VERSION을 상향하고 `CHANGELOG.md`에 사용자 관점 변경을 추가하세요.
같은 버전 zip은 `routine update`로 재설치되지 않습니다.
버전은 선행 0 없는 `MAJOR.MINOR.PATCH` 숫자 세 개를 사용합니다.

package는 커밋하지 않은 변경·새 파일이 있으면 거부하고
`git archive HEAD`로 `dist/routine-automation-<VERSION>.zip`을 만듭니다.
zip 최상위 폴더는 `routine-automation-<VERSION>/`이며
`routine 설치.command`의 실행 권한, `설치 방법.txt`, `CHANGELOG.md`, `LICENSE`가 포함됩니다.
dist는 Git에서 제외됩니다.

`docs/`의 세부 문서도 zip에 포함됩니다.

package는 생성한 zip을 현재 검증기 하나로 자기 검증하며,
`tools/legacy-validators/*.sh`에 보관된 모든 공개 검증기로도 검사합니다.
어느 쪽에서든 거부하면 zip을 삭제하고 실패합니다.

검증 코드를 바꿀 때 직전 공개 버전의 `share/update.sh`를
`tools/legacy-validators/<VERSION>.sh`로 먼저 보관하고, 이전 공개 검증기는 누적 유지하세요.
현재는 공개 0.1.0 검증기와 `tests/fixtures/public-0.1.0.zip`의 실제 클라이언트 트리를 보관합니다.
검증기만 실행하는 검사에 더해 그 클라이언트의 네트워크·설치 인터페이스로 새 package까지 업데이트하는 회귀를 유지합니다.
package는 Git 과거 이력·원격 조회·push에 의존하지 않습니다.

### 개인 값 검사

로컬 `.personal-patterns`에 개인 값의 ERE 패턴을 한 줄씩 둘 수 있습니다.
이 파일은 `.gitignore`에 등록되어 zip·커밋에 포함되지 않습니다.
존재하면 package가 zip의 압축 해제된 모든 내용·파일 경로·원본 메타데이터를 검사하고,
일치 시 배포 zip을 삭제하고 실패합니다.
패턴/일치 내용은 출력하지 않습니다.

파일이 없는 팀원 환경은 검사만 건너뜁니다.
테스트도 이 파일이 있을 때 전체 tracked 파일을 검사합니다.

## 공개 배포

개발 레포에는 원격을 추가하거나 개발 이력을 push하지 마세요.
개인 값이 있는 과거 이력·작성자 메타데이터는 공개할 수 없습니다.
커밋을 cherry-pick/format-patch로 옮기지 않고 아래 절차의 `git archive`로만 반영합니다.

공개 계정·저장소 이름 `coldplay126/routine-automation`은 변경·이전하지 않습니다.
배포된 클라이언트는 이 이름과 저장소 ID를 고정해서 사용합니다.

VERSION·CHANGELOG를 갱신하고 전체 격리 테스트와 개인 값 검사를 통과한 개발 HEAD를 커밋한 뒤 실행하세요.

```bash
./tools/release.sh "$(cat VERSION)"                         # 로컬 준비만
./tools/release.sh "$(cat VERSION)" ../routine-automation-public
# 회사 확인·공개 승인 후 개발 레포에서만 실행:
./tools/release.sh "$(cat VERSION)" --publish
```

공개 경로의 기본값은 개발 레포 옆 `../routine-automation-public`입니다.
스크립트는 깨끗한 개발 HEAD를 archive로 추출해 공개 레포의 추적 파일만 교체하고,
`.personal-patterns`를 복사·ignore 상태로 유지합니다.
공개 신원 `coldplay126 <coldplay126@gmail.com>`으로 `release <VERSION>` 커밋과 annotated `v<VERSION>` 태그를 만듭니다.

공개 트리·전체 이력의 patch/작성자/커미터·태그 메타데이터를 내용 비출력으로 검사한 다음
공개 레포에서 package를 생성하고 CHANGELOG의 해당 버전 절만 노트 파일로 검사합니다.
같은 내용의 준비된 태그는 재사용하며 이미 준비한 태그의 내용을 바꾸지는 않습니다.

공개 레포에는 `.personal-patterns`가 필수인 pre-push hook을 설치합니다.
나가는 범위의 patch·커밋/태그 메타데이터·branch/tag 이름·트리에 개인 값이 있거나 검사에 실패하면 push를 거부합니다.
기존 사용자 hook/hooksPath가 다르면 덮어쓰지 않고 중단하며, 패턴 파일·Git 설정·hooks 링크로 레포 밖에 쓰지 않습니다.

개인 패턴은 개발·공개 레포 모두 추적하지 않고 ignore해야 합니다.
개발 이력은 공개 레포로 가져오지 않으며 개발 레포 원격도 허용하지 않습니다.

기본 실행은 push·Release 명령을 출력만 합니다.
미리보기는 UTF-8을 그대로 표시하고 작은따옴표로 인용하여 제목·경로의 공백과 작은따옴표도 복사 후 한 인자로 유지합니다.

`--publish`에서만 현재 GitHub 계정을 기록하고 `coldplay126`으로 전환·확인한 뒤 공개 branch와 해당 태그를 push합니다.
계정 전환을 무시하는 `GH_TOKEN`·`GITHUB_TOKEN`·`GH_HOST` 환경 변수는 미리 해제해야 합니다.
성공·실패 모두 원래 계정으로 복귀합니다.

공개 저장소는 Immutable releases를 사용합니다.
반드시 draft 생성 → asset 업로드 → API의 URL/state/size/digest 및 제목·노트 검증 →
`gh release edit --draft=false`로 공개하는 순서를 지킵니다.
검증 실패 시 draft를 공개하지 않으며 기존 asset을 덮어쓰지 않습니다.

공개 후 asset·태그는 수정할 수 없으므로 수정은 새 버전으로만 배포합니다.
`0.x` 배포는 prerelease로 게시합니다.

## 격리 검증


전체 격리 테스트:

```bash
/bin/bash tests/run.sh --all-jq
```

아래 검증은 사용자 설치본과 실제 서비스 대신 임시 HOME·스텁을 사용합니다.
Finder·OS 권한·조직별 Slack 화면은 이 테스트만으로 보장하지 않습니다.

<details>
<summary>검증 범위와 테스트 격리 세부</summary>

테스트는 임시 HOME·가짜 이메일/Slack 값·전용 PATH의 스텁을 사용합니다. 실제 brew/launchctl/Slack/Orca/LLM/사용자 설치는 실행하지 않습니다. 별도 클립보드 회귀만 `routine-test-*` named pasteboard에서 실제 JXA를 실행하고 일반 클립보드는 건드리지 않습니다. 기존 SQLite·근거 판정·사용자 입력/전면 복원·붙여넣기 안전 회귀에 더해 jq 1.7/1.8, 스키마 복구·설정 저장/설치 격리, init 링크·자동 제안, Claude 격리·JSONL 메타/상한, bash 3.2의 실제 script PTY setup·명시적 FDA 확인, 보호 경로 실패 경고/재검증, jq 누락/구버전 설치 동의, clipboard 자동 GUI 차단, 첫 실행 실패 표지, doctor/status, zip 개인 패턴 차단, 폴더 A→B 업데이트·누락 자산 복원·실제 SIGKILL 경계별 journal 복구·기존 서비스 재로드·legacy 이전·소유 거부·uninstall을 검증합니다. FDA 권한 자체는 실제 launchd/TCC 환경을 실행하지 않으므로 이 테스트가 OS 권한 보장의 증거는 아닙니다.
선택한 jq와 타임아웃·가상 시계·입력 보호 스텁은 필요한 테스트의 `~/.local/bin`에도 미러링합니다. `bin/routine`의 정렬된 PATH가 테스트용 도구 대신 Homebrew/시스템 도구를 먼저 고르지 않도록 하며, GUI·LLM 명령은 계속 전용 스텁으로 격리합니다.
SQLite 잠금 회귀(`tests/sqlite-lock.sh`)는 임시 History를 별도 프로세스의 EXCLUSIVE 쓰기 트랜잭션과 실제 hot journal 상태로 유지한 채 수집합니다. 커밋된 Jira 행 복구·미커밋 행 제외·오류 없음·원본 DB/저널 해시 불변·15초 상한을 확인합니다. `tests/run.sh`는 Notion의 WAL-only 행을 online backup과 강제 복사 폴백 양쪽에서 확인하고, `quick_check`가 실패하는 사본의 오류·프로필별 재시도·원본 read-only 가드도 검증합니다. 사용자 Chrome/Notion DB는 테스트에 쓰지 않습니다.
업데이트 회귀(`tests/update.sh`)는 두 jq·임시 HOME·PATH와 내보낸 함수의 이중 스텁 격리에서 내부 VERSION 비교·검증된 후보 선택·필수 파일 누락/CRC 오류/크기 초과 후보의 다음 정상 후보 선택·한글 이름·대소문자/정규화 중복·호스트별 링크 속성·로컬 헤더 불일치·안전한 경로·동일/하위 버전·비TTY 동의·확인만 실행을 검증합니다. 사용자 지정 설정 경로와 예약 시간·데이터/로그/install-id 보존, 실행 잠금 중 교체 차단, LaunchAgent 등록 실패 롤백·등록 직전 SIGKILL 뒤 같은 ZIP 재실행 복구·status 미완료/미등록 경고·새 설정 도구 안내·알림의 자동 설치 금지·배포 zip 런처 권한과 상대 심볼릭 링크 실행도 확인합니다. Finder/Gatekeeper GUI는 실행하지 않습니다.
정상 업데이트 후보는 이력 없는 임시 Git 저장소의 **실제 `bin/routine package` 산출물**로 생성해 확인과 설치까지 소비합니다. curl의 PATH·내보낸 함수 이중 스텁으로 prerelease·draft·숫자/페이지 비교·정확한 최초 URL·저장소 ID·uploaded 상태·digest/size 불일치·302→서명 asset 호스트·리다이렉트 경계·`-q`/HTTPS/크기 제한·curl 63을 확인합니다. GitHub 403과 Downloads 9.9.9이 겹쳐도 auto 설치·알림이 없으며, Downloads의 `--yes` 비TTY 거부와 실제 PTY의 거절·동의를 검증합니다. 실제 15초 종료와 임시 파일 정리·변경된 ZIP의 캐시 무효화·0.1.0 보관 클라이언트에서 새 package로의 업데이트도 확인합니다. `TEST_HEAD_PACKAGE_ZIP`에 공개 `dist/routine-automation-VERSION.zip` 경로를 전달하면 이 호환 회귀가 실제 공개 HEAD 산출물을 소비합니다. 실제 네트워크는 호출하지 않습니다. 특수 ZIP 중앙/로컬 헤더·CRC·외부 속성과 LICENSE 대소문자/내용 경계는 `tests/zip-fixtures.cjs`로 생성합니다.
배포 회귀(`tests/release.sh`)는 임시 개발 이력에 개인 값과 비공개 작성자를 넣고 archive로 새 공개 레포에 옮겨 공개 신원·태그·노트 절·준비 재실행·실제 pre-push의 patch/작성자/태그 이름 거부를 확인합니다. 패턴·hooks 링크로 외부 사용자 파일이 바뀌지 않는지도 확인합니다. UTF-8·공백·작은따옴표가 있는 미리보기 명령은 실제 Bash 파서로 소비해 인자가 유지되는지 확인합니다. push·gh는 PATH/내보낸 함수 스텁에서만 동작하며, draft 업로드 검증 후 공개·digest 불일치 시 미공개·양쪽 계정 복귀를 검증합니다. 실제 저장소·Release 생성은 하지 않습니다.
검토 회귀는 두 jq에서 0600 권한·날짜 선택·초안 없음 실패·CSP·악성 문구 이스케이프·redact/300자 상한·체크박스 기본값·기존 텍스트와 초기 미리보기 일치·질문 전용 후보 보존·스냅샷 없는 초안의 기본 format을 확인합니다. 복사·검토 앱은 osacompile 스텁으로 생성하고 사용자 지정 설정 경로 전달·manifest 소유 확인·변조 거부·uninstall 제거를 검증합니다. 앱의 고정 PATH가 스텁을 우회하지 않도록 앱 호출 회귀에는 Bash의 open/osascript 스텁 함수도 내보냅니다. 실제 브라우저의 클립보드 권한은 스텁 테스트로 보장하지 않습니다.
선택 브라우저 회귀는 `tests/review-browser.cjs`로 실제 JS `render()`의 HTML·텍스트가 저장된 초안과 같은지, 설정 변경 후에도 형식이 보존되는지, `<!--<script>` 경계·Unicode 주제 접기·줄바꿈/빈 편집·오늘 보류·복사 API·좁은 화면을 검증합니다. node·Playwright 드라이버·headless Chromium이 없으면 SKIP하며 설치하지 않습니다. 기존 드라이버와 실행 파일을 `REVIEW_BROWSER_DRIVER`·`REVIEW_BROWSER_CHROMIUM`으로 지정할 수 있습니다. `REVIEW_BROWSER_SHOTS=/tmp/routine-review-shots`는 화면·검증 결과를, `REVIEW_BROWSER_SAMPLE_DIR=/tmp/routine-review-sample`은 0600 HTML 샘플을 남깁니다. OS 클립보드는 변경하지 않고 브라우저의 clipboard sink만 스텁으로 교체합니다.
스타일 회귀는 두 jq에서 Claude·OMP 프롬프트의 신뢰 섹션 위치·2,000자 상한·경고·데이터의 위장 제목 격리, 스타일을 따른 스텁 LLM의 level 강등과 완료 기호·약어 주장 제외/일반 OK 문구 보존, 선택 스타일 검사 실패 후 계속 생성, 템플릿 주석 제거, format 값 거부·init 파싱·설정 미변경, tree/flat·커스텀 글머리의 text/HTML/초기 검토/JS 렌더/복사 일치, 상한 항목·근거·질문 보존과 검토 재선택·생략 수 안내, preview의 파일 미변경·현재 형식 적용, 인용한 EDITOR 경로·인자/open 스텁·템플릿 0600을 확인합니다. JS 렌더는 node에서 실제 검토 스크립트를 실행하며 선택 브라우저 회귀에도 flat 사례를 추가했습니다. 드라이버가 없으면 브라우저는 SKIP합니다.
학습 회귀는 `tests/learn.sh`에서 두 jq의 직전 근무일(추석 예외 근무)/명시 날짜·본인 댓글 본문 경계·구조적 입력창/인용/첨부/구분선 제외·일반 본문 키워드 보존·같은 부모 안 작성자 생략 연속 메시지/반응 뒤 본문 보존·미인식 작성자와 이름에 컨트롤 단어가 든 타인 제외·댓글 버튼 최대 1회/이미 열린 대상 0회·입력/전송 0회·작성 중 스레드/다른 작업 잠금 중단·오늘 pasted/paste-attention의 전송/빈 오늘 입력창 확인 후 진행과 미확인 중단·표지/타 작업 잠금 보존·본인 확인/LLM 전송 거절·사용자 입력 감지·전면 활성화 무시 후 `open -b` 대체/실패/입력 중단의 Slack 알림·다른 앱 전환의 포커스 보존·Claude/OMP 격리·데이터 구분자 위장 격리·스키마 상한/제어/채움/주석 위반 거부·NFD/결합/VS16/ZWJ 허용·미리보기 코드포인트 표시·예시 줄바꿈 표시·redact·0600·선택 순서/전 날짜 중복 방지/기존 절 보존·style 안전 정책·2,000자 경고·비TTY 캐시 출력/획득 차단·무인 미실행을 확인합니다. 작성자 회귀 데이터는 `tests/fixtures/slack-learn-authors.json`에 있습니다. gum은 시작부터 PATH·`$HOME/.local/bin`의 forbidden 스텁과 `type -P` 함수 보호로 격리하고 대화형 단계에는 전용 스텁을 사용합니다. 비TTY 단언은 `</dev/null`로 실행하며 터미널에서 전체 테스트를 실행해도 설치된 gum을 사용하지 않습니다. open/osascript/pbpaste/pbcopy/orca/claude/omp는 PATH와 내보낸 Bash 함수 스텁을 함께 사용해 호출 기록을 확인합니다. 실제 Slack AX·GUI·LLM·일반 클립보드는 실행하지 않으므로 Slack 버전별 AX 형식·동명이인·댓글 요약 노출 여부는 미검증이며 확인 불가 시 중단하거나 `--paste`로 대체합니다.
근무일 회귀는 `tests/calendar.sh`에서 공휴일·휴가·예외 근무일의 날짜 표, 휴일 작업까지 포함한 실제 로컬 Git 수집·초안·검토, 14일 상한과 질문/status 안내, 범위·중복·입력 오류·0600 저장, 비근무일 morning/auto skip과 extra_steps 실행, 다음 예약·표 없는 연도 경고, 달력 비활성화·기존 설정 무변경 로드를 두 jq로 검증합니다. 실제 GUI·LLM·설치·launchctl·네트워크는 사용하지 않습니다.

gum 회귀는 설치된 실제 gum을 실행하지 않고 전용 스텁만 사용합니다. 실제 `expect`/`script` PTY에서 setup의 config FIFO/tee 경로, 4/5단계 머리글·요약, 저장/한 항목 수정/최종 취소·Esc·Ctrl-C의 파일 보존, 텍스트 경로와 NO_COLOR, 최종 체크리스트 한 벌, 스피너의 성공/실패 명령 단일 실행·stdout 보존, Slack 감지 후 포커스 복원을 검증합니다. 사전 선택·쉼표/공백 경로 추가, 사용 불가 소스 거부·Git 위치 복구·빈 위치 확인, 비대화형 질문 차단과 선택 의존성 설치 동의·실패 후 계속 진행 회귀도 유지합니다.
안내 유형별 기호와 기본색의 굵은 제목, 본문·요약 값의 기본색 유지, 출처 기호와 보조 글자의 색 분리, 새 링크와 명시적인 Slack 플래그의 저장 우선순위도 검증합니다.
`tests/first-run-ui.sh`는 지연된 morning 스텁의 로그를 실제 setup PTY에서 읽어 수집→LLM 전환, 소스별 진행, 이전 실행 로그 제외, 부분 기록된 줄의 이어 읽기, 좁은 화면의 현재 작업 표시와 안내 줄 정리를 확인합니다. `s`는 Enter 없이 대기만 끝내고 스텁 서비스는 계속 완료하며, SIGINT/SIGTERM/SIGQUIT/SIGHUP 종료에서도 설정 가능한 모든 stty 상태와 커서를 복원하는지 검사합니다. SIGTSTP 일시정지 중에는 입력 상태·커서를 복원하고 계속 실행 시 스피너 모드를 다시 적용합니다. macOS가 raw→canonical 전환 때 자동으로 붙이는 일시적인 커널 PENDIN 비트는 상태 비교에서 제외합니다.

`tests/real-gum.sh`는 gum만 실제 바이너리로 실행하고 brew·launchctl·Slack/Orca·LLM 관련 명령은 전용 스텁으로 격리합니다. 임시 HOME의 setup을 실제 화살표·Enter 입력으로 구동해 일반/좁은 화면의 질문·요약 잔여와 중복 체크리스트가 없는지, 저장/취소 뒤 결과와 단계 상태가 맞는지 확인합니다. 실제 요약 카드의 라벨/값 구분선은 터미널 셀 기준으로 같은 열인지 단언하고, 버튼의 전경·배경·굵기와 NO_COLOR의 SGR 제거도 검증합니다. `REAL_GUM_BIN=/절대/경로/gum`으로 바이너리를 지정할 수 있습니다. `REAL_GUM_SHOTS=/tmp/routine-ui-shots`도 지정하면 단계 머리글·입력·다중 선택·확인·요약·경고·성공/실패 체크리스트·소스 목록의 실제 PTY ANSI 화면을 `.ans` 파일로 남깁니다.

</details>

영어 Slack, Orca 없는 AX 직접 구현, 메뉴 막대 UI, Claude 데스크톱 대화 수집, Slack API 게시는 범위에 포함하지 않습니다.
