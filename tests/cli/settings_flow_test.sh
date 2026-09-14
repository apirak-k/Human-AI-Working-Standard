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
    assert_output_contains 'Second Brain Remote' || return 1
    assert_output_contains 'Auto Update' || return 1
    assert_output_contains 'Apply' || return 1
    assert_output_contains 'Discard Changes' || return 1
    assert_output_contains 'Existing repository sources' || return 1
    assert_output_contains 'all active (default)' || return 1
    assert_output_contains 'Accept the draft for preview' || return 1
    assert_output_not_contains 'HAWS Settings — First Install'
}

test_settings_repositories_route_keeps_old_actions() {
    local down=$'\033[B'
    run_haws_input "${down}\n\nq" || true
    assert_output_contains 'HAWS Settings' || return 1
    assert_output_contains 'Repositories' || return 1
    assert_output_contains 'Add Git Repository' || return 1
    assert_output_contains 'Remove Git Repository' || return 1
    assert_output_contains 'Back to Settings' || return 1
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
    assert_output_contains 'Health' || return 1
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

test_unchanged_preview_update_offers_only_back_routes() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema=1\tcompleted_at=fixture\n' > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > \
        "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    local down=$'\033[B'
    local input="\n"
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

test_second_brain_remote_empty_does_not_persist() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}${down}${down} ${down}${down}\nq"
    run_haws_input_with_env "${input}" 'HAWS_TEST_NO_INTEGRATION=1' || true
    assert_output_contains 'remote URL' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/install.complete" || return 1
    if [ -f "${FIXTURE_PROJECT}/.haws/state/settings.tsv" ]; then
        ! grep -F $'second_brain\ton' "${FIXTURE_PROJECT}/.haws/state/settings.tsv" >/dev/null 2>&1 || return 1
    fi
}

test_second_brain_remote_invalid_does_not_persist() {
    local down=$'\033[B'
    local input="${down}\n"
    input+="${down}${down}${down} ${down}${down}\nnot-a-remote\nq"
    run_haws_input_with_env "${input}" 'HAWS_TEST_NO_INTEGRATION=1' || true
    assert_output_contains 'Invalid remote URL' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/install.complete" || return 1
    if [ -f "${FIXTURE_PROJECT}/.haws/state/settings.tsv" ]; then
        ! grep -F $'second_brain\ton' "${FIXTURE_PROJECT}/.haws/state/settings.tsv" >/dev/null 2>&1 || return 1
    fi
}

test_second_brain_remote_unreachable_does_not_persist() {
    local down=$'\033[B'
    local up=$'\033[A'
    local input="${down}\n"
    input+="${down}${down}${down} ${down}${down}\nfile://${FIXTURE_ROOT}/missing.git\n${up}\nq"
    run_haws_input_with_env "${input}" 'HAWS_TEST_NO_INTEGRATION=1' || true
    assert_output_contains 'Remote validation failed' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/install.complete" || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
}

test_second_brain_remote_access_is_deferred_until_final_apply() {
    local real_git
    real_git="$(command -v git)"
    local fake_bin="${FIXTURE_ROOT}/fake-bin"
    local git_log="${FIXTURE_ROOT}/git-calls.log"
    mkdir -p "${fake_bin}"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'for arg in "$@"; do' \
        '    case "${arg}" in' \
        '        ls-remote|pull) printf "%s\\n" "${arg}" >> "${GIT_CALL_LOG}"; break ;;' \
        '    esac' \
        'done' \
        'exec "${HAWS_REAL_GIT}" "$@"' > "${fake_bin}/git"
    chmod +x "${fake_bin}/git"

    local down=$'\033[B'
    local up=$'\033[A'
    local toggle_input="${down}\n"
    toggle_input+="${down}${down}${down} q"
    local old_path="${PATH}"
    PATH="${fake_bin}:${old_path}"
    run_haws_input_with_env "${toggle_input}" "GIT_CALL_LOG=${git_log} HAWS_REAL_GIT=${real_git}" || true
    PATH="${old_path}"
    [ ! -s "${git_log}" ] || return 1

    git init --bare --quiet "${FIXTURE_ROOT}/remote.git" || return 1
    local remote="file://${FIXTURE_ROOT}/remote.git"
    mkdir -p "${FIXTURE_PROJECT}/secondbrain"
    git -C "${FIXTURE_PROJECT}/secondbrain" init --quiet || return 1
    git -C "${FIXTURE_PROJECT}/secondbrain" checkout --quiet -b main || return 1
    git -C "${FIXTURE_PROJECT}/secondbrain" config user.name HAWS-Test
    git -C "${FIXTURE_PROJECT}/secondbrain" config user.email test@example.invalid
    printf '# Preferences\n' > "${FIXTURE_PROJECT}/secondbrain/USER_PREFERENCES.md"
    printf '# Anti-patterns\n' > "${FIXTURE_PROJECT}/secondbrain/ANTI_PATTERNS.md"
    git -C "${FIXTURE_PROJECT}/secondbrain" add . || return 1
    git -C "${FIXTURE_PROJECT}/secondbrain" commit --quiet -m baseline || return 1
    git -C "${FIXTURE_PROJECT}/secondbrain" remote add origin "${remote}" || return 1
    git -C "${FIXTURE_PROJECT}/secondbrain" push --quiet -u origin main || return 1
    git --git-dir="${FIXTURE_ROOT}/remote.git" symbolic-ref HEAD refs/heads/main || return 1
    local apply_input="${down}\n"
    apply_input+="${down}${down}${down} ${down}${down}\n${remote}\n${up}\nq"
    PATH="${fake_bin}:${old_path}"
    run_haws_input_with_env "${apply_input}" "GIT_CALL_LOG=${git_log} HAWS_REAL_GIT=${real_git} HAWS_TEST_NO_INTEGRATION=1" || return 1
    PATH="${old_path}"
    [ "$(wc -l < "${git_log}" | tr -d ' ')" = 1 ] || return 1
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/settings.tsv" \
        $'second_brain_remote\tfile://' || return 1
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/settings.tsv" $'second_brain\ton' || return 1

    PATH="${fake_bin}:${old_path}"
    run_haws_input_with_env "${up}${up}\nq" "GIT_CALL_LOG=${git_log} HAWS_REAL_GIT=${real_git} HAWS_TEST_NO_INTEGRATION=1" || return 1
    PATH="${old_path}"
    [ "$(wc -l < "${git_log}" | tr -d ' ')" = 2 ] || return 1
    tail -n 1 "${git_log}" | grep -Fx pull >/dev/null
}

test_successful_install_records_completion_and_next_launch_home() {
    run_haws_input_with_env $'\n\033[A\n' 'HAWS_TEST_NO_INTEGRATION=1' || return 1
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
run_test test_settings_repositories_route_keeps_old_actions
run_test test_settings_skills_route_keeps_old_single_pack_labels
run_test test_settings_skills_without_edits_has_no_false_discard_prompt
run_test test_settings_skills_shows_catalog_loading_status
run_test test_settings_skills_route_keeps_draft_and_avoids_duplicate_frame
run_test test_settings_ai_environments_opens_an_actionable_selector
run_test test_settings_enter_toggles_auto_update_and_reaches_preview
run_test test_settings_apply_reaches_preview_without_persisting
run_test test_preview_back_to_settings_preserves_draft
run_test test_preview_cancel_discards_draft_and_returns_to_setup
run_test test_reset_defaults_requires_confirmation_before_replacing_draft
run_test test_completed_install_opens_home_without_sync_or_doctor
run_test test_home_enter_does_not_dispatch_sync_by_default
run_test test_dirty_settings_exit_prompts_before_discarding_draft
run_test test_unchanged_preview_update_offers_only_back_routes
run_test test_draft_cancel_preserves_existing_state_bytes
run_test test_partial_failure_reports_completed_and_remaining_actions
run_test test_first_install_creates_empty_environment_state_file
run_test test_second_brain_remote_empty_does_not_persist
run_test test_second_brain_remote_invalid_does_not_persist
run_test test_second_brain_remote_unreachable_does_not_persist
run_test test_second_brain_remote_access_is_deferred_until_final_apply
run_test test_successful_install_records_completion_and_next_launch_home

echo "CLI settings-flow tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
