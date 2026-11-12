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
just release 0.1.0        # bundle, notarize and staple into dist/
```

Signing uses the "Developer ID Application" identity in your keychain
(`JUIST_SIGN_IDENTITY` names another). Notarizing uses a `notarytool` keychain profile named
`priel` (`PRIEL_NOTARY_PROFILE` names another), stored once with
`xcrun notarytool store-credentials priel`.

## The juist fork

[0x23me/juist](https://github.com/0x23me/juist) is upstream juist with three commits on the
`priel` branch, tagged `vX.Y.Z-priel.N`:

- On macOS, the rc.d service helpers are built rather than the systemd ones.
- On macOS, a juist subnet is left out of the tunnel while the Mac is on a network inside it.
- juistd reports each peer's last handshake and bytes received and sent, as `PeerReach` keys
  100 to 102, when a status request sets `Figures` (key 100). The stock `juist` never sets it
  and gets the stock answer, so juist's own command line keeps working.

## The daemon

Root never runs a file inside the app, which your user can rewrite. Switching on the first
time, and after an update, runs `Helper.swift`'s install as root through the password prompt:
it copies `juist`, `juistd`, `juistd-launch` and `priel-dns` into
`/Library/PrivilegedHelperTools/me.0x23.priel`, strips ACLs and file flags, makes root the
owner, checks each against `identifier "me.0x23.priel.<tool>"` and the app's own Developer ID
team, and writes `/Library/LaunchDaemons/me.0x23.priel.juistd.plist` running that copy of
`juistd-launch`. The app compares code directory hashes to tell whether the copy is its own.

`juistd-launch` keeps juistd running while `/Library/Application Support/Priel/on` exists, a
file of the installing user's that the app creates and removes: the switch. It makes
`/var/run/juist` readable (juistd makes it 0700, and the app and the command line read the
0666 socket inside), runs juistd with `--home /var/db/juist --socket
/var/run/juist/juistd.sock --tun utun9` and what `/etc/priel/juistd.flags` adds, if root owns
that file and no one else can write it, calls `priel-dns` as juistd starts and stops, and
rotates `/var/log/juistd.log` at 10 MB. It checks the switch once a second.

## Upgrading juist

1. In a clone of the fork: fetch upstream's new tag, `git rebase --onto vNEW vOLD priel`, fix what
   conflicts, run `go test ./ipc ./daemon` with a short `TMPDIR` (unix socket paths are limited
   to 104 bytes), tag `vNEW-priel.1` and push the branch and the tag.
2. Put that tag in `juist/VERSION` and `just install`; Priel then shows Update, which installs
   the new juistd as root and restarts it.
3. Capture the status again and run the tests, which fail when juistd's status changed in a way
   the app reads: `just capture operator-figures --figures` as the operator; for the view of a
   user who is not, as one who cannot read your home folder,
   `cp Scripts/capture-status.py /tmp/ && cd /tmp && sudo -u nobody python3 capture-status.py reader --out /tmp`
   and move `/tmp/reader.cbor` into `Tests/JuistKitTests/Fixtures/`. Replace names and
   addresses in new fixtures before committing them. Then `just test`.
