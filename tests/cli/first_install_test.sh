#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/test_helper.sh"
passed=0
failed=0

test_bare_first_launch_opens_default_populated_settings_without_git_calls() {
  new_fixture
  export HAWS_TEST_KEYS=cancel
  run_haws || true
  assert_output_contains "First Install" || return 1
  assert_output_contains "Second Brain: off" || return 1
  [ ! -d "${FIXTURE_REPO}/.haws/state" ] || return 1
  [ ! -s "${CALL_LOG}" ] || return 1
}

test_default_setup_only_resets_the_draft() {
  new_fixture
  export HAWS_TEST_KEYS=default,cancel
  run_haws || true
  assert_output_contains "Default Setup restored in draft." || return 1
  [ ! -d "${FIXTURE_REPO}/.haws/state" ] || return 1
  [ ! -e "${FIXTURE_HOME}/.haws_manifest" ] || return 1
}

test_cancel_leaves_state_and_integrations_unchanged() {
  new_fixture
  mkdir -p "${FIXTURE_HOME}/.claude"
  export HAWS_TEST_KEYS=cancel
  run_haws || true
  [ ! -e "${FIXTURE_HOME}/.claude/CLAUDE.md" ] || return 1
  [ ! -e "${FIXTURE_REPO}/.haws/state/install.complete" ] || return 1
}

test_first_save_apply_downloads_only_selected_missing_sources() {
  new_fixture
  cat > "${FIXTURE_REPO}/.gitmodules" <<'EOF'
[submodule "selected"]
	path = skills/packs/selected
	url = https://example.invalid/selected.git
[submodule "unselected"]
	path = skills/packs/unselected
	url = https://example.invalid/unselected.git
EOF
  load_state_api || return 1
  . "${PROJECT_ROOT}/runtime/catalog.sh"
  . "${PROJECT_ROOT}/runtime/integrations.sh"
  HAWS_INTEGRATION_PLAN="${FIXTURE_ROOT}/integration.plan"
  integration_plan "" "selected::skills/packs/selected" || return 1
  assert_file_contains "${HAWS_INTEGRATION_PLAN}" "selected::skills/packs/selected" || return 1
  ! grep -F "unselected::skills/packs/unselected" "${HAWS_INTEGRATION_PLAN}" >/dev/null 2>&1
}

test_first_save_apply_configures_only_selected_environments() {
  new_fixture
  mkdir -p "${FIXTURE_HOME}/.claude" "${FIXTURE_HOME}/.gemini"
  export HAWS_TEST_KEYS=envs=claude,save
  run_haws || return 1
  [ -f "${FIXTURE_HOME}/.claude/CLAUDE.md" ] || return 1
  [ ! -e "${FIXTURE_HOME}/.gemini/GEMINI.md" ] || return 1
  [ -s "${FIXTURE_REPO}/.haws/state/install.complete" ] || return 1
}

test_first_save_apply_runs_doctor_then_reaches_home() {
  new_fixture
  mkdir -p "${FIXTURE_HOME}/.claude"
  export HAWS_TEST_KEYS=save
  run_haws || return 1
  assert_output_contains "Doctor: Ready" || return 1
  assert_output_contains "Home" || return 1
}

run_test() {
  local name="$1"
  if "$name"; then echo "PASS ${name}"; passed=$((passed + 1)); else echo "FAIL ${name}"; failed=$((failed + 1)); fi
  unset HAWS_TEST_KEYS
  cleanup_fixture
}
trap cleanup_fixture EXIT
run_test test_bare_first_launch_opens_default_populated_settings_without_git_calls
run_test test_default_setup_only_resets_the_draft
run_test test_cancel_leaves_state_and_integrations_unchanged
run_test test_first_save_apply_downloads_only_selected_missing_sources
run_test test_first_save_apply_configures_only_selected_environments
run_test test_first_save_apply_runs_doctor_then_reaches_home
echo "CLI first-install tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
