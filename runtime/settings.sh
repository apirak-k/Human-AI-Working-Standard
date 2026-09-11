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

settings_ensure_skills_draft() {
  [ "${HAWS_SKILLS_DRAFT_LOADED:-0}" = 1 ] && return 0
  echo "Loading skills catalog (this can take a moment)..."
  HAWS_SELECTED_SKILLS="$(_settings_active_skills)"
  HAWS_SKILLS_DRAFT_LOADED=1
  export HAWS_SELECTED_SKILLS HAWS_SKILLS_DRAFT_LOADED
}

settings_draft_defaults() {
  echo "Loading HAWS settings..."
  HAWS_SELECTED_ENVS="$(_settings_detected_envs)"
  echo "Loading repository catalog..."
  HAWS_SELECTED_SOURCES="$(_settings_sources)"
  # Skills are the expensive catalog. Load them only if the user enters Skills
  # or asks for Preview; the opening screen must remain responsive.
  HAWS_SELECTED_SKILLS=""
  HAWS_SKILLS_DRAFT_LOADED=0
  HAWS_DRAFT_SECOND_BRAIN="off"
  HAWS_DRAFT_SECOND_BRAIN_REMOTE="${HAWS_SECOND_BRAIN_REMOTE:-}"
  HAWS_DRAFT_AUTO_UPDATE="on"
  echo "Settings ready. Skills load when you open Skills or Preview."
  export HAWS_SELECTED_ENVS HAWS_SELECTED_SOURCES HAWS_SELECTED_SKILLS HAWS_DRAFT_SECOND_BRAIN HAWS_DRAFT_SECOND_BRAIN_REMOTE HAWS_DRAFT_AUTO_UPDATE
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
        [ -d "${detail}" ] && detail="Detected" || detail="Not detected"
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
    skills|skills-single)
      while IFS=$'\t' read -r id label _ detail active; do
        [ -n "${id}" ] || continue
        if [ "${type}" != skills ]; then
          local source_count
          source_count="$(catalog_skills 2>/dev/null | awk -F '\t' -v wanted="${_}" '$3 == wanted {n++} END {print n+0}')"
          [ "${type}" = skills-single ] && [ "${source_count}" -eq 1 ] || continue
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

_settings_skill_counts() {
  local current="$1" source filter="$2" id label source_id detail active total=0 enabled=0
  while IFS=$'\t' read -r id label source_id detail active; do
    [ -n "${id}" ] || continue
    source="$(catalog_skills 2>/dev/null | awk -F '\t' -v wanted="${source_id}" '$3 == wanted {n++} END {print n+0}')"
    [ "${filter}" = single ] && [ "${source}" -ne 1 ] && continue
    [ "${filter}" = packs ] && [ "${source}" -le 1 ] && continue
    total=$((total + 1))
    _settings_list_contains "${current}" "${id}" && enabled=$((enabled + 1))
  done <<EOF
$(catalog_skills 2>/dev/null || true)
EOF
  printf '%s / %s active' "${enabled}" "${total}"
}

multi_skill_packs_menu() {
  local current="${HAWS_SELECTED_SKILLS:-}" key id label source_id detail active count records=()
  declare -A seen=()
  while IFS=$'\t' read -r id label source_id detail active; do
    [ -n "${id}" ] || continue
    [ -n "${seen[${source_id}]:-}" ] && continue
    seen[${source_id}]=1
    count="$(catalog_skills 2>/dev/null | awk -F '\t' -v wanted="${source_id}" '$3 == wanted {n++} END {print n+0}')"
    [ "${count}" -gt 1 ] || continue
    local enabled=0 skill_id
    while IFS=$'\t' read -r skill_id _ _ _ _; do _settings_list_contains "${current}" "${skill_id}" && enabled=$((enabled + 1)); done <<EOF
$(catalog_skills 2>/dev/null | awk -F '\t' -v wanted="${source_id}" '$3 == wanted')
EOF
    records+=("${source_id}"$'\t'"${source_id}"$'\t'"${enabled} / ${count} active")
  done <<EOF
$(catalog_skills 2>/dev/null || true)
EOF
  records+=($'back\tBack to Skills\t')
  while true; do
    ui_cursor_menu "HAWS Settings — Multi-Skill Packs" "${records[@]}" || return 0
    key="${UI_MENU_RESULT:-back}"; [ "${key}" = back ] && return 0
    _settings_choose_pack "${key}" || true
    current="${HAWS_SELECTED_SKILLS:-}"
  done
}

_settings_choose_pack() {
  local pack="$1" id label source_id detail active records=()
  while IFS=$'\t' read -r id label source_id detail active; do
    [ "${source_id}" = "${pack}" ] || continue
    _settings_list_contains "${HAWS_SELECTED_SKILLS:-}" "${id}" && active=1 || active=0
    records+=("${id}"$'\t'"${label}"$'\t'"${detail}"$'\t'"${active}")
  done <<EOF
$(catalog_skills 2>/dev/null || true)
EOF
  [ "${#records[@]}" -gt 0 ] || return 1
  ui_checklist "Configure Skills in ${pack}" "${records[@]}" || return 1
  HAWS_SELECTED_SKILLS="${UI_CHECKLIST_RESULT}"; export HAWS_SELECTED_SKILLS
}

repositories_menu() {
  local key url records=()
  while true; do
    records=($'add\tAdd Repository\t' $'remove\tRemove Repository\t' $'back\tBack to Settings\t')
    ui_cursor_menu "HAWS Settings — Repositories" "${records[@]}" || return 0
    key="${UI_MENU_RESULT:-back}"
    case "${key}" in
      add)
        echo "Add Repository"
        echo "Enter repository URL, or Q to cancel."
        ui_next_key >/dev/null 2>&1 || continue
        url="${UI_LAST_KEY:-}"
        case "${url}" in q|Q|cancel|quit|"") continue ;; esac
        HAWS_DRAFT_ADDED_REPOSITORIES="${HAWS_DRAFT_ADDED_REPOSITORIES:-}${url}"$'\n'
        export HAWS_DRAFT_ADDED_REPOSITORIES
        echo "Repository added to draft: ${url}"
        ;;
      remove) _settings_choose_list HAWS_SELECTED_SOURCES "Remove Repository" "${HAWS_SELECTED_SOURCES:-}" sources || true ;;
      back) return 0 ;;
    esac
  done
}

skills_menu() {
  local key records=() single_count pack_count
  settings_ensure_skills_draft || return 1
  while true; do
    single_count="$(_settings_skill_counts "${HAWS_SELECTED_SKILLS:-}" single)"
    pack_count="$(_settings_skill_counts "${HAWS_SELECTED_SKILLS:-}" packs)"
    records=("single"$'\t'"Single Skills"$'\t'"${single_count}" "packs"$'\t'"Multi-Skill Packs"$'\t'"${pack_count}" $'back\tBack to Settings\t')
    ui_cursor_menu "HAWS Settings — Skills" "${records[@]}" || return 0
    key="${UI_MENU_RESULT:-back}"
    case "${key}" in
      1|single) _settings_choose_list HAWS_SELECTED_SKILLS "Single Skills" "${HAWS_SELECTED_SKILLS:-}" skills-single || true ;;
      2|packs) multi_skill_packs_menu ;;
      back) return 0 ;;
    esac
  done
}

settings_boolean_menu() {
  local target="$1" title="$2" current="$3" key value
  while true; do
    ui_cursor_menu "${title}" $'on\tOn\t' $'off\tOff\t' $'back\tBack to Settings\t' || return 0
    key="${UI_MENU_RESULT:-back}"
    case "${key}" in
      1|on) value=on ;;
      2|off) value=off ;;
      back) return 0 ;;
    esac
    printf -v "${target}" '%s' "${value}"
    export "${target}"
    return 0
  done
}

settings_second_brain_menu() {
  local key value
  ui_cursor_menu "Second Brain Remote" $'on\tOn\t' $'off\tOff\t' $'back\tBack to Settings\t' || return 0
  key="${UI_MENU_RESULT:-back}"
  case "${key}" in
    off) HAWS_DRAFT_SECOND_BRAIN=off; HAWS_DRAFT_SECOND_BRAIN_REMOTE=""; export HAWS_DRAFT_SECOND_BRAIN HAWS_DRAFT_SECOND_BRAIN_REMOTE; return 0 ;;
    back) return 0 ;;
    on) ;;
  esac
  HAWS_DRAFT_SECOND_BRAIN=on
  if [ -z "${HAWS_DRAFT_SECOND_BRAIN_REMOTE:-}" ]; then
    echo "Second Brain Remote URL (draft only):"
    ui_next_key >/dev/null 2>&1 || return 1
    value="${UI_LAST_KEY:-}"
    case "${value}" in ""|q|Q|cancel) HAWS_DRAFT_SECOND_BRAIN=off; return 0 ;; esac
    case "${value}" in *://*|git@*:* ) HAWS_DRAFT_SECOND_BRAIN_REMOTE="${value}" ;; *) echo "Invalid remote URL. No changes saved."; HAWS_DRAFT_SECOND_BRAIN=off; return 1 ;; esac
    if timeout 5 git ls-remote --heads "${HAWS_DRAFT_SECOND_BRAIN_REMOTE}" HEAD >/dev/null 2>&1; then
      echo "Remote connection: Ready (draft only)"
    else
      echo "Remote connection: Failed (draft only; URL was not saved)"
    fi
  fi
  export HAWS_DRAFT_SECOND_BRAIN HAWS_DRAFT_SECOND_BRAIN_REMOTE
  echo "Remote URL saved in draft; it will be applied only after Preview and Apply."
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
  echo "  1) Reset Standard Setup"
  echo "  2) Repositories: $(printf '%s\n' "${HAWS_SELECTED_SOURCES:-}" | sed '/^$/d' | wc -l | tr -d ' ') selected"
  echo "  3) Skills: $(printf '%s\n' "${HAWS_SELECTED_SKILLS:-}" | sed '/^$/d' | wc -l | tr -d ' ') active"
  echo "  4) AI Environments: ${HAWS_SELECTED_ENVS:-none}"
  echo "  5) Second Brain: ${HAWS_DRAFT_SECOND_BRAIN}"
  echo "  6) Auto Update when Syncing: ${HAWS_DRAFT_AUTO_UPDATE}"
  install_is_complete && echo "  7) Uninstall HAWS"
  echo "  0) Save & Apply / Exit"
  echo "  Q) Cancel"
}

_settings_menu_records() {
  local mode="${1:-settings}" source_count skill_count env_count title
  source_count="$(printf '%s\n' "${HAWS_SELECTED_SOURCES:-}" | sed '/^$/d' | wc -l | tr -d ' ')"
  skill_count="$(printf '%s\n' "${HAWS_SELECTED_SKILLS:-}" | sed '/^$/d' | wc -l | tr -d ' ')"
  env_count="$(printf '%s\n' "${HAWS_SELECTED_ENVS:-}" | sed '/^$/d' | wc -l | tr -d ' ')"
  [ "${mode}" = first-install ] && title="HAWS Settings — First Install" || title="HAWS Settings"
  printf '%s\t%s\t%s\n' default "Restore Recommended Defaults" ""
  printf '%s\t%s\t%s\n' repositories "Repositories" "${source_count} sources"
  printf '%s\t%s\t%s\n' skills "Skills" "${skill_count} active"
  printf '%s\t%s\t%s\n' envs "AI Environments" "${env_count} selected"
  printf '%s\t%s\t%s\n' second-brain "Second Brain Remote" "[ ${HAWS_DRAFT_SECOND_BRAIN^} ]"
  printf '%s\t%s\t%s\n' auto-update "Auto Update" "[ ${HAWS_DRAFT_AUTO_UPDATE^} ]"
  [ "${mode}" = first-install ] && printf '%s\t%s\t%s\n' save "Preview Install" "" || printf '%s\t%s\t%s\n' save "Preview Update" ""
  install_is_complete && printf '%s\t%s\t%s\n' uninstall "Uninstall HAWS" ""
  [ "${mode}" = first-install ] && printf '%s\t%s\t%s\n' cancel "Cancel Setup" "" || printf '%s\t%s\t%s\n' cancel "Cancel Update" ""
  printf '%s\n' "${title}" >&2
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
  local mode="${1:-settings}" key value title records=()
  settings_load || return $?
  disabled_envs_load || return $?
  disabled_skills_load || return $?
  HAWS_DRAFT_ENVS_TOUCHED=0
  settings_draft_defaults
  while true; do
    records=()
    while IFS=$'\t' read -r key value title; do records+=("${key}"$'\t'"${value}"$'\t'"${title}"); done <<EOF
$(_settings_menu_records "${mode}")
EOF
    title="HAWS Settings"
    [ "${mode}" = first-install ] && title="HAWS Settings — First Install"
    if [ -n "${HAWS_TEST_KEYS:-}" ] && [[ "${_HAWS_UI_KEYS_REMAINING:-}" == *=* ]]; then
      ui_next_key >/dev/null 2>&1 || key="cancel"
      key="${UI_LAST_KEY:-cancel}"
    else
      ui_cursor_menu "${title}" "${records[@]}" || { echo "Cancelled. No changes saved."; return 1; }
      key="${UI_MENU_RESULT:-cancel}"
    fi
    case "${key}" in
      1|default|d|D) settings_draft_defaults; HAWS_DRAFT_ENVS_TOUCHED=1; echo "Recommended defaults restored in draft." ;;
      0|save|s|S|apply)
        settings_plan_apply
        case $? in 0) return 0 ;; 2) continue ;; *) return 1 ;; esac
        ;;
      cancel|c|C|q|quit|exit|no) echo "Cancelled. No changes saved."; return 1 ;;
      2|repositories|sources|source) repositories_menu ;;
      3|skills|skill) skills_menu ;;
      4|envs|environment|environments) _settings_choose_list HAWS_SELECTED_ENVS "AI Environments" "${HAWS_SELECTED_ENVS:-}" envs; HAWS_DRAFT_ENVS_TOUCHED=1 ;;
      5|second-brain|second_brain) settings_second_brain_menu ;;
      6|auto-update|auto_update) settings_boolean_menu HAWS_DRAFT_AUTO_UPDATE "Auto Update" "${HAWS_DRAFT_AUTO_UPDATE}" ;;
      7|uninstall) uninstall_settings_menu; return $? ;;
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
  settings_ensure_skills_draft || return 1
  plan="${state}/settings.plan"; integration="${state}/integrations.plan"
  HAWS_INTEGRATION_PLAN="${integration}" integration_plan "" "${HAWS_SELECTED_SOURCES:-}" >/dev/null || return 1
  {
    printf 'setting\tsecond_brain\t%s\n' "${HAWS_DRAFT_SECOND_BRAIN:-off}"
    [ -z "${HAWS_DRAFT_SECOND_BRAIN_REMOTE:-}" ] || printf 'setting\tsecond_brain_remote\t%s\n' "${HAWS_DRAFT_SECOND_BRAIN_REMOTE}"
    printf 'setting\tauto_update\t%s\n' "${HAWS_DRAFT_AUTO_UPDATE:-on}"
    printf 'envs\t%s\n' "$(_settings_encode_list "${HAWS_SELECTED_ENVS:-}")"
    printf 'skills\t%s\n' "$(_settings_encode_list "${HAWS_SELECTED_SKILLS:-}")"
    cat "${integration}"
  } > "${plan}" || return 1
  if [ -s "${state}/install.complete" ] \
    && [ "${HAWS_DRAFT_SECOND_BRAIN:-off}" = "${HAWS_SECOND_BRAIN_ENABLED:-off}" ] \
    && [ "${HAWS_DRAFT_AUTO_UPDATE:-on}" = "${HAWS_AUTO_UPDATE:-on}" ] \
    && [ -z "${HAWS_DRAFT_SECOND_BRAIN_REMOTE:-}" ] \
    && [ -z "${HAWS_SELECTED_ENVS:-}" ] \
    && [ -z "${HAWS_SELECTED_SKILLS:-}" ] \
    && [ -z "${HAWS_SELECTED_SOURCES:-}" ]; then
    echo "No changes detected"
    return 0
  fi
  echo "Settings review"
  echo "Current -> Draft"
  printf '  Second Brain Remote: %s -> %s\n' "${HAWS_SECOND_BRAIN_ENABLED:-off}" "${HAWS_DRAFT_SECOND_BRAIN:-off}"
  printf '  Auto Update: %s -> %s\n' "${HAWS_AUTO_UPDATE:-on}" "${HAWS_DRAFT_AUTO_UPDATE:-on}"
  cat "${plan}"
  settings_apply "${plan}"
}

settings_apply() {
  local plan="${1:-}" action key value list env disabled skill
  [ -f "${plan}" ] || return 1
  ui_review "${plan}"
  case $? in
    0) ;;
    2) return 2 ;;
    *) echo "Cancelled. No changes saved."; return 1 ;;
  esac
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
  local second_brain_remote=""
  while IFS="	" read -r action key value _ || [ -n "${action}" ]; do
    [ "${action}" = setting ] && [ "${key}" = second_brain_remote ] && second_brain_remote="${value}"
  done < "${plan}"
  settings_save "${second_brain}" "${auto_update}" "${second_brain_remote}" || return 1
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
  if grep -qE '^(initialize|pointer|skill-link)[[:space:]]' "${plan}"; then
    echo "Apply progress"
    if integration_apply "${plan}"; then
      echo "Done: integration changes"
    else
      echo "Failed: integration changes"
      return 1
    fi
  else
    echo "Apply progress"
    echo "Skipped: no integration changes"
  fi
  printf 'schema=1\tcompleted_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$(_haws_state_dir)/install.complete" || return 1
  echo "Doctor: Ready (read-only)"
  echo "Home"
  home_run
}

home_run() {
  local key records=()
  settings_load || return $?
  while true; do
    status_run
    echo ""
    records=($'sync\tSync Now\t' $'settings\tSettings\t' $'doctor\tDoctor\t' $'details\tStatus Details\t' $'exit\tExit\t')
    if [ -n "${HAWS_TEST_KEYS:-}" ] && [[ "${_HAWS_UI_KEYS_REMAINING:-}" == *=* ]]; then
      ui_next_key >/dev/null 2>&1 || return 0
      key="${UI_LAST_KEY:-}"
    else
      ui_cursor_menu "HAWS Home" "${records[@]}" || return 0
      key="${UI_MENU_RESULT:-exit}"
    fi
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
