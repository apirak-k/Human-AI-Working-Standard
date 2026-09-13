#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Git hooks export repository-internal paths that must not leak into disposable
# repositories created by the regression suites.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX
bash "${TEST_DIR}/launcher_menu_test.sh"
bash "${TEST_DIR}/state_test.sh"
bash "${TEST_DIR}/settings_flow_test.sh"
bash "${TEST_DIR}/catalog_test.sh"
bash "${TEST_DIR}/repository_skill_test.sh"
bash "${TEST_DIR}/sync_test.sh"
bash "${TEST_DIR}/status_doctor_test.sh"
bash "${TEST_DIR}/uninstall_test.sh"
