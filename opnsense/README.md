# os-juist: juist on OPNsense

Runs juistd on the firewall and gives it a page under VPN › juist. What it touches:

- juistd from juist's own FreeBSD package, as an OPNsense service (Services list, widgets).
  DNS stays the firewall's: the plugin runs `juist set --dns=false` on start, because otherwise
  juistd rewrites `resolv.conf`.
- An interface group `juist` holding `juist0`, so you have something to write rules on.
- juist's pf anchors are called from the ruleset, and its WireGuard and relay ports are opened on
  the interfaces you pick.
- Settings: port, relay, relay port, public DHT and STUN on or off.
- Optionally an admin key, in a keystore of root's own (not juistd's), so you can invite and
  remove devices from the GUI.
- A status page: devices, how each is reached, subnets routed through them.

It doesn't route anything for you. Rules from the `juist` group to your LAN are yours to write,
same as any other VPN.

## The admin key

Inviting and removing devices from the GUI needs an admin key on the firewall, in
`/var/db/juist-admin`, which has to be root's and closed to everyone else (the plugin refuses
it otherwise). Make one there, as root, and give it a vote from a machine that already has one:

```sh
install -d -m 700 /var/db/juist-admin
JUIST_HOME=/var/db/juist-admin juist admins new firewall   # prints its key
juist admins add firewall KEY                              # on an existing admin's machine
```

Or bring an existing key: `juist admins export NAME` on its machine, then
`JUIST_HOME=/var/db/juist-admin juist admins import NAME` here, pasting the line. Then tick Admin
in the plugin's settings.

An invite from the GUI is `juist invite --yes --no-lan`: a link that admits whoever opens it
first, until it expires (15 minutes, an hour or a day), without the words `juist invite`
otherwise has both sides compare. Anyone who can open the plugin's status page can read the
link while it lasts. Send it somewhere only the new device's owner reads, and cancel it if it
went astray.

## Install

OPNsense 26.7 or later (FreeBSD 15), amd64 or arm64. Add juist's repository and this one, then
install, as root on the firewall:

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

`pkg install os-juist` pulls juist from juist's repository. Remove with `pkg delete os-juist`;
juist's state in its home directory stays.

## Build

`sh build-pkg.sh` writes `dist/os-juist-VERSION-FreeBSD-15-amd64.pkg` and the aarch64 one, on
any system with Go: the package is assembled by `tools/mkpkg` (from juist) rather than by
FreeBSD's `pkg create`, and runs the same install scripts OPNsense's own plugins do.

`sh build-repo.sh OUT KEY` adds the signed catalog around them with `tools/mkrepo` (also from
juist). The site's deploy runs it with the `PKG_SIGNING_KEY` secret, so the repository at
`0x23me.github.io/priel/opnsense/${ABI}` follows `main`.

The `Makefile` is the one OPNsense's [plugins](https://github.com/opnsense/plugins) tree takes,
for building it there as `net/juist`.
