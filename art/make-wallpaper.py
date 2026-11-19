#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate freemac's original wallpapers ("Dusk Tide" and "Night Tide") as PNGs.

The images are computed from scratch (gradients and sine waves), so the
repository holds no binary artwork.

Usage: make-wallpaper.py [--night] OUT.png [W H]
"""
import math
import struct
import sys
import zlib


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(lerp(x, y, t) for x, y in zip(c1, c2))


PALETTES = {
    # top (deep indigo), middle (dusk blue), bottom (warm horizon), wave tints
    "dusk": ((28, 30, 74), (60, 92, 150), (226, 150, 120), (255, 255, 255), (250, 200, 170)),
    # the same scene after dark: near-black navy, slate, a low violet glow
    "night": ((8, 9, 24), (22, 30, 62), (88, 62, 112), (170, 180, 255), (150, 110, 190)),
}
PALETTE = PALETTES["dusk"]


def pixel(x, y, w, h):
    top, mid, bottom, tint1, tint2 = PALETTE
    v = y / (h - 1)
    base = mix(top, mid, v / 0.6) if v < 0.6 else mix(mid, bottom, (v - 0.6) / 0.4)
    # Two soft translucent waves across the lower half.
    u = x / (w - 1)
    for amp, freq, phase, centre, tint, alpha in (
        (0.05, 1.3, 0.4, 0.68, tint1, 0.10),
        (0.07, 0.9, 2.1, 0.80, tint2, 0.16),
    ):
        edge = centre + amp * math.sin(2 * math.pi * freq * u + phase)
        if v > edge:
            fade = min(1.0, (v - edge) * 12)
            base = mix(base, tint, alpha * fade)
    return bytes(int(max(0, min(255, c))) for c in base)


def main():
    global PALETTE
    args = sys.argv[1:]
    if args and args[0] == "--night":
        PALETTE = PALETTES["night"]
        args = args[1:]
    out = args[0]
    w, h = (int(args[1]), int(args[2])) if len(args) == 3 else (1920, 1080)
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        for x in range(w):
            rows += pixel(x, y, w, h)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")
    with open(out, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    main()
