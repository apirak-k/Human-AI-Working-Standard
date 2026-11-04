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

for tool in go tar zip; do command -v "$tool" >/dev/null 2>&1 || fail "required packaging tool not found: $tool"; done
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

Extract this package into the root of your existing HAWS checkout. Its files
stay under haws-go/$os, leaving root haws.sh and haws.bat in place.

Start the included launcher from haws-go/$os. This compatibility release
delegates Settings, Doctor, and Uninstall to the existing checkout. Sync also
checks for a verified Go app release before running the existing HAWS Sync.
EOF
	cat > "$dir/package-manifest.json" <<EOF
{
  "schema_version": 1,
  "version": "$version",
  "platform": "$os",
  "files": {
    "README.txt": "$(package_sha256 "$readme")",
    "$launcher": "$(package_sha256 "$dir/$launcher")",
    "bin/$os-amd64/haws$extension": "$(package_sha256 "$dir/bin/$os-amd64/haws$extension")",
    "bin/$os-arm64/haws$extension": "$(package_sha256 "$dir/bin/$os-arm64/haws$extension")"
  }
}
EOF
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
tar -czf "$stage/haws-macos.tar.gz" -C "$stage/archive-root" haws-go/macos
tar -czf "$stage/haws-linux.tar.gz" -C "$stage/archive-root" haws-go/linux

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
