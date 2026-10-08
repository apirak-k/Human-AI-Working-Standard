#!/usr/bin/env bash
# Batch 4 repository draft/application and old Single/Pack integration tests.
#
# UX route contracts covered here:
#   HAWS Settings -> "Repositories" -> old Add/Remove Git Repository actions
#   remain draft-only; Back/q returns without repository mutation.
#   HAWS Settings -> "Skills" retains "Single Skills" and "Multi-Skill Packs";
#   checklist q returns without writing legacy skill state.

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${TEST_DIR}/test_helper.sh"

passed=0
failed=0
REMOTE_URL=""

git_fixture() {
    git -c core.bare=false -c safe.directory='*' \
        -c protocol.file.allow=always "$@"
}

source_haws() {
    grep -q '^settings_plan_build()' "${FIXTURE_PROJECT}/haws.sh" || return 1
    export HOME="${FIXTURE_HOME}"
    export CODEX_HOME="${FIXTURE_HOME}/.codex"
    export HAWS_REPO_DIR="${FIXTURE_PROJECT}"
    export HAWS_STATE_DIR="${FIXTURE_PROJECT}/.haws/state"
    export GIT_CONFIG_COUNT=3
    export GIT_CONFIG_KEY_0=core.bare
    export GIT_CONFIG_VALUE_0=false
    export GIT_CONFIG_KEY_1=safe.directory
    export GIT_CONFIG_VALUE_1='*'
    export GIT_CONFIG_KEY_2=protocol.file.allow
    export GIT_CONFIG_VALUE_2=always
    export HAWS_SOURCE_ONLY=1
    # shellcheck disable=SC1091
    . "${FIXTURE_PROJECT}/haws.sh"
    unset HAWS_SOURCE_ONLY
}

write_sync_settings() {
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema_version\t1\nauto_update\toff\n' \
        > "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
}

prepare_worktree_skill_checkout() {
    local project="$1"
    local marker="$2"
    mkdir -p "${project}/skills/custom/worktree-skill"
    cp "${PROJECT_ROOT}/haws.sh" "${project}/haws.sh"
    printf '%s\n' '---' 'name: worktree-skill' "description: ${marker}" '---' \
        > "${project}/skills/custom/worktree-skill/SKILL.md"
    git_fixture -C "${project}" init -q || return 1
    git_fixture -C "${project}" config user.email test@example.invalid
    git_fixture -C "${project}" config user.name "HAWS Test"
    git_fixture -C "${project}" add haws.sh skills/custom/worktree-skill/SKILL.md || return 1
    git_fixture -C "${project}" commit -qm "${marker}" || return 1
    mkdir -p "${project}/.haws/state"
    printf 'schema_version\t1\nauto_update\toff\n' \
        > "${project}/.haws/state/settings.tsv"
}

assert_output_not_contains() {
    local needle="$1"
    ! grep -F -- "${needle}" "${OUTPUT_FILE}" >/dev/null 2>&1
}

init_superproject() {
    git_fixture -C "${FIXTURE_PROJECT}" init -q || return 1
    git_fixture -C "${FIXTURE_PROJECT}" config user.email test@example.invalid
    git_fixture -C "${FIXTURE_PROJECT}" config user.name "HAWS Test"
    printf 'fixture\n' > "${FIXTURE_PROJECT}/README.md"
    git_fixture -C "${FIXTURE_PROJECT}" add README.md
    git_fixture -C "${FIXTURE_PROJECT}" commit -qm fixture
}

make_remote() {
    local name="$1"
    local kind="${2:-single}"
    local bare="${FIXTURE_ROOT}/${name}.git"
    local work="${FIXTURE_ROOT}/${name}-work"
    git_fixture init --bare -q "${bare}" || return 1
    mkdir -p "${work}"
    git_fixture -C "${work}" init -q || return 1
    git_fixture -C "${work}" config user.email test@example.invalid
    git_fixture -C "${work}" config user.name "HAWS Test"
    if [ "${kind}" = single ]; then
        printf '%s\n' '---' "name: ${name}-skill" '---' > "${work}/SKILL.md"
    else
        mkdir -p "${work}/alpha" "${work}/beta"
        printf '%s\n' 'name: alpha' > "${work}/alpha/SKILL.md"
        printf '%s\n' 'name: beta' > "${work}/beta/SKILL.md"
    fi
    git_fixture -C "${work}" add .
    git_fixture -C "${work}" commit -qm source
    git_fixture -C "${work}" branch -M main
    git_fixture -C "${work}" remote add origin "file://${bare}"
    git_fixture -C "${work}" push -q -u origin main || return 1
    git_fixture --git-dir="${bare}" symbolic-ref HEAD refs/heads/main
    REMOTE_URL="file://${bare}"
}

write_catalog_skill() {
    local relative_path="$1"
    local skill_name="$2"
    local description="$3"
    mkdir -p "${FIXTURE_PROJECT}/$(dirname "${relative_path}")"
    printf '%s\n' '---' "name: ${skill_name}" "description: ${description}" '---' \
        > "${FIXTURE_PROJECT}/${relative_path}"
}

write_sync_settings() {
    local auto_update="${1:-off}"
    mkdir -p "${FIXTURE_PROJECT}/.haws/state"
    printf 'schema_version\t1\nsecond_brain\toff\nauto_update\t%s\n' \
        "${auto_update}" > "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
}

create_test_directory_link() {
    local target="$1"
    local link="$2"

    if command -v cmd.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
        local win_target win_link
        win_target="$(cygpath -w "${target}")" || return 1
        win_link="$(cygpath -w "${link}")" || return 1
        MSYS_NO_PATHCONV=1 cmd.exe /c mklink /J "${win_link}" "${win_target}" \
            >/dev/null 2>&1
    else
        ln -s "${target}" "${link}"
    fi
}

prepare_logical_skill_catalog() {
    init_superproject || return 1
    rm -rf -- "${FIXTURE_PROJECT}/skills/custom/demo-one"
    {
        printf '[submodule "source-one"]\n'
        printf '\tpath = skills/packs/source-one\n'
        printf '\turl = https://github.com/acme/source-one.git\n'
        printf '[submodule "source-two"]\n'
        printf '\tpath = skills/packs/source-two\n'
        printf '\turl = https://github.com/acme/source-two.git\n'
        printf '[submodule "source-uninitialized"]\n'
        printf '\tpath = skills/standalone/source-uninitialized\n'
        printf '\turl = https://github.com/acme/source-uninitialized.git\n'
    } > "${FIXTURE_PROJECT}/.gitmodules"

    write_catalog_skill \
        'skills/packs/source-one/shared-skill/SKILL.md' \
        'Shared Skill' 'Canonical source-one description.'
    write_catalog_skill \
        'skills/packs/source-one/.openclaw/shared-skill/SKILL.md' \
        'Shared Skill' 'Adapter copy must not win.'
    write_catalog_skill \
        'skills/packs/source-one/caveman/plugins/shared-skill/SKILL.md' \
        'Shared Skill' 'Vendor copy must not win.'
    write_catalog_skill \
        'skills/packs/source-one/planning-with-files/SKILL.md' \
        'planning-with-files' 'Filtered planning copy.'
    write_catalog_skill \
        'skills/packs/source-one/.agents/skills/planning-with-files/SKILL.md' \
        'planning-with-files' 'Canonical planning description.'
    write_catalog_skill \
        'skills/packs/source-one/planning-with-files-v2/SKILL.md' \
        'planning-with-files-v2' 'Versioned planning copy.'
    write_catalog_skill \
        'skills/packs/source-one/ui-ux-pro-max/SKILL.md' \
        'ui-ux-pro-max' 'Filtered UI copy.'
    write_catalog_skill \
        'skills/packs/source-one/.claude/skills/ui-ux-pro-max/SKILL.md' \
        'ui-ux-pro-max' 'Canonical UI description.'
    write_catalog_skill \
        'skills/packs/source-one/design-taste-frontend-v1/SKILL.md' \
        'design-taste-frontend-v1' 'Versioned design copy.'
    mkdir -p "${FIXTURE_PROJECT}/skills/packs/source-one/.codex-plugin" \
        "${FIXTURE_PROJECT}/skills/packs/source-one/hooks" \
        "${FIXTURE_PROJECT}/skills/packs/source-one/commands" \
        "${FIXTURE_PROJECT}/skills/packs/source-one/references" \
        "${FIXTURE_PROJECT}/skills/packs/source-one/templates"
    printf '%s\n' '{}' > "${FIXTURE_PROJECT}/skills/packs/source-one/.codex-plugin/plugin.json"
    printf '%s\n' hook > "${FIXTURE_PROJECT}/skills/packs/source-one/hooks/test.sh"
    printf '%s\n' command > "${FIXTURE_PROJECT}/skills/packs/source-one/commands/test.md"
    printf '%s\n' reference > "${FIXTURE_PROJECT}/skills/packs/source-one/references/test.md"
    printf '%s\n' template > "${FIXTURE_PROJECT}/skills/packs/source-one/templates/test.md"
    write_catalog_skill \
        'skills/packs/source-two/shared-skill/SKILL.md' \
        'Shared Skill' 'Canonical source-two description.'
    write_catalog_skill \
        'skills/custom/catalog-custom/SKILL.md' \
        'Catalog Custom' 'Local custom description.'
}

test_catalog_resolves_source_scoped_logical_skills() {
    prepare_logical_skill_catalog || return 1
    enable_local_sources
    source_haws || return 1

    local rows
    rows="$(catalog_skills)"

    printf '%s\n' "${rows}" | awk -F '\t' '
        $1 == "source-one::skills/packs/source-one" && $3 == "Shared Skill" {
            count++
            if (NF == 6 && $2 == "source-one::skills/packs/source-one::Shared Skill" &&
                $4 == "Canonical source-one description." &&
                $5 == "shared-skill/SKILL.md" && $6 == 1) {
                canonical++
            }
        }
        END { exit !(count == 1 && canonical == 1) }' || return 1

    printf '%s\n' "${rows}" | awk -F '\t' '
        $1 == "source-two::skills/packs/source-two" && $3 == "Shared Skill" {
            count++
            if (NF == 6 && $2 == "source-two::skills/packs/source-two::Shared Skill" &&
                $4 == "Canonical source-two description." &&
                $5 == "shared-skill/SKILL.md" && $6 == 1) {
                canonical++
            }
        }
        END { exit !(count == 1 && canonical == 1) }' || return 1

    printf '%s\n' "${rows}" | awk -F '\t' '
        $1 == "custom::skills/custom" &&
            $2 == "custom::skills/custom::Catalog Custom" &&
            $3 == "Catalog Custom" && $4 == "Local custom description." && NF == 6 {found++}
        END { exit !(found == 1) }' || return 1
}

test_catalog_respects_repository_folder_taxonomy() {
    prepare_logical_skill_catalog || return 1
    source_haws || return 1

    [ "$(catalog_source_kind 'source-one::skills/packs/source-one')" = PACK ] || return 1
    [ "$(catalog_source_kind 'source-two::skills/packs/source-two')" = PACK ] || return 1
    [ "$(catalog_source_kind 'custom::skills/custom')" = SINGLE ] || return 1
    [ "$(catalog_source_kind 'source-uninitialized::skills/standalone/source-uninitialized')" = UNVERIFIED ] || return 1
}

test_catalog_keeps_only_historical_canonical_skill_copies() {
    prepare_logical_skill_catalog || return 1
    source_haws || return 1

    local rows
    rows="$(catalog_skills)"
    printf '%s\n' "${rows}" | awk -F '\t' '
        $3 == "planning-with-files" && $4 == "Canonical planning description." { planning++ }
        $3 == "ui-ux-pro-max" && $4 == "Canonical UI description." { ui++ }
        $3 == "planning-with-files-v2" || $3 == "design-taste-frontend-v1" { rejected++ }
        END { exit !(planning == 1 && ui == 1 && rejected == 0) }' || return 1
    ! printf '%s\n' "${rows}" | grep -F 'Filtered planning copy.' >/dev/null 2>&1 || return 1
    ! printf '%s\n' "${rows}" | grep -F 'Filtered UI copy.' >/dev/null 2>&1 || return 1
}

enable_local_sources() {
    export HAWS_TEST_ALLOW_LOCAL_SOURCES=1
    export HAWS_TEST_NO_INTEGRATION=1
}

prepare_clean_kit_project() {
    init_superproject || return 1
    printf '/.haws/\n/ai-configs/environments.disabled\n' > "${FIXTURE_PROJECT}/.gitignore"
    git_fixture -C "${FIXTURE_PROJECT}" add .gitignore haws.sh \
        skills/custom skills/packs/demo-pack || return 1
    git_fixture -C "${FIXTURE_PROJECT}" commit -qm 'clean HAWS fixture' || return 1
}

prepare_pending_kit_source() {
    local name="${1:-pending-source}"
    prepare_clean_kit_project || return 1
    make_remote "${name}" single || return 1
    printf '# Existing tracked skill sources\n' > "${FIXTURE_PROJECT}/.gitmodules"
    git_fixture -C "${FIXTURE_PROJECT}" add .gitmodules || return 1
    git_fixture -C "${FIXTURE_PROJECT}" commit -qm 'track an empty submodule registry' || return 1
    git_fixture -C "${FIXTURE_PROJECT}" submodule add -- "${REMOTE_URL}" \
        "skills/packs/${name}" || return 1
}

test_kit_migrate_converts_exact_pending_addition() {
    prepare_pending_kit_source pending-migrate || return 1
    source_haws || return 1
    enable_local_sources
    mkdir -p "${FIXTURE_HOME}/.claude"

    if ! run_kit migrate pending-migrate >"${OUTPUT_FILE}" 2>&1; then
        cat "${OUTPUT_FILE}" >&2
        return 1
    fi
    local device_source="${FIXTURE_PROJECT}/.haws/state/skill-sources/skills/packs/pending-migrate"
    [ -s "${device_source}/SKILL.md" ] || return 1
    [ ! -e "${FIXTURE_PROJECT}/skills/packs/pending-migrate" ] || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" ls-files --stage -- skills/packs/pending-migrate)" ] || return 1
    [ "$(git_fixture -C "${FIXTURE_PROJECT}" show HEAD:.gitmodules)" = '# Existing tracked skill sources' ] || return 1
    catalog_skills | awk -F '\t' '$3 == "pending-migrate-skill" { found=1 } END { exit !found }' || return 1
    [ "${FIXTURE_HOME}/.claude/skills/pending-migrate-skill" -ef "${device_source}" ] || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain=v1 --untracked-files=all)" ] || return 1
    _sync_root_preflight
}

test_kit_migrate_reuses_clean_device_mirror() {
    prepare_pending_kit_source cached-migrate || return 1
    source_haws || return 1
    enable_local_sources
    local source_id device_source old_head
    source_id="$(catalog_sources | cut -f1)" || return 1
    _haws_prepare_device_source "${source_id}" || return 1
    device_source="${FIXTURE_PROJECT}/.haws/state/skill-sources/skills/packs/cached-migrate"
    old_head="$(git_fixture -C "${device_source}" rev-parse HEAD)" || return 1

    if ! run_kit migrate cached-migrate >"${OUTPUT_FILE}" 2>&1; then
        cat "${OUTPUT_FILE}" >&2
        return 1
    fi
    [ "$(git_fixture -C "${device_source}" rev-parse HEAD)" = "${old_head}" ] || return 1
    _catalog_device_source_is_registered skills/packs/cached-migrate || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain=v1 --untracked-files=all)" ]
}

test_kit_migrate_refuses_unrelated_root_changes() {
    prepare_pending_kit_source blocked-root-change || return 1
    source_haws || return 1
    enable_local_sources
    printf '\nUser-owned edit.\n' >> "${FIXTURE_PROJECT}/README.md"

    if run_kit migrate blocked-root-change >"${OUTPUT_FILE}" 2>&1; then
        return 1
    fi
    assert_output_contains 'no files were changed' || return 1
    [ -d "${FIXTURE_PROJECT}/skills/packs/blocked-root-change" ] || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" ls-files --stage -- .haws/state/skill-sources/skills/packs/blocked-root-change)" ] || return 1
    git_fixture -C "${FIXTURE_PROJECT}" ls-files --stage -- skills/packs/blocked-root-change |
        awk '$1 == "160000" {found=1} END {exit !found}'
}

test_kit_migrate_refuses_unrelated_gitmodules_addition() {
    prepare_pending_kit_source blocked-gitmodules-change || return 1
    source_haws || return 1
    enable_local_sources
    git_fixture -C "${FIXTURE_PROJECT}" config --file .gitmodules \
        submodule.unrelated.path skills/packs/unrelated || return 1
    git_fixture -C "${FIXTURE_PROJECT}" config --file .gitmodules \
        submodule.unrelated.url https://github.com/acme/unrelated.git || return 1
    git_fixture -C "${FIXTURE_PROJECT}" add .gitmodules || return 1

    if run_kit migrate blocked-gitmodules-change >"${OUTPUT_FILE}" 2>&1; then
        return 1
    fi
    assert_output_contains 'no files were changed' || return 1
    [ -d "${FIXTURE_PROJECT}/skills/packs/blocked-gitmodules-change" ] || return 1
    git_fixture -C "${FIXTURE_PROJECT}" ls-files --stage -- skills/packs/blocked-gitmodules-change |
        awk '$1 == "160000" {found=1} END {exit !found}'
}

test_kit_migrate_preserves_ignored_submodule_files() {
    prepare_clean_kit_project || return 1
    make_remote ignored-migrate single || return 1
    local source_work="${FIXTURE_ROOT}/ignored-migrate-work"
    printf '/private-cache/\n' > "${source_work}/.gitignore"
    git_fixture -C "${source_work}" add .gitignore || return 1
    git_fixture -C "${source_work}" commit -qm 'ignore private local cache' || return 1
    git_fixture -C "${source_work}" push -q origin main || return 1
    printf '# Existing tracked skill sources\n' > "${FIXTURE_PROJECT}/.gitmodules"
    git_fixture -C "${FIXTURE_PROJECT}" add .gitmodules || return 1
    git_fixture -C "${FIXTURE_PROJECT}" commit -qm 'track an empty submodule registry' || return 1
    git_fixture -C "${FIXTURE_PROJECT}" submodule add -- "${REMOTE_URL}" \
        skills/packs/ignored-migrate || return 1
    mkdir -p "${FIXTURE_PROJECT}/skills/packs/ignored-migrate/private-cache"
    printf 'preserve me\n' > "${FIXTURE_PROJECT}/skills/packs/ignored-migrate/private-cache/user.txt"
    source_haws || return 1
    enable_local_sources

    if run_kit migrate ignored-migrate >"${OUTPUT_FILE}" 2>&1; then
        return 1
    fi
    [ -f "${FIXTURE_PROJECT}/skills/packs/ignored-migrate/private-cache/user.txt" ] || return 1
    git_fixture -C "${FIXTURE_PROJECT}" ls-files --stage -- skills/packs/ignored-migrate |
        awk '$1 == "160000" {found=1} END {exit !found}'
}

test_add_only_apply_creates_device_local_source() {
    prepare_clean_kit_project || return 1
    make_remote add-source single || return 1
    source_haws || return 1
    settings_draft_load || return 1
    enable_local_sources
    settings_draft_add_source "${REMOTE_URL}" || return 1
    settings_plan_build || return 1
    grep -F $'add-source\tsources\t' "${HAWS_PLAN_FILE}" >/dev/null || return 1
    if ! settings_apply_final >"${OUTPUT_FILE}" 2>&1; then
        cat "${OUTPUT_FILE}" >&2
        return 1
    fi
    if [ ! -f "${FIXTURE_PROJECT}/.haws/state/skill-sources/skills/packs/add-source/SKILL.md" ]; then
        echo "device-local source was not created" >&2
        cat "${OUTPUT_FILE}" >&2
        find "${FIXTURE_PROJECT}/.haws/state" -maxdepth 5 -type f -print 2>/dev/null >&2 || true
        return 1
    fi
    ! git_fixture -C "${FIXTURE_PROJECT}" config --file .gitmodules \
        --get submodule.skills/packs/add-source.path >/dev/null 2>&1 || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain --untracked-files=all)" ]
}

test_kit_add_registers_device_source_and_links_skill() {
    prepare_clean_kit_project || return 1
    make_remote hallmark single || return 1
    source_haws || return 1
    enable_local_sources
    mkdir -p "${FIXTURE_HOME}/.claude"

    run_kit add "${REMOTE_URL}" hallmark >"${OUTPUT_FILE}" 2>&1 || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }

    local device_source="${FIXTURE_PROJECT}/.haws/state/skill-sources/skills/packs/hallmark"
    [ -s "${device_source}/SKILL.md" ] || return 1
    catalog_skills | awk -F '\t' '$3 == "hallmark-skill" { found=1 } END { exit !found }' || return 1
    [ -L "${FIXTURE_HOME}/.claude/skills/hallmark-skill" ] || return 1
    [ "${FIXTURE_HOME}/.claude/skills/hallmark-skill" -ef "${device_source}" ] || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain --untracked-files=all)" ] || {
        git_fixture -C "${FIXTURE_PROJECT}" status --short >&2
        return 1
    }
    _sync_root_preflight
}

test_kit_add_survives_remote_skill_update() {
    prepare_clean_kit_project || return 1
    make_remote updated-skill single || return 1
    source_haws || return 1
    enable_local_sources
    mkdir -p "${FIXTURE_HOME}/.claude"
    run_kit add "${REMOTE_URL}" updated-skill >"${OUTPUT_FILE}" 2>&1 || return 1

    local device_source="${FIXTURE_PROJECT}/.haws/state/skill-sources/skills/packs/updated-skill"
    local old_head new_head work="${FIXTURE_ROOT}/updated-skill-work"
    old_head="$(git_fixture -C "${device_source}" rev-parse HEAD)" || return 1
    printf '%s\n' '---' 'name: updated-skill-skill' \
        'description: Updated from remote.' '---' > "${work}/SKILL.md"
    git_fixture -C "${work}" add SKILL.md || return 1
    git_fixture -C "${work}" commit -qm 'update skill' || return 1
    git_fixture -C "${work}" push -q origin main || return 1
    new_head="$(git_fixture -C "${work}" rev-parse HEAD)" || return 1
    [ "${new_head}" != "${old_head}" ] || return 1

    write_sync_settings on
    if ! run_sync >"${OUTPUT_FILE}" 2>&1; then
        cat "${OUTPUT_FILE}" >&2
        return 1
    fi
    [ "$(git_fixture -C "${device_source}" rev-parse HEAD)" = "${new_head}" ] || return 1
    grep -F 'Updated from remote.' "${device_source}/SKILL.md" >/dev/null || return 1
    [ "${FIXTURE_HOME}/.claude/skills/updated-skill-skill" -ef "${device_source}" ] || return 1
    [ -n "$(catalog_sources | grep -F 'skills/packs/updated-skill')" ] || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain --untracked-files=all)" ]
}

test_local_skill_survives_haws_remote_update() {
    prepare_clean_kit_project || return 1
    make_remote hallmark single || return 1
    local haws_remote="${FIXTURE_ROOT}/haws.git"
    git_fixture init --bare -q "${haws_remote}" || return 1
    local branch
    branch="$(git_fixture -C "${FIXTURE_PROJECT}" branch --show-current)" || return 1
    git_fixture -C "${FIXTURE_PROJECT}" remote add origin "${haws_remote}" || return 1
    git_fixture -C "${FIXTURE_PROJECT}" push -q -u origin "${branch}" || return 1
    git_fixture --git-dir="${haws_remote}" symbolic-ref HEAD "refs/heads/${branch}" || return 1

    source_haws || return 1
    enable_local_sources
    mkdir -p "${FIXTURE_HOME}/.claude"
    run_kit add "${REMOTE_URL}" hallmark >"${OUTPUT_FILE}" 2>&1 || return 1
    local device_source="${FIXTURE_PROJECT}/.haws/state/skill-sources/skills/packs/hallmark"
    local upstream="${FIXTURE_ROOT}/haws-upstream"
    git_fixture clone -q "${haws_remote}" "${upstream}" || return 1
    git_fixture -C "${upstream}" config user.name HAWS-Test
    git_fixture -C "${upstream}" config user.email test@example.invalid
    printf 'remote update\n' >> "${upstream}/README.md"
    git_fixture -C "${upstream}" add README.md || return 1
    git_fixture -C "${upstream}" commit -qm 'remote HAWS update' || return 1
    git_fixture -C "${upstream}" push -q origin "${branch}" || return 1
    local remote_head
    remote_head="$(git_fixture -C "${upstream}" rev-parse HEAD)" || return 1

    write_sync_settings on
    if ! run_sync >"${OUTPUT_FILE}" 2>&1; then
        cat "${OUTPUT_FILE}" >&2
        return 1
    fi
    local current_head
    current_head="$(git_fixture -C "${FIXTURE_PROJECT}" rev-parse HEAD)" || return 1
    [ "${current_head}" = "${remote_head}" ] || {
        echo "expected HAWS to advance to ${remote_head}, got ${current_head}" >&2
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    catalog_skills | awk -F '\t' '$3 == "hallmark-skill" { found=1 } END { exit !found }' || return 1
    [ "${FIXTURE_HOME}/.claude/skills/hallmark-skill" -ef "${device_source}" ] || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain --untracked-files=all)" ]
}

test_kit_update_refreshes_device_local_source_when_auto_update_is_off() {
    prepare_clean_kit_project || return 1
    make_remote explicit-update single || return 1
    source_haws || return 1
    enable_local_sources
    run_kit add "${REMOTE_URL}" explicit-update >"${OUTPUT_FILE}" 2>&1 || return 1

    local device_source="${FIXTURE_PROJECT}/.haws/state/skill-sources/skills/packs/explicit-update"
    local old_head new_head work="${FIXTURE_ROOT}/explicit-update-work"
    old_head="$(git_fixture -C "${device_source}" rev-parse HEAD)" || return 1
    printf '%s\n' '---' 'name: explicit-update-skill' \
        'description: Explicit kit update.' '---' > "${work}/SKILL.md"
    git_fixture -C "${work}" add SKILL.md || return 1
    git_fixture -C "${work}" commit -qm 'explicit source update' || return 1
    git_fixture -C "${work}" push -q origin main || return 1
    new_head="$(git_fixture -C "${work}" rev-parse HEAD)" || return 1
    write_sync_settings off

    if ! run_kit update explicit-update >"${OUTPUT_FILE}" 2>&1; then
        cat "${OUTPUT_FILE}" >&2
        return 1
    fi
    [ "${new_head}" != "${old_head}" ] || return 1
    [ "$(git_fixture -C "${device_source}" rev-parse HEAD)" = "${new_head}" ] || return 1
    grep -F 'Explicit kit update.' "${device_source}/SKILL.md" >/dev/null || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain --untracked-files=all)" ]
}

test_doctor_cache_refreshes_after_device_source_changes() {
    prepare_clean_kit_project || return 1
    make_remote health-source single || return 1
    source_haws || return 1
    enable_local_sources
    run_kit add "${REMOTE_URL}" health-source >"${OUTPUT_FILE}" 2>&1 || return 1
    unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE
    _health_collect --deep || return 1
    [ "${HAWS_HEALTH_SKILLS_TOTAL}" -eq 2 ] || return 1

    : > "$(_catalog_device_source_registry)"
    unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE
    _health_collect || return 1
    [ "${HAWS_HEALTH_SKILLS_TOTAL}" -eq 1 ]
}

test_kit_list_includes_device_local_sources() {
    prepare_clean_kit_project || return 1
    make_remote listed single || return 1
    source_haws || return 1
    enable_local_sources
    run_kit add "${REMOTE_URL}" listed >"${OUTPUT_FILE}" 2>&1 || return 1

    run_kit list >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'device-local' || return 1
    assert_output_contains 'skills/packs/listed' || return 1
}

test_kit_prune_removes_device_source_and_owned_link() {
    prepare_clean_kit_project || return 1
    make_remote prunable single || return 1
    source_haws || return 1
    enable_local_sources
    mkdir -p "${FIXTURE_HOME}/.claude"
    run_kit add "${REMOTE_URL}" prunable >"${OUTPUT_FILE}" 2>&1 || return 1

    run_kit prune prunable >"${OUTPUT_FILE}" 2>&1 || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/skill-sources/skills/packs/prunable" || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.claude/skills/prunable-skill" || return 1
    ! catalog_sources | grep -F 'skills/packs/prunable' >/dev/null || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain --untracked-files=all)" ]
}

test_kit_prune_blocks_dirty_device_source() {
    prepare_clean_kit_project || return 1
    make_remote protected single || return 1
    source_haws || return 1
    enable_local_sources
    run_kit add "${REMOTE_URL}" protected >"${OUTPUT_FILE}" 2>&1 || return 1
    local device_source="${FIXTURE_PROJECT}/.haws/state/skill-sources/skills/packs/protected"
    printf 'user edit\n' >> "${device_source}/SKILL.md"

    if run_kit prune protected >"${OUTPUT_FILE}" 2>&1; then
        return 1
    fi
    assert_output_contains 'repository has local changes' || return 1
    [ -f "${device_source}/SKILL.md" ] || return 1
    catalog_sources | grep -F 'skills/packs/protected' >/dev/null
}

test_kit_prune_preserves_ignored_device_source_files() {
    prepare_clean_kit_project || return 1
    make_remote ignored-prune single || return 1
    local source_work="${FIXTURE_ROOT}/ignored-prune-work"
    printf '/private-cache/\n' > "${source_work}/.gitignore"
    git_fixture -C "${source_work}" add .gitignore || return 1
    git_fixture -C "${source_work}" commit -qm 'ignore private local cache' || return 1
    git_fixture -C "${source_work}" push -q origin main || return 1
    source_haws || return 1
    enable_local_sources
    run_kit add "${REMOTE_URL}" ignored-prune >"${OUTPUT_FILE}" 2>&1 || return 1
    local device_source="${FIXTURE_PROJECT}/.haws/state/skill-sources/skills/packs/ignored-prune"
    mkdir -p "${device_source}/private-cache"
    printf 'preserve me\n' > "${device_source}/private-cache/user.txt"

    if run_kit prune ignored-prune >"${OUTPUT_FILE}" 2>&1; then
        return 1
    fi
    assert_output_contains 'repository has local changes' || return 1
    [ -f "${device_source}/private-cache/user.txt" ] || return 1
    _catalog_device_source_is_registered skills/packs/ignored-prune
}

test_kit_prune_refuses_replaced_device_source() {
    prepare_clean_kit_project || return 1
    make_remote replaced-source single || return 1
    source_haws || return 1
    enable_local_sources
    run_kit add "${REMOTE_URL}" replaced-source >"${OUTPUT_FILE}" 2>&1 || return 1
    local device_source="${FIXTURE_PROJECT}/.haws/state/skill-sources/skills/packs/replaced-source"
    git_fixture -C "${device_source}" remote set-url origin https://github.com/acme/unrelated.git || return 1

    if run_kit prune replaced-source >"${OUTPUT_FILE}" 2>&1; then
        return 1
    fi
    assert_output_contains 'origin does not match' || return 1
    [ -s "${device_source}/SKILL.md" ] || return 1
    _catalog_device_source_is_registered skills/packs/replaced-source
}

test_tracked_kit_add_requires_explicit_flag() {
    prepare_clean_kit_project || return 1
    make_remote bundled single || return 1
    source_haws || return 1
    enable_local_sources

    run_kit add --tracked "${REMOTE_URL}" bundled >"${OUTPUT_FILE}" 2>&1 || return 1
    git_fixture -C "${FIXTURE_PROJECT}" config --file .gitmodules \
        --get submodule.skills/packs/bundled.path >/dev/null || return 1
    assert_output_contains 'Commit' || return 1
}

test_kit_update_reports_tracked_submodule_failure() {
    prepare_clean_kit_project || return 1
    make_remote tracked-update single || return 1
    git_fixture -C "${FIXTURE_PROJECT}" submodule add -q -- "${REMOTE_URL}" \
        skills/packs/tracked-update || return 1
    git_fixture -C "${FIXTURE_PROJECT}" add .gitmodules skills/packs/tracked-update || return 1
    git_fixture -C "${FIXTURE_PROJECT}" commit -qm 'add tracked skill source' || return 1
    source_haws || return 1
    enable_local_sources
    write_sync_settings off
    local source_dir="${FIXTURE_PROJECT}/skills/packs/tracked-update"
    local old_head bad_remote="file://${FIXTURE_ROOT}/missing-tracked-update.git"
    old_head="$(git_fixture -C "${source_dir}" rev-parse HEAD)" || return 1
    git_fixture -C "${source_dir}" remote set-url origin "${bad_remote}" || return 1

    if run_kit update tracked-update >"${OUTPUT_FILE}" 2>&1; then
        return 1
    fi
    assert_output_contains 'Submodule tracked-update update failed' || return 1
    [ "$(git_fixture -C "${source_dir}" rev-parse HEAD)" = "${old_head}" ] || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain=v1 --untracked-files=all)" ]
}

test_settings_remove_only_apply_removes_device_local_source() {
    prepare_clean_kit_project || return 1
    make_remote settings-remove single || return 1
    source_haws || return 1
    enable_local_sources
    settings_draft_load || return 1
    settings_draft_add_source "${REMOTE_URL}" || return 1
    settings_plan_build || return 1
    settings_apply_final >"${OUTPUT_FILE}" 2>&1 || return 1

    settings_draft_load || return 1
    local source_id
    source_id="$(catalog_sources | cut -f1)" || return 1
    [ -n "${source_id}" ] || return 1
    settings_draft_remove_source "${source_id}" || return 1
    settings_plan_build || return 1
    if ! settings_apply_final >"${OUTPUT_FILE}" 2>&1; then
        cat "${OUTPUT_FILE}" >&2
        return 1
    fi
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/skill-sources/skills/packs/settings-remove" || return 1
    ! catalog_sources | grep -F 'skills/packs/settings-remove' >/dev/null || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain --untracked-files=all)" ]
}

prepare_registered_source() {
    init_superproject || return 1
    make_remote registered single || return 1
    git_fixture -C "${FIXTURE_PROJECT}" submodule add -q "${REMOTE_URL}" \
        skills/packs/registered || return 1
    mkdir -p "${FIXTURE_PROJECT}/skills/custom"
    printf 'keep me\n' > "${FIXTURE_PROJECT}/skills/custom/user-owned.txt"
}

test_remove_only_apply_removes_registered_source_and_keeps_unrelated_file() {
    prepare_registered_source || return 1
    source_haws || return 1
    settings_draft_load || return 1
    local source_id
    source_id="$(catalog_sources | cut -f1)"
    [ -n "${source_id}" ] || return 1
    settings_draft_remove_source "${source_id}" || return 1
    settings_plan_build || return 1
    grep -F $'remove-source\tsources\t' "${HAWS_PLAN_FILE}" >/dev/null || return 1
    enable_local_sources
    if ! settings_apply_final >"${OUTPUT_FILE}" 2>&1; then
        return 1
    fi
    ! grep -F 'skills/packs/registered' "${FIXTURE_PROJECT}/.gitmodules" \
        >/dev/null 2>&1 || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/skills/packs/registered" || return 1
    assert_file_contains "${FIXTURE_PROJECT}/skills/custom/user-owned.txt" 'keep me'
}

test_reopened_removal_selector_excludes_sources_already_removed_in_draft() {
    prepare_registered_source || return 1
    source_haws || return 1
    settings_draft_load || return 1
    local source_id
    source_id="$(catalog_sources | cut -f1)"
    [ -n "${source_id}" ] || return 1
    settings_draft_remove_source "${source_id}" || return 1

    _settings_repository_remove_page < <(printf 'q') >"${OUTPUT_FILE}" 2>&1 || return 1
    _settings_repository_remove_page < <(printf 'q') >>"${OUTPUT_FILE}" 2>&1 || return 1
    ! grep -F 'skills/packs/registered' "${OUTPUT_FILE}" >/dev/null || return 1
    [ "$(grep -Fc 'No external git repositories currently installed.' "${OUTPUT_FILE}")" -eq 2 ]
}

test_dirty_source_removal_is_blocked_before_disk_removal() {
    prepare_registered_source || return 1
    printf 'local edit\n' >> "${FIXTURE_PROJECT}/skills/packs/registered/SKILL.md"
    source_haws || return 1
    settings_draft_load || return 1
    local source_id
    source_id="$(catalog_sources | cut -f1)"
    settings_draft_remove_source "${source_id}" || return 1
    settings_plan_build || return 1
    enable_local_sources
    if settings_apply_final >"${OUTPUT_FILE}" 2>&1; then
        return 1
    fi
    assert_output_contains 'Blocked: repository has local changes' || return 1
    [ -f "${FIXTURE_PROJECT}/skills/packs/registered/SKILL.md" ] || return 1
    grep -F 'skills/packs/registered' "${FIXTURE_PROJECT}/.gitmodules" >/dev/null
}

test_run_sync_honors_source_aware_disabled_skill_without_legacy_scanner() {
    init_superproject || return 1
    make_remote legacy-disabled single || return 1
    git_fixture -C "${FIXTURE_PROJECT}" submodule add -q "${REMOTE_URL}" \
        skills/packs/legacy-disabled || return 1
    source_haws || return 1
    local skill_id display_name
    skill_id="$(catalog_skills | awk -F '\t' \
        '$1 == "skills/packs/legacy-disabled::skills/packs/legacy-disabled" {print $2; exit}')"
    display_name="$(catalog_skills | awk -F '\t' \
        '$1 == "skills/packs/legacy-disabled::skills/packs/legacy-disabled" {print $3; exit}')"
    [ -n "${skill_id}" ] && [ -n "${display_name}" ] || return 1
    mkdir -p "${FIXTURE_PROJECT}/skills" "${FIXTURE_HOME}/.claude"
    printf '%s\n' "${skill_id}" > "${FIXTURE_PROJECT}/skills/skills.disabled"
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.claude/skills/${display_name}" || return 1
    ! grep -F "skill:${display_name}" "${FIXTURE_HOME}/.haws_manifest" \
        >/dev/null 2>&1 || return 1
    local run_sync_block
    run_sync_block="$(sed -n '/^_run_sync_impl() {/,/^run_sync() {/p' \
        "${FIXTURE_PROJECT}/haws.sh")"
    printf '%s\n' "${run_sync_block}" | grep -F 'catalog_skills' >/dev/null || return 1
    ! printf '%s\n' "${run_sync_block}" | grep -Fq '_legacy_skill_is_disabled'
}

test_direct_skills_route_uses_the_settings_catalog() {
    prepare_logical_skill_catalog || return 1
    enable_local_sources
    local down=$'\033[B'
    printf '%b' "${down}${down}\n\nq" |
        HOME="${FIXTURE_HOME}" CODEX_HOME="${FIXTURE_HOME}/.codex" \
        HAWS_REPO_DIR="${FIXTURE_PROJECT}" \
        HAWS_STATE_DIR="${FIXTURE_PROJECT}/.haws/state" \
        bash "${FIXTURE_PROJECT}/haws.sh" skills >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_output_contains 'Canonical source-one description.' || return 1
    assert_output_contains 'Shared Skill [source-one]' || return 1
    grep -Fq 'settings_skills_page' "${FIXTURE_PROJECT}/haws.sh" || return 1
    ! grep -q '^run_configure_skills()' "${FIXTURE_PROJECT}/haws.sh"
}

test_run_sync_keeps_each_source_qualified_skill_in_state() {
    prepare_logical_skill_catalog || return 1
    write_sync_settings
    mkdir -p "${FIXTURE_HOME}/.agents/skills"
    source_haws || return 1
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || true
    local manifest="${FIXTURE_HOME}/.haws_manifest"
    grep -Fq $'skill:source-one::skills/packs/source-one::Shared Skill\tShared Skill' \
        "${manifest}" || return 1
    grep -Fq $'skill:source-two::skills/packs/source-two::Shared Skill\tShared Skill' \
        "${manifest}"
}

test_run_sync_does_not_create_codex_link_for_plugin_owned_ponytail() {
    init_superproject || return 1
    rm -rf -- "${FIXTURE_PROJECT}/skills/custom/demo-one" \
        "${FIXTURE_PROJECT}/skills/packs/demo-pack"
    mkdir -p "${FIXTURE_PROJECT}/skills/custom/ponytail" \
        "${FIXTURE_HOME}/.agents/skills" \
        "${FIXTURE_HOME}/.codex/plugins/cache/provider/1.0/skills/ponytail"
    write_catalog_skill 'skills/custom/ponytail/SKILL.md' 'ponytail' \
        'HAWS copy of Ponytail.'
    printf '%s\n' 'not a skill entrypoint' > \
        "${FIXTURE_PROJECT}/skills/custom/ponytail/README.md"
    printf '%s\n' '---' 'name: ponytail' 'description: Plugin copy of Ponytail.' '---' \
        > "${FIXTURE_HOME}/.codex/plugins/cache/provider/1.0/skills/ponytail/SKILL.md"
    write_sync_settings
    source_haws || return 1
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || true
    assert_output_contains 'plugin-owned' || return 1
    assert_output_contains 'active catalog skills' || return 1
    assert_output_contains 'Codex links: 0' || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.agents/skills/ponytail" || return 1
    assert_file_contains \
        "${FIXTURE_HOME}/.codex/plugins/cache/provider/1.0/skills/ponytail/SKILL.md" \
        'Plugin copy of Ponytail.'
}

test_run_sync_preserves_unowned_codex_skill_link() {
    init_superproject || return 1
    mkdir -p "${FIXTURE_PROJECT}/skills/custom/foreign-skill" \
        "${FIXTURE_ROOT}/foreign-skill" "${FIXTURE_HOME}/.agents/skills"
    write_catalog_skill 'skills/custom/foreign-skill/SKILL.md' 'foreign-skill' \
        'HAWS source copy.'
    printf '%s\n' 'foreign' > "${FIXTURE_ROOT}/foreign-skill/SKILL.md"
    cp -R "${FIXTURE_ROOT}/foreign-skill" \
        "${FIXTURE_HOME}/.agents/skills/foreign-skill" || return 1
    write_sync_settings
    source_haws || return 1
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || true
    assert_file_contains "${FIXTURE_HOME}/.agents/skills/foreign-skill/SKILL.md" foreign
}

test_run_sync_repairs_dangling_manifest_skill_link() {
    local stale_project="${FIXTURE_ROOT}/stale-project"
    init_superproject || return 1
    mkdir -p "${FIXTURE_PROJECT}/skills/custom/repair-me" \
        "${FIXTURE_HOME}/.claude/skills"
    write_catalog_skill 'skills/custom/repair-me/SKILL.md' 'repair-me' \
        'Repair stale HAWS links.'
    git_fixture -C "${FIXTURE_PROJECT}" add skills/custom/repair-me/SKILL.md || return 1
    git_fixture -C "${FIXTURE_PROJECT}" commit -qm 'add repair skill' || return 1
    git_fixture -C "${FIXTURE_PROJECT}" worktree add -q --detach "${stale_project}" HEAD || return 1
    mkdir -p "${stale_project}/skills/custom/repair-me" || return 1
    write_sync_settings
    printf 'skill:repair-me\n' > "${FIXTURE_HOME}/.haws_manifest"
    printf 'schema=1\tcompleted_at=previous-install\n' \
        > "${FIXTURE_PROJECT}/.haws/state/install.complete" || return 1

    create_test_directory_link \
        "${stale_project}/skills/custom/repair-me" \
        "${FIXTURE_HOME}/.claude/skills/repair-me" || return 1
    rm -rf -- "${stale_project}/skills/custom/repair-me"

    source_haws || return 1
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1

    [ "${FIXTURE_HOME}/.claude/skills/repair-me" -ef \
        "${FIXTURE_PROJECT}/skills/custom/repair-me" ] || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    assert_output_contains '[REPAIRED] Removed stale skill link' || return 1
}

test_run_sync_rebinds_unowned_haws_workspace_skill_link() {
    local old_project="${FIXTURE_ROOT}/old-worktree"
    init_superproject || return 1
    mkdir -p "${FIXTURE_PROJECT}/skills/custom/workspace-skill" \
        "${FIXTURE_HOME}/.claude/skills"
    write_catalog_skill 'skills/custom/workspace-skill/SKILL.md' \
        'workspace-skill' 'Current HAWS workspace source.'
    git_fixture -C "${FIXTURE_PROJECT}" add skills/custom/workspace-skill/SKILL.md || return 1
    git_fixture -C "${FIXTURE_PROJECT}" commit -qm 'add workspace skill' || return 1
    git_fixture -C "${FIXTURE_PROJECT}" worktree add -q --detach "${old_project}" HEAD || return 1
    printf '%s\n' '---' 'name: workspace-skill' \
        'description: Old HAWS workspace source.' '---' \
        > "${old_project}/skills/custom/workspace-skill/SKILL.md"
    write_sync_settings
    printf 'skill:workspace-skill\n' > "${FIXTURE_HOME}/.haws_manifest"
    printf 'schema=1\tcompleted_at=previous-install\n' \
        > "${FIXTURE_PROJECT}/.haws/state/install.complete" || return 1

    create_test_directory_link \
        "${old_project}/skills/custom/workspace-skill" \
        "${FIXTURE_HOME}/.claude/skills/workspace-skill" || return 1

    source_haws || return 1
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1
    [ "${FIXTURE_HOME}/.claude/skills/workspace-skill" -ef \
        "${FIXTURE_PROJECT}/skills/custom/workspace-skill" ] || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
}

test_run_sync_preserves_unowned_link_to_unregistered_repo_path() {
    init_superproject || return 1
    mkdir -p "${FIXTURE_PROJECT}/skills/custom/workspace-skill" \
        "${FIXTURE_PROJECT}/scratch/foreign-skill" \
        "${FIXTURE_HOME}/.claude/skills"
    write_catalog_skill 'skills/custom/workspace-skill/SKILL.md' \
        'workspace-skill' 'Current HAWS workspace source.'
    printf '%s\n' 'foreign user skill' \
        > "${FIXTURE_PROJECT}/scratch/foreign-skill/SKILL.md"
    git_fixture -C "${FIXTURE_PROJECT}" add \
        skills/custom/workspace-skill/SKILL.md scratch/foreign-skill/SKILL.md || return 1
    git_fixture -C "${FIXTURE_PROJECT}" commit -qm 'add foreign skill fixture' || return 1
    write_sync_settings
    create_test_directory_link \
        "${FIXTURE_PROJECT}/scratch/foreign-skill" \
        "${FIXTURE_HOME}/.claude/skills/workspace-skill" || return 1

    source_haws || return 1
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1
    [ "${FIXTURE_HOME}/.claude/skills/workspace-skill" -ef \
        "${FIXTURE_PROJECT}/scratch/foreign-skill" ] || return 1
    assert_file_contains "${FIXTURE_HOME}/.claude/skills/workspace-skill/SKILL.md" \
        'foreign user skill'
}

run_worktree_switch_rebind_case() {
    local legacy_mode="${1:-0}"
    local old_project="${FIXTURE_ROOT}/old-project"
    local new_project="${FIXTURE_ROOT}/new-project"
    prepare_worktree_skill_checkout "${old_project}" old || return 1
    prepare_worktree_skill_checkout "${new_project}" new || return 1
    mkdir -p "${FIXTURE_HOME}/.claude"

    FIXTURE_PROJECT="${old_project}"
    source_haws || return 1
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1
    local link="${FIXTURE_HOME}/.claude/skills/worktree-skill"
    local old_target new_target
    old_target="$(canonical_path "${link}")"
    [ "${old_target}" = "$(canonical_path "${old_project}/skills/custom/worktree-skill")" ] || return 1
    [ -f "${FIXTURE_HOME}/.haws/skills-ownership.tsv" ] || return 1
    awk -F '\t' -v wanted="${link}" \
        '$1 == "skills" && $3 == wanted { found = 1 } END { exit found ? 0 : 1 }' \
        "${FIXTURE_HOME}/.haws/skills-ownership.tsv" || return 1
    if [ "${legacy_mode}" = 1 ]; then
        cp "${FIXTURE_HOME}/.haws/skills-ownership.tsv" \
            "${old_project}/.haws/state/ownership.tsv" || return 1
        rm -f -- "${FIXTURE_HOME}/.haws/skills-ownership.tsv"
    else
        if [ -f "${old_project}/.haws/state/ownership.tsv" ] &&
            awk -F '\t' '$1 == "skills" { found = 1 } END { exit found ? 0 : 1 }' \
                "${old_project}/.haws/state/ownership.tsv"; then
            return 1
        fi
    fi

    FIXTURE_PROJECT="${new_project}"
    unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE
    source_haws || return 1
    _haws_ownership_skills_invalidate
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1
    new_target="$(canonical_path "${link}")"
    [ "${new_target}" = "$(canonical_path "${new_project}/skills/custom/worktree-skill")" ] || {
        cat "${OUTPUT_FILE}" >&2
        printf 'old target: %s\nnew target: %s\n' "${old_target}" "${new_target}" >&2
        return 1
    }
    [ "${old_target}" != "${new_target}" ]
}

test_run_sync_rebinds_owned_skill_link_after_worktree_switch() {
    run_worktree_switch_rebind_case 0
}

test_run_sync_rebinds_owned_skill_link_after_skill_directory_move() {
    local old_skill_dir="${FIXTURE_PROJECT}/skills/custom/in-progress/moved-skill"
    local new_skill_dir="${FIXTURE_PROJECT}/skills/custom/engineering/moved-skill"
    init_superproject || return 1
    write_catalog_skill 'skills/custom/in-progress/moved-skill/SKILL.md' \
        'moved-skill' 'Skill moved to a new directory.'
    mkdir -p "${FIXTURE_HOME}/.agents" || return 1
    write_sync_settings

    source_haws || return 1
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1

    local link="${FIXTURE_HOME}/.agents/skills/moved-skill"
    [ "${link}" -ef "${old_skill_dir}" ] || return 1
    awk -F '\t' -v wanted="${link}" \
        '$1 == "skills" && $3 == wanted { found = 1 } END { exit found ? 0 : 1 }' \
        "${FIXTURE_HOME}/.haws/skills-ownership.tsv" || return 1

    mkdir -p "${new_skill_dir}" || return 1
    mv "${old_skill_dir}/SKILL.md" "${new_skill_dir}/SKILL.md" || return 1
    rmdir "${old_skill_dir}" \
        "${FIXTURE_PROJECT}/skills/custom/in-progress" || return 1
    unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE
    source_haws || return 1
    _haws_ownership_skills_invalidate
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1

    [ "${link}" -ef "${new_skill_dir}" ] || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    assert_file_contains "${link}/SKILL.md" 'Skill moved to a new directory.' || return 1
    awk -F '\t' -v wanted="${link}" -v source="${new_skill_dir}" \
        '$1 == "skills" && $3 == wanted && $4 == source { found = 1 } END { exit found ? 0 : 1 }' \
        "${FIXTURE_HOME}/.haws/skills-ownership.tsv"
}

test_run_sync_migrates_unversioned_owned_link_after_skill_directory_move() {
    local old_skill_dir="${FIXTURE_PROJECT}/skills/custom/in-progress/moved-skill"
    local new_skill_dir="${FIXTURE_PROJECT}/skills/custom/engineering/moved-skill"
    init_superproject || return 1
    write_catalog_skill 'skills/custom/in-progress/moved-skill/SKILL.md' \
        'moved-skill' 'Skill moved to a new directory.'
    mkdir -p "${FIXTURE_HOME}/.agents" || return 1
    write_sync_settings

    source_haws || return 1
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1

    local link="${FIXTURE_HOME}/.agents/skills/moved-skill"
    local ownership_file="${FIXTURE_HOME}/.haws/skills-ownership.tsv"
    local staged_ownership="${ownership_file}.test"
    [ "${link}" -ef "${old_skill_dir}" ] || return 1
    awk -F '\t' -v OFS='\t' -v wanted="${link}" '
        $1 == "skills" && $3 == wanted {
            print $1, $2, $3, $4, $5
            found = 1
            next
        }
        { print }
        END { if (!found) exit 1 }
    ' "${ownership_file}" > "${staged_ownership}" || return 1
    mv "${staged_ownership}" "${ownership_file}" || return 1
    _haws_ownership_skills_invalidate
    local legacy_record
    legacy_record="$(_haws_skill_link_legacy_owned_record "${link}" 2>/dev/null || true)"
    [ -n "${legacy_record}" ] || {
        printf 'legacy ownership lookup failed for %s\n' "${link}" >&2
        cat "${ownership_file}" >&2
        return 1
    }

    mkdir -p "${new_skill_dir}" || return 1
    mv "${old_skill_dir}/SKILL.md" "${new_skill_dir}/SKILL.md" || return 1
    rmdir "${old_skill_dir}" \
        "${FIXTURE_PROJECT}/skills/custom/in-progress" || return 1
    unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE
    source_haws || return 1
    _haws_ownership_skills_invalidate
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1

    [ "${link}" -ef "${new_skill_dir}" ] || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    assert_file_contains "${link}/SKILL.md" 'Skill moved to a new directory.' || return 1
    awk -F '\t' -v wanted="${link}" -v source="${new_skill_dir}" \
        '$1 == "skills" && $3 == wanted && $4 == source && $6 == "schema=2" { found = 1 } END { exit found ? 0 : 1 }' \
        "${ownership_file}"
}

test_run_sync_rebinds_legacy_owned_skill_link_after_worktree_switch() {
    run_worktree_switch_rebind_case 1
}

test_run_sync_preserves_modified_owned_skill_link_after_worktree_switch() {
    local old_project="${FIXTURE_ROOT}/old-project"
    local new_project="${FIXTURE_ROOT}/new-project"
    local foreign="${FIXTURE_ROOT}/foreign-skill"
    prepare_worktree_skill_checkout "${old_project}" old || return 1
    prepare_worktree_skill_checkout "${new_project}" new || return 1
    mkdir -p "${FIXTURE_HOME}/.claude" "${foreign}"
    printf '%s\n' foreign > "${foreign}/SKILL.md"

    FIXTURE_PROJECT="${old_project}"
    source_haws || return 1
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1
    local link="${FIXTURE_HOME}/.claude/skills/worktree-skill"
    rm -f -- "${link}" 2>/dev/null || true
    if [ -e "${link}" ] || [ -L "${link}" ]; then
        _uninstall_remove_path junction "${link}" || return 1
    fi
    if ! ln -s "${foreign}" "${link}" 2>/dev/null; then
        mkdir -p "${link}" || return 1
        cp -f "${foreign}/SKILL.md" "${link}/SKILL.md" || return 1
    fi

    FIXTURE_PROJECT="${new_project}"
    unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE
    source_haws || return 1
    _haws_ownership_skills_invalidate
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_file_contains "${link}/SKILL.md" foreign
}

test_run_sync_preserves_modified_unversioned_owned_skill_link() {
    local foreign="${FIXTURE_ROOT}/foreign-skill"
    init_superproject || return 1
    write_catalog_skill 'skills/custom/owned-skill/SKILL.md' \
        'owned-skill' 'Legacy ownership safety fixture.'
    mkdir -p "${FIXTURE_HOME}/.agents" "${foreign}" || return 1
    printf '%s\n' 'foreign user skill' > "${foreign}/SKILL.md"
    write_sync_settings

    source_haws || return 1
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1

    local link="${FIXTURE_HOME}/.agents/skills/owned-skill"
    local ownership_file="${FIXTURE_HOME}/.haws/skills-ownership.tsv"
    local staged_ownership="${ownership_file}.test"
    awk -F '\t' -v OFS='\t' -v wanted="${link}" '
        $1 == "skills" && $3 == wanted {
            print $1, $2, $3, $4, $5
            found = 1
            next
        }
        { print }
        END { if (!found) exit 1 }
    ' "${ownership_file}" > "${staged_ownership}" || return 1
    mv "${staged_ownership}" "${ownership_file}" || return 1
    rm -f -- "${link}" || return 1
    create_test_directory_link "${foreign}" "${link}" || return 1

    unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE
    source_haws || return 1
    _haws_ownership_skills_invalidate
    run_codex_agents() { return 0; }
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1

    [ "${link}" -ef "${foreign}" ] || return 1
    assert_file_contains "${link}/SKILL.md" 'foreign user skill' || return 1
    awk -F '\t' -v wanted="${link}" \
        '$1 == "skills" && $3 == wanted && NF == 5 { found = 1 } END { exit found ? 0 : 1 }' \
        "${ownership_file}"
}

test_skill_draft_persists_source_identity_only_on_final_apply() {
    init_superproject || return 1
    make_remote persist-skill single || return 1
    git_fixture -C "${FIXTURE_PROJECT}" submodule add -q "${REMOTE_URL}" \
        skills/packs/persist-skill || return 1
    source_haws || return 1
    enable_local_sources
    settings_draft_load || return 1
    _settings_ensure_skill_draft || return 1
    local skill_id
    skill_id="$(catalog_skills | awk -F '\t' \
        '$1 == "skills/packs/persist-skill::skills/packs/persist-skill" {print $2; exit}')"
    [ -n "${skill_id}" ] || return 1
    HAWS_DRAFT_SKILLS=""
    HAWS_DRAFT_SKILLS_LOADED=1
    HAWS_PERSIST_SKILLS="${skill_id}"
    export HAWS_DRAFT_SKILLS HAWS_DRAFT_SKILLS_LOADED HAWS_PERSIST_SKILLS
    settings_plan_build || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/skills.disabled" || return 1
    settings_apply_final >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/skills.disabled" "${skill_id}" || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain -- skills/skills.disabled)" ] || return 1
    catalog_skills | awk -F '\t' -v wanted="${skill_id}" \
        '$2 == wanted && $6 == 0 {found=1} END {exit found ? 0 : 1}'
}

test_legacy_tracked_skill_state_migrates_to_device_state() {
    init_superproject || return 1
    mkdir -p "${FIXTURE_PROJECT}/skills"
    printf '%s\n' \
        '# HAWS Disabled Skills (source-aware)' \
        'demo-one' > "${FIXTURE_PROJECT}/skills/skills.disabled"
    printf '%s\n' '/.haws/state/' > "${FIXTURE_PROJECT}/.gitignore"
    git_fixture -C "${FIXTURE_PROJECT}" add .gitignore haws.sh \
        skills/skills.disabled skills/custom/demo-one/SKILL.md \
        skills/packs/demo-pack || return 1
    git_fixture -C "${FIXTURE_PROJECT}" commit -qm baseline || return 1

    printf '%s\n' '# HAWS Disabled Skills (source-aware)' \
        > "${FIXTURE_PROJECT}/skills/skills.disabled"
    source_haws || return 1
    state_init || return 1

    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/skills.disabled" \
        '# HAWS Disabled Skills (source-aware)' || return 1
    ! grep -F 'demo-one' "${FIXTURE_PROJECT}/.haws/state/skills.disabled" \
        >/dev/null 2>&1 || return 1
    [ -z "$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain -- skills/skills.disabled)" ] || return 1
    [ "$(catalog_skills | awk -F '\t' '$3 == "demo-one" {print $6; exit}')" = 1 ] || return 1
    _sync_root_preflight || return 1
}

test_repository_back_and_discard_do_not_mutate_git_files() {
    prepare_registered_source || return 1
    local before_modules before_status
    before_modules="$(sha256sum "${FIXTURE_PROJECT}/.gitmodules" | awk '{print $1}')"
    before_status="$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain)"
    source_haws || return 1
    settings_draft_load || return 1
    if settings_repositories_page <<< $'\nhttps://github.com/acme/not-applied.git\nq' >"${OUTPUT_FILE}" 2>&1; then
        :
    fi
    [ -n "${HAWS_DRAFT_ADDED_REPOSITORIES:-}" ] || return 1
    settings_draft_discard
    [ "${before_modules}" = "$(sha256sum "${FIXTURE_PROJECT}/.gitmodules" | awk '{print $1}')" ] || return 1
    [ "${before_status}" = "$(git_fixture -C "${FIXTURE_PROJECT}" status --porcelain)" ]
}

prepare_settings_skill_presentation_catalog() {
    init_superproject || return 1
    rm -rf -- "${FIXTURE_PROJECT}/skills/custom/demo-one"
    {
        printf '[submodule "source-one"]\n'
        printf '\tpath = skills/packs/source-one\n'
        printf '\turl = https://github.com/acme/source-one.git\n'
        printf '[submodule "source-two"]\n'
        printf '\tpath = skills/standalone/source-two\n'
        printf '\turl = https://github.com/acme/source-two.git\n'
    } > "${FIXTURE_PROJECT}/.gitmodules"

    write_catalog_skill \
        'skills/packs/source-one/pack-alpha/SKILL.md' \
        'Pack Alpha' 'Canonical pack alpha description.'
    write_catalog_skill \
        'skills/packs/source-one/pack-beta/SKILL.md' \
        'Pack Beta' 'Canonical pack beta description.'
    write_catalog_skill \
        'skills/packs/source-one/.openclaw/pack-beta/SKILL.md' \
        'Pack Beta' 'Filtered adapter description.'
    write_catalog_skill \
        'skills/packs/source-one/caveman/plugins/pack-beta/SKILL.md' \
        'Pack Beta' 'Filtered vendor description.'
    write_catalog_skill \
        'skills/standalone/source-two/standalone/SKILL.md' \
        'Standalone Skill' 'Canonical standalone description.'
    write_catalog_skill \
        'skills/custom/catalog-custom/SKILL.md' \
        'Catalog Custom' 'Canonical custom description.'

    mkdir -p "${FIXTURE_PROJECT}/skills"
    printf '%s\n' \
        'source-one::skills/packs/source-one::Pack Beta' \
        > "${FIXTURE_PROJECT}/skills/skills.disabled"
}

test_settings_skills_presents_logical_groups_and_keeps_state_draft_only() {
    prepare_settings_skill_presentation_catalog || return 1
    enable_local_sources
    source_haws || return 1
    settings_draft_load || return 1
    local disabled_before
    disabled_before="$(sha256sum "${FIXTURE_PROJECT}/skills/skills.disabled" | awk '{print $1}')"

    if settings_skills_page <<< $'\nqj\nqjj\n\nqqq' >"${OUTPUT_FILE}" 2>&1; then
        :
    fi
    assert_output_contains 'Canonical standalone description.' || return 1
    assert_output_contains 'Canonical custom description.' || return 1
    assert_output_contains 'Canonical pack alpha description.' || return 1
    grep -E 'source-one[[:space:]]+\[Active:[[:space:]]+1 /[[:space:]]+2 skills\]' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    assert_output_contains 'Single Skills' || return 1
    assert_output_not_contains 'Configure skills in this pack' || return 1
    assert_output_not_contains 'Filtered adapter description.' || return 1
    assert_output_not_contains 'Filtered vendor description.' || return 1
    assert_output_not_contains 'Status: [Active: 2 / 2 skills]' || return 1
    [ "${disabled_before}" = "$(sha256sum "${FIXTURE_PROJECT}/skills/skills.disabled" | awk '{print $1}')" ] || return 1
}

test_settings_skills_uses_one_page_frame() {
    init_superproject || return 1
    source_haws || return 1
    settings_draft_load || return 1
    if settings_skills_page <<< 'q' >"${OUTPUT_FILE}" 2>&1; then
        :
    fi
    [ "$(grep -Fc 'Configure Active Skills (Enable / Disable)' "${OUTPUT_FILE}")" -eq 1 ] || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/skills/skills.disabled"
}

test_settings_skills_preserves_old_single_and_pack_organization() {
    rm -rf -- "${FIXTURE_PROJECT}/skills/custom"
    init_superproject || return 1
    {
        printf '[submodule "single"]\n'
        printf '\tpath = skills/standalone/single\n'
        printf '\turl = https://github.com/acme/single.git\n'
        printf '[submodule "pack"]\n'
        printf '\tpath = skills/packs/pack\n'
        printf '\turl = https://github.com/acme/pack.git\n'
    } > "${FIXTURE_PROJECT}/.gitmodules"
    mkdir -p "${FIXTURE_PROJECT}/skills/standalone/single" \
        "${FIXTURE_PROJECT}/skills/packs/pack/alpha" \
        "${FIXTURE_PROJECT}/skills/packs/pack/beta"
    printf 'name: one\n' > "${FIXTURE_PROJECT}/skills/standalone/single/SKILL.md"
    printf 'name: alpha\n' > "${FIXTURE_PROJECT}/skills/packs/pack/alpha/SKILL.md"
    printf 'name: beta\n' > "${FIXTURE_PROJECT}/skills/packs/pack/beta/SKILL.md"
    source_haws || return 1
    settings_draft_load || return 1
    if settings_skills_page <<< $'jj\n\nqq' >"${OUTPUT_FILE}" 2>&1; then
        :
    fi
    assert_output_contains 'Configure Active Skills' || return 1
    assert_output_contains 'Single Skills' || return 1
    assert_output_contains 'Multi-Skill Packs' || return 1
    assert_output_contains 'Active:   2 /   2 skills' || return 1
    local single_count_column pack_count_column submenu_pack_count_column
    single_count_column="$(awk '/Single Skills[[:space:]]+\[Active:/ { print index($0, "[Active:"); exit }' "${OUTPUT_FILE}")"
    pack_count_column="$(awk '/Multi-Skill Packs[[:space:]]+\[Active:/ { print index($0, "[Active:"); exit }' "${OUTPUT_FILE}")"
    [ -n "${single_count_column}" ] || return 1
    [ -n "${pack_count_column}" ] || return 1
    [ "${single_count_column}" -eq "${pack_count_column}" ] || return 1
    submenu_pack_count_column="$(awk '/pack[[:space:]]+\[Active:/ { print index($0, "[Active:"); exit }' "${OUTPUT_FILE}")"
    [ -n "${submenu_pack_count_column}" ] || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/skills.disabled"
}

run_test() {
    local test_name="$1"
    create_fixture
    if "${test_name}"; then
        echo "PASS ${test_name}"
        passed=$((passed + 1))
    else
        echo "FAIL ${test_name}"
        failed=$((failed + 1))
    fi
    cleanup_fixture
}

trap cleanup_fixture EXIT

if [ -n "${HAWS_REPOSITORY_TEST_ONLY:-}" ]; then
    run_test "${HAWS_REPOSITORY_TEST_ONLY}"
    echo "CLI Batch 4 repository/skill tests: ${passed} passed, ${failed} failed"
    [ "${failed}" -eq 0 ]
    exit
fi

run_test test_catalog_resolves_source_scoped_logical_skills
run_test test_catalog_respects_repository_folder_taxonomy
run_test test_catalog_keeps_only_historical_canonical_skill_copies
run_test test_kit_migrate_converts_exact_pending_addition
run_test test_kit_migrate_reuses_clean_device_mirror
run_test test_kit_migrate_refuses_unrelated_root_changes
run_test test_kit_migrate_refuses_unrelated_gitmodules_addition
run_test test_kit_migrate_preserves_ignored_submodule_files
run_test test_add_only_apply_creates_device_local_source
run_test test_kit_add_registers_device_source_and_links_skill
run_test test_kit_add_survives_remote_skill_update
run_test test_local_skill_survives_haws_remote_update
run_test test_kit_update_refreshes_device_local_source_when_auto_update_is_off
run_test test_doctor_cache_refreshes_after_device_source_changes
run_test test_kit_list_includes_device_local_sources
run_test test_kit_prune_removes_device_source_and_owned_link
run_test test_kit_prune_blocks_dirty_device_source
run_test test_kit_prune_preserves_ignored_device_source_files
run_test test_kit_prune_refuses_replaced_device_source
run_test test_tracked_kit_add_requires_explicit_flag
run_test test_kit_update_reports_tracked_submodule_failure
run_test test_settings_remove_only_apply_removes_device_local_source
run_test test_remove_only_apply_removes_registered_source_and_keeps_unrelated_file
run_test test_reopened_removal_selector_excludes_sources_already_removed_in_draft
run_test test_dirty_source_removal_is_blocked_before_disk_removal
run_test test_run_sync_honors_source_aware_disabled_skill_without_legacy_scanner
run_test test_direct_skills_route_uses_the_settings_catalog
run_test test_run_sync_keeps_each_source_qualified_skill_in_state
run_test test_run_sync_does_not_create_codex_link_for_plugin_owned_ponytail
run_test test_run_sync_preserves_unowned_codex_skill_link
run_test test_run_sync_repairs_dangling_manifest_skill_link
run_test test_run_sync_rebinds_unowned_haws_workspace_skill_link
run_test test_run_sync_preserves_unowned_link_to_unregistered_repo_path
run_test test_run_sync_rebinds_owned_skill_link_after_worktree_switch
run_test test_run_sync_rebinds_owned_skill_link_after_skill_directory_move
run_test test_run_sync_migrates_unversioned_owned_link_after_skill_directory_move
run_test test_run_sync_rebinds_legacy_owned_skill_link_after_worktree_switch
run_test test_run_sync_preserves_modified_owned_skill_link_after_worktree_switch
run_test test_run_sync_preserves_modified_unversioned_owned_skill_link
run_test test_skill_draft_persists_source_identity_only_on_final_apply
run_test test_legacy_tracked_skill_state_migrates_to_device_state
run_test test_repository_back_and_discard_do_not_mutate_git_files
run_test test_settings_skills_presents_logical_groups_and_keeps_state_draft_only
run_test test_settings_skills_uses_one_page_frame
run_test test_settings_skills_preserves_old_single_and_pack_organization

echo "CLI Batch 4 repository/skill tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
