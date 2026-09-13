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

test_customize_setup_reaches_lifecycle_neutral_settings() {
    local down=$'\033[B'
    run_haws_input "${down}\nq" || return 1
    assert_output_contains 'HAWS Settings' || return 1
    assert_output_contains 'Second Brain Remote' || return 1
    assert_output_contains 'Auto Update' || return 1
    assert_output_contains 'Apply' || return 1
    assert_output_contains 'Discard Changes' || return 1
    assert_output_not_contains 'HAWS Settings — First Install'
}

test_settings_apply_reaches_preview_without_persisting() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}${down}${down}${down}${down}\nq"
    run_haws_input "${input}" || return 1
    assert_output_contains 'HAWS Settings' || return 1
    assert_output_contains 'HAWS — Preview Install' || return 1
    assert_output_contains 'Install' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/settings.tsv" || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/install.complete"
}

test_preview_back_to_settings_preserves_draft() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}${down}${down}${down} ${down}\n"
    input+="${down}\n"
    run_haws_input "${input}" || true
    assert_output_contains 'HAWS — Preview Install' || return 1
    assert_output_contains 'Back to Settings' || return 1
    assert_output_contains 'Auto Update [ Off ]' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
}

test_preview_cancel_discards_draft_and_returns_to_setup() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}${down}${down}${down} ${down}\n"
    input+="${down}${down}\n"
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
    assert_output_contains 'Status Details' || return 1
    assert_output_contains 'Uninstall' || return 1
    assert_output_contains 'Exit' || return 1
    assert_output_not_contains 'HAWS Setup' || return 1
    [ ! -s "${CALL_LOG}" ]
}

test_unchanged_preview_update_offers_only_back_routes() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema=1\tcompleted_at=fixture\n' > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > \
        "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}${down}${down}${down}${down}\nq"
    run_haws_input "${input}" || true
    assert_output_contains 'HAWS — Preview Update' || return 1
    assert_output_contains 'No settings have changed.' || return 1
    assert_output_contains 'Back to Settings' || return 1
    assert_output_contains 'Back to Home' || return 1
    ! grep -E $'\r(> |  )(Install|Update)[[:space:]]*$' "${OUTPUT_FILE}" >/dev/null 2>&1
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
    run_haws_input_with_env $'\n\n' 'HAWS_TEST_FAIL_AFTER_SETTINGS=1' || true
    assert_output_contains 'Partial failure' || return 1
    assert_output_contains 'Completed: settings' || return 1
    assert_output_contains 'Remaining: integration' || return 1
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/settings.tsv" 'auto_update' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/install.complete"
}

test_successful_install_records_completion_and_next_launch_home() {
    run_haws_input_with_env $'\n\n' 'HAWS_TEST_NO_INTEGRATION=1' || return 1
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/install.complete" 'schema=1' || return 1
    run_haws_input 'q' || return 1
    assert_output_contains 'HAWS Home'
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

run_test test_first_use_opens_setup_without_mutation
run_test test_default_setup_reaches_preview_install_before_cancel
run_test test_customize_setup_reaches_lifecycle_neutral_settings
run_test test_settings_apply_reaches_preview_without_persisting
run_test test_preview_back_to_settings_preserves_draft
run_test test_preview_cancel_discards_draft_and_returns_to_setup
run_test test_reset_defaults_requires_confirmation_before_replacing_draft
run_test test_completed_install_opens_home_without_sync_or_doctor
run_test test_unchanged_preview_update_offers_only_back_routes
run_test test_draft_cancel_preserves_existing_state_bytes
run_test test_partial_failure_reports_completed_and_remaining_actions
run_test test_successful_install_records_completion_and_next_launch_home

echo "CLI settings-flow tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
