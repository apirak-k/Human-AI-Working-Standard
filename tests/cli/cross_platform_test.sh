#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/test_helper.sh"
passed=0
failed=0

test_same_command_surface() {
  new_fixture
  local output
  output="$(bash "${PROJECT_ROOT}/haws.sh" unknown 2>&1 || true)"
  printf '%s\n' "${output}" | grep -F 'sync' >/dev/null || return 1
  printf '%s\n' "${output}" | grep -F 'status' >/dev/null || return 1
  ! printf '%s\n' "${output}" | grep -F 'notify' >/dev/null 2>&1
}

test_public_flow_has_no_bat_launcher_reference() {
  ! rg -n 'SETUP\.bat|1-CLICK-SYNC\.bat' --glob '!docs/superpowers/**' --glob '!README.md' --glob '!HANDOFF.md' --glob '!spec.md' --glob '!HAWS-*.md' --glob '!tests/cli/cross_platform_test.sh' "${PROJECT_ROOT}" >/dev/null 2>&1
}

test_bare_launcher_never_dispatches_sync() {
  new_fixture
  export HAWS_TEST_KEYS=cancel
  run_haws || true
  assert_no_call 'fetch' || return 1
  assert_no_call 'submodule update'
}

test_parity_bat_launcher_is_pure_forwarder() {
  local bat="${PROJECT_ROOT}/haws.bat"
  [ -f "${bat}" ] || return 1
  grep -F '"%BASH_CMD%" "%HAWS_SCRIPT%" %*' "${bat}" >/dev/null 2>&1 || return 1
  ! grep -iE 'settings_run|sync_run|doctor_run|home_run' "${bat}" >/dev/null 2>&1 || return 1
}

test_parity_shared_runtime_scripts_are_lf() {
  local f
  for f in "${PROJECT_ROOT}/haws.sh" "${PROJECT_ROOT}/runtime/"*.sh; do
    [ -f "${f}" ] || continue
    if grep -q $'\r' "${f}" 2>/dev/null; then
      echo "FAIL: ${f} contains CRLF" >&2
      return 1
    fi
  done
}

run_test() { local name="$1"; if "$name"; then echo "PASS ${name}"; passed=$((passed + 1)); else echo "FAIL ${name}"; failed=$((failed + 1)); fi; cleanup_fixture; }
trap cleanup_fixture EXIT
run_test test_same_command_surface
run_test test_public_flow_has_no_bat_launcher_reference
run_test test_bare_launcher_never_dispatches_sync
run_test test_parity_bat_launcher_is_pure_forwarder
run_test test_parity_shared_runtime_scripts_are_lf
echo "CLI cross-platform tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
