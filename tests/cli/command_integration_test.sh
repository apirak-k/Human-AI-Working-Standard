#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"; trap 'rm -rf "${fixture}"' EXIT
export HOME="${fixture}/home" HAWS_REPO_DIR="${fixture}/repo" HAWS_STATE_DIR="${fixture}/state"
mkdir -p "${HOME}" "${HAWS_REPO_DIR}" "${HAWS_STATE_DIR}"
. "${ROOT}/runtime/platform.sh"; . "${ROOT}/runtime/state.sh"; . "${ROOT}/runtime/command_integration.sh"

export HAWS_COMMAND_PLATFORM=linux HAWS_COMMAND_PROFILE="${fixture}/home/.bashrc"
plan="${fixture}/state/command.plan"
command_integration_plan "${plan}" >/dev/null
grep -q 'command-access.*ready' "${plan}"
command_integration_apply "${plan}"
grep -q 'HAWS command integration START' "${HAWS_COMMAND_PROFILE}"
command_integration_apply "${plan}"
[ "$(grep -c 'HAWS command integration START' "${HAWS_COMMAND_PROFILE}")" -eq 1 ]
command_integration_remove
! grep -q 'HAWS command integration START' "${HAWS_COMMAND_PROFILE}"

export HAWS_COMMAND_PLATFORM=windows-git-bash HAWS_COMMAND_AUTORUN_FILE="${fixture}/autorun" HAWS_GIT_BASH_PATH=""
command_integration_plan "${plan}" >/dev/null
grep -q $'^command-access\tblocked\t' "${plan}"

printf '%s\n' 'prompt $g' > "${HAWS_COMMAND_AUTORUN_FILE}"
export HAWS_GIT_BASH_PATH='C:/Program Files/Git/bin/bash.exe'
command_integration_plan "${plan}" >/dev/null
command_integration_apply "${plan}"
grep -q 'prompt \$g.*doskey haws=' "${HAWS_COMMAND_AUTORUN_FILE}"
command_integration_remove
[ "$(cat "${HAWS_COMMAND_AUTORUN_FILE}")" = 'prompt $g' ]
echo '[PASS] command integration fixtures'
