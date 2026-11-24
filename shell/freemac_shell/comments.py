# SPDX-License-Identifier: GPL-3.0-or-later
"""Comments on files, as in a Mac's Get Info: a few words of your own about
a file or folder, which Seek also finds.

A comment is kept in the user.xdg.comment extended attribute, the
freedesktop.org name for it, so it moves with the file on the same disk and
other file managers can read it too. Original freemac code.
"""
import os

ATTR = "user.xdg.comment"
LONGEST = 2000   # characters kept


def get(path):
    try:
        return os.getxattr(path, ATTR, follow_symlinks=False).decode("utf-8", "replace")
    except OSError:
        return ""


def put(path, text):
    """Keep text as the comment, or take it off when empty; raises OSError
    when the disk can't keep it."""
    text = (text or "").strip()[:LONGEST]
    if text:
        if text != get(path):
            os.setxattr(path, ATTR, text.encode(), follow_symlinks=False)
        return
    try:
        os.removexattr(path, ATTR, follow_symlinks=False)
    except OSError as err:
        if err.errno not in (61, 95):   # none there, or none possible
            raise
