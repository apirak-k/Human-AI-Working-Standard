#!/usr/bin/env bash
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
FIXTURE_ROOT=""
FIXTURE_HOME=""
FIXTURE_PROJECT=""

fail() {
    echo "FAIL: $*" >&2
    return 1
}

assert_output_contains() {
    local expected="$1"
    grep -F -- "${expected}" "${OUTPUT_FILE}" >/dev/null 2>&1 ||
        fail "expected output to contain: ${expected}"
}

assert_file_not_exists() {
    local target="$1"
    [ ! -e "${target}" ] && [ ! -L "${target}" ] ||
        fail "expected path not to exist: ${target}"
}

assert_file_contains() {
    local target="$1"
    local expected="$2"
    grep -F -- "${expected}" "${target}" >/dev/null 2>&1 ||
        fail "expected ${target} to contain: ${expected}"
}

create_fixture() {
    FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/haws-batch1.XXXXXX")"
    FIXTURE_HOME="${FIXTURE_ROOT}/home"
    FIXTURE_PROJECT="${FIXTURE_ROOT}/project"
    mkdir -p "${FIXTURE_HOME}" \
        "${FIXTURE_PROJECT}/skills/custom/demo-one" \
        "${FIXTURE_PROJECT}/skills/packs/demo-pack/alpha" \
        "${FIXTURE_PROJECT}/skills/packs/demo-pack/beta"
    cp "${PROJECT_ROOT}/haws.sh" "${FIXTURE_PROJECT}/haws.sh"
    printf '%s\n' '---' 'name: demo-one' 'description: Fixture single skill.' '---' \
        > "${FIXTURE_PROJECT}/skills/custom/demo-one/SKILL.md"
    printf '%s\n' '---' 'name: demo-alpha' 'description: Fixture pack skill alpha.' '---' \
        > "${FIXTURE_PROJECT}/skills/packs/demo-pack/alpha/SKILL.md"
    printf '%s\n' '---' 'name: demo-beta' 'description: Fixture pack skill beta.' '---' \
        > "${FIXTURE_PROJECT}/skills/packs/demo-pack/beta/SKILL.md"
    OUTPUT_FILE="${FIXTURE_ROOT}/output.txt"
}

cleanup_fixture() {
    if [ -n "${FIXTURE_ROOT}" ] && [ -d "${FIXTURE_ROOT}" ]; then
        rm -rf -- "${FIXTURE_ROOT}"
    fi
    FIXTURE_ROOT=""
    FIXTURE_HOME=""
    FIXTURE_PROJECT=""
}

run_test() {
    local name="$1"
    create_fixture
    if "${name}"; then
        echo "PASS ${name}"
        passed=$((passed + 1))
    else
        echo "FAIL ${name}"
        failed=$((failed + 1))
    fi
    cleanup_fixture
}

