#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fill in build/release-notes.md for a release.

  release-notes.py VERSION SIZE_MB SHA256 > notes.md

@WHATSNEW@ becomes the version's items from docs/ROADMAP.md, between the
markers that Dials > Software Update reads. Original freemac code.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import whats_new  # noqa: E402

version, size, checksum = sys.argv[1:4]
with open(os.path.join(HERE, "..", "build", "release-notes.md"), encoding="utf-8") as f:
    text = f.read()
items = "\n".join("- " + item for item in whats_new.items(version)) or "- Fixes and improvements."
text = text.replace("@WHATSNEW@", items)
text = text.replace("@VERSION@", version).replace("@SIZE@", size).replace("@SHA256@", checksum)
sys.stdout.write(text)
