#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/test_helper.sh"
passed=0
failed=0

seed_health_fixture() {
  mkdir -p "${FIXTURE_REPO}/.haws/state" "${FIXTURE_HOME}/.claude"
  printf 'schema_version\t1\nsecond_brain\toff\nauto_update\toff\n' > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  printf '%s\t%s\t%s\t%s\t%s\n' '2026-09-09T00:00:00Z' haws 'Up to date' abc123 'local check' > "${FIXTURE_REPO}/.haws/state/sync-state.tsv"
  printf 'schema=1\tcompleted_at=now\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
  printf 'environments\tgenerated-file\t%s\tsource\tfingerprint\n' "${FIXTURE_HOME}/.claude/CLAUDE.md" > "${FIXTURE_REPO}/.haws/state/ownership.tsv"
}

test_status_reads_local_configuration_and_recorded_sync_only() {
  new_fixture; seed_health_fixture; export HAWS_TEST_KEYS=exit
  run_haws status || return 1
  assert_output_contains "HAWS Status" || return 1
  assert_output_contains "Last sync: Up to date" || return 1
  assert_output_contains "Auto Update: off" || return 1
}

test_status_never_invokes_fetch_pull_ls_remote_or_network_stub() {
  new_fixture; seed_health_fixture; install_fake_command git
  run_haws status || return 1
  assert_no_call "fetch" || return 1
  assert_no_call "pull" || return 1
  assert_no_call "ls-remote" || return 1
}

test_status_distinguishes_last_sync_record_from_current_local_health() {
  new_fixture; seed_health_fixture
  printf 'user edit\n' > "${FIXTURE_HOME}/.claude/CLAUDE.md"
  run_haws status || return 1
  assert_output_contains "Last sync: Up to date" || return 1
  assert_output_contains "Overall: Attention" || return 1
}

test_status_details_lists_environment_source_and_skill_sections() {
  new_fixture; seed_health_fixture
  run_haws status --details || return 1
  assert_output_contains "AI Environments" || return 1
  assert_output_contains "Sources" || return 1
  assert_output_contains "Skills" || return 1
}

test_doctor_does_not_set_core_hooks_path_or_repair() {
  new_fixture; seed_health_fixture
  git -C "${FIXTURE_REPO}" config core.hooksPath custom-hooks
  local before after
  before="$(git -C "${FIXTURE_REPO}" config --get core.hooksPath)"
  run_haws doctor || true
  after="$(git -C "${FIXTURE_REPO}" config --get core.hooksPath)"
  [ "${before}" = "${after}" ] || return 1
  ! grep -F "repair" "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
}

test_doctor_and_status_share_overall_classification() {
  new_fixture; seed_health_fixture
  printf 'user edit\n' > "${FIXTURE_HOME}/.claude/CLAUDE.md"
  run_haws status || return 1
  local status_level
  status_level="$(grep -F 'Overall:' "${OUTPUT_FILE}" | head -1)"
  run_haws doctor || return 1
  grep -F "Overall: Attention" "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
  [ -n "${status_level}" ] || return 1
}

run_test() { local name="$1"; if "$name"; then echo "PASS ${name}"; passed=$((passed + 1)); else echo "FAIL ${name}"; failed=$((failed + 1)); fi; cleanup_fixture; }
trap cleanup_fixture EXIT
run_test test_status_reads_local_configuration_and_recorded_sync_only
run_test test_status_never_invokes_fetch_pull_ls_remote_or_network_stub
run_test test_status_distinguishes_last_sync_record_from_current_local_health
run_test test_status_details_lists_environment_source_and_skill_sections
run_test test_doctor_does_not_set_core_hooks_path_or_repair
run_test test_doctor_and_status_share_overall_classification
echo "CLI status/doctor tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
