# Third-party code

**juist** (github.com/nning/juist), BSD-3-Clause, Copyright (c) 2026, henning mueller.
Priel.app carries `juist` and `juistd` built from juist's source with `mac/juist/macos.patch`
applied. `opnsense/tools/mkpkg` is juist's `packaging/freebsd/mkpkg`, changed in one line.
juist's license and its third-party licenses are in its repository at the version in
`mac/juist/VERSION`.

juist's own dependencies (WireGuard and Tailscale's `magicsock`, among others) are listed in
its `THIRD_PARTY_LICENSES`.
