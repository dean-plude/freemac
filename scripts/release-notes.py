#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fill in build/release-notes.md for a release.

  release-notes.py VERSION SIZE_MB SHA256 [FERRY_DEB] > notes.md

@WHATSNEW@ becomes the version's items from docs/ROADMAP.md, between the
markers that Dials > Software Update reads. @FERRY@ becomes a line about
Ferry's package when its file name is given, and nothing otherwise.
Original freemac code.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import whats_new  # noqa: E402

version, size, checksum = sys.argv[1:4]
ferry = sys.argv[4] if len(sys.argv) > 4 else ""
with open(os.path.join(HERE, "..", "build", "release-notes.md"), encoding="utf-8") as f:
    text = f.read()
items = "\n".join("- " + item for item in whats_new.items(version)) or "- Fixes and improvements."
text = text.replace("@WHATSNEW@", items)
ferry_line = ""
if ferry:
    ferry_line = ("- **%s**: Ferry, freemac's own runner for Intel Mac apps, on its own. The ISO already has "
                  "it; this package is for other Ubuntu computers. App Store apps don't run.\n" % ferry)
text = text.replace("@FERRY@\n", ferry_line)
text = text.replace("@VERSION@", version).replace("@SIZE@", size).replace("@SHA256@", checksum)
sys.stdout.write(text)
