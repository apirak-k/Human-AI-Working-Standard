#!/usr/bin/env bash
set -euo pipefail

gemini_dir="${HOME}/.gemini/config/skills"
claude_dir="${HOME}/.claude/skills"
manifest="${HOME}/.haws_manifest"

gemini_count=0
claude_count=0
manifest_count=0

[ -d "${gemini_dir}" ] && gemini_count=$(find "${gemini_dir}" -mindepth 1 -maxdepth 1 -type d | wc -l)
[ -d "${claude_dir}" ] && claude_count=$(find "${claude_dir}" -mindepth 1 -maxdepth 1 -type d | wc -l)
[ -f "${manifest}" ] && manifest_count=$(grep -c '^skill:' "${manifest}" || true)

echo "=== HAWS Fast Skill Status ==="
echo "Antigravity Active Skills : ${gemini_count}"
echo "Claude Code Active Skills : ${claude_count}"
echo "Manifest Registered Skills: ${manifest_count}"

if [ "${gemini_count}" -eq "${claude_count}" ] && [ "${gemini_count}" -eq "${manifest_count}" ]; then
    echo "Health Status             : [100% HEALTHY & IN SYNC]"
else
    echo "Health Status             : [MISMATCH DETECTED - Run update.sh]"
fi
