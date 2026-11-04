#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/haws-brain-safety.XXXXXX")"
trap 'rm -rf -- "${tmp}"' EXIT
HAWS_SOURCE_ONLY=1 source "${root}/haws.sh"
fixture() {
    local name="$1"
    SCRIPT_DIR="${tmp}/${name}/app"
    mkdir -p "${SCRIPT_DIR}/secondbrain"
    git init -q -b main "${SCRIPT_DIR}/secondbrain"
    git -C "${SCRIPT_DIR}/secondbrain" config user.name Test
    git -C "${SCRIPT_DIR}/secondbrain" config user.email test@example.invalid
    printf 'original\n' > "${SCRIPT_DIR}/secondbrain/old.txt"
    git -C "${SCRIPT_DIR}/secondbrain" add old.txt
    git -C "${SCRIPT_DIR}/secondbrain" commit -qm initial
    git init --bare -q "${tmp}/${name}/remote.git"
    git -C "${SCRIPT_DIR}/secondbrain" remote add origin "${tmp}/${name}/remote.git"
    git -C "${SCRIPT_DIR}/secondbrain" push -q origin main
}
test_pushurl() (
    set -e
    fixture pushurl
    git init --bare -q "${tmp}/pushurl/other.git"
    git -C "${SCRIPT_DIR}/secondbrain" remote set-url --push origin "${tmp}/pushurl/other.git"
    printf 'secret\n' > "${SCRIPT_DIR}/secondbrain/secret.txt"
    if printf 'y\n' | run_user sync > "${tmp}/pushurl/out" 2>&1; then return 1; fi
    ! git --git-dir="${tmp}/pushurl/other.git" rev-parse --verify main >/dev/null 2>&1 || return 1
    git -C "${SCRIPT_DIR}/secondbrain" remote set-url --push origin "${tmp}/pushurl/remote.git"
    git -C "${SCRIPT_DIR}/secondbrain" remote set-url --add --push origin "${tmp}/pushurl/other.git"
    if printf 'y\n' | run_user sync > "${tmp}/pushurl/out" 2>&1; then return 1; fi
    ! git --git-dir="${tmp}/pushurl/other.git" rev-parse --verify main >/dev/null 2>&1 || return 1
    run_user connect "${tmp}/pushurl/remote.git" > "${tmp}/pushurl/out"
    [ "$(git -C "${SCRIPT_DIR}/secondbrain" remote get-url --push origin)" = "${tmp}/pushurl/remote.git" ] || return 1
)
test_nonmain() (
    set -e
    fixture nonmain
    git --git-dir="${tmp}/nonmain/remote.git" branch other main
    git --git-dir="${tmp}/nonmain/remote.git" branch -D main >/dev/null
    local head
    head="$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)"
    if printf 'y\n' | run_user sync > "${tmp}/nonmain/out" 2>&1; then return 1; fi
    [ "$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)" = "${head}" ] || return 1
    ! git --git-dir="${tmp}/nonmain/remote.git" rev-parse --verify main >/dev/null 2>&1 || return 1
    [ "$(git --git-dir="${tmp}/nonmain/remote.git" rev-parse other)" = "${head}" ] || return 1
)
test_content_race() (
    set -e
    fixture race
    printf 'previewed\n' > "${SCRIPT_DIR}/secondbrain/private.txt"
    local head index
    head="$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)"
    index="$(git -C "${SCRIPT_DIR}/secondbrain" write-tree)"
    read() { printf 'changed after preview\n' > "${SCRIPT_DIR}/secondbrain/private.txt"; builtin read "$@"; }
    if run_user sync > "${tmp}/race/out" 2>&1 <<<'y'; then return 1; fi
    [ "$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)" = "${head}" ] || return 1
    [ "$(git -C "${SCRIPT_DIR}/secondbrain" write-tree)" = "${index}" ] || return 1
    [ "$(git --git-dir="${tmp}/race/remote.git" rev-parse main)" = "${head}" ] || return 1
    [ "$(cat "${SCRIPT_DIR}/secondbrain/private.txt")" = 'changed after preview' ] || return 1
)
test_head_changes_before_snapshot() (
    set -e
    fixture headrace
    local head
    head="$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)"
    git() {
        if [[ " $* " == *" ls-remote --heads origin "* ]] && [ ! -f "${tmp}/headrace/changed" ]; then
            command git "$@" || return 1
            printf 'new committed content\n' > "${SCRIPT_DIR}/secondbrain/new.txt"
            command git -C "${SCRIPT_DIR}/secondbrain" add new.txt
            command git -C "${SCRIPT_DIR}/secondbrain" commit -qm concurrent
            : > "${tmp}/headrace/changed"
        else
            command git "$@"
        fi
    }
    if printf 'y\n' | run_user sync > "${tmp}/headrace/out" 2>&1; then return 1; fi
    [ "$(command git --git-dir="${tmp}/headrace/remote.git" rev-parse main)" = "${head}" ] || return 1
    [ -f "${SCRIPT_DIR}/secondbrain/new.txt" ]
)
test_symlink_race() (
    set -e
    fixture symlink
    printf 'same\n' > "${tmp}/symlink/a"
    cp "${tmp}/symlink/a" "${tmp}/symlink/b"
    ln -s "${tmp}/symlink/a" "${SCRIPT_DIR}/secondbrain/link"
    local head
    head="$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)"
    read() { ln -sf "${tmp}/symlink/b" "${SCRIPT_DIR}/secondbrain/link"; builtin read "$@"; }
    if run_user sync > "${tmp}/symlink/out" 2>&1 <<<'y'; then return 1; fi
    [ "$(git --git-dir="${tmp}/symlink/remote.git" rev-parse main)" = "${head}" ] || return 1
    [ "$(readlink "${SCRIPT_DIR}/secondbrain/link")" = "${tmp}/symlink/b" ] || return 1
)
test_rename_preview() (
    set -e
    fixture rename
    git -C "${SCRIPT_DIR}/secondbrain" config diff.renames true
    git -C "${SCRIPT_DIR}/secondbrain" mv old.txt new.txt
    git -C "${SCRIPT_DIR}/secondbrain" commit -qm rename
    printf 'n\n' | run_user sync > "${tmp}/rename/out" 2>&1 || true
    grep -Fx 'old.txt' "${tmp}/rename/out" >/dev/null || return 1
    grep -Fx 'new.txt' "${tmp}/rename/out" >/dev/null
)
test_disconnect() (
    set -e
    SCRIPT_DIR="${tmp}/disconnect/app"
    mkdir -p "${SCRIPT_DIR}/secondbrain"
    for doc in USER_PREFERENCES.md ANTI_PATTERNS.md WORKFLOW.md; do printf 'default\n' > "${SCRIPT_DIR}/secondbrain/${doc}"; done
    printf 'private\n' > "${SCRIPT_DIR}/secondbrain/private.txt"
    run_user disconnect --yes > "${tmp}/disconnect/out"
    [ ! -e "${SCRIPT_DIR}/secondbrain/.git" ] || return 1
    [ "$(cat "${SCRIPT_DIR}/secondbrain/private.txt")" = private ] || return 1
)
failed=0
for test in test_pushurl test_nonmain test_content_race test_head_changes_before_snapshot test_symlink_race test_rename_preview test_disconnect; do
    if "${test}"; then echo "PASS ${test}"; else echo "FAIL ${test}"; failed=$((failed + 1)); fi
done
[ "${failed}" -eq 0 ]
