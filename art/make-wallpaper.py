#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate freemac's original wallpapers as PNGs.

Every image is computed from scratch (gradients, sine waves and a seeded
random sprinkle of stars), so the repository holds no binary artwork. Each
scene has a day and a night version; Dials switches between them when the
light/dark mode changes.

Usage:
  make-wallpaper.py [--night] OUT.png [W H]          Tide (the original pair)
  make-wallpaper.py --scene NAME [--night] OUT.png [W H]
  make-wallpaper.py --all DIR [W H]                  every scene, both versions

Scenes: tide, lagoon, prism, harbor.
"""
import math
import os
import random
import struct
import sys
import zlib

# File names for each scene's day and night versions. Tide keeps its original
# names so existing settings still point at a real file.
FILES = {
    "tide": ("dusk-tide.png", "night-tide.png"),
    "lagoon": ("lagoon-day.png", "lagoon-night.png"),
    "prism": ("prism-day.png", "prism-night.png"),
    "harbor": ("harbor-day.png", "harbor-night.png"),
}


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(lerp(x, y, t) for x, y in zip(c1, c2))


def gradient(stops, t):
    """Colour at t (0..1) along [(pos, colour), ...]."""
    if t <= stops[0][0]:
        return stops[0][1]
    for (p1, c1), (p2, c2) in zip(stops, stops[1:]):
        if t <= p2:
            return mix(c1, c2, (t - p1) / (p2 - p1))
    return stops[-1][1]


# -- Tide: soft translucent waves under a dusk sky ---------------------------------
TIDE = {
    # top (deep indigo), middle (dusk blue), bottom (warm horizon), wave tints
    False: ((28, 30, 74), (60, 92, 150), (226, 150, 120), (255, 255, 255), (250, 200, 170)),
    # the same scene after dark: near-black navy, slate, a low violet glow
    True: ((8, 9, 24), (22, 30, 62), (88, 62, 112), (170, 180, 255), (150, 110, 190)),
}


def tide(w, h, night):
    top, mid, bottom, tint1, tint2 = TIDE[night]
    waves = ((0.05, 1.3, 0.4, 0.68, tint1, 0.10), (0.07, 0.9, 2.1, 0.80, tint2, 0.16))
    edges = [[c + a * math.sin(2 * math.pi * f * (x / (w - 1)) + p) for x in range(w)]
             for a, f, p, c, _t, _al in waves]
    for y in range(h):
        v = y / (h - 1)
        base = mix(top, mid, v / 0.6) if v < 0.6 else mix(mid, bottom, (v - 0.6) / 0.4)
        row = []
        for x in range(w):
            colour = base
            for (_a, _f, _p, _c, tint, alpha), edge in zip(waves, edges):
                e = edge[x]
                if v > e:
                    colour = mix(colour, tint, alpha * min(1.0, (v - e) * 12))
            row.append(colour)
        yield row


# -- Lagoon: rings of ripples spreading across clear water ------------------------
def lagoon(w, h, night):
    if night:
        stops = ((0.0, (4, 22, 38)), (0.55, (8, 52, 72)), (1.0, (18, 88, 104)))
        light, alpha = (120, 210, 220), 0.10
    else:
        stops = ((0.0, (186, 232, 226)), (0.5, (72, 178, 190)), (1.0, (24, 112, 146)))
        light, alpha = (255, 255, 255), 0.16
    centres = ((-0.15, 1.15, 26.0, 0.0), (1.05, 0.95, 34.0, 1.7))
    aspect = w / h
    for y in range(h):
        v = y / (h - 1)
        row = []
        for x in range(w):
            u = x / (w - 1)
            colour = gradient(stops, 0.65 * v + 0.35 * u)
            for cx, cy, freq, phase in centres:
                d = math.hypot((u - cx) * aspect, v - cy)
                ring = 0.5 + 0.5 * math.sin(d * freq + phase)
                ring = ring ** 6                       # thin bright crests
                fade = max(0.0, 1.0 - d / 1.6)
                colour = mix(colour, light, alpha * ring * fade)
            row.append(colour)
        yield row


# -- Prism: broad diagonal bands of light, softly blended -------------------------
def prism(w, h, night):
    if night:
        bands = ((0.0, (18, 16, 46)), (0.3, (46, 30, 92)), (0.55, (24, 58, 112)),
                 (0.8, (60, 34, 96)), (1.0, (14, 22, 52)))
        sheen = (200, 190, 255)
    else:
        bands = ((0.0, (255, 214, 170)), (0.3, (246, 160, 170)), (0.55, (172, 168, 238)),
                 (0.8, (138, 206, 236)), (1.0, (232, 240, 250)))
        sheen = (255, 255, 255)
    aspect = w / h
    for y in range(h):
        v = y / (h - 1)
        row = []
        for x in range(w):
            u = x / (w - 1)
            # Distance along a diagonal, bent by a slow wave so the bands curve.
            t = (u * aspect * 0.55 + v * 0.45) / (aspect * 0.55 + 0.45)
            t += 0.04 * math.sin(2 * math.pi * (v * 1.2 + u * 0.4))
            colour = gradient(bands, t)
            # Fine facets: a faint sheen along each band edge.
            facet = 0.5 + 0.5 * math.cos(2 * math.pi * t * 5)
            colour = mix(colour, sheen, 0.07 * facet ** 8)
            row.append(colour)
        yield row


# -- Harbor: a calm horizon, the sun or moon and its reflection on the water ----
def harbor(w, h, night):
    horizon = 0.62
    if night:
        sky = ((0.0, (6, 8, 26)), (0.7, (24, 28, 70)), (1.0, (64, 56, 110)))
        sea = ((0.0, (30, 32, 72)), (1.0, (6, 8, 22)))
        orb, orb_glow, orb_pos, orb_r = (236, 236, 255), (120, 130, 220), (0.70, 0.30), 0.035
    else:
        sky = ((0.0, (110, 160, 214)), (0.7, (214, 196, 214)), (1.0, (255, 196, 150)))
        sea = ((0.0, (230, 168, 140)), (1.0, (40, 86, 140)))
        orb, orb_glow, orb_pos, orb_r = (255, 246, 214), (255, 190, 140), (0.32, 0.52), 0.05
    aspect = w / h
    rng = random.Random(7)
    stars = set()
    if night:
        for _ in range(int(w * h / 2600)):
            sx, sy = rng.randrange(w), rng.randrange(int(h * horizon * 0.9))
            stars.add((sx, sy))
    ox, oy = orb_pos
    for y in range(h):
        v = y / (h - 1)
        row = []
        if v < horizon:
            base = gradient(sky, v / horizon)
            for x in range(w):
                u = x / (w - 1)
                d = math.hypot((u - ox) * aspect, v - oy)
                colour = mix(base, orb_glow, 0.55 * math.exp(-d * 6))
                if d < orb_r:
                    colour = mix(colour, orb, min(1.0, (orb_r - d) * 400))
                if (x, y) in stars:
                    colour = mix(colour, (255, 255, 255), 0.4 + 0.5 * rng.random())
                row.append(colour)
        else:
            depth = (v - horizon) / (1 - horizon)
            base = gradient(sea, depth)
            ripple_rows = 0.5 + 0.5 * math.sin(depth ** 0.5 * 260)
            for x in range(w):
                u = x / (w - 1)
                # The reflection: a column under the orb, broken into
                # horizontal glints that widen towards the viewer.
                spread = 0.02 + 0.10 * depth
                across = abs(u - ox) * aspect
                streak = math.exp(-(across / spread) ** 2) * ripple_rows
                glint = 0.5 + 0.5 * math.sin(u * 90 + depth * 40)
                colour = mix(base, orb_glow, 0.5 * streak * (0.6 + 0.4 * glint))
                colour = mix(colour, orb, 0.35 * streak * glint ** 4)
                # A soft line of light along the horizon.
                colour = mix(colour, orb_glow, 0.25 * math.exp(-depth * 40))
                row.append(colour)
        yield row


SCENES = {"tide": tide, "lagoon": lagoon, "prism": prism, "harbor": harbor}


def write_png(out, w, h, rows):
    raw = bytearray()
    for row in rows:
        raw.append(0)
        for colour in row:
            raw += bytes(int(max(0, min(255, round(c)))) for c in colour)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(out, "wb") as f:
        f.write(png)


def main():
    args = sys.argv[1:]
    scene, night, all_dir = "tide", False, None
    while args and args[0].startswith("--"):
        flag = args.pop(0)
        if flag == "--night":
            night = True
        elif flag == "--scene":
            scene = args.pop(0)
        elif flag == "--all":
            all_dir = args.pop(0)
        else:
            sys.exit(__doc__)
    w, h = (int(args[-2]), int(args[-1])) if len(args) >= 2 else (1920, 1080)
    if all_dir:
        os.makedirs(all_dir, exist_ok=True)
        for name, files in FILES.items():
            for is_night, filename in zip((False, True), files):
                write_png(os.path.join(all_dir, filename), w, h, SCENES[name](w, h, is_night))
        return
    if not args or scene not in SCENES:
        sys.exit(__doc__)
    write_png(args[0], w, h, SCENES[scene](w, h, night))


if __name__ == "__main__":
    main()
