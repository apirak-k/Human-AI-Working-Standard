#!/usr/bin/env bash
# Device-local HAWS state boundary. No network calls and no user workflow.

# state.sh is usable on its own in tests and by small consumers, while haws.sh
# sources platform.sh first.  Keep the dependency local and deterministic.
if ! command -v atomic_replace >/dev/null 2>&1; then
  _HAWS_STATE_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC1091
  . "${_HAWS_STATE_MODULE_DIR}/platform.sh"
fi

_haws_state_repo() {
  if [ -n "${HAWS_REPO_DIR:-}" ]; then printf '%s\n' "${HAWS_REPO_DIR}"; return; fi
  if [ -n "${SCRIPT_DIR:-}" ]; then printf '%s\n' "${SCRIPT_DIR}"; return; fi
  pwd -P
}

_haws_state_dir() {
  if [ -n "${HAWS_STATE_DIR:-}" ]; then printf '%s\n' "${HAWS_STATE_DIR}"; return; fi
  printf '%s/.haws/state\n' "$(_haws_state_repo)"
}

_haws_compat_file() {
  local filename="$1"
  local repo="$(_haws_state_repo)"
  if [ -f "${repo}/ai-configs/${filename}" ]; then printf '%s\n' "${repo}/ai-configs/${filename}"; return; fi
  if [ -f "${repo}/config/${filename}" ]; then printf '%s\n' "${repo}/config/${filename}"; return; fi
  if [ -f "${repo}/${filename}" ]; then printf '%s\n' "${repo}/${filename}"; return; fi
  printf '%s/ai-configs/%s\n' "${repo}" "${filename}"
}

_haws_sha256() {
  local path="$1"
  [ -f "${path}" ] || return 0
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "${path}" 2>/dev/null | awk '{print $1}'; return; fi
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "${path}" 2>/dev/null | awk '{print $1}'; return; fi
  cksum "${path}" | awk '{print $1 ":" $2}'
}

settings_defaults() {
  HAWS_SECOND_BRAIN_ENABLED="off"
  HAWS_SECOND_BRAIN_REMOTE=""
  HAWS_AUTO_UPDATE="on"
  SECOND_BRAIN_ENABLED="off"
  AUTO_UPDATE="on"
  export HAWS_SECOND_BRAIN_ENABLED HAWS_SECOND_BRAIN_REMOTE HAWS_AUTO_UPDATE SECOND_BRAIN_ENABLED AUTO_UPDATE
}

_settings_valid_value() { [ "${1:-}" = on ] || [ "${1:-}" = off ]; }

settings_load() {
  local file="$(_haws_state_dir)/settings.tsv"
  settings_defaults
  [ -f "${file}" ] || return 0
  local key value extra
  while IFS="	" read -r key value extra || [ -n "${key:-}" ]; do
    [ -z "${key:-}" ] && continue
    case "${key}" in
      schema_version) [ "${value}" = 1 ] || { echo "Blocked: malformed settings schema; remove ${file} after review" >&2; return 2; } ;;
      second_brain|second_brain_enabled)
        [ -z "${extra:-}" ] && _settings_valid_value "${value}" || { echo "Blocked: malformed second brain setting; review ${file}" >&2; return 2; }
        HAWS_SECOND_BRAIN_ENABLED="${value}"; SECOND_BRAIN_ENABLED="${value}" ;;
      second_brain_remote)
        [ -z "${extra:-}" ] || { echo "Blocked: malformed second brain remote; review ${file}" >&2; return 2; }
        HAWS_SECOND_BRAIN_REMOTE="${value}" ;;
      auto_update)
        [ -z "${extra:-}" ] && _settings_valid_value "${value}" || { echo "Blocked: malformed auto update setting; review ${file}" >&2; return 2; }
        HAWS_AUTO_UPDATE="${value}"; AUTO_UPDATE="${value}" ;;
      *) echo "Blocked: unknown settings key '${key}'; review ${file}" >&2; return 2 ;;
    esac
  done < "${file}"
  export HAWS_SECOND_BRAIN_ENABLED HAWS_SECOND_BRAIN_REMOTE HAWS_AUTO_UPDATE SECOND_BRAIN_ENABLED AUTO_UPDATE
}

settings_save() {
  local second_brain="${1:-${HAWS_SECOND_BRAIN_ENABLED:-off}}"
  local auto_update="${2:-${HAWS_AUTO_UPDATE:-on}}"
  local second_brain_remote="${3:-${HAWS_SECOND_BRAIN_REMOTE:-}}"
  _settings_valid_value "${second_brain}" || return 2
  _settings_valid_value "${auto_update}" || return 2
  local state="$(_haws_state_dir)" temp
  mkdir -p "${state}" || return 1
  temp="${state}/settings.stage.$$"
  {
    printf 'schema_version\t1\n'
    printf 'second_brain\t%s\n' "${second_brain}"
    [ -z "${second_brain_remote}" ] || printf 'second_brain_remote\t%s\n' "${second_brain_remote}"
    printf 'auto_update\t%s\n' "${auto_update}"
  } > "${temp}" || { rm -f "${temp}"; return 1; }
  atomic_replace "${temp}" "${state}/settings.tsv"; local result=$?
  rm -f "${temp}"
  [ "${result}" -eq 0 ] || return "${result}"
  HAWS_SECOND_BRAIN_ENABLED="${second_brain}"; HAWS_SECOND_BRAIN_REMOTE="${second_brain_remote}"; HAWS_AUTO_UPDATE="${auto_update}"
  SECOND_BRAIN_ENABLED="${second_brain}"; AUTO_UPDATE="${auto_update}"
  export HAWS_SECOND_BRAIN_ENABLED HAWS_SECOND_BRAIN_REMOTE HAWS_AUTO_UPDATE SECOND_BRAIN_ENABLED AUTO_UPDATE
}

disabled_envs_load() {
  local file="$(_haws_compat_file environments.disabled)" line
  HAWS_DISABLED_ENVS=""
  if [ -f "${file}" ]; then
    while IFS= read -r line || [ -n "${line}" ]; do
      line="${line%$'\r'}"; line="${line%%#*}"
      line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
      [ -n "${line}" ] && HAWS_DISABLED_ENVS="${HAWS_DISABLED_ENVS}${line}\n"
    done < "${file}"
  fi
  export HAWS_DISABLED_ENVS
  if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
    eval 'declare -gA DISABLED_ENVS=()'
    while IFS= read -r line; do [ -n "${line}" ] && DISABLED_ENVS["${line}"]=1; done < <(printf '%b' "${HAWS_DISABLED_ENVS}")
  fi
}

disabled_envs_save() {
  local file="$(_haws_compat_file environments.disabled)" state="$(_haws_state_dir)" temp line
  mkdir -p "$(dirname "${file}")" || return 1
  temp="${state}/environments.disabled.stage.$$"; mkdir -p "${state}" || return 1
  {
    printf '# HAWS Disabled AI Environments\n'
    printf '# Environments listed here will not receive Global Pointers or Linked Skills\n'
    if [ "$#" -gt 0 ]; then printf '%s\n' "$@" | sort; else printf '%b' "${HAWS_DISABLED_ENVS:-}" | sed '/^[[:space:]]*$/d' | sort; fi
  } > "${temp}" || { rm -f "${temp}"; return 1; }
  atomic_replace "${temp}" "${file}"; local result=$?; rm -f "${temp}"; return "${result}"
}

disabled_skills_load() {
  local file="$(_haws_compat_file skills.disabled)" line
  HAWS_DISABLED_SKILLS=""
  if [ -f "${file}" ]; then
    while IFS= read -r line || [ -n "${line}" ]; do
      line="${line%$'\r'}"; line="${line%%#*}"
      line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
      [ -n "${line}" ] && HAWS_DISABLED_SKILLS="${HAWS_DISABLED_SKILLS}${line}\n"
    done < "${file}"
  fi
  export HAWS_DISABLED_SKILLS
  if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
    eval 'declare -gA DISABLED_SKILLS=()'
    while IFS= read -r line; do [ -n "${line}" ] && DISABLED_SKILLS["${line}"]=1; done < <(printf '%b' "${HAWS_DISABLED_SKILLS}")
  fi
}

disabled_skills_save() {
  local file="$(_haws_compat_file skills.disabled)" state="$(_haws_state_dir)" temp
  mkdir -p "$(dirname "${file}")" "${state}" || return 1
  temp="${state}/skills.disabled.stage.$$"
  { printf '# HAWS Disabled Skills\n'; printf '# Skills listed here will not be linked to Claude Code or Antigravity\n'; if [ "$#" -gt 0 ]; then printf '%s\n' "$@" | sort; else printf '%b' "${HAWS_DISABLED_SKILLS:-}" | sed '/^[[:space:]]*$/d' | sort; fi; } > "${temp}" || { rm -f "${temp}"; return 1; }
  atomic_replace "${temp}" "${file}"; local result=$?; rm -f "${temp}"; return "${result}"
}

ownership_record() {
  local group="${1:-}" kind="${2:-}" path="${3:-}" source="${4:-}" fingerprint="${5:-}"
  [ -n "${group}" ] && [ -n "${kind}" ] && [ -n "${path}" ] || return 2
  local state="$(_haws_state_dir)" file temp
  mkdir -p "${state}" || return 1
  file="${state}/ownership.tsv"; temp="${state}/ownership.stage.$$"
  [ -f "${file}" ] && cp "${file}" "${temp}" || : > "${temp}"
  if ! awk -F '\t' -v g="${group}" -v k="${kind}" -v p="${path}" '$1==g && $2==k && $3==p {found=1} END {exit found ? 0 : 1}' "${temp}"; then
    printf '%s\t%s\t%s\t%s\t%s\n' "${group}" "${kind}" "${path}" "${source}" "${fingerprint}" >> "${temp}" || { rm -f "${temp}"; return 1; }
  fi
  atomic_replace "${temp}" "${file}"; local result=$?; rm -f "${temp}"; return "${result}"
}

ownership_list() {
  local group="${1:-}" file="$(_haws_state_dir)/ownership.tsv"
  [ -f "${file}" ] || return 0
  if [ -n "${group}" ]; then awk -F '\t' -v g="${group}" '$1==g' "${file}"; else cat "${file}"; fi
}

sync_lock_acquire() {
  local state="$(_haws_state_dir)" lock pid timestamp now
  mkdir -p "${state}" || return 1
  lock="${state}/sync.lock"
  if mkdir "${lock}" 2>/dev/null; then
    printf '%s\n' "$$" > "${lock}/pid"
    date +%s > "${lock}/timestamp"
    return 0
  fi
  pid="$(cat "${lock}/pid" 2>/dev/null || true)"
  timestamp="$(cat "${lock}/timestamp" 2>/dev/null || true)"
  if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
    echo "Blocked: sync already running (pid ${pid})" >&2
    return 1
  fi
  now="$(date +%s)"
  echo "Blocked: stale sync lock (pid ${pid:-unknown}, timestamp ${timestamp:-unknown}); run sync_lock_release --recover after review" >&2
  return 2
}

sync_lock_release() {
  local lock="$(_haws_state_dir)/sync.lock" pid mode="${1:-}" owner
  [ -d "${lock}" ] || return 0
  owner="$(cat "${lock}/pid" 2>/dev/null || true)"
  if [ "${mode}" = --recover ] || [ "${mode}" = recover ]; then
    if [ -n "${owner}" ] && kill -0 "${owner}" 2>/dev/null; then
      echo "Blocked: refusing to recover live sync lock (pid ${owner})" >&2; return 1
    fi
    rmdir "${lock}" 2>/dev/null || { rm -f "${lock}/pid" "${lock}/timestamp" && rmdir "${lock}" 2>/dev/null; }
    return 0
  fi
  [ "${owner}" = "$$" ] || { echo "Blocked: sync lock is owned by pid ${owner:-unknown}" >&2; return 1; }
  rm -f "${lock}/pid" "${lock}/timestamp" && rmdir "${lock}"
}

_state_migrate_manifest() {
  local manifest="${HOME:-}/.haws_manifest" line type name target source kind fp
  [ -f "${manifest}" ] || return 0
  while IFS= read -r line || [ -n "${line}" ]; do
    [ -n "${line}" ] || continue
    type="${line%%:*}"; name="${line#*:}"
    [ -n "${name}" ] || continue
    target=""
    if [ "${type}" = skill ]; then
      for candidate in "${HOME}/.claude/skills/${name}" "${HOME}/.gemini/config/skills/${name}" "${HOME}/.agents/skills/${name}"; do
        if [ -e "${candidate}" ] || [ -L "${candidate}" ]; then target="${candidate}"; break; fi
      done
    elif [ "${type}" = agent ]; then
      for candidate in "${HOME}/.claude/agents/${name}.md" "${HOME}/.gemini/config/agents/${name}" "${HOME}/.codex/agents/${name}.md"; do
        if [ -e "${candidate}" ] || [ -L "${candidate}" ]; then target="${candidate}"; break; fi
      done
    fi
    [ -n "${target}" ] || continue
    if [ -L "${target}" ]; then
      kind=symlink
      source="$(canonical_path "${target}")"
      # Hashing a directory through a symlink is not portable; the canonical
      # target is the ownership proof for managed links.
      fp="${source}"
    elif [ -d "${target}" ]; then
      kind=directory
      source="$(canonical_path "${target}")"
      fp="${source}"
    else
      kind=file
      source=""
      fp="$(_haws_sha256 "${target}")"
    fi
    if [ "${kind}" = symlink ]; then
      ownership_record "${type}s" "${kind}" "${target}" "${source}" "${fp}" || return 1
    else
      ownership_record "${type}s" "${kind}" "${target}" "${source}" "${fp}" || return 1
    fi
  done < "${manifest}"
}

state_init() {
  local state="$(_haws_state_dir)"
  mkdir -p "${state}" || return 1
  settings_load || return $?
  if [ ! -f "${state}/settings.tsv" ]; then settings_save "${HAWS_SECOND_BRAIN_ENABLED}" "${HAWS_AUTO_UPDATE}" || return 1; fi
  disabled_envs_load
  disabled_skills_load
  _state_migrate_manifest || return 1
}
