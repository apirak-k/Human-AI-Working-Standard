#!/usr/bin/env bash
# ==============================================================================
# HAWS Doctor Shell Wrapper (macOS / Linux / Git Bash)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Detect functional Python 3 command (robust against Windows Store shims)
PY_CMD=""
if command -v py &>/dev/null && py -3 -c "import sys" &>/dev/null; then
    PY_CMD="py -3"
elif command -v python3 &>/dev/null && python3 -c "import sys" &>/dev/null; then
    PY_CMD="python3"
elif command -v python &>/dev/null && python -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" &>/dev/null; then
    PY_CMD="python"
fi

if [ -z "${PY_CMD}" ]; then
    echo "Error: Python 3 is required to run haws doctor but was not found." >&2
    exit 1
fi

exec ${PY_CMD} "${SCRIPT_DIR}/haws_doctor.py" --repo-root "${REPO_ROOT}" "$@"
