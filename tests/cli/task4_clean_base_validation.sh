#!/usr/bin/env bash
# Task 4 — Clean Base Validation Suite
# Broad validation across Tasks 1-3, Settings draft/state, Preview/Back/Cancel,
# Home, loading, Skills, TUI, Status, and Doctor.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/test_helper.sh"

passed=0
failed=0

run_val() {
  local name="$1"
  if "$name"; then
    echo "  [PASS] ${name}"
    passed=$((passed + 1))
  else
    echo "  [FAIL] ${name}"
    failed=$((failed + 1))
  fi
  unset HAWS_TEST_KEYS
  cleanup_fixture
}

# --- 1. Loop safety ---
test_loop_safety_precommit_and_doctor() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state" "${FIXTURE_HOME}/.claude"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\toff\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  run_haws doctor || true
  assert_output_contains "HAWS Doctor" || return 1
  assert_output_contains "Overall:" || return 1
  [ ! -s "${CALL_LOG}" ] || return 1
}

# --- 2. Product flow ---
test_flow_first_install_uninstalled_entry() {
  new_fixture
  export HAWS_TEST_KEYS=cancel
  run_haws || true
  assert_output_contains "First Install" || return 1
  assert_output_contains "Use Recommended Defaults" || return 1
  assert_output_contains "Preview Install" || return 1
  assert_output_contains "Cancel Setup" || return 1
  ! grep -F "Uninstall HAWS" "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
  [ ! -e "${FIXTURE_REPO}/.haws/state/install.complete" ] || return 1
}

test_flow_first_install_default_setup_to_home() {
  new_fixture
  mkdir -p "${FIXTURE_HOME}/.claude"
  export HAWS_TEST_KEYS=save
  run_haws || return 1
  assert_output_contains "Apply progress" || return 1
  assert_output_contains "Doctor: Ready" || return 1
  assert_output_contains "Home" || return 1
  [ -s "${FIXTURE_REPO}/.haws/state/install.complete" ] || return 1
}

test_flow_installed_bare_launch_enters_home_without_sync() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  export HAWS_TEST_KEYS=exit
  run_haws || return 1
  assert_output_contains "HAWS Home" || return 1
  assert_output_contains "Sync Now" || return 1
  assert_output_contains "Settings" || return 1
  assert_output_contains "Doctor" || return 1
  assert_output_contains "Exit" || return 1
  ! grep -F "Sync progress" "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
}

# --- 3. Settings / State Draft Model ---
test_state_opening_settings_leaves_persistent_state_untouched() {
  new_fixture
  export HAWS_TEST_KEYS=cancel
  run_haws settings || true
  [ ! -d "${FIXTURE_REPO}/.haws/state" ] || return 1
}

test_state_discard_changes_leaves_no_trace() {
  new_fixture
  export HAWS_TEST_KEYS=6,off,cancel
  run_haws settings || true
  assert_output_contains "Cancelled. No changes saved." || return 1
  [ ! -f "${FIXTURE_REPO}/.haws/state/settings.tsv" ] || return 1
}

test_state_reset_defaults_in_draft_only() {
  new_fixture
  export HAWS_TEST_KEYS=default,cancel
  run_haws settings || true
  assert_output_contains "Recommended defaults restored in draft." || return 1
  [ ! -f "${FIXTURE_REPO}/.haws/state/settings.tsv" ] || return 1
}

test_state_q_and_uppercase_q_equivalence() {
  new_fixture
  export HAWS_TEST_KEYS=q
  run_haws settings || true
  assert_output_contains "Cancelled. No changes saved." || return 1
  cleanup_fixture

  new_fixture
  export HAWS_TEST_KEYS=Q
  run_haws settings || true
  assert_output_contains "Cancelled. No changes saved." || return 1
}

test_state_back_from_subpage_preserves_parent_draft() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  export HAWS_TEST_KEYS=6,off,2,back,save,cancel
  run_haws settings || true
  assert_output_contains "Preview Update" || return 1
  assert_output_contains "Auto Update: on -> off" || return 1
}

# --- 4. Repositories ---
test_repo_url_deterministic_path() {
  new_fixture
  load_state_api
  . "${PROJECT_ROOT}/runtime/settings.sh"
  local path
  path="$(_settings_repo_path_from_url "https://github.com/foo/my-pack.git")"
  [ "${path}" = "skills/packs/my-pack" ] || return 1
}

test_repo_duplicate_rejection_in_draft() {
  new_fixture
  export HAWS_TEST_KEYS=2,add,https://example.invalid/repo.git,add,https://example.invalid/repo.git,cancel,cancel
  run_haws settings || true
  assert_output_contains "Repository already exists in draft:" || return 1
}

# --- 5. Skills ---
test_skills_lazy_catalog_loading() {
  new_fixture
  export HAWS_TEST_KEYS=cancel
  run_haws settings || true
  assert_output_contains "Loading HAWS settings..." || return 1
  assert_output_contains "Loading repository catalog..." || return 1
  ! grep -F "Loading skills catalog" "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
}

test_skills_hierarchy_single_and_packs() {
  new_fixture
  export HAWS_TEST_KEYS=3,cancel,cancel
  run_haws settings || true
  assert_output_contains "Single Skills" || return 1
  assert_output_contains "Multi-Skill Packs" || return 1
}

# --- 6. AI Environments ---
test_envs_detection_accuracy() {
  new_fixture
  mkdir -p "${FIXTURE_HOME}/.claude"
  load_state_api
  . "${PROJECT_ROOT}/runtime/settings.sh"
  local detected
  detected="$(_settings_detected_envs)"
  printf '%s\n' "${detected}" | grep -Fx "claude" >/dev/null || return 1
  ! printf '%s\n' "${detected}" | grep -Fx "gemini" >/dev/null || return 1
}

test_envs_vertical_preview() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state" "${FIXTURE_HOME}/.claude"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\ton\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  export HAWS_TEST_KEYS=4,space,enter,save,cancel
  run_haws settings || true
  assert_output_contains "Settings review" || return 1
}

# --- 7. Second Brain ---
test_second_brain_draft_url_does_not_mutate_state() {
  new_fixture
  export HAWS_TEST_KEYS=5,on,https://example.invalid/brain.git,cancel
  run_haws settings || true
  [ ! -d "${FIXTURE_REPO}/.haws/state" ] || return 1
}

# --- 8. TUI & Presentation ---
test_tui_no_numeric_prefixes_in_cursor_menu() {
  new_fixture
  export HAWS_TEST_KEYS=cancel
  . "${PROJECT_ROOT}/runtime/ui.sh"
  local out
  out="$(ui_cursor_menu "Test Menu" $'item_a\tItem Alpha\t' $'item_b\tItem Beta\t' 2>&1)" || true
  ! printf "%s\n" "${out}" | grep -E '^[ >]*[0-9]+\)' >/dev/null 2>&1 || return 1
  printf "%s\n" "${out}" | grep -F "Item Alpha" >/dev/null 2>&1 || return 1
  printf "%s\n" "${out}" | grep -F "Item Beta" >/dev/null 2>&1 || return 1
}

test_tui_contextual_q_label() {
  new_fixture
  export HAWS_TEST_KEYS=cancel
  . "${PROJECT_ROOT}/runtime/ui.sh"
  local out_settings out_home out_sub
  out_settings="$(ui_cursor_menu "Settings" $'save\tSave\t' $'cancel\tCancel\t' 2>&1)" || true
  printf "%s\n" "${out_settings}" | grep -F "Q Cancel" >/dev/null 2>&1 || return 1

  export HAWS_TEST_KEYS=exit
  out_home="$(ui_cursor_menu "Home" $'sync\tSync\t' $'exit\tExit\t' 2>&1)" || true
  printf "%s\n" "${out_home}" | grep -F "Q Exit" >/dev/null 2>&1 || return 1

  export HAWS_TEST_KEYS=back
  out_sub="$(ui_cursor_menu "Submenu" $'item\tItem\t' $'back\tBack\t' 2>&1)" || true
  printf "%s\n" "${out_sub}" | grep -F "Q Back" >/dev/null 2>&1 || return 1
}

# --- 9. Status & Doctor Diagnostics ---
test_status_is_strictly_readonly() {
  new_fixture
  run_haws status || return 1
  assert_output_contains "HAWS Status" || return 1
  [ ! -d "${FIXTURE_REPO}/.haws/state" ] || return 1
}

test_doctor_classification_matches_status() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/.haws/state" "${FIXTURE_HOME}/.claude"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\toff\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  run_haws status || true
  local status_overall
  status_overall="$(grep -F "Overall:" "${OUTPUT_FILE}" | head -1)"
  run_haws doctor || true
  local doctor_overall
  doctor_overall="$(grep -F "Overall:" "${OUTPUT_FILE}" | head -1)"
  [ "${status_overall}" = "${doctor_overall}" ] || return 1
}

# --- 10. Architecture Invariants ---
test_architecture_no_bat_or_platform_bloat_in_core() {
  new_fixture
  ! grep -iE "1-CLICK-SYNC\.bat|SETUP\.bat|2nd-BRAIN-TOGGLE\.bat" "${PROJECT_ROOT}/haws.sh" >/dev/null 2>&1 || return 1
  ! grep -iE "1-CLICK-SYNC\.bat|SETUP\.bat|2nd-BRAIN-TOGGLE\.bat" "${PROJECT_ROOT}/runtime/"*.sh >/dev/null 2>&1 || return 1
}

echo "=== Task 4 Clean Base Validation Suite ==="
trap cleanup_fixture EXIT

run_val test_loop_safety_precommit_and_doctor
run_val test_flow_first_install_uninstalled_entry
run_val test_flow_first_install_default_setup_to_home
run_val test_flow_installed_bare_launch_enters_home_without_sync
run_val test_state_opening_settings_leaves_persistent_state_untouched
run_val test_state_discard_changes_leaves_no_trace
run_val test_state_reset_defaults_in_draft_only
run_val test_state_q_and_uppercase_q_equivalence
run_val test_state_back_from_subpage_preserves_parent_draft
run_val test_repo_url_deterministic_path
run_val test_repo_duplicate_rejection_in_draft
run_val test_skills_lazy_catalog_loading
run_val test_skills_hierarchy_single_and_packs
run_val test_envs_detection_accuracy
run_val test_envs_vertical_preview
run_val test_second_brain_draft_url_does_not_mutate_state
run_val test_tui_no_numeric_prefixes_in_cursor_menu
run_val test_tui_contextual_q_label
run_val test_status_is_strictly_readonly
run_val test_doctor_classification_matches_status
run_val test_architecture_no_bat_or_platform_bloat_in_core

echo "=========================================="
echo "Task 4 Validation: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
