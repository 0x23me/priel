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
