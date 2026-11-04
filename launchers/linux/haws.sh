#!/bin/bash
set -eu

case "$0" in
	/*) launcher_path="$0" ;;
	*) launcher_path="$PWD/$0" ;;
esac
launcher_dir="$(CDPATH= cd -- "$(dirname -- "$launcher_path")" && pwd -P)"

case "$(uname -m)" in
	arm64|aarch64) arch=arm64 ;;
	x86_64|amd64) arch=amd64 ;;
	*)
		echo "Unsupported CPU architecture: $(uname -m)" >&2
		exit 2
		;;
esac

base_binary="$launcher_dir/bin/linux-$arch/haws"
for path in "$launcher_dir/bin" "$launcher_dir/bin/linux-$arch" "$base_binary"; do
	if [ -L "$path" ]; then
		echo "HAWS base binary must be a regular file inside this package (symlinks are not allowed): $path" >&2
		exit 1
	fi
done
if [ ! -f "$base_binary" ] || [ ! -x "$base_binary" ]; then
	echo "HAWS base binary not found or not executable at $base_binary" >&2
	exit 1
fi

if ! binary="$("$base_binary" --haws-resolve-active-binary)"; then
	exit 1
fi
if [ -z "$binary" ] || [ ! -f "$binary" ] || [ ! -x "$binary" ]; then
	echo "HAWS active binary not found or not executable at $binary" >&2
	exit 1
fi
if [ -L "$binary" ]; then
	echo "HAWS active binary must be a regular file (symlinks are not allowed): $binary" >&2
	exit 1
fi

exec "$binary" "$@"
