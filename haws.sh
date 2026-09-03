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
files = []
if os.path.isfile(gemini_json):
    try:
        with open(gemini_json, 'r', encoding='utf-8') as f:
            cfg = json.load(f)
        for entry in cfg.get('entries', []):
            p = entry.get('path', '')
            if os.path.isdir(p):
                for s in os.listdir(p):
                    for mname in ('SKILL.md', 'skill.md'):
                        mf = os.path.join(p, s, mname)
                        if os.path.isfile(mf):
                            files.append(mf)
                            break
    except: pass
if not files and os.path.isdir(gemini_dir):
    raw_files = glob.glob(os.path.join(gemini_dir, '*', 'SKILL.md')) + glob.glob(os.path.join(gemini_dir, '*', 'skill.md'))
    files = list({os.path.normcase(f): f for f in raw_files}.values())

chars = 0
for f in files:
    try:
        with open(f, 'r', encoding='utf-8', errors='ignore') as fp:
            content = fp.read()
        fm = re.search(r'(?s)^---\r?\n(.*?)\r?\n---', content)
        if fm:
            dm = re.search(r'(?s)description:\s*(.*?)(?=\r?\n[a-zA-Z0-9_-]+:|\Z)', fm.group(1))
            if dm:
                chars += len(dm.group(1).strip())
    except: pass
print(f'{len(files)}:{round(chars / 3.8)}')
" 2>/dev/null || echo "0:0")
        gemini_count="${stat_res%%:*}"
        est_tokens="${stat_res##*:}"
    fi

    if [ -z "${gemini_count}" ] || [ "${gemini_count}" -eq 0 ]; then
        [ -d "${gemini_dir}" ] && gemini_count=$(find "${gemini_dir}" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | wc -l)
    fi

    local token_limit=20000
    local token_pct=0
    [ "${est_tokens}" -gt 0 ] && token_pct=$(( (est_tokens * 100) / token_limit ))

    local unmanaged_gemini=0
    local unmanaged_claude=0
    [ "${manifest_count}" -gt 0 ] && [ "${gemini_count}" -gt "${manifest_count}" ] && unmanaged_gemini=$((gemini_count - manifest_count))
    [ "${manifest_count}" -gt 0 ] && [ "${claude_count}" -gt "${manifest_count}" ] && unmanaged_claude=$((claude_count - manifest_count))
    local total_unmanaged=$((unmanaged_gemini + unmanaged_claude))

    echo "=== HAWS Fast Skill & Token Status ==="
    echo "Antigravity Active Skills : ${gemini_count}"
    echo "Claude Code Active Skills : ${claude_count}"
    echo "Manifest Registered Skills: ${manifest_count}"
    [ "${total_unmanaged}" -gt 0 ] && echo "Unmanaged Foreign Skills  : [ALERT: ${total_unmanaged} foreign skill(s) detected - Run './haws.sh sync --clean']"

    if [ "${est_tokens}" -ge 18000 ]; then
        echo "Token Budget Status       : [CRITICAL DANGER: ~${est_tokens} / ${token_limit} (${token_pct}%)]"
        echo "  (!) IMMEDIATE ACTION REQUIRED: Customization budget near overflow."
    elif [ "${est_tokens}" -ge 15000 ]; then
        echo "Token Budget Status       : [WARNING DANGEROUS: ~${est_tokens} / ${token_limit} (${token_pct}%)]"
        echo "  (!) ALERT: Skill descriptions exceed 75% budget. Review largest skills."
    else
        echo "Token Budget Status       : [SAFE: ~${est_tokens} / ${token_limit} (${token_pct}%)]"
    fi

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

    # 1. Check Core Standard Files (6 Canonical Files)
    [ "$json_mode" = false ] && echo "1. Checking Core Standards (6 Canonical Files)..."
    local core_files=("HAWS.md" "WORK_INSTRUCTIONS.md" "WORKFLOW.md" "USER_PREFERENCES.md" "ANTI_PATTERNS.md" "SKILL_TAXONOMY.md")
    for f in "${core_files[@]}"; do
        check_item "${SCRIPT_DIR}/core/${f}" "core/${f}"
    done

    # 2. Check Project Templates (8 Canonical Blueprints)
    [ "$json_mode" = false ] && echo "" && echo "2. Checking Project Templates (8 Canonical Blueprints)..."
    local tpl_files=("README.md" "DESIGN.md" "PROJECT.md" "ARCHITECTURE.md" "CONSTRAINTS.md" "HANDOFF.md" "SOT.md" "AGENTS.md")
    for f in "${tpl_files[@]}"; do
        check_item "${SCRIPT_DIR}/templates/${f}" "templates/${f}"
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

    # 5. Check Root Hygiene
    [ "$json_mode" = false ] && echo "" && echo "5. Checking Root Hygiene..."
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

    # 6. Check for Unmanaged Foreign Skills
    [ "$json_mode" = false ] && echo "" && echo "6. Checking for Unmanaged Foreign Skills..."
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

    # 7. Check Line Endings (LF Normalization)
    [ "$json_mode" = false ] && echo "" && echo "7. Checking Line Endings (LF Normalization)..."
    local crlf_count=0
    for dir in "${SCRIPT_DIR}/core" "${SCRIPT_DIR}/templates" "${SCRIPT_DIR}/agents"; do
        if [ -d "${dir}" ]; then
            for f in "${dir}"/*.md; do
                [ ! -f "${f}" ] && continue
                if grep -q $'\r' "${f}" 2>/dev/null; then
                    crlf_count=$((crlf_count + 1))
                fi
            done
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

run_sync() {
    local CLEAN_UNMANAGED=false
    for opt in "$@"; do
        [ "$opt" = "--clean" ] && CLEAN_UNMANAGED=true
    done
    shift || true
    echo "=== HAWS Universal Command Engine (All-in-One Sync) ==="
    echo ""

    local SOURCE_DIR="${SCRIPT_DIR}"

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
        git -C "${SOURCE_DIR}" submodule update --init --recursive --remote --quiet 2>/dev/null || true
        echo "  [✓] Embedded submodules ready."
        echo ""
    fi

    # 3. Detect AI Environments
    echo "--- Step 3: Detecting AI Environments ---"
    local DETECTED_CLAUDE=false
    local DETECTED_GEMINI=false

    [ -d "${HOME}/.claude" ] && DETECTED_CLAUDE=true
    [ -d "${HOME}/.gemini" ] && DETECTED_GEMINI=true

    [ "$DETECTED_CLAUDE" = true ] && echo "  [✓] Claude Code detected (${HOME}/.claude)"
    [ "$DETECTED_GEMINI" = true ] && echo "  [✓] Google Antigravity detected (${HOME}/.gemini)"
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

        if ln -s "${src}" "${dest}" 2>/dev/null; then
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

            if [ -L "${dest}" ]; then
                local current_target
                current_target="$(readlink "${dest}" || true)"
                if [ "${current_target}" = "${src}" ]; then
                    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                    return 0
                fi
                rm -f "${dest}" 2>/dev/null || true
            elif [ -d "${dest}" ]; then
                rm -rf "${dest}" 2>/dev/null || true
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

        if ln -s "${src}" "${dest}" 2>/dev/null; then
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
        if [ -f "${target_file}" ] && grep -q "${marker_start}" "${target_file}" 2>/dev/null; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            return 0
        fi

        local pointer_content=""
        pointer_content+="${marker_start}\n"
        pointer_content+="# HAWS — Human-AI Working Standard\n"
        pointer_content+="This environment operates under HAWS. Read and adhere to:\n"
        pointer_content+="- Core Standard: ${SOURCE_DIR}/core/HAWS.md\n"
        pointer_content+="- Work Instructions: ${SOURCE_DIR}/core/WORK_INSTRUCTIONS.md\n"
        pointer_content+="- User Preferences & Second Brain: ${SOURCE_DIR}/core/USER_PREFERENCES.md and ${SOURCE_DIR}/core/ANTI_PATTERNS.md\n"
        pointer_content+="${marker_end}\n"

        if [ -f "${target_file}" ]; then
            printf "\n%b" "${pointer_content}" >> "${target_file}"
            echo "  [UPDATED] Appended HAWS Global Pointer to ${target_file}"
        else
            printf "%b" "${pointer_content}" > "${target_file}"
            echo "  [CREATED] Created HAWS Global Pointer at ${target_file}"
        fi
        RULES_LINKED=$((RULES_LINKED + 1))
    }

    # 4. Setup Global Pointers
    echo "--- Step 4: Setting Up Global Environment Pointers ---"
    [ "$DETECTED_CLAUDE" = true ] && safe_append_pointer "${HOME}/.claude/CLAUDE.md"
    [ "$DETECTED_GEMINI" = true ] && safe_append_pointer "${HOME}/.gemini/GEMINI.md"
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
                skill_name="$(grep -E '^[[:space:]]*name:[[:space:]]*' "${skill_file}" | head -n 1 | sed -E 's/^[[:space:]]*name:[[:space:]]*["'"'"']?([^"'"'"'#\r\n]+)["'"'"']?.*$/\1/' | tr -d '\r\n' | xargs 2>/dev/null || true)"
            fi
            [ -z "${skill_name}" ] && skill_name="$(basename "${skill_dir}")"

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

        cat <<EOF > "${target_json}"
{
  "entries": [
    { "path": "${win_source}/skills/standalone" },
    { "path": "${win_source}/skills/packs/agent-skills/skills" },
    { "path": "${win_source}/skills/packs/anthropics-skills/skills" },
    { "path": "${win_source}/skills/packs/mattpocock-skills/skills/engineering" },
    { "path": "${win_source}/skills/packs/mattpocock-skills/skills/in-progress" },
    { "path": "${win_source}/skills/packs/mattpocock-skills/skills/misc" },
    { "path": "${win_source}/skills/packs/mattpocock-skills/skills/productivity" },
    { "path": "${win_source}/skills/packs/superpowers/skills" },
    { "path": "${win_source}/skills/custom" }
  ]
}
EOF
        echo "  [CONFIG] Antigravity Native Config: ${target_json}"
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

run_setup() {
    echo "=== HAWS Automated Setup & Bootstrapper ==="
    echo ""
    if [ -d "${SCRIPT_DIR}/.git" ]; then
        echo "[1/3] Initializing Git Submodules..."
        git -C "${SCRIPT_DIR}" submodule update --init --recursive 2>/dev/null || true
        echo "  [✓] Submodules verified."
    fi
    echo ""
    echo "[2/3] Linking Skills, Commands, and Agent Profiles..."
    run_sync "$@"
    echo ""
    echo "[3/3] Running Diagnostic Verification..."
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
    sync|update|install)
        run_sync "$@"
        ;;
    *)
        echo "Usage: ./haws.sh [setup|sync|status|doctor] [--clean]"
        echo "  setup           Complete frictionless setup: submodules + sync + doctor"
        echo "  sync [--clean]  All-in-one Smart Sync (use --clean to purge unmanaged foreign skills)"
        echo "  status          Instant sub-second skill count and token budget check"
        echo "  doctor [--json] Run comprehensive 7-axis system diagnostics"
        exit 1
        ;;
esac
