# 설치·업데이트·제거

처음 설치하는 순서는 [README](../README.md#설치)를 참고하세요.
이 문서는 출처 확인, 업데이트 검증, 복구와 제거 절차를 설명합니다.

- [첫 설치](#첫-설치)
- [이후 업데이트](#이후-업데이트)
- [첫 설치·재설정의 세부 동작](#첫-설치재설정의-세부-동작)
- [1.0 개발판·초기 빌드 전환](#10-개발판초기-빌드-전환)
- [설치 소유권과 복구](#설치-소유권과-복구)
- [롤백·제거](#롤백제거)

[설정](configuration.md) · [안전과 한계](safety.md) · [전체 명령](commands.md)

## 첫 설치

Release에서 받은 최신 `routine-automation-<VERSION>.zip`을 풀고 폴더 안의 `routine 설치.command`를 더블클릭하세요.
`<VERSION>`은 받은 zip의 실제 버전으로 바꾸세요.
자기 폴더에서 설치를 시작하고, 끝나면 결과를 보여 준 뒤 아무 키나 누를 때까지 기다립니다.

zip 안의 `설치 방법.txt`에도 같은 안내가 있습니다.
터미널에서 실행할 때는 파일 이름에 공백이 있으니 경로를 따옴표로 감싸세요.

인터넷/Slack에서 받은 zip은 격리(quarantine) 속성이 압축을 푼 파일에도 붙을 수 있습니다.
이 패키지는 서명·공증되지 않아 macOS 15 이상에서 더블클릭이 차단될 수 있습니다.
우클릭 › 열기를 우회 방법으로 안내하지 않습니다.
신뢰하는 팀 배포본에 한해서 아래 대안을 쓰세요.

1. 더블클릭을 시도한 직후 **시스템 설정 › 개인정보 보호 및 보안 › 보안 › 그래도 열기**, 이어서 경고의 **열기**를 선택합니다. 회사 관리 정책에 따라 예외 버튼이 없거나 허용되지 않을 수 있습니다. 악성 소프트웨어·손상 경고면 강행하지 말고 배포자에게 확인하세요.
2. 터미널에서 아래 한 줄을 실행합니다. 압축을 푼 폴더의 위치나 이름이 다르면 경로를 바꾸세요.

```bash
/bin/bash "$HOME/Downloads/routine-automation-<VERSION>/install.sh"
```

기존처럼 압축을 푼 폴더 안에서 `./install.sh`를 실행해도 됩니다.
전역 Gatekeeper 비활성화나 Downloads 전체의 격리 속성 제거는 하지 않습니다.
설치가 시작된 뒤 설치 복사본에 한해서 기존 절차로 격리 속성을 제거합니다.

조사 근거: 이 Mac(macOS 26.3.1, Darwin 25)에서 임시 `.command`에 `com.apple.quarantine`을 붙인 뒤 `spctl --assess --type execute --verbose=4`를 실행하자 `rejected`, `source=no usable signature`(종료 코드 3)였습니다. 같은 임시 파일은 `/bin/bash 파일경로`로 실행됐습니다. [Apple 공식 안내](https://support.apple.com/102445)는 미확인 개발자 앱의 보안 예외를 설정에서 허용하는 절차를 설명합니다. **Finder/Archive Utility의 격리 전파·실제 더블클릭 경고·이 파일의 예외 버튼 노출은 GUI를 실행하지 않아 미검증입니다 [INFERENCE].** `spctl` 결과만으로 Finder 동작을 보장하지 않습니다.

첫 설치의 `install.sh`는 `routine setup`을 호출합니다. TTY는 단계 체크리스트를 갱신하고 실행 중 스피너·경과시간을 보여 줍니다. 비 TTY는 단계별 한 줄 요약을 출력합니다. 상세 로그는 `~/Library/Logs/routine-automation/setup-<시각>-<PID>.log`입니다.

## 이후 업데이트

인자가 없으면 **`coldplay126/routine-automation`의 공개 Release**를 인증 없는 `curl`로 조회합니다. 업데이트 자체에는 `gh` 로그인이나 설치가 필요하지 않습니다. 저장소 이름과 ID `1405988374`는 코드 상수이며 설정 파일로 바꿀 수 없습니다. `ROUTINE_TEST_RELEASE_REPO`는 소스 트리의 격리 테스트에서만 동작하며 manifest가 있는 설치본에서는 무시합니다.

```bash
routine update
routine update --check             # 버전·변경 내역 확인만
routine update --yes               # GitHub 또는 직접 지정한 비Downloads ZIP의 확인 질문 생략
routine update "/다른 위치/routine-automation-<VERSION>.zip"
routine update --from downloads    # 네트워크 없이 Downloads에서만 찾기
routine update --from github       # 공개 Release만 사용
```

### Release 선택과 다운로드 검증

GitHub의 `/repositories/1405988374/releases?per_page=100&page=N` 목록을 페이지 끝까지 조회해 **draft는 제외하고 prerelease는 포함**합니다. 태그가 정확한 `vMAJOR.MINOR.PATCH`인 Release 중 세 숫자를 비교해 최고 버전을 고릅니다 (`0.10.0 > 0.9.0`). 해당 Release에서 `state: uploaded`인 `routine-automation-<버전>.zip` asset 하나만 사용하며, 실제 바이트 수와 SHA-256을 API `size`·`digest`에 대조합니다. zip 내부 VERSION이 태그와 달라도 거부합니다. `/releases/latest`나 태그 없는 `gh release download`는 사용하지 않습니다. 최초 URL은 저장소·태그·파일명까지 정확히 `https://github.com/coldplay126/routine-automation/releases/download/v<버전>/routine-automation-<버전>.zip`이어야 합니다. 이후 HTTPS `objects.githubusercontent.com`·`release-assets.githubusercontent.com`의 정확한 호스트만 허용하고 각 리다이렉트를 요청 전에 검사합니다(최대 5회 요청). 만료되는 서명 URL은 캐시하지 않고 매번 최초 URL에서 다시 해석합니다. 다운로드는 64MiB, 목록 페이지는 2MiB로 제한합니다.

네트워크 실패·HTTP 403/429 요청 제한·빈 공개 목록·asset 검증 실패이면 이유와 수동 경로를 안내하고 **설치하지 않습니다. Downloads로 자동 대체하지 않습니다.** `routine update --from downloads`를 직접 지정해야 오프라인 후보를 탐색합니다. 직접 ZIP 경로를 주면 네트워크를 조회하지 않으며 `--from`과 함께 쓸 수 없습니다. GitHub 인프라 변화나 업로드 미완료로 원격 업데이트가 막히면 `--from downloads` 또는 신뢰한 ZIP을 직접 풀어 `install.sh --update`를 사용하세요. 배포된 0.1.0 클라이언트는 새 정책으로 바뀌기 전까지 `routine update --from github`로 업데이트하는 편이 안전합니다.

### Downloads 선택과 출처 확인

Downloads에서는 `~/Downloads/routine-automation-*.zip` 중 **전체 검증을 통과한 zip의 VERSION이 가장 높은 것**을 고릅니다. 파일명의 버전은 믿지 않으며, 잘못된 ZIP은 경로와 거부 이유를 표시하고 다음 후보를 찾습니다. `ROUTINE_DOWNLOADS_DIR`로 검색 폴더를 바꿀 수 있습니다. 검증 결과는 경로·크기·나노초 mtime/ctime·inode별로 0600 캐시하며, 전체 탐색은 `gtimeout`/`timeout`으로 15초(강제 종료 유예 1초) 제한합니다. 시간 초과로 검증 프로세스가 강제 종료되어도 부모가 압축 해제·캐시 임시 파일을 정리합니다. 설치 직전에는 선택한 ZIP을 다시 검증합니다.
Downloads에서 고르거나 그 폴더의 ZIP을 직접 지정하면 **경로·SHA-256·quarantine·`kMDItemWhereFroms` 출처**를 보여 줍니다. 이 메타데이터는 위조·누락될 수 있어 출처 증명이 아닙니다. 실제 설치는 **TTY에서 별도로 확인해야 하며 `--yes`도 생략하지 못합니다. 비TTY에서는 거부**합니다. `--check`는 비TTY에서도 설치 없이 확인할 수 있습니다. 압축을 푼 폴더는 자동 후보가 아니지만 그 폴더의 `./install.sh`는 첫 설치·재설정 대안으로 동작합니다.
공개 전 개발판을 거르는 표지로 루트의 **정확한 `LICENSE` 이름·비어 있지 않은 일반 파일·첫 줄 `MIT License`**를 확인합니다. 이 표지는 ZIP 출처나 작성자의 진위를 증명하지 않습니다. 버전 번호 자체는 차단하지 않아 이후 정식 공개 버전으로도 업데이트할 수 있습니다.

### ZIP 검증과 설치 동의

설치 전 안전한 경로·일반 파일 속성·압축 해제 총량 **64MiB 이하**·VERSION **32바이트 이하**를 확인하고 `unzip -tq`로 무결성을 검사합니다. 권한 0700 임시 디렉터리에 macOS `ditto`로 풀어 한글 파일명과 실행 권한을 보존한 뒤, **실제 트리**의 단일 최상위 폴더·필수 일반 파일·중복을 확인합니다. 절대경로·`..`·링크·비정규 파일·대소문자/Unicode 정규화 충돌·압축 해제 중 덮어쓰기는 거부합니다. 한글 이름을 손실시키는 목록 출력으로 파일의 중복 여부를 판단하지 않습니다. 검증이 끝난 뒤에만 `✓ zip 검증`, 현재 → 새 버전, 두 버전 사이의 변경 내역을 보여 줍니다. 변경 내역의 C0·C1·bidi 제어문자는 제거합니다. GitHub·직접 지정한 비Downloads ZIP은 비TTY에서 `--yes` 없으면 안내만 하고 설치하지 않습니다. Downloads는 `--yes`여도 TTY 확인을 요구합니다. `--check`는 임시 파일을 정리하고 설치본·설정에 손대지 않습니다. 같거나 낮은 버전은 **이미 최신**으로 안내하고 설치하지 않습니다. 낮은 버전이 필요하면 아래 롤백 절차를 따르세요.

### 설정 보존과 중단 복구

업데이트는 새 zip의 `install.sh --update`로 **기존 설치 트랜잭션만** 실행합니다. manifest의 `configuration_path`에 기록된 기존 설정을 읽으므로 사용자 지정 경로도 유지합니다. 명시한 `ROUTINE_CONFIG`가 설치 기록과 다르면 경로를 바꾸지 않고 중단·안내합니다. 설정 파일 자체와 수집 데이터·로그·install-id는 보존하며, 로그인·권한 요청·첫 실행·수집·LLM·Slack 조작은 하지 않습니다. 아침 루틴이나 스크럼 붙여넣기가 실행 중이면 파일 교체를 미룹니다. 파일·복사/검토 앱·LaunchAgent를 갱신하고 **LaunchAgent 로드까지 성공한 뒤에만** 새 세대를 확정합니다. 실패하면 기존 manifest/소유권 검증·journal 복구로 되돌립니다.

강제 종료 등으로 journal 또는 `.previous` 세대가 남으면 버전이 같아도 최신으로 판단하지 않습니다. `routine update --yes`는 버전 비교 전에 소유 확인된 중단 기록을 복구하고 다시 업데이트합니다. `--check`와 동의 없는 실행은 복구 안내만 하며, `routine status`는 미완료 설치와 미등록 LaunchAgent를 경고합니다. 실행 중인 루틴이나 다른 설치 작업이 있으면 복구도 미룹니다. 설치본 명령을 실행할 수 없으면 **새 zip을 풀고 그 안의 `install.sh --update`**를 실행하세요.

새 설정 키는 **이전 동작을 유지하는 의미 있는 기본값**을 `config.jq`에 두고, 이전 저장 형식 변환은 순수한 `migrate_config`에서 처리합니다. 업데이트는 이 결과를 메모리에서 사용할 뿐 저장된 설정을 자동으로 덮어쓰지 않습니다. 기본값으로 채울 수 없는 새 필수 키나 사용자 선택이 필요하면 설치 전에 멈춥니다. 이때는 기존 설치본의 `routine init`이 아니라 **새 zip을 직접 풀어 새 `routine 설치.command` 또는 새 `bin/routine setup`**으로 설정을 확인하세요. 값·경로 변경은 사용자 확인 후 진행합니다.

### 새 버전 알림과 임시 파일

완료 시 업데이트된 버전을 표시합니다. 사용자가 지정하거나 Downloads에서 찾은 zip은 그대로 보관하고, GitHub에서 받은 임시 zip은 종료 시 정리합니다. `routine status`와 아침 요약/알림은 같은 공개 목록을 **총 5초 이내**로 조회하고 `~/Library/Caches/routine-automation/releases.json`에 0600 권한으로 하루 한 번 캐시합니다. 실패도 그날 캐시하며 **Downloads를 탐색하거나 알리지 않습니다. 설치본 VERSION**보다 높은 GitHub 버전만 `새 버전 <VERSION> — routine update`로 안내합니다. asset 다운로드나 자동 설치는 하지 않습니다.

## 1.0 개발판·초기 빌드 전환

공개 전 1.0 개발판이나 업데이트 명령이 없는 초기 빌드에서도 아래 수동 경로를 사용합니다.

업데이트 명령이 없거나 공개 베타보다 높은 번호의 비공개 개발 설치본에서 전환할 때는 최신 zip을 먼저 풀고 **`/bin/bash "$HOME/Downloads/routine-automation-<VERSION>/install.sh" --update`**를 한 번 실행하세요. 이 명시적 경로는 버전 번호가 내려가는 전환에도 기존 설정·데이터·설치 신원을 보존하며 첫 실행을 하지 않습니다. `routine update` 자체는 같은 버전이나 낮은 버전을 설치하지 않습니다.

## 첫 설치·재설정의 세부 동작

터미널에서 `gum`이 있으면 링크·수동 값 입력, 확인 질문, Git 위치·수집 소스의 복수 선택과 권한 안내 박스를 gum으로 표시합니다. `dependencies` 단계는 gum이 없을 때 설치를 제안하지만 **명시적으로 동의한 경우에만** `brew install gum`을 실행합니다 (`--yes`로 동의를 대신하지 않음). 거절하거나 설치가 실패해도 기존 텍스트 방식으로 계속 진행합니다. gum은 선택 의존성이며, 없거나 비 TTY이면 텍스트 방식이 유지됩니다. `--non-interactive`에서는 질문하지 않습니다.

<details>
<summary>터미널 화면·진행 표시 세부</summary>

체크리스트는 기존 상대 이동 방식으로 갱신합니다. TTY에서는 `routine 설정 · 10단계` 머리글 아래 한글 단계 이름을 고정 셀 폭으로 맞추고, 완료·실패 단계의 소요 시간을 오른쪽에 표시합니다. 대기 `○`·건너뜀 `–`·실행 안 함 `·`은 회색, 진행 중 기호는 파랑, 완료 `✓`는 초록, 실패 `✗`는 빨강입니다. 이름은 기본색, 건너뜀 사유·실행 안 함·시간은 회색(245)을 사용합니다. 비 TTY에서는 내부 단계 ID를 포함한 기존 출력 형식을 유지합니다. init은 `설정 N/M · 이름` 머리글로 진행하며, 클립보드 방식은 4단계, 자동 붙여넣기는 Slack 정보 단계를 포함한 5단계입니다. 머리글은 빈 줄, 회색 단계 번호와 기본색의 굵은 이름, 최대 48셀의 얇은 구분선으로 구성합니다. gum 모드의 전환·종료는 현재 단계가 소유한 화면 안 출력만 지워 이전 질문·요약이 쌓이지 않게 합니다. 커서·입력 기호는 파랑(75), 선택 기호는 초록, 확인 필요·선택 불가는 노랑 또는 빨강입니다. `NO_COLOR`가 설정되어 있거나 gum이 없거나 비 TTY이면 색을 쓰지 않습니다.
첫 실행 대기는 이번 kickstart 직전의 로그 위치부터 읽어 `수집 중 · 0:42`, `초안 작성 중 (LLM) · 0:12`처럼 현재 작업과 해당 작업의 경과시간을 표시합니다. 수집 중에는 `git ✓ · PR ✓ · omp 세션 …`처럼 소스별 상태도 보여 줍니다. 완료한 작업의 시간은 회색으로 누적하되 한 줄에 들어가지 않으면 현재 작업만 표시합니다. 아래에는 `보통 1~3분 · s 키: 기다리지 않고 넘어가기 (실행은 계속)` 안내가 나옵니다. 대기 중에는 비정규 입력 모드로 전환하고 커서를 숨겨 터미널의 비밀번호 입력 표시가 나타나지 않게 하며, 완료·중단·Ctrl-C/SIGTERM 뒤에는 원래 입력 모드와 커서를 복원합니다.
안내 박스는 정보(💡), 주의(⚠️), 오류(⛔), 성공(✅), 요약(📋), 권한(🔐)을 구분합니다. 제목은 기본색으로 굵게, 본문은 기본색으로 표시하고 아이콘과 테두리에만 상태색을 사용합니다. 정보·요약 테두리는 회색, 주의·권한은 노랑, 오류는 빨강, 성공은 초록입니다. 확인 버튼은 선택 상태에서 파랑 배경(25)에 굵은 흰 글자(231), 미선택 상태에서 짙은 회색 배경(237)에 밝은 글자(252)를 사용합니다. 전경/배경 대비는 각각 6.45:1, 7.37:1입니다. 목록은 파란 커서 `›`, 회색 미선택 기호 `○`, 초록 선택 기호 `●`로 구분하고 항목 글자는 터미널 기본색을 사용합니다.
파일·파이프로 보내는 stdout은 평문을 유지하고, `/dev/tty`의 대화형 화면만 색을 사용합니다. 긴 줄은 터미널 폭에 맞춰 줄바꿈하며 macOS의 NFD 한글 경로·결합 문자는 실제 셀 폭으로 셉니다. 지울 줄 수는 화면에 남아 있는 init 출력 범위로 제한해 앞선 셸 출력이나 체크리스트를 건드리지 않습니다. 좁은 터미널에서는 요약 박스 대신 텍스트 표를 사용하며 화면 밖 스크롤백은 지우지 않습니다.

setup의 마지막 화면은 체크리스트 한 벌과 결과 안내로 정리합니다. 실패 안내는 단계 이름과 소요 시간, 개인 값이 포함되지 않는 단계별 확인 사항, `~`로 축약한 로그 경로, `routine setup` 재실행 안내를 표시합니다. 로그 경로는 자체 줄에 두고 폭을 넘으면 줄바꿈합니다. 좁은 화면과 NO_COLOR에서는 텍스트 안내를 사용합니다. 성공 안내는 총 소요 시간과 `routine status`·설정 변경 안내를 표시합니다. standalone init은 저장 시 `✓ 설정 저장`, 취소 시 `– 설정 저장 취소, 기존 설정 유지` 한 줄을 남깁니다.
최근 first-run의 전체 디스크 접근 상태가 `denied`이면 TTY 완료 화면에도 보호 경로 읽기 거부 경고를 남깁니다. TTY first-run 실패에서도 `/bin/bash`의 전체 디스크 접근 보고를 유지합니다.

</details>

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

### 건너뛰기와 재실행

로그인 대기 중 `s`를 누르면 해당 단계를 건너뜁니다. 첫 실행 확인 중에도 `s`로 대기만 건너뛸 수 있으며 이미 시작한 LaunchAgent는 계속 실행됩니다. 실패하면 해당 단계에서 중단합니다. 첫 실행의 morning 성공/실패 결과를 요청 ID로 확인하여 실패 즉시 중단하고 표지를 정리합니다. 재실행하면 의존성·로그인·기존 설정을 다시 확인하고 충족된 단계는 완료로 표시합니다.
Orca 선택은 설정 질문보다 먼저 진행합니다. 기본은 클립보드이며, 자동 붙여넣기를 고르면 Slack 화면 읽기에 필요한 접근성과 결과 확인에 필요한 화면 기록 권한을 안내합니다. 권한을 허용하면 질문 없이 실제 읽기 성공으로 완료하고, `s`로 건너뛰면 전달 방식을 `clipboard`로 저장합니다. 체크리스트는 그린 줄 수만큼 상대적으로 올라가 지우고 다시 그립니다. 대화형 출력 전에는 이전 체크리스트를 지우고 줄 수를 초기화하므로, 터미널이 스크롤되어도 질문을 덮거나 체크리스트가 쌓이지 않습니다. 스피너 중에는 터미널 에코를 끄고, 종료·중단 시 원래 모드를 복원합니다. 스피너가 실제로 그린 줄 수도 부모에 전달해 다음 질문 앞에서 정확히 지웁니다.
설치 파일·저장된 설정·로드 상태가 같으면 파일 복사·앱 재컴파일·LaunchAgent 재로드를 하지 않습니다. 같은 버전·설정·날짜의 첫 실행이 이미 검증됐으면 kickstart도 반복하지 않습니다. 보호 경로 읽기가 거부된 첫 실행은 권한 변경 뒤 재검증합니다.

```bash
bin/routine setup --yes --non-interactive --skip disk-access
bin/routine setup --overwrite-config
bin/routine setup --skip first-run
```

### 전체 디스크 접근

`--yes` 없이 비대화형 설치 명령을 실행하지 않습니다. **`--yes`는 전체 디스크 접근 허용을 확인한 것으로 취급하지 않습니다.** 터미널에서 `~/Library/Mail`을 읽을 수 있어도 launchd의 `/bin/bash` 권한 증거가 아니므로, TTY에서 시스템 설정을 열고 직접 확인합니다. 터미널 읽기 실패만으로 확인 후 설치를 막지 않습니다. 실제 first-run morning(`/bin/bash`)이 같은 보호 경로를 읽어 결과 JSON에 `readable`/`denied`/`unverified`를 기록합니다. 경로가 없으면 미검증이며, 거부는 설치 실패가 아니라 `/bin/bash에 전체 디스크 접근 허용 필요` 경고입니다. setup/status/doctor에서 최근 결과와 `--skip disk-access` 안내를 확인할 수 있습니다. `--non-interactive`는 로그인·권한 확인을 대신하지 않으며, 이전의 명시적 확인이 없으면 TTY에서 확인하거나 해당 단계를 건너뛰세요.

대화형 설치의 전체 디스크 접근 단계는 시스템 설정을 열고 `[+]` → `Cmd+Shift+G` → `/bin/bash` 추가 순서를 화면에 안내합니다. `n`으로 답하면 설치를 멈추지 않고 이 단계만 건너뛰며, 첫 실행에서 실제 권한을 다시 확인합니다.

## 설치 소유권과 복구

설치 파일은 `~/.local/share/routine-automation`, PATH 링크는 **`~/.local/bin/routine` 하나**입니다. 기존 `morning`, `scrum-collect`, `scrum-draft`, `scrum-paste` 링크는 이 설치 또는 현재 배포 폴더를 가리킬 때만 제거합니다. 남의 링크는 보존합니다.

설치 루트의 `install-id`와 `manifest.json`에 파일 경로·SHA-256, 링크 대상이 기록됩니다. 새 zip을 **다른 폴더**에 풀어 `./install.sh`를 실행해도 같은 설치를 업데이트하며 설정·수집 데이터·로그는 보존됩니다. 경로 문자열을 설치 신원으로 사용하지 않습니다. 기존 `.source-repo`/`.files` 설치는 기존 파일 목록·링크·프로그램 경로를 검증한 뒤 새 manifest로 이전합니다. 소유하지 않은 파일/앱/plist 또는 변경된 관리 파일은 덮어쓰거나 삭제하지 않고 중단합니다. 설치 복사본의 `com.apple.quarantine` 속성을 제거합니다.
관리 파일·링크·앱이 이미 삭제됐으면 업데이트/제거를 막지 않습니다. plist 파일이 없어도 manifest의 경로에서 라벨을 구해 로드된 서비스를 bootout합니다. 재설치는 누락 자산을 복원하되, 존재하는 파일의 해시 불일치는 계속 거부합니다. 완성된 manifest를 포함한 임시 설치 루트를 rename으로 교체하며 실패하면 이전 루트·외부 자산과 기존에 로드됐던 LaunchAgent를 복원합니다.
SIGKILL로 중단돼도 다음 setup/uninstall이 `.previous`와 설치 journal의 ID·경로·파일 해시를 확인해 이전 자산을 복원하고 소유가 확인된 `.routine-install.*`/`.routine-transaction.*`만 정리합니다. 루트가 `.previous`에만 있어도 uninstall할 수 있습니다. 다른 설치가 진행 중이면 중단합니다. 소유 journal에 사용자가 추가/변경한 파일이 있으면 이전 세대를 삭제하지 않고 복구를 중단하며, 소유를 확인할 수 없는 별도 임시 디렉터리는 보존합니다.

## 롤백·제거

검토 앱을 모르는 이전 버전으로 롤백할 때는 **현재 버전의 `routine uninstall`을 먼저 실행한 뒤 이전 패키지를 설치**하세요. `--purge` 없이 제거하면 설정·데이터·로그가 보존됩니다. 이전 버전으로 현재 설치를 직접 덮어쓰거나 제거하면 검토 앱 경로의 소유 검증에서 차단될 수 있습니다.

```bash
routine uninstall           # LaunchAgent·링크·복사/검토 앱·설치 루트만 제거
routine uninstall --purge   # 설정·데이터·로그도 제거
```

실행 중인 LaunchAgent의 `bootout`이 실패하면 제거를 중단합니다. 외부 파일은 manifest와 일치할 때만 제거합니다. `~/Applications/스크럼 초안 복사.app`과 `스크럼 초안 검토.app`도 설치가 소유한 경우에만 제거합니다. 앱에 추가되거나 변경된 파일이 있으면 제거를 거부합니다.
설정 JSON이 깨져 있어도 manifest 소유 검증으로 uninstall할 수 있습니다.

Jira 토큰은 Keychain에 별도로 보관하므로 `uninstall --purge`도 지우지 않습니다. 토큰까지 제거하려면 설정에 쓴 이메일로 다음 명령을 실행하세요.

```bash
security delete-generic-password -s routine-automation.jira -a "<이메일>"
```
