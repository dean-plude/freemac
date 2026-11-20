# SPDX-License-Identifier: GPL-3.0-or-later
"""Shared look for freemac's shell (original styling)."""
import json
import os

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gtk  # noqa: E402

from gi.repository import Gio  # noqa: E402

# Colours are freemac's own: a pale frosted glass in light mode and a smoky
# glass in dark mode (Strata blurs what's behind the menu bar), with a blue accent.
TEMPLATE = """
.topline { background-color: @bar; color: @ink; }
.topline button { background: none; border: none; box-shadow: none; padding: 0 9px; min-height: 24px; color: @ink; }
.topline button:hover, .topline button:checked { background-color: @hover; border-radius: 6px; }
.topline label { color: @ink; }
.topline .app-name { font-weight: 700; }
.topline .app-name menu, .topline .app-name menu label { font-weight: 400; }
.topline menu label.dim-label { opacity: 0.55; }
.topline menuitem:hover > label, .topline menuitem:hover > box label { color: white; }
/* Items that can't be chosen now (a window's commands while its app has no
 * window open) are greyed out, as on a Mac. */
.topline menuitem:disabled label, .topline menuitem:disabled box label { color: alpha(@ink, 0.4); }
.topline .clock { font-feature-settings: "tnum"; padding: 0 12px; }
.topline .clock label { font-feature-settings: "tnum"; }
.topline button.status { padding: 0 6px; min-width: 0; }
.topline button.recording image { color: #e5484d; }

.pier-shelf { padding: 6px 10px; }
.pier-shelf-bg {
  background-color: @shelf;
  border: 1px solid @edge;
  border-radius: 18px;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.16);
}
.pier-item { background: none; border: none; box-shadow: none; padding: 0 3px; }
.pier-dot { color: @ink; font-size: 7px; }
.topline-popup {
  background-color: @shelf;
  border: 1px solid @edge;
  border-radius: 14px;
  padding: 10px 12px;
}
.topline-popup label { color: @ink; }
.pier-sep { background-color: @edge; min-width: 1px; margin: 8px 6px; }

.seek {
  background-color: @panel;
  border: 1px solid @edge;
  border-radius: 16px;
  padding: 10px;
  color: @ink;
}
.seek entry { font-size: 22px; min-height: 44px; border: none; box-shadow: none; background: none; color: @ink; }
.seek row { padding: 6px 10px; border-radius: 9px; color: @ink; }
.seek row:selected { background-color: #2f7bf5; color: white; }
.seek row:selected .hint { color: rgba(255, 255, 255, 0.75); }
.seek .hint { color: @dim; font-size: 12px; }
.seek list { background: transparent; }
.seek .seek-preview { border-left: 1px solid rgba(128, 128, 128, 0.22); padding: 8px 4px 8px 18px; }
.seek .seek-preview-title { font-size: 17px; font-weight: bold; color: @ink; }
.seek .seek-preview-text { font-family: monospace; font-size: 11px; color: @dim; }
.help-panel list, .help-panel row { background-color: transparent; }
.help-panel row { padding: 2px 4px; border-radius: 5px; }
.help-panel row:selected { background-color: #2f7bf5; }
.help-panel row:selected label { color: white; }
"""

LIGHT = {"bar": "rgba(246, 246, 248, 0.66)", "ink": "#1d1d1f", "hover": "rgba(0, 0, 0, 0.09)",
         "shelf": "rgba(255, 255, 255, 0.36)", "edge": "rgba(255, 255, 255, 0.50)",
         "panel": "rgba(246, 246, 248, 0.985)", "dim": "rgba(29, 29, 31, 0.55)"}
DARK = {"bar": "rgba(30, 30, 33, 0.60)", "ink": "#ececef", "hover": "rgba(255, 255, 255, 0.13)",
        "shelf": "rgba(40, 40, 44, 0.50)", "edge": "rgba(255, 255, 255, 0.16)",
        "panel": "rgba(38, 38, 42, 0.985)", "dim": "rgba(236, 236, 239, 0.55)"}

PREFS = os.path.expanduser("~/.config/freemac/shell.json")


def prefs():
    """Shell preferences written by Dials (for example the clock format)."""
    try:
        with open(PREFS) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def watch_prefs(callback):
    """Call callback() whenever Dials changes shell.json; keep the monitor."""
    monitor = Gio.File.new_for_path(PREFS).monitor_file(Gio.FileMonitorFlags.NONE, None)
    monitor.connect("changed", lambda *_: callback())
    return monitor


_provider = None
_settings = None


def interface_settings():
    """org.gnome.desktop.interface, or None if the schema is missing."""
    source = Gio.SettingsSchemaSource.get_default()
    if source and source.lookup("org.gnome.desktop.interface", True):
        return Gio.Settings.new("org.gnome.desktop.interface")
    return None


def is_dark():
    settings = _settings or interface_settings()
    return bool(settings) and settings.get_string("color-scheme") == "prefer-dark"


def css(dark):
    text = TEMPLATE
    for key, value in (DARK if dark else LIGHT).items():
        text = text.replace("@" + key + ";", value + ";").replace("@" + key + " ", value + " ")
    return text.encode()


def apply(on_change=None):
    """Load the shell's style and follow light/dark changes from Dials."""
    global _provider, _settings
    screen = Gdk.Screen.get_default()
    if _provider is None:
        _provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_screen(screen, _provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        _settings = interface_settings()
        if _settings:
            def changed(*_args):
                _provider.load_from_data(css(is_dark()))
                if on_change:
                    on_change(is_dark())
            _settings.connect("changed::color-scheme", changed)
    _provider.load_from_data(css(is_dark()))


def blurred(pixbuf, width, height):
    """A picture filling width x height, softly blurred (shrunk a lot, then
    grown back with smooth scaling): for the login screen and Marina."""
    from gi.repository import GdkPixbuf

    scale = max(width / pixbuf.get_width(), height / pixbuf.get_height())
    full = pixbuf.scale_simple(max(1, int(pixbuf.get_width() * scale)), max(1, int(pixbuf.get_height() * scale)),
                               GdkPixbuf.InterpType.BILINEAR)
    small = full.scale_simple(max(1, full.get_width() // 24), max(1, full.get_height() // 24),
                              GdkPixbuf.InterpType.HYPER)
    small = small.scale_simple(max(1, full.get_width() // 8), max(1, full.get_height() // 8),
                               GdkPixbuf.InterpType.BILINEAR)
    return small.scale_simple(full.get_width(), full.get_height(), GdkPixbuf.InterpType.BILINEAR)


def make_transparent(window):
    screen = window.get_screen()
    visual = screen.get_rgba_visual()
    if visual:
        window.set_visual(visual)
    window.set_app_paintable(True)
