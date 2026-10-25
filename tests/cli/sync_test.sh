#!/usr/bin/env bash
# Batch 5 explicit Sync/Update behavior tests.

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
FIXTURE_ROOT=""
FIXTURE_HOME=""
FIXTURE_REPO=""
OUTPUT_FILE=""
passed=0
failed=0

fail() {
    echo "FAIL: $*" >&2
    return 1
}

create_fixture() {
    local temp_root="${TMPDIR:-/tmp}"
    temp_root="${temp_root%/}"
    [ -n "${temp_root}" ] || temp_root="/"
    FIXTURE_ROOT="$(mktemp -d "${temp_root%/}/haws-batch5.XXXXXX")"
    FIXTURE_HOME="${FIXTURE_ROOT}/home"
    FIXTURE_REPO="${FIXTURE_ROOT}/project"
    OUTPUT_FILE="${FIXTURE_ROOT}/output.txt"
    mkdir -p "${FIXTURE_HOME}" "${FIXTURE_REPO}"
    cp "${PROJECT_ROOT}/haws.sh" "${FIXTURE_REPO}/haws.sh"
    git init -q "${FIXTURE_REPO}"
    git -C "${FIXTURE_REPO}" config user.name HAWS-Test
    git -C "${FIXTURE_REPO}" config user.email test@example.invalid
    : > "${FIXTURE_REPO}/.gitmodules"
}

cleanup_fixture() {
    if [ -n "${FIXTURE_ROOT}" ] && [ -d "${FIXTURE_ROOT}" ]; then
        rm -rf -- "${FIXTURE_ROOT}"
    fi
    unset HAWS_REPO_DIR HAWS_STATE_DIR HAWS_SOURCE_ONLY HAWS_TEST_SYNC_DELAY \
        HAWS_AUTO_UPDATE AUTO_UPDATE HAWS_SECOND_BRAIN_ENABLED HAWS_SYNC_PREFETCH_DONE \
        HAWS_TEST_ALLOW_LOCAL_SOURCES HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE \
        GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
    FIXTURE_ROOT=""
    FIXTURE_HOME=""
    FIXTURE_REPO=""
    OUTPUT_FILE=""
}

source_haws() {
    export HOME="${FIXTURE_HOME}"
    export HAWS_REPO_DIR="${FIXTURE_REPO}"
    export HAWS_STATE_DIR="${FIXTURE_REPO}/.haws/state"
    export HAWS_SOURCE_ONLY=1
    # shellcheck disable=SC1091
    . "${FIXTURE_REPO}/haws.sh"
    unset HAWS_SOURCE_ONLY
}

write_settings() {
    local auto_update="$1"
    mkdir -p "${FIXTURE_REPO}/.haws/state"
    printf 'schema_version\t1\nsecond_brain\toff\nauto_update\t%s\n' \
        "${auto_update}" > "${FIXTURE_REPO}/.haws/state/settings.tsv"
}

add_source() {
    local name="$1"
    local seed="${FIXTURE_ROOT}/seed-${name}"
    local remote="${FIXTURE_ROOT}/${name}.git"
    local source="${FIXTURE_REPO}/skills/packs/${name}"
    mkdir -p "${seed}" "$(dirname "${source}")"
    git init --bare -q "${remote}"
    git init -q "${seed}"
    git -C "${seed}" config user.name HAWS-Test
    git -C "${seed}" config user.email test@example.invalid
    git -C "${seed}" checkout -q -b main
    printf '%s\n' '---' "name: ${name}" 'description: baseline' '---' \
        > "${seed}/SKILL.md"
    git -C "${seed}" add SKILL.md
    git -C "${seed}" commit -q -m baseline
    git -C "${seed}" remote add origin "${remote}"
    git -C "${seed}" push -q -u origin main
    git --git-dir="${remote}" symbolic-ref HEAD refs/heads/main
    git clone -q "${remote}" "${source}"
    printf '[submodule "%s"]\n\tpath = skills/packs/%s\n\turl = %s\n' \
        "${name}" "${name}" "${remote}" >> "${FIXTURE_REPO}/.gitmodules"
}

add_indexed_source() {
    local name="$1"
    local seed="${FIXTURE_ROOT}/seed-${name}"
    local remote="${FIXTURE_ROOT}/${name}.git"
    local source_path="skills/packs/${name}"
    mkdir -p "${seed}"
    git init --bare -q "${remote}"
    git init -q "${seed}"
    git -C "${seed}" config user.name HAWS-Test
    git -C "${seed}" config user.email test@example.invalid
    git -C "${seed}" checkout -q -b main
    printf '%s\n' '---' "name: ${name}" 'description: baseline' '---' \
        > "${seed}/SKILL.md"
    git -C "${seed}" add SKILL.md
    git -C "${seed}" commit -q -m baseline
    git -C "${seed}" remote add origin "${remote}"
    git -C "${seed}" push -q -u origin main
    git --git-dir="${remote}" symbolic-ref HEAD refs/heads/main
    printf '%s\n' '/.haws/' > "${FIXTURE_REPO}/.gitignore"
    git -C "${FIXTURE_REPO}" add haws.sh .gitignore
    git -C "${FIXTURE_REPO}" commit -q -m baseline
    git -C "${FIXTURE_REPO}" -c protocol.file.allow=always \
        submodule add -q "${remote}" "${source_path}"
    git -C "${FIXTURE_REPO}" add .gitmodules "${source_path}"
    git -C "${FIXTURE_REPO}" commit -q -m "register ${name}"
}

add_second_brain() {
    local seed="${FIXTURE_ROOT}/seed-secondbrain"
    local remote="${FIXTURE_ROOT}/secondbrain.git"
    mkdir -p "${seed}"
    git init --bare -q "${remote}"
    git init -q "${seed}"
    git -C "${seed}" config user.name HAWS-Test
    git -C "${seed}" config user.email test@example.invalid
    git -C "${seed}" checkout -q -b main
    printf '%s\n' '# Preferences' > "${seed}/USER_PREFERENCES.md"
    printf '%s\n' '# Anti-patterns' > "${seed}/ANTI_PATTERNS.md"
    printf '%s\n' '# Workflow' > "${seed}/WORKFLOW.md"
    git -C "${seed}" add USER_PREFERENCES.md ANTI_PATTERNS.md WORKFLOW.md
    git -C "${seed}" commit -q -m baseline
    git -C "${seed}" remote add origin "${remote}"
    git -C "${seed}" push -q -u origin main
    git --git-dir="${remote}" symbolic-ref HEAD refs/heads/main
    git clone -q "${remote}" "${FIXTURE_REPO}/secondbrain"
}

advance_source() {
    local name="$1"
    local content="${2:-updated}"
    local seed="${FIXTURE_ROOT}/seed-${name}"
    printf '%s\n' '---' "name: ${name}" "description: ${content}" '---' \
        > "${seed}/SKILL.md"
    git -C "${seed}" add SKILL.md
    git -C "${seed}" commit -q -m "update ${name}"
    git -C "${seed}" push -q origin main
    git -C "${seed}" rev-parse HEAD
}

sync_test_commit_source_file() {
    local name="$1" path="$2" content="$3" message
    local seed="${FIXTURE_ROOT}/seed-${name}"
    message="${4:-update ${path}}"
    mkdir -p "${seed}/$(dirname "${path}")" || return 1
    printf '%s\n' "${content}" > "${seed}/${path}" || return 1
    git -C "${seed}" add -- "${path}" || return 1
    git -C "${seed}" commit -q -m "${message}" || return 1
    git -C "${seed}" push -q origin main || return 1
    git -C "${seed}" rev-parse HEAD
}

delete_source_entrypoint() {
    local name="$1"
    local seed="${FIXTURE_ROOT}/seed-${name}"
    rm -f -- "${seed}/SKILL.md"
    git -C "${seed}" add -A
    git -C "${seed}" commit -q -m "remove ${name} entrypoint"
    git -C "${seed}" push -q origin main
    git -C "${seed}" rev-parse HEAD
}

source_head() {
    git -C "${FIXTURE_REPO}/skills/packs/$1" rev-parse HEAD
}

device_source_head() {
    git -C "${FIXTURE_REPO}/.haws/state/skill-sources/skills/packs/$1" rev-parse HEAD
}

source_remote_head() {
    git -C "${FIXTURE_REPO}/skills/packs/$1" rev-parse refs/remotes/origin/main
}

assert_record() {
    local target="$1"
    local result="$2"
    local file="${FIXTURE_REPO}/.haws/state/sync-state.tsv"
    [ -f "${file}" ] || return 1
    awk -F '\t' -v target="${target}" -v result="${result}" \
        '$2 == target && $3 == result { found = 1 } END { exit found ? 0 : 1 }' \
        "${file}"
}

assert_single_sync_presentation() {
    local expected_source="${1:-}" expected_brain="${2:-}"
    local haws_line source_line brain_line summary_line sync_summary_count
    [ "$(grep -Ec '^[[:space:]]+HAWS SYNC$' "${OUTPUT_FILE}" || true)" -eq 1 ] || return 1
    [ "$(grep -xc 'OPTIONS' "${OUTPUT_FILE}" || true)" -eq 1 ] || return 1
    [ "$(grep -Ec '^  TARGET[[:space:]]+RESULT[[:space:]]+DETAIL$' "${OUTPUT_FILE}" || true)" -eq 1 ] || return 1
    sync_summary_count="$(awk '
        /^[[:space:]]+HAWS SYNC$/ { in_sync=1 }
        in_sync && /^SUMMARY$/ { count++ }
        in_sync && /^\[(PASS|WARN)\] Sources are synchronized or safely unchanged|^\[WARN\] Source synchronization completed with target issues/ { in_sync=0 }
        END { print count+0 }
    ' "${OUTPUT_FILE}")"
    [ "${sync_summary_count}" -eq 1 ] || return 1

    haws_line="$(grep -nE '^  haws[[:space:]]+\[PASS\] Updated' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    summary_line="$(grep -nFx 'SUMMARY' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    [ -n "${haws_line}" ] && [ -n "${summary_line}" ] &&
        [ "${haws_line}" -lt "${summary_line}" ] || return 1
    if [ -n "${expected_source}" ]; then
        source_line="$(grep -nE "^  ${expected_source}[[:space:]]" "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
        [ -n "${source_line}" ] && [ "${haws_line}" -lt "${source_line}" ] &&
            [ "${source_line}" -lt "${summary_line}" ] || return 1
    fi
    if [ -n "${expected_brain}" ]; then
        brain_line="$(grep -nE "^  ${expected_brain}[[:space:]]" "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
        [ -n "${source_line}" ] && [ -n "${brain_line}" ] &&
            [ "${source_line}" -lt "${brain_line}" ] &&
            [ "${brain_line}" -lt "${summary_line}" ] || return 1
    fi
}

run_sync_process() {
    local -a args=("$@")
    [ "${#args[@]}" -gt 0 ] || args=(sync)
    env HOME="${FIXTURE_HOME}" HAWS_REPO_DIR="${FIXTURE_REPO}" \
        HAWS_STATE_DIR="${FIXTURE_REPO}/.haws/state" PATH="${PATH}" \
        bash "${FIXTURE_REPO}/haws.sh" "${args[@]}" >"${OUTPUT_FILE}" 2>&1
}

add_device_source_pack() {
    local name="$1" skill_count="${2:-3}"
    local bare="${FIXTURE_ROOT}/${name}.git"
    local seed="${FIXTURE_ROOT}/seed-${name}"
    local registry="${FIXTURE_REPO}/.haws/state/skill-sources/registry.tsv"
    local index skill_name
    mkdir -p "${seed}" "$(dirname "${registry}")"
    git init --bare -q "${bare}"
    git init -q "${seed}"
    git -C "${seed}" config user.name HAWS-Test
    git -C "${seed}" config user.email test@example.invalid
    git -C "${seed}" checkout -q -b main
    for index in $(seq 1 "${skill_count}"); do
        skill_name="${name}-skill-${index}"
        mkdir -p "${seed}/${skill_name}"
        printf '%s\n' '---' "name: ${skill_name}" \
            "description: Fixture skill ${index}." '---' \
            > "${seed}/${skill_name}/SKILL.md"
    done
    git -C "${seed}" add .
    git -C "${seed}" commit -q -m baseline
    git -C "${seed}" remote add origin "${bare}"
    git -C "${seed}" push -q -u origin main
    git --git-dir="${bare}" symbolic-ref HEAD refs/heads/main
    printf '%s\t%s\tfile://%s\n' "${name}" \
        "skills/packs/${name}" "${bare}" >> "${registry}"
    export HAWS_TEST_ALLOW_LOCAL_SOURCES=1
}

device_source_id() {
    printf 'device-%s::skills/packs/%s\n' "$1" "$1"
}

device_source_dir() {
    printf '%s/.haws/state/skill-sources/skills/packs/%s\n' \
        "${FIXTURE_REPO}" "$1"
}

prepare_haws_remote() {
    local bare="${FIXTURE_ROOT}/haws.git"
    local updater="${FIXTURE_ROOT}/haws-updater"
    if [ ! -f "${FIXTURE_REPO}/.gitignore" ]; then
        printf '%s\n' '.haws/' > "${FIXTURE_REPO}/.gitignore"
    elif ! grep -Fxq '.haws/' "${FIXTURE_REPO}/.gitignore"; then
        printf '%s\n' '.haws/' >> "${FIXTURE_REPO}/.gitignore"
    fi
    git -C "${FIXTURE_REPO}" checkout -q -b main
    git -C "${FIXTURE_REPO}" config user.name HAWS-Test
    git -C "${FIXTURE_REPO}" config user.email test@example.invalid
    git init --bare -q "${bare}"
    git -C "${FIXTURE_REPO}" add .gitignore .gitmodules haws.sh
    git -C "${FIXTURE_REPO}" commit -q -m baseline
    git -C "${FIXTURE_REPO}" remote add origin "${bare}"
    git -C "${FIXTURE_REPO}" push -q -u origin main
    git --git-dir="${bare}" symbolic-ref HEAD refs/heads/main
    git clone -q "${bare}" "${updater}"
    git -C "${updater}" config user.name HAWS-Test
    git -C "${updater}" config user.email test@example.invalid
    printf '%s\n' "${updater}"
}

add_runtime_marker_and_update_haws() {
    local updater="$1"
    awk '
        /^_run_sync_impl\(\) \{/ { in_sync=1 }
        in_sync && /^    shift \|\| true$/ {
            print
            print "    echo HAWS_RUNTIME_B"
            print "    if [ \"${CLEAN_UNMANAGED}\" = true ]; then echo HAWS_CLEAN_ARGUMENT_PRESERVED; fi"
            in_sync=0
            next
        }
        { print }
    ' "${updater}/haws.sh" > "${updater}/haws.sh.next" || return 1
    mv -- "${updater}/haws.sh.next" "${updater}/haws.sh" || return 1
    git -C "${updater}" add haws.sh || return 1
    git -C "${updater}" commit -q -m 'add runtime marker' || return 1
    git -C "${updater}" push -q origin main
}

add_remote_submodule_pack() {
    local updater="$1" name="$2" skill_count="${3:-2}"
    local bare="${FIXTURE_ROOT}/${name}-source.git"
    local seed="${FIXTURE_ROOT}/${name}-source-seed"
    local index skill_name
    mkdir -p "${seed}"
    git init --bare -q "${bare}"
    git init -q "${seed}"
    git -C "${seed}" config user.name HAWS-Test
    git -C "${seed}" config user.email test@example.invalid
    git -C "${seed}" checkout -q -b main
    for index in $(seq 1 "${skill_count}"); do
        skill_name="${name}-skill-${index}"
        mkdir -p "${seed}/${skill_name}"
        printf '%s\n' '---' "name: ${skill_name}" \
            "description: New submodule skill ${index}." '---' \
            > "${seed}/${skill_name}/SKILL.md"
    done
    git -C "${seed}" add .
    git -C "${seed}" commit -q -m baseline
    git -C "${seed}" remote add origin "${bare}"
    git -C "${seed}" push -q -u origin main
    git --git-dir="${bare}" symbolic-ref HEAD refs/heads/main
    git -C "${updater}" -c protocol.file.allow=always submodule add -q \
        "file://${bare}" "skills/packs/${name}" || return 1
    git -C "${updater}" add .gitmodules "skills/packs/${name}" || return 1
    git -C "${updater}" commit -q -m "register ${name}" || return 1
    git -C "${updater}" push -q origin main
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0=protocol.file.allow
    export GIT_CONFIG_VALUE_0=always
}

test_sync_output_has_sections_and_summary() {
    local source="${PROJECT_ROOT}/haws.sh"
    local sync_block
    sync_block="$(sed -n '/^sync_run() {/,/^run_sync() {/p' "${source}")"
    grep -Fq 'OPTIONS' <<< "${sync_block}" || return 1
    grep -Fq 'TARGET' <<< "${sync_block}" || return 1
    grep -Fq 'SUMMARY' <<< "${sync_block}" || return 1
    grep -Fq 'Updated' <<< "${sync_block}" || return 1
}

test_sync_uses_short_bootstrap_style_phases() {
    local source="${PROJECT_ROOT}/haws.sh"
    local sync_block
    sync_block="$(sed -n '/^_run_sync_impl() {/,/^run_sync() {/p' "${source}")"
    grep -Fq 'Step 1:' <<< "${sync_block}" || return 1
    grep -Fq 'Step 2:' <<< "${sync_block}" || return 1
    grep -Fq 'Step 5:' <<< "${sync_block}" || return 1
}

test_sync_result_defines_full_header_and_navigation_contract() {
    local source="${PROJECT_ROOT}/haws.sh"
    local sync_block wait_block
    sync_block="$(sed -n '/^_run_sync_impl() {/,/^run_sync() {/p' "${source}")"
    wait_block="$(sed -n '/^_haws_wait_for_result() {/,/^status_run() {/p' "${source}")"
    grep -Fq 'HAWS Sync Result' <<< "${sync_block}" || return 1
    grep -Fq '=============================================================' <<< "${sync_block}" || return 1
    grep -Fq '[Q] Return to Home' <<< "${wait_block}" || return 1
    grep -Fq '[Any key] Exit CLI' <<< "${wait_block}" || return 1
    grep -Fq 'q|Q' <<< "${wait_block}" || return 1
}

test_sync_result_wait_does_not_replace_sync_exit_status() {
    local source="${PROJECT_ROOT}/haws.sh"
    local sync_block
    sync_block="$(sed -n '/^_run_sync_impl() {/,/^run_sync() {/p' "${source}")"
    grep -Fq 'wait_status' <<< "${sync_block}" || return 1
    grep -Fq 'return "${sync_status}"' <<< "${sync_block}" || return 1
}

test_direct_sync_prints_result_without_entering_home() {
    write_settings off
    run_sync_process sync || return 1
    local banner_line summary_line
    banner_line="$(grep -nF 'HAWS Sync Result' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    summary_line="$(grep -nF 'SUMMARY' "${OUTPUT_FILE}" | tail -n 1 | cut -d: -f1)"
    [ -n "${banner_line}" ] && [ -n "${summary_line}" ] && [ "${banner_line}" -lt "${summary_line}" ] || return 1
    ! grep -F '(on)' "${OUTPUT_FILE}" >/dev/null 2>&1 || return 1
    ! grep -F '(off)' "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_run_sync_reuses_catalog_cache_for_step4() {
    mkdir -p "${FIXTURE_REPO}/skills/custom/demo-one" "${FIXTURE_HOME}/.claude"
    printf '%s\n' '---' 'name: demo-one' 'description: Cached skill.' '---' \
        > "${FIXTURE_REPO}/skills/custom/demo-one/SKILL.md"
    source_haws || return 1
    HAWS_CATALOG_SKILLS_CACHE="$(catalog_skills)" || return 1
    export HAWS_CATALOG_SKILLS_CACHE

    catalog_skills() {
        echo 'unexpected Step 4 catalog rescan' >&2
        return 97
    }

    local status=0
    if run_sync >"${OUTPUT_FILE}" 2>&1; then
        status=0
    else
        status=$?
    fi
    unset -f catalog_skills
    [ "${status}" -eq 0 ] || return 1
    [ -e "${FIXTURE_HOME}/.claude/skills/demo-one" ] || \
        [ -L "${FIXTURE_HOME}/.claude/skills/demo-one" ] || return 1
    local step4_end
    step4_end="$(grep -nF '[PASS] Skills, profiles, commands, and cleanup are ready' \
        "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    [ -n "${step4_end}" ] || return 1
    ! sed -n "1,${step4_end}p" "${OUTPUT_FILE}" | \
        grep -F 'unexpected Step 4 catalog rescan' >/dev/null 2>&1
}

test_run_sync_reuses_runtime_source_cache_for_step4() {
    mkdir -p "${FIXTURE_REPO}/skills/custom/demo-one" \
        "${FIXTURE_REPO}/skills/custom/demo-two" "${FIXTURE_HOME}/.claude"
    printf '%s\n' '---' 'name: demo-one' 'description: First cached skill.' '---' \
        > "${FIXTURE_REPO}/skills/custom/demo-one/SKILL.md"
    printf '%s\n' '---' 'name: demo-two' 'description: Second cached skill.' '---' \
        > "${FIXTURE_REPO}/skills/custom/demo-two/SKILL.md"
    source_haws || return 1
    HAWS_CATALOG_SKILLS_CACHE="$(catalog_skills)" || return 1
    export HAWS_CATALOG_SKILLS_CACHE

    local calls_file="${FIXTURE_ROOT}/runtime-source-calls"
    printf '0\n' > "${calls_file}"
    _catalog_runtime_source_dir() {
        local requested="${1:-}" out_var="${2:-}" calls resolved
        calls="$(<"${calls_file}")"
        printf '%s\n' "$((calls + 1))" > "${calls_file}"
        resolved="$(_catalog_repo_dir)/${requested}"
        if [ -n "${out_var}" ]; then
            printf -v "${out_var}" '%s' "${resolved}"
        else
            printf '%s\n' "${resolved}"
        fi
    }

    local status=0
    if run_sync >"${OUTPUT_FILE}" 2>&1; then
        status=0
    else
        status=$?
    fi
    local runtime_calls
    runtime_calls="$(<"${calls_file}")"
    unset -f _catalog_runtime_source_dir
    [ "${status}" -eq 0 ] || return 1
    # One lookup is expected during Step 4; the two fixture skills are then
    # inspected again by the health summary after linking.
    [ "${runtime_calls}" -eq 3 ] || {
        echo "expected one Step 4 lookup plus two health lookups, got ${runtime_calls}" >&2
        return 1
    }
}

test_sync_runs_phases_in_order_and_configures_hooks() {
    mkdir -p "${FIXTURE_REPO}/.githooks"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${FIXTURE_REPO}/.githooks/commit-msg"
    chmod +x "${FIXTURE_REPO}/.githooks/commit-msg"
    write_settings off
    run_sync_process sync || return 1

    local banner_line step1 step2 step3 step4 step5
    banner_line="$(grep -nF 'HAWS SYNC' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    step1="$(grep -nF '[*] Step 1:' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    step2="$(grep -nF '[*] Step 2:' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    step3="$(grep -nF '[*] Step 3:' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    step4="$(grep -nF '[*] Step 4:' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    step5="$(grep -nF '[*] Step 5:' "${OUTPUT_FILE}" | head -n 1 | cut -d: -f1)"
    [ -n "${banner_line}" ] && [ -n "${step1}" ] && [ "${banner_line}" -lt "${step1}" ] || return 1
    [ "${step1}" -lt "${step2}" ] || return 1
    [ "${step2}" -lt "${step3}" ] && [ "${step3}" -lt "${step4}" ] || return 1
    [ "${step4}" -lt "${step5}" ] || return 1
    grep -F '[PASS] Git advisory hooks configured' "${OUTPUT_FILE}" >/dev/null || return 1
    [ "$(git -C "${FIXTURE_REPO}" config --get core.hooksPath)" = .githooks ]
}

test_sync_adopts_exact_legacy_pointer_after_ownership_ledger_upgrade() {
    write_settings off
    mkdir -p "${FIXTURE_HOME}/.gemini" "${FIXTURE_HOME}/.haws" \
        "${FIXTURE_REPO}/.haws/state" "${FIXTURE_REPO}/ai-configs/gemini"
    cp "${PROJECT_ROOT}/ai-configs/gemini/skills-json.mjs" \
        "${FIXTURE_REPO}/ai-configs/gemini/skills-json.mjs" || return 1
    printf 'installed\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
    printf 'skill:legacy-fixture:skills/packs/legacy-fixture\n' \
        > "${FIXTURE_HOME}/.haws_manifest"
    printf 'skills\tsymlink\t%s\t%s\tlegacy-hash\n' \
        "${FIXTURE_HOME}/.gemini/config/skills/legacy-fixture" \
        "${FIXTURE_REPO}/skills/packs/legacy-fixture" \
        > "${FIXTURE_HOME}/.haws/skills-ownership.tsv"

    local repo_path pointer_file expected_file
    repo_path="$(cd "${FIXTURE_REPO}" && pwd)" || return 1
    pointer_file="${FIXTURE_HOME}/.gemini/GEMINI.md"
    expected_file="${FIXTURE_ROOT}/expected-pointer.txt"
    cat > "${expected_file}" <<EOF
<!-- HAWS_GLOBAL_POINTER_START -->
# HAWS — Human-AI Working Standard
This environment operates under HAWS. Read and adhere to:
- Core Standard: ${repo_path}/core/HAWS.md
- Work Instructions: ${repo_path}/core/WORK_INSTRUCTIONS.md
- Second Brain documents: ${repo_path}/secondbrain/ (neutral defaults in public main; personal DEV content stays in the private DEV checkout)
- Subagent roles: ${repo_path}/agents/ (organizer, researcher, frontend-engineer, backend-engineer, tester). Read the relevant role before delegating with available native subagent tools.
<!-- HAWS_GLOBAL_POINTER_END -->
EOF
    cp "${expected_file}" "${pointer_file}" || return 1

    run_sync_process sync || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    [ -s "${FIXTURE_REPO}/.haws/state/ownership-ledger-v2" ] || return 1
    [ -s "${FIXTURE_REPO}/.haws/state/integration-ownership-migration-v1" ] || return 1
    grep -F '[ADOPTED] Exact legacy HAWS pointer ownership:' "${OUTPUT_FILE}" >/dev/null || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    ! grep -F '[PRESERVED] Exact HAWS pointer is unowned outside the one-time legacy migration:' \
        "${OUTPUT_FILE}" >/dev/null || return 1
    cmp -s "${expected_file}" "${pointer_file}" || return 1

    source_haws || return 1
    local expected_hash record
    expected_hash="$(_haws_pointer_block_fingerprint "${pointer_file}")" || return 1
    record="$(ownership_record_for_path pointers "${pointer_file}" 2>/dev/null || true)"
    [ "${record}" = "pointer-block$(printf '\t')${pointer_file}$(printf '\t')created$(printf '\t')${expected_hash}" ]
}

test_sync_repairs_legacy_pointer_migration_marked_complete_too_early() {
    write_settings off
    mkdir -p "${FIXTURE_HOME}/.gemini" "${FIXTURE_HOME}/.haws" \
        "${FIXTURE_REPO}/.haws/state" "${FIXTURE_REPO}/ai-configs/gemini"
    cp "${PROJECT_ROOT}/ai-configs/gemini/skills-json.mjs" \
        "${FIXTURE_REPO}/ai-configs/gemini/skills-json.mjs" || return 1
    printf 'installed\n' > "${FIXTURE_REPO}/.haws/state/install.complete"
    printf 'skill:legacy-fixture:skills/packs/legacy-fixture\n' \
        > "${FIXTURE_HOME}/.haws_manifest"
    printf 'skills\tsymlink\t%s\t%s\tlegacy-hash\n' \
        "${FIXTURE_HOME}/.gemini/config/skills/legacy-fixture" \
        "${FIXTURE_REPO}/skills/packs/legacy-fixture" \
        > "${FIXTURE_HOME}/.haws/skills-ownership.tsv"

    local repo_path pointer_file expected_file old_migration_marker
    local fixed_timestamp='2024-01-01T00:00:00Z'
    repo_path="$(cd "${FIXTURE_REPO}" && pwd)" || return 1
    pointer_file="${FIXTURE_HOME}/.gemini/GEMINI.md"
    expected_file="${FIXTURE_ROOT}/expected-pointer.txt"
    cat > "${expected_file}" <<EOF
<!-- HAWS_GLOBAL_POINTER_START -->
# HAWS — Human-AI Working Standard
This environment operates under HAWS. Read and adhere to:
- Core Standard: ${repo_path}/core/HAWS.md
- Work Instructions: ${repo_path}/core/WORK_INSTRUCTIONS.md
- Second Brain documents: ${repo_path}/secondbrain/ (neutral defaults in public main; personal DEV content stays in the private DEV checkout)
- Subagent roles: ${repo_path}/agents/ (organizer, researcher, frontend-engineer, backend-engineer, tester). Read the relevant role before delegating with available native subagent tools.
<!-- HAWS_GLOBAL_POINTER_END -->
EOF
    cp "${expected_file}" "${pointer_file}" || return 1
    touch -t 202001010000.00 "${pointer_file}" || return 1

    old_migration_marker="schema=1$(printf '\t')migrated_at=${fixed_timestamp}"
    printf '%s\n' "${old_migration_marker}" \
        > "${FIXTURE_REPO}/.haws/state/integration-ownership-migration-v1"
    printf 'schema=2\tupgraded_at=%s\n' "${fixed_timestamp}" \
        > "${FIXTURE_REPO}/.haws/state/ownership-ledger-v2"
    touch -t 202401010000.00 \
        "${FIXTURE_REPO}/.haws/state/integration-ownership-migration-v1" \
        "${FIXTURE_REPO}/.haws/state/ownership-ledger-v2" || return 1

    source_haws || return 1
    _haws_schema_marker_valid "$(_haws_state_dir)/integration-ownership-migration-v1" \
        1 migrated_at || return 1
    _haws_schema_marker_valid "$(_haws_state_dir)/ownership-ledger-v2" \
        2 upgraded_at || return 1
    [ "$(<"$(_haws_state_dir)/integration-ownership-migration-v1")" = \
        "${old_migration_marker}" ] || return 1
    [ ! -e "$(_haws_state_dir)/ownership.tsv" ] || return 1

    run_sync_process sync || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    grep -F '[ADOPTED] Exact legacy HAWS pointer ownership:' "${OUTPUT_FILE}" >/dev/null || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    ! grep -F '[PRESERVED] Exact HAWS pointer is unowned outside the one-time legacy migration:' \
        "${OUTPUT_FILE}" >/dev/null || return 1
    cmp -s "${expected_file}" "${pointer_file}" || return 1

    source_haws || return 1
    local expected_hash record current_migration_marker
    _haws_schema_marker_valid "$(_haws_state_dir)/integration-ownership-migration-v1" \
        1 migrated_at || return 1
    _haws_schema_marker_valid "$(_haws_state_dir)/ownership-ledger-v2" \
        2 upgraded_at || return 1
    current_migration_marker="$(<"$(_haws_state_dir)/integration-ownership-migration-v1")"
    [ "${current_migration_marker}" != "${old_migration_marker}" ] || return 1
    expected_hash="$(_haws_pointer_block_fingerprint "${pointer_file}")" || return 1
    record="$(ownership_record_for_path pointers "${pointer_file}" 2>/dev/null || true)"
    [ "${record}" = "pointer-block$(printf '\t')${pointer_file}$(printf '\t')created$(printf '\t')${expected_hash}" ]
}

test_sync_target_rows_use_batch_result_markers() {
    source_haws || return 1
    SYNC_SUMMARY_UPDATED=0
    SYNC_SUMMARY_UP_TO_DATE=0
    SYNC_SUMMARY_SKIPPED=0
    SYNC_SUMMARY_BLOCKED=0
    SYNC_SUMMARY_FAILED=0
    SYNC_SUMMARY_TIMEOUT=0
    local result marker label
    for result in updated up-to-date skipped blocked failed timeout; do
        case "${result}" in
            updated) marker='[PASS]'; label=Updated ;;
            up-to-date) marker='[PASS]'; label=Up-to-date ;;
            skipped) marker='[WARN]'; label=Skipped ;;
            blocked) marker='[BLOCKED]'; label=Blocked ;;
            failed) marker='[FAIL]'; label=Failed ;;
            timeout) marker='[WARN]'; label=Timeout ;;
        esac
        _sync_present_result "target-${result}" "${result}" detail >>"${OUTPUT_FILE}"
        grep -F "target-${result}" "${OUTPUT_FILE}" >/dev/null || return 1
        grep -F "${marker} ${label}" "${OUTPUT_FILE}" >/dev/null || return 1
        grep -F detail "${OUTPUT_FILE}" >/dev/null || return 1
    done
}

test_sync_apis_are_present() {
    source_haws || return 1
    for api in run_with_deadline source_preflight source_candidate_validate \
        sync_target sync_result_write sync_run; do
        declare -F "${api}" >/dev/null || return 1
    done
}

test_clean_source_applies_remote_revision() {
    add_source clean
    local target="clean::skills/packs/clean"
    local old_head new_head
    new_head="$(advance_source clean valid)" || return 1
    old_head="$(source_head clean)" || return 1
    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1
    [ "$(source_head clean)" = "${new_head}" ] || return 1
    [ "$(source_head clean)" != "${old_head}" ] || return 1
    grep -F 'description: valid' "${FIXTURE_REPO}/skills/packs/clean/SKILL.md" >/dev/null || return 1
    assert_record "${target}" updated
}

test_device_source_without_seed_remote_stays_local_only() {
    add_indexed_source local-only
    local source_path="${FIXTURE_REPO}/skills/packs/local-only"
    local source_id="skills/packs/local-only::skills/packs/local-only"
    git -C "${source_path}" remote remove origin || return 1
    source_haws || return 1
    _haws_prepare_device_source "${source_id}" || return 1
    ! git -C "${FIXTURE_REPO}/.haws/state/skill-sources/skills/packs/local-only" \
        remote get-url origin >/dev/null 2>&1
}

test_indexed_submodule_skill_update_does_not_dirty_root() {
    add_indexed_source indexed
    local target="skills/packs/indexed::skills/packs/indexed"
    local new_head root_head
    root_head="$(git -C "${FIXTURE_REPO}" rev-parse HEAD)" || return 1
    new_head="$(advance_source indexed device-update)" || return 1
    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1
    [ "$(device_source_head indexed)" = "${new_head}" ] || return 1
    [ "$(source_head indexed)" != "${new_head}" ] || return 1
    [ "$(git -C "${FIXTURE_REPO}" rev-parse HEAD)" = "${root_head}" ] || {
        echo "expected skill refresh not to create a root commit" >&2
        return 1
    }
    [ -z "$(git -C "${FIXTURE_REPO}" status --porcelain --untracked-files=all)" ] || {
        echo "expected clean root after device-local skill update" >&2
        git -C "${FIXTURE_REPO}" status --short >&2
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    assert_record "${target}" updated
}

test_root_preflight_ignores_only_legacy_submodule_worktree_drift() {
    add_indexed_source legacy
    local new_head
    new_head="$(advance_source legacy legacy-drift)" || return 1
    git -C "${FIXTURE_REPO}/skills/packs/legacy" fetch -q origin main || return 1
    git -C "${FIXTURE_REPO}/skills/packs/legacy" checkout -q "${new_head}" || return 1
    source_haws || return 1

    git -C "${FIXTURE_REPO}" status --porcelain --ignore-submodules=none |
        grep -F 'skills/packs/legacy' >/dev/null || return 1
    _sync_root_preflight || return 1

    printf '%s\n' 'ordinary root change' > "${FIXTURE_REPO}/root-change.txt"
    _sync_root_preflight
    [ "$?" -eq 2 ] || return 1
    rm -f -- "${FIXTURE_REPO}/root-change.txt"

    git -C "${FIXTURE_REPO}" add skills/packs/legacy || return 1
    _sync_root_preflight
    [ "$?" -eq 2 ]
}

test_root_preflight_blocks_tracked_untracked_and_gitmodules_edits() {
    add_indexed_source root-safety
    source_haws || return 1

    printf '\nuser edit\n' >> "${FIXTURE_REPO}/haws.sh"
    _sync_root_preflight
    [ "$?" -eq 2 ] || return 1
    git -C "${FIXTURE_REPO}" checkout -- haws.sh || return 1

    printf 'untracked user file\n' > "${FIXTURE_REPO}/user-data.txt"
    _sync_root_preflight
    [ "$?" -eq 2 ] || return 1
    rm -f -- "${FIXTURE_REPO}/user-data.txt" || return 1

    printf '\n# user registration\n' >> "${FIXTURE_REPO}/.gitmodules"
    _sync_root_preflight
    [ "$?" -eq 2 ] || return 1
    git -C "${FIXTURE_REPO}" add .gitmodules || return 1
    _sync_root_preflight
    [ "$?" -eq 2 ] || return 1
    git -C "${FIXTURE_REPO}" reset -q -- .gitmodules || return 1
    git -C "${FIXTURE_REPO}" checkout -- .gitmodules || return 1
    _sync_root_preflight
}

test_haws_sync_treats_remote_ancestor_as_up_to_date() {
    local remote="${FIXTURE_ROOT}/haws.git"
    git init --bare -q "${remote}" || return 1
    printf '%s\n' '/.haws/' > "${FIXTURE_REPO}/.gitignore"
    git -C "${FIXTURE_REPO}" add haws.sh .gitmodules || return 1
    git -C "${FIXTURE_REPO}" add .gitignore || return 1
    git -C "${FIXTURE_REPO}" commit -q -m baseline || return 1
    git -C "${FIXTURE_REPO}" branch -M main || return 1
    git -C "${FIXTURE_REPO}" remote add origin "${remote}" || return 1
    git -C "${FIXTURE_REPO}" push -q -u origin main || return 1
    git --git-dir="${remote}" symbolic-ref HEAD refs/heads/main || return 1

    printf '%s\n' 'local-only commit' > "${FIXTURE_REPO}/local-only.txt"
    git -C "${FIXTURE_REPO}" add local-only.txt || return 1
    git -C "${FIXTURE_REPO}" commit -q -m 'local ahead' || return 1
    local local_head
    local_head="$(git -C "${FIXTURE_REPO}" rev-parse HEAD)" || return 1

    write_settings on
    source_haws || return 1
    local status=0
    if sync_target haws >"${OUTPUT_FILE}" 2>&1; then
        status=0
    else
        status=$?
    fi
    [ "${status}" -eq 0 ] || return 1
    [ "$(git -C "${FIXTURE_REPO}" rev-parse HEAD)" = "${local_head}" ] || return 1
    assert_record haws up-to-date || return 1
    grep -F 'local HEAD is ahead of remote candidate' "${OUTPUT_FILE}" >/dev/null || return 1
}

test_up_to_date_requires_measured_head_equality() {
    add_source current
    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1
    assert_record "current::skills/packs/current" up-to-date
}

test_dirty_source_is_blocked_while_clean_source_continues() {
    add_source dirty
    add_source safe
    local dirty_target="dirty::skills/packs/dirty"
    local safe_target="safe::skills/packs/safe"
    local dirty_head safe_head
    dirty_head="$(advance_source dirty dirty-remote)" || return 1
    safe_head="$(advance_source safe safe-remote)" || return 1
    printf 'local change\n' >> "${FIXTURE_REPO}/skills/packs/dirty/SKILL.md"
    : > "${FIXTURE_REPO}/skills/packs/dirty/untracked.txt"
    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1
    local status=$?
    [ "${status}" -ne 0 ] || return 1
    [ "$(source_head dirty)" != "${dirty_head}" ] || return 1
    [ "$(source_head safe)" = "${safe_head}" ] || return 1
    assert_record "${dirty_target}" blocked || return 1
    grep -F 'source skills/packs/dirty' "${OUTPUT_FILE}" >/dev/null || return 1
    grep -F 'SKILL.md' "${OUTPUT_FILE}" >/dev/null || return 1
    grep -F 'untracked.txt' "${OUTPUT_FILE}" >/dev/null || return 1
    assert_record "${safe_target}" updated
}

test_second_brain_syncs_local_changes() {
    add_second_brain
    printf '%s\n' 'local preference' >> "${FIXTURE_REPO}/secondbrain/USER_PREFERENCES.md"
    mkdir -p "${FIXTURE_REPO}/.haws/state"
    printf 'schema_version\t1\nsecond_brain\ton\nauto_update\toff\nauto_update_brain\ton\n' \
        > "${FIXTURE_REPO}/.haws/state/settings.tsv"
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1
    [ "$?" -eq 0 ] || return 1
    assert_record secondbrain updated || return 1
    git --git-dir="${FIXTURE_ROOT}/secondbrain.git" show main:USER_PREFERENCES.md \
        | grep -F 'local preference' >/dev/null || return 1
}

test_second_brain_syncs_local_changes_with_auto_update_on() {
    add_second_brain
    printf '%s\n' 'local preference' >> "${FIXTURE_REPO}/secondbrain/USER_PREFERENCES.md"
    mkdir -p "${FIXTURE_REPO}/.haws/state"
    printf 'schema_version\t1\nsecond_brain\ton\nauto_update\ton\nauto_update_brain\ton\n' \
        > "${FIXTURE_REPO}/.haws/state/settings.tsv"
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1
    [ "$?" -eq 0 ] || return 1
    assert_record secondbrain updated || return 1
    git --git-dir="${FIXTURE_ROOT}/secondbrain.git" show main:USER_PREFERENCES.md \
        | grep -F 'local preference' >/dev/null || return 1
}

test_second_brain_push_failure_is_reported() {
    add_second_brain
    printf '%s\n' 'local preference' >> "${FIXTURE_REPO}/secondbrain/USER_PREFERENCES.md"

    local remote="${FIXTURE_ROOT}/secondbrain.git"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "${remote}/hooks/pre-receive"
    chmod +x "${remote}/hooks/pre-receive"

    source_haws || return 1
    local status=0
    if run_user sync >"${OUTPUT_FILE}" 2>&1; then
        status=0
    else
        status=$?
    fi
    [ "${status}" -ne 0 ] || return 1
    grep -F '[ERROR] Failed to push Second Brain' "${OUTPUT_FILE}" >/dev/null || return 1
    ! grep -F '[✓] Second Brain in sync.' "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_candidate_accepts_moved_and_removed_skill_entrypoints() {
    add_source transitions
    local seed="${FIXTURE_ROOT}/seed-transitions"
    local source="${FIXTURE_REPO}/skills/packs/transitions"
    mkdir -p "${seed}/skills/in-progress/movable" "${seed}/skills/in-progress/removed"
    printf '%s\n' '---' 'name: movable' 'description: old location' '---' > "${seed}/skills/in-progress/movable/SKILL.md"
    printf '%s\n' '---' 'name: removed' 'description: retired skill' '---' > "${seed}/skills/in-progress/removed/SKILL.md"
    git -C "${seed}" add SKILL.md skills/in-progress || return 1
    git -C "${seed}" commit -q -m 'add source transition fixture' || return 1
    git -C "${seed}" push -q origin main || return 1
    git -C "${source}" pull -q --ff-only origin main || return 1

    mkdir -p "${seed}/skills/engineering/movable"
    git -C "${seed}" mv skills/in-progress/movable/SKILL.md skills/engineering/movable/SKILL.md || return 1
    git -C "${seed}" rm -q skills/in-progress/removed/SKILL.md SKILL.md || return 1
    git -C "${seed}" commit -q -m 'move and remove skills' || return 1
    git -C "${seed}" push -q origin main || return 1
    local candidate_head old_head
    candidate_head="$(git -C "${seed}" rev-parse HEAD)" || return 1
    old_head="$(source_head transitions)" || return 1

    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }

    [ "${old_head}" != "${candidate_head}" ] || return 1
    [ "$(source_head transitions)" = "${candidate_head}" ] || return 1
    [ -s "${source}/skills/engineering/movable/SKILL.md" ] || return 1
    [ ! -e "${source}/SKILL.md" ] || return 1
    assert_record "transitions::skills/packs/transitions" updated
}

test_missing_candidate_entrypoint_does_not_fall_back_to_old_content() {
    add_source missing
    local old_head candidate_head
    old_head="$(source_head missing)" || return 1
    candidate_head="$(delete_source_entrypoint missing)" || return 1
    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1
    local status=$?
    [ "${status}" -ne 0 ] || return 1
    [ "$(source_head missing)" = "${old_head}" ] || return 1
    [ -f "${FIXTURE_REPO}/skills/packs/missing/SKILL.md" ] || return 1
    [ "$(source_head missing)" != "${candidate_head}" ] || return 1
    assert_record "missing::skills/packs/missing" failed
}

test_deadline_returns_distinct_timeout_status() {
    source_haws || return 1
    run_with_deadline 1 bash -c 'sleep 2'
    [ "$?" -eq 124 ]
}

test_timeout_uses_local_fallback_without_failure() {
    add_source localfallback
    local old_head
    old_head="$(source_head localfallback)" || return 1
    write_settings on
    source_haws || return 1
    HAWS_SYNC_TIMEOUT_SECONDS=1 HAWS_TEST_SYNC_FETCH_DELAY=2 \
        sync_run >"${OUTPUT_FILE}" 2>&1
    [ "$?" -eq 0 ] || return 1
    [ "$(source_head localfallback)" = "${old_head}" ] || return 1
    grep -F 'Local fallback' "${OUTPUT_FILE}" >/dev/null || return 1
}

test_auto_update_off_skips_remote_work_but_runs_explicit_sync() {
    add_source disabled
    local old_head remote_head
    advance_source disabled skipped-update >/dev/null || return 1
    old_head="$(source_head disabled)" || return 1
    remote_head="$(source_remote_head disabled)" || return 1
    write_settings off
    run_sync_process sync || return 1
    [ "$(source_head disabled)" = "${old_head}" ] || return 1
    [ "$(source_remote_head disabled)" = "${remote_head}" ] || return 1
    assert_record "disabled::skills/packs/disabled" skipped || return 1
    grep -F '[INFO] Skipped' "${OUTPUT_FILE}" >/dev/null || return 1
    grep -F 'Auto Update is disabled' "${OUTPUT_FILE}" >/dev/null || return 1
    ! grep -F 'Auto Update is disabled' "${OUTPUT_FILE}" | grep -F '[WARN]' >/dev/null
}

test_second_brain_update_applies_remote_revision() {
    add_second_brain
    local seed="${FIXTURE_ROOT}/seed-secondbrain"
    printf '%s\n' 'remote note' > "${seed}/REMOTE_NOTE.md"
    git -C "${seed}" add REMOTE_NOTE.md
    git -C "${seed}" commit -q -m "remote brain update"
    local new_head
    git -C "${seed}" push -q origin main || return 1
    new_head="$(git -C "${seed}" rev-parse HEAD)" || return 1
    mkdir -p "${FIXTURE_REPO}/.haws/state"
    printf 'schema_version\t1\nsecond_brain\ton\nauto_update\toff\nauto_update_brain\ton\n' \
        > "${FIXTURE_REPO}/.haws/state/settings.tsv"
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1
    [ "$(git -C "${FIXTURE_REPO}/secondbrain" rev-parse HEAD)" = "${new_head}" ] || return 1
    [ -f "${FIXTURE_REPO}/secondbrain/REMOTE_NOTE.md" ] || return 1
    assert_record secondbrain updated
}

test_auto_update_brain_off_skips_brain_sync() {
    add_second_brain
    local seed="${FIXTURE_ROOT}/seed-secondbrain"
    printf '%s\n' 'remote note 2' > "${seed}/REMOTE_NOTE_2.md"
    git -C "${seed}" add REMOTE_NOTE_2.md
    git -C "${seed}" commit -q -m "remote brain update 2"
    git -C "${seed}" push -q origin main || return 1
    mkdir -p "${FIXTURE_REPO}/.haws/state"
    printf 'schema_version\t1\nauto_update_skills\ton\nauto_update_brain\toff\n' \
        > "${FIXTURE_REPO}/.haws/state/settings.tsv"
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1
    [ ! -f "${FIXTURE_REPO}/secondbrain/REMOTE_NOTE_2.md" ] || return 1
    assert_record secondbrain skipped
}

test_explicit_update_uses_same_safe_application() {
    add_source update
    local new_head
    new_head="$(advance_source update explicit-update)" || return 1
    write_settings on
    run_sync_process update || return 1
    [ "$(source_head update)" = "${new_head}" ] || return 1
    assert_record "update::skills/packs/update" updated
}

test_haws_update_preserves_the_current_branch() {
    local remote="${FIXTURE_ROOT}/haws.git"
    local seed="${FIXTURE_ROOT}/haws-seed"
    git init --bare -q "${remote}" || return 1
    git -C "${FIXTURE_REPO}" checkout -q -b main || return 1
    git -C "${FIXTURE_REPO}" add haws.sh .gitmodules || return 1
    git -C "${FIXTURE_REPO}" commit -q -m baseline || return 1
    git -C "${FIXTURE_REPO}" remote add origin "${remote}" || return 1
    git -C "${FIXTURE_REPO}" push -q -u origin main || return 1
    git --git-dir="${remote}" symbolic-ref HEAD refs/heads/main || return 1
    git clone -q "${remote}" "${seed}" || return 1
    git -C "${seed}" config user.name HAWS-Test
    git -C "${seed}" config user.email test@example.invalid
    printf '\n# remote update fixture\n' >> "${seed}/haws.sh"
    git -C "${seed}" add haws.sh || return 1
    git -C "${seed}" commit -q -m update || return 1
    git -C "${seed}" push -q origin main || return 1
    local expected
    expected="$(git -C "${seed}" rev-parse HEAD)" || return 1

    source_haws || return 1
    HAWS_AUTO_UPDATE=on
    sync_target haws >"${OUTPUT_FILE}" 2>&1
    local sync_status=$?
    [ "${sync_status}" -eq 0 ] || return 1
    local actual_branch actual_head
    actual_branch="$(git -C "${FIXTURE_REPO}" symbolic-ref --short HEAD 2>/dev/null || true)"
    actual_head="$(git -C "${FIXTURE_REPO}" rev-parse HEAD 2>/dev/null || true)"
    [ "${actual_branch}" = main ] || {
        echo "expected HAWS update to preserve branch main, got: ${actual_branch:-detached}" >&2
        return 1
    }
    [ "${actual_head}" = "${expected}" ] || {
        echo "expected HAWS HEAD ${expected}, got: ${actual_head:-missing}" >&2
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    assert_record haws updated
}

test_path_scoped_diff_skips_checkout_when_active_skills_unchanged() {
    add_source partial
    local seed="${FIXTURE_ROOT}/seed-partial"
    local old_head
    old_head="$(source_head partial)" || return 1
    printf 'remote non-skill change\n' > "${seed}/README.md"
    printf 'release notes\n' > "${seed}/CHANGELOG.md"
    mkdir -p "${seed}/.github/workflows"
    printf 'name: checks\n' > "${seed}/.github/workflows/checks.yml"
    git -C "${seed}" add README.md CHANGELOG.md .github/workflows/checks.yml
    git -C "${seed}" commit -q -m "update source docs only"
    git -C "${seed}" push -q origin main || return 1
    local new_head
    new_head="$(git -C "${seed}" rev-parse HEAD)" || return 1

    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1

    [ "$(source_head partial)" = "${old_head}" ] || return 1
    [ "$(source_head partial)" != "${new_head}" ] || return 1
    assert_record "partial::skills/packs/partial" up-to-date || return 1
    grep -F "active skills unchanged" "${FIXTURE_REPO}/.haws/state/sync-state.tsv" >/dev/null
}

test_active_root_skill_supporting_update_and_repeat_sync() {
    add_source root-support
    local old_head new_head expected_skills expected_identity ownership_before
    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1
    old_head="$(source_head root-support)" || return 1
    HAWS_CATALOG_SKILLS_CACHE="$(catalog_skills)" || return 1
    export HAWS_CATALOG_SKILLS_CACHE
    expected_skills="$(catalog_skills | awk 'NF { count++ } END { print count+0 }')" || return 1
    expected_identity="$(catalog_skills | awk -F '\t' '$1 == "root-support::skills/packs/root-support" { print $2 }')" || return 1
    ownership_before="$(ownership_list skills)" || return 1

    new_head="$(sync_test_commit_source_file root-support scripts/run.sh 'echo updated')" || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    [ "${old_head}" != "${new_head}" ] || return 1
    [ "$(source_head root-support)" = "${new_head}" ] || return 1
    grep -Fx 'echo updated' "${FIXTURE_REPO}/skills/packs/root-support/scripts/run.sh" >/dev/null || return 1
    assert_record "root-support::skills/packs/root-support" updated || return 1
    [ "$(catalog_skills | awk -F '\t' '$1 == "root-support::skills/packs/root-support" { print $2 }')" = "${expected_identity}" ] || return 1
    [ "$(catalog_skills | awk 'NF { count++ } END { print count+0 }')" -eq "${expected_skills}" ] || return 1
    [ "$(ownership_list skills)" = "${ownership_before}" ] || return 1

    sync_run >"${OUTPUT_FILE}" 2>&1 || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    [ "$(source_head root-support)" = "${new_head}" ] || return 1
    [ "$(catalog_skills | awk 'NF { count++ } END { print count+0 }')" -eq "${expected_skills}" ] || return 1
    [ "$(ownership_list skills)" = "${ownership_before}" ] || return 1
    assert_record "root-support::skills/packs/root-support" up-to-date || return 1
    ! grep -F '[REPAIRED]' "${OUTPUT_FILE}" >/dev/null
}

test_active_nested_skill_reference_update_advances_source() {
    add_source nested-reference
    local seed="${FIXTURE_ROOT}/seed-nested-reference"
    local source_id="nested-reference::skills/packs/nested-reference"
    local entrypoint="skills/engineering/api-guide/SKILL.md"
    local reference="skills/engineering/api-guide/references/api.md"
    local old_head new_head expected_identity ownership_before
    mkdir -p "${seed}/skills/engineering/api-guide/references" || return 1
    printf '%s\n' '---' 'name: api-guide' 'description: Nested skill.' '---' \
        > "${seed}/${entrypoint}"
    printf 'initial reference\n' > "${seed}/${reference}"
    git -C "${seed}" add -- skills/engineering/api-guide || return 1
    git -C "${seed}" commit -q -m 'add nested skill fixture' || return 1
    git -C "${seed}" push -q origin main || return 1
    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1

    HAWS_CATALOG_SKILLS_CACHE="$(catalog_skills)" || return 1
    export HAWS_CATALOG_SKILLS_CACHE
    printf '%s\n' "${HAWS_CATALOG_SKILLS_CACHE}" | awk -F '\t' -v source_id="${source_id}" \
        -v entrypoint="${entrypoint}" \
        '$1 == source_id && $5 == entrypoint && $6 == 1 { found=1 } END { exit found ? 0 : 1 }' || return 1
    expected_identity="$(printf '%s\n' "${HAWS_CATALOG_SKILLS_CACHE}" | awk -F '\t' \
        -v source_id="${source_id}" '$1 == source_id { print $2 }')" || return 1
    ownership_before="$(ownership_list skills)" || return 1
    old_head="$(source_head nested-reference)" || return 1
    new_head="$(sync_test_commit_source_file nested-reference "${reference}" 'updated reference')" || return 1

    sync_run >"${OUTPUT_FILE}" 2>&1 || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    [ "${old_head}" != "${new_head}" ] || return 1
    [ "$(source_head nested-reference)" = "${new_head}" ] || return 1
    grep -Fx 'updated reference' "${FIXTURE_REPO}/skills/packs/nested-reference/${reference}" >/dev/null || return 1
    [ "$(catalog_skills | awk -F '\t' -v source_id="${source_id}" '$1 == source_id { print $2 }')" = "${expected_identity}" ] || return 1
    [ "$(ownership_list skills)" = "${ownership_before}" ] || return 1
    assert_record "${source_id}" updated
}

test_all_disabled_source_skips_structure_change_then_reconciles_after_reenable() {
    local name="all-disabled-lifecycle"
    add_source "${name}" || return 1
    local seed="${FIXTURE_ROOT}/seed-${name}"
    local source_id="${name}::skills/packs/${name}"
    local disabled_file="${FIXTURE_REPO}/.haws/state/skills.disabled"
    local pack_head single_head old_remote_head rows disabled_ids kind
    local total active links

    git -C "${seed}" rm -q -- SKILL.md || return 1
    mkdir -p "${seed}/skills/alpha-before" "${seed}/skills/beta-before" || return 1
    printf '%s\n' '---' 'name: alpha-before' 'description: Initial pack skill.' '---' \
        > "${seed}/skills/alpha-before/SKILL.md"
    printf '%s\n' '---' 'name: beta-before' 'description: Initial pack skill.' '---' \
        > "${seed}/skills/beta-before/SKILL.md"
    git -C "${seed}" add -A || return 1
    git -C "${seed}" commit -q -m 'change source structure to a pack' || return 1
    git -C "${seed}" push -q origin main || return 1
    pack_head="$(git -C "${seed}" rev-parse HEAD)" || return 1

    write_settings on
    mkdir -p "${FIXTURE_HOME}/.claude" "${FIXTURE_REPO}/.haws/state" || return 1
    source_haws || return 1
    run_sync_process sync || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    [ "$(source_head "${name}")" = "${pack_head}" ] || return 1
    rows="$(catalog_skills)" || return 1
    total="$(printf '%s\n' "${rows}" | awk -F '\t' -v source_id="${source_id}" \
        '$1 == source_id { count++ } END { print count+0 }')" || return 1
    active="$(printf '%s\n' "${rows}" | awk -F '\t' -v source_id="${source_id}" \
        '$1 == source_id && $6 == 1 { count++ } END { print count+0 }')" || return 1
    kind="$(catalog_source_kind "${source_id}")" || return 1
    [ "${total}" -eq 2 ] && [ "${active}" -eq 2 ] && [ "${kind}" = PACK ] || return 1

    disabled_ids="$(printf '%s\n' "${rows}" | awk -F '\t' -v source_id="${source_id}" \
        '$1 == source_id { print $2 }')" || return 1
    [ "$(printf '%s\n' "${disabled_ids}" | awk 'NF { count++ } END { print count+0 }')" -eq 2 ] || return 1
    printf '%s\n' "${disabled_ids}" > "${disabled_file}" || return 1
    old_remote_head="$(source_remote_head "${name}")" || return 1

    # While every local skill is disabled, upstream removes the old entrypoints
    # and replaces the PACK with a new root-level SINGLE skill.
    git -C "${seed}" rm -qr -- skills || return 1
    printf '%s\n' '---' 'name: recovered-single' 'description: Replacement skill.' '---' \
        > "${seed}/SKILL.md"
    git -C "${seed}" add -A || return 1
    git -C "${seed}" commit -q -m 'change source structure to a single skill' || return 1
    git -C "${seed}" push -q origin main || return 1
    single_head="$(git -C "${seed}" rev-parse HEAD)" || return 1

    run_sync_process sync || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    grep -F 'source has no active skills' "${OUTPUT_FILE}" >/dev/null || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    grep -E 'Failed[[:space:]]*:[[:space:]]*0' "${OUTPUT_FILE}" >/dev/null || return 1
    assert_record "${source_id}" skipped || return 1
    [ "$(source_head "${name}")" = "${pack_head}" ] || return 1
    [ "$(source_remote_head "${name}")" = "${old_remote_head}" ] || return 1

    unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE \
        HAWS_CATALOG_SOURCE_CONFIG_FP HAWS_CATALOG_SKILL_STATE_FP \
        HAWS_CATALOG_SKILLS_DIRTY HAWS_CATALOG_SOURCE_KIND_CACHE \
        HAWS_CATALOG_DISABLED_SKILL_KEYS_MODE
    HAWS_CATALOG_DISABLED_SKILL_KEYS=()
    rows="$(catalog_skills)" || return 1
    total="$(printf '%s\n' "${rows}" | awk -F '\t' -v source_id="${source_id}" \
        '$1 == source_id { count++ } END { print count+0 }')" || return 1
    active="$(printf '%s\n' "${rows}" | awk -F '\t' -v source_id="${source_id}" \
        '$1 == source_id && $6 == 1 { count++ } END { print count+0 }')" || return 1
    kind="$(catalog_source_kind "${source_id}")" || return 1
    [ "${total}" -eq 2 ] && [ "${active}" -eq 0 ] && [ "${kind}" = PACK ] || return 1

    # Re-enable using the local PACK state, then let Sync reconcile upstream.
    : > "${disabled_file}" || return 1
    unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE \
        HAWS_CATALOG_SOURCE_CONFIG_FP HAWS_CATALOG_SKILL_STATE_FP \
        HAWS_CATALOG_SKILLS_DIRTY HAWS_CATALOG_SOURCE_KIND_CACHE \
        HAWS_CATALOG_DISABLED_SKILL_KEYS_MODE
    HAWS_CATALOG_DISABLED_SKILL_KEYS=()
    rows="$(catalog_skills)" || return 1
    active="$(printf '%s\n' "${rows}" | awk -F '\t' -v source_id="${source_id}" \
        '$1 == source_id && $6 == 1 { count++ } END { print count+0 }')" || return 1
    [ "${active}" -eq 2 ] || return 1

    run_sync_process sync || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    grep -E 'Failed[[:space:]]*:[[:space:]]*0' "${OUTPUT_FILE}" >/dev/null || return 1
    assert_record "${source_id}" updated || return 1
    [ "$(source_head "${name}")" = "${single_head}" ] || return 1
    [ ! -e "${FIXTURE_REPO}/skills/packs/${name}/skills/alpha-before/SKILL.md" ] || return 1
    [ ! -e "${FIXTURE_REPO}/skills/packs/${name}/skills/beta-before/SKILL.md" ] || return 1

    unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE \
        HAWS_CATALOG_SOURCE_CONFIG_FP HAWS_CATALOG_SKILL_STATE_FP \
        HAWS_CATALOG_SKILLS_DIRTY HAWS_CATALOG_SOURCE_KIND_CACHE \
        HAWS_CATALOG_DISABLED_SKILL_KEYS_MODE
    HAWS_CATALOG_DISABLED_SKILL_KEYS=()
    rows="$(catalog_skills)" || return 1
    total="$(printf '%s\n' "${rows}" | awk -F '\t' -v source_id="${source_id}" \
        '$1 == source_id { count++ } END { print count+0 }')" || return 1
    active="$(printf '%s\n' "${rows}" | awk -F '\t' -v source_id="${source_id}" \
        '$1 == source_id && $6 == 1 { count++ } END { print count+0 }')" || return 1
    kind="$(catalog_source_kind "${source_id}")" || return 1
    links="$(find "${FIXTURE_HOME}/.claude/skills" -mindepth 1 -maxdepth 1 -type l -print 2>/dev/null | \
        wc -l | tr -d '[:space:]')"
    [ "${total}" -eq 1 ] && [ "${active}" -eq 1 ] && [ "${kind}" = SINGLE ] && \
        [ "${links}" -eq 1 ] || return 1
    [ -L "${FIXTURE_HOME}/.claude/skills/recovered-single" ] && \
        [ -f "${FIXTURE_HOME}/.claude/skills/recovered-single/SKILL.md" ] || return 1
    ! [ -e "${FIXTURE_HOME}/.claude/skills/alpha-before" ] && \
        ! [ -L "${FIXTURE_HOME}/.claude/skills/alpha-before" ] && \
        ! [ -e "${FIXTURE_HOME}/.claude/skills/beta-before" ] && \
        ! [ -L "${FIXTURE_HOME}/.claude/skills/beta-before" ]
}

test_disabled_skill_structure_updates_and_reclassifies_same_sync() {
    add_source disabled-structure
    local seed="${FIXTURE_ROOT}/seed-disabled-structure"
    local source_id="disabled-structure::skills/packs/disabled-structure"
    local entrypoint="skills/disabled-beta/SKILL.md"
    local old_head add_head remove_head kind rows
    mkdir -p "${seed}/skills/disabled-beta" || return 1
    printf '%s\n' '---' 'name: disabled-beta' 'description: Disabled fixture.' '---' \
        > "${seed}/${entrypoint}"
    git -C "${seed}" add -- skills/disabled-beta || return 1
    git -C "${seed}" commit -q -m 'add disabled skill structure' || return 1
    git -C "${seed}" push -q origin main || return 1
    add_head="$(git -C "${seed}" rev-parse HEAD)" || return 1
    mkdir -p "${FIXTURE_REPO}/.haws/state" || return 1
    printf 'disabled-beta\n' > "${FIXTURE_REPO}/.haws/state/skills.disabled"
    write_settings on
    source_haws || return 1
    old_head="$(source_head disabled-structure)" || return 1

    sync_run >"${OUTPUT_FILE}" 2>&1 || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    [ "$(source_head disabled-structure)" = "${add_head}" ] || return 1
    rows="$(catalog_skills)" || return 1
    printf '%s\n' "${rows}" | awk -F '\t' -v source_id="${source_id}" \
        -v entrypoint="${entrypoint}" \
        '$1 == source_id && $5 == entrypoint && $6 == 0 { found=1 } END { exit found ? 0 : 1 }' || return 1
    kind="$(catalog_source_kind "${source_id}")" || return 1
    [ "${kind}" = PACK ] || return 1

    git -C "${seed}" rm -q -- "${entrypoint}" || return 1
    git -C "${seed}" commit -q -m 'remove disabled skill structure' || return 1
    git -C "${seed}" push -q origin main || return 1
    remove_head="$(git -C "${seed}" rev-parse HEAD)" || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    [ "${remove_head}" != "${add_head}" ] && [ "${old_head}" != "${remove_head}" ] || return 1
    [ "$(source_head disabled-structure)" = "${remove_head}" ] || return 1
    kind="$(catalog_source_kind "${source_id}")" || return 1
    [ "${kind}" = SINGLE ] || return 1
    rows="$(catalog_skills)" || return 1
    [ "$(printf '%s\n' "${rows}" | awk -F '\t' -v source_id="${source_id}" \
        '$1 == source_id && $6 == 1 { count++ } END { print count+0 }')" -eq 1 ] || return 1
    assert_record "${source_id}" updated
}

test_disabled_skill_supporting_file_change_stays_skipped() {
    add_source disabled-support
    local seed="${FIXTURE_ROOT}/seed-disabled-support"
    local source_id="disabled-support::skills/packs/disabled-support"
    local entrypoint="skills/disabled-beta/SKILL.md"
    local support_file="skills/disabled-beta/references/notes.md"
    local old_head new_head
    mkdir -p "${seed}/skills/disabled-beta/references" || return 1
    printf '%s\n' '---' 'name: disabled-beta' 'description: Disabled fixture.' '---' \
        > "${seed}/${entrypoint}"
    printf 'initial notes\n' > "${seed}/${support_file}"
    git -C "${seed}" add -- skills/disabled-beta || return 1
    git -C "${seed}" commit -q -m 'add disabled skill fixture' || return 1
    git -C "${seed}" push -q origin main || return 1
    mkdir -p "${FIXTURE_REPO}/.haws/state" || return 1
    printf 'disabled-beta\n' > "${FIXTURE_REPO}/.haws/state/skills.disabled"
    write_settings on
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1
    HAWS_CATALOG_SKILLS_CACHE="$(catalog_skills)" || return 1
    export HAWS_CATALOG_SKILLS_CACHE
    printf '%s\n' "${HAWS_CATALOG_SKILLS_CACHE}" | awk -F '\t' -v entrypoint="${entrypoint}" \
        '$5 == entrypoint && $6 == 0 { found=1 } END { exit found ? 0 : 1 }' || return 1

    old_head="$(source_head disabled-support)" || return 1
    new_head="$(sync_test_commit_source_file disabled-support "${support_file}" 'changed disabled notes')" || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    [ "${old_head}" != "${new_head}" ] || return 1
    [ "$(source_head disabled-support)" = "${old_head}" ] || return 1
    assert_record "${source_id}" up-to-date || return 1
    grep -F 'active skills unchanged' "${FIXTURE_REPO}/.haws/state/sync-state.tsv" >/dev/null
}

test_source_diff_failure_fails_safely() {
    add_source diff-failure
    local old_head new_head status=0
    old_head="$(source_head diff-failure)" || return 1
    new_head="$(sync_test_commit_source_file diff-failure README.md 'docs update')" || return 1
    write_settings on
    source_haws || return 1

    git() {
        if [ "${1:-}" = -C ] && [ "${3:-}" = diff ]; then
            return 42
        fi
        command git "$@"
    }
    if sync_run >"${OUTPUT_FILE}" 2>&1; then
        status=0
    else
        status=$?
    fi
    unset -f git

    [ "${new_head}" != "${old_head}" ] && [ "${status}" -ne 0 ] || return 1
    [ "$(source_head diff-failure)" = "${old_head}" ] || return 1
    grep -F 'changed paths could not be inspected' "${OUTPUT_FILE}" >/dev/null || return 1
    assert_record "diff-failure::skills/packs/diff-failure" failed
}

test_lock_releases_after_success_and_failure() {
    add_source success
    write_settings off
    source_haws || return 1
    sync_run >"${OUTPUT_FILE}" 2>&1 || return 1
    [ ! -d "${FIXTURE_REPO}/.haws/state/sync.lock" ] || return 1

    add_source failure
    delete_source_entrypoint failure >/dev/null || return 1
    write_settings on
    sync_run >"${OUTPUT_FILE}" 2>&1
    [ "$?" -ne 0 ] || return 1
    [ ! -d "${FIXTURE_REPO}/.haws/state/sync.lock" ]
}

test_lock_releases_after_interrupt() {
    add_source interrupted
    write_settings off
    env HOME="${FIXTURE_HOME}" HAWS_REPO_DIR="${FIXTURE_REPO}" \
        HAWS_STATE_DIR="${FIXTURE_REPO}/.haws/state" HAWS_TEST_SYNC_DELAY=5 \
        PATH="${PATH}" bash "${FIXTURE_REPO}/haws.sh" sync >"${OUTPUT_FILE}" 2>&1 &
    local child=$!
    local ready=0
    for _ in $(seq 1 50); do
        if [ -d "${FIXTURE_REPO}/.haws/state/sync.lock" ]; then
            ready=1
            break
        fi
        sleep 0.1
    done
    [ "${ready}" -eq 1 ] || { kill "${child}" 2>/dev/null || true; wait "${child}" 2>/dev/null || true; return 1; }
    kill -TERM "${child}" 2>/dev/null || true
    wait "${child}"
    local status=$?
    [ "${status}" -ne 0 ] || return 1
    [ ! -d "${FIXTURE_REPO}/.haws/state/sync.lock" ]
}

test_stock_bash_bootstraps_to_a_user_installed_bash() {
    local compatible_bash
    compatible_bash="$(command -v bash)" || return 1
    [ -x "${compatible_bash}" ] || return 1
    mkdir -p "${FIXTURE_HOME}/.local/bin" || return 1
    cp -- "${compatible_bash}" "${FIXTURE_HOME}/.local/bin/bash" || return 1

    env HOME="${FIXTURE_HOME}" HAWS_REPO_DIR="${FIXTURE_REPO}" \
        PATH="${PATH}" /bin/bash "${FIXTURE_REPO}/haws.sh" help \
        >"${OUTPUT_FILE}" 2>&1 || return 1
    grep -F 'Usage: ./haws.sh' "${OUTPUT_FILE}" >/dev/null
}

test_sync_materializes_absent_registered_pack_and_links_same_run() {
    local name="one-sync-pack" initial_rows rows source_dir
    add_device_source_pack "${name}" 3 || return 1
    write_settings on
    mkdir -p "${FIXTURE_HOME}/.claude"
    source_haws || return 1
    HAWS_CATALOG_SOURCES_CACHE="$(catalog_sources)"
    HAWS_CATALOG_SKILLS_CACHE="$(catalog_skills)"
    export HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE
    initial_rows="${HAWS_CATALOG_SKILLS_CACHE}"
    [ -z "${initial_rows}" ] || return 1

    run_sync >"${OUTPUT_FILE}" 2>&1 || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }

    source_dir="$(device_source_dir "${name}")"
    [ -d "${source_dir}" ] || return 1
    ! grep -F 'source has no active skills' "${OUTPUT_FILE}" >/dev/null || return 1
    rows="$(catalog_skills)"
    [ "$(printf '%s\n' "${rows}" | awk -F '\t' 'NF { n++ } END { print n+0 }')" -eq 3 ] || return 1
    [ "$(find "${FIXTURE_HOME}/.claude/skills" -type l -print | wc -l | tr -d '[:space:]')" -eq 3 ] || return 1
    [ "$(awk -F '\t' '$1 ~ /^skill:/ { n++ } END { print n+0 }' \
        "${FIXTURE_HOME}/.haws_manifest")" -eq 3 ]
}

test_background_prefetch_refreshes_parent_catalog_after_materialization() {
    local name="prefetch-pack" rows source_dir
    add_device_source_pack "${name}" 3 || return 1
    write_settings on
    source_haws || return 1
    export HAWS_AUTO_UPDATE=on
    HAWS_CATALOG_SOURCES_CACHE="$(catalog_sources)"
    HAWS_CATALOG_SKILLS_CACHE="$(catalog_skills)"
    export HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE
    [ -z "${HAWS_CATALOG_SKILLS_CACHE}" ] || return 1

    _sync_prefetch_all || return 1
    source_dir="$(device_source_dir "${name}")"
    [ -d "${source_dir}" ] || return 1
    if [ -n "${HAWS_CATALOG_SKILLS_CACHE+x}" ]; then
        echo 'background prefetch left the parent skill catalog cached' >&2
        return 1
    fi
    rows="$(catalog_skills)"
    [ "$(printf '%s\n' "${rows}" | awk -F '\t' 'NF { n++ } END { print n+0 }')" -eq 3 ]
}

test_multiskill_pack_counts_match_catalog_manifest_and_links() {
    local name="count-pack" source_id source_dir rows physical total active manifest links
    add_device_source_pack "${name}" 3 || return 1
    write_settings on
    mkdir -p "${FIXTURE_HOME}/.claude"
    source_haws || return 1
    source_id="$(device_source_id "${name}")"
    _haws_prepare_device_source "${source_id}" || return 1
    source_dir="$(device_source_dir "${name}")"
    rows="$(catalog_skills)"
    physical="$(find "${source_dir}" -type f -name SKILL.md -print | wc -l | tr -d '[:space:]')"
    total="$(printf '%s\n' "${rows}" | awk -F '\t' 'NF { n++ } END { print n+0 }')"
    active="$(printf '%s\n' "${rows}" | awk -F '\t' '$6 == 1 { n++ } END { print n+0 }')"
    [ "${physical}" -eq 3 ] && [ "${total}" -eq 3 ] && [ "${active}" -eq 3 ] || return 1

    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1
    rows="$(catalog_skills)"
    total="$(printf '%s\n' "${rows}" | awk -F '\t' 'NF { n++ } END { print n+0 }')"
    active="$(printf '%s\n' "${rows}" | awk -F '\t' '$6 == 1 { n++ } END { print n+0 }')"
    manifest="$(awk -F '\t' '$1 ~ /^skill:/ { n++ } END { print n+0 }' \
        "${FIXTURE_HOME}/.haws_manifest")"
    links="$(find "${FIXTURE_HOME}/.claude/skills" -type l -print | wc -l | tr -d '[:space:]')"
    [ "${physical}" -eq "${total}" ] && [ "${total}" -eq "${active}" ] &&
        [ "${active}" -eq "${manifest}" ] && [ "${manifest}" -eq "${links}" ]
}

test_disabled_new_pack_skill_stays_disabled_while_others_link() {
    local name="disabled-pack" source_id disabled_id disabled_file saved_disabled rows total active links
    add_device_source_pack "${name}" 3 || return 1
    write_settings on
    mkdir -p "${FIXTURE_HOME}/.claude" "${FIXTURE_REPO}/.haws/state"
    source_id="$(device_source_id "${name}")"
    disabled_id="${source_id}::${name}-skill-2"
    disabled_file="${FIXTURE_REPO}/.haws/state/skills.disabled"
    saved_disabled="${FIXTURE_ROOT}/skills.disabled.before"
    printf '%s\n' "${disabled_id}" > "${disabled_file}"
    cp -- "${disabled_file}" "${saved_disabled}" || return 1
    source_haws || return 1
    HAWS_CATALOG_SOURCES_CACHE="$(catalog_sources)"
    HAWS_CATALOG_SKILLS_CACHE="$(catalog_skills)"
    export HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE

    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1
    rows="$(catalog_skills)"
    total="$(printf '%s\n' "${rows}" | awk -F '\t' 'NF { n++ } END { print n+0 }')"
    active="$(printf '%s\n' "${rows}" | awk -F '\t' '$6 == 1 { n++ } END { print n+0 }')"
    links="$(find "${FIXTURE_HOME}/.claude/skills" -type l -print | wc -l | tr -d '[:space:]')"
    [ "${total}" -eq 3 ] && [ "${active}" -eq 2 ] && [ "${links}" -eq 2 ] || return 1
    cmp -s -- "${disabled_file}" "${saved_disabled}" || return 1
    ! [ -e "${FIXTURE_HOME}/.claude/skills/${name}-skill-2" ] &&
        ! [ -L "${FIXTURE_HOME}/.claude/skills/${name}-skill-2" ] || return 1
    [ "$(awk -F '\t' '$1 ~ /^skill:/ { n++ } END { print n+0 }' \
        "${FIXTURE_HOME}/.haws_manifest")" -eq 2 ]
}

test_haws_self_update_reexecutes_new_runtime_once_and_preserves_args() {
    local updater expected
    write_settings on
    updater="$(prepare_haws_remote)" || return 1
    add_runtime_marker_and_update_haws "${updater}" || return 1
    expected="$(git -C "${updater}" rev-parse HEAD)" || return 1

    run_sync_process sync --clean || return 1
    [ "$(git -C "${FIXTURE_REPO}" rev-parse HEAD)" = "${expected}" ] || return 1
    grep -F 'HAWS_RUNTIME_B' "${OUTPUT_FILE}" >/dev/null || return 1
    grep -F 'HAWS_CLEAN_ARGUMENT_PRESERVED' "${OUTPUT_FILE}" >/dev/null || return 1
    grep -F '[PASS] HAWS synchronization completed' "${OUTPUT_FILE}" >/dev/null || return 1
    [ "$(grep -Fc 'HAWS_RUNTIME_B' "${OUTPUT_FILE}" || true)" -eq 1 ] || return 1
    assert_single_sync_presentation || return 1
    [ ! -d "${FIXTURE_REPO}/.haws/state/sync.lock" ]
}

test_haws_update_adds_submodule_source_and_links_it_in_same_sync() {
    local name="new-haws-pack" updater expected source_dir rows active links
    printf '%s\n' '.haws/' 'secondbrain/' > "${FIXTURE_REPO}/.gitignore"
    add_second_brain || return 1
    mkdir -p "${FIXTURE_REPO}/.haws/state"
    printf 'schema_version\t1\nsecond_brain\ton\nauto_update\ton\nauto_update_brain\ton\n' \
        > "${FIXTURE_REPO}/.haws/state/settings.tsv"
    mkdir -p "${FIXTURE_HOME}/.claude"
    updater="$(prepare_haws_remote)" || return 1
    add_remote_submodule_pack "${updater}" "${name}" 2 || return 1
    add_runtime_marker_and_update_haws "${updater}" || return 1
    expected="$(git -C "${updater}" rev-parse HEAD)" || return 1

    run_sync_process sync || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    [ "$(git -C "${FIXTURE_REPO}" rev-parse HEAD)" = "${expected}" ] || return 1
    grep -F 'HAWS_RUNTIME_B' "${OUTPUT_FILE}" >/dev/null || return 1
    [ "$(grep -Fc 'HAWS_RUNTIME_B' "${OUTPUT_FILE}" || true)" -eq 1 ] || return 1
    assert_single_sync_presentation "${name}" secondbrain || {
        cat "${OUTPUT_FILE}" >&2
        return 1
    }
    ! grep -F 'source has no active skills' "${OUTPUT_FILE}" >/dev/null || return 1
    source_dir="$(device_source_dir "${name}")"
    [ -d "${source_dir}" ] || return 1
    git -C "${FIXTURE_REPO}/skills/packs/${name}" rev-parse --is-inside-work-tree >/dev/null || return 1
    source_haws || return 1
    rows="$(catalog_skills)"
    active="$(printf '%s\n' "${rows}" | awk -F '\t' '$6 == 1 { n++ } END { print n+0 }')"
    links="$(find "${FIXTURE_HOME}/.claude/skills" -type l -print | wc -l | tr -d '[:space:]')"
    [ "${active}" -eq 2 ] && [ "${links}" -eq 2 ] || return 1
    [ "$(awk -F '\t' '$1 ~ /^skill:/ { n++ } END { print n+0 }' \
        "${FIXTURE_HOME}/.haws_manifest")" -eq 2 ] || return 1
    assert_record "skills/packs/${name}::skills/packs/${name}" up-to-date
}

test_second_sync_is_idempotent_for_materialized_multiskill_pack() {
    local name="idempotent-pack" manifest_before ownership_before links_before \
        head_before root_status_before rows total active links
    add_device_source_pack "${name}" 3 || return 1
    write_settings on
    mkdir -p "${FIXTURE_HOME}/.claude"
    source_haws || return 1
    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1
    [ -f "${FIXTURE_HOME}/.haws_manifest" ] || return 1
    manifest_before="${FIXTURE_ROOT}/manifest.before"
    ownership_before="${FIXTURE_ROOT}/ownership.before"
    links_before="${FIXTURE_ROOT}/links.before"
    cp -- "${FIXTURE_HOME}/.haws_manifest" "${manifest_before}" || return 1
    ownership_list skills | sort > "${ownership_before}"
    find "${FIXTURE_HOME}/.claude/skills" -type l -print | sort > "${links_before}"
    head_before="$(device_source_head "${name}")" || return 1
    root_status_before="$(git -C "${FIXTURE_REPO}" status --porcelain --untracked-files=all)"

    run_sync >"${OUTPUT_FILE}" 2>&1 || return 1
    [ "$(device_source_head "${name}")" = "${head_before}" ] || return 1
    [ "$(git -C "${FIXTURE_REPO}" status --porcelain --untracked-files=all)" = \
        "${root_status_before}" ] || return 1
    cmp -s -- "${manifest_before}" "${FIXTURE_HOME}/.haws_manifest" || return 1
    ownership_list skills | sort > "${FIXTURE_ROOT}/ownership.after"
    cmp -s -- "${ownership_before}" "${FIXTURE_ROOT}/ownership.after" || return 1
    find "${FIXTURE_HOME}/.claude/skills" -type l -print | sort > \
        "${FIXTURE_ROOT}/links.after"
    cmp -s -- "${links_before}" "${FIXTURE_ROOT}/links.after" || return 1
    rows="$(catalog_skills)"
    total="$(printf '%s\n' "${rows}" | awk -F '\t' 'NF { n++ } END { print n+0 }')"
    active="$(printf '%s\n' "${rows}" | awk -F '\t' '$6 == 1 { n++ } END { print n+0 }')"
    links="$(find "${FIXTURE_HOME}/.claude/skills" -type l -print | wc -l | tr -d '[:space:]')"
    [ "${total}" -eq 3 ] && [ "${active}" -eq 3 ] && [ "${links}" -eq 3 ] || return 1
    ! grep -F "[LINKED] Claude Skill [${name}-skill-" "${OUTPUT_FILE}" >/dev/null || return 1
    awk -F '\t' '$1 == "skills" { key=$1 FS $3; if (seen[key]++) duplicate=1 }
        END { exit duplicate ? 1 : 0 }' \
        "${FIXTURE_HOME}/.haws/skills-ownership.tsv"
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

if [ -n "${HAWS_SYNC_TEST_ONLY:-}" ]; then
    run_test "${HAWS_SYNC_TEST_ONLY}"
else
    run_test test_sync_apis_are_present
    run_test test_sync_output_has_sections_and_summary
    run_test test_sync_uses_short_bootstrap_style_phases
    run_test test_sync_result_defines_full_header_and_navigation_contract
    run_test test_sync_result_wait_does_not_replace_sync_exit_status
    run_test test_direct_sync_prints_result_without_entering_home
    run_test test_run_sync_reuses_catalog_cache_for_step4
    run_test test_run_sync_reuses_runtime_source_cache_for_step4
    run_test test_sync_runs_phases_in_order_and_configures_hooks
    run_test test_sync_adopts_exact_legacy_pointer_after_ownership_ledger_upgrade
    run_test test_sync_repairs_legacy_pointer_migration_marked_complete_too_early
    run_test test_sync_target_rows_use_batch_result_markers
    run_test test_clean_source_applies_remote_revision
    run_test test_device_source_without_seed_remote_stays_local_only
    run_test test_indexed_submodule_skill_update_does_not_dirty_root
    run_test test_root_preflight_ignores_only_legacy_submodule_worktree_drift
    run_test test_root_preflight_blocks_tracked_untracked_and_gitmodules_edits
    run_test test_haws_sync_treats_remote_ancestor_as_up_to_date
    run_test test_up_to_date_requires_measured_head_equality
    run_test test_dirty_source_is_blocked_while_clean_source_continues
    run_test test_second_brain_syncs_local_changes
    run_test test_second_brain_syncs_local_changes_with_auto_update_on
    run_test test_second_brain_push_failure_is_reported
    run_test test_candidate_accepts_moved_and_removed_skill_entrypoints
    run_test test_missing_candidate_entrypoint_does_not_fall_back_to_old_content
    run_test test_deadline_returns_distinct_timeout_status
    run_test test_timeout_uses_local_fallback_without_failure
    run_test test_auto_update_off_skips_remote_work_but_runs_explicit_sync
    run_test test_second_brain_update_applies_remote_revision
    run_test test_auto_update_brain_off_skips_brain_sync
    run_test test_explicit_update_uses_same_safe_application
    run_test test_haws_update_preserves_the_current_branch
    run_test test_stock_bash_bootstraps_to_a_user_installed_bash
    run_test test_sync_materializes_absent_registered_pack_and_links_same_run
    run_test test_background_prefetch_refreshes_parent_catalog_after_materialization
    run_test test_multiskill_pack_counts_match_catalog_manifest_and_links
    run_test test_disabled_new_pack_skill_stays_disabled_while_others_link
    run_test test_haws_self_update_reexecutes_new_runtime_once_and_preserves_args
    run_test test_haws_update_adds_submodule_source_and_links_it_in_same_sync
    run_test test_second_sync_is_idempotent_for_materialized_multiskill_pack
    run_test test_path_scoped_diff_skips_checkout_when_active_skills_unchanged
    run_test test_active_root_skill_supporting_update_and_repeat_sync
    run_test test_active_nested_skill_reference_update_advances_source
    run_test test_disabled_skill_structure_updates_and_reclassifies_same_sync
    run_test test_all_disabled_source_skips_structure_change_then_reconciles_after_reenable
    run_test test_disabled_skill_supporting_file_change_stays_skipped
    run_test test_source_diff_failure_fails_safely
    run_test test_lock_releases_after_success_and_failure
    run_test test_lock_releases_after_interrupt
fi

echo "CLI Batch 5 sync tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
