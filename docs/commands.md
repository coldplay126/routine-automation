# 전체 명령

`routine --help`와 `routine <명령> --help`로 사용법을 확인할 수 있습니다.
하위 명령의 도움말은 설정 없이 동작합니다.

- [명령 목록](#명령-목록)
- [예약과 실행 예시](#예약과-실행-예시)
- [휴무·예외 근무일](#휴무예외-근무일)
- [수집 결과와 PR 판정](#수집-결과와-pr-판정)

[설치](install.md) · [설정](configuration.md) · [안전과 한계](safety.md)

## 명령 목록

| 명령 | 동작 |
|---|---|
| `routine setup` | 설치 마법사 |
| `routine init` | 설정 생성·수정 |
| `routine doctor` | 읽기 전용 의존성·버전·로그인·필수 설정·LaunchAgent·선택형 Orca 점검 |
| `routine sources [enable\|disable NAME]` | 소스 선택·사용 조건 확인, 설정 파일만 변경 |
| `routine status` | 오늘 소스 건수·오류, 초안 항목·확인 필요, 전달 표지, extra_steps 결과, 다음 예약 |
| `routine off [날짜\|범위] [메모]` / `off --remove 날짜\|범위` | 개인 휴무 등록·삭제. 인자 없으면 앞으로 60일 공휴일·휴무·예외 목록 |
| `routine work 날짜` / `work --remove 날짜` | 개인 예외 근무일 지정·삭제. 휴가·공휴일·주말보다 우선 |
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

## 예약과 실행 예시

LaunchAgent는 TCC 권한 귀속을 위해 `/bin/bash <설치본>/bin/routine run`을 실행합니다.
gui-paste의 별도 agent는 `/bin/bash <설치본>/bin/routine paste --auto`를 600초 간격으로 실행합니다.
clipboard에서는 paste agent를 설치하지 않습니다.
설정 변경 뒤 예약/plist를 바꾸려면 setup을 다시 실행하세요.

시스템 launchd 예약 자체는 시스템 로컬 시간 기준입니다.
`timezone`은 수집·초안·상태의 시간대이며 시스템과 다르면 macOS 시간대도 맞추세요.

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

## 휴무·예외 근무일

```bash
routine off 10-07~10-08 연차
routine off tomorrow 회사 휴무
routine off                              # 오늘부터 60일의 일정
routine off --remove 10-07~10-08
routine work 10-09                       # 한글날에도 스크럼 작성
routine work today
routine work --remove 10-09
```

날짜는 `YYYY-MM-DD` 또는 올해의 `MM-DD`입니다. `off`는 `today`·`tomorrow`와 양끝 포함 범위를, `work`는 날짜 하나 또는 `today`만 받습니다.
과거 날짜·존재하지 않는 날짜·잘못된 형식·역순 범위·60일을 넘는 범위는 저장 전에 거부합니다.
연도 경계는 `12-31~2027-01-02`처럼 끝의 연도를 명시하세요. 중복 날짜는 한 번만 저장합니다.
메모는 휴무 날짜별 `calendar.day_off_notes`에 저장하며 삭제할 때 같이 지웁니다.
기존 설정 경로를 원자적으로 저장하고 0600 권한을 유지합니다.
예약 요일 밖의 예외 근무일에는 launchd가 실행되지 않습니다. 그날 `routine run`으로 수동 실행하세요.
근무일·휴무 변경에는 plist를 바꾸지 않으므로 setup 재실행이 필요 없습니다.

## 수집 결과와 PR 판정

`morning`·`scrum-*`는 설치 내부 구현입니다. PATH 별칭은 제공하지 않습니다.
기본 수집 창은 공휴일·개인 휴무·근무 예외를 반영한 직전 근무일 00:00부터 실행일 로컬 00:00 미만입니다.
직전 근무일이 멀면 `collect.max_days`(기본 14)로 제한하며, 초안 질문 목록·status에 안내합니다. 명시적 `--since`는 이 기본 제한보다 우선합니다.
`collect.until=now` 또는 명시적 `--until`로 상한을 바꿀 수 있습니다.
수집 파일이 없는 draft도 같은 직전 근무일 계산과 상한 설정을 사용합니다.

PR 검색의 `updatedAt >= 시작 시각`은 후보 선정 조건일 뿐입니다.
역할별 검색은 updated 내림차순으로 받고 URL 중복을 제거한 뒤
내 작성 PR(기간 내 생성 우선) → 내 리뷰 PR → 내 코멘트 PR 순서로 최대 50개를 한 번씩 조회합니다.
검색 역할 하나라도 50개에 도달하거나 중복 제거 결과가 50개를 넘으면 포화 오류를 남깁니다.

`gh api user`의 login으로 내 생성·직접 병합·커밋·리뷰·코멘트 시각을 확인하고
`[시작, 종료)` 안의 내 활동이 있을 때 `in_window: true`로 표시합니다.
`mergedBy`가 다른 계정이면 `merged_by_other`로 병합 결과를 기록하지만 그것만으로 내 어제 작업을 만들지 않습니다.
닫기는 행위자를 확인할 수 없어 내 활동으로 세지 않습니다.
오래전 열린 PR도 기간 내 내 활동이 있으면 포함되지만, 기간 밖의 마지막 변경만으로 어제 근거가 되지는 않습니다.
현재 상태는 `current`에 따로 저장합니다.

검색·개별 PR 조회는 각각 20초, 계정 확인은 10초, 전체 PR 수집 단계는 120초 상한을 적용합니다.
단계 제한 뒤 남은 후보와 조회·활동 해석·계정 확인 실패는 `in_window: "unknown"`과 오류로 남깁니다.
draft는 이 수집 결과를 재사용하며 PR을 다시 조회하지 않습니다.

존재하지 않는 Git 위치는 경로 없음으로, 읽기 거부는 권한 오류로 기록하고,
stderr 없는 스캔 시간 초과도 오류 메시지를 남깁니다.
Slack URL 시각 해석 실패도 오류에 포함합니다.

결과는 `~/Library/Application Support/routine-automation/scrum/YYYY-MM-DD.{json,md}`와
`.draft.{json,html,txt,questions.md}`입니다. 새 데이터 디렉터리는 0700, 파일은 0600입니다.
Chrome/Notion은 원본의 읽기 전용 SQLite 온라인 백업을 검증하고 사본만 조회하며 원본을 수정하지 않습니다.
일관된 스냅샷을 얻지 못하면 소스 오류로 기록합니다.

`gh pr view`의 커밋 export는 첫 100개 상한이 있습니다.
커밋이 100개 이상이고 다른 근거에서도 기간 내 내 활동이 확인되지 않으면
활동이 없다고 단정하지 않고 `unknown`과 오류로 남깁니다.
리뷰·코멘트는 gh가 페이지를 모두 조회하므로 개수 100개만으로 포화 처리하지 않습니다.
커밋 응답이 포화되어도 기간 내 내 활동이 하나 이상 확인되면 `true`를 유지합니다.

큰 응답은 파일을 통해 해석하며 jq 인자 크기 제한을 피합니다.
`unknown` OPEN PR은 어제 근거에서는 제외하지만 오늘 계획에서는 사용할 수 있습니다.
이전 버전 수집 파일에 `in_window`가 없으면 질문에 `다시 routine collect 필요`를 표시합니다.
