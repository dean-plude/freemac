#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""What a version added, from its section of docs/ROADMAP.md: one line per
item, as the release notes and Dials > Software Update show it.

  whats_new.py VERSION     print the items as a Markdown list

Original freemac code.
"""
import os
import re
import sys

ROADMAP = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "ROADMAP.md")


def items(version, roadmap=ROADMAP):
    """The Item column of the table under '## 1.NNN "name"' for VERSION 1.NNN.x."""
    minor = ".".join(str(version).lstrip("v").split(".")[:2])
    found, inside = [], False
    try:
        with open(roadmap, encoding="utf-8") as f:
            lines = f.readlines()
    except OSError:
        return []
    for line in lines:
        if line.startswith("## "):
            if inside:
                break
            inside = re.match(r"## " + re.escape(minor) + r"\b", line) is not None
            continue
        if not inside or not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2 or not cells[0].isdigit():
            continue
        text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", cells[1]).replace("`", "")
        if text and not text.startswith("freemac"):     # freemac stays lower case
            text = text[0].upper() + text[1:]
        found.append(text)
    return found


if __name__ == "__main__":
    for item in items(sys.argv[1] if len(sys.argv) > 1 else open(os.path.join(os.path.dirname(ROADMAP), "..", "VERSION")).read().strip()):
        print("- " + item)
