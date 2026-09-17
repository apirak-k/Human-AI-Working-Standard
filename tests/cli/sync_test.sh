#!/usr/bin/env bash
# Batch 5 explicit Sync/Update behavior tests.

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
FIXTURE_ROOT=""
FIXTURE_HOME=""
FIXTURE_REPO=""
OUTPUT_FILE=""
passed=0
failed=0

fail() {
    echo "FAIL: $*" >&2
    return 1
}

create_fixture() {
    FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/haws-batch5.XXXXXX")"
    FIXTURE_HOME="${FIXTURE_ROOT}/home"
    FIXTURE_REPO="${FIXTURE_ROOT}/project"
    OUTPUT_FILE="${FIXTURE_ROOT}/output.txt"
    mkdir -p "${FIXTURE_HOME}" "${FIXTURE_REPO}"
    cp "${PROJECT_ROOT}/haws.sh" "${FIXTURE_REPO}/haws.sh"
    git init -q "${FIXTURE_REPO}"
    git -C "${FIXTURE_REPO}" config user.name HAWS-Test
    git -C "${FIXTURE_REPO}" config user.email test@example.invalid
    : > "${FIXTURE_REPO}/.gitmodules"
}

cleanup_fixture() {
    if [ -n "${FIXTURE_ROOT}" ] && [ -d "${FIXTURE_ROOT}" ]; then
        rm -rf -- "${FIXTURE_ROOT}"
    fi
    unset HAWS_REPO_DIR HAWS_STATE_DIR HAWS_SOURCE_ONLY HAWS_TEST_SYNC_DELAY \
        HAWS_AUTO_UPDATE AUTO_UPDATE HAWS_SECOND_BRAIN_ENABLED HAWS_SYNC_PREFETCH_DONE
    FIXTURE_ROOT=""
    FIXTURE_HOME=""
    FIXTURE_REPO=""
    OUTPUT_FILE=""
}

source_haws() {
    export HOME="${FIXTURE_HOME}"
    export HAWS_REPO_DIR="${FIXTURE_REPO}"
    export HAWS_STATE_DIR="${FIXTURE_REPO}/.haws/state"
    export HAWS_SOURCE_ONLY=1
    # shellcheck disable=SC1091
    . "${FIXTURE_REPO}/haws.sh"
    unset HAWS_SOURCE_ONLY
}

write_settings() {
    local auto_update="$1"
    mkdir -p "${FIXTURE_REPO}/.haws/state"
    printf 'schema_version\t1\nsecond_brain\toff\nauto_update\t%s\n' \
        "${auto_update}" > "${FIXTURE_REPO}/.haws/state/settings.tsv"
}

add_source() {
    local name="$1"
    local seed="${FIXTURE_ROOT}/seed-${name}"
    local remote="${FIXTURE_ROOT}/${name}.git"
    local source="${FIXTURE_REPO}/skills/packs/${name}"
    mkdir -p "${seed}" "$(dirname "${source}")"
    git init --bare -q "${remote}"
    git init -q "${seed}"
    git -C "${seed}" config user.name HAWS-Test
    git -C "${seed}" config user.email test@example.invalid
    git -C "${seed}" checkout -q -b main
    printf '%s\n' '---' "name: ${name}" 'description: baseline' '---' \
        > "${seed}/SKILL.md"
    git -C "${seed}" add SKILL.md
    git -C "${seed}" commit -q -m baseline
    git -C "${seed}" remote add origin "${remote}"
    git -C "${seed}" push -q -u origin main
    git --git-dir="${remote}" symbolic-ref HEAD refs/heads/main
    git clone -q "${remote}" "${source}"
    printf '[submodule "%s"]\n\tpath = skills/packs/%s\n\turl = %s\n' \
        "${name}" "${name}" "${remote}" >> "${FIXTURE_REPO}/.gitmodules"
}

add_second_brain() {
    local seed="${FIXTURE_ROOT}/seed-secondbrain"
    local remote="${FIXTURE_ROOT}/secondbrain.git"
    mkdir -p "${seed}"
    git init --bare -q "${remote}"
    git init -q "${seed}"
    git -C "${seed}" config user.name HAWS-Test
    git -C "${seed}" config user.email test@example.invalid
    git -C "${seed}" checkout -q -b main
    printf '%s\n' '# Preferences' > "${seed}/USER_PREFERENCES.md"
    git -C "${seed}" add USER_PREFERENCES.md
    git -C "${seed}" commit -q -m baseline
    git -C "${seed}" remote add origin "${remote}"
    git -C "${seed}" push -q -u origin main
    git --git-dir="${remote}" symbolic-ref HEAD refs/heads/main
    git clone -q "${remote}" "${FIXTURE_REPO}/secondbrain"
}

advance_source() {
    local name="$1"
    local content="${2:-updated}"
    local seed="${FIXTURE_ROOT}/seed-${name}"
    printf '%s\n' '---' "name: ${name}" "description: ${content}" '---' \
        > "${seed}/SKILL.md"
    git -C "${seed}" add SKILL.md
    git -C "${seed}" commit -q -m "update ${name}"
    git -C "${seed}" push -q origin main
    git -C "${seed}" rev-parse HEAD
}

delete_source_entrypoint() {
    local name="$1"
    local seed="${FIXTURE_ROOT}/seed-${name}"
    rm -f -- "${seed}/SKILL.md"
    git -C "${seed}" add -A
    git -C "${seed}" commit -q -m "remove ${name} entrypoint"
    git -C "${seed}" push -q origin main
    git -C "${seed}" rev-parse HEAD
}

source_head() {
    git -C "${FIXTURE_REPO}/skills/packs/$1" rev-parse HEAD
}

source_remote_head() {
    git -C "${FIXTURE_REPO}/skills/packs/$1" rev-parse refs/remotes/origin/main
}

assert_record() {
    local target="$1"
    local result="$2"
    local file="${FIXTURE_REPO}/.haws/state/sync-state.tsv"
    [ -f "${file}" ] || return 1
    awk -F '\t' -v target="${target}" -v result="${result}" \
        '$2 == target && $3 == result { found = 1 } END { exit found ? 0 : 1 }' \
        "${file}"
}

run_sync_process() {
    local command="${1:-sync}"
    env HOME="${FIXTURE_HOME}" HAWS_REPO_DIR="${FIXTURE_REPO}" \
        HAWS_STATE_DIR="${FIXTURE_REPO}/.haws/state" PATH="${PATH}" \
        bash "${FIXTURE_REPO}/haws.sh" "${command}" >"${OUTPUT_FILE}" 2>&1
}

test_sync_output_has_sections_and_summary() {
    local source="${PROJECT_ROOT}/haws.sh"
    local sync_block
    sync_block="$(sed -n '/^sync_run() {/,/^run_sync() {/p' "${source}")"
    printf '%s\n' "${sync_block}" | grep -Fq 'OPTIONS' || return 1
    printf '%s\n' "${sync_block}" | grep -Fq 'TARGET' || return 1
    printf '%s\n' "${sync_block}" | grep -Fq 'SUMMARY' || return 1
    printf '%s\n' "${sync_block}" | grep -Fq 'Updated' || return 1
}

test_sync_uses_short_bootstrap_style_phases() {
    local source="${PROJECT_ROOT}/haws.sh"
    local sync_block
    sync_block="$(sed -n '/^run_sync() {/,/^run_edit_gitmodules() {/p' "${source}")"
    printf '%s\n' "${sync_block}" | grep -Fq 'Step 1:' || return 1
    printf '%s\n' "${sync_block}" | grep -Fq 'Step 2:' || return 1
    printf '%s\n' "${sync_block}" | grep -Fq 'Step 5:' || return 1
}

test_sync_result_defines_full_header_and_navigation_contract() {
    local source="${PROJECT_ROOT}/haws.sh"
    local sync_block wait_block
    sync_block="$(sed -n '/^run_sync() {/,/^run_edit_gitmodules() {/p' "${source}")"
    wait_block="$(sed -n '/^_haws_wait_for_result() {/,/^status_run() {/p' "${source}")"
    printf '%s\n' "${sync_block}" | grep -Fq 'HAWS Sync Result' || return 1
    printf '%s\n' "${sync_block}" | grep -Fq '=============================================================' || return 1
    printf '%s\n' "${wait_block}" | grep -Fq '[Q] Return to Home' || return 1
    printf '%s\n' "${wait_block}" | grep -Fq '[Any key] Exit CLI' || return 1
    printf '%s\n' "${wait_block}" | grep -Fq 'q|Q' || return 1
}

test_sync_result_wait_does_not_replace_sync_exit_status() {
    local source="${PROJECT_ROOT}/haws.sh"
    local sync_block
    sync_block="$(sed -n '/^run_sync() {/,/^run_edit_gitmodules() {/p' "${source}")"
    printf '%s\n' "${sync_block}" | grep -Fq 'wait_status' || return 1
    printf '%s\n' "${sync_block}" | grep -Fq 'return "${sync_status}"' || return 1
}

test_direct_sync_prints_result_without_entering_home() {
    write_settings off
    run_sync_process sync || return 1
    local banner_line summary_line
    banner_line="$(grep -nF 'HAWS Sync Result' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    summary_line="$(grep -nF 'SUMMARY' "${OUTPUT_FILE}" | tail -n 1 | cut -d: -f1)"
    [ -n "${banner_line}" ] && [ -n "${summary_line}" ] && [ "${banner_line}" -lt "${summary_line}" ] || return 1
    ! grep -F '(on)' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    ! grep -F '(off)' "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_sync_runs_phases_in_order_and_configures_hooks() {
    mkdir -p "${FIXTURE_REPO}/.githooks"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${FIXTURE_REPO}/.githooks/commit-msg"
    chmod +x "${FIXTURE_REPO}/.githooks/commit-msg"
    write_settings off
    run_sync_process sync || return 1

    local banner_line step1 step2 step3 step4 step5
    banner_line="$(grep -nF 'HAWS SYNC' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    step1="$(grep -nF '[*] Step 1:' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    step2="$(grep -nF '[*] Step 2:' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    step3="$(grep -nF '[*] Step 3:' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    step4="$(grep -nF '[*] Step 4:' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    step5="$(grep -nF '[*] Step 5:' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    [ -n "${banner_line}" ] && [ -n "${step1}" ] && [ "${banner_line}" -lt "${step1}" ] || return 1
    [ "${step1}" -lt "${step2}" ] || return 1
    [ "${step2}" -lt "${step3}" ] && [ "${step3}" -lt "${step4}" ] || return 1
    [ "${step4}" -lt "${step5}" ] || return 1
    grep -F '[PASS] Git safety hooks configured' "${OUTPUT_FILE}" >/dev/null || return 1
    [ "$(git -C "${FIXTURE_REPO}" config --get core.hooksPath)" = .githooks ]
}

test_sync_target_rows_use_batch_result_markers() {
    source_haws || return 1
    SYNC_SUMMARY_UPDATED=0
    SYNC_SUMMARY_UP_TO_DATE=0
    SYNC_SUMMARY_SKIPPED=0
    SYNC_SUMMARY_BLOCKED=0
    SYNC_SUMMARY_FAILED=0
    SYNC_SUMMARY_TIMEOUT=0
    local result marker label
    for result in updated up-to-date skipped blocked failed timeout; do
        case "${result}" in
            updated) marker='[PASS]'; label=Updated ;;
            up-to-date) marker='[PASS]'; label=Up-to-date ;;
            skipped) marker='[WARN]'; label=Skipped ;;
            blocked) marker='[BLOCKED]'; label=Blocked ;;
            failed) marker='[FAIL]'; label=Failed ;;
            timeout) marker='[WARN]'; label=Timeout ;;
        esac
        _sync_present_result "target-${result}" "${result}" detail >>"${OUTPUT_FILE}"
        grep -F "target-${result}" "${OUTPUT_FILE}" >/dev/null || return 1
        grep -F "${marker} ${label}" "${OUTPUT_FILE}" >/dev/null || return 1
        grep -F detail "${OUTPUT_FILE}" >/dev/null || return 1
    done
}

test_sync_apis_are_present() {
    source_haws || return 1
    for api in run_with_deadline source_preflight source_candidate_validate \
        sync_target sync_result_write sync_run; do
        declare -F "${api}" >/dev/null || return 1
    done
}

test_clean_source_applies_remote_revision() {
    add_source clean
    local target="clean::skills/packs/clean"
    local old_head new_head
    new_head="$(advance_source clean valid)" || return 1
    old_head="$(source_head clean)" || return 1
    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1
    [ "$(source_head clean)" = "${new_head}" ] || return 1
    [ "$(source_head clean)" != "${old_head}" ] || return 1
    grep -F 'description: valid' "${FIXTURE_REPO}/skills/packs/clean/SKILL.md" >/dev/null || return 1
    assert_record "${target}" updated
}

test_up_to_date_requires_measured_head_equality() {
    add_source current
    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_record "current::skills/packs/current" up-to-date
}

test_dirty_source_is_blocked_while_clean_source_continues() {
    add_source dirty
    add_source safe
    local dirty_target="dirty::skills/packs/dirty"
    local safe_target="safe::skills/packs/safe"
    local dirty_head safe_head
    dirty_head="$(advance_source dirty dirty-remote)" || return 1
    safe_head="$(advance_source safe safe-remote)" || return 1
    printf 'local change\n' >> "${FIXTURE_REPO}/skills/packs/dirty/SKILL.md"
    : > "${FIXTURE_REPO}/skills/packs/dirty/untracked.txt"
    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1
    local status=$?
    [ "${status}" -ne 0 ] || return 1
    [ "$(source_head dirty)" != "${dirty_head}" ] || return 1
    [ "$(source_head safe)" = "${safe_head}" ] || return 1
    assert_record "${dirty_target}" blocked || return 1
    assert_record "${safe_target}" updated
}

test_missing_candidate_entrypoint_does_not_fall_back_to_old_content() {
    add_source missing
    local old_head candidate_head
    old_head="$(source_head missing)" || return 1
    candidate_head="$(delete_source_entrypoint missing)" || return 1
    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1
    local status=$?
    [ "${status}" -ne 0 ] || return 1
    [ "$(source_head missing)" = "${old_head}" ] || return 1
    [ -f "${FIXTURE_REPO}/skills/packs/missing/SKILL.md" ] || return 1
    [ "$(source_head missing)" != "${candidate_head}" ] || return 1
    assert_record "missing::skills/packs/missing" failed
}

test_deadline_returns_distinct_timeout_status() {
    source_haws || return 1
    run_with_deadline 1 bash -c 'sleep 2'
    [ "$?" -eq 124 ]
}

test_timeout_uses_local_fallback_without_failure() {
    add_source localfallback
    local old_head
    old_head="$(source_head localfallback)" || return 1
    write_settings on
    source_haws || return 1
    HAWS_SYNC_TIMEOUT_SECONDS=1 HAWS_TEST_SYNC_FETCH_DELAY=2 \
        sync_run >"${OUTPUT_FILE}" 2>&1
    [ "$?" -eq 0 ] || return 1
    [ "$(source_head localfallback)" = "${old_head}" ] || return 1
    grep -F 'Local fallback' "${OUTPUT_FILE}" >/dev/null || return 1
}

test_auto_update_off_skips_remote_work_but_runs_explicit_sync() {
    add_source disabled
    local old_head remote_head
    advance_source disabled skipped-update >/dev/null || return 1
    old_head="$(source_head disabled)" || return 1
    remote_head="$(source_remote_head disabled)" || return 1
    write_settings off
    run_sync_process sync || return 1
    [ "$(source_head disabled)" = "${old_head}" ] || return 1
    [ "$(source_remote_head disabled)" = "${remote_head}" ] || return 1
    assert_record "disabled::skills/packs/disabled" skipped || return 1
    grep -F '[INFO] Skipped' "${OUTPUT_FILE}" >/dev/null || return 1
    grep -F 'Auto Update is disabled' "${OUTPUT_FILE}" >/dev/null || return 1
    ! grep -F 'Auto Update is disabled' "${OUTPUT_FILE}" | grep -F '[WARN]' >/dev/null
}

test_second_brain_update_applies_remote_revision() {
    add_second_brain
    local seed="${FIXTURE_ROOT}/seed-secondbrain"
    printf '%s\n' 'remote note' > "${seed}/REMOTE_NOTE.md"
    git -C "${seed}" add REMOTE_NOTE.md
    git -C "${seed}" commit -q -m "remote brain update"
    local new_head
    git -C "${seed}" push -q origin main || return 1
    new_head="$(git -C "${seed}" rev-parse HEAD)" || return 1
    mkdir -p "${FIXTURE_REPO}/.haws/state"
    printf 'schema_version\t1\nsecond_brain\ton\nauto_update\toff\n' \
        > "${FIXTURE_REPO}/.haws/state/settings.tsv"
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1
    [ "$(git -C "${FIXTURE_REPO}/secondbrain" rev-parse HEAD)" = "${new_head}" ] || return 1
    [ -f "${FIXTURE_REPO}/secondbrain/REMOTE_NOTE.md" ] || return 1
    assert_record secondbrain updated
}

test_explicit_update_uses_same_safe_application() {
    add_source update
    local new_head
    new_head="$(advance_source update explicit-update)" || return 1
    write_settings on
    run_sync_process update || return 1
    [ "$(source_head update)" = "${new_head}" ] || return 1
    assert_record "update::skills/packs/update" updated
}

test_haws_update_preserves_the_current_branch() {
    local remote="${FIXTURE_ROOT}/haws.git"
    local seed="${FIXTURE_ROOT}/haws-seed"
    git init --bare -q "${remote}" || return 1
    git -C "${FIXTURE_REPO}" checkout -q -b main || return 1
    git -C "${FIXTURE_REPO}" add haws.sh .gitmodules || return 1
    git -C "${FIXTURE_REPO}" commit -q -m baseline || return 1
    git -C "${FIXTURE_REPO}" remote add origin "${remote}" || return 1
    git -C "${FIXTURE_REPO}" push -q -u origin main || return 1
    git --git-dir="${remote}" symbolic-ref HEAD refs/heads/main || return 1
    git clone -q "${remote}" "${seed}" || return 1
    git -C "${seed}" config user.name HAWS-Test
    git -C "${seed}" config user.email test@example.invalid
    printf '\n# remote update fixture\n' >> "${seed}/haws.sh"
    git -C "${seed}" add haws.sh || return 1
    git -C "${seed}" commit -q -m update || return 1
    git -C "${seed}" push -q origin main || return 1
    local expected
    expected="$(git -C "${seed}" rev-parse HEAD)" || return 1

    source_haws || return 1
    HAWS_AUTO_UPDATE=on
    sync_target haws >"${OUTPUT_FILE}" 2>&1
    local sync_status=$?
    [ "${sync_status}" -eq 0 ] || return 1
    local actual_branch actual_head
    actual_branch="$(git -C "${FIXTURE_REPO}" symbolic-ref --short HEAD 2>/dev/null || true)"
    actual_head="$(git -C "${FIXTURE_REPO}" rev-parse HEAD 2>/dev/null || true)"
    [ "${actual_branch}" = main ] || {
        echo "expected HAWS update to preserve branch main, got: ${actual_branch:-detached}" >&2
        return 1
    }
    [ "${actual_head}" = "${expected}" ] || {
        echo "expected HAWS HEAD ${expected}, got: ${actual_head:-missing}" >&2
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    assert_record haws updated
}

test_path_scoped_diff_skips_checkout_when_active_skills_unchanged() {
    add_source partial
    local seed="${FIXTURE_ROOT}/seed-partial"
    local old_head
    old_head="$(source_head partial)" || return 1
    printf 'remote non-skill change\n' > "${seed}/README.md"
    git -C "${seed}" add README.md
    git -C "${seed}" commit -q -m "update docs only"
    git -C "${seed}" push -q origin main || return 1
    local new_head
    new_head="$(git -C "${seed}" rev-parse HEAD)" || return 1

    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1

    [ "$(source_head partial)" = "${old_head}" ] || return 1
    [ "$(source_head partial)" != "${new_head}" ] || return 1
    assert_record "partial::skills/packs/partial" up-to-date || return 1
    grep -F "active skills unchanged" "${FIXTURE_REPO}/.haws/state/sync-state.tsv" >/dev/null
}

test_lock_releases_after_success_and_failure() {
    add_source success
    write_settings off
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1
    [ ! -d "${FIXTURE_REPO}/.haws/state/sync.lock" ] || return 1

    add_source failure
    delete_source_entrypoint failure >/dev/null || return 1
    write_settings on
    sync_run >"${OUTPUT_FILE}" 2>&1
    [ "$?" -ne 0 ] || return 1
    [ ! -d "${FIXTURE_REPO}/.haws/state/sync.lock" ]
}

test_lock_releases_after_interrupt() {
    add_source interrupted
    write_settings off
    env HOME="${FIXTURE_HOME}" HAWS_REPO_DIR="${FIXTURE_REPO}" \
        HAWS_STATE_DIR="${FIXTURE_REPO}/.haws/state" HAWS_TEST_SYNC_DELAY=5 \
        PATH="${PATH}" bash "${FIXTURE_REPO}/haws.sh" sync >"${OUTPUT_FILE}" 2>&1 &
    local child=$!
    local ready=0
    for _ in $(seq 1 50); do
        if [ -d "${FIXTURE_REPO}/.haws/state/sync.lock" ]; then
            ready=1
            break
        fi
        sleep 0.1
    done
    [ "${ready}" -eq 1 ] || { kill "${child}" 2>/dev/null || true; wait "${child}" 2>/dev/null || true; return 1; }
    kill -TERM "${child}" 2>/dev/null || true
    wait "${child}"
    local status=$?
    [ "${status}" -ne 0 ] || return 1
    [ ! -d "${FIXTURE_REPO}/.haws/state/sync.lock" ]
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

if [ -n "${HAWS_SYNC_TEST_ONLY:-}" ]; then
    run_test "${HAWS_SYNC_TEST_ONLY}"
else
    run_test test_sync_apis_are_present
    run_test test_sync_output_has_sections_and_summary
    run_test test_sync_uses_short_bootstrap_style_phases
    run_test test_sync_result_defines_full_header_and_navigation_contract
    run_test test_sync_result_wait_does_not_replace_sync_exit_status
    run_test test_direct_sync_prints_result_without_entering_home
    run_test test_sync_runs_phases_in_order_and_configures_hooks
    run_test test_sync_target_rows_use_batch_result_markers
    run_test test_clean_source_applies_remote_revision
    run_test test_up_to_date_requires_measured_head_equality
    run_test test_dirty_source_is_blocked_while_clean_source_continues
    run_test test_missing_candidate_entrypoint_does_not_fall_back_to_old_content
    run_test test_deadline_returns_distinct_timeout_status
    run_test test_timeout_uses_local_fallback_without_failure
    run_test test_auto_update_off_skips_remote_work_but_runs_explicit_sync
    run_test test_second_brain_update_applies_remote_revision
    run_test test_explicit_update_uses_same_safe_application
    run_test test_haws_update_preserves_the_current_branch
    run_test test_path_scoped_diff_skips_checkout_when_active_skills_unchanged
    run_test test_lock_releases_after_success_and_failure
    run_test test_lock_releases_after_interrupt
fi

echo "CLI Batch 5 sync tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
