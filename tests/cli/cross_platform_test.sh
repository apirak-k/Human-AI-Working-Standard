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
  ! rg -n 'SETUP\.bat|1-CLICK-SYNC\.bat' --glob '!docs/superpowers/**' --glob '!README.md' --glob '!HANDOFF.md' --glob '!tests/cli/cross_platform_test.sh' "${PROJECT_ROOT}" >/dev/null 2>&1
}

test_bare_launcher_never_dispatches_sync() {
  new_fixture
  export HAWS_TEST_KEYS=cancel
  run_haws || true
  assert_no_call 'fetch' || return 1
  assert_no_call 'submodule update'
}

run_test() { local name="$1"; if "$name"; then echo "PASS ${name}"; passed=$((passed + 1)); else echo "FAIL ${name}"; failed=$((failed + 1)); fi; cleanup_fixture; }
trap cleanup_fixture EXIT
run_test test_same_command_surface
run_test test_public_flow_has_no_bat_launcher_reference
run_test test_bare_launcher_never_dispatches_sync
echo "CLI cross-platform tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
