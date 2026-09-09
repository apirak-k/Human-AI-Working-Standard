#!/usr/bin/env bash
# Guarded per-target sync operations.  Network work is explicit, serialized,
# and never runs for a disabled target.

_operations_repo() { printf '%s\n' "${HAWS_REPO_DIR:-${SCRIPT_DIR:-$(pwd)}}"; }
_operations_state() { printf '%s\n' "$(_haws_state_dir)"; }

sync_result_write() {
  local target="${1:-}" result="${2:-}" revision="${3:--}" detail="${4:-}"
  local state file temp
  [ -n "${target}" ] && [ -n "${result}" ] || return 2
  state="$(_operations_state)"; file="${state}/sync-state.tsv"; temp="${state}/sync-state.stage.$$"
  mkdir -p "${state}" || return 1
  [ -f "${file}" ] && cp "${file}" "${temp}" || : > "${temp}"
  detail="${detail//$'\t'/ }"; detail="${detail//$'\n'/ }"
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${target}" "${result}" "${revision}" "${detail}" >> "${temp}" || { rm -f "${temp}"; return 1; }
  atomic_replace "${temp}" "${file}"; local status=$?; rm -f "${temp}"; return "${status}"
}

_operations_source_path() {
  local fields
  fields="$(_catalog_source_fields "${1:-}" 2>/dev/null || true)"
  [ -n "${fields}" ] || return 1
  printf '%s\n' "${fields%%$'\t'*}"
}

_operations_source_revision() {
  local source_id="${1:-}" path
  path="$(_operations_source_path "${source_id}")" || return 1
  _catalog_source_revision "${path}"
}

source_preflight() {
  local source_id="${1:-}" source_dir status
  source_dir="$(_operations_repo)/$(_operations_source_path "${source_id}")" || return 1
  [ -d "${source_dir}" ] || { echo "Blocked: source unavailable: ${source_id}" >&2; return 4; }
  source_has_active_skills "${source_id}" || { echo "Skipped: no active skills: ${source_id}"; return 3; }
  status="$(git -C "${source_dir}" status --porcelain --untracked-files=all 2>/dev/null || true)"
  if [ -n "${status}" ]; then
    echo "Blocked: local changes: ${source_id}" >&2
    return 2
  fi
  return 0
}

source_fetch_candidate() {
  local source_id="${1:-}" source_dir revision
  source_dir="$(_operations_repo)/$(_operations_source_path "${source_id}")" || return 1
  [ -d "${source_dir}" ] || return 1
  git -C "${source_dir}" fetch --quiet --depth 1 origin || return 2
  revision="$(git -C "${source_dir}" rev-parse --verify origin/HEAD 2>/dev/null || git -C "${source_dir}" rev-parse --verify HEAD 2>/dev/null || true)"
  [ -n "${revision}" ] || return 2
  printf '%s\n' "${revision}"
}

source_validate_candidate() {
  local source_id="${1:-}" revision="${2:-}" row skill_id entrypoint active source_id_row source_dir skill_file candidate_content
  [ -n "${source_id}" ] || return 2
  source_dir="$(_operations_repo)/$(_operations_source_path "${source_id}")" || return 1
  [ -d "${source_dir}" ] || return 1
  while IFS= read -r row || [ -n "${row}" ]; do
    [ -n "${row}" ] || continue
    IFS="	" read -r skill_id _ source_id_row entrypoint active <<EOF
${row}
EOF
    [ "${source_id_row}" = "${source_id}" ] && [ "${active}" = 1 ] || continue
    skill_file="${source_dir}/${entrypoint}"
    if [ -n "${revision}" ] && git -C "${source_dir}" cat-file -e "${revision}:${entrypoint}" 2>/dev/null; then
      candidate_content="$(git -C "${source_dir}" show "${revision}:${entrypoint}" 2>/dev/null || true)"
      [ -n "${candidate_content//[[:space:]]/}" ] || { echo "Failed: validation: ${skill_id}" >&2; return 1; }
    else
      [ -s "${skill_file}" ] || { echo "Failed: validation: ${skill_id}" >&2; return 1; }
    fi
  done <<EOF
$(catalog_skills 2>/dev/null || true)
EOF
  return 0
}

source_activate_candidate() {
  local source_id="${1:-}" revision="${2:-}" source_dir current
  source_dir="$(_operations_repo)/$(_operations_source_path "${source_id}")" || return 1
  [ -d "${source_dir}" ] || return 1
  current="$(git -C "${source_dir}" rev-parse --verify HEAD 2>/dev/null || true)"
  [ -n "${revision}" ] || return 2
  [ "${current}" = "${revision}" ] && return 0
  source_preflight "${source_id}" >/dev/null || return $?
  git -C "${source_dir}" checkout --detach "${revision}" >/dev/null 2>&1 || return 1
}

second_brain_sync() {
  local dir="${HAWS_SECOND_BRAIN_DIR:-$(_operations_repo)/secondbrain}" revision
  if [ "${HAWS_SECOND_BRAIN_ENABLED:-${SECOND_BRAIN_ENABLED:-off}}" != on ]; then
    sync_result_write secondbrain Disabled - "Second Brain is disabled" || true
    echo "Second Brain: Disabled"
    return 0
  fi
  [ -d "${dir}" ] || { sync_result_write secondbrain "Offline / timeout" - "Second Brain checkout unavailable" || true; echo "Second Brain: Offline / timeout"; return 0; }
  git -C "${dir}" fetch --quiet origin || { sync_result_write secondbrain "Offline / timeout" - "remote fetch failed" || true; echo "Second Brain: Offline / timeout"; return 0; }
  revision="$(git -C "${dir}" rev-parse --verify HEAD 2>/dev/null || printf '%s' -)"
  sync_result_write secondbrain "Up to date" "${revision}" "Second Brain remote checked" || true
  echo "Second Brain: Up to date"
}

_sync_interrupt() {
  sync_lock_release >/dev/null 2>&1 || true
  HAWS_SYNC_LOCK_ACQUIRED=0
  exit 130
}

sync_target() {
  local target="${1:-}" revision current status
  [ -n "${target}" ] || return 2
  if [ "${target}" = secondbrain ]; then second_brain_sync; return $?; fi
  if [ "${HAWS_AUTO_UPDATE:-${AUTO_UPDATE:-on}}" != on ]; then
    sync_result_write "${target}" Disabled - "Auto Update is disabled" || true
    echo "${target}: Disabled"
    return 0
  fi
  if [ "${target}" = haws ]; then
    git -C "$(_operations_repo)" fetch --quiet origin || { sync_result_write haws "Offline / timeout" - "remote fetch failed" || true; echo "HAWS: Offline / timeout"; return 0; }
    current="$(git -C "$(_operations_repo)" rev-parse --verify HEAD 2>/dev/null || printf '%s' -)"
    sync_result_write haws "Up to date" "${current}" "HAWS remote checked" || true
    echo "HAWS: Up to date"
    return 0
  fi
  status=0; source_preflight "${target}" >/dev/null 2>&1 || status=$?
  case "${status}" in
    2) sync_result_write "${target}" "Blocked: local changes" - "source has staged, unstaged, or untracked changes" || true; echo "${target}: Blocked: local changes"; return 0 ;;
    3) sync_result_write "${target}" "Skipped: no active skills" - "source has no active skills" || true; echo "${target}: Skipped: no active skills"; return 0 ;;
    4) sync_result_write "${target}" "Offline / timeout" - "source checkout unavailable" || true; echo "${target}: Offline / timeout"; return 0 ;;
    0) ;;
    *) sync_result_write "${target}" "Failed: validation" - "source preflight failed" || true; return 0 ;;
  esac
  revision="$(source_fetch_candidate "${target}" 2>/dev/null || true)"
  [ -n "${revision}" ] || { sync_result_write "${target}" "Offline / timeout" - "candidate fetch failed" || true; echo "${target}: Offline / timeout"; return 0; }
  source_validate_candidate "${target}" "${revision}" >/dev/null 2>&1 || { sync_result_write "${target}" "Failed: validation" "${revision}" "active skill entrypoint is invalid" || true; echo "${target}: Failed: validation"; return 0; }
  current="$(_operations_source_revision "${target}" 2>/dev/null || printf '%s' -)"
  if [ "${current}" = "${revision}" ]; then
    sync_result_write "${target}" "Up to date" "${revision}" "candidate matches active revision" || true
    echo "${target}: Up to date"
    return 0
  fi
  source_activate_candidate "${target}" "${revision}" || { sync_result_write "${target}" "Failed: validation" "${revision}" "candidate activation failed" || true; echo "${target}: Failed: validation"; return 0; }
  sync_result_write "${target}" Updated "${revision}" "validated candidate activated" || true
  echo "${target}: Updated"
}

sync_run() {
  local target row source_id status=0
  if [ "${1:-}" = --recover-lock ]; then sync_lock_release --recover; return $?; fi
  state_init || return $?
  sync_lock_acquire || return $?
  HAWS_SYNC_LOCK_ACQUIRED=1
  export HAWS_SYNC_LOCK_ACQUIRED
  trap 'if [ "${HAWS_SYNC_LOCK_ACQUIRED:-0}" -eq 1 ]; then sync_lock_release >/dev/null 2>&1 || true; HAWS_SYNC_LOCK_ACQUIRED=0; fi' EXIT
  trap _sync_interrupt INT TERM
  settings_load || return $?
  if [ "${HAWS_AUTO_UPDATE}" != on ] && [ "${HAWS_SECOND_BRAIN_ENABLED}" != on ]; then
    echo "No remote targets enabled"
    sync_result_write sync "Disabled" - "No remote targets enabled" || true
    sync_lock_release >/dev/null 2>&1 || true
    HAWS_SYNC_LOCK_ACQUIRED=0; trap - EXIT INT TERM
    return 0
  fi
  if [ "${HAWS_AUTO_UPDATE}" = on ]; then
    sync_target haws || status=1
    while IFS= read -r row || [ -n "${row}" ]; do
      [ -n "${row}" ] || continue
      IFS="	" read -r source_id _ _ _ <<EOF
${row}
EOF
      sync_target "${source_id}" || status=1
    done <<EOF
$(catalog_sources 2>/dev/null || true)
EOF
  else
    echo "Auto Update: Disabled"
  fi
  if [ "${HAWS_SECOND_BRAIN_ENABLED}" = on ]; then second_brain_sync || status=1; else echo "Second Brain: Disabled"; fi
  sync_lock_release >/dev/null 2>&1 || true
  HAWS_SYNC_LOCK_ACQUIRED=0
  trap - EXIT INT TERM
  return "${status}"
}

_uninstall_group_name() {
  case "$1" in
    pointers|environments) printf '%s\n' environments ;;
    skills) printf '%s\n' skills ;;
    agents) printf '%s\n' agents ;;
    hooks) printf '%s\n' hooks ;;
    metadata) printf '%s\n' metadata ;;
    *) return 1 ;;
  esac
}

uninstall_plan() {
  local groups="${1:-pointers,skills,agents,hooks,metadata}" group mapped line output
  output="${HAWS_UNINSTALL_PLAN:-$(_operations_state)/uninstall.plan}"
  mkdir -p "$(dirname "${output}")" || return 1
  : > "${output}" || return 1
  groups="${groups// /,}"
  IFS=',' read -r -a _uninstall_groups <<< "${groups}"
  for group in "${_uninstall_groups[@]}"; do
    mapped="$(_uninstall_group_name "${group}" 2>/dev/null || true)"
    [ -n "${mapped}" ] || continue
    while IFS= read -r line || [ -n "${line}" ]; do
      [ -n "${line}" ] || continue
      printf 'remove\t%s\n' "${line}" >> "${output}"
    done <<EOF
$(ownership_list "${mapped}")
EOF
  done
  printf '%s\n' "${output}"
}

ownership_verify() {
  local record="${1:-}" group kind path source fingerprint actual
  IFS=$'\t' read -r group kind path source fingerprint <<EOF
${record}
EOF
  [ -n "${kind}" ] && [ -n "${path}" ] || return 2
  if [ "${kind}" = symlink ]; then
    [ -L "${path}" ] || return 1
    [ "$(canonical_path "${path}")" = "${source}" ] || return 1
    return 0
  fi
  if [ "${kind}" = generated-file ] || [ "${kind}" = file ]; then
    [ -f "${path}" ] || return 1
    actual="$(_haws_sha256 "${path}")"
    [ -n "${fingerprint}" ] && [ "${actual}" = "${fingerprint}" ] || return 1
    return 0
  fi
  [ -e "${path}" ] || [ -L "${path}" ]
}

_ownership_remove_record() {
  local record="$1" group kind path file temp
  IFS=$'\t' read -r group kind path _ _ <<EOF
${record}
EOF
  file="$(_operations_state)/ownership.tsv"; temp="${file}.stage.$$"
  [ -f "${file}" ] || return 0
  awk -F $'\t' -v g="${group}" -v k="${kind}" -v p="${path}" '!($1==g && $2==k && $3==p)' "${file}" > "${temp}" || { rm -f "${temp}"; return 1; }
  atomic_replace "${temp}" "${file}"; local result=$?; rm -f "${temp}"; return "${result}"
}

uninstall_preview() {
  local plan="${1:-}" action record
  [ -f "${plan}" ] || return 1
  echo "Uninstall preview"
  while IFS=$'\t' read -r action record || [ -n "${action}" ]; do
    [ "${action}" = remove ] || continue
    if ownership_verify "${record}"; then
      IFS=$'\t' read -r _ _ path _ _ <<EOF
${record}
EOF
      printf 'Remove\t%s\n' "${path}"
    else
      IFS=$'\t' read -r _ _ path _ _ <<EOF
${record}
EOF
      printf 'Preserved\t%s\tmodified, shared, or unproven\n' "${path}"
    fi
  done < "${plan}"
}

uninstall_apply() {
  local plan="${1:-}" action record path
  [ -f "${plan}" ] || return 1
  while IFS=$'\t' read -r action record || [ -n "${action}" ]; do
    [ "${action}" = remove ] || continue
    IFS=$'\t' read -r _ _ path _ _ <<EOF
${record}
EOF
    if ownership_verify "${record}"; then
      if [ -d "${path}" ] && [ ! -L "${path}" ]; then rmdir "${path}" 2>/dev/null || true; else rm -f "${path}"; fi
      if [ ! -e "${path}" ] && [ ! -L "${path}" ]; then
        _ownership_remove_record "${record}" || return 1
        printf 'Removed\t%s\n' "${path}"
      else
        printf 'Preserved\t%s\tremoval verification failed\n' "${path}"
      fi
    else
      printf 'Preserved\t%s\tmodified, shared, or unproven\n' "${path}"
    fi
  done < "${plan}"
}

uninstall_run() {
  local groups="${1:-pointers,skills,agents,hooks,metadata}" plan key
  state_init || return $?
  plan="$(uninstall_plan "${groups}")" || return 1
  uninstall_preview "${plan}"
  if [ -n "${HAWS_TEST_KEYS:-}" ]; then
    key="${HAWS_TEST_KEYS%%,*}"
    case "${key}" in yes|y|confirm|apply) uninstall_apply "${plan}"; return $? ;; *) echo "Cancelled. No changes saved."; return 1 ;; esac
  fi
  echo "Confirm uninstall? [yes/no]"
  ui_next_key >/dev/null 2>&1 || return 1
  case "${UI_LAST_KEY:-}" in yes|y|confirm|apply) uninstall_apply "${plan}" ;; *) echo "Cancelled. No changes saved."; return 1 ;; esac
}
