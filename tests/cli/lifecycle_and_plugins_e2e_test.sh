#!/usr/bin/env bash
# ==============================================================================
# HAWS Universal Command Engine - Lifecycle & Plugins E2E Test Suite
#
# Comprehensive end-to-end hermetic test suite covering:
# 1. Zero-Install & Setup Flow (virgin fixture, state, secondbrain, hooks, sync)
# 2. Deep Settings & Sub-Menus (single skills, packs, environments, draft isolation)
# 3. Google Antigravity (AGY / Gemini) Sync & Native Config (skills.json, GEMINI.md, agents)
# 4. Plugin-Containing Skills & Extensions (ponytail, caveman, deduplication, scripts/hooks)
# 5. Command Surface Verification (status, doctor, hook install)
# 6. Clean Full Uninstall (pointers, managed links, preserved user data, doctor post-uninstall)
# ==============================================================================

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${TEST_DIR}/test_helper.sh"

passed=0
failed=0

fail() {
    echo "FAIL: $*" >&2
    if [ -n "${OUTPUT_FILE:-}" ] && [ -f "${OUTPUT_FILE}" ]; then
        echo "=== OUTPUT_FILE START ===" >&2
        cat "${OUTPUT_FILE}" >&2
        echo "=== OUTPUT_FILE END ===" >&2
    fi
    return 1
}


run_haws() {
    local status=0
    env HOME="${FIXTURE_HOME}" CODEX_HOME="${FIXTURE_HOME}/.codex" \
        HAWS_REPO_DIR="${FIXTURE_PROJECT}" HAWS_STATE_DIR="${FIXTURE_PROJECT}/.haws/state" \
        HAWS_TEST_KEYS="${HAWS_TEST_KEYS:-}" \
        HAWS_CALL_LOG="${CALL_LOG:-}" PATH="${PATH}" \
        bash "${FIXTURE_PROJECT}/haws.sh" "$@" >"${OUTPUT_FILE}" 2>&1 || status=$?
    if [ "${status}" -ne 0 ]; then
        cat "${OUTPUT_FILE}" >&2
        return "${status}"
    fi
}

run_haws_input() {
    local input="$1"
    shift
    printf '%b' "${input}" |
        env HOME="${FIXTURE_HOME}" CODEX_HOME="${FIXTURE_HOME}/.codex" \
            HAWS_REPO_DIR="${FIXTURE_PROJECT}" HAWS_STATE_DIR="${FIXTURE_PROJECT}/.haws/state" \
            HAWS_CALL_LOG="${CALL_LOG:-}" PATH="${PATH}" \
            bash "${FIXTURE_PROJECT}/haws.sh" "$@" >"${OUTPUT_FILE}" 2>&1
}

source_haws() {
    export HOME="${FIXTURE_HOME}"
    export CODEX_HOME="${FIXTURE_HOME}/.codex"
    export HAWS_REPO_DIR="${FIXTURE_PROJECT}"
    export HAWS_STATE_DIR="${FIXTURE_PROJECT}/.haws/state"
    export HAWS_SOURCE_ONLY=1
    # shellcheck disable=SC1091
    . "${FIXTURE_PROJECT}/haws.sh"
    unset HAWS_SOURCE_ONLY
}

create_test_directory_link() {
    local source="$1" destination="$2"
    if command -v cmd.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
        local windows_source windows_destination
        windows_source="$(cygpath -w "${source}")" || return 1
        windows_destination="$(cygpath -w "${destination}")" || return 1
        MSYS2_ARG_CONV_EXCL="*" cmd.exe /c mklink /J \
            "${windows_destination}" "${windows_source}" >/dev/null 2>&1
    else
        ln -s "${source}" "${destination}"
    fi
}

init_project_repo() {
    git -C "${FIXTURE_PROJECT}" init -q || return 1
    git -C "${FIXTURE_PROJECT}" config user.name "HAWS Tester"
    git -C "${FIXTURE_PROJECT}" config user.email "tester@example.invalid"
}

populate_full_fixture() {
    init_project_repo || return 1
    cp -r "${PROJECT_ROOT}/core" "${FIXTURE_PROJECT}/" 2>/dev/null || mkdir -p "${FIXTURE_PROJECT}/core"
    cp -r "${PROJECT_ROOT}/agents" "${FIXTURE_PROJECT}/" 2>/dev/null || mkdir -p "${FIXTURE_PROJECT}/agents"
    cp -r "${PROJECT_ROOT}/ai-configs" "${FIXTURE_PROJECT}/" 2>/dev/null || mkdir -p "${FIXTURE_PROJECT}/ai-configs"
    rm -f "${FIXTURE_PROJECT}/ai-configs/environments.disabled" "${FIXTURE_PROJECT}/skills/skills.disabled" 2>/dev/null || true
    cp -r "${PROJECT_ROOT}/.githooks" "${FIXTURE_PROJECT}/" 2>/dev/null || {
        mkdir -p "${FIXTURE_PROJECT}/.githooks"
        printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${FIXTURE_PROJECT}/.githooks/commit-msg"
        chmod +x "${FIXTURE_PROJECT}/.githooks/commit-msg"
    }
    mkdir -p "${FIXTURE_PROJECT}/secondbrain"
    printf '%s\n' '# User Preferences' > "${FIXTURE_PROJECT}/secondbrain/USER_PREFERENCES.md"
    printf '%s\n' '# Anti-patterns' > "${FIXTURE_PROJECT}/secondbrain/ANTI_PATTERNS.md"

    # Seed baseline Git submodules in .gitmodules
    {
        printf '[submodule "skills/packs/ponytail"]\n'
        printf '\tpath = skills/packs/ponytail\n'
        printf '\turl = https://github.com/DietrichGebert/ponytail.git\n'
        printf '[submodule "skills/standalone/caveman"]\n'
        printf '\tpath = skills/standalone/caveman\n'
        printf '\turl = https://github.com/JuliusBrussee/caveman.git\n'
        printf '[submodule "skills/standalone/graphify"]\n'
        printf '\tpath = skills/standalone/graphify\n'
        printf '\turl = https://github.com/Graphify-Labs/graphify.git\n'
    } > "${FIXTURE_PROJECT}/.gitmodules"

    # Populate ponytail multi-skill pack
    mkdir -p "${FIXTURE_PROJECT}/skills/packs/ponytail/skills/ponytail" \
        "${FIXTURE_PROJECT}/skills/packs/ponytail/skills/ponytail-review" \
        "${FIXTURE_PROJECT}/skills/packs/ponytail/skills/ponytail-audit" \
        "${FIXTURE_PROJECT}/skills/packs/ponytail/skills/ponytail-debt" \
        "${FIXTURE_PROJECT}/skills/packs/ponytail/skills/ponytail-gain" \
        "${FIXTURE_PROJECT}/skills/packs/ponytail/skills/ponytail-help" \
        "${FIXTURE_PROJECT}/skills/packs/ponytail/.claude-plugin" \
        "${FIXTURE_PROJECT}/skills/packs/ponytail/hooks" \
        "${FIXTURE_PROJECT}/skills/packs/ponytail/scripts"

    printf '%s\n' '---' 'name: ponytail' 'description: Root ponytail skill.' '---' \
        > "${FIXTURE_PROJECT}/skills/packs/ponytail/skills/ponytail/SKILL.md"
    printf '%s\n' '---' 'name: ponytail-review' 'description: Review code over-engineering.' '---' \
        > "${FIXTURE_PROJECT}/skills/packs/ponytail/skills/ponytail-review/SKILL.md"
    printf '%s\n' '---' 'name: ponytail-audit' 'description: Whole-repo over-engineering audit.' '---' \
        > "${FIXTURE_PROJECT}/skills/packs/ponytail/skills/ponytail-audit/SKILL.md"
    printf '%s\n' '---' 'name: ponytail-debt' 'description: Track tech debt comments.' '---' \
        > "${FIXTURE_PROJECT}/skills/packs/ponytail/skills/ponytail-debt/SKILL.md"
    printf '%s\n' '---' 'name: ponytail-gain' 'description: Measure simplification gains.' '---' \
        > "${FIXTURE_PROJECT}/skills/packs/ponytail/skills/ponytail-gain/SKILL.md"
    printf '%s\n' '---' 'name: ponytail-help' 'description: Quick reference card.' '---' \
        > "${FIXTURE_PROJECT}/skills/packs/ponytail/skills/ponytail-help/SKILL.md"
    printf '%s\n' '{"name":"ponytail"}' > "${FIXTURE_PROJECT}/skills/packs/ponytail/.claude-plugin/plugin.json"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${FIXTURE_PROJECT}/skills/packs/ponytail/hooks/post-install.sh"
    printf '%s\n' 'console.log("check versions");' > "${FIXTURE_PROJECT}/skills/packs/ponytail/scripts/check-versions.js"
    printf '%s\n' '{"id":"ponytail-agy"}' > "${FIXTURE_PROJECT}/skills/packs/ponytail/gemini-extension.json"

    # Populate standalone skills (caveman with internal plugin copy, graphify)
    mkdir -p "${FIXTURE_PROJECT}/skills/standalone/caveman/plugins/vendor-plugin" \
        "${FIXTURE_PROJECT}/skills/standalone/graphify"
    printf '%s\n' '---' 'name: caveman' 'description: Succinct caveman communication style.' '---' \
        > "${FIXTURE_PROJECT}/skills/standalone/caveman/SKILL.md"
    printf '%s\n' '---' 'name: vendor-plugin' 'description: Internal vendor plugin copy.' '---' \
        > "${FIXTURE_PROJECT}/skills/standalone/caveman/plugins/vendor-plugin/SKILL.md"
    printf '%s\n' '---' 'name: graphify' 'description: Knowledge graph builder and visualizer.' '---' \
        > "${FIXTURE_PROJECT}/skills/standalone/graphify/SKILL.md"

    # Copy .gitignore to protect state directory from triggering dirty tree detection
    cp "${PROJECT_ROOT}/.gitignore" "${FIXTURE_PROJECT}/.gitignore" 2>/dev/null || true

    # Initialize submodules as distinct Git checkouts so status is clean for preflight
    local sub
    for sub in skills/packs/ponytail skills/standalone/caveman skills/standalone/graphify; do
        git -C "${FIXTURE_PROJECT}/${sub}" init -q || return 1
        git -C "${FIXTURE_PROJECT}/${sub}" config user.name "HAWS Tester" || return 1
        git -C "${FIXTURE_PROJECT}/${sub}" config user.email "tester@example.invalid" || return 1
        git -C "${FIXTURE_PROJECT}/${sub}" add -A || return 1
        git -C "${FIXTURE_PROJECT}/${sub}" commit -qm "baseline ${sub}" || return 1
    done

    # Commit superproject files
    git -C "${FIXTURE_PROJECT}" add -A || return 1
    git -C "${FIXTURE_PROJECT}" commit -qm "baseline fixture setup" || return 1
}



# ==============================================================================
# Scenario 1: Zero-Install & Setup Flow
# ==============================================================================
test_zero_install_and_setup_flow() {
    populate_full_fixture || return 1

    # Assert virgin state
    assert_file_not_exists "${FIXTURE_HOME}/.claude" || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.gemini" || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.agents" || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state" || return 1

    # Run 'haws.sh setup' with input:
    # 1. '\n' -> Selects 'Use Default Setup'
    # 2. '\033[A\n' -> Moves up from Cancel/Back to 'Install' and applies
    # 3. 'q' -> Exits post-install Home menu
    local input=$'\n\033[A\nq'
    run_haws_input "${input}" setup || return 1

    # Assert output contains setup progress and completion
    assert_output_contains 'HAWS Setup' || return 1
    assert_output_contains 'HAWS — Preview Install' || return 1
    assert_output_contains 'Installation state completed.' || return 1

    # Assert creation of .haws/state/
    [ -d "${FIXTURE_PROJECT}/.haws/state" ] || fail "Expected .haws/state directory"
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/settings.tsv" 'schema_version' || return 1
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/install.complete" 'schema=1' || return 1
    [ -f "${FIXTURE_PROJECT}/.haws/state/sync-state.tsv" ] || fail "Expected sync-state.tsv after initial sync"

    # Assert Git hook configuration
    local hooks_path
    hooks_path="$(git -C "${FIXTURE_PROJECT}" config --get core.hooksPath 2>/dev/null || true)"
    [ "${hooks_path}" = ".githooks" ] || fail "Expected core.hooksPath to be .githooks, got: ${hooks_path}"

    # Assert secondbrain linkage and pointer reference
    [ -f "${FIXTURE_PROJECT}/secondbrain/USER_PREFERENCES.md" ] || fail "Missing USER_PREFERENCES.md"
    [ -f "${FIXTURE_PROJECT}/secondbrain/ANTI_PATTERNS.md" ] || fail "Missing ANTI_PATTERNS.md"
    assert_output_contains 'Second Brain' || return 1
}

# ==============================================================================
# Scenario 2: Deep Settings & Sub-Menus
# ==============================================================================
test_deep_settings_and_submenus_draft_isolation() {
    populate_full_fixture || return 1

    # Prepare detected environment directories in HOME
    mkdir -p "${FIXTURE_HOME}/.claude" "${FIXTURE_HOME}/.gemini" "${FIXTURE_HOME}/.codex"

    source_haws || return 1
    settings_draft_load || return 1
    _settings_ensure_skill_draft || return 1

    # 1. Assert initial draft isolation before any edits
    assert_file_not_exists "${FIXTURE_PROJECT}/skills/skills.disabled" || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/ai-configs/environments.disabled" || return 1

    # 2. Toggle single skills (caveman, graphify) in draft
    local caveman_id graphify_id
    caveman_id="$(catalog_skills | awk -F '\t' '$3 == "caveman" {print $2; exit}')"
    graphify_id="$(catalog_skills | awk -F '\t' '$3 == "graphify" {print $2; exit}')"
    [ -n "${caveman_id}" ] || fail "Could not find caveman skill id"
    [ -n "${graphify_id}" ] || fail "Could not find graphify skill id"

    # 3. Toggle packs (ponytail multi-skills) in draft
    local ponytail_ids
    ponytail_ids="$(catalog_skills | awk -F '\t' '$1 == "skills/packs/ponytail::skills/packs/ponytail" {print $2}')"
    [ -n "${ponytail_ids}" ] || fail "Could not find ponytail skill ids"

    # Filter out caveman, graphify, and ponytail from draft skills list
    local draft_skills="${HAWS_DRAFT_SKILLS:-}"
    draft_skills="$(_settings_list_without "${draft_skills}" "${caveman_id}")"
    draft_skills="$(_settings_list_without "${draft_skills}" "${graphify_id}")"
    while IFS= read -r pid; do
        [ -n "${pid}" ] || continue
        draft_skills="$(_settings_list_without "${draft_skills}" "${pid}")"
    done <<< "${ponytail_ids}"
    HAWS_DRAFT_SKILLS="${draft_skills}"
    export HAWS_DRAFT_SKILLS

    # 4. Toggle environments (disable claude, gemini, and codex)
    HAWS_DRAFT_ENVIRONMENTS=""
    HAWS_DRAFT_ENVIRONMENTS_TOUCHED=1
    export HAWS_DRAFT_ENVIRONMENTS HAWS_DRAFT_ENVIRONMENTS_TOUCHED

    # Assert DRAFT ISOLATION: state files on disk MUST NOT be created or changed yet
    assert_file_not_exists "${FIXTURE_PROJECT}/skills/skills.disabled" || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/ai-configs/environments.disabled" || return 1

    # 5. Apply settings and verify persistence
    export HAWS_TEST_NO_INTEGRATION=1
    settings_plan_build || return 1
    settings_apply_final >"${OUTPUT_FILE}" 2>&1 || return 1
    unset HAWS_TEST_NO_INTEGRATION

    # Assert persisted device-local skill state
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/skills.disabled" "${caveman_id}" || return 1
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/skills.disabled" "${graphify_id}" || return 1
    while IFS= read -r pid; do
        [ -n "${pid}" ] || continue
        assert_file_contains "${FIXTURE_PROJECT}/.haws/state/skills.disabled" "${pid}" || return 1
    done <<< "${ponytail_ids}"

    # Assert persisted environments.disabled
    assert_file_contains "${FIXTURE_PROJECT}/ai-configs/environments.disabled" "claude" || return 1
    assert_file_contains "${FIXTURE_PROJECT}/ai-configs/environments.disabled" "gemini" || return 1
    assert_file_contains "${FIXTURE_PROJECT}/ai-configs/environments.disabled" "codex" || return 1

    # Verify catalog_skills now marks toggled skills as inactive (active=0)
    local active_caveman active_graphify
    active_caveman="$(catalog_skills | awk -F '\t' -v cid="${caveman_id}" '$2 == cid {print $6}')"
    active_graphify="$(catalog_skills | awk -F '\t' -v gid="${graphify_id}" '$2 == gid {print $6}')"
    [ "${active_caveman}" = "0" ] || fail "Expected caveman to be inactive (0), got: ${active_caveman}"
    [ "${active_graphify}" = "0" ] || fail "Expected graphify to be inactive (0), got: ${active_graphify}"
}

# ==============================================================================
# Scenario 3: Google Antigravity (AGY / Gemini) Sync & Native Config
# ==============================================================================
test_google_antigravity_gemini_sync_and_native_config() {
    populate_full_fixture || return 1

    # Create .gemini in HOME to trigger Antigravity detection
    mkdir -p "${FIXTURE_HOME}/.gemini" "${FIXTURE_HOME}/.claude"

    # Execute haws.sh sync
    run_haws sync || return 1
    assert_output_contains 'Google Antigravity detected' || return 1
    assert_output_contains 'Antigravity Native Config (Dynamic)' || return 1

    # 1. Assert ~/.gemini/config/skills.json exists and is valid JSON
    local skills_json="${FIXTURE_HOME}/.gemini/config/skills.json"
    [ -f "${skills_json}" ] || fail "Expected ${skills_json} to exist"
    if command -v node >/dev/null 2>&1; then
        node -e '
            const fs = require("fs");
            const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
            if (!Array.isArray(data.entries) || data.entries.length === 0) {
                process.exit(1);
            }
            if (!data.entries[0].path) {
                process.exit(1);
            }
        ' "${skills_json}" || fail "${skills_json} is not valid JSON with skill entries"
    else
        grep -F '"entries": [' "${skills_json}" >/dev/null || fail "Malformed skills.json entries"
        grep -F '"path":' "${skills_json}" >/dev/null || fail "Malformed skills.json path"
    fi

    # 2. Assert ~/.gemini/GEMINI.md contains HAWS standard pointer
    local gemini_pointer="${FIXTURE_HOME}/.gemini/GEMINI.md"
    [ -f "${gemini_pointer}" ] || fail "Expected ${gemini_pointer} to exist"
    assert_file_contains "${gemini_pointer}" '<!-- HAWS_GLOBAL_POINTER_START -->' || return 1
    assert_file_contains "${gemini_pointer}" '# HAWS — Human-AI Working Standard' || return 1
    assert_file_contains "${gemini_pointer}" 'core/HAWS.md' || return 1
    assert_file_contains "${gemini_pointer}" 'core/WORK_INSTRUCTIONS.md' || return 1
    assert_file_contains "${gemini_pointer}" 'secondbrain/' || return 1
    assert_file_contains "${gemini_pointer}" '<!-- HAWS_GLOBAL_POINTER_END -->' || return 1

    # 3. Assert Antigravity agent profiles are created in ~/.gemini/config/agents/
    local agents_dir="${FIXTURE_HOME}/.gemini/config/agents"
    [ -d "${agents_dir}" ] || fail "Expected ${agents_dir} to exist"
    local agent
    for agent in organizer researcher frontend-engineer backend-engineer tester; do
        local agent_md="${agents_dir}/${agent}/agent.md"
        [ -f "${agent_md}" ] || fail "Expected agent profile at ${agent_md}"
    done
}

# ==============================================================================
# Scenario 4: Plugin-Containing Skills & Extensions (ponytail, caveman, graphify)
# ==============================================================================
test_plugin_containing_skills_and_extensions() {
    populate_full_fixture || return 1
    source_haws || return 1

    # 1. Verify catalog_skills finds ponytail multi-skills
    local catalog_output
    catalog_output="$(catalog_skills)"
    printf '%s\n' "${catalog_output}" | grep -q 'skills/packs/ponytail.*ponytail-audit' || \
        fail "catalog_skills missing ponytail-audit"
    printf '%s\n' "${catalog_output}" | grep -q 'skills/packs/ponytail.*ponytail-review' || \
        fail "catalog_skills missing ponytail-review"
    printf '%s\n' "${catalog_output}" | grep -q 'skills/packs/ponytail.*ponytail-debt' || \
        fail "catalog_skills missing ponytail-debt"
    printf '%s\n' "${catalog_output}" | grep -q 'skills/packs/ponytail.*ponytail-gain' || \
        fail "catalog_skills missing ponytail-gain"
    printf '%s\n' "${catalog_output}" | grep -q 'skills/packs/ponytail.*ponytail-help' || \
        fail "catalog_skills missing ponytail-help"

    # Also verify caveman and graphify single skills
    printf '%s\n' "${catalog_output}" | grep -q 'skills/standalone/caveman.*caveman' || \
        fail "catalog_skills missing caveman"
    printf '%s\n' "${catalog_output}" | grep -q 'skills/standalone/graphify.*graphify' || \
        fail "catalog_skills missing graphify"

    # 2. Verify internal plugin files are NOT treated as false skill entrypoints
    ! printf '%s\n' "${catalog_output}" | grep -q 'vendor-plugin' || \
        fail "caveman/plugins/vendor-plugin was treated as a false skill entrypoint"
    ! printf '%s\n' "${catalog_output}" | grep -q '\.claude-plugin' || \
        fail ".claude-plugin treated as skill entrypoint"
    ! printf '%s\n' "${catalog_output}" | grep -q 'hooks/' || \
        fail "hooks/ treated as skill entrypoint"
    ! printf '%s\n' "${catalog_output}" | grep -q 'scripts/' || \
        fail "scripts/ treated as skill entrypoint"

    # 3. Verify deduplication: when ~/.codex/plugins/cache/ contains ponytail, HAWS sync skips duplicate link
    mkdir -p "${FIXTURE_HOME}/.codex/plugins/cache/provider/1.0/skills/ponytail" \
        "${FIXTURE_HOME}/.agents/skills"
    printf '%s\n' '---' 'name: ponytail' 'description: Plugin copy of Ponytail.' '---' \
        > "${FIXTURE_HOME}/.codex/plugins/cache/provider/1.0/skills/ponytail/SKILL.md"

    run_haws sync || return 1
    assert_output_contains 'plugin-owned' || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.agents/skills/ponytail" || return 1

    # 4. Verify supporting scripts/hooks in ponytail remain intact and accessible
    [ -f "${FIXTURE_PROJECT}/skills/packs/ponytail/hooks/post-install.sh" ] || \
        fail "Supporting hook post-install.sh missing"
    [ -f "${FIXTURE_PROJECT}/skills/packs/ponytail/scripts/check-versions.js" ] || \
        fail "Supporting script check-versions.js missing"
    [ -f "${FIXTURE_PROJECT}/skills/packs/ponytail/gemini-extension.json" ] || \
        fail "Supporting gemini-extension.json missing"
}

# ==============================================================================
# Scenario 5: Command Surface Verification (status, doctor, hook install)
# ==============================================================================
test_command_surface_status_doctor_hook() {
    populate_full_fixture || return 1
    mkdir -p "${FIXTURE_HOME}/.claude" "${FIXTURE_HOME}/.gemini"

    # Run initial sync so environment is populated
    run_haws sync || return 1

    # 1. Test 'haws.sh status' returns exit code 0 and valid status summary
    run_haws status || return 1
    assert_output_contains 'HAWS Status' || return 1
    assert_output_contains 'Overall:' || return 1
    assert_output_contains 'Skills:' || return 1
    assert_output_contains 'Second Brain:' || return 1
    assert_output_contains 'Auto Update:' || return 1

    # 2. Test 'haws.sh doctor' returns exit code 0 with diagnostic findings
    run_haws doctor || return 1
    assert_output_contains 'HAWS Doctor' || return 1
    assert_output_contains 'FINDINGS' || return 1
    assert_output_contains 'Overall:' || return 1

    # 3. Test 'haws.sh hook install' verifies Git commit-msg hook
    run_haws hook install || return 1
    assert_output_contains 'Git core.hooksPath set to .githooks' || return 1
    assert_output_contains 'commit-msg hook active' || return 1
    local current_hooks
    current_hooks="$(git -C "${FIXTURE_PROJECT}" config --get core.hooksPath 2>/dev/null || true)"
    [ "${current_hooks}" = ".githooks" ] || fail "Expected core.hooksPath to be .githooks, got: ${current_hooks}"
}

# ==============================================================================
# Scenario 6: Clean Full Uninstall
# ==============================================================================
test_clean_full_uninstall() {
    populate_full_fixture || return 1
    mkdir -p "${FIXTURE_HOME}/.claude/skills" "${FIXTURE_HOME}/.gemini" "${FIXTURE_HOME}/.agents/skills"

    # Perform initial sync
    run_haws sync || return 1

    source_haws || return 1
    local claude_pointer="${FIXTURE_HOME}/.claude/CLAUDE.md"
    local gemini_pointer="${FIXTURE_HOME}/.gemini/GEMINI.md"
    [ -f "${claude_pointer}" ] || fail "Missing claude pointer before uninstall"
    [ -f "${gemini_pointer}" ] || fail "Missing gemini pointer before uninstall"

    ownership_list pointers | grep -F $'pointers\tpointer-block\t' >/dev/null || \
        fail "Sync did not record pointer-block ownership"
    assert_file_contains "${claude_pointer}" '<!-- HAWS_GLOBAL_POINTER_START -->' || return 1
    assert_file_contains "${gemini_pointer}" '<!-- HAWS_GLOBAL_POINTER_END -->' || return 1

    # Seed unrelated file in skills and custom notes in secondbrain
    printf '%s\n' 'user-unrelated-content' > "${FIXTURE_HOME}/.claude/skills/unrelated.txt"
    printf '%s\n' '# User Personal Notes' > "${FIXTURE_PROJECT}/secondbrain/my_notes.md"

    # Verify managed skill links exist prior to uninstall
    [ -e "${FIXTURE_HOME}/.claude/skills/caveman" ] || [ -L "${FIXTURE_HOME}/.claude/skills/caveman" ] || \
        fail "Expected managed caveman link in .claude/skills"

    # Run 'haws.sh uninstall' with confirmation 'y'
    if ! HAWS_TEST_KEYS=y run_haws uninstall; then
        echo 'Uninstall of the fresh user-owned integration fixture failed.'
        cat "${OUTPUT_FILE}"
        return 1
    fi
    assert_output_contains 'HAWS Uninstall Preview' || return 1
    assert_output_contains 'Applying uninstall changes' || return 1

    # 1. Assert pointers removed
    assert_file_not_exists "${claude_pointer}" || return 1
    assert_file_not_exists "${gemini_pointer}" || return 1
    ! ownership_list pointers | grep -F $'pointers\tpointer-block\t' >/dev/null || \
        fail "Uninstall retained pointer-block ownership records"

    # 2. Assert managed skill links removed
    assert_file_not_exists "${FIXTURE_HOME}/.claude/skills/caveman" || return 1

    # 3. Assert unrelated files and secondbrain contents are preserved
    assert_file_contains "${FIXTURE_HOME}/.claude/skills/unrelated.txt" 'user-unrelated-content' || return 1
    assert_file_contains "${FIXTURE_PROJECT}/secondbrain/my_notes.md" 'User Personal Notes' || return 1

    # 4. Run 'haws.sh doctor' post-uninstall and verify clean detached classification without crashes
    run_haws doctor || return 1
    assert_output_contains 'HAWS Doctor' || return 1
    assert_output_contains 'Overall:' || return 1

    # A fresh launch after full removal must return to Setup, not Home.
    run_haws_input 'q' || return 1
    assert_output_contains 'HAWS Setup' || return 1
    if grep -F 'HAWS Home' "${OUTPUT_FILE}" >/dev/null; then
        fail "A bare launch after full uninstall entered Home"
    fi
}

test_stateful_fresh_setup_update_uninstall_and_bare_launch() {
    populate_full_fixture || return 1
    local brain="${FIXTURE_PROJECT}/secondbrain"
    local brain_remote="${FIXTURE_ROOT}/stateful-brain.git"
    printf '%s\n' '# Fixture Workflow' > "${brain}/WORKFLOW.md" || return 1
    git init --bare -q "${brain_remote}" || return 1
    git -C "${brain}" init -q -b main 2>/dev/null || git -C "${brain}" init -q || return 1
    git -C "${brain}" checkout -q -B main || return 1
    git -C "${brain}" config user.name HAWS-Test
    git -C "${brain}" config user.email test@example.invalid
    git -C "${brain}" add . || return 1
    git -C "${brain}" commit -qm 'fixture Second Brain baseline' || return 1
    git -C "${brain}" remote add origin "file://${brain_remote}" || return 1
    git -C "${brain}" push -q -u origin main || return 1
    git --git-dir="${brain_remote}" symbolic-ref HEAD refs/heads/main || return 1

    export HAWS_TEST_NO_INTEGRATION=1
    if ! run_haws_input $'\n\033[A\nq'; then
        echo 'Fresh launch setup/install flow exited unsuccessfully.'
        cat "${OUTPUT_FILE}"
        return 1
    fi
    assert_output_contains 'HAWS Setup' || return 1
    assert_output_contains 'HAWS — Preview Install' || return 1
    assert_output_contains 'HAWS Home' || return 1
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/install.complete" 'schema=1' || return 1
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/settings.tsv" \
        $'auto_update_brain\ton' || return 1

    # Change Skills Auto Update, accept the Update preview, and run the update.
    local down=$'\033[B' up=$'\033[A'
    local update_input="${down}${down}${down}${down}\n"
    update_input+="\nq"
    update_input+="${down}${down}${down}${down}${down}\n${up}\nq"
    if ! run_haws_input "${update_input}" settings; then
        echo 'Settings Update/Update flow exited unsuccessfully.'
        cat "${OUTPUT_FILE}"
        return 1
    fi
    assert_output_contains 'HAWS — Preview Update' || {
        echo 'Settings navigation did not reach Update preview.'
        cat "${OUTPUT_FILE}"
        return 1
    }
    assert_output_contains 'Update completed.' || {
        echo 'Update confirmation is missing from the completed lifecycle.'
        cat "${OUTPUT_FILE}"
        return 1
    }
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/settings.tsv" \
        $'auto_update_skills\toff' || return 1

    if ! HAWS_TEST_KEYS=y run_haws uninstall; then
        echo 'Uninstall in the stateful lifecycle fixture failed.'
        cat "${OUTPUT_FILE}"
        return 1
    fi
    assert_output_contains 'Applying uninstall changes' || return 1
    assert_file_not_exists "${FIXTURE_PROJECT}/.haws/state/install.complete" || return 1
    assert_file_contains "${FIXTURE_PROJECT}/.haws/state/settings.tsv" \
        $'auto_update_skills\toff' || {
        echo 'Uninstall did not preserve the saved Skills Auto Update setting.'
        cat "${OUTPUT_FILE}"
        return 1
    }

    run_haws_input 'q' || return 1
    assert_output_contains 'HAWS Setup' || return 1
    assert_output_contains 'Use Previous Settings' || return 1
    local expected_post_uninstall_skills=$'auto_update_skills\toff'
    if ! grep -F "${expected_post_uninstall_skills}" \
        "${FIXTURE_PROJECT}/.haws/state/settings.tsv" >/dev/null; then
        echo 'Post-uninstall bare launch did not retain the saved Skills Auto Update value.'
        cat "${FIXTURE_PROJECT}/.haws/state/settings.tsv"
        return 1
    fi
}

test_fresh_exact_user_integrations_remain_unowned() {
    populate_full_fixture || return 1
    mkdir -p "${FIXTURE_HOME}/.claude/agents" \
        "${FIXTURE_HOME}/.claude/commands" "${FIXTURE_HOME}/.claude/skills" \
        "${FIXTURE_HOME}/.gemini/config" || return 1
    source_haws || return 1
    settings_save auto_update_all off off || return 1
    local exact_agent="${FIXTURE_HOME}/.claude/agents/organizer.md"
    local command_file="${FIXTURE_HOME}/.claude/commands/demo-one.md"
    local skill_link="${FIXTURE_HOME}/.claude/skills/demo-one"
    local skill_source="${FIXTURE_PROJECT}/skills/custom/demo-one"
    local gemini_skills="${FIXTURE_HOME}/.gemini/config/skills.json"
    local gemini_path="${FIXTURE_PROJECT}/skills/custom/demo-one"
    cp "${FIXTURE_PROJECT}/agents/organizer.md" "${exact_agent}" || return 1
    create_test_directory_link "${skill_source}" "${skill_link}" || {
        echo 'Could not create the fresh user-owned skill symlink fixture.'
        return 1
    }
    cat > "${command_file}" <<'EOF'
---
description: Fixture single skill.
---
Execute the demo-one skill workflow defined in ~/.claude/skills/demo-one/SKILL.md.
EOF
    printf '{\n  "entries": [\n    { "path": "%s" }\n  ]\n}\n' \
        "${gemini_path}" > "${gemini_skills}" || return 1
    git -C "${FIXTURE_PROJECT}" config --local core.hooksPath .githooks || return 1
    local agent_before command_before gemini_before
    agent_before="$(cat "${exact_agent}")"
    command_before="$(cat "${command_file}")"
    gemini_before="$(cat "${gemini_skills}")"

    run_haws sync || return 1
    source_haws || return 1
    for path in "${exact_agent}" "${command_file}"; do
        if ownership_list agents | grep -F "${path}" >/dev/null; then
            echo "Fresh exact user-owned integration was adopted: ${path}"
            ownership_list agents | grep -F "${path}"
            cat "${OUTPUT_FILE}"
            return 1
        fi
    done
    if ownership_list skills | grep -F "${skill_link}" >/dev/null; then
        echo "Fresh user-created exact skill link was adopted: ${skill_link}"
        ownership_list skills | grep -F "${skill_link}"
        cat "${OUTPUT_FILE}"
        return 1
    fi
    [ "$(cat "${exact_agent}")" = "${agent_before}" ] || return 1
    [ "$(cat "${command_file}")" = "${command_before}" ] || return 1
    if grep -F "${gemini_path}" "${FIXTURE_PROJECT}/.haws/state/gemini-skills-ownership.json" \
        >/dev/null 2>&1; then
        echo 'Fresh exact user-owned Gemini entry was adopted.'
        cat "${FIXTURE_PROJECT}/.haws/state/gemini-skills-ownership.json"
        return 1
    fi
    [ "$(git -C "${FIXTURE_PROJECT}" config --local --get core.hooksPath)" = .githooks ] || return 1
    if ownership_list hooks | grep -F "${FIXTURE_PROJECT}/.githooks" >/dev/null; then
        echo 'Fresh user core.hooksPath was incorrectly recorded as HAWS-owned.'
        ownership_list hooks | grep -F "${FIXTURE_PROJECT}/.githooks"
        return 1
    fi
    [ "$(cat "${gemini_skills}")" != "${gemini_before}" ] || {
        echo 'Sync should merge generated Gemini entries while retaining the user entry.'
        return 1
    }
    HAWS_GEMINI_SKILLS_FILE="${gemini_skills}" \
        HAWS_GEMINI_SKILLS_SUFFIX='skills/custom/demo-one' \
        node -e 'const fs=require("node:fs");const data=JSON.parse(fs.readFileSync(process.env.HAWS_GEMINI_SKILLS_FILE,"utf8"));if(!data.entries.some(entry=>typeof entry.path==="string"&&entry.path.endsWith("/"+process.env.HAWS_GEMINI_SKILLS_SUFFIX)))process.exit(1);' || return 1

    if ! { [ -L "${skill_link}" ] && [ "$(readlink "${skill_link}" 2>/dev/null || true)" = "${skill_source}" ]; } &&
        ! { [ -d "${skill_link}" ] && [ "${skill_link}" -ef "${skill_source}" ]; }; then
        echo 'Sync did not preserve the fresh user-owned skill symlink.'
        printf 'link=%s source=%s exists=%s symlink=%s directory=%s target=%s\n' \
            "${skill_link}" "${skill_source}" \
            "$([ -e "${skill_link}" ] && echo yes || echo no)" \
            "$([ -L "${skill_link}" ] && echo yes || echo no)" \
            "$([ -d "${skill_link}" ] && echo yes || echo no)" \
            "$(readlink "${skill_link}" 2>/dev/null || true)"
        ls -ld "${skill_link}" "${skill_source}" 2>&1 || true
        cat "${OUTPUT_FILE}"
        return 1
    fi
    if ! HAWS_TEST_KEYS=y run_haws uninstall; then
        echo 'Uninstall of the fresh user-owned integration fixture failed.'
        cat "${OUTPUT_FILE}"
        return 1
    fi
    assert_file_contains "${exact_agent}" 'name: organizer' || return 1
    assert_file_contains "${command_file}" 'Execute the demo-one skill workflow' || return 1
    { [ -L "${skill_link}" ] && [ "$(readlink "${skill_link}" 2>/dev/null || true)" = "${skill_source}" ]; } ||
        { [ -d "${skill_link}" ] && [ "${skill_link}" -ef "${skill_source}" ]; } || {
        echo 'Uninstall removed the fresh user-owned skill symlink.'
        cat "${OUTPUT_FILE}"
        return 1
    }
    [ "$(git -C "${FIXTURE_PROJECT}" config --local --get core.hooksPath)" = .githooks ] || return 1
    HAWS_GEMINI_SKILLS_FILE="${gemini_skills}" \
        HAWS_GEMINI_SKILLS_SUFFIX='skills/custom/demo-one' \
        node -e 'const fs=require("node:fs");const data=JSON.parse(fs.readFileSync(process.env.HAWS_GEMINI_SKILLS_FILE,"utf8"));if(!data.entries.some(entry=>typeof entry.path==="string"&&entry.path.endsWith("/"+process.env.HAWS_GEMINI_SKILLS_SUFFIX)))process.exit(1);' || return 1
}

test_sync_adopts_frozen_legacy_artifacts_and_uninstall_removes_them() {
    populate_full_fixture || return 1
    mkdir -p "${FIXTURE_HOME}/.claude/agents" "${FIXTURE_HOME}/.claude/skills" \
        "${FIXTURE_HOME}/.gemini/config" "${FIXTURE_PROJECT}/.haws/state" || return 1
    source_haws || return 1
    settings_save auto_update_all off off || return 1

    # Frozen fixture uses the v1 manifest format and committed artifacts from
    # 7846259; it does not create a current Sync result and strip its ledger.
    git -C "${PROJECT_ROOT}" show 7846259:agents/organizer.md \
        > "${FIXTURE_PROJECT}/agents/organizer.md" || return 1
    git -C "${PROJECT_ROOT}" show 7846259:skills/custom/keyboard-layout-fixer/SKILL.md \
        > "${FIXTURE_PROJECT}/skills/custom/keyboard-layout-fixer.SOURCE" || return 1
    git -C "${PROJECT_ROOT}" show 7846259:.githooks/commit-msg \
        > "${FIXTURE_PROJECT}/.githooks/commit-msg" || return 1
    mkdir -p "${FIXTURE_PROJECT}/skills/custom/keyboard-layout-fixer" || return 1
    mv "${FIXTURE_PROJECT}/skills/custom/keyboard-layout-fixer.SOURCE" \
        "${FIXTURE_PROJECT}/skills/custom/keyboard-layout-fixer/SKILL.md" || return 1
    git -C "${FIXTURE_PROJECT}" add agents/organizer.md \
        skills/custom/keyboard-layout-fixer/SKILL.md .githooks/commit-msg || return 1
    git -C "${FIXTURE_PROJECT}" commit -qm 'freeze legacy artifacts from 7846259' || return 1

    local legacy_agent="${FIXTURE_HOME}/.claude/agents/organizer.md"
    local legacy_skill="${FIXTURE_PROJECT}/skills/custom/keyboard-layout-fixer"
    local legacy_skill_link="${FIXTURE_HOME}/.claude/skills/keyboard-layout-fixer"
    local gemini_skills="${FIXTURE_HOME}/.gemini/config/skills.json"
    local gemini_manifest="${FIXTURE_PROJECT}/.haws/state/gemini-skills-ownership.json"
    local user_gemini_path="/user-owned/legacy-fixture-entry"
    [ ! -e "${gemini_manifest}" ] || return 1
    if ! ln -s "${FIXTURE_PROJECT}/agents/organizer.md" "${legacy_agent}" 2>/dev/null; then
        cp "${FIXTURE_PROJECT}/agents/organizer.md" "${legacy_agent}" || return 1
    fi
    create_test_directory_link "${legacy_skill}" "${legacy_skill_link}" || {
        echo 'Could not create the legacy skill symlink fixture.'
        return 1
    }
    printf 'schema=1\tcompleted_at=legacy-7846259\n' \
        > "${FIXTURE_PROJECT}/.haws/state/install.complete" || return 1
    printf 'skill:legacy-fixture\tkeyboard-layout-fixer\nagent:organizer\n' \
        > "${FIXTURE_HOME}/.haws_manifest" || return 1
    printf '{\n  "entries": [\n    { "path": "%s" },\n    { "path": "%s" }\n  ]\n}\n' \
        "${legacy_skill}" "${user_gemini_path}" > "${gemini_skills}" || return 1
    git -C "${FIXTURE_PROJECT}" config --local core.hooksPath .githooks || return 1

    run_haws sync || return 1
    source_haws || return 1
    ownership_list agents | grep -F "${legacy_agent}" >/dev/null || {
        echo 'Exact legacy Claude agent was not adopted from the frozen 7846259 fixture.'
        cat "${OUTPUT_FILE}"
        return 1
    }
    if [ ! -e "${legacy_skill_link}" ] && [ ! -L "${legacy_skill_link}" ]; then
        echo 'Exact legacy skill link was not preserved/adopted during Sync.'
        cat "${OUTPUT_FILE}"
        return 1
    fi
    ownership_list skills | grep -F "${legacy_skill_link}" >/dev/null || return 1
    [ -f "${gemini_manifest}" ] || return 1
    ownership_list environments | grep -F "${gemini_skills}" >/dev/null || return 1
    ownership_list hooks | grep -F "${FIXTURE_PROJECT}/.githooks" >/dev/null || return 1

    local first_agent_record second_agent_record
    first_agent_record="$(ownership_list agents | grep -F "${legacy_agent}")" || return 1
    run_haws sync || return 1
    source_haws || return 1
    second_agent_record="$(ownership_list agents | grep -F "${legacy_agent}")" || return 1
    [ "${second_agent_record}" = "${first_agent_record}" ] || return 1
    if grep -F '[ADOPTED] Exact legacy Claude Agent' "${OUTPUT_FILE}" >/dev/null; then
        echo 'A previously adopted Claude agent was adopted a second time.'
        cat "${OUTPUT_FILE}"
        return 1
    fi

    HAWS_TEST_KEYS=y run_haws uninstall || return 1
    assert_file_not_exists "${legacy_agent}" || return 1
    assert_file_not_exists "${legacy_skill_link}" || return 1
    assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest" || return 1
    assert_file_not_exists "${gemini_manifest}" || return 1
    [ -z "$(git -C "${FIXTURE_PROJECT}" config --local --get core.hooksPath 2>/dev/null || true)" ] || return 1
    HAWS_GEMINI_SKILLS_FILE="${gemini_skills}" \
        HAWS_GEMINI_LEGACY_SUFFIX='skills/custom/keyboard-layout-fixer' \
        HAWS_GEMINI_USER_SUFFIX='user-owned/legacy-fixture-entry' \
        node -e 'const fs=require("node:fs");const data=JSON.parse(fs.readFileSync(process.env.HAWS_GEMINI_SKILLS_FILE,"utf8"));if(data.entries.some(entry=>typeof entry.path==="string"&&entry.path.endsWith("/"+process.env.HAWS_GEMINI_LEGACY_SUFFIX)))process.exit(1);if(!data.entries.some(entry=>typeof entry.path==="string"&&entry.path.endsWith("/"+process.env.HAWS_GEMINI_USER_SUFFIX)))process.exit(2);' || return 1
}

# ==============================================================================
# Runner
# ==============================================================================
trap cleanup_fixture EXIT

if [ -n "${HAWS_LIFECYCLE_TEST_ONLY:-}" ]; then
    run_test "${HAWS_LIFECYCLE_TEST_ONLY}"
else
    run_test test_zero_install_and_setup_flow
    run_test test_deep_settings_and_submenus_draft_isolation
    run_test test_google_antigravity_gemini_sync_and_native_config
    run_test test_plugin_containing_skills_and_extensions
    run_test test_command_surface_status_doctor_hook
    run_test test_fresh_exact_user_integrations_remain_unowned
    run_test test_sync_adopts_frozen_legacy_artifacts_and_uninstall_removes_them
    run_test test_clean_full_uninstall
    run_test test_stateful_fresh_setup_update_uninstall_and_bare_launch
fi

echo "CLI lifecycle and plugins E2E tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
