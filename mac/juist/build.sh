#!/bin/sh
# Builds juist for macOS (arm64 and x86_64, joined with lipo) with macos.patch into ./build.
set -e
here=$(cd "$(dirname "$0")" && pwd)
version=$(cat "$here/VERSION")
src=$(mktemp -d)
trap 'rm -rf "$src"' EXIT
git clone --quiet --depth 1 --branch "$version" https://github.com/nning/juist.git "$src"
git -C "$src" apply "$here/macos.patch"
rm -rf "$here/build"
for arch in arm64 amd64; do
	(cd "$src" && GOOS=darwin GOARCH=$arch CGO_ENABLED=0 go build -trimpath -o "$here/build/$arch/" ./cmd/juist ./cmd/juistd)
done
for tool in juist juistd; do
	lipo -create -output "$here/build/$tool" "$here/build/arm64/$tool" "$here/build/amd64/$tool"
done
rm -rf "$here/build/arm64" "$here/build/amd64"
lipo -info "$here/build/juist" "$here/build/juistd"
