#!/usr/bin/env bash
# Shared plan/apply boundary for selected AI adapters and skill links.

_integration_repo() { printf '%s\n' "${HAWS_REPO_DIR:-${SCRIPT_DIR:-$(pwd)}}"; }
_integration_checkout() { printf '%s\n' "${SCRIPT_DIR:-${HAWS_REPO_DIR:-$(pwd)}}"; }

_integration_env_path() {
  case "$1" in
    claude) printf '%s\n' "${HOME}/.claude/CLAUDE.md" ;;
    gemini) printf '%s\n' "${HOME}/.gemini/GEMINI.md" ;;
    cursor) printf '%s\n' "${HOME}/.cursor/rules/haws.mdc" ;;
    copilot) printf '%s\n' "${HOME}/.copilot/copilot-instructions.md" ;;
    codex) printf '%s\n' "${HOME}/.codex/AGENTS.md" ;;
  esac
}

_integration_template() {
  case "$1" in
    claude) printf '%s\n' "$(_integration_checkout)/ai-configs/claude/CLAUDE.md.template" ;;
    gemini) printf '%s\n' "$(_integration_checkout)/ai-configs/gemini/GEMINI.md.template" ;;
    cursor) printf '%s\n' "$(_integration_checkout)/ai-configs/cursor/haws.mdc.template" ;;
    copilot) printf '%s\n' "$(_integration_checkout)/ai-configs/copilot/copilot-instructions.md.template" ;;
    codex) printf '%s\n' "$(_integration_checkout)/ai-configs/codex/AGENTS.override.md.template" ;;
  esac
}

_integration_env_selected() {
  local wanted="$1" line
  while IFS= read -r line || [ -n "${line}" ]; do
    [ "${line}" = "${wanted}" ] && return 0
  done <<EOF
${HAWS_SELECTED_ENVS:-}
EOF
  return 1
}

_integration_source_selected() {
  local wanted="$1" line selection="${2:-}"
  [ -z "${selection}" ] && return 0
  while IFS= read -r line || [ -n "${line}" ]; do
    [ "${line}" = "${wanted}" ] && return 0
  done <<EOF
${selection}
EOF
  return 1
}

integration_plan() {
  local old_selection="${1:-}" new_selection="${2:-}" output="${HAWS_INTEGRATION_PLAN:-}"
  [ -n "${output}" ] || output="${TMPDIR:-/tmp}/haws-integration-plan.$$"
  : > "${output}" || return 1
  local repo source_row source_id path url revision source_dir env skill_row skill_id display source_skill entrypoint active destination template
  repo="$(_integration_repo)"
  while IFS= read -r source_row || [ -n "${source_row}" ]; do
    [ -n "${source_row}" ] || continue
    IFS="	" read -r source_id path url revision <<EOF
${source_row}
EOF
    _integration_source_selected "${source_id}" "${new_selection}" || continue
    source_dir="${repo}/${path}"
    if [ ! -d "${source_dir}" ]; then
      printf 'initialize\tsources\t%s\t%s\tselected source is missing locally\n' "${source_id}" "${path}" >> "${output}"
      continue
    fi
  done <<EOF
$(catalog_sources 2>/dev/null || true)
EOF
  for env in claude gemini cursor copilot codex; do
    _integration_env_selected "${env}" || continue
    template="$(_integration_template "${env}")"
    destination="$(_integration_env_path "${env}")"
    [ -f "${template}" ] && printf 'pointer\tenvironments\t%s\t%s\tselected AI environment\n' "${template}" "${destination}" >> "${output}"
  done
  while IFS= read -r skill_row || [ -n "${skill_row}" ]; do
    [ -n "${skill_row}" ] || continue
    IFS="	" read -r skill_id display source_id entrypoint active <<EOF
${skill_row}
EOF
    [ "${active}" = 1 ] || continue
    source_skill="${repo}/$(_catalog_source_fields "${source_id}" 2>/dev/null | cut -f1)/${entrypoint%/SKILL.md}"
    for env in claude gemini codex; do
      _integration_env_selected "${env}" || continue
      case "${env}" in
        claude) destination="${HOME}/.claude/skills/${display}" ;;
        gemini) destination="${HOME}/.gemini/config/skills/${display}" ;;
        codex) destination="${HOME}/.agents/skills/${display}" ;;
      esac
      printf 'skill-link\tskills\t%s\t%s\tactive skill for selected environment\n' "${source_skill}" "${destination}" >> "${output}"
    done
  done <<EOF
$(catalog_skills 2>/dev/null || true)
EOF
  printf '%s\n' "${output}"
}

_integration_pointer_apply() {
  local source="$1" destination="$2" parent temp
  [ -f "${source}" ] || return 1
  if [ -e "${destination}" ] || [ -L "${destination}" ]; then
    if [ -f "${destination}" ] && cmp -s "${source}" "${destination}"; then
      ownership_record environments generated-file "${destination}" "${source}" "$(_haws_sha256 "${source}")" || return 1
      return 0
    fi
    echo "Blocked: existing user artifact conflicts with ${destination}" >&2
    return 2
  fi
  parent="$(dirname "${destination}")"; mkdir -p "${parent}" || return 1
  temp="${destination}.stage.$$"
  cp "${source}" "${temp}" || { rm -f "${temp}"; return 1; }
  mv "${temp}" "${destination}" || { rm -f "${temp}"; return 1; }
  ownership_record environments generated-file "${destination}" "${source}" "$(_haws_sha256 "${source}")"
}

integration_apply() {
  local plan="${1:-}" action group source destination reason source_dir
  [ -f "${plan}" ] || return 1
  while IFS="	" read -r action group source destination reason || [ -n "${action}" ]; do
    case "${action}" in
      initialize)
        source_dir="${destination}"
        git -C "$(_integration_repo)" submodule update --init --depth 1 "${source_dir}" || return 1
        ;;
      pointer)
        _integration_pointer_apply "${source}" "${destination}" || return $?
        ;;
      skill-link)
        if create_managed_link "${source}" "${destination}" >/dev/null 2>&1; then
          ownership_record skills symlink "${destination}" "${source}" "$(canonical_path "${source}")" || return 1
        else
          echo "Blocked: cannot safely link ${destination}" >&2
          return 2
        fi
        ;;
    esac
  done < "${plan}"
  return 0
}
