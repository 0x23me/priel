# Priel

A menu bar app for [juist](https://github.com/nning/juist) on the Mac, and an OPNsense plugin
for the firewall end. juist is a peer-to-peer WireGuard mesh VPN with no coordination server.

I wanted juist on my laptop without two shell scripts and a sudo prompt every time I turned it
off, and I wanted to see whether the tunnel to home was actually up. This is that.

Priel is not part of juist and not made by its author. If something breaks, open an issue
[here](../../issues), not on juist.

(A priel is a tidal channel in the mud flats. Juist is an island with plenty of them.)

## Mac

Grab `Priel-VERSION.zip` from [releases](../../releases), unzip, move Priel to Applications,
open it. Signed and notarized. macOS 14 or later, Apple silicon or Intel.

1. Flip the switch. macOS asks once whether Priel may run juist in the background
   (System Settings › General › Login Items & Extensions). After that, no more prompts.
2. Paste an invite code from `juist invite` on a device that's already in the network.
   Joining also makes you this Mac's juist operator, which is what shows device names and
   latency.
3. If you want the `juist` command too, hit Install. It links `/usr/local/bin/juist` to the
   copy inside the app.

Off means juistd is stopped and stays stopped across reboots. On means it starts at boot,
before anyone logs in. Quitting Priel doesn't touch juistd.

juistd runs as root from inside the app:
`--home /var/db/juist --socket /var/run/juist/juistd.sock --tun utun9`. Anything else goes in
`/etc/priel/juistd.flags`, which has to be owned by root (otherwise it's ignored):

```sh
sudo mkdir -p /etc/priel
echo "--no-dht --no-stun" | sudo tee /etc/priel/juistd.flags
```

Flip the switch off and on to pick it up.

The bundled juist comes from [0x23me/juist](https://github.com/0x23me/juist), juist plus three
small commits on the `priel` branch. They leave a juist subnet out of the tunnel while the Mac
sits on a network inside that subnet (so at home your LAN stays direct), let juistd tell the app
each peer's last handshake and byte counts, and fix a build tag on macOS. The subnet one is my
policy, not a safe default: any network numbered inside the subnet gets the same treatment.
Building it yourself: [mac/README.md](mac/README.md).

## OPNsense

Two pkg repositories, once: juist's own (for juist) and Priel's (for the plugin, which depends
on juist). As root on the firewall:

```sh
mkdir -p /usr/local/etc/pkg/keys
fetch -o /usr/local/etc/pkg/keys/juist.pub https://pkg.juist.nning.io/juist/freebsd.pub
fetch -o /usr/local/etc/pkg/keys/priel.pub https://0x23me.github.io/priel/opnsense/priel.pub
cat > /usr/local/etc/pkg/repos/priel.conf <<'EOF'
juist: { url: "https://pkg.juist.nning.io/juist/freebsd/${ABI}", signature_type: "pubkey", pubkey: "/usr/local/etc/pkg/keys/juist.pub" }
priel: { url: "https://0x23me.github.io/priel/opnsense/${ABI}", signature_type: "pubkey", pubkey: "/usr/local/etc/pkg/keys/priel.pub" }
EOF
pkg update && pkg install os-juist
```

Key checksums (`sha256 /usr/local/etc/pkg/keys/*.pub`): juist's is
`c649f2cd073f9e72825b0c1b8a2682f25c5c55405a178ea6d8a0f8b65ed89e3d` (from juist's install docs),
Priel's is `092493a223800ae06b56630efc2483b59eb3331fa43d7fd6b2dd26708655121b`.

After that the plugin is under VPN › juist and should be listed under System › Firmware ›
Plugins; it updates with the firewall. OPNsense 26.7 or later (FreeBSD 15), amd64 or arm64. What it changes
on the box: [opnsense/README.md](opnsense/README.md).

## State of things

Early. It runs on one Mac and one OPNsense box, mine. Expect rough edges and tell me about them.

## License

BSD-3-Clause, same as juist. What's taken from juist is listed in
[THIRD_PARTY.md](THIRD_PARTY.md).
