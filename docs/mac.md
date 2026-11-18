# Priel on the Mac

The switch is the file `/Library/Application Support/Priel/on`; the daemon starts juistd
while it exists.

Why the copy: anything inside an app in `/Applications` can be rewritten by your user, and
root running it would hand root to anything running as you.

juistd starts as root with `--home /var/db/juist --socket /var/run/juist/juistd.sock`, keeps a
small helper as root for the tunnel (`utun100`), its addresses and routes, and runs the rest as
`_juist`, which owns `/var/db/juist`. Anything else goes in `/etc/priel/juistd.flags`, which has
to be owned by root (otherwise it's ignored):

```sh
sudo mkdir -p /etc/priel
echo "--no-dht --no-stun" | sudo tee /etc/priel/juistd.flags
```

Flip the switch off and on to pick it up.

## If juist's own installer was here first

`curl -fsSL https://juist.nning.io/install | sh` sets juist up with the same user and the same
`/var/db/juist`, so this Mac stays the same device when Priel takes over: Priel's password step
stops and disables juist's LaunchDaemon (`io.nning.juist.juistd`) and runs its own instead.
Running juist's installer again leaves it disabled; `brew uninstall --zap priel` turns it back on.
Other networks you started with juist's `setup.sh instance start` keep running as they are.

## Split DNS

If your network has internal domains, the DNS section sends their lookups to a server on the
other side: `b.home.example` to 10.23.1.1, say. It uses `/etc/resolver`, one file per domain,
written when juistd starts and removed when it stops, so with the VPN off nothing hangs on a
server you can't reach. Priel only removes files it wrote. If you already made some by hand
that point into a juist subnet, Take Over adopts them. The list lives in
`/etc/priel/resolvers`.

## Removing it

Installed with Homebrew: `brew uninstall --zap priel`. A plain `brew uninstall` leaves juistd
running: Homebrew runs a cask's uninstall steps on every upgrade too, and the VPN would drop.
Otherwise:

```sh
sudo launchctl bootout system/me.0x23.priel.juistd
sudo rm -rf /Library/LaunchDaemons/me.0x23.priel.juistd.plist /Library/PrivilegedHelperTools/me.0x23.priel \
  "/Library/Application Support/Priel" /etc/priel /usr/local/bin/juist
```

`/var/db/juist` holds this Mac's keys in the network, owned by the `_juist` user. If you're done
with juist, delete both:

```sh
sudo rm -rf /var/db/juist
sudo dscl . -delete /Users/_juist; sudo dscl . -delete /Groups/_juist
```

## The bundled juist

The bundled juist comes from [0x23me/juist](https://github.com/0x23me/juist), juist plus one
small commit on the `priel` branch: it leaves a juist subnet out of the tunnel while the Mac
sits on a network inside that subnet, so at home your LAN stays direct. That is my policy, not a
safe default: any network numbered inside the subnet gets the same treatment. Everything else
the app shows, each peer's last handshake and, to the operator, its byte counts, is juist's own.
Building it yourself: [mac/README.md](../mac/README.md).
