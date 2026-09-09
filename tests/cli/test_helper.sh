#!/usr/bin/env bash
# Dependency-free helpers for isolated HAWS CLI integration fixtures.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

FIXTURE_ROOT=""
FIXTURE_REPO=""
FIXTURE_HOME=""
FAKE_BIN=""
OUTPUT_FILE=""
CALL_LOG=""

new_fixture() {
  cleanup_fixture
  FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/haws-cli.XXXXXX")"
  FIXTURE_REPO="${FIXTURE_ROOT}/repo"
  FIXTURE_HOME="${FIXTURE_ROOT}/home"
  FAKE_BIN="${FIXTURE_ROOT}/bin"
  OUTPUT_FILE="${FIXTURE_ROOT}/output.log"
  CALL_LOG="${FIXTURE_ROOT}/calls.log"
  mkdir -p "${FIXTURE_REPO}" "${FIXTURE_HOME}" "${FAKE_BIN}"
  git -C "${FIXTURE_REPO}" init -q
  : > "${OUTPUT_FILE}"
  : > "${CALL_LOG}"
}

cleanup_fixture() {
  if [ -n "${FIXTURE_ROOT:-}" ] && [ -d "${FIXTURE_ROOT}" ]; then
    rm -rf -- "${FIXTURE_ROOT}"
  fi
  FIXTURE_ROOT=""
  FIXTURE_REPO=""
  FIXTURE_HOME=""
  FAKE_BIN=""
  OUTPUT_FILE=""
  CALL_LOG=""
}

run_haws() {
  env HOME="${FIXTURE_HOME}" HAWS_REPO_DIR="${FIXTURE_REPO}" \
    HAWS_CALL_LOG="${CALL_LOG}" PATH="${FAKE_BIN}:${PATH}" \
    bash "${PROJECT_ROOT}/haws.sh" "$@" >"${OUTPUT_FILE}" 2>&1
}

load_state_api() {
  export HOME="${FIXTURE_HOME}"
  export HAWS_REPO_DIR="${FIXTURE_REPO}"
  export HAWS_STATE_DIR="${FIXTURE_REPO}/.haws/state"

  if [ ! -f "${PROJECT_ROOT}/runtime/state.sh" ]; then
    echo "[FAIL] missing state API module: runtime/state.sh" >&2
    return 1
  fi

  # shellcheck disable=SC1091
  . "${PROJECT_ROOT}/runtime/state.sh"
}

install_fake_command() {
  local command_name="$1"
  local exit_status="${2:-0}"
  local command_path="${FAKE_BIN}/${command_name}"

  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\\n" "$0 $*" >> "${HAWS_CALL_LOG}"' \
    "exit ${exit_status}" > "${command_path}"
  chmod +x "${command_path}"
}

assert_status() {
  local expected="$1"
  shift
  "$@"
  local actual=$?
  if [ "${actual}" -ne "${expected}" ]; then
    echo "[FAIL] expected exit ${expected}, got ${actual}: $*" >&2
    return 1
  fi
  return 0
}

assert_output_contains() {
  local needle="$1"
  if ! grep -F -- "${needle}" "${OUTPUT_FILE}" >/dev/null 2>&1; then
    echo "[FAIL] output does not contain: ${needle}" >&2
    return 1
  fi
  return 0
}

assert_file_contains() {
  local file_path="$1"
  local needle="$2"
  if [ ! -f "${file_path}" ] || ! grep -F -- "${needle}" "${file_path}" >/dev/null 2>&1; then
    echo "[FAIL] ${file_path} does not contain: ${needle}" >&2
    return 1
  fi
  return 0
}

assert_no_call() {
  local needle="$1"
  if [ -f "${CALL_LOG}" ] && grep -F -- "${needle}" "${CALL_LOG}" >/dev/null 2>&1; then
    echo "[FAIL] unexpected fake command call: ${needle}" >&2
    return 1
  fi
  return 0
}
