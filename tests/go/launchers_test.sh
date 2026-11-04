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

assert_contains() {
	local haystack="$1" needle="$2" message="$3"
	[[ "$haystack" == *"$needle"* ]] || fail "$message (missing: $needle)"
}

make_uname() {
	local dir="$1"
	mkdir -p "$dir"
	cat >"$dir/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "${HAWS_TEST_UNAME:-}"
EOF
	chmod +x "$dir/uname"
}

make_sentinel() {
	local binary="$1"
	mkdir -p "$(dirname "$binary")"
	cat >"$binary" <<'EOF'
#!/bin/sh
printf 'selected=%s\n' "$0"
printf 'arg=<%s>\n' "$@"
EOF
	chmod +x "$binary"
}

make_base_resolver() {
	local binary="$1"
	mkdir -p "$(dirname "$binary")"
	cat >"$binary" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --haws-resolve-active-binary ]; then
	if [ "${HAWS_TEST_RESOLVE_FAIL:-}" = 1 ]; then
		echo 'active version marker is invalid' >&2
		exit 1
	fi
	printf '%s\n' "${HAWS_TEST_RESOLVED_BINARY:-$0}"
	exit 0
fi
printf 'selected=%s\n' "$0"
printf 'arg=<%s>\n' "$@"
EOF
	chmod +x "$binary"
}

launcher_for() {
	if [[ "$1" == macos ]]; then
		printf '%s\n' launchers/macos/haws.command
	else
		printf '%s\n' launchers/linux/haws.sh
	fi
}

run_unix_success_case() {
	local os="$1" machine="$2" arch="$3"
	local launcher_rel launcher case_root fakebin binary output
	launcher_rel="$(launcher_for "$os")"
	case_root="$TMP/${os}-${machine}"
	launcher="$case_root/launcher"
	fakebin="$case_root/fakebin"
	binary="$launcher/bin/${os}-${arch}/haws"
	mkdir -p "$launcher"
	cp "$ROOT/$launcher_rel" "$launcher/$(basename "$launcher_rel")"
	chmod +x "$launcher/$(basename "$launcher_rel")"
	make_uname "$fakebin"
	make_base_resolver "$binary"
	output="$(PATH="$fakebin:$PATH" HAWS_TEST_UNAME="$machine" HAWS_TEST_RESOLVED_BINARY="$binary" "$launcher/$(basename "$launcher_rel")" 'arg with spaces' two)" || fail "$os $machine should launch"
	assert_contains "$output" "selected=$binary" "$os $machine selected the wrong binary"
	assert_contains "$output" 'arg=<arg with spaces>' "$os $machine did not preserve quoted arguments"
	assert_contains "$output" 'arg=<two>' "$os $machine did not preserve arguments"
}

for os in macos linux; do
	for machine in arm64 aarch64; do
		run_unix_success_case "$os" "$machine" arm64
	done
	for machine in x86_64 amd64; do
		run_unix_success_case "$os" "$machine" amd64
	done
done

run_unix_rejection_case() {
	local os="$1" machine="$2" arch="$3" expected="$4"
	local launcher_rel launcher case_root fakebin output rc
	launcher_rel="$(launcher_for "$os")"
	case_root="$TMP/${os}-reject-${machine}"
	launcher="$case_root/launcher"
	fakebin="$case_root/fakebin"
	mkdir -p "$launcher"
	cp "$ROOT/$launcher_rel" "$launcher/$(basename "$launcher_rel")"
	chmod +x "$launcher/$(basename "$launcher_rel")"
	make_uname "$fakebin"
	case "$arch" in
		missing) ;;
		symlink)
			mkdir -p "$case_root/outside" "$launcher/bin/${os}-amd64"
			make_sentinel "$case_root/outside/haws"
			ln -s "$case_root/outside/haws" "$launcher/bin/${os}-amd64/haws"
			;;
		*) make_base_resolver "$launcher/bin/${os}-${arch}/haws" ;;
	esac
	set +e
	output="$(PATH="$fakebin:$PATH" HAWS_TEST_UNAME="$machine" "$launcher/$(basename "$launcher_rel")" 2>&1)"
	rc=$?
	set -e
	[[ "$rc" -ne 0 ]] || fail "$os $machine unexpectedly succeeded"
	assert_contains "$output" "$expected" "$os $machine did not explain rejection"
}

for os in macos linux; do
	run_unix_rejection_case "$os" riscv64 missing 'Unsupported CPU architecture'
	run_unix_rejection_case "$os" x86_64 missing 'HAWS base binary not found'
	run_unix_rejection_case "$os" x86_64 symlink 'HAWS base binary must be a regular file'
done

run_unix_active_version_case() {
	local os="$1" launcher_rel launcher case_root fakebin base_binary version_binary outside_binary output rc
	launcher_rel="$(launcher_for "$os")"
	case_root="$TMP/${os}-active-version"
	launcher="$case_root/launcher"
	fakebin="$case_root/fakebin"
	base_binary="$launcher/bin/${os}-amd64/haws"
	version_binary="$launcher/versions/v1.2.3/bin/${os}-amd64/haws"
	mkdir -p "$launcher"
	cp "$ROOT/$launcher_rel" "$launcher/$(basename "$launcher_rel")"
	chmod +x "$launcher/$(basename "$launcher_rel")"
	make_uname "$fakebin"
	make_base_resolver "$base_binary"
	make_sentinel "$version_binary"
	output="$(PATH="$fakebin:$PATH" HAWS_TEST_UNAME=x86_64 HAWS_TEST_RESOLVED_BINARY="$version_binary" "$launcher/$(basename "$launcher_rel")" --version)" || fail "$os launcher should start the resolved active version"
	assert_contains "$output" "selected=$version_binary" "$os launcher ignored the Go resolver result"

	set +e
	output="$(PATH="$fakebin:$PATH" HAWS_TEST_UNAME=x86_64 HAWS_TEST_RESOLVE_FAIL=1 "$launcher/$(basename "$launcher_rel")" 2>&1)"
	rc=$?
	set -e
	[[ "$rc" -ne 0 ]] || fail "$os launcher ignored a failed active-version resolver"
	assert_contains "$output" 'active version marker is invalid' "$os launcher did not show the resolver failure"

	outside_binary="$case_root/outside/haws"
	make_sentinel "$outside_binary"
	rm "$version_binary"
	ln -s "$outside_binary" "$version_binary"
	set +e
	output="$(PATH="$fakebin:$PATH" HAWS_TEST_UNAME=x86_64 HAWS_TEST_RESOLVED_BINARY="$version_binary" "$launcher/$(basename "$launcher_rel")" 2>&1)"
	rc=$?
	set -e
	[[ "$rc" -ne 0 ]] || fail "$os launcher followed a symlink active binary"
	assert_contains "$output" 'HAWS active binary must be a regular file' "$os launcher did not reject a symlink active binary"
}

run_unix_active_version_case macos
run_unix_active_version_case linux

echo 'PASS: Unix launchers select supported CPUs, preserve arguments, and use the verified active-binary resolver.'
