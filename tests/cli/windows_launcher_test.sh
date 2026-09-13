#!/usr/bin/env bash
# Tests for haws.bat Windows native entrypoint static contracts.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/test_helper.sh"
passed=0
failed=0

BAT_PATH="${PROJECT_ROOT}/haws.bat"

test_bat_exists_and_nonempty() {
  [ -f "${BAT_PATH}" ] || return 1
  [ -s "${BAT_PATH}" ] || return 1
}

test_bat_contains_no_business_logic() {
  # haws.bat must be a thin launcher: no settings/sync/doctor/tui logic
  ! grep -iE "settings_run|sync_run|doctor_run|home_run|_settings_" "${BAT_PATH}" >/dev/null 2>&1 || return 1
  ! grep -iE "submodule\." "${BAT_PATH}" >/dev/null 2>&1 || return 1
}

test_bat_contains_no_blocking_pause() {
  # haws.bat must never hang headlessly: no unconditional or unhandled pause
  ! grep -iE '^[[:space:]]*pause' "${BAT_PATH}" >/dev/null 2>&1 || return 1
}

test_bat_probes_standard_git_bash_locations() {
  grep -F "ProgramFiles%\Git\bin\bash.exe" "${BAT_PATH}" >/dev/null 2>&1 || return 1
  grep -F "where bash" "${BAT_PATH}" >/dev/null 2>&1 || return 1
  grep -F "haws.sh" "${BAT_PATH}" >/dev/null 2>&1 || return 1
}

test_bat_missing_runtime_error_message() {
  grep -F "Git Bash was not found" "${BAT_PATH}" >/dev/null 2>&1 || return 1
  grep -F "https://git-scm.com/" "${BAT_PATH}" >/dev/null 2>&1 || return 1
}

test_bat_forwards_arguments_and_propagates_exit() {
  grep -F '"%BASH_CMD%" --login "%HAWS_SCRIPT%" %*' "${BAT_PATH}" >/dev/null 2>&1 || return 1
  grep -F "exit /b %HAWS_EXIT%" "${BAT_PATH}" >/dev/null 2>&1 || return 1
}

test_bat_starts_git_bash_login_shell() {
  grep -F '"%BASH_CMD%" --login "%HAWS_SCRIPT%" %*' "${BAT_PATH}" >/dev/null 2>&1
}

test_bat_starts_bare_launch_as_interactive_shell() {
  grep -F 'if "%~1"==""' "${BAT_PATH}" >/dev/null 2>&1 || return 1
  grep -F '"%BASH_CMD%" --login "%HAWS_SCRIPT%" interactive' "${BAT_PATH}" >/dev/null 2>&1 || return 1
}

run_test() { local name="$1"; if "$name"; then echo "PASS ${name}"; passed=$((passed + 1)); else echo "FAIL ${name}"; failed=$((failed + 1)); fi; cleanup_fixture; }
trap cleanup_fixture EXIT

run_test test_bat_exists_and_nonempty
run_test test_bat_contains_no_business_logic
run_test test_bat_contains_no_blocking_pause
run_test test_bat_probes_standard_git_bash_locations
run_test test_bat_missing_runtime_error_message
run_test test_bat_forwards_arguments_and_propagates_exit
run_test test_bat_starts_git_bash_login_shell
run_test test_bat_starts_bare_launch_as_interactive_shell

echo "CLI Windows launcher tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
