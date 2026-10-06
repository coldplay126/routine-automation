# routine-automation

[![Release](https://img.shields.io/github/v/release/coldplay126/routine-automation?include_prereleases)](https://github.com/coldplay126/routine-automation/releases)
[![License: MIT](https://img.shields.io/github/license/coldplay126/routine-automation)](LICENSE)

근거 기반 업무 글 초안 도구 — 첫 프리셋: 데일리 스크럼 (베타)

> [!NOTE]
> 팀 시범 사용용 베타입니다. 설정·동작은 바뀔 수 있으며, 초안은 전송 전에 직접 검토해야 합니다.

## 무엇을 하나

평일 아침에 Git 커밋·GitHub PR·AI 작업 세션을 모아 LLM으로 스크럼 초안을 만듭니다.
Jira 방문 이력과 Notion 편집 기록도 선택해서 읽을 수 있습니다.
근거 없는 '완료' 표현을 걸러내고, 사람이 검토한 글을 복사하도록 돕습니다.
**Slack에 전송하지 않습니다.** 설치부터 시작하려면 [설치](#설치)를 참고하세요.

## 결과 예시

가상 작업 기록으로 만든 예시입니다. 기본 텍스트 출력과 같은 형식입니다.

```text
어제 작업한 내용
• 개발
  ◦ 예제 서비스
    ▪ 검색 필터 추가

오늘의 작업 계획
• 개발
  ◦ 예제 서비스
    ▪ 검색 필터 경계 조건 확인
```

수집 → 초안 → 근거 검증 → 검토 → 복사/붙여넣기. 마지막 전송은 사용자가 합니다.

## 목차

[요구 사항](#요구-사항) · [설치](#설치) · [매일 사용법](#매일-사용법) · [자주 쓰는 명령](#자주-쓰는-명령)
[설정 핵심](#설정-핵심) · [개인정보·안전](#개인정보안전) · [문제 해결](#문제-해결) · [문서](#문서) · [기여·문의](#기여문의) · [라이선스](#라이선스)

## 요구 사항

| 항목 | 요구 사항 |
|---|---|
| macOS | macOS 전용입니다. 설치 확인 환경은 26.3.1이며, 15 이상에서 보안 차단이 발생할 수 있습니다. |
| jq | 1.7 이상입니다. macOS 내장 jq 1.7.1도 사용할 수 있습니다. |
| Homebrew·coreutils | 설치 마법사는 Homebrew와 `gtimeout`을 확인합니다. |
| gh | GitHub PR 수집에 사용합니다. 소스 선택은 선택 사항이며, 설치 마법사는 gh 설치·로그인을 확인합니다. |
| gum | 선택 사항입니다. 없으면 터미널의 텍스트 안내를 사용합니다. |
| Claude Code 또는 omp | LLM 초안 작성에 사용합니다. 둘 다 없으면 로컬 요약을 사용할 수 있습니다. |
| Slack·Orca | Slack 데스크톱 앱을 사용합니다. Orca는 선택 기능인 자동 붙여넣기에만 필요합니다. |

## 설치

1. [최신 Release](https://github.com/coldplay126/routine-automation/releases)에서 `routine-automation-<VERSION>.zip`을 받습니다.
2. zip을 풀고 폴더를 엽니다.
3. `routine 설치.command`를 더블클릭하고 터미널 안내를 따릅니다.

`<VERSION>`은 받은 파일의 실제 버전입니다. 설치 마법사에서 소스·시간·전달 방식을 고릅니다.

<details>
<summary>macOS에서 더블클릭을 차단할 때</summary>

신뢰하는 배포본만 실행하세요. 더블클릭 직후 시스템 설정 › 개인정보 보호 및 보안의 '그래도 열기'를 확인합니다.
회사 정책상 예외를 허용하지 않거나 악성 소프트웨어·손상 경고가 나오면 강행하지 마세요.
터미널에서 실행하려면 실제 압축을 푼 경로로 바꿉니다.

```bash
/bin/bash "$HOME/Downloads/routine-automation-<VERSION>/install.sh"
```

전역 Gatekeeper를 끄거나 Downloads 전체의 격리 속성을 제거하지 마세요.
[보안 차단 안내와 미검증 범위](docs/install.md#첫-설치)를 참고하세요.

</details>

업데이트는 `routine update`, 제거는 `routine uninstall`입니다. 기본 제거는 설정·데이터·로그를 보존합니다.
출처 선택, 초기 개발판 전환, 복구·롤백과 완전 제거는 [설치 문서](docs/install.md)에 있습니다.

## 매일 사용법

1. 근무일 아침에 '초안 준비' 알림을 받습니다. 기본 예약은 평일 08:00이며 한국 공휴일과 등록한 휴무일에는 스크럼을 건너뜁니다.
2. `routine review` 또는 Spotlight의 '스크럼 초안 검토' 앱을 엽니다.
3. 근거를 확인하고 항목을 선택·편집한 뒤 미리보기를 복사합니다.
4. Slack 채널을 열어 직접 붙여넣고 전송합니다.

휴가 전에는 `routine off 10-07~10-08`로 등록하세요. 휴일에 일한다면 `routine work 10-09`로 예외를 지정할 수 있습니다.

`routine copy`나 '스크럼 초안 복사' 앱은 기존 초안 전체를 복사하고 Slack 채널을 엽니다.
자동 붙여넣기(`gui-paste`)는 선택 기능입니다. Orca로 스레드에 붙여넣기까지만 하며 전송하지 않습니다.
검토 화면의 편집은 저장되지 않습니다. 새로고침하면 원래 초안으로 돌아갑니다.

## 자주 쓰는 명령

| 명령 | 하는 일 |
|---|---|
| `routine 설치.command` | 압축을 푼 폴더에서 더블클릭해 첫 설치를 시작합니다. CLI 하위 명령은 아닙니다. |
| `routine setup` | 설치·로그인·권한·설정·예약을 다시 확인합니다. |
| `routine status` | 수집·초안·다음 예약과 새 공개 버전을 확인합니다. |
| `routine off` / `routine off 날짜[~날짜] [메모]` | 앞으로 60일의 일정을 보거나 개인 휴무를 등록합니다. |
| `routine work 날짜` | 휴가·공휴일·주말의 예외 근무일을 지정합니다. |
| `routine review` | 로컬 초안 검토 화면을 엽니다. |
| `routine copy` | 오늘 초안 전체를 복사하고 Slack 채널을 엽니다. |
| `routine paste` | 선택한 전달 방식으로 붙여넣기를 진행합니다. 전송은 하지 않습니다. |
| `routine update` | 공개 Release의 새 버전을 확인하고 동의 후 설치합니다. |
| `routine style` / `routine style edit` | 표현 선호·출력 형식을 확인하거나 스타일 파일을 편집합니다. |
| `routine learn` | 보낸 글과 초안을 비교하고 선택한 표현 선호만 반영합니다. |
| `routine sources` | 수집 소스의 선택 상태와 사용 조건을 확인합니다. |
| `routine doctor` | 의존성·설정·예약·선택형 Orca 상태를 읽기 전용으로 점검합니다. |
| `routine uninstall` | 이 설치가 소유한 파일·앱·예약을 제거합니다. |

전체 명령과 옵션은 `routine --help`, `routine <명령> --help`, [명령 문서](docs/commands.md)를 참고하세요.

## 설정 핵심

- 설정 파일은 `~/.config/routine-automation/config.json`입니다. `ROUTINE_CONFIG`로 경로를 바꿀 수 있습니다.
- `routine setup`으로 설정을 다시 확인합니다. 설정만 바꾸려면 `routine init`을 사용합니다.
- 소스는 `routine sources`로 확인합니다. 기본 수집 기간은 직전 근무일부터 오늘 00:00 미만입니다.
- 표현 선호는 설정 파일 옆의 `style.md`에 적습니다. `routine style edit`으로 열 수 있습니다.
- 글머리·트리/평면 형식·항목 수는 `draft.format`으로 바꿉니다. 예약 변경 뒤에는 setup을 다시 실행합니다.

모든 설정 키, 소스·수집 기간, 보낸 글 학습은 [설정 문서](docs/configuration.md)에 있습니다.

## 개인정보·안전

- 로컬 Git, OMP·Claude Code JSONL, 선택한 Chrome History·Notion DB를 읽습니다. 홈 전체를 스캔하지 않습니다.
- GitHub PR은 gh로 조회합니다. Slack 기록은 선택형 Orca 화면 읽기에서만 가져오며 무인 아침 수집에서는 제외합니다.
- 선택한 LLM 제공자에게 수집 근거·메모·스타일을 보냅니다. 토큰·키 등은 redact로 마스킹하지만 모든 민감정보를 지우지는 못합니다.
- LLM은 빈 작업 폴더에서 도구·세션·규칙을 제한해 호출합니다. 근거 검증에도 [알려진 한계](docs/safety.md#알려진-한계)가 있습니다.
- 설정·초안·검토 파일은 0600 권한으로 보관합니다. 마스킹 뒤에도 업무 문구가 남으므로 공유 전에 확인하세요.
- 자동 전송·Slack API 게시·댓글 입력창의 Return·채널 동시 전송 체크박스 조작은 하지 않습니다.
- 기본 전달 방식은 알림만입니다. 검토 화면은 외부 리소스·네트워크 요청 없이 로컬에서 동작합니다.

도입 전에 회사의 소스 공개·업무 데이터·LLM 사용 정책을 확인하세요. 세부 규칙은 [안전 문서](docs/safety.md)에 있습니다.

## 문제 해결

### 설치나 실행이 안 됩니다

`routine doctor`로 의존성·필수 설정·예약을 점검하세요. 설치를 다시 확인하려면 `routine setup`을 실행합니다.

### macOS가 설치 파일을 차단합니다

위 [설치 대안](#설치)과 [상세 안내](docs/install.md#첫-설치)를 확인하세요. 조직 정책이나 손상 경고를 무시하지 마세요.

### 초안이 비어 있거나 없습니다

`routine status`의 소스 건수·오류와 `routine sources`의 사용 조건을 확인하세요.
Git 위치·작성자, gh 로그인, 세션 폴더와 `/bin/bash`의 전체 디스크 접근 권한을 점검합니다.
`routine review`는 없는 초안을 자동 생성하지 않습니다. 자세한 조건은 [설정 문서](docs/configuration.md#git-위치수집-소스)에 있습니다.

### 자동 붙여넣기를 건너뜁니다

기본 `clipboard`는 알림만 보냅니다. `gui-paste`도 시간 창·사용자 입력·실행 중 작업·기존 댓글/입력이 있으면 멈춥니다.
`routine status`와 [화면 안전장치](docs/safety.md#전달화면-안전장치)를 확인하고 Slack 화면을 직접 검토하세요.
"화면 형식 변경 의심"으로 멈췄다면 `~/Library/Logs/routine-automation/slack-format/`에 그때의 화면 구조와 확인 단계별 결과가 남습니다. 본문·입력값·이름·일반 링크는 글자 수로, 워크스페이스·채널·글 제목은 자리표시자로 가리지만 로컬 진단용입니다. 이슈에 첨부하기 전에 파일을 직접 열어 확인하세요.

### 업데이트가 실패합니다

GitHub 실패 시 Downloads로 자동 대체하지 않습니다. 신뢰한 zip을 Downloads에 받은 뒤 `routine update --from downloads`를 실행하세요.
출처를 확인하는 질문은 터미널에서 직접 답해야 합니다. 복구와 수동 설치는 [업데이트 안내](docs/install.md#이후-업데이트)를 참고하세요.

## 문서

- [설치·업데이트·복구·제거](docs/install.md)
- [설정·수집 소스·스타일·학습](docs/configuration.md)
- [전체 명령과 옵션](docs/commands.md)
- [개인정보·안전·알려진 한계](docs/safety.md)
- [개발·격리 검증·공개 배포](docs/development.md)
- [변경 내역](CHANGELOG.md)

## 기여·문의

베타 사용 중 겪은 문제와 피드백은 [Issues](https://github.com/coldplay126/routine-automation/issues)에 남겨 주세요.
설정·초안·로그를 첨부할 때는 개인 값과 업무 내용을 먼저 확인하세요. 개발 참여는 [개발자 문서](docs/development.md)를 참고하세요.

## 라이선스

[MIT](LICENSE) © 2026 coldplay126
