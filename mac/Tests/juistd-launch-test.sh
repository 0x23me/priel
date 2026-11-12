#!/bin/sh
# Runs Resources/juistd-launch with its paths moved into a scratch directory and stand-ins for
# juistd and priel-dns: the switch starts and stops juistd, a crash is restarted, TERM stops all.
set -eu
src="$(cd "$(dirname "$0")/.." && pwd)/Resources/juistd-launch"
t=$(mktemp -d)
launch=
trap '[ -z "$launch" ] || kill "$launch" 2>/dev/null || true; rm -rf "$t"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$t/log" >&2; exit 1; }
mkdir -p "$t/here" "$t/state"
sed -e "s|/Library/PrivilegedHelperTools/me.0x23.priel|$t/here|" \
	-e "s|/Library/Application Support/Priel|$t/state|" \
	-e "s|/etc/priel/juistd.flags|$t/flags|" \
	-e "s|/var/log/juistd.log|$t/juistd.log|" -e "s|10485760|100|" \
	-e "s|/var/db/juist|$t/db|g" -e "s|/var/run/juist|$t/run|g" "$src" > "$t/launch"
cat > "$t/here/juistd" <<EOF
#!/bin/sh
echo "juistd \$*" >> "$t/log"
trap 'echo "juistd stopped" >> "$t/log"; exit 0' TERM
while :; do sleep 0.2; done
EOF
cat > "$t/here/priel-dns" <<EOF
#!/bin/sh
echo "dns \$1" >> "$t/log"
EOF
chmod 755 "$t/here/juistd" "$t/here/priel-dns"
printf '%s\n' '--no-dht' > "$t/flags"
chmod 644 "$t/flags"
: > "$t/log"

# Waits up to five seconds for the log to hold a line matching $1, $2 times.
until_log() {
	for _ in $(seq 50); do
		[ "$(grep -c -- "$1" "$t/log")" -ge "${2:-1}" ] && return 0
		sleep 0.1
	done
	fail "no \"$1\" (x${2:-1}) in the log"
}

# A log over the (here) 100-byte limit is rotated on the first tick.
head -c 300 /dev/zero > "$t/juistd.log"
sh "$t/launch" 2>>"$t/log" &
launch=$!
sleep 1.5
grep -q juistd "$t/log" && fail "juistd started with the switch off"
[ "$(wc -c < "$t/juistd.log.1")" -eq 300 ] && [ ! -s "$t/juistd.log" ] || fail "log not rotated"

touch "$t/state/on"
until_log "^juistd --home"
until_log "^dns start"
# The flags file is not root's here, so it is ignored, and said so.
grep -q -- "--no-dht" "$t/log" && fail "used a flags file root does not own"
rm "$t/state/on"
until_log "^juistd stopped"
until_log "^dns stop"

touch "$t/state/on"
until_log "^juistd --home" 2
pkill -f "$t/here/juistd"
until_log "exited with" 1
# Restarted after its pause, as the switch is still on.
for _ in $(seq 150); do [ "$(grep -c '^juistd --home' "$t/log")" -ge 3 ] && break; sleep 0.1; done
[ "$(grep -c '^juistd --home' "$t/log")" -ge 3 ] || fail "juistd not restarted after it died"

kill -TERM "$launch"
wait "$launch" || true
until_log "^juistd stopped" 2
pgrep -f "$t/here/juistd" >/dev/null && fail "juistd still running after TERM"
echo "juistd-launch: ok"
