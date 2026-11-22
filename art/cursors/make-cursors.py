#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Draw freemac's own pointer (mouse cursor) theme and write it as Xcursor
files, the format Wayland compositors and X apps read.

    python3 art/cursors/make-cursors.py OUTDIR
    make-cursors.py OUTDIR --fill '#RRGGBB' --outline '#RRGGBB' --name NAME

OUTDIR gets cursors/ (and an index.theme if it has none). With colours, the
pointer is drawn in them instead, as Dials > Accessibility > Pointer colour
asks (dials_pointer.py runs this from /usr/share/freemac), and OUTDIR is a
theme of its own called NAME that takes what it lacks from freemac's.
Every shape here is drawn from scratch:
a black arrow with a white edge and a soft shadow, a white pointing hand, an
I-beam, a ring of dots while something is busy, double arrows for resizing.
Shapes we don't draw come from Adwaita (index.theme inherits it).
"""
import os
import struct
import sys

import gi

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf  # noqa: E402

SIZES = (24, 32, 48, 64)   # nominal sizes; every shape is drawn on a 32-unit grid
SPIN_FRAMES = 10
SPIN_DELAY = 70            # ms per frame

SHADOW = ('<filter id="s" x="-30%" y="-30%" width="160%" height="160%">'
          '<feGaussianBlur stdDeviation="1.1"/><feOffset dy="1"/>'
          '<feComponentTransfer><feFuncA type="linear" slope="0.38"/></feComponentTransfer></filter>')


def svg(body, shadow=""):
    """A 32x32 picture: the shadow shape blurred underneath, then the body."""
    under = f'<g filter="url(#s)" fill="#000" stroke="#000" stroke-width="2.4" stroke-linejoin="round">{shadow}</g>' \
        if shadow else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">'
            f'<defs>{SHADOW}</defs>{under}{body}</svg>')


def edged(shape, fill="#000", edge="#fff", width=2.4):
    """A shape filled in one colour with an edge of the other around it."""
    return (f'<g fill="{edge}" stroke="{edge}" stroke-width="{width}" stroke-linejoin="round" '
            f'stroke-linecap="round">{shape}</g><g fill="{fill}">{shape}</g>')


# ---- the shapes (32-unit grid) -------------------------------------------------
ARROW = '<path d="M6 4 L6 26.6 L11.3 21.7 L14.9 29.6 L18.5 28 L15 20.4 L22.2 20.4 Z"/>'
HOTSPOT_ARROW = (6, 4)

HAND = ('<rect x="11" y="3" width="4.6" height="17" rx="2.3"/>'
        '<rect x="15.1" y="10.6" width="4.4" height="10" rx="2.2"/>'
        '<rect x="19" y="11.8" width="4.2" height="9" rx="2.1"/>'
        '<rect x="22.7" y="13.4" width="3.9" height="8" rx="1.95"/>'
        '<rect x="11" y="16.5" width="15.6" height="9.5" rx="4"/>'
        '<rect x="12.6" y="22" width="12.2" height="7.4" rx="3"/>'
        '<rect x="4.8" y="15.2" width="9.6" height="4.6" rx="2.3" transform="rotate(42 9.6 17.5)"/>')
HAND_LINES = ('<g stroke="#000" stroke-width="0.9" stroke-linecap="round">'
              '<path d="M15.3 14.8 V19.2 M19.2 15.8 V19.6 M22.9 17 V20.2"/></g>')
HOTSPOT_HAND = (13, 3)

IBEAM = ('<path d="M11.6 6 H14.4 Q16 6 16 7.4 Q16 6 17.6 6 H20.4 V7.8 H18 Q16.9 7.8 16.9 8.9 V23.1 '
         'Q16.9 24.2 18 24.2 H20.4 V26 H17.6 Q16 26 16 24.6 Q16 26 14.4 26 H11.6 V24.2 H14 '
         'Q15.1 24.2 15.1 23.1 V8.9 Q15.1 7.8 14 7.8 H11.6 Z"/>')

DOUBLE = '<path d="M4.5 16 L10.5 10 V13.8 H21.5 V10 L27.5 16 L21.5 22 V18.2 H10.5 V22 Z"/>'
FOUR = ('<path d="M16 3.5 L21 8.5 H17.6 V14.4 H23.5 V11 L28.5 16 L23.5 21 V17.6 H17.6 V23.5 H21 L16 28.5 '
        'L11 23.5 H14.4 V17.6 H8.5 V21 L3.5 16 L8.5 11 V14.4 H14.4 V8.5 H11 Z"/>')
CROSS = '<path d="M16 5 V13 M16 19 V27 M5 16 H13 M19 16 H27" fill="none"/>'
FORBIDDEN = ('<circle cx="16" cy="16" r="8.5" fill="none" stroke-width="3"/>'
             '<path d="M10 22 L22 10" fill="none" stroke-width="3"/>')


def spinner(frame, cx=16.0, cy=16.0, r=6.6, dot=2.1):
    """A ring of dots, the brightest one moving round: freemac's busy sign."""
    import math
    out = []
    for i in range(SPIN_FRAMES):
        angle = 2 * math.pi * i / SPIN_FRAMES - math.pi / 2
        x, y = cx + r * math.cos(angle), cy + r * math.sin(angle)
        age = (frame - i) % SPIN_FRAMES
        shade = 0.18 + 0.82 * (1 - age / SPIN_FRAMES)
        out.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{dot + 0.9:.2f}" fill="#fff" fill-opacity="0.95"/>')
        out.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{dot:.2f}" fill="#2b2f36" fill-opacity="{shade:.2f}"/>')
    return "".join(out)


def rotated(shape, degrees):
    return f'<g transform="rotate({degrees} 16 16)">{shape}</g>'


def lines(shape, edge_width=3.6, width=1.6, fill="#000", edge="#fff"):
    return (f'<g stroke="{edge}" stroke-width="{edge_width}" stroke-linecap="round" fill="none">{shape}</g>'
            f'<g stroke="{fill}" stroke-width="{width}" stroke-linecap="round" fill="none">{shape}</g>')


# name -> (frames as a list of svg strings, hotspot on the 32 grid, other names)
def shapes(fill="#000", edge="#fff"):
    """Every pointer, drawn in `fill` with an `edge` round it (the hand the
    other way round, as it's white with a black edge)."""
    arrow = svg(edged(ARROW, fill, edge), ARROW)
    hand = svg(edged(HAND, fill=edge, edge=fill, width=2.0) + HAND_LINES.replace("#000", fill), HAND)
    resize = {}
    for name, degrees, aliases in (
            ("ew-resize", 0, ["e-resize", "w-resize", "col-resize", "h_double_arrow", "sb_h_double_arrow",
                              "left_side", "right_side", "size_hor", "split_h"]),
            ("ns-resize", 90, ["n-resize", "s-resize", "row-resize", "v_double_arrow", "sb_v_double_arrow",
                               "top_side", "bottom_side", "size_ver", "split_v", "double_arrow"]),
            ("nwse-resize", 45, ["nw-resize", "se-resize", "top_left_corner", "bottom_right_corner", "size_fdiag"]),
            ("nesw-resize", -45, ["ne-resize", "sw-resize", "top_right_corner", "bottom_left_corner", "size_bdiag"])):
        shape = rotated(DOUBLE, degrees)
        resize[name] = ([svg(edged(shape, fill, edge, width=2.2), shape)], (16, 16), aliases)
    out = {
        "default": ([arrow], HOTSPOT_ARROW, ["left_ptr", "arrow", "top_left_arrow", "context-menu",
                                             "dnd-move", "dnd-copy", "dnd-none", "dnd-link", "dnd-ask"]),
        "pointer": ([hand], HOTSPOT_HAND, ["hand", "hand1", "hand2", "pointing_hand",
                                           "9d800788f1b08800ae810202380a0822", "e29285e634086352946a0e7090d73106"]),
        "text": ([svg(edged(IBEAM, fill, edge, width=2.0), IBEAM)], (16, 16), ["xterm", "ibeam"]),
        "wait": ([svg(spinner(f)) for f in range(SPIN_FRAMES)], (16, 16), ["watch"]),
        "progress": ([svg(edged(ARROW, fill, edge) + spinner(f, 23.5, 23.5, 4.4, 1.35), ARROW) for f in range(SPIN_FRAMES)],
                     HOTSPOT_ARROW, ["left_ptr_watch", "half-busy", "3ecb610c1bf2410f44200f48c40d3599",
                                     "08e8e1c95fe2fc01f976f1e063a24ccd"]),
        "move": ([svg(edged(FOUR, fill, edge, width=2.2), FOUR)], (16, 16), ["all-scroll", "fleur", "size_all"]),
        "crosshair": ([svg(lines(CROSS, fill=fill, edge=edge))], (16, 16), ["cross", "tcross"]),
        "not-allowed": ([svg(lines(FORBIDDEN, 5.2, 3.0, fill, edge))], (16, 16),
                        ["no-drop", "crossed_circle", "forbidden", "circle"]),
    }
    out.update(resize)
    return out


# ---- Xcursor --------------------------------------------------------------------
def render(svg_text, size):
    loader = GdkPixbuf.PixbufLoader.new_with_type("svg")
    loader.set_size(size, size)
    loader.write(svg_text.encode())
    loader.close()
    pix = loader.get_pixbuf()
    if not pix.get_has_alpha():
        pix = pix.add_alpha(False, 0, 0, 0)
    data, stride, n = pix.get_pixels(), pix.get_rowstride(), pix.get_n_channels()
    pixels = []
    for y in range(size):
        row = data[y * stride:y * stride + size * n]
        for x in range(size):
            r, g, b, a = row[x * n:x * n + 4]
            # Xcursor wants premultiplied ARGB.
            pixels.append((a << 24) | ((r * a // 255) << 16) | ((g * a // 255) << 8) | (b * a // 255))
    return pixels


def xcursor(frames, hotspot, delay):
    images = []
    for size in SIZES:
        hx = min(size - 1, round(hotspot[0] * size / 32))
        hy = min(size - 1, round(hotspot[1] * size / 32))
        for frame in frames:
            pixels = render(frame, size)
            chunk = struct.pack("<9I", 36, 0xfffd0002, size, 1, size, size, hx, hy, delay)
            images.append((size, chunk + struct.pack(f"<{len(pixels)}I", *pixels)))
    header = struct.pack("<4sIII", b"Xcur", 16, 0x10000, len(images))
    position = 16 + 12 * len(images)
    toc, body = b"", b""
    for size, chunk in images:
        toc += struct.pack("<III", 0xfffd0002, size, position)
        position += len(chunk)
        body += chunk
    return header + toc + body


INDEX = """[Icon Theme]
Name=freemac
Comment=freemac's own pointer: a black arrow with a white edge
Inherits=Adwaita
"""


CUSTOM_INDEX = """[Icon Theme]
Name={name}
Comment=freemac's pointer in colours of your own
Inherits=freemac,Adwaita
"""


def colour(text):
    """'#RRGGBB' (or #RGB) checked, for the SVG."""
    text = (text or "").strip()
    digits = text[1:] if text.startswith("#") else ""
    if len(digits) in (3, 6) and all(c in "0123456789abcdefABCDEF" for c in digits):
        return "#" + digits.lower()
    raise SystemExit(f"make-cursors: not a colour: {text!r} (use #RRGGBB)")


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    options = {"--fill": None, "--outline": None, "--name": None}
    rest = []
    while args:
        arg = args.pop(0)
        if arg in options and args:
            options[arg] = args.pop(0)
        else:
            rest.append(arg)
    out = rest[0] if rest else "freemac-cursors"
    fill = colour(options["--fill"]) if options["--fill"] else "#000"
    edge = colour(options["--outline"]) if options["--outline"] else "#fff"
    cursors = os.path.join(out, "cursors")
    os.makedirs(cursors, exist_ok=True)
    index = os.path.join(out, "index.theme")
    if options["--name"]:
        with open(index, "w") as f:
            f.write(CUSTOM_INDEX.format(name=options["--name"]))
    elif not os.path.exists(index):  # an icon theme of the same name already inherits Adwaita
        with open(index, "w") as f:
            f.write(INDEX)
    for name, (frames, hotspot, aliases) in shapes(fill, edge).items():
        with open(os.path.join(cursors, name), "wb") as f:
            f.write(xcursor(frames, hotspot, SPIN_DELAY if len(frames) > 1 else 0))
        for alias in aliases:
            path = os.path.join(cursors, alias)
            if os.path.lexists(path):
                os.remove(path)
            os.symlink(name, path)


if __name__ == "__main__":
    main()
