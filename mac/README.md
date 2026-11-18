# Priel for the Mac

A Swift package: `JuistKit` (juistd's socket and its CBOR, the status, the tunnel's 64-bit
interface counters, the switch, the split DNS list) and `Priel` (the SwiftUI `MenuBarExtra`
app, and `Helper.swift`, which installs what root runs). `juist/` holds the juist version and `build.sh`, which
builds `juist` and `juistd` for arm64 and x86_64 from that tag of
[0x23me/juist](https://github.com/0x23me/juist).

```sh
just test                 # unit tests, and the two root scripts against scratch directories;
                          # JUIST_LIVE_TESTS=1 adds the ones against a running juistd
just install              # build juist if needed, bundle, sign, copy to /Applications, start
just release 0.1.0        # bundle, notarize and staple into dist/, by hand
```

Signing uses the "Developer ID Application" identity in your keychain
(`JUIST_SIGN_IDENTITY` names another). Notarizing uses an App Store Connect API key when
`PRIEL_NOTARY_KEY` names its `.p8` (with `PRIEL_NOTARY_KEY_ID` and `PRIEL_NOTARY_ISSUER`), and
otherwise a `notarytool` keychain profile named `priel` (`PRIEL_NOTARY_PROFILE` names another),
stored once with `xcrun notarytool store-credentials priel`.

`.build/debug/Priel --shot connected|several|reader|join light|dark <file.png>` shows the window
with a made-up network (laptop-01, lab, gate) and saves a picture of it, which is how the
pictures on the site are made, in a virtual machine. It is in a debug build only (`swift build`).

## Releasing

CI does it, from a tag. Put the version in `VERSION`, commit, then push an annotated tag whose
message is the release notes:

```sh
git tag -a v0.3.0 -m "What changed, in Markdown"
git push origin main v0.3.0
```

`.github/workflows/release.yml` checks the tag against `VERSION`, runs the tests, builds juist
from the fork, signs, notarizes and staples the app on a macOS runner, builds the OPNsense
plugin packages, publishes the release with both and what they were built with, and puts the
cask into `0x23me/homebrew-tap`. The secrets it needs are listed at its top.

## The juist fork

[0x23me/juist](https://github.com/0x23me/juist) is upstream juist with one commit on the
`priel` branch, tagged `vX.Y.Z-priel.N`: on macOS, a juist subnet is left out of the tunnel
while the Mac is on a network inside it, where upstream leaves out only the part the Mac's own
routes cover. Its test expects that on macOS.

Until 0.29 the branch also carried the darwin build tag fix and the per-peer handshake and
bytes, which upstream now has; the bytes are `PeerReach` keys 14 and 15, the handshake 13,
in every status answer, the bytes zero to anyone but the operator.

## The daemon

Root never runs a file inside the app, which your user can rewrite. Switching on the first
time, and after an update, runs `Helper.swift`'s install as root through the password prompt:
it copies `juist`, `juistd`, `juistd-launch` and `priel-dns` into
`/Library/PrivilegedHelperTools/me.0x23.priel`, strips ACLs and file flags, makes root the
owner, checks each against `identifier "me.0x23.priel.<tool>"` and the app's own Developer ID
team, and writes `/Library/LaunchDaemons/me.0x23.priel.juistd.plist` running that copy of
`juistd-launch`. It then makes the hidden user `_juist` if there is none, as juist's own
installer does, gives it `/var/db/juist` if an earlier Priel left that root's, and stops and
disables juist's own LaunchDaemon `io.nning.juist.juistd` if there is one, which would run the
same device from the same folder. The app compares code directory hashes to tell whether the
copy is its own.

`juistd-launch` keeps juistd running while `/Library/Application Support/Priel/on` exists, a
file of the installing user's that the app creates and removes: the switch. It makes
`/var/db/juist` (0700) and `/var/run/juist` (0755, as the app and the command line read the
0666 socket inside) `_juist`'s, runs juistd with `--home /var/db/juist --socket
/var/run/juist/juistd.sock` and what `/etc/priel/juistd.flags` adds, if root owns
that file and no one else can write it, calls `priel-dns` as juistd starts and stops, and
rotates `/var/log/juistd.log` at 10 MB. It checks the switch once a second. Started as root,
juistd keeps a helper as root for `utun100`, its addresses, routes and pf anchors, and runs the
daemon as `_juist`; without that user the launcher does not start it.

## Upgrading juist

1. In a clone of the fork: fetch upstream's new tag, `git rebase --onto vNEW vOLD priel`, fix what
   conflicts, run `go test ./ipc ./daemon` with a short `TMPDIR` (unix socket paths are limited
   to 104 bytes), tag `vNEW-priel.1` and push the branch and the tag.
2. Put that tag in `juist/VERSION` and `just install`; Priel then shows Update, which installs
   the new juistd as root and restarts it.
3. Capture the status again and run the tests, which fail when juistd's status changed in a way
   the app reads: `just capture operator` as the operator; for the view of a
   user who is not, as one who cannot read your home folder,
   `cp Scripts/capture-status.py /tmp/ && cd /tmp && sudo -u nobody python3 capture-status.py reader --out /tmp`
   and move `/tmp/reader.cbor` into `Tests/JuistKitTests/Fixtures/`. Replace names and
   addresses in new fixtures before committing them. Then `just test`.
