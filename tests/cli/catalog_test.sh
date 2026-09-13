#!/usr/bin/env bash
# Batch 4 source-aware catalog and draft collision tests.
#
# UX contract covered by the interactive assertion below:
#   HAWS Settings -> "Skills" -> old "Single Skills"/"Multi-Skill Packs"
#   opens the catalog only when the user enters Skills; q returns without saving.

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${TEST_DIR}/test_helper.sh"

passed=0
failed=0

git_fixture() {
    git -c core.bare=false -c safe.directory='*' "$@"
}

source_haws() {
    grep -q '^catalog_sources()' "${FIXTURE_PROJECT}/haws.sh" || return 1
    export HOME="${FIXTURE_HOME}"
    export HAWS_REPO_DIR="${FIXTURE_PROJECT}"
    export HAWS_STATE_DIR="${FIXTURE_PROJECT}/.haws/state"
    export GIT_CONFIG_COUNT=2
    export GIT_CONFIG_KEY_0=core.bare
    export GIT_CONFIG_VALUE_0=false
    export GIT_CONFIG_KEY_1=safe.directory
    export GIT_CONFIG_VALUE_1='*'
    export HAWS_SOURCE_ONLY=1
    # shellcheck disable=SC1091
    . "${FIXTURE_PROJECT}/haws.sh"
    unset HAWS_SOURCE_ONLY
}

write_sources() {
    {
        printf '[submodule "source-one"]\n'
        printf '\tpath = skills/packs/source-one\n'
        printf '\turl = https://github.com/acme/source-one.git\n'
        printf '[submodule "source-two"]\n'
        printf '\tpath = skills/packs/source-two\n'
        printf '\turl = https://github.com/other/source-two.git\n'
    } > "${FIXTURE_PROJECT}/.gitmodules"
}

write_skill() {
    local source="$1"
    local directory="$2"
    local name="$3"
    mkdir -p "${FIXTURE_PROJECT}/${source}/${directory}"
    printf '%s\n' '---' "name: ${name}" "description: ${name} fixture." '---' \
        > "${FIXTURE_PROJECT}/${source}/${directory}/SKILL.md"
}

test_catalog_keeps_duplicate_names_source_aware() {
    write_sources
    write_skill "skills/packs/source-one" "shared" "Shared"
    write_skill "skills/packs/source-two" "shared" "Shared"
    source_haws || return 1
    local rows count ids
    rows="$(catalog_skills)"
    count="$(printf '%s\n' "${rows}" | awk -F '\t' '$2 == "Shared" {n++} END {print n+0}')"
    [ "${count}" -eq 2 ] || return 1
    ids="$(printf '%s\n' "${rows}" | awk -F '\t' '$2 == "Shared" {print $1}' | sort -u | wc -l | tr -d ' ')"
    [ "${ids}" -eq 2 ] || return 1
    printf '%s\n' "${rows}" | awk -F '\t' \
        '$2 == "Shared" && $1 ~ /source-one/ && $3 == "source-one::skills\/packs\/source-one" {found=1}
         END {exit found ? 0 : 1}'
}

test_catalog_ignores_empty_skill_entrypoints() {
    write_sources
    mkdir -p "${FIXTURE_PROJECT}/skills/packs/source-one/empty"
    : > "${FIXTURE_PROJECT}/skills/packs/source-one/empty/SKILL.md"
    write_skill "skills/packs/source-one" "valid" "Valid"
    source_haws || return 1
    local rows
    rows="$(catalog_skills)"
    ! printf '%s\n' "${rows}" | grep -F '/empty/SKILL.md' >/dev/null 2>&1 || return 1
    printf '%s\n' "${rows}" | awk -F '\t' '$2 == "Valid" {found=1} END {exit found ? 0 : 1}'
}

test_settings_draft_defers_skill_catalog_until_skills_is_entered() {
    write_sources
    write_skill "skills/packs/source-one" "one" "One"
    source_haws || return 1
    settings_draft_load || return 1
    [ "${HAWS_DRAFT_SKILLS_LOADED:-0}" = 0 ] || return 1
    if settings_skills_page <<< 'q' >"${OUTPUT_FILE}" 2>&1; then
        :
    fi
    [ "${HAWS_DRAFT_SKILLS_LOADED:-0}" = 1 ] || return 1
    assert_output_contains 'Single Skills'
}

test_catalog_validates_github_urls_and_safe_destinations() {
    source_haws || return 1
    catalog_validate_url 'https://github.com/acme/useful-skill.git' || return 1
    catalog_validate_url 'https://github.com/acme/useful-skill' || return 1
    if catalog_validate_url 'https://github.com/acme/../useful-skill'; then return 1; fi
    if catalog_validate_url 'http://github.com/acme/useful-skill'; then return 1; fi
    catalog_validate_destination 'skills/packs/useful-skill' || return 1
    if catalog_validate_destination '../outside'; then return 1; fi
    mkdir -p "${FIXTURE_PROJECT}/skills/packs/existing"
    if catalog_validate_destination 'skills/packs/existing'; then return 1; fi
}

test_duplicate_url_does_not_mutate_source_draft() {
    source_haws || return 1
    settings_draft_load || return 1
    settings_draft_add_source 'https://github.com/acme/shared.git' || return 1
    local before="${HAWS_DRAFT_ADDED_REPOSITORIES:-}|${HAWS_DRAFT_ADDED_PATHS:-}"
    if settings_draft_add_source 'https://github.com/acme/shared.git'; then return 1; fi
    [ "${before}" = "${HAWS_DRAFT_ADDED_REPOSITORIES:-}|${HAWS_DRAFT_ADDED_PATHS:-}" ]
}

test_duplicate_destination_does_not_mutate_source_draft() {
    source_haws || return 1
    settings_draft_load || return 1
    settings_draft_add_source 'https://github.com/acme/shared.git' || return 1
    local before="${HAWS_DRAFT_ADDED_REPOSITORIES:-}|${HAWS_DRAFT_ADDED_PATHS:-}"
    if settings_draft_add_source 'https://github.com/other/shared.git'; then return 1; fi
    [ "${before}" = "${HAWS_DRAFT_ADDED_REPOSITORIES:-}|${HAWS_DRAFT_ADDED_PATHS:-}" ]
}

run_test() {
    local test_name="$1"
    create_fixture
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

run_test test_catalog_keeps_duplicate_names_source_aware
run_test test_catalog_ignores_empty_skill_entrypoints
run_test test_settings_draft_defers_skill_catalog_until_skills_is_entered
run_test test_catalog_validates_github_urls_and_safe_destinations
run_test test_duplicate_url_does_not_mutate_source_draft
run_test test_duplicate_destination_does_not_mutate_source_draft

echo "CLI Batch 4 catalog tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
