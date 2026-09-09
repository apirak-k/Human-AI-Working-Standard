#!/usr/bin/env bash
# Device-local draft settings and explicit Save & Apply orchestration.

install_is_complete() { [ -s "$(_haws_state_dir)/install.complete" ]; }

_settings_detected_envs() {
  local env
  for env in claude gemini cursor copilot codex; do
    case "${env}" in
      claude) [ -d "${HOME}/.claude" ] || continue ;;
      gemini) [ -d "${HOME}/.gemini" ] || continue ;;
      cursor) { [ -d "${HOME}/.cursor" ] || [ -f "${HOME}/.cursorrules" ]; } || continue ;;
      copilot) { [ -d "${HOME}/.copilot" ] || [ -d "${HOME}/.config/github-copilot" ]; } || continue ;;
      codex) { [ -d "${HOME}/.codex" ] || [ -d "${HOME}/.agents" ]; } || continue ;;
    esac
    printf '%s\n' "${env}"
  done
}

_settings_active_skills() { catalog_skills 2>/dev/null | awk -F '	' '$5 == 1 {print $1}'; }
_settings_sources() { catalog_sources 2>/dev/null | cut -f1; }

settings_draft_defaults() {
  HAWS_SELECTED_ENVS="$(_settings_detected_envs)"
  HAWS_SELECTED_SOURCES="$(_settings_sources)"
  HAWS_SELECTED_SKILLS="$(_settings_active_skills)"
  HAWS_DRAFT_SECOND_BRAIN="off"
  HAWS_DRAFT_AUTO_UPDATE="on"
  export HAWS_SELECTED_ENVS HAWS_SELECTED_SOURCES HAWS_SELECTED_SKILLS HAWS_DRAFT_SECOND_BRAIN HAWS_DRAFT_AUTO_UPDATE
}

_settings_render() {
  echo ""
  echo "HAWS Settings${1:+ — $1}"
  echo "  Source Repositories / KIT: $(printf '%s\n' "${HAWS_SELECTED_SOURCES:-}" | sed '/^$/d' | wc -l | tr -d ' ') selected"
  echo "  Skills: $(printf '%s\n' "${HAWS_SELECTED_SKILLS:-}" | sed '/^$/d' | wc -l | tr -d ' ') active"
  echo "  AI Environments: ${HAWS_SELECTED_ENVS:-none}"
  echo "  Second Brain: ${HAWS_DRAFT_SECOND_BRAIN}"
  echo "  Auto Update when Syncing: ${HAWS_DRAFT_AUTO_UPDATE}"
  install_is_complete && echo "  Uninstall"
  echo "  [default] Default Setup  [save] Save & Apply  [cancel] Cancel"
}

_settings_set_list() {
  local var="$1" value="$2" item
  value="${value//,/ }"
  local result=""
  for item in ${value}; do result="${result}${item}\n"; done
  printf -v "${var}" '%b' "${result}"
  export "${var}"
}

_settings_encode_list() {
  # Plan records stay single-line while preserving IDs that may contain spaces.
  printf '%s\n' "${1:-}" | sed '/^[[:space:]]*$/d' | paste -sd, -
}

_settings_list_contains() {
  local list="${1:-}" item="${2:-}"
  list="${list//$'\n'/,}"
  case ",${list}," in
    *,"${item}",*) return 0 ;;
    *) return 1 ;;
  esac
}

settings_edit() {
  local mode="${1:-settings}" key value
  settings_load || return $?
  disabled_envs_load || return $?
  disabled_skills_load || return $?
  settings_draft_defaults
  [ "${mode}" = first-install ] && _settings_render "First Install"
  while true; do
    [ "${mode}" = first-install ] || _settings_render
    ui_next_key >/dev/null 2>&1 || key="cancel"
    key="${UI_LAST_KEY:-${key:-cancel}}"
    case "${key}" in
      default|d|D) settings_draft_defaults; echo "Default Setup restored in draft." ;;
      save|s|S|apply) settings_plan_apply || return $?; return 0 ;;
      cancel|c|C|q|quit|exit|no) echo "Cancelled. No changes saved."; return 1 ;;
      second_brain=*) HAWS_DRAFT_SECOND_BRAIN="${key#*=}" ;;
      auto_update=*) HAWS_DRAFT_AUTO_UPDATE="${key#*=}" ;;
      envs=*) _settings_set_list HAWS_SELECTED_ENVS "${key#*=}" ;;
      skills=*) _settings_set_list HAWS_SELECTED_SKILLS "${key#*=}" ;;
      sources=*) _settings_set_list HAWS_SELECTED_SOURCES "${key#*=}" ;;
      *)
        if [ -z "${HAWS_TEST_KEYS:-}" ]; then echo "Type save, default, or cancel."; else echo "Unknown settings input: ${key}"; fi
        [ -n "${HAWS_TEST_KEYS:-}" ] && return 1
        ;;
    esac
  done
}

settings_plan_apply() {
  local state plan integration old_envs env
  state="$(_haws_state_dir)"; mkdir -p "${state}" || return 1
  plan="${state}/settings.plan"; integration="${state}/integrations.plan"
  HAWS_INTEGRATION_PLAN="${integration}" integration_plan "" "${HAWS_SELECTED_SOURCES:-}" >/dev/null || return 1
  {
    printf 'setting\tsecond_brain\t%s\n' "${HAWS_DRAFT_SECOND_BRAIN:-off}"
    printf 'setting\tauto_update\t%s\n' "${HAWS_DRAFT_AUTO_UPDATE:-on}"
    printf 'envs\t%s\n' "$(_settings_encode_list "${HAWS_SELECTED_ENVS:-}")"
    printf 'skills\t%s\n' "$(_settings_encode_list "${HAWS_SELECTED_SKILLS:-}")"
    cat "${integration}"
  } > "${plan}" || return 1
  echo "Settings review"
  cat "${plan}"
  settings_apply "${plan}"
}

settings_apply() {
  local plan="${1:-}" action key value list env disabled skill
  [ -f "${plan}" ] || return 1
  ui_review "${plan}" || { echo "Cancelled. No changes saved."; return 1; }
  local second_brain=off auto_update=on selected_envs="" selected_skills=""
  while IFS="	" read -r action key value _ || [ -n "${action}" ]; do
    case "${action}" in
      setting) [ "${key}" = second_brain ] && second_brain="${value}"; [ "${key}" = auto_update ] && auto_update="${value}" ;;
      envs) selected_envs="${key}" ;;
      skills) selected_skills="${key}" ;;
    esac
  done < "${plan}"
  settings_save "${second_brain}" "${auto_update}" || return 1
  local disabled_envs=""
  for env in claude gemini cursor copilot codex; do
    _settings_list_contains "${selected_envs}" "${env}" || disabled_envs="${disabled_envs}${env}\n"
  done
  if [ -n "${disabled_envs}" ]; then
    disabled_envs_save $(printf '%b' "${disabled_envs}" | sed '/^$/d') || return 1
  else
    disabled_envs_save || return 1
  fi
  if [ -n "${HAWS_SELECTED_SKILLS:-}" ]; then
    local desired_skill_ids="" skill_row skill_id display source_id entrypoint active
    while IFS= read -r skill_row || [ -n "${skill_row}" ]; do
      [ -n "${skill_row}" ] || continue
      IFS="	" read -r skill_id display source_id entrypoint active <<EOF
${skill_row}
EOF
      _settings_list_contains "${selected_skills}" "${skill_id}" || desired_skill_ids="${desired_skill_ids}${skill_id}\n"
    done <<EOF
$(catalog_skills 2>/dev/null || true)
EOF
    disabled_skills_save $(printf '%b' "${desired_skill_ids}") || return 1
  else
    disabled_skills_save || return 1
  fi
  integration_apply "${plan}" || return $?
  printf 'schema=1\tcompleted_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$(_haws_state_dir)/install.complete" || return 1
  echo "Doctor: Ready (read-only)"
  echo "Home"
  return 0
}

home_run() {
  settings_load || return $?
  echo "HAWS Home"
  echo "Status | Sync | Settings | Doctor | Status details | Exit"
  if [ -n "${HAWS_TEST_KEYS:-}" ]; then
    ui_next_key >/dev/null 2>&1 || true
    case "${UI_LAST_KEY:-}" in
      sync) run_sync ;;
      settings) settings_run ;;
      doctor) run_doctor ;;
      details|status) run_status ;;
      *) return 0 ;;
    esac
  fi
  return 0
}

settings_run() { settings_edit "${1:-settings}"; }
