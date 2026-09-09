#!/usr/bin/env bash
# Isolated tests for the source and skill catalog boundary.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/test_helper.sh"

passed=0
failed=0

write_gitmodules() {
  local repo_name="$1"
  local repo_path="$2"
  local repo_url="$3"
  {
    printf '[submodule "%s"]\n' "${repo_name}"
    printf '\tpath = %s\n' "${repo_path}"
    printf '\turl = %s\n' "${repo_url}"
  } > "${FIXTURE_REPO}/.gitmodules"
}

load_catalog_api() {
  export HAWS_REPO_DIR="${FIXTURE_REPO}"
  export HAWS_STATE_DIR="${FIXTURE_REPO}/.haws/state"
  . "${PROJECT_ROOT}/runtime/catalog.sh"
}

init_source_repo() {
  local source_path="$1"
  mkdir -p "${FIXTURE_REPO}/${source_path}"
  git -C "${FIXTURE_REPO}/${source_path}" init -q
  git -C "${FIXTURE_REPO}/${source_path}" config user.email test@example.invalid
  git -C "${FIXTURE_REPO}/${source_path}" config user.name "HAWS Test"
  git -C "${FIXTURE_REPO}/${source_path}" config core.autocrlf false
}

commit_source() {
  local source_path="$1"
  git -C "${FIXTURE_REPO}/${source_path}" add .
  git -C "${FIXTURE_REPO}/${source_path}" commit -qm snapshot
}

test_gitmodules_is_the_only_versioned_source_registry() {
  new_fixture
  local source_path="skills/packs/alpha"
  init_source_repo "${source_path}"
  mkdir -p "${FIXTURE_REPO}/skills/packs/unregistered"
  printf '# Alpha\n' > "${FIXTURE_REPO}/${source_path}/SKILL.md"
  write_gitmodules "${source_path}" "${source_path}" "https://example.invalid/alpha.git"
  load_catalog_api
  local rows
  rows="$(catalog_sources)"
  printf '%s\n' "${rows}" | awk -F '\t' -v p="${source_path}" -v u="https://example.invalid/alpha.git" \
    '$2 == p && $3 == u && $1 == "'"${source_path}"'::'"${source_path}"'" && NF == 4 {found=1} END {exit found ? 0 : 1}' || return 1
  ! printf '%s\n' "${rows}" | grep -F 'unregistered' >/dev/null 2>&1
}

test_skill_requires_nonempty_skill_md_entrypoint() {
  new_fixture
  local source_path="skills/packs/alpha"
  init_source_repo "${source_path}"
  mkdir -p "${FIXTURE_REPO}/${source_path}/empty" "${FIXTURE_REPO}/${source_path}/valid"
  : > "${FIXTURE_REPO}/${source_path}/empty/SKILL.md"
  printf '%s\n' '---' 'name: Valid Skill' '---' > "${FIXTURE_REPO}/${source_path}/valid/SKILL.md"
  write_gitmodules "${source_path}" "${source_path}" "https://example.invalid/alpha.git"
  load_catalog_api
  local rows
  rows="$(catalog_skills)"
  ! printf '%s\n' "${rows}" | grep -F '/empty/SKILL.md' >/dev/null 2>&1 || return 1
  printf '%s\n' "${rows}" | grep -F 'Valid Skill' >/dev/null 2>&1
}

test_duplicate_names_remain_distinct_by_source_id() {
  new_fixture
  local first="skills/packs/one" second="skills/packs/two"
  init_source_repo "${first}"; init_source_repo "${second}"
  mkdir -p "${FIXTURE_REPO}/${first}/shared" "${FIXTURE_REPO}/${second}/shared"
  printf '%s\n' 'name: Shared' > "${FIXTURE_REPO}/${first}/shared/SKILL.md"
  printf '%s\n' 'name: Shared' > "${FIXTURE_REPO}/${second}/shared/SKILL.md"
  {
    printf '[submodule "%s"]\n\tpath = %s\n\turl = https://example.invalid/one.git\n' "${first}" "${first}"
    printf '[submodule "%s"]\n\tpath = %s\n\turl = https://example.invalid/two.git\n' "${second}" "${second}"
  } > "${FIXTURE_REPO}/.gitmodules"
  load_catalog_api
  local rows count ids
  rows="$(catalog_skills)"
  count="$(printf '%s\n' "${rows}" | grep -c 'Shared' || true)"
  [ "${count}" -eq 2 ] || return 1
  ids="$(printf '%s\n' "${rows}" | cut -f1 | sort -u | wc -l | tr -d ' ')"
  [ "${ids}" -eq 2 ]
}

test_absent_disabled_file_enables_every_discovered_skill() {
  new_fixture
  local source_path="skills/packs/alpha"
  init_source_repo "${source_path}"
  mkdir -p "${FIXTURE_REPO}/${source_path}/one" "${FIXTURE_REPO}/${source_path}/two"
  printf 'name: One\n' > "${FIXTURE_REPO}/${source_path}/one/SKILL.md"
  printf 'name: Two\n' > "${FIXTURE_REPO}/${source_path}/two/SKILL.md"
  write_gitmodules "${source_path}" "${source_path}" "https://example.invalid/alpha.git"
  load_catalog_api
  local inactive
  inactive="$(catalog_skills | awk -F '\t' '$5 != "1" {count++} END {print count+0}')"
  [ "${inactive}" -eq 0 ]
}

test_source_with_no_active_skills_is_ineligible() {
  new_fixture
  local source_path="skills/packs/alpha"
  init_source_repo "${source_path}"
  mkdir -p "${FIXTURE_REPO}/${source_path}/one"
  printf 'name: One\n' > "${FIXTURE_REPO}/${source_path}/one/SKILL.md"
  write_gitmodules "${source_path}" "${source_path}" "https://example.invalid/alpha.git"
  printf '%s::%s\n' "${source_path}::${source_path}" "one/SKILL.md" > "${FIXTURE_REPO}/skills/skills.disabled"
  load_catalog_api
  local source_id="${source_path}::${source_path}"
  ! source_has_active_skills "${source_id}"
}

test_changed_paths_classify_inactive_only_update() {
  new_fixture
  local source_path="skills/packs/alpha"
  init_source_repo "${source_path}"
  mkdir -p "${FIXTURE_REPO}/${source_path}/active" "${FIXTURE_REPO}/${source_path}/inactive"
  printf 'name: Active\n' > "${FIXTURE_REPO}/${source_path}/active/SKILL.md"
  printf 'name: Inactive\n' > "${FIXTURE_REPO}/${source_path}/inactive/SKILL.md"
  commit_source "${source_path}"
  local old_rev
  old_rev="$(git -C "${FIXTURE_REPO}/${source_path}" rev-parse HEAD)"
  printf 'inactive update\n' >> "${FIXTURE_REPO}/${source_path}/inactive/SKILL.md"
  commit_source "${source_path}"
  local inactive_rev
  inactive_rev="$(git -C "${FIXTURE_REPO}/${source_path}" rev-parse HEAD)"
  printf 'active update\n' >> "${FIXTURE_REPO}/${source_path}/active/SKILL.md"
  commit_source "${source_path}"
  local active_rev
  active_rev="$(git -C "${FIXTURE_REPO}/${source_path}" rev-parse HEAD)"
  write_gitmodules "${source_path}" "${source_path}" "https://example.invalid/alpha.git"
  printf '%s::%s\n' "${source_path}::${source_path}" "inactive/SKILL.md" > "${FIXTURE_REPO}/skills/skills.disabled"
  load_catalog_api
  local source_id="${source_path}::${source_path}"
  ! changed_paths_affect_active_skills "${source_id}" "${old_rev}" "${inactive_rev}" || return 1
  changed_paths_affect_active_skills "${source_id}" "${inactive_rev}" "${active_rev}"
}

run_test() {
  local test_name="$1"
  if "${test_name}"; then
    echo "PASS ${test_name}"
    passed=$((passed + 1))
  else
    echo "FAIL ${test_name}"
    failed=$((failed + 1))
  fi
  cleanup_fixture
}

trap cleanup_fixture EXIT
run_test test_gitmodules_is_the_only_versioned_source_registry
run_test test_skill_requires_nonempty_skill_md_entrypoint
run_test test_duplicate_names_remain_distinct_by_source_id
run_test test_absent_disabled_file_enables_every_discovered_skill
run_test test_source_with_no_active_skills_is_ineligible
run_test test_changed_paths_classify_inactive_only_update
echo "CLI catalog tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
