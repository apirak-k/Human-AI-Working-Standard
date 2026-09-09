#!/usr/bin/env bash
# Read-only source and skill catalog.  The top-level .gitmodules file is the
# only source registry; this module never contacts a remote or mutates state.

_catalog_repo_dir() {
  printf '%s\n' "${HAWS_REPO_DIR:-${SCRIPT_DIR:-$(pwd)}}"
}

_catalog_gitmodules() {
  printf '%s/.gitmodules\n' "$(_catalog_repo_dir)"
}

_catalog_source_id() {
  local name="$1" path="$2"
  printf '%s::%s\n' "${name}" "${path#./}"
}

_catalog_source_fields() {
  local wanted="$1" line source_id path url revision
  while IFS= read -r line || [ -n "${line}" ]; do
    [ -n "${line}" ] || continue
    IFS="$(printf '\t')" read -r source_id path url revision <<EOF
${line}
EOF
    if [ "${source_id}" = "${wanted}" ]; then
      printf '%s\t%s\t%s\n' "${path}" "${url}" "${revision}"
      return 0
    fi
  done <<EOF
$(catalog_sources)
EOF
  return 1
}

_catalog_source_revision() {
  local path="$1" repo
  repo="$(_catalog_repo_dir)"
  # Git otherwise walks upward and reports the superproject HEAD for an
  # uninitialised submodule.  Only accept a revision from a repository rooted
  # at this source path; fall back to the recorded gitlink below.
  if [ -e "${repo}/${path}/.git" ]; then
    git -C "${repo}/${path}" rev-parse --verify HEAD 2>/dev/null && return 0
  fi
  if [ -e "${repo}/.git" ]; then
    git -C "${repo}" rev-parse --verify "HEAD:${path}" 2>/dev/null && return 0
  fi
  printf '%s\n' uninitialized
}

_catalog_source_url() {
  local name="$1" gm
  gm="$(_catalog_gitmodules)"
  git -C "$(_catalog_repo_dir)" config --file "${gm}" --get "submodule.${name}.url" 2>/dev/null || printf '%s\n' -
}

catalog_sources() {
  local repo gm record key name path url revision source_id
  repo="$(_catalog_repo_dir)"
  gm="${repo}/.gitmodules"
  [ -f "${gm}" ] || return 0

  # --null returns one NUL-delimited "key\nvalue" record at a time, which
  # preserves spaces in paths while remaining available in Bash 3.2.
  while IFS= read -r -d '' record; do
    key="${record%%$'\n'*}"
    path="${record#*$'\n'}"
    case "${key}" in
      submodule.*.path)
        name="${key#submodule.}"
        name="${name%.path}"
        path="${path#./}"
        source_id="$(_catalog_source_id "${name}" "${path}")"
        url="$(_catalog_source_url "${name}")"
        revision="$(_catalog_source_revision "${path}")"
        printf '%s\t%s\t%s\t%s\n' "${source_id}" "${path}" "${url}" "${revision}"
        ;;
    esac
  done < <(git -C "${repo}" config --null --file "${gm}" --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)
}

_catalog_skill_display_name() {
  local skill_file="$1" fallback="${2:-}" line value
  [ -f "${skill_file}" ] || { printf '%s\n' "${fallback}"; return 0; }
  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      name:*)
        value="${line#name:}"
        value="${value%%#*}"
        value="${value#${value%%[![:space:]]*}}"
        value="${value%${value##*[![:space:]]}}"
        value="${value#\"}"; value="${value%\"}"
        value="${value#\'}"; value="${value%\'}"
        value="${value%$'\r'}"
        [ -n "${value}" ] && { printf '%s\n' "${value}"; return 0; }
        ;;
      [[:space:]]name:*)
        value="${line#*:}"
        value="${value%%#*}"
        value="${value#${value%%[![:space:]]*}}"
        value="${value%${value##*[![:space:]]}}"
        value="${value#\"}"; value="${value%\"}"
        value="${value#\'}"; value="${value%\'}"
        value="${value%$'\r'}"
        [ -n "${value}" ] && { printf '%s\n' "${value}"; return 0; }
        ;;
    esac
  done < "${skill_file}"
  printf '%s\n' "${fallback}"
}

_catalog_disabled_file() {
  local repo="$(_catalog_repo_dir)"
  local candidate
  for candidate in \
    "${repo}/skills/skills.disabled" \
    "${repo}/skills.disabled" \
    "${repo}/config/skills.disabled"; do
    if [ -f "${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

_catalog_is_disabled() {
  local skill_id="$1" display_name="$2" entrypoint="$3" line file
  file="$(_catalog_disabled_file 2>/dev/null || true)"
  [ -n "${file}" ] || return 1
  while IFS= read -r line || [ -n "${line}" ]; do
    line="${line%$'\r'}"
    line="${line%%#*}"
    line="${line#${line%%[![:space:]]*}}"
    line="${line%${line##*[![:space:]]}}"
    case "${line}" in
      "${skill_id}"|"${display_name}"|"${entrypoint}") return 0 ;;
    esac
  done < "${file}"
  return 1
}

catalog_skills() {
  local source_row source_id path url revision source_dir skill_file entrypoint skill_dir display_name skill_id active
  while IFS= read -r source_row || [ -n "${source_row}" ]; do
    [ -n "${source_row}" ] || continue
    IFS="$(printf '\t')" read -r source_id path url revision <<EOF
${source_row}
EOF
    source_dir="$(_catalog_repo_dir)/${path}"
    [ -d "${source_dir}" ] || continue
    while IFS= read -r -d '' skill_file; do
      [ -s "${skill_file}" ] || continue
      entrypoint="${skill_file#${source_dir}/}"
      skill_dir="${entrypoint%/SKILL.md}"
      display_name="$(_catalog_skill_display_name "${skill_file}" "${skill_dir##*/}")"
      skill_id="${source_id}::${entrypoint}"
      active=1
      if _catalog_is_disabled "${skill_id}" "${display_name}" "${entrypoint}"; then
        active=0
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' "${skill_id}" "${display_name}" "${source_id}" "${entrypoint}" "${active}"
    done < <(find "${source_dir}" -type f -name SKILL.md -print0 2>/dev/null)
  done <<EOF
$(catalog_sources)
EOF
}

source_has_active_skills() {
  local wanted="$1" row source_id active
  while IFS= read -r row || [ -n "${row}" ]; do
    [ -n "${row}" ] || continue
    IFS="$(printf '\t')" read -r _ _ source_id _ active <<EOF
${row}
EOF
    if [ "${source_id}" = "${wanted}" ] && [ "${active}" = 1 ]; then
      return 0
    fi
  done <<EOF
$(catalog_skills)
EOF
  return 1
}

changed_paths_affect_active_skills() {
  local wanted="$1" old_revision="$2" new_revision="$3"
  local fields path source_dir row source_id entrypoint active changed matched active_match
  fields="$(_catalog_source_fields "${wanted}" 2>/dev/null || true)"
  [ -n "${fields}" ] || return 1
  IFS="$(printf '\t')" read -r path _ _ <<EOF
${fields}
EOF
  source_dir="$(_catalog_repo_dir)/${path}"
  [ -d "${source_dir}" ] || return 1
  source_has_active_skills "${wanted}" || return 1

  while IFS= read -r changed || [ -n "${changed}" ]; do
    [ -n "${changed}" ] || continue
    matched=0
    active_match=0
    while IFS= read -r row || [ -n "${row}" ]; do
      [ -n "${row}" ] || continue
      IFS="$(printf '\t')" read -r _ _ source_id entrypoint active <<EOF
${row}
EOF
      [ "${source_id}" = "${wanted}" ] || continue
      case "${changed}" in
        "${entrypoint}"|"${entrypoint%/SKILL.md}"/*)
          matched=1
          [ "${active}" = 1 ] && active_match=1
          ;;
      esac
    done <<EOF
$(catalog_skills)
EOF
    # Any shared source path, or an active skill path, makes the update relevant.
    [ "${active_match}" -eq 1 ] && return 0
    [ "${matched}" -eq 0 ] && return 0
  done < <(git -C "${source_dir}" diff --name-only "${old_revision}" "${new_revision}" 2>/dev/null || true)
  return 1
}
