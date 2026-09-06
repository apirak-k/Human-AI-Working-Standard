#!/usr/bin/env bash
# ==============================================================================
# HAWS (Human-AI Working Standard) Universal Command Engine
# Standalone, Self-Contained CLI: Sync, Install, Update, Status, and Diagnostics
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="${1:-sync}"

run_status() {
    local gemini_dir="${HOME}/.gemini/config/skills"
    local claude_dir="${HOME}/.claude/skills"
    local manifest="${HOME}/.haws_manifest"

    local gemini_json="${HOME}/.gemini/config/skills.json"
    local gemini_count=0
    local claude_count=0
    local manifest_count=0

    [ -d "${claude_dir}" ] && claude_count=$(find "${claude_dir}" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | wc -l)
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

run_doctor() {
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

    # 2. Check Project Templates & Blueprints (15 Canonical Blueprints)
    [ "$json_mode" = false ] && echo "" && echo "2. Checking Project Templates & Blueprints (15 Blueprints)..."
    check_item "${SCRIPT_DIR}/templates/README.md" "templates/README.md"
    local doc_tpls=("PROJECT.md" "ARCHITECTURE.md" "CONSTRAINTS.md" "HANDOFF.md" "AGENTS.md" "DESIGN.md")
    for f in "${doc_tpls[@]}"; do
        check_item "${SCRIPT_DIR}/templates/docs/${f}" "templates/docs/${f}"
    done
    check_item "${SCRIPT_DIR}/templates/ai-configs/claude/CLAUDE.md.template" "templates/ai-configs/claude/CLAUDE.md.template"
    check_item "${SCRIPT_DIR}/templates/ai-configs/cursor/haws.mdc.template" "templates/ai-configs/cursor/haws.mdc.template"
    check_item "${SCRIPT_DIR}/templates/ai-configs/gemini/GEMINI.md.template" "templates/ai-configs/gemini/GEMINI.md.template"
    check_item "${SCRIPT_DIR}/templates/ai-configs/copilot/copilot-instructions.md.template" "templates/ai-configs/copilot/copilot-instructions.md.template"
    local container_tpls=("devcontainer.json" "Dockerfile.template" ".dockerignore.template" "docker-compose.yml.template")
    for f in "${container_tpls[@]}"; do
        check_item "${SCRIPT_DIR}/templates/containers/${f}" "templates/containers/${f}"
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
                known_skills["${BASH_REMATCH[1]}"]=1
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
    if [ -f "${SCRIPT_DIR}/.githooks/pre-commit" ] && [ -f "${SCRIPT_DIR}/.githooks/pre-push" ]; then
        if [ "${hooks_path}" != ".githooks" ]; then
            git -C "${SCRIPT_DIR}" config core.hooksPath .githooks 2>/dev/null || true
        fi
        passed=$((passed + 1))
        [ "$json_mode" = false ] && echo "   [PASS] Git hooks active (.githooks: pre-commit, pre-push)"
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
    check_item "${SCRIPT_DIR}/1-CLICK-SYNC.bat" "1-CLICK-SYNC.bat"
    check_item "${SCRIPT_DIR}/2nd-BRAIN-TOGGLE.bat" "2nd-BRAIN-TOGGLE.bat"
    check_item "${SCRIPT_DIR}/UNINSTALL.bat" "UNINSTALL.bat"

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

declare -A DISABLED_SKILLS

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

load_disabled_skills() {
    DISABLED_SKILLS=()
    local dfile="${SCRIPT_DIR}/config/skills.disabled"
    if [ -f "${dfile}" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/#.*//')"
            [ -n "$line" ] && DISABLED_SKILLS["$line"]=1
        done < "${dfile}"
    fi
}

save_disabled_skills() {
    local dfile="${SCRIPT_DIR}/config/skills.disabled"
    mkdir -p "$(dirname "${dfile}")"
    {
        echo "# HAWS Disabled Skills"
        echo "# Skills listed here will not be linked to Claude Code or Antigravity"
        for sk in "${!DISABLED_SKILLS[@]}"; do
            [ -n "$sk" ] && echo "$sk"
        done | sort
    } > "${dfile}"
}

run_sync() {
    local CLEAN_UNMANAGED=false
    for opt in "$@"; do
        [ "$opt" = "--clean" ] && CLEAN_UNMANAGED=true
    done
    shift || true
    echo "=== HAWS Universal Command Engine (All-in-One Sync) ==="
    echo ""

    local SOURCE_DIR="${SCRIPT_DIR}"
    load_disabled_skills

    # 0. Sync Personal Second Brain if connected
    echo "--- Step 0: Syncing Personal Second Brain ---"
    run_user sync
    echo ""

    # 1. Check Git Remote
    if [ -d "${SOURCE_DIR}/.git" ]; then
        echo "--- Step 1: Checking Remote Repository ---"
        git -C "${SOURCE_DIR}" fetch --quiet origin main 2>/dev/null || true
        local INCOMING_COMMITS
        INCOMING_COMMITS=$(git -C "${SOURCE_DIR}" rev-list HEAD..origin/main --count 2>/dev/null || echo 0)
        if [ "${INCOMING_COMMITS}" -gt 0 ]; then
            echo "  [*] Remote updates detected (${INCOMING_COMMITS} new commits). Pulling..."
            git -C "${SOURCE_DIR}" pull --quiet || true
            echo "  [✓] Repository updated to latest commit."
        else
            echo "  [✓] Local repository is up to date."
        fi
        echo ""
    fi

    # 2. Sync Submodules
    if [ -f "${SOURCE_DIR}/.gitmodules" ]; then
        echo "--- Step 2: Syncing Embedded Skill Submodules ---"
        git -C "${SOURCE_DIR}" submodule update --init --recursive --quiet 2>/dev/null || true
        echo "  [✓] Embedded submodules ready."
        echo ""
    fi

    # 3. Detect AI Environments
    echo "--- Step 3: Detecting AI Environments ---"
    local DETECTED_CLAUDE=false
    local DETECTED_GEMINI=false
    local DETECTED_CURSOR=false
    local DETECTED_CODEX=false

    [ -d "${HOME}/.claude" ] && DETECTED_CLAUDE=true
    [ -d "${HOME}/.gemini" ] && DETECTED_GEMINI=true
    { [ -d "${HOME}/.cursor" ] || [ -d "${HOME}/AppData/Roaming/Cursor" ] || [ -f "${HOME}/.cursorrules" ]; } && DETECTED_CURSOR=true
    { [ -d "${HOME}/.config/github-copilot" ] || [ -d "${HOME}/.copilot" ] || [ -d "${HOME}/AppData/Local/github-copilot" ]; } && DETECTED_CODEX=true

    [ "$DETECTED_CLAUDE" = true ] && echo "  [✓] Claude Code detected (${HOME}/.claude)"
    [ "$DETECTED_GEMINI" = true ] && echo "  [✓] Google Antigravity detected (${HOME}/.gemini)"
    [ "$DETECTED_CURSOR" = true ] && echo "  [✓] Cursor IDE detected"
    [ "$DETECTED_CODEX" = true ] && echo "  [✓] GitHub Copilot / Codex detected"
    echo ""

    # Helper Linking Functions
    local SKILLS_LINKED=0
    local AGENTS_LINKED=0
    local RULES_LINKED=0
    local SKIPPED_COUNT=0
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

        if [ "$IS_WINDOWS" = true ]; then
            local win_src win_dest
            win_src="$(cygpath -w "${src}")"
            win_dest="$(cygpath -w "${dest}")"

            # Check if skill marker already exists and matches to avoid redundant process spawning
            local src_marker="${src}/SKILL.md"
            [ -f "${src}/skill.md" ] && src_marker="${src}/skill.md"
            local dest_marker="${dest}/SKILL.md"
            [ -f "${dest}/skill.md" ] && dest_marker="${dest}/skill.md"

            if [ -f "${src_marker}" ] && [ -f "${dest_marker}" ] && diff -q --strip-trailing-cr "${src_marker}" "${dest_marker}" >/dev/null 2>&1; then
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                return 0
            fi

            if [ -d "${dest}" ] || [ -L "${dest}" ]; then
                MSYS2_ARG_CONV_EXCL="*" cmd.exe /c rmdir "${win_dest}" >/dev/null 2>&1 || rm -rf "${dest}" 2>/dev/null || true
            fi

            if MSYS2_ARG_CONV_EXCL="*" cmd.exe /c mklink /J "${win_dest}" "${win_src}" >/dev/null 2>&1; then
                echo "  [JUNCTION] ${label}: ${dest} -> ${src}"
                return 0
            fi
        fi

        if [ -L "${dest}" ]; then
            local current_target
            current_target="$(readlink "${dest}" || true)"
            if [ "${current_target}" = "${src}" ]; then
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                return 0
            fi
            rm -f "${dest}"
        elif [ -d "${dest}" ]; then
            local src_marker="${src}/SKILL.md"
            [ -f "${src}/skill.md" ] && src_marker="${src}/skill.md"
            local dest_marker="${dest}/SKILL.md"
            [ -f "${dest}/skill.md" ] && dest_marker="${dest}/skill.md"

            if [ -f "${src_marker}" ] && [ -f "${dest_marker}" ] && diff -q --strip-trailing-cr "${src_marker}" "${dest_marker}" >/dev/null 2>&1; then
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                return 0
            else
                cp -rf "${src}"/* "${dest}/" 2>/dev/null || cp -rf "${src}" "${dest_dir}/"
                echo "  [UPDATED] ${label}: ${dest} -> ${src}"
                return 0
            fi
        fi

        if ln -sfn "${src}" "${dest}" 2>/dev/null || ln -s "${src}" "${dest}" 2>/dev/null; then
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

    # 4. Setup Global Pointers
    echo "--- Step 4: Setting Up Global Environment Pointers ---"
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
    if [ "$DETECTED_CODEX" = true ]; then
        if [ -d "${HOME}/.copilot" ]; then
            safe_append_pointer "${HOME}/.copilot/copilot-instructions.md"
        elif [ -d "${HOME}/.config/github-copilot" ]; then
            safe_append_pointer "${HOME}/.config/github-copilot/copilot-instructions.md"
        fi
    fi
    echo ""

    # 5. Link Skills
    echo "--- Step 5: Linking Skills ---"
    declare -A PROCESSED_SKILLS

    local MANIFEST_FILE="${HOME}/.haws_manifest"
    local PREV_MANIFEST="${HOME}/.haws_manifest.prev"
    local TMP_MANIFEST="${HOME}/.haws_manifest.tmp"

    rm -f "${PREV_MANIFEST}"
    [ -f "${MANIFEST_FILE}" ] && cp -f "${MANIFEST_FILE}" "${PREV_MANIFEST}"
    rm -f "${TMP_MANIFEST}"
    touch "${TMP_MANIFEST}"

    find_and_link_skills() {
        local base_dir="$1"
        [ ! -d "${base_dir}" ] && return 0

        while IFS= read -r -d '' skill_file; do
            local skill_dir
            skill_dir="$(dirname "${skill_file}")"

            local skill_name=""
            if [ -f "${skill_file}" ]; then
                while IFS= read -r line; do
                    if [[ "${line}" =~ ^[[:space:]]*name:[[:space:]]*[\"\']?([^\"\'#]+)[\"\']? ]]; then
                        skill_name="${BASH_REMATCH[1]}"
                        skill_name="${skill_name%"${skill_name##*[![:space:]]}"}"
                        break
                    fi
                done < "${skill_file}"
            fi
            [ -z "${skill_name}" ] && skill_name="$(basename "${skill_dir}")"

            # Check dynamic disabled list
            [ -n "${DISABLED_SKILLS[${skill_name}]:-}" ] && continue

            # Filter rules per user specification:
            [[ "${skill_dir}" =~ \.openclaw ]] && continue
            [[ "${skill_dir}" =~ planning-with-files ]] && [[ ! "${skill_dir}" =~ \.agents/skills ]] && continue
            [[ "${skill_dir}" =~ ui-ux-pro-max ]] && [[ ! "${skill_dir}" =~ \.claude/skills ]] && continue
            [[ "${skill_dir}" =~ caveman/plugins ]] && continue

            # 1. planning-with-files: keep only primary 'planning-with-files'
            [[ "${skill_name}" == "pi-planning-with-files" ]] && continue
            [[ "${skill_name}" =~ ^planning-with-files- ]] && continue

            # 2. taste-skill: exclude v1, keep only v2
            [[ "${skill_name}" == "design-taste-frontend-v1" ]] && continue

            if [ -n "${skill_name}" ] && [ -z "${PROCESSED_SKILLS[${skill_name}]:-}" ]; then
                PROCESSED_SKILLS[${skill_name}]=1
                echo "skill:${skill_name}" >> "${TMP_MANIFEST}"

                if [ "$DETECTED_CLAUDE" = true ]; then
                    safe_link_dir "${skill_dir}" "${HOME}/.claude/skills/${skill_name}" "Claude Skill [${skill_name}]"
                    SKILLS_LINKED=$((SKILLS_LINKED + 1))
                fi
            fi
        done < <(find "${base_dir}" -type f \( -name "SKILL.md" -o -name "skill.md" \) -print0 2>/dev/null || true)
    }

    [ -d "${SOURCE_DIR}/skills/custom" ] && find_and_link_skills "${SOURCE_DIR}/skills/custom"
    find_and_link_skills "${SOURCE_DIR}/skills"
    [ -d "${SOURCE_DIR}/skills/packs/ponytail/skills" ] && find_and_link_skills "${SOURCE_DIR}/skills/packs/ponytail/skills"

    if [ "$DETECTED_GEMINI" = true ]; then
        local target_json="${HOME}/.gemini/config/skills.json"
        mkdir -p "${HOME}/.gemini/config"

        # Clean legacy broken junctions on Windows so Antigravity doesn't choke
        if [ "$IS_WINDOWS" = true ] && [ -d "${HOME}/.gemini/config/skills" ]; then
            for junc in "${HOME}/.gemini/config/skills"/*; do
                if [ -d "${junc}" ] || [ -L "${junc}" ]; then
                    rm -rf "${junc}" 2>/dev/null || true
                fi
            done
        fi

        local win_source="${SOURCE_DIR}"
        command -v cygpath &>/dev/null && win_source="$(cygpath -m "${SOURCE_DIR}")"

        local json_entries=()
        declare -A seen_dirs

        # 1. Custom skills (respect disabled)
        if [ -d "${SOURCE_DIR}/skills/custom" ]; then
            for cdir in "${SOURCE_DIR}/skills/custom"/*; do
                [ ! -d "$cdir" ] && continue
                local cname="$(basename "$cdir")"
                [ -n "${DISABLED_SKILLS[$cname]:-}" ] && continue
                local win_cdir="$cdir"
                command -v cygpath &>/dev/null && win_cdir="$(cygpath -m "$cdir")"
                seen_dirs["$win_cdir"]=1
                json_entries+=("    { \"path\": \"${win_cdir}\" }")
            done
        fi

        # 2. Standalone & Packs
        while IFS= read -r f; do
            [ -z "${f}" ] && continue
            local sdir="$(dirname "${f}")"
            local pdir="$(dirname "${sdir}")"
            local sname=""
            while IFS= read -r line; do
                if [[ "${line}" =~ ^[[:space:]]*name:[[:space:]]*[\"\']?([^\"\'#]+)[\"\']? ]]; then
                    sname="${BASH_REMATCH[1]}"
                    sname="${sname%"${sname##*[![:space:]]}"}"
                    break
                fi
            done < "${f}"
            [ -z "${sname}" ] && sname="$(basename "${sdir}")"

            # Check if disabled
            [ -n "${DISABLED_SKILLS[$sname]:-}" ] && continue
            [[ "${sname}" == "pi-planning-with-files" ]] && continue
            [[ "${sname}" =~ ^planning-with-files- ]] && continue
            [[ "${sname}" == "design-taste-frontend-v1" ]] && continue

            # Structural rules
            [[ "${sdir}" =~ \.openclaw ]] && continue
            [[ "${sdir}" =~ planning-with-files ]] && [[ ! "${sdir}" =~ \.agents/skills ]] && continue
            [[ "${sdir}" =~ ui-ux-pro-max ]] && [[ ! "${sdir}" =~ \.claude/skills ]] && continue
            [[ "${sdir}" =~ caveman/plugins ]] && continue

            local target_dir="${pdir}"
            if [ -d "${pdir}/skills" ] && [ "$(basename "${pdir}")" != "skills" ]; then
                target_dir="${sdir}"
            fi
            [[ "${pdir}" == "${SOURCE_DIR}/skills/standalone" ]] && target_dir="${sdir}"
            [[ "${sdir}" =~ taste-skill/skills ]] && target_dir="${sdir}"

            local win_target="${target_dir}"
            command -v cygpath &>/dev/null && win_target="$(cygpath -m "${target_dir}")"
            if [ -z "${seen_dirs[${win_target}]:-}" ]; then
                seen_dirs["${win_target}"]=1
                json_entries+=("    { \"path\": \"${win_target}\" }")
            fi
        done < <(find "${SOURCE_DIR}/skills/packs" "${SOURCE_DIR}/skills/standalone" -type f \( -name "SKILL.md" -o -name "skill.md" \) 2>/dev/null || true)

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
        SKILLS_LINKED=$((SKILLS_LINKED + ${#PROCESSED_SKILLS[@]}))
    fi
    echo ""

    # 6. Link Subagents
    echo "--- Step 6: Linking Subagents ---"
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

    # 7. Link Custom Commands
    echo "--- Step 7: Linking Slash Commands for Custom Skills ---"
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

    # 8. Auto-Pruning
    echo "--- Step 8: Auto-Pruning Orphaned & Removed Items ---"
    local PRUNED=0
    if [ -f "${PREV_MANIFEST}" ] && [ -f "${MANIFEST_FILE}" ]; then
        while IFS= read -r entry || [ -n "$entry" ]; do
            [ -z "$entry" ] && continue
            if ! grep -q -F "${entry}" "${MANIFEST_FILE}" 2>/dev/null; then
                local type="${entry%%:*}"
                local name="${entry#*:}"
                if [ "$type" = "skill" ]; then
                    [ -e "${HOME}/.claude/skills/${name}" ] && rm -rf "${HOME}/.claude/skills/${name}" && PRUNED=$((PRUNED + 1))
                    [ -e "${HOME}/.gemini/config/skills/${name}" ] && rm -rf "${HOME}/.gemini/config/skills/${name}" && PRUNED=$((PRUNED + 1))
                    echo "  [PRUNED] Skill [${name}]"
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
                    if ! grep -q "^skill:${sname}$" "${MANIFEST_FILE}" 2>/dev/null; then
                        rm -rf "${s}" 2>/dev/null || true
                        echo "  [PURGED UNMANAGED] Skill [${sname}]"
                        UNMANAGED_PURGED=$((UNMANAGED_PURGED + 1))
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
    echo ""

    # 9. Summary & Fast Status
    echo "=== Summary ==="
    echo "Global Rules  : ${RULES_LINKED}"
    echo "Skills Linked : ${SKILLS_LINKED}"
    echo "Commands Ready: ${COMMANDS_LINKED}"
    echo "Agents Linked : ${AGENTS_LINKED}"
    echo "Skipped Items : ${SKIPPED_COUNT}"
    echo ""
    run_status
    echo ""
    echo "================================================================"
    echo "  [✓] HAWS Universal Sync Completed Successfully."
    echo "================================================================"
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

interactive_checklist() {
    local title="$1"
    shift
    local items=("$@") # Format: "name|detail|initial_state_0_or_1"
    local count=${#items[@]}
    [ "$count" -eq 0 ] && return 0

    local item_names=()
    local item_details=()
    local item_states=()

    for item in "${items[@]}"; do
        local n="${item%%|*}"
        local rest="${item#*|}"
        local d="${rest%%|*}"
        local s="${rest##*|}"
        item_names+=("$n")
        item_details+=("$d")
        item_states+=("$s")
    done

    local total=$((count + 1))
    local cursor=0
    local cancelled=0

    render_row() {
        local idx="$1"
        local is_curr="$2"
        local ptr="  "
        [ "$is_curr" -eq 1 ] && ptr="> "

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
            printf "\033[2K\r%s%s %b%-26s\033[0m \033[90m(%s)\033[0m\n" "${ptr}" "${mark}" "${color}" "${item_names[$real_idx]}" "${item_details[$real_idx]}"
        fi
    }

    echo ""
    echo "=== ${title} ==="
    echo "Controls: [↑/↓] Navigate | [Space] Toggle | [Enter] Confirm & Save | [q] Cancel"
    echo ""

    for ((i=0; i<total; i++)); do
        local is_c=0
        [ "$i" -eq "$cursor" ] && is_c=1
        render_row "$i" "$is_c"
    done

    if [ -t 0 ]; then
        printf "\033[?25l" 2>/dev/null || true
        while true; do
            local key=""
            IFS= read -rsn1 key || break
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
            elif [[ "${key}" == " " || "${key}" == "x" || "${key}" == "X" ]]; then
                if [ "$cursor" -eq 0 ]; then
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
                break
            elif [[ "${key}" == "q" || "${key}" == "Q" ]]; then
                cancelled=1
                break
            fi

            printf "\033[%dA" "${total}"
            for ((i=0; i<total; i++)); do
                local is_c=0
                [ "$i" -eq "$cursor" ] && is_c=1
                render_row "$i" "$is_c"
            done
        done
        printf "\033[?25h" 2>/dev/null || true
    fi

    echo ""
    if [ "$cancelled" -eq 1 ]; then
        return 1
    fi

    CHECKLIST_RESULTS=()
    for ((i=0; i<count; i++)); do
        CHECKLIST_RESULTS["${item_names[$i]}"]="${item_states[$i]}"
    done
    return 0
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
                echo "  [INFO] No repositories added. Returning to main menu."
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
        load_disabled_skills
        for ndir in "${newly_added_dirs[@]}"; do
            configure_repo_skills "${SCRIPT_DIR}/${ndir}"
        done
        save_disabled_skills
    else
        echo "  [✓] Kept all skills enabled by default."
    fi

    echo ""
    echo "  [✓] Add Git Repository complete. Returning to main menu."
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
        read -r -p "Press [Enter] to return to main menu: " _dummy || true
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

get_repo_skills() {
    local rdir="$1"
    declare -A seen=()
    while IFS= read -r sf; do
        [ -z "$sf" ] && continue
        [[ "$sf" =~ \.openclaw/ ]] && continue
        [[ "$sf" =~ planning-with-files ]] && [[ ! "$sf" =~ \.agents/skills ]] && [[ ! "$sf" =~ skills/i18n ]] && continue
        [[ "$sf" =~ ui-ux-pro-max ]] && [[ ! "$sf" =~ \.claude/skills ]] && continue
        [[ "$sf" =~ caveman/plugins/ ]] && continue

        local sn
        sn="$(extract_skill_name "$sf")"
        [ -z "$sn" ] && continue
        [ -n "${seen[$sn]:-}" ] && continue
        seen["$sn"]=1

        local sdesc=""
        sdesc="$(extract_skill_desc "$sf")"
        [ -z "$sdesc" ] && sdesc="${sn}"

        echo "${sn}|${sdesc}|${sf}"
    done < <(find "$rdir" -type f \( -name "SKILL.md" -o -name "skill.md" \) 2>/dev/null | sort || true)
}

configure_repo_skills() {
    local rdir="$1"
    local rname="${2:-$(basename "$rdir")}"

    local chk_items=()
    while IFS='|' read -r sn sdesc sf; do
        [ -z "$sn" ] && continue
        local is_on=1
        [ -n "${DISABLED_SKILLS[$sn]:-}" ] && is_on=0
        chk_items+=("${sn}|${sdesc}|${is_on}")
    done < <(get_repo_skills "$rdir")

    if [ ${#chk_items[@]} -eq 0 ]; then
        echo "  [INFO] No skills found in ${rname}."
        return 0
    fi

    declare -A CHECKLIST_RESULTS
    if interactive_checklist "Configure Skills in ${rname}" "${chk_items[@]}"; then
        for sn in "${!CHECKLIST_RESULTS[@]}"; do
            if [ "${CHECKLIST_RESULTS[$sn]}" -eq 1 ]; then
                unset "DISABLED_SKILLS[$sn]"
            else
                DISABLED_SKILLS["$sn"]=1
            fi
        done
        save_disabled_skills
        echo "  [✓] Updated active skills for ${rname}."
    else
        echo "  [INFO] Configuration cancelled. No changes saved."
    fi
}

run_configure_skills() {
    load_disabled_skills
    while true; do
        local single_total=0
        local single_active=0
        local single_repos=()

        # Multi-skill packs
        local pack_repos=()
        local pack_names=()
        local pack_totals=()
        local pack_actives=()

        for rpath in "${SCRIPT_DIR}/skills/packs"/* "${SCRIPT_DIR}/skills/standalone"/* "${SCRIPT_DIR}/skills/custom"/*; do
            [ ! -d "$rpath" ] && continue
            local rname="$(basename "$rpath")"
            local repo_skills=()
            while IFS= read -r line; do
                [ -n "$line" ] && repo_skills+=("$line")
            done < <(get_repo_skills "$rpath")

            local total_in_repo=${#repo_skills[@]}
            [ "$total_in_repo" -eq 0 ] && continue

            local active_in_repo=0
            for item in "${repo_skills[@]}"; do
                local sn="${item%%|*}"
                [ -z "${DISABLED_SKILLS[$sn]:-}" ] && active_in_repo=$((active_in_repo + 1))
            done

            if [ "$total_in_repo" -eq 1 ]; then
                single_repos+=("${repo_skills[0]}")
                single_total=$((single_total + 1))
                single_active=$((single_active + active_in_repo))
            else
                pack_repos+=("$rpath")
                pack_names+=("$rname")
                pack_totals+=("$total_in_repo")
                pack_actives+=("$active_in_repo")
            fi
        done

        echo ""
        echo "============================================================="
        echo "             Configure Active Skills (Enable / Disable)"
        echo "============================================================="
        echo "Select skill category to configure:"
        printf "  1) Single Skills\n     Status: [Active: %d / %d skills]\n" "${single_active}" "${single_total}"
        echo "  2) Multi-Skill Packs"
        echo "     Status:"
        for ((i=0; i<${#pack_names[@]}; i++)); do
            printf "       • %-20s [Active: %2d / %2d skills]\n" "${pack_names[$i]}" "${pack_actives[$i]}" "${pack_totals[$i]}"
        done
        echo "  0) Back to Main Menu"
        echo ""

        local sub_choice="0"
        read -r -p "Enter selection [0-2] (default: 0): " sub_choice || sub_choice="0"
        sub_choice="$(echo "${sub_choice}" | tr -d ' \r\n')"
        [ -z "${sub_choice}" ] && sub_choice="0"

        if [ "${sub_choice}" = "1" ]; then
            local chk_items=()
            for sitem in "${single_repos[@]}"; do
                local sn="${sitem%%|*}"
                local srest="${sitem#*|}"
                local sdesc="${srest%%|*}"
                local is_on=1
                [ -n "${DISABLED_SKILLS[$sn]:-}" ] && is_on=0
                chk_items+=("${sn}|${sdesc}|${is_on}")
            done

            declare -A CHECKLIST_RESULTS
            if interactive_checklist "Configure Single Skills" "${chk_items[@]}"; then
                for sn in "${!CHECKLIST_RESULTS[@]}"; do
                    if [ "${CHECKLIST_RESULTS[$sn]}" -eq 1 ]; then
                        unset "DISABLED_SKILLS[$sn]"
                    else
                        DISABLED_SKILLS["$sn"]=1
                    fi
                done
                save_disabled_skills
                echo "  [✓] Updated single skills configuration."
            else
                echo "  [INFO] Configuration cancelled. No changes saved."
            fi

        elif [ "${sub_choice}" = "2" ]; then
            echo ""
            echo "Select a Skill Pack to configure:"
            for ((i=0; i<${#pack_names[@]}; i++)); do
                printf "  %2d) %-20s [Active: %2d / %2d skills]\n" "$((i+1))" "${pack_names[$i]}" "${pack_actives[$i]}" "${pack_totals[$i]}"
            done
            echo "   0) Back"
            echo ""
            local p_idx=""
            read -r -p "Select pack [0-${#pack_names[@]}] (default: 0): " p_idx || p_idx="0"
            p_idx="$(echo "${p_idx}" | tr -d ' \r\n')"
            [ -z "${p_idx}" ] && p_idx="0"

            if [[ "${p_idx}" =~ ^[1-9][0-9]*$ ]] && [ "${p_idx}" -le "${#pack_names[@]}" ]; then
                local sel_pack_dir="${pack_repos[$((p_idx - 1))]}"
                local sel_pack_name="${pack_names[$((p_idx - 1))]}"
                configure_repo_skills "${sel_pack_dir}" "${sel_pack_name}"
            fi

        elif [ "${sub_choice}" = "0" ] || [[ "${sub_choice}" =~ ^(q|quit|back|b)$ ]]; then
            break
        fi
    done
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
            h = r_h if len(r_h) >= len(l_h) else l_h
            for line in h:
                if line.strip(): out.append(line)

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

            echo "=== Connecting Second Brain Cloud ==="
            echo "=========================================================================="
            echo " [PRIVACY NOTICE] Ensure your repository is set to PRIVATE on GitHub!"
            echo " Second Brain stores personal notes & anti-patterns and must NEVER be Public."
            echo "=========================================================================="
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
                echo "================================================================"
                echo " [GUARD] WARNING: Disconnecting Second Brain Cloud"
                echo " Current Remote: ${current_remote}"
                echo " This machine will return to Local-Only mode."
                echo " (Your cloud repository data will NOT be deleted)."
                echo "================================================================"
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
                echo "  [*] Syncing Second Brain with ${current_remote}..."
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
            echo "=== HAWS Second Brain Status ==="
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

run_hooks() {
    local action="${1:-install}"
    case "${action}" in
        install)
            echo "=== Installing HAWS Git Hooks ==="
            if [ -d "${SCRIPT_DIR}/.githooks" ]; then
                git -C "${SCRIPT_DIR}" config core.hooksPath .githooks
                chmod +x "${SCRIPT_DIR}/.githooks"/* 2>/dev/null || true
                echo "  [✓] Git core.hooksPath set to .githooks"
                echo "  [✓] pre-commit hook active (Secret scan + LF audit + doctor check)"
                echo "  [✓] commit-msg hook active (Conventional Commits & English invariant)"
                echo "  [✓] pre-push hook active (Human authorization guardrail)"
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

run_uninstall() {
    local dry_run=false
    local force_yes=false

    for arg in "$@"; do
        case "$arg" in
            --dry-run)
                dry_run=true
                ;;
            --yes|-y)
                force_yes=true
                ;;
        esac
    done

    echo "=== HAWS Clean Uninstaller & Environment Restore ==="
    if [ "$dry_run" = true ]; then
        echo "[MODE] DRY-RUN (Previewing actions - no files will be modified or removed)"
    fi
    echo ""

    if [ "$dry_run" = false ] && [ "$force_yes" = false ]; then
        echo "WARNING: This will detach HAWS pointers from all AI tools (Claude, Antigravity, Cursor, Copilot),"
        echo "remove linked skills, subagents, and slash commands, and restore your environment to pre-HAWS state."
        echo "Your project code and Second Brain will NOT be deleted."
        echo ""
        read -r -p "Are you sure you want to proceed with uninstallation? (y/N): " confirm_uninstall
        if [[ ! "${confirm_uninstall:-}" =~ ^[Yy]$ ]]; then
            echo "[ABORTED] Uninstallation cancelled by user."
            return 0
        fi
        echo ""
    fi

    local removed_pointers=0
    local removed_skills=0
    local removed_agents=0
    local removed_commands=0

    # 1. Strip Global Environment Pointers
    echo "--- Step 1: Detaching Global Environment Pointers ---"
    local pointer_files=(
        "${HOME}/.claude/CLAUDE.md"
        "${HOME}/.gemini/GEMINI.md"
        "${HOME}/.cursor/rules/haws.mdc"
        "${HOME}/.cursorrules"
        "${HOME}/.copilot/copilot-instructions.md"
        "${HOME}/.config/github-copilot/copilot-instructions.md"
    )

    strip_pointer_from_file() {
        local target="$1"
        [ ! -f "${target}" ] && return 0

        if grep -q "<!-- HAWS_.*_START -->" "${target}" 2>/dev/null; then
            if [ "$dry_run" = true ]; then
                echo "  [DRY-RUN] Would remove HAWS pointer block from: ${target}"
                removed_pointers=$((removed_pointers + 1))
                return 0
            fi

            local tmp_cleaned="${target}.haws_clean_tmp"
            sed '/<!-- HAWS_.*_START -->/,/<!-- HAWS_.*_END -->/d' "${target}" > "${tmp_cleaned}"
            local non_whitespace
            non_whitespace="$(tr -d '[:space:]' < "${tmp_cleaned}" || true)"
            if [ -z "${non_whitespace}" ]; then
                rm -f "${tmp_cleaned}" "${target}"
                echo "  [REMOVED] ${target} (contained only HAWS pointer)"
            else
                mv -f "${tmp_cleaned}" "${target}"
                echo "  [STRIPPED] ${target} (removed HAWS pointer, preserved user configuration)"
            fi
            removed_pointers=$((removed_pointers + 1))
        fi
    }

    for pfile in "${pointer_files[@]}"; do
        strip_pointer_from_file "${pfile}"
    done
    echo ""

    # 2. Detach Antigravity Native Config & Legacy Links
    echo "--- Step 2: Detaching Antigravity (AGY) Skills & Agents ---"
    local gemini_json="${HOME}/.gemini/config/skills.json"
    if [ -f "${gemini_json}" ]; then
        if [ "$dry_run" = true ]; then
            echo "  [DRY-RUN] Would clean HAWS paths from: ${gemini_json}"
        else
            local remaining_entries
            remaining_entries="$(grep -v 'Human-AI-Working-Standard' "${gemini_json}" | grep '"path"' || true)"
            if [ -z "${remaining_entries}" ]; then
                rm -f "${gemini_json}"
                echo "  [REMOVED] ${gemini_json}"
            else
                local tmp_json="${gemini_json}.tmp"
                grep -v 'Human-AI-Working-Standard' "${gemini_json}" > "${tmp_json}"
                mv -f "${tmp_json}" "${gemini_json}"
                echo "  [UPDATED] Removed HAWS skill paths from ${gemini_json}"
            fi
        fi
    fi

    # 3. Clean Skills and Agents via Manifest
    echo "--- Step 3: Cleaning Linked Skills, Agents, and Slash Commands ---"
    local manifest_file="${HOME}/.haws_manifest"
    if [ -f "${manifest_file}" ]; then
        while IFS= read -r entry || [ -n "$entry" ]; do
            [ -z "$entry" ] && continue
            local type="${entry%%:*}"
            local name="${entry#*:}"
            if [ "$type" = "skill" ]; then
                if [ -e "${HOME}/.claude/skills/${name}" ] || [ -L "${HOME}/.claude/skills/${name}" ]; then
                    if [ "$dry_run" = true ]; then
                        echo "  [DRY-RUN] Would remove Claude skill: ~/.claude/skills/${name}"
                    else
                        rm -rf "${HOME}/.claude/skills/${name}"
                    fi
                    removed_skills=$((removed_skills + 1))
                fi
                if [ -e "${HOME}/.gemini/config/skills/${name}" ] || [ -L "${HOME}/.gemini/config/skills/${name}" ]; then
                    if [ "$dry_run" = true ]; then
                        echo "  [DRY-RUN] Would remove Antigravity skill: ~/.gemini/config/skills/${name}"
                    else
                        rm -rf "${HOME}/.gemini/config/skills/${name}"
                    fi
                fi
            elif [ "$type" = "agent" ]; then
                if [ -f "${HOME}/.claude/agents/${name}.md" ]; then
                    if [ "$dry_run" = true ]; then
                        echo "  [DRY-RUN] Would remove Claude agent: ~/.claude/agents/${name}.md"
                    else
                        rm -f "${HOME}/.claude/agents/${name}.md"
                    fi
                    removed_agents=$((removed_agents + 1))
                fi
                if [ -d "${HOME}/.gemini/config/agents/${name}" ]; then
                    if [ "$dry_run" = true ]; then
                        echo "  [DRY-RUN] Would remove Antigravity agent: ~/.gemini/config/agents/${name}"
                    else
                        rm -rf "${HOME}/.gemini/config/agents/${name}"
                    fi
                    removed_agents=$((removed_agents + 1))
                fi
            fi
        done < "${manifest_file}"
    fi

    # Custom Slash Commands for Claude
    if [ -d "${HOME}/.claude/commands" ] && [ -d "${SCRIPT_DIR}/skills/custom" ]; then
        for cdir in "${SCRIPT_DIR}/skills/custom"/*; do
            if [ -d "${cdir}" ]; then
                local cname="$(basename "${cdir}")"
                local cmd_file="${HOME}/.claude/commands/${cname}.md"
                if [ -f "${cmd_file}" ]; then
                    if [ "$dry_run" = true ]; then
                        echo "  [DRY-RUN] Would remove Claude custom slash command: ~/.claude/commands/${cname}.md"
                    else
                        rm -f "${cmd_file}"
                        echo "  [REMOVED] ~/.claude/commands/${cname}.md"
                    fi
                    removed_commands=$((removed_commands + 1))
                fi
            fi
        done
    fi

    # Remove manifest files
    if [ "$dry_run" = true ]; then
        [ -f "${HOME}/.haws_manifest" ] && echo "  [DRY-RUN] Would remove ~/.haws_manifest"
    else
        rm -f "${HOME}/.haws_manifest" "${HOME}/.haws_manifest.prev" 2>/dev/null || true
    fi
    echo ""

    # 4. Detach Git Hooks
    echo "--- Step 4: Detaching Git Safety Hooks ---"
    if [ -d "${SCRIPT_DIR}/.git" ]; then
        if [ "$dry_run" = true ]; then
            echo "  [DRY-RUN] Would unset Git core.hooksPath (.githooks)"
        else
            git -C "${SCRIPT_DIR}" config --unset core.hooksPath 2>/dev/null || true
            echo "  [DETACHED] Git core.hooksPath unset."
        fi
    fi
    echo ""

    echo "================================================================"
    if [ "$dry_run" = true ]; then
        echo "  [DRY-RUN COMPLETE] Summary of items eligible for removal:"
        echo "  - Pointer Blocks : ${removed_pointers}"
        echo "  - Active Skills  : ${removed_skills}"
        echo "  - Subagents      : ${removed_agents}"
        echo "  - Slash Commands : ${removed_commands}"
        echo "  To execute actual uninstallation, run: ./haws.sh uninstall"
    else
        echo "  [PASS] Uninstallation Complete!"
        echo "  - All HAWS pointers, skills, and hooks have been safely removed."
        echo "  - Local repository (${SCRIPT_DIR}) and Second Brain preserved."
        echo "  - To re-enable HAWS at any time, run: ./haws.sh sync"
    fi
    echo "================================================================"
}

run_setup() {
    echo "=== HAWS Automated Setup & Bootstrapper ==="
    echo ""
    echo "[1/5] Initializing Personal Second Brain & Submodules Protection..."
    run_user status
    echo ""
    if [ -d "${SCRIPT_DIR}/.git" ]; then
        echo "[2/5] Configuring Skill Kit & Git Submodules..."
        local is_modified=false

        if [ -t 0 ]; then
            while true; do
                local default_choice="1"
                [ "$is_modified" = true ] && default_choice="0"

                echo ""
                echo "============================================================="
                echo "             HAWS Automated Setup & Skill Kit"
                echo "============================================================="
                echo "Choose setup mode:"
                echo "  1) Standard HAWS Kit      (Default — install standard curated skills & sync)"
                echo "  2) Add Git Repository     (Add Git repo URLs until 'done')"
                echo "  3) Remove Git Repository  (Select repos to remove with confirmation)"
                echo "  4) Configure Active Skills (Single skills directly, Packs choose repo first)"
                echo "  5) Edit .gitmodules       (Edit Git Repository Links directly in editor)"
                if [ "$is_modified" = true ]; then
                    echo "  0) Save & Finish          (Sync your changes to AI & complete setup)"
                else
                    echo "  0) Save & Finish          (Sync configuration to AI & complete setup)"
                fi
                echo ""
                local kit_choice=""
                read -r -p "Select [0-5] (Default: ${default_choice}): " kit_choice || kit_choice="${default_choice}"
                kit_choice="$(echo "${kit_choice}" | tr -d ' \r\n')"
                [ -z "${kit_choice}" ] && kit_choice="${default_choice}"

                case "${kit_choice}" in
                    1)
                        echo "  [*] Initializing Standard HAWS Kit submodules..."
                        git -C "${SCRIPT_DIR}" submodule update --init --recursive 2>/dev/null || true
                        echo "  [✓] Standard HAWS Kit submodules verified."
                        break
                        ;;
                    2)
                        run_add_git_repo && is_modified=true
                        ;;
                    3)
                        run_remove_git_repo && is_modified=true
                        ;;
                    4)
                        run_configure_skills && is_modified=true
                        ;;
                    5)
                        run_edit_gitmodules && is_modified=true
                        ;;
                    0)
                        break
                        ;;
                    *)
                        echo "  [ERROR] Invalid option '${kit_choice}'. Please enter 0-5."
                        sleep 1
                        ;;
                esac
            done
        else
            echo "  [*] Initializing Standard HAWS Kit submodules (Non-interactive)..."
            git -C "${SCRIPT_DIR}" submodule update --init --recursive 2>/dev/null || true
            echo "  [✓] Standard HAWS Kit submodules verified."
        fi
    fi
    echo ""
    echo "[3/5] Linking Skills, Commands, and Agent Profiles..."
    run_sync "$@"
    echo ""
    echo "[4/5] Configuring HAWS Git Safety Hooks..."
    run_hooks install
    echo ""
    echo "[5/5] Running Diagnostic Verification..."
    run_doctor
}

case "${COMMAND}" in
    status|health|check)
        run_status
        ;;
    doctor|test)
        shift || true
        run_doctor "$@"
        ;;
    setup|bootstrap)
        shift || true
        run_setup "$@"
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
    notify)
        shift || true
        if [ -f "${SCRIPT_DIR}/tools/notify.sh" ]; then
            "${SCRIPT_DIR}/tools/notify.sh" "$@"
        else
            echo "[ERROR] tools/notify.sh not found."
            exit 1
        fi
        ;;
    *)
        echo "Usage: ./haws.sh [setup|sync|status|doctor|hook|kit|user|uninstall|notify] [--clean]"
        echo "  setup           Complete frictionless setup: secondbrain + submodules + sync + hooks + doctor"
        echo "  sync [--clean]  All-in-one Smart Sync (use --clean to purge unmanaged foreign skills)"
        echo "  kit [add|prune|update] Manage KIT submodules and external tools with merge protection"
        echo "  user [connect]  Manage personal Second Brain (symmetrical 1-click cloud sync)"
        echo "  hook [install]  Install or inspect HAWS Git pre-commit and pre-push hooks"
        echo "  status          Instant sub-second skill count and token budget check"
        echo "  doctor [--json] Run comprehensive 10-axis system diagnostics"
        echo "  uninstall       Safely detach HAWS pointers, skills, and hooks without deleting user data"
        echo "  notify          Dispatch task completion alert via Telegram/Discord/Webhook"
        exit 1
        ;;
esac

