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

# Native Codex agent installation is also available without a global sync.
run_codex_agents() {
    if ! command -v node >/dev/null 2>&1; then
        echo "[ERROR] Node.js is required for native Codex agent profiles." >&2
        return 1
    fi
    node "${SCRIPT_DIR}/ai-configs/codex/agents.mjs" "$@"
}

run_status() {
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
    check_item "${SCRIPT_DIR}/SETUP.bat" "SETUP.bat"
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

_haws_remote_access_check() {
    local remote="${1:-}"
    _haws_remote_is_valid "${remote}" || return 2
    [ -n "${remote}" ] || return 1
    [ "${HAWS_VALIDATED_REMOTE:-}" = "${remote}" ] && return 0
    command -v timeout >/dev/null 2>&1 || return 1
    timeout 5 git ls-remote --heads "${remote}" HEAD >/dev/null 2>&1 || return 1
    HAWS_VALIDATED_REMOTE="${remote}"
    export HAWS_VALIDATED_REMOTE
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
                HAWS_SECOND_BRAIN_ENABLED="${value}"
                SECOND_BRAIN_ENABLED="${value}"
                ;;
            second_brain_remote)
                [ -z "${extra:-}" ] || return 2
                _haws_remote_is_valid "${value}" || return 2
                HAWS_SECOND_BRAIN_REMOTE="${value}"
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
    export HAWS_SECOND_BRAIN_ENABLED HAWS_SECOND_BRAIN_REMOTE \
        HAWS_AUTO_UPDATE SECOND_BRAIN_ENABLED AUTO_UPDATE
}

settings_save() {
    local second_brain auto_update second_brain_remote
    case "${1:-}" in
        second_brain|second_brain_enabled|auto_update|second_brain_remote)
            local setting_name="$1"
            local setting_value="${2:-}"
            settings_load || return $?
            case "${setting_name}" in
                second_brain|second_brain_enabled)
                    second_brain="${setting_value}"
                    auto_update="${HAWS_AUTO_UPDATE}"
                    second_brain_remote="${HAWS_SECOND_BRAIN_REMOTE}"
                    ;;
                auto_update)
                    second_brain="${HAWS_SECOND_BRAIN_ENABLED}"
                    auto_update="${setting_value}"
                    second_brain_remote="${HAWS_SECOND_BRAIN_REMOTE}"
                    ;;
                second_brain_remote)
                    second_brain="${HAWS_SECOND_BRAIN_ENABLED}"
                    auto_update="${HAWS_AUTO_UPDATE}"
                    second_brain_remote="${setting_value}"
                    ;;
            esac
            ;;
        *)
            second_brain="${1:-${HAWS_SECOND_BRAIN_ENABLED:-off}}"
            auto_update="${2:-${HAWS_AUTO_UPDATE:-on}}"
            if [ "$#" -ge 3 ]; then
                second_brain_remote="$3"
            else
                second_brain_remote="${HAWS_SECOND_BRAIN_REMOTE:-}"
            fi
            ;;
    esac
    _haws_setting_is_toggle "${second_brain}" || return 2
    _haws_setting_is_toggle "${auto_update}" || return 2
    _haws_remote_is_valid "${second_brain_remote}" || return 2

    local state="$(_haws_state_dir)"
    local file="${state}/settings.tsv"
    local temporary="${state}/settings.stage.$$"
    mkdir -p "${state}" || return 1
    {
        printf 'schema_version\t1\n'
        printf 'second_brain\t%s\n' "${second_brain}"
        [ -z "${second_brain_remote}" ] ||
            printf 'second_brain_remote\t%s\n' "${second_brain_remote}"
        printf 'auto_update\t%s\n' "${auto_update}"
    } > "${temporary}" || {
        rm -f -- "${temporary}"
        return 1
    }
    _haws_state_replace "${temporary}" "${file}"
    local result=$?
    rm -f -- "${temporary}"
    [ "${result}" -eq 0 ] || return "${result}"
    HAWS_SECOND_BRAIN_ENABLED="${second_brain}"
    HAWS_SECOND_BRAIN_REMOTE="${second_brain_remote}"
    HAWS_AUTO_UPDATE="${auto_update}"
    SECOND_BRAIN_ENABLED="${second_brain}"
    AUTO_UPDATE="${auto_update}"
    export HAWS_SECOND_BRAIN_ENABLED HAWS_SECOND_BRAIN_REMOTE \
        HAWS_AUTO_UPDATE SECOND_BRAIN_ENABLED AUTO_UPDATE
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
    done < <(catalog_sources)
    return 1
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

catalog_skills() {
    local row source_id path url revision source_dir skill_file entrypoint
    local display_name skill_id active
    while IFS= read -r row || [ -n "${row}" ]; do
        [ -n "${row}" ] || continue
        IFS=$'\t' read -r source_id path url revision <<< "${row}"
        source_dir="$(_catalog_repo_dir)/${path}"
        [ -d "${source_dir}" ] || continue
        while IFS= read -r -d '' skill_file; do
            [ -s "${skill_file}" ] || continue
            entrypoint="${skill_file#${source_dir}/}"
            display_name="$(extract_skill_name "${skill_file}")"
            skill_id="${source_id}::${entrypoint}"
            active=1
            _catalog_is_disabled "${skill_id}" "${display_name}" "${entrypoint}" && active=0
            printf '%s\t%s\t%s\t%s\t%s\n' \
                "${skill_id}" "${display_name}" "${source_id}" "${entrypoint}" "${active}"
        done < <(find "${source_dir}" -type f \
            \( -name SKILL.md -o -name skill.md \) -print0 2>/dev/null | sort -z)
    done < <(catalog_sources)
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

_legacy_skill_is_disabled() {
    local skill_path="$1"
    local skill_name="$2"
    local repo="$(_catalog_repo_dir)"
    local skill_file="${skill_path}"
    local source_id source_path source_url source_revision entrypoint

    [ -n "${DISABLED_SKILLS["${skill_name}"]:-}" ] && return 0
    if [ -d "${skill_path}" ]; then
        if [ -f "${skill_path}/SKILL.md" ]; then
            skill_file="${skill_path}/SKILL.md"
        elif [ -f "${skill_path}/skill.md" ]; then
            skill_file="${skill_path}/skill.md"
        fi
    fi
    while IFS=$'\t' read -r source_id source_path source_url source_revision ||
        [ -n "${source_id}" ]; do
        [ -n "${source_id}" ] || continue
        case "${skill_file}" in
            "${repo}/${source_path}"/*)
                entrypoint="${skill_file#${repo}/${source_path}/}"
                _catalog_is_disabled "${source_id}::${entrypoint}" \
                    "${skill_name}" "${entrypoint}" && return 0
                ;;
        esac
    done < <(catalog_sources)
    return 1
}

run_sync() {
    local CLEAN_UNMANAGED=false
    for opt in "$@"; do
        [ "$opt" = "--clean" ] && CLEAN_UNMANAGED=true
    done
    shift || true
    settings_load || return $?
    if [ "${HAWS_SECOND_BRAIN_ENABLED:-off}" = on ]; then
        if [ -z "${HAWS_SECOND_BRAIN_REMOTE:-}" ] ||
            ! _haws_remote_access_check "${HAWS_SECOND_BRAIN_REMOTE}"; then
            echo "Remote validation failed. Sync aborted."
            return 1
        fi
    fi
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
    echo ""

    # 5. Link Skills
    echo "--- Step 5: Linking Skills ---"
    echo "  [*] Discovering and linking active skills to AI environments, please wait..."
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
            _legacy_skill_is_disabled "${skill_file}" "${skill_name}" && continue

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
                if [ "$DETECTED_CODEX" = true ]; then
                    safe_link_dir "${skill_dir}" "${HOME}/.agents/skills/${skill_name}" "Codex Skill [${skill_name}]"
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
                _legacy_skill_is_disabled "${cdir}" "${cname}" && continue
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
            _legacy_skill_is_disabled "${f}" "${sname}" && continue
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
            [[ "${sdir}" =~ skills/standalone/ ]] && target_dir="${sdir}"

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
        local active_count=${#PROCESSED_SKILLS[@]}
        SKILLS_LINKED=$((SKILLS_LINKED + active_count))
    fi
    local active_count=${#PROCESSED_SKILLS[@]}
    echo "  [✓] Skills linking complete (${active_count} active skills linked)."
    echo ""

    # 6. Link Subagents
    echo "--- Step 6: Linking Subagents ---"
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

interactive_menu() {
    local mode="$1"
    local title="$2"
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
        item_names=("${items[@]}")
    else
        item_names=("${items[@]}")
    fi

    local cursor=0
    local cancelled=0

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
                printf "\033[2K\r%s%s %b%-26s\033[0m \033[90m(%s)\033[0m\n" "${ptr}" "${mark}" "${color}" "${item_names[$real_idx]}" "${item_details[$real_idx]}"
            fi
        elif [ "${mode}" = "settings" ]; then
            local state_mark=""
            case "${item_states[$idx]}" in
                on) state_mark=" [ On ]" ;;
                off) state_mark=" [ Off ]" ;;
            esac
            printf "\033[2K\r%s%s%s\n" "${ptr}" "${item_names[$idx]}" "${state_mark}"
        else
            printf "\033[2K\r%s%s\n" "${ptr}" "${item_names[$idx]}"
        fi
    }

    echo ""
    if [ "${mode}" = "checklist" ]; then
        echo "=== ${title} ==="
        echo "Controls: [↑/↓] Navigate | [Space] Toggle | [Enter] Confirm & Save | [q] Cancel"
    elif [ "${mode}" = "settings" ]; then
        echo "=== ${title} ==="
        echo "Controls: Up/Down Move | Enter Select | Space Toggle | Q Back"
    else
        echo "============================================================="
        echo "                       ${title}"
        echo "============================================================="
    fi
    echo ""

    for ((i=0; i<total; i++)); do
        local is_c=0
        [ "$i" -eq "$cursor" ] && is_c=1
        render_row "$i" "$is_c"
    done
    if [ "${mode}" = "menu" ] || [ "${mode}" = "settings" ]; then
        echo ""
        if [ "${mode}" = "settings" ]; then
            echo "Controls: Up/Down Move | Enter Select | Space Toggle | Q Back"
        else
            echo "Controls: Up/Down Move | Enter Select | Q Exit"
        fi
    fi

    local interactive_terminal=0
    [ -t 0 ] && [ -t 1 ] && interactive_terminal=1
    local redraw_rows="${total}"
    if [ "${mode}" = "menu" ] || [ "${mode}" = "settings" ]; then
        redraw_rows=$((total + 2))
    fi
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
            break
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
            if [ "${mode}" = "menu" ]; then
                echo ""
                echo "Controls: Up/Down Move | Enter Select | Q Exit"
            elif [ "${mode}" = "settings" ]; then
                echo ""
                echo "Controls: Up/Down Move | Enter Select | Space Toggle | Q Back"
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
    local with_desc="${2:-1}"
    declare -A seen=()
    while IFS= read -r sf; do
        [ -z "$sf" ] && continue
        [[ "$sf" =~ \.openclaw/ ]] && continue
        [[ "$sf" =~ planning-with-files ]] && [[ ! "$sf" =~ \.agents/skills ]] && [[ ! "$sf" =~ skills/i18n ]] && continue
        [[ "$sf" =~ ui-ux-pro-max ]] && [[ ! "$sf" =~ \.claude/skills ]] && continue
        [[ "$sf" =~ caveman/plugins/ ]] && continue

        local sn="$(extract_skill_name "$sf")"
        [ -z "$sn" ] && continue
        [ -n "${seen[$sn]:-}" ] && continue
        seen["$sn"]=1

        local sdesc=""
        if [ "$with_desc" -eq 1 ]; then
            sdesc="$(extract_skill_desc "$sf")"
            [ -z "$sdesc" ] && sdesc="${sn}"
        fi

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
    done < <(get_repo_skills "$rdir" 1)

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
    printf "  [*] Scanning skills catalog, please wait...\r"
    local single_total=0
    local single_names=()
    local single_files=()

    local -A repo_total=()
    local -A repo_first_sn=()
    local -A repo_first_sf=()
    local -A repo_all_skills=()
    local -A seen_combo=()
    local -A repo_registered=()
    local repo_order=()

    while IFS= read -r sf; do
        [ -z "$sf" ] && continue
        [[ "$sf" =~ \.openclaw/ ]] && continue
        [[ "$sf" =~ planning-with-files ]] && [[ ! "$sf" =~ \.agents/skills ]] && [[ ! "$sf" =~ skills/i18n ]] && continue
        [[ "$sf" =~ ui-ux-pro-max ]] && [[ ! "$sf" =~ \.claude/skills ]] && continue
        [[ "$sf" =~ caveman/plugins/ ]] && continue

        local rel="${sf#${SCRIPT_DIR}/skills/}"
        local category="${rel%%/*}"
        local rest="${rel#*/}"
        local rname="${rest%%/*}"
        local rpath="${SCRIPT_DIR}/skills/${category}/${rname}"

        local sn="$(extract_skill_name "$sf")"
        [ -z "$sn" ] && continue

        local combo="${rpath}|${sn}"
        [ -n "${seen_combo[$combo]:-}" ] && continue
        seen_combo["$combo"]=1

        if [ -z "${repo_registered[$rpath]:-}" ]; then
            repo_registered["$rpath"]=1
            repo_order+=("$rpath")
            repo_total["$rpath"]=0
            repo_all_skills["$rpath"]=""
        fi

        repo_total["$rpath"]=$(( ${repo_total["$rpath"]} + 1 ))
        repo_first_sn["$rpath"]="$sn"
        repo_first_sf["$rpath"]="$sf"
        repo_all_skills["$rpath"]="${repo_all_skills["$rpath"]} ${sn}"
    done < <(find "${SCRIPT_DIR}/skills" -type f \( -name "SKILL.md" -o -name "skill.md" \) 2>/dev/null | sort || true)

    local pack_repos=()
    local pack_names=()
    local pack_totals=()

    for rpath in "${repo_order[@]}"; do
        local rname="$(basename "$rpath")"
        local tot="${repo_total[$rpath]}"

        if [ "$tot" -eq 1 ]; then
            single_total=$((single_total + 1))
            single_names+=("${repo_first_sn[$rpath]}")
            single_files+=("${repo_first_sf[$rpath]}")
        else
            pack_repos+=("$rpath")
            pack_names+=("$rname")
            pack_totals+=("$tot")
        fi
    done

    printf "\033[2K"
    echo "  [✓] Skills catalog ready."

    while true; do
        # Fast in-memory recount of active skills (0 subprocesses, 0 disk I/O)
        local single_active=0
        for sn in "${single_names[@]}"; do
            [ -z "${DISABLED_SKILLS[$sn]:-}" ] && single_active=$((single_active + 1))
        done

        local pack_actives=()
        for ((i=0; i<${#pack_repos[@]}; i++)); do
            local rpath="${pack_repos[$i]}"
            local act=0
            for sn in ${repo_all_skills["$rpath"]}; do
                [ -z "${DISABLED_SKILLS[$sn]:-}" ] && act=$((act + 1))
            done
            pack_actives+=("$act")
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
            echo ""
            echo "  [*] Loading Single Skills checklist..."
            local chk_items=()
            for ((i=0; i<${#single_names[@]}; i++)); do
                local sn="${single_names[$i]}"
                local sf="${single_files[$i]}"
                local sdesc="$(extract_skill_desc "$sf")"
                [ -z "$sdesc" ] && sdesc="${sn}"
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
            if ! read -r -p "Select pack [0-${#pack_names[@]}] (default: 0): " p_idx; then
                [ -n "${p_idx}" ] || p_idx="0"
            fi
            p_idx="$(echo "${p_idx}" | tr -d ' \r\n')"
            [ -z "${p_idx}" ] && p_idx="0"

            if [[ "${p_idx,,}" =~ ^(q|quit|back|b)$ ]]; then
                break
            elif [[ "${p_idx}" =~ ^[1-9][0-9]*$ ]] && [ "${p_idx}" -le "${#pack_names[@]}" ]; then
                local sel_pack_dir="${pack_repos[$((p_idx - 1))]}"
                local sel_pack_name="${pack_names[$((p_idx - 1))]}"
                echo ""
                echo "  [*] Loading skills for ${sel_pack_name}, please wait..."
                configure_repo_skills "${sel_pack_dir}" "${sel_pack_name}"
            fi

        elif [ "${sub_choice}" = "0" ] || [[ "${sub_choice,,}" =~ ^(q|quit|back|b)$ ]]; then
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

    # Preflight native profiles before detaching other environments. Conflicting
    # user files are preserved, including edited HAWS-generated profiles.
    if [ -f "${CODEX_HOME:-${HOME}/.codex}/haws-agents.json" ]; then
        run_codex_agents uninstall --dry-run
        if [ "$dry_run" = false ]; then
            run_codex_agents uninstall
        fi
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
        "${HOME}/.codex/AGENTS.md"
        "${HOME}/.codex/AGENTS.override.md"
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
                if [ -e "${HOME}/.agents/skills/${name}" ] || [ -L "${HOME}/.agents/skills/${name}" ]; then
                    if [ "$dry_run" = true ]; then
                        echo "  [DRY-RUN] Would remove Codex skill: ~/.agents/skills/${name}"
                    else
                        rm -rf "${HOME}/.agents/skills/${name}"
                    fi
                    removed_skills=$((removed_skills + 1))
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
    HAWS_DRAFT_SKILLS="$(catalog_skills | awk -F '\t' '$5 == 1 {print $1}')"
    HAWS_DRAFT_SKILLS_LOADED=1
    HAWS_PERSIST_SKILLS="${HAWS_DRAFT_SKILLS}"
    export HAWS_PERSIST_SKILLS HAWS_DRAFT_SKILLS HAWS_DRAFT_SKILLS_LOADED
}

settings_draft_load() {
    settings_load || return $?
    disabled_environments_load
    HAWS_PERSIST_SECOND_BRAIN="${HAWS_SECOND_BRAIN_ENABLED}"
    HAWS_PERSIST_SECOND_BRAIN_REMOTE="${HAWS_SECOND_BRAIN_REMOTE}"
    HAWS_PERSIST_AUTO_UPDATE="${HAWS_AUTO_UPDATE}"
    HAWS_PERSIST_ENVIRONMENTS=""
    local environment
    while IFS= read -r environment; do
        [ -n "${DISABLED_ENVIRONMENTS[${environment}]:-}" ] && continue
        HAWS_PERSIST_ENVIRONMENTS+="${environment}"$'\n'
    done < <(_haws_detected_environments)
    HAWS_DRAFT_SECOND_BRAIN="${HAWS_PERSIST_SECOND_BRAIN}"
    HAWS_DRAFT_SECOND_BRAIN_REMOTE="${HAWS_PERSIST_SECOND_BRAIN_REMOTE}"
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
    export HAWS_PERSIST_SECOND_BRAIN HAWS_PERSIST_SECOND_BRAIN_REMOTE \
        HAWS_PERSIST_AUTO_UPDATE HAWS_PERSIST_ENVIRONMENTS \
        HAWS_DRAFT_SECOND_BRAIN HAWS_DRAFT_SECOND_BRAIN_REMOTE \
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
    unset HAWS_PERSIST_SECOND_BRAIN HAWS_PERSIST_SECOND_BRAIN_REMOTE \
        HAWS_PERSIST_AUTO_UPDATE HAWS_PERSIST_ENVIRONMENTS \
        HAWS_DRAFT_SECOND_BRAIN HAWS_DRAFT_SECOND_BRAIN_REMOTE \
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
    [ "${HAWS_DRAFT_SECOND_BRAIN:-}" != "${HAWS_PERSIST_SECOND_BRAIN:-}" ] && return 0
    [ "${HAWS_DRAFT_SECOND_BRAIN_REMOTE:-}" != "${HAWS_PERSIST_SECOND_BRAIN_REMOTE:-}" ] && return 0
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
    HAWS_DRAFT_SECOND_BRAIN="off"
    HAWS_DRAFT_SECOND_BRAIN_REMOTE=""
    HAWS_DRAFT_AUTO_UPDATE="on"
    HAWS_DRAFT_ENVIRONMENTS="$(_haws_detected_environments)"
    HAWS_DRAFT_ENVIRONMENTS_TOUCHED=1
    HAWS_DRAFT_SOURCES="${HAWS_PERSIST_SOURCES:-}"
    HAWS_DRAFT_ADDED_REPOSITORIES=""
    HAWS_DRAFT_ADDED_PATHS=""
    HAWS_DRAFT_SKILLS=""
    HAWS_DRAFT_SKILLS_LOADED=0
    export HAWS_DRAFT_SECOND_BRAIN HAWS_DRAFT_SECOND_BRAIN_REMOTE \
        HAWS_DRAFT_AUTO_UPDATE HAWS_DRAFT_ENVIRONMENTS \
        HAWS_DRAFT_ENVIRONMENTS_TOUCHED HAWS_DRAFT_SOURCES \
        HAWS_DRAFT_ADDED_REPOSITORIES HAWS_DRAFT_ADDED_PATHS \
        HAWS_DRAFT_SKILLS HAWS_DRAFT_SKILLS_LOADED
    echo "The draft now contains default values. Nothing has changed on this computer yet."
    return 0
}

_settings_collect_second_brain_remote() {
    [ "${HAWS_DRAFT_SECOND_BRAIN:-off}" = on ] || return 0
    [ -n "${HAWS_DRAFT_SECOND_BRAIN_REMOTE:-}" ] && return 0

    echo "Second Brain Remote URL (draft only)"
    local remote=""
    if ! read -r -p "Enter remote URL (blank cancels): " remote; then
        [ -n "${remote}" ] || remote=""
    fi
    remote="${remote%$'\r'}"
    case "${remote}" in
        q|Q) remote="" ;;
    esac
    if [ -z "${remote}" ]; then
        echo "Cannot enable Second Brain Remote without a remote URL. No changes saved."
        HAWS_DRAFT_SECOND_BRAIN="off"
        export HAWS_DRAFT_SECOND_BRAIN
        return 1
    fi
    if ! _haws_remote_is_valid "${remote}"; then
        echo "Invalid remote URL. No changes saved."
        HAWS_DRAFT_SECOND_BRAIN="off"
        export HAWS_DRAFT_SECOND_BRAIN
        return 1
    fi
    HAWS_DRAFT_SECOND_BRAIN_REMOTE="${remote}"
    export HAWS_DRAFT_SECOND_BRAIN_REMOTE
    echo "Remote URL saved in draft; it will be applied only after Preview and Apply."
    return 0
}

_settings_skill_selector() {
    local title="$1"
    local rows="$2"
    local wanted_source="${3:-}"
    local source_id entrypoint id display active source_count
    local detail label source_path skill_file
    local items=() ids=()
    local -A source_counts=() display_counts=()

    while IFS=$'\t' read -r id display source_id entrypoint active || [ -n "${id}" ]; do
        [ -n "${id}" ] || continue
        source_counts["${source_id}"]=$(( ${source_counts[${source_id}]:-0} + 1 ))
        display_counts["${display}"]=$(( ${display_counts[${display}]:-0} + 1 ))
    done <<< "${rows}"

    while IFS=$'\t' read -r id display source_id entrypoint active || [ -n "${id}" ]; do
        [ -n "${id}" ] || continue
        source_count="${source_counts[${source_id}]:-0}"
        if [ -n "${wanted_source}" ]; then
            [ "${source_id}" = "${wanted_source}" ] || continue
        else
            [ "${source_count}" -eq 1 ] || continue
        fi
        label="${display}"
        if [ "${display_counts[${display}]:-0}" -gt 1 ]; then
            label="${display} [${source_id}::${entrypoint}]"
        fi
        source_path="$(_catalog_source_fields "${source_id}" 2>/dev/null | cut -f1)"
        skill_file="$(_catalog_repo_dir)/${source_path}/${entrypoint}"
        detail="$(extract_skill_desc "${skill_file}")"
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

settings_skills_page() {
    _settings_ensure_skill_draft || return 1
    local rows="$(catalog_skills)"
    local id display source_id entrypoint active source_count
    local single_total=0 single_active=0
    local pack_total=0
    local pack_ids=() pack_names=()
    local -A source_counts=() pack_name_counts=() seen_sources=()

    while IFS=$'\t' read -r id display source_id entrypoint active || [ -n "${id}" ]; do
        [ -n "${id}" ] || continue
        source_counts["${source_id}"]=$(( ${source_counts[${source_id}]:-0} + 1 ))
    done <<< "${rows}"
    while IFS=$'\t' read -r id display source_id entrypoint active || [ -n "${id}" ]; do
        [ -n "${id}" ] || continue
        source_count="${source_counts[${source_id}]:-0}"
        if [ "${source_count}" -eq 1 ]; then
            single_total=$((single_total + 1))
            _settings_list_contains "${HAWS_DRAFT_SKILLS:-}" "${id}" && \
                single_active=$((single_active + 1))
        elif [ -z "${seen_sources[${source_id}]:-}" ]; then
            seen_sources["${source_id}"]=1
            pack_ids+=("${source_id}")
            local pack_name="${source_id##*/}"
            pack_names+=("${pack_name}")
            pack_name_counts["${pack_name}"]=$(( ${pack_name_counts[${pack_name}]:-0} + 1 ))
            pack_total=$((pack_total + 1))
        fi
    done <<< "${rows}"

    while true; do
        echo ""
        echo "============================================================="
        echo "             Configure Active Skills (Enable / Disable)"
        echo "============================================================="
        printf "  Single Skills\n     Status: [Active: %d / %d skills]\n" \
            "${single_active}" "${single_total}"
        echo "  Multi-Skill Packs"
        echo "     Status: [${pack_total} pack(s)]"
        echo ""
        if interactive_menu menu "Configure Active Skills (Enable / Disable)" \
            "Single Skills" "Multi-Skill Packs" "Back to Settings"; then
            case "${INTERACTIVE_MENU_SELECTION}" in
                0)
                    _settings_skill_selector "Configure Single Skills" "${rows}" || true
                    ;;
                1)
                    local pack_items=() i pack_label
                    for ((i=0; i<${#pack_ids[@]}; i++)); do
                        pack_label="${pack_names[$i]}"
                        if [ "${pack_name_counts[${pack_label}]:-0}" -gt 1 ]; then
                            pack_label="${pack_label} [${pack_ids[$i]}]"
                        fi
                        pack_items+=("${pack_label}")
                    done
                    pack_items+=("Back to Settings")
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
        type=PACK
        [[ "${path}" == skills/standalone/* ]] && type=SINGLE
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
        if ! interactive_menu menu "Repositories" \
            "Add Git Repository" "Remove Git Repository" "Back to Settings"; then
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
    local items=(
        "Repositories|Existing repository sources|-"
        "Skills|Existing Single Skills and Multi-Skill Packs|-"
        "AI Environments|${environment_count} selected|-"
        "Second Brain Remote|Toggle remote participation|${HAWS_DRAFT_SECOND_BRAIN:-off}"
        "Auto Update|Toggle remote update work during explicit Sync|${HAWS_DRAFT_AUTO_UPDATE:-on}"
        "Apply|Accept the draft for preview|-"
        "Reset to Defaults|Replace the current draft|-"
        "Discard Changes|Return without saving|-"
    )
    if interactive_menu settings "HAWS Settings" "${items[@]}"; then
        HAWS_DRAFT_SECOND_BRAIN="${INTERACTIVE_MENU_STATES[Second Brain Remote]:-${HAWS_DRAFT_SECOND_BRAIN}}"
        HAWS_DRAFT_AUTO_UPDATE="${INTERACTIVE_MENU_STATES[Auto Update]:-${HAWS_DRAFT_AUTO_UPDATE}}"
        export HAWS_DRAFT_SECOND_BRAIN HAWS_DRAFT_AUTO_UPDATE
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
                echo "This Settings draft row is preserved for the next catalog batch."
                return 2
                ;;
            3|4)
                return 2
                ;;
            5)
                _settings_collect_second_brain_remote || return 2
                return 0
                ;;
            6)
                settings_draft_reset || true
                return 2
                ;;
            7)
                echo "Cancelled. No changes saved."
                return 1
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
    echo "Back to caller."
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
        printf 'setting\tsecond_brain\t%s\n' "${HAWS_DRAFT_SECOND_BRAIN:-off}"
        [ -z "${HAWS_DRAFT_SECOND_BRAIN_REMOTE:-}" ] ||
            printf 'setting\tsecond_brain_remote\t%s\n' "${HAWS_DRAFT_SECOND_BRAIN_REMOTE}"
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
    local title="HAWS — Preview ${HAWS_PLAN_KIND:-Install}"
    _settings_ensure_skill_draft || return 1
    echo ""
    if [ "${HAWS_PLAN_CHANGED:-1}" -eq 0 ]; then
        echo "No settings have changed."
        if interactive_menu menu "${title}" "Back to Settings" "Back to Home"; then
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
    local skill_rows skill_id skill_display skill_source_id entrypoint active printed_skill=0
    skill_rows="$(catalog_skills)"
    while IFS=$'\t' read -r skill_id skill_display skill_source_id entrypoint active ||
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
    echo "Second Brain Remote"
    echo "  $(_haws_toggle_label "${HAWS_DRAFT_SECOND_BRAIN:-off}")"
    echo ""
    echo "Auto Update"
    echo "  $(_haws_toggle_label "${HAWS_DRAFT_AUTO_UPDATE:-on}")"
    if interactive_menu menu "${title}" \
        "${HAWS_PLAN_KIND:-Install}" "Back to Settings" "Cancel"; then
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
    local skill_id display source_id entrypoint active
    mkdir -p "$(dirname "${destination}")" || return 1
    {
        echo "# HAWS Disabled Skills (source-aware)"
        while IFS=$'\t' read -r skill_id display source_id entrypoint active ||
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
    if [ "${HAWS_DRAFT_SECOND_BRAIN:-off}" = on ]; then
        if [ -z "${HAWS_DRAFT_SECOND_BRAIN_REMOTE:-}" ]; then
            echo "Cannot enable Second Brain Remote without a remote URL. No changes saved."
            return 1
        fi
        if ! _haws_remote_is_valid "${HAWS_DRAFT_SECOND_BRAIN_REMOTE}"; then
            echo "Invalid remote URL. No changes saved."
            return 1
        fi
        if ! _haws_remote_access_check "${HAWS_DRAFT_SECOND_BRAIN_REMOTE}"; then
            echo "Remote validation failed. No changes saved."
            return 1
        fi
    fi
    settings_save "${HAWS_DRAFT_SECOND_BRAIN:-off}" \
        "${HAWS_DRAFT_AUTO_UPDATE:-on}" "${HAWS_DRAFT_SECOND_BRAIN_REMOTE:-}" || return 1
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
        echo "Second Brain Remote Off"
        echo "Auto Update         On"
        if interactive_menu menu "HAWS Setup" "Use Default Setup" "Customize Settings" "Exit"; then
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
    settings_load || return $?
    while true; do
        echo ""
        echo "Status: Installed"
        echo "Second Brain Remote: $(_haws_toggle_label "${HAWS_SECOND_BRAIN_ENABLED:-off}")"
        echo "Auto Update: $(_haws_toggle_label "${HAWS_AUTO_UPDATE:-on}")"
        if interactive_menu menu "HAWS Home" "Sync" "Settings" "Doctor" "Status Details" "Uninstall" "Exit"; then
            case "${INTERACTIVE_MENU_SELECTION}" in
                0) run_sync ;;
                1)
                    settings_draft_load || return 1
                    if settings_flow_run settings; then
                        settings_load || return $?
                    else
                        result=$?
                        [ "${result}" -eq 3 ] && return 3
                    fi
                    ;;
                2) run_doctor ;;
                3) run_status ;;
                4) run_uninstall ;;
                *) return 0 ;;
            esac
        else
            return 0
        fi
    done
}

run_lifecycle() {
    if install_is_complete; then
        home_run
    else
        setup_run
    fi
}

run_main_menu() {
    local items=(
        "Skills"
        "Repositories"
        "Second Brain"
        "Sync"
        "Status"
        "Doctor"
        "Uninstall"
        "Exit"
    )

    run_menu_action() {
        local status=0
        bash "${SCRIPT_DIR}/haws.sh" "$@" || status=$?
        if [ "${status}" -ne 0 ]; then
            echo "  [ERROR] Action failed (exit ${status})."
        fi
    }

    while true; do
        if ! interactive_menu menu "HAWS — Main Menu" "${items[@]}"; then
            return 0
        fi
        case "${INTERACTIVE_MENU_SELECTION}" in
            0) run_menu_action skills ;;
            1) run_menu_action kit list ;;
            2) run_menu_action user status ;;
            3) run_menu_action sync ;;
            4) run_menu_action status ;;
            5) run_menu_action doctor ;;
            6) run_menu_action uninstall ;;
            7) return 0 ;;
        esac
    done
}

if [ "${HAWS_SOURCE_ONLY:-0}" != 1 ]; then
case "${COMMAND}" in
    menu|interactive)
        shift || true
        if [ "${BARE_LAUNCH}" = 1 ]; then
            run_lifecycle
        else
            run_main_menu
        fi
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
    skills|skill)
        shift || true
        run_configure_skills "$@"
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
        echo "Usage: ./haws.sh [menu|setup|sync|status|doctor|hook|kit|user|uninstall|notify|codex-agents] [--clean]"
        echo "  codex-agents [install|check|uninstall] [--dry-run] Native Codex roles only (no network sync)"
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
fi
