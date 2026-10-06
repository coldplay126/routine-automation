# routine-automation — 공개 베타

**0.1.2 베타**는 팀 시범 사용을 위한 배포입니다. 안정판이 아니며 설정·동작이 바뀔 수 있습니다. Finder 보안 경고, launchd/TCC 권한과 조직별 Slack 화면은 격리 테스트만으로 보장하지 않습니다. 이번 변경의 GitHub 통신은 스텁으로 검증했습니다. 도입 전 회사의 소스 공개·업무 데이터·LLM 사용 정책을 확인하세요.

공개 저장소: [coldplay126/routine-automation](https://github.com/coldplay126/routine-automation) · [베타 Release](https://github.com/coldplay126/routine-automation/releases) · [MIT 라이선스](LICENSE)

macOS에서 평일 아침에 로컬 작업 근거를 모아 한국어 스크럼 초안을 만듭니다. 기본 전달 방식은 **알림만**입니다. Spotlight에서 **스크럼 초안 검토**를 실행하면 항목을 선택·편집하고 미리보기를 복사할 수 있습니다. **스크럼 초안 복사**는 기존 초안 전체를 바로 복사하고 Slack 채널을 엽니다.

**Slack에 전송하지 않습니다.** 자동 게시, Slack API 게시, 댓글 입력창의 Return, 채널 동시 전송 체크박스 조작은 지원하지 않습니다. Orca를 쓰는 선택형 `gui-paste`도 스레드에 붙여넣기까지만 합니다. 마지막 검토와 전송은 사용자가 직접 합니다.

## 설치·업데이트·제거

### 첫 설치

Release에서 받은 최신 `routine-automation-<VERSION>.zip`을 풀고 폴더 안의 **`routine 설치.command`를 더블클릭**하세요. `<VERSION>`은 받은 zip의 실제 버전으로 바꾸세요. 자기 폴더에서 설치를 시작하고, 끝나면 결과를 보여 준 뒤 아무 키나 누를 때까지 기다립니다. zip 안의 `설치 방법.txt`에도 같은 안내가 있습니다. 터미널에서 실행할 때는 파일 이름에 공백이 있으니 경로를 따옴표로 감싸세요.

**macOS 보안 차단 시:** 인터넷/Slack에서 받은 zip은 격리(quarantine) 속성이 압축을 푼 파일에도 붙을 수 있습니다. 이 패키지는 서명·공증되지 않아 macOS 15 이상에서 더블클릭이 차단될 수 있습니다. 우클릭 › 열기를 우회 방법으로 안내하지 않습니다. 신뢰하는 팀 배포본에 한해서 아래 대안을 쓰세요.

1. 더블클릭을 시도한 직후 **시스템 설정 › 개인정보 보호 및 보안 › 보안 › 그래도 열기**, 이어서 경고의 **열기**를 선택합니다. 회사 관리 정책에 따라 예외 버튼이 없거나 허용되지 않을 수 있습니다. 악성 소프트웨어·손상 경고면 강행하지 말고 배포자에게 확인하세요.
2. 터미널에서 아래 한 줄을 실행합니다. 압축을 푼 폴더의 위치나 이름이 다르면 경로를 바꾸세요.

```bash
/bin/bash "$HOME/Downloads/routine-automation-<VERSION>/install.sh"
```

기존처럼 압축을 푼 폴더 안에서 `./install.sh`를 실행해도 됩니다. 전역 Gatekeeper 비활성화나 Downloads 전체의 격리 속성 제거는 하지 않습니다. 설치가 시작된 뒤 **설치 복사본에 한해서** 기존 절차로 격리 속성을 제거합니다.

조사 근거: 이 Mac(macOS 26.3.1, Darwin 25)에서 임시 `.command`에 `com.apple.quarantine`을 붙인 뒤 `spctl --assess --type execute --verbose=4`를 실행하자 `rejected`, `source=no usable signature`(종료 코드 3)였습니다. 같은 임시 파일은 `/bin/bash 파일경로`로 실행됐습니다. [Apple 공식 안내](https://support.apple.com/102445)는 미확인 개발자 앱의 보안 예외를 설정에서 허용하는 절차를 설명합니다. **Finder/Archive Utility의 격리 전파·실제 더블클릭 경고·이 파일의 예외 버튼 노출은 GUI를 실행하지 않아 미검증입니다 [INFERENCE].** `spctl` 결과만으로 Finder 동작을 보장하지 않습니다.

첫 설치의 `install.sh`는 `routine setup`을 호출합니다. TTY는 단계 체크리스트를 갱신하고 실행 중 스피너·경과시간을 보여 줍니다. 비 TTY는 단계별 한 줄 요약을 출력합니다. 상세 로그는 `~/Library/Logs/routine-automation/setup-<시각>-<PID>.log`입니다.

### 이후 업데이트

인자가 없으면 **`coldplay126/routine-automation`의 공개 Release**를 인증 없는 `curl`로 조회합니다. 업데이트 자체에는 `gh` 로그인이나 설치가 필요하지 않습니다. 저장소 이름과 ID `1405988374`는 코드 상수이며 설정 파일로 바꿀 수 없습니다. `ROUTINE_TEST_RELEASE_REPO`는 소스 트리의 격리 테스트에서만 동작하며 manifest가 있는 설치본에서는 무시합니다.

```bash
routine update
routine update --check             # 버전·변경 내역 확인만
routine update --yes               # GitHub 또는 직접 지정한 비Downloads ZIP의 확인 질문 생략
routine update "/다른 위치/routine-automation-<VERSION>.zip"
routine update --from downloads    # 네트워크 없이 Downloads에서만 찾기
routine update --from github       # 공개 Release만 사용
```

GitHub의 `/repositories/1405988374/releases?per_page=100&page=N` 목록을 페이지 끝까지 조회해 **draft는 제외하고 prerelease는 포함**합니다. 태그가 정확한 `vMAJOR.MINOR.PATCH`인 Release 중 세 숫자를 비교해 최고 버전을 고릅니다 (`0.10.0 > 0.9.0`). 해당 Release에서 `state: uploaded`인 `routine-automation-<버전>.zip` asset 하나만 사용하며, 실제 바이트 수와 SHA-256을 API `size`·`digest`에 대조합니다. zip 내부 VERSION이 태그와 달라도 거부합니다. `/releases/latest`나 태그 없는 `gh release download`는 사용하지 않습니다. 최초 URL은 저장소·태그·파일명까지 정확히 `https://github.com/coldplay126/routine-automation/releases/download/v<버전>/routine-automation-<버전>.zip`이어야 합니다. 이후 HTTPS `objects.githubusercontent.com`·`release-assets.githubusercontent.com`의 정확한 호스트만 허용하고 각 리다이렉트를 요청 전에 검사합니다(최대 5회 요청). 만료되는 서명 URL은 캐시하지 않고 매번 최초 URL에서 다시 해석합니다. 다운로드는 64MiB, 목록 페이지는 2MiB로 제한합니다.

네트워크 실패·HTTP 403/429 요청 제한·빈 공개 목록·asset 검증 실패이면 이유와 수동 경로를 안내하고 **설치하지 않습니다. Downloads로 자동 대체하지 않습니다.** `routine update --from downloads`를 직접 지정해야 오프라인 후보를 탐색합니다. 직접 ZIP 경로를 주면 네트워크를 조회하지 않으며 `--from`과 함께 쓸 수 없습니다. GitHub 인프라 변화나 업로드 미완료로 원격 업데이트가 막히면 `--from downloads` 또는 신뢰한 ZIP을 직접 풀어 `install.sh --update`를 사용하세요. 배포된 0.1.0 클라이언트는 새 정책으로 바뀌기 전까지 `routine update --from github`로 업데이트하는 편이 안전합니다.

Downloads에서는 `~/Downloads/routine-automation-*.zip` 중 **전체 검증을 통과한 zip의 VERSION이 가장 높은 것**을 고릅니다. 파일명의 버전은 믿지 않으며, 잘못된 ZIP은 경로와 거부 이유를 표시하고 다음 후보를 찾습니다. `ROUTINE_DOWNLOADS_DIR`로 검색 폴더를 바꿀 수 있습니다. 검증 결과는 경로·크기·나노초 mtime/ctime·inode별로 0600 캐시하며, 전체 탐색은 `gtimeout`/`timeout`으로 15초(강제 종료 유예 1초) 제한합니다. 시간 초과로 검증 프로세스가 강제 종료되어도 부모가 압축 해제·캐시 임시 파일을 정리합니다. 설치 직전에는 선택한 ZIP을 다시 검증합니다.
Downloads에서 고르거나 그 폴더의 ZIP을 직접 지정하면 **경로·SHA-256·quarantine·`kMDItemWhereFroms` 출처**를 보여 줍니다. 이 메타데이터는 위조·누락될 수 있어 출처 증명이 아닙니다. 실제 설치는 **TTY에서 별도로 확인해야 하며 `--yes`도 생략하지 못합니다. 비TTY에서는 거부**합니다. `--check`는 비TTY에서도 설치 없이 확인할 수 있습니다. 압축을 푼 폴더는 자동 후보가 아니지만 그 폴더의 `./install.sh`는 첫 설치·재설정 대안으로 동작합니다.
공개 전 개발판을 거르는 표지로 루트의 **정확한 `LICENSE` 이름·비어 있지 않은 일반 파일·첫 줄 `MIT License`**를 확인합니다. 이 표지는 ZIP 출처나 작성자의 진위를 증명하지 않습니다. 버전 번호 자체는 차단하지 않아 이후 정식 공개 버전으로도 업데이트할 수 있습니다.

설치 전 안전한 경로·일반 파일 속성·압축 해제 총량 **64MiB 이하**·VERSION **32바이트 이하**를 확인하고 `unzip -tq`로 무결성을 검사합니다. 권한 0700 임시 디렉터리에 macOS `ditto`로 풀어 한글 파일명과 실행 권한을 보존한 뒤, **실제 트리**의 단일 최상위 폴더·필수 일반 파일·중복을 확인합니다. 절대경로·`..`·링크·비정규 파일·대소문자/Unicode 정규화 충돌·압축 해제 중 덮어쓰기는 거부합니다. 한글 이름을 손실시키는 목록 출력으로 파일의 중복 여부를 판단하지 않습니다. 검증이 끝난 뒤에만 `✓ zip 검증`, 현재 → 새 버전, 두 버전 사이의 변경 내역을 보여 줍니다. 변경 내역의 C0·C1·bidi 제어문자는 제거합니다. GitHub·직접 지정한 비Downloads ZIP은 비TTY에서 `--yes` 없으면 안내만 하고 설치하지 않습니다. Downloads는 `--yes`여도 TTY 확인을 요구합니다. `--check`는 임시 파일을 정리하고 설치본·설정에 손대지 않습니다. 같거나 낮은 버전은 **이미 최신**으로 안내하고 설치하지 않습니다. 낮은 버전이 필요하면 아래 롤백 절차를 따르세요.

업데이트는 새 zip의 `install.sh --update`로 **기존 설치 트랜잭션만** 실행합니다. manifest의 `configuration_path`에 기록된 기존 설정을 읽으므로 사용자 지정 경로도 유지합니다. 명시한 `ROUTINE_CONFIG`가 설치 기록과 다르면 경로를 바꾸지 않고 중단·안내합니다. 설정 파일 자체와 수집 데이터·로그·install-id는 보존하며, 로그인·권한 요청·첫 실행·수집·LLM·Slack 조작은 하지 않습니다. 아침 루틴이나 스크럼 붙여넣기가 실행 중이면 파일 교체를 미룹니다. 파일·복사/검토 앱·LaunchAgent를 갱신하고 **LaunchAgent 로드까지 성공한 뒤에만** 새 세대를 확정합니다. 실패하면 기존 manifest/소유권 검증·journal 복구로 되돌립니다.

강제 종료 등으로 journal 또는 `.previous` 세대가 남으면 버전이 같아도 최신으로 판단하지 않습니다. `routine update --yes`는 버전 비교 전에 소유 확인된 중단 기록을 복구하고 다시 업데이트합니다. `--check`와 동의 없는 실행은 복구 안내만 하며, `routine status`는 미완료 설치와 미등록 LaunchAgent를 경고합니다. 실행 중인 루틴이나 다른 설치 작업이 있으면 복구도 미룹니다. 설치본 명령을 실행할 수 없으면 **새 zip을 풀고 그 안의 `install.sh --update`**를 실행하세요.

새 설정 키는 **이전 동작을 유지하는 의미 있는 기본값**을 `config.jq`에 두고, 이전 저장 형식 변환은 순수한 `migrate_config`에서 처리합니다. 업데이트는 이 결과를 메모리에서 사용할 뿐 저장된 설정을 자동으로 덮어쓰지 않습니다. 기본값으로 채울 수 없는 새 필수 키나 사용자 선택이 필요하면 설치 전에 멈춥니다. 이때는 기존 설치본의 `routine init`이 아니라 **새 zip을 직접 풀어 새 `routine 설치.command` 또는 새 `bin/routine setup`**으로 설정을 확인하세요. 값·경로 변경은 사용자 확인 후 진행합니다.

완료 시 업데이트된 버전을 표시합니다. 사용자가 지정하거나 Downloads에서 찾은 zip은 그대로 보관하고, GitHub에서 받은 임시 zip은 종료 시 정리합니다. `routine status`와 아침 요약/알림은 같은 공개 목록을 **총 5초 이내**로 조회하고 `~/Library/Caches/routine-automation/releases.json`에 0600 권한으로 하루 한 번 캐시합니다. 실패도 그날 캐시하며 **Downloads를 탐색하거나 알리지 않습니다. 설치본 VERSION**보다 높은 GitHub 버전만 `새 버전 <VERSION> — routine update`로 안내합니다. asset 다운로드나 자동 설치는 하지 않습니다.

업데이트 명령이 없거나 공개 베타보다 높은 번호의 비공개 개발 설치본에서 전환할 때는 최신 zip을 먼저 풀고 **`/bin/bash "$HOME/Downloads/routine-automation-<VERSION>/install.sh" --update`**를 한 번 실행하세요. 이 명시적 경로는 버전 번호가 내려가는 전환에도 기존 설정·데이터·설치 신원을 보존하며 첫 실행을 하지 않습니다. `routine update` 자체는 같은 버전이나 낮은 버전을 설치하지 않습니다.

### 첫 설치·재설정의 세부 동작

터미널에서 `gum`이 있으면 링크·수동 값 입력, 확인 질문, Git 위치·수집 소스의 복수 선택과 권한 안내 박스를 gum으로 표시합니다. `dependencies` 단계는 gum이 없을 때 설치를 제안하지만 **명시적으로 동의한 경우에만** `brew install gum`을 실행합니다 (`--yes`로 동의를 대신하지 않음). 거절하거나 설치가 실패해도 기존 텍스트 방식으로 계속 진행합니다. gum은 선택 의존성이며, 없거나 비 TTY이면 텍스트 방식이 유지됩니다. `--non-interactive`에서는 질문하지 않습니다.

체크리스트는 기존 상대 이동 방식으로 갱신합니다. TTY에서는 `routine 설정 · 10단계` 머리글 아래 한글 단계 이름을 고정 셀 폭으로 맞추고, 완료·실패 단계의 소요 시간을 오른쪽에 표시합니다. 대기 `○`·건너뜀 `–`·실행 안 함 `·`은 회색, 진행 중 기호는 파랑, 완료 `✓`는 초록, 실패 `✗`는 빨강입니다. 이름은 기본색, 건너뜀 사유·실행 안 함·시간은 회색(245)을 사용합니다. 비 TTY에서는 내부 단계 ID를 포함한 기존 출력 형식을 유지합니다. init은 `설정 N/M · 이름` 머리글로 진행하며, 클립보드 방식은 4단계, 자동 붙여넣기는 Slack 정보 단계를 포함한 5단계입니다. 머리글은 빈 줄, 회색 단계 번호와 기본색의 굵은 이름, 최대 48셀의 얇은 구분선으로 구성합니다. gum 모드의 전환·종료는 현재 단계가 소유한 화면 안 출력만 지워 이전 질문·요약이 쌓이지 않게 합니다. 커서·입력 기호는 파랑(75), 선택 기호는 초록, 확인 필요·선택 불가는 노랑 또는 빨강입니다. `NO_COLOR`가 설정되어 있거나 gum이 없거나 비 TTY이면 색을 쓰지 않습니다.
첫 실행 대기는 이번 kickstart 직전의 로그 위치부터 읽어 `수집 중 · 0:42`, `초안 작성 중 (LLM) · 0:12`처럼 현재 작업과 해당 작업의 경과시간을 표시합니다. 수집 중에는 `git ✓ · PR ✓ · omp 세션 …`처럼 소스별 상태도 보여 줍니다. 완료한 작업의 시간은 회색으로 누적하되 한 줄에 들어가지 않으면 현재 작업만 표시합니다. 아래에는 `보통 1~3분 · s 키: 기다리지 않고 넘어가기 (실행은 계속)` 안내가 나옵니다. 대기 중에는 비정규 입력 모드로 전환하고 커서를 숨겨 터미널의 비밀번호 입력 표시가 나타나지 않게 하며, 완료·중단·Ctrl-C/SIGTERM 뒤에는 원래 입력 모드와 커서를 복원합니다.
안내 박스는 정보(💡), 주의(⚠️), 오류(⛔), 성공(✅), 요약(📋), 권한(🔐)을 구분합니다. 제목은 기본색으로 굵게, 본문은 기본색으로 표시하고 아이콘과 테두리에만 상태색을 사용합니다. 정보·요약 테두리는 회색, 주의·권한은 노랑, 오류는 빨강, 성공은 초록입니다. 확인 버튼은 선택 상태에서 파랑 배경(25)에 굵은 흰 글자(231), 미선택 상태에서 짙은 회색 배경(237)에 밝은 글자(252)를 사용합니다. 전경/배경 대비는 각각 6.45:1, 7.37:1입니다. 목록은 파란 커서 `›`, 회색 미선택 기호 `○`, 초록 선택 기호 `●`로 구분하고 항목 글자는 터미널 기본색을 사용합니다.
파일·파이프로 보내는 stdout은 평문을 유지하고, `/dev/tty`의 대화형 화면만 색을 사용합니다. 긴 줄은 터미널 폭에 맞춰 줄바꿈하며 macOS의 NFD 한글 경로·결합 문자는 실제 셀 폭으로 셉니다. 지울 줄 수는 화면에 남아 있는 init 출력 범위로 제한해 앞선 셸 출력이나 체크리스트를 건드리지 않습니다. 좁은 터미널에서는 요약 박스 대신 텍스트 표를 사용하며 화면 밖 스크롤백은 지우지 않습니다.

setup의 마지막 화면은 체크리스트 한 벌과 결과 안내로 정리합니다. 실패 안내는 단계 이름과 소요 시간, 개인 값이 포함되지 않는 단계별 확인 사항, `~`로 축약한 로그 경로, `routine setup` 재실행 안내를 표시합니다. 로그 경로는 자체 줄에 두고 폭을 넘으면 줄바꿈합니다. 좁은 화면과 NO_COLOR에서는 텍스트 안내를 사용합니다. 성공 안내는 총 소요 시간과 `routine status`·설정 변경 안내를 표시합니다. standalone init은 저장 시 `✓ 설정 저장`, 취소 시 `– 설정 저장 취소, 기존 설정 유지` 한 줄을 남깁니다.
최근 first-run의 전체 디스크 접근 상태가 `denied`이면 TTY 완료 화면에도 보호 경로 읽기 거부 경고를 남깁니다. TTY first-run 실패에서도 `/bin/bash`의 전체 디스크 접근 보고를 유지합니다.

| 단계 ID | 수행 내용 |
|---|---|
| `platform` | macOS·Homebrew 확인. Homebrew가 없으면 설치 안내 후 중단 |
| `dependencies` | `jq >=1.7`(macOS 내장 1.7.1 포함), `coreutils`의 `gtimeout`, `gh` 확인. 누락/구버전은 설치 전 `[Y/n]` 확인. TTY에서는 선택 의존성 gum 설치를 별도 `[y/N]` 확인 |
| `github` | `gh auth status`. 미로그인이면 `gh auth login` |
| `llm` | Claude 로그인 JSON의 `loggedIn` 확인. `/login` 완료를 폴링하거나 omp 선택. Claude 공식 설치 명령은 확인 후 실행 |
| `slack` | Slack 데스크톱 앱 설치 확인 |
| `orca` | 자동 붙여넣기 선택 → Orca 앱·실제 Slack 화면/스크린샷 읽기로 권한 검증. 필요하면 접근성·화면 기록 패널을 열고 2초마다 재확인. **brew의 orca cask는 다른 제품이므로 사용하지 않음** |
| `disk-access` | 터미널 읽기는 참고만 표시. TTY에서 `/bin/bash` 권한 설정 패널·명시적 확인 |
| `config` | `routine init`. 기존 설정은 유지하거나 사용자 확인 후 덮어쓰기 |
| `launchd` | 개인 설정의 시간·요일·라벨로 LaunchAgent 생성·로드 |
| `first-run` | `launchctl kickstart`로 설치된 `routine run` 실행. 수집+LLM 초안만 실행하고 GUI·업데이트·AWS 단계는 생략. 결과 파일·다음 예약 출력 |

로그인 대기 중 `s`를 누르면 해당 단계를 건너뜁니다. 첫 실행 확인 중에도 `s`로 대기만 건너뛸 수 있으며 이미 시작한 LaunchAgent는 계속 실행됩니다. 실패하면 해당 단계에서 중단합니다. 첫 실행의 morning 성공/실패 결과를 요청 ID로 확인하여 실패 즉시 중단하고 표지를 정리합니다. 재실행하면 의존성·로그인·기존 설정을 다시 확인하고 충족된 단계는 완료로 표시합니다.
Orca 선택은 설정 질문보다 먼저 진행합니다. 기본은 클립보드이며, 자동 붙여넣기를 고르면 Slack 화면 읽기에 필요한 접근성과 결과 확인에 필요한 화면 기록 권한을 안내합니다. 권한을 허용하면 질문 없이 실제 읽기 성공으로 완료하고, `s`로 건너뛰면 전달 방식을 `clipboard`로 저장합니다. 체크리스트는 그린 줄 수만큼 상대적으로 올라가 지우고 다시 그립니다. 대화형 출력 전에는 이전 체크리스트를 지우고 줄 수를 초기화하므로, 터미널이 스크롤되어도 질문을 덮거나 체크리스트가 쌓이지 않습니다. 스피너 중에는 터미널 에코를 끄고, 종료·중단 시 원래 모드를 복원합니다. 스피너가 실제로 그린 줄 수도 부모에 전달해 다음 질문 앞에서 정확히 지웁니다.
설치 파일·저장된 설정·로드 상태가 같으면 파일 복사·앱 재컴파일·LaunchAgent 재로드를 하지 않습니다. 같은 버전·설정·날짜의 첫 실행이 이미 검증됐으면 kickstart도 반복하지 않습니다. 보호 경로 읽기가 거부된 첫 실행은 권한 변경 뒤 재검증합니다.

```bash
bin/routine setup --yes --non-interactive --skip disk-access
bin/routine setup --overwrite-config
bin/routine setup --skip first-run
```

`--yes` 없이 비대화형 설치 명령을 실행하지 않습니다. **`--yes`는 전체 디스크 접근 허용을 확인한 것으로 취급하지 않습니다.** 터미널에서 `~/Library/Mail`을 읽을 수 있어도 launchd의 `/bin/bash` 권한 증거가 아니므로, TTY에서 시스템 설정을 열고 직접 확인합니다. 터미널 읽기 실패만으로 확인 후 설치를 막지 않습니다. 실제 first-run morning(`/bin/bash`)이 같은 보호 경로를 읽어 결과 JSON에 `readable`/`denied`/`unverified`를 기록합니다. 경로가 없으면 미검증이며, 거부는 설치 실패가 아니라 `/bin/bash에 전체 디스크 접근 허용 필요` 경고입니다. setup/status/doctor에서 최근 결과와 `--skip disk-access` 안내를 확인할 수 있습니다. `--non-interactive`는 로그인·권한 확인을 대신하지 않으며, 이전의 명시적 확인이 없으면 TTY에서 확인하거나 해당 단계를 건너뛰세요.

대화형 설치의 전체 디스크 접근 단계는 시스템 설정을 열고 `[+]` → `Cmd+Shift+G` → `/bin/bash` 추가 순서를 화면에 안내합니다. `n`으로 답하면 설치를 멈추지 않고 이 단계만 건너뛰며, 첫 실행에서 실제 권한을 다시 확인합니다.

설치 파일은 `~/.local/share/routine-automation`, PATH 링크는 **`~/.local/bin/routine` 하나**입니다. 기존 `morning`, `scrum-collect`, `scrum-draft`, `scrum-paste` 링크는 이 설치 또는 현재 배포 폴더를 가리킬 때만 제거합니다. 남의 링크는 보존합니다.

설치 루트의 `install-id`와 `manifest.json`에 파일 경로·SHA-256, 링크 대상이 기록됩니다. 새 zip을 **다른 폴더**에 풀어 `./install.sh`를 실행해도 같은 설치를 업데이트하며 설정·수집 데이터·로그는 보존됩니다. 경로 문자열을 설치 신원으로 사용하지 않습니다. 기존 `.source-repo`/`.files` 설치는 기존 파일 목록·링크·프로그램 경로를 검증한 뒤 새 manifest로 이전합니다. 소유하지 않은 파일/앱/plist 또는 변경된 관리 파일은 덮어쓰거나 삭제하지 않고 중단합니다. 설치 복사본의 `com.apple.quarantine` 속성을 제거합니다.
관리 파일·링크·앱이 이미 삭제됐으면 업데이트/제거를 막지 않습니다. plist 파일이 없어도 manifest의 경로에서 라벨을 구해 로드된 서비스를 bootout합니다. 재설치는 누락 자산을 복원하되, 존재하는 파일의 해시 불일치는 계속 거부합니다. 완성된 manifest를 포함한 임시 설치 루트를 rename으로 교체하며 실패하면 이전 루트·외부 자산과 기존에 로드됐던 LaunchAgent를 복원합니다.
SIGKILL로 중단돼도 다음 setup/uninstall이 `.previous`와 설치 journal의 ID·경로·파일 해시를 확인해 이전 자산을 복원하고 소유가 확인된 `.routine-install.*`/`.routine-transaction.*`만 정리합니다. 루트가 `.previous`에만 있어도 uninstall할 수 있습니다. 다른 설치가 진행 중이면 중단합니다. 소유 journal에 사용자가 추가/변경한 파일이 있으면 이전 세대를 삭제하지 않고 복구를 중단하며, 소유를 확인할 수 없는 별도 임시 디렉터리는 보존합니다.
검토 앱을 모르는 이전 버전으로 롤백할 때는 **현재 버전의 `routine uninstall`을 먼저 실행한 뒤 이전 패키지를 설치**하세요. `--purge` 없이 제거하면 설정·데이터·로그가 보존됩니다. 이전 버전으로 현재 설치를 직접 덮어쓰거나 제거하면 검토 앱 경로의 소유 검증에서 차단될 수 있습니다.

```bash
routine uninstall           # LaunchAgent·링크·복사/검토 앱·설치 루트만 제거
routine uninstall --purge   # 설정·데이터·로그도 제거
```

실행 중인 LaunchAgent의 `bootout`이 실패하면 제거를 중단합니다. 외부 파일은 manifest와 일치할 때만 제거합니다. `~/Applications/스크럼 초안 복사.app`과 `스크럼 초안 검토.app`도 설치가 소유한 경우에만 제거합니다. 앱에 추가되거나 변경된 파일이 있으면 제거를 거부합니다.
설정 JSON이 깨져 있어도 manifest 소유 검증으로 uninstall할 수 있습니다.

## 설정

기본 경로는 `~/.config/routine-automation/config.json`, 권한은 **0600**입니다. `ROUTINE_CONFIG`로 재정의할 수 있습니다. 심볼릭 링크 설정 파일은 거부합니다. 우선순위는 **CLI 플래그 > `ROUTINE_*` 환경 변수 > 설정 파일 > 기본값**입니다. `routine --set KEY JSON <cmd>`는 해당 실행과 자식 명령에만 적용하며 설정 파일을 바꾸지 않습니다.

```bash
routine init
routine init --non-interactive \
  --slack-link 'https://example.slack.com/archives/CEXAMPLE/p1790895609247049' \
  --slack-team-id TEXAMPLE \
  --identity-git-authors '["example@example.com","42+example@users.noreply.github.com"]' \
  --sources-git-roots '["/Users/example/Developer","/Users/example/work/service"]' \
  --draft-llm-engine claude --delivery-mode clipboard
routine config get draft.llm.engine
routine config set draft.llm.model '"sonnet"'
routine --set draft.project '"일회용 프로젝트"' draft
```

Slack 글 링크에서 `workspace_domain`, `channel_id`를 추출합니다. `team_id`는 필수이며, `channel_name`, `post_title`, `slack_display_name`은 **gui-paste에서만 필수**입니다. 클립보드 복사와 Slack 검색 수집에는 이 세 값이 필요하지 않습니다. 프로젝트 이름은 선택 항목이며 대화형으로 묻지 않습니다. Git 수집을 켜면 `git_authors`와 하나 이상의 `sources.git.roots`가 필요하고, Notion을 켜면 `notion_email_like`가 필요합니다. Git author는 `git config user.email`과 `gh api user`의 GitHub noreply 주소로 감지합니다. 시스템 시간대와 `$USER` 기반 라벨을 사용합니다. Claude가 있으면 claude, 없으면 omp, 둘 다 없으면 none을 제안합니다.
링크의 워크스페이스가 바뀌면 이전 팀 ID·표시 이름을, 채널이 바뀌면 이전 채널 이름·글 제목을 비웁니다. 같은 init 호출에 명시한 Slack 플래그는 링크 적용 뒤에 반영하므로 새 대상의 지정값이 지워지지 않습니다. 최종 확인에서 링크를 다시 편집할 때는 이전 대상의 종속 값을 비우고 다시 확인합니다.
대화형 init은 **스크럼 글 링크 하나**를 먼저 묻고, 워크스페이스 ID는 Slack의 `~/Library/Application Support/Slack/storage/root-state.json`에서 링크 도메인으로 읽기 전용 감지합니다. 실패할 때만 ID를 추가로 묻습니다. gui-paste이면 이동 전 전면 앱을 기록하며, `ui.terminal_bundle_ids`에 등록된 터미널 앱일 때만 `open -g`로 채널 딥링크를 열고 화면 감지를 진행합니다. 기본 목록에는 Terminal·iTerm2·VS Code·Cursor·주요 JetBrains IDE·Alacritty·WezTerm·kitty·Ghostty·Warp·cmux·Orca가 포함되며, 다른 터미널은 기존 목록에 bundle ID를 추가할 수 있습니다. 브라우저 등 다른 앱이면 이동 없이 수동 입력합니다. 링크의 `p<타임스탬프>`가 화면에 나타날 때까지 최대 5회, 1초 간격으로 확인한 뒤 채널·내 표시 이름·해당 타임스탬프를 감싸는 가장 가까운 메시지 컨테이너의 `<접두어>:`를 제안합니다. 가까운 컨테이너에 접두어가 없거나 들여쓰기로 메시지 경계를 확인할 수 없으면 제목을 제안하지 않습니다. 접두어가 작성자 이름일 수도 있으므로 제안을 확인하고 수정하세요. 댓글 수·답장 버튼·이전 글의 컨테이너에서 제목을 가져오지 않습니다. 연결된 글을 찾지 못하면 모든 제안을 버리고 수동 입력으로 진행합니다. 감지가 끝나면 약 1.5초 동안 전면 앱을 반복 확인하고 필요하면 터미널로 복원한 뒤 첫 입력을 받습니다. 매 질문의 입력을 읽기 직전에도 원래 터미널인지 확인하며, 복원에 실패하면 터미널을 클릭한 뒤 Enter로 확인할 때까지 기다립니다. 클릭·입력·전송은 하지 않습니다. standalone init에서 권한이나 실행 가능한 Orca가 없으면 수동 입력으로 진행합니다.
이어서 Git 위치와 수집 소스를 선택합니다. 세션 폴더가 없는 소스 등은 기본 선택에서 빠지며, 사용 불가 소스를 켜려 하면 필요한 조건을 안내하고 거부합니다. 비대화형 init은 명시한 플래그를 유지하며, 없는 세션 폴더는 명시적으로 켜지 않은 경우에만 자동 비활성화합니다.
Slack 정보 다음에는 채널·표시 이름·글 제목의 감지/입력/기존 값 구분, git 작성자 목록, LLM과 전달 방식을 요약 카드로 보여 줍니다. 라벨은 고정 폭 열에 기본색으로 굵게 표시하고, 구분선은 회색, 값은 기본색으로 유지합니다. 출처는 작은 상태색 점과 회색 `감지`·`입력`·`기존 값`·`미설정` 글자로 표시합니다. Slack, 수집, 초안·전달 묶음 사이에 빈 줄을 둡니다. gum에서는 테두리 박스, 텍스트 모드에서는 열을 맞춘 표를 사용하며 배열 JSON을 그대로 출력하지 않습니다. Git 위치 후보 탐색의 **세션 기록에서 저장소 위치 찾는 중…**과 읽기 전용 **Slack 화면 이동**은 gum 스피너로 표시합니다. 스피너는 명령을 한 번만 실행하고 성공/실패의 출력·종료 코드를 보존하며 실패한 명령을 다시 실행하지 않습니다. Slack 화면 이동 전후의 터미널 포커스 확인은 그대로 유지합니다.
대화형 설정은 저장 전에 **전체 설정 요약**(Git 위치·수집 소스·예약 요일/시각 포함)과 **저장 / 항목 고치기 / 취소**를 표시합니다. 고치기에서는 Slack 글 링크, 자동 붙여넣기의 Slack 정보, Git 위치, 수집 소스 또는 git 작성자를 골라 그 단계만 다시 실행한 뒤 최종 확인으로 돌아갑니다. 질문·항목 선택 중 Esc는 기존 값을 유지하고, **최종 확인의 취소·Esc는 저장 없이 종료**합니다 (`init` 종료 코드 1, setup의 `config` 단계 ✗와 재실행 안내). Ctrl-C는 setup 전체를 중단하며 설정 파일을 바꾸지 않습니다. 비대화형 init은 최종 확인 없이 기존처럼 검증 후 저장합니다. 필수 값이 비어 있으면 저장 전 검증에서 안내합니다.
필수 값이 없거나 형식이 잘못되면 이유를 표시하고 최종 메뉴에 머무릅니다. 이 상태에서 저장을 골라도 입력은 사라지지 않으며 항목 고치기로 수정할 수 있습니다. Git 위치를 0개로 확정하면 git 커밋 수집을 끌지 확인하고, 끄지 않으면 수집 소스 단계에서 선택을 고칩니다. Git 위치 재편집은 부분 선택·빈 선택을 그대로 유지합니다. git 작성자 재편집에는 **고치기 · git 작성자** 머리글을 사용하며 Enter로 기존 순서·값·감지 출처를 유지합니다. 텍스트 최종 메뉴의 Enter·범위 밖 번호·오타는 다시 묻고, 취소 항목의 번호 또는 EOF에서만 저장 없이 종료합니다.
gum 화면에서는 Space로 여러 항목을 선택하고 Enter로 확정합니다. 현재 선택은 미리 표시하며, 사용 불가 소스도 필요한 조건을 라벨에 표시합니다. 이를 선택하면 이유를 안내하고 재선택을 요청합니다. Git 저장소가 없으면 위치를 다시 고를 수 있고, 위치 0개 확정에는 기존 확인 질문을 유지합니다. Slack 화면에서 감지한 값은 gum 사용 시 확인하거나 수동으로 수정할 수 있습니다. gum 호출 전후에도 기존 `ensure_prompt_focus`로 원래 터미널이 전면인지 확인합니다.
`routine sources`를 파일·파이프로 출력할 때는 기존 `[ ]`·`[선택]`·`– 필요 조건` 평문 표지를 유지합니다. `○`·`●`·`⚠` 표지는 TTY 목록에서만 사용합니다.
자동 세션 후보만 물리 경로로 정규화한 홈 하위 폴더로 제한합니다. 저장된 Git 위치와 직접 `+경로`로 추가한 위치는 외장 볼륨이나 홈 밖을 가리키는 심볼릭 링크도 사용할 수 있습니다. `/Volumes/` 아래 저장 위치가 현재 연결되지 않았으면 `연결 안 됨`으로 표시하고 Enter 기본 확정에서는 유지합니다. 위치 번호를 명시적으로 해제해야 목록에서 제거합니다. 그 외 존재하지 않는 저장 위치는 `경로 없음`으로 표시하고 기본 선택에서 해제합니다. 모든 위치에서 홈 자체·홈 상위 경로·`/`·`~/.omp/wt`·`~/.cache`·`~/Library`는 거부하며, 안전하지 않은 저장 후보를 제외하면 이유를 표시합니다. `--sources-git-roots`와 `config set`으로 새 위치를 저장할 때도 같은 검증·정규화를 적용하며 연결된 폴더가 필요합니다. 세션 후보 탐색은 최근 수정된 JSONL 최대 300개를 확인합니다. OMP는 첫 줄의 session 헤더만, Claude는 앞부분 최대 64KB·50줄에서 첫 유효 cwd를 읽으므로 cwd 없는 메타 레코드가 앞에 있어도 감지할 수 있습니다. cwd를 먼저 정규화·중복 제거해 Git 조회를 반복하지 않고, 전체 탐색은 15초로 제한합니다. 실패·시간 초과 시 저장된 위치와 일반적인 개발 폴더 후보로 계속 진행합니다.

**모든 스키마 항목은 init 플래그로 지정할 수 있습니다.** 점과 밑줄을 `-`로 바꾸세요. 예: `--sources-claude-sessions-dir PATH`, `--morning-extra-steps-aws-session true`, `--delivery-daily-attempts 6`. `--set dotted.key VALUE`도 사용할 수 있습니다. init의 문자열은 그대로, 배열·불리언·숫자는 JSON, nullable 값은 `null`로 받습니다. `config set`과 진입점의 `--set`은 문자열도 JSON 따옴표로 감쌉니다.
환경 변수와 진입점 `--set`은 실행에만 적용합니다. `config set`/`init` 저장은 파일의 값과 명시적으로 바꾼 값·자동 제안만 사용하므로 일시적 GUI 전달 설정 등이 파일에 새지 않습니다. 하위 명령의 `--help`는 설정 없이 동작합니다.
setup의 영구 LaunchAgent/복사 앱은 **저장된 설정**으로만 만듭니다. 전역 `routine --set … setup`은 거부하며, 바꾸려면 `routine config set` 또는 setup의 init 플래그를 사용하세요. 명시적 setup 플래그와 Claude 미설치 시 omp 선택은 설정에도 저장됩니다.
이전 설정의 idle 하한·시간 접두어 등이 새 스키마에 맞지 않아도 JSON 루트가 객체이면 `config set`으로 해당 필드를, `init --non-interactive` 플래그로 여러 필드를 동시에 수정할 수 있습니다. 최종 저장값은 현재 스키마를 통과해야 합니다.

| 키 | 타입·기본값 | 설명 |
|---|---|---|
| `identity.slack_display_name` | string, `""` | gui-paste 필수. 본인 댓글 중복 검사 이름 |
| `identity.git_authors` | string[], `[]` | Git 작성자 이메일/이름. 자동 제안 |
| `identity.notion_email_like` | string, `""` | Notion SQL LIKE 이메일 패턴. Notion 활성화 시 필수 |
| `slack.team_id` | string, 필수 | `T…` 팀 ID |
| `slack.workspace_domain` | string, 필수 | `<domain>.slack.com`의 domain |
| `slack.channel_id` | string, 필수 | `C…` 또는 `G…` 채널 ID |
| `slack.channel_name` | string, `""` | gui-paste 필수. 한국어 UI 스레드 라벨의 채널 이름 |
| `slack.post_title` | string, `""` | gui-paste 필수. 오늘 스크럼 글을 식별할 고유 제목 |
| `slack.post_time_prefix` | string, `오전 8:0` | `오전/오후 1–12시:분` 접두어. 분 첫 숫자 0–5, 둘째 숫자 0–9는 선택. 넓은 `오전 1`은 거부 |
| `draft.project` | string, `""` | 선택. 비어 있으면 분류가 최상위 글머리 |
| `draft.markers` | `none\|uncertain\|all`, none | 표시 접미사만 조절. 근거 수준·질문 검증은 동일 |
| `draft.headers.yesterday` / `.today` | string, `어제 작업한 내용` / `오늘의 작업 계획` | HTML·텍스트 제목 |
| `draft.categories` | string[], 현황 파악·배포·개발·인프라·업무 자동화·기타 | 분류 순서·프롬프트 |
| `draft.format.bullets` | string[1–6], `["•","◦","▪","▪"]` | 깊이별 글머리. 공백만 있는 값은 거부하며 더 깊은 단계는 마지막 값을 재사용 |
| `draft.format.layout` | `tree\|flat`, `tree` | flat은 분류 단계를 생략하고 같은 묶음 주제 아래 작업을 모음 |
| `draft.format.max_items_per_section` | 양의 정수/null, null | 어제·오늘 각각의 작업 수 상한. 초과 항목은 질문·검토에 `생략됨`으로 보존 |
| `draft.llm.engine` | `auto\|claude\|omp\|none`, `auto` | 자동 선택은 claude → omp → none |
| `draft.llm.model` | string/null, null | null이면 엔진 기본 모델 |
| `sources.git.enabled` / `.roots` | bool/string[], true / `["~/Documents/GitHub"]` | 각 위치 자체와 하위 깊이 2까지. 로컬 Git, fetch하지 않음 |
| `sources.prs.enabled` | bool, true | gh PR 검색·최신 상태 조회 |
| `sources.omp_sessions.enabled` / `.dir` | bool/path, true / `~/.omp/agent/sessions` | OMP JSONL 읽기 전용 |
| `sources.claude_sessions.enabled` / `.dir` | bool/path, true / `~/.claude/projects` | Claude Code JSONL 읽기 전용 |
| `sources.jira.enabled` / `.chrome_dir` | bool/path, false / 기본 Chrome 디렉터리 | 방문 이력에서 Jira 근거 |
| `sources.notion.enabled` / `.db` | bool/path, false / 기본 Notion DB | 본인 편집 이력 |
| `sources.slack.enabled` | bool, false | Slack GUI 소스 선택. 무인 morning은 GUI를 수집하지 않음 |
| `collect.until` | `today_start\|now`, today_start | 기본 상한은 실행일 로컬 00:00. `--until` 우선 |
| `ui.terminal_bundle_ids` | string[] | init에서 복원 가능한 터미널 bundle ID 목록. 다른 터미널은 기본 목록에 추가 |
| `delivery.mode` | `clipboard\|gui-paste`, clipboard | 기본은 초안 알림만 |
| `delivery.window.start` / `.end` | HH:MM, `08:10` / `11:30` | 자동 붙여넣기 창 |
| `delivery.no_post_after` | HH:MM, `09:00` | 오늘 글이 없을 때 재시도 종결 시각 |
| `delivery.idle_seconds` | integer ≥ 60, 180 | 자동 GUI 시작 전 사용자 유휴 시간 |
| `delivery.daily_attempts` | positive integer, 6 | 일일 GUI 시도 상한 |
| `morning.time` | HH:MM, `08:00` | 아침 예약 시각 |
| `morning.weekdays` | integer[], `[1,2,3,4,5]` | ISO 요일, 월=1·일=7 |
| `morning.extra_steps.omp_update` | bool, false | `omp update` |
| `morning.extra_steps.claude_update` | bool, false | `claude update` |
| `morning.extra_steps.npm_update` | bool, false | `npm update -g` |
| `morning.extra_steps.aws_session` | bool, false | `aws-session-check`, 항상 마지막 |
| `launchd.label_prefix` | string, `com.<$USER>.routine` | `.morning`/`.scrum-paste` 라벨 앞부분 |
| `timezone` | string/null, null=시스템 | 수집·초안·예약 표시 시간대 |

기존 환경 변수 `ROUTINE_REPO_ROOT`(단일 경로 → roots 배열), `ROUTINE_GIT_AUTHORS`(공백 구분), `ROUTINE_OMP_SESSIONS`, `ROUTINE_CHROME_DIR`, `ROUTINE_NOTION_DB`, `ROUTINE_NOTION_EMAIL_LIKE`, `ROUTINE_TZ`를 유지합니다. 다중 경로는 `ROUTINE_GIT_ROOTS` JSON 배열을 쓰세요. 새 이름에는 `ROUTINE_COLLECT_UNTIL`, `ROUTINE_DRAFT_MARKERS`, `ROUTINE_CLAUDE_SESSIONS`, `ROUTINE_LLM_ENGINE`, `ROUTINE_LLM_MODEL`, `ROUTINE_DELIVERY_MODE`, `ROUTINE_PROJECT`, `ROUTINE_SLACK_*`, `ROUTINE_*_ENABLED`, `ROUTINE_WEEKDAYS`, `ROUTINE_MORNING_TIME`, `ROUTINE_LABEL_PREFIX`가 있습니다. 전체 매핑은 `share/config.sh`에 있습니다. 배열 환경 변수는 JSON입니다(`ROUTINE_GIT_AUTHORS`만 기존 공백 구분 유지). `ROUTINE_NOW`는 격리 테스트용 시각입니다.

### Git 위치·수집 소스

Git 위치 후보는 OMP·Claude 세션의 `cwd`에서 감지한 저장소 최상위의 부모와, 존재하는 `~/Documents/GitHub`, `~/GitHub`, `~/Developer`, `~/dev`, `~/src`, `~/code`, `~/projects`, `~/workspace`, `~/repos`입니다. 홈 전체를 스캔하지 않습니다. 후보별 저장소 수를 표시하고 저장소가 있는 후보를 기본 선택합니다. 번호로 선택을 켜고 끄거나 `+/절대/경로`로 직접 위치를 추가할 수 있습니다. `.git` 디렉터리와 worktree의 `.git` 파일을 모두 찾고 공통 git 디렉터리로 중복을 제거합니다. 보호 폴더를 읽지 못하면 해당 위치 이름을 포함해 오류를 기록하며 다른 위치의 결과는 보존합니다.
gum의 Git 위치 목록에서는 **`+ 위치 직접 추가`**를 선택하면 경로 입력창이 열립니다. 입력한 위치도 같은 안전 검사·정규화를 통과해야 하며, 목록으로 돌아가 다른 위치와 함께 선택/해제할 수 있습니다. gum이 없는 텍스트 화면의 번호 토글·`+경로` 입력 방식은 그대로입니다.
이전 `sources.git.root`는 읽을 때 `roots: [root]`로 바뀌고 옛 키는 제거합니다. 다음 설정 저장 시 새 형태로 저장합니다. 이미 `roots`가 있으면 새 값을 우선합니다.

| 소스 이름 | 가져오는 것·방법 | 사용 조건 | 기본 선택 |
|---|---|---|---|
| git 커밋 (`git`) — 내 작성 커밋 | 작성자별 로컬 커밋, `git log --all` | 선택 위치에 저장소·작성자 신원 | 켬, 없으면 대화형에서 끔 |
| GitHub PR (`prs`) — 내가 만든·리뷰한 PR | 작성·리뷰·댓글 PR와 최신 상태, `gh` 읽기 | gh 로그인 | 켬, 미로그인이면 끔 |
| omp 세션 (`omp_sessions`) — AI 작업 보고 | 사용자 요청·assistant 결과, 로컬 JSONL | OMP 세션 폴더 | 폴더가 있으면 켬 |
| Claude Code 세션 (`claude_sessions`) — AI 작업 보고 | Claude Code 요청·assistant 결과, 로컬 JSONL | Claude 세션 폴더 | 폴더가 있으면 켬 |
| Jira (Chrome 방문 기록) (`jira`) | Jira 방문 이력, Chrome 각 프로필 History의 읽기 전용 스냅샷 | Chrome 앱·프로필 | 끔 |
| Notion 편집 기록 (`notion`) | 본인 편집 페이지, 로컬 DB의 읽기 전용 스냅샷 | Notion 앱·기록 DB·이메일 LIKE 패턴 | 끔 |
| Slack 내 메시지 (`slack`) — 자동 붙여넣기 전용 | 본인 메시지 검색, Orca GUI 읽기 | gui-paste·Slack·Orca | 끔, 무인 morning에서는 제외 |

setup의 소스 질문과 `routine sources` 목록은 같은 한글 표시 이름·설명을 사용합니다. 명령 인자는 기존 내부 이름(`git`, `prs`, `omp_sessions` 등)을 그대로 사용합니다.

소스 질문에 `5 6`을 입력하면 Jira·Notion 선택을 토글하고, Enter로 확정합니다. Notion을 켜면 Git 이메일을 LIKE 패턴의 기본값으로 제안합니다. Jira는 기존 Chrome 프로필 경로를 사용합니다.

Jira·Notion은 원본 DB를 읽기 전용 online backup으로 먼저 수집합니다(잠금 대기 250ms, `gtimeout`/`timeout`이 있으면 프로세스 상한 3초). Chrome의 배타 잠금 등으로 backup이 실패하면 DB와 존재하는 `-journal`·`-wal`·`-shm`을 0700 임시 디렉터리에 복사합니다. 복사 전후 파일 크기·inode·나노초 mtime/ctime·동반 파일 유무가 달라지면 최대 3번 다시 복사합니다. hot journal/WAL 복구와 `journal_mode=DELETE` 전환은 사본에서만 수행하고 `quick_check=ok`인 사본만 조회합니다. Jira는 스냅샷 실패 시 프로필마다 처음 시도 뒤 최대 3회 재시도하며, 다른 정상 프로필의 행은 유지합니다. 원본은 쓰기로 열거나 체크포인트하지 않습니다. 파일 복사는 원자적 스냅샷이 아니므로 지속적인 쓰기·체크포인트 경합에서는 재시도 후 오류가 남을 수 있습니다.

```bash
routine sources                         # 선택 상태·사용 조건
routine sources enable claude_sessions  # 사용 가능할 때만 켬
routine sources disable jira            # 설정 파일만 변경
routine config set sources.git.roots '["/Users/example/dev","/Users/example/work"]'
```

### 수집 기간

기본 `collect.until=today_start`는 실행일 로컬 00:00 미만까지 수집합니다. 월요일은 금요일 00:00부터 월요일 00:00까지, 그 외에는 전날 00:00부터 오늘 00:00까지입니다. 시작은 포함하고 상한은 제외합니다. DST가 바뀌어도 로컬 달력 날짜를 기준으로 잡습니다. `now`는 실행 시각 미만까지이며 `--since`·`--until`이 설정보다 우선합니다. 실제 기간은 수집 JSON/Markdown과 `routine status`에 표시합니다. 이번 수집에서 제외한 오늘 활동을 “오늘 계획” 근거로 자동 재분류하지는 않습니다.

### 프로젝트·표지

프로젝트가 비어 있으면 현황 파악·배포·개발 등의 분류가 text와 HTML의 최상위 글머리가 됩니다. 필요하면 `--project` 또는 `draft.project`로 한 단계 위 묶음을 넣을 수 있습니다.
표지 기본값은 **none**입니다. `none`은 수준/확인 필요 접미사를 숨기고, `uncertain`은 `(확인 필요)`만, `all`은 기존의 `(검토)`·`(병합)`·`(운영 배포)`·`(확인)`까지 표시합니다. 메모로 지정한 `(보류)`는 모든 모드에서 유지합니다. 표시를 줄여도 항목을 버리거나 근거 수준을 높이지 않으며 내부 `level`과 questions.md는 동일합니다.

```bash
routine config set draft.markers '"uncertain"'
routine config set collect.until '"now"'
```

### 스타일·출력 형식

`routine style`은 스타일 파일 경로·글자 수·처음 6줄과 현재 `draft.format`을 보여줍니다. 선택 파일의 기본 경로는 `~/.config/routine-automation/style.md`이며, `ROUTINE_CONFIG`를 지정하면 **그 설정 파일과 같은 디렉터리**의 `style.md`를 사용합니다. `routine style edit`은 파일이 없으면 안내 주석을 담은 템플릿을 0600으로 만들고 `$EDITOR`로 엽니다. EDITOR는 사용자가 신뢰하는 셸 명령으로 해석하므로 인용한 공백 경로·옵션을 쓸 수 있습니다. 비어 있거나 공백뿐이면 `open -t`를 사용합니다. 사용자 소유의 읽기 가능한 일반 파일만 읽고 0600으로 맞춥니다. 사용자 소유 파일을 가리키더라도 심볼릭 링크는 대상 파일을 읽거나 chmod하지 않습니다. 링크·디렉터리·읽기/권한 보호 실패는 초안 생성에서 **경고 후 스타일 없이 계속** 진행하며, 조회·편집에서는 오류를 반환합니다.

말투·길이·용어 선호를 자유롭게 적으세요. Claude·OMP 초안 프롬프트에 데이터 블록 밖의 `## 사용자 스타일` 지시로 넣되, HTML 주석을 제거한 뒤 Unicode 문자 기준 **처음 2,000자만 적용**하며 초과하면 경고합니다. 파일 원문은 자르지 않으며 주석만 있는 빈 템플릿은 스타일 지시로 넣지 않습니다. 스타일은 표현만 바꾸고 **근거 수준·근거 규칙·출력 스키마를 바꿀 수 없습니다**. 스타일을 따라 LLM이 근거보다 높은 level을 반환해도 기존 검증에서 강등하며, 근거보다 강한 완료 표현은 전달 초안에서 제외하고 질문에 남깁니다.

기존 `scrum/notes.md`의 `## 표현 선호`는 계속 `notes_original`로 읽지만 신뢰할 수 없는 **데이터로만** 전달합니다. `## 보류`·`## 오늘 추가`의 기존 처리는 유지합니다. 표현 선호는 style.md로 옮기세요. `routine style`이 해당 제목을 찾으면 이전 안내 한 줄을 출력합니다. style.md가 없으면 초안 생성의 stderr와 setup·status에도 안내합니다. 메모·수집 데이터 안에 `## 사용자 스타일`이나 데이터 구분자를 적어도 신뢰 지시로 승격하지 않습니다.

```bash
routine style
routine style edit
routine config set draft.format.bullets '["→","-"]'
routine config set draft.format.layout '"flat"'
routine config set draft.format.max_items_per_section 5
routine style preview                    # 가장 최근 날짜의 기존 draft.json
routine style preview --date 2026-09-25   # 지정 날짜의 기존 draft.json
```

기본 tree·글머리·무제한 설정은 기존 text/HTML 출력을 그대로 유지합니다. flat은 분류만 생략하고 프로젝트가 있으면 최상위 프로젝트 묶음은 유지합니다. 커스텀 글머리 HTML은 기본 목록의 글머리가 중복되지 않도록 ul/li 없이 줄바꿈·들여쓰기로 만듭니다. 어제·오늘 상한은 JSON 항목 순서로 적용하며 오늘의 보류 항목은 상한 계산에서 제외합니다. 넘치는 정상 항목·근거를 draft.json에서 삭제하지 않고 questions.md와 검토 화면에 `생략됨`으로 남깁니다. 생략 사유는 근거 문제에 따른 제외 사유와 구분하며 status·초안 결과는 `전달 N · 생략 M`, 복사 안내·아침/붙여넣기 알림은 생략 수를 표시합니다. 검토에서 다른 항목을 해제한 뒤 생략 항목을 선택할 수 있으며 선택 수가 상한을 넘으면 미리보기 옆에 생략 수를 표시합니다. 제한을 없애려면 `routine config set draft.format.max_items_per_section null`을 사용하세요.

초안은 생성 당시의 `draft.format`을 포함한 `.settings` 스냅샷을 저장합니다. 나중에 설정을 바꿔도 `routine review`의 초기 미리보기·복사 결과는 저장된 draft.txt/draft.html의 형식을 유지합니다. 스냅샷이 없는 이전 초안의 검토에는 기본 tree·글머리·무제한 format을 강제해 현재 상한 때문에 기존 항목이 숨겨지지 않게 합니다. `routine style preview`는 LLM·수집 없이 기존 draft.json을 **현재 format만** 적용해 텍스트로 출력합니다. 다른 렌더 설정은 저장된 스냅샷을 유지하며 초안·질문·검토 파일을 덮어쓰지 않습니다. 스타일 문구를 바꾼 효과는 새 `routine draft` 실행에 반영됩니다.


### 보낸 글에서 배우기

```bash
routine learn                         # 어제: 직전 평일의 보낸 글과 그 날짜 초안 비교
routine learn --date 2026-09-25       # 특정 날짜
routine learn --paste                 # 모든 전달 모드에서 클립보드 글 사용
```

학습은 **명시적인 `routine learn` 호출에서만** 실행합니다. 수집 단계의 대화형 붙여넣기 시점에도 자동 획득하지 않는 보수적인 정책을 택했습니다. `morning`·`routine run`·`collect`·`paste --auto`에는 학습 경로를 연결하지 않습니다. 기본 날짜는 현지 시간 기준 직전 평일(월요일·주말이면 금요일)이며 공휴일 달력은 사용하지 않습니다. 지정 날짜의 `$HOME/Library/Application Support/routine-automation/scrum/<date>.draft.json`이 없거나 유효하지 않으면 외부 접근 없이 비0 종료합니다. 학습에는 설정된 `draft.llm.engine`이 필요하며 `none`이면 보낸 글을 읽지 않고 안내합니다.

gui-paste 모드는 **대화형 터미널에서만**, 설정된 터미널 앱이 전면일 때 실행 중인 Orca로 AX 텍스트를 읽습니다. Slack 탐색은 채널 `slack://` 딥링크 최대 한 번과 해당 글의 댓글 버튼 클릭 최대 한 번뿐이며, 대상 스레드가 이미 열려 확정됐다면 둘 다 생략합니다. 기존 `scrum_blocks`와 동일한 글 경계·제목·시간 규칙을 날짜에 맞춰 사용하고, 채널 ID와 루트 URL의 실제 날짜까지 확인합니다. 댓글 버튼의 **연속된 자식** 안에서 본인 표시 이름을 정확히 확인한 경우만 클릭합니다. 다른 반응 그룹·계정 메뉴의 이름은 근거로 쓰지 않습니다. 글이 여러 개이거나 본인 유무를 클릭 전에 확정할 수 없으면 클릭 없이 `--date YYYY-MM-DD`로 직전 근무일 지정 또는 `--paste`를 안내합니다. 클릭 직전에도 같은 루트·인덱스·라벨·본인 여부를 다시 확인합니다. 댓글 본문은 작성자의 reply 링크 뒤에서 같은 메시지 들여쓰기의 `container, Text:`만 읽고, 입력창·체크박스·전송·구분선·인용/첨부 컨테이너 등 **역할·들여쓰기 구조**에서 끊습니다. 일반 본문의 '첨부파일', '인용 기능', '새 메시지' 같은 단어는 경계로 쓰지 않습니다. 작성자 버튼의 제외 라벨은 정확히 일치할 때만 적용하며, 작성자가 생략된 연속 링크는 **같은 부모 메시지 컨테이너 안이고 사이에 더 얕은 줄이나 미인식 헤더가 없을 때만** 작성자를 이어받습니다. 다른 컨테이너·깊이가 다른 작성자·link/정적 텍스트 등 미인식 작성자는 본인으로 추정하지 않고 제외합니다. 반응 버튼은 본문을 자르지 않습니다. 타인 댓글·편집 메타데이터·작성 중인 입력창은 본문에서 제외합니다. 표시 이름만으로 동명이인을 구별할 수 없으므로 **GUI 획득도 redact 미리보기에서 본인 글인지 확인하고 LLM 전송에 동의해야** 비교·저장합니다.

학습은 입력창 포커스·타이핑·붙여넣기·체크박스·Return·전송을 **전혀 조작하지 않습니다**. 열린 스레드에 비어 있지 않은 입력이 있거나 상태를 확인할 수 없으면 딥링크·클릭 없이 중단합니다. 오늘 `.pasted` 또는 `.paste-attention` 표지가 있으면 **오늘 글의 댓글 버튼 자식에 본인 이름이 보이거나, 열린 오늘 스레드 입력창이 비어 있음을 확인한 경우만** 진행합니다. 이 확인도 설정된 채널 ID와 루트 URL 타임스탬프의 현지 오늘 날짜가 일치해야 합니다. 표지는 전송 후에도 남으므로 학습에서 지우지 않습니다. 확인할 수 없으면 '오늘 붙여넣은 초안이 아직 전송되지 않았을 수 있어 화면 학습을 하지 않습니다 — 전송 후 다시 실행하거나 --paste 사용'을 안내합니다. 살아 있는 morning 잠금과 조율하고 GUI 단계 동안 공유 `.scrum-paste.lock`을 잡아 붙여넣기와 겹치지 않게 합니다. 남은 잠금은 임의 회수하지 않습니다. 주말에도 `--paste`를 사용할 수 있고, 수동 해제하려면 PID 프로세스와 모든 routine 작업이 종료됐는지 먼저 확인한 뒤 해당 잠금의 `pid` 파일을 삭제하고 **빈 잠금 디렉터리만** 제거하세요(스크럼 출력 경로의 `.scrum-paste.lock`, `~/Library/Logs/routine-automation/.morning.lock`). 스크롤·검색·Orca 자동 실행도 하지 않으므로 글이나 본인 댓글이 보이지 않거나 AX 형식이 다르면 안전하게 중단합니다. 각 화면 조작 전 잠금·현재 콘솔 사용자·HID 입력 감지 가드를 적용합니다. 정상 종료와 오류의 전면 앱 복원은 공용 `restore_previous_app`을 사용하며, 활성화 요청이 무시되면 `lsappinfo`로 **실행 중인 원래 앱만** 확인하고 입력 가드를 재검사한 뒤 `open -b`로 복원합니다. 사용자 입력/다른 앱 전환이 감지되면 포커스를 빼앗지 않고 중단합니다(입력/잠금 중단 exit 4). 화면 획득을 시도한 모든 종료 경로에서 전면 앱을 다시 확인하여 Slack이 남았거나 상태 확인이 실패하면 OS 알림과 stderr에 **'Slack에 키를 입력하지 마세요'**를 표시합니다. 다른 앱으로 바뀌면 이를 안내하고 포커스를 바꾸지 않습니다.

`--paste`는 대화형 터미널에서 **읽기 전 확인 → pbpaste → redact한 미리보기 → 본인 글 확인·LLM 전송 동의** 순서입니다. 첫 확인을 거절하면 클립보드에 접근하지 않고, 두 번째를 거절하면 LLM·학습 저장·스타일 반영을 하지 않습니다. 일반 클립보드에 쓰거나 복원하지 않습니다. 비TTY `--paste`는 확인할 수 없어 읽기 전에 비0 종료합니다. 비TTY의 일반 `learn`은 해당 날짜에 이미 저장된 유효한 제안만 출력하며 GUI·클립보드 획득·LLM 호출·자동 반영은 하지 않습니다. 저장 결과가 없으면 대화형 학습을 안내하고 비0 종료합니다. 미리보기는 위험한 제어/형식·양방향/줄 구분·한글 채움 문자를 지우지 않고 `<U+202E>` 같은 코드포인트 표기로 보여 줍니다. 줄바꿈·탭, NFD 한글·결합 악센트, 이모지 VS16/ZWJ는 보존합니다. 이 표시는 미리보기용이며 LLM에는 redact된 원문을 그대로 보냅니다. 보낸 글은 최대 20,000자만 허용합니다.

보낸 글·초안 항목은 먼저 redact하고 `share/learn-prompt.md`의 **신뢰할 수 없는 JSON 데이터 블록**에 넣습니다. 설정된 Claude 또는 OMP를 기존 초안과 같은 도구·세션·규칙 격리 옵션과 빈 작업 디렉터리에서 호출합니다. 이 비교에 보내는 업무 문구는 해당 LLM 제공자에게 전달되므로 민감한 내용을 확인하세요. 응답은 `{"suggestions":[{"kind":"style|exclude|rename|category","text":"…","example_before":"…","example_after":"…"}]}` 객체 하나만 허용합니다. 실제 kind는 네 값 중 하나이며 추가 필드·잘못된 타입·20개 초과·text 300자 초과/빈 값·예시 각각 500자 초과를 거부합니다. 지침과 비어 있지 않은 예시는 보이는 문자가 있어야 하며 Unicode 제어 문자·ZWJ 이외의 형식 문자·양방향/줄 구분 문자·한글 채움 문자(U+115F/U+1160/U+3164/U+FFA0)와 `<!--`/`-->`를 거부합니다. 일반 결합 문자·NFD 한글·이모지 VS16/ZWJ는 허용합니다. 예시의 줄바꿈·탭만 허용하며 목록에는 `⏎`·`⇥`로 표시해 가짜 선택 항목을 만들지 못하게 합니다. 위반 응답은 저장·반영하지 않으며 제안에도 redact를 적용합니다.

결과는 `$HOME/Library/Application Support/routine-automation/scrum/learn/<date>.json`에 `{date,sent,suggestions}`로 **원자적으로 0600 저장**합니다(디렉터리 0700). 같은 날짜 재실행은 이 결과를 새 제안으로 교체합니다. redact는 모든 개인정보를 지우는 보장이 아니므로 업무 본문·예시·용어가 이 파일에 남습니다. 자동 삭제하지 않으며 공유 전에 확인하거나 불필요하면 직접 삭제하세요. 학습 저장 디렉터리/결과의 심볼릭 링크와 사용자 소유가 아닌 경로는 거부합니다.

대화형에서는 `ui_choose_many`의 **기본 미선택 목록**에서 고른 지침만 style.md의 `## 학습된 선호 (YYYY-MM-DD)` 아래에 기록합니다. 비TTY에서는 저장된 제안만 출력하고 style.md에는 반영하지 않습니다. **모든 학습 날짜 절**을 통틀어 이미 있는 동일 지침은 중복 추가하지 않으며 선택 순서·다른 절·기존 내용을 보존합니다. style.md 경로는 설정 파일과 같은 디렉터리이고 사용자 소유 일반 파일·symlink 거부·0600 규칙을 따릅니다. 길이가 2,000자를 넘을 예정이면 반영 전에 경고하며 초안은 기존처럼 처음 2,000자만 적용합니다. `exclude`·`rename`·`category`도 **표현용 자연어 선호**로만 기록하고 설정·근거 규칙·검증기는 바꾸지 않습니다. 자동 반영은 없습니다.

## 명령

| 명령 | 동작 |
|---|---|
| `routine setup` | 설치 마법사 |
| `routine init` | 설정 생성·수정 |
| `routine doctor` | 읽기 전용 의존성·버전·로그인·필수 설정·LaunchAgent·선택형 Orca 점검 |
| `routine sources [enable\|disable NAME]` | 소스 선택·사용 조건 확인, 설정 파일만 변경 |
| `routine status` | 오늘 소스 건수·오류, 초안 항목·확인 필요, 전달 표지, extra_steps 결과, 다음 예약 |
| `routine run` | 설정된 extra_steps → collect → draft → deliver → 마지막 AWS 단계 |
| `routine collect` | `--since`, `--until`, `--out`, `--sources git,prs,sessions,claude_sessions,jira,notion,slack` |
| `routine draft` | `--date`, `--out`, `--engine`, `--model`, `--project`, `--no-llm`, 선택형 `--slack` |
| `routine review [--date YYYY-MM-DD] [--no-open]` | 로컬 초안 검토 화면 생성·열기. `--no-open`은 경로만 출력 |
| `routine style` / `style edit` | 스타일 경로·내용·형식 조회 / 0600 템플릿 생성·편집 |
| `routine style preview [--date YYYY-MM-DD]` | 기존 초안을 현재 format으로 출력. LLM·파일 덮어쓰기 없음 |
| `routine learn [--date YYYY-MM-DD] [--paste]` | 보낸 글 읽기·격리 LLM 비교·0600 제안 저장. 대화형에서 선택한 선호만 기록 |
| `routine paste` | `--auto`, `--no-draft`, `--dry-run`, 수동 `--force`/`--replace` |
| `routine copy` | 오늘 HTML+텍스트를 복사하고 채널 딥링크 열기. 입력창 접근·전송 없음 |
| `routine config get KEY` / `set KEY JSON` | 유효 설정 조회·0600 저장 |
| `routine update [ZIP] [--check] [--yes] [--from github\|downloads]` | 공개 Release/Downloads zip 검증·설정 보존 업데이트. 확인만 실행·명시적 오프라인 선택 |
| `routine package` | 깨끗한 Git 작업 트리에서 `git archive HEAD` zip 생성 |
| `routine uninstall [--purge]` | 소유 검증 후 제거 |

LaunchAgent는 TCC 권한 귀속을 위해 `/bin/bash <설치본>/bin/routine run`을 실행합니다. gui-paste의 별도 agent는 `/bin/bash <설치본>/bin/routine paste --auto`를 600초 간격으로 실행합니다. clipboard에서는 paste agent를 설치하지 않습니다. 설정 변경 뒤 예약/plist를 바꾸려면 setup을 다시 실행하세요. 시스템 launchd 예약 자체는 시스템 로컬 시간 기준입니다. `timezone`은 수집·초안·상태의 시간대이며 시스템과 다르면 macOS 시간대도 맞추세요.

```bash
routine run --dry-run
routine run --only scrum-collect --only scrum-draft
routine collect --since 2026-09-25 --sources git,sessions,claude_sessions
routine draft --no-llm
routine review
routine review --date 2026-09-25 --no-open
routine paste --dry-run
routine copy
```

`morning`·`scrum-*`는 설치 내부 구현입니다. PATH 별칭은 제공하지 않습니다. 기본 수집 창은 직전 근무일 00:00부터 실행일 로컬 00:00 미만이며 월요일에는 금요일부터입니다. `collect.until=now` 또는 명시적 `--until`로 상한을 바꿀 수 있습니다. 수집 파일이 없는 draft도 같은 직전 근무일 계산과 상한 설정을 사용합니다. PR 검색의 `updatedAt >= 시작 시각`은 후보 선정 조건일 뿐입니다. 역할별 검색은 updated 내림차순으로 받고 URL 중복을 제거한 뒤 내 작성 PR(기간 내 생성 우선) → 내 리뷰 PR → 내 코멘트 PR 순서로 최대 50개를 한 번씩 조회합니다. 검색 역할 하나라도 50개에 도달하거나 중복 제거 결과가 50개를 넘으면 포화 오류를 남깁니다. `gh api user`의 login으로 내 생성·직접 병합·커밋·리뷰·코멘트 시각을 확인하고 `[시작, 종료)` 안의 내 활동이 있을 때 `in_window: true`로 표시합니다. `mergedBy`가 다른 계정이면 `merged_by_other`로 병합 결과를 기록하지만 그것만으로 내 어제 작업을 만들지 않습니다. 닫기는 행위자를 확인할 수 없어 내 활동으로 세지 않습니다. 오래전 열린 PR도 기간 내 내 활동이 있으면 포함되지만, 기간 밖의 마지막 변경만으로 어제 근거가 되지는 않습니다. 현재 상태는 `current`에 따로 저장합니다. 검색·개별 PR 조회는 각각 20초, 계정 확인은 10초, 전체 PR 수집 단계는 120초 상한을 적용합니다. 단계 제한 뒤 남은 후보와 조회·활동 해석·계정 확인 실패는 `in_window: "unknown"`과 오류로 남깁니다. draft는 이 수집 결과를 재사용하며 PR을 다시 조회하지 않습니다. 존재하지 않는 Git 위치는 경로 없음으로, 읽기 거부는 권한 오류로 기록하고, stderr 없는 스캔 시간 초과도 오류 메시지를 남깁니다. Slack URL 시각 해석 실패도 오류에 포함합니다. 결과는 `~/Library/Application Support/routine-automation/scrum/YYYY-MM-DD.{json,md}`와 `.draft.{json,html,txt,questions.md}`입니다. 새 데이터 디렉터리는 0700, 파일은 0600입니다. Chrome/Notion은 원본의 읽기 전용 SQLite 온라인 백업을 검증하고 사본만 조회하며 원본을 수정하지 않습니다. 일관된 스냅샷을 얻지 못하면 소스 오류로 기록합니다.

`gh pr view`의 커밋 export는 첫 100개 상한이 있습니다. 커밋이 100개 이상이고 다른 근거에서도 기간 내 내 활동이 확인되지 않으면 활동이 없다고 단정하지 않고 `unknown`과 오류로 남깁니다. 리뷰·코멘트는 gh가 페이지를 모두 조회하므로 개수 100개만으로 포화 처리하지 않습니다. 커밋 응답이 포화되어도 기간 내 내 활동이 하나 이상 확인되면 `true`를 유지합니다. 큰 응답은 파일을 통해 해석하며 jq 인자 크기 제한을 피합니다. `unknown` OPEN PR은 어제 근거에서는 제외하지만 오늘 계획에서는 사용할 수 있습니다. 이전 버전 수집 파일에 `in_window`가 없으면 질문에 `다시 routine collect 필요`를 표시합니다.

## LLM 격리·근거 검증

Claude Code 호출은 빈 임시 cwd에서 stdin 프롬프트를 전달하고 `gtimeout -k 5 270`으로 제한합니다.

```text
claude -p --tools "" --strict-mcp-config --setting-sources ""
  --disable-slash-commands --no-session-persistence --output-format json
  --json-schema <share/items-schema.json 내용> [--model 설정값]
```

**`--bare`와 `--safe-mode`는 사용하지 않습니다.** bare는 구독 OAuth 인증 경로를 읽지 않고 safe-mode 단독은 격리 기준을 만족하지 않았습니다. 공식 [headless 문서](https://code.claude.com/docs/en/headless)와 로컬 CLI help에서 확인한 응답 계약은 `.structured_output`에 스키마 결과, 일반 JSON 출력의 `.result`에 문자열 결과입니다. 두 경로를 읽되 문자열 result는 JSON으로 파싱하고 동일 jq 스키마 검사를 적용합니다. 유효하지 않으면 1회 재시도하고 2회 모두 실패하면 중단합니다.

omp는 기존 `--no-session --no-title --no-tools --no-lsp --no-pty --no-extensions --no-skills --no-rules --approval-mode always-ask --max-time 240 --config share/scrum-omp.yml`을 유지합니다. none/`--no-llm`은 로컬 요약이며 gh·GUI·LLM을 호출하지 않습니다. `--no-llm --slack` 조합은 거부합니다. 엔진과 무관하게 jq가 근거 수준·보류·확인 필요 표지·트리·HTML escaping을 결정합니다. 모델이 HTML이나 트리를 만들지 않습니다.

| 수준 | 최소 근거 | all 모드의 어제 표지 |
|---|---|---|
| request | 세션·사용자 메모 | 검토 |
| work | 실제 커밋·기간 내 내 활동이 확인된 PR | 없음 |
| merged | merge 커밋·내 기간 활동이 확인된 현재 MERGED PR의 기간 내 병합 결과 | 병합 |
| deployed | 해당 주제의 실제 운영 배포 완료 결과 | 운영 배포 |
| verified | 해당 주제의 실제 운영 조회·확인 결과 | 확인 |

요청·질문·예정·조건·실패·대기는 완료 근거가 아닙니다. LLM 입력의 어제 근거 `evidence.prs`에는 `in_window=true` PR만 전달하며, 현재 OPEN인 PR은 `current_prs`로 별도 전달합니다. `in_window=false/unknown` OPEN PR은 오늘 계획 근거로만 사용할 수 있습니다. 어제 항목이 이런 PR을 참조하면 jq 검증이 해당 근거를 제외하고 질문을 남깁니다. 유효한 근거가 하나도 남지 않은 일반 항목은 전달용 초안에서 제외되며, 사용자 메모의 명시적 보류 항목은 유지할 수 있습니다.

완료 표현 검증은 **어제 항목에만** 적용하며 오늘 계획은 완료 주장으로 보지 않습니다. topic과 묶음 주제(path[1]), 사용자 지정 분류를 검사하되 유효한 Git/PR 근거의 저장소 이름인 묶음 주제는 제외합니다. Git 커밋/PR 제목을 topic에 그대로 복사한 원문도 `--no-llm`과 LLM 모두에서 유지하며, 같은 원문인 묶음 주제에만 이 예외를 적용합니다. 별도로 만들어 낸 완료형 묶음·분류까지 면제하지 않습니다. `held_ref` 없는 자동 보류 매칭은 정규화한 topic이 메모 전체를 포함할 때만 허용합니다. 명시한 `held_ref`의 부분 연결은 확인할 수 있지만, 완료 주장 면제는 정규화한 topic이 메모와 같거나 메모의 연속 부분 문자열이고 해당 술어 뒤에 대기·후·전·여부·예정·필요·실패가 없을 때만 허용합니다. 단어 겹침만으로는 완료 주장을 면제하지 않습니다. 모호한 자동 매칭은 `보류 항목 매칭 확인` 질문만 남기며, 오늘 계획은 정규화한 topic과 보류 메모가 정확히 같을 때만 숨깁니다.

완료 주장은 동작과 인접한 완료 술어로 판단합니다. `배포했습니다`·`재배포 완료`·`운영배포 완료`·`프로덕션 반영 완료`·`릴리스 완료`·`Deployment 완료`는 deployed, `머지했음`·`병합 완료`·`merge 완료`는 merged, `정상 확인 완료`·`검증 완료`는 verified 주장입니다. `배포 스크립트`·`릴리스 노트`·`Release 준비`·`머지 충돌 해결`·`prod 설정`처럼 완료 술어가 없는 동작 명사는 완료 주장이 아닙니다. 영문 완료형 `deployed`·`merged`·`released`·`shipped` 등은 단어 경계로 비교하므로 `membership`·`Product`를 배포 표현으로 오인하지 않습니다.

완료 술어에는 `하였습니다`·`했어요`·`마쳤`·`성공`·`진행 완료`·`처리 완료`도 포함합니다. 술어 바로 뒤의 `대기`·`후`·`전`·`여부`·`예정`·`필요`·`실패`는 완료 주장으로 보지 않습니다. 따라서 `배포 완료 여부 확인`·`머지 완료 후 배포` 같은 문맥을 완료 작업으로 오인해 제외하지 않습니다.
`✅`·`✔`·`☑`·`(완)`·`[완]`·`done`·`OK`·`complete`·`completed`·`finished`도 동작 영역어 바로 뒤에서는 공백 유무와 관계없이 완료 술어로 판정합니다. 예를 들어 `운영배포✅`·`운영 반영 OK`는 배포, `머지✔`·`merge(done)`은 병합 주장입니다. 영역어와 연결되지 않은 `HTTP 200 OK 응답`이나 `배포 OKR 목표`는 이 약어만으로 완료 주장으로 보지 않으며, 뒤에 `여부`·`대기` 등이 붙은 문맥도 기존 규칙대로 검사합니다.

병합·배포·검증은 **서로 독립된 사실**입니다. 병합 주장은 기간 내 실제 병합 PR/merge 커밋, 배포 주장은 운영 배포 결과 보고, 검증 주장은 운영 조회·확인 결과 보고가 각각 필요합니다. 배포나 검증 결과가 병합을 대신 증명하지 않습니다. `구현 완료`·일반적인 `완료`·`마무리` 같은 work 주장에는 커밋/기간 내 PR이 필요하며, 복수 주장은 필요한 사실을 **모두** 증명해야 합니다. LLM의 level과 표시 표지도 그 수준의 실제 근거로 검증하며 최고 수준으로 줄 세우지 않습니다. 없는 근거 ID는 질문에 남기되 함께 제출된 유효한 근거는 그대로 사용합니다. `--no-llm`도 merge 커밋과 기간 내 병합 결과가 확인된 PR에 merged를 부여합니다.

표현에 필요한 수준이 부족하면 `draft.markers=none/uncertain/all` 모두에서 항목 전체를 제외하고 `완료 표현이 근거보다 강해 초안에서 제외 — 원문: …` 질문을 남깁니다. 단순히 `(확인 필요)`를 붙여 강한 완료 표현을 전달하지 않습니다. 표시 접미사는 `draft.markers`로 조절하며 기본 none에서는 숨깁니다. 사용자 메모는 `scrum/notes.md`의 `## 보류`, `## 오늘 추가` 목록을 읽고 `(보류)`는 모드와 무관하게 유지합니다. MERGED/CLOSED PR·커밋만으로 오늘 계획을 추정하지 않습니다.

OMP와 Claude Code는 `*/*.jsonl`을 읽기만 합니다. Claude 데스크톱 앱의 대화는 수집하지 않습니다. 창 안의 사용자 요청과 assistant 텍스트만 읽고 도구 payload·sidechain을 제외합니다. Claude의 `isMeta`, 텍스트 없는 content, command/local-command 태그, 중단 표지와 빈 텍스트도 제외합니다. 사용자 메시지는 첫 요청+최근 요청을 최대 20개 유지하고 제목은 첫 유효 요청으로 정합니다. 결과 보고 최대 6개+최근 4개를 선택하며 보고 하나는 1,000자, 보고 합계는 6,000자로 제한합니다. presigned URL, AWS ASIA/AKIA 키, 토큰·개인키 등은 **자르기 전에** 기존 redact 규칙으로 마스킹합니다. 세션과 보고에 완성된 `evidence_id`를 제공하며 OMP는 `session:<id>[#<보고 인덱스>]`, Claude는 `claude-session:<id>[#<보고 인덱스>]`입니다. 같은 ID 문자열이어도 다른 엔진의 보고를 근거로 오인하지 않습니다.

### 알려진 한계

- 완료 술어 없는 `운영 배포` 명사구와 `운영에 올렸습니다`·`배포를 진행했습니다` 등 미지원 표현은 배포 주장으로 분류하지 않습니다.
- `정상 동작 확인`·`확인 결과 정상`·`모니터링 결과 이상 없음`·`배포 후 정상 확인` 같은 verified 동의어는 완료 주장 분류에 추가하지 않았습니다.
- merged는 병합 근거를 검증하지만 topic과 병합 근거의 주제 연결은 별도로 검사하지 않습니다.
- 리뷰만 한 타인 PR이나 OPEN PR의 제목도 원문 면제 대상이며, 제목 보존이 본인의 작성·배포 참여를 뜻하지는 않습니다.
- 근거가 부족한 경로의 항목은 먼저 제외되므로 `path_uncertain` 기반 라벨 표지는 실질적 효과가 없는 미정리 경로입니다.


## 초안 검토 화면

`routine review`는 오늘의 `~/Library/Application Support/routine-automation/scrum/YYYY-MM-DD.draft.json`을 읽어 같은 폴더에 `YYYY-MM-DD.review.html`을 0600 권한으로 만들고 기본 브라우저로 엽니다. 다른 날짜는 `--date`로 지정하세요. `--no-open`은 파일을 만든 뒤 경로만 출력합니다. 초안이 없으면 날짜와 `routine draft --date` 안내를 출력하고 실패하며, 수집이나 LLM을 자동 실행하지 않습니다.
검토 경로는 기본 scrum 폴더로 고정되어 있으며 `review --out`은 지원하지 않습니다. `routine draft --out DIR`로 만든 별도 초안은 이 명령의 대상이 아닙니다. 필수 설정은 `routine init`으로 저장해야 하며 검토 앱에는 설치 당시 설정 파일 경로가 전달됩니다.

왼쪽에서 항목 포함 여부를 체크하고 문구를 편집하면 오른쪽 미리보기가 즉시 갱신됩니다. 새 초안에 저장된 생성 당시 머리글·프로젝트·분류·표지 설정을 사용하므로 이후 설정을 바꿔도 초기 미리보기·복사본은 원래 초안과 같습니다. 스냅샷이 없는 이전 초안은 현재 설정을 사용합니다. 일반 항목은 기본 선택되고, 근거 부족으로 제외된 항목은 **확인 필요** 영역에서 기본 해제됩니다. 제외 항목을 확인한 뒤 체크하면 원래 어제/오늘 위치에 포함됩니다. 제외 메타데이터가 없는 이전 초안의 질문만 오늘의 기타/확인 필요 묶음에서 선택할 수 있습니다. 새 초안의 일반 수집 안내는 복사 대상이 아닌 안내로 표시합니다. 보류 표지와 항목별 확인 사유는 문구 표시 설정과 별개로 볼 수 있습니다. 오늘 보류 항목은 선택할 수 없으며 선택 수에서도 제외합니다.

근거 보기를 펼치면 Git SHA·PR/Slack 링크와 세션 보고 발췌가 표시됩니다. 새 초안은 생성 시의 Git·PR·세션·Slack·메모 근거 카탈로그를 저장하며, 기존 redact 규칙을 적용한 뒤 발췌를 최대 300자로 제한합니다. 따라서 수집 파일이 없어지거나 초안 생성 중 추가 수집한 Slack 근거가 원래 수집 파일에 없어도 발췌를 보존합니다. 카탈로그가 없는 이전 초안만 같은 날짜 수집 JSON에서 발췌를 찾고, 없으면 ID와 발췌 없음 안내를 표시합니다. 근거 URL은 텍스트로 표시하며 자동 접속하지 않습니다.

**복사**는 선택·편집 결과의 HTML과 일반 텍스트를 함께 클립보드에 넣습니다. ClipboardItem을 지원하지 않는 브라우저는 일반 텍스트만 복사하며, 권한 거부 등 실패는 화면에서 안내합니다. **Slack 채널 열기**는 설정의 팀·채널 ID로 만든 `slack://` 딥링크일 뿐입니다. 전송 버튼·Slack API·입력창 조작은 없습니다.

검토 HTML은 외부 폰트·스크립트·이미지·네트워크 요청을 사용하지 않으며 CSP로 외부 리소스를 차단합니다. 데이터는 HTML 이스케이프하고 삽입 JSON의 `<`·`>`·`&`는 Unicode 이스케이프로 바꿉니다. 붙여넣기는 텍스트만 받으며 편집한 줄바꿈은 공백으로 정리하고 빈 문구는 미리보기·복사에서 제외합니다. 편집 내용은 현재 화면에만 남고 새로고침하면 초기화됩니다. 원본 초안이나 최종 파일을 저장·다운로드하지 않습니다. 로컬 검토 파일에는 redact 후의 업무 문구가 남으므로 공유할 때는 내용을 확인하세요.

## 전달·화면 안전장치

clipboard에서는 무인 morning과 잔존 LaunchAgent의 `routine paste --auto`가 일반 클립보드·GUI를 건드리지 않습니다. 아침 알림은 **초안 준비 — 검토: routine review**로 안내하며 상한으로 생략한 항목이 있으면 그 수를 함께 알립니다. `스크럼 초안 복사.app`과 `스크럼 초안 검토.app`는 `osacompile`로 생성되며 Homebrew PATH와 설치 당시 `ROUTINE_CONFIG`를 지정한 설치본의 `routine copy`와 `routine review`만 각각 실행합니다. Spotlight나 Dock에서 사용할 수 있습니다.

`doctor`는 앱을 실행하거나 권한·설정을 변경하지 않습니다. gui-paste를 고른 경우 이미 실행 중인 Orca의 읽기 전용 상태와 `ax_lines` 인덱스 형식(대괄호/숫자)을 확인합니다. **현재 보이지 않는 Slack 라벨은 `미검증`**으로 표시하며 그 자체로 실패하지 않습니다. 계정 메뉴/도구 막대·검색 패널·스레드 패널이 보이면 해당 화면의 필수 라벨 누락을 실패로 판정합니다. clipboard로 바꾼 뒤 paste LaunchAgent가 남아 있으면 경고합니다. 실제 수집·붙여넣기 직전 필요한 화면 라벨이 달라지면 `Slack/Orca 화면 형식 변경 의심 — <화면>/<라벨>` 알림을 남깁니다. 한국어 Slack 접근성 문자열은 `share/slack.jq` 상단에 모았으며 사용자 설정으로 번역하지 않습니다.

자동 gui-paste는 아래 경우 화면을 건드리지 않고 건너뜁니다.

- 설정 요일·시간 창 밖, `autopaste.disabled` 존재, 오늘 초안 없음
- 오늘 `.pasted`, `.paste-skipped`, `.paste-attention` 표지 존재
- 다른 morning/붙여넣기 실행 중, 잠금·콘솔 사용자·idle 확인 실패
- 설정된 유휴 시간 미충족, Slack이 이미 전면

각 GUI 조작 직전 잠금·HID idle을 다시 확인합니다. 마지막 자체 조작 이후의 경과시간보다 idle이 작으면 사용자 입력으로 중단합니다(100ms 허용). 클릭 대상 인덱스·라벨, 오늘 고유 스크럼 글, 스레드 루트 URL, 댓글 수·URL, 본인 댓글, 빈 입력창·포커스, 채널 동시 전송 체크박스 **해제 상태**를 검증합니다. 댓글이 화면 밖이면 최대 12페이지 내려 읽되 중복 URL로 전체 댓글 수를 부풀리지 않습니다. Return은 검색 콤보의 포커스를 직전에 확인한 검색 확정에만 허용합니다. 댓글 입력창에는 누르지 않습니다.

붙여넣기 전에 클립보드의 항목·바이너리 타입을 백업하고 작업 후 복원합니다. Concealed/Transient 타입은 백업하지 않습니다. JXA는 실제 기록한 데이터를 다시 읽어 검증합니다. Cmd+V 후에는 같은 스레드·체크박스 상태와 스크린샷을 확인합니다. Cmd+V 이후 오류는 **붙여넣기 됐을 수 있음**으로 종결하며 자동 재시도하지 않습니다. 전면 앱 복원은 사용자가 다른 앱으로 전환하지 않은 경우에만 시도합니다.

| 표지 | 의미 |
|---|---|
| `.pasted` | 붙여넣기·복원 성공, 스크린샷 경로 |
| `.copied` | 사용자가 copy를 실행한 시각 |
| `.paste-skipped` | 본인 댓글·기존 입력·글 없음 시각·일일 상한 종결 |
| `.paste-attention` | 붙여넣기 가능성/복원 문제, 직접 확인 필요 |
| `.paste-attempts` | 일일 시도 수. 사용자 입력/잠금 중단은 차감 |
| `.draft-refresh-attempted` | Slack 근거 초안 재생성의 당일 시도 표지 |
| `.paste-notified-*` | 같은 날 같은 단계 알림 중복 방지 |

자동 모드의 `--force`/`--replace`는 금지합니다. 수동 override도 다른 안전 검사를 생략하지 않습니다. exit 0은 성공/조용한 건너뜀, 1은 실패, 2는 옵션·환경 오류, 3은 자동 종결/확인 필요, 4는 사용자 입력/잠금 중단입니다. SIGKILL 뒤에는 cleanup을 보장할 수 없습니다. 자동 실행을 잠시 끄려면 `~/Library/Application Support/routine-automation/autopaste.disabled`를 만드세요.

## 패키지·검증

```bash
./tests/run.sh --all-jq     # 기본 jq + 별도 /usr/bin/jq가 있으면 두 버전
./tests/real-gum.sh         # 선택 실행: 실제 gum PTY, 없으면 SKIP (전체 테스트에 포함하지 않음)
bin/routine package
```

현재 버전은 루트 `VERSION` 파일에 있습니다. **새 zip을 배포하기 전에 반드시 VERSION을 상향**하고 `CHANGELOG.md`에 사용자 관점 변경을 추가하세요. 같은 버전 zip은 `routine update`로 재설치되지 않습니다. 버전은 선행 0 없는 `MAJOR.MINOR.PATCH` 숫자 세 개를 사용합니다. package는 커밋하지 않은 변경·새 파일이 있으면 거부하고 `git archive HEAD`로 `dist/routine-automation-<VERSION>.zip`을 만듭니다. zip 최상위 폴더는 `routine-automation-<VERSION>/`이며 `routine 설치.command`의 실행 권한, `설치 방법.txt`, `CHANGELOG.md`, `LICENSE`가 포함됩니다. dist는 Git에서 제외됩니다.
package는 생성한 zip을 **현재 검증기 하나**로 자기 검증하며, `tools/legacy-validators/*.sh`에 보관된 모든 공개 검증기로도 검사합니다. 어느 쪽에서든 거부하면 zip을 삭제하고 실패합니다. **검증 코드를 바꿀 때 직전 공개 버전의 `share/update.sh`를 `tools/legacy-validators/<VERSION>.sh`로 먼저 보관하고, 이전 공개 검증기는 누적 유지하세요.** 현재는 공개 0.1.0 검증기와 `tests/fixtures/public-0.1.0.zip`의 실제 클라이언트 트리를 보관합니다. 검증기만 실행하는 검사에 더해 그 클라이언트의 네트워크·설치 인터페이스로 새 package까지 업데이트하는 회귀를 유지합니다. package는 Git 과거 이력·원격 조회·push에 의존하지 않습니다.
로컬 `.personal-patterns`에 개인 값의 ERE 패턴을 한 줄씩 둘 수 있습니다. 이 파일은 `.gitignore`에 등록되어 zip·커밋에 포함되지 않습니다. 존재하면 package가 zip의 압축 해제된 모든 내용·파일 경로·원본 메타데이터를 검사하고, 일치 시 배포 zip을 삭제하고 실패합니다. 패턴/일치 내용은 출력하지 않습니다. 파일이 없는 팀원 환경은 검사만 건너뜁니다. 테스트도 이 파일이 있을 때 전체 tracked 파일을 검사합니다.

### 공개 배포

**개발 레포에는 원격을 추가하거나 개발 이력을 push하지 마세요.** 개인 값이 있는 과거 이력·작성자 메타데이터는 공개할 수 없습니다. 커밋을 cherry-pick/format-patch로 옮기지 않고 아래 절차의 `git archive`로만 반영합니다. 공개 계정·저장소 이름 `coldplay126/routine-automation`은 변경·이전하지 않습니다. 배포된 클라이언트는 이 이름과 저장소 ID를 고정해서 사용합니다.

VERSION·CHANGELOG를 갱신하고 전체 격리 테스트와 개인 값 검사를 통과한 개발 HEAD를 커밋한 뒤 실행하세요.

```bash
./tools/release.sh "$(cat VERSION)"                         # 로컬 준비만
./tools/release.sh "$(cat VERSION)" ../routine-automation-public
# 회사 확인·공개 승인 후 개발 레포에서만 실행:
./tools/release.sh "$(cat VERSION)" --publish
```

공개 경로의 기본값은 개발 레포 옆 `../routine-automation-public`입니다. 스크립트는 깨끗한 개발 HEAD를 archive로 추출해 공개 레포의 **추적 파일만** 교체하고, `.personal-patterns`를 복사·ignore 상태로 유지합니다. 공개 신원 `coldplay126 <coldplay126@gmail.com>`으로 `release <VERSION>` 커밋과 annotated `v<VERSION>` 태그를 만듭니다. 공개 트리·전체 이력의 patch/작성자/커미터·태그 메타데이터를 내용 비출력으로 검사한 다음 공개 레포에서 package를 생성하고 CHANGELOG의 해당 버전 절만 노트 파일로 검사합니다. 같은 내용의 준비된 태그는 재사용하며 이미 준비한 태그의 내용을 바꾸지는 않습니다.

공개 레포에는 `.personal-patterns`가 필수인 pre-push hook을 설치합니다. 나가는 범위의 patch·커밋/태그 메타데이터·branch/tag 이름·트리에 개인 값이 있거나 검사에 실패하면 push를 거부합니다. 기존 사용자 hook/hooksPath가 다르면 덮어쓰지 않고 중단하며, 패턴 파일·Git 설정·hooks 링크로 레포 밖에 쓰지 않습니다. 개인 패턴은 개발·공개 레포 모두 추적하지 않고 ignore해야 합니다. 개발 이력은 공개 레포로 가져오지 않으며 개발 레포 원격도 허용하지 않습니다.

기본 실행은 push·Release 명령을 **출력만** 합니다. 미리보기는 UTF-8을 그대로 표시하고 작은따옴표로 인용하여 제목·경로의 공백과 작은따옴표도 복사 후 한 인자로 유지합니다. `--publish`에서만 현재 GitHub 계정을 기록하고 `coldplay126`으로 전환·확인한 뒤 공개 branch와 해당 태그를 push합니다. 계정 전환을 무시하는 `GH_TOKEN`·`GITHUB_TOKEN`·`GH_HOST` 환경 변수는 미리 해제해야 합니다. 성공·실패 모두 원래 계정으로 복귀합니다.

공개 저장소는 **Immutable releases**를 사용합니다. 반드시 **draft 생성 → asset 업로드 → API의 URL/state/size/digest 및 제목·노트 검증 → `gh release edit --draft=false`로 공개**하는 순서를 지킵니다. 검증 실패 시 draft를 공개하지 않으며 기존 asset을 덮어쓰지 않습니다. **공개 후 asset·태그는 수정할 수 없으므로 수정은 새 버전으로만 배포합니다.** `0.x` 배포는 prerelease로 게시합니다.

### 격리 검증


테스트는 임시 HOME·가짜 이메일/Slack 값·전용 PATH의 스텁을 사용합니다. 실제 brew/launchctl/Slack/Orca/LLM/사용자 설치는 실행하지 않습니다. 별도 클립보드 회귀만 `routine-test-*` named pasteboard에서 실제 JXA를 실행하고 일반 클립보드는 건드리지 않습니다. 기존 SQLite·근거 판정·사용자 입력/전면 복원·붙여넣기 안전 회귀에 더해 jq 1.7/1.8, 스키마 복구·설정 저장/설치 격리, init 링크·자동 제안, Claude 격리·JSONL 메타/상한, bash 3.2의 실제 script PTY setup·명시적 FDA 확인, 보호 경로 실패 경고/재검증, jq 누락/구버전 설치 동의, clipboard 자동 GUI 차단, 첫 실행 실패 표지, doctor/status, zip 개인 패턴 차단, 폴더 A→B 업데이트·누락 자산 복원·실제 SIGKILL 경계별 journal 복구·기존 서비스 재로드·legacy 이전·소유 거부·uninstall을 검증합니다. FDA 권한 자체는 실제 launchd/TCC 환경을 실행하지 않으므로 이 테스트가 OS 권한 보장의 증거는 아닙니다.
선택한 jq와 타임아웃·가상 시계·입력 보호 스텁은 필요한 테스트의 `~/.local/bin`에도 미러링합니다. `bin/routine`의 정렬된 PATH가 테스트용 도구 대신 Homebrew/시스템 도구를 먼저 고르지 않도록 하며, GUI·LLM 명령은 계속 전용 스텁으로 격리합니다.
SQLite 잠금 회귀(`tests/sqlite-lock.sh`)는 임시 History를 별도 프로세스의 EXCLUSIVE 쓰기 트랜잭션과 실제 hot journal 상태로 유지한 채 수집합니다. 커밋된 Jira 행 복구·미커밋 행 제외·오류 없음·원본 DB/저널 해시 불변·15초 상한을 확인합니다. `tests/run.sh`는 Notion의 WAL-only 행을 online backup과 강제 복사 폴백 양쪽에서 확인하고, `quick_check`가 실패하는 사본의 오류·프로필별 재시도·원본 read-only 가드도 검증합니다. 사용자 Chrome/Notion DB는 테스트에 쓰지 않습니다.
업데이트 회귀(`tests/update.sh`)는 두 jq·임시 HOME·PATH와 내보낸 함수의 이중 스텁 격리에서 내부 VERSION 비교·검증된 후보 선택·필수 파일 누락/CRC 오류/크기 초과 후보의 다음 정상 후보 선택·한글 이름·대소문자/정규화 중복·호스트별 링크 속성·로컬 헤더 불일치·안전한 경로·동일/하위 버전·비TTY 동의·확인만 실행을 검증합니다. 사용자 지정 설정 경로와 예약 시간·데이터/로그/install-id 보존, 실행 잠금 중 교체 차단, LaunchAgent 등록 실패 롤백·등록 직전 SIGKILL 뒤 같은 ZIP 재실행 복구·status 미완료/미등록 경고·새 설정 도구 안내·알림의 자동 설치 금지·배포 zip 런처 권한과 상대 심볼릭 링크 실행도 확인합니다. Finder/Gatekeeper GUI는 실행하지 않습니다.
정상 업데이트 후보는 이력 없는 임시 Git 저장소의 **실제 `bin/routine package` 산출물**로 생성해 확인과 설치까지 소비합니다. curl의 PATH·내보낸 함수 이중 스텁으로 prerelease·draft·숫자/페이지 비교·정확한 최초 URL·저장소 ID·uploaded 상태·digest/size 불일치·302→서명 asset 호스트·리다이렉트 경계·`-q`/HTTPS/크기 제한·curl 63을 확인합니다. GitHub 403과 Downloads 9.9.9이 겹쳐도 auto 설치·알림이 없으며, Downloads의 `--yes` 비TTY 거부와 실제 PTY의 거절·동의를 검증합니다. 실제 15초 종료와 임시 파일 정리·변경된 ZIP의 캐시 무효화·0.1.0 보관 클라이언트에서 새 package로의 업데이트도 확인합니다. `TEST_HEAD_PACKAGE_ZIP`에 공개 `dist/routine-automation-VERSION.zip` 경로를 전달하면 이 호환 회귀가 실제 공개 HEAD 산출물을 소비합니다. 실제 네트워크는 호출하지 않습니다. 특수 ZIP 중앙/로컬 헤더·CRC·외부 속성과 LICENSE 대소문자/내용 경계는 `tests/zip-fixtures.cjs`로 생성합니다.
배포 회귀(`tests/release.sh`)는 임시 개발 이력에 개인 값과 비공개 작성자를 넣고 archive로 새 공개 레포에 옮겨 공개 신원·태그·노트 절·준비 재실행·실제 pre-push의 patch/작성자/태그 이름 거부를 확인합니다. 패턴·hooks 링크로 외부 사용자 파일이 바뀌지 않는지도 확인합니다. UTF-8·공백·작은따옴표가 있는 미리보기 명령은 실제 Bash 파서로 소비해 인자가 유지되는지 확인합니다. push·gh는 PATH/내보낸 함수 스텁에서만 동작하며, draft 업로드 검증 후 공개·digest 불일치 시 미공개·양쪽 계정 복귀를 검증합니다. 실제 저장소·Release 생성은 하지 않습니다.
검토 회귀는 두 jq에서 0600 권한·날짜 선택·초안 없음 실패·CSP·악성 문구 이스케이프·redact/300자 상한·체크박스 기본값·기존 텍스트와 초기 미리보기 일치·질문 전용 후보 보존·스냅샷 없는 초안의 기본 format을 확인합니다. 복사·검토 앱은 osacompile 스텁으로 생성하고 사용자 지정 설정 경로 전달·manifest 소유 확인·변조 거부·uninstall 제거를 검증합니다. 앱의 고정 PATH가 스텁을 우회하지 않도록 앱 호출 회귀에는 Bash의 open/osascript 스텁 함수도 내보냅니다. 실제 브라우저의 클립보드 권한은 스텁 테스트로 보장하지 않습니다.
선택 브라우저 회귀는 `tests/review-browser.cjs`로 실제 JS `render()`의 HTML·텍스트가 저장된 초안과 같은지, 설정 변경 후에도 형식이 보존되는지, `<!--<script>` 경계·Unicode 주제 접기·줄바꿈/빈 편집·오늘 보류·복사 API·좁은 화면을 검증합니다. node·Playwright 드라이버·headless Chromium이 없으면 SKIP하며 설치하지 않습니다. 기존 드라이버와 실행 파일을 `REVIEW_BROWSER_DRIVER`·`REVIEW_BROWSER_CHROMIUM`으로 지정할 수 있습니다. `REVIEW_BROWSER_SHOTS=/tmp/routine-review-shots`는 화면·검증 결과를, `REVIEW_BROWSER_SAMPLE_DIR=/tmp/routine-review-sample`은 0600 HTML 샘플을 남깁니다. OS 클립보드는 변경하지 않고 브라우저의 clipboard sink만 스텁으로 교체합니다.
스타일 회귀는 두 jq에서 Claude·OMP 프롬프트의 신뢰 섹션 위치·2,000자 상한·경고·데이터의 위장 제목 격리, 스타일을 따른 스텁 LLM의 level 강등과 완료 기호·약어 주장 제외/일반 OK 문구 보존, 선택 스타일 검사 실패 후 계속 생성, 템플릿 주석 제거, format 값 거부·init 파싱·설정 미변경, tree/flat·커스텀 글머리의 text/HTML/초기 검토/JS 렌더/복사 일치, 상한 항목·근거·질문 보존과 검토 재선택·생략 수 안내, preview의 파일 미변경·현재 형식 적용, 인용한 EDITOR 경로·인자/open 스텁·템플릿 0600을 확인합니다. JS 렌더는 node에서 실제 검토 스크립트를 실행하며 선택 브라우저 회귀에도 flat 사례를 추가했습니다. 드라이버가 없으면 브라우저는 SKIP합니다.
학습 회귀는 `tests/learn.sh`에서 두 jq의 직전 평일/명시 날짜·본인 댓글 본문 경계·구조적 입력창/인용/첨부/구분선 제외·일반 본문 키워드 보존·같은 부모 안 작성자 생략 연속 메시지/반응 뒤 본문 보존·미인식 작성자와 이름에 컨트롤 단어가 든 타인 제외·댓글 버튼 최대 1회/이미 열린 대상 0회·입력/전송 0회·작성 중 스레드/다른 작업 잠금 중단·오늘 pasted/paste-attention의 전송/빈 오늘 입력창 확인 후 진행과 미확인 중단·표지/타 작업 잠금 보존·본인 확인/LLM 전송 거절·사용자 입력 감지·전면 활성화 무시 후 `open -b` 대체/실패/입력 중단의 Slack 알림·다른 앱 전환의 포커스 보존·Claude/OMP 격리·데이터 구분자 위장 격리·스키마 상한/제어/채움/주석 위반 거부·NFD/결합/VS16/ZWJ 허용·미리보기 코드포인트 표시·예시 줄바꿈 표시·redact·0600·선택 순서/전 날짜 중복 방지/기존 절 보존·style 안전 정책·2,000자 경고·비TTY 캐시 출력/획득 차단·무인 미실행을 확인합니다. 작성자 회귀 데이터는 `tests/fixtures/slack-learn-authors.json`에 있습니다. gum은 시작부터 PATH·`$HOME/.local/bin`의 forbidden 스텁과 `type -P` 함수 보호로 격리하고 대화형 단계에는 전용 스텁을 사용합니다. 비TTY 단언은 `</dev/null`로 실행하며 터미널에서 전체 테스트를 실행해도 설치된 gum을 사용하지 않습니다. open/osascript/pbpaste/pbcopy/orca/claude/omp는 PATH와 내보낸 Bash 함수 스텁을 함께 사용해 호출 기록을 확인합니다. 실제 Slack AX·GUI·LLM·일반 클립보드는 실행하지 않으므로 Slack 버전별 AX 형식·동명이인·댓글 요약 노출 여부는 미검증이며 확인 불가 시 중단하거나 `--paste`로 대체합니다.

gum 회귀는 설치된 실제 gum을 실행하지 않고 전용 스텁만 사용합니다. 실제 `expect`/`script` PTY에서 setup의 config FIFO/tee 경로, 4/5단계 머리글·요약, 저장/한 항목 수정/최종 취소·Esc·Ctrl-C의 파일 보존, 텍스트 경로와 NO_COLOR, 최종 체크리스트 한 벌, 스피너의 성공/실패 명령 단일 실행·stdout 보존, Slack 감지 후 포커스 복원을 검증합니다. 사전 선택·쉼표/공백 경로 추가, 사용 불가 소스 거부·Git 위치 복구·빈 위치 확인, 비대화형 질문 차단과 선택 의존성 설치 동의·실패 후 계속 진행 회귀도 유지합니다.
안내 유형별 기호와 기본색의 굵은 제목, 본문·요약 값의 기본색 유지, 출처 기호와 보조 글자의 색 분리, 새 링크와 명시적인 Slack 플래그의 저장 우선순위도 검증합니다.
`tests/first-run-ui.sh`는 지연된 morning 스텁의 로그를 실제 setup PTY에서 읽어 수집→LLM 전환, 소스별 진행, 이전 실행 로그 제외, 부분 기록된 줄의 이어 읽기, 좁은 화면의 현재 작업 표시와 안내 줄 정리를 확인합니다. `s`는 Enter 없이 대기만 끝내고 스텁 서비스는 계속 완료하며, SIGINT/SIGTERM/SIGQUIT/SIGHUP 종료에서도 설정 가능한 모든 stty 상태와 커서를 복원하는지 검사합니다. SIGTSTP 일시정지 중에는 입력 상태·커서를 복원하고 계속 실행 시 스피너 모드를 다시 적용합니다. macOS가 raw→canonical 전환 때 자동으로 붙이는 일시적인 커널 PENDIN 비트는 상태 비교에서 제외합니다.

`tests/real-gum.sh`는 gum만 실제 바이너리로 실행하고 brew·launchctl·Slack/Orca·LLM 관련 명령은 전용 스텁으로 격리합니다. 임시 HOME의 setup을 실제 화살표·Enter 입력으로 구동해 일반/좁은 화면의 질문·요약 잔여와 중복 체크리스트가 없는지, 저장/취소 뒤 결과와 단계 상태가 맞는지 확인합니다. 실제 요약 카드의 라벨/값 구분선은 터미널 셀 기준으로 같은 열인지 단언하고, 버튼의 전경·배경·굵기와 NO_COLOR의 SGR 제거도 검증합니다. `REAL_GUM_BIN=/절대/경로/gum`으로 바이너리를 지정할 수 있습니다. `REAL_GUM_SHOTS=/tmp/routine-ui-shots`도 지정하면 단계 머리글·입력·다중 선택·확인·요약·경고·성공/실패 체크리스트·소스 목록의 실제 PTY ANSI 화면을 `.ans` 파일로 남깁니다.

영어 Slack, Orca 없는 AX 직접 구현, 메뉴 막대 UI, Claude 데스크톱 대화 수집, Slack API 게시는 범위에 포함하지 않습니다.
