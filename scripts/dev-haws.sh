#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
GO_VERSION=1.27.3

fail() { printf '[HAWS dev] %s\n' "$*" >&2; exit 1; }

go_is_compatible() {
	local go_bin="$1" version major minor
	version="$("$go_bin" version 2>/dev/null | sed -E 's/.*go([0-9]+)\.([0-9]+)(\.[0-9]+)?.*/\1 \2/')" || return 1
	read -r major minor <<<"$version"
	[[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
	(( major > 1 || (major == 1 && minor >= 26) ))
}

get_cached_go() {
	local goos goarch archive expected url cache_root extracted download actual go_bin
	case "$(uname -s)" in
		Darwin) goos=darwin ;;
		Linux) goos=linux ;;
		*) fail "development toolchain bootstrap supports macOS and Linux; install Go 1.26+ and invoke cmd/haws-dev directly on this OS" ;;
	esac
	case "$(uname -m)" in
		arm64|aarch64) goarch=arm64 ;;
		x86_64|amd64) goarch=amd64 ;;
		*) fail "unsupported CPU architecture: $(uname -m)" ;;
	esac
	case "$goos/$goarch" in
		darwin/arm64) expected=dd3908cf20959d798c1e06ebe5b72213f0505ce01373b40ce3110975a6cd99c2 ;;
		darwin/amd64) expected=b6f8e931e4ab497fcde6da8ae4499a58f9d258e55c8a80824a516eae5950a750 ;;
		linux/arm64) expected=a06e99309dbcbdca1a8ccd2282c3ee146e55930886e26b4f1193269587165f49 ;;
		linux/amd64) expected=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40 ;;
	esac
	archive="go${GO_VERSION}.${goos}-${goarch}.tar.gz"
	url="https://go.dev/dl/${archive}"
	cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}/haws-dev/toolchains"
	go_bin="${cache_root}/go${GO_VERSION}/bin/go"
	[[ -x "$go_bin" ]] && { printf '%s\n' "$go_bin"; return; }
	command -v curl >/dev/null 2>&1 || fail 'curl is required to download the temporary Go toolchain'
	mkdir -p "$cache_root"
	extracted="$(mktemp -d "${cache_root}/.go${GO_VERSION}.XXXXXX")"
	trap 'rm -rf "$extracted"' EXIT
	download="${extracted}/${archive}"
	printf '[HAWS dev] Downloading Go %s for %s/%s into the user cache.\n' "$GO_VERSION" "$goos" "$goarch" >&2
	curl --fail --location --silent --show-error "$url" --output "$download" || fail 'Go toolchain download failed'
	if command -v shasum >/dev/null 2>&1; then
		actual="$(shasum -a 256 "$download" | awk '{print $1}')"
	elif command -v sha256sum >/dev/null 2>&1; then
		actual="$(sha256sum "$download" | awk '{print $1}')"
	else
		fail 'a SHA-256 utility (shasum or sha256sum) is required to verify Go'
	fi
	[[ "$actual" == "$expected" ]] || fail "Go archive SHA-256 mismatch for ${archive}"
	mkdir "$extracted/unpacked"
	tar -xzf "$download" -C "$extracted/unpacked"
	[[ -x "$extracted/unpacked/go/bin/go" ]] || fail 'Go archive did not contain the expected toolchain'
	if [[ -e "${cache_root}/go${GO_VERSION}" ]]; then fail 'the Go toolchain cache appeared during installation; inspect it and retry'; fi
	mv "$extracted/unpacked/go" "${cache_root}/go${GO_VERSION}"
	rm -rf "$extracted"
	trap - EXIT
	printf '%s\n' "$go_bin"
}

GO_BIN="${HAWS_DEV_GO:-}"
if [[ -z "$GO_BIN" ]] && command -v go >/dev/null 2>&1 && go_is_compatible "$(command -v go)"; then
	GO_BIN="$(command -v go)"
fi
if [[ -z "$GO_BIN" ]] || ! go_is_compatible "$GO_BIN"; then
	GO_BIN="$(get_cached_go)"
fi

SANDBOX="${HAWS_DEV_HOME:-}"
if [[ -z "$SANDBOX" ]]; then
	SANDBOX="${XDG_CACHE_HOME:-${HOME}/.cache}/HAWS/development-sandbox-live"
fi

cd "$ROOT"
PATH="$(dirname "$GO_BIN"):${PATH}"
export PATH
exec "$GO_BIN" run ./cmd/haws-dev --source-root "$ROOT" --sandbox-root "$SANDBOX" -- "$@"
