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

juist first, then the plugin, as root on the firewall (FreeBSD 15 shown; OPNsense on
FreeBSD 14 takes the `FreeBSD-14` plugin package):

```sh
pkg add https://github.com/nning/juist/releases/download/v0.27.1/juist-freebsd15-amd64.pkg
pkg add https://github.com/0x23me/priel/releases/download/v0.1.0/os-juist-0.1-FreeBSD-15-amd64.pkg
```

Remove with `pkg delete os-juist`; juist's state in its home directory stays.

## Build

`sh build-pkg.sh` writes `dist/os-juist-VERSION-FreeBSD-14-amd64.pkg` and the FreeBSD 15 one, on
any system with Go: the package is assembled by `tools/mkpkg` (from juist) rather than by
FreeBSD's `pkg create`, and runs the same install scripts OPNsense's own plugins do.

The `Makefile` is the one OPNsense's [plugins](https://github.com/opnsense/plugins) tree takes,
for building it there as `net/juist`.
