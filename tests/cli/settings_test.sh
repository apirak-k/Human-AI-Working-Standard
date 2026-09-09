#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/test_helper.sh"
passed=0
failed=0

test_home_contains_status_sync_settings_doctor_details_and_exit() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  export HAWS_TEST_KEYS=exit
  run_haws || return 1
  assert_output_contains "HAWS Home" || return 1
  assert_output_contains "Status | Sync | Settings | Doctor | Status details | Exit"
}

test_checklist_supports_space_select_all_clear_all_and_enter() {
  new_fixture
  export HAWS_TEST_KEYS=space,enter
  load_state_api
  . "${PROJECT_ROOT}/runtime/ui.sh"
  local result
  result="$(ui_checklist Test $'one\tOne\tdetail\t0' $'two\tTwo\tdetail\t0')"
  printf '%s\n' "${result}" | grep -F "one" >/dev/null
}

test_boolean_requires_explicit_on_or_off() {
  new_fixture
  export HAWS_TEST_KEYS=off
  . "${PROJECT_ROOT}/runtime/ui.sh"
  [ "$(ui_boolean Auto on | tail -1)" = off ]
}

test_review_precedes_every_mutation() {
  new_fixture
  mkdir -p "${FIXTURE_HOME}/.claude"
  export HAWS_TEST_KEYS=save
  run_haws || return 1
  assert_output_contains "Settings review" || return 1
  assert_output_contains "Review planned changes:" || return 1
  [ -f "${FIXTURE_HOME}/.claude/CLAUDE.md" ]
}

test_later_save_apply_does_not_fetch_existing_sources() {
  new_fixture
  mkdir -p "${FIXTURE_HOME}/.claude" "${FIXTURE_REPO}/.haws/state"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  export HAWS_TEST_KEYS=envs=claude,save
  run_haws || return 1
  assert_no_call "fetch" || return 1
  assert_no_call "submodule update" || return 1
}

test_uninstall_is_visible_only_after_install_complete() {
  new_fixture
  export HAWS_TEST_KEYS=cancel
  env HOME="${FIXTURE_HOME}" HAWS_REPO_DIR="${FIXTURE_REPO}" HAWS_CALL_LOG="${CALL_LOG}" PATH="${FAKE_BIN}:${PATH}" bash "${PROJECT_ROOT}/haws.sh" settings >"${OUTPUT_FILE}" 2>&1 || true
  ! grep -F "Uninstall" "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
  cleanup_fixture
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  export HAWS_TEST_KEYS=cancel
  env HOME="${FIXTURE_HOME}" HAWS_REPO_DIR="${FIXTURE_REPO}" HAWS_CALL_LOG="${CALL_LOG}" PATH="${FAKE_BIN}:${PATH}" bash "${PROJECT_ROOT}/haws.sh" settings >"${OUTPUT_FILE}" 2>&1 || true
  assert_output_contains "Uninstall"
}

test_adapter_templates_reference_canonical_rules_without_duplicating_them() {
  local file
  for file in "${PROJECT_ROOT}"/ai-configs/*/*.template; do
    case "${file}" in *agents.mjs|*skills.mjs) continue ;; esac
    grep -E 'core/HAWS.md|core/WORK_INSTRUCTIONS.md' "${file}" >/dev/null || return 1
    ! grep -E 'Engineering Invariants|Rules of Engagement|Quality Gates' "${file}" >/dev/null || return 1
  done
}

run_test() { local name="$1"; if "$name"; then echo "PASS ${name}"; passed=$((passed + 1)); else echo "FAIL ${name}"; failed=$((failed + 1)); fi; unset HAWS_TEST_KEYS; cleanup_fixture; }
trap cleanup_fixture EXIT
run_test test_home_contains_status_sync_settings_doctor_details_and_exit
run_test test_checklist_supports_space_select_all_clear_all_and_enter
run_test test_boolean_requires_explicit_on_or_off
run_test test_review_precedes_every_mutation
run_test test_later_save_apply_does_not_fetch_existing_sources
run_test test_uninstall_is_visible_only_after_install_complete
run_test test_adapter_templates_reference_canonical_rules_without_duplicating_them
echo "CLI settings tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
