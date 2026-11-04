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

run_unix_success_case() {
	local os="$1" launcher_rel="$2" machine="$3" arch="$4"
	local case_root="$TMP/${os}-${machine}"
	local launcher="$case_root/launcher"
	local fakebin="$case_root/fakebin"
	local binary="$launcher/bin/${os}-${arch}/haws"
	mkdir -p "$launcher"
	cp "$ROOT/$launcher_rel" "$launcher/$(basename "$launcher_rel")"
	chmod +x "$launcher/$(basename "$launcher_rel")"
	make_uname "$fakebin"
	make_sentinel "$binary"
	local output
	output="$(PATH="$fakebin:$PATH" HAWS_TEST_UNAME="$machine" "$launcher/$(basename "$launcher_rel")" 'arg with spaces' two)" || fail "$os $machine should launch"
	assert_contains "$output" "selected=$binary" "$os $machine selected the wrong binary"
	assert_contains "$output" 'arg=<arg with spaces>' "$os $machine did not preserve quoted arguments"
	assert_contains "$output" 'arg=<two>' "$os $machine did not preserve arguments"
}

for os in macos linux; do
	if [[ "$os" == macos ]]; then
		launcher_rel="launchers/macos/haws.command"
	else
		launcher_rel="launchers/linux/haws.sh"
	fi
	for machine in arm64 aarch64; do
		run_unix_success_case "$os" "$launcher_rel" "$machine" arm64
	done
	for machine in x86_64 amd64; do
		run_unix_success_case "$os" "$launcher_rel" "$machine" amd64
	done
done

run_unix_rejection_case() {
	local os="$1" launcher_rel="$2" machine="$3" arch="$4" expected="$5"
	local case_root="$TMP/${os}-reject-${machine}"
	local launcher="$case_root/launcher"
	local fakebin="$case_root/fakebin"
	mkdir -p "$launcher"
	cp "$ROOT/$launcher_rel" "$launcher/$(basename "$launcher_rel")"
	chmod +x "$launcher/$(basename "$launcher_rel")"
	make_uname "$fakebin"
	if [[ "$arch" == symlink ]]; then
		mkdir -p "$case_root/outside"
		make_sentinel "$case_root/outside/haws"
		mkdir -p "$launcher/bin/${os}-amd64"
		ln -s "$case_root/outside/haws" "$launcher/bin/${os}-amd64/haws"
	elif [[ "$arch" != missing ]]; then
		make_sentinel "$launcher/bin/${os}-${arch}/haws"
	fi
	local output rc
	set +e
	output="$(PATH="$fakebin:$PATH" HAWS_TEST_UNAME="$machine" "$launcher/$(basename "$launcher_rel")" 2>&1)"
	rc=$?
	set -e
	[[ "$rc" -ne 0 ]] || fail "$os $machine unexpectedly succeeded"
	assert_contains "$output" "$expected" "$os $machine did not explain rejection"
}

for os in macos linux; do
	if [[ "$os" == macos ]]; then
		launcher_rel="launchers/macos/haws.command"
	else
		launcher_rel="launchers/linux/haws.sh"
	fi
	run_unix_rejection_case "$os" "$launcher_rel" riscv64 missing 'Unsupported CPU architecture'
	run_unix_rejection_case "$os" "$launcher_rel" x86_64 missing 'HAWS binary not found'
	run_unix_rejection_case "$os" "$launcher_rel" x86_64 symlink 'must be a regular file'
done

echo 'PASS: Unix launchers select supported CPUs, preserve arguments, and reject invalid binaries.'
