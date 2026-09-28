#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/haws-settings-apply.XXXXXX")"
cleanup() {
    case "$(basename "${tmp}")" in
        haws-settings-apply.*) rm -rf -- "${tmp}" ;;
        *) echo "Refusing to remove unexpected test path: ${tmp}" >&2; return 1 ;;
    esac
}
trap cleanup EXIT

mkdir -p "${tmp}/project/skills/custom/demo-one"
cat > "${tmp}/project/skills/custom/demo-one/SKILL.md" <<'EOF'
---
name: demo-one
description: Fixture skill for Settings Apply verification.
---
# Demo One
EOF

HAWS_SOURCE_ONLY=1
HAWS_REPO_DIR="${tmp}/project"
HAWS_STATE_DIR="${tmp}/state"
HAWS_TEST_NO_INTEGRATION=1
export HAWS_REPO_DIR HAWS_STATE_DIR HAWS_TEST_NO_INTEGRATION
source "${root}/haws.sh"

skill_id="$(catalog_skills | awk -F '\t' '$3 == "demo-one" {print $2; exit}')"
[ -n "${skill_id}" ] || { echo "Fixture skill was not catalogued." >&2; exit 1; }

HAWS_DRAFT_SKILLS=""
HAWS_DRAFT_SKILLS_LOADED=1
HAWS_PERSIST_SKILLS="${skill_id}"
export HAWS_DRAFT_SKILLS HAWS_DRAFT_SKILLS_LOADED HAWS_PERSIST_SKILLS

settings_plan_build
[ ! -e "${HAWS_STATE_DIR}/skills.disabled" ] || {
    echo "Building a settings plan must not persist the draft." >&2
    exit 1
}
settings_apply_final

grep -qF -- "${skill_id}" "${HAWS_STATE_DIR}/skills.disabled"
catalog_skills | awk -F '\t' -v id="${skill_id}" '$2 == id && $6 == 0 {found=1} END {exit !found}'
[ -s "${HAWS_STATE_DIR}/install.complete" ]
echo "Settings Apply regression passed."
