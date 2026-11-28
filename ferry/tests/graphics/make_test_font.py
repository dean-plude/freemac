# SPDX-License-Identifier: GPL-3.0-or-later
# Writes test_font.h: a small TrueType font of Ferry's own, "Ferry Test Glyphs",
# made of squares, as a C array, for tests that load a font from data that
# isn't installed (freemac 1.NEXT, Neovide). Run it again to change the font:
#   python3 make_test_font.py > test_font.h
import struct, sys

FAMILY = "Ferry Test Glyphs"
PSNAME = "FerryTestGlyphs-Regular"
UPM = 1000
# .notdef, then a square for each of these characters
CHARS = "AB~"


def checksum(data):
    data += b"\0" * (-len(data) % 4)
    return sum(struct.unpack(">%dI" % (len(data) // 4), data)) & 0xFFFFFFFF


def square(inset):
    lo, hi = 100 + inset, 600 - inset
    pts = [(lo, lo), (lo, hi), (hi, hi), (hi, lo)]
    flags = bytes([0x01] * 4)  # on-curve, two-byte coordinates
    xs = b"".join(struct.pack(">h", x - px) for (x, _), (px, _) in zip(pts, [(0, 0)] + pts[:-1]))
    ys = b"".join(struct.pack(">h", y - py) for (_, y), (_, py) in zip(pts, [(0, 0)] + pts[:-1]))
    return struct.pack(">hhhhh", 1, lo, lo, hi, hi) + struct.pack(">H", 3) + struct.pack(">H", 0) + flags + xs + ys


glyphs = [square(0)] + [square(20 * (i + 1)) for i in range(len(CHARS))]
glyf = b""
offsets = []
for g in glyphs:
    offsets.append(len(glyf))
    glyf += g + b"\0" * (-len(g) % 4)
offsets.append(len(glyf))
n = len(glyphs)

head = struct.pack(">IIIIHHqqhhhhHHhhh", 0x00010000, 0x00010000, 0, 0x5F0F3CF5, 0x000B, UPM, 0, 0,
                   100, 100, 600, 600, 0, 8, 2, 1, 0)
hhea = struct.pack(">IhhhHhhhhhhhhhhhH", 0x00010000, 800, -200, 0, 700, 100, 100, 600, 1, 0, 0, 0, 0, 0, 0, 0, n)
hmtx = b"".join(struct.pack(">Hh", 700, 100) for _ in range(n))
maxp = struct.pack(">IHHHHHHHHHHHHHH", 0x00010000, n, 4, 1, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0)
loca = b"".join(struct.pack(">I", o) for o in offsets)

# cmap: format 4, one segment per character, then the end segment
codes = sorted(ord(c) for c in CHARS)
segs = [(c, c, CHARS.index(chr(c)) + 1 - c) for c in codes] + [(0xFFFF, 0xFFFF, 1)]
sc = len(segs)
sr = 2 * (1 << (sc.bit_length() - 1))
body = struct.pack(">HHHH", 2 * sc, sr, (sc.bit_length() - 1), 2 * sc - sr)
body += b"".join(struct.pack(">H", e) for _, e, _ in segs) + b"\0\0"
body += b"".join(struct.pack(">H", s) for s, _, _ in segs)
body += b"".join(struct.pack(">h", ((d + 0x8000) & 0xFFFF) - 0x8000) for _, _, d in segs)
body += b"".join(struct.pack(">H", 0) for _ in segs)
sub = struct.pack(">HHH", 4, 6 + len(body), 0) + body
cmap = struct.pack(">HHHHI", 0, 1, 3, 1, 12) + sub

names = {1: FAMILY, 2: "Regular", 3: PSNAME, 4: FAMILY + " Regular", 5: "Version 1.0", 6: PSNAME}
recs, strs = b"", b""
for nid, text in sorted(names.items()):
    s = text.encode("utf-16-be")
    recs += struct.pack(">HHHHHH", 3, 1, 0x409, nid, len(s), len(strs))
    strs += s
name = struct.pack(">HHH", 0, len(names), 6 + len(recs)) + recs + strs

post = struct.pack(">IIhhIIIII", 0x00030000, 0, -100, 50, 1, 0, 0, 0, 0)
os2 = struct.pack(">HhHHHhhhhhhhhhhh10sIIII4sHHHhhhHH", 1, 700, 400, 5, 0, 650, 600, 0, 75, 650, 600, 0, 350,
                  50, 300, 0, b"\0" * 10, 0, 0, 0, 0, b"FRRY", 0x40, min(codes), max(codes), 800, -200, 0, 800, 200)
os2 += struct.pack(">II", 1, 0)

tables = {b"OS/2": os2, b"cmap": cmap, b"glyf": glyf, b"head": head, b"hhea": hhea, b"hmtx": hmtx,
          b"loca": loca, b"maxp": maxp, b"name": name, b"post": post}
tags = sorted(tables)
nt = len(tags)
es = nt.bit_length() - 1
out = struct.pack(">IHHHH", 0x00010000, nt, 16 * (1 << es), es, 16 * nt - 16 * (1 << es))
offset = 12 + 16 * nt
data = b""
for t in tags:
    tb = tables[t]
    out += struct.pack(">4sIII", t, checksum(tb), offset + len(data), len(tb))
    data += tb + b"\0" * (-len(tb) % 4)
font = bytearray(out + data)
# head's checkSumAdjustment
hoff = offset + sum(len(tables[t]) + (-len(tables[t]) % 4) for t in tags[:tags.index(b"head")])
struct.pack_into(">I", font, hoff + 8, (0xB1B0AFBA - checksum(bytes(font))) & 0xFFFFFFFF)

w = sys.stdout.write
w("/* SPDX-License-Identifier: GPL-3.0-or-later\n * Made by make_test_font.py: %s, %d glyphs, "
  "squares for %s. */\n" % (FAMILY, n, " ".join(CHARS)))
w("static const unsigned char test_font[%d] = {\n" % len(font))
for i in range(0, len(font), 16):
    w("    " + ", ".join("0x%02x" % b for b in font[i:i + 16]) + ",\n")
w("};\n")
