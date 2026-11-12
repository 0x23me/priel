#!/bin/sh
# Adds juist's pkg repository and Priel's to an OPNsense firewall, with their keys.
# Then: pkg update && pkg install os-juist
set -e
mkdir -p /usr/local/etc/pkg/keys /usr/local/etc/pkg/repos
fetch -o /usr/local/etc/pkg/keys/juist.pub https://pkg.juist.nning.io/juist/freebsd.pub
fetch -o /usr/local/etc/pkg/keys/priel.pub https://0x23me.github.io/priel/opnsense/priel.pub
cat > /usr/local/etc/pkg/repos/priel.conf <<'EOF'
juist: { url: "https://pkg.juist.nning.io/juist/freebsd/${ABI}", signature_type: "pubkey", pubkey: "/usr/local/etc/pkg/keys/juist.pub" }
priel: { url: "https://0x23me.github.io/priel/opnsense/${ABI}", signature_type: "pubkey", pubkey: "/usr/local/etc/pkg/keys/priel.pub" }
EOF
sha256 /usr/local/etc/pkg/keys/juist.pub /usr/local/etc/pkg/keys/priel.pub
