# SPDX-License-Identifier: GPL-3.0-or-later
"""Text input, as on a Mac, in the apps where you write (the same ones that
check spelling): Text Replacements ("omw" becomes "On my way!" when you type
a space after it), smart quotes and dashes (“ ” ‘ ’ and — for two hyphens),
and a full stop when you press the space bar twice. Dials > Keyboard > Text
Input sets each one; the replacements live in
~/.config/freemac/text-replacements.json. Only what you type is changed,
one key at a time: pasted text is left as it is. Original freemac code."""
import json
import os

from gi.repository import GLib

from . import style

REPLACEMENTS = os.path.expanduser("~/.config/freemac/text-replacements.json")
DEFAULT_REPLACEMENTS = [["omw", "On my way!"]]
BOUNDARY = set(" \t\n.,!?;:)")
OPENERS = set(" \t\n([{<—–-/")

_cache = {"mtime": None, "items": DEFAULT_REPLACEMENTS}


def replacements():
    """[[replace, with], ...], as the person set them in Dials."""
    try:
        mtime = os.stat(REPLACEMENTS).st_mtime
    except OSError:
        return list(DEFAULT_REPLACEMENTS)
    if mtime != _cache["mtime"]:
        try:
            with open(REPLACEMENTS, encoding="utf-8") as f:
                items = json.load(f)
            items = [[str(a), str(b)] for a, b in items if str(a).strip() and str(b)]
        except (OSError, ValueError, TypeError):
            items = list(DEFAULT_REPLACEMENTS)
        _cache.update(mtime=mtime, items=items)
    return _cache["items"]


def save_replacements(items):
    os.makedirs(os.path.dirname(REPLACEMENTS), exist_ok=True)
    tmp = REPLACEMENTS + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump([[a, b] for a, b in items if a.strip() and b], f, indent=2, ensure_ascii=False)
    os.replace(tmp, REPLACEMENTS)


def options():
    p = style.prefs()
    return {"replace": p.get("text_replacements", True), "quotes": p.get("smart_quotes", True),
            "period": p.get("double_space_period", True)}


def change(before, typed, wanted=None):
    """What typing `typed` after `before` should become, as (how many
    characters to take back from the end of before + typed, what to put
    there), or None to leave it. Kept apart from GTK so it can be tested."""
    wanted = wanted or options()
    prev = before[-1:] if before else ""
    if wanted["quotes"] and typed in "\"'":
        opening = prev == "" or prev in OPENERS or prev in "“‘"
        if typed == '"':
            return 1, "“" if opening else "”"
        return 1, "‘" if opening else "’"
    if wanted["quotes"] and typed == "-" and prev == "-" and before[-2:-1] not in ("-", "<", "!"):
        return 2, "—"
    if wanted["period"] and typed == " " and prev == " " and before[-2:-1].isalnum():
        return 2, ". "
    if wanted["replace"] and typed in BOUNDARY:
        start = len(before)
        while start > 0 and not before[start - 1].isspace():
            start -= 1
        word = before[start:]
        for short, full in replacements():
            if word == short:
                return len(word) + 1, full + typed
    return None


def attach(view):
    """Watch what is typed into this Gtk.TextView."""
    buffer = view.get_buffer()
    if getattr(buffer, "_freemac_textinput", False):
        return
    buffer._freemac_textinput = True
    busy = {"on": False}

    def inserted(buf, where, text, _length):
        if busy["on"] or len(text) != 1 or not getattr(view, "_freemac_prose", True) or not view.has_focus():
            return
        start = where.copy()
        start.backward_chars(41)   # enough for a replacement's short form
        line_start = where.copy()
        line_start.set_line_offset(0)
        if start.compare(line_start) < 0:
            start = line_start
        end_of_typed = where.copy()
        before_iter = where.copy()
        before_iter.backward_char()
        before = buf.get_text(start, before_iter, True)
        result = change(before, text)
        if result is None:
            return
        back, new = result
        mark = buf.create_mark(None, end_of_typed, False)

        def apply():
            busy["on"] = True
            try:
                end = buf.get_iter_at_mark(mark)
                begin = end.copy()
                begin.backward_chars(back)
                if buf.get_text(begin, end, True)[-1:] == text:
                    buf.begin_user_action()
                    buf.delete(begin, end)
                    buf.insert(begin, new)
                    buf.end_user_action()
            finally:
                busy["on"] = False
                buf.delete_mark(mark)
            return False

        GLib.idle_add(apply, priority=GLib.PRIORITY_HIGH_IDLE)

    buffer.connect_after("insert-text", inserted)
