# SPDX-License-Identifier: GPL-3.0-or-later
"""Shared look for freemac's shell (original styling)."""
import json
import os

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gtk  # noqa: E402

from gi.repository import Gio  # noqa: E402

# Colours are freemac's own: a soft lavender-grey glass in light mode and a deep
# navy glass in dark mode, with an indigo accent.
TEMPLATE = """
.topline { background-color: @bar; color: @ink; }
.topline button { background: none; border: none; box-shadow: none; padding: 0 9px; min-height: 24px; color: @ink; }
.topline button:hover { background-color: @hover; border-radius: 6px; }
.topline label { color: @ink; }
.topline .app-name { font-weight: 700; }
.topline .clock { font-feature-settings: "tnum"; padding: 0 12px; }
.topline .clock label { font-feature-settings: "tnum"; }
.topline button.status { padding: 0 6px; min-width: 0; }

.pier-shelf {
  background-color: @shelf;
  border: 1px solid @edge;
  border-radius: 20px;
  padding: 6px 10px;
}
.pier-item { background: none; border: none; box-shadow: none; padding: 0 3px; }
.pier-dot { color: @ink; font-size: 7px; }
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
.seek row:selected { background-color: #4b5fc4; color: white; }
.seek row:selected .hint { color: rgba(255, 255, 255, 0.75); }
.seek .hint { color: @dim; font-size: 12px; }
"""

LIGHT = {"bar": "rgba(246, 245, 250, 0.82)", "ink": "#1d1d27", "hover": "rgba(30, 30, 60, 0.10)",
         "shelf": "rgba(250, 249, 253, 0.42)", "edge": "rgba(255, 255, 255, 0.55)",
         "panel": "rgba(248, 247, 252, 0.94)", "dim": "rgba(30, 30, 50, 0.55)"}
DARK = {"bar": "rgba(22, 24, 44, 0.80)", "ink": "#ecebf5", "hover": "rgba(255, 255, 255, 0.12)",
        "shelf": "rgba(30, 32, 58, 0.55)", "edge": "rgba(255, 255, 255, 0.14)",
        "panel": "rgba(28, 30, 52, 0.95)", "dim": "rgba(236, 235, 245, 0.55)"}

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


def make_transparent(window):
    screen = window.get_screen()
    visual = screen.get_rgba_visual()
    if visual:
        window.set_visual(visual)
    window.set_app_paintable(True)
