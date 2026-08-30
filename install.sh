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

# 3. Helper Functions for Symlinking / Linking
SKILLS_LINKED=0
AGENTS_LINKED=0
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
        # Check if identical agent.md exists inside
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

# 4. Link Skills
echo "--- Linking Skills ---"
SKILLS_SRC_DIR="${SOURCE_DIR}/skills"
SKILL_FOLDERS=()

if [ -d "${SKILLS_SRC_DIR}" ]; then
    while IFS= read -r -d '' folder; do
        if [ -d "${folder}" ] && [ "$(basename "${folder}")" != "skills" ]; then
            if [ -f "${folder}/SKILL.md" ]; then
                SKILL_FOLDERS+=("${folder}")
            fi
        fi
    done < <(find "${SKILLS_SRC_DIR}" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null || true)
fi

if [ ${#SKILL_FOLDERS[@]} -eq 0 ]; then
    echo "  (No skills to link yet in ${SKILLS_SRC_DIR})"
else
    for skill_path in "${SKILL_FOLDERS[@]}"; do
        skill_name="$(basename "${skill_path}")"
        if [ "$DETECTED_CLAUDE" = true ]; then
            safe_link_dir "${skill_path}" "${HOME}/.claude/skills/${skill_name}" "Claude Skill [${skill_name}]"
            SKILLS_LINKED=$((SKILLS_LINKED + 1))
        fi
        if [ "$DETECTED_GEMINI" = true ]; then
            safe_link_dir "${skill_path}" "${HOME}/.gemini/config/skills/${skill_name}" "Antigravity Skill [${skill_name}]"
            SKILLS_LINKED=$((SKILLS_LINKED + 1))
        fi
    done
fi
echo ""

# 5. Link Subagents
echo "--- Linking Subagents ---"
# Claude Code Subagents
if [ "$DETECTED_CLAUDE" = true ]; then
    CLAUDE_AGENTS_DIR="${SOURCE_DIR}/agents-claude-code"
    if [ -d "${CLAUDE_AGENTS_DIR}" ]; then
        for agent_file in "${CLAUDE_AGENTS_DIR}"/*.md; do
            if [ -f "${agent_file}" ]; then
                agent_name="$(basename "${agent_file}")"
                safe_link_file "${agent_file}" "${HOME}/.claude/agents/${agent_name}" "Claude Agent [${agent_name}]"
                AGENTS_LINKED=$((AGENTS_LINKED + 1))
            fi
        done
    fi
fi

# Antigravity Subagents
if [ "$DETECTED_GEMINI" = true ]; then
    GEMINI_AGENTS_DIR="${SOURCE_DIR}/agents-antigravity"
    if [ -d "${GEMINI_AGENTS_DIR}" ]; then
        for agent_dir in "${GEMINI_AGENTS_DIR}"/*; do
            if [ -d "${agent_dir}" ] && [ -f "${agent_dir}/agent.md" ]; then
                agent_name="$(basename "${agent_dir}")"
                safe_link_dir "${agent_dir}" "${HOME}/.gemini/config/agents/${agent_name}" "Antigravity Agent [${agent_name}]"
                AGENTS_LINKED=$((AGENTS_LINKED + 1))
            fi
        done
    fi
fi
echo ""

# 6. Summary Report
echo "=== Installation Summary ==="
echo "Tools Setup : Claude Code ($DETECTED_CLAUDE), Google Antigravity ($DETECTED_GEMINI)"
echo "Skills Linked: ${SKILLS_LINKED}"
echo "Agents Linked: ${AGENTS_LINKED}"
echo "Skipped (Already Installed): ${SKIPPED_COUNT}"
echo "Warnings/Conflicts: ${WARNINGS_COUNT}"
echo ""
echo "HAWS setup completed successfully!"