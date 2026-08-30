#!/usr/bin/env bash
# ==============================================================================
# HAWS (Human-AI Working Standard) Cross-Tool Updater (Symlink-Based)
# ==============================================================================
set -euo pipefail

CANONICAL_DIR="${HOME}/haws"

echo "=== HAWS Cross-Tool Updater ==="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/core/HAWS.md" ]; then
    SOURCE_DIR="${SCRIPT_DIR}"
else
    SOURCE_DIR="${CANONICAL_DIR}"
fi

if [ -d "${SOURCE_DIR}/.git" ]; then
    echo "Pulling latest changes in ${SOURCE_DIR}..."
    git -C "${SOURCE_DIR}" pull --quiet
    echo "  [✓] Updated to latest git commit"
else
    echo "  [!] ${SOURCE_DIR} is not a git repository. Skipping git pull."
fi
echo ""

# Run install.sh to ensure any newly added skills/agents are linked
echo "Re-syncing symlinks for all detected AI environments..."
bash "${SOURCE_DIR}/install.sh"
echo ""

# Check for dangling symlinks
echo "--- Checking for Dangling Symlinks ---"
DANGLING_FOUND=0

check_dangling() {
    local target_dir="$1"
    local label="$2"

    if [ -d "${target_dir}" ]; then
        for link in "${target_dir}"/*; do
            if [ -L "${link}" ]; then
                if [ ! -e "${link}" ]; then
                    local target
                    target="$(readlink "${link}" || true)"
                    echo "  [DANGLING] ${label}: ${link} -> ${target} (Target missing)"
                    DANGLING_FOUND=$((DANGLING_FOUND + 1))
                fi
            fi
        done
    fi
}

check_dangling "${HOME}/.claude/skills" "Claude Skill"
check_dangling "${HOME}/.claude/agents" "Claude Agent"
check_dangling "${HOME}/.gemini/config/skills" "Antigravity Skill"
check_dangling "${HOME}/.gemini/config/agents" "Antigravity Agent"

if [ ${DANGLING_FOUND} -eq 0 ]; then
    echo "  [✓] No dangling symlinks found."
else
    echo ""
    echo "Note: ${DANGLING_FOUND} dangling symlink(s) detected above."
    echo "If these skills/agents were intentionally removed from HAWS, you may safely delete those symlinks manually."
fi

echo ""
echo "HAWS update completed!"