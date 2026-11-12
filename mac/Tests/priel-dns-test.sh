#!/bin/sh
# Runs Resources/priel-dns with its paths moved into a scratch directory, and the test's user in
# place of root as the list's owner.
set -eu
src="$(cd "$(dirname "$0")/.." && pwd)/Resources/priel-dns"
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
dns="$t/priel-dns"
sed -e "s|^conf=/etc/priel/resolvers$|conf=$t/priel/resolvers|" -e "s|^dir=/etc/resolver$|dir=$t/resolver|" \
	-e "s|^owner=0$|owner=$(id -u)|" -e "s|pgrep -qx juistd|false|" "$src" > "$dns"
chmod 755 "$dns"
grep -q "^owner=$(id -u)$" "$dns" || { echo "FAIL: the test's sed no longer matches priel-dns" >&2; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$t/resolver"
printf 'nameserver 192.0.2.1\n' > "$t/resolver/mine.example"
"$dns" set lab.example 10.99.0.1 taken.example 10.99.0.2 v6.example fd12::1
grep -q '^lab.example 10.99.0.1$' "$t/priel/resolvers" || fail "list not written"

"$dns" stop
[ ! -e "$t/resolver/lab.example" ] || fail "stop left lab.example"
[ -f "$t/resolver/mine.example" ] || fail "stop removed a file Priel did not write"

# A file of the same name that Priel did not write survives start; set, with juistd off here,
# removes it, and start then writes Priel's.
printf 'nameserver 192.0.2.2\n' > "$t/resolver/taken.example"
"$dns" start 2>/dev/null
grep -q '^nameserver 10.99.0.1$' "$t/resolver/lab.example" || fail "start did not write lab.example"
grep -q '^nameserver fd12::1$' "$t/resolver/v6.example" || fail "start did not write v6.example"
grep -q '192.0.2.2' "$t/resolver/taken.example" || fail "start replaced a file Priel did not write"
"$dns" set taken.example 10.99.0.2
[ ! -e "$t/resolver/taken.example" ] || fail "set left the hand-made taken.example"
"$dns" start
grep -q '^nameserver 10.99.0.2$' "$t/resolver/taken.example" || fail "start did not write taken.example"

# A list anyone could write is ignored.
chmod 666 "$t/priel/resolvers"
"$dns" stop
"$dns" start 2>/dev/null
[ ! -e "$t/resolver/taken.example" ] || fail "used a list writable by others"
chmod 644 "$t/priel/resolvers"

for bad in "../etc 10.0.0.1" "a/b 10.0.0.1" "ok.example 10.0.0.1;rm" ".lead 10.0.0.1" "odd"; do
	# shellcheck disable=SC2086
	if "$dns" set $bad 2>/dev/null; then fail "accepted \"$bad\""; fi
done

# An empty list removes every file Priel wrote.
"$dns" set
"$dns" stop
for f in "$t"/resolver/*; do
	[ "$f" = "$t/resolver/mine.example" ] || fail "$f left after an empty list"
done
[ -f "$t/resolver/mine.example" ] || fail "removed a file Priel did not write"
echo "priel-dns: ok"
