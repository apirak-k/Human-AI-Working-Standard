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
    grep -F 'title HAWS — Human-AI Working Standard' "${PROJECT_ROOT}/haws.bat" >/dev/null || return 1
    grep -F 'if "%HAWS_BARE%"=="1" set "HAWS_PAUSE=1"' "${PROJECT_ROOT}/haws.bat" >/dev/null || return 1
    grep -F 'if /i "%~1"=="sync" set "HAWS_PAUSE=1"' "${PROJECT_ROOT}/haws.bat" >/dev/null || return 1
    ! grep -iE 'run_sync|run_setup|run_doctor|git submodule' "${PROJECT_ROOT}/haws.bat" >/dev/null
}

test_single_entrypoint_reuses_old_interaction_engine() {
    local source="${PROJECT_ROOT}/haws.sh"

    grep -q '^interactive_menu()' "${source}" || return 1
    grep -Fq 'interactive_menu checklist' "${source}" || return 1
    grep -Fq 'interactive_menu menu' "${source}" || return 1
    ! grep -q '^run_main_menu()' "${source}" || return 1
    ! grep -Fq '\033[H\033[2J' "${source}" || return 1
    [ "$(grep -Fc 'read -rsn1' "${source}")" -ge 1 ] || return 1
    grep -Fq 'printf "\033[?25l"' "${source}" || return 1
    grep -Fq 'printf "\033[%dA"' "${source}" || return 1
    grep -Fq 'printf "\033[2K\r' "${source}" || return 1
    grep -Fq 'printf "\033[?25h"' "${source}"
}

test_help_aliases_exit_successfully() {
    local command
    for command in help --help -h; do
        if ! HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" "${command}" >"${OUTPUT_FILE}" 2>&1; then
            return 1
        fi
        assert_output_contains 'Usage:' || return 1
        ! grep -F 'notify' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    done
}

test_notify_command_is_removed() {
    if HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" notify >"${OUTPUT_FILE}" 2>&1; then
        return 1
    fi
    assert_output_contains 'Usage:' || return 1
    ! grep -F 'tools/notify.sh' "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_home_navigation_has_no_exit_row() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema_version\t1\nauto_update\ton\n' \
        > "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    printf 'schema=1\tcompleted_at=fixture\n' \
        > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    printf 'q' |
        HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" menu >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'HAWS Home' || return 1
    ! grep -F '> Exit' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest"
}

test_menu_and_bare_launch_use_the_same_home() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema_version\t1\nauto_update\ton\n' \
        > "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    printf 'schema=1\tcompleted_at=fixture\n' \
        > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    printf 'q' | HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" menu >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'HAWS Home' || return 1
    assert_output_contains 'Sync' || return 1
    assert_output_contains 'Doctor' || return 1
    assert_output_contains 'Uninstall' || return 1
    ! grep -F '> Exit' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    assert_output_contains 'Run explicit synchronization' || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest" || return 1
    printf 'Q' | HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'HAWS Home' || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest"
}

test_home_has_purpose_and_context_controls() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema_version\t1\nauto_update\ton\n' \
        > "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    printf 'schema=1\tcompleted_at=fixture\n' \
        > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    printf 'q' | HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" menu >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'Run explicit synchronization' || return 1
    assert_output_contains 'Controls: [Up/Down] Move | [Enter] Select | [Q] Exit'
}

test_home_shows_local_status_without_health_page() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema_version\t1\nsecond_brain\toff\nauto_update\toff\n' \
        > "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    printf 'schema=1\tcompleted_at=now\n' \
        > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    printf 'q' |
        HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'CURRENT STATUS' || return 1
    assert_output_contains 'Last Sync' || return 1
    assert_output_contains 'Never' || return 1
    assert_output_contains 'Auto Update' || return 1
    assert_output_contains 'Second Brain' || return 1
    ! grep -F 'Diagnostics' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    ! grep -F 'Overall' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    ! grep -F 'HAWS Health' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    ! grep -F 'FINDINGS' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    ! grep -F '[PASS]' "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_home_has_one_header_and_settings_back_is_silent() {
    local source="${PROJECT_ROOT}/haws.sh"
    [ "$(grep -c 'HAWS HOME' "${source}")" -ge 1 ] || return 1
    ! grep -Fq 'Back to caller.' "${source}" || return 1
    grep -Fq 'HAWS_MENU_SUPPRESS_HEADER' "${source}" || return 1
}

test_menu_descriptions_use_a_shared_label_column() {
    local source="${PROJECT_ROOT}/haws.sh"
    grep -Fq 'menu_label_width' "${source}" || return 1
    grep -Fq '%-*s' "${source}"
}

test_checklist_redraws_rows_and_footer_as_one_frame() {
    local source="${PROJECT_ROOT}/haws.sh"
    grep -Fq 'if [ "${mode}" = "checklist" ] || [ "${mode}" = "menu" ] || [ "${mode}" = "settings" ]; then' "${source}" || return 1
    grep -Fq 'redraw_rows=$((total + 2))' "${source}" || return 1
}

test_bare_eof_exits_without_home_mutation() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema_version\t1\nauto_update\ton\n' \
        > "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    printf 'schema=1\tcompleted_at=fixture\n' \
        > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    HOME="${FIXTURE_HOME}" bash "${FIXTURE_HOME}/../project/haws.sh" menu </dev/null >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'HAWS Home' || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest"
}

prepare_fixture_skill_source() {
    printf '%s\n' \
        '[submodule "demo-pack"]' \
        $'\tpath = skills/packs/demo-pack' \
        $'\turl = https://example.invalid/demo-pack.git' \
        > "${FIXTURE_PROJECT}/.gitmodules"
}

test_skills_keeps_old_categories_and_controls() {
    prepare_fixture_skill_source
    printf '\n1\nq0\nq' | HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" skills >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'Single Skills' || return 1
    assert_output_contains 'Multi-Skill Packs' || return 1
    assert_output_contains '[Space] Toggle' || return 1
    assert_output_contains '[Enter] Confirm & Save'
}

test_skills_category_accepts_arrow_enter() {
    prepare_fixture_skill_source
    local down=$'\033[B'
    local input="${down}\n\nq"
    printf '%b' "${input}" |
        HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" skills >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'Select a Skill Pack to configure' || return 1
    assert_output_contains 'Configure Skills in demo-pack'
}

test_arrow_space_enter_updates_only_fixture() {
    prepare_fixture_skill_source
    local down=$'\033[B'
    printf '%b' "${down}\n\n${down} \n\nq" |
        HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" skills >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_file_contains "${FIXTURE_PROJECT}/skills/skills.disabled" 'demo-alpha' || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest"
}

test_skills_pack_q_returns_to_category_menu() {
    prepare_fixture_skill_source
    local down=$'\033[B'
    printf '%b' "${down}q" |
        HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" skills >"${OUTPUT_FILE}" 2>&1 || return 1
    [ "$(grep -c 'Configure Active Skills' "${OUTPUT_FILE}")" -eq 1 ] || return 1
    ! grep -F 'HAWS — Main Menu' "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_checklist_eof_cancels_without_saving() {
    prepare_fixture_skill_source
    local down=$'\033[B'
    printf '%b' "${down}\n\n${down} " |
        HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" skills >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'Configuration cancelled. No changes saved.' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/skills.disabled"
}

test_q_exits_without_an_exit_row() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema_version\t1\nauto_update\ton\n' \
        > "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    printf 'schema=1\tcompleted_at=fixture\n' \
        > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    printf 'q' | HOME="${FIXTURE_HOME}" bash "${FIXTURE_PROJECT}/haws.sh" menu >"${OUTPUT_FILE}" 2>&1 || return 1
    ! grep -F '> Exit' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/skills.disabled" || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest"
}

run_test test_launcher_is_thin
run_test test_single_entrypoint_reuses_old_interaction_engine
run_test test_help_aliases_exit_successfully
run_test test_notify_command_is_removed
run_test test_home_navigation_has_no_exit_row
run_test test_menu_and_bare_launch_use_the_same_home
run_test test_home_has_purpose_and_context_controls
run_test test_home_shows_local_status_without_health_page
run_test test_menu_descriptions_use_a_shared_label_column
run_test test_checklist_redraws_rows_and_footer_as_one_frame
run_test test_bare_eof_exits_without_home_mutation
run_test test_skills_keeps_old_categories_and_controls
run_test test_skills_category_accepts_arrow_enter
run_test test_arrow_space_enter_updates_only_fixture
run_test test_skills_pack_q_returns_to_category_menu
run_test test_checklist_eof_cancels_without_saving
run_test test_q_exits_without_an_exit_row

echo "Batch 1 launcher/menu tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
