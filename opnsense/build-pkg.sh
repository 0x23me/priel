#!/bin/sh
# Builds the OPNsense plugin as a FreeBSD package on any system: dist/os-juist-VERSION-ABI.pkg
# for each ABI given (default FreeBSD 15, amd64 and aarch64, as OPNsense 26.7 and later). It holds
# scripts and templates only, and depends on juist, which comes from juist's own repository.
#   sh build-pkg.sh [ABI...]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
cd "$here"
version=$(sed -n 's/^PLUGIN_VERSION=[[:space:]]*//p' Makefile)
name=os-juist
[ $# -gt 0 ] || set -- FreeBSD:15:amd64 FreeBSD:15:aarch64
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mtime=$(git log -1 --format=%ct -- . 2>/dev/null || date +%s)
# OPNsense lists installed plugins by these files, as its plugins.mk writes them.
cat > "$work/version" <<JSON
{
    "product_abi": "",
    "product_arch": "",
    "product_conflicts": "",
    "product_email": "",
    "product_hash": "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)",
    "product_id": "$name",
    "product_name": "juist",
    "product_tier": "3",
    "product_version": "$version",
    "product_website": "https://github.com/0x23me/priel"
}
JSON
cat > "$work/manifest.json" <<JSON
{
	"name": "$name",
	"origin": "opnsense/$name",
	"comment": "$(sed -n 's/^PLUGIN_COMMENT=[[:space:]]*//p' Makefile)",
	"maintainer": "noreply@github.com",
	"www": "https://github.com/0x23me/priel",
	"prefix": "/usr/local",
	"licenselogic": "single",
	"licenses": ["BSD3CLAUSE"],
	"deps": {"juist": {"origin": "net/juist", "version": "0.28.1,1"}},
	"desc": $(python3 -c 'import json,sys; print(json.dumps(open("pkg-descr").read().split("\nPlugin Changelog")[0].strip()))')
}
JSON
# Paths hold no spaces; $files is split into words on purpose.
set -f
files="/usr/local/opnsense/version/juist=$work/version"
for f in $(cd src && find . -type f ! -name .DS_Store | sort); do
	files="$files /usr/local/${f#./}=$here/src/${f#./}"
done
mkdir -p dist
for abi in "$@"; do
	out="dist/$name-$version-$(echo "$abi" | tr ':' '-').pkg"
	(cd tools && go run ./mkpkg -manifest "$work/manifest.json" -scripts "$here/scripts" -version "$version" \
		-abi "$abi" -mtime "$mtime" -o "$here/$out" $files)
	echo "$out"
done
