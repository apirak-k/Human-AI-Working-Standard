#!/usr/bin/env bash
# RED compatibility tests for the future HAWS local-state boundary.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/test_helper.sh"

passed=0
failed=0

test_empty_disabled_environment_file_means_all_enabled() {
  new_fixture
  mkdir -p "${FIXTURE_REPO}/ai-configs"
  : > "${FIXTURE_REPO}/ai-configs/environments.disabled"
  load_state_api || return 1
  assert_status 0 state_init || return 1
  assert_status 0 disabled_envs_load || return 1
  if [ -n "${DISABLED_ENVS[claude]:-}" ] || [ -n "${DISABLED_ENVS[codex]:-}" ] || \
    [ -n "${DISABLED_ENVS[cursor]:-}" ]; then
    echo "[FAIL] an empty disabled-environment file disabled an environment" >&2
    return 1
  fi
  return 0
}

test_existing_disabled_environment_file_is_not_overwritten_by_migration() {
  new_fixture
  local disabled_file="${FIXTURE_REPO}/ai-configs/environments.disabled"
  mkdir -p "$(dirname "${disabled_file}")"
  printf 'cursor\r\ncodex\r\n' > "${disabled_file}"
  local before_file="${FIXTURE_ROOT}/environments.disabled.before"
  cp "${disabled_file}" "${before_file}"
  load_state_api || return 1
  assert_status 0 state_init || return 1
  assert_status 0 disabled_envs_load || return 1
  if ! cmp -s "${before_file}" "${disabled_file}"; then
    echo "[FAIL] migration rewrote ai-configs/environments.disabled" >&2
    return 1
  fi
  assert_file_contains "${disabled_file}" "cursor" || return 1
  assert_file_contains "${disabled_file}" "codex" || return 1
  return 0
}

test_existing_disabled_skill_file_is_not_overwritten_by_migration() {
  new_fixture
  local disabled_file="${FIXTURE_REPO}/skills/skills.disabled"
  mkdir -p "$(dirname "${disabled_file}")"
  printf 'custom-skill\r\nlegacy-skill\r\n' > "${disabled_file}"
  local before_file="${FIXTURE_ROOT}/skills.disabled.before"
  cp "${disabled_file}" "${before_file}"
  load_state_api || return 1
  assert_status 0 state_init || return 1
  assert_status 0 disabled_skills_load || return 1
  if ! cmp -s "${before_file}" "${disabled_file}"; then
    echo "[FAIL] migration rewrote skills/skills.disabled" >&2
    return 1
  fi
  assert_file_contains "${disabled_file}" "custom-skill" || return 1
  assert_file_contains "${disabled_file}" "legacy-skill" || return 1
  return 0
}

test_valid_legacy_manifest_entries_can_be_migrated() {
  new_fixture
  local skill_target="${FIXTURE_HOME}/.claude/skills/alpha"
  local agent_target="${FIXTURE_HOME}/.claude/agents/tester.md"
  mkdir -p "${FIXTURE_HOME}/.claude/skills" "${FIXTURE_HOME}/.claude/agents" \
    "${FIXTURE_REPO}/skills/alpha"
  printf '# Alpha skill\n' > "${FIXTURE_REPO}/skills/alpha/SKILL.md"
  ln -s "${FIXTURE_REPO}/skills/alpha" "${skill_target}"
  printf '# Tester agent\n' > "${agent_target}"
  printf 'skill:alpha\nagent:tester\n' > "${FIXTURE_HOME}/.haws_manifest"
  load_state_api || return 1
  assert_status 0 state_init || return 1
  if ! command -v ownership_list >/dev/null 2>&1; then
    echo "[FAIL] missing state API: ownership_list" >&2
    return 1
  fi
  local ownership_output
  ownership_output="$(ownership_list 2>&1)" || {
    echo "[FAIL] ownership_list could not read migrated records" >&2
    return 1
  }
  case "${ownership_output}" in
    *alpha*) : ;;
    *) echo "[FAIL] migrated ownership does not include skill:alpha" >&2; return 1 ;;
  esac
  case "${ownership_output}" in
    *tester*) : ;;
    *) echo "[FAIL] migrated ownership does not include agent:tester" >&2; return 1 ;;
  esac
  return 0
}

test_haws_state_and_skill_selection_are_git_ignored() {
  new_fixture
  cp "${PROJECT_ROOT}/.gitignore" "${FIXTURE_REPO}/.gitignore"
  mkdir -p "${FIXTURE_REPO}/.haws/state" "${FIXTURE_REPO}/skills"
  : > "${FIXTURE_REPO}/.haws/state/settings.tsv"
  : > "${FIXTURE_REPO}/skills/skills.disabled"
  if ! git -C "${FIXTURE_REPO}" check-ignore -q --no-index ".haws/state/settings.tsv"; then
    echo "[FAIL] .haws/state/ is not ignored" >&2
    return 1
  fi
  if ! git -C "${FIXTURE_REPO}" check-ignore -q --no-index "skills/skills.disabled"; then
    echo "[FAIL] skills/skills.disabled is not ignored" >&2
    return 1
  fi
  return 0
}

run_test() {
  local test_name="$1"
  if "$test_name"; then
    echo "PASS ${test_name}"
    passed=$((passed + 1))
  else
    echo "FAIL ${test_name}"
    failed=$((failed + 1))
  fi
  cleanup_fixture
}

trap cleanup_fixture EXIT

run_test test_empty_disabled_environment_file_means_all_enabled
run_test test_existing_disabled_environment_file_is_not_overwritten_by_migration
run_test test_existing_disabled_skill_file_is_not_overwritten_by_migration
run_test test_valid_legacy_manifest_entries_can_be_migrated
run_test test_haws_state_and_skill_selection_are_git_ignored

echo "CLI state compatibility tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
