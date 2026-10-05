#!/usr/bin/env bash
# shellcheck disable=SC2154 # repo is supplied by the calling test suite.
# Shared fake identities; tests never inherit the operator's real configuration.
# shellcheck source=network.sh
source "$repo/tests/network.sh"
export ROUTINE_CONFIG="$HOME/.config/routine-automation/config.json"
export ROUTINE_GIT_AUTHORS='fixture@example.com 42+fixture@users.noreply.github.com'
export ROUTINE_NOTION_EMAIL_LIKE='fixture@%'
export ROUTINE_SLACK_DISPLAY_NAME='테스트_사용자' ROUTINE_SLACK_TEAM_ID=TEXAMPLE ROUTINE_SLACK_DOMAIN=example
export ROUTINE_SLACK_CHANNEL_ID=CEXAMPLE ROUTINE_SLACK_CHANNEL_NAME=daily-scrum ROUTINE_SLACK_POST_TITLE='스크럼-예제팀: 예제팀'
export ROUTINE_PROJECT='예제 프로젝트' ROUTINE_LLM_ENGINE=omp ROUTINE_DELIVERY_MODE=gui-paste
export ROUTINE_CLAUDE_SESSIONS_ENABLED=false ROUTINE_JIRA_ENABLED=true ROUTINE_NOTION_ENABLED=true
# These scenarios deliberately include the current morning; cutoff coverage uses today_start explicitly.
export ROUTINE_COLLECT_UNTIL=now
export ROUTINE_DRAFT_MARKERS=all
export ROUTINE_OMP_UPDATE=true ROUTINE_CLAUDE_UPDATE=true ROUTINE_NPM_UPDATE=true ROUTINE_AWS_SESSION=true
# Never fall back to the real Orca app bundle from tests.
export ROUTINE_ORCA_APP_CLI=/nonexistent/orca
share_dir="$repo/share"
# shellcheck source=../share/config.sh
source "$share_dir/config.sh"
routine_load_config
