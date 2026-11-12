#!/usr/bin/env bash
# Builds and signs .build/Priel.app for arm64 and x86_64: the menu bar app, the patched juist
# and juistd from juist/build (built by juist/build.sh when missing or older than juist/VERSION),
# and the launchd daemon the app registers to run juistd.
set -euo pipefail
cd "$(dirname "$0")/.."
identity="${JUIST_SIGN_IDENTITY:-Developer ID Application}"
go=juist/build
if [ ! -x "$go/juistd" ] || [ juist/VERSION -nt "$go/juistd" ]; then
    sh juist/build.sh
fi
version="${PRIEL_VERSION:-0.0.0}"

swift build -c release --arch arm64 --arch x86_64
bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
app=".build/Priel.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Library/LaunchDaemons"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
cp "$bin/Priel" "$go/juist" "$go/juistd" "$app/Contents/MacOS/"

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

# juistd creates its socket directory 0700 when missing; the directory has to be readable for
# the app and the command line to reach the socket, which is itself 0666. Extra juistd options
# (say --no-dht --no-stun) go in /etc/priel/juistd.flags, read only when root owns it and no one
# else can write it, since they are run as root.
cat > "$app/Contents/MacOS/juistd-launch" <<'SH'
#!/bin/sh
set -e
mkdir -p -m 700 /var/db/juist
mkdir -p /var/run/juist
chmod 755 /var/run/juist
flags=/etc/priel/juistd.flags
extra=
if [ -f "$flags" ]; then
	if [ "$(/usr/bin/stat -f '%u' "$flags")" = 0 ] && [ $(( 0$(/usr/bin/stat -f '%Lp' "$flags") & 022 )) = 0 ]; then
		extra=$(grep -v '^#' "$flags" | tr '\n' ' ' || true)
	else
		echo "juistd-launch: ignoring $flags: it must be owned by root and writable by root alone" >&2
	fi
fi
# $extra is split into words on purpose.
exec "$(dirname "$0")/juistd" --home /var/db/juist --socket /var/run/juist/juistd.sock --tun utun9 $extra
SH
chmod 755 "$app/Contents/MacOS/juistd-launch"

cat > "$app/Contents/Library/LaunchDaemons/me.0x23.priel.juistd.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>me.0x23.priel.juistd</string>
  <key>BundleProgram</key><string>Contents/MacOS/juistd-launch</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/var/log/juistd.log</string>
  <key>StandardErrorPath</key><string>/var/log/juistd.log</string>
</dict></plist>
PLIST

for tool in juist juistd juistd-launch; do
    codesign --force --options runtime --timestamp --sign "$identity" -i "me.0x23.priel.$tool" "$app/Contents/MacOS/$tool"
done
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
echo "built $app"
