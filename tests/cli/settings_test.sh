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
  assert_output_contains "Sync Now" || return 1
  assert_output_contains "Status Details" || return 1
  assert_output_contains "Exit" || return 1
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

test_checklist_renders_approved_bulk_row_help_and_state_marks() {
  new_fixture
  export HAWS_TEST_KEYS=down,space,enter
  . "${PROJECT_ROOT}/runtime/ui.sh"
  ui_checklist Test $'one\tOne\tdetail\t0' $'two\tTwo\tdetail\t0' > /dev/null 2>"${OUTPUT_FILE}" || return 1
  assert_output_contains "Select All" || return 1
  assert_output_contains "Space Toggle" || return 1
  assert_output_contains "Enter Select" || return 1
  assert_output_contains "[ ]" || return 1
  assert_output_contains "[-]" || return 1
  assert_output_contains "[x]"
}

test_checklist_cancel_returns_no_result() {
  new_fixture
  export HAWS_TEST_KEYS=cancel
  . "${PROJECT_ROOT}/runtime/ui.sh"
  UI_CHECKLIST_RESULT=stale
  if ui_checklist Test $'one\tOne\tdetail\t1' >"${OUTPUT_FILE}" 2>&1; then
    return 1
  fi
  [ -z "${UI_CHECKLIST_RESULT:-}" ]
}

test_cursor_menu_uses_down_and_enter_to_return_stable_id() {
  new_fixture
  export HAWS_TEST_KEYS=down,enter
  . "${PROJECT_ROOT}/runtime/ui.sh"
  ui_cursor_menu "Test menu" $'first\tFirst\t' $'second\tSecond\t' >/dev/null || return 1
  [ "${UI_MENU_RESULT:-}" = second ]
}

test_cursor_menu_wraps_up_from_first_to_last_item() {
  new_fixture
  export HAWS_TEST_KEYS=up,enter
  . "${PROJECT_ROOT}/runtime/ui.sh"
  ui_cursor_menu "Test menu" $'first\tFirst\t' $'second\tSecond\t' $'third\tThird\t' >/dev/null || return 1
  [ "${UI_MENU_RESULT:-}" = third ]
}

test_cursor_menu_wraps_down_from_last_to_first_item() {
  new_fixture
  export HAWS_TEST_KEYS=down,down,down,enter
  . "${PROJECT_ROOT}/runtime/ui.sh"
  ui_cursor_menu "Test menu" $'first\tFirst\t' $'second\tSecond\t' $'third\tThird\t' >/dev/null || return 1
  [ "${UI_MENU_RESULT:-}" = first ]
}

test_cursor_menu_cancel_returns_nonzero() {
  new_fixture
  export HAWS_TEST_KEYS=cancel
  . "${PROJECT_ROOT}/runtime/ui.sh"
  ! ui_cursor_menu "Test menu" $'first\tFirst\t' >/dev/null 2>&1
}

test_checklist_select_all_key() {
  new_fixture
  export HAWS_TEST_KEYS=a,enter
  . "${PROJECT_ROOT}/runtime/ui.sh"
  local result
  result="$(ui_checklist Test $'one\tOne\tdetail\t0' $'two\tTwo\tdetail\t0')"
  printf '%s\n' "${result}" | grep -Fx "one" >/dev/null || return 1
  printf '%s\n' "${result}" | grep -Fx "two" >/dev/null
}

test_checklist_clear_all_key() {
  new_fixture
  export HAWS_TEST_KEYS=c,enter
  . "${PROJECT_ROOT}/runtime/ui.sh"
  local result
  result="$(ui_checklist Test $'one\tOne\tdetail\t1' $'two\tTwo\tdetail\t1')"
  [ -z "${result:-}" ]
}

test_cursor_menu_accepts_numbered_test_seam_for_existing_fixture_flows() {
  new_fixture
  export HAWS_TEST_KEYS=2
  . "${PROJECT_ROOT}/runtime/ui.sh"
  ui_cursor_menu "Test menu" $'first\tFirst\t' $'second\tSecond\t' >/dev/null || return 1
  [ "${UI_MENU_RESULT:-}" = second ]
}

test_boolean_requires_explicit_on_or_off() {
  new_fixture
  export HAWS_TEST_KEYS=off
  . "${PROJECT_ROOT}/runtime/ui.sh"
  [ "$(ui_boolean Auto on | tail -1)" = off ]
}

test_settings_defers_skill_catalog_loading_until_the_user_needs_it() {
  new_fixture
  export HAWS_TEST_KEYS=cancel
  run_haws settings || true
  assert_output_contains "Loading HAWS settings..." || return 1
  assert_output_contains "Loading repository catalog..." || return 1
  assert_output_contains "Settings ready. Skills load when you open Skills or Preview." || return 1
  ! grep -F "Loading skills catalog (this can take a moment)..." "${OUTPUT_FILE}" >/dev/null 2>&1
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
  assert_output_contains "Preview Update" || return 1
  assert_output_contains "Restore Recommended Defaults" || return 1
  assert_output_contains "Repositories" || return 1
  assert_output_contains "Skills" || return 1
  assert_output_contains "AI Environments" || return 1
  assert_output_contains "Second Brain Remote" || return 1
  assert_output_contains "Auto Update" || return 1
  assert_output_contains "Uninstall HAWS"
}

test_preview_update_shows_review_actions_and_not_changed_safeguards() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  local before after
  before="$(sha256sum "${FIXTURE_REPO}/.haws/state/install.complete" | awk '{print $1}')"
  export HAWS_TEST_KEYS=6,off,save,cancel
  run_haws settings || true
  assert_output_contains "Preview Update" || return 1
  assert_output_contains "Current settings:" || return 1
  assert_output_contains "Not changed" || return 1
  assert_output_contains "Apply Update" || return 1
  assert_output_contains "Back to Settings" || return 1
  assert_output_contains "Cancel Update" || return 1
  after="$(sha256sum "${FIXTURE_REPO}/.haws/state/install.complete" | awk '{print $1}')"
  [ "${before}" = "${after}" ] || return 1
}

test_second_brain_remote_connection_is_checked_in_draft_only() {
  new_fixture
  export HAWS_TEST_KEYS=5,on,https://example.invalid/brain.git,cancel
  run_haws settings || true
  assert_output_contains "Remote connection" || return 1
  assert_output_contains "draft" || return 1
  [ ! -d "${FIXTURE_REPO}/.haws/state" ] || return 1
}

test_second_brain_remote_persists_only_after_apply() {
  new_fixture
  export HAWS_TEST_KEYS=5,on,https://example.invalid/brain.git,save,yes
  run_haws settings || true
  assert_file_contains "${FIXTURE_REPO}/.haws/state/settings.tsv" $'second_brain_remote\thttps://example.invalid/brain.git' || return 1
}

test_preview_update_with_no_changes_has_no_apply_action() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  export HAWS_TEST_KEYS=save
  run_haws settings || true
  assert_output_contains "No changes detected" || return 1
  ! grep -F "Apply Update" "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_repositories_opens_approved_draft_add_remove_menu() {
  new_fixture
  export HAWS_TEST_KEYS=2,cancel
  run_haws settings || true
  assert_output_contains "Add Repository" || return 1
  assert_output_contains "Remove Repository" || return 1
  assert_output_contains "Back to Settings" || return 1
  ! grep -F "Git Submodule" "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
  [ ! -f "${FIXTURE_REPO}/.gitmodules" ] || return 1
  [ ! -d "${FIXTURE_REPO}/.haws/state" ]
}

test_skills_opens_the_legacy_single_and_pack_submenu() {
  new_fixture
  export HAWS_TEST_KEYS=3,cancel
  run_haws settings || true
  assert_output_contains "HAWS Settings — Skills" || return 1
  assert_output_contains "Single Skills" || return 1
  assert_output_contains "Multi-Skill Packs" || return 1
  assert_output_contains "Up/Down Move   Enter Select   Q Back" || return 1
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
  assert_output_contains "On" || return 1
  assert_output_contains "Off" || return 1
  assert_output_contains "Back to Settings" || return 1
}

test_uninstall_setting_opens_group_checklist_before_preview() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  export HAWS_TEST_KEYS=uninstall,cancel
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
run_test test_checklist_renders_approved_bulk_row_help_and_state_marks
run_test test_checklist_cancel_returns_no_result
run_test test_cursor_menu_uses_down_and_enter_to_return_stable_id
run_test test_cursor_menu_wraps_up_from_first_to_last_item
run_test test_cursor_menu_wraps_down_from_last_to_first_item
run_test test_cursor_menu_cancel_returns_nonzero
run_test test_checklist_select_all_key
run_test test_checklist_clear_all_key
run_test test_cursor_menu_accepts_numbered_test_seam_for_existing_fixture_flows
run_test test_boolean_requires_explicit_on_or_off
run_test test_settings_defers_skill_catalog_loading_until_the_user_needs_it
run_test test_review_precedes_every_mutation
run_test test_later_save_apply_does_not_fetch_existing_sources
run_test test_unrelated_setting_change_preserves_environment_disabled_bytes
run_test test_uninstall_is_visible_only_after_install_complete
run_test test_installed_settings_keeps_every_spec_action_and_adds_uninstall
run_test test_preview_update_shows_review_actions_and_not_changed_safeguards
run_test test_second_brain_remote_connection_is_checked_in_draft_only
run_test test_second_brain_remote_persists_only_after_apply
run_test test_preview_update_with_no_changes_has_no_apply_action
run_test test_repositories_opens_approved_draft_add_remove_menu
run_test test_skills_opens_the_legacy_single_and_pack_submenu
run_test test_ai_environment_screen_lists_supported_options_on_a_clean_machine
run_test test_boolean_settings_open_explicit_on_off_submenus
run_test test_uninstall_setting_opens_group_checklist_before_preview
run_test test_adapter_templates_reference_canonical_rules_without_duplicating_them
echo "CLI settings tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
