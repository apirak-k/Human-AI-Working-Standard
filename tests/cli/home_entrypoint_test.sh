#!/usr/bin/env bash
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${TEST_DIR}/test_helper.sh"

passed=0
failed=0
trap cleanup_fixture EXIT

seed_installed_state() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema_version\t1\nauto_update\ton\n' \
        > "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    printf 'schema=1\tcompleted_at=fixture\n' \
        > "${FIXTURE_PROJECT}/.haws/state/install.complete"
}

test_explicit_menu_uses_home_entrypoint() {
    seed_installed_state
    printf 'q' | HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" menu >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'HAWS Home' || return 1
    assert_output_contains 'Sync' || return 1
    assert_output_contains 'Settings' || return 1
    assert_output_contains 'Doctor' || return 1
    assert_output_contains 'Uninstall' || return 1
    ! grep -F 'HAWS — Main Menu' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    ! grep -F 'Health|Show current status and diagnostic reasons' "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_bare_launch_shows_home_and_loads_status_before_summary() {
    seed_installed_state
    printf 'q' | HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'HAWS Home' || return 1
    assert_output_contains '[*] Loading current status, please wait...' || return 1
    assert_output_contains 'CURRENT STATUS' || return 1
    ! grep -F 'HAWS Health' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    ! grep -F 'FINDINGS' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    local loading_line status_line
    loading_line="$(grep -nF '[*] Loading current status, please wait...' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    status_line="$(grep -nF 'CURRENT STATUS' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    [ -n "${loading_line}" ] && [ -n "${status_line}" ] && [ "${loading_line}" -lt "${status_line}" ]
}

test_main_menu_is_not_a_second_user_facing_entrypoint() {
    ! grep -q '^run_main_menu()' "${PROJECT_ROOT}/haws.sh"
}

run_test test_explicit_menu_uses_home_entrypoint
run_test test_bare_launch_shows_home_and_loads_status_before_summary
run_test test_main_menu_is_not_a_second_user_facing_entrypoint

echo "Single-entry Home tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
