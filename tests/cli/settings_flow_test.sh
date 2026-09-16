#!/usr/bin/env bash
# Setup/Home and draft-to-preview tests for the old HAWS interaction engine.
#
# UX route contract covered here:
#   Setup -> Use Default Setup -> Preview Install -> Cancel -> Setup
#   Setup -> Customize Settings -> HAWS Settings
#   Settings -> Apply -> Preview Install/Update
#   Preview -> Back to Settings preserves the draft
#   Preview -> Cancel discards the draft and returns to Setup/Home
#   completed install -> bare launch -> Home

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${TEST_DIR}/test_helper.sh"

passed=0
failed=0

run_haws_input() {
    local input="$1"
    shift
    printf '%b' "${input}" |
        env HOME="${FIXTURE_HOME}" HAWS_REPO_DIR="${FIXTURE_PROJECT}" \
            HAWS_CALL_LOG="${CALL_LOG}" PATH="${PATH}" \
            bash "${FIXTURE_PROJECT}/haws.sh" "$@" >"${OUTPUT_FILE}" 2>&1
}

run_haws_input_with_env() {
    local input="$1"
    local extra_env="$2"
    shift 2
    printf '%b' "${input}" |
        env HOME="${FIXTURE_HOME}" HAWS_REPO_DIR="${FIXTURE_PROJECT}" \
            HAWS_CALL_LOG="${CALL_LOG}" PATH="${PATH}" \
            ${extra_env} bash "${FIXTURE_PROJECT}/haws.sh" "$@" >"${OUTPUT_FILE}" 2>&1
}

assert_output_not_contains() {
    local needle="$1"
    ! grep -F -- "${needle}" "${OUTPUT_FILE}" >/dev/null 2>&1
}

seed_second_brain_with_remote() {
    local remote="${FIXTURE_ROOT}/secondbrain.git"
    local brain="${FIXTURE_PROJECT}/secondbrain"
    git init --bare -q "${remote}" || return 1
    mkdir -p "${brain}" || return 1
    git -C "${brain}" init -q || return 1
    git -C "${brain}" checkout -q -b main || return 1
    git -C "${brain}" config user.name HAWS-Test
    git -C "${brain}" config user.email test@example.invalid
    printf '%s\n' '# Preferences' > "${brain}/USER_PREFERENCES.md"
    printf '%s\n' '# Anti-patterns' > "${brain}/ANTI_PATTERNS.md"
    git -C "${brain}" add . || return 1
    git -C "${brain}" commit -q -m baseline || return 1
    git -C "${brain}" remote add origin "file://${remote}" || return 1
    git -C "${brain}" push -q -u origin main || return 1
    git --git-dir="${remote}" symbolic-ref HEAD refs/heads/main
}

test_first_use_opens_setup_without_mutation() {
    run_haws_input 'q' || return 1
    assert_output_contains 'HAWS Setup' || return 1
    assert_output_contains 'No changes have been made to this computer.' || return 1
    assert_output_contains 'Use Default Setup' || return 1
    assert_output_contains 'Customize Settings' || return 1
    assert_output_contains 'Exit' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/settings.tsv" || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest"
}

test_default_setup_reaches_preview_install_before_cancel() {
    run_haws_input $'\nq' || return 1
    assert_output_contains 'HAWS — Preview Install' || return 1
    assert_output_contains 'Install' || return 1
    assert_output_contains 'Back to Settings' || return 1
    assert_output_contains 'Cancel' || return 1
    assert_output_contains 'Cancelled. No changes saved.' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/settings.tsv" || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/install.complete"
}

test_preview_enter_does_not_apply_by_default() {
    run_haws_input $'\n\nq' || true
    assert_output_contains 'HAWS — Preview Install' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/settings.tsv" || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/install.complete"
}

test_customize_setup_reaches_lifecycle_neutral_settings() {
    local down=$'\033[B'
    run_haws_input "${down}\nq" || return 1
    assert_output_contains 'HAWS Settings' || return 1
    assert_output_contains 'Second Brain' || return 1
    assert_output_contains 'View status / Connect / Disconnect' || return 1
    assert_output_not_contains 'Second Brain Remote' || return 1
    assert_output_contains 'Auto Update' || return 1
    assert_output_contains 'Apply' || return 1
    assert_output_not_contains 'Discard Changes|Return without saving' || return 1
    assert_output_contains 'Existing repository sources' || return 1
    assert_output_contains 'all active (default)' || return 1
    assert_output_contains 'Accept the draft for preview' || return 1
    assert_output_not_contains 'HAWS Settings — First Install'
}

test_settings_exposes_second_brain_detail_without_toggle() {
    run_haws_input 'q' settings || true
    assert_output_contains 'Second Brain' || return 1
    assert_output_contains 'View status / Connect / Disconnect' || return 1
    assert_output_contains 'Auto Update' || return 1
    assert_output_not_contains 'Second Brain Remote' || return 1
    ! grep -E 'Second Brain[[:space:]]+\[ (On|Off) \]' "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_second_brain_local_only_cancel_preserves_local_only_mode() {
    local down=$'\033[B'
    local input="${down}${down}${down}\nn\nq"
    run_haws_input "${input}" settings || true
    assert_output_contains 'LOCAL-ONLY' || return 1
    assert_output_contains 'Do you want to connect? (y/N):' || return 1
    assert_output_contains 'Connection cancelled.' || return 1
    [ ! -d "${FIXTURE_PROJECT}/secondbrain/.git" ]
}

test_second_brain_connected_detail_disconnects_after_yes() {
    seed_second_brain_with_remote || return 1
    local down=$'\033[B'
    local input="${down}${down}${down}\ny\nq"
    run_haws_input "${input}" settings || true
    assert_output_contains 'ONLINE / CONNECTED' || return 1
    assert_output_contains 'Remote URL' || return 1
    assert_output_contains 'Total Commits' || return 1
    assert_output_contains 'Do you want to disconnect? (y/N):' || return 1
    assert_output_contains 'Successfully disconnected' || return 1
    ! git -C "${FIXTURE_PROJECT}/secondbrain" remote get-url origin >/dev/null 2>&1
}

test_second_brain_connect_is_immediate_after_yes() {
    local remote="file://${FIXTURE_ROOT}/secondbrain-connect.git"
    git init --bare -q "${FIXTURE_ROOT}/secondbrain-connect.git" || return 1
    local down=$'\033[B'
    local input="${down}${down}${down}\ny\n${remote}\nq"
    run_haws_input "${input}" settings || true
    assert_output_contains 'Connecting Second Brain' || return 1
    assert_output_contains 'please wait' || return 1
    [ "$(git -C "${FIXTURE_PROJECT}/secondbrain" remote get-url origin)" = "${remote}" ]
}

test_settings_repositories_route_keeps_old_actions() {
    local down=$'\033[B'
    run_haws_input "${down}\n\nq" || true
    assert_output_contains 'HAWS Settings' || return 1
    assert_output_contains 'Repositories' || return 1
    assert_output_contains 'Add Git Repository' || return 1
    assert_output_contains 'Remove Git Repository' || return 1
    assert_output_contains '[Q] Back' || return 1
    ! grep -F 'Back to Settings' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.gitmodules"
}

test_settings_skills_route_keeps_old_single_pack_labels() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}\nq"
    run_haws_input "${input}" || true
    assert_output_contains 'Configure Active Skills' || return 1
    assert_output_contains 'Single Skills' || return 1
    assert_output_contains 'Multi-Skill Packs' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/skills.disabled"
}

test_settings_skills_without_edits_has_no_false_discard_prompt() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}\nq"
    input+="q"
    run_haws_input "${input}" || true
    assert_output_not_contains 'Discard Changes?' || return 1
    assert_output_not_contains 'You have unapplied changes in Settings.'
}

test_settings_skills_shows_catalog_loading_status() {
    local down=$'\033[B'
    local input="${down}\n${down}\nqq"
    run_haws_input "${input}" || true
    assert_output_contains '[*] Loading skills catalog, please wait...' || return 1
    assert_output_contains '[✓] Skills catalog ready.'
}

test_settings_skills_route_keeps_draft_and_avoids_duplicate_frame() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}\nq"
    run_haws_input "${input}" || true
    [ "$(grep -Fc 'Configure Active Skills (Enable / Disable)' "${OUTPUT_FILE}")" -eq 1 ] || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/skills.disabled" || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
}

test_interactive_skill_pages_use_settings_header_and_fixed_state_columns() {
    mkdir -p "${FIXTURE_PROJECT}/skills/custom/presentation-sample" || return 1
    printf '%s\n' '---' 'name: presentation-sample' 'description: Presentation sample.' '---' \
        > "${FIXTURE_PROJECT}/skills/custom/presentation-sample/SKILL.md"
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}\n\nq"
    run_haws_input "${input}" || true
    assert_output_contains '                       Configure Single Skills' || return 1
    assert_output_not_contains '=== Configure Single Skills ===' || return 1
    local state_column detail_column
    state_column="$(awk '/Auto Update[[:space:]]+\[ On \]/ { print index($0, "[ On ]"); exit }' "${OUTPUT_FILE}")"
    detail_column="$(awk '/Auto Update[[:space:]]+\[ On \]/ { print index($0, " - "); exit }' "${OUTPUT_FILE}")"
    [ -n "${state_column}" ] || return 1
    [ -n "${detail_column}" ] || return 1
    [ "${detail_column}" -gt "${state_column}" ]
}

test_settings_ai_environments_opens_an_actionable_selector() {
    mkdir -p "${FIXTURE_HOME}/.claude" "${FIXTURE_HOME}/.codex" || return 1
    local down=$'\033[B'
    local input="${down}\n${down}${down}\n"
    input+="${down} \n"
    input+="qq"
    run_haws_input "${input}" || true
    assert_output_contains 'Configure AI Environments' || return 1
    assert_output_contains 'Claude Code' || return 1
    assert_output_contains 'OpenAI Codex' || return 1
    assert_output_not_contains 'This Settings draft row is preserved for the next catalog batch.'
}

test_settings_enter_toggles_auto_update_and_reaches_preview() {
    local down=$'\033[B'
    local input="${down}${down}${down}${down}\n"
    input+="${down}\nq"
    run_haws_input "${input}" settings || true
    assert_output_contains 'HAWS — Preview Install' || return 1
    grep -E 'Auto Update[[:space:]]+\[ Off \]' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
}

test_settings_apply_reaches_preview_without_persisting() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}${down}${down}${down}${down}\nq"
    run_haws_input "${input}" || return 1
    assert_output_contains 'HAWS Settings' || return 1
    assert_output_contains 'HAWS — Preview Install' || return 1
    assert_output_contains '[*] Loading skills catalog, please wait...' || return 1
    assert_output_contains '[✓] Skills catalog ready.' || return 1
    assert_output_contains 'Install' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/settings.tsv" || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/install.complete"
}

test_preview_back_to_settings_preserves_draft() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}${down}${down}${down} ${down}\n"
    input+="\n"
    run_haws_input "${input}" || true
    assert_output_contains 'HAWS — Preview Install' || return 1
    assert_output_contains 'Back to Settings' || return 1
    grep -E 'Auto Update[[:space:]]+\[ Off \]' "${OUTPUT_FILE}" || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
}

test_preview_cancel_discards_draft_and_returns_to_setup() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}${down}${down}${down} ${down}\n"
    input+="${down}\n"
    run_haws_input "${input}" || true
    assert_output_contains 'Cancelled. No changes saved.' || return 1
    assert_output_contains 'HAWS Setup' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
}

test_reset_defaults_requires_confirmation_before_replacing_draft() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}${down}${down}${down}${down}${down}\nq"
    run_haws_input "${input}" || true
    assert_output_contains 'Reset Settings to Defaults?' || return 1
    assert_output_contains '> Reset' || return 1
    assert_output_contains 'Cancel' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
}

test_completed_install_opens_home_without_sync_or_doctor() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema=1\tcompleted_at=fixture\n' > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > \
        "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    run_haws_input 'q' || return 1
    assert_output_contains 'HAWS Home' || return 1
    assert_output_contains 'Sync' || return 1
    assert_output_contains 'Settings' || return 1
    assert_output_contains 'Doctor' || return 1
    assert_output_not_contains 'Health' || return 1
    assert_output_contains 'Uninstall' || return 1
    assert_output_contains 'Exit' || return 1
    assert_output_not_contains '> Exit' || return 1
    assert_output_not_contains '> Doctor' || return 1
    assert_output_not_contains 'Status Details' || return 1
    assert_output_not_contains 'HAWS Setup' || return 1
    [ ! -s "${CALL_LOG}" ]
}

test_home_enter_does_not_dispatch_sync_by_default() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema=1\tcompleted_at=fixture\n' > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > \
        "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    run_haws_input $'\nq' || true
    assert_output_contains 'HAWS Home' || return 1
    assert_output_not_contains 'Preparing synchronization' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/sync-state.tsv"
}

test_dirty_settings_exit_prompts_before_discarding_draft() {
    local down=$'\033[B'
    local up=$'\033[A'
    local input="${down}${down}${down}${down}\n"
    input+="${up}${up}${up}${up}\n"
    input+="qqq"
    run_haws_input "${input}" settings || true
    assert_output_contains 'Discard Changes?' || return 1
    assert_output_contains 'You have unapplied changes in Settings.' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
}

test_unchanged_home_route_is_clear_and_does_not_sync() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema=1\tcompleted_at=fixture\n' > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > \
        "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    local input="q"
    run_haws_input "${input}" || true
    assert_output_contains 'HAWS Home' || return 1
    assert_output_not_contains 'Preparing synchronization' || return 1
    assert_output_not_contains 'Back to caller.'
}

test_draft_cancel_preserves_existing_state_bytes() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state" "${FIXTURE_PROJECT}/ai-configs"
    printf 'schema=1\tcompleted_at=fixture\n' > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > \
        "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    printf 'cursor\r\ncodex\r\n' > "${FIXTURE_PROJECT}/ai-configs/environments.disabled"
    local settings_before environments_before settings_after environments_after
    settings_before="$(_sha256_file "${FIXTURE_PROJECT}/.haws/state/settings.tsv")"
    environments_before="$(_sha256_file "${FIXTURE_PROJECT}/ai-configs/environments.disabled")"
    local down=$'\033[B'
    local input="${down}\nq"
    run_haws_input "${input}" || true
    settings_after="$(_sha256_file "${FIXTURE_PROJECT}/.haws/state/settings.tsv")"
    environments_after="$(_sha256_file "${FIXTURE_PROJECT}/ai-configs/environments.disabled")"
    [ "${settings_before}" = "${settings_after}" ] || return 1
    [ "${environments_before}" = "${environments_after}" ]
}

_sha256_file() {
    sha256sum "$1" | awk '{print $1}'
}

test_partial_failure_reports_completed_and_remaining_actions() {
    run_haws_input_with_env $'\n\033[A\n' 'HAWS_TEST_FAIL_AFTER_SETTINGS=1' || true
    assert_output_contains 'Partial failure' || return 1
    assert_output_contains 'Completed: settings' || return 1
    assert_output_contains 'Remaining: integration' || return 1
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/settings.tsv" 'auto_update' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/install.complete"
}

test_first_install_creates_empty_environment_state_file() {
    run_haws_input_with_env $'\n\033[A\n' 'HAWS_TEST_NO_INTEGRATION=1' || return 1
    local disabled_file="${FIXTURE_PROJECT}/ai-configs/environments.disabled"
    [ -f "${disabled_file}" ] || return 1
    ! grep -E '^[[:space:]]*[^#[:space:]]' "${disabled_file}" >/dev/null 2>&1
}

test_legacy_second_brain_fields_do_not_override_remote_state() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema_version\t1\nsecond_brain\ton\nsecond_brain_remote\tfile://${FIXTURE_ROOT}/missing.git\nauto_update\toff\n' \
        > "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    run_haws_input 'q' status || return 1
    assert_output_contains 'Second Brain: Local-Only' || return 1
    assert_output_contains 'Auto Update: off' || return 1
}

test_second_brain_detail_rejects_blank_url_without_creating_remote() {
    local down=$'\033[B'
    local input="${down}${down}${down}\ny\n\nq"
    run_haws_input "${input}" settings || true
    assert_output_contains 'Connection cancelled.' || return 1
    [ ! -d "${FIXTURE_PROJECT}/secondbrain/.git" ]
}

test_second_brain_detail_rejects_invalid_url() {
    local down=$'\033[B'
    local input="${down}${down}${down}\ny\nnot-a-remote\nq"
    run_haws_input "${input}" settings || true
    assert_output_contains 'Invalid Git repository URL format' || return 1
    ! git -C "${FIXTURE_PROJECT}/secondbrain" remote get-url origin >/dev/null 2>&1
}

test_second_brain_settings_have_no_deferred_remote_validation() {
    ! grep -F '_settings_collect_second_brain_remote' "${PROJECT_ROOT}/haws.sh" >/dev/null 2>&1 || return 1
    ! grep -F 'setting\tsecond_brain' "${PROJECT_ROOT}/haws.sh" >/dev/null 2>&1
}

test_successful_install_records_completion_and_next_launch_home() {
    run_haws_input_with_env $'\n\033[A\n' 'HAWS_TEST_NO_INTEGRATION=1' || return 1
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/install.complete" 'schema=1' || return 1
    run_haws_input 'q' || return 1
    assert_output_contains 'HAWS Home'
}

test_settings_repository_remove_shows_loading_status() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="\n"
    input+="${down}\n"
    input+="qqq"
    run_haws_input "${input}" || true
    assert_output_contains '[*] Loading repository sources, please wait...' || return 1
}

test_settings_auto_update_toggle_alignment_equal_columns() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}${down}${down}${down} "
    input+=" "
    input+="qq"
    run_haws_input "${input}" || true
    local on_detail_col off_detail_col
    on_detail_col="$(awk '/Auto Update[[:space:]]+\[ On \]/ { print index($0, " - "); exit }' "${OUTPUT_FILE}")"
    off_detail_col="$(awk '/Auto Update[[:space:]]+\[ Off \]/ { print index($0, " - "); exit }' "${OUTPUT_FILE}")"
    [ -n "${on_detail_col}" ] || return 1
    [ -n "${off_detail_col}" ] || return 1
    [ "${on_detail_col}" -eq "${off_detail_col}" ]
}

run_test() {
    local test_name="$1"
    create_fixture
    CALL_LOG="${FIXTURE_ROOT}/calls.log"
    : > "${CALL_LOG}"
    if "${test_name}"; then
        echo "PASS ${test_name}"
        passed=$((passed + 1))
    else
        echo "FAIL ${test_name}"
        failed=$((failed + 1))
    fi
    cleanup_fixture
}

trap cleanup_fixture EXIT

if [ -n "${HAWS_SETTINGS_TEST_ONLY:-}" ]; then
    run_test "${HAWS_SETTINGS_TEST_ONLY}"
    echo "CLI settings-flow tests: ${passed} passed, ${failed} failed"
    [ "${failed}" -eq 0 ]
    exit
fi

run_test test_first_use_opens_setup_without_mutation
run_test test_default_setup_reaches_preview_install_before_cancel
run_test test_preview_enter_does_not_apply_by_default
run_test test_customize_setup_reaches_lifecycle_neutral_settings
run_test test_settings_exposes_second_brain_detail_without_toggle
run_test test_second_brain_local_only_cancel_preserves_local_only_mode
run_test test_second_brain_connected_detail_disconnects_after_yes
run_test test_second_brain_connect_is_immediate_after_yes
run_test test_settings_repositories_route_keeps_old_actions
run_test test_settings_skills_route_keeps_old_single_pack_labels
run_test test_settings_skills_without_edits_has_no_false_discard_prompt
run_test test_settings_skills_shows_catalog_loading_status
run_test test_settings_skills_route_keeps_draft_and_avoids_duplicate_frame
run_test test_interactive_skill_pages_use_settings_header_and_fixed_state_columns
run_test test_settings_ai_environments_opens_an_actionable_selector
run_test test_settings_enter_toggles_auto_update_and_reaches_preview
run_test test_settings_apply_reaches_preview_without_persisting
run_test test_preview_back_to_settings_preserves_draft
run_test test_preview_cancel_discards_draft_and_returns_to_setup
run_test test_reset_defaults_requires_confirmation_before_replacing_draft
run_test test_completed_install_opens_home_without_sync_or_doctor
run_test test_home_enter_does_not_dispatch_sync_by_default
run_test test_dirty_settings_exit_prompts_before_discarding_draft
run_test test_unchanged_home_route_is_clear_and_does_not_sync
run_test test_draft_cancel_preserves_existing_state_bytes
run_test test_partial_failure_reports_completed_and_remaining_actions
run_test test_first_install_creates_empty_environment_state_file
run_test test_legacy_second_brain_fields_do_not_override_remote_state
run_test test_second_brain_detail_rejects_blank_url_without_creating_remote
run_test test_second_brain_detail_rejects_invalid_url
run_test test_second_brain_settings_have_no_deferred_remote_validation
run_test test_successful_install_records_completion_and_next_launch_home
run_test test_settings_repository_remove_shows_loading_status
run_test test_settings_auto_update_toggle_alignment_equal_columns

echo "CLI settings-flow tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
