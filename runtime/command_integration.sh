#!/usr/bin/env bash
# Ownership-aware native-terminal command integration.

command_integration_platform() { printf '%s\n' "${HAWS_COMMAND_PLATFORM:-$(platform_id)}"; }
_command_integration_state_dir() { printf '%s\n' "${HAWS_STATE_DIR:-${HAWS_REPO_DIR:-${SCRIPT_DIR:-$(pwd)}}/.haws/state}"; }
_command_integration_profile() { printf '%s\n' "${HAWS_COMMAND_PROFILE:-${HOME}/.bashrc}"; }
_COMMAND_INTEGRATION_MARKER_START='# HAWS command integration START'
_COMMAND_INTEGRATION_MARKER_END='# HAWS command integration END'

_command_integration_windows_file() {
  printf '%s\n' "${HAWS_COMMAND_AUTORUN_FILE:-$(_command_integration_state_dir)/windows-autorun.txt}"
}

_command_integration_uses_fixture_file() { [ -n "${HAWS_COMMAND_AUTORUN_FILE:-}" ] || [ -n "${HAWS_TEST_KEYS:-}" ]; }

_command_integration_windows_prior_file() { printf '%s\n' "$(_command_integration_state_dir)/windows-autorun-prior.txt"; }

_command_integration_windows_read() {
  # Fixture tests inject a plain file. Production reads the per-user value only.
  if _command_integration_uses_fixture_file; then file="$(_command_integration_windows_file)"; [ -f "${file}" ] && cat "${file}"; return 0; fi
  reg.exe query 'HKCU\Software\Microsoft\Command Processor' /v AutoRun 2>/dev/null | awk 'BEGIN{found=0} /AutoRun/{sub(/^[^A]*AutoRun[[:space:]]+REG_SZ[[:space:]]*/, ""); print; found=1} END{exit found ? 0 : 1}'
}

_command_integration_windows_write() {
  local value="$1"
  if _command_integration_uses_fixture_file; then file="$(_command_integration_windows_file)"; mkdir -p "$(dirname "${file}")" && printf '%s\n' "${value}" > "${file}"; return; fi
  reg.exe add 'HKCU\Software\Microsoft\Command Processor' /v AutoRun /t REG_SZ /d "${value}" /f >/dev/null
}

_command_integration_windows_delete() {
  if _command_integration_uses_fixture_file; then rm -f "$(_command_integration_windows_file)"; return; fi
  reg.exe delete 'HKCU\Software\Microsoft\Command Processor' /v AutoRun /f >/dev/null 2>&1 || true
}

command_integration_plan() {
  local output="${1:-${HAWS_COMMAND_PLAN:-$(_command_integration_state_dir)/command-integration.plan}}" platform bash_path profile existing
  mkdir -p "$(dirname "${output}")" || return 1
  : > "${output}" || return 1
  platform="$(command_integration_platform)"
  case "${platform}" in
    windows*)
      bash_path="${HAWS_GIT_BASH_PATH:-$(command -v bash.exe 2>/dev/null || command -v bash 2>/dev/null || true)}"
      if [ -z "${bash_path}" ]; then printf 'command-access\tblocked\tBash is unavailable\n' >> "${output}"; else printf 'command-access\tready\t%s\n' "${bash_path}" >> "${output}"; fi
      _command_integration_uses_fixture_file && printf 'windows-autorun\t%s\n' "$(_command_integration_windows_file)" >> "${output}" || printf 'windows-autorun\tHKCU\\Software\\Microsoft\\Command Processor\\AutoRun\n' >> "${output}" ;;
    macos|linux|*)
      profile="$(_command_integration_profile)"
      printf 'command-access\tready\t%s\n' "${profile}" >> "${output}"
      printf 'shell-profile\t%s\n' "${profile}" >> "${output}" ;;
  esac
  printf '%s\n' "${output}"
}

command_integration_apply() {
  local plan="${1:-}" platform bash_path file profile block old prior macro
  [ -f "${plan}" ] || return 1
  platform="$(command_integration_platform)"
  if grep -q $'^command-access\tblocked\t' "${plan}"; then echo "Blocked: Bash is unavailable"; return 2; fi
  if [[ "${platform}" == windows* ]]; then
    file="$(_command_integration_windows_prior_file)"; mkdir -p "$(dirname "${file}")" || return 1
    old="$(_command_integration_windows_read || true)"
    if ! grep -q 'doskey haws=' <<<"${old}"; then
      [ -f "${file}" ] || { if [ -n "${old}" ]; then printf 'present\n%s\n' "${old}" > "${file}"; else printf 'absent\n' > "${file}"; fi; }
      macro="doskey haws=\"${HAWS_GIT_BASH_PATH:-bash.exe}\" \"${HAWS_REPO_DIR:-${SCRIPT_DIR}}/haws.sh\" \$*"
      [ -n "${old}" ] && macro="${old} & ${macro}"
      _command_integration_windows_write "${macro}" || return 1
    fi
    ownership_record command registry 'HKCU\Software\Microsoft\Command Processor\AutoRun' command-integration "haws" || return 1
  else
    profile="$(_command_integration_profile)"; mkdir -p "$(dirname "${profile}")" || return 1
    if ! grep -qF "${_COMMAND_INTEGRATION_MARKER_START}" "${profile}" 2>/dev/null; then
      block="${_COMMAND_INTEGRATION_MARKER_START}\nhaws() { bash \"${HAWS_REPO_DIR:-${SCRIPT_DIR}}/haws.sh\" \"$@\"; }\n${_COMMAND_INTEGRATION_MARKER_END}"
      printf '%s\n' "${block}" >> "${profile}" || return 1
    fi
    ownership_record command file "${profile}" command-integration "${_COMMAND_INTEGRATION_MARKER_START}" || return 1
  fi
}

command_integration_remove() {
  local platform="$(command_integration_platform)" file profile tmp prior marker value
  if [[ "${platform}" == windows* ]]; then
    prior="$(_command_integration_windows_prior_file)"; [ -f "${prior}" ] || return 0
    IFS= read -r marker < "${prior}" || return 1
    if [ "${marker}" = present ]; then value="$(tail -n +2 "${prior}")"; _command_integration_windows_write "${value}" || return 1; else _command_integration_windows_delete; fi
    rm -f "${prior}"
  else
    profile="$(_command_integration_profile)"; [ -f "${profile}" ] || return 0
    tmp="${profile}.tmp.$$"
    awk -v start="${_COMMAND_INTEGRATION_MARKER_START}" -v end="${_COMMAND_INTEGRATION_MARKER_END}" '$0==start {skip=1; next} $0==end {skip=0; next} !skip {print}' "${profile}" > "${tmp}" && mv -f "${tmp}" "${profile}"
  fi
}
