# Priel for the Mac

A Swift package: `JuistKit` (juistd's socket and its CBOR, the status, the tunnel's 64-bit
interface counters, the daemon's registration with `SMAppService`) and `Priel` (the SwiftUI
`MenuBarExtra` app). `juist/` holds the juist version, `macos.patch` and `build.sh`, which
builds `juist` and `juistd` from juist's source for arm64 and x86_64.

```sh
just test                 # unit tests; JUIST_LIVE_TESTS=1 adds the ones against a running juistd
just install              # build juist if needed, bundle, sign, copy to /Applications, start
just release 0.1.0        # bundle, notarize and staple into dist/
```

Signing uses the "Developer ID Application" identity in your keychain
(`JUIST_SIGN_IDENTITY` names another). Notarizing uses a `notarytool` keychain profile named
`priel` (`PRIEL_NOTARY_PROFILE` names another), stored once with
`xcrun notarytool store-credentials priel`.

## The patch

- On macOS, a juist subnet is left out of the tunnel while the Mac is on a network inside it.
- juistd reports each peer's last handshake and bytes received and sent, as `PeerReach` keys
  100–102, when a status request sets `Figures` (key 100). The stock `juist` never sets it and
  gets the stock answer, so the command line from juist's own release keeps working.

## The daemon

The app registers `Contents/Library/LaunchDaemons/me.0x23.priel.juistd.plist`. Its program is
`juistd-launch`, which makes `/var/run/juist` readable (juistd makes it 0700, and the app and
the command line read the 0666 socket inside) and runs juistd with `--home /var/db/juist
--socket /var/run/juist/juistd.sock --tun utun9` and what `/etc/priel/juistd.flags` adds, if
root owns that file and no one else can write it. Its log is `/var/log/juistd.log`.

## Upgrading juist

1. Put the new tag in `juist/VERSION` and rebase `macos.patch` onto it: clone the tag, `git
   apply --3way` the patch, fix what does not apply, run `go test ./ipc ./daemon` with a short
   `TMPDIR` (unix socket paths are limited to 104 bytes), and write the diff back.
2. `just install`, then turn the switch off and on to run the new juistd.
3. Capture the status again and run the tests, which fail when juistd's status changed in a way
   the app reads: `just capture operator-figures --figures` as the operator; for the view of a
   user who is not, as one who cannot read your home folder,
   `cp Scripts/capture-status.py /tmp/ && cd /tmp && sudo -u nobody python3 capture-status.py reader --out /tmp`
   and move `/tmp/reader.cbor` into `Tests/JuistKitTests/Fixtures/`. Replace names and
   addresses in new fixtures before committing them. Then `just test`.
