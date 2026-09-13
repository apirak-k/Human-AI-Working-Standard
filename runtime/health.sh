#!/usr/bin/env bash
# Read-only local health reporting for Status and Doctor.

_health_repo() { printf '%s\n' "${HAWS_REPO_DIR:-${SCRIPT_DIR:-$(pwd)}}"; }
_health_state() { printf '%s\n' "$(_haws_state_dir)"; }

health_classify() {
  local findings="${1:-}" level
  while IFS=$'\t' read -r level _ _ _ || [ -n "${level}" ]; do
    case "${level}" in
      Blocked) printf '%s\n' Blocked; return 0 ;;
      Attention) printf '%s\n' Attention ;;
    esac
  done <<EOF
${findings}
EOF
  if printf '%s\n' "${findings}" | grep -q '^Attention'; then printf '%s\n' Attention; else printf '%s\n' Ready; fi
}

_health_add() {
  HAWS_HEALTH_FINDINGS="${HAWS_HEALTH_FINDINGS:-}${1}\t${2}\t${3}\t${4}\n"
}

_health_env_path() {
  case "$1" in
    claude) printf '%s/.claude/CLAUDE.md\n' "${HOME}" ;;
    gemini) printf '%s/.gemini/GEMINI.md\n' "${HOME}" ;;
    cursor) printf '%s/.cursor/rules/haws.mdc\n' "${HOME}" ;;
    copilot) printf '%s/.copilot/copilot-instructions.md\n' "${HOME}" ;;
    codex) printf '%s/.codex/AGENTS.md\n' "${HOME}" ;;
  esac
}

_health_env_detected() {
  case "$1" in
    claude) [ -d "${HOME}/.claude" ] ;;
    gemini) [ -d "${HOME}/.gemini" ] ;;
    cursor) [ -d "${HOME}/.cursor" ] || [ -f "${HOME}/.cursorrules" ] ;;
    copilot) [ -d "${HOME}/.copilot" ] || [ -d "${HOME}/.config/github-copilot" ] ;;
    codex) [ -d "${HOME}/.codex" ] || [ -d "${HOME}/.agents" ] ;;
    *) return 1 ;;
  esac
}

_health_owned_file_matches() {
  local path="$1" row recorded actual
  row="$(ownership_list environments 2>/dev/null | awk -F $'\t' -v p="${path}" '$2=="generated-file" && $3==p {print; exit}' || true)"
  [ -n "${row}" ] || return 0
  recorded="$(printf '%s\n' "${row}" | cut -f5)"
  [ -n "${recorded}" ] || return 0
  actual="$(_haws_sha256 "${path}")"
  [ "${actual}" = "${recorded}" ]
}

_health_collect() {
  local env path row source_id source_path url revision skill_id display source_id_row entrypoint active
  HAWS_HEALTH_FINDINGS=""
  settings_load || _health_add Blocked settings "settings file is invalid" "Run haws.sh settings"
  disabled_envs_load
  disabled_skills_load
  for env in claude gemini cursor copilot codex; do
    _health_env_detected "${env}" || continue
    if [ -n "${DISABLED_ENVS[${env}]:-}" ]; then
      _health_add Ready "environment:${env}" "environment disabled by local selection" "Enable in Settings if needed"
      continue
    fi
    path="$(_health_env_path "${env}")"
    if [ -e "${path}" ] || [ -L "${path}" ]; then
      if _health_owned_file_matches "${path}"; then
        _health_add Ready "environment:${env}" "adapter present" "No action"
      else
        _health_add Attention "environment:${env}" "HAWS-owned adapter changed locally" "Review or restore adapter in Settings"
      fi
    else
      _health_add Attention "environment:${env}" "selected adapter missing" "Run haws.sh settings"
    fi
  done

  local sources_raw
  sources_raw="$(catalog_sources 2>/dev/null || true)"
  local s_var
  while IFS= read -r row || [ -n "${row}" ]; do
    [ -n "${row}" ] || continue
    IFS=$'\t' read -r source_id source_path url revision <<EOF
${row}
EOF
    s_var="SRC_PATH_${source_id//[^a-zA-Z0-9_]/_}"
    printf -v "${s_var}" '%s' "${source_path}"
    if [ -d "$(_health_repo)/${source_path}" ]; then
      _health_add Ready "source:${source_id}" "source available" "No action"
    else
      _health_add Attention "source:${source_id}" "source checkout missing" "Run haws.sh sync"
    fi
  done <<EOF
${sources_raw}
EOF

  local skills_raw
  skills_raw="$(catalog_skills 2>/dev/null || true)"
  HAWS_HEALTH_SKILLS_DATA="${skills_raw}"
  while IFS= read -r row || [ -n "${row}" ]; do
    [ -n "${row}" ] || continue
    IFS=$'\t' read -r skill_id display source_id_row entrypoint active <<EOF
${row}
EOF
    [ "${active}" = 1 ] || continue
    s_var="SRC_PATH_${source_id_row//[^a-zA-Z0-9_]/_}"
    path="${!s_var:-}"
    [ -n "${path}" ] || path="$(_catalog_source_fields "${source_id_row}" 2>/dev/null | cut -f1 || true)"
    if [ -s "$(_health_repo)/${path}/${entrypoint}" ]; then
      _health_add Ready "skill:${skill_id}" "active entrypoint usable" "No action"
    else
      _health_add Blocked "skill:${skill_id}" "active entrypoint missing or empty" "Run haws.sh settings or sync"
    fi
  done <<EOF
${skills_raw}
EOF
}

_health_last_sync() {
  local file="$(_health_state)/sync-state.tsv"
  [ -s "${file}" ] && tail -n 1 "${file}" || printf '%s\n' "none"
}

status_run() {
  local details=false last classification env_count source_count active_count disabled_count row
  [ "${1:-}" = --details ] && details=true
  _health_collect
  classification="$(health_classify "${HAWS_HEALTH_FINDINGS}")"
  settings_load || true
  env_count=0; for row in claude gemini cursor copilot codex; do _health_env_detected "${row}" && env_count=$((env_count + 1)); done
  source_count="$(catalog_sources 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
  read -r active_count disabled_count <<EOF
$(printf '%s\n' "${HAWS_HEALTH_SKILLS_DATA:-}" | awk -F $'\t' '
  $5 == 1 {act++}
  $5 != 1 && NF >= 5 {dis++}
  END {print (act+0), (dis+0)}
')
EOF
  echo "HAWS Status"
  echo "Overall: ${classification}"
  last="$(_health_last_sync)"
  if [ "${last}" = none ]; then echo "Last sync: none"; else IFS=$'\t' read -r _ _ result _ _ <<EOF
${last}
EOF
    echo "Last sync: ${result}"; fi
  echo "AI Environments: ${env_count} detected"
  echo "Skills: ${active_count} active, ${disabled_count} disabled"
  echo "Sources: ${source_count}"
  echo "Second Brain: ${HAWS_SECOND_BRAIN_ENABLED:-off}"
  echo "Auto Update: ${HAWS_AUTO_UPDATE:-on}"
  if [ "${details}" = true ]; then
    echo ""
    echo "AI Environments"
    printf '%b' "${HAWS_HEALTH_FINDINGS}" | grep '^Ready\|^Attention\|^Blocked' | grep 'environment:' || true
    echo "Sources"
    printf '%b' "${HAWS_HEALTH_FINDINGS}" | grep '^Ready\|^Attention\|^Blocked' | grep 'source:' || true
    echo "Skills"
    printf '%b' "${HAWS_HEALTH_FINDINGS}" | grep '^Ready\|^Attention\|^Blocked' | grep 'skill:' || true
  fi
  return 0
}

doctor_run() {
  local classification
  _health_collect
  classification="$(health_classify "${HAWS_HEALTH_FINDINGS}")"
  echo "HAWS Doctor"
  echo "Overall: ${classification}"
  printf '%b' "${HAWS_HEALTH_FINDINGS}" | while IFS=$'\t' read -r level item cause action || [ -n "${level}" ]; do
    [ -n "${level}" ] || continue
    printf '%s\t%s\t%s\t%s\n' "${level}" "${item}" "${cause}" "${action}"
  done
  [ "${classification}" != Blocked ]
}
