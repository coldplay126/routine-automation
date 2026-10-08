# 설정

`routine setup`으로 설치와 설정을 다시 확인할 수 있습니다.
설정만 바꾸려면 `routine init` 또는 아래 명령을 사용하세요.
예약을 바꾼 뒤에는 `routine setup`을 다시 실행해야 합니다.

- [설정 파일과 입력](#설정-파일과-입력)
- [Git 위치·수집 소스](#git-위치수집-소스)
- [수집 기간](#수집-기간)
- [근무일·공휴일·휴가](#근무일공휴일휴가)
- [프로젝트·표지](#프로젝트표지)
- [스타일·출력 형식](#스타일출력-형식)
- [보낸 글에서 배우기](#보낸-글에서-배우기)

[설치](install.md) · [안전과 한계](safety.md) · [전체 명령](commands.md)

## 설정 파일과 입력

기본 경로는 `~/.config/routine-automation/config.json`, 권한은 0600입니다.
`ROUTINE_CONFIG`로 재정의할 수 있습니다. 심볼릭 링크 설정 파일은 거부합니다.

우선순위는 CLI 플래그 > `ROUTINE_*` 환경 변수 > 설정 파일 > 기본값입니다.
`routine --set KEY JSON <cmd>`는 해당 실행과 자식 명령에만 적용하며 설정 파일을 바꾸지 않습니다.

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

### 필수 값과 자동 제안

Slack 글 링크에서 `workspace_domain`, `channel_id`를 추출합니다. `team_id`는 필수이며, `channel_name`, `post_title`, `slack_display_name`은 **gui-paste에서만 필수**입니다. 클립보드 복사와 Slack 검색 수집에는 이 세 값이 필요하지 않습니다. 프로젝트 이름은 선택 항목이며 대화형으로 묻지 않습니다. Git 수집을 켜면 `git_authors`와 하나 이상의 `sources.git.roots`가 필요하고, Notion을 켜면 `notion_email_like`가 필요합니다. Git author는 `git config user.email`과 `gh api user`의 GitHub noreply 주소로 감지합니다. 시스템 시간대와 `$USER` 기반 라벨을 사용합니다. Claude가 있으면 claude, 없으면 omp, 둘 다 없으면 none을 제안합니다.
링크의 워크스페이스가 바뀌면 이전 팀 ID·표시 이름을, 채널이 바뀌면 이전 채널 이름·글 제목을 비웁니다. 같은 init 호출에 명시한 Slack 플래그는 링크 적용 뒤에 반영하므로 새 대상의 지정값이 지워지지 않습니다. 최종 확인에서 링크를 다시 편집할 때는 이전 대상의 종속 값을 비우고 다시 확인합니다.
<details>
<summary>대화형 설정·Slack 감지·화면 표시 세부</summary>

대화형 init은 **스크럼 글 링크 하나**를 먼저 묻고, 워크스페이스 ID는 Slack의 `~/Library/Application Support/Slack/storage/root-state.json`에서 링크 도메인으로 읽기 전용 감지합니다. 실패할 때만 ID를 추가로 묻습니다. gui-paste이면 이동 전 전면 앱을 기록하며, `ui.terminal_bundle_ids`에 등록된 터미널 앱일 때만 `open -g`로 채널 딥링크를 열고 화면 감지를 진행합니다. 기본 목록에는 Terminal·iTerm2·VS Code·Cursor·주요 JetBrains IDE·Alacritty·WezTerm·kitty·Ghostty·Warp·cmux·Orca가 포함되며, 다른 터미널은 기존 목록에 bundle ID를 추가할 수 있습니다. 브라우저 등 다른 앱이면 이동 없이 수동 입력합니다. 링크의 `p<타임스탬프>`가 화면에 나타날 때까지 최대 5회, 1초 간격으로 확인한 뒤 채널·내 표시 이름·해당 타임스탬프를 감싸는 가장 가까운 메시지 컨테이너의 `<접두어>:`를 제안합니다. 가까운 컨테이너에 접두어가 없거나 들여쓰기로 메시지 경계를 확인할 수 없으면 제목을 제안하지 않습니다. 접두어가 작성자 이름일 수도 있으므로 제안을 확인하고 수정하세요. 댓글 수·답장 버튼·이전 글의 컨테이너에서 제목을 가져오지 않습니다. 연결된 글을 찾지 못하면 모든 제안을 버리고 수동 입력으로 진행합니다. 감지가 끝나면 약 1.5초 동안 전면 앱을 반복 확인하고 필요하면 터미널로 복원한 뒤 첫 입력을 받습니다. 매 질문의 입력을 읽기 직전에도 원래 터미널인지 확인하며, 복원에 실패하면 터미널을 클릭한 뒤 Enter로 확인할 때까지 기다립니다. 클릭·입력·전송은 하지 않습니다. standalone init에서 권한이나 실행 가능한 Orca가 없으면 수동 입력으로 진행합니다.
이어서 Git 위치와 수집 소스를 선택합니다. 세션 폴더가 없는 소스 등은 기본 선택에서 빠지며, 사용 불가 소스를 켜려 하면 필요한 조건을 안내하고 거부합니다. 비대화형 init은 명시한 플래그를 유지하며, 없는 세션 폴더는 명시적으로 켜지 않은 경우에만 자동 비활성화합니다.
Slack 정보 다음에는 채널·표시 이름·글 제목의 감지/입력/기존 값 구분, git 작성자 목록, LLM과 전달 방식을 요약 카드로 보여 줍니다. 라벨은 고정 폭 열에 기본색으로 굵게 표시하고, 구분선은 회색, 값은 기본색으로 유지합니다. 출처는 작은 상태색 점과 회색 `감지`·`입력`·`기존 값`·`미설정` 글자로 표시합니다. Slack, 수집, 초안·전달 묶음 사이에 빈 줄을 둡니다. gum에서는 테두리 박스, 텍스트 모드에서는 열을 맞춘 표를 사용하며 배열 JSON을 그대로 출력하지 않습니다. Git 위치 후보 탐색의 **세션 기록에서 저장소 위치 찾는 중…**과 읽기 전용 **Slack 화면 이동**은 gum 스피너로 표시합니다. 스피너는 명령을 한 번만 실행하고 성공/실패의 출력·종료 코드를 보존하며 실패한 명령을 다시 실행하지 않습니다. Slack 화면 이동 전후의 터미널 포커스 확인은 그대로 유지합니다.
대화형 설정은 저장 전에 **전체 설정 요약**(Git 위치·수집 소스·예약 요일/시각 포함)과 **저장 / 항목 고치기 / 취소**를 표시합니다. 고치기에서는 Slack 글 링크, 자동 붙여넣기의 Slack 정보, Git 위치, 수집 소스 또는 git 작성자를 골라 그 단계만 다시 실행한 뒤 최종 확인으로 돌아갑니다. 질문·항목 선택 중 Esc는 기존 값을 유지하고, **최종 확인의 취소·Esc는 저장 없이 종료**합니다 (`init` 종료 코드 1, setup의 `config` 단계 ✗와 재실행 안내). Ctrl-C는 setup 전체를 중단하며 설정 파일을 바꾸지 않습니다. 비대화형 init은 최종 확인 없이 기존처럼 검증 후 저장합니다. 필수 값이 비어 있으면 저장 전 검증에서 안내합니다.
필수 값이 없거나 형식이 잘못되면 이유를 표시하고 최종 메뉴에 머무릅니다. 이 상태에서 저장을 골라도 입력은 사라지지 않으며 항목 고치기로 수정할 수 있습니다. Git 위치를 0개로 확정하면 git 커밋 수집을 끌지 확인하고, 끄지 않으면 수집 소스 단계에서 선택을 고칩니다. Git 위치 재편집은 부분 선택·빈 선택을 그대로 유지합니다. git 작성자 재편집에는 **고치기 · git 작성자** 머리글을 사용하며 Enter로 기존 순서·값·감지 출처를 유지합니다. 텍스트 최종 메뉴의 Enter·범위 밖 번호·오타는 다시 묻고, 취소 항목의 번호 또는 EOF에서만 저장 없이 종료합니다.
gum 화면에서는 Space로 여러 항목을 선택하고 Enter로 확정합니다. 현재 선택은 미리 표시하며, 사용 불가 소스도 필요한 조건을 라벨에 표시합니다. 이를 선택하면 이유를 안내하고 재선택을 요청합니다. Git 저장소가 없으면 위치를 다시 고를 수 있고, 위치 0개 확정에는 기존 확인 질문을 유지합니다. Slack 화면에서 감지한 값은 gum 사용 시 확인하거나 수동으로 수정할 수 있습니다. gum 호출 전후에도 기존 `ensure_prompt_focus`로 원래 터미널이 전면인지 확인합니다.
`routine sources`를 파일·파이프로 출력할 때는 기존 `[ ]`·`[선택]`·`– 필요 조건` 평문 표지를 유지합니다. `○`·`●`·`⚠` 표지는 TTY 목록에서만 사용합니다.
</details>

### Git 위치의 안전 검사

자동 세션 후보만 물리 경로로 정규화한 홈 하위 폴더로 제한합니다. 저장된 Git 위치와 직접 `+경로`로 추가한 위치는 외장 볼륨이나 홈 밖을 가리키는 심볼릭 링크도 사용할 수 있습니다. `/Volumes/` 아래 저장 위치가 현재 연결되지 않았으면 `연결 안 됨`으로 표시하고 Enter 기본 확정에서는 유지합니다. 위치 번호를 명시적으로 해제해야 목록에서 제거합니다. 그 외 존재하지 않는 저장 위치는 `경로 없음`으로 표시하고 기본 선택에서 해제합니다. 모든 위치에서 홈 자체·홈 상위 경로·`/`·`~/.omp/wt`·`~/.cache`·`~/Library`는 거부하며, 안전하지 않은 저장 후보를 제외하면 이유를 표시합니다. `--sources-git-roots`와 `config set`으로 새 위치를 저장할 때도 같은 검증·정규화를 적용하며 연결된 폴더가 필요합니다. 세션 후보 탐색은 최근 수정된 JSONL 최대 300개를 확인합니다. OMP는 첫 줄의 session 헤더만, Claude는 앞부분 최대 64KB·50줄에서 첫 유효 cwd를 읽으므로 cwd 없는 메타 레코드가 앞에 있어도 감지할 수 있습니다. cwd를 먼저 정규화·중복 제거해 Git 조회를 반복하지 않고, 전체 탐색은 15초로 제한합니다. 실패·시간 초과 시 저장된 위치와 일반적인 개발 폴더 후보로 계속 진행합니다.

### 플래그와 저장 규칙

**모든 스키마 항목은 init 플래그로 지정할 수 있습니다.** 점과 밑줄을 `-`로 바꾸세요. 예: `--sources-claude-sessions-dir PATH`, `--morning-extra-steps-aws-session true`, `--delivery-daily-attempts 6`. `--set dotted.key VALUE`도 사용할 수 있습니다. init의 문자열은 그대로, 배열·불리언·숫자는 JSON, nullable 값은 `null`로 받습니다. `config set`과 진입점의 `--set`은 문자열도 JSON 따옴표로 감쌉니다.
환경 변수와 진입점 `--set`은 실행에만 적용합니다. `config set`/`init` 저장은 파일의 값과 명시적으로 바꾼 값·자동 제안만 사용하므로 일시적 GUI 전달 설정 등이 파일에 새지 않습니다. 하위 명령의 `--help`는 설정 없이 동작합니다.
setup의 영구 LaunchAgent/복사 앱은 **저장된 설정**으로만 만듭니다. 전역 `routine --set … setup`은 거부하며, 바꾸려면 `routine config set` 또는 setup의 init 플래그를 사용하세요. 명시적 setup 플래그와 Claude 미설치 시 omp 선택은 설정에도 저장됩니다.
이전 설정의 idle 하한·시간 접두어 등이 새 스키마에 맞지 않아도 JSON 루트가 객체이면 `config set`으로 해당 필드를, `init --non-interactive` 플래그로 여러 필드를 동시에 수정할 수 있습니다. 최종 저장값은 현재 스키마를 통과해야 합니다.

## 설정 키 전체

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
| `draft.projects` | object[], `[]` | 순서가 최상위 프로젝트 순서. 각 항목은 고유한 비공백 `label`, 선택 `owners`·`keywords` 문자열 배열. 빈 배열이면 분류가 최상위 |
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
| `collect.max_days` | 양의 정수, 14 | 직전 근무일이 멀면 기본 수집 기간을 이 일수로 제한. 명시적 `--since`는 우선 |
| `calendar.public_holidays` | `kr\|none`, `kr` | 한국 내장 공휴일 표(2026–2027) 사용 여부 |
| `calendar.days_off` | YYYY-MM-DD[], `[]` | 회사 휴무·연차·임시공휴일. 중복 없는 날짜 배열 |
| `calendar.work_days` | YYYY-MM-DD[], `[]` | 공휴일·개인 휴무·예약 요일보다 우선하는 예외 근무일 |
| `calendar.day_off_notes` | object, `{}` | `routine off` 메모를 날짜별로 저장. 근무일 판정에는 영향 없음 |
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
| `morning.extra_steps.jira_propose` | bool, false | `jira.enabled`일 때 읽기 전용 Jira 제안 생성. AWS 직전. 최초 setup 후 실행에서는 건너뜀 |
| `launchd.label_prefix` | string, `com.<$USER>.routine` | `.morning`/`.scrum-paste` 라벨 앞부분 |
| `timezone` | string/null, null=시스템 | 수집·초안·예약 표시 시간대 |

### Jira 동기화

`sources.jira.enabled`는 기존 Chrome 방문 기록 소스이고, 아래 `jira.enabled`와 별개입니다.
Jira 설정 오류는 `routine jira`·제안 생성에만 적용하며 기존 스크럼 초안을 막지 않습니다.

| 키 | 타입·기본값 | 설명 |
|---|---|---|
| `jira.enabled` | bool, false | API 동기화 사용 |
| `jira.site` / `.email` | string, `""` | `https://example.atlassian.net` 형식의 사이트 / Keychain account 이메일 |
| `jira.evidence_days` | 정수 1–30, 7 | 연결 판단 근거 기간 |
| `jira.candidate_days` | 정수 1–90, 30 | 내 미완료 이슈 연결 후보 검색 기간. 중복 검색에는 적용하지 않음 |
| `jira.duplicate_max_pages` | 정수 1–100, 20 | 중복 검색 쿼리당 페이지 상한. 끝까지 못 읽으면 생성 금지 |
| `jira.repos` | object, `{}` | 저장소 이름 → 프로젝트·제목 머리말. `prefix:""`는 머리말 없음이며 제목 앞에 공백을 붙이지 않음. 공백만 있는 머리말은 거부 |
| `jira.projects` | object, `{}` | 프로젝트별 초기 상태·진행 중 상태·생성 유형 ID |
| `jira.templates` | object, 작업/버그 양식 | 유형 이름 match, 머리글·스타일·완료 조건/링크 머리글 |
| `jira.stopwords` | string[], `[]` | 연결·검색에서 뺄 흔한 단어 추가 |
| `jira.key_like_ignore` | string[], `["CVE","RFC","GPT","ISO","SHA","UTF","TLS","HTTP"]` | 이슈 키처럼 보이는 문자열의 예외 접두어 |

검색의 저장소/접두어 제외는 현재 작업에만 적용합니다. 다른 저장소의 이름·접두어에 쓰인 업무 단어를 전역에서 지우지 않습니다. 모델 제목 앞의 설정 머리말/현재 저장소 토큰만 제거한 뒤 `jira.repos.<repo>.prefix`를 한 번만 붙이며 `[긴급]`·`[AOS]` 등 의미 있는 태그는 보존합니다. 미매핑 안내에는 해당 `jira.repos.<repo>.project` 설정과 작업 ID 예시를 표시합니다.

```bash
routine config set jira.site '"https://example.atlassian.net"'
routine config set jira.email '"fixture@example.com"'
routine config set jira.projects '{"ABC":{"statuses":{"start_from":["1"],"in_progress":"3"},"create_type":"10"}}'
routine config set jira.repos '{"example":{"project":"ABC","prefix":"[BACK]"}}'
routine config set jira.enabled true
routine config set morning.extra_steps.jira_propose true
```

상태 ID와 전환 ID는 다릅니다. 위 숫자는 가상 예시이므로 프로젝트의 실제 **상태 ID**와 유형 ID를 확인해 바꾸세요.
`start_from`에는 초기 상태 하나만 넣는 것을 권합니다. 보류 상태를 추가하면 자동 재개 제안의 대상이 됩니다.
객체 키는 `jira.projects`·`jira.repos`를 JSON 전체로 저장합니다. 새 환경 변수는 없습니다.
`prefix`는 문자열이어야 합니다. 머리말이 필요 없는 저장소는 `{"project":"ABC","prefix":""}`로 지정하세요.
새 이슈 담당자는 인증한 본인입니다. 타인 담당·미배정 이슈에는 댓글만 제안합니다.
작업 양식은 `확인사항/작업 내용/완료 조건/관련 링크`(strong),
버그 양식은 `[사전조건]/[재현경로]/[기대결과]/[실제결과]/관련 제보 링크`(plain)입니다.
버그에는 완료 조건 칸이 없고 관련 제보 링크 칸을 자동으로 채우지 않습니다.


### 환경 변수

기존 환경 변수 `ROUTINE_REPO_ROOT`(단일 경로 → roots 배열), `ROUTINE_GIT_AUTHORS`(공백 구분), `ROUTINE_OMP_SESSIONS`, `ROUTINE_CHROME_DIR`, `ROUTINE_NOTION_DB`, `ROUTINE_NOTION_EMAIL_LIKE`, `ROUTINE_TZ`를 유지합니다. 다중 경로는 `ROUTINE_GIT_ROOTS` JSON 배열을 쓰세요. 새 이름에는 `ROUTINE_COLLECT_UNTIL`, `ROUTINE_DRAFT_MARKERS`, `ROUTINE_CLAUDE_SESSIONS`, `ROUTINE_LLM_ENGINE`, `ROUTINE_LLM_MODEL`, `ROUTINE_DELIVERY_MODE`, `ROUTINE_PROJECT`, `ROUTINE_SLACK_*`, `ROUTINE_*_ENABLED`, `ROUTINE_WEEKDAYS`, `ROUTINE_MORNING_TIME`, `ROUTINE_LABEL_PREFIX`가 있습니다. 전체 매핑은 `share/config.sh`에 있습니다. 배열 환경 변수는 JSON입니다(`ROUTINE_GIT_AUTHORS`만 기존 공백 구분 유지). `ROUTINE_NOW`는 격리 테스트용 시각입니다.
근무일 관련 재정의는 `ROUTINE_PUBLIC_HOLIDAYS`, `ROUTINE_DAYS_OFF`, `ROUTINE_WORK_DAYS`, `ROUTINE_COLLECT_MAX_DAYS`입니다. `off`·`work`의 영구 저장은 실행용 환경 변수·`--set`이 아니라 기존 설정 파일을 기준으로 합니다.

## Git 위치·수집 소스

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

## 근무일·공휴일·휴가

근무일은 `morning.weekdays`에 속하면서 공휴일·개인 휴무일이 아닌 날입니다.
`calendar.work_days`에 지정한 날은 다른 조건에 관계없이 근무일입니다.
`routine off 10-07~10-08 연차`로 휴가를 등록하고, `routine work 10-09`로 휴일 근무를 지정합니다.
`routine off`는 오늘부터 60일의 공휴일·개인 휴무·예외 근무일을 함께 보여 줍니다.
등록·삭제의 날짜 형식, 범위와 주말 수동 실행은 [명령 문서](commands.md#휴무예외-근무일)에 있습니다.

기본 `calendar.public_holidays=kr`는 `share/holidays-kr.json`의 한국 공휴일 표를 사용합니다.
출처는 우주항공청의 2026년 월력요항(2025-06-30 발표)과 2027년 월력요항(2026-06-29 발표)이며, 출처 URL·발표일도 파일에 저장합니다.
노동절·제헌절은 2026년 4월 공휴일 지정에 따라 2026년부터 포함합니다.
표에 없는 연도는 공휴일이 없는 것으로 처리하며 status·아침 요약에 `공휴일 표 없음(YYYY) — 업데이트 필요`를 표시합니다.
해외 팀 등은 `routine config set calendar.public_holidays '"none"'`으로 끌 수 있습니다.
임시공휴일·회사 휴무일은 `calendar.days_off`에 추가하세요.

비근무일에는 morning의 collect·draft·paste만 건너뛰고 사유를 알립니다. 도구 업데이트·Jira 제안·AWS 등 `extra_steps`는 설정대로 실행합니다. Jira 제안은 `jira.enabled=false`이면 항상 건너뜁니다.
자동 붙여넣기도 비근무일이면 GUI·클립보드 접근 전에 즉시 건너뜁니다. 수동 collect·draft는 막지 않습니다.
status는 다음 실제 예약 근무일과 앞으로 건너뛸 가장 가까운 예약일을 표시합니다.
주말 등 예약 요일 밖의 예외 근무일은 launchd 예약을 새로 만들지 않으므로 그날 `routine run`을 실행하세요.
새 키는 기존 설정을 읽을 때 기본값으로 합치며, 읽기만으로 파일을 바꾸지 않습니다. init/setup 저장 시 새 키가 반영됩니다.

## 수집 기간

기본 `collect.until=today_start`는 실행일 로컬 00:00 미만까지 수집합니다.
시작은 오늘을 제외한 **직전 근무일의 00:00**입니다. 예를 들어 2026-10-06은 10-02부터, 한글날 뒤 10-12는 10-08부터 수집합니다.
주말·휴일·휴가 중 일한 내용도 이 기간에 자연히 포함됩니다. 기간이 하루보다 길어도 팀 머리글 `어제 작업한 내용`은 바꾸지 않습니다.
직전 근무일이 `collect.max_days`(기본 14)보다 멀면 오늘로부터 14일 전 00:00으로 자르고 질문 목록·status에 `수집 기간을 14일로 제한`을 표시합니다.
시작은 포함하고 상한은 제외합니다. DST가 바뀌어도 로컬 달력 날짜를 기준으로 잡습니다.

`now`는 실행 시각 미만까지이며 `--since`·`--until`이 설정보다 우선합니다.
실제 기간은 수집 JSON/Markdown과 `routine status`에 표시합니다.
이번 수집에서 제외한 오늘 활동을 “오늘 계획” 근거로 자동 재분류하지는 않습니다.

## 프로젝트·표지

`draft.projects`가 비어 있으면 현황 파악·배포·개발 등의 분류가 text·HTML·Slack의 최상위 글머리가 됩니다. 여러 프로젝트는 설정 순서대로 어제/오늘 각각의 최상위 묶음이 되며, 항목이 없는 프로젝트는 출력하지 않습니다. 프로젝트 아래의 분류·주제·작업 계층은 기존과 같습니다. `flat`은 각 프로젝트 안에서 분류만 생략합니다.

```sh
routine config set draft.projects '[{"label":"예제 A","owners":["alpha-org"],"keywords":["alpha","알파"]},{"label":"예제 B","owners":["beta-org"],"keywords":["beta","베타"]}]'
```

판정은 ① 연결된 유효 Git/PR 저장소 owner가 가리키는 단일 프로젝트 ② 항목의 **path 모든 요소·topic·연결 근거 텍스트**에 설정 keywords가 가리키는 단일 프로젝트 ③ 목록에서 검증된 LLM `project` ④ 첫 프로젝트 순서입니다. owner는 대소문자를 무시하고 정확히 비교하며, keywords는 대소문자를 무시한 부분 문자열입니다. 둘 이상의 프로젝트 키워드가 잡히면 모호한 것으로 보고 LLM 값 또는 첫 프로젝트를 사용하고 확인 질문을 남깁니다. 저장소 판정과 단일 키워드 판정이 충돌하거나 결정적 판정과 유효한 LLM 값이 다르면 owner > keywords 판정을 유지하며 `<topic>: 프로젝트 판정 충돌(<a> vs <b>)`을 남깁니다. 여러 프로젝트의 저장소가 연결된 항목도 모호함을 질문에 남깁니다. 목록 밖·잘못된 형식의 LLM `project`만 무시하고 확인 질문을 남기며, 초안 전체를 거부하지 않습니다. Claude 출력 스키마도 설정 라벨과 null로 제한합니다. 프로젝트 질문은 검토 화면의 이유와 **확인 필요** 표지에도 나타납니다. 설정 프로젝트 객체에는 `label`, `owners`, `keywords`만 허용하므로 `owner`·`keyword` 오타는 저장하지 않습니다.

검토 이유는 항목에 저장된 `reasons`를 우선합니다. 어제·오늘이나 제외된 항목의 topic이 같아도 다른 항목의 질문을 섞어 붙이지 않습니다. 이전 저장본에 프로젝트 질문만 있고 항목별 이유가 없다면 **수집·초안 안내**에서 질문을 보여 주며 특정 항목에 재배정하지 않습니다.

기존 설정 파일의 `draft.project` 문자열은 단일 `{label,owners:[],keywords:[]}` 배열로 읽고, 이후 설정 저장에는 `draft.projects`만 기록합니다. `""`는 빈 배열입니다. 기존 `--project`·`--draft-project`·`ROUTINE_PROJECT`·`--set draft.project`·`config set draft.project` 입력도 단일 프로젝트 지정으로 처리합니다. 단일 프로젝트일 때 `config get draft.project`는 기존 라벨을 반환하지만, 여러 프로젝트는 `config get draft.projects`로 조회해야 합니다. 새 초기화 배열 플래그는 `--draft-projects JSON`입니다. 검토 화면과 형식 미리보기는 초안에 저장된 프로젝트 설정을 사용하므로 이후 설정 변경으로 분류를 바꾸지 않습니다.

표지 기본값은 none입니다.
`none`은 수준/확인 필요 접미사를 숨기고, `uncertain`은 `(확인 필요)`만,
`all`은 기존의 `(검토)`·`(병합)`·`(운영 배포)`·`(확인)`까지 표시합니다.
메모로 지정한 `(보류)`는 모든 모드에서 유지합니다.

표시를 줄여도 항목을 버리거나 근거 수준을 높이지 않으며 내부 `level`과 questions.md는 동일합니다.

```bash
routine config set draft.markers '"uncertain"'
routine config set collect.until '"now"'
```

## 스타일·출력 형식

`routine style`은 스타일 파일 경로·글자 수·처음 6줄과 현재 `draft.format`을 보여줍니다.
선택 파일의 기본 경로는 `~/.config/routine-automation/style.md`이며,
`ROUTINE_CONFIG`를 지정하면 그 설정 파일과 같은 디렉터리의 `style.md`를 사용합니다.

`routine style edit`은 파일이 없으면 안내 주석을 담은 템플릿을 0600으로 만들고 `$EDITOR`로 엽니다.
EDITOR는 사용자가 신뢰하는 셸 명령으로 해석하므로 인용한 공백 경로·옵션을 쓸 수 있습니다.
비어 있거나 공백뿐이면 `open -t`를 사용합니다.

사용자 소유의 읽기 가능한 일반 파일만 읽고 0600으로 맞춥니다.
사용자 소유 파일을 가리키더라도 심볼릭 링크는 대상 파일을 읽거나 chmod하지 않습니다.
링크·디렉터리·읽기/권한 보호 실패는 초안 생성에서 경고 후 스타일 없이 계속 진행하며,
조회·편집에서는 오류를 반환합니다.

말투·길이·용어 선호를 자유롭게 적으세요.
Claude·OMP 초안 프롬프트에 데이터 블록 밖의 `## 사용자 스타일` 지시로 넣되,
HTML 주석을 제거한 뒤 Unicode 문자 기준 처음 2,000자만 적용하며 초과하면 경고합니다.
파일 원문은 자르지 않으며 주석만 있는 빈 템플릿은 스타일 지시로 넣지 않습니다.

스타일은 표현만 바꾸고 근거 수준·근거 규칙·출력 스키마를 바꿀 수 없습니다.
스타일을 따라 LLM이 근거보다 높은 level을 반환해도 기존 검증에서 강등하며,
근거보다 강한 완료 표현은 전달 초안에서 제외하고 질문에 남깁니다.

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


## 보낸 글에서 배우기

```bash
routine learn                         # 직전 근무일의 보낸 글과 그 날짜 초안 비교
routine learn --date 2026-09-25       # 특정 날짜
routine learn --paste                 # 모든 전달 모드에서 클립보드 글 사용
```

학습은 **명시적인 `routine learn` 호출에서만** 실행합니다. 수집 단계의 대화형 붙여넣기 시점에도 자동 획득하지 않는 보수적인 정책을 택했습니다. `morning`·`routine run`·`collect`·`paste --auto`에는 학습 경로를 연결하지 않습니다. 기본 날짜는 공휴일·개인 휴무·근무 예외를 반영하는 수집 시작일 계산을 공유합니다 (`collect.max_days` 제한 포함). 지정 날짜의 `$HOME/Library/Application Support/routine-automation/scrum/<date>.draft.json`이 없거나 유효하지 않으면 외부 접근 없이 비0 종료합니다. 학습에는 설정된 `draft.llm.engine`이 필요하며 `none`이면 보낸 글을 읽지 않고 안내합니다.

gui-paste 모드는 **대화형 터미널에서만**, 설정된 터미널 앱이 전면일 때 실행 중인 Orca로 AX 텍스트를 읽습니다. Slack 탐색은 채널 `slack://` 딥링크 최대 한 번과 해당 글의 댓글 버튼 클릭 최대 한 번뿐이며, 대상 스레드가 이미 열려 확정됐다면 둘 다 생략합니다. 기존 `scrum_blocks`와 동일한 글 경계·제목·시간 규칙을 날짜에 맞춰 사용하고, 채널 ID와 루트 URL의 실제 날짜까지 확인합니다. 댓글 버튼의 **연속된 자식** 안에서 본인 표시 이름을 정확히 확인한 경우만 클릭합니다. 다른 반응 그룹·계정 메뉴의 이름은 근거로 쓰지 않습니다. 글이 여러 개이거나 본인 유무를 클릭 전에 확정할 수 없으면 클릭 없이 `--date YYYY-MM-DD`로 직전 근무일 지정 또는 `--paste`를 안내합니다. 클릭 직전에도 같은 루트·인덱스·라벨·본인 여부를 다시 확인합니다. 댓글 본문은 작성자의 reply 링크 뒤에서 같은 메시지 들여쓰기의 `container, Text:`만 읽고, 입력창·체크박스·전송·구분선·인용/첨부 컨테이너 등 **역할·들여쓰기 구조**에서 끊습니다. 일반 본문의 '첨부파일', '인용 기능', '새 메시지' 같은 단어는 경계로 쓰지 않습니다. 작성자 버튼의 제외 라벨은 정확히 일치할 때만 적용하며, 작성자가 생략된 연속 링크는 **같은 부모 메시지 컨테이너 안이고 사이에 더 얕은 줄이나 미인식 헤더가 없을 때만** 작성자를 이어받습니다. 다른 컨테이너·깊이가 다른 작성자·link/정적 텍스트 등 미인식 작성자는 본인으로 추정하지 않고 제외합니다. 반응 버튼은 본문을 자르지 않습니다. 타인 댓글·편집 메타데이터·작성 중인 입력창은 본문에서 제외합니다. 표시 이름만으로 동명이인을 구별할 수 없으므로 **GUI 획득도 redact 미리보기에서 본인 글인지 확인하고 LLM 전송에 동의해야** 비교·저장합니다.

학습은 입력창 포커스·타이핑·붙여넣기·체크박스·Return·전송을 **전혀 조작하지 않습니다**. 열린 스레드에 비어 있지 않은 입력이 있거나 상태를 확인할 수 없으면 딥링크·클릭 없이 중단합니다. 오늘 `.pasted` 또는 `.paste-attention` 표지가 있으면 **오늘 글의 댓글 버튼 자식에 본인 이름이 보이거나, 열린 오늘 스레드 입력창이 비어 있음을 확인한 경우만** 진행합니다. 이 확인도 설정된 채널 ID와 루트 URL 타임스탬프의 현지 오늘 날짜가 일치해야 합니다. 표지는 전송 후에도 남으므로 학습에서 지우지 않습니다. 확인할 수 없으면 '오늘 붙여넣은 초안이 아직 전송되지 않았을 수 있어 화면 학습을 하지 않습니다 — 전송 후 다시 실행하거나 --paste 사용'을 안내합니다. 살아 있는 morning 잠금과 조율하고 GUI 단계 동안 공유 `.scrum-paste.lock`을 잡아 붙여넣기와 겹치지 않게 합니다. 남은 잠금은 임의 회수하지 않습니다. 주말에도 `--paste`를 사용할 수 있고, 수동 해제하려면 PID 프로세스와 모든 routine 작업이 종료됐는지 먼저 확인한 뒤 해당 잠금의 `pid` 파일을 삭제하고 **빈 잠금 디렉터리만** 제거하세요(스크럼 출력 경로의 `.scrum-paste.lock`, `~/Library/Logs/routine-automation/.morning.lock`). 스크롤·검색·Orca 자동 실행도 하지 않으므로 글이나 본인 댓글이 보이지 않거나 AX 형식이 다르면 안전하게 중단합니다. 각 화면 조작 전 잠금·현재 콘솔 사용자·HID 입력 감지 가드를 적용합니다. 정상 종료와 오류의 전면 앱 복원은 공용 `restore_previous_app`을 사용하며, 활성화 요청이 무시되면 `lsappinfo`로 **실행 중인 원래 앱만** 확인하고 입력 가드를 재검사한 뒤 `open -b`로 복원합니다. 사용자 입력/다른 앱 전환이 감지되면 포커스를 빼앗지 않고 중단합니다(입력/잠금 중단 exit 4). 화면 획득을 시도한 모든 종료 경로에서 전면 앱을 다시 확인하여 Slack이 남았거나 상태 확인이 실패하면 OS 알림과 stderr에 **'Slack에 키를 입력하지 마세요'**를 표시합니다. 다른 앱으로 바뀌면 이를 안내하고 포커스를 바꾸지 않습니다.

`--paste`는 대화형 터미널에서 **읽기 전 확인 → pbpaste → redact한 미리보기 → 본인 글 확인·LLM 전송 동의** 순서입니다. 첫 확인을 거절하면 클립보드에 접근하지 않고, 두 번째를 거절하면 LLM·학습 저장·스타일 반영을 하지 않습니다. 일반 클립보드에 쓰거나 복원하지 않습니다. 비TTY `--paste`는 확인할 수 없어 읽기 전에 비0 종료합니다. 비TTY의 일반 `learn`은 해당 날짜에 이미 저장된 유효한 제안만 출력하며 GUI·클립보드 획득·LLM 호출·자동 반영은 하지 않습니다. 저장 결과가 없으면 대화형 학습을 안내하고 비0 종료합니다. 미리보기는 위험한 제어/형식·양방향/줄 구분·한글 채움 문자를 지우지 않고 `<U+202E>` 같은 코드포인트 표기로 보여 줍니다. 줄바꿈·탭, NFD 한글·결합 악센트, 이모지 VS16/ZWJ는 보존합니다. 이 표시는 미리보기용이며 LLM에는 redact된 원문을 그대로 보냅니다. 보낸 글은 최대 20,000자만 허용합니다.

보낸 글·초안 항목은 먼저 redact하고 `share/learn-prompt.md`의 **신뢰할 수 없는 JSON 데이터 블록**에 넣습니다. 설정된 Claude 또는 OMP를 기존 초안과 같은 도구·세션·규칙 격리 옵션과 빈 작업 디렉터리에서 호출합니다. 이 비교에 보내는 업무 문구는 해당 LLM 제공자에게 전달되므로 민감한 내용을 확인하세요. 응답은 `{"suggestions":[{"kind":"style|exclude|rename|category","text":"…","example_before":"…","example_after":"…"}]}` 객체 하나만 허용합니다. 실제 kind는 네 값 중 하나이며 추가 필드·잘못된 타입·20개 초과·text 300자 초과/빈 값·예시 각각 500자 초과를 거부합니다. 지침과 비어 있지 않은 예시는 보이는 문자가 있어야 하며 Unicode 제어 문자·ZWJ 이외의 형식 문자·양방향/줄 구분 문자·한글 채움 문자(U+115F/U+1160/U+3164/U+FFA0)와 `<!--`/`-->`를 거부합니다. 일반 결합 문자·NFD 한글·이모지 VS16/ZWJ는 허용합니다. 예시의 줄바꿈·탭만 허용하며 목록에는 `⏎`·`⇥`로 표시해 가짜 선택 항목을 만들지 못하게 합니다. 위반 응답은 저장·반영하지 않으며 제안에도 redact를 적용합니다.

결과는 `$HOME/Library/Application Support/routine-automation/scrum/learn/<date>.json`에 `{date,sent,suggestions}`로 **원자적으로 0600 저장**합니다(디렉터리 0700). 같은 날짜 재실행은 이 결과를 새 제안으로 교체합니다. redact는 모든 개인정보를 지우는 보장이 아니므로 업무 본문·예시·용어가 이 파일에 남습니다. 자동 삭제하지 않으며 공유 전에 확인하거나 불필요하면 직접 삭제하세요. 학습 저장 디렉터리/결과의 심볼릭 링크와 사용자 소유가 아닌 경로는 거부합니다.

대화형에서는 `ui_choose_many`의 **기본 미선택 목록**에서 고른 지침만 style.md의 `## 학습된 선호 (YYYY-MM-DD)` 아래에 기록합니다. 비TTY에서는 저장된 제안만 출력하고 style.md에는 반영하지 않습니다. **모든 학습 날짜 절**을 통틀어 이미 있는 동일 지침은 중복 추가하지 않으며 선택 순서·다른 절·기존 내용을 보존합니다. style.md 경로는 설정 파일과 같은 디렉터리이고 사용자 소유 일반 파일·symlink 거부·0600 규칙을 따릅니다. 길이가 2,000자를 넘을 예정이면 반영 전에 경고하며 초안은 기존처럼 처음 2,000자만 적용합니다. `exclude`·`rename`·`category`도 **표현용 자연어 선호**로만 기록하고 설정·근거 규칙·검증기는 바꾸지 않습니다. 자동 반영은 없습니다.
