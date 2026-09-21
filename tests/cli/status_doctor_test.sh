#!/usr/bin/env bash
# Batch 6 read-only health and evidence-based label tests.

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${TEST_DIR}/test_helper.sh"
HAWS_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

passed=0
failed=0

source_haws() {
    export HOME="${FIXTURE_HOME}"
    export HAWS_REPO_DIR="${FIXTURE_PROJECT}"
    export HAWS_STATE_DIR="${FIXTURE_PROJECT}/.haws/state"
    export HAWS_SOURCE_ONLY=1
    . "${FIXTURE_PROJECT}/haws.sh"
    unset HAWS_SOURCE_ONLY
}

run_haws() {
    env HOME="${FIXTURE_HOME}" HAWS_REPO_DIR="${FIXTURE_PROJECT}" \
        HAWS_STATE_DIR="${FIXTURE_PROJECT}/.haws/state" \
        HAWS_CALL_LOG="${CALL_LOG:-}" PATH="${PATH}" \
        bash "${FIXTURE_PROJECT}/haws.sh" "$@" >"${OUTPUT_FILE}" 2>&1
}

fixture_snapshot() {
    find "${FIXTURE_PROJECT}" "${FIXTURE_HOME}" -type f -print0 2>/dev/null |
        sort -z |
        while IFS= read -r -d '' path; do
            printf '%s\t' "${path}"
            sha256sum "${path}" | awk '{print $1}'
        done
}

seed_health_fixture() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state" "${FIXTURE_HOME}/.claude" \
        "${FIXTURE_PROJECT}/.githooks"
    : > "${FIXTURE_PROJECT}/.githooks/commit-msg"
    printf 'schema_version\t1\nsecond_brain\toff\nauto_update\toff\n' \
        > "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    printf '2026-09-09T00:00:00Z\thaws\tUp to date\tabc123\tlocal check\n' \
        > "${FIXTURE_PROJECT}/.haws/state/sync-state.tsv"
    printf 'schema=1\tcompleted_at=now\n' \
        > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    printf '%s\n' 'managed' > "${FIXTURE_HOME}/.claude/CLAUDE.md"
    source_haws || return 1
    local pointer_hash
    pointer_hash="$(_haws_sha256 "${FIXTURE_HOME}/.claude/CLAUDE.md")"
    ownership_record environments generated-file \
        "${FIXTURE_HOME}/.claude/CLAUDE.md" "${FIXTURE_PROJECT}/core/HAWS.md" \
        "${pointer_hash}" || return 1
    git -C "${FIXTURE_PROJECT}" init -q || return 1
    git -C "${FIXTURE_PROJECT}" config core.hooksPath custom-hooks || return 1
}

test_health_apis_are_present() {
    source_haws || return 1
    for api in status_run doctor_run; do
        declare -F "${api}" >/dev/null || return 1
    done
}

test_doctor_is_the_only_detailed_diagnostics_page() {
    source_haws || return 1
    ! grep -q '^health_run()' "${FIXTURE_PROJECT}/haws.sh" || return 1
    ! grep -q '^run_health()' "${FIXTURE_PROJECT}/haws.sh" || return 1
    seed_health_fixture || return 1
    run_haws doctor || true
    assert_output_contains '=============================================================' || return 1
    assert_output_contains 'HAWS Doctor' || return 1
    assert_output_contains '[*] Running diagnostics, please wait...' || return 1
    assert_output_contains 'FINDINGS' || return 1
    ! grep -F 'HAWS Health' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    local loading_line overall_line
    loading_line="$(grep -nF '[*] Running diagnostics, please wait...' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    overall_line="$(grep -nF 'Overall:' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    [ -n "${loading_line}" ] && [ -n "${overall_line}" ] && [ "${loading_line}" -lt "${overall_line}" ]
}

test_slow_routes_have_explicit_progress_messages() {
    local source="${PROJECT_ROOT}/haws.sh"
    local message
    for message in \
        '[*] Running diagnostics, please wait...' \
        '[*] Loading skills catalog, please wait...' \
        '[*] Connecting Second Brain, please wait...' \
        '[*] Syncing Second Brain, please wait...' \
        '[*] Building uninstall preview, please wait...' \
        '[*] Applying uninstall changes, please wait...' \
        '[*] Applying settings draft...' \
        '[*] Validating repository source, please wait...'; do
        grep -F "${message}" "${source}" >/dev/null 2>&1 || return 1
    done
}

test_only_commit_msg_hook_is_present() {
    [ -f "${HAWS_ROOT}/.githooks/commit-msg" ] || return 1
    [ ! -e "${HAWS_ROOT}/.githooks/pre-commit" ] || return 1
    [ ! -e "${HAWS_ROOT}/.githooks/pre-push" ] || return 1
}

test_status_and_doctor_preserve_all_fixture_files_and_git_state() {
    seed_health_fixture || return 1
    local before after git_before git_after
    before="$(fixture_snapshot)"
    git_before="$(git -C "${FIXTURE_PROJECT}" status --porcelain)"
    run_haws status || return 1
    run_haws doctor || true
    after="$(fixture_snapshot)"
    git_after="$(git -C "${FIXTURE_PROJECT}" status --porcelain)"
    [ "${before}" = "${after}" ] || return 1
    [ "${git_before}" = "${git_after}" ] || return 1
    [ "$(git -C "${FIXTURE_PROJECT}" config --get core.hooksPath)" = custom-hooks ]
}

test_status_never_invokes_network_commands() {
    seed_health_fixture || return 1
    local real_git="$(command -v git)"
    local fake_bin="${FIXTURE_ROOT}/fake-bin"
    mkdir -p "${fake_bin}"
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "%s\\n" "$*" >> "${HAWS_CALL_LOG}"' \
        'exec "${HAWS_REAL_GIT}" "$@"' > "${fake_bin}/git"
    chmod +x "${fake_bin}/git"
    HAWS_REAL_GIT="${real_git}" HAWS_CALL_LOG="${FIXTURE_ROOT}/git-calls.log" \
        PATH="${fake_bin}:${PATH}" run_haws status || return 1
    ! grep -E '(^|[[:space:]])(fetch|pull|ls-remote)([[:space:]]|$)' \
        "${FIXTURE_ROOT}/git-calls.log" >/dev/null 2>&1
}

test_status_reports_current_attention_separately_from_last_sync() {
    seed_health_fixture || return 1
    printf '%s\n' 'user edit' >> "${FIXTURE_HOME}/.claude/CLAUDE.md"
    run_haws status || return 1
    assert_output_contains 'HAWS Status' || return 1
    assert_output_contains 'Last sync: Up to date' || return 1
    assert_output_contains 'Overall: Attention' || return 1
    ! grep -F 'Overall: Ready' "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_status_summary_reports_health_facts_without_sync_state() {
    seed_health_fixture || return 1
    rm -f "${FIXTURE_PROJECT}/.haws/state/sync-state.tsv"
    run_haws status || return 1
    assert_output_contains 'Overall: Attention' || return 1
    assert_output_contains 'Skills: 1 / 1 active' || return 1
    assert_output_contains 'Second Brain: Local-Only' || return 1
    assert_output_contains 'Auto Update: off' || return 1
    assert_output_contains 'Last sync: Never'
}

test_status_derives_second_brain_from_git_remote() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state" "${FIXTURE_PROJECT}/secondbrain"
    printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' \
        > "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    git -C "${FIXTURE_PROJECT}/secondbrain" init -q || return 1
    git -C "${FIXTURE_PROJECT}/secondbrain" remote add origin \
        'file:///tmp/haws-secondbrain-status.git' || return 1
    run_haws status || return 1
    assert_output_contains 'Second Brain: Connected' || return 1
    ! grep -F 'Second Brain: off' "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_status_details_labels_executed_sections() {
    seed_health_fixture || return 1
    run_haws status --details || return 1
    assert_output_contains 'AI Environments' || return 1
    assert_output_contains 'Sources' || return 1
    assert_output_contains 'Skills' || return 1
    grep -E $'^(Ready|Attention|Blocked)\t' "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_doctor_reports_failed_check_instead_of_fixed_ready() {
    seed_health_fixture || return 1
    rm -f "${FIXTURE_HOME}/.claude/CLAUDE.md"
    run_haws doctor || true
    assert_output_contains 'HAWS Doctor' || return 1
    assert_output_contains 'Overall: Attention' || return 1
    grep -E '\[(WARN|BLOCKED)\]' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    ! grep -F 'HEALTHY & READY' "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_doctor_and_status_share_classification() {
    seed_health_fixture || return 1
    printf '%s\n' 'user edit' >> "${FIXTURE_HOME}/.claude/CLAUDE.md"
    run_haws status || return 1
    local status_level
    status_level="$(grep -F 'Overall:' "${OUTPUT_FILE}" | head -1)"
    run_haws doctor || true
    grep -F 'Overall: Attention' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    [ "${status_level}" = 'Overall: Attention' ]
}

if [ -n "${HAWS_STATUS_TEST_ONLY:-}" ]; then
    run_test "${HAWS_STATUS_TEST_ONLY}"
else
    run_test test_health_apis_are_present
    run_test test_doctor_is_the_only_detailed_diagnostics_page
    run_test test_slow_routes_have_explicit_progress_messages
    run_test test_only_commit_msg_hook_is_present
    run_test test_status_and_doctor_preserve_all_fixture_files_and_git_state
    run_test test_status_never_invokes_network_commands
    run_test test_status_reports_current_attention_separately_from_last_sync
    run_test test_status_summary_reports_health_facts_without_sync_state
    run_test test_status_derives_second_brain_from_git_remote
    run_test test_status_details_labels_executed_sections
    run_test test_doctor_reports_failed_check_instead_of_fixed_ready
    run_test test_doctor_and_status_share_classification
fi

echo "CLI Batch 6 status/doctor tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
