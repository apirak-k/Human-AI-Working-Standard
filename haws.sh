#!/usr/bin/env bash
# ==============================================================================
# HAWS (Human-AI Working Standard) Universal Command Engine
# Standalone, Self-Contained CLI: Sync, Install, Update, Status, and Diagnostics
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="${1:-menu}"
BARE_LAUNCH="${HAWS_BARE_LAUNCH:-0}"
[ "$#" -eq 0 ] && BARE_LAUNCH=1
HAWS_WINDOW_TITLE="HAWS — Human-AI Working Standard"

haws_set_terminal_title() {
    [ -t 1 ] || return 0
    printf '\033]0;%s\007' "${HAWS_WINDOW_TITLE}"
}

# Native Codex agent installation is also available without a global sync.
run_codex_agents() {
    if ! command -v node >/dev/null 2>&1; then
        echo "[ERROR] Node.js is required for native Codex agent profiles." >&2
        return 1
    fi
    node "${SCRIPT_DIR}/ai-configs/codex/agents.mjs" "$@"
}


_health_repo() {
    local repo
    repo="$(printenv HAWS_REPO_DIR 2>/dev/null || true)"
    [ -n "$repo" ] || repo="$SCRIPT_DIR"
    printf '%s\n' "$repo"
}

_health_state() {
    _haws_state_dir
}

_health_add() {
    local level="$1"
    local check="$2"
    local detail="$3"
    HAWS_HEALTH_FINDINGS="$HAWS_HEALTH_FINDINGS$level"$'\t'"$check"$'\t'"$detail"$'\n'
}

_health_env_path() {
    case "$1" in
        claude) printf '%s/.claude\n' "$HOME" ;;
        gemini) printf '%s/.gemini\n' "$HOME" ;;
        agents) printf '%s/.agents\n' "$HOME" ;;
        *) printf '%s/.%s\n' "$HOME" "$1" ;;
    esac
}

health_classify() {
    if printf '%s' "$HAWS_HEALTH_FINDINGS" | grep -q $'^Blocked\t'; then
        printf '%s\n' Blocked
    elif printf '%s' "$HAWS_HEALTH_FINDINGS" | grep -q $'^Attention\t'; then
        printf '%s\n' Attention
    else
        printf '%s\n' Ready
    fi
}

_health_collect() {
    HAWS_HEALTH_FINDINGS=""
    if settings_load; then
        _health_add Ready Settings "settings.tsv parsed successfully"
    else
        _health_add Blocked Settings "settings.tsv could not be parsed"
    fi
    if disabled_environments_load; then
        _health_add Ready "AI Environments" "environments.disabled parsed successfully"
    else
        _health_add Blocked "AI Environments" "environments.disabled could not be parsed"
    fi
    if load_disabled_skills; then
        _health_add Ready Skills "skills.disabled parsed successfully"
    else
        _health_add Blocked Skills "skills.disabled could not be parsed"
    fi

    local env env_path
    for env in claude gemini agents; do
        env_path="$(_health_env_path "$env")"
        if [ -n "${DISABLED_ENVS[$env]-}" ]; then
            _health_add Ready "AI Environments" "$env disabled by local configuration"
        elif [ -d "$env_path" ]; then
            _health_add Ready "AI Environments" "$env directory detected at $env_path"
        else
            _health_add Ready "AI Environments" "$env not detected"
        fi
    done

    local kind path source fingerprint verify_status
    while IFS=$'\t' read -r kind path source fingerprint _ ||
        [ -n "$kind" ]; do
        [ -n "$kind" ] || continue
        if ownership_verify "$kind"$'\t'"$path"$'\t'"$source"$'\t'"$fingerprint"; then
            _health_add Ready "AI Environment ownership" "$kind $path matches its recorded fingerprint"
        else
            verify_status="$?"
            if [ "$verify_status" -eq 2 ]; then
                _health_add Blocked "AI Environment ownership" "$kind $path is dirty or unsafe"
            else
                _health_add Attention "AI Environment ownership" "$kind $path differs from its recorded fingerprint"
            fi
        fi
    done < <(ownership_list environments)

    local repo="$(_health_repo)"
    local source_rows=0
    local source_id source_path source_url source_revision
    local -A health_source_paths=()
    while IFS=$'\t' read -r source_id source_path source_url source_revision _ ||
        [ -n "$source_id" ]; do
        [ -n "$source_id" ] || continue
        health_source_paths["$source_id"]="$source_path"
        [ "$source_url" = local ] && continue
        source_rows=1
        if [ -d "$repo/$source_path" ]; then
            _health_add Ready Sources "$source_id available at $source_path ($source_revision)"
        else
            _health_add Attention Sources "$source_id missing at $source_path"
        fi
    done < <(_catalog_skill_sources)
    [ "$source_rows" -eq 1 ] ||
        _health_add Ready Sources "no registered sources"

    HAWS_HEALTH_SKILLS_ACTIVE=0
    HAWS_HEALTH_SKILLS_TOTAL=0
    local skill_rows=0
    local logical_id display description skill_source entrypoint active
    local skill_source_path
    while IFS=$'\t' read -r skill_source logical_id display description entrypoint active _ ||
        [ -n "$logical_id" ]; do
        [ -n "$logical_id" ] || continue
        HAWS_HEALTH_SKILLS_TOTAL=$((HAWS_HEALTH_SKILLS_TOTAL + 1))
        [ "$active" = 1 ] || continue
        HAWS_HEALTH_SKILLS_ACTIVE=$((HAWS_HEALTH_SKILLS_ACTIVE + 1))
        skill_rows=1
        skill_source_path="${health_source_paths["$skill_source"]:-}"
        if [ -n "$skill_source_path" ] && [ -s "$repo/$skill_source_path/$entrypoint" ]; then
            _health_add Ready Skills "$display entrypoint is present"
        else
            _health_add Blocked Skills "$display entrypoint is missing"
        fi
    done < <(catalog_skills)
    [ "$skill_rows" -eq 1 ] ||
        _health_add Ready Skills "no active skills"

    return 0
}

_health_last_sync() {
    local state="$(_health_state)"
    local file="$state/sync-state.tsv"
    [ -f "$file" ] || {
        printf '%s\n' Never
        return 0
    }
    local result timestamp
    result="$(tail -n 1 "$file" 2>/dev/null | awk -F $'\t' '{print $3}')"
    timestamp="$(tail -n 1 "$file" 2>/dev/null | awk -F $'\t' '{print $1}')"
    [ -n "$result" ] || result=Never
    if [ -n "$timestamp" ]; then
        printf '%s · %s\n' "$result" "${timestamp//T/ }"
    else
        printf '%s\n' "$result"
    fi
}

_health_print_details() {
    local section="$1"
    local level check detail
    printf '%s\n' "$section"
    while IFS=$'\t' read -r level check detail _ || [ -n "$level" ]; do
        [ "$check" = "$section" ] || continue
        printf '%s\t%s\t%s\n' "$level" "$check" "$detail"
    done <<< "$HAWS_HEALTH_FINDINGS"
}

_health_collect_hooks() {
    local repo hook_path
    repo="$(_health_repo)"
    if hook_path="$(git -C "$repo" config --get core.hooksPath 2>/dev/null)"; then
        if [ -z "$hook_path" ]; then
            _health_add Ready Hooks "core.hooksPath is not configured"
        elif [ -d "$repo/$hook_path" ] || [ -d "$hook_path" ]; then
            _health_add Ready Hooks "core.hooksPath points to $hook_path"
        else
            _health_add Attention Hooks "core.hooksPath points to missing $hook_path"
        fi
    else
        _health_add Ready Hooks "core.hooksPath is not configured"
    fi
}

_health_print_summary() {
    local ai_summary="" env env_path label
    for env in claude gemini agents; do
        env_path="$(_health_env_path "$env")"
        case "$env" in claude) label=Claude ;; gemini) label=Gemini ;; agents) label=Codex ;; esac
        if [ -n "${DISABLED_ENVS[$env]-}" ]; then
            label+=" (off)"
        elif [ -d "$env_path" ]; then
            label+=" (on)"
        else
            label+=" (not found)"
        fi
        [ -n "$ai_summary" ] && ai_summary+=", "
        ai_summary+="$label"
    done
    printf '  Overall       : %s\n' "$(health_classify)"
    printf '  AI            : %s\n' "$ai_summary"
    printf '  Skills        : %s / %s active\n' "$HAWS_HEALTH_SKILLS_ACTIVE" "$HAWS_HEALTH_SKILLS_TOTAL"
    printf '  Last Sync     : %s\n' "$(_health_last_sync)"
    printf '  Second Brain  : %s\n' "$(_second_brain_status_label)"
    printf '  Auto Update   : %s\n' "$(_haws_toggle_label "${HAWS_AUTO_UPDATE:-on}")"
}

_health_print_findings() {
    local level check detail display_level short_detail
    local section total ready issues issue_level issue_detail
    local sections=("Settings" "AI Environments" "AI Environment ownership" "Sources" "Skills" "Hooks")
    for section in "${sections[@]}"; do
        total=0; ready=0; issues=0; issue_level=""; issue_detail=""
        while IFS=$'\t' read -r level check detail _ || [ -n "$level" ]; do
            [ "$check" = "$section" ] || continue
            total=$((total + 1))
            if [ "$level" = Ready ]; then
                ready=$((ready + 1))
            else
                issues=$((issues + 1))
                [ -n "$issue_level" ] || issue_level="$level"
                [ -n "$issue_detail" ] || issue_detail="$detail"
            fi
        done <<< "$HAWS_HEALTH_FINDINGS"
        [ "$total" -gt 0 ] || continue
        if [ "$issues" -eq 0 ]; then
            case "$section" in
                Settings) short_detail="settings ready" ;;
                "AI Environments") short_detail="${total} environment checks passed" ;;
                "AI Environment ownership") short_detail="${total} managed item(s) verified" ;;
                Sources) short_detail="${total} source(s) available" ;;
                Skills) short_detail="${total} active skill check(s) passed" ;;
                Hooks) short_detail="commit-msg active" ;;
            esac
            printf '  [PASS] %-20s - %s\n' "$section" "$short_detail"
        else
            case "$issue_level" in
                Blocked) display_level=BLOCKED ;;
                *) display_level=WARN ;;
            esac
            short_detail="$issue_detail"
            if [ "${#short_detail}" -gt 72 ]; then short_detail="${short_detail:0:72}..."; fi
            printf '  [%s] %-20s - %s\n' "$display_level" "$section" "$short_detail"
            [ "$issues" -gt 1 ] && printf '  [INFO] %-20s - %s other issue(s)\n' "$section" "$((issues - 1))"
        fi
    done
}

_haws_wait_for_result() {
    HAWS_RESULT_NAVIGATION=home
    export HAWS_RESULT_NAVIGATION
    [ "${HAWS_INTERACTIVE_RESULT:-0}" = 1 ] || return 0
    [ -t 0 ] && [ -t 1 ] || return 0
    printf '\n[Q] Return to Home\n[Any key] Exit CLI\n'
    local result_key=""
    IFS= read -rsn1 result_key || true
    printf '\n'
    case "${result_key}" in
        q|Q) HAWS_RESULT_NAVIGATION=home ;;
        *) HAWS_RESULT_NAVIGATION=exit ;;
    esac
    export HAWS_RESULT_NAVIGATION
}

status_run() {
    local details=0 arg
    for arg in "$@"; do
        [ "$arg" = --details ] && details=1
    done
    _health_collect
    local overall
    overall="$(health_classify)"
    printf '%s\n' "HAWS Status"
    printf 'Overall: %s\n' "$overall"
    printf 'Skills: %s / %s active\n' "$HAWS_HEALTH_SKILLS_ACTIVE" "$HAWS_HEALTH_SKILLS_TOTAL"
    printf 'Last sync: %s\n' "$(_health_last_sync)"
    printf 'Second Brain: %s\n' "$(_second_brain_status_label)"
    printf 'Auto Update: %s\n' "$HAWS_AUTO_UPDATE"
    if [ "$details" -eq 1 ]; then
        _health_print_details "AI Environments"
        _health_print_details Sources
        _health_print_details Skills
    fi
    return 0
}

doctor_run() {
    local json=0 arg
    for arg in "$@"; do
        [ "$arg" = --json ] && json=1
    done
    if [ "$json" -eq 0 ]; then
        echo ""
        echo "============================================================="
        echo "                         HAWS Doctor"
        echo "============================================================="
        echo ""
        echo "[*] Running diagnostics, please wait..."
    fi
    _health_collect
    _health_collect_hooks
    local overall
    overall="$(health_classify)"
    if [ "$json" -eq 1 ]; then
        printf '{"status":"%s"}\n' "$overall"
    else
        echo ""
        echo "CURRENT STATUS"
        printf 'Overall: %s\n' "$overall"
        echo ""
        echo "FINDINGS"
        _health_print_findings
    fi
    [ "$overall" != Blocked ]
}

run_status() {
    status_run "$@"
}

run_doctor() {
    doctor_run "$@"
}

legacy_run_status() {
    local gemini_dir="${HOME}/.gemini/config/skills"
    local claude_dir="${HOME}/.claude/skills"
    local codex_dir="${HOME}/.agents/skills"
    local manifest="${HOME}/.haws_manifest"

    local gemini_json="${HOME}/.gemini/config/skills.json"
    local gemini_count=0
    local claude_count=0
    local codex_count=0
    local manifest_count=0

    [ -d "${claude_dir}" ] && claude_count=$(find "${claude_dir}" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | wc -l)
    [ -d "${codex_dir}" ] && codex_count=$(find "${codex_dir}" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | wc -l)
    [ -f "${manifest}" ] && manifest_count=$(grep -c '^skill:' "${manifest}" || true)

    local est_tokens=0
    local py_cmd=""
    for candidate in python3 python3.11 python3.12 python3.14 py python; do
        if command -v "${candidate}" &>/dev/null && "${candidate}" -c "import sys" &>/dev/null; then
            py_cmd="${candidate}"
            break
        fi
    done

    if [ -n "${py_cmd}" ]; then
        local stat_res
        stat_res=$($py_cmd -c "
import glob, os, re, json
gemini_json = os.path.expanduser('~/.gemini/config/skills.json')
gemini_dir = os.path.expanduser('~/.gemini/config/skills')
unique_skills = set()

def check_skill(dp, default_name):
    for mname in ('SKILL.md', 'skill.md'):
        mf = os.path.join(dp, mname)
        if os.path.isfile(mf):
            sname = default_name
            try:
                with open(mf, 'r', encoding='utf-8') as sf:
                    for line in sf:
                        m = re.match(r'^[ \t]*name:[ \t]*[\'\"]?([^\'\"#\r\n]+)', line)
                        if m:
                            sname = m.group(1).strip()
                            break
            except: pass
            unique_skills.add(sname)
            return True
    return False

if os.path.isfile(gemini_json):
    try:
        with open(gemini_json, 'r', encoding='utf-8') as f:
            cfg = json.load(f)
        for entry in cfg.get('entries', []):
            p = entry.get('path', '')
            if os.path.isdir(p):
                check_skill(p, os.path.basename(p))
                for s in os.listdir(p):
                    sp = os.path.join(p, s)
                    if os.path.isdir(sp):
                        check_skill(sp, s)
    except: pass
if not unique_skills and os.path.isdir(gemini_dir):
    for s in os.listdir(gemini_dir):
        unique_skills.add(s)

print(len(unique_skills))
" 2>/dev/null || echo "0")
        gemini_count="${stat_res}"
    fi

    if [ -z "${gemini_count}" ] || [ "${gemini_count}" -eq 0 ]; then
        [ -d "${gemini_dir}" ] && gemini_count=$(find "${gemini_dir}" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | wc -l)
    fi

    local unmanaged_gemini=0
    local unmanaged_claude=0
    [ "${manifest_count}" -gt 0 ] && [ "${gemini_count}" -gt "${manifest_count}" ] && unmanaged_gemini=$((gemini_count - manifest_count))
    [ "${manifest_count}" -gt 0 ] && [ "${claude_count}" -gt "${manifest_count}" ] && unmanaged_claude=$((claude_count - manifest_count))
    local total_unmanaged=$((unmanaged_gemini + unmanaged_claude))

    echo "=== HAWS Fast Skill Status ==="
    echo "Antigravity Active Skills : ${gemini_count}"
    echo "Claude Code Active Skills : ${claude_count}"
    if [ -d "${HOME}/.codex" ] || [ -d "${HOME}/.agents" ]; then
        echo "OpenAI Codex Active Skills: ${codex_count}"
    fi
    echo "Manifest Registered Skills: ${manifest_count}"
    [ "${total_unmanaged}" -gt 0 ] && echo "Unmanaged Foreign Skills  : [ALERT: ${total_unmanaged} foreign skill(s) detected - Run './haws.sh sync --clean']"

    local brain_mode="LOCAL-ONLY"
    local brain_remote
    brain_remote="$(git -C "${SCRIPT_DIR}/secondbrain" remote get-url origin 2>/dev/null || true)"
    if [ -n "${brain_remote}" ]; then
        brain_mode="ONLINE (${brain_remote})"
    fi
    echo "Second Brain Mode         : [${brain_mode}]"

    if [ "${claude_count}" -eq "${manifest_count}" ] && [ "${gemini_count}" -eq "${manifest_count}" ]; then
        echo "Sync Health Status        : [100% HEALTHY & IN SYNC]"
    elif [ "${total_unmanaged}" -gt 0 ]; then
        echo "Sync Health Status        : [UNMANAGED SKILLS DETECTED - Run './haws.sh sync --clean']"
    else
        echo "Sync Health Status        : [MISMATCH DETECTED - Run './haws.sh sync']"
    fi
}

legacy_run_doctor() {
    local json_mode=false
    if [ "${1:-}" = "--json" ]; then
        json_mode=true
    fi

    local passed=0
    local failed=0
    local details=()
    local manifest="${HOME}/.haws_manifest"

    check_item() {
        local path="$1"
        local label="$2"
        local status="PASS"
        if [ -s "${path}" ]; then
            passed=$((passed + 1))
            [ "$json_mode" = false ] && echo "   [PASS] ${label}"
        else
            status="FAIL"
            failed=$((failed + 1))
            [ "$json_mode" = false ] && echo "   [FAIL] ${label} missing or empty"
        fi
        details+=("{\"item\":\"${label}\",\"status\":\"${status}\"}")
    }

    [ "$json_mode" = false ] && echo "=== HAWS System Doctor & Environment Diagnostics ===" && echo ""

    # 1. Check Core Standard Files (3 Canonical Files)
    [ "$json_mode" = false ] && echo "1. Checking Core Standards (3 Canonical Files)..."
    local core_files=("HAWS.md" "WORK_INSTRUCTIONS.md" "WORKFLOW.md")
    for f in "${core_files[@]}"; do
        check_item "${SCRIPT_DIR}/core/${f}" "core/${f}"
    done

    # 2. Check Project Templates & Blueprints (15 Blueprints)
    [ "$json_mode" = false ] && echo "" && echo "2. Checking Project Templates & Blueprints (15 Blueprints)..."
    local doc_tpls=("PROJECT.md" "ARCHITECTURE.md" "CONSTRAINTS.md" "HANDOFF.md" "AGENTS.md" "DESIGN.md")
    for f in "${doc_tpls[@]}"; do
        if [ -f "${SCRIPT_DIR}/templates/${f}" ]; then
            check_item "${SCRIPT_DIR}/templates/${f}" "templates/${f}"
        else
            check_item "${SCRIPT_DIR}/templates/docs/${f}" "templates/docs/${f}"
        fi
    done
    check_item "${SCRIPT_DIR}/ai-configs/claude/CLAUDE.md.template" "ai-configs/claude/CLAUDE.md.template"
    check_item "${SCRIPT_DIR}/ai-configs/cursor/haws.mdc.template" "ai-configs/cursor/haws.mdc.template"
    check_item "${SCRIPT_DIR}/ai-configs/gemini/GEMINI.md.template" "ai-configs/gemini/GEMINI.md.template"
    check_item "${SCRIPT_DIR}/ai-configs/copilot/copilot-instructions.md.template" "ai-configs/copilot/copilot-instructions.md.template"
    check_item "${SCRIPT_DIR}/ai-configs/codex/AGENTS.override.md.template" "ai-configs/codex/AGENTS.override.md.template"
    local container_tpls=("devcontainer.json" "Dockerfile.template" ".dockerignore.template" "docker-compose.yml.template")
    for f in "${container_tpls[@]}"; do
        check_item "${SCRIPT_DIR}/containers/${f}" "containers/${f}"
    done

    # 3. Check Subagents (5 Canonical Specialists)
    [ "$json_mode" = false ] && echo "" && echo "3. Checking Subagents (5 Canonical Specialists)..."
    local agent_files=("backend-engineer.md" "frontend-engineer.md" "organizer.md" "researcher.md" "tester.md")
    for f in "${agent_files[@]}"; do
        check_item "${SCRIPT_DIR}/agents/${f}" "agents/${f}"
    done

    # 4. Check Skills Structure (3 Clean Categories)
    [ "$json_mode" = false ] && echo "" && echo "4. Checking Skills Structure (3 Clean Categories)..."
    local skill_dirs=("custom" "packs" "standalone")
    for d in "${skill_dirs[@]}"; do
        if [ -d "${SCRIPT_DIR}/skills/${d}" ]; then
            passed=$((passed + 1))
            [ "$json_mode" = false ] && echo "   [PASS] skills/${d}/"
            details+=("{\"item\":\"skills/${d}/\",\"status\":\"PASS\"}")
        else
            failed=$((failed + 1))
            [ "$json_mode" = false ] && echo "   [FAIL] skills/${d}/ missing"
            details+=("{\"item\":\"skills/${d}/\",\"status\":\"FAIL\"}")
        fi
    done

    # Verify that all installed skills have valid SKILL.md
    local valid_skills=0
    local invalid_skills=0
    while IFS= read -r -d '' sf; do
        if [ -s "${sf}" ]; then
            valid_skills=$((valid_skills + 1))
        else
            invalid_skills=$((invalid_skills + 1))
        fi
    done < <(find "${SCRIPT_DIR}/skills" -type f \( -name "SKILL.md" -o -name "skill.md" \) -print0 2>/dev/null || true)

    if [ "${invalid_skills}" -eq 0 ] && [ "${valid_skills}" -gt 0 ]; then
        passed=$((passed + 1))
        [ "$json_mode" = false ] && echo "   [PASS] 100% Skills validated (${valid_skills} active skills)"
        details+=("{\"item\":\"Skills inventory validity\",\"status\":\"PASS\"}")
    else
        failed=$((failed + 1))
        [ "$json_mode" = false ] && echo "   [FAIL] Invalid or empty SKILL.md detected (${invalid_skills} invalid)"
        details+=("{\"item\":\"Skills inventory validity\",\"status\":\"FAIL\"}")
    fi

    # 5. Check Personal Second Brain & Plugins
    [ "$json_mode" = false ] && echo "" && echo "5. Checking Personal Second Brain & Plugins..."
    if [ -d "${SCRIPT_DIR}/secondbrain/.git" ] && [ -s "${SCRIPT_DIR}/secondbrain/USER_PREFERENCES.md" ] && [ -s "${SCRIPT_DIR}/secondbrain/ANTI_PATTERNS.md" ]; then
        passed=$((passed + 1))
        [ "$json_mode" = false ] && echo "   [PASS] secondbrain/ (decoupled local git repository)"
        details+=("{\"item\":\"secondbrain/ decoupling\",\"status\":\"PASS\"}")
        local dirty_notes
        dirty_notes=$(git -C "${SCRIPT_DIR}/secondbrain" status --porcelain 2>/dev/null | wc -l || echo 0)
        if [ "${dirty_notes}" -gt 0 ]; then
            [ "$json_mode" = false ] && echo "   [NOTE] secondbrain has ${dirty_notes} uncommitted note(s). Run './haws.sh sync' or './haws.sh user sync'."
        fi
    else
        failed=$((failed + 1))
        [ "$json_mode" = false ] && echo "   [FAIL] secondbrain/ missing or uninitialized (run './haws.sh user connect' or './haws.sh setup')"
        details+=("{\"item\":\"secondbrain/ decoupling\",\"status\":\"FAIL\"}")
    fi

    if [ ! -d "${SCRIPT_DIR}/plugins" ]; then
        passed=$((passed + 1))
        [ "$json_mode" = false ] && echo "   [PASS] plugins/ consolidated into skills/packs/ (zero bloat)"
        details+=("{\"item\":\"plugins/ directory\",\"status\":\"PASS\"}")
    else
        failed=$((failed + 1))
        [ "$json_mode" = false ] && echo "   [FAIL] Redundant plugins/ directory still present"
        details+=("{\"item\":\"plugins/ directory\",\"status\":\"FAIL\"}")
    fi

    # 6. Check Submodule Merge Independence (.gitmodules merge=ours)
    [ "$json_mode" = false ] && echo "" && echo "6. Checking Submodule Merge Independence..."
    if [ -f "${SCRIPT_DIR}/.gitattributes" ] && grep -q "\.gitmodules merge=ours" "${SCRIPT_DIR}/.gitattributes" 2>/dev/null; then
        passed=$((passed + 1))
        [ "$json_mode" = false ] && echo "   [PASS] Submodule merge independence configured (.gitmodules merge=ours)"
        details+=("{\"item\":\"Submodule merge=ours\",\"status\":\"PASS\"}")
    else
        failed=$((failed + 1))
        [ "$json_mode" = false ] && echo "   [FAIL] .gitattributes missing .gitmodules merge=ours"
        details+=("{\"item\":\"Submodule merge=ours\",\"status\":\"FAIL\"}")
    fi

    # 7. Check Root Hygiene
    [ "$json_mode" = false ] && echo "" && echo "7. Checking Root Hygiene..."
    if [ ! -d "${SCRIPT_DIR}/.agents" ]; then
        passed=$((passed + 1))
        [ "$json_mode" = false ] && echo "   [PASS] Zero redundant .agents/ directory"
        details+=("{\"item\":\"Zero redundant .agents/ directory\",\"status\":\"PASS\"}")
    else
        failed=$((failed + 1))
        [ "$json_mode" = false ] && echo "   [FAIL] Redundant .agents/ directory exists"
        details+=("{\"item\":\"Zero redundant .agents/ directory\",\"status\":\"FAIL\"}")
    fi

    if [ ! -d "${SCRIPT_DIR}/scripts" ]; then
        passed=$((passed + 1))
        [ "$json_mode" = false ] && echo "   [PASS] Zero redundant scripts/ directory"
        details+=("{\"item\":\"Zero redundant scripts/ directory\",\"status\":\"PASS\"}")
    else
        [ "$json_mode" = false ] && echo "   [WARN] Legacy scripts/ directory present"
        details+=("{\"item\":\"Zero redundant scripts/ directory\",\"status\":\"WARN\"}")
    fi

    if [ ! -d "${SCRIPT_DIR}/tools" ]; then
        passed=$((passed + 1))
        [ "$json_mode" = false ] && echo "   [PASS] Zero redundant tools/ directory"
        details+=("{\"item\":\"Zero redundant tools/ directory\",\"status\":\"PASS\"}")
    else
        failed=$((failed + 1))
        [ "$json_mode" = false ] && echo "   [FAIL] Redundant tools/ directory exists"
        details+=("{\"item\":\"Zero redundant tools/ directory\",\"status\":\"FAIL\"}")
    fi

    # 8. Check for Unmanaged Foreign Skills
    [ "$json_mode" = false ] && echo "" && echo "8. Checking for Unmanaged Foreign Skills..."
    local foreign_count=0
    local manifest="${HOME}/.haws_manifest"
    local gemini_skills="${HOME}/.gemini/config/skills"
    local claude_skills="${HOME}/.claude/skills"
    if [ -f "${manifest}" ]; then
        declare -A known_skills
        while IFS= read -r line || [ -n "$line" ]; do
            if [[ "$line" =~ ^skill:(.+) ]]; then
                local manifest_skill_target
                manifest_skill_target="$(_manifest_skill_target_name "$line" 2>/dev/null || true)"
                [ -n "${manifest_skill_target}" ] &&
                    known_skills["${manifest_skill_target}"]=1
            fi
        done < "${manifest}"

        for dir in "${gemini_skills}" "${claude_skills}"; do
            if [ -d "${dir}" ]; then
                for s in "${dir}"/*; do
                    [ ! -d "${s}" ] && [ ! -L "${s}" ] && continue
                    local sname
                    sname="$(basename "${s}")"
                    if [ -z "${known_skills[${sname}]:-}" ]; then
                        foreign_count=$((foreign_count + 1))
                    fi
                done
            fi
        done
    fi
    if [ "${foreign_count}" -eq 0 ]; then
        passed=$((passed + 1))
        [ "$json_mode" = false ] && echo "   [PASS] Zero unmanaged foreign skills"
        details+=("{\"item\":\"Zero unmanaged foreign skills\",\"status\":\"PASS\"}")
    else
        [ "$json_mode" = false ] && echo "   [WARN] ${foreign_count} unmanaged skill(s) detected (run './haws.sh sync --clean' to purge)"
        details+=("{\"item\":\"Zero unmanaged foreign skills\",\"status\":\"WARN\"}")
    fi

    # 9. Check Line Endings (LF Normalization)
    [ "$json_mode" = false ] && echo "" && echo "9. Checking Line Endings (LF Normalization)..."
    local crlf_count=0
    for dir in "${SCRIPT_DIR}/core" "${SCRIPT_DIR}/templates" "${SCRIPT_DIR}/agents"; do
        if [ -d "${dir}" ]; then
            while IFS= read -r -d '' f; do
                if grep -q $'\r' "${f}" 2>/dev/null; then
                    crlf_count=$((crlf_count + 1))
                fi
            done < <(find "${dir}" -type f \( -name "*.md" -o -name "*.template" -o -name "*.json" \) -print0 2>/dev/null || true)
        fi
    done
    if [ "${crlf_count}" -eq 0 ]; then
        passed=$((passed + 1))
        [ "$json_mode" = false ] && echo "   [PASS] All core/templates/agents files normalized to LF"
        details+=("{\"item\":\"LF Normalization\",\"status\":\"PASS\"}")
    else
        [ "$json_mode" = false ] && echo "   [WARN] ${crlf_count} file(s) contain CRLF line endings (run 'git add --renormalize .' to fix)"
        details+=("{\"item\":\"LF Normalization\",\"status\":\"WARN\"}")
    fi

    # 10. Check Git Hooks (Quality & Safety Gates)
    [ "$json_mode" = false ] && echo "" && echo "10. Checking Git Hooks (Quality & Safety Gates)..."
    local hooks_path
    hooks_path="$(git -C "${SCRIPT_DIR}" config core.hooksPath 2>/dev/null || echo "")"
    if [ -f "${SCRIPT_DIR}/.githooks/commit-msg" ]; then
        if [ "${hooks_path}" != ".githooks" ]; then
            git -C "${SCRIPT_DIR}" config core.hooksPath .githooks 2>/dev/null || true
        fi
        passed=$((passed + 1))
        [ "$json_mode" = false ] && echo "   [PASS] Git hooks active (.githooks: commit-msg)"
        details+=("{\"item\":\"Git Hooks Guardrails\",\"status\":\"PASS\"}")
    else
        failed=$((failed + 1))
        [ "$json_mode" = false ] && echo "   [FAIL] Git hooks missing in .githooks"
        details+=("{\"item\":\"Git Hooks Guardrails\",\"status\":\"FAIL\"}")
    fi

    # 11. Check Cross-OS & Multi-AI Environment Detection
    [ "$json_mode" = false ] && echo "" && echo "11. Checking Cross-OS & Multi-AI Support..."
    local os_type="POSIX"
    if [[ "$(uname -s)" =~ MINGW|MSYS|CYGWIN ]] || command -v cygpath &>/dev/null; then
        os_type="Windows (NTFS / MSYS2)"
    elif [[ "$(uname -s)" = "Darwin" ]]; then
        os_type="macOS (Darwin)"
    else
        os_type="Linux ($(uname -s))"
    fi
    passed=$((passed + 1))
    [ "$json_mode" = false ] && echo "   [PASS] OS Platform: ${os_type}"
    details+=("{\"item\":\"OS Platform: ${os_type}\",\"status\":\"PASS\"}")

    local detected_ais=()
    [ -d "${HOME}/.gemini" ] && detected_ais+=("Antigravity")
    [ -d "${HOME}/.claude" ] && detected_ais+=("Claude Code")
    { [ -d "${HOME}/.cursor" ] || [ -d "${HOME}/AppData/Roaming/Cursor" ] || [ -f "${HOME}/.cursorrules" ]; } && detected_ais+=("Cursor")
    { [ -d "${HOME}/.config/github-copilot" ] || [ -d "${HOME}/.copilot" ] || [ -d "${HOME}/AppData/Local/github-copilot" ]; } && detected_ais+=("Codex/Copilot")

    local ai_summary="None detected"
    [ "${#detected_ais[@]}" -gt 0 ] && ai_summary="${detected_ais[*]}"
    passed=$((passed + 1))
    [ "$json_mode" = false ] && echo "   [PASS] Active AI Environments: ${ai_summary}"
    details+=("{\"item\":\"Active AIs: ${ai_summary}\",\"status\":\"PASS\"}")

    # 12. Check Launchers & Automation Tools
    [ "$json_mode" = false ] && echo "" && echo "12. Checking Launchers & Automation Tools..."
    check_item "${SCRIPT_DIR}/haws.sh" "haws.sh"
    check_item "${SCRIPT_DIR}/haws.bat" "haws.bat"

    if "${SCRIPT_DIR}/haws.sh" uninstall --dry-run >/dev/null 2>&1; then
        passed=$((passed + 1))
        [ "$json_mode" = false ] && echo "   [PASS] haws.sh uninstall --dry-run (operational)"
        details+=("{\"item\":\"Uninstaller Dry-Run Test\",\"status\":\"PASS\"}")
    else
        failed=$((failed + 1))
        [ "$json_mode" = false ] && echo "   [FAIL] haws.sh uninstall --dry-run failed"
        details+=("{\"item\":\"Uninstaller Dry-Run Test\",\"status\":\"FAIL\"}")
    fi


    local overall_status="HEALTHY & READY"
    [ "${failed}" -gt 0 ] && overall_status="ATTENTION REQUIRED"


    if [ "$json_mode" = true ]; then
        local IFS=","
        cat <<EOF
{
  "status": "${overall_status}",
  "total_passed": ${passed},
  "total_failed": ${failed},
  "checks": [${details[*]}]
}
EOF
    else
        echo ""
        echo "--- Diagnostics Summary ---"
        echo "Total Checks Passed: ${passed}"
        echo "Total Checks Failed: ${failed}"
        echo "System Status: [${overall_status}]"
    fi

    if [ "${failed}" -ne 0 ]; then
        return 1
    fi
}

declare -gA DISABLED_SKILLS

extract_skill_name() {
    local sfile="$1"
    local sname=""
    if [ -f "$sfile" ]; then
        while IFS= read -r line; do
            if [[ "${line}" =~ ^[[:space:]]*name:[[:space:]]*[\"\']?([^\"\'#]+)[\"\']? ]]; then
                sname="${BASH_REMATCH[1]}"
                sname="${sname%"${sname##*[![:space:]]}"}"
                break
            fi
        done < "$sfile"
    fi
    [ -z "$sname" ] && sname="$(basename "$(dirname "$sfile")")"
    echo "$sname"
}

extract_skill_desc() {
    local sfile="$1"
    local sdesc=""
    if [ -f "$sfile" ]; then
        local in_fm=0
        local capturing_multiline=0
        while IFS= read -r line || [ -n "$line" ]; do
            local line_trim
            line_trim="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            if [ "$line_trim" = "---" ]; then
                if [ "$in_fm" -eq 0 ]; then
                    in_fm=1
                    continue
                else
                    break
                fi
            fi
            [ "$in_fm" -eq 0 ] && continue

            if [ "$capturing_multiline" -eq 1 ]; then
                if [[ "$line" =~ ^[[:space:]]+([^#].*) ]]; then
                    sdesc="${BASH_REMATCH[1]}"
                    break
                else
                    capturing_multiline=0
                fi
            fi

            if [[ "$line" =~ ^[[:space:]]*description:[[:space:]]*(.*) ]]; then
                local val="${BASH_REMATCH[1]}"
                val="$(echo "$val" | sed -E 's/^["'"'"']|["'"'"']$//g' | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                if [ "$val" = ">" ] || [ "$val" = "|" ] || [ -z "$val" ]; then
                    capturing_multiline=1
                else
                    sdesc="$val"
                    break
                fi
            fi
        done < "$sfile"

        # Fallback to first non-header markdown line
        if [ -z "$sdesc" ]; then
            local fm_count=0
            while IFS= read -r line || [ -n "$line" ]; do
                local lt
                lt="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                if [ "$lt" = "---" ]; then
                    fm_count=$((fm_count + 1))
                    continue
                fi
                [ "$fm_count" -eq 1 ] && continue
                [[ "$lt" =~ ^# ]] && continue
                if [ -n "$lt" ]; then
                    sdesc="$lt"
                    break
                fi
            done < "$sfile"
        fi
    fi
    [ ${#sdesc} -gt 60 ] && sdesc="${sdesc:0:57}..."
    echo "$sdesc"
}

_haws_state_dir() {
    if [ -n "${HAWS_STATE_DIR:-}" ]; then
        printf '%s\n' "${HAWS_STATE_DIR}"
    else
        printf '%s/.haws/state\n' "${SCRIPT_DIR}"
    fi
}

_haws_compat_file() {
    local filename="$1"
    local candidate
    for candidate in \
        "${SCRIPT_DIR}/ai-configs/${filename}" \
        "${SCRIPT_DIR}/config/${filename}" \
        "${SCRIPT_DIR}/${filename}"; do
        if [ -f "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    printf '%s/ai-configs/%s\n' "${SCRIPT_DIR}" "${filename}"
}

_haws_sha256() {
    local path="$1"
    [ -f "${path}" ] || return 0
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${path}" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${path}" | awk '{print $1}'
    else
        cksum "${path}" | awk '{print $1 ":" $2}'
    fi
}

_haws_state_replace() {
    local temporary="$1"
    local destination="$2"
    [ -f "${temporary}" ] || return 1
    mkdir -p "$(dirname "${destination}")" || return 1
    # Redirection has closed the complete temporary file before this rename.
    if [ "${HAWS_TEST_FAIL_BEFORE_RENAME:-0}" = 1 ] || \
        [ "${HAWS_TEST_FAIL_BEFORE_SETTINGS_RENAME:-0}" = 1 ]; then
        return 70
    fi
    mv -f -- "${temporary}" "${destination}"
}

_second_brain_dir() {
    printf '%s/secondbrain\n' "${SCRIPT_DIR}"
}

_second_brain_remote_url() {
    git -C "$(_second_brain_dir)" remote get-url origin 2>/dev/null || true
}

_second_brain_refresh_state() {
    local remote
    remote="$(_second_brain_remote_url)"
    HAWS_SECOND_BRAIN_REMOTE="${remote}"
    if [ -n "${remote}" ]; then
        HAWS_SECOND_BRAIN_ENABLED="on"
        SECOND_BRAIN_ENABLED="on"
    else
        HAWS_SECOND_BRAIN_ENABLED="off"
        SECOND_BRAIN_ENABLED="off"
    fi
    export HAWS_SECOND_BRAIN_ENABLED HAWS_SECOND_BRAIN_REMOTE SECOND_BRAIN_ENABLED
}

_second_brain_status_label() {
    [ -n "$(_second_brain_remote_url)" ] && printf '%s\n' Connected || printf '%s\n' Local-Only
}

settings_defaults() {
    HAWS_SECOND_BRAIN_ENABLED="off"
    HAWS_SECOND_BRAIN_REMOTE=""
    HAWS_AUTO_UPDATE="on"
    SECOND_BRAIN_ENABLED="off"
    AUTO_UPDATE="on"
    export HAWS_SECOND_BRAIN_ENABLED HAWS_SECOND_BRAIN_REMOTE \
        HAWS_AUTO_UPDATE SECOND_BRAIN_ENABLED AUTO_UPDATE
}

_haws_setting_is_toggle() {
    [ "${1:-}" = on ] || [ "${1:-}" = off ]
}

_haws_remote_is_valid() {
    local remote="${1:-}"
    [ -z "${remote}" ] && return 0
    [[ "${remote}" != *[[:cntrl:]]* ]] || return 1
    [[ "${remote}" != -* ]] || return 1
    case "${remote}" in
        git@?*:?*|?*://?*) return 0 ;;
        *) return 1 ;;
    esac
}

settings_load() {
    local file="$(_haws_state_dir)/settings.tsv"
    settings_defaults
    [ -f "${file}" ] || return 0

    local key value extra
    while IFS=$'\t' read -r key value extra || [ -n "${key:-}" ]; do
        [ -n "${key:-}" ] || continue
        case "${key}" in
            schema_version)
                [ "${value}" = 1 ] && [ -z "${extra:-}" ] || return 2
                ;;
            second_brain|second_brain_enabled)
                _haws_setting_is_toggle "${value}" && [ -z "${extra:-}" ] || return 2
                ;;
            second_brain_remote)
                [ -z "${extra:-}" ] || return 2
                _haws_remote_is_valid "${value}" || return 2
                ;;
            auto_update)
                _haws_setting_is_toggle "${value}" && [ -z "${extra:-}" ] || return 2
                HAWS_AUTO_UPDATE="${value}"
                AUTO_UPDATE="${value}"
                ;;
            *)
                return 2
                ;;
        esac
    done < "${file}"
    _second_brain_refresh_state
    export HAWS_SECOND_BRAIN_ENABLED HAWS_SECOND_BRAIN_REMOTE \
        HAWS_AUTO_UPDATE SECOND_BRAIN_ENABLED AUTO_UPDATE
}

settings_save() {
    local auto_update="${HAWS_AUTO_UPDATE:-on}"
    case "${1:-}" in
        auto_update)
            auto_update="${2:-}"
            ;;
        second_brain|second_brain_enabled)
            _haws_setting_is_toggle "${2:-}" || return 2
            ;;
        second_brain_remote)
            _haws_remote_is_valid "${2:-}" || return 2
            ;;
        *)
            [ "$#" -lt 2 ] || auto_update="$2"
            if [ "$#" -ge 3 ]; then
                _haws_remote_is_valid "$3" || return 2
            fi
            ;;
    esac
    _haws_setting_is_toggle "${auto_update}" || return 2

    local state="$(_haws_state_dir)"
    local file="${state}/settings.tsv"
    local temporary="${state}/settings.stage.$$"
    mkdir -p "${state}" || return 1
    {
        printf 'schema_version\t1\n'
        printf 'auto_update\t%s\n' "${auto_update}"
    } > "${temporary}" || {
        rm -f -- "${temporary}"
        return 1
    }
    _haws_state_replace "${temporary}" "${file}"
    local result=$?
    rm -f -- "${temporary}"
    [ "${result}" -eq 0 ] || return "${result}"
    HAWS_AUTO_UPDATE="${auto_update}"
    AUTO_UPDATE="${auto_update}"
    _second_brain_refresh_state
    export HAWS_AUTO_UPDATE AUTO_UPDATE
}

disabled_environments_load() {
    declare -gA DISABLED_ENVIRONMENTS=()
    declare -gA DISABLED_ENVS=()
    local dfile="$(_haws_compat_file environments.disabled)"
    local line
    if [ -f "${dfile}" ]; then
        while IFS= read -r line || [ -n "${line}" ]; do
            line="${line%$'\r'}"
            line="${line%%#*}"
            line="${line#${line%%[![:space:]]*}}"
            line="${line%${line##*[![:space:]]}}"
            [ -n "${line}" ] || continue
            DISABLED_ENVIRONMENTS["${line}"]=1
            DISABLED_ENVS["${line}"]=1
        done < "${dfile}"
    fi
    HAWS_DISABLED_ENVIRONMENTS_FILE="${dfile}"
    export HAWS_DISABLED_ENVIRONMENTS_FILE
}

disabled_environments_save_if_changed() {
    local dfile="${HAWS_DISABLED_ENVIRONMENTS_FILE:-$(_haws_compat_file environments.disabled)}"
    local state="$(_haws_state_dir)"
    local temporary="${state}/environments.disabled.stage.$$"
    local desired_signature current_signature env create_empty=0
    local desired=()

    if [ "${1:-}" = --all-enabled ]; then
        create_empty=1
        shift
    elif [ "$#" -gt 0 ]; then
        desired=("$@")
    else
        for env in "${!DISABLED_ENVIRONMENTS[@]}"; do
            desired+=("${env}")
        done
    fi
    desired_signature="$(printf '%s\n' "${desired[@]}" | sed '/^$/d' | sort)"
    current_signature=""
    if [ -f "${dfile}" ]; then
        current_signature="$(sed -e 's/\r$//' -e 's/#.*//' "${dfile}" |
            sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' |
            sed '/^$/d' | sort)"
    fi
    if [ "${desired_signature}" = "${current_signature}" ]; then
        if [ "${create_empty}" -ne 1 ] || [ -e "${dfile}" ]; then
            return 0
        fi
    fi
    [ "${#desired[@]}" -gt 0 ] || {
        [ -f "${dfile}" ] || [ "${create_empty}" -eq 1 ] || return 0
    }
    mkdir -p "${state}" "$(dirname "${dfile}")" || return 1
    {
        printf '# HAWS Disabled AI Environments\n'
        printf '# Environments listed here will not receive global pointers or linked skills\n'
        printf '%s\n' "${desired[@]}" | sed '/^$/d' | sort
    } > "${temporary}" || {
        rm -f -- "${temporary}"
        return 1
    }
    _haws_state_replace "${temporary}" "${dfile}"
    local result=$?
    rm -f -- "${temporary}"
    [ "${result}" -eq 0 ] || return "${result}"
    disabled_environments_load
}

# Keep the naming used by later state consumers without replacing the old
# skills.disabled implementation below.
disabled_envs_load() { disabled_environments_load "$@"; }
disabled_envs_save() { disabled_environments_save_if_changed "$@"; }

ownership_record() {
    local group="${1:-}" kind="${2:-}" path="${3:-}"
    local source="${4:-}" fingerprint="${5:-}"
    [ -n "${group}" ] && [ -n "${kind}" ] && [ -n "${path}" ] || return 2
    local state="$(_haws_state_dir)"
    local file="${state}/ownership.tsv"
    local temporary="${state}/ownership.stage.$$"
    mkdir -p "${state}" || return 1
    awk -F $'\t' -v OFS=$'\t' -v group="${group}" -v kind="${kind}" \
        -v path="${path}" -v source="${source}" -v fingerprint="${fingerprint}" '
        $1 == group && $2 == kind && $3 == path {
            if (!found) print group, kind, path, source, fingerprint
            found = 1
            next
        }
        { print }
        END {
            if (!found) print group, kind, path, source, fingerprint
        }
    ' "${file}" 2>/dev/null > "${temporary}" || {
        if [ -f "${file}" ]; then
            rm -f -- "${temporary}"
            return 1
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "${group}" "${kind}" "${path}" "${source}" "${fingerprint}" > "${temporary}" || {
            rm -f -- "${temporary}"
            return 1
        }
    }
    _haws_state_replace "${temporary}" "${file}"
    local result=$?
    rm -f -- "${temporary}"
    return "${result}"
}

ownership_list() {
    local group="${1:-}"
    local file="$(_haws_state_dir)/ownership.tsv"
    [ -f "${file}" ] || return 0
    if [ -n "${group}" ]; then
        awk -F $'\t' -v group="${group}" '$1 == group' "${file}"
    else
        cat -- "${file}"
    fi
}

sync_lock_acquire() {
    local state="$(_haws_state_dir)"
    local lock="${state}/sync.lock"
    local pid timestamp
    mkdir -p "${state}" || return 1
    if mkdir "${lock}" 2>/dev/null; then
        printf '%s\n' "$$" > "${lock}/pid"
        date +%s > "${lock}/timestamp"
        return 0
    fi
    pid="$(cat "${lock}/pid" 2>/dev/null || true)"
    timestamp="$(cat "${lock}/timestamp" 2>/dev/null || true)"
    if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
        echo "Blocked: sync already running (pid ${pid})" >&2
        return 1
    fi
    echo "Blocked: stale sync lock (pid ${pid:-unknown}, timestamp ${timestamp:-unknown}); run sync_lock_release --recover after review" >&2
    return 2
}

sync_lock_release() {
    local lock="$(_haws_state_dir)/sync.lock"
    local owner="${1:-}"
    local pid
    [ -d "${lock}" ] || return 0
    pid="$(cat "${lock}/pid" 2>/dev/null || true)"
    if [ "${owner}" = --recover ] || [ "${owner}" = recover ]; then
        if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
            echo "Blocked: refusing to recover live sync lock (pid ${pid})" >&2
            return 1
        fi
    elif [ "${pid}" != "$$" ]; then
        echo "Blocked: sync lock is owned by pid ${pid:-unknown}" >&2
        return 1
    fi
    rm -f -- "${lock}/pid" "${lock}/timestamp" && rmdir -- "${lock}"
}

state_init() {
    local state="$(_haws_state_dir)"
    mkdir -p "${state}" || return 1
    settings_load || return $?
    if [ ! -f "${state}/settings.tsv" ]; then
        settings_save || return $?
    fi
    disabled_environments_load
    load_disabled_skills
}

load_disabled_skills() {
    DISABLED_SKILLS=()
    local dfile="${SCRIPT_DIR}/skills.disabled"
    [ ! -f "${dfile}" ] && [ -f "${SCRIPT_DIR}/config/skills.disabled" ] && dfile="${SCRIPT_DIR}/config/skills.disabled"
    if [ -f "${dfile}" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/#.*//')"
            [ -n "$line" ] && DISABLED_SKILLS["$line"]=1
        done < "${dfile}"
    fi
}

disabled_skills_load() { load_disabled_skills "$@"; }

save_disabled_skills() {
    local dfile="${SCRIPT_DIR}/skills.disabled"
    mkdir -p "$(dirname "${dfile}")"
    {
        echo "# HAWS Disabled Skills"
        echo "# Skills listed here will not be linked to Claude Code or Antigravity"
        for sk in "${!DISABLED_SKILLS[@]}"; do
            [ -n "$sk" ] && echo "$sk"
        done | sort
    } > "${dfile}"
}

_catalog_repo_dir() {
    printf '%s\n' "${HAWS_REPO_DIR:-${SCRIPT_DIR}}"
}

_catalog_gitmodules() {
    printf '%s/.gitmodules\n' "$(_catalog_repo_dir)"
}

_catalog_source_id() {
    printf '%s::%s\n' "$1" "${2#./}"
}

_catalog_source_url() {
    local name="$1"
    git -C "$(_catalog_repo_dir)" config --file "$(_catalog_gitmodules)" \
        --get "submodule.${name}.url" 2>/dev/null || printf '%s\n' -
}

_catalog_source_revision() {
    local path="$1"
    local repo="$(_catalog_repo_dir)"
    if [ -e "${repo}/${path}/.git" ]; then
        git -C "${repo}/${path}" rev-parse --verify HEAD 2>/dev/null && return 0
    fi
    if [ -e "${repo}/.git" ]; then
        git -C "${repo}" rev-parse --verify "HEAD:${path}" 2>/dev/null && return 0
    fi
    printf '%s\n' uninitialized
}

catalog_sources() {
    local repo="$(_catalog_repo_dir)"
    local gitmodules="$(_catalog_gitmodules)"
    local record key name path source_id url revision
    [ -f "${gitmodules}" ] || return 0
    while IFS= read -r -d '' record; do
        key="${record%%$'\n'*}"
        path="${record#*$'\n'}"
        case "${key}" in
            submodule.*.path)
                name="${key#submodule.}"
                name="${name%.path}"
                path="${path#./}"
                source_id="$(_catalog_source_id "${name}" "${path}")"
                url="$(_catalog_source_url "${name}")"
                revision="$(_catalog_source_revision "${path}")"
                printf '%s\t%s\t%s\t%s\n' \
                    "${source_id}" "${path}" "${url}" "${revision}"
                ;;
        esac
    done < <(git -C "${repo}" config --null --file "${gitmodules}" \
        --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)
}

_catalog_skill_sources() {
    local repo="$(_catalog_repo_dir)"
    catalog_sources

    local custom_path="skills/custom"
    [ -d "${repo}/${custom_path}" ] || return 0
    printf '%s\t%s\t%s\t%s\n' \
        "$(_catalog_source_id custom "${custom_path}")" \
        "${custom_path}" local local
}

_catalog_source_fields() {
    local wanted="$1"
    local row source_id path url revision
    while IFS= read -r row || [ -n "${row}" ]; do
        [ -n "${row}" ] || continue
        IFS=$'\t' read -r source_id path url revision <<< "${row}"
        if [ "${source_id}" = "${wanted}" ]; then
            printf '%s\t%s\t%s\n' "${path}" "${url}" "${revision}"
            return 0
        fi
    done < <(_catalog_skill_sources)
    return 1
}

catalog_source_kind() {
    local source_id="${1:-}"
    local path url revision source_dir raw_skill_count
    [ -n "${source_id}" ] || return 1
    IFS=$'\t' read -r path url revision <<< "$(_catalog_source_fields "${source_id}")" || return 1
    source_dir="$(_catalog_repo_dir)/${path}"
    if [ ! -d "${source_dir}" ]; then
        printf '%s\n' UNVERIFIED
        return 0
    fi
    raw_skill_count="$(find "${source_dir}" -type f \
        \( -name SKILL.md -o -name skill.md \) -print 2>/dev/null | awk 'END { print NR + 0 }')"
    if [ "${raw_skill_count}" -eq 1 ]; then
        printf '%s\n' SINGLE
    elif [ "${raw_skill_count}" -gt 1 ]; then
        printf '%s\n' PACK
    else
        printf '%s\n' UNVERIFIED
    fi
}

_catalog_is_disabled() {
    local skill_id="$1"
    local display_name="$2"
    local entrypoint="$3"
    local file line
    for file in \
        "${SCRIPT_DIR}/skills/skills.disabled" \
        "${SCRIPT_DIR}/skills.disabled" \
        "${SCRIPT_DIR}/config/skills.disabled"; do
        [ -f "${file}" ] || continue
        while IFS= read -r line || [ -n "${line}" ]; do
            line="${line%$'\r'}"
            line="${line%%#*}"
            line="${line#${line%%[![:space:]]*}}"
            line="${line%${line##*[![:space:]]}}"
            case "${line}" in
                "${skill_id}"|"${display_name}"|"${entrypoint}")
                    return 0
                    ;;
            esac
        done < "${file}"
    done
    return 1
}

_catalog_skill_is_eligible() {
    local skill_file="$1"
    [[ "${skill_file}" =~ \.openclaw/ ]] && return 1
    [[ "${skill_file}" =~ planning-with-files ]] && \
        [[ ! "${skill_file}" =~ \.agents/skills ]] && \
        [[ ! "${skill_file}" =~ skills/i18n ]] && return 1
    [[ "${skill_file}" =~ ui-ux-pro-max ]] && \
        [[ ! "${skill_file}" =~ \.claude/skills ]] && return 1
    [[ "${skill_file}" =~ caveman/plugins/ ]] && return 1
    return 0
}

catalog_skills() {
    local row source_id path url revision source_dir skill_file entrypoint
    local logical_id display_name description active
    local -A seen_names=()
    while IFS= read -r row || [ -n "${row}" ]; do
        [ -n "${row}" ] || continue
        IFS=$'\t' read -r source_id path url revision <<< "${row}"
        source_dir="$(_catalog_repo_dir)/${path}"
        [ -d "${source_dir}" ] || continue
        seen_names=()
        while IFS= read -r -d '' skill_file; do
            [ -s "${skill_file}" ] || continue
            _catalog_skill_is_eligible "${skill_file}" || continue
            entrypoint="${skill_file#${source_dir}/}"
            display_name="$(extract_skill_name "${skill_file}")"
            [ -n "${display_name}" ] || continue
            case "${display_name}" in
                pi-planning-with-files|planning-with-files-*|design-taste-frontend-v1)
                    continue
                    ;;
            esac
            [ -n "${seen_names["${display_name}"]:-}" ] && continue
            seen_names["${display_name}"]=1
            display_name="${display_name//$'\t'/ }"
            display_name="${display_name//$'\n'/ }"
            logical_id="${source_id}::${display_name}"
            description="$(extract_skill_desc "${skill_file}")"
            [ -n "${description}" ] || description="${display_name}"
            description="${description//$'\t'/ }"
            description="${description//$'\n'/ }"
            active=1
            _catalog_is_disabled "${logical_id}" "${display_name}" "${entrypoint}" && active=0
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                "${source_id}" "${logical_id}" "${display_name}" \
                "${description}" "${entrypoint}" "${active}"
        done < <(find "${source_dir}" -type f \
            \( -name SKILL.md -o -name skill.md \) -print0 2>/dev/null | sort -z)
    done < <(_catalog_skill_sources)
}

_codex_plugin_skill_dir() {
    local skill_name="${1:-}"
    [ -n "${skill_name}" ] || return 1
    local roots=(
        "${CODEX_HOME:-${HOME}/.codex}/plugins/cache"
        "${HOME}/.codex/plugins/cache"
        "${HOME}/.agents/plugins/cache"
    )
    local root skill_file
    for root in "${roots[@]}"; do
        [ -d "${root}" ] || continue
        while IFS= read -r -d '' skill_file; do
            case "${skill_file}" in
                */skills/${skill_name}/SKILL.md|*/skills/${skill_name}/skill.md)
                    printf '%s\n' "$(dirname "${skill_file}")"
                    return 0
                    ;;
            esac
        done < <(find "${root}" -type f \( -name SKILL.md -o -name skill.md \) \
            -print0 2>/dev/null || true)
    done
    return 1
}

_manifest_skill_target_name() {
    local entry="${1:-}"
    [[ "${entry}" == skill:* ]] || return 1
    local payload="${entry#skill:}"
    local target="${payload}"
    [[ "${payload}" == *$'\t'* ]] && target="${payload#*$'\t'}"
    [[ "${payload}" == *$'\t'* ]] || target="${payload##*::}"
    [ -n "${target}" ] || return 1
    printf '%s\n' "${target}"
}

_manifest_has_skill_target() {
    local manifest="${1:-}" wanted="${2:-}" entry target
    [ -f "${manifest}" ] || return 1
    while IFS= read -r entry || [ -n "${entry}" ]; do
        target="$(_manifest_skill_target_name "${entry}" 2>/dev/null || true)"
        [ "${target}" = "${wanted}" ] && return 0
    done < "${manifest}"
    return 1
}

_haws_skill_link_owned_record() {
    local wanted="${1:-}"
    local wanted_native="$(_uninstall_native_path "${wanted}")"
    local group kind path source fingerprint extra path_native
    while IFS=$'\t' read -r group kind path source fingerprint extra ||
        [ -n "${group}" ]; do
        [ "${group}" = skills ] || continue
        path_native="$(_uninstall_native_path "${path}")"
        [ "${path_native}" = "${wanted_native}" ] || continue
        if ownership_verify "${kind}"$'\t'"${path}"$'\t'"${source}"$'\t'"${fingerprint}"; then
            printf '%s\t%s\t%s\t%s\n' "${kind}" "${path}" "${source}" "${fingerprint}"
            return 0
        fi
    done < <(ownership_list skills)
    return 1
}

_haws_skill_link_is_owned() {
    _haws_skill_link_owned_record "${1:-}" >/dev/null
}

_haws_skill_link_remove_if_owned() {
    local record kind path source fingerprint
    record="$(_haws_skill_link_owned_record "${1:-}" 2>/dev/null)" || return 1
    IFS=$'\t' read -r kind path source fingerprint <<< "${record}"
    _uninstall_remove_path "${kind}" "${path}"
}

_haws_record_skill_link() {
    local kind="${1:-symlink}" dest="${2:-}" source="${3:-}" fingerprint
    [ -n "${dest}" ] && [ -n "${source}" ] || return 2
    [ -L "${dest}" ] || return 0
    fingerprint="$(readlink "${dest}" 2>/dev/null || true)"
    [ -n "${fingerprint}" ] || fingerprint="${source}"
    ownership_record skills "${kind}" "${dest}" "${source}" "${fingerprint}"
}

catalog_validate_url() {
    local url="${1:-}"
    url="${url%/}"
    [ -n "${url}" ] || return 1
    [[ "${url}" != *[[:cntrl:]]* ]] || return 1
    if [ "${HAWS_TEST_ALLOW_LOCAL_SOURCES:-0}" = 1 ]; then
        case "${url}" in
            file://*|/*|[A-Za-z]:[\\/]*) return 0 ;;
        esac
    fi
    [[ "${url}" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\.git)?$ ]] || return 1
    local path_part="${url#https://github.com/}"
    local owner="${path_part%%/*}"
    local repository="${path_part##*/}"
    repository="${repository%.git}"
    [ "${owner}" != "." ] && [ "${owner}" != ".." ] || return 1
    [ "${repository}" != "." ] && [ "${repository}" != ".." ] || return 1
}

catalog_validate_destination() {
    local destination="${1:-}"
    local repo="$(_catalog_repo_dir)"
    case "${destination}" in
        skills/packs/*|skills/standalone/*) ;;
        *) return 1 ;;
    esac
    case "/${destination}/" in
        */../*|*/./*) return 1 ;;
    esac
    local name="${destination##*/}"
    [[ "${name}" =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
    [ "${name}" != "." ] && [ "${name}" != ".." ] || return 1
    [ ! -e "${repo}/${destination}" ] && [ ! -L "${repo}/${destination}" ]
}


run_with_deadline() {
    local seconds="${1:-}"
    shift || true
    case "${seconds}" in
        ''|*[!0-9]*|0) return 2 ;;
    esac
    [ "$#" -gt 0 ] || return 2

    local command_type
    command_type="$(type -t "${1}" 2>/dev/null || true)"
    if [ "${command_type}" != function ] && command -v timeout >/dev/null 2>&1; then
        local timeout_status=0
        if timeout --version >/dev/null 2>&1; then
            if timeout --foreground "${seconds}s" "$@"; then
                timeout_status=0
            else
                timeout_status=$?
            fi
            case "${timeout_status}" in
                124|137) return 124 ;;
                *) return "${timeout_status}" ;;
            esac
        fi
    fi

    "$@" &
    local child="$!"
    local deadline=$(( $(date +%s) + seconds ))
    while kill -0 "${child}" >/dev/null 2>&1; do
        if [ "$(date +%s)" -ge "${deadline}" ]; then
            kill -TERM "${child}" >/dev/null 2>&1 || true
            sleep 0.1 || true
            kill -KILL "${child}" >/dev/null 2>&1 || true
            wait "${child}" >/dev/null 2>&1 || true
            return 124
        fi
        sleep 0.1 || true
    done
    local wait_status=0
    if wait "${child}"; then
        wait_status=0
    else
        wait_status=$?
    fi
    return "${wait_status}"
}

_sync_timeout_seconds() {
    local configured="${HAWS_SYNC_TIMEOUT_SECONDS:-30}"
    case "${configured}" in
        ''|*[!0-9]*|0) printf '%s\n' 30 ;;
        *) printf '%s\n' "${configured}" ;;
    esac
}

_sync_fetch_candidate() {
    local source_dir="$1" fetch_remote="$2" fetch_source="$3" candidate_ref="$4"
    if [ -n "${HAWS_TEST_SYNC_FETCH_DELAY:-}" ]; then
        sleep "${HAWS_TEST_SYNC_FETCH_DELAY}"
    fi
    git -C "${source_dir}" fetch --quiet "${fetch_remote}" "+${fetch_source}:${candidate_ref}"
}

_sync_result_label() {
    case "${1:-}" in
        updated) printf '%s\n' Updated ;;
        up-to-date) printf '%s\n' Up-to-date ;;
        skipped) printf '%s\n' Skipped ;;
        blocked) printf '%s\n' Blocked ;;
        failed) printf '%s\n' Failed ;;
        timeout) printf '%s\n' Timeout ;;
        *) printf '%s\n' "${1:--}" ;;
    esac
}

_sync_result_marker() {
    case "${1:-}" in
        updated|up-to-date) printf '%s\n' '[PASS]' ;;
        skipped|timeout) printf '%s\n' '[WARN]' ;;
        blocked) printf '%s\n' '[BLOCKED]' ;;
        failed) printf '%s\n' '[FAIL]' ;;
        *) printf '%s\n' '[INFO]' ;;
    esac
}

_sync_present_result() {
    local target="${1:-}" result="${2:-}" detail="${3:-}"
    local label marker
    label="$(_sync_result_label "${result}")"
    marker="$(_sync_result_marker "${result}")"
    printf '  %-28s %-18s %s\n' "${target}" "${marker} ${label}" "${detail:--}"
    case "${result}" in
        updated) SYNC_SUMMARY_UPDATED=$((SYNC_SUMMARY_UPDATED + 1)) ;;
        up-to-date) SYNC_SUMMARY_UP_TO_DATE=$((SYNC_SUMMARY_UP_TO_DATE + 1)) ;;
        skipped) SYNC_SUMMARY_SKIPPED=$((SYNC_SUMMARY_SKIPPED + 1)) ;;
        blocked) SYNC_SUMMARY_BLOCKED=$((SYNC_SUMMARY_BLOCKED + 1)) ;;
        failed) SYNC_SUMMARY_FAILED=$((SYNC_SUMMARY_FAILED + 1)) ;;
        timeout) SYNC_SUMMARY_TIMEOUT=$((SYNC_SUMMARY_TIMEOUT + 1)) ;;
    esac
}

_sync_legacy_echo() {
    [ "${HAWS_SYNC_PRESENTATION:-0}" = 1 ] || echo "$*"
}

sync_result_write() {
    local target="${1:-}" result="${2:-}" revision="${3:--}" detail="${4:-}"
    [ -n "${target}" ] && [ -n "${result}" ] || return 2
    local state="$(_haws_state_dir)"
    local file="${state}/sync-state.tsv"
    local temporary="${state}/sync-state.stage.$$"
    mkdir -p "${state}" || return 1
    if [ -f "${file}" ]; then
        cp -- "${file}" "${temporary}" || return 1
    else
        : > "${temporary}" || return 1
    fi
    detail="${detail//$'\t'/ }"
    detail="${detail//$'\n'/ }"
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${target}" "${result}" \
        "${revision}" "${detail}" >> "${temporary}" || {
        rm -f -- "${temporary}"
        return 1
    }
    local replace_status=0
    if _haws_state_replace "${temporary}" "${file}"; then
        replace_status=0
    else
        replace_status=$?
    fi
    rm -f -- "${temporary}"
    if [ "${replace_status}" -eq 0 ] && [ "${HAWS_SYNC_PRESENTATION:-0}" = 1 ]; then
        _sync_present_result "${target}" "${result}" "${detail}"
    fi
    return "${replace_status}"
}

_sync_source_path() {
    local fields source_path
    fields="$(_catalog_source_fields "${1:-}" 2>/dev/null || true)"
    [ -n "${fields}" ] || return 1
    source_path="${fields%%$'\t'*}"
    case "${source_path}" in
        ''|/*|[A-Za-z]:[\\/]*|*/../*|../*|*/./*|./*) return 1 ;;
    esac
    printf '%s\n' "${source_path}"
}

_sync_candidate_ref() {
    local safe
    safe="$(printf '%s' "${1:-target}" | tr -c 'A-Za-z0-9' '-')"
    printf 'refs/haws-sync/%s-%s\n' "$$" "${safe:0:80}"
}

_sync_candidate_cleanup() {
    git -C "$1" update-ref -d "$2" >/dev/null 2>&1 || true
}

source_preflight() {
    local source_id="${1:-}"
    local source_path source_dir status skill_source skill_active has_active=0
    source_path="$(_sync_source_path "${source_id}")" || return 4
    source_dir="$(_catalog_repo_dir)/${source_path}"
    [ -d "${source_dir}" ] || return 4
    git -C "${source_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 4
    if ! status="$(git -C "${source_dir}" status --porcelain --untracked-files=all 2>/dev/null)"; then
        return 4
    fi
    [ -z "${status}" ] || return 2
    while IFS=$'\t' read -r skill_source _ _ _ _ skill_active || [ -n "${skill_source:-}" ]; do
        if [ "${skill_source:-}" = "${source_id}" ] && [ "${skill_active:-0}" = 1 ]; then
            has_active=1
            break
        fi
    done < <(catalog_skills 2>/dev/null || true)
    [ "${has_active}" -eq 1 ] || return 3
    return 0
}

source_candidate_validate() {
    local source_id="${1:-}" revision="${2:-}"
    local source_path source_dir skill_id display skill_source entrypoint active
    local found=0 candidate_content
    [ -n "${source_id}" ] && [ -n "${revision}" ] || return 2
    source_path="$(_sync_source_path "${source_id}")" || return 1
    source_dir="$(_catalog_repo_dir)/${source_path}"
    [ -d "${source_dir}" ] || return 1
    while IFS=$'\t' read -r skill_source skill_id display _ entrypoint active ||
        [ -n "${skill_id:-}" ]; do
        [ "${skill_source:-}" = "${source_id}" ] && [ "${active:-0}" = 1 ] || continue
        found=1
        git -C "${source_dir}" cat-file -e "${revision}:${entrypoint}" >/dev/null 2>&1 || return 1
        candidate_content="$(git -C "${source_dir}" show "${revision}:${entrypoint}" 2>/dev/null || true)"
        [ -n "${candidate_content//[[:space:]]/}" ] || return 1
    done < <(catalog_skills 2>/dev/null || true)
    [ "${found}" -eq 1 ]
}

_sync_root_preflight() {
    local repo="$(_catalog_repo_dir)" status
    git -C "${repo}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 4
    if ! status="$(git -C "${repo}" status --porcelain --untracked-files=all 2>/dev/null)"; then
        return 4
    fi
    [ -z "${status}" ] || return 2
    return 0
}

_sync_root_candidate_validate() {
    local repo="$(_catalog_repo_dir)" revision="${1:-}" size
    [ -n "${revision}" ] || return 2
    size="$(git -C "${repo}" cat-file -s "${revision}:haws.sh" 2>/dev/null || true)"
    [ "${size:-0}" -gt 0 ]
}

sync_target() {
    local target="${1:-}" source_dir source_path candidate_ref candidate_revision
    local preflight_status fetch_status current final timeout_seconds activation_status=0
    local fetch_remote=origin fetch_source=HEAD current_branch
    [ -n "${target}" ] || return 2
    if [ "${HAWS_AUTO_UPDATE:-${AUTO_UPDATE:-on}}" != on ]; then
        sync_result_write "${target}" skipped - "Auto Update is disabled" || return 1
        _sync_legacy_echo "${target}: skipped (Auto Update is disabled)"
        return 0
    fi

    if [ "${target}" = haws ]; then
        source_dir="$(_catalog_repo_dir)"
        current_branch="$(git -C "${source_dir}" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
        [ -n "${current_branch}" ] || {
            sync_result_write "${target}" blocked - "HAWS checkout is detached" || true
            _sync_legacy_echo "${target}: blocked (detached checkout)"
            return 1
        }
        fetch_remote="$(git -C "${source_dir}" config --get "branch.${current_branch}.remote" 2>/dev/null || true)"
        fetch_source="$(git -C "${source_dir}" config --get "branch.${current_branch}.merge" 2>/dev/null || true)"
        [ -n "${fetch_remote}" ] && [ -n "${fetch_source}" ] || {
            sync_result_write "${target}" failed - "HAWS branch has no tracked remote" || true
            _sync_legacy_echo "${target}: failed (no tracked remote)"
            return 1
        }
        if _sync_root_preflight; then
            preflight_status=0
        else
            preflight_status=$?
        fi
    else
        source_path="$(_sync_source_path "${target}")" || {
            sync_result_write "${target}" failed - "source is not registered" || true
            _sync_legacy_echo "${target}: failed (source is not registered)"
            return 1
        }
        source_dir="$(_catalog_repo_dir)/${source_path}"
        if source_preflight "${target}"; then
            preflight_status=0
        else
            preflight_status=$?
        fi
    fi

    case "${preflight_status}" in
        2)
            sync_result_write "${target}" blocked - "source has staged, unstaged, or untracked changes" || return 1
            _sync_legacy_echo "${target}: blocked (local changes)"
            return 1
            ;;
        3)
            sync_result_write "${target}" skipped - "source has no active skills" || return 1
            _sync_legacy_echo "${target}: skipped (no active skills)"
            return 0
            ;;
        4)
            sync_result_write "${target}" failed - "source checkout is unavailable" || return 1
            _sync_legacy_echo "${target}: failed (source checkout is unavailable)"
            return 1
            ;;
        0) ;;
        *)
            sync_result_write "${target}" failed - "source preflight failed" || return 1
            _sync_legacy_echo "${target}: failed (source preflight failed)"
            return 1
            ;;
    esac

    candidate_ref="$(_sync_candidate_ref "${target}")"
    timeout_seconds="$(_sync_timeout_seconds)"
    if run_with_deadline "${timeout_seconds}" _sync_fetch_candidate \
        "${source_dir}" "${fetch_remote}" "${fetch_source}" "${candidate_ref}"; then
        fetch_status=0
    else
        fetch_status=$?
    fi
    candidate_revision="$(git -C "${source_dir}" rev-parse --verify "${candidate_ref}" 2>/dev/null || true)"
    if [ "${fetch_status}" -eq 124 ]; then
        _sync_candidate_cleanup "${source_dir}" "${candidate_ref}"
        sync_result_write "${target}" skipped - "Local fallback; remote fetch exceeded ${timeout_seconds}s" || return 1
        _sync_legacy_echo "${target}: timeout"
        return 0
    fi
    if [ "${fetch_status}" -ne 0 ] || [ -z "${candidate_revision}" ]; then
        _sync_candidate_cleanup "${source_dir}" "${candidate_ref}"
        sync_result_write "${target}" skipped - "Local fallback; network unavailable" || return 1
        _sync_legacy_echo "${target}: failed (remote candidate could not be fetched)"
        return 0
    fi

    if [ "${target}" = haws ]; then
        if _sync_root_candidate_validate "${candidate_revision}"; then
            :
        else
            _sync_candidate_cleanup "${source_dir}" "${candidate_ref}"
            sync_result_write "${target}" failed "${candidate_revision}" "candidate validation failed" || return 1
            _sync_legacy_echo "${target}: failed (candidate validation)"
            return 1
        fi
    elif source_candidate_validate "${target}" "${candidate_revision}"; then
        :
    else
        _sync_candidate_cleanup "${source_dir}" "${candidate_ref}"
        sync_result_write "${target}" failed "${candidate_revision}" "candidate validation failed" || return 1
        _sync_legacy_echo "${target}: failed (candidate validation)"
        return 1
    fi

    current="$(git -C "${source_dir}" rev-parse --verify HEAD 2>/dev/null || true)"
    if [ -z "${current}" ]; then
        _sync_candidate_cleanup "${source_dir}" "${candidate_ref}"
        sync_result_write "${target}" failed "${candidate_revision}" "current revision could not be read" || return 1
        _sync_legacy_echo "${target}: failed (current revision could not be read)"
        return 1
    fi
    if [ "${current}" != "${candidate_revision}" ]; then
        if [ "${target}" = haws ]; then
            git -C "${source_dir}" merge --ff-only "${candidate_revision}" >/dev/null 2>&1 || activation_status=$?
        else
            git -C "${source_dir}" checkout --detach "${candidate_revision}" >/dev/null 2>&1 || activation_status=$?
        fi
        if [ "${activation_status}" -eq 0 ]; then
            :
        else
            _sync_candidate_cleanup "${source_dir}" "${candidate_ref}"
            sync_result_write "${target}" failed "${candidate_revision}" "candidate activation failed" || return 1
            _sync_legacy_echo "${target}: failed (candidate activation)"
            return 1
        fi
    fi
    final="$(git -C "${source_dir}" rev-parse --verify HEAD 2>/dev/null || true)"
    _sync_candidate_cleanup "${source_dir}" "${candidate_ref}"
    if [ "${final}" = "${candidate_revision}" ]; then
        if [ "${current}" = "${candidate_revision}" ]; then
            sync_result_write "${target}" up-to-date "${candidate_revision}" "final HEAD equals candidate" || return 1
            _sync_legacy_echo "${target}: up-to-date"
        else
            sync_result_write "${target}" updated "${candidate_revision}" "final HEAD equals candidate" || return 1
            _sync_legacy_echo "${target}: updated"
        fi
        return 0
    fi
    sync_result_write "${target}" failed "${candidate_revision}" "final HEAD did not equal candidate" || return 1
    _sync_legacy_echo "${target}: failed (final HEAD did not equal candidate)"
    return 1
}

sync_second_brain_target() {
    local brain_dir="${SCRIPT_DIR}/secondbrain"
    local current remote_head final before status timeout_seconds
    [ "${HAWS_SECOND_BRAIN_ENABLED:-off}" = on ] || {
        sync_result_write secondbrain skipped - "Second Brain is disabled" || return 1
        _sync_legacy_echo "secondbrain: skipped (disabled)"
        return 0
    }
    [ -d "${brain_dir}/.git" ] || {
        sync_result_write secondbrain failed - "Second Brain checkout is unavailable" || return 1
        _sync_legacy_echo "secondbrain: failed (checkout is unavailable)"
        return 1
    }
    if ! status="$(git -C "${brain_dir}" status --porcelain --untracked-files=all 2>/dev/null)"; then
        sync_result_write secondbrain failed - "Second Brain checkout could not be inspected" || return 1
        _sync_legacy_echo "secondbrain: failed (checkout could not be inspected)"
        return 1
    fi
    [ -z "${status}" ] || {
        sync_result_write secondbrain blocked - "Second Brain has local changes" || return 1
        _sync_legacy_echo "secondbrain: blocked (local changes)"
        return 1
    }
    git -C "${brain_dir}" remote get-url origin >/dev/null 2>&1 || {
        sync_result_write secondbrain skipped - "Second Brain is local-only" || return 1
        _sync_legacy_echo "secondbrain: skipped (local-only)"
        return 0
    }
    current="$(git -C "${brain_dir}" rev-parse --verify HEAD 2>/dev/null || true)"
    timeout_seconds="$(_sync_timeout_seconds)"
    if run_with_deadline "${timeout_seconds}" run_user sync; then
        :
    else
        local sync_status=$?
        if [ "${sync_status}" -eq 124 ]; then
            sync_result_write secondbrain timeout - "remote sync exceeded ${timeout_seconds}s" || return 1
            _sync_legacy_echo "secondbrain: timeout"
        else
            sync_result_write secondbrain failed - "remote sync failed" || return 1
            _sync_legacy_echo "secondbrain: failed (remote sync)"
        fi
        return 1
    fi
    final="$(git -C "${brain_dir}" rev-parse --verify HEAD 2>/dev/null || true)"
    remote_head="$(git -C "${brain_dir}" rev-parse --verify refs/remotes/origin/main 2>/dev/null || true)"
    [ -n "${remote_head}" ] && [ "${final}" = "${remote_head}" ] || {
        sync_result_write secondbrain failed "${final:--}" "final HEAD did not equal origin/main" || return 1
        _sync_legacy_echo "secondbrain: failed (final HEAD did not equal origin/main)"
        return 1
    }
    if [ "${final}" = "${current}" ]; then
        sync_result_write secondbrain up-to-date "${final}" "final HEAD equals origin/main" || return 1
        _sync_legacy_echo "secondbrain: up-to-date"
    else
        sync_result_write secondbrain updated "${final}" "final HEAD equals origin/main" || return 1
        _sync_legacy_echo "secondbrain: updated"
    fi
    return 0
}

_sync_interrupt() {
    sync_lock_release >/dev/null 2>&1 || true
    HAWS_SYNC_LOCK_ACQUIRED=0
    exit 130
}

sync_run() {
    local target_count=0 target row source_id status=0
    echo "  [*] Preparing synchronization..."
    if [ "${1:-}" = --recover-lock ]; then
        sync_lock_release --recover
        return $?
    fi
    state_init || return $?
    trap _sync_interrupt INT TERM
    if sync_lock_acquire; then
        :
    else
        local lock_status=$?
        trap - INT TERM
        return "${lock_status}"
    fi
    HAWS_SYNC_LOCK_ACQUIRED=1
    export HAWS_SYNC_LOCK_ACQUIRED
    trap 'if [ "${HAWS_SYNC_LOCK_ACQUIRED:-0}" -eq 1 ]; then sync_lock_release >/dev/null 2>&1 || true; HAWS_SYNC_LOCK_ACQUIRED=0; fi' EXIT
    if settings_load; then
        :
    else
        local settings_status=$?
        sync_lock_release >/dev/null 2>&1 || true
        HAWS_SYNC_LOCK_ACQUIRED=0
        trap - EXIT INT TERM
        return "${settings_status}"
    fi
    if [ -n "${HAWS_TEST_SYNC_DELAY:-}" ]; then
        sleep "${HAWS_TEST_SYNC_DELAY}"
    fi

    HAWS_SYNC_PRESENTATION=1
    SYNC_SUMMARY_UPDATED=0
    SYNC_SUMMARY_UP_TO_DATE=0
    SYNC_SUMMARY_SKIPPED=0
    SYNC_SUMMARY_BLOCKED=0
    SYNC_SUMMARY_FAILED=0
    SYNC_SUMMARY_TIMEOUT=0
    echo "============================================================="
    echo "                         HAWS SYNC"
    echo "============================================================="
    echo ""
    echo "OPTIONS"
    printf '  Auto Update   : %s\n' "$(_haws_toggle_label "${HAWS_AUTO_UPDATE:-on}")"
    printf '  Second Brain  : %s\n' "$(_second_brain_status_label)"
    echo ""
    echo "TARGETS"
    printf '  %-28s %-10s %s\n' Target Result Detail
    if [ "${HAWS_AUTO_UPDATE:-on}" != on ]; then
        echo "  [INFO] Auto Update is disabled; explicit synchronization remains available."
    fi
    echo "  [*] Checking configured remote targets, please wait..."
    if git -C "$(_catalog_repo_dir)" remote get-url origin >/dev/null 2>&1; then
        target_count=$((target_count + 1))
        sync_target haws || status=1
    fi
    while IFS=$'\t' read -r source_id _ _ _ || [ -n "${source_id:-}" ]; do
        [ -n "${source_id:-}" ] || continue
        target_count=$((target_count + 1))
        sync_target "${source_id}" || status=1
    done < <(catalog_sources 2>/dev/null || true)
    if [ "${HAWS_SECOND_BRAIN_ENABLED:-off}" = on ]; then
        target_count=$((target_count + 1))
        sync_second_brain_target || status=1
    fi
    [ "${target_count}" -gt 0 ] || echo "  [INFO] No remote targets enabled"

    if sync_lock_release; then
        :
    else
        status=1
    fi
    HAWS_SYNC_LOCK_ACQUIRED=0
    trap - EXIT INT TERM
    echo ""
    echo "SUMMARY"
    printf '  Updated: %-4s Up-to-date: %-4s Skipped: %-4s\n' \
        "${SYNC_SUMMARY_UPDATED}" "${SYNC_SUMMARY_UP_TO_DATE}" "${SYNC_SUMMARY_SKIPPED}"
    printf '  Blocked: %-4s Failed: %-4s Timeout: %-4s\n' \
        "${SYNC_SUMMARY_BLOCKED}" "${SYNC_SUMMARY_FAILED}" "${SYNC_SUMMARY_TIMEOUT}"
    HAWS_SYNC_PRESENTATION=0
    return "${status}"
}

run_sync() {
    local CLEAN_UNMANAGED=false
    for opt in "$@"; do
        [ "$opt" = "--clean" ] && CLEAN_UNMANAGED=true
    done
    shift || true
    local sync_status=0
    echo "[*] Step 1/5: Preparing local state and synchronizing sources"
    sync_run "$@" || sync_status=$?
    if [ "${sync_status}" -eq 0 ]; then
        echo "[PASS] Step 1/5: Sources are synchronized or safely unchanged"
    else
        echo "[WARN] Step 1/5: Source synchronization completed with target issues"
    fi

    local SOURCE_DIR="${SCRIPT_DIR}"

    # 2. Detect AI Environments
    echo "[*] Step 2/5: Detecting AI environments"
    local DETECTED_CLAUDE=false
    local DETECTED_GEMINI=false
    local DETECTED_CURSOR=false
    local DETECTED_COPILOT=false
    local DETECTED_CODEX=false

    [ -d "${HOME}/.claude" ] && DETECTED_CLAUDE=true
    [ -d "${HOME}/.gemini" ] && DETECTED_GEMINI=true
    { [ -d "${HOME}/.cursor" ] || [ -d "${HOME}/AppData/Roaming/Cursor" ] || [ -f "${HOME}/.cursorrules" ]; } && DETECTED_CURSOR=true
    { [ -d "${HOME}/.config/github-copilot" ] || [ -d "${HOME}/.copilot" ] || [ -d "${HOME}/AppData/Local/github-copilot" ]; } && DETECTED_COPILOT=true
    { [ -d "${HOME}/.codex" ] || [ -d "${HOME}/.agents" ]; } && DETECTED_CODEX=true

    [ "$DETECTED_CLAUDE" = true ] && echo "  [✓] Claude Code detected (${HOME}/.claude)"
    [ "$DETECTED_GEMINI" = true ] && echo "  [✓] Google Antigravity detected (${HOME}/.gemini)"
    [ "$DETECTED_CURSOR" = true ] && echo "  [✓] Cursor IDE detected"
    [ "$DETECTED_COPILOT" = true ] && echo "  [✓] GitHub Copilot detected"
    [ "$DETECTED_CODEX" = true ] && echo "  [✓] OpenAI Codex detected (${HOME}/.codex)"
    echo "[PASS] Step 2/5: AI environment detection complete"
    echo ""

    # Helper Linking Functions
    local SKILLS_LINKED=0
    local AGENTS_LINKED=0
    local RULES_LINKED=0
    local SKIPPED_COUNT=0
    local active_count=0
    local IS_WINDOWS=false
    if [[ "$(uname -s)" =~ MINGW|MSYS|CYGWIN ]] || command -v cygpath &>/dev/null; then
        IS_WINDOWS=true
    fi

    safe_link_file() {
        local src="$1"
        local dest="$2"
        local label="$3"
        mkdir -p "$(dirname "${dest}")"

        if [ -L "${dest}" ]; then
            local current_target
            current_target="$(readlink "${dest}" || true)"
            if [ "${current_target}" = "${src}" ]; then
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                return 0
            fi
            rm -f "${dest}"
        elif [ -f "${dest}" ]; then
            if diff -q --strip-trailing-cr "${src}" "${dest}" >/dev/null 2>&1; then
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                return 0
            fi
            rm -f "${dest}"
        fi

        if [ "$IS_WINDOWS" = true ]; then
            local win_src win_dest
            win_src="$(cygpath -w "${src}")"
            win_dest="$(cygpath -w "${dest}")"
            rm -f "${dest}" 2>/dev/null || true
            if MSYS2_ARG_CONV_EXCL="*" cmd.exe /c mklink /H "${win_dest}" "${win_src}" >/dev/null 2>&1; then
                echo "  [HARDLINK] ${label}: ${dest} -> ${src}"
                return 0
            fi
        fi

        if ln -sf "${src}" "${dest}" 2>/dev/null || ln -s "${src}" "${dest}" 2>/dev/null; then
            echo "  [LINKED] ${label}: ${dest} -> ${src}"
        else
            cp -f "${src}" "${dest}"
            echo "  [COPIED] ${label}: ${dest} -> ${src}"
        fi
    }

    safe_link_dir() {
        local src="$1"
        local dest="$2"
        local label="$3"
        local dest_dir
        dest_dir="$(dirname "${dest}")"
        mkdir -p "${dest_dir}"

        local src_marker="${src}/SKILL.md"
        [ -f "${src}/skill.md" ] && src_marker="${src}/skill.md"
        local dest_marker="${dest}/SKILL.md"
        [ -f "${dest}/skill.md" ] && dest_marker="${dest}/skill.md"
        local current_target=""
        [ -L "${dest}" ] && current_target="$(readlink "${dest}" 2>/dev/null || true)"
        if [ -n "${current_target}" ] && [ "${current_target}" = "${src}" ]; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            return 0
        fi
        if [ -e "${dest}" ] || [ -L "${dest}" ]; then
            if ! _haws_skill_link_remove_if_owned "${dest}"; then
                echo "  [SKIPPED] Preserved existing skill link: ${dest}"
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                return 0
            fi
        elif [ -f "${src_marker}" ] && [ -f "${dest_marker}" ] &&
            diff -q --strip-trailing-cr "${src_marker}" "${dest_marker}" >/dev/null 2>&1; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            return 0
        fi

        if [ "$IS_WINDOWS" = true ]; then
            local win_src win_dest
            win_src="$(cygpath -w "${src}")"
            win_dest="$(cygpath -w "${dest}")"
            if MSYS2_ARG_CONV_EXCL="*" cmd.exe /c mklink /J "${win_dest}" "${win_src}" >/dev/null 2>&1; then
                _haws_record_skill_link junction "${dest}" "${src}" || return 1
                echo "  [JUNCTION] ${label}: ${dest} -> ${src}"
                return 0
            fi
        fi

        if ln -sfn "${src}" "${dest}" 2>/dev/null || ln -s "${src}" "${dest}" 2>/dev/null; then
            _haws_record_skill_link symlink "${dest}" "${src}" || return 1
            echo "  [LINKED] ${label}: ${dest} -> ${src}"
        else
            cp -rf "${src}" "${dest}"
            echo "  [COPIED] ${label}: ${dest} -> ${src}"
        fi
    }

    safe_append_pointer() {
        local target_file="$1"
        local marker_start="<!-- HAWS_GLOBAL_POINTER_START -->"
        local marker_end="<!-- HAWS_GLOBAL_POINTER_END -->"

        mkdir -p "$(dirname "${target_file}")"

        local pointer_content=""
        pointer_content+="${marker_start}\n"
        pointer_content+="# HAWS — Human-AI Working Standard\n"
        pointer_content+="This environment operates under HAWS. Read and adhere to:\n"
        pointer_content+="- Core Standard: ${SOURCE_DIR}/core/HAWS.md\n"
        pointer_content+="- Work Instructions: ${SOURCE_DIR}/core/WORK_INSTRUCTIONS.md\n"
        pointer_content+="- User Preferences & Second Brain: ${SOURCE_DIR}/secondbrain/USER_PREFERENCES.md and ${SOURCE_DIR}/secondbrain/ANTI_PATTERNS.md\n"
        pointer_content+="- Subagent roles: ${SOURCE_DIR}/agents/ (organizer, researcher, frontend-engineer, backend-engineer, tester). Read the relevant role before delegating with available native subagent tools.\n"
        pointer_content+="${marker_end}\n"

        if [ -f "${target_file}" ]; then
            if grep -q "${marker_start}" "${target_file}" 2>/dev/null; then
                local tmp_file="${target_file}.tmp.$$"
                awk -v start="${marker_start}" -v end="${marker_end}" '
                    $0 ~ start { skip=1; next }
                    $0 ~ end { skip=0; next }
                    !skip { print }
                ' "${target_file}" > "${tmp_file}"
                printf "%b" "${pointer_content}" >> "${tmp_file}"
                mv -f "${tmp_file}" "${target_file}"
                echo "  [UPDATED] Refreshed HAWS Global Pointer in ${target_file}"
                RULES_LINKED=$((RULES_LINKED + 1))
                return 0
            else
                printf "\n%b" "${pointer_content}" >> "${target_file}"
                echo "  [UPDATED] Appended HAWS Global Pointer to ${target_file}"
                RULES_LINKED=$((RULES_LINKED + 1))
                return 0
            fi
        else
            printf "%b" "${pointer_content}" > "${target_file}"
            echo "  [CREATED] Created HAWS Global Pointer at ${target_file}"
            RULES_LINKED=$((RULES_LINKED + 1))
            return 0
        fi
    }

    # 3. Setup Global Pointers
    echo "[*] Step 3/5: Configuring global environment pointers"
    [ "$DETECTED_CLAUDE" = true ] && safe_append_pointer "${HOME}/.claude/CLAUDE.md"
    [ "$DETECTED_GEMINI" = true ] && safe_append_pointer "${HOME}/.gemini/GEMINI.md"
    if [ "$DETECTED_CURSOR" = true ]; then
        if [ -d "${HOME}/.cursor" ]; then
            mkdir -p "${HOME}/.cursor/rules"
            safe_append_pointer "${HOME}/.cursor/rules/haws.mdc"
        else
            safe_append_pointer "${HOME}/.cursorrules"
        fi
    fi
    if [ "$DETECTED_COPILOT" = true ]; then
        if [ -d "${HOME}/.copilot" ]; then
            safe_append_pointer "${HOME}/.copilot/copilot-instructions.md"
        elif [ -d "${HOME}/.config/github-copilot" ]; then
            safe_append_pointer "${HOME}/.config/github-copilot/copilot-instructions.md"
        fi
    fi
    if [ "$DETECTED_CODEX" = true ]; then
        if [ -s "${HOME}/.codex/AGENTS.override.md" ]; then
            safe_append_pointer "${HOME}/.codex/AGENTS.override.md"
        elif [ -f "${HOME}/.codex/AGENTS.md" ]; then
            safe_append_pointer "${HOME}/.codex/AGENTS.md"
        elif [ -d "${HOME}/.codex" ]; then
            safe_append_pointer "${HOME}/.codex/AGENTS.override.md"
        fi
    fi
    echo "[PASS] Step 3/5: Global environment pointers configured"
    echo ""

    # 4. Link Skills, profiles, and commands
    echo "[*] Step 4/5: Linking skills, profiles, and commands"
    echo "  [*] Discovering and linking active skills to AI environments, please wait..."
    local skill_rows source_id skill_id skill_display skill_description entrypoint active
    local source_path source_dir skill_dir target_name source_label
    local -A source_paths=() display_counts=() processed_skills=()
    skill_rows="$(catalog_skills)"
    while IFS=$'\t' read -r source_id skill_id skill_display skill_description entrypoint active ||
        [ -n "${skill_id}" ]; do
        [ -n "${skill_id}" ] && [ "${active}" = 1 ] || continue
        display_counts["${skill_display}"]=$(( ${display_counts[${skill_display}]:-0} + 1 ))
    done <<< "${skill_rows}"
    while IFS=$'\t' read -r source_id source_path _ _ || [ -n "${source_id}" ]; do
        [ -n "${source_id}" ] || continue
        source_paths["${source_id}"]="${source_path}"
    done < <(_catalog_skill_sources)

    local MANIFEST_FILE="${HOME}/.haws_manifest"
    local PREV_MANIFEST="${HOME}/.haws_manifest.prev"
    local TMP_MANIFEST="${HOME}/.haws_manifest.tmp"

    rm -f "${PREV_MANIFEST}"
    [ -f "${MANIFEST_FILE}" ] && cp -f "${MANIFEST_FILE}" "${PREV_MANIFEST}"
    rm -f "${TMP_MANIFEST}"
    touch "${TMP_MANIFEST}"

    while IFS=$'\t' read -r source_id skill_id skill_display skill_description entrypoint active ||
        [ -n "${skill_id}" ]; do
        [ -n "${skill_id}" ] && [ "${active}" = 1 ] || continue
        [ -n "${processed_skills[${skill_id}]:-}" ] && continue
        processed_skills["${skill_id}"]=1
        source_path="${source_paths[${source_id}]:-}"
        [ -n "${source_path}" ] || continue
        source_dir="${SOURCE_DIR}/${source_path}"
        skill_dir="${source_dir}/$(dirname "${entrypoint}")"
        target_name="${skill_display}"
        if [ "${display_counts[${skill_display}]:-0}" -gt 1 ]; then
            source_label="${source_path##*/}"
            target_name="${skill_display} [${source_label}]"
        fi
        active_count=$((active_count + 1))
        printf 'skill:%s\t%s\n' "${skill_id}" "${target_name}" >> "${TMP_MANIFEST}"

        if [ "$DETECTED_CLAUDE" = true ]; then
            safe_link_dir "${skill_dir}" "${HOME}/.claude/skills/${target_name}" \
                "Claude Skill [${target_name}]"
            SKILLS_LINKED=$((SKILLS_LINKED + 1))
        fi
        if [ "$DETECTED_CODEX" = true ]; then
            local plugin_dir=""
            if [ "${skill_display}" = ponytail ]; then
                plugin_dir="$(_codex_plugin_skill_dir "${skill_display}" 2>/dev/null || true)"
            fi
            if [ -n "${plugin_dir}" ]; then
                echo "  [SKIPPED] Codex Skill [${target_name}] (plugin-owned: ${plugin_dir})"
            else
                safe_link_dir "${skill_dir}" "${HOME}/.agents/skills/${target_name}" \
                    "Codex Skill [${target_name}]"
                SKILLS_LINKED=$((SKILLS_LINKED + 1))
            fi
        fi
    done <<< "${skill_rows}"

    if [ "$DETECTED_GEMINI" = true ]; then
        local target_json="${HOME}/.gemini/config/skills.json"
        mkdir -p "${HOME}/.gemini/config"
        local json_entries=()
        declare -A seen_dirs
        while IFS=$'\t' read -r source_id skill_id skill_display skill_description entrypoint active ||
            [ -n "${skill_id}" ]; do
            [ -n "${skill_id}" ] && [ "${active}" = 1 ] || continue
            source_path="${source_paths[${source_id}]:-}"
            source_dir="${SOURCE_DIR}/${source_path}"
            skill_dir="${source_dir}/$(dirname "${entrypoint}")"
            local target_dir="${skill_dir}"
            if [[ "${source_path}" == skills/packs/* ]]; then
                local parent_dir="$(dirname "${skill_dir}")"
                target_dir="${parent_dir}"
                if [ -d "${parent_dir}/skills" ] && [ "$(basename "${parent_dir}")" != skills ]; then
                    target_dir="${skill_dir}"
                fi
            fi
            [[ "${source_path}" == skills/standalone/* ]] && target_dir="${skill_dir}"
            local win_target="${target_dir}"
            command -v cygpath &>/dev/null && win_target="$(cygpath -m "${target_dir}")"
            if [ -z "${seen_dirs[${win_target}]:-}" ]; then
                seen_dirs["${win_target}"]=1
                json_entries+=("    { \"path\": \"${win_target}\" }")
            fi
        done <<< "${skill_rows}"

        {
            echo "{"
            echo '  "entries": ['
            local total_entries=${#json_entries[@]}
            for ((i=0; i<total_entries; i++)); do
                local comma=","
                [ "$i" -eq $((total_entries - 1)) ] && comma=""
                echo "${json_entries[$i]}${comma}"
            done
            echo '  ]'
            echo "}"
        } > "${target_json}"
        echo "  [CONFIG] Antigravity Native Config (Dynamic): ${target_json}"
        SKILLS_LINKED=$((SKILLS_LINKED + active_count))
    fi
    echo "  [✓] Skills linking complete (${active_count} active skills linked)."
    echo ""

    # Link Subagents
    echo "  [*] Linking native subagent profiles"
    if [ "$DETECTED_CODEX" = true ]; then
        run_codex_agents install --source "${SOURCE_DIR}"
        AGENTS_LINKED=$((AGENTS_LINKED + 5))
    fi
    if [ -d "${SOURCE_DIR}/agents" ]; then
        for agent_file in "${SOURCE_DIR}/agents"/*.md; do
            if [ -f "${agent_file}" ]; then
                local agent_name
                agent_name="$(basename "${agent_file}" .md)"
                echo "agent:${agent_name}" >> "${TMP_MANIFEST}"

                if [ "$DETECTED_CLAUDE" = true ]; then
                    safe_link_file "${agent_file}" "${HOME}/.claude/agents/${agent_name}.md" "Claude Agent [${agent_name}]"
                    AGENTS_LINKED=$((AGENTS_LINKED + 1))
                fi
                if [ "$DETECTED_GEMINI" = true ]; then
                    local gemini_agent_dir="${HOME}/.gemini/config/agents/${agent_name}"
                    mkdir -p "${gemini_agent_dir}"
                    safe_link_file "${agent_file}" "${gemini_agent_dir}/agent.md" "Antigravity Agent [${agent_name}]"
                    AGENTS_LINKED=$((AGENTS_LINKED + 1))
                fi
            fi
        done
    fi
    echo ""

    # Link Custom Commands
    echo "  [*] Preparing custom skill commands"
    local COMMANDS_LINKED=0
    if [ "$DETECTED_CLAUDE" = true ] && [ -d "${SOURCE_DIR}/skills/custom" ]; then
        mkdir -p "${HOME}/.claude/commands"
        for custom_skill_dir in "${SOURCE_DIR}/skills/custom"/*; do
            if [ -d "${custom_skill_dir}" ]; then
                local custom_name
                custom_name="$(basename "${custom_skill_dir}")"
                local cmd_target="${HOME}/.claude/commands/${custom_name}.md"
                local desc="Execute the custom ${custom_name} skill workflow."

                for sfile in "${custom_skill_dir}/SKILL.md" "${custom_skill_dir}/skill.md"; do
                    if [ -f "$sfile" ]; then
                        local extracted_desc
                        extracted_desc=$(grep -E '^[[:space:]]*description:[[:space:]]*' "$sfile" | head -n 1 | sed -E 's/^[[:space:]]*description:[[:space:]]*["'"'"']?([^"'"'"'#\r\n]+)["'"'"']?.*$/\1/' | tr -d '\r\n' | xargs 2>/dev/null || true)
                        [ -n "$extracted_desc" ] && desc="$extracted_desc"
                        break
                    fi
                done

                cat <<EOF > "${cmd_target}"
---
description: ${desc}
---
Execute the ${custom_name} skill workflow defined in ~/.claude/skills/${custom_name}/SKILL.md.
EOF
                echo "  [COMMAND] Claude Slash Command [/${custom_name}]: ${cmd_target}"
                COMMANDS_LINKED=$((COMMANDS_LINKED + 1))
            fi
        done
    fi
    echo ""
    # Commit Manifest
    [ -f "${TMP_MANIFEST}" ] && mv -f "${TMP_MANIFEST}" "${MANIFEST_FILE}"

    # 4. Finalize linked state and prune removed items
    echo "  [*] Pruning removed items"
    local PRUNED=0
    if [ -f "${PREV_MANIFEST}" ] && [ -f "${MANIFEST_FILE}" ]; then
        while IFS= read -r entry || [ -n "$entry" ]; do
            [ -z "$entry" ] && continue
            if ! grep -q -F "${entry}" "${MANIFEST_FILE}" 2>/dev/null; then
                local type="${entry%%:*}"
                local name="${entry#*:}"
                if [ "$type" = "skill" ]; then
                    local target_name
                    target_name="$(_manifest_skill_target_name "${entry}" 2>/dev/null || true)"
                    [ -n "${target_name}" ] || continue
                    if _haws_skill_link_remove_if_owned "${HOME}/.claude/skills/${target_name}"; then
                        PRUNED=$((PRUNED + 1))
                    fi
                    if _haws_skill_link_remove_if_owned "${HOME}/.agents/skills/${target_name}"; then
                        PRUNED=$((PRUNED + 1))
                    fi
                    echo "  [PRUNED] Skill [${target_name}] (owned links only)"
                elif [ "$type" = "agent" ]; then
                    [ -e "${HOME}/.claude/agents/${name}.md" ] && rm -f "${HOME}/.claude/agents/${name}.md" && PRUNED=$((PRUNED + 1))
                    [ -e "${HOME}/.gemini/config/agents/${name}" ] && rm -rf "${HOME}/.gemini/config/agents/${name}" && PRUNED=$((PRUNED + 1))
                    echo "  [PRUNED] Agent [${name}]"
                fi
            fi
        done < "${PREV_MANIFEST}"
    fi
    if [ "${PRUNED}" -eq 0 ]; then
        echo "  [✓] Zero orphaned items detected."
    else
        echo "  [✓] Auto-pruned ${PRUNED} obsolete item(s)."
    fi

    if [ "$CLEAN_UNMANAGED" = true ] && [ -f "${MANIFEST_FILE}" ]; then
        echo "  [*] Purging unmanaged foreign skills (--clean requested)..."
        local UNMANAGED_PURGED=0
        for dir in "${HOME}/.gemini/config/skills" "${HOME}/.claude/skills"; do
            if [ -d "${dir}" ]; then
                for s in "${dir}"/*; do
                    [ ! -d "${s}" ] && [ ! -L "${s}" ] && continue
                    local sname
                    sname="$(basename "${s}")"
                    if ! _manifest_has_skill_target "${MANIFEST_FILE}" "${sname}"; then
                        if _haws_skill_link_remove_if_owned "${s}"; then
                            echo "  [PURGED UNMANAGED] Skill [${sname}]"
                            UNMANAGED_PURGED=$((UNMANAGED_PURGED + 1))
                        else
                            echo "  [SKIPPED] Preserved unowned skill [${sname}]"
                        fi
                    fi
                done
            fi
        done
        if [ "${UNMANAGED_PURGED}" -eq 0 ]; then
            echo "  [✓] Zero unmanaged foreign skills found."
        else
            echo "  [✓] Purged ${UNMANAGED_PURGED} unmanaged foreign skill(s)."
        fi
    fi
    echo "[PASS] Step 4/5: Skills, profiles, commands, and cleanup are ready"
    echo ""

    # 5. Configure hooks
    echo "[*] Step 5/5: Configuring hooks"
    if [ -d "${SCRIPT_DIR}/.githooks" ]; then
        if run_hooks install >/dev/null; then
            echo "[PASS] Step 5/5: Git safety hooks configured"
        else
            echo "[FAIL] Step 5/5: Git safety hooks could not be configured"
            sync_status=1
        fi
    else
        echo "[WARN] Step 5/5: Git safety hooks directory is not present"
    fi
    echo ""

    # 9. Summary & Fast Status
    echo "SUMMARY"
    echo "Global Rules  : ${RULES_LINKED}"
    echo "Skills Linked : ${SKILLS_LINKED}"
    echo "Commands Ready: ${COMMANDS_LINKED}"
    echo "Agents Linked : ${AGENTS_LINKED}"
    echo "Skipped Items : ${SKIPPED_COUNT}"
    echo ""
    _health_collect
    _health_print_summary
    echo ""
    echo "============================================================="
    echo "                    HAWS Sync Result"
    echo "============================================================="
    if [ "${sync_status}" -eq 0 ]; then
        echo "[PASS] HAWS synchronization completed"
    else
        echo "[WARN] HAWS synchronization completed with target issues"
    fi
    local wait_status=0
    _haws_wait_for_result || wait_status=$?
    [ "${wait_status}" -eq 0 ] || return "${wait_status}"
    return "${sync_status}"
}

run_edit_gitmodules() {
    echo "=== Direct .gitmodules Management ==="
    echo "Repository links are configured in: ${SCRIPT_DIR}/.gitmodules"
    echo ""
    if [ -f "${SCRIPT_DIR}/.gitmodules" ]; then
        echo "Current Submodules in .gitmodules:"
        git -C "${SCRIPT_DIR}" config --file .gitmodules --get-regexp path 2>/dev/null | awk '{print "  - " $2}' || true
    fi
    echo ""
    echo "  [*] Opening .gitmodules in editor..."
    if command -v code >/dev/null 2>&1; then
        code "${SCRIPT_DIR}/.gitmodules"
    elif [ -n "${EDITOR:-}" ] && command -v "${EDITOR}" >/dev/null 2>&1; then
        "${EDITOR}" "${SCRIPT_DIR}/.gitmodules"
    elif command -v notepad.exe >/dev/null 2>&1; then
        notepad.exe "${SCRIPT_DIR}/.gitmodules" &
    elif command -v nano >/dev/null 2>&1; then
        nano "${SCRIPT_DIR}/.gitmodules"
    elif command -v vi >/dev/null 2>&1; then
        vi "${SCRIPT_DIR}/.gitmodules"
    fi
    echo ""
    if [ -t 0 ]; then
        local sync_confirm=""
        read -r -p "Press [Enter] when done editing to sync submodules (or 's' to skip): " sync_confirm || sync_confirm=""
        if [[ "${sync_confirm}" =~ ^[Ss] ]]; then
            echo "  [INFO] Skipping submodule sync for now. Run './haws.sh sync' later."
            return 0
        fi
    fi
    echo "  [*] Synchronizing and updating configured submodules..."
    git -C "${SCRIPT_DIR}" submodule sync 2>/dev/null || true
    git -C "${SCRIPT_DIR}" submodule update --init --recursive 2>/dev/null || true
    echo "  [✓] Submodule configuration synchronized."
}

_interactive_truncate() {
    local value="$1"
    local maximum="${2:-48}"
    [ "${#value}" -le "${maximum}" ] && {
        printf '%s\n' "${value}"
        return 0
    }
    printf '%s...\n' "${value:0:$((maximum - 3))}"
}

_interactive_source_label() {
    local source_path="${1%/}"
    source_path="${source_path##*/}"
    _interactive_truncate "${source_path}" 24
}

interactive_menu() {
    local mode="$1"
    local title_spec="$2"
    local title="${title_spec}"
    local purpose=""
    local start_index=0
    if [[ "${title_spec}" == *"|"* ]]; then
        title="${title_spec%%|*}"
        local metadata="${title_spec#*|}"
        purpose="${metadata%%|*}"
        if [[ "${metadata}" == *"|"* ]]; then
            local requested_start="${metadata#*|}"
            [[ "${requested_start}" =~ ^[0-9]+$ ]] && start_index="${requested_start}"
        fi
    fi
    shift 2
    local items=("$@") # checklist: "name|detail|initial_state_0_or_1"
    local count=${#items[@]}
    [ "$count" -eq 0 ] && return 0

    local item_names=()
    local item_details=()
    local item_states=()
    local total="$count"

    if [ "${mode}" = "checklist" ] || [ "${mode}" = "settings" ]; then
        if [ "${mode}" = "checklist" ]; then
            total=$((count + 1))
        fi
        for item in "${items[@]}"; do
            local n="${item%%|*}"
            local rest="${item#*|}"
            local d="${rest%%|*}"
            local s="${rest##*|}"
            item_names+=("$n")
            item_details+=("$d")
            item_states+=("$s")
        done
    elif [ "${mode}" = "menu" ]; then
        for item in "${items[@]}"; do
            local n="${item%%|*}"
            local d=""
            [[ "${item}" == *"|"* ]] && d="${item#*|}"
            item_names+=("${n}")
            item_details+=("${d}")
        done
    else
        item_names=("${items[@]}")
    fi

    local menu_label_width=0 label_length
    for item_name in "${item_names[@]}"; do
        label_length=${#item_name}
        [ "${label_length}" -gt "${menu_label_width}" ] && menu_label_width="${label_length}"
    done
    menu_label_width=$((menu_label_width + 2))

    local cursor="${start_index}"
    [ "${cursor}" -lt "${total}" ] || cursor=0
    local cancelled=0
    local controls
    if [ "${mode}" = "checklist" ]; then
        controls="Controls: [Up/Down] Move | [Space] Toggle | [Enter] Confirm & Save | [Q] Cancel"
    elif [ "${mode}" = "settings" ]; then
        controls="Controls: [Up/Down] Move | [Enter] Select/Toggle | [Space] Toggle | [Q] Back"
    else
        local exit_hint="Exit"
        case "${title}" in
            "HAWS Setup"|"HAWS Home") ;;
            *) exit_hint="Back" ;;
        esac
        controls="Controls: [Up/Down] Move | [Enter] Select | [Q] ${exit_hint}"
    fi

    render_row() {
        local idx="$1"
        local is_curr="$2"
        local ptr="  "
        [ "$is_curr" -eq 1 ] && ptr="> "

        if [ "${mode}" = "checklist" ]; then
            if [ "$idx" -eq 0 ]; then
                local all_sel=1
                local any_sel=0
                for ((j=0; j<count; j++)); do
                    if [ "${item_states[$j]}" -eq 1 ]; then
                        any_sel=1
                    else
                        all_sel=0
                    fi
                done
                local mark="[ ]"
                if [ "$all_sel" -eq 1 ]; then
                    mark="[x]"
                elif [ "$any_sel" -eq 1 ]; then
                    mark="[-]"
                fi
                printf "\033[2K\r%s\033[1;36m%s [Toggle All: Select All / Deselect All]\033[0m\n" "${ptr}" "${mark}"
            else
                local real_idx=$((idx - 1))
                local mark="[ ]"
                local color="\033[0m"
                if [ "${item_states[$real_idx]}" -eq 1 ]; then
                    mark="[x]"
                    color="\033[32m"
                else
                    color="\033[90m"
                fi
                printf "\033[2K\r%s%s %b%-*s\033[0m \033[90m(%s)\033[0m\n" "${ptr}" "${mark}" "${color}" "${menu_label_width}" "${item_names[$real_idx]}" "${item_details[$real_idx]}"
            fi
        elif [ "${mode}" = "settings" ]; then
            local state_mark=""
            local detail="${item_details[$idx]:-}"
            local state_width=7
            case "${item_states[$idx]}" in
                on) state_mark=" [ On ]" ;;
                off) state_mark=" [ Off ]" ;;
            esac
            if [ -n "${detail}" ]; then
                printf "\033[2K\r%s%-*s %-*s - \033[90m%s\033[0m\n" \
                    "${ptr}" "${menu_label_width}" "${item_names[$idx]}" \
                    "${state_width}" "${state_mark}" "${detail}"
            else
                printf "\033[2K\r%s%-*s %-*s\n" \
                    "${ptr}" "${menu_label_width}" "${item_names[$idx]}" \
                    "${state_width}" "${state_mark}"
            fi
        else
            local detail="${item_details[$idx]:-}"
            if [ -n "${detail}" ]; then
                printf "\033[2K\r%s%-*s \033[90m- %s\033[0m\n" \
                    "${ptr}" "${menu_label_width}" "${item_names[$idx]}" "${detail}"
            else
                printf "\033[2K\r%s%s\n" "${ptr}" "${item_names[$idx]}"
            fi
        fi
    }

    echo ""
    if [ "${mode}" = "checklist" ] || [ "${mode}" = "settings" ]; then
        echo "============================================================="
        echo "                       ${title}"
        echo "============================================================="
        [ -n "${purpose}" ] && echo "${purpose}"
    else
        if [ "${HAWS_MENU_SUPPRESS_HEADER:-0}" != 1 ]; then
            echo "============================================================="
            echo "                       ${title}"
            echo "============================================================="
            [ -n "${purpose}" ] && echo "${purpose}"
        fi
    fi
    echo ""

    for ((i=0; i<total; i++)); do
        local is_c=0
        [ "$i" -eq "$cursor" ] && is_c=1
        render_row "$i" "$is_c"
    done
    echo ""
    echo "${controls}"

    local interactive_terminal=0
    [ -t 0 ] && [ -t 1 ] && interactive_terminal=1
    local redraw_rows=$((total + 2))
    [ "${interactive_terminal}" -eq 1 ] && printf "\033[?25l" 2>/dev/null || true
    while true; do
        local key=""
        if ! IFS= read -rsn1 key; then
            cancelled=1
            break
        fi
        if [[ "${key}" == $'\x1b' ]]; then
            local rest=""
            read -rsn2 -t 0.1 rest || rest=""
            case "${rest}" in
                "[A") cursor=$(( (cursor - 1 + total) % total )) ;;
                "[B") cursor=$(( (cursor + 1) % total )) ;;
            esac
        elif [[ "${key}" == "k" || "${key}" == "K" ]]; then
            cursor=$(( (cursor - 1 + total) % total ))
        elif [[ "${key}" == "j" || "${key}" == "J" ]]; then
            cursor=$(( (cursor + 1) % total ))
        elif [ "${mode}" = "menu" ] && [[ "${key}" =~ ^[0-9]$ ]]; then
            local numeric_index
            if [ "${key}" = 0 ]; then
                numeric_index=$((total - 1))
            else
                numeric_index=$((key - 1))
            fi
            if [ "${numeric_index}" -ge 0 ] && [ "${numeric_index}" -lt "${total}" ]; then
                cursor="${numeric_index}"
            fi
        elif [[ "${key}" == " " || "${key}" == "x" || "${key}" == "X" ]] && \
            { [ "${mode}" = "checklist" ] || [ "${mode}" = "settings" ]; }; then
            if [ "${mode}" = "settings" ]; then
                case "${item_states[$cursor]}" in
                    on) item_states[$cursor]=off ;;
                    off) item_states[$cursor]=on ;;
                esac
            elif [ "$cursor" -eq 0 ]; then
                local any_unsel=0
                for ((j=0; j<count; j++)); do
                    [ "${item_states[$j]}" -eq 0 ] && any_unsel=1 && break
                done
                local new_state=1
                [ "$any_unsel" -eq 0 ] && new_state=0
                for ((j=0; j<count; j++)); do
                    item_states[$j]=$new_state
                done
            else
                local target_idx=$((cursor - 1))
                if [ "${item_states[$target_idx]}" -eq 1 ]; then
                    item_states[$target_idx]=0
                else
                    item_states[$target_idx]=1
                fi
            fi
        elif [[ "${key}" == "" ]]; then
            if [ "${mode}" = "settings" ] && \
                { [ "${item_states[$cursor]}" = on ] || [ "${item_states[$cursor]}" = off ]; }; then
                case "${item_states[$cursor]}" in
                    on) item_states[$cursor]=off ;;
                    off) item_states[$cursor]=on ;;
                esac
            else
                break
            fi
        elif [[ "${key}" == "q" || "${key}" == "Q" ]]; then
            cancelled=1
            break
        fi

        if [ "${interactive_terminal}" -eq 1 ]; then
            printf "\033[%dA" "${redraw_rows}"
        fi
        if [ "${interactive_terminal}" -eq 1 ] || [ "${mode}" = "menu" ] || [ "${mode}" = "settings" ]; then
            for ((i=0; i<total; i++)); do
                local is_c=0
                [ "$i" -eq "$cursor" ] && is_c=1
                render_row "$i" "$is_c"
            done
            if [ "${mode}" = "checklist" ] || [ "${mode}" = "menu" ] || [ "${mode}" = "settings" ]; then
                echo ""
                echo "${controls}"
            fi
        fi
    done
    [ "${interactive_terminal}" -eq 1 ] && printf "\033[?25h" 2>/dev/null || true

    echo ""
    if [ "$cancelled" -eq 1 ]; then
        return 1
    fi

    if [ "${mode}" = "checklist" ]; then
        CHECKLIST_RESULTS=()
        for ((i=0; i<count; i++)); do
            CHECKLIST_RESULTS["${item_names[$i]}"]="${item_states[$i]}"
        done
    elif [ "${mode}" = "settings" ]; then
        declare -gA INTERACTIVE_MENU_STATES=()
        for ((i=0; i<count; i++)); do
            INTERACTIVE_MENU_STATES["${item_names[$i]}"]="${item_states[$i]}"
        done
        INTERACTIVE_MENU_SELECTION="${cursor}"
    else
        INTERACTIVE_MENU_SELECTION="${cursor}"
    fi
    return 0
}

interactive_checklist() {
    interactive_menu checklist "$@"
}

run_add_git_repo() {
    echo ""
    echo "============================================================="
    echo "                 Add Git Repository"
    echo "============================================================="
    echo "Enter external Git repository URLs to clone as submodules."
    echo "Type 'done' when finished, or 'c' / 'cancel' to return."
    echo ""

    local added_count=0
    local newly_added_dirs=()

    while true; do
        local repo_url=""
        read -r -p "Enter Git Repository URL (or 'done' to finish, 'c' to cancel): " repo_url || repo_url=""
        repo_url="$(echo "${repo_url}" | tr -d ' \r\n')"

        if [ -z "${repo_url}" ] || [[ "${repo_url}" =~ ^(c|cancel)$ ]]; then
            if [ "${added_count}" -eq 0 ]; then
                echo "  [INFO] No repositories added. Returning to Home."
                return 1
            fi
            break
        fi

        if [[ "${repo_url}" =~ ^(done|exit|quit|q)$ ]]; then
            break
        fi

        local repo_name
        repo_name="$(basename "${repo_url}" .git)"

        echo "  [*] Inspecting repository structure for ${repo_name}..."
        local tmp_inspect
        tmp_inspect="$(mktemp -d 2>/dev/null || mktemp -d -t 'haws_inspect_XXXXXX')"
        if ! git clone --depth 1 -q "${repo_url}" "${tmp_inspect}" 2>/dev/null; then
            echo "  [ERROR] Failed to clone ${repo_url}. Please verify URL and credentials."
            rm -rf "${tmp_inspect}" 2>/dev/null || true
            continue
        fi

        local total_skills=0
        total_skills=$(find "${tmp_inspect}" -type f \( -name "SKILL.md" -o -name "skill.md" \) 2>/dev/null | wc -l || echo "0")

        local target_dir="skills/packs/${repo_name}"
        local target_type="PACK"
        if [ -f "${tmp_inspect}/SKILL.md" ] || [ -f "${tmp_inspect}/skill.md" ] || [ "${total_skills}" -eq 1 ]; then
            target_dir="skills/standalone/${repo_name}"
            target_type="SINGLE"
            echo "  [✓] Auto-detected: Single Skill repository (1 skill found)"
        elif [ "${total_skills}" -gt 1 ]; then
            target_dir="skills/packs/${repo_name}"
            target_type="PACK"
            echo "  [✓] Auto-detected: Multi-Skill Pack repository (${total_skills} skills found)"
        else
            echo "  [WARNING] No SKILL.md found in repository. Registering as pack."
        fi
        rm -rf "${tmp_inspect}" 2>/dev/null || true

        echo "  [*] Adding submodule: ${repo_name} -> ${target_dir}..."
        if git -C "${SCRIPT_DIR}" submodule add "${repo_url}" "${target_dir}" 2>/dev/null || \
           git -C "${SCRIPT_DIR}" clone "${repo_url}" "${target_dir}" 2>/dev/null; then
            git -C "${SCRIPT_DIR}" submodule update --init --recursive "${target_dir}" 2>/dev/null || true
            echo "  [✓] Successfully added and downloaded ${repo_name} (${target_type})."
            added_count=$((added_count + 1))
            newly_added_dirs+=("${target_dir}")
        else
            echo "  [ERROR] Failed to add submodule ${repo_url}."
        fi
        echo ""
    done

    if [ "${added_count}" -eq 0 ]; then
        return 1
    fi

    echo ""
    echo "============================================================="
    echo "Successfully downloaded ${added_count} new repository/repositories!"
    echo "============================================================="
    local configure_now="n"
    read -r -p "Configure active skills now? [y/N] (Default: N - enable all skills): " configure_now || configure_now="n"
    configure_now="$(echo "${configure_now}" | tr -d ' \r\n')"

    if [[ "${configure_now}" =~ ^[Yy] ]]; then
        run_skills_route || true
    else
        echo "  [✓] Kept all skills enabled by default."
    fi

    echo ""
    echo "  [✓] Add Git Repository complete. Returning to Home."
    return 0
}

run_remove_git_repo() {
    echo ""
    echo "============================================================="
    echo "                Remove Git Repository"
    echo "============================================================="
    echo "Select repository/repositories to remove from Git and disk."
    echo ""

    local repos=()
    local repo_paths=()
    local repo_types=()
    local checklist_items=()

    if [ -f "${SCRIPT_DIR}/.gitmodules" ]; then
        while IFS=' ' read -r key url; do
            [ -z "${key}" ] || [ -z "${url}" ] && continue
            local path="${key#submodule.}"
            path="${path%.url}"
            local name="$(basename "${path}")"
            local stype="PACK"
            [[ "${path}" =~ standalone ]] && stype="SINGLE"
            repos+=("${name}")
            repo_paths+=("${path}")
            repo_types+=("${stype}")
            checklist_items+=("${name}|[${stype}] ${path}|0")
        done < <(git -C "${SCRIPT_DIR}" config --file .gitmodules --get-regexp url 2>/dev/null || true)
    fi

    if [ "${#checklist_items[@]}" -eq 0 ]; then
        echo "  No external git repositories currently installed."
        read -r -p "Press [Enter] to return to Home: " _dummy || true
        return 1
    fi

    declare -A CHECKLIST_RESULTS
    if ! interactive_checklist "Select Repositories to REMOVE" "${checklist_items[@]}"; then
        echo "  [INFO] Removal cancelled. Kept all repositories."
        return 1
    fi

    local selected_repos=()
    local selected_paths=()
    local selected_types=()

    for ((i=0; i<${#repos[@]}; i++)); do
        local rname="${repos[$i]}"
        if [ "${CHECKLIST_RESULTS[$rname]:-0}" -eq 1 ]; then
            selected_repos+=("${rname}")
            selected_paths+=("${repo_paths[$i]}")
            selected_types+=("${repo_types[$i]}")
        fi
    done

    if [ "${#selected_repos[@]}" -eq 0 ]; then
        echo "  [✓] No repositories selected for removal. Kept all."
        return 1
    fi

    echo ""
    echo "Selected for REMOVAL:"
    for ((i=0; i<${#selected_repos[@]}; i++)); do
        echo "  [-] ${selected_repos[$i]} [${selected_types[$i]}] (${selected_paths[$i]})"
    done
    echo ""
    local confirm_del="n"
    read -r -p "Remove the ${#selected_repos[@]} selected repository/repositories from Git and disk? [y/N]: " confirm_del || confirm_del="n"
    confirm_del="$(echo "${confirm_del}" | tr -d ' \r\n')"

    if [[ ! "${confirm_del}" =~ ^[Yy] ]]; then
        echo "  [INFO] Removal cancelled. Kept all repositories."
        return 1
    fi

    load_disabled_skills
    for ((i=0; i<${#selected_repos[@]}; i++)); do
        local r_name="${selected_repos[$i]}"
        local r_path="${selected_paths[$i]}"
        local r_type="${selected_types[$i]}"
        echo "  [*] Removing ${r_type}: ${r_name} (${r_path})..."

        # Clean any skills in this repo from DISABLED_SKILLS
        if [ -d "${SCRIPT_DIR}/${r_path}" ]; then
            while IFS= read -r sf; do
                local sn
                sn="$(basename "$(dirname "$sf")")"
                unset "DISABLED_SKILLS[$sn]"
            done < <(find "${SCRIPT_DIR}/${r_path}" -type f \( -name "SKILL.md" -o -name "skill.md" \) 2>/dev/null || true)
        fi

        git -C "${SCRIPT_DIR}" submodule deinit -f -- "${r_path}" 2>/dev/null || true
        git -C "${SCRIPT_DIR}" rm -f "${r_path}" 2>/dev/null || true
        rm -rf "${SCRIPT_DIR}/.git/modules/${r_path}" 2>/dev/null || true
        rm -rf "${SCRIPT_DIR}/${r_path}" 2>/dev/null || true
        echo "  [✓] Removed ${r_name} from disk and Git."
    done
    save_disabled_skills
    return 0
}


run_interactive_kit_setup() {
    run_setup "$@"
}

run_kit() {
    local action="${1:-status}"
    shift || true

    case "${action}" in
        add)
            local target_type="skill"
            local url=""
            local name=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    --skill) target_type="skill"; shift ;;
                    --tool) target_type="tool"; shift ;;
                    *)
                        if [ -z "${url}" ]; then
                            url="$1"
                        elif [ -z "${name}" ]; then
                            name="$1"
                        fi
                        shift
                        ;;
                esac
            done

            if [ -z "${url}" ]; then
                echo "Usage: ./haws.sh kit add <git-url> [name]"
                return 1
            fi

            if [ -z "${name}" ]; then
                name="$(basename "${url}" .git)"
            fi

            local dest_path="skills/packs/${name}"

            echo "=== Adding ${target_type} to KIT: ${name} ==="
            git -C "${SCRIPT_DIR}" submodule add "${url}" "${dest_path}"
            git -C "${SCRIPT_DIR}" submodule update --init --recursive "${dest_path}"
            echo "  [✓] Submodule added at ${dest_path}"
            run_sync
            ;;
        prune|remove|rm)
            local name="${1:-}"
            if [ -z "${name}" ]; then
                echo "Usage: ./haws.sh kit prune <name>"
                return 1
            fi

            echo "=== Pruning from KIT: ${name} ==="
            local found_path=""
            for candidate in "skills/packs/${name}" "skills/standalone/${name}" "skills/custom/${name}"; do
                if [ -d "${SCRIPT_DIR}/${candidate}" ] || grep -q "${candidate}" "${SCRIPT_DIR}/.gitmodules" 2>/dev/null; then
                    found_path="${candidate}"
                    break
                fi
            done

            if [ -z "${found_path}" ]; then
                echo "  [ERROR] Submodule or tool '${name}' not found."
                return 1
            fi

            echo "  [*] Deinitializing submodule ${found_path}..."
            git -C "${SCRIPT_DIR}" submodule deinit -f -- "${found_path}" 2>/dev/null || true
            echo "  [*] Removing from git index and working tree..."
            git -C "${SCRIPT_DIR}" rm -f "${found_path}" 2>/dev/null || true
            echo "  [*] Purging internal submodule git cache..."
            rm -rf "${SCRIPT_DIR}/.git/modules/${found_path}" 2>/dev/null || true
            rm -rf "${SCRIPT_DIR}/${found_path}" 2>/dev/null || true
            echo "  [✓] ${name} pruned completely (Zero ghost files)."
            run_sync --clean
            ;;
        update)
            local target="${1:-}"
            echo "=== HAWS KIT Submodule Remote Updater ==="
            echo "Preserving local configuration: only updating submodules present in local .gitmodules."
            echo "Local 'skills/custom/' remains 100% protected and untouched."
            echo ""

            if [ ! -f "${SCRIPT_DIR}/.gitmodules" ]; then
                echo "  [INFO] No .gitmodules file found. Nothing to update."
                return 0
            fi

            if [ -n "${target}" ]; then
                local found_path=""
                for candidate in "skills/packs/${target}" "skills/standalone/${target}"; do
                    if grep -q "${candidate}" "${SCRIPT_DIR}/.gitmodules" 2>/dev/null; then
                        found_path="${candidate}"
                        break
                    fi
                done
                if [ -z "${found_path}" ]; then
                    echo "  [ERROR] Submodule '${target}' not found in local .gitmodules."
                    return 1
                fi
                echo "  [*] Updating submodule [${target}] (${found_path}) from remote link..."
                git -C "${SCRIPT_DIR}" submodule update --remote --merge "${found_path}" 2>/dev/null || \
                git -C "${SCRIPT_DIR}" submodule update --remote "${found_path}" 2>/dev/null || true
                echo "  [✓] Submodule ${target} updated successfully."
            else
                echo "  [*] Scanning active submodules in local .gitmodules..."
                local updated_count=0
                while IFS= read -r sub_path; do
                    [ -z "${sub_path}" ] && continue
                    if [ -d "${SCRIPT_DIR}/${sub_path}" ]; then
                        echo "  --> Updating [${sub_path}] from remote link..."
                        git -C "${SCRIPT_DIR}" submodule update --remote --merge "${sub_path}" 2>/dev/null || \
                        git -C "${SCRIPT_DIR}" submodule update --remote "${sub_path}" 2>/dev/null || true
                        updated_count=$((updated_count + 1))
                    fi
                done < <(git -C "${SCRIPT_DIR}" config --file .gitmodules --get-regexp path 2>/dev/null | awk '{print $2}')
                echo "  [✓] Updated ${updated_count} active submodule(s) from remote links."
            fi
            echo ""
            run_sync
            ;;
        edit|modules)
            run_edit_gitmodules
            echo ""
            run_sync
            ;;
        setup|interactive)
            echo "=== HAWS Skill Kit Setup & Adjustment ==="
            echo "Choose your skill kit setup mode:"
            echo "  1) Standard HAWS Kit (Default)"
            echo "  2) Custom Setup (Select, remove, or add skills)"
            echo "  3) Edit .gitmodules (Open file to edit links directly)"
            local mode_choice="1"
            if [ -t 0 ]; then
                read -r -p "Enter selection [1-3] (default: 1): " mode_choice || mode_choice="1"
                mode_choice="$(echo "${mode_choice}" | tr -d ' \r\n')"
                [ -z "${mode_choice}" ] && mode_choice="1"
            fi
            if [ "${mode_choice}" = "2" ]; then
                run_interactive_kit_setup
            elif [ "${mode_choice}" = "3" ]; then
                run_edit_gitmodules
                echo ""
                run_sync
            else
                echo ""
                echo "Applying Standard HAWS Kit configuration..."
                git -C "${SCRIPT_DIR}" submodule update --init --recursive
                run_sync
            fi
            ;;
        list|status)
            echo "=== HAWS KIT Installed Submodules & Tools ==="
            if [ -f "${SCRIPT_DIR}/.gitmodules" ]; then
                git -C "${SCRIPT_DIR}" submodule status
            else
                echo "  No submodules configured."
            fi
            ;;
        *)
            echo "Usage: ./haws.sh kit [setup|edit|add|prune|update|list]"
            return 1
            ;;
    esac
}

symmetrical_merge_secondbrain() {
    local brain_dir="$1"
    local py_bin=""
    for candidate in python3 python3.11 python3.12 py python; do
        if command -v "${candidate}" &>/dev/null && "${candidate}" -c "import sys" &>/dev/null; then
            py_bin="${candidate}"
            break
        fi
    done

    # 1. Commit any local working changes first
    git -C "${brain_dir}" add . 2>/dev/null || true
    git -C "${brain_dir}" commit -m "chore(brain): pre-merge local snapshot" --quiet 2>/dev/null || true

    # 2. Reconcile Git commit graphs with -s ours to establish common ancestor
    git -C "${brain_dir}" merge origin/main --allow-unrelated-histories -s ours --no-edit -m "chore(brain): symmetrical merge and deduplication" 2>/dev/null || true

    # 3. If python is available, run content deduplication & transaction sorting
    if [ -n "${py_bin}" ]; then
        ${py_bin} -c '
import os, sys, re, subprocess

def run_merge(brain_dir):
    def get_git_file(ref, filepath):
        try:
            cmd = ["git", "-C", brain_dir, "show", ref + ":" + filepath]
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            out, _ = p.communicate()
            if p.returncode == 0:
                try: return out.decode("utf-8")
                except: return out
            return ""
        except: return ""

    def read_local(filepath):
        p = os.path.join(brain_dir, filepath)
        if os.path.isfile(p):
            with open(p, "rb") as f:
                c = f.read()
                try: return c.decode("utf-8")
                except: return c
        return ""

    def merge_anti(local_txt, remote_txt):
        def extract_items(txt):
            items = {}
            curr_key = None
            curr_lines = []
            curr_date = "2026-01-01"
            for line in txt.splitlines():
                m = re.match(r"^\s*-\s*\*\*\[Learned\s+(\d{4}-\d{2}-\d{2})\]\*\*:\s*(`[^`]+`)(.*)", line)
                if m:
                    if curr_key: items[curr_key] = (curr_date, "\n".join(curr_lines).strip())
                    curr_date = m.group(1)
                    curr_key = m.group(2).strip()
                    curr_lines = [line]
                elif curr_key and (line.startswith("  ") or line.startswith("\t")):
                    curr_lines.append(line)
                elif curr_key and not line.strip(): pass
                else:
                    if curr_key:
                        items[curr_key] = (curr_date, "\n".join(curr_lines).strip())
                        curr_key = None
                        curr_lines = []
            if curr_key: items[curr_key] = (curr_date, "\n".join(curr_lines).strip())
            return items

        l_items = extract_items(local_txt)
        r_items = extract_items(remote_txt)
        all_keys = set(l_items.keys()) | set(r_items.keys())
        merged = []
        for k in all_keys:
            if k in l_items and k in r_items:
                ld, lc = l_items[k]
                rd, rc = r_items[k]
                chosen = lc if len(lc) >= len(rc) else rc
                merged.append((max(ld, rd), chosen))
            elif k in l_items: merged.append(l_items[k])
            else: merged.append(r_items[k])

        merged.sort(key=lambda x: x[0], reverse=True)
        hdr = (
            "# Anti-Patterns & Failure Modes (Second Brain)\n\n"
            "This document records operational anti-patterns and concrete failure modes observed in agent sessions. All AI agents must actively avoid these behaviors across all sessions, projects, and tools.\n\n"
            "---\n\n"
            "## Operational Anti-Patterns\n"
        )
        return hdr + "\n" + "\n".join([item[1] for item in merged]) + "\n"

    def merge_pref(local_txt, remote_txt):
        def parse_secs(txt):
            secs = {}
            curr = "Introduction"
            secs[curr] = []
            for line in txt.splitlines():
                m = re.match(r"^(##\s+.*)", line)
                if m:
                    curr = m.group(1).strip()
                    secs.setdefault(curr, [])
                else: secs[curr].append(line)
            return secs

        l_secs = parse_secs(local_txt)
        r_secs = parse_secs(remote_txt)
        ordered = ["Introduction", "## 1. Interaction & Communication Style", "## 2. Engineering & Architectural Conventions", "## 3. Tool & Command Conventions"]
        for s in list(l_secs.keys()) + list(r_secs.keys()):
            if s not in ordered: ordered.append(s)

        out = []
        for s in ordered:
            if s != "Introduction": out.append("\n---\n\n" + s)
            l_lines = l_secs.get(s, [])
            r_lines = r_secs.get(s, [])

            def get_bullets(lines):
                bul = {}
                hdr = []
                cur_k = None
                cur_lines = []
                for l in lines:
                    m = re.match(r"^\s*-\s*\*\*([^*]+)\*\*:\s*(.*)", l)
                    if m:
                        if cur_k: bul[cur_k] = "\n".join(cur_lines).strip()
                        cur_k = m.group(1).strip()
                        cur_lines = [l]
                    elif cur_k and (l.startswith("  ") or l.startswith("\t")): cur_lines.append(l)
                    elif cur_k and not l.strip(): pass
                    else:
                        if cur_k:
                            bul[cur_k] = "\n".join(cur_lines).strip()
                            cur_k = None
                            cur_lines = []
                        if l.strip() and not l.startswith("---") and not l.startswith("#"): hdr.append(l)
                if cur_k: bul[cur_k] = "\n".join(cur_lines).strip()
                return hdr, bul

            l_h, l_b = get_bullets(l_lines)
            r_h, r_b = get_bullets(r_lines)
            seen_h = set()
            for line in h:
                sline = line.strip()
                if sline:
                    if "This document records the user" in sline:
                        continue
                    if sline not in seen_h:
                        seen_h.add(sline)
                        out.append(line)

            all_keys = []
            for k in list(r_b.keys()) + list(l_b.keys()):
                if k not in all_keys: all_keys.append(k)

            for k in all_keys:
                if k in l_b and k in r_b:
                    chosen = l_b[k] if len(l_b[k]) > len(r_b[k]) else r_b[k]
                    out.append(chosen)
                elif k in l_b: out.append(l_b[k])
                else: out.append(r_b[k])

        hdr = (
            "# User Preferences & Style Guide (Second Brain)\n\n"
            "This document records the user'\''s permanent preferences, communication style, and architectural conventions. All AI agents must adhere to these preferences across all sessions, projects, and tools.\n"
        )
        return hdr + "\n" + "\n".join(out).strip() + "\n"

    l_anti = read_local("ANTI_PATTERNS.md")
    r_anti = get_git_file("origin/main", "ANTI_PATTERNS.md")
    if l_anti or r_anti:
        m_anti = merge_anti(l_anti, r_anti)
        with open(os.path.join(brain_dir, "ANTI_PATTERNS.md"), "wb") as f:
            f.write(m_anti.encode("utf-8"))

    l_pref = read_local("USER_PREFERENCES.md")
    r_pref = get_git_file("origin/main", "USER_PREFERENCES.md")
    if l_pref or r_pref:
        m_pref = merge_pref(l_pref, r_pref)
        with open(os.path.join(brain_dir, "USER_PREFERENCES.md"), "wb") as f:
            f.write(m_pref.encode("utf-8"))

run_merge("'"${brain_dir}"'")
' 2>/dev/null || true
    fi

    # 4. Stage and commit the clean merged files
    git -C "${brain_dir}" add . 2>/dev/null || true
    git -C "${brain_dir}" commit --amend --no-edit 2>/dev/null || git -C "${brain_dir}" commit -m "chore(brain): symmetrical merge and deduplication" --quiet 2>/dev/null || true
}

run_user() {
    local action="${1:-status}"
    shift || true

    local brain_dir="${SCRIPT_DIR}/secondbrain"
    mkdir -p "${brain_dir}"

    if [ ! -d "${brain_dir}/.git" ]; then
        git -C "${brain_dir}" init -b main --quiet 2>/dev/null || git -C "${brain_dir}" init --quiet
        git -C "${brain_dir}" config user.name "HAWS User" 2>/dev/null || true
        git -C "${brain_dir}" config user.email "user@haws.local" 2>/dev/null || true
        if [ ! -f "${brain_dir}/USER_PREFERENCES.md" ]; then
            cat << 'EOF' > "${brain_dir}/USER_PREFERENCES.md"
# Personal User Preferences

> **Purpose**: Preserves personal developer preferences, habits, architectural styles, and communication rules across all AI tools and sessions.

## Communication Style
- Concise, clear, direct.
- Explain reasoning and trade-offs.

## Technology Preferences
- Coding Conventions: Clean modular architecture, standard libraries first.
EOF
        fi
        if [ ! -f "${brain_dir}/ANTI_PATTERNS.md" ]; then
            cat << 'EOF' > "${brain_dir}/ANTI_PATTERNS.md"
# Permanent Anti-Patterns & Operational Safeguards

> **Purpose**: Records learned mistakes, forbidden patterns, and operational constraints to prevent regressions across sessions.

## Operational Safeguards
- No destructive git operations without human confirmation.
- Evidence before assertions: run verification tests before claiming success.
EOF
        fi
        git -C "${brain_dir}" add . 2>/dev/null || true
        git -C "${brain_dir}" commit -m "Initialize second brain" --quiet 2>/dev/null || true
    fi

    case "${action}" in
        connect)
            local repo_url="${1:-}"
            repo_url="$(echo "${repo_url}" | tr -d '\r\n' | xargs 2>/dev/null || true)"
            if [ -z "${repo_url}" ]; then
                read -r -p "Enter Private GitHub Repository URL (e.g. git@github.com:user/my-haws-brain.git): " repo_url
                repo_url="$(echo "${repo_url}" | tr -d '\r\n' | xargs 2>/dev/null || true)"
            fi
            if [ -z "${repo_url}" ] || [[ "${repo_url}" =~ ^[[:space:]]*$ ]]; then
                echo "  [ERROR] No valid URL provided. Aborted."
                return 1
            fi
            if [[ ! "${repo_url}" =~ (git@|https?://|ssh://|file://|^/|^[A-Za-z]:|^(\.\.?/)) ]]; then
                echo "  [ERROR] Invalid Git repository URL format: '${repo_url}'"
                echo "  [INFO] URL must start with git@, https://, ssh://, or be a valid repository path."
                return 1
            fi

            echo "============================================================="
            echo "             HAWS Second Brain Connect"
            echo "============================================================="
            echo " [PRIVACY NOTICE] Ensure your repository is set to PRIVATE on GitHub!"
            echo " Second Brain stores personal notes & anti-patterns and must NEVER be Public."
            echo "============================================================="
            echo "  [*] Connecting Second Brain, please wait..."
            if git -C "${brain_dir}" remote get-url origin &>/dev/null; then
                git -C "${brain_dir}" remote set-url origin "${repo_url}"
            else
                git -C "${brain_dir}" remote add origin "${repo_url}"
            fi

            echo "  [*] Testing remote connection..."
            if git -C "${brain_dir}" fetch origin main --quiet 2>/dev/null; then
                echo "  [*] Remote repo has existing history. Performing Symmetrical Merge..."
                symmetrical_merge_secondbrain "${brain_dir}"
                if git -C "${brain_dir}" push -u origin main --quiet 2>/dev/null; then
                    echo "  [✓] Second brain synced and connected to ${repo_url}"
                else
                    echo "  [ERROR] Failed to push merged updates to ${repo_url}."
                    return 1
                fi
            else
                echo "  [*] Remote is fresh or initial push. Publishing local brain..."
                if git -C "${brain_dir}" push -u origin main --quiet 2>/dev/null; then
                    echo "  [✓] Local second brain pushed to cloud ${repo_url}"
                else
                    echo "  [ERROR] Failed to connect or push to ${repo_url}."
                    echo "  [INFO] Please check URL, network, or GitHub SSH/Token authentication."
                    git -C "${brain_dir}" remote remove origin 2>/dev/null || true
                    return 1
                fi
            fi
            ;;
        disconnect)
            local confirm="${1:-}"
            local current_remote
            current_remote="$(git -C "${brain_dir}" remote get-url origin 2>/dev/null || echo "")"
            if [ -z "${current_remote}" ]; then
                echo "  Second Brain is currently in Local-Only mode (not connected)."
                return 0
            fi

            if [[ ! "${confirm}" =~ ^(-y|--yes|-f|--force)$ ]]; then
                echo "============================================================="
                echo " [GUARD] WARNING: Disconnecting Second Brain Cloud"
                echo " Current Remote: ${current_remote}"
                echo " This machine will return to Local-Only mode."
                echo " (Your cloud repository data will NOT be deleted)."
                echo "============================================================="
                read -r -p "Are you sure you want to disconnect? [y/N]: " confirm
            fi
            if [[ "${confirm}" =~ ^([Yy]|-y|--yes|-f|--force)$ ]]; then
                git -C "${brain_dir}" remote remove origin
                echo "  [✓] Successfully disconnected. Local-Only mode active."
            else
                echo "  [Aborted] Cloud connection preserved."
            fi
            ;;
        sync)
            local current_remote
            current_remote="$(git -C "${brain_dir}" remote get-url origin 2>/dev/null || echo "")"
            if [ -n "${current_remote}" ]; then
                echo "  [*] Syncing Second Brain, please wait..."
                echo "      Remote: ${current_remote}"
                git -C "${brain_dir}" add . 2>/dev/null || true
                git -C "${brain_dir}" commit -m "chore(brain): auto-sync local updates" --quiet 2>/dev/null || true
                if ! git -C "${brain_dir}" pull --rebase origin main --quiet 2>/dev/null; then
                    echo "  [*] Symmetrical reconciliation required..."
                    git -C "${brain_dir}" rebase --abort 2>/dev/null || true
                    git -C "${brain_dir}" fetch origin main --quiet 2>/dev/null || true
                    symmetrical_merge_secondbrain "${brain_dir}"
                fi
                git -C "${brain_dir}" push origin main --quiet 2>/dev/null || true
                echo "  [✓] Second Brain in sync."
            else
                echo "  [i] Second Brain is Local-Only. (Connect cloud anytime via './haws.sh user connect <url>')"
            fi
            ;;
        status)
            local current_remote
            current_remote="$(git -C "${brain_dir}" remote get-url origin 2>/dev/null || echo "")"
            echo "============================================================="
            echo "                 HAWS Second Brain Status"
            echo "============================================================="
            if [ -n "${current_remote}" ]; then
                echo "Mode          : [ONLINE / CONNECTED]"
                echo "Remote URL    : ${current_remote}"
                local commit_count
                commit_count="$(git -C "${brain_dir}" rev-list --count HEAD 2>/dev/null || echo 0)"
                echo "Total Commits : ${commit_count}"
            else
                echo "Mode          : [LOCAL-ONLY (Zero Cloud Telemetry)]"
                echo "Path          : ${brain_dir}"
                echo "Status        : [SAFE & CONFINED TO THIS MACHINE]"
                echo "Hint          : Run './haws.sh user connect <url>' to enable cross-device cloud sync."
            fi
            ;;
        *)
            echo "Usage: ./haws.sh user [connect|disconnect|sync|status]"
            return 1
            ;;
    esac
}

second_brain_detail_page() {
    local brain_dir="$(_second_brain_dir)"
    local current_remote confirm url commit_count
    echo ""
    echo "============================================================="
    echo "                 HAWS Second Brain Status"
    echo "============================================================="
    current_remote="$(_second_brain_remote_url)"
    if [ -n "${current_remote}" ]; then
        echo "Mode          : [ONLINE / CONNECTED]"
        echo "Remote URL    : ${current_remote}"
        commit_count="$(git -C "${brain_dir}" rev-list --count HEAD 2>/dev/null || echo 0)"
        echo "Total Commits : ${commit_count}"
        echo ""
        confirm=""
        printf '%s' "Do you want to disconnect? (y/N): "
        read -r confirm || confirm=""
        printf '\n'
        if [[ "${confirm}" =~ ^[Yy]$ ]]; then
            run_user disconnect --yes || return $?
        else
            echo "  [INFO] Disconnect cancelled. Connection preserved."
        fi
    else
        echo "Mode          : [LOCAL-ONLY (Zero Cloud Telemetry)]"
        echo "Path          : ${brain_dir}"
        echo "Status        : [SAFE & CONFINED TO THIS MACHINE]"
        echo ""
        confirm=""
        printf '%s' "Do you want to connect? (y/N): "
        read -r confirm || confirm=""
        printf '\n'
        if [[ "${confirm}" =~ ^[Yy]$ ]]; then
            url=""
            read -r -p "Enter Private GitHub Repository URL (blank cancels): " url || url=""
            url="${url%$'\r'}"
            if [ -z "${url}" ]; then
                echo "  [INFO] Connection cancelled."
                return 0
            fi
            run_user connect "${url}" || return $?
        else
            echo "  [INFO] Connection cancelled."
        fi
    fi
    return 0
}

run_hooks() {
    local action="${1:-install}"
    case "${action}" in
        install)
            echo "=== Installing HAWS Git Hooks ==="
            if [ -d "${SCRIPT_DIR}/.githooks" ]; then
                if ! git -C "${SCRIPT_DIR}" config core.hooksPath .githooks; then
                    echo "  [ERROR] Could not configure Git core.hooksPath"
                    return 1
                fi
                chmod +x "${SCRIPT_DIR}/.githooks/commit-msg" 2>/dev/null || true
                echo "  [✓] Git core.hooksPath set to .githooks"
                echo "  [✓] commit-msg hook active (Conventional Commits & English invariant)"
            else
                echo "  [ERROR] .githooks directory not found in ${SCRIPT_DIR}"
                return 1
            fi
            ;;
        status)
            local current_hooks
            current_hooks="$(git -C "${SCRIPT_DIR}" config core.hooksPath 2>/dev/null || echo "default (.git/hooks)")"
            echo "=== HAWS Git Hooks Status ==="
            echo "Current core.hooksPath: ${current_hooks}"
            if [ "${current_hooks}" = ".githooks" ]; then
                echo "Status: [ACTIVE & GUARDED]"
            else
                echo "Status: [INACTIVE - Run './haws.sh hook install' to activate]"
            fi
            ;;
        *)
            echo "Usage: ./haws.sh hook [install|status]"
            return 1
            ;;
    esac
}


_uninstall_native_path() {
    local path="$1"
    case "$path" in
        [A-Za-z]:[\\/]*)
            if command -v cygpath >/dev/null 2>&1; then
                cygpath -u -- "$path"
            else
                printf '%s\n' "$path"
            fi
            ;;
        *) printf '%s\n' "$path" ;;
    esac
}

canonical_path() {
    local path
    path="$(_uninstall_native_path "$1")"
    if command -v realpath >/dev/null 2>&1; then
        realpath -m -- "$path" 2>/dev/null && return 0
    fi
    if [ -e "$path" ] || [ -L "$path" ]; then
        readlink -f -- "$path" 2>/dev/null && return 0
    fi
    case "$path" in
        /*) printf '%s\n' "$path" ;;
        *) printf '%s/%s\n' "$PWD" "$path" ;;
    esac
}

_ownership_path_safe() {
    local path="$(_uninstall_native_path "$1")"
    local repo="$(_health_repo)"
    local state="$(_health_state)"
    [ -n "$path" ] || return 1
    [ "$path" != / ] && [ "$path" != "$HOME" ] &&
        [ "$path" != "$repo" ] && [ "$path" != "$state" ] || return 1
    case "$path" in
        *"/../"*|*"/./"*|../*|./*) return 1 ;;
    esac
    local parent home_root repo_root state_root
    parent="$(canonical_path "$(dirname "$path")" 2>/dev/null || true)"
    home_root="$(canonical_path "$HOME" 2>/dev/null || true)"
    repo_root="$(canonical_path "$repo" 2>/dev/null || true)"
    state_root="$(canonical_path "$state" 2>/dev/null || true)"
    [ -n "$parent" ] && [ -n "$home_root" ] && [ -n "$repo_root" ] || return 1
    case "$parent" in
        "$state_root"|"$state_root"/*) return 1 ;;
        "$home_root"|"$home_root"/*|"$repo_root"|"$repo_root"/*) return 0 ;;
        *) return 1 ;;
    esac
}

ownership_verify() {
    local record="$1"
    local kind path source fingerprint extra
    IFS=$'\t' read -r kind path source fingerprint extra <<< "$record"
    [ -n "$kind" ] && [ -n "$path" ] || return 1
    local actual="$(_uninstall_native_path "$path")"
    _ownership_path_safe "$actual" || return 3

    case "$kind" in
        symlink|junction|directory-link)
            [ -L "$actual" ] || return 1
            local current current_path source_path current_canonical source_canonical
            current="$(readlink "$actual" 2>/dev/null || true)"
            [ -n "$current" ] || return 1
            current_path="$current"
            source_path="$source"
            case "$current_path" in
                /*|[A-Za-z]:[\\/]*) ;;
                *) current_path="$(dirname "$actual")/$current_path" ;;
            esac
            case "$source_path" in
                /*|[A-Za-z]:[\\/]*) ;;
                *) source_path="$(dirname "$actual")/$source_path" ;;
            esac
            current_path="$(_uninstall_native_path "$current_path")"
            source_path="$(_uninstall_native_path "$source_path")"
            current_canonical="$(canonical_path "$current_path" 2>/dev/null || true)"
            source_canonical="$(canonical_path "$source_path" 2>/dev/null || true)"
            if [ "$current" != "$source" ] &&
                [ "$current_path" != "$source_path" ] &&
                { [ -z "$source_canonical" ] || [ "$current_canonical" != "$source_canonical" ]; }; then
                return 1
            fi
            [ -n "$fingerprint" ] || return 1
            [ "$fingerprint" = "$current" ] ||
                [ "$fingerprint" = "$current_path" ] ||
                [ "$fingerprint" = "$current_canonical" ] ||
                [ "$fingerprint" = "$source_canonical" ]
            ;;
        generated-file|file|hardlink)
            [ -f "$actual" ] && [ ! -L "$actual" ] || return 1
            [ -n "$fingerprint" ] || return 1
            [ "$(_haws_sha256 "$actual")" = "$fingerprint" ]
            ;;
        repository)
            [ -d "$actual" ] && [ ! -L "$actual" ] || return 1
            git -C "$actual" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
            local head repo_status
            repo_status="$(git -C "$actual" status --porcelain --untracked-files=all 2>/dev/null || true)"
            [ -z "$repo_status" ] || return 2
            head="$(git -C "$actual" rev-parse HEAD 2>/dev/null || true)"
            [ -n "$head" ] && [ "$head" = "$fingerprint" ] || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

_uninstall_group_name() {
    case "$1" in
        pointer|pointers|environment|environments) printf '%s\n' environments ;;
        skill|skills) printf '%s\n' skills ;;
        agent|agents) printf '%s\n' agents ;;
        hook|hooks) printf '%s\n' hooks ;;
        metadata|meta) printf '%s\n' metadata ;;
        repository|repositories|source|sources) printf '%s\n' repositories ;;
        *) printf '%s\n' "$1" ;;
    esac
}

uninstall_plan() {
    local temp_dir
    temp_dir="$(printenv TMPDIR 2>/dev/null || true)"
    [ -n "$temp_dir" ] || temp_dir=/tmp
    local plan
    plan="$(mktemp "$temp_dir/haws-uninstall-plan.XXXXXX")" || return 1
    local requested=""
    local group record_group row
    [ "$#" -gt 0 ] && requested="$1"
    [ -n "$requested" ] || requested="environments,skills,agents,hooks,metadata"

    while IFS= read -r group || [ -n "$group" ]; do
        [ -n "$group" ] || continue
        group="$(_uninstall_group_name "$group")"
        case "$group" in
            environments)
                for record_group in environments pointers; do
                    while IFS= read -r row || [ -n "$row" ]; do
                        [ -n "$row" ] || continue
                        printf 'remove\t%s\n' "$row" >> "$plan"
                    done < <(ownership_list "$record_group")
                done
                ;;
            *)
                while IFS= read -r row || [ -n "$row" ]; do
                    [ -n "$row" ] || continue
                    printf 'remove\t%s\n' "$row" >> "$plan"
                done < <(ownership_list "$group")
                ;;
        esac
    done < <(printf '%s\n' "$requested" | tr ',' '\n')
    printf '%s\n' "$plan"
}

uninstall_preview() {
    local plan="$1"
    [ -f "$plan" ] || return 2
    printf '%s\n' "Uninstall preview"
    local action group kind path source fingerprint extra record verify_record verify_status
    while IFS=$'\t' read -r action group kind path source fingerprint extra ||
        [ -n "$action" ]; do
        [ "$action" = remove ] || continue
        verify_record="$kind"$'\t'"$path"$'\t'"$source"$'\t'"$fingerprint"
        if ownership_verify "$verify_record"; then
            printf 'Remove: %s %s %s\n' "$group" "$kind" "$path"
        else
            verify_status="$?"
            if [ "$verify_status" -eq 2 ]; then
                printf 'Blocked: %s %s %s (repository is dirty)\n' "$group" "$kind" "$path"
            else
                printf 'Preserved: %s %s %s (type or fingerprint changed)\n' \
                    "$group" "$kind" "$path"
            fi
        fi
    done < "$plan"
}

_ownership_remove_record() {
    local record="$1"
    local group kind path source fingerprint extra
    IFS=$'\t' read -r group kind path source fingerprint extra <<< "$record"
    local state="$(_health_state)"
    local file="$state/ownership.tsv"
    local temporary="$state/ownership.stage.$$"
    [ -f "$file" ] || return 0
    awk -F $'\t' -v group="$group" -v kind="$kind" -v path="$path" '
        $1 == group && $2 == kind && $3 == path { next }
        { print }
    ' "$file" > "$temporary" || return 1
    _haws_state_replace "$temporary" "$file"
    local result="$?"
    rm -f -- "$temporary"
    return "$result"
}

_uninstall_remove_path() {
    local kind="$1"
    local path="$(_uninstall_native_path "$2")"
    _ownership_path_safe "$path" || return 1
    case "$kind" in
        symlink|junction|directory-link)
            if [ -d "$path" ] && [ -L "$path" ] &&
                command -v cmd.exe >/dev/null 2>&1 &&
                command -v cygpath >/dev/null 2>&1; then
                local windows_path
                windows_path="$(cygpath -w "$path")"
                MSYS_NO_PATHCONV=1 cmd.exe /c rmdir /s /q "$windows_path" >/dev/null 2>&1 || return 1
            else
                rm -f -- "$path" || return 1
            fi
            ;;
        generated-file|file|hardlink)
            rm -f -- "$path" || return 1
            ;;
        repository)
            rm -rf -- "$path" || return 1
            ;;
        *) return 1 ;;
    esac
    [ ! -e "$path" ] && [ ! -L "$path" ]
}

uninstall_apply() {
    local plan="$1"
    [ -f "$plan" ] || return 2
    echo "  [*] Applying uninstall changes, please wait..."
    local status=0
    local processed=0
    local threshold
    threshold="$(printenv HAWS_TEST_UNINSTALL_INTERRUPT_AFTER 2>/dev/null || true)"
    local interrupted=0
    _uninstall_interrupt() { interrupted=1; }
    trap _uninstall_interrupt INT TERM
    local action group kind path source fingerprint extra record verify_record verify_status
    while IFS=$'\t' read -r action group kind path source fingerprint extra ||
        [ -n "$action" ]; do
        [ "$action" = remove ] || continue
        if [ "$interrupted" -eq 1 ]; then
            printf '%s\n' "Interrupted: remaining ownership records were preserved"
            status=130
            break
        fi
        if [ -n "$threshold" ] && [ "$threshold" -eq "$threshold" ] &&
            [ "$processed" -ge "$threshold" ]; then
            printf '%s\n' "Interrupted: remaining ownership records were preserved"
            status=130
            break
        fi
        record="$group"$'\t'"$kind"$'\t'"$path"$'\t'"$source"$'\t'"$fingerprint"
        verify_record="$kind"$'\t'"$path"$'\t'"$source"$'\t'"$fingerprint"
        if ownership_verify "$verify_record"; then
            if _uninstall_remove_path "$kind" "$path"; then
                _ownership_remove_record "$record" || status=1
                printf 'Removed: %s %s %s\n' "$group" "$kind" "$path"
            else
                printf 'Preserved: %s %s %s (removal failed)\n' "$group" "$kind" "$path"
                status=1
            fi
        else
            verify_status="$?"
            if [ "$verify_status" -eq 2 ]; then
                printf 'Blocked: %s %s %s (repository is dirty)\n' "$group" "$kind" "$path"
                status=1
            else
                printf 'Preserved: %s %s %s (type or fingerprint changed)\n' \
                    "$group" "$kind" "$path"
            fi
        fi
        processed=$((processed + 1))
    done < "$plan"
    trap - INT TERM
    return "$status"
}

uninstall_run() {
    local dry_run=0 confirmed=0
    local requested="" arg
    while [ "$#" -gt 0 ]; do
        arg="$1"
        shift
        case "$arg" in
            --dry-run|--preview) dry_run=1 ;;
            --yes|-y) confirmed=1 ;;
            --help|-h)
                printf '%s\n' "Usage: haws.sh uninstall [groups] [--dry-run] [--yes]"
                return 0
                ;;
            *)
                if [[ "$arg" == -* ]]; then
                    printf 'Unknown uninstall option: %s\n' "$arg" >&2
                    return 2
                fi
                if [ -n "$requested" ]; then
                    requested="$requested,$arg"
                else
                    requested="$arg"
                fi
                ;;
        esac
    done

    local plan
    echo ""
    echo "============================================================="
    echo "                   HAWS Uninstall Preview"
    echo "============================================================="
    echo ""
    echo "[*] Building uninstall preview, please wait..."
    if [ -n "$requested" ]; then
        plan="$(uninstall_plan "$requested")" || return $?
    else
        plan="$(uninstall_plan)" || return $?
    fi
    uninstall_preview "$plan" || return $?
    if [ "$dry_run" -eq 1 ]; then
        rm -f -- "$plan"
        return 0
    fi

    echo ""
    echo "============================================================="
    echo "[SAFETY GUARD] Uninstallation will detach global AI pointers,"
    echo "linked skills, subagents, and Git hooks."
    echo ""
    echo "Your project code and Second Brain will NOT be deleted."
    echo "============================================================="
    echo ""

    if [ "$confirmed" -eq 0 ]; then
        local test_keys confirmation
        test_keys="$(printenv HAWS_TEST_KEYS 2>/dev/null || true)"
        if [ -n "$test_keys" ]; then
            confirmation="$test_keys"
        else
            read -r -p "Do you really want to proceed with uninstallation? (y/N): " confirmation || confirmation=""
        fi
        case "$confirmation" in
            y|Y) confirmed=1 ;;
            *) printf '%s\n' "Uninstall cancelled"; rm -f -- "$plan"; return 0 ;;
        esac
    fi
    [ "$confirmed" -eq 1 ] || return 0
    local result
    if uninstall_apply "$plan"; then
        result=0
    else
        result="$?"
    fi
    rm -f -- "$plan"
    return "$result"
}

run_uninstall() {
    uninstall_run "$@"
}

install_is_complete() {
    [ -s "$(_haws_state_dir)/install.complete" ] || [ -s "${HOME}/.haws_manifest" ]
}

_haws_all_environments() {
    printf '%s\n' claude gemini cursor copilot codex
}

_haws_environment_label() {
    case "${1:-}" in
        claude) echo "Claude Code" ;;
        gemini) echo "Google Antigravity" ;;
        cursor) echo "Cursor" ;;
        copilot) echo "GitHub Copilot" ;;
        codex) echo "OpenAI Codex" ;;
        *) echo "${1:-Unknown}" ;;
    esac
}

_haws_toggle_label() {
    case "${1:-}" in
        on) echo "On" ;;
        off) echo "Off" ;;
        *) echo "${1:-Unknown}" ;;
    esac
}

_haws_detected_environments() {
    local environment
    while IFS= read -r environment; do
        case "${environment}" in
            claude) [ -d "${HOME}/.claude" ] || continue ;;
            gemini) [ -d "${HOME}/.gemini" ] || continue ;;
            cursor) {
                [ -d "${HOME}/.cursor" ] || [ -f "${HOME}/.cursorrules" ]
            } || continue ;;
            copilot) {
                [ -d "${HOME}/.copilot" ] || [ -d "${HOME}/.config/github-copilot" ]
            } || continue ;;
            codex) {
                [ -d "${HOME}/.codex" ] || [ -d "${HOME}/.agents" ]
            } || continue ;;
        esac
        printf '%s\n' "${environment}"
    done < <(_haws_all_environments)
}

_settings_list_contains() {
    local list="${1:-}"
    local wanted="${2:-}"
    local value
    while IFS= read -r value || [ -n "${value}" ]; do
        [ "${value}" = "${wanted}" ] && return 0
    done <<< "${list}"
    return 1
}

_settings_list_signature() {
    printf '%s\n' "${1:-}" | sed '/^[[:space:]]*$/d' | sort
}

_settings_url_identity() {
    local url="$1"
    url="${url%/}"
    case "${url}" in
        https://github.com/*) url="${url%.git}" ;;
    esac
    printf '%s\n' "${url}"
}

_settings_source_path_from_url() {
    local url="$1"
    local name="${url##*/}"
    name="${name%.git}"
    printf 'skills/packs/%s\n' "${name}"
}

_settings_list_without() {
    local list="$1"
    local unwanted="$2"
    local value
    while IFS= read -r value || [ -n "${value}" ]; do
        [ -n "${value}" ] || continue
        [ "${value}" = "${unwanted}" ] || printf '%s\n' "${value}"
    done <<< "${list}"
}

_settings_source_path_taken() {
    local wanted="$1"
    local row source_id path url revision
    while IFS= read -r row || [ -n "${row}" ]; do
        [ -n "${row}" ] || continue
        IFS=$'\t' read -r source_id path url revision <<< "${row}"
        [ "${path}" = "${wanted}" ] && return 0
    done < <(catalog_sources)
    _settings_list_contains "${HAWS_DRAFT_ADDED_PATHS:-}" "${wanted}"
}

settings_draft_add_source() {
    local url="${1:-}"
    local identity existing existing_identity destination
    echo "  [*] Validating repository source, please wait..."
    catalog_validate_url "${url}" || {
        echo "Invalid GitHub repository URL: ${url}"
        return 1
    }
    url="${url%/}"
    identity="$(_settings_url_identity "${url}")"
    while IFS= read -r existing || [ -n "${existing}" ]; do
        [ -n "${existing}" ] || continue
        existing_identity="$(_settings_url_identity "${existing}")"
        if [ "${existing_identity}" = "${identity}" ]; then
            echo "Repository already exists in draft: ${url}"
            return 1
        fi
    done < <(catalog_sources | cut -f3)
    while IFS= read -r existing || [ -n "${existing}" ]; do
        [ -n "${existing}" ] || continue
        existing_identity="$(_settings_url_identity "${existing}")"
        if [ "${existing_identity}" = "${identity}" ]; then
            echo "Repository already exists in draft: ${url}"
            return 1
        fi
    done <<< "${HAWS_DRAFT_ADDED_REPOSITORIES:-}"

    destination="$(_settings_source_path_from_url "${url}")"
    if _settings_source_path_taken "${destination}" || \
        ! catalog_validate_destination "${destination}"; then
        echo "Repository path collision: ${destination}; no changes made."
        return 1
    fi
    HAWS_DRAFT_ADDED_REPOSITORIES="${HAWS_DRAFT_ADDED_REPOSITORIES:-}${url}"$'\n'
    HAWS_DRAFT_ADDED_PATHS="${HAWS_DRAFT_ADDED_PATHS:-}${destination}"$'\n'
    export HAWS_DRAFT_ADDED_REPOSITORIES HAWS_DRAFT_ADDED_PATHS
    echo "Repository added to draft: ${url}"
}

settings_draft_remove_source() {
    local wanted="${1:-}"
    local current="${HAWS_DRAFT_SOURCES:-}"
    if _settings_list_contains "${current}" "${wanted}"; then
        HAWS_DRAFT_SOURCES="$(_settings_list_without "${current}" "${wanted}")"
        export HAWS_DRAFT_SOURCES
        echo "Repository marked for removal in draft: ${wanted}"
        return 0
    fi
    case "${wanted}" in
        url:*) wanted="${wanted#url:}" ;;
        *) return 1 ;;
    esac
    local new_urls="" new_paths="" url path
    while IFS=$'\t' read -r url path || [ -n "${url}" ]; do
        [ -n "${url}" ] || continue
        if [ "${url}" != "${wanted}" ]; then
            new_urls="${new_urls}${url}"$'\n'
            new_paths="${new_paths}${path}"$'\n'
        fi
    done < <(paste -d $'\t' \
        <(printf '%s\n' "${HAWS_DRAFT_ADDED_REPOSITORIES:-}" | sed '/^$/d') \
        <(printf '%s\n' "${HAWS_DRAFT_ADDED_PATHS:-}" | sed '/^$/d'))
    HAWS_DRAFT_ADDED_REPOSITORIES="${new_urls}"
    HAWS_DRAFT_ADDED_PATHS="${new_paths}"
    export HAWS_DRAFT_ADDED_REPOSITORIES HAWS_DRAFT_ADDED_PATHS
    echo "Repository removed from draft: ${wanted}"
}

_settings_ensure_skill_draft() {
    [ "${HAWS_DRAFT_SKILLS_LOADED:-0}" = 1 ] && return 0
    load_disabled_skills
    HAWS_DRAFT_SKILLS="$(catalog_skills | awk -F '\t' '$6 == 1 {print $2}')"
    HAWS_DRAFT_SKILLS_LOADED=1
    HAWS_PERSIST_SKILLS="${HAWS_DRAFT_SKILLS}"
    export HAWS_PERSIST_SKILLS HAWS_DRAFT_SKILLS HAWS_DRAFT_SKILLS_LOADED
}

settings_draft_load() {
    settings_load || return $?
    disabled_environments_load
    HAWS_PERSIST_AUTO_UPDATE="${HAWS_AUTO_UPDATE}"
    HAWS_PERSIST_ENVIRONMENTS=""
    local environment
    while IFS= read -r environment; do
        [ -n "${DISABLED_ENVIRONMENTS[${environment}]:-}" ] && continue
        HAWS_PERSIST_ENVIRONMENTS+="${environment}"$'\n'
    done < <(_haws_detected_environments)
    HAWS_DRAFT_AUTO_UPDATE="${HAWS_PERSIST_AUTO_UPDATE}"
    HAWS_DRAFT_ENVIRONMENTS="${HAWS_PERSIST_ENVIRONMENTS}"
    HAWS_DRAFT_ENVIRONMENTS_TOUCHED=0
    HAWS_DRAFT_PLAN=""
    HAWS_PERSIST_SOURCES="$(catalog_sources | cut -f1)"
    HAWS_DRAFT_SOURCES="${HAWS_PERSIST_SOURCES}"
    HAWS_DRAFT_ADDED_REPOSITORIES=""
    HAWS_DRAFT_ADDED_PATHS=""
    HAWS_DRAFT_SKILLS=""
    HAWS_DRAFT_SKILLS_LOADED=0
    export HAWS_PERSIST_AUTO_UPDATE HAWS_PERSIST_ENVIRONMENTS \
        HAWS_DRAFT_AUTO_UPDATE HAWS_DRAFT_ENVIRONMENTS \
        HAWS_DRAFT_ENVIRONMENTS_TOUCHED HAWS_DRAFT_PLAN
    export HAWS_PERSIST_SOURCES HAWS_DRAFT_SOURCES \
        HAWS_DRAFT_ADDED_REPOSITORIES HAWS_DRAFT_ADDED_PATHS \
        HAWS_DRAFT_SKILLS HAWS_DRAFT_SKILLS_LOADED
}

settings_draft_discard() {
    local state="$(_haws_state_dir)"
    rm -f -- "${state}/settings.plan" "${state}/apply.result"
    rmdir -- "${state}" 2>/dev/null || true
    rmdir -- "$(dirname "${state}")" 2>/dev/null || true
    unset HAWS_PERSIST_AUTO_UPDATE HAWS_PERSIST_ENVIRONMENTS \
        HAWS_DRAFT_AUTO_UPDATE HAWS_DRAFT_ENVIRONMENTS \
        HAWS_DRAFT_ENVIRONMENTS_TOUCHED HAWS_DRAFT_PLAN \
        HAWS_PERSIST_SOURCES HAWS_DRAFT_SOURCES \
        HAWS_DRAFT_ADDED_REPOSITORIES HAWS_DRAFT_ADDED_PATHS \
        HAWS_PERSIST_SKILLS HAWS_DRAFT_SKILLS HAWS_DRAFT_SKILLS_LOADED \
        HAWS_PLAN_KIND HAWS_PLAN_CHANGED HAWS_PLAN_FILE
}

_settings_draft_is_dirty() {
    [ "$( _settings_list_signature "${HAWS_DRAFT_SOURCES:-}" )" != \
        "$( _settings_list_signature "${HAWS_PERSIST_SOURCES:-}" )" ] && return 0
    [ -n "${HAWS_DRAFT_ADDED_REPOSITORIES:-}" ] && return 0
    if [ "${HAWS_DRAFT_SKILLS_LOADED:-0}" = 1 ] && \
        [ "$( _settings_list_signature "${HAWS_DRAFT_SKILLS:-}" )" != \
          "$( _settings_list_signature "${HAWS_PERSIST_SKILLS:-}" )" ]; then
        return 0
    fi
    [ "${HAWS_DRAFT_AUTO_UPDATE:-}" != "${HAWS_PERSIST_AUTO_UPDATE:-}" ] && return 0
    [ "$( _settings_list_signature "${HAWS_DRAFT_ENVIRONMENTS:-}" )" != \
        "$( _settings_list_signature "${HAWS_PERSIST_ENVIRONMENTS:-}" )" ]
}

settings_draft_reset() {
    echo "Reset Settings to Defaults?"
    echo "This will replace the current draft. Nothing will change on this computer yet."
    if ! interactive_menu menu "Reset Settings to Defaults?" "Reset" "Cancel"; then
        echo "Reset cancelled."
        return 1
    fi
    [ "${INTERACTIVE_MENU_SELECTION}" -eq 0 ] || {
        echo "Reset cancelled."
        return 1
    }
    HAWS_DRAFT_AUTO_UPDATE="on"
    HAWS_DRAFT_ENVIRONMENTS="$(_haws_detected_environments)"
    HAWS_DRAFT_ENVIRONMENTS_TOUCHED=1
    HAWS_DRAFT_SOURCES="${HAWS_PERSIST_SOURCES:-}"
    HAWS_DRAFT_ADDED_REPOSITORIES=""
    HAWS_DRAFT_ADDED_PATHS=""
    HAWS_DRAFT_SKILLS=""
    HAWS_DRAFT_SKILLS_LOADED=0
    export HAWS_DRAFT_AUTO_UPDATE HAWS_DRAFT_ENVIRONMENTS \
        HAWS_DRAFT_ENVIRONMENTS_TOUCHED HAWS_DRAFT_SOURCES \
        HAWS_DRAFT_ADDED_REPOSITORIES HAWS_DRAFT_ADDED_PATHS \
        HAWS_DRAFT_SKILLS HAWS_DRAFT_SKILLS_LOADED
    echo "The draft now contains default values. Nothing has changed on this computer yet."
    return 0
}

_settings_skill_selector() {
    local title="$1"
    local rows="$2"
    local wanted_source="${3:-}"
    local source_id id display description entrypoint active source_path
    local detail label source_label
    local items=() ids=()
    local -A source_paths=() source_labels=() display_counts=()

    local source_url source_revision
    while IFS=$'\t' read -r source_id source_path source_url source_revision ||
        [ -n "${source_id}" ]; do
        [ -n "${source_id}" ] || continue
        source_paths["${source_id}"]="${source_path}"
        source_labels["${source_id}"]="$(_interactive_source_label "${source_path}")"
    done < <(_catalog_skill_sources)

    while IFS=$'\t' read -r source_id id display description entrypoint active || [ -n "${id}" ]; do
        [ -n "${id}" ] || continue
        display_counts["${display}"]=$(( ${display_counts[${display}]:-0} + 1 ))
    done <<< "${rows}"

    while IFS=$'\t' read -r source_id id display description entrypoint active || [ -n "${id}" ]; do
        [ -n "${id}" ] || continue
        if [ -n "${wanted_source}" ]; then
            [ "${source_id}" = "${wanted_source}" ] || continue
        else
            source_path="${source_paths[${source_id}]:-}"
            [[ "${source_path}" == skills/packs/* ]] && continue
        fi
        label="$(_interactive_truncate "${display}")"
        if [ "${display_counts[${display}]:-0}" -gt 1 ]; then
            source_label="${source_labels[${source_id}]:-${source_id}}"
            label="$(_interactive_truncate "${display}" 36) [${source_label}]"
        fi
        detail="${description}"
        [ -n "${detail}" ] || detail="${source_id}"
        active=0
        _settings_list_contains "${HAWS_DRAFT_SKILLS:-}" "${id}" && active=1
        items+=("${label}|${detail}|${active}")
        ids+=("${id}")
    done <<< "${rows}"

    [ "${#items[@]}" -gt 0 ] || {
        echo "  [INFO] No skills found for this selection."
        return 0
    }
    declare -A CHECKLIST_RESULTS=()
    if ! interactive_checklist "${title}" "${items[@]}"; then
        echo "  [INFO] Configuration cancelled. No changes saved."
        return 1
    fi
    local selected="${HAWS_DRAFT_SKILLS:-}"
    local i
    for ((i=0; i<${#ids[@]}; i++)); do
        if [ "${CHECKLIST_RESULTS[${items[$i]%%|*}]:-0}" -eq 1 ]; then
            _settings_list_contains "${selected}" "${ids[$i]}" || \
                selected="${selected}${ids[$i]}"$'\n'
        else
            selected="$(_settings_list_without "${selected}" "${ids[$i]}")"
        fi
    done
    HAWS_DRAFT_SKILLS="${selected}"
    export HAWS_DRAFT_SKILLS
}

settings_environments_page() {
    local environment label active
    local items=() environments=()
    while IFS= read -r environment; do
        [ -n "${environment}" ] || continue
        label="$(_haws_environment_label "${environment}")"
        active=0
        _settings_list_contains "${HAWS_DRAFT_ENVIRONMENTS:-}" "${environment}" && active=1
        items+=("${label}|${environment}|${active}")
        environments+=("${environment}")
    done < <(_haws_detected_environments)

    if [ "${#items[@]}" -eq 0 ]; then
        echo "  [INFO] No AI environments detected on this machine."
        return 0
    fi

    declare -A CHECKLIST_RESULTS=()
    if ! interactive_checklist "Configure AI Environments (Enable / Disable)" "${items[@]}"; then
        echo "  [INFO] Environment configuration cancelled. No changes saved."
        return 1
    fi

    local selected="" i
    for ((i=0; i<${#environments[@]}; i++)); do
        if [ "${CHECKLIST_RESULTS[${items[$i]%%|*}]:-0}" -eq 1 ]; then
            selected="${selected}${environments[$i]}"$'\n'
        fi
    done
    HAWS_DRAFT_ENVIRONMENTS="${selected}"
    HAWS_DRAFT_ENVIRONMENTS_TOUCHED=1
    export HAWS_DRAFT_ENVIRONMENTS HAWS_DRAFT_ENVIRONMENTS_TOUCHED
    echo "AI environment draft updated; it will be applied only after Preview and Apply."
}

settings_skills_page() {
    echo "  [*] Loading skills catalog, please wait..."
    _settings_ensure_skill_draft || return 1
    local rows="$(catalog_skills)"
    echo "  [✓] Skills catalog ready."
    local source_id id display description entrypoint active source_path
    local pack_ids=() pack_names=()
    local -A source_counts=() source_active_counts=() source_paths=() source_labels=()
    local -A pack_name_counts=() seen_sources=()

    local source_url source_revision
    while IFS=$'\t' read -r source_id source_path source_url source_revision ||
        [ -n "${source_id}" ]; do
        [ -n "${source_id}" ] || continue
        source_paths["${source_id}"]="${source_path}"
        source_labels["${source_id}"]="$(_interactive_source_label "${source_path}")"
    done < <(_catalog_skill_sources)

    while IFS=$'\t' read -r source_id id display description entrypoint active || [ -n "${id}" ]; do
        [ -n "${id}" ] || continue
        source_counts["${source_id}"]=$(( ${source_counts[${source_id}]:-0} + 1 ))
        if _settings_list_contains "${HAWS_DRAFT_SKILLS:-}" "${id}"; then
            local current_active="${source_active_counts[${source_id}]:-0}"
            source_active_counts["${source_id}"]=$((current_active + 1))
        fi
    done <<< "${rows}"
    while IFS=$'\t' read -r source_id id display description entrypoint active || [ -n "${id}" ]; do
        [ -n "${id}" ] || continue
        source_path="${source_paths[${source_id}]:-}"
        [[ "${source_path}" == skills/packs/* ]] || continue
        [ -z "${seen_sources[${source_id}]:-}" ] || continue
        seen_sources["${source_id}"]=1
        pack_ids+=("${source_id}")
        local pack_name="${source_labels[${source_id}]:-${source_id}}"
        pack_names+=("${pack_name}")
        pack_name_counts["${pack_name}"]=$(( ${pack_name_counts[${pack_name}]:-0} + 1 ))
    done <<< "${rows}"

    local single_total=0 single_active=0
    local single_source_id single_source_path
    for single_source_id in "${!source_counts[@]}"; do
        single_source_path="${source_paths[${single_source_id}]:-}"
        [[ "${single_source_path}" == skills/packs/* ]] && continue
        single_total=$((single_total + ${source_counts[${single_source_id}]:-0}))
        single_active=$((single_active + ${source_active_counts[${single_source_id}]:-0}))
    done

    local summary_label="Single Skills"
    local summary_width=${#summary_label}
    local summary_name i
    for ((i=0; i<${#pack_names[@]}; i++)); do
        summary_name="${pack_names[$i]}"
        if [ "${pack_name_counts[${summary_name}]:-0}" -gt 1 ]; then
            summary_name="${summary_name} [$(_interactive_truncate "${pack_ids[$i]}" 24)]"
        fi
        [ "${#summary_name}" -gt "${summary_width}" ] && summary_width="${#summary_name}"
    done
    summary_width=$((summary_width + 2))

    while true; do
        local summary="Choose a skill category to edit the current draft."
        summary+=$'\n\nSkill Summary\n  Single Skills\n  Multi-Skill Packs'
        if [ "${#pack_names[@]}" -eq 0 ]; then
            summary+=$'\n    (none)'
        else
            for ((i=0; i<${#pack_names[@]}; i++)); do
                summary_name="${pack_names[$i]}"
                if [ "${pack_name_counts[${summary_name}]:-0}" -gt 1 ]; then
                    summary_name="${summary_name} [$(_interactive_truncate "${pack_ids[$i]}" 24)]"
                fi
                printf -v summary_name '    %-*s [Active: %d / %d skills]' \
                    "$((summary_width - 2))" "${summary_name}" \
                    "${source_active_counts[${pack_ids[$i]}]:-0}" \
                    "${source_counts[${pack_ids[$i]}]:-0}"
                summary+=$'\n'"${summary_name}"
            done
        fi
        if interactive_menu menu "Configure Active Skills (Enable / Disable)|${summary}" \
            "Single Skills|Configure individual skills" \
            "Multi-Skill Packs|Configure skills by pack"; then
            case "${INTERACTIVE_MENU_SELECTION}" in
                0)
                    _settings_skill_selector "Configure Single Skills" "${rows}" || true
                    ;;
                1)
                    local pack_items=() i pack_label
                    for ((i=0; i<${#pack_ids[@]}; i++)); do
                        pack_label="${pack_names[$i]}"
                        if [ "${pack_name_counts[${pack_label}]:-0}" -gt 1 ]; then
                            pack_label="${pack_label} [$(_interactive_truncate "${pack_ids[$i]}" 24)]"
                        fi
                        pack_label="${pack_label} [Active: ${source_active_counts[${pack_ids[$i]}]:-0} / ${source_counts[${pack_ids[$i]}]:-0} skills]"
                        pack_items+=("${pack_label}")
                    done
                    if interactive_menu menu "Select a Skill Pack to configure" \
                        "${pack_items[@]}"; then
                        [ "${INTERACTIVE_MENU_SELECTION}" -lt "${#pack_ids[@]}" ] || continue
                        _settings_skill_selector \
                            "Configure Skills in ${pack_names[$INTERACTIVE_MENU_SELECTION]}" \
                            "${rows}" "${pack_ids[$INTERACTIVE_MENU_SELECTION]}" || true
                    fi
                    ;;
                *) return 0 ;;
            esac
        else
            return 0
        fi
    done
}

_settings_repository_remove_page() {
    local rows="$(catalog_sources)"
    local id path url revision name type label
    local items=() ids=()
    local -A name_counts=()

    while IFS=$'\t' read -r id path url revision || [ -n "${id}" ]; do
        [ -n "${id}" ] || continue
        name="${path##*/}"
        name_counts["${name}"]=$(( ${name_counts[${name}]:-0} + 1 ))
    done <<< "${rows}"
    while IFS=$'\t' read -r id path url revision || [ -n "${id}" ]; do
        [ -n "${id}" ] || continue
        name="${path##*/}"
        type="$(catalog_source_kind "${id}")"
        label="${name}"
        [ "${name_counts[${name}]:-0}" -gt 1 ] && label="${name} [${id}]"
        items+=("${label}|[${type}] ${path}|0")
        ids+=("${id}")
    done <<< "${rows}"

    while IFS=$'\t' read -r url path || [ -n "${url}" ]; do
        [ -n "${url}" ] || continue
        name="${url##*/}"
        name="${name%.git}"
        items+=("${name} (draft)|${path}|0")
        ids+=("url:${url}")
    done < <(paste -d $'\t' \
        <(printf '%s\n' "${HAWS_DRAFT_ADDED_REPOSITORIES:-}" | sed '/^$/d') \
        <(printf '%s\n' "${HAWS_DRAFT_ADDED_PATHS:-}" | sed '/^$/d'))

    [ "${#items[@]}" -gt 0 ] || {
        echo "  No external git repositories currently installed."
        return 0
    }
    declare -A CHECKLIST_RESULTS=()
    if ! interactive_checklist "Select Repositories to REMOVE" "${items[@]}"; then
        echo "  [INFO] Removal cancelled. Kept all repositories."
        return 0
    fi
    local i
    for ((i=0; i<${#ids[@]}; i++)); do
        [ "${CHECKLIST_RESULTS[${items[$i]%%|*}]:-0}" -eq 1 ] || continue
        settings_draft_remove_source "${ids[$i]}" || true
    done
}

settings_repositories_page() {
    local url
    while true; do
        if ! interactive_menu menu "Repositories|Manage repository sources in the current draft." \
            "Add Git Repository|Add a repository to the draft" \
            "Remove Git Repository|Remove a repository from the draft" \
            "Back to Settings|Return without changing the draft"; then
            return 0
        fi
        case "${INTERACTIVE_MENU_SELECTION}" in
            0)
                echo ""
                echo "============================================================="
                echo "                 Add Git Repository"
                echo "============================================================="
                echo "Enter external Git repository URLs to add as submodules."
                read -r -p "Enter Git Repository URL (or 'c' to cancel): " url || url=""
                url="${url%$'\r'}"
                case "${url}" in
                    ""|c|C|cancel|Cancel|q|Q) continue ;;
                esac
                settings_draft_add_source "${url}" || true
                ;;
            1)
                _settings_repository_remove_page || true
                ;;
            *) return 0 ;;
        esac
    done
}

settings_page() {
    local environment_count=0
    local environment
    while IFS= read -r environment; do
        [ -n "${environment}" ] && environment_count=$((environment_count + 1))
    done <<< "${HAWS_DRAFT_ENVIRONMENTS:-}"
    local skills_detail="all active (default)"
    [ "${HAWS_DRAFT_SKILLS_LOADED:-0}" = 1 ] && skills_detail="draft selection loaded"
    local items=(
        "Repositories|Existing repository sources|-"
        "Skills|${skills_detail}|-"
        "AI Environments|${environment_count} selected|-"
        "Second Brain|View status / Connect / Disconnect >|"
        "Auto Update|Update HAWS sources during Sync|${HAWS_DRAFT_AUTO_UPDATE:-on}"
        "Apply|Accept the draft for preview|-"
        "Reset to Defaults|Replace the current draft|-"
    )
    if interactive_menu settings "HAWS Settings|Review the draft; Apply is the only way to save changes." "${items[@]}"; then
        HAWS_DRAFT_AUTO_UPDATE="${INTERACTIVE_MENU_STATES[Auto Update]:-${HAWS_DRAFT_AUTO_UPDATE}}"
        export HAWS_DRAFT_AUTO_UPDATE
        case "${INTERACTIVE_MENU_SELECTION}" in
            0)
                settings_repositories_page || true
                return 2
                ;;
            1)
                settings_skills_page || true
                return 2
                ;;
            2)
                settings_environments_page || true
                return 2
                ;;
            3)
                second_brain_detail_page || true
                return 2
                ;;
            4)
                return 2
                ;;
            5)
                return 0
                ;;
            6)
                settings_draft_reset || true
                return 2
                ;;
        esac
    fi

    if _settings_draft_is_dirty; then
        echo "Discard Changes?"
        echo "You have unapplied changes in Settings."
        if interactive_menu menu "Discard Changes?" "Keep Editing" "Discard Changes"; then
            [ "${INTERACTIVE_MENU_SELECTION}" -eq 0 ] && return 2
            echo "Cancelled. No changes saved."
            return 1
        fi
        echo "Cancelled. No changes saved."
        return 1
    fi
    return 1
}

settings_plan_build() {
    local state="$(_haws_state_dir)"
    local plan="${state}/settings.plan"
    local temporary="${state}/settings.plan.stage.$$"
    local action_kind="Install"
    local changed=1
    local source_id path url revision add_url add_path
    if install_is_complete; then
        action_kind="Update"
        changed=0
        _settings_draft_is_dirty && changed=1
    fi
    mkdir -p "${state}" || return 1
    {
        printf 'setting\tauto_update\t%s\n' "${HAWS_DRAFT_AUTO_UPDATE:-on}"
        if [ "${HAWS_DRAFT_ENVIRONMENTS_TOUCHED:-0}" = 1 ]; then
            while IFS= read -r environment; do
                [ -n "${environment}" ] || continue
                if _settings_list_contains "${HAWS_DRAFT_ENVIRONMENTS:-}" "${environment}"; then
                    printf 'environment\t%s\tenabled\n' "${environment}"
                else
                    printf 'environment\t%s\tdisabled\n' "${environment}"
                fi
            done < <(_haws_all_environments)
        fi
        while IFS=$'\t' read -r source_id path url revision || [ -n "${source_id}" ]; do
            [ -n "${source_id}" ] || continue
            if ! _settings_list_contains "${HAWS_DRAFT_SOURCES:-}" "${source_id}"; then
                printf 'remove-source\tsources\t%s\t%s\n' "${source_id}" "${path}"
            fi
        done < <(catalog_sources)
        while IFS=$'\t' read -r add_url add_path || [ -n "${add_url}" ]; do
            [ -n "${add_url}" ] || continue
            printf 'add-source\tsources\t%s\t%s\n' "${add_url}" "${add_path}"
        done < <(paste -d $'\t' \
            <(printf '%s\n' "${HAWS_DRAFT_ADDED_REPOSITORIES:-}" | sed '/^$/d') \
            <(printf '%s\n' "${HAWS_DRAFT_ADDED_PATHS:-}" | sed '/^$/d'))
        if [ "${changed}" -eq 1 ]; then
            printf 'integration\t%s\told HAWS integration\n' "${action_kind,,}"
        fi
    } > "${temporary}" || {
        rm -f -- "${temporary}"
        return 1
    }
    _haws_state_replace "${temporary}" "${plan}"
    local result=$?
    rm -f -- "${temporary}"
    [ "${result}" -eq 0 ] || return "${result}"
    HAWS_PLAN_KIND="${action_kind}"
    HAWS_PLAN_CHANGED="${changed}"
    HAWS_PLAN_FILE="${plan}"
    export HAWS_PLAN_KIND HAWS_PLAN_CHANGED HAWS_PLAN_FILE
}

settings_preview() {
    local title="HAWS — Preview ${HAWS_PLAN_KIND:-Install}|Review the draft; Apply is the only way to write changes."
    [ "${HAWS_PLAN_CHANGED:-1}" -eq 0 ] || title+="|1"
    local skills_was_loaded="${HAWS_DRAFT_SKILLS_LOADED:-0}"
    if [ "${skills_was_loaded}" != 1 ]; then
        echo "  [*] Loading skills catalog, please wait..."
    fi
    _settings_ensure_skill_draft || return 1
    if [ "${skills_was_loaded}" != 1 ]; then
        echo "  [✓] Skills catalog ready."
    fi
    echo ""
    if [ "${HAWS_PLAN_CHANGED:-1}" -eq 0 ]; then
        echo "No settings have changed."
        if interactive_menu menu "${title}" \
            "Back to Settings|Review or edit the draft" \
            "Back to Home|Leave the settings flow"; then
            [ "${INTERACTIVE_MENU_SELECTION}" -eq 0 ] && return 2
            return 1
        fi
        return 1
    fi
    echo "No changes have been applied yet."
    echo ""
    echo "Repositories"
    local source_rows source_id path url revision printed_source=0
    source_rows="$(catalog_sources)"
    while IFS=$'\t' read -r source_id path url revision || [ -n "${source_id}" ]; do
        [ -n "${source_id}" ] || continue
        if _settings_list_contains "${HAWS_DRAFT_SOURCES:-}" "${source_id}"; then
            echo "  ${path}"
        else
            echo "  - ${path}"
        fi
        printed_source=1
    done <<< "${source_rows}"
    local add_url add_path
    while IFS=$'\t' read -r add_url add_path || [ -n "${add_url}" ]; do
        [ -n "${add_url}" ] || continue
        echo "  + ${add_path} (${add_url})"
        printed_source=1
    done < <(paste -d $'\t' \
        <(printf '%s\n' "${HAWS_DRAFT_ADDED_REPOSITORIES:-}" | sed '/^$/d') \
        <(printf '%s\n' "${HAWS_DRAFT_ADDED_PATHS:-}" | sed '/^$/d'))
    [ "${printed_source}" -eq 1 ] || echo "  Default"
    echo ""
    echo "Skills"
    local skill_rows skill_id skill_display skill_source_id skill_description entrypoint active printed_skill=0
    skill_rows="$(catalog_skills)"
    while IFS=$'\t' read -r skill_source_id skill_id skill_display skill_description entrypoint active ||
        [ -n "${skill_id}" ]; do
        [ -n "${skill_id}" ] || continue
        _settings_list_contains "${HAWS_DRAFT_SKILLS:-}" "${skill_id}" || continue
        echo "  ${skill_display} [${skill_source_id}::${entrypoint}]"
        printed_skill=1
    done <<< "${skill_rows}"
    [ "${printed_skill}" -eq 1 ] || echo "  Default"
    echo ""
    echo "AI Environments"
    local environment
    local printed_environment=0
    while IFS= read -r environment; do
        [ -n "${environment}" ] || continue
        echo "  $(_haws_environment_label "${environment}")"
        printed_environment=1
    done <<< "${HAWS_DRAFT_ENVIRONMENTS:-}"
    [ "${printed_environment}" -eq 1 ] || echo "  None detected"
    echo ""
    echo "Second Brain"
    echo "  $(_second_brain_status_label)"
    echo ""
    echo "Auto Update"
    echo "  $(_haws_toggle_label "${HAWS_DRAFT_AUTO_UPDATE:-on}")"
    if interactive_menu menu "${title}" \
        "${HAWS_PLAN_KIND:-Install}|Apply this plan" \
        "Back to Settings|Review or edit the draft" \
        "Cancel|Discard the draft and leave"; then
        case "${INTERACTIVE_MENU_SELECTION}" in
            0) return 0 ;;
            1) return 2 ;;
            *) return 1 ;;
        esac
    fi
    return 1
}

settings_apply_repository_action() {
    local action="${1:-}"
    local source_url="${2:-}"
    local destination="${3:-}"
    local repo="$(_catalog_repo_dir)"
    local source_id path url revision status

    case "${action}" in
        add-source)
            catalog_validate_url "${source_url}" || {
                echo "Blocked: invalid repository URL: ${source_url}"
                return 1
            }
            catalog_validate_destination "${destination}" || {
                echo "Blocked: repository destination is unsafe or occupied: ${destination}"
                return 1
            }
            while IFS=$'\t' read -r source_id path url revision || [ -n "${source_id}" ]; do
                [ -n "${source_id}" ] || continue
                [ "${path}" = "${destination}" ] || continue
                echo "Blocked: repository destination is already registered: ${destination}"
                return 1
            done < <(catalog_sources)
            git -C "${repo}" submodule add "${source_url}" "${destination}" || {
                echo "Blocked: could not add repository: ${source_url}"
                return 1
            }
            echo "Repository added: ${destination}"
            ;;
        remove-source)
            source_id="${source_url}"
            _catalog_source_fields "${source_id}" >/dev/null || {
                echo "Blocked: repository source is no longer registered: ${source_id}"
                return 1
            }
            IFS=$'\t' read -r path url revision <<< "$(_catalog_source_fields "${source_id}")"
            [ -z "${destination}" ] || [ "${destination}" = "${path}" ] || {
                echo "Blocked: repository destination changed: ${path}"
                return 1
            }
            case "${path}" in
                skills/packs/*|skills/standalone/*) ;;
                *)
                    echo "Blocked: refusing to remove repository outside the HAWS skill roots: ${path}"
                    return 1
                    ;;
            esac
            case "/${path}/" in
                */../*|*/./*)
                    echo "Blocked: unsafe repository destination: ${path}"
                    return 1
                    ;;
            esac
            if ! git -C "${repo}" ls-files --stage -- "${path}" |
                awk '$1 == "160000" {found=1} END {exit found ? 0 : 1}'; then
                echo "Blocked: repository is not a registered submodule: ${path}"
                return 1
            fi
            if [ -d "${repo}/${path}" ]; then
                if ! status="$(git -C "${repo}/${path}" status --porcelain --untracked-files=all 2>/dev/null)"; then
                    echo "Blocked: could not inspect repository: ${path}"
                    return 1
                fi
                if [ -n "${status}" ]; then
                    echo "Blocked: repository has local changes: ${path}"
                    return 2
                fi
            fi
            git -C "${repo}" submodule deinit -f -- "${path}" || {
                echo "Blocked: could not deinitialize repository: ${path}"
                return 1
            }
            git -C "${repo}" rm -f -- "${path}" || {
                echo "Blocked: could not remove repository from Git: ${path}"
                return 1
            }
            echo "Repository removed: ${path}"
            ;;
        *)
            echo "Blocked: unknown repository action: ${action}"
            return 1
            ;;
    esac
}

settings_apply_skill_draft() {
    [ "${HAWS_DRAFT_SKILLS_LOADED:-0}" = 1 ] || return 0
    local destination="${SCRIPT_DIR}/skills/skills.disabled"
    local temporary="${destination}.stage.$$"
    local source_id skill_id display description entrypoint active
    mkdir -p "$(dirname "${destination}")" || return 1
    {
        echo "# HAWS Disabled Skills (source-aware)"
        while IFS=$'\t' read -r source_id skill_id display description entrypoint active ||
            [ -n "${skill_id}" ]; do
            [ -n "${skill_id}" ] || continue
            _settings_list_contains "${HAWS_DRAFT_SKILLS:-}" "${skill_id}" ||
                printf '%s\n' "${skill_id}"
        done < <(catalog_skills)
    } > "${temporary}" || {
        rm -f -- "${temporary}"
        return 1
    }
    _haws_state_replace "${temporary}" "${destination}"
    local result=$?
    rm -f -- "${temporary}"
    return "${result}"
}

settings_apply_final() {
    local plan="${HAWS_PLAN_FILE:-$(_haws_state_dir)/settings.plan}"
    local state="$(_haws_state_dir)"
    local environment_file="${HAWS_DISABLED_ENVIRONMENTS_FILE:-$(_haws_compat_file environments.disabled)}"
    [ -f "${plan}" ] || return 1
    echo "  [*] Applying settings draft..."
    settings_save auto_update "${HAWS_DRAFT_AUTO_UPDATE:-on}" || return 1
    if [ "${HAWS_DRAFT_ENVIRONMENTS_TOUCHED:-0}" = 1 ]; then
        local disabled=()
        local environment
        while IFS= read -r environment; do
            _settings_list_contains "${HAWS_DRAFT_ENVIRONMENTS:-}" "${environment}" ||
                disabled+=("${environment}")
        done < <(_haws_all_environments)
        if [ "${#disabled[@]}" -eq 0 ]; then
            disabled_environments_save_if_changed --all-enabled || return 1
        else
            disabled_environments_save_if_changed "${disabled[@]}" || return 1
        fi
    elif [ "${HAWS_PLAN_KIND:-Install}" = Install ] && [ ! -e "${environment_file}" ]; then
        disabled_environments_save_if_changed --all-enabled || return 1
    fi
    if ! settings_apply_skill_draft; then
        echo "Partial failure"
        echo "Remaining: skills"
        return 3
    fi
    printf 'settings\tcompleted\n' > "${state}/apply.result"
    echo "Completed: settings"
    if [ "${HAWS_TEST_FAIL_AFTER_SETTINGS:-0}" = 1 ]; then
        echo "Partial failure"
        echo "Remaining: integration"
        return 3
    fi

    local action key value rest
    while IFS=$'\t' read -r action key value rest || [ -n "${action:-}" ]; do
        [ -n "${action:-}" ] || continue
        case "${action}" in
            setting|environment) ;;
            add-source|remove-source)
                if ! settings_apply_repository_action "${action}" "${value}" "${rest}"; then
                    echo "Partial failure"
                    echo "Remaining: ${action}"
                    return 3
                fi
                printf '%s\tcompleted\n' "${action}" >> "${state}/apply.result"
                echo "Completed: ${action}"
                ;;
            initialize|pointer|skill-link|integration)
                if [ "${HAWS_TEST_NO_INTEGRATION:-0}" = 1 ]; then
                    echo "Skipped: ${action} (test fixture)"
                elif ! run_sync; then
                    echo "Partial failure"
                    echo "Remaining: ${action}"
                    return 3
                fi
                printf '%s\tcompleted\n' "${action}" >> "${state}/apply.result"
                echo "Completed: ${action}"
                ;;
            *)
                echo "Partial failure"
                echo "Completed: settings"
                echo "Remaining: ${action}"
                return 3
                ;;
        esac
    done < "${plan}"
    local marker_temporary="${state}/install.complete.stage.$$"
    printf 'schema=1\tcompleted_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${marker_temporary}" || return 1
    _haws_state_replace "${marker_temporary}" "${state}/install.complete"
    local result=$?
    rm -f -- "${marker_temporary}"
    [ "${result}" -eq 0 ] || return "${result}"
    echo "Installation state completed."
    return 0
}

settings_flow_run() {
    local start="${1:-settings}"
    local result
    while true; do
        if [ "${start}" = settings ]; then
            if settings_page; then
                :
            else
                result=$?
                [ "${result}" -eq 2 ] && continue
                settings_draft_discard
                return 1
            fi
        fi
        settings_plan_build || return 1
        if settings_preview; then
            settings_apply_final
            result=$?
            if [ "${result}" -eq 0 ]; then
                settings_draft_discard
                return 0
            fi
            [ "${result}" -eq 3 ] && return 3
            return 1
        else
            result=$?
            if [ "${result}" -eq 2 ]; then
                start=settings
                continue
            fi
            settings_draft_discard
            echo "Cancelled. No changes saved."
            return 1
        fi
    done
}

run_skills_route() {
    settings_draft_load || return $?
    local result=0
    settings_skills_page "$@" || result=$?
    if [ "${result}" -eq 0 ] && _settings_draft_is_dirty; then
        echo "  [*] Applying active skills, please wait..."
        if ! settings_apply_skill_draft; then
            settings_draft_discard
            return 1
        fi
    fi
    settings_draft_discard
    return "${result}"
}

setup_run() {
    local result
    while true; do
        echo ""
        echo "No changes have been made to this computer."
        echo ""
        echo "Default Setup"
        echo "Repositories        Default"
        echo "Skills              Default"
        echo "AI Environments     Default"
        echo "Second Brain       Local-Only"
        echo "Auto Update         On"
        if interactive_menu menu "HAWS Setup|Choose a setup option or leave without changes." \
            "Use Default Setup|Preview the standard HAWS setup" \
            "Customize Settings|Edit settings before preview"; then
            case "${INTERACTIVE_MENU_SELECTION}" in
                0)
                    settings_draft_load || return 1
                    if settings_flow_run preview; then
                        home_run
                        return $?
                    fi
                    result=$?
                    [ "${result}" -eq 3 ] && return 3
                    ;;
                1)
                    settings_draft_load || return 1
                    if settings_flow_run settings; then
                        home_run
                        return $?
                    fi
                    result=$?
                    [ "${result}" -eq 3 ] && return 3
                    ;;
                *)
                    return 0
                    ;;
            esac
        else
            return 0
        fi
    done
}

run_setup() { setup_run "$@"; }

home_run() {
    local result
    while true; do
        echo ""
        echo "============================================================="
        echo "                         HAWS Home"
        echo "============================================================="
        echo ""
        settings_load || return $?
        echo "CURRENT STATUS"
        printf '  Last Sync     : %s\n' "$(_health_last_sync)"
        printf '  Auto Update   : %s\n' "$(_haws_toggle_label "${HAWS_AUTO_UPDATE:-on}")"
        printf '  Second Brain  : %s\n' "$(_second_brain_status_label)"
        printf '  Diagnostics   : Use Doctor for full diagnostics\n'
        echo ""
        export HAWS_MENU_SUPPRESS_HEADER=1
        if interactive_menu menu "HAWS Home|Choose an action for your installed HAWS environment.|1" \
            "Sync|Run explicit synchronization" \
            "Settings|Edit the HAWS settings draft" \
            "Doctor|Run read-only diagnostics" \
            "Uninstall|Preview removal of HAWS-owned items"; then
            case "${INTERACTIVE_MENU_SELECTION}" in
                0)
                    local sync_status=0
                    HAWS_RESULT_NAVIGATION=home
                    HAWS_INTERACTIVE_RESULT=1
                    run_sync || sync_status=$?
                    unset HAWS_INTERACTIVE_RESULT
                    [ "${HAWS_RESULT_NAVIGATION:-home}" = exit ] && return "${sync_status}"
                    ;;
                1)
                    settings_draft_load || return 1
                    if settings_flow_run settings; then
                        settings_load || return $?
                    else
                        result=$?
                        [ "${result}" -eq 3 ] && return 3
                    fi
                    ;;
                2) run_doctor || true ;;
                3)
                    local uninstall_status=0
                    HAWS_INTERACTIVE_RESULT=1 run_uninstall || uninstall_status=$?
                    if [ "${uninstall_status}" -eq 0 ] && ! install_is_complete; then
                        echo "HAWS uninstalled. You can close this window."
                        HAWS_INTERACTIVE_RESULT=1 _haws_wait_for_result
                        return 0
                    fi
                    ;;
            esac
        else
            unset HAWS_MENU_SUPPRESS_HEADER
            return 0
        fi
        unset HAWS_MENU_SUPPRESS_HEADER
    done
}

run_lifecycle() {
    if install_is_complete; then
        home_run
    else
        setup_run
    fi
}

if [ "${HAWS_SOURCE_ONLY:-0}" != 1 ]; then
    haws_set_terminal_title
case "${COMMAND}" in
    help|--help|-h)
        echo "Usage: ./haws.sh [menu|setup|sync|status|doctor|hook|kit|user|uninstall|codex-agents] [--clean]"
        ;;
    menu|interactive)
        shift || true
        run_lifecycle
        ;;
    settings|configure)
        shift || true
        settings_draft_load || exit $?
        settings_flow_run settings
        result=$?
        if [ "${result}" -eq 0 ]; then
            home_run
            result=$?
        fi
        [ "${result}" -eq 3 ] && exit 3
        ;;
    codex-agents)
        shift || true
        run_codex_agents "$@"
        ;;
    status|health|check)
        shift || true
        run_status "$@"
        ;;
    doctor|test)
        shift || true
        run_doctor "$@"
        ;;
    setup|bootstrap)
        shift || true
        run_setup "$@"
        ;;
    skills|skill)
        shift || true
        run_skills_route "$@"
        ;;
    kit)
        shift || true
        run_kit "$@"
        ;;
    user|brain)
        shift || true
        run_user "$@"
        ;;
    hook|hooks)
        shift || true
        run_hooks "$@"
        ;;
    sync|update|install)
        run_sync "$@"
        ;;
    uninstall|remove)
        shift || true
        run_uninstall "$@"
        ;;
    *)
        echo "Usage: ./haws.sh [menu|setup|sync|status|doctor|hook|kit|user|uninstall|codex-agents] [--clean]"
        echo "  codex-agents [install|check|uninstall] [--dry-run] Native Codex roles only (no network sync)"
        echo "  setup           Complete frictionless setup: secondbrain + submodules + sync + hooks + doctor"
        echo "  sync [--clean]  All-in-one Smart Sync (use --clean to purge unmanaged foreign skills)"
        echo "  kit [add|prune|update] Manage KIT submodules and external tools with merge protection"
        echo "  user [connect]  Manage personal Second Brain (symmetrical 1-click cloud sync)"
        echo "  hook [install]  Install or inspect the HAWS Git commit-msg hook"
        echo "  status          Instant sub-second skill count and token budget check"
        echo "  doctor [--json] Run comprehensive 10-axis system diagnostics"
        echo "  uninstall       Safely detach HAWS pointers, skills, and hooks without deleting user data"
        exit 1
        ;;
esac
fi
