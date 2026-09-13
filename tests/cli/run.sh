#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${TEST_DIR}/launcher_menu_test.sh"
bash "${TEST_DIR}/state_test.sh"
bash "${TEST_DIR}/settings_flow_test.sh"
