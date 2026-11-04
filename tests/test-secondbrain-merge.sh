#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/haws-secondbrain-test.XXXXXX")"
trap 'rm -rf -- "${tmp}"' EXIT
git init --bare -q "${tmp}/remote.git"
git init -q -b main "${tmp}/seed"
git -C "${tmp}/seed" config user.name Test
git -C "${tmp}/seed" config user.email test@example.invalid
printf 'remote notes\n' > "${tmp}/seed/notes.md"
git -C "${tmp}/seed" add notes.md
git -C "${tmp}/seed" commit -qm remote
git -C "${tmp}/seed" push -q "${tmp}/remote.git" main
mkdir -p "${tmp}/app/secondbrain"
git init -q -b main "${tmp}/app/secondbrain"
git -C "${tmp}/app/secondbrain" config user.name Test
git -C "${tmp}/app/secondbrain" config user.email test@example.invalid
for doc in USER_PREFERENCES.md ANTI_PATTERNS.md WORKFLOW.md; do printf "default\n" > "${tmp}/app/secondbrain/${doc}"; done
printf 'local notes\n' > "${tmp}/app/secondbrain/notes.md"
git -C "${tmp}/app/secondbrain" add notes.md USER_PREFERENCES.md ANTI_PATTERNS.md WORKFLOW.md
git -C "${tmp}/app/secondbrain" commit -qm local
printf 'staged changes\n' >> "${tmp}/app/secondbrain/notes.md"
git -C "${tmp}/app/secondbrain" add notes.md
printf 'untracked secret\n' > "${tmp}/app/secondbrain/secret.txt"
HAWS_SOURCE_ONLY=1 source "${root}/haws.sh"
SCRIPT_DIR="${tmp}/app"
local_before="$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)"
remote_before="$(git --git-dir="${tmp}/remote.git" rev-parse main)"
index_before="$(git -C "${SCRIPT_DIR}/secondbrain" write-tree)"
run_user connect "${tmp}/remote.git" > "${tmp}/output"
[ "$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)" = "${local_before}" ]
[ "$(git --git-dir="${tmp}/remote.git" rev-parse main)" = "${remote_before}" ]
[ "$(cat "${SCRIPT_DIR}/secondbrain/notes.md")" = "$(printf 'local notes\nstaged changes')" ]
[ "$(cat "${SCRIPT_DIR}/secondbrain/secret.txt")" = 'untracked secret' ]
if printf 'y\n' | run_user sync > "${tmp}/output" 2>&1; then
    echo 'Diverged publication unexpectedly succeeded' >&2; exit 1
fi
[ "$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)" = "${local_before}" ]
[ "$(git -C "${SCRIPT_DIR}/secondbrain" write-tree)" = "${index_before}" ]
[ "$(git --git-dir="${tmp}/remote.git" rev-parse main)" = "${remote_before}" ]
# A fresh remote is publishable only after an explicit confirmation.
git init --bare -q "${tmp}/empty.git"
run_user connect "${tmp}/empty.git" > "${tmp}/output"
if printf 'n\n' | run_user sync > "${tmp}/preview" 2>&1; then
    echo 'Cancelled publication unexpectedly succeeded' >&2; exit 1
fi
grep -F 'secret.txt' "${tmp}/preview" >/dev/null
[ "$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)" = "${local_before}" ]
[ "$(git -C "${SCRIPT_DIR}/secondbrain" write-tree)" = "${index_before}" ]
! git --git-dir="${tmp}/empty.git" rev-parse --verify main >/dev/null 2>&1
# Simulate a concurrent remote push after the preview and final preflight.
git() {
    if [[ " $* " == *" push origin main "* ]]; then
        command git -C "${tmp}/seed" push -q "${tmp}/empty.git" main || return 1
    fi
    command git "$@"
}
if printf 'y\n' | run_user sync > "${tmp}/race-output" 2>&1; then
    echo 'Concurrent remote update unexpectedly published' >&2; exit 1
fi
unset -f git
[ "$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)" = "${local_before}" ]
[ "$(git -C "${SCRIPT_DIR}/secondbrain" write-tree)" = "${index_before}" ]
[ "$(git --git-dir="${tmp}/empty.git" rev-parse main)" = "${remote_before}" ]
[ "$(git -C "${SCRIPT_DIR}/secondbrain" remote get-url origin)" = "${tmp}/empty.git" ]
[ "$(cat "${SCRIPT_DIR}/secondbrain/notes.md")" = "$(printf 'local notes\nstaged changes')" ]
[ "$(cat "${SCRIPT_DIR}/secondbrain/secret.txt")" = 'untracked secret' ]
# Reconnect an empty remote for the successful publication case.
git init --bare -q "${tmp}/empty-again.git"
run_user connect "${tmp}/empty-again.git" > "${tmp}/output"
printf 'y\n' | run_user sync > "${tmp}/output"
git --git-dir="${tmp}/empty-again.git" show main:secret.txt | grep -F 'untracked secret' >/dev/null
# A previously uninitialized local brain can publish after connecting to an empty remote.
mkdir -p "${tmp}/new-app/secondbrain"
printf 'new notes\n' > "${tmp}/new-app/secondbrain/new.txt"
git init --bare -q "${tmp}/new-empty.git"
SCRIPT_DIR="${tmp}/new-app"
run_user connect "${tmp}/new-empty.git" > "${tmp}/output"
printf 'y\n' | run_user sync > "${tmp}/output"
git --git-dir="${tmp}/new-empty.git" show main:new.txt | grep -F 'new notes' >/dev/null
# Status and connect preserve a checkout with missing defaults and private files.
mkdir -p "${tmp}/status-app/secondbrain"
git init -q -b main "${tmp}/status-app/secondbrain"
git -C "${tmp}/status-app/secondbrain" config user.name Test
git -C "${tmp}/status-app/secondbrain" config user.email test@example.invalid
printf 'tracked\n' > "${tmp}/status-app/secondbrain/notes.txt"
git -C "${tmp}/status-app/secondbrain" add notes.txt
git -C "${tmp}/status-app/secondbrain" commit -qm initial
printf 'private\n' > "${tmp}/status-app/secondbrain/private.txt"
git -C "${tmp}/status-app/secondbrain" remote add origin "${tmp}/empty-again.git"
SCRIPT_DIR="${tmp}/status-app"
status_head="$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)"
status_index="$(git -C "${SCRIPT_DIR}/secondbrain" write-tree)"
status_before="$(git -C "${SCRIPT_DIR}/secondbrain" status --porcelain -uall)"
run_user status > "${tmp}/status-output"
[ "$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)" = "${status_head}" ]
[ "$(git -C "${SCRIPT_DIR}/secondbrain" write-tree)" = "${status_index}" ]
[ "$(git -C "${SCRIPT_DIR}/secondbrain" status --porcelain -uall)" = "${status_before}" ]
[ "$(git -C "${SCRIPT_DIR}/secondbrain" remote get-url origin)" = "${tmp}/empty-again.git" ]
run_user connect "${tmp}/empty-again.git" > "${tmp}/output"
[ "$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)" = "${status_head}" ]
[ "$(git -C "${SCRIPT_DIR}/secondbrain" write-tree)" = "${status_index}" ]
[ "$(git -C "${SCRIPT_DIR}/secondbrain" status --porcelain -uall)" = "${status_before}" ]
[ "$(cat "${SCRIPT_DIR}/secondbrain/private.txt")" = private ]
[ "$(git -C "${SCRIPT_DIR}/secondbrain" remote get-url origin)" = "${tmp}/empty-again.git" ]
echo 'Second Brain safety checks passed'
