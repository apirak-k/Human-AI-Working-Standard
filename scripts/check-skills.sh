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

est_tokens=0
if command -v python3 &>/dev/null || command -v py &>/dev/null; then
    py_cmd="python3"
    command -v py &>/dev/null && py_cmd="py -3.11"
    est_tokens=$($py_cmd -c "
import glob, os, re
gemini_dir = os.path.expanduser('~/.gemini/config/skills')
files = glob.glob(os.path.join(gemini_dir, '*', 'SKILL.md')) + glob.glob(os.path.join(gemini_dir, '*', 'skill.md'))
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
print(round(chars / 3.8))
" 2>/dev/null || echo 0)
fi

token_limit=20000
token_pct=0
[ "${est_tokens}" -gt 0 ] && token_pct=$(( (est_tokens * 100) / token_limit ))

echo "=== HAWS Fast Skill & Token Status ==="
echo "Antigravity Active Skills : ${gemini_count}"
echo "Claude Code Active Skills : ${claude_count}"
echo "Manifest Registered Skills: ${manifest_count}"

if [ "${est_tokens}" -ge 18000 ]; then
    echo "Token Budget Status       : [CRITICAL DANGER: ~${est_tokens} / ${token_limit} (${token_pct}%)]"
    echo "  (!) IMMEDIATE ACTION REQUIRED: Customization budget near overflow."
elif [ "${est_tokens}" -ge 15000 ]; then
    echo "Token Budget Status       : [WARNING DANGEROUS: ~${est_tokens} / ${token_limit} (${token_pct}%)]"
    echo "  (!) ALERT: Skill descriptions exceed 75% budget. Review largest skills."
else
    echo "Token Budget Status       : [SAFE: ~${est_tokens} / ${token_limit} (${token_pct}%)]"
fi

if [ "${gemini_count}" -eq "${claude_count}" ] && [ "${gemini_count}" -eq "${manifest_count}" ]; then
    echo "Sync Health Status        : [100% HEALTHY & IN SYNC]"
else
    echo "Sync Health Status        : [MISMATCH DETECTED - Run update.sh]"
fi
