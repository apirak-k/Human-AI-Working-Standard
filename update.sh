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
elif [ -f "${SCRIPT_DIR}/../core/HAWS.md" ]; then
    SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
    SOURCE_DIR="${CANONICAL_DIR}"
fi

if [ -d "${SOURCE_DIR}/.git" ]; then
    echo "Pulling latest changes in ${SOURCE_DIR}..."
    git -C "${SOURCE_DIR}" pull --quiet
    echo "  [✓] Updated to latest git commit"

    if [ -f "${SOURCE_DIR}/.gitmodules" ]; then
        echo "Updating embedded git submodules (skills packs)..."
        git -C "${SOURCE_DIR}" submodule update --init --recursive --remote --quiet || true
        echo "  [✓] Updated all embedded submodules"
    fi
else
    echo "  [!] ${SOURCE_DIR} is not a git repository. Skipping git pull."
fi
echo ""

MANIFEST_FILE="${HOME}/.haws_manifest"
PREV_MANIFEST="${HOME}/.haws_manifest.prev"
rm -f "${PREV_MANIFEST}"
[ -f "${MANIFEST_FILE}" ] && cp -f "${MANIFEST_FILE}" "${PREV_MANIFEST}"

# Run install.sh to ensure any newly added skills/agents are linked
echo "Re-syncing symlinks for all detected AI environments..."
if [ -f "${SOURCE_DIR}/scripts/install.sh" ]; then
    bash "${SOURCE_DIR}/scripts/install.sh" "$@"
else
    bash "${SOURCE_DIR}/install.sh" "$@"
fi
echo ""

# Check and auto-prune dangling and removed items
echo "--- Auto-Pruning Orphaned & Dangling Links ---"
PRUNED_COUNT=0

DETECTED_CLAUDE=false
DETECTED_GEMINI=false
[ -d "${HOME}/.claude" ] && DETECTED_CLAUDE=true
[ -d "${HOME}/.gemini" ] && DETECTED_GEMINI=true

# 1. Prune items removed from HAWS manifest
if [ -f "${PREV_MANIFEST}" ] && [ -f "${MANIFEST_FILE}" ]; then
    while IFS= read -r entry || [ -n "$entry" ]; do
        [ -z "$entry" ] && continue
        if ! grep -q -F "${entry}" "${MANIFEST_FILE}" 2>/dev/null; then
            type="${entry%%:*}"
            name="${entry#*:}"
            if [ "$type" = "skill" ]; then
                if [ "$DETECTED_CLAUDE" = true ] && [ -e "${HOME}/.claude/skills/${name}" ]; then
                    rm -rf "${HOME}/.claude/skills/${name}"
                    echo "  [PRUNED] Claude Skill [${name}]"
                    PRUNED_COUNT=$((PRUNED_COUNT + 1))
                fi
                if [ "$DETECTED_GEMINI" = true ] && [ -e "${HOME}/.gemini/config/skills/${name}" ]; then
                    rm -rf "${HOME}/.gemini/config/skills/${name}"
                    echo "  [PRUNED] Antigravity Skill [${name}]"
                    PRUNED_COUNT=$((PRUNED_COUNT + 1))
                fi
            elif [ "$type" = "agent" ]; then
                if [ "$DETECTED_CLAUDE" = true ] && [ -e "${HOME}/.claude/agents/${name}.md" ]; then
                    rm -rf "${HOME}/.claude/agents/${name}.md"
                    echo "  [PRUNED] Claude Agent [${name}]"
                    PRUNED_COUNT=$((PRUNED_COUNT + 1))
                fi
                if [ "$DETECTED_GEMINI" = true ] && [ -e "${HOME}/.gemini/config/agents/${name}" ]; then
                    rm -rf "${HOME}/.gemini/config/agents/${name}"
                    echo "  [PRUNED] Antigravity Agent [${name}]"
                    PRUNED_COUNT=$((PRUNED_COUNT + 1))
                fi
            fi
        fi
    done < "${PREV_MANIFEST}"
    rm -f "${PREV_MANIFEST}"
fi

# 2. Prune dangling symlinks
prune_dangling() {
    local target_dir="$1"
    local label="$2"

    if [ -d "${target_dir}" ]; then
        for link in "${target_dir}"/*; do
            if [ -L "${link}" ]; then
                if [ ! -e "${link}" ]; then
                    local target
                    target="$(readlink "${link}" || true)"
                    rm -rf "${link}"
                    echo "  [PRUNED] ${label}: Removed orphaned link ${link} -> ${target}"
                    PRUNED_COUNT=$((PRUNED_COUNT + 1))
                fi
            fi
        done
    fi
}

[ "$DETECTED_CLAUDE" = true ] && prune_dangling "${HOME}/.claude/skills" "Claude Skill"
[ "$DETECTED_CLAUDE" = true ] && prune_dangling "${HOME}/.claude/agents" "Claude Agent"
[ "$DETECTED_GEMINI" = true ] && prune_dangling "${HOME}/.gemini/config/skills" "Antigravity Skill"
[ "$DETECTED_GEMINI" = true ] && prune_dangling "${HOME}/.gemini/config/agents" "Antigravity Agent"

if [ ${PRUNED_COUNT} -eq 0 ]; then
    echo "  [✓] All links clean and healthy (0 orphaned links found)."
else
    echo "  [✓] Successfully pruned and removed ${PRUNED_COUNT} orphaned item(s)."
fi

echo ""
echo "HAWS update completed!"