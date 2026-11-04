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
    if run_user disconnect --yes > "${tmp}/disconnect/out" 2>&1; then return 1; fi
    [ ! -e "${SCRIPT_DIR}/secondbrain/.git" ] || return 1
    [ "$(cat "${SCRIPT_DIR}/secondbrain/private.txt")" = private ] || return 1
)
parent_fixture() {
    SCRIPT_DIR="${tmp}/$1/app"
    mkdir -p "${SCRIPT_DIR}/secondbrain"
    git init -q -b main "${SCRIPT_DIR}" || return 1
    git -C "${SCRIPT_DIR}" config user.name Test
    git -C "${SCRIPT_DIR}" config user.email test@example.invalid
    printf 'parent tracked\n' > "${SCRIPT_DIR}/tracked.txt"
    git -C "${SCRIPT_DIR}" add tracked.txt
    git -C "${SCRIPT_DIR}" commit -qm initial
    git init --bare -q "${tmp}/$1/remote.git"
    git -C "${SCRIPT_DIR}" remote add origin "${tmp}/$1/remote.git"
    printf 'personal note\n' > "${SCRIPT_DIR}/secondbrain/private.txt"
}
test_parent_disconnect_refused() (
    parent_fixture parent_disconnect || return 1
    local head index before
    head="$(git -C "${SCRIPT_DIR}" rev-parse HEAD)"
    index="$(git -C "${SCRIPT_DIR}" write-tree)"
    before="$(git -C "${SCRIPT_DIR}" status --porcelain -uall)"
    if run_user disconnect --yes > "${tmp}/parent_disconnect/out" 2>&1; then return 1; fi
    [ "$(git -C "${SCRIPT_DIR}" remote get-url origin)" = "${tmp}/parent_disconnect/remote.git" ] || return 1
    [ "$(git -C "${SCRIPT_DIR}" rev-parse HEAD)" = "${head}" ] || return 1
    [ "$(git -C "${SCRIPT_DIR}" write-tree)" = "${index}" ] || return 1
    [ "$(git -C "${SCRIPT_DIR}" status --porcelain -uall)" = "${before}" ] || return 1
    [ "$(cat "${SCRIPT_DIR}/secondbrain/private.txt")" = 'personal note' ]
)
test_parent_status_is_local_only() (
    parent_fixture parent_status || return 1
    run_user status > "${tmp}/parent_status/out" || return 1
    grep -F '[LOCAL-ONLY' "${tmp}/parent_status/out" >/dev/null || return 1
    [ "$(git -C "${SCRIPT_DIR}" remote get-url origin)" = "${tmp}/parent_status/remote.git" ]
)
test_inherited_git_dir_refused() (
    parent_fixture inherited_git || return 1
    git init -q -b main "${SCRIPT_DIR}/secondbrain" || return 1
    if GIT_DIR="${SCRIPT_DIR}/.git" GIT_WORK_TREE="${SCRIPT_DIR}/secondbrain" run_user disconnect --yes > "${tmp}/inherited_git/out" 2>&1; then return 1; fi
    [ "$(git -C "${SCRIPT_DIR}" remote get-url origin)" = "${tmp}/inherited_git/remote.git" ] || return 1
    [ "$(cat "${SCRIPT_DIR}/secondbrain/private.txt")" = 'personal note' ]
)
test_original_git_dir_publish_refused() (
    fixture original_git || return 1
    printf 'private\n' > "${SCRIPT_DIR}/secondbrain/private.txt"
    local head index
    head="$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)"
    index="$(git -C "${SCRIPT_DIR}/secondbrain" write-tree)"
    if printf 'y\n' | GIT_DIR="${SCRIPT_DIR}/secondbrain/.git" GIT_WORK_TREE="${SCRIPT_DIR}/secondbrain" run_user sync > "${tmp}/original_git/out" 2>&1; then return 1; fi
    [ "$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)" = "${head}" ] || return 1
    [ "$(git -C "${SCRIPT_DIR}/secondbrain" write-tree)" = "${index}" ] || return 1
    [ "$(git --git-dir="${tmp}/original_git/remote.git" rev-parse main)" = "${head}" ] || return 1
    [ "$(cat "${SCRIPT_DIR}/secondbrain/private.txt")" = private ]
)
test_connect_git_environment_overrides_refused() (
    parent_fixture connect_env || return 1
    local name
    for name in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES; do
        (
            export "${name}=${SCRIPT_DIR}/.git"
            if run_user connect "${tmp}/connect_env/remote.git" > "${tmp}/connect_env/out" 2>&1; then exit 1; fi
        ) || return 1
        [ ! -e "${SCRIPT_DIR}/secondbrain/.git" ] || return 1
        [ "$(git -C "${SCRIPT_DIR}" remote get-url origin)" = "${tmp}/connect_env/remote.git" ] || return 1
        [ "$(cat "${SCRIPT_DIR}/secondbrain/private.txt")" = 'personal note' ] || return 1
    done
)
test_candidate_worktree_redirection_refused() (
    fixture candidate_worktree || return 1
    git -C "${SCRIPT_DIR}/secondbrain" config core.worktree "${SCRIPT_DIR}/secondbrain" || return 1
    printf 'private\n' > "${SCRIPT_DIR}/secondbrain/private.txt"
    local head index
    head="$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)"
    index="$(git -C "${SCRIPT_DIR}/secondbrain" write-tree)"
    if printf 'y\n' | run_user sync > "${tmp}/candidate_worktree/out" 2>&1; then return 1; fi
    [ "$(git -C "${SCRIPT_DIR}/secondbrain" rev-parse HEAD)" = "${head}" ] || return 1
    [ "$(git -C "${SCRIPT_DIR}/secondbrain" write-tree)" = "${index}" ] || return 1
    [ "$(git --git-dir="${tmp}/candidate_worktree/remote.git" rev-parse main)" = "${head}" ] || return 1
    [ "$(cat "${SCRIPT_DIR}/secondbrain/private.txt")" = private ]
)
failed=0
for test in test_pushurl test_nonmain test_content_race test_head_changes_before_snapshot test_symlink_race test_rename_preview test_disconnect test_parent_disconnect_refused test_parent_status_is_local_only test_inherited_git_dir_refused test_original_git_dir_publish_refused test_connect_git_environment_overrides_refused test_candidate_worktree_redirection_refused; do
    if "${test}"; then echo "PASS ${test}"; else echo "FAIL ${test}"; failed=$((failed + 1)); fi
done
[ "${failed}" -eq 0 ]
