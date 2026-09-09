#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/test_helper.sh"
passed=0
failed=0

seed_uninstall_state() {
  mkdir -p "${FIXTURE_REPO}/.haws/state" "${FIXTURE_HOME}/.claude/skills" "${FIXTURE_HOME}/shared"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  printf '%s\n' 'managed' > "${FIXTURE_REPO}/managed-source.txt"
  local managed_hash
  managed_hash="$(_haws_sha256 "${FIXTURE_REPO}/managed-source.txt")"
  printf '%s\n' 'managed' > "${FIXTURE_HOME}/.claude/CLAUDE.md"
  local pointer_hash
  pointer_hash="$(_haws_sha256 "${FIXTURE_HOME}/.claude/CLAUDE.md")"
  ownership_record environments generated-file "${FIXTURE_HOME}/.claude/CLAUDE.md" "${FIXTURE_REPO}/managed-source.txt" "${pointer_hash}"
  printf '%s\n' 'skill' > "${FIXTURE_REPO}/skill-source.txt"
  ln -s "${FIXTURE_REPO}/skill-source.txt" "${FIXTURE_HOME}/.claude/skills/managed"
  if [ -L "${FIXTURE_HOME}/.claude/skills/managed" ]; then
    ownership_record skills symlink "${FIXTURE_HOME}/.claude/skills/managed" "${FIXTURE_REPO}/skill-source.txt" "$(canonical_path "${FIXTURE_REPO}/skill-source.txt")"
  else
    ownership_record skills generated-file "${FIXTURE_HOME}/.claude/skills/managed" "${FIXTURE_REPO}/skill-source.txt" "$(_haws_sha256 "${FIXTURE_HOME}/.claude/skills/managed")"
  fi
  printf '%s\n' "${managed_hash}" > "${FIXTURE_ROOT}/managed.hash"
}

test_uninstall_preview_is_exact_and_nonmutating() {
  new_fixture; load_state_api; . "${PROJECT_ROOT}/runtime/operations.sh"; seed_uninstall_state
  local before after plan
  before="$(find "${FIXTURE_HOME}" -type f -print | sort)"
  plan="$(uninstall_plan)" || return 1
  uninstall_preview "${plan}" || return 1
  after="$(find "${FIXTURE_HOME}" -type f -print | sort)"
  [ "${before}" = "${after}" ]
}

test_default_groups_include_pointers_skills_agents_hooks_and_metadata() {
  new_fixture; load_state_api; . "${PROJECT_ROOT}/runtime/operations.sh"; seed_uninstall_state
  local plan="$(uninstall_plan)"
  assert_file_contains "${plan}" $'remove\tenvironments' || return 1
  grep -F $'remove\tskills' "${plan}" >/dev/null
}

test_user_can_deselect_each_group() {
  new_fixture; load_state_api; . "${PROJECT_ROOT}/runtime/operations.sh"; seed_uninstall_state
  local plan="$(uninstall_plan skills)"
  ! grep -F $'remove\tenvironments' "${plan}" >/dev/null 2>&1
}

test_matching_owned_link_is_removed() {
  new_fixture; load_state_api; . "${PROJECT_ROOT}/runtime/operations.sh"; seed_uninstall_state
  local plan="$(uninstall_plan skills)"
  uninstall_apply "${plan}" || return 1
  [ ! -L "${FIXTURE_HOME}/.claude/skills/managed" ]
}

test_modified_generated_file_is_preserved() {
  new_fixture; load_state_api; . "${PROJECT_ROOT}/runtime/operations.sh"; seed_uninstall_state
  printf '%s\n' changed >> "${FIXTURE_HOME}/.claude/CLAUDE.md"
  local plan="$(uninstall_plan pointers)"
  uninstall_apply "${plan}" || return 1
  [ -f "${FIXTURE_HOME}/.claude/CLAUDE.md" ]
}

test_repo_sources_and_second_brain_are_preserved_by_default() {
  new_fixture; load_state_api; . "${PROJECT_ROOT}/runtime/operations.sh"; seed_uninstall_state
  mkdir -p "${FIXTURE_REPO}/secondbrain"; printf note > "${FIXTURE_REPO}/secondbrain/note.md"
  local plan="$(uninstall_plan)"; uninstall_apply "${plan}" || return 1
  [ -f "${FIXTURE_REPO}/managed-source.txt" ] && [ -f "${FIXTURE_REPO}/secondbrain/note.md" ]
}

test_direct_uninstall_uses_same_preview_confirm_apply_path() {
  new_fixture; seed_uninstall_state
  export HAWS_TEST_KEYS=yes
  run_haws uninstall skills || return 1
  assert_output_contains "Uninstall preview" || return 1
  [ ! -L "${FIXTURE_HOME}/.claude/skills/managed" ]
}

run_test() { local name="$1"; if "$name"; then echo "PASS ${name}"; passed=$((passed + 1)); else echo "FAIL ${name}"; failed=$((failed + 1)); fi; cleanup_fixture; }
trap cleanup_fixture EXIT
run_test test_uninstall_preview_is_exact_and_nonmutating
run_test test_default_groups_include_pointers_skills_agents_hooks_and_metadata
run_test test_user_can_deselect_each_group
run_test test_matching_owned_link_is_removed
run_test test_modified_generated_file_is_preserved
run_test test_repo_sources_and_second_brain_are_preserved_by_default
run_test test_direct_uninstall_uses_same_preview_confirm_apply_path
echo "CLI uninstall tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
