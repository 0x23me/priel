#!/bin/sh
# Builds the plugin's pkg repository into OUT, one directory per ABI as pkg's ${ABI} names it,
# each holding the package and a catalog signed with KEY (an RSA private key, PEM). The public
# half is site/opnsense/priel.pub.
#   sh build-repo.sh OUT KEY
set -eu
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$1"
out=$(cd "$1" && pwd)
key=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
sh "$here/build-pkg.sh" >/dev/null
for pkg in "$here"/dist/os-juist-*.pkg; do
	abi=$(basename "$pkg" .pkg | sed 's/^os-juist-[^-]*-//; s/-/:/g')
	mkdir -p "$out/$abi"
	cp "$pkg" "$out/$abi/"
done
for dir in "$out"/FreeBSD:*; do
	(cd "$here/tools" && go run ./mkrepo -key "$key" "$dir")
	ls "$dir"
done
