#!/usr/bin/env bash
# Builds, signs and notarizes Priel VERSION into dist/: Priel-VERSION.zip and its SHA256.
# Notarization uses the notarytool keychain profile in PRIEL_NOTARY_PROFILE (default "priel"),
# stored once with: xcrun notarytool store-credentials priel --apple-id ... --team-id ...
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: release.sh VERSION, as 0.1.0}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION is MAJOR.MINOR.PATCH, not $version" >&2; exit 1; }
profile="${PRIEL_NOTARY_PROFILE:-priel}"
PRIEL_VERSION="$version" ./Scripts/bundle.sh
app=.build/Priel.app
mkdir -p dist
zip="dist/Priel-$version.zip"
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
spctl --assess --type execute --verbose=2 "$app"
rm "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
(cd dist && shasum -a 256 "Priel-$version.zip" > "Priel-$version.zip.sha256")
echo "notarized: $zip"
