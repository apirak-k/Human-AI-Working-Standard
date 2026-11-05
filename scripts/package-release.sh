#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fail() { echo "[ERROR] $*" >&2; exit 1; }

if [[ $# -ne 2 ]]; then
	echo "Usage: $0 <version> <new-output-directory>" >&2
	exit 2
fi
version="$1"
output="$2"
case "$version" in ''|*[!A-Za-z0-9._+-]*) fail "invalid version string: $version" ;; esac
[[ -n "$output" ]] || fail 'output directory is required'

for tool in go git tar zip; do command -v "$tool" >/dev/null 2>&1 || fail "required packaging tool not found: $tool"; done
for launcher in launchers/windows/haws.bat launchers/macos/haws.command launchers/linux/haws.sh; do
	[[ -f "$ROOT/$launcher" ]] || fail "launcher source is missing: $launcher"
done

output_parent="$(dirname -- "$output")"
output_name="$(basename -- "$output")"
mkdir -p "$output_parent"
output_parent="$(cd "$output_parent" && pwd -P)"
output="$output_parent/$output_name"
if [[ -e "$output" || -L "$output" ]]; then fail "output directory already exists; choose a new path: $output"; fi

stage="$(mktemp -d "$output_parent/.${output_name}.tmp.XXXXXXXX")"
cleanup() {
	status=$?
	if [[ -n "${stage:-}" && -d "$stage" ]]; then rm -rf "$stage"; fi
	exit "$status"
}
trap cleanup EXIT

mkdir -p \
	"$stage/windows/bin/windows-amd64" \
	"$stage/windows/bin/windows-arm64" \
	"$stage/macos/bin/macos-amd64" \
	"$stage/macos/bin/macos-arm64" \
	"$stage/linux/bin/linux-amd64" \
	"$stage/linux/bin/linux-arm64"
cp "$ROOT/launchers/windows/haws.bat" "$stage/windows/haws.bat"
cp "$ROOT/launchers/macos/haws.command" "$stage/macos/haws.command"
cp "$ROOT/launchers/linux/haws.sh" "$stage/linux/haws.sh"
chmod 755 "$stage/macos/haws.command" "$stage/linux/haws.sh"
# Runtime files are intentionally listed individually: never copy a checkout wholesale.
runtime_files=(
 haws.sh haws.bat .gitmodules
 core/HAWS.md core/WORK_INSTRUCTIONS.md
 docs/technical-practices.md
 agents/backend-engineer.md agents/frontend-engineer.md agents/organizer.md agents/researcher.md agents/tester.md
 templates/AGENTS.md templates/ARCHITECTURE.md templates/CONSTRAINTS.md templates/DESIGN.md templates/HANDOFF.md templates/PROJECT.md
 ai-configs/claude/CLAUDE.md.template ai-configs/codex/AGENTS.override.md.template ai-configs/codex/agents.mjs
 ai-configs/gemini/GEMINI.md.template ai-configs/gemini/skills-json.mjs
 secondbrain/ANTI_PATTERNS.md secondbrain/USER_PREFERENCES.md secondbrain/WORKFLOW.md
 skills/skills.disabled skills/custom/README.md skills/custom/keyboard-layout-fixer/SKILL.md
 skills/custom/keyboard-layout-fixer/scripts/layout_fixer.mjs
)
# Gitlinks are pinned by the release commit; no submodule checkout is needed.
git -C "$ROOT" ls-tree -r HEAD | awk '$1 == "160000" && $2 == "commit" { print $4 "\t" $3 }' > "$stage/source-revisions.tsv"
[[ -s "$stage/source-revisions.tsv" ]] || fail 'release commit has no pinned source revisions'
for os in windows macos linux; do
 mkdir -p "$stage/$os/runtime"
 cp "$stage/source-revisions.tsv" "$stage/$os/runtime/source-revisions.tsv"
 for file in "${runtime_files[@]}"; do
  [[ -f "$ROOT/$file" && ! -L "$ROOT/$file" ]] || fail "runtime source missing or symlinked: $file"
  mkdir -p "$stage/$os/runtime/$(dirname "$file")"
  cp "$ROOT/$file" "$stage/$os/runtime/$file"
 done
done
mkdir -p "$stage/archive-root/haws-go"

package_sha256() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
	else fail 'SHA-256 tool not found (need sha256sum or shasum)'
	fi
}

write_package_metadata() {
	local os="$1" launcher="$2" readme dir extension=""
	dir="$stage/$os"
	readme="$dir/README.txt"
	if [[ "$os" == windows ]]; then extension=.exe; fi
	cat > "$readme" <<EOF
HAWS Go compatibility package for $os

Extract this package anywhere and run the included launcher with setup for the
first-time setup (for example, ./haws.command setup). The runtime/
directory contains HAWS resources and neutral Second Brain seeds. Persistent
personal state and Second Brain documents are created in the sibling data/
directory; retain data/ when removing or replacing a package. The manifest
records shipped files and never includes personal data.

To keep using an existing HAWS installation, open a terminal in this folder
and run: $launcher migrate --from "/path/to/old/HAWS/checkout". The Home menu
also includes Migrate existing installation. HAWS shows the paths first and
asks for confirmation. Migration reuses the old settings, sources, skill
selections, ownership records, integrations, and Second Brain in place; it
does not copy, move, or remove those files. Use 'migrate --clear --yes' to
remove only the saved reference. Keep the old checkout while using migrated
sources.
EOF
 {
  printf '{\n  "schema_version": 1,\n  "version": "%s",\n  "platform": "%s",\n  "files": {\n' "$version" "$os"
  local relative first=1
  for relative in README.txt "$launcher" "bin/$os-amd64/haws$extension" "bin/$os-arm64/haws$extension" "${runtime_files[@]/#/runtime/}" runtime/source-revisions.tsv; do
   if [[ $first -eq 0 ]]; then printf ',\n'; fi
   printf '    "%s": "%s"' "$relative" "$(package_sha256 "$dir/$relative")"
   first=0
  done
  printf '\n  }\n}\n'
 } > "$dir/package-manifest.json"
}

build_target() {
	local os="$1" goos="$1" arch="$2" extension=""
	local binary="$stage/$os/bin/$os-$arch/haws"
	if [[ "$os" == macos ]]; then goos=darwin; fi
	if [[ "$os" == windows ]]; then extension=.exe; binary="${binary}${extension}"; fi
	echo "[BUILD] $goos/$arch"
	GOOS="$goos" GOARCH="$arch" go build -trimpath -buildvcs=false -ldflags "-s -w -X main.version=$version" -o "$binary" ./cmd/haws
	chmod 755 "$binary"
}
build_target windows amd64
build_target windows arm64
build_target macos amd64
build_target macos arm64
build_target linux amd64
build_target linux arm64

write_package_metadata windows haws.bat
write_package_metadata macos haws.command
write_package_metadata linux haws.sh

cp -R "$stage/windows" "$stage/archive-root/haws-go/windows"
cp -R "$stage/macos" "$stage/archive-root/haws-go/macos"
cp -R "$stage/linux" "$stage/archive-root/haws-go/linux"
(cd "$stage/archive-root" && zip -q -r -X "$stage/haws-windows.zip" haws-go/windows)
COPYFILE_DISABLE=1 tar -czf "$stage/haws-macos.tar.gz" -C "$stage/archive-root" haws-go/macos
COPYFILE_DISABLE=1 tar -czf "$stage/haws-linux.tar.gz" -C "$stage/archive-root" haws-go/linux

write_checksum() {
	local archive="$1"
	(
		cd "$stage"
		if command -v sha256sum >/dev/null 2>&1; then sha256sum "$archive"
		elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$archive"
		else fail 'SHA-256 tool not found (need sha256sum or shasum)'
		fi
	) > "$stage/$archive.sha256"
}
write_checksum haws-windows.zip
write_checksum haws-macos.tar.gz
write_checksum haws-linux.tar.gz

if [[ -e "$output" || -L "$output" ]]; then fail "output directory appeared during build; refusing to overwrite it: $output"; fi
mv "$stage" "$output"
stage=""
echo "[OK] Packages written to $output"
