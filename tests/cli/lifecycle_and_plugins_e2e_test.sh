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
    env HOME="${FIXTURE_HOME}" CODEX_HOME="${FIXTURE_HOME}/.codex" \
        HAWS_REPO_DIR="${FIXTURE_PROJECT}" HAWS_STATE_DIR="${FIXTURE_PROJECT}/.haws/state" \
        HAWS_TEST_KEYS="${HAWS_TEST_KEYS:-}" \
        HAWS_CALL_LOG="${CALL_LOG:-}" PATH="${PATH}" \
        bash "${FIXTURE_PROJECT}/haws.sh" "$@" >"${OUTPUT_FILE}" 2>&1
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

    # 4. Toggle environments (disable claude, gemini, agents)
    HAWS_DRAFT_ENVIRONMENTS="cursor"
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

    # Assert persisted skills.disabled
    assert_file_contains "${FIXTURE_PROJECT}/skills/skills.disabled" "${caveman_id}" || return 1
    assert_file_contains "${FIXTURE_PROJECT}/skills/skills.disabled" "${graphify_id}" || return 1
    while IFS= read -r pid; do
        [ -n "${pid}" ] || continue
        assert_file_contains "${FIXTURE_PROJECT}/skills/skills.disabled" "${pid}" || return 1
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
    assert_file_contains "${gemini_pointer}" 'secondbrain/USER_PREFERENCES.md' || return 1
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

    # Seed ownership records for global pointers to ensure full lifecycle coverage
    source_haws || return 1
    local claude_pointer="${FIXTURE_HOME}/.claude/CLAUDE.md"
    local gemini_pointer="${FIXTURE_HOME}/.gemini/GEMINI.md"
    [ -f "${claude_pointer}" ] || fail "Missing claude pointer before uninstall"
    [ -f "${gemini_pointer}" ] || fail "Missing gemini pointer before uninstall"

    local claude_hash gemini_hash
    claude_hash="$(_haws_sha256 "${claude_pointer}")"
    gemini_hash="$(_haws_sha256 "${gemini_pointer}")"
    ownership_record environments generated-file "${claude_pointer}" \
        "${FIXTURE_PROJECT}/core/HAWS.md" "${claude_hash}" || return 1
    ownership_record environments generated-file "${gemini_pointer}" \
        "${FIXTURE_PROJECT}/core/HAWS.md" "${gemini_hash}" || return 1

    # Seed unrelated file in skills and custom notes in secondbrain
    printf '%s\n' 'user-unrelated-content' > "${FIXTURE_HOME}/.claude/skills/unrelated.txt"
    printf '%s\n' '# User Personal Notes' > "${FIXTURE_PROJECT}/secondbrain/my_notes.md"

    # Verify managed skill links exist prior to uninstall
    [ -e "${FIXTURE_HOME}/.claude/skills/caveman" ] || [ -L "${FIXTURE_HOME}/.claude/skills/caveman" ] || \
        fail "Expected managed caveman link in .claude/skills"

    # Run 'haws.sh uninstall' with confirmation 'y'
    HAWS_TEST_KEYS=y run_haws uninstall || return 1
    assert_output_contains 'HAWS Uninstall Preview' || return 1
    assert_output_contains 'Applying uninstall changes' || return 1

    # 1. Assert pointers removed
    assert_file_not_exists "${claude_pointer}" || return 1
    assert_file_not_exists "${gemini_pointer}" || return 1

    # 2. Assert managed skill links removed
    assert_file_not_exists "${FIXTURE_HOME}/.claude/skills/caveman" || return 1

    # 3. Assert unrelated files and secondbrain contents are preserved
    assert_file_contains "${FIXTURE_HOME}/.claude/skills/unrelated.txt" 'user-unrelated-content' || return 1
    assert_file_contains "${FIXTURE_PROJECT}/secondbrain/my_notes.md" 'User Personal Notes' || return 1

    # 4. Run 'haws.sh doctor' post-uninstall and verify clean detached classification without crashes
    run_haws doctor || return 1
    assert_output_contains 'HAWS Doctor' || return 1
    assert_output_contains 'Overall:' || return 1
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
    run_test test_clean_full_uninstall
fi

echo "CLI lifecycle and plugins E2E tests: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
