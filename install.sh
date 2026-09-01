#!/usr/bin/env bash
# ==============================================================================
# HAWS (Human-AI Working Standard) Cross-Tool Installer (Symlink-Based)
# Supported Tools: Google Antigravity, Claude Code
# ==============================================================================
set -euo pipefail

REPO_URL="https://github.com/apirak-k/Human-AI-Working-Standard.git"
CANONICAL_DIR="${HOME}/haws"

echo "=== HAWS Cross-Tool Installer ==="
echo ""

# 1. Detect Installed AI Tools
DETECTED_CLAUDE=false
DETECTED_GEMINI=false

if [ -d "${HOME}/.claude" ]; then
    DETECTED_CLAUDE=true
fi

if [ -d "${HOME}/.gemini" ]; then
    DETECTED_GEMINI=true
fi

echo "--- Detected AI Environments ---"
if [ "$DETECTED_CLAUDE" = true ]; then
    echo "  [✓] Claude Code detected (${HOME}/.claude)"
else
    echo "  [ ] Claude Code not detected"
fi

if [ "$DETECTED_GEMINI" = true ]; then
    echo "  [✓] Google Antigravity detected (${HOME}/.gemini)"
else
    echo "  [ ] Google Antigravity not detected"
fi

if [ "$DETECTED_CLAUDE" = false ] && [ "$DETECTED_GEMINI" = false ]; then
    echo ""
    echo "Warning: Neither Claude Code nor Google Antigravity directories were detected."
    echo "You can still clone HAWS, but no symlinks will be created."
fi
echo ""

# 2. Canonical Local Clone Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/core/HAWS.md" ]; then
    SOURCE_DIR="${SCRIPT_DIR}"
    echo "Using current repository directory as source: ${SOURCE_DIR}"
else
    SOURCE_DIR="${CANONICAL_DIR}"
    if [ -d "${CANONICAL_DIR}" ]; then
        if [ -d "${CANONICAL_DIR}/.git" ]; then
            echo "Canonical clone found at ${CANONICAL_DIR}. Pulling latest..."
            git -C "${CANONICAL_DIR}" pull --quiet
        else
            echo "ERROR: Directory ${CANONICAL_DIR} exists but is not a Git repository."
            echo "Please inspect or remove it before proceeding."
            exit 1
        fi
    else
        echo "Cloning HAWS repository into ${CANONICAL_DIR}..."
        git clone --quiet "${REPO_URL}" "${CANONICAL_DIR}"
    fi
fi
echo ""

# 2.5 Ensure all git submodules (Skill Packs) are initialized and downloaded
if [ -d "${SOURCE_DIR}/.git" ] && [ -f "${SOURCE_DIR}/.gitmodules" ]; then
    echo "Initializing and updating all embedded skill submodules..."
    git -C "${SOURCE_DIR}" submodule update --init --recursive --quiet || true
    echo "  [✓] Skill submodules ready"
    echo ""
fi

# 3. Helper Functions for Linking
SKILLS_LINKED=0
AGENTS_LINKED=0
RULES_LINKED=0
SKIPPED_COUNT=0
WARNINGS_COUNT=0

safe_link_file() {
    local src="$1"
    local dest="$2"
    local label="$3"

    local dest_dir
    dest_dir="$(dirname "${dest}")"
    mkdir -p "${dest_dir}"

    if [ -L "${dest}" ]; then
        local current_target
        current_target="$(readlink "${dest}" || true)"
        if [ "${current_target}" = "${src}" ]; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            return 0
        else
            echo "  [WARN] Symlink conflict at ${dest} -> points to '${current_target}', expected '${src}' (Skipping)"
            WARNINGS_COUNT=$((WARNINGS_COUNT + 1))
            return 0
        fi
    elif [ -f "${dest}" ]; then
        if cmp -s "${src}" "${dest}"; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            return 0
        else
            echo "  [WARN] Existing file at ${dest} differs from source (Skipping to prevent overwrite)"
            WARNINGS_COUNT=$((WARNINGS_COUNT + 1))
            return 0
        fi
    fi

    # Attempt symlink; fall back to copy if symlink unsupported on OS
    if ln -s "${src}" "${dest}" 2>/dev/null; then
        echo "  [LINKED] ${label}: ${dest} -> ${src}"
    else
        cp -f "${src}" "${dest}"
        echo "  [COPIED] ${label}: ${dest} -> ${src}"
    fi
    return 0
}

safe_link_dir() {
    local src="$1"
    local dest="$2"
    local label="$3"

    local dest_dir
    dest_dir="$(dirname "${dest}")"
    mkdir -p "${dest_dir}"

    if [ -L "${dest}" ]; then
        local current_target
        current_target="$(readlink "${dest}" || true)"
        if [ "${current_target}" = "${src}" ]; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            return 0
        else
            echo "  [WARN] Symlink conflict at ${dest} -> points to '${current_target}', expected '${src}' (Skipping)"
            WARNINGS_COUNT=$((WARNINGS_COUNT + 1))
            return 0
        fi
    elif [ -d "${dest}" ]; then
        if [ -f "${src}/agent.md" ] && [ -f "${dest}/agent.md" ] && cmp -s "${src}/agent.md" "${dest}/agent.md"; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            return 0
        elif [ -f "${src}/SKILL.md" ] && [ -f "${dest}/SKILL.md" ] && cmp -s "${src}/SKILL.md" "${dest}/SKILL.md"; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            return 0
        else
            echo "  [WARN] Existing directory at ${dest} differs from source (Skipping to prevent overwrite)"
            WARNINGS_COUNT=$((WARNINGS_COUNT + 1))
            return 0
        fi
    fi

    if ln -s "${src}" "${dest}" 2>/dev/null; then
        echo "  [LINKED] ${label}: ${dest} -> ${src}"
    else
        cp -rf "${src}" "${dest}"
        echo "  [COPIED] ${label}: ${dest} -> ${src}"
    fi
    return 0
}

safe_append_pointer() {
    local target_file="$1"
    local tool_name="$2"

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
        echo "  [UPDATED] Appended HAWS Global Pointer to existing ${target_file}"
    else
        printf "%b" "${pointer_content}" > "${target_file}"
        echo "  [CREATED] Created HAWS Global Pointer at ${target_file}"
    fi
    RULES_LINKED=$((RULES_LINKED + 1))
}

# 4. Setup Global Pointers (So HAWS is active globally for all projects)
echo "--- Setting Up Global Environment Pointers ---"
if [ "$DETECTED_CLAUDE" = true ]; then
    safe_append_pointer "${HOME}/.claude/CLAUDE.md" "Claude Code"
fi

if [ "$DETECTED_GEMINI" = true ]; then
    safe_append_pointer "${HOME}/.gemini/GEMINI.md" "Google Antigravity"
fi
echo ""

# 5. Link Skills (Smart Recursive Discovery: Single Skills & Multi-Skill Packs)
echo "--- Linking Skills ---"
declare -A PROCESSED_SKILLS

find_and_link_skills() {
    local base_dir="$1"
    if [ ! -d "${base_dir}" ]; then
        return 0
    fi

    while IFS= read -r -d '' skill_file; do
        local skill_dir
        skill_dir="$(dirname "${skill_file}")"
        local rel_path="${skill_dir#"${base_dir}/"}"

        # If skill is directly in a subfolder (e.g. taste-skill)
        local skill_name
        if [[ "${rel_path}" != *"/"* ]]; then
            skill_name="${rel_path}"
        else
            # If skill is nested in a pack (e.g. superpowers/skills/brainstorming)
            # Flatten name: replace slashes with hyphens or pack-subskill
            skill_name="$(echo "${rel_path}" | tr '/' '-')"
            # If it has "skills-" in name, clean it up for elegance (e.g. superpowers-skills-brainstorming -> superpowers-brainstorming)
            skill_name="${skill_name/-skills-/-}"
        fi

        if [ -n "${skill_name}" ] && [ -z "${PROCESSED_SKILLS[${skill_name}]:-}" ]; then
            PROCESSED_SKILLS[${skill_name}]=1

            if [ "$DETECTED_CLAUDE" = true ]; then
                safe_link_dir "${skill_dir}" "${HOME}/.claude/skills/${skill_name}" "Claude Skill [${skill_name}]"
                SKILLS_LINKED=$((SKILLS_LINKED + 1))
            fi
            if [ "$DETECTED_GEMINI" = true ]; then
                safe_link_dir "${skill_dir}" "${HOME}/.gemini/config/skills/${skill_name}" "Antigravity Skill [${skill_name}]"
                SKILLS_LINKED=$((SKILLS_LINKED + 1))
            fi
        fi
    done < <(find "${base_dir}" -type f -name "SKILL.md" -print0 2>/dev/null || true)
}

find_and_link_skills "${SOURCE_DIR}/skills"

if [ ${#PROCESSED_SKILLS[@]} -eq 0 ]; then
    echo "  (No skills found in ${SOURCE_DIR}/skills)"
fi
echo ""

# 6. Link Subagents (Unified Authoring in agents/ with Cross-Tool Deployment)
echo "--- Linking Subagents ---"

# Check if unified agents/ directory exists
if [ -d "${SOURCE_DIR}/agents" ]; then
    for agent_file in "${SOURCE_DIR}/agents"/*.md; do
        if [ -f "${agent_file}" ]; then
            agent_name="$(basename "${agent_file}" .md)"
            
            # Claude Code: links directly as ~/.claude/agents/<name>.md
            if [ "$DETECTED_CLAUDE" = true ]; then
                safe_link_file "${agent_file}" "${HOME}/.claude/agents/${agent_name}.md" "Claude Agent [${agent_name}]"
                AGENTS_LINKED=$((AGENTS_LINKED + 1))
            fi

            # Antigravity: requires folder ~/.gemini/config/agents/<name>/agent.md
            if [ "$DETECTED_GEMINI" = true ]; then
                gemini_agent_dir="${HOME}/.gemini/config/agents/${agent_name}"
                mkdir -p "${gemini_agent_dir}"
                safe_link_file "${agent_file}" "${gemini_agent_dir}/agent.md" "Antigravity Agent [${agent_name}]"
                AGENTS_LINKED=$((AGENTS_LINKED + 1))
            fi
        fi
    done
fi

# Fallback / Compatibility: Only check legacy folders if unified agents/ does NOT exist
if [ ! -d "${SOURCE_DIR}/agents" ]; then
    if [ "$DETECTED_CLAUDE" = true ] && [ -d "${SOURCE_DIR}/agents-claude-code" ]; then
        for agent_file in "${SOURCE_DIR}/agents-claude-code"/*.md; do
            if [ -f "${agent_file}" ]; then
                agent_name="$(basename "${agent_file}")"
                safe_link_file "${agent_file}" "${HOME}/.claude/agents/${agent_name}" "Claude Legacy Agent [${agent_name}]"
            fi
        done
    fi

    if [ "$DETECTED_GEMINI" = true ] && [ -d "${SOURCE_DIR}/agents-antigravity" ]; then
        for agent_dir in "${SOURCE_DIR}/agents-antigravity"/*; do
            if [ -d "${agent_dir}" ] && [ -f "${agent_dir}/agent.md" ]; then
                agent_name="$(basename "${agent_dir}")"
                safe_link_dir "${agent_dir}" "${HOME}/.gemini/config/agents/${agent_name}" "Antigravity Legacy Agent [${agent_name}]"
            fi
        done
    fi
fi
echo ""

# 7. Summary Report
echo "=== Installation Summary ==="
echo "Tools Setup   : Claude Code ($DETECTED_CLAUDE), Google Antigravity ($DETECTED_GEMINI)"
echo "Global Rules  : ${RULES_LINKED}"
echo "Skills Linked : ${SKILLS_LINKED}"
echo "Agents Linked : ${AGENTS_LINKED}"
echo "Skipped Items : ${SKIPPED_COUNT}"
echo "Warnings      : ${WARNINGS_COUNT}"
echo ""
echo "HAWS setup completed successfully!"