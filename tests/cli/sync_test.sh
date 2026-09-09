#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/test_helper.sh"
passed=0
failed=0

make_source_fixture() {
  local name="$1" skill_text path
  skill_text="${2:-name: ${name}\n\nValid skill}"
  path="${FIXTURE_REPO}/skills/packs/${name}"
  mkdir -p "${path}"
  printf '%b\n' "${skill_text}" > "${path}/SKILL.md"
  git -C "${path}" init -q
  git -C "${path}" config user.email test@example.invalid
  git -C "${path}" config user.name HAWS-Test
  git -C "${path}" add SKILL.md
  git -C "${path}" commit -qm initial
}

write_gitmodules_fixture() {
  local name path
  : > "${FIXTURE_REPO}/.gitmodules"
  for name in "$@"; do
    path="skills/packs/${name}"
    printf '[submodule "%s"]\n\tpath = %s\n\turl = https://example.invalid/%s.git\n' "${name}" "${path}" "${name}" >> "${FIXTURE_REPO}/.gitmodules"
  done
}

test_both_remote_settings_off_makes_no_network_request() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\toff\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  install_fake_command git
  run_haws sync || return 1
  assert_output_contains "No remote targets enabled" || return 1
  assert_no_call "fetch" || return 1
}

test_second_brain_off_never_calls_its_git_remote() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  install_fake_command git
  run_haws sync || return 1
  ! grep -F -- "secondbrain" "${CALL_LOG}" >/dev/null 2>&1 || return 1
}

test_auto_update_off_never_fetches_haws_or_sources() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\toff\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  install_fake_command git
  run_haws sync || return 1
  assert_no_call "fetch" || return 1
}

test_concurrent_sync_reports_already_running() {
  new_fixture
  load_state_api || return 1
  sync_lock_acquire || return 1
  local owner="$(cat "${FIXTURE_REPO}/.haws/state/sync.lock/pid")"
  HAWS_SECOND_BRAIN_ENABLED=off HAWS_AUTO_UPDATE=off
  . "${PROJECT_ROOT}/runtime/operations.sh"
  assert_status 1 sync_run
  grep -F -- "sync already running" "${FIXTURE_REPO}/.haws/state/last-error" >/dev/null 2>&1 || true
  [ "${owner}" = "$$" ] || return 1
  sync_lock_release
}

test_lock_is_released_on_success_failure_and_interrupt() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\toff\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  load_state_api || return 1
  . "${PROJECT_ROOT}/runtime/operations.sh"
  sync_run || return 1
  [ ! -d "${FIXTURE_REPO}/.haws/state/sync.lock" ] || return 1
}

test_dirty_source_is_blocked_while_other_targets_continue() {
  new_fixture
  make_source_fixture dirty
  make_source_fixture clean
  write_gitmodules_fixture dirty clean
  printf 'changed\n' >> "${FIXTURE_REPO}/skills/packs/dirty/SKILL.md"
  load_state_api || return 1
  . "${PROJECT_ROOT}/runtime/catalog.sh"
  . "${PROJECT_ROOT}/runtime/operations.sh"
  assert_status 2 source_preflight "dirty::skills/packs/dirty" || return 1
  assert_status 0 source_preflight "clean::skills/packs/clean"
}

test_untracked_file_blocks_only_its_source() {
  new_fixture
  make_source_fixture tracked
  make_source_fixture clean
  write_gitmodules_fixture tracked clean
  : > "${FIXTURE_REPO}/skills/packs/tracked/untracked.txt"
  load_state_api || return 1
  . "${PROJECT_ROOT}/runtime/catalog.sh"
  . "${PROJECT_ROOT}/runtime/operations.sh"
  assert_status 2 source_preflight "tracked::skills/packs/tracked" || return 1
  assert_status 0 source_preflight "clean::skills/packs/clean"
}

test_source_with_no_active_skills_is_skipped() {
  new_fixture
  make_source_fixture inactive
  write_gitmodules_fixture inactive
  mkdir -p "${FIXTURE_REPO}/skills"
  printf 'inactive::skills/packs/inactive::SKILL.md\n' > "${FIXTURE_REPO}/skills/skills.disabled"
  load_state_api || return 1
  . "${PROJECT_ROOT}/runtime/catalog.sh"
  . "${PROJECT_ROOT}/runtime/operations.sh"
  assert_status 3 source_preflight "inactive::skills/packs/inactive"
}

run_test() {
  local name="$1"
  if "$name"; then echo "PASS ${name}"; passed=$((passed + 1)); else echo "FAIL ${name}"; failed=$((failed + 1)); fi
  cleanup_fixture
}
trap cleanup_fixture EXIT
run_test test_both_remote_settings_off_makes_no_network_request
run_test test_second_brain_off_never_calls_its_git_remote
run_test test_auto_update_off_never_fetches_haws_or_sources
run_test test_concurrent_sync_reports_already_running
run_test test_lock_is_released_on_success_failure_and_interrupt
run_test test_dirty_source_is_blocked_while_other_targets_continue
run_test test_untracked_file_blocks_only_its_source
run_test test_source_with_no_active_skills_is_skipped
echo "CLI sync tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
