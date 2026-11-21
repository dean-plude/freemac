# SPDX-License-Identifier: GPL-3.0-or-later
"""Check spelling while typing, as on a Mac: misspelled words get a red
underline in the apps where you write (Jot, Post, Stickies, Quill's plain
text, the notes in Tide, Nudge, Crew and Corkboard), and a right-click on one
offers corrections, Ignore All and Add to Dictionary. It is gspell over
Enchant and Hunspell's dictionaries; Dials > Keyboard turns it off for
everyone (check_spelling in shell.json). Without gspell the apps work as
before. Original freemac code."""
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

from . import style, textinput  # noqa: E402

try:
    gi.require_version("Gspell", "1")
    from gi.repository import Gspell  # noqa: E402
except (ImportError, ValueError):
    Gspell = None

_views = []   # kept until each view is destroyed
_watch = None


def available():
    return Gspell is not None


def wanted():
    return bool(style.prefs().get("check_spelling", True))


def _refresh():
    on = wanted()
    for view in list(_views):
        _apply(view, on)


def _apply(view, on):
    on = on and getattr(view, "_freemac_prose", True) and view.get_editable()
    Gspell.TextView.get_from_gtk_text_view(view).set_inline_spell_checking(on)


def attach(view):
    """Underline misspelled words in this Gtk.TextView (or GtkSource.View)."""
    global _watch
    textinput.attach(view)   # Text Replacements, smart quotes, double-space full stop
    if Gspell is None or view in _views:
        return
    gview = Gspell.TextView.get_from_gtk_text_view(view)
    gview.basic_setup()   # a checker in the default language, and the Languages menu
    gview.set_enable_language_menu(True)
    _views.append(view)
    view.connect("destroy", lambda v: v in _views and _views.remove(v))
    view.connect("notify::editable", lambda v, _p: _apply(v, wanted()))
    view.connect_after("populate-popup", _mac_menu)
    if _watch is None:
        _watch = style.watch_prefs(_refresh)
    _apply(view, wanted())


def allow(view, allowed):
    """For Quill: spelling and smart text input only in prose (plain text,
    Markdown), not code."""
    view._freemac_prose = allowed
    if Gspell is not None and view in _views:
        _apply(view, wanted())


# gspell's own words, which we change to a Mac's.
RENAME = {"_Ignore All": "Ignore Spelling", "_Add": "Learn Spelling", "_Language": "Spelling Language"}


def _mac_menu(_view, popup):
    """As on a Mac, the suggestions for a misspelled word are at the top of
    its right-click menu, not in a Spelling Suggestions submenu, followed by
    Ignore Spelling and Learn Spelling."""
    if not isinstance(popup, Gtk.Menu):
        return
    for item in popup.get_children():
        if isinstance(item, Gtk.MenuItem) and item.get_label() in RENAME:
            item.set_label(RENAME[item.get_label()])
    for item in popup.get_children():
        sub = item.get_submenu() if isinstance(item, Gtk.MenuItem) else None
        if sub is None or "Spelling Suggestions" not in (item.get_label() or ""):
            continue
        place = popup.get_children().index(item)
        for kid in sub.get_children():
            if isinstance(kid, Gtk.MenuItem) and kid.get_label() in RENAME:
                kid.set_label(RENAME[kid.get_label()])
            sub.remove(kid)
            popup.insert(kid, place)
            place += 1
        separator = Gtk.SeparatorMenuItem()
        separator.show()
        popup.insert(separator, place)
        popup.remove(item)
        break
