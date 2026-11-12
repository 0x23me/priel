#!/usr/bin/env python3
"""Saves juistd's raw status answer as a test fixture.

    capture-status.py NAME [--figures] [--socket PATH]

Writes Tests/JuistKitTests/Fixtures/NAME.cbor: the CBOR response without its
length prefix, exactly as the app receives it. Run it as the user whose view
the fixture is meant to hold: as the operator for the full status, as another
user (sudo -u nobody) for the reader's.
"""
import argparse
import os
import socket
import struct

here = os.path.dirname(os.path.abspath(__file__))
p = argparse.ArgumentParser()
p.add_argument("name")
p.add_argument("--figures", action="store_true", help="ask for the patch's per-peer figures")
p.add_argument("--socket", default="/var/run/juist/juistd.sock")
p.add_argument("--out", default=os.path.join(here, "..", "Tests", "JuistKitTests", "Fixtures"))
a = p.parse_args()

# The canonical encoding juistd insists on: CmdStatus (1: 1) and the two
# identity fields (15, 31), which are written even when zero; 100: true asks
# for the figures.
zero = bytes([0x58, 0x20]) + bytes(32)
req = bytes([0xA4 if a.figures else 0xA3, 0x01, 0x01, 0x0F]) + zero + bytes([0x18, 0x1F]) + zero
if a.figures:
    req += bytes([0x18, 0x64, 0xF5])
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(5)
s.connect(a.socket)
s.sendall(struct.pack(">I", len(req)) + req)


def read(n):
    b = b""
    while len(b) < n:
        chunk = s.recv(n - len(b))
        if not chunk:
            raise SystemExit("juistd closed the connection")
        b += chunk
    return b


(n,) = struct.unpack(">I", read(4))
body = read(n)
path = os.path.join(a.out, a.name + ".cbor")
with open(path, "wb") as f:
    f.write(body)
print(f"{path}: {len(body)} bytes")
