#!/usr/bin/env bash
# Run the CLI integration tests and aggregate their exit status.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
overall_status=0
test_count=0

for test_file in "${SCRIPT_DIR}"/*_test.sh; do
  [ -f "${test_file}" ] || continue
  test_count=$((test_count + 1))
  echo "==> $(basename "${test_file}")"
  if ! bash "${test_file}"; then
    overall_status=1
  fi
done

if [ "${test_count}" -eq 0 ]; then
  echo "[FAIL] no CLI tests found" >&2
  exit 1
fi

exit "${overall_status}"
