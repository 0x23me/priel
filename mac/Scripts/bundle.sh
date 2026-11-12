#!/usr/bin/env bash
# Builds and signs .build/Priel.app for arm64 and x86_64: the menu bar app, the patched juist
# and juistd from juist/build (built by juist/build.sh when missing or older than juist/VERSION),
# and the two scripts root runs. Root never runs them from here: the app copies them into
# /Library/PrivilegedHelperTools and checks their signatures there (Helper.swift).
set -euo pipefail
cd "$(dirname "$0")/.."
identity="${JUIST_SIGN_IDENTITY:-Developer ID Application}"
go=juist/build
if [ ! -x "$go/juistd" ] || [ juist/VERSION -nt "$go/juistd" ]; then
    sh juist/build.sh
fi
version="${PRIEL_VERSION:-$(cat VERSION)}"

swift build -c release --arch arm64 --arch x86_64
bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
app=".build/Priel.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
cp "$bin/Priel" "$go/juist" "$go/juistd" Resources/juistd-launch Resources/priel-dns "$app/Contents/MacOS/"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>me.0x23.priel</string>
  <key>CFBundleName</key><string>Priel</string>
  <key>CFBundleExecutable</key><string>Priel</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>${version}</string>
  <key>CFBundleShortVersionString</key><string>${version}</string>
  <key>JuistVersion</key><string>$(cat juist/VERSION)</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHumanReadableCopyright</key><string>BSD-3-Clause. juist is by henning mueller; Priel is not part of it.</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

for tool in juist juistd juistd-launch priel-dns; do
    codesign --force --options runtime --timestamp --sign "$identity" -i "me.0x23.priel.$tool" "$app/Contents/MacOS/$tool"
done
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
echo "built $app"
