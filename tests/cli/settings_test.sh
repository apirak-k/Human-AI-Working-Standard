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

test_checklist_starts_at_visible_toggle_all_and_selects_every_item() {
  new_fixture
  export HAWS_TEST_KEYS=space,enter
  . "${PROJECT_ROOT}/runtime/ui.sh"
  local result
  result="$(ui_checklist Test $'one\tOne\tdetail\t0' $'two\tTwo\tdetail\t0')"
  printf '%s\n' "${result}" | grep -Fx "one" >/dev/null || return 1
  printf '%s\n' "${result}" | grep -Fx "two" >/dev/null
}

test_checklist_wraps_up_from_toggle_all_to_the_last_item() {
  new_fixture
  export HAWS_TEST_KEYS=up,space,enter
  . "${PROJECT_ROOT}/runtime/ui.sh"
  local result
  result="$(ui_checklist Test $'one\tOne\tdetail\t1' $'two\tTwo\tdetail\t1')"
  printf '%s\n' "${result}" | grep -Fx "one" >/dev/null || return 1
  ! printf '%s\n' "${result}" | grep -Fx "two" >/dev/null 2>&1
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

test_unrelated_setting_change_preserves_environment_disabled_bytes() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/ai-configs" "${FIXTURE_REPO}/.haws/state"
  printf 'cursor\r\ncodex\r\n' > "${FIXTURE_REPO}/ai-configs/environments.disabled"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  local before after
  before="$(sha256sum "${FIXTURE_REPO}/ai-configs/environments.disabled" | awk '{print $1}')"
  export HAWS_TEST_KEYS=auto_update=off,save
  run_haws settings || return 1
  after="$(sha256sum "${FIXTURE_REPO}/ai-configs/environments.disabled" | awk '{print $1}')"
  [ "${before}" = "${after}" ] || return 1
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

test_installed_settings_keeps_every_spec_action_and_adds_uninstall() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  export HAWS_TEST_KEYS=cancel
  run_haws settings || true
  assert_output_contains "Save & Apply / Exit" || return 1
  assert_output_contains "Reset Standard Setup" || return 1
  assert_output_contains "Repositories" || return 1
  assert_output_contains "Skills" || return 1
  assert_output_contains "AI Environments" || return 1
  assert_output_contains "Second Brain" || return 1
  assert_output_contains "Auto Update when Syncing" || return 1
  assert_output_contains "Uninstall HAWS"
}

test_repositories_opens_a_draft_add_remove_submenu() {
  new_fixture
  export HAWS_TEST_KEYS=2,cancel
  run_haws settings || true
  assert_output_contains "Select Repositories / KIT" || return 1
  assert_output_contains "Add Repository" || return 1
  assert_output_contains "Remove Repository" || return 1
  [ ! -f "${FIXTURE_REPO}/.gitmodules" ] || return 1
  [ ! -d "${FIXTURE_REPO}/.haws/state" ]
}

test_skills_opens_the_legacy_single_and_pack_submenu() {
  new_fixture
  export HAWS_TEST_KEYS=3,cancel
  run_haws settings || true
  assert_output_contains "Single Skills" || return 1
  assert_output_contains "Multi-Skill Packs" || return 1
  [ ! -d "${FIXTURE_REPO}/.haws/state" ]
}

test_ai_environment_screen_lists_supported_options_on_a_clean_machine() {
  new_fixture
  export HAWS_TEST_KEYS=4,cancel
  run_haws settings || true
  assert_output_contains "Claude" || return 1
  assert_output_contains "Gemini" || return 1
  assert_output_contains "Copilot" || return 1
  assert_output_contains "Codex"
}

test_boolean_settings_open_explicit_on_off_submenus() {
  new_fixture
  export HAWS_TEST_KEYS=5,cancel
  run_haws settings || true
  assert_output_contains "Second Brain"
  assert_output_contains "1) On" || return 1
  assert_output_contains "2) Off" || return 1
}

test_uninstall_setting_opens_group_checklist_before_preview() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  export HAWS_TEST_KEYS=7,cancel
  run_haws settings || true
  assert_output_contains "Uninstall groups" || return 1
  assert_output_contains "AI pointers" || return 1
  assert_output_contains "Skill links" || return 1
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
run_test test_checklist_starts_at_visible_toggle_all_and_selects_every_item
run_test test_checklist_wraps_up_from_toggle_all_to_the_last_item
run_test test_boolean_requires_explicit_on_or_off
run_test test_review_precedes_every_mutation
run_test test_later_save_apply_does_not_fetch_existing_sources
run_test test_unrelated_setting_change_preserves_environment_disabled_bytes
run_test test_uninstall_is_visible_only_after_install_complete
run_test test_installed_settings_keeps_every_spec_action_and_adds_uninstall
run_test test_repositories_opens_a_draft_add_remove_submenu
run_test test_skills_opens_the_legacy_single_and_pack_submenu
run_test test_ai_environment_screen_lists_supported_options_on_a_clean_machine
run_test test_boolean_settings_open_explicit_on_off_submenus
run_test test_uninstall_setting_opens_group_checklist_before_preview
run_test test_adapter_templates_reference_canonical_rules_without_duplicating_them
echo "CLI settings tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
