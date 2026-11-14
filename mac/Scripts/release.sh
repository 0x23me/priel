#!/usr/bin/env bash
# Builds, signs and notarizes Priel VERSION into dist/: Priel-VERSION.zip, its SHA256, and the
# Homebrew cask for it (dist/priel.rb, to copy into 0x23me/homebrew-tap's Casks folder).
# Notarization uses an App Store Connect API key when PRIEL_NOTARY_KEY names its .p8 file (with
# PRIEL_NOTARY_KEY_ID and PRIEL_NOTARY_ISSUER; this is how the release workflow runs it), and
# otherwise the notarytool keychain profile in PRIEL_NOTARY_PROFILE (default "priel"), stored once
# with: xcrun notarytool store-credentials priel --apple-id ... --team-id ...
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: release.sh VERSION, as 0.1.0}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION is MAJOR.MINOR.PATCH, not $version" >&2; exit 1; }
if [ -n "${PRIEL_NOTARY_KEY:-}" ]; then
    notary=(--key "$PRIEL_NOTARY_KEY" --key-id "${PRIEL_NOTARY_KEY_ID:?}" --issuer "${PRIEL_NOTARY_ISSUER:?}")
else
    notary=(--keychain-profile "${PRIEL_NOTARY_PROFILE:-priel}")
fi
PRIEL_VERSION="$version" ./Scripts/bundle.sh
app=.build/Priel.app
team="$(codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=\([A-Z0-9]*\)$/\1/p')"
[ -n "$team" ] || { echo "the app is not signed by a developer; a release has to be" >&2; exit 1; }
mkdir -p dist
zip="dist/Priel-$version.zip"
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" "${notary[@]}" --wait
xcrun stapler staple "$app"
spctl --assess --type execute --verbose=2 "$app"
rm "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
(cd dist && shasum -a 256 "Priel-$version.zip" > "Priel-$version.zip.sha256")
sha="$(cut -d' ' -f1 "dist/Priel-$version.zip.sha256")"

# The daemon and the root-owned copy stay on plain uninstall, as Homebrew runs uninstall on every
# upgrade too and the VPN would drop until the next password; zap removes them.
read -r -d '' cask <<'CASK' || true
cask "priel" do
  version "@VERSION@"
  sha256 "@SHA@"

  url "https://github.com/0x23me/priel/releases/download/v#{version}/Priel-#{version}.zip"
  name "Priel"
  desc "Menu bar switch and status for the juist mesh VPN"
  homepage "https://0x23me.github.io/priel/"

  depends_on macos: :sonoma

  app "Priel.app"

  uninstall quit: "me.0x23.priel"

  # After launchd stops the daemon: its split DNS files go once it is gone, and a juist command
  # linked to the copy goes with the copy.
  zap launchctl: "me.0x23.priel.juistd",
      script:    {
        executable: "/bin/sh",
        args:       ["-c", <<~SH],
          h=/Library/PrivilegedHelperTools/me.0x23.priel
          i=0
          while pgrep -qf "$h/juistd-launch" && [ $i -lt 50 ]; do sleep 0.2; i=$((i + 1)); done
          [ ! -x "$h/priel-dns" ] || "$h/priel-dns" stop
          case $(readlink /usr/local/bin/juist) in "$h"/*) rm /usr/local/bin/juist ;; esac
          # juist's own LaunchDaemon, which Priel disabled, runs this Mac's keys again.
          p=/Library/LaunchDaemons/io.nning.juist.juistd.plist
          if [ -f "$p" ]; then
            launchctl enable system/io.nning.juist.juistd
            launchctl bootstrap system "$p" 2>/dev/null || true
          fi
        SH
        sudo:       true,
      },
      delete:    [
        "/etc/priel",
        "/Library/Application Support/Priel",
        "/Library/LaunchDaemons/me.0x23.priel.juistd.plist",
        "/Library/PrivilegedHelperTools/me.0x23.priel",
        "/var/log/juistd.log*",
      ]

  caveats <<~EOS
    The first switch-on, and the first after each upgrade, asks for your password to install
    juistd for root in /Library/PrivilegedHelperTools.

    brew uninstall leaves juistd running if it is on. brew uninstall --zap stops it and removes
    it. Neither removes /var/db/juist, this Mac's keys in the network, or the _juist user who
    owns them.
  EOS
end
CASK
cask=${cask//@VERSION@/$version}
printf '%s\n' "${cask//@SHA@/$sha}" > dist/priel.rb
echo "notarized: $zip"
echo "cask:      dist/priel.rb"
