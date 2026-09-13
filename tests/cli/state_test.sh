#!/usr/bin/env bash
# Local-state compatibility tests for the old HAWS command engine.

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${TEST_DIR}/test_helper.sh"

passed=0
failed=0

source_haws() {
    grep -q '^settings_load()' "${FIXTURE_PROJECT}/haws.sh" || return 1
    export HOME="${FIXTURE_HOME}"
    export HAWS_REPO_DIR="${FIXTURE_PROJECT}"
    export HAWS_STATE_DIR="${FIXTURE_PROJECT}/.haws/state"
    export HAWS_SOURCE_ONLY=1
    # shellcheck disable=SC1091
    . "${FIXTURE_PROJECT}/haws.sh"
    unset HAWS_SOURCE_ONLY
}

test_state_api_is_present() {
    source_haws || return 1
    local api
    for api in settings_load settings_save disabled_environments_load \
        disabled_environments_save_if_changed ownership_record ownership_list \
        sync_lock_acquire sync_lock_release; do
        declare -F "${api}" >/dev/null || return 1
    done
}

test_empty_disabled_environment_file_means_all_enabled() {
    mkdir -p "${FIXTURE_PROJECT}/ai-configs"
    : > "${FIXTURE_PROJECT}/ai-configs/environments.disabled"
    source_haws || return 1
    disabled_environments_load || return 1
    [ -z "${DISABLED_ENVIRONMENTS[*]:-}" ]
}

test_settings_save_does_not_rewrite_disabled_environment_bytes() {
    local disabled_file="${FIXTURE_PROJECT}/ai-configs/environments.disabled"
    mkdir -p "$(dirname "${disabled_file}")"
    printf 'cursor\r\ncodex\r\n' > "${disabled_file}"
    local before after
    source_haws || return 1
    before="$(_haws_sha256 "${disabled_file}")"
    settings_save auto_update off || return 1
    after="$(_haws_sha256 "${disabled_file}")"
    [ "${before}" = "${after}" ] || return 1
    cmp -s <(printf 'cursor\r\ncodex\r\n') "${disabled_file}"
}

test_disabled_environment_save_is_noop_when_bytes_are_unchanged() {
    local disabled_file="${FIXTURE_PROJECT}/ai-configs/environments.disabled"
    mkdir -p "$(dirname "${disabled_file}")"
    printf 'cursor\r\ncodex\r\n' > "${disabled_file}"
    local before after
    source_haws || return 1
    before="$(_haws_sha256 "${disabled_file}")"
    disabled_environments_load || return 1
    disabled_environments_save_if_changed || return 1
    after="$(_haws_sha256 "${disabled_file}")"
    [ "${before}" = "${after}" ]
}

test_settings_round_trip_preserves_spaces() {
    export HAWS_STATE_DIR="${FIXTURE_PROJECT}/state folder/with spaces"
    source_haws || return 1
    settings_save on off "git@example.invalid:user/brain with spaces.git" || return 1
    settings_load || return 1
    [ "${HAWS_SECOND_BRAIN_ENABLED}" = on ] || return 1
    [ "${HAWS_AUTO_UPDATE}" = off ] || return 1
    [ "${HAWS_SECOND_BRAIN_REMOTE}" = "git@example.invalid:user/brain with spaces.git" ]
}

test_settings_save_can_clear_remote() {
    source_haws || return 1
    settings_save on off "git@example.invalid:user/brain.git" || return 1
    settings_save on off "" || return 1
    settings_load || return 1
    [ -z "${HAWS_SECOND_BRAIN_REMOTE}" ]
}

test_settings_save_rejects_remote_control_injection() {
    source_haws || return 1
    local remote=$'git@example.invalid:user/brain\nmalicious'
    if settings_save off on "${remote}"; then
        return 1
    fi
    [ ! -f "${HAWS_STATE_DIR}/settings.tsv" ]
}

test_settings_failure_before_rename_preserves_previous_file() {
    source_haws || return 1
    settings_save off on || return 1
    local settings_file="${HAWS_STATE_DIR}/settings.tsv"
    local before before_hash after_hash
    before="$(<"${settings_file}")"
    before_hash="$(_haws_sha256 "${settings_file}")"
    export HAWS_TEST_FAIL_BEFORE_SETTINGS_RENAME=1
    if settings_save on off; then
        unset HAWS_TEST_FAIL_BEFORE_SETTINGS_RENAME
        return 1
    fi
    unset HAWS_TEST_FAIL_BEFORE_SETTINGS_RENAME
    after_hash="$(_haws_sha256 "${settings_file}")"
    [ "${before_hash}" = "${after_hash}" ] || return 1
    [ "$(<"${settings_file}")" = "${before}" ] || return 1
    ! compgen -G "${HAWS_STATE_DIR}/settings.stage.*" >/dev/null
}

test_ownership_round_trip_preserves_spaces_in_paths() {
    source_haws || return 1
    local owned_path="${FIXTURE_HOME}/AI Profiles/Claude Code/skills/test skill"
    ownership_record pointers symlink "${owned_path}" \
        "/source/with spaces" fingerprint123 || return 1
    ownership_list pointers |
        awk -F '\t' -v p="${owned_path}" \
            '$3 == p && $4 == "/source/with spaces" && $5 == "fingerprint123" {found=1} END {exit found ? 0 : 1}'
}

test_ownership_record_updates_one_identity_without_duplicates() {
    source_haws || return 1
    local owned_path="${FIXTURE_HOME}/managed skill"
    ownership_record skills symlink "${owned_path}" source-a hash-a || return 1
    ownership_record skills symlink "${owned_path}" source-b hash-b || return 1
    [ "$(ownership_list skills | awk -F '\t' -v p="${owned_path}" '$3 == p {count++} END {print count + 0}')" = 1 ] || return 1
    ownership_list skills |
        awk -F '\t' -v p="${owned_path}" \
            '$3 == p && $4 == "source-b" && $5 == "hash-b" {found=1} END {exit found ? 0 : 1}'
}

test_live_sync_lock_blocks_second_owner() {
    source_haws || return 1
    sync_lock_acquire || return 1
    if sync_lock_acquire 2>"${OUTPUT_FILE}"; then
        sync_lock_release || true
        return 1
    fi
    grep -F 'sync already running' "${OUTPUT_FILE}" >/dev/null || return 1
    sync_lock_release || return 1
    [ ! -d "${HAWS_STATE_DIR}/sync.lock" ]
}

test_stale_sync_lock_is_reported_and_recoverable() {
    source_haws || return 1
    mkdir -p "${HAWS_STATE_DIR}/sync.lock"
    printf '99999999\n' > "${HAWS_STATE_DIR}/sync.lock/pid"
    printf '1\n' > "${HAWS_STATE_DIR}/sync.lock/timestamp"
    if sync_lock_acquire 2>"${OUTPUT_FILE}"; then return 1; fi
    grep -F 'stale sync lock' "${OUTPUT_FILE}" >/dev/null || return 1
    sync_lock_release --recover || return 1
    sync_lock_acquire || return 1
    sync_lock_release || return 1
    [ ! -d "${HAWS_STATE_DIR}/sync.lock" ]
}

test_recovery_refuses_a_live_sync_lock() {
    source_haws || return 1
    sync_lock_acquire || return 1
    if sync_lock_release --recover 2>"${OUTPUT_FILE}"; then
        sync_lock_release || true
        return 1
    fi
    grep -F 'refusing to recover live sync lock' "${OUTPUT_FILE}" >/dev/null || return 1
    sync_lock_release
}

test_local_state_paths_are_ignored() {
    grep -F '/.haws/state/' "${PROJECT_ROOT}/.gitignore" >/dev/null || return 1
    grep -F 'ai-configs/environments.disabled' "${PROJECT_ROOT}/.gitignore" >/dev/null || return 1
    grep -F 'config/environments.disabled' "${PROJECT_ROOT}/.gitignore" >/dev/null || return 1
    grep -F 'environments.disabled' "${PROJECT_ROOT}/.gitignore" >/dev/null
}

run_test() {
    local test_name="$1"
    create_fixture
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

run_test test_state_api_is_present
run_test test_empty_disabled_environment_file_means_all_enabled
run_test test_settings_save_does_not_rewrite_disabled_environment_bytes
run_test test_disabled_environment_save_is_noop_when_bytes_are_unchanged
run_test test_settings_round_trip_preserves_spaces
run_test test_settings_save_can_clear_remote
run_test test_settings_save_rejects_remote_control_injection
run_test test_settings_failure_before_rename_preserves_previous_file
run_test test_ownership_round_trip_preserves_spaces_in_paths
run_test test_ownership_record_updates_one_identity_without_duplicates
run_test test_live_sync_lock_blocks_second_owner
run_test test_stale_sync_lock_is_reported_and_recoverable
run_test test_recovery_refuses_a_live_sync_lock
run_test test_local_state_paths_are_ignored

echo "CLI local-state tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
