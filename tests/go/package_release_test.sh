#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
TMP="$(mktemp -d)"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for tool in zip unzip tar; do
	command -v "$tool" >/dev/null 2>&1 || fail "required test utility not found: $tool"
done

FAKE_BIN="$TMP/fake-bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/go" <<'EOF'
#!/bin/sh
out=
while [ "$#" -gt 0 ]; do
	if [ "$1" = -o ]; then
		out="$2"
		shift 2
	else
		shift
	fi
done
[ -n "$out" ] || { echo 'fake go: missing -o output' >&2; exit 2; }
echo "$GOOS/$GOARCH" >> "$HAWS_TEST_BUILDS"
if [ "${HAWS_TEST_FAIL_TARGET:-}" = "$GOOS/$GOARCH" ]; then
	exit 19
fi
mkdir -p "$(dirname "$out")"
cat > "$out" <<SCRIPT
#!/bin/sh
echo fixture $GOOS/$GOARCH
SCRIPT
chmod +x "$out"
EOF
chmod +x "$FAKE_BIN/go"

OUTPUT="$TMP/release"
BUILD_LOG="$TMP/build-targets"
PATH="$FAKE_BIN:$PATH" HAWS_TEST_BUILDS="$BUILD_LOG" bash "$ROOT/scripts/package-release.sh" v9.8.7 "$OUTPUT" || fail 'packager failed with fixture binaries'

expected_targets=$(cat <<'EOF'
windows/amd64
windows/arm64
darwin/amd64
darwin/arm64
linux/amd64
linux/arm64
EOF
)
actual_targets="$(cat "$BUILD_LOG")"
[[ "$actual_targets" == "$expected_targets" ]] || fail "built targets differ: $actual_targets"

[[ -x "$OUTPUT/macos/haws.command" ]] || fail 'macOS launcher is missing or not executable'
[[ -x "$OUTPUT/linux/haws.sh" ]] || fail 'Linux launcher is missing or not executable'
[[ -f "$OUTPUT/windows/haws.bat" ]] || fail 'Windows launcher is missing'
for target in windows/amd64 windows/arm64 macos/amd64 macos/arm64 linux/amd64 linux/arm64; do
	os="${target%%/*}"
	arch="${target#*/}"
	case "$target" in windows/*) ext=.exe ;; *) ext= ;; esac
	[[ -f "$OUTPUT/$os/bin/$os-$arch/haws$ext" ]] || fail "binary missing for $target"
done
for os in windows macos linux; do
	[[ -f "$OUTPUT/$os/README.txt" ]] || fail "$os package README is missing"
	[[ -f "$OUTPUT/$os/package-manifest.json" ]] || fail "$os package ownership manifest is missing"
	manifest="$OUTPUT/$os/package-manifest.json"
	case "$os" in
		windows) launcher=haws.bat; extension=.exe ;;
		macos) launcher=haws.command; extension= ;;
		linux) launcher=haws.sh; extension= ;;
	esac
	for relative in "README.txt" "$launcher" "bin/$os-amd64/haws$extension" "bin/$os-arm64/haws$extension"; do
		want="$(awk -F '"' -v key="$relative" '$2 == key { print $4 }' "$manifest")"
		[[ -n "$want" ]] || fail "$os package manifest is missing $relative"
		if command -v sha256sum >/dev/null 2>&1; then
			got="$(sha256sum "$OUTPUT/$os/$relative" | awk '{print $1}')"
		else
			got="$(shasum -a 256 "$OUTPUT/$os/$relative" | awk '{print $1}')"
		fi
		[[ "$want" == "$got" ]] || fail "$os package manifest fingerprint differs for $relative"
	done
done

unzip -Z1 "$OUTPUT/haws-windows.zip" | rg -q '^haws-go/windows/haws[.]bat$' || fail 'Windows archive is missing its launcher'
windows_entries="$(unzip -Z1 "$OUTPUT/haws-windows.zip")"
[[ "$windows_entries" == *haws-go/windows/bin/windows-arm64/haws.exe* ]] || { echo "$windows_entries" >&2; fail 'Windows archive is missing ARM64 binary'; }
unzip -Z1 "$OUTPUT/haws-windows.zip" | rg -q '^haws-go/windows/README[.]txt$' || fail 'Windows archive is missing installation instructions'
unzip -Z1 "$OUTPUT/haws-windows.zip" | rg -q '^haws-go/windows/package-manifest[.]json$' || fail 'Windows archive is missing its ownership manifest'
if unzip -Z1 "$OUTPUT/haws-windows.zip" | rg -q '^README[.]txt$'; then fail 'Windows archive may overwrite a checkout-root README'; fi
tar -tzf "$OUTPUT/haws-macos.tar.gz" | rg -q '^haws-go/macos/haws[.]command$' || fail 'macOS archive is missing its launcher'
tar -tzf "$OUTPUT/haws-macos.tar.gz" | rg -q '^haws-go/macos/package-manifest[.]json$' || fail 'macOS archive is missing its ownership manifest'
tar -tzf "$OUTPUT/haws-macos.tar.gz" | rg -q '^haws-go/macos/bin/macos-amd64/haws$' || fail 'macOS archive is missing AMD64 binary'
tar -tzf "$OUTPUT/haws-linux.tar.gz" | rg -q '^haws-go/linux/bin/linux-arm64/haws$' || fail 'Linux archive is missing ARM64 binary'
tar -tzf "$OUTPUT/haws-linux.tar.gz" | rg -q '^haws-go/linux/package-manifest[.]json$' || fail 'Linux archive is missing its ownership manifest'

for archive in haws-windows.zip haws-macos.tar.gz haws-linux.tar.gz; do
	[[ -f "$OUTPUT/$archive.sha256" ]] || fail "checksum manifest missing for $archive"
	want="$(awk '{print $1}' "$OUTPUT/$archive.sha256")"
	if command -v sha256sum >/dev/null 2>&1; then
		got="$(sha256sum "$OUTPUT/$archive" | awk '{print $1}')"
	else
		got="$(shasum -a 256 "$OUTPUT/$archive" | awk '{print $1}')"
	fi
	[[ "$want" == "$got" ]] || fail "checksum mismatch for $archive"
done

PROTECTED="$TMP/existing"
mkdir -p "$PROTECTED"
echo keep > "$PROTECTED/marker"
set +e
PATH="$FAKE_BIN:$PATH" HAWS_TEST_BUILDS="$TMP/should-not-build" bash "$ROOT/scripts/package-release.sh" v1.0.0 "$PROTECTED" >"$TMP/existing.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail 'packager overwrote an existing output directory'
[[ "$(cat "$PROTECTED/marker")" == keep ]] || fail 'existing output content changed'

FAILED_OUTPUT="$TMP/failed"
set +e
PATH="$FAKE_BIN:$PATH" HAWS_TEST_BUILDS="$TMP/failed-targets" HAWS_TEST_FAIL_TARGET=linux/arm64 bash "$ROOT/scripts/package-release.sh" v1.0.1 "$FAILED_OUTPUT" >"$TMP/failed.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail 'packager did not report a failed cross-build'
[[ ! -e "$FAILED_OUTPUT" ]] || fail 'failed package build left a published output directory'

echo 'PASS: release packaging builds six targets, emits three archives and SHA-256 manifests, and preserves existing output on failure.'
