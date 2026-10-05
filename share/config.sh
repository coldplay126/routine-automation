#!/usr/bin/env bash
# shellcheck disable=SC2154 # share_dir is supplied by each entrypoint.
# Shared by every entrypoint: existing environment names retain precedence.
routine_config_path() { printf '%s\n' "${ROUTINE_CONFIG:-$HOME/.config/routine-automation/config.json}"; }
routine_load_config() {
  local path raw='{}' env key value mode=${1:-runtime}
  path=$(routine_config_path)
  if [[ -e $path ]]; then
    [[ -f $path && ! -L $path ]] || { echo '설정은 일반 파일이어야 합니다.' >&2; return 2; }
    raw=$(command jq -ce 'select(type=="object")' "$path") || { echo '설정 JSON 오류' >&2; return 2; }
  fi
  ROUTINE_SETTINGS=$(command jq -L "$share_dir" -nc --arg home "$HOME" --arg user "${USER:-user}" --argjson config "$raw" 'include "config"; defaults($home;$user) * ($config|migrate_config)') || return 2
  # shellcheck disable=SC2034 # Used by init/config-set callers, separate from runtime overrides.
  ROUTINE_FILE_SETTINGS=$ROUTINE_SETTINGS
  if [[ $mode == file ]]; then return 0; fi
  if [[ $mode == persisted ]]; then routine_validate_loaded; return; fi
  while IFS=' ' read -r env key; do
    if [[ ${!env+x} ]]; then
      value=${!env}
      case $key in
        identity.git_authors) value=$(command jq -nc --arg v "$value" '$v|split(" ")|map(select(length>0))') ;;
        sources.git.roots)
          if [[ $env == ROUTINE_REPO_ROOT ]]; then value=$(command jq -nc --arg v "$value" '[$v]')
          else command jq empty <<< "$value" >/dev/null || { echo "환경 변수 JSON 오류: $env" >&2; return 2; }; fi ;;
        *.enabled|morning.extra_steps.*|delivery.idle_seconds|delivery.daily_attempts|morning.weekdays|draft.categories) command jq empty <<< "$value" >/dev/null || { echo "환경 변수 JSON 오류: $env" >&2; return 2; } ;;
        *) value=$(command jq -nc --arg v "$value" '$v') ;;
      esac
      ROUTINE_SETTINGS=$(command jq -c --arg key "$key" --argjson value "$value" 'setpath($key|split(".");$value)' <<< "$ROUTINE_SETTINGS") || return 2
    fi
  done <<'MAP'
ROUTINE_TZ timezone
ROUTINE_SLACK_DISPLAY_NAME identity.slack_display_name
ROUTINE_GIT_AUTHORS identity.git_authors
ROUTINE_NOTION_EMAIL_LIKE identity.notion_email_like
ROUTINE_SLACK_TEAM_ID slack.team_id
ROUTINE_SLACK_DOMAIN slack.workspace_domain
ROUTINE_SLACK_CHANNEL_ID slack.channel_id
ROUTINE_SLACK_CHANNEL_NAME slack.channel_name
ROUTINE_SLACK_POST_TITLE slack.post_title
ROUTINE_SLACK_POST_TIME_PREFIX slack.post_time_prefix
ROUTINE_PROJECT draft.project
ROUTINE_DRAFT_MARKERS draft.markers
ROUTINE_HEADER_YESTERDAY draft.headers.yesterday
ROUTINE_HEADER_TODAY draft.headers.today
ROUTINE_CATEGORIES draft.categories
ROUTINE_LLM_ENGINE draft.llm.engine
ROUTINE_LLM_MODEL draft.llm.model
ROUTINE_REPO_ROOT sources.git.roots
ROUTINE_GIT_ROOTS sources.git.roots
ROUTINE_COLLECT_UNTIL collect.until
ROUTINE_GIT_ENABLED sources.git.enabled
ROUTINE_PRS_ENABLED sources.prs.enabled
ROUTINE_OMP_SESSIONS sources.omp_sessions.dir
ROUTINE_OMP_SESSIONS_ENABLED sources.omp_sessions.enabled
ROUTINE_CLAUDE_SESSIONS sources.claude_sessions.dir
ROUTINE_CLAUDE_SESSIONS_ENABLED sources.claude_sessions.enabled
ROUTINE_CHROME_DIR sources.jira.chrome_dir
ROUTINE_JIRA_ENABLED sources.jira.enabled
ROUTINE_NOTION_DB sources.notion.db
ROUTINE_NOTION_ENABLED sources.notion.enabled
ROUTINE_SLACK_ENABLED sources.slack.enabled
ROUTINE_DELIVERY_MODE delivery.mode
ROUTINE_WINDOW_START delivery.window.start
ROUTINE_WINDOW_END delivery.window.end
ROUTINE_NO_POST_AFTER delivery.no_post_after
ROUTINE_IDLE_SECONDS delivery.idle_seconds
ROUTINE_DAILY_ATTEMPTS delivery.daily_attempts
ROUTINE_MORNING_TIME morning.time
ROUTINE_WEEKDAYS morning.weekdays
ROUTINE_OMP_UPDATE morning.extra_steps.omp_update
ROUTINE_CLAUDE_UPDATE morning.extra_steps.claude_update
ROUTINE_NPM_UPDATE morning.extra_steps.npm_update
ROUTINE_AWS_SESSION morning.extra_steps.aws_session
ROUTINE_LABEL_PREFIX launchd.label_prefix
MAP
  if [[ -n ${ROUTINE_CLI_OVERRIDES:-} ]]; then
    ROUTINE_SETTINGS=$(command jq -c --argjson overrides "$ROUTINE_CLI_OVERRIDES" '. as $known | reduce $overrides[] as $o (.;if ($known|[paths|join(".")]|index($o.key))==null then error("알 수 없는 CLI 설정: "+$o.key) else setpath($o.key|split(".");$o.value) end)' <<< "$ROUTINE_SETTINGS") || return 2
  fi
  routine_validate_loaded
}
routine_validate_loaded() {
  command jq -L "$share_dir" -e 'include "config"; config_ok' <<< "$ROUTINE_SETTINGS" >/dev/null || { echo '설정 스키마 오류' >&2; return 2; }
  export ROUTINE_SETTINGS
  TZ=$(routine_get timezone)
  export TZ="${TZ:-:/etc/localtime}"
}
routine_jq_supported() {
  local version
  type -P jq >/dev/null || return 1
  version=$(command jq --version 2>/dev/null) || return 1
  [[ $version =~ ^jq-([0-9]+)\.([0-9]+) ]] || return 1
  ((BASH_REMATCH[1]>1 || (BASH_REMATCH[1]==1 && BASH_REMATCH[2]>=7)))
}
routine_get() { command jq -r --arg key "$1" 'getpath($key|split(".")) | select(.!=null)' <<< "$ROUTINE_SETTINGS"; }
routine_require_config() {
  local missing guide=${1:-routine init}
  missing=$(command jq -L "$share_dir" -r 'include "config"; required_errors|join(", ")' <<< "$ROUTINE_SETTINGS") || return 2
  [[ -z $missing ]] || { printf '필수 설정 누락/오류: %s — %s 실행\n' "$missing" "$guide" >&2; return 2; }
}
routine_save_config() {
  local settings=$1 path dir temp
  command jq -L "$share_dir" -e 'include "config"; config_ok' <<< "$settings" >/dev/null || { echo '설정 스키마 오류' >&2; return 2; }
  path=$(routine_config_path); dir=${path%/*}
  mkdir -p "$dir"; chmod 700 "$dir"
  [[ ! -L $path ]] || { echo '설정 심볼릭 링크 덮어쓰기 거부' >&2; return 2; }
  temp=$(mktemp "$dir/.config.XXXXXXXX")
  if command jq . <<< "$settings" > "$temp"; then chmod 600 "$temp"; mv -f "$temp" "$path"; else rm -f "$temp"; return 2; fi
}
# jq modules receive data explicitly; no user text is compiled into jq programs.
jq() { local settings=${ROUTINE_SETTINGS:-'{}'}; command jq --argjson routine "$settings" "$@"; }
routine_sources() {
  command jq -r '[.sources|to_entries[]|select(.value.enabled and .key!="slack")|.key|if .=="omp_sessions" then "sessions" else . end]|join(",")' <<< "$ROUTINE_SETTINGS"
}
routine_draft_omission_notice() {
  local path=$1 count
  [[ -f $path ]] || return 0
  count=$(command jq -L "$share_dir" -r 'include "scrum"; delivery_counts.omitted' "$path" 2>/dev/null) || return 0
  if ((count>0)); then printf ' — 생략 %s개: routine review에서 확인' "$count"; fi
}
routine_day() {
  if [[ -n ${ROUTINE_NOW:-} ]]; then
    local stamp=${ROUTINE_NOW/Z/+0000}
    stamp=$(printf '%s' "$stamp" | sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/')
    date -j -f '%Y-%m-%dT%H:%M:%S%z' "$stamp" '+%Y-%m-%d'
  else date '+%Y-%m-%d'; fi
}
routine_collect_since() {
  local day=$1 days=1
  [[ $(date -j -f '%Y-%m-%d %H:%M:%S' "$day 12:00:00" '+%u') != 1 ]] || days=3
  date -j "-v-${days}d" -f '%Y-%m-%d %H:%M:%S' "$day 12:00:00" '+%Y-%m-%d'
}
