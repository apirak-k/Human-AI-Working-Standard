#!/usr/bin/env bash
# Device-local draft settings and explicit Save & Apply orchestration.

install_is_complete() {
  [ -s "$(_haws_state_dir)/install.complete" ] || [ -s "${HOME}/.haws_manifest" ]
}

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

_settings_choose_list() {
  local target="$1" title="$2" current="$3" type="$4" id label detail active
  local records=()
  case "${type}" in
    envs)
      for id in claude gemini cursor copilot codex; do
        _settings_list_contains "${current}" "${id}" && active=1 || active=0
        case "${id}" in
          claude) label="Claude Code"; detail="${HOME}/.claude" ;;
          gemini) label="Gemini"; detail="${HOME}/.gemini" ;;
          cursor) label="Cursor"; detail="${HOME}/.cursor" ;;
          copilot) label="Copilot"; detail="${HOME}/.copilot" ;;
          codex) label="Codex"; detail="${HOME}/.codex" ;;
        esac
        [ -d "${detail}" ] && detail="${detail} (detected)" || detail="${detail} (not detected)"
        records+=("${id}"$'\t'"${label}"$'\t'"${detail}"$'\t'"${active}")
      done
      ;;
    sources)
      while IFS=$'\t' read -r id label detail _; do
        [ -n "${id}" ] || continue
        _settings_list_contains "${current}" "${id}" && active=1 || active=0
        records+=("${id}"$'\t'"${id}"$'\t'"${detail}"$'\t'"${active}")
      done <<EOF
$(catalog_sources 2>/dev/null || true)
EOF
      ;;
    skills|skills-single|skills-pack)
      while IFS=$'\t' read -r id label _ detail active; do
        [ -n "${id}" ] || continue
        if [ "${type}" != skills ]; then
          local source_count
          source_count="$(catalog_skills 2>/dev/null | awk -F '\t' -v wanted="${_}" '$3 == wanted {n++} END {print n+0}')"
          [ "${type}" = skills-single ] && [ "${source_count}" -eq 1 ] || { [ "${type}" = skills-pack ] && [ "${source_count}" -gt 1 ] || continue; }
        fi
        _settings_list_contains "${current}" "${id}" && active=1 || active=0
        records+=("${id}"$'\t'"${label}"$'\t'"${detail}"$'\t'"${active}")
      done <<EOF
$(catalog_skills 2>/dev/null || true)
EOF
      ;;
  esac
  [ "${#records[@]}" -gt 0 ] || { echo "No selectable ${type}."; return 1; }
  ui_checklist "${title}" "${records[@]}" || return 1
  printf -v "${target}" '%s' "${UI_CHECKLIST_RESULT}"
  export "${target}"
}

repositories_menu() {
  local key url
  while true; do
    echo ""
    echo "Repositories"
    echo "  1) Select Repositories / KIT"
    echo "  2) Add Repository"
    echo "  3) Remove Repository"
    echo "  0) Back"
    ui_next_key >/dev/null 2>&1 || return 0
    key="${UI_LAST_KEY:-}"
    case "${key}" in
      1) _settings_choose_list HAWS_SELECTED_SOURCES "Repositories" "${HAWS_SELECTED_SOURCES:-}" sources || true ;;
      2)
        echo "Add Repository"
        echo "Enter repository URL, or Q to cancel."
        ui_next_key >/dev/null 2>&1 || continue
        url="${UI_LAST_KEY:-}"
        case "${url}" in q|Q|cancel|quit|"") continue ;; esac
        HAWS_DRAFT_ADDED_REPOSITORIES="${HAWS_DRAFT_ADDED_REPOSITORIES:-}${url}"$'\n'
        export HAWS_DRAFT_ADDED_REPOSITORIES
        echo "Repository added to draft: ${url}"
        ;;
      3) _settings_choose_list HAWS_SELECTED_SOURCES "Remove Repository" "${HAWS_SELECTED_SOURCES:-}" sources || true ;;
      0|back|b|q|Q|cancel) return 0 ;;
      *) echo "Invalid selection. Enter 0-3 or Q." ;;
    esac
  done
}

skills_menu() {
  local key
  while true; do
    echo ""
    echo "Skills"
    echo "  1) Single Skills"
    echo "  2) Multi-Skill Packs"
    echo "  0) Back"
    ui_next_key >/dev/null 2>&1 || return 0
    key="${UI_LAST_KEY:-}"
    case "${key}" in
      1) _settings_choose_list HAWS_SELECTED_SKILLS "Single Skills" "${HAWS_SELECTED_SKILLS:-}" skills-single || true ;;
      2) _settings_choose_list HAWS_SELECTED_SKILLS "Multi-Skill Packs" "${HAWS_SELECTED_SKILLS:-}" skills-pack || true ;;
      0|back|b|q|Q|cancel) return 0 ;;
      *) echo "Invalid selection. Enter 0-2 or Q." ;;
    esac
  done
}

settings_boolean_menu() {
  local target="$1" title="$2" current="$3" key value
  while true; do
    echo ""
    echo "${title}"
    echo "  1) On"
    echo "  2) Off"
    echo "  0) Back"
    ui_next_key >/dev/null 2>&1 || return 0
    key="${UI_LAST_KEY:-}"
    case "${key}" in
      1) value=on ;;
      2) value=off ;;
      0|back|b|q|Q|cancel) return 0 ;;
      *) echo "Invalid selection. Enter 0-2 or Q."; continue ;;
    esac
    printf -v "${target}" '%s' "${value}"
    export "${target}"
    return 0
  done
}

uninstall_settings_menu() {
  local records result groups="" id
  records=(
    $'pointers\tAI pointers\tEnvironment adapters\t1'
    $'skills\tSkill links\tLinked active skills\t1'
    $'agents\tAgent profiles\tInstalled role profiles\t1'
    $'hooks\tGit hooks\tHAWS hooks\t1'
    $'metadata\tHAWS metadata\tLocal ownership records\t1'
  )
  ui_checklist "Uninstall groups" "${records[@]}" || return 1
  while IFS= read -r id || [ -n "${id}" ]; do
    [ -n "${id}" ] || continue
    [ -n "${groups}" ] && groups="${groups},"
    groups="${groups}${id}"
  done <<EOF
${UI_CHECKLIST_RESULT}
EOF
  [ -n "${groups}" ] || { echo "No uninstall groups selected."; return 1; }
  uninstall_run "${groups}"
}

_settings_render() {
  echo ""
  echo "HAWS Settings${1:+ — $1}"
  [ -s "${HOME}/.haws_manifest" ] && [ ! -s "$(_haws_state_dir)/install.complete" ] && echo "  Existing HAWS installation detected; no files are changed until Save & Apply."
  echo "  0) Save & Apply / Exit"
  echo "  1) Reset Standard Setup"
  echo "  2) Repositories: $(printf '%s\n' "${HAWS_SELECTED_SOURCES:-}" | sed '/^$/d' | wc -l | tr -d ' ') selected"
  echo "  3) Skills: $(printf '%s\n' "${HAWS_SELECTED_SKILLS:-}" | sed '/^$/d' | wc -l | tr -d ' ') active"
  echo "  4) AI Environments: ${HAWS_SELECTED_ENVS:-none}"
  echo "  5) Second Brain: ${HAWS_DRAFT_SECOND_BRAIN}"
  echo "  6) Auto Update when Syncing: ${HAWS_DRAFT_AUTO_UPDATE}"
  install_is_complete && echo "  7) Uninstall HAWS"
  echo "  Q) Cancel"
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
  HAWS_DRAFT_ENVS_TOUCHED=0
  settings_draft_defaults
  [ "${mode}" = first-install ] && _settings_render "First Install"
  while true; do
    [ "${mode}" = first-install ] || _settings_render
    ui_next_key >/dev/null 2>&1 || key="cancel"
    key="${UI_LAST_KEY:-${key:-cancel}}"
    case "${key}" in
      1|default|d|D) settings_draft_defaults; HAWS_DRAFT_ENVS_TOUCHED=1; echo "Default Setup restored in draft." ;;
      0|save|s|S|apply) settings_plan_apply || return $?; return 0 ;;
      cancel|c|C|q|quit|exit|no) echo "Cancelled. No changes saved."; return 1 ;;
      2|sources|source) repositories_menu ;;
      3|skills|skill) skills_menu ;;
      4|envs|environment|environments) _settings_choose_list HAWS_SELECTED_ENVS "AI Environments" "${HAWS_SELECTED_ENVS:-}" envs; HAWS_DRAFT_ENVS_TOUCHED=1 ;;
      5|second-brain|second_brain) settings_boolean_menu HAWS_DRAFT_SECOND_BRAIN "Second Brain" "${HAWS_DRAFT_SECOND_BRAIN}" ;;
      6|auto-update|auto_update) settings_boolean_menu HAWS_DRAFT_AUTO_UPDATE "Auto Update when Syncing" "${HAWS_DRAFT_AUTO_UPDATE}" ;;
      7) uninstall_settings_menu; return $? ;;
      second_brain=*) HAWS_DRAFT_SECOND_BRAIN="${key#*=}" ;;
      auto_update=*) HAWS_DRAFT_AUTO_UPDATE="${key#*=}" ;;
      envs=*) _settings_set_list HAWS_SELECTED_ENVS "${key#*=}"; HAWS_DRAFT_ENVS_TOUCHED=1 ;;
      skills=*) _settings_set_list HAWS_SELECTED_SKILLS "${key#*=}" ;;
      sources=*) _settings_set_list HAWS_SELECTED_SOURCES "${key#*=}" ;;
      *)
        if [ -z "${HAWS_TEST_KEYS:-}" ]; then echo "Invalid selection. Enter 0-7 or Q."; else echo "Unknown settings input: ${key}"; fi
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
  # Adoption is a write, so it happens only after the reviewed confirmation.
  # This imports legacy manifest ownership before any reconciliation changes.
  state_init || return $?
  local second_brain=off auto_update=on selected_envs="" selected_skills=""
  while IFS="	" read -r action key value _ || [ -n "${action}" ]; do
    case "${action}" in
      setting) [ "${key}" = second_brain ] && second_brain="${value}"; [ "${key}" = auto_update ] && auto_update="${value}" ;;
      envs) selected_envs="${key}" ;;
      skills) selected_skills="${key}" ;;
    esac
  done < "${plan}"
  settings_save "${second_brain}" "${auto_update}" || return 1
  if [ "${HAWS_DRAFT_ENVS_TOUCHED:-0}" = 1 ]; then
    local disabled_envs=""
    for env in claude gemini cursor copilot codex; do
      _settings_list_contains "${selected_envs}" "${env}" || disabled_envs="${disabled_envs}${env}\n"
    done
    if [ -n "${disabled_envs}" ]; then
      disabled_envs_save $(printf '%b' "${disabled_envs}" | sed '/^$/d') || return 1
    else
      disabled_envs_save || return 1
    fi
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
  local key
  settings_load || return $?
  while true; do
    status_run
    echo ""
    echo "HAWS Home"
    echo "Status | Sync | Settings | Doctor | Status details | Exit"
    ui_next_key >/dev/null 2>&1 || return 0
    key="${UI_LAST_KEY:-}"
    case "${key}" in
      sync) sync_run || true ;;
      settings) settings_run || true ;;
      doctor) doctor_run || true ;;
      details|status) status_run --details ;;
      exit|q|quit|cancel|"") return 0 ;;
      *) echo "Invalid selection. Choose Sync, Settings, Doctor, Status details, or Exit." ;;
    esac
  done
}

settings_run() { settings_edit "${1:-settings}"; }
