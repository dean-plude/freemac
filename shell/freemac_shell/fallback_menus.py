# SPDX-License-Identifier: GPL-3.0-or-later
"""Menus for apps that publish none, so every app has a menu bar, as on a Mac.

Firefox, VLC, Qt apps and older programs don't hand their menus to the menu
bar. For them Topline shows File, Edit and View menus anyway, whose items
press the app's own shortcuts (New Tab presses Ctrl+T in Firefox, which
⌘T does too). Every app gets the usual Edit menu; a few well-known apps get
their usual menus from the short list here. Original freemac code.
"""
import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

PRESS = "topline.press"
CLOSE = "topline.close-window"
CLOSE_NO_KEY = "close-window, no shortcut"   # where ⌘W already means Close Tab

# (label, shortcut it presses), with None between groups.
EDIT = ("Edit", [
    ("Undo", "<Primary>z"), ("Redo", "<Primary><Shift>z"), None,
    ("Cut", "<Primary>x"), ("Copy", "<Primary>c"), ("Paste", "<Primary>v"),
    ("Select All", "<Primary>a"), None,
    ("Find…", "<Primary>f"),
])
FILE = ("File", [("Close Window", CLOSE)])


def _browser(private, history, close_window):
    """A web browser's menus; browsers differ only in a few keys."""
    return [
        ("File", [
            ("New Tab", "<Primary>t"), ("New Window", "<Primary>n"),
            ("New Private Window", private), None,
            ("Open File…", "<Primary>o"), ("Open Location…", "<Primary>l"), None,
            ("Close Tab", "<Primary>w"), ("Close Window", close_window), None,
            ("Save Page As…", "<Primary>s"), ("Print…", "<Primary>p"),
        ]),
        ("Edit", EDIT[1] + [("Find Again", "<Primary>g")]),
        ("View", [
            ("Reload Page", "<Primary>r"), None,
            ("Zoom In", "<Primary>plus"), ("Zoom Out", "<Primary>minus"), ("Actual Size", "<Primary>0"),
            None, ("Enter Full Screen", "F11"),
        ]),
        ("History", [
            ("Back", "<Alt>Left"), ("Forward", "<Alt>Right"), ("Home", "<Alt>Home"), None,
            ("Reopen Closed Tab", "<Primary><Shift>t"), ("Show All History", history),
        ]),
        ("Bookmarks", [
            ("Bookmark This Page", "<Primary>d"), ("Show All Bookmarks", "<Primary><Shift>o"),
        ]),
    ]


FIREFOX = _browser("<Primary><Shift>p", "<Primary><Shift>h", "<Primary><Shift>w")
WEB = _browser("<Primary><Shift>n", "<Primary>h", CLOSE_NO_KEY)

KNOWN = {
    "firefox": FIREFOX,
    "org.mozilla.firefox": FIREFOX,
    "firefox-esr": FIREFOX,
    "org.gnome.epiphany": WEB,
    "vlc": [
        ("File", [("Open File…", "<Primary>o"), ("Open Network Stream…", "<Primary>n"), None,
                  ("Close Window", CLOSE)]),
        EDIT,
        ("Playback", [("Play or Pause", "space"), ("Stop", "s"), None,
                      ("Next", "n"), ("Previous", "p")]),
        ("View", [("Enter Full Screen", "f")]),
    ],
}


def menubar_for(app_id):
    """A menu bar model for an app that publishes none."""
    spec = KNOWN.get((app_id or "").lower(), [FILE, EDIT])
    bar = Gio.Menu()
    for title, entries in spec:
        menu, section = Gio.Menu(), Gio.Menu()
        for entry in entries:
            if entry is None:
                menu.append_section(None, section)
                section = Gio.Menu()
                continue
            label, keys = entry
            item = Gio.MenuItem.new(label, None)
            if keys in (CLOSE, CLOSE_NO_KEY):
                item.set_action_and_target_value(CLOSE, None)
                if keys == CLOSE:
                    item.set_attribute_value("accel", GLib.Variant("s", "<Primary>w"))
            else:
                item.set_action_and_target_value(PRESS, GLib.Variant("s", keys))
                item.set_attribute_value("accel", GLib.Variant("s", keys))
            section.append_item(item)
        menu.append_section(None, section)
        bar.append_submenu(title, menu)
    return bar
