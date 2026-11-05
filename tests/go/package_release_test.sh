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

# Verify the extracted package can run an actual action with no checkout nearby.
NATIVE_OUTPUT="$TMP/native-release"
bash "$ROOT/scripts/package-release.sh" v9.8.7 "$NATIVE_OUTPUT" || fail 'native package build failed'
case "$(uname -s)" in
  Darwin) native_os=macos; launcher=haws.command; archive=haws-macos.tar.gz ;;
  Linux) native_os=linux; launcher=haws.sh; archive=haws-linux.tar.gz ;;
  *) fail 'native package test requires macOS or Linux' ;;
esac
mkdir -p "$TMP/extracted" "$TMP/home"
tar -xzf "$NATIVE_OUTPUT/$archive" -C "$TMP/extracted"
native_root="$TMP/extracted/haws-go/$native_os"
[[ -f "$native_root/runtime/haws.sh" ]] || fail 'extracted package is missing its runtime'
[[ -s "$native_root/runtime/source-revisions.tsv" ]] || fail 'packaged pinned source revisions are missing'
(cd "$TMP/home" && env -u HAWS_ROOT HOME="$TMP/home" "$native_root/$launcher" doctor >"$TMP/doctor.log" 2>&1) || { cat "$TMP/doctor.log" >&2; fail 'extracted launcher could not run Doctor'; }
rg -qi 'doctor|health' "$TMP/doctor.log" || fail 'Doctor action did not run'
(cd "$TMP/home" && env -u HAWS_ROOT HOME="$TMP/home" "$native_root/$launcher" status >"$TMP/status.log" 2>&1) || { cat "$TMP/status.log" >&2; fail 'extracted launcher could not run Status'; }
rg -q 'HAWS Status' "$TMP/status.log" || fail 'Status action did not run through the extracted Go host'
[[ -f "$native_root/data/secondbrain/WORKFLOW.md" ]] || fail 'persistent Second Brain seed was not initialized in data/'
[[ ! -d "$native_root/runtime/.haws" ]] || fail 'runtime contains writable state'


# Inspect every actual archive and compare each shipped file to its manifest.
python3 - "$NATIVE_OUTPUT" "$TMP/inspect" <<'PYTEST'
import hashlib, json, pathlib, sys, tarfile, zipfile
output, dest = map(pathlib.Path, sys.argv[1:])
for platform, archive in (("windows", "haws-windows.zip"), ("macos", "haws-macos.tar.gz"), ("linux", "haws-linux.tar.gz")):
    target = dest / platform
    target.mkdir(parents=True)
    if archive.endswith(".zip"):
        with zipfile.ZipFile(output / archive) as source:
            source.extractall(target)
    else:
        with tarfile.open(output / archive) as source:
            source.extractall(target)
    root = target / "haws-go" / platform
    manifest = json.loads((root / "package-manifest.json").read_text())
    actual = {str(p.relative_to(root)) for p in root.rglob("*") if p.is_file()}
    assert actual == set(manifest["files"]) | {"package-manifest.json"}, (platform, actual ^ set(manifest["files"]))
    for name, expected in manifest["files"].items():
        assert hashlib.sha256((root / name).read_bytes()).hexdigest() == expected, (platform, name)
    assert "runtime/haws.sh" in actual
    assert not any(part in {".git", "tests", ".superpowers", "data"} for name in actual for part in pathlib.PurePosixPath(name).parts)
PYTEST

# Exercise uninstall against actual extracted native archives. The first
# fixture must remove an empty package root; the second must retain personal
# data and its containing package directory while removing verified app files.
uninstall_empty_parent="$TMP/uninstall-empty"
uninstall_data_parent="$TMP/uninstall-data"
mkdir -p "$uninstall_empty_parent" "$uninstall_data_parent"
tar -xzf "$NATIVE_OUTPUT/$archive" -C "$uninstall_empty_parent"
tar -xzf "$NATIVE_OUTPUT/$archive" -C "$uninstall_data_parent"
uninstall_empty_root="$uninstall_empty_parent/haws-go/$native_os"
uninstall_data_root="$uninstall_data_parent/haws-go/$native_os"
mkdir -p "$uninstall_data_root/data/secondbrain"
printf '%s\n' 'private package data' > "$uninstall_data_root/data/secondbrain/personal.md"
HAWS_TEST_UNINSTALL_EMPTY_PACKAGE="$uninstall_empty_root" \
HAWS_TEST_UNINSTALL_DATA_PACKAGE="$uninstall_data_root" \
  go test ./internal/uninstall -run 'TestApply(RemovesExtractedPackageToEmpty|PreservesExtractedPackageData)$' -count=1 || {
    fail 'extracted package uninstall/data-preservation checks failed'
}

# Exercise first-time setup with a pinned local source from the extracted package.
fixture_repo="$TMP/source-repo"
git init -q "$fixture_repo"
git -C "$fixture_repo" config user.name 'HAWS Test'
git -C "$fixture_repo" config user.email test@example.invalid
printf '%s\n' '---' 'name: local-fixture' 'description: fixture' '---' > "$fixture_repo/SKILL.md"
git -C "$fixture_repo" add SKILL.md
git -C "$fixture_repo" commit -qm fixture
fixture_revision="$(git -C "$fixture_repo" rev-parse HEAD)"
printf '[submodule "skills/packs/fixture"]\n\tpath = skills/packs/fixture\n\turl = %s\n' "$fixture_repo" > "$native_root/runtime/.gitmodules"
printf 'skills/packs/fixture\t%s\n' "$fixture_revision" > "$native_root/runtime/source-revisions.tsv"
# An existing unowned checkout must never be adopted or updated.
unowned="$native_root/data/state/skill-sources/skills/packs/fixture"
mkdir -p "$(dirname "$unowned")"
git clone -q "$fixture_repo" "$unowned"
echo private > "$unowned/personal-file"
if env HOME="$TMP/home" HAWS_STATE_DIR="$native_root/data/state" HAWS_TEST_ALLOW_LOCAL_SOURCES=1 HAWS_SOURCE_ONLY=1 bash -c '. "$1"; _haws_prepare_device_source "skills/packs/fixture::skills/packs/fixture"' _ "$native_root/runtime/haws.sh"; then
 fail 'unowned checkout was accepted for materialization'
fi
[[ "$(cat "$unowned/personal-file")" == private ]] || fail 'unowned checkout was changed'
rm -rf "$unowned"
# Verify the initial checkout uses the release pin even if the remote moved.
printf '%s\n' 'new supporting content' > "$fixture_repo/extra.txt"
git -C "$fixture_repo" add extra.txt
git -C "$fixture_repo" commit -qm 'fixture update'
fixture_updated="$(git -C "$fixture_repo" rev-parse HEAD)"
env HOME="$TMP/home" HAWS_STATE_DIR="$native_root/data/state" HAWS_TEST_ALLOW_LOCAL_SOURCES=1 HAWS_SOURCE_ONLY=1 bash -c '. "$1"; _haws_prepare_device_source "skills/packs/fixture::skills/packs/fixture"' _ "$native_root/runtime/haws.sh" || fail 'could not materialize pinned source'
[[ "$(git -C "$unowned" rev-parse HEAD)" == "$fixture_revision" ]] || fail 'initial source checkout did not use release pin'
echo keep > "$native_root/data/personal-note"
# Customize the first-run draft to keep update checks offline in this isolated
# package fixture. The Go Sync still applies and reconciles the selected state.
setup_input="$(printf '\033[B\n\033[B\033[B\033[B\033[B\n\nq\033[B\033[B\033[B\033[B\033[B\n\033[A\nq')"
if ! printf '%s' "$setup_input" | (cd "$TMP/home" && env -u HAWS_ROOT HOME="$TMP/home" CODEX_HOME="$TMP/home/.codex" HAWS_TEST_ALLOW_LOCAL_SOURCES=1 "$native_root/$launcher" setup >"$TMP/setup.log" 2>&1); then
 cat "$TMP/setup.log" >&2; fail 'extracted launcher setup failed'
fi
rg -q 'Settings saved; Go Home will run the authoritative Sync' "$TMP/setup.log" || { cat "$TMP/setup.log" >&2; fail 'first-time setup did not hand integration work to Go Sync'; }
rg -Fq $'integration\tcompleted' "$native_root/data/state/apply.result" || { cat "$TMP/setup.log" >&2; fail 'Go Sync did not complete the pending Settings integration'; }
[[ "$(rg -c '\[PASS\] HAWS synchronization completed' "$TMP/setup.log")" == 1 ]] || { cat "$TMP/setup.log" >&2; fail 'Go-hosted Setup did not run exactly one Sync'; }
source_dir="$native_root/data/state/skill-sources/skills/packs/fixture"
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$fixture_revision" ]] || fail 'Setup changed a source while source auto-update was disabled'
[[ -f "$source_dir/SKILL.md" ]] || fail 'materialized source is missing its skill'
rg -q 'Auto Update is disabled' "$TMP/setup.log" || { cat "$TMP/setup.log" >&2; fail 'Setup did not honor the offline update setting'; }
[[ "$(cat "$native_root/data/personal-note")" == keep ]] || fail 'setup changed personal data'
# Keep release and source network checks disabled for the explicit launcher Sync.
printf 'schema_version\t1\nauto_update_skills\toff\nauto_update_brain\toff\n' > "$native_root/data/state/settings.tsv"
(cd "$TMP/home" && env -u HAWS_ROOT HOME="$TMP/home" CODEX_HOME="$TMP/home/.codex" HAWS_TEST_ALLOW_LOCAL_SOURCES=1 "$native_root/$launcher" sync >"$TMP/sync.log" 2>&1) || { cat "$TMP/sync.log" >&2; fail 'extracted launcher Sync failed'; }
rg -q 'Sources are synchronized|Source synchronization' "$TMP/sync.log" || fail 'Sync action did not execute'
[[ "$(cat "$native_root/data/personal-note")" == keep ]] || fail 'Sync changed personal data'

# A repeat launch must preserve user edits.
echo 'personal change' >> "$native_root/data/secondbrain/WORKFLOW.md"
(cd "$TMP/home" && env -u HAWS_ROOT HOME="$TMP/home" "$native_root/$launcher" doctor >"$TMP/doctor-repeat.log" 2>&1) || fail 'repeat Doctor failed'
rg -q 'personal change' "$native_root/data/secondbrain/WORKFLOW.md" || fail 'repeat launch overwrote personal data'

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
