#!/usr/bin/env bash
# Batch 6 ownership-aware uninstall tests.

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${TEST_DIR}/test_helper.sh"

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
        HAWS_TEST_KEYS="${HAWS_TEST_KEYS:-}" PATH="${PATH}" \
        bash "${FIXTURE_PROJECT}/haws.sh" "$@" >"${OUTPUT_FILE}" 2>&1
}

run_haws_with_input() {
    printf '%s' "$1" | env HOME="${FIXTURE_HOME}" HAWS_REPO_DIR="${FIXTURE_PROJECT}" \
        HAWS_STATE_DIR="${FIXTURE_PROJECT}/.haws/state" HAWS_TEST_KEYS= PATH="${PATH}" \
        bash "${FIXTURE_PROJECT}/haws.sh" "${@:2}" >"${OUTPUT_FILE}" 2>&1
}

seed_uninstall_state() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state" \
        "${FIXTURE_HOME}/.claude/skills" "${FIXTURE_HOME}/shared"
    printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' \
        > "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
    printf 'schema=1\tcompleted_at=now\n' \
        > "${FIXTURE_PROJECT}/.haws/state/install.complete"
    printf '%s\n' 'managed' > "${FIXTURE_PROJECT}/managed-source.txt"
    printf '%s\n' 'managed' > "${FIXTURE_HOME}/.claude/CLAUDE.md"
    source_haws || return 1
    local pointer_hash
    pointer_hash="$(_haws_sha256 "${FIXTURE_HOME}/.claude/CLAUDE.md")"
    ownership_record environments generated-file \
        "${FIXTURE_HOME}/.claude/CLAUDE.md" \
        "${FIXTURE_PROJECT}/managed-source.txt" "${pointer_hash}" || return 1

    printf '%s\n' 'skill' > "${FIXTURE_PROJECT}/skill-source.txt"
    local skill_link="${FIXTURE_HOME}/.claude/skills/managed"
    if ln -s "${FIXTURE_PROJECT}/skill-source.txt" "${skill_link}" 2>/dev/null &&
        [ -L "${skill_link}" ]; then
        ownership_record skills symlink "${skill_link}" \
            "${FIXTURE_PROJECT}/skill-source.txt" \
            "$(readlink "${skill_link}")" || return 1
    else
        rm -f "${skill_link}"
        printf '%s\n' 'skill' > "${skill_link}"
        ownership_record skills generated-file "${skill_link}" \
            "${FIXTURE_PROJECT}/skill-source.txt" \
            "$(_haws_sha256 "${skill_link}")" || return 1
    fi
    printf '%s\n' 'unrelated' > "${FIXTURE_HOME}/.claude/skills/unrelated"
}

test_uninstall_apis_are_present() {
    source_haws || return 1
    for api in uninstall_plan uninstall_preview uninstall_apply; do
        declare -F "${api}" >/dev/null || return 1
    done
}

test_uninstall_preview_is_nonmutating() {
    seed_uninstall_state || return 1
    local plan before after state_before state_after
    state_before="$(find "${FIXTURE_PROJECT}/.haws/state" -type f -print0 2>/dev/null |
        sort -z |
        while IFS= read -r -d '' path; do sha256sum "${path}"; done)"
    before="$(sha256sum "${FIXTURE_HOME}/.claude/CLAUDE.md" \
        "${FIXTURE_HOME}/.claude/skills/managed" 2>/dev/null || true)"
    plan="$(uninstall_plan skills)" || return 1
    uninstall_preview "${plan}" >"${OUTPUT_FILE}" 2>&1 || return 1
    after="$(sha256sum "${FIXTURE_HOME}/.claude/CLAUDE.md" \
        "${FIXTURE_HOME}/.claude/skills/managed" 2>/dev/null || true)"
    state_after="$(find "${FIXTURE_PROJECT}/.haws/state" -type f -print0 2>/dev/null |
        sort -z |
        while IFS= read -r -d '' path; do sha256sum "${path}"; done)"
    [ "${before}" = "${after}" ] || return 1
    [ "${state_before}" = "${state_after}" ] || return 1
    assert_output_contains 'Uninstall preview'
}

test_default_groups_are_ownership_only() {
    seed_uninstall_state || return 1
    local plan
    plan="$(uninstall_plan)" || return 1
    grep -F $'remove\tenvironments' "${plan}" >/dev/null || return 1
    grep -F $'remove\tskills' "${plan}" >/dev/null || return 1
    awk -F $'\t' '$1 == "remove" && $4 ~ /managed-source[.]txt/ {found=1}
        END {exit found + 0}' "${plan}"
}

test_matching_owned_link_or_generated_file_is_removed() {
    seed_uninstall_state || return 1
    source_haws || return 1
    local plan
    plan="$(uninstall_plan skills)" || return 1
    uninstall_apply "${plan}" >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.claude/skills/managed"
}

test_modified_owned_file_is_preserved() {
    seed_uninstall_state || return 1
    printf '%s\n' changed >> "${FIXTURE_HOME}/.claude/CLAUDE.md"
    source_haws || return 1
    local plan
    plan="$(uninstall_plan pointers)" || return 1
    uninstall_apply "${plan}" >"${OUTPUT_FILE}" 2>&1 || return 1
    [ -f "${FIXTURE_HOME}/.claude/CLAUDE.md" ] || return 1
    assert_output_contains 'Preserved'
}

test_unrelated_files_and_second_brain_are_preserved() {
    seed_uninstall_state || return 1
    mkdir -p "${FIXTURE_PROJECT}/secondbrain"
    printf '%s\n' note > "${FIXTURE_PROJECT}/secondbrain/note.md"
    source_haws || return 1
    local plan
    plan="$(uninstall_plan)" || return 1
    uninstall_apply "${plan}" >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_file_contains "${FIXTURE_HOME}/.claude/skills/unrelated" 'unrelated' || return 1
    assert_file_contains "${FIXTURE_PROJECT}/secondbrain/note.md" 'note'
}

test_dirty_owned_repository_is_blocked() {
    seed_uninstall_state || return 1
    local owned_repo="${FIXTURE_PROJECT}/owned repository"
    mkdir -p "${owned_repo}"
    git -C "${owned_repo}" init -q || return 1
    git -C "${owned_repo}" config user.name HAWS-Test
    git -C "${owned_repo}" config user.email test@example.invalid
    printf '%s\n' clean > "${owned_repo}/README.md"
    git -C "${owned_repo}" add README.md || return 1
    git -C "${owned_repo}" commit -qm baseline || return 1
    local head
    head="$(git -C "${owned_repo}" rev-parse HEAD)"
    source_haws || return 1
    ownership_record repositories repository "${owned_repo}" "${owned_repo}" "${head}" || return 1
    printf '%s\n' dirty >> "${owned_repo}/README.md"
    local plan
    plan="$(uninstall_plan repositories)" || return 1
    uninstall_apply "${plan}" >"${OUTPUT_FILE}" 2>&1 || true
    assert_output_contains 'Blocked' || return 1
    [ -d "${owned_repo}/.git" ]
}

test_interrupted_apply_keeps_remaining_records_recoverable() {
    seed_uninstall_state || return 1
    printf '%s\n' second > "${FIXTURE_HOME}/.claude/second-owned"
    source_haws || return 1
    ownership_record skills generated-file "${FIXTURE_HOME}/.claude/second-owned" \
        "${FIXTURE_PROJECT}/second-source.txt" \
        "$(_haws_sha256 "${FIXTURE_HOME}/.claude/second-owned")" || return 1
    local plan
    plan="$(uninstall_plan skills)" || return 1
    HAWS_TEST_UNINSTALL_INTERRUPT_AFTER=1 \
        uninstall_apply "${plan}" >"${OUTPUT_FILE}" 2>&1 || true
    assert_output_contains 'Interrupted' || return 1
    [ -f "${FIXTURE_HOME}/.claude/second-owned" ] || return 1
    ownership_list skills | grep -F 'second-owned' >/dev/null
}

test_direct_uninstall_requires_preview_confirmation_and_applies() {
    seed_uninstall_state || return 1
    HAWS_TEST_KEYS=y run_haws uninstall skills || return 1
    assert_output_contains 'Uninstall preview' || return 1
    assert_output_contains '=============================================================' || return 1
    assert_output_contains '                   HAWS Uninstall Preview' || return 1
    assert_output_contains '[SAFETY GUARD]' || return 1
    assert_output_contains 'Your project code and Second Brain will NOT be deleted.' || return 1
    assert_output_contains '[*] Applying uninstall changes, please wait...' || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.claude/skills/managed"
    assert_file_contains "${FIXTURE_HOME}/.claude/skills/unrelated" 'unrelated'
}

test_default_confirmation_cancels_safely() {
    seed_uninstall_state || return 1
    run_haws_with_input $'\n' uninstall skills || return 1
    grep -F 'Do you really want to proceed with uninstallation? (y/N):' \
        "${FIXTURE_PROJECT}/haws.sh" >/dev/null || return 1
    assert_output_contains 'Uninstall cancelled' || return 1
    [ -e "${FIXTURE_HOME}/.claude/skills/managed" ] ||
        [ -L "${FIXTURE_HOME}/.claude/skills/managed" ] || return 1
}

test_confirmation_accepts_only_y_or_y_uppercase() {
    seed_uninstall_state || return 1
    HAWS_TEST_KEYS=yes run_haws uninstall skills || return 1
    assert_output_contains 'Uninstall cancelled' || return 1
    [ -e "${FIXTURE_HOME}/.claude/skills/managed" ] ||
        [ -L "${FIXTURE_HOME}/.claude/skills/managed" ] || return 1
}

test_legacy_uninstall_route_is_removed() {
    source_haws || return 1
    ! declare -F legacy_run_uninstall >/dev/null 2>&1
}

test_direct_dry_run_never_removes_owned_item() {
    seed_uninstall_state || return 1
    local state_before state_after
    state_before="$(find "${FIXTURE_PROJECT}/.haws/state" -type f -print0 2>/dev/null |
        sort -z |
        while IFS= read -r -d '' path; do sha256sum "${path}"; done)"
    run_haws uninstall skills --dry-run || return 1
    state_after="$(find "${FIXTURE_PROJECT}/.haws/state" -type f -print0 2>/dev/null |
        sort -z |
        while IFS= read -r -d '' path; do sha256sum "${path}"; done)"
    assert_output_contains 'Uninstall preview' || return 1
    [ "${state_before}" = "${state_after}" ] || return 1
    [ -e "${FIXTURE_HOME}/.claude/skills/managed" ] || [ -L "${FIXTURE_HOME}/.claude/skills/managed" ]
}

run_test test_uninstall_apis_are_present
run_test test_uninstall_preview_is_nonmutating
run_test test_default_groups_are_ownership_only
run_test test_matching_owned_link_or_generated_file_is_removed
run_test test_modified_owned_file_is_preserved
run_test test_unrelated_files_and_second_brain_are_preserved
run_test test_dirty_owned_repository_is_blocked
run_test test_interrupted_apply_keeps_remaining_records_recoverable
run_test test_direct_uninstall_requires_preview_confirmation_and_applies
run_test test_default_confirmation_cancels_safely
run_test test_confirmation_accepts_only_y_or_y_uppercase
run_test test_legacy_uninstall_route_is_removed
run_test test_direct_dry_run_never_removes_owned_item

echo "CLI Batch 6 uninstall tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
