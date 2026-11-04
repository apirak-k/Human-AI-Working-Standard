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

binary_dir="$launcher_dir/bin/macos-$arch"
binary="$binary_dir/haws"
for path in "$launcher_dir/bin" "$binary_dir" "$binary"; do
	if [ -L "$path" ]; then
		echo "HAWS binary must be a regular file inside this package (symlinks are not allowed): $path" >&2
		exit 1
	fi
done
if [ ! -f "$binary" ] || [ ! -x "$binary" ]; then
	echo "HAWS binary not found or not executable at $binary" >&2
	exit 1
fi

exec "$binary" "$@"
