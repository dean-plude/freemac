#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Render the boot screen's pictures for the freemac Plymouth theme: the
white mark (boot-mark.svg), the progress bar's track and fill, and the
password field and its dots for unlocking an encrypted disk.

    python3 art/plymouth/make-boot-art.py OUTDIR
"""
import os
import sys

import gi

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
BAR = ('<svg xmlns="http://www.w3.org/2000/svg" width="200" height="6">'
       '<rect width="200" height="6" rx="3" fill="#fff" fill-opacity="{a}"/></svg>')

FIELD = ('<svg xmlns="http://www.w3.org/2000/svg" width="240" height="34">'
         '<rect x="0.5" y="0.5" width="239" height="33" rx="16.5" fill="#fff" fill-opacity="0.14" '
         'stroke="#fff" stroke-opacity="0.35"/></svg>')
DOT = '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><circle cx="4" cy="4" r="4" fill="#fff"/></svg>'


def render(svg_bytes, out, w, h):
    loader = GdkPixbuf.PixbufLoader.new_with_type("svg")
    loader.set_size(w, h)
    loader.write(svg_bytes)
    loader.close()
    loader.get_pixbuf().savev(out, "png", [], [])


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(HERE, "boot-mark.svg"), "rb") as f:
        render(f.read(), os.path.join(out, "mark.png"), 112, 112)
    render(BAR.format(a="0.22").encode(), os.path.join(out, "track.png"), 200, 6)
    render(BAR.format(a="1").encode(), os.path.join(out, "fill.png"), 200, 6)
    render(FIELD.encode(), os.path.join(out, "field.png"), 240, 34)
    render(DOT.encode(), os.path.join(out, "dot.png"), 8, 8)


if __name__ == "__main__":
    main()
