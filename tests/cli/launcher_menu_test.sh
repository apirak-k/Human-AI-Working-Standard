#!/usr/bin/env bash
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${TEST_DIR}/test_helper.sh"

passed=0
failed=0
trap cleanup_fixture EXIT

test_launcher_is_thin() {
    [ -f "${PROJECT_ROOT}/haws.bat" ] || return 1
    grep -F 'haws.sh' "${PROJECT_ROOT}/haws.bat" >/dev/null || return 1
    ! grep -iE 'run_sync|run_setup|run_doctor|git submodule' "${PROJECT_ROOT}/haws.bat" >/dev/null
}

test_main_menu_reuses_old_interaction_engine() {
    local source="${PROJECT_ROOT}/haws.sh"
    local main_block

    grep -q '^interactive_menu()' "${source}" || return 1
    grep -Fq 'interactive_menu checklist' "${source}" || return 1
    grep -Fq 'interactive_menu menu' "${source}" || return 1

    main_block="$(sed -n '/^run_main_menu() {/,/^case "${COMMAND}"/p' "${source}")"
    ! printf '%s\n' "${main_block}" | grep -F 'read -rsn1' >/dev/null || return 1
    ! printf '%s\n' "${main_block}" | grep -F 'render_main_menu' >/dev/null || return 1
    ! grep -Fq '\033[H\033[2J' "${source}" || return 1
    [ "$(grep -Fc 'read -rsn1' "${source}")" -eq 1 ] || return 1
    grep -Fq 'printf "\033[?25l"' "${source}" || return 1
    grep -Fq 'printf "\033[%dA"' "${source}" || return 1
    grep -Fq 'printf "\033[2K\r' "${source}" || return 1
    grep -Fq 'printf "\033[?25h"' "${source}"
}

test_bare_q_shows_menu_without_home_mutation() {
    grep -q '^run_main_menu()' "${PROJECT_ROOT}/haws.sh" || return 1
    printf 'q' | HOME="${FIXTURE_HOME}" bash "${PROJECT_ROOT}/haws.sh" menu >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'HAWS — Main Menu' || return 1
    assert_output_contains 'Skills' || return 1
    assert_output_contains 'Repositories' || return 1
    assert_output_contains 'Second Brain' || return 1
    assert_output_contains 'Sync' || return 1
    assert_output_contains 'Status' || return 1
    assert_output_contains 'Doctor' || return 1
    assert_output_contains 'Uninstall' || return 1
    assert_output_contains 'Exit' || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest" || return 1
    printf 'Q' | HOME="${FIXTURE_HOME}" bash "${PROJECT_ROOT}/haws.sh" menu >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'HAWS — Main Menu' || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest"
}

test_bare_eof_exits_without_home_mutation() {
    grep -q '^run_main_menu()' "${PROJECT_ROOT}/haws.sh" || return 1
    HOME="${FIXTURE_HOME}" bash "${PROJECT_ROOT}/haws.sh" menu </dev/null >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'HAWS — Main Menu' || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest"
}

test_skills_keeps_old_categories_and_controls() {
    grep -q '^run_main_menu()' "${FIXTURE_PROJECT}/haws.sh" || return 1
    printf '\n1\nq0\nq' | HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" menu >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'Single Skills' || return 1
    assert_output_contains 'Multi-Skill Packs' || return 1
    assert_output_contains '[Space] Toggle' || return 1
    assert_output_contains '[Enter] Confirm & Save'
}

test_arrow_space_enter_updates_only_fixture() {
    grep -q '^run_main_menu()' "${FIXTURE_PROJECT}/haws.sh" || return 1
    printf '\n1\n\033[B \n0\nq' | HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" menu >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_file_contains "${FIXTURE_PROJECT}/skills.disabled" 'demo-one' || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest"
}

test_checklist_eof_cancels_without_saving() {
    grep -q '^run_main_menu()' "${FIXTURE_PROJECT}/haws.sh" || return 1
    printf '\n1\n\033[B ' | HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" menu >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'Configuration cancelled. No changes saved.' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/skills.disabled"
}

test_exit_selection_does_not_dispatch_an_action() {
    {
        local i
        for ((i=0; i<7; i++)); do printf '\033[B'; done
        printf '\n'
    } | HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" menu >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains '> Exit' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/skills.disabled" || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest"
}

run_test test_launcher_is_thin
run_test test_main_menu_reuses_old_interaction_engine
run_test test_bare_q_shows_menu_without_home_mutation
run_test test_bare_eof_exits_without_home_mutation
run_test test_skills_keeps_old_categories_and_controls
run_test test_arrow_space_enter_updates_only_fixture
run_test test_checklist_eof_cancels_without_saving
run_test test_exit_selection_does_not_dispatch_an_action

echo "Batch 1 launcher/menu tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
