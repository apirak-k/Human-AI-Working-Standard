#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/haws-secondbrain-merge.XXXXXX")"
cleanup() {
    case "$(basename "${tmp}")" in
        haws-secondbrain-merge.*) rm -rf -- "${tmp}" ;;
        *) echo "Refusing to remove unexpected test path: ${tmp}" >&2; return 1 ;;
    esac
}
trap cleanup EXIT

git init --bare "${tmp}/remote.git" >/dev/null
git init -b main "${tmp}/remote-seed" >/dev/null
git -C "${tmp}/remote-seed" config user.name Test
git -C "${tmp}/remote-seed" config user.email test@example.invalid
cat > "${tmp}/remote-seed/USER_PREFERENCES.md" <<'EOF'
# User Preferences

## 1. Interaction & Communication Style
- **Remote-only**: Preserve this preference.
EOF
: > "${tmp}/remote-seed/ANTI_PATTERNS.md"
: > "${tmp}/remote-seed/WORKFLOW.md"
git -C "${tmp}/remote-seed" add USER_PREFERENCES.md
git -C "${tmp}/remote-seed" add ANTI_PATTERNS.md WORKFLOW.md
git -C "${tmp}/remote-seed" commit -m remote --quiet
git -C "${tmp}/remote-seed" remote add origin "${tmp}/remote.git"
git -C "${tmp}/remote-seed" push origin main --quiet

git init -b main "${tmp}/local" >/dev/null
git -C "${tmp}/local" config user.name Test
git -C "${tmp}/local" config user.email test@example.invalid
cat > "${tmp}/local/USER_PREFERENCES.md" <<'EOF'
# User Preferences

## 1. Interaction & Communication Style
- **Local-only**: Preserve this preference.
EOF
: > "${tmp}/local/ANTI_PATTERNS.md"
: > "${tmp}/local/WORKFLOW.md"
git -C "${tmp}/local" add USER_PREFERENCES.md
git -C "${tmp}/local" add ANTI_PATTERNS.md WORKFLOW.md
git -C "${tmp}/local" commit -m local --quiet
git -C "${tmp}/local" remote add origin "${tmp}/remote.git"
git -C "${tmp}/local" fetch origin main --quiet
git -C "${tmp}/local" show origin/main:USER_PREFERENCES.md >/dev/null

HAWS_SOURCE_ONLY=1
source "${root}/haws.sh"
symmetrical_merge_secondbrain "${tmp}/local"

for preference in '- **Local-only**: Preserve this preference.' '- **Remote-only**: Preserve this preference.'; do
    if ! grep -qF -- "${preference}" "${tmp}/local/USER_PREFERENCES.md"; then
        echo "Missing merged preference: ${preference}" >&2
        cat "${tmp}/local/USER_PREFERENCES.md" >&2
        exit 1
    fi
done
