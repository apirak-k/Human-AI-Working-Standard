#!/usr/bin/env bash
set -euo pipefail

TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_REPO_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
ORIGINAL_TMPDIR="${TMPDIR:-/tmp}"
TEST_ROOT=""
PASS_COUNT=0

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    [ "${expected}" = "${actual}" ] ||
        fail "${label}: expected '${expected}', got '${actual}'"
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '[PASS] %s\n' "${label}"
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    [[ "${haystack}" == *"${needle}"* ]] || fail "${label}: missing '${needle}'"
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '[PASS] %s\n' "${label}"
}

cleanup() {
    if [ -n "${TEST_ROOT}" ] && [[ "${TEST_ROOT}" == "${ORIGINAL_TMPDIR%/}"/haws-catalog-test.* ]]; then
        rm -rf -- "${TEST_ROOT}"
    fi
}
trap cleanup EXIT

new_fixture() {
    if [ -n "${TEST_ROOT}" ]; then
        cleanup
    fi
    TRACE_GIT=""
    TEST_ROOT="$(mktemp -d "${ORIGINAL_TMPDIR%/}/haws-catalog-test.XXXXXX")"
    export HOME="${TEST_ROOT}/home"
    export TMPDIR="${TEST_ROOT}/tmp"
    export HAWS_STATE_DIR="${TEST_ROOT}/state"
    export HAWS_REPO_DIR="${TEST_ROOT}/repo"
    export HAWS_TEST_ALLOW_LOCAL_SOURCES=1
    export GIT_CONFIG_GLOBAL="${TEST_ROOT}/gitconfig"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_TERMINAL_PROMPT=0
    mkdir -p "${HOME}" "${TMPDIR}" "${HAWS_STATE_DIR}/skill-sources" "${HAWS_REPO_DIR}"
    cat > "${GIT_CONFIG_GLOBAL}" <<'EOF'
[user]
	name = HAWS Test
	email = haws-test@example.invalid
EOF
    git init -q -b main "${HAWS_REPO_DIR}"
    printf '# Test-only submodule registry\n' > "${HAWS_REPO_DIR}/.gitmodules"
    git -C "${HAWS_REPO_DIR}" add .gitmodules
    git -C "${HAWS_REPO_DIR}" commit -q -m 'test fixture root'

    mkdir -p "${TEST_ROOT}/traces"
    TRACE_CATALOG="${TEST_ROOT}/traces/catalog.tsv"
    TRACE_FIND="${TEST_ROOT}/traces/find.txt"
    TRACE_SOURCE_BUILDS="${TEST_ROOT}/traces/source-builds.txt"
    TRACE_RUNTIME_DIR="${TEST_ROOT}/traces/runtime-dirs.txt"
    TRACE_DISABLED_LOADS="${TEST_ROOT}/traces/disabled-loads.txt"
    TRACE_SOURCE_SNAPSHOTS="${TEST_ROOT}/traces/source-snapshots.txt"
    TRACE_HEALTH_COLLECTS="${TEST_ROOT}/traces/health-collects.txt"
    TRACE_HEALTH_FINGERPRINTS="${TEST_ROOT}/traces/health-fingerprints.txt"
    TRACE_HEALTH_CLEAN_CHECKS="${TEST_ROOT}/traces/health-clean-checks.txt"
    TRACE_GIT="${TEST_ROOT}/traces/git.txt"
    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    : > "${TRACE_SOURCE_BUILDS}"
    : > "${TRACE_RUNTIME_DIR}"
    : > "${TRACE_DISABLED_LOADS}"
    : > "${TRACE_SOURCE_SNAPSHOTS}"
    : > "${TRACE_HEALTH_COLLECTS}"
    : > "${TRACE_HEALTH_FINGERPRINTS}"
    : > "${TRACE_HEALTH_CLEAN_CHECKS}"
    : > "${TRACE_GIT}"

    unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE \
        HAWS_CATALOG_SOURCE_CONFIG_FP HAWS_CATALOG_SKILL_STATE_FP \
        HAWS_CATALOG_SKILLS_DIRTY
    unset HAWS_HEALTH_CACHE_FP HAWS_HEALTH_CACHE_FINDINGS
    unset HAWS_HEALTH_CACHE_ACTIVE HAWS_HEALTH_CACHE_TOTAL
    HAWS_CATALOG_SOURCE_KIND_CACHE=()
    HAWS_CATALOG_RUNTIME_SOURCE_DIR_CACHE=()
    HAWS_CATALOG_RUNTIME_SOURCE_REVISION_CACHE=()
    _catalog_clear_submodule_snapshot
    HAWS_HEALTH_FINDINGS=""
    HAWS_DRAFT_SKILLS_LOADED=0
    DISABLED_SKILLS=()
}

write_skill() {
    local source_dir="$1" relative_dir="$2" display_name="$3" description="$4"
    mkdir -p "${source_dir}/${relative_dir}"
    cat > "${source_dir}/${relative_dir}/SKILL.md" <<EOF
---
name: ${display_name}
description: ${description}
---
# ${display_name}
Fixture skill entrypoint.
EOF
}

commit_source() {
    local source_dir="$1" message="${2:-fixture source}"
    git -C "${source_dir}" add -A
    git -C "${source_dir}" commit -q -m "${message}"
}

register_source() {
    local name="$1" source_path="$2" source_dir url
    source_dir="${HAWS_STATE_DIR}/skill-sources/${source_path}"
    mkdir -p "$(dirname "${source_dir}")"
    git init -q -b main "${source_dir}"
    git -C "${source_dir}" config user.name 'HAWS Test'
    git -C "${source_dir}" config user.email 'haws-test@example.invalid'
    git -C "${source_dir}" commit --allow-empty -q -m 'initial fixture source'
    url="file://${source_dir}"
    printf '%s\t%s\t%s\n' "${name}" "${source_path}" "${url}" \
        >> "$(_catalog_device_source_registry)"
    printf '%s\n' "${source_dir}"
}

register_local_source() {
    local name="$1" source_path="$2" source_dir="${HAWS_STATE_DIR}/skill-sources/${2}"
    mkdir -p "${source_dir}"
    git init -q -b main "${source_dir}"
    git -C "${source_dir}" config user.name 'HAWS Test'
    git -C "${source_dir}" config user.email 'haws-test@example.invalid'
    printf '%s\t%s\tfile://%s\n' "${name}" "${source_path}" "${source_dir}" \
        >> "$(_catalog_device_source_registry)"
    printf '%s\n' "${source_dir}"
}

source_id() {
    _catalog_device_source_id "$1" "$2"
}

git_trace_count() {
    awk -F '\t' -v kind="$1" '$1 == kind { count++ } END { print count + 0 }' "${TRACE_GIT}"
}

catalog_call_count() {
    awk 'END { print NR + 0 }' "${TRACE_CATALOG}"
}

filtered_catalog_call_count() {
    awk -F '\t' 'NF >= 2 && $2 != "" { n++ } END { print n + 0 }' "${TRACE_CATALOG}"
}

find_call_count() {
    awk 'END { print NR + 0 }' "${TRACE_FIND}"
}

source_materialization_count() {
    awk 'END { print NR + 0 }' "${TRACE_SOURCE_BUILDS}"
}

source_count_in_rows() {
    local rows="$1" wanted="$2"
    printf '%s\n' "${rows}" | awk -F '\t' -v source="${wanted}" \
        '$1 == source { count++ } END { print count + 0 }'
}

# Load HAWS once, then wrap the filesystem seams with append-only traces. The
# wrappers preserve the production implementations and work through command
# substitutions used by the Settings and Health paths.
export HAWS_SOURCE_ONLY=1
source "${TEST_REPO_ROOT}/haws.sh"
git() {
    local joined="$*" kind=other
    if [[ "${joined}" == *"config --null --file"* && "${joined}" == *"--get-regexp"* ]]; then
        if [[ "${joined}" == *".path$"* ]]; then
            kind=submodule-path-config
        elif [[ "${joined}" == *".url$"* ]]; then
            kind=submodule-url-config
        fi
    elif [[ "${joined}" == *"ls-files --stage"* ]]; then
        kind=gitlink-index
    elif [[ "${joined}" == *"rev-parse --show-toplevel --verify HEAD"* ]]; then
        kind=source-root-head
    elif [[ "${joined}" == *" status --porcelain=v1"* ]]; then
        kind=source-status
    elif [[ "${joined}" == *" ls-files --others --ignored --exclude-standard"* ]]; then
        kind=ignored-entrypoint-check
    elif [[ "${joined}" == *"rev-parse HEAD"* ]]; then
        kind=source-revision
    elif [[ "${joined}" == *"rev-parse --verify HEAD"* ]]; then
        kind=source-revision
    elif [[ "${joined}" == *"rev-parse --is-inside-work-tree"* ]]; then
        kind=inside-work-tree
    fi
    printf '%s\t%s\n' "${kind}" "${joined}" >> "${TRACE_GIT:-/dev/null}"
    command git "$@"
}
eval "$(declare -f catalog_skills | sed '1s/^catalog_skills/_catalog_skills_original/')"
catalog_skills() {
    printf '%s\t%s\n' "${1:-effective}" "${2:-}" >> "${TRACE_CATALOG}"
    _catalog_skills_original "$@"
}
eval "$(declare -f catalog_sources | sed '1s/^catalog_sources/_catalog_sources_original/')"
catalog_sources() {
    if [ -z "${HAWS_CATALOG_SOURCES_CACHE+x}" ]; then
        printf 'materialize\n' >> "${TRACE_SOURCE_BUILDS}"
    fi
    _catalog_sources_original "$@"
}
find() {
    printf '%s\n' "$*" >> "${TRACE_FIND}"
    command find "$@"
}
eval "$(declare -f _catalog_runtime_source_dir | sed '1s/^_catalog_runtime_source_dir/_catalog_runtime_source_dir_original/')"
_catalog_runtime_source_dir() {
    printf '%s\n' "${1:-}" >> "${TRACE_RUNTIME_DIR}"
    _catalog_runtime_source_dir_original "$@"
}
if declare -F _catalog_load_disabled_skill_keys >/dev/null 2>&1; then
    eval "$(declare -f _catalog_load_disabled_skill_keys | sed '1s/^_catalog_load_disabled_skill_keys ()/_catalog_load_disabled_skill_keys_original ()/')"
fi
_catalog_load_disabled_skill_keys() {
    printf 'load\n' >> "${TRACE_DISABLED_LOADS}"
    _catalog_load_disabled_skill_keys_original "$@"
}
eval "$(declare -f _catalog_refresh_source_snapshot | sed '1s/^_catalog_refresh_source_snapshot/_catalog_refresh_source_snapshot_original/')"
_catalog_refresh_source_snapshot() {
    printf 'refresh\n' >> "${TRACE_SOURCE_SNAPSHOTS}"
    _catalog_refresh_source_snapshot_original "$@"
}
eval "$(declare -f _health_collect | sed '1s/^_health_collect/_health_collect_original/')"
_health_collect() {
    printf 'collect\n' >> "${TRACE_HEALTH_COLLECTS}"
    _health_collect_original "$@"
}
eval "$(declare -f _health_fingerprint | sed '1s/^_health_fingerprint/_health_fingerprint_original/')"
_health_fingerprint() {
    printf 'fingerprint\n' >> "${TRACE_HEALTH_FINGERPRINTS}"
    _health_fingerprint_original "$@"
}
eval "$(declare -f _health_skill_sources_clean | sed '1s/^_health_skill_sources_clean/_health_skill_sources_clean_original/')"
_health_skill_sources_clean() {
    printf 'clean\n' >> "${TRACE_HEALTH_CLEAN_CHECKS}"
    _health_skill_sources_clean_original "$@"
}

trace_line_count() {
    awk 'END { print NR + 0 }' "$1"
}

test_content_based_classification() {
    new_fixture
    local empty_dir single_pack_dir many_standalone_dir single_standalone_dir duplicate_dir ineligible_dir
    local empty_id single_pack_id many_id single_standalone_id duplicate_id ineligible_id
    empty_dir="$(register_local_source empty skills/packs/empty)"
    single_pack_dir="$(register_local_source single-pack skills/packs/single-pack)"
    write_skill "${single_pack_dir}" skills/tool 'Single Pack Skill' 'one eligible skill'
    commit_source "${single_pack_dir}"
    many_standalone_dir="$(register_local_source many skills/standalone/many)"
    write_skill "${many_standalone_dir}" skills/one 'First Skill' 'first eligible skill'
    write_skill "${many_standalone_dir}" skills/two 'Second Skill' 'second eligible skill'
    commit_source "${many_standalone_dir}"
    single_standalone_dir="$(register_local_source single-standalone skills/standalone/single-standalone)"
    write_skill "${single_standalone_dir}" skill 'Single Standalone Skill' 'one eligible skill'
    commit_source "${single_standalone_dir}"
    duplicate_dir="$(register_local_source duplicate skills/packs/duplicate)"
    write_skill "${duplicate_dir}" skills/a 'Repeated Display Name' 'duplicate first file'
    write_skill "${duplicate_dir}" skills/b 'Repeated Display Name' 'duplicate second file'
    commit_source "${duplicate_dir}"
    ineligible_dir="$(register_local_source ineligible skills/packs/ineligible)"
    write_skill "${ineligible_dir}" .openclaw 'Hidden Skill' 'ineligible fixture'
    commit_source "${ineligible_dir}"

    empty_id="$(source_id empty skills/packs/empty)"
    single_pack_id="$(source_id single-pack skills/packs/single-pack)"
    many_id="$(source_id many skills/standalone/many)"
    single_standalone_id="$(source_id single-standalone skills/standalone/single-standalone)"
    duplicate_id="$(source_id duplicate skills/packs/duplicate)"
    ineligible_id="$(source_id ineligible skills/packs/ineligible)"
    mkdir -p "${HAWS_STATE_DIR}"
    printf '%s\n%s\n' \
        "${single_pack_id}::Single Pack Skill" \
        "${many_id}::First Skill" > "$(_skills_disabled_state_file)"
    load_disabled_skills

    HAWS_CATALOG_SOURCES_CACHE="$(catalog_sources)"
    HAWS_CATALOG_SKILLS_CACHE="$(catalog_skills)"
    assert_eq 1 "$(awk 'END { print NR + 0 }' "${TRACE_DISABLED_LOADS}")" \
        'one catalog build loads disabled state once for all skill rows'
    : > "${TRACE_CATALOG}"
    local classification rows
    catalog_source_kind "${empty_id}" classification
    assert_eq UNVERIFIED "${classification}" 'zero eligible skills classify as UNVERIFIED'
    catalog_source_kind "${single_pack_id}" classification
    assert_eq SINGLE "${classification}" 'one skill under skills/packs classifies as SINGLE'
    catalog_source_kind "${many_id}" classification
    assert_eq PACK "${classification}" 'multiple skills under skills/standalone classify as PACK'
    catalog_source_kind "${single_standalone_id}" classification
    assert_eq SINGLE "${classification}" 'one skill under skills/standalone classifies as SINGLE'
    catalog_source_kind "${duplicate_id}" classification
    assert_eq SINGLE "${classification}" 'duplicate display names dedupe before source classification'
    catalog_source_kind "${ineligible_id}" classification
    assert_eq UNVERIFIED "${classification}" 'ineligible SKILL.md files do not classify a source'

    rows="${HAWS_CATALOG_SKILLS_CACHE}"
    assert_eq 0 "$(source_count_in_rows "${rows}" "${empty_id}")" 'empty source has no catalog rows'
    assert_eq 0 "$(source_count_in_rows "${rows}" "${ineligible_id}")" 'ineligible source has no catalog rows'
    assert_eq 1 "$(source_count_in_rows "${rows}" "${duplicate_id}")" 'duplicate display names produce one catalog row'
    assert_eq 0 "$(printf '%s\n' "${rows}" | awk -F '\t' -v id="${single_pack_id}::Single Pack Skill" '$2 == id && $6 == 1 {n++} END {print n+0}')" \
        'disabled state marks a single skill inactive'
    assert_eq 0 "$(printf '%s\n' "${rows}" | awk -F '\t' -v id="${many_id}::First Skill" '$2 == id && $6 == 1 {n++} END {print n+0}')" \
        'disabled state marks one pack member inactive'
    assert_eq 0 "$(catalog_call_count)" 'source classification reuses the already built complete snapshot'
}

test_source_snapshot_batches_gitlink_and_root_revision_checks() {
    new_fixture
    local i name path source_dir revision source_rows source_id
    for i in 1 2 3 4; do
        name="snapshot-${i}"
        path="skills/packs/${name}"
        source_dir="${HAWS_STATE_DIR}/skill-sources/${path}"
        mkdir -p "${source_dir}"
        if [ "${i}" -le 3 ]; then
            git init -q -b main "${source_dir}"
            printf 'name: Snapshot %s\n' "${i}" > "${source_dir}/SKILL.md"
            git -C "${source_dir}" add SKILL.md
            git -C "${source_dir}" commit -q -m "source ${i}"
            revision="$(git -C "${source_dir}" rev-parse HEAD)"
            git -C "${HAWS_REPO_DIR}" update-index --add --cacheinfo "160000,${revision},${path}"
        fi
        git -C "${HAWS_REPO_DIR}" config --file .gitmodules "submodule.${name}.path" "${path}"
        git -C "${HAWS_REPO_DIR}" config --file .gitmodules "submodule.${name}.url" "https://example.invalid/${name}.git"
    done

    unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SOURCE_CONFIG_FP
    HAWS_CATALOG_RUNTIME_SOURCE_DIR_CACHE=()
    : > "${TRACE_GIT}"
    source_rows="$(catalog_sources)"
    assert_eq 4 "$(printf '%s\n' "${source_rows}" | awk 'NF { count++ } END { print count + 0 }')" \
        'submodule snapshot retains every configured source row'
    assert_eq 1 "$(git_trace_count gitlink-index)" \
        'submodule index membership is validated with one batched Git query'
    assert_eq 1 "$(git_trace_count submodule-path-config)" \
        'submodule paths are read with one Git config query'
    assert_eq 1 "$(git_trace_count submodule-url-config)" \
        'submodule URLs are read with one Git config query'
    assert_eq 3 "$(git_trace_count source-root-head)" \
        'each checked out gitlink combines repository-root and HEAD validation'
    assert_eq 0 "$(git_trace_count inside-work-tree)" \
        'source resolution does not run a second inside-work-tree probe'
    source_id='snapshot-4::skills/packs/snapshot-4'
    assert_contains "${source_rows}" "${source_id}" \
        'a configured source absent from the current index remains represented safely'
    assert_contains "${source_rows}" "${source_id}"$'\t'"skills/packs/snapshot-4"$'\t'"https://example.invalid/snapshot-4.git"$'\t'uninitialized \
        'an unindexed source does not resolve to its device-local directory'
}

test_combined_skill_metadata_extraction_matches_existing_helpers() {
    new_fixture
    local metadata_dir="${TEST_ROOT}/metadata" file case_name old_name old_desc combined_name combined_desc
    local -a files=()
    mkdir -p "${metadata_dir}/quoted" "${metadata_dir}/multiline" \
        "${metadata_dir}/body-fallback" "${metadata_dir}/no-frontmatter" \
        "${metadata_dir}/one-delimiter" "${metadata_dir}/name-fallback"

    cat > "${metadata_dir}/quoted/SKILL.md" <<'EOF'
---
name: "Quoted Skill" # trailing comment
description: 'quoted description'
---
EOF
    cat > "${metadata_dir}/multiline/SKILL.md" <<'EOF'
---
name: Multiline Skill
description: >
  first multiline description
  second continuation
---
EOF
    cat > "${metadata_dir}/body-fallback/SKILL.md" <<'EOF'
---
name: Body Fallback Skill
category: test
---
# Heading
First body description.
EOF
    cat > "${metadata_dir}/no-frontmatter/SKILL.md" <<'EOF'
name: No Frontmatter Skill
# Heading
Body content.
EOF
    cat > "${metadata_dir}/one-delimiter/SKILL.md" <<'EOF'
---
name: One Delimiter Skill
No description field
EOF
    cat > "${metadata_dir}/name-fallback/SKILL.md" <<'EOF'
---
description: Description without an explicit name
---
EOF
    files=(
        "${metadata_dir}/quoted/SKILL.md"
        "${metadata_dir}/multiline/SKILL.md"
        "${metadata_dir}/body-fallback/SKILL.md"
        "${metadata_dir}/no-frontmatter/SKILL.md"
        "${metadata_dir}/one-delimiter/SKILL.md"
        "${metadata_dir}/name-fallback/SKILL.md"
    )
    for file in "${files[@]}"; do
        case_name="${file%/SKILL.md}"
        case_name="${case_name##*/}"
        old_name="$(extract_skill_name "${file}")"
        old_desc="$(extract_skill_desc "${file}")"
        _catalog_extract_skill_metadata "${file}" combined_name combined_desc
        assert_eq "${old_name}" "${combined_name}" \
            "single-pass metadata preserves name for ${case_name}"
        assert_eq "${old_desc}" "${combined_desc}" \
            "single-pass metadata preserves description for ${case_name}"
    done
}

test_settings_entry_does_not_run_catalog_or_health_work() {
    new_fixture
    local source_dir i
    for i in 1 2 3; do
        source_dir="$(register_local_source "settings-${i}" "skills/packs/settings-${i}")"
        write_skill "${source_dir}" skills/main "Settings ${i} Skill" "settings startup fixture ${i}"
        commit_source "${source_dir}"
    done

    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    : > "${TRACE_SOURCE_BUILDS}"
    : > "${TRACE_RUNTIME_DIR}"
    : > "${TRACE_SOURCE_SNAPSHOTS}"
    : > "${TRACE_HEALTH_COLLECTS}"
    : > "${TRACE_HEALTH_FINGERPRINTS}"
    : > "${TRACE_HEALTH_CLEAN_CHECKS}"
    : > "${TRACE_GIT}"
    settings_draft_load

    local menu_calls=0 flow_status=0
    interactive_menu() {
        case "${2:-}" in
            'HAWS Settings|'*) menu_calls=$((menu_calls + 1)); return 1 ;;
            *) return 1 ;;
        esac
    }
    if settings_flow_run settings > "${TEST_ROOT}/settings.out" 2>&1; then
        flow_status=0
    else
        flow_status=$?
    fi
    unset -f interactive_menu
    [ "${flow_status}" -le 1 ] || fail "Settings flow returned unexpected status ${flow_status}"

    assert_eq 1 "${menu_calls}" 'bare Settings opens the page once'
    assert_eq 0 "$(catalog_call_count)" 'bare Settings does not build the skill catalog'
    assert_eq 0 "$(find_call_count)" 'bare Settings does not scan skill directories'
    assert_eq 0 "$(source_materialization_count)" 'bare Settings does not enumerate repository sources'
    assert_eq 0 "$(trace_line_count "${TRACE_SOURCE_SNAPSHOTS}")" 'bare Settings does not refresh source snapshots'
    assert_eq 0 "$(trace_line_count "${TRACE_HEALTH_COLLECTS}")" 'bare Settings does not collect deep Health diagnostics'
    assert_eq 0 "$(trace_line_count "${TRACE_HEALTH_FINGERPRINTS}")" 'bare Settings does not fingerprint Health state'
    assert_eq 0 "$(trace_line_count "${TRACE_HEALTH_CLEAN_CHECKS}")" 'bare Settings does not inspect source cleanliness'
    assert_eq 0 "$(git_trace_count source-status)" 'bare Settings does not run per-source status checks'
    assert_eq 0 "$(git_trace_count ignored-entrypoint-check)" 'bare Settings does not inspect ignored skill entrypoints'
    assert_eq 0 "$(git_trace_count source-revision)" 'bare Settings does not probe source revisions'
    assert_eq 0 "$(trace_line_count "${TRACE_RUNTIME_DIR}")" 'bare Settings does not resolve runtime source directories'
}

test_settings_source_draft_rebases_external_adds_and_removals() {
    new_fixture
    local source_a source_b id_a id_b page_status=0
    source_a="$(register_source source-a skills/packs/source-a)"
    source_b="$(register_source source-b skills/packs/source-b)"
    id_a="$(source_id source-a skills/packs/source-a)"
    id_b="$(source_id source-b skills/packs/source-b)"

    settings_draft_load
    _settings_prepare_source_draft
    register_source source-c skills/packs/source-c >/dev/null

    interactive_menu() { return 1; }
    settings_page > "${TEST_ROOT}/settings.out" 2>&1 || page_status=$?
    [ "${page_status}" -le 1 ] || fail "Settings page returned unexpected status ${page_status}"
    unset -f interactive_menu
    settings_plan_build
    assert_eq 3 "$(printf '%s\n' "${HAWS_PERSIST_SOURCES}" | awk 'NF {n++} END {print n+0}')" \
        'fresh Apply state includes sources added after the draft was opened'
    assert_eq 3 "$(printf '%s\n' "${HAWS_DRAFT_SOURCES}" | awk 'NF {n++} END {print n+0}')" \
        'an untouched source draft adopts external source additions'
    assert_contains "${HAWS_DRAFT_SOURCES}" "${id_b}" \
        'external source additions remain enabled in the source draft'
    assert_eq 0 "$(grep -cF 'remove-source' "${HAWS_PLAN_FILE}" || true)" \
        'external source additions are not misplanned as removals'

    settings_draft_load
    _settings_prepare_source_draft
    settings_draft_remove_source "${id_a}"
    awk -F '\t' '$1 != "source-b" {print}' "$(_catalog_device_source_registry)" \
        > "${TEST_ROOT}/registry.next"
    mv -- "${TEST_ROOT}/registry.next" "$(_catalog_device_source_registry)"
    page_status=0
    interactive_menu() { return 1; }
    settings_page > "${TEST_ROOT}/settings.out" 2>&1 || page_status=$?
    [ "${page_status}" -le 1 ] || fail "Settings page returned unexpected status ${page_status}"
    unset -f interactive_menu
    settings_plan_build
    assert_eq 2 "$(printf '%s\n' "${HAWS_PERSIST_SOURCES}" | awk 'NF {n++} END {print n+0}')" \
        'fresh Apply state drops sources removed externally after the draft was opened'
    assert_eq 1 "$(printf '%s\n' "${HAWS_DRAFT_SOURCES}" | awk 'NF {n++} END {print n+0}')" \
        'explicit source removals remain applied when the draft is rebased'
    assert_contains "$(cat "${HAWS_PLAN_FILE}")" "remove-source" \
        'an explicit source removal remains in the Apply plan after rebase'
    assert_eq 1 "$(grep -cF 'remove-source' "${HAWS_PLAN_FILE}" || true)" \
        'externally removed sources do not create duplicate removal actions'
    assert_contains "${HAWS_PERSIST_SOURCES}" "${id_a}" \
        'the remaining registered source stays in the fresh baseline'
    if _settings_list_contains "${HAWS_PERSIST_SOURCES}" "${id_b}"; then
        fail 'an externally removed source remained in the fresh baseline'
    fi
    [ -n "${source_a}" ] && [ -n "${source_b}" ]
}

test_settings_builds_one_catalog_snapshot() {
    new_fixture
    local dirs=() ids=() i source_path source_dir support_file
    for i in 1 2 3 4 5; do
        source_path="skills/packs/source-${i}"
        source_dir="$(register_local_source "source-${i}" "${source_path}")"
        write_skill "${source_dir}" skills/main "Source ${i} Skill" "settings fixture ${i}"
        if [ "${i}" -eq 1 ]; then
            printf '__pycache__/\n' > "${source_dir}/.gitignore"
        fi
        commit_source "${source_dir}"
        if [ "${i}" -eq 1 ]; then
            support_file="${source_dir}/skills/main/scripts/office/__pycache__/module.pyc"
            mkdir -p "$(dirname "${support_file}")"
            printf 'ignored supporting content\n' > "${support_file}"
            git -C "${source_dir}" check-ignore -q skills/main/scripts/office/__pycache__/module.pyc || \
                fail 'Settings support-file fixture was not ignored by Git'
        fi
        ids+=("$(source_id "source-${i}" "${source_path}")")
    done

    settings_draft_load
    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    local settings_page_count=0 flow_status=0
    interactive_menu() {
        case "${2:-}" in
            'HAWS Settings|'*)
                settings_page_count=$((settings_page_count + 1))
                if [ "${settings_page_count}" -eq 1 ]; then
                    INTERACTIVE_MENU_SELECTION=1
                    return 0
                fi
                return 1
                ;;
            'Configure Active Skills (Enable / Disable)'*) return 1 ;;
            *) return 1 ;;
        esac
    }
    if settings_flow_run settings > "${TEST_ROOT}/settings.out" 2>&1; then
        flow_status=0
    else
        flow_status=$?
    fi
    unset -f interactive_menu
    [ "${flow_status}" -le 1 ] || fail "Settings flow returned unexpected status ${flow_status}"
    assert_eq 2 "${settings_page_count}" 'Settings flow visited Active Skills and returned to Settings'
    assert_eq 1 "$(catalog_call_count)" 'opening Active Skills builds one complete catalog snapshot'
    assert_eq 0 "$(filtered_catalog_call_count)" 'Settings classification performs no source-filtered catalog builds'
    assert_eq 5 "$(find_call_count)" 'one complete catalog build scans each registered source once'
    assert_eq 1 "$(source_materialization_count)" 'opening Active Skills materializes its source list once'
    local built_sources
    built_sources="$(awk -F '\t' 'NR == 1 {print $2}' "${TRACE_CATALOG}")"
    assert_eq '' "${built_sources}" 'Settings catalog build is not filtered to a single source'
}

test_active_skills_refreshes_source_changes_made_after_draft_load() {
    new_fixture
    local source_dir source_id current_revision classification page_status=0
    source_dir="$(register_source fresh-skills skills/packs/fresh-skills)"
    source_id="$(source_id fresh-skills skills/packs/fresh-skills)"
    write_skill "${source_dir}" skills/one 'First Fresh Skill' 'initial Settings catalog view'
    commit_source "${source_dir}" 'initial skill'

    settings_draft_load
    assert_eq 0 "${HAWS_DRAFT_SOURCES_LOADED}" 'Settings draft leaves source rows unloaded until a source view is needed'
    write_skill "${source_dir}" skills/two 'Second Fresh Skill' 'source changed after Settings draft load'
    commit_source "${source_dir}" 'add skill after Settings draft load'
    current_revision="$(git -C "${source_dir}" rev-parse HEAD)"

    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    : > "${TRACE_SOURCE_SNAPSHOTS}"
    : > "${TRACE_HEALTH_CLEAN_CHECKS}"
    : > "${TRACE_GIT}"
    interactive_menu() { return 1; }
    settings_skills_page > "${TEST_ROOT}/skills.out" 2>&1 || page_status=$?
    unset -f interactive_menu
    [ "${page_status}" -le 1 ] || fail "Active Skills returned unexpected status ${page_status}"

    assert_eq 1 "$(catalog_call_count)" 'Active Skills builds one fresh catalog after the source advances'
    assert_eq 1 "$(find_call_count)" 'fresh Active Skills scans the changed source once'
    assert_eq 2 "$(source_count_in_rows "${HAWS_CATALOG_SKILLS_CACHE}" "${source_id}")" \
        'fresh Active Skills includes the new upstream skill'
    catalog_source_kind "${source_id}" classification
    assert_eq PACK "${classification}" 'fresh Active Skills reclassifies the updated source as PACK'
    assert_eq "${current_revision}" "$(printf '%s\n' "${HAWS_CATALOG_SOURCES_CACHE}" | \
        awk -F '\t' -v id="${source_id}" '$1 == id {print $4}')" \
        'fresh Active Skills stores the current source revision'
    assert_eq 0 "$(trace_line_count "${TRACE_HEALTH_CLEAN_CHECKS}")" \
        'Active Skills does not run the Health cleanliness scan'
    assert_eq 0 "$(git_trace_count source-status)" \
        'Active Skills does not run per-source cleanliness checks'
    assert_eq 0 "$(git_trace_count ignored-entrypoint-check)" \
        'Active Skills does not check ignored entrypoints'

    : > "${TRACE_SOURCE_SNAPSHOTS}"
    : > "${TRACE_SOURCE_BUILDS}"
    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    : > "${TRACE_GIT}"
    page_status=0
    settings_skills_page > "${TEST_ROOT}/skills-warm.out" 2>&1 || page_status=$?
    [ "${page_status}" -le 1 ] || fail "warm Active Skills returned unexpected status ${page_status}"
    assert_eq 0 "$(trace_line_count "${TRACE_SOURCE_SNAPSHOTS}")" \
        'warm Active Skills reuses the current Settings draft source snapshot'
    assert_eq 0 "$(source_materialization_count)" \
        'warm Active Skills does not rematerialize an unchanged source list'
    assert_eq 0 "$(catalog_call_count)" 'warm Active Skills reuses its catalog snapshot'
    assert_eq 0 "$(find_call_count)" 'warm Active Skills does not rescan unchanged skill trees'
    assert_eq 0 "$(git_trace_count source-status)" 'warm Active Skills skips repeated cleanliness checks'
    assert_eq 0 "$(git_trace_count ignored-entrypoint-check)" \
        'warm Active Skills skips repeated ignored-entrypoint checks'
}

test_apply_plan_rebases_skill_draft_after_external_catalog_change() {
    new_fixture
    local source_dir source_id previous_id added_id page_status=0 current_revision
    source_dir="$(register_local_source plan-rebase skills/packs/plan-rebase)"
    source_id="$(source_id plan-rebase skills/packs/plan-rebase)"
    write_skill "${source_dir}" skills/one 'Existing Draft Skill' 'initial catalog row'
    commit_source "${source_dir}" 'initial source skill'

    settings_draft_load
    _settings_prepare_source_draft
    _settings_ensure_skill_draft
    previous_id="$(printf '%s\n' "${HAWS_CATALOG_SKILLS_CACHE}" | \
        awk -F '\t' -v source_id="${source_id}" '$1 == source_id {print $2}')"
    assert_contains "${HAWS_DRAFT_SKILLS}" "${previous_id}" \
        'skill draft starts from the active catalog state'

    # Preserve an explicit user disable while the source changes in another process.
    HAWS_DRAFT_SKILLS=""
    interactive_menu() { return 1; }
    settings_page > "${TEST_ROOT}/settings.out" 2>&1 || page_status=$?
    unset -f interactive_menu
    [ "${page_status}" -le 1 ] || fail "Settings page returned unexpected status ${page_status}"
    write_skill "${source_dir}" skills/two 'Added Draft Skill' 'new external catalog row'
    commit_source "${source_dir}" 'add source skill after draft load'
    current_revision="$(git -C "${source_dir}" rev-parse HEAD)"

    : > "${TRACE_SOURCE_SNAPSHOTS}"
    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    settings_plan_build
    added_id="$(printf '%s\n' "${HAWS_CATALOG_SKILLS_CACHE}" | \
        awk -F '\t' -v source_id="${source_id}" '$1 == source_id && $3 == "Added Draft Skill" {print $2}')"
    assert_contains "${HAWS_DRAFT_SKILLS}" "${added_id}" \
        'fresh Apply plan includes a skill added after draft load'
    if _settings_list_contains "${HAWS_DRAFT_SKILLS}" "${previous_id}"; then
        fail 'fresh Apply plan discarded the explicit disable of an existing skill'
    fi
    assert_contains "${HAWS_PERSIST_SKILLS}" "${previous_id}" \
        'fresh skill baseline includes the existing source skill'
    assert_contains "${HAWS_PERSIST_SKILLS}" "${added_id}" \
        'fresh skill baseline includes the external addition'
    assert_eq "${current_revision}" "$(printf '%s\n' "${HAWS_CATALOG_SOURCES_CACHE}" | \
        awk -F '\t' -v id="${source_id}" '$1 == id {print $4}')" \
        'Apply plan records the current external source revision'
    assert_eq 1 "$(catalog_call_count)" 'Apply plan builds one fresh catalog for its source snapshot'
    assert_eq 1 "$(find_call_count)" 'Apply plan scans the changed source once'
}

test_health_disk_cache_fast_path() {
    new_fixture
    local source_dir
    source_dir="$(register_source health skills/packs/health)"
    write_skill "${source_dir}" skills/main 'Health Skill' 'health cache fixture'
    commit_source "${source_dir}"
    HAWS_CATALOG_SOURCES_CACHE="$(catalog_sources)"
    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    : > "${TRACE_HEALTH_CLEAN_CHECKS}"
    : > "${TRACE_GIT}"
    _health_collect
    assert_eq 1 "${HAWS_HEALTH_SKILLS_TOTAL}" 'initial Health collection counts fixture skill'
    assert_eq 1 "$(catalog_call_count)" 'Health cache miss builds one complete catalog snapshot'
    assert_eq 1 "$(find_call_count)" 'Health cache miss scans the one registered source once'
    assert_eq 1 "$(trace_line_count "${TRACE_HEALTH_CLEAN_CHECKS}")" \
        'deep Health performs its source-cleanliness validation'
    assert_eq 1 "$(git_trace_count source-status)" 'deep Health checks tracked skill cleanliness'
    assert_eq 1 "$(git_trace_count ignored-entrypoint-check)" \
        'deep Health checks for ignored skill entrypoints'

    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    : > "${TRACE_HEALTH_CLEAN_CHECKS}"
    : > "${TRACE_GIT}"
    unset HAWS_CATALOG_SKILLS_CACHE
    unset HAWS_HEALTH_CACHE_FP HAWS_HEALTH_CACHE_FINDINGS
    unset HAWS_HEALTH_CACHE_ACTIVE HAWS_HEALTH_CACHE_TOTAL
    _health_collect
    assert_eq 0 "$(catalog_call_count)" 'valid disk Health cache fast path does not build the catalog'
    assert_eq 0 "$(find_call_count)" 'valid disk Health cache fast path performs no skill-file scans'
    assert_eq 1 "${HAWS_HEALTH_SKILLS_TOTAL}" 'valid disk Health cache restores stored skill count'
    assert_eq 1 "$(trace_line_count "${TRACE_HEALTH_CLEAN_CHECKS}")" \
        'cached Health still validates source cleanliness before trusting the disk result'
    assert_eq 1 "$(git_trace_count source-status)" 'cached Health checks tracked skill cleanliness'
    assert_eq 1 "$(git_trace_count ignored-entrypoint-check)" \
        'cached Health checks for ignored skill entrypoints'
}

test_preview_reuses_the_built_catalog_snapshot() {
    new_fixture
    local source_dir preview_status=0
    source_dir="$(register_source preview skills/packs/preview)"
    write_skill "${source_dir}" skills/main 'Preview Snapshot Skill' 'preview cache fixture'
    commit_source "${source_dir}"
    settings_draft_load
    _health_collect
    HAWS_DRAFT_SKILLS_LOADED=0
    HAWS_PLAN_KIND=Install
    HAWS_PLAN_CHANGED=1
    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    : > "${TRACE_SOURCE_BUILDS}"
    : > "${TRACE_SOURCE_SNAPSHOTS}"
    : > "${TRACE_HEALTH_CLEAN_CHECKS}"
    settings_plan_build
    assert_eq 1 "$(catalog_call_count)" 'Apply plan construction builds one current catalog snapshot'
    assert_eq 1 "$(find_call_count)" 'Apply plan construction scans each source once'

    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    : > "${TRACE_SOURCE_BUILDS}"
    : > "${TRACE_SOURCE_SNAPSHOTS}"
    : > "${TRACE_HEALTH_CLEAN_CHECKS}"
    interactive_menu() { return 1; }
    if settings_preview > "${TEST_ROOT}/preview.out" 2>&1; then
        preview_status=0
    else
        preview_status=$?
    fi
    unset -f interactive_menu

    assert_eq 2 "${preview_status}" 'Preview cancel returns to the prior draft flow'
    assert_eq 0 "$(catalog_call_count)" 'Preview reuses the catalog built with its Apply plan'
    assert_eq 0 "$(filtered_catalog_call_count)" 'Preview performs no source-filtered catalog build'
    assert_eq 0 "$(find_call_count)" 'Preview performs no additional skill-file scans'
    assert_eq 0 "$(source_materialization_count)" 'Preview performs no additional source-list materialization'
    assert_eq 0 "$(trace_line_count "${TRACE_SOURCE_SNAPSHOTS}")" \
        'Preview reuses the source snapshot refreshed during plan construction'
    assert_eq 0 "$(trace_line_count "${TRACE_HEALTH_CLEAN_CHECKS}")" \
        'Preview does not repeat source-cleanliness checks after plan construction'
}

test_process_a_refreshes_source_revision_after_process_b_sync() {
    new_fixture
    local source_dir bare author source_path='skills/packs/cross-process'
    local source="$(source_id cross-process skills/packs/cross-process)" new_revision classification
    source_dir="$(register_source cross-process "${source_path}")"
    write_skill "${source_dir}" skills/one 'First Cross Process Skill' 'initial source revision'
    commit_source "${source_dir}" 'initial source revision'
    bare="${TEST_ROOT}/remotes/cross-process.git"
    author="${TEST_ROOT}/authors/cross-process"
    git clone -q --bare "${source_dir}" "${bare}"
    git clone -q "${bare}" "${author}"
    write_skill "${author}" skills/two 'Second Cross Process Skill' 'updated source revision'
    git -C "${author}" add -A
    git -C "${author}" commit -q -m 'add second cross-process skill'
    git -C "${author}" push -q origin main
    new_revision="$(git --git-dir="${bare}" rev-parse refs/heads/main)"

    _health_collect
    assert_eq 1 "${HAWS_HEALTH_SKILLS_TOTAL}" 'process A caches the initial source revision'
    catalog_source_kind "${source}" classification
    assert_eq SINGLE "${classification}" 'process A caches the initial SINGLE source kind'

    # A separate process advances the shared source checkout, as another HAWS
    # Sync process can do while this shell session remains alive.
    bash -c 'git -C "$1" fetch -q "$2" main && git -C "$1" checkout --quiet --detach "$3"' \
        bash "${source_dir}" "${bare}" "${new_revision}"
    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    _health_collect
    assert_eq 2 "${HAWS_HEALTH_SKILLS_TOTAL}" 'process A refreshes Health after process B advances source HEAD'
    catalog_source_kind "${source}" classification
    assert_eq PACK "${classification}" 'process A refreshes source kind after process B advances source HEAD'
    assert_eq 1 "$(catalog_call_count)" 'cross-process source revision change rebuilds one complete catalog'
    assert_eq 1 "$(find_call_count)" 'cross-process source revision change scans the source once'
}

test_settings_draft_snapshot_refreshes_before_health_after_external_source_advance() {
    new_fixture
    local source_path='skills/packs/cross-process-health'
    local source="$(source_id cross-process-health "${source_path}")"
    local source_dir bare author new_revision classification cached_revision
    source_dir="$(register_source cross-process-health "${source_path}")"
    write_skill "${source_dir}" skills/one 'First Health Race Skill' 'initial health race revision'
    commit_source "${source_dir}" 'initial health race revision'

    _health_collect
    assert_eq 1 "${HAWS_HEALTH_SKILLS_TOTAL}" 'process A starts with one Health skill'
    catalog_source_kind "${source}" classification
    assert_eq SINGLE "${classification}" 'process A caches initial SINGLE classification'

    settings_draft_load
    assert_eq '' "${HAWS_CATALOG_SOURCE_SNAPSHOT_FRESH:-}" \
        'Settings draft does not grant later readers stale snapshot reuse'

    bare="${TEST_ROOT}/remotes/cross-process-health.git"
    author="${TEST_ROOT}/authors/cross-process-health"
    git clone -q --bare "${source_dir}" "${bare}"
    git clone -q "${bare}" "${author}"
    write_skill "${author}" skills/two 'Second Health Race Skill' 'updated health race revision'
    git -C "${author}" add -A
    git -C "${author}" commit -q -m 'add second health race skill'
    git -C "${author}" push -q origin main
    new_revision="$(git --git-dir="${bare}" rev-parse refs/heads/main)"

    # Process B advances the shared source after Settings cached its snapshot.
    bash -c 'git -C "$1" fetch -q "$2" main && git -C "$1" checkout --quiet --detach "$3"' \
        bash "${source_dir}" "${bare}" "${new_revision}"

    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    _health_collect
    assert_eq 2 "${HAWS_HEALTH_SKILLS_TOTAL}" \
        'Health refreshes after process B advances a source following Settings draft load'
    catalog_source_kind "${source}" classification
    assert_eq PACK "${classification}" 'Health refresh updates classification to PACK'
    cached_revision="$(printf '%s\n' "${HAWS_CATALOG_SOURCES_CACHE}" | awk -F '\t' -v id="${source}" '$1 == id {print $4}')"
    assert_eq "${new_revision}" "${cached_revision}" 'Health refresh stores the advanced source revision'
    assert_eq 1 "$(catalog_call_count)" 'Health refresh rebuilds one complete catalog snapshot'
    assert_eq 1 "$(find_call_count)" 'Health refresh scans the changed source once'
}

test_runtime_source_resolution_scales_with_sources() {
    new_fixture
    local source_dir source_path source_id i n=3 skills_per_source=8
    for i in 1 2 3; do
        source_path="skills/packs/runtime-${i}"
        source_dir="$(register_source "runtime-${i}" "${source_path}")"
        source_id="$(source_id "runtime-${i}" "${source_path}")"
        local skill_index
        for skill_index in $(seq 1 "${skills_per_source}"); do
            write_skill "${source_dir}" "skills/skill-${skill_index}" \
                "Runtime ${i} Skill ${skill_index}" 'runtime mapping fixture'
        done
        commit_source "${source_dir}"
    done

    : > "${TRACE_RUNTIME_DIR}"
    _health_collect --deep
    assert_eq "$((n * skills_per_source))" "${HAWS_HEALTH_SKILLS_TOTAL}" \
        'Health counts every active skill across large sources'
    [ "$(awk 'END { print NR + 0 }' "${TRACE_RUNTIME_DIR}")" -le "$((n * 5))" ] || \
        fail 'runtime source resolution grew with skill rows instead of source count'
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '[PASS] runtime source resolution stays proportional to source count\n'

    printf 'runtime-unsafe\t../outside\tfile://%s\n' "${TEST_ROOT}/outside" \
        >> "$(_catalog_device_source_registry)"
    _catalog_invalidate_source_catalog
    : > "${TRACE_RUNTIME_DIR}"
    _health_collect --deep
    ! grep -F '../outside' "${TRACE_RUNTIME_DIR}" >/dev/null || \
        fail 'unsafe registered path bypassed source path validation'
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '[PASS] source mapping does not resolve a traversal path\n'
}

test_cached_runtime_source_mapping_skips_repo_resolution() {
    new_fixture
    local source_path='skills/packs/runtime-cache' source_dir resolved
    source_dir="$(register_source runtime-cache "${source_path}")"
    TRACE_REPO_LOOKUPS="${TEST_ROOT}/traces/repo-lookups.txt"
    : > "${TRACE_REPO_LOOKUPS}"
    eval "$(declare -f _catalog_repo_dir | sed '1s/^_catalog_repo_dir ()/_catalog_repo_dir_original ()/')"
    _catalog_repo_dir() {
        printf 'lookup\n' >> "${TRACE_REPO_LOOKUPS}"
        _catalog_repo_dir_original
    }

    HAWS_CATALOG_RUNTIME_SOURCE_DIR_CACHE=()
    _catalog_runtime_source_dir "${source_path}" resolved
    assert_eq "${source_dir}" "${resolved}" 'runtime source mapping resolves a registered source'
    _catalog_runtime_source_dir "${source_path}" resolved
    assert_eq "${source_dir}" "${resolved}" 'runtime source mapping returns its cached path'
    assert_eq 0 "$(awk 'END { print NR + 0 }' "${TRACE_REPO_LOOKUPS}")" \
        'cached runtime source mapping does not resolve the repository fallback'

    : > "${TRACE_REPO_LOOKUPS}"
    local expected_revision
    expected_revision="$(git -C "${source_dir}" rev-parse HEAD)"
    _catalog_source_revision "${source_path}" resolved "${source_dir}"
    assert_eq "${expected_revision}" "${resolved}" 'source revision comes from the registered Git repository'
    assert_eq 0 "$(awk 'END { print NR + 0 }' "${TRACE_REPO_LOOKUPS}")" \
        'source revision does not resolve the root repository when source Git metadata exists'
    eval "$(declare -f _catalog_repo_dir_original | sed '1s/^_catalog_repo_dir_original ()/_catalog_repo_dir ()/')"
    unset -f _catalog_repo_dir_original
}

test_health_ignored_skill_bypasses_disk_cache() {
    new_fixture
    local source_dir ignored_file ignored_status=0
    source_dir="$(register_source ignored-health skills/packs/ignored-health)"
    write_skill "${source_dir}" skills/main 'Baseline Health Skill' 'ignored cache baseline'
    printf 'skills/ignored/SKILL.md\n__pycache__/\n' > "${source_dir}/.gitignore"
    commit_source "${source_dir}" 'track ignored skill fixture rule'
    HAWS_CATALOG_SOURCES_CACHE="$(catalog_sources)"

    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    _health_collect
    assert_eq 1 "${HAWS_HEALTH_SKILLS_TOTAL}" 'Health disk-cache fixture starts with one skill'

    # Clear process-local values so this call must restore the valid disk cache.
    unset HAWS_CATALOG_SKILLS_CACHE
    unset HAWS_HEALTH_CACHE_FP HAWS_HEALTH_CACHE_FINDINGS
    unset HAWS_HEALTH_CACHE_ACTIVE HAWS_HEALTH_CACHE_TOTAL
    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    _health_collect
    assert_eq 0 "$(catalog_call_count)" 'clean ignored-file fixture loads its valid Health disk cache'
    assert_eq 0 "$(find_call_count)" 'clean disk-cache reload performs no skill-file scans'
    assert_eq 1 "${HAWS_HEALTH_SKILLS_TOTAL}" 'clean disk-cache reload retains baseline skill count'

    local support_file="${source_dir}/skills/main/scripts/office/__pycache__/module.pyc"
    mkdir -p "$(dirname "${support_file}")"
    printf 'ignored supporting content\n' > "${support_file}"
    git -C "${source_dir}" check-ignore -q skills/main/scripts/office/__pycache__/module.pyc || \
        fail 'supporting-file fixture was not ignored by Git'
    unset HAWS_CATALOG_SKILLS_CACHE
    unset HAWS_HEALTH_CACHE_FP HAWS_HEALTH_CACHE_FINDINGS
    unset HAWS_HEALTH_CACHE_ACTIVE HAWS_HEALTH_CACHE_TOTAL
    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    _health_collect
    assert_eq 0 "$(catalog_call_count)" 'ignored supporting content does not invalidate the Health disk cache'
    assert_eq 0 "$(find_call_count)" 'ignored supporting content does not trigger a skill-tree scan'
    assert_eq 1 "${HAWS_HEALTH_SKILLS_TOTAL}" 'ignored supporting content keeps the baseline Health count'

    ignored_file="${source_dir}/skills/ignored/SKILL.md"
    write_skill "${source_dir}" skills/ignored 'Ignored Health Skill' 'ignored eligible skill'
    git -C "${source_dir}" check-ignore -q skills/ignored/SKILL.md || ignored_status=$?
    assert_eq 0 "${ignored_status}" 'new eligible SKILL.md is ignored by Git'

    # Force the next Health call to prove that an ignored marker bypasses the
    # otherwise valid disk cache and rebuilds the catalog snapshot.
    unset HAWS_CATALOG_SKILLS_CACHE
    unset HAWS_HEALTH_CACHE_FP HAWS_HEALTH_CACHE_FINDINGS
    unset HAWS_HEALTH_CACHE_ACTIVE HAWS_HEALTH_CACHE_TOTAL
    : > "${TRACE_CATALOG}"
    : > "${TRACE_FIND}"
    _health_collect
    assert_eq 2 "${HAWS_HEALTH_SKILLS_TOTAL}" 'ignored eligible skill bypasses disk cache and refreshes Health totals'
    assert_eq 1 "$(catalog_call_count)" 'ignored eligible skill triggers one full catalog build'
    assert_eq 1 "$(find_call_count)" 'ignored eligible skill triggers a source-tree scan'
    assert_contains "${HAWS_CATALOG_SKILLS_CACHE}" 'Ignored Health Skill' \
        'ignored eligible skill appears in the refreshed catalog snapshot'
    [ -f "${ignored_file}" ] || fail 'ignored skill fixture was not created'
}

test_health_cache_invalidation() {
    new_fixture
    local source_dir source_path='skills/packs/health' source="$(source_id health skills/packs/health)"
    source_dir="$(register_source health "${source_path}")"
    write_skill "${source_dir}" skills/one 'First Health Skill' 'first health skill'
    commit_source "${source_dir}"
    HAWS_CATALOG_SOURCES_CACHE="$(catalog_sources)"
    _health_collect
    assert_eq 1 "${HAWS_HEALTH_SKILLS_TOTAL}" 'baseline Health cache contains one skill'

    # A revision update must invalidate the cached source and skill snapshots.
    write_skill "${source_dir}" skills/two 'Second Health Skill' 'new revision skill'
    commit_source "${source_dir}" 'add second skill in a new source revision'
    : > "${TRACE_CATALOG}"
    _health_collect
    assert_eq 2 "${HAWS_HEALTH_SKILLS_TOTAL}" 'source revision change refreshes Health skill counts'
    assert_eq 1 "$(catalog_call_count)" 'source revision change rebuilds the complete skill snapshot once'
    local classification
    catalog_source_kind "${source}" classification
    assert_eq PACK "${classification}" 'source revision change refreshes dynamic PACK classification'

    # Registry changes are represented by the device-local registry fingerprint.
    local added_dir added_path='skills/standalone/added' added_id
    added_dir="$(register_source added "${added_path}")"
    write_skill "${added_dir}" skills/main 'Added Health Skill' 'added source skill'
    commit_source "${added_dir}"
    added_id="$(source_id added "${added_path}")"
    : > "${TRACE_CATALOG}"
    _health_collect
    assert_eq 3 "${HAWS_HEALTH_SKILLS_TOTAL}" 'registered source addition invalidates Health cache'
    assert_eq 1 "$(catalog_call_count)" 'source addition causes one full catalog rebuild'

    awk -F '\t' -v name=added '$1 != name {print}' "$(_catalog_device_source_registry)" \
        > "${TEST_ROOT}/registry.next"
    mv -- "${TEST_ROOT}/registry.next" "$(_catalog_device_source_registry)"
    : > "${TRACE_CATALOG}"
    _health_collect
    assert_eq 2 "${HAWS_HEALTH_SKILLS_TOTAL}" 'registered source removal invalidates Health cache'
    assert_eq 1 "$(catalog_call_count)" 'source removal causes one full catalog rebuild'
    assert_eq 0 "$(source_count_in_rows "${HAWS_CATALOG_SKILLS_CACHE}" "${added_id}")" \
        'removed source rows disappear from the rebuilt snapshot'

    # Active state changes do not affect source kind, but do invalidate Health totals.
    printf '%s\n' "${source}::First Health Skill" > "$(_skills_disabled_state_file)"
    : > "${TRACE_CATALOG}"
    _health_collect
    assert_eq 1 "${HAWS_HEALTH_SKILLS_ACTIVE}" 'disabling a skill refreshes Health active count'
    assert_eq 2 "${HAWS_HEALTH_SKILLS_TOTAL}" 'disabled skill remains in total source count'
    assert_eq 1 "$(catalog_call_count)" 'active-state change rebuilds the skill snapshot once'
    catalog_source_kind "${source}" classification
    assert_eq PACK "${classification}" 'active toggle leaves dynamic source kind unchanged'

    # A dirty, untracked eligible entrypoint must bypass the Health cache and refresh rows.
    rm -f "$(_skills_disabled_state_file)"
    local dirty_file="${source_dir}/skills/untracked/SKILL.md"
    write_skill "${source_dir}" skills/untracked 'Untracked Health Skill' 'untracked skill'
    : > "${TRACE_CATALOG}"
    _health_collect
    assert_eq 3 "${HAWS_HEALTH_SKILLS_TOTAL}" 'untracked eligible skill invalidates Health cache'
    assert_eq 1 "$(catalog_call_count)" 'untracked eligible skill causes one full catalog rebuild'
    assert_contains "${HAWS_CATALOG_SKILLS_CACHE}" 'Untracked Health Skill' 'untracked skill appears in refreshed snapshot'

    cat > "${dirty_file}" <<'EOF'
---
name: Updated Untracked Skill
description: modified dirty skill fixture
---
# Updated Untracked Skill
Fixture skill entrypoint after an uncommitted edit.
EOF
    : > "${TRACE_CATALOG}"
    _health_collect
    assert_eq 1 "$(catalog_call_count)" 'changed dirty skill content bypasses Health cache again'
    assert_contains "${HAWS_CATALOG_SKILLS_CACHE}" 'Updated Untracked Skill' 'dirty skill edit refreshes display data'
}

test_content_based_classification
test_source_snapshot_batches_gitlink_and_root_revision_checks
test_combined_skill_metadata_extraction_matches_existing_helpers
test_settings_entry_does_not_run_catalog_or_health_work
test_settings_source_draft_rebases_external_adds_and_removals
test_settings_builds_one_catalog_snapshot
test_active_skills_refreshes_source_changes_made_after_draft_load
test_apply_plan_rebases_skill_draft_after_external_catalog_change
test_health_disk_cache_fast_path
test_preview_reuses_the_built_catalog_snapshot
test_process_a_refreshes_source_revision_after_process_b_sync
test_settings_draft_snapshot_refreshes_before_health_after_external_source_advance
test_runtime_source_resolution_scales_with_sources
test_cached_runtime_source_mapping_skips_repo_resolution
test_health_cache_invalidation
test_health_ignored_skill_bypasses_disk_cache

printf '\nTests: %s passed, 0 failed\n' "${PASS_COUNT}"
