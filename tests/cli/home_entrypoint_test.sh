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

test_bare_launch_opens_home_from_local_state() {
    seed_installed_state
    printf '2026-09-15T00:00:00Z\thaws\tUp to date\tabc123\tlocal check\n' \
        > "${FIXTURE_PROJECT}/.haws/state/sync-state.tsv"
    printf 'q' | HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'HAWS Home' || return 1
    assert_output_contains 'Last Sync' || return 1
    assert_output_contains 'Up to date' || return 1
    assert_output_contains 'Auto Update' || return 1
    assert_output_contains 'Second Brain' || return 1
    assert_output_contains 'Use Doctor for full diagnostics' || return 1
    ! grep -F '[*] Loading current status, please wait...' "${OUTPUT_FILE}" >/dev/null 2>&1
}

source_haws() {
    export HOME="${FIXTURE_HOME}"
    export HAWS_REPO_DIR="${FIXTURE_PROJECT}"
    export HAWS_STATE_DIR="${FIXTURE_PROJECT}/.haws/state"
    export HAWS_SOURCE_ONLY=1
    . "${FIXTURE_PROJECT}/haws.sh"
    unset HAWS_SOURCE_ONLY
}

test_home_does_not_run_full_health_scan_before_menu() {
    seed_installed_state
    source_haws || return 1
    local scan_log="${FIXTURE_ROOT}/forbidden-home-scan.log"
    _health_collect() {
        printf 'health\n' >> "${scan_log}"
        HAWS_HEALTH_FINDINGS=""
        HAWS_HEALTH_SKILLS_ACTIVE=0
        HAWS_HEALTH_SKILLS_TOTAL=0
        return 0
    }
    disabled_environments_load() { printf 'environments\n' >> "${scan_log}"; return 0; }
    load_disabled_skills() { printf 'skills\n' >> "${scan_log}"; return 0; }
    catalog_sources() { printf 'sources\n' >> "${scan_log}"; return 0; }
    catalog_skills() { printf 'catalog\n' >> "${scan_log}"; return 0; }
    ownership_list() { printf 'ownership-list\n' >> "${scan_log}"; return 0; }
    ownership_verify() { printf 'ownership-verify\n' >> "${scan_log}"; return 0; }

    printf 'q' | home_run >"${OUTPUT_FILE}" 2>&1 || return 1
    [ ! -e "${scan_log}" ]
}

test_main_menu_is_not_a_second_user_facing_entrypoint() {
    ! grep -q '^run_main_menu()' "${PROJECT_ROOT}/haws.sh"
}

run_test test_explicit_menu_uses_home_entrypoint
run_test test_bare_launch_opens_home_from_local_state
run_test test_home_does_not_run_full_health_scan_before_menu
run_test test_main_menu_is_not_a_second_user_facing_entrypoint

echo "Single-entry Home tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
