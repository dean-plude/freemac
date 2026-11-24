# SPDX-License-Identifier: GPL-3.0-or-later
"""Shared look for freemac's shell (original styling)."""
import json
import os

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gtk  # noqa: E402

from gi.repository import Gio  # noqa: E402

# GTK has just taken the region's formats from the session (LC_TIME and the
# rest, Dials > Language & Region). freemac's own apps are in English and
# build their dates themselves, so the day and month names they write stay
# English, as on a Mac whose language is English, in any region; mail dates
# need them in English too.
from . import region as _region  # noqa: E402
_region.english_names()

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
.topline menuitem:disabled label, .topline menuitem:disabled box label { color: alpha(@ink , 0.4); }
/* A heading inside a menu, such as Applications in Recent Items. */
menuitem.menu-heading:disabled label, .topline menuitem.menu-heading:disabled label {
  color: alpha(@ink , 0.55); font-size: 12px; font-weight: 600; }
.topline .clock { font-feature-settings: "tnum"; padding: 0 12px; }
.topline .clock label { font-feature-settings: "tnum"; }
.topline button.status { padding: 0 6px; min-width: 0; }
.topline button.menu-extra.open { background-color: @hover; border-radius: 6px; }
.topline button.recording image { color: #e5484d; }
.topline button.battery-low-power image { color: #e8a316; }

.pier-shelf { padding: 6px 10px; }
.pier-shelf-side { padding: 10px 6px; }
.pier-shelf-bg {
  background-color: @shelf;
  border: 1px solid @edge;
  border-radius: 18px;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.16);
}
.pier-item { background: none; border: none; box-shadow: none; padding: 0 3px; }
.pier-dot { color: @ink; font-size: 7px; }
/* Pop-ups from the menu bar (quick settings, volume) are nearly solid: with
 * no blur behind them, see-through glass let windows show through the text. */
.topline-popup {
  background-color: @panel;
  border: 1px solid @edge;
  border-radius: 14px;
  padding: 10px 12px;
}
.topline-popup label { color: @ink; }
/* The Sound menu (status.py): a title, the slider, the outputs, Settings. */
.sound-menu { padding: 10px 8px; }
.sound-menu-title { font-weight: bold; padding: 0 6px; }
.sound-menu-heading { color: @dim; font-size: 12px; font-weight: 600; padding: 2px 6px; }
.sound-menu-item { padding: 4px 6px; border-radius: 7px; }
.menu-note { color: @dim; padding: 0 6px; }
.sound-menu-item:hover { background-color: alpha(currentColor, 0.08); }
.sound-device { border-radius: 50%; padding: 5px; background-color: alpha(currentColor, 0.12); }
.sound-device-on { background-color: @theme_selected_bg_color; color: white; }
/* Lifeboat's lifebuoy turns slowly while it backs up (lifeboat_menu.py). */
@keyframes lifeboat-turn { from { -gtk-icon-transform: rotate(0deg); } to { -gtk-icon-transform: rotate(360deg); } }
.lifeboat-busy image { animation: lifeboat-turn 4s linear infinite; }
/* Now Playing in the menu bar (now_playing_menu.py). */
.now-playing-blank { border-radius: 8px; background-color: alpha(currentColor, 0.1); color: @dim; }
.now-playing-progress trough { min-height: 4px; border-radius: 2px; background-color: alpha(currentColor, 0.15); }
.now-playing-progress progress { min-height: 4px; border-radius: 2px; background-color: @dim; }
.now-playing-time { font-feature-settings: "tnum"; }
.now-playing-control { padding: 4px; border-radius: 50%; color: @ink; }
.now-playing-control:hover { background-color: alpha(currentColor, 0.08); }
.sound-mute, .sound-mute:checked { background: none; border: none; box-shadow: none; padding: 2px 4px; color: @ink; }
.sound-mute:checked { color: @dim; }
.pier-sep { background-color: @edge; min-width: 1px; margin: 8px 6px; }
.pier-shelf-side .pier-sep { min-width: 0; min-height: 1px; margin: 6px 8px; }
.pier-shelf-side .pier-item { padding: 3px 0; }

.seek {
  background-color: @panel;
  border: 1px solid @edge;
  border-radius: 16px;
  padding: 10px;
  color: @ink;
}
.seek entry { font-size: 22px; min-height: 44px; border: none; box-shadow: none; background: none; color: @ink; }
.seek row { padding: 6px 10px; border-radius: 9px; color: @ink; }
.seek row:selected { background-color: @theme_selected_bg_color; color: white; }
.seek row:selected .hint { color: rgba(255, 255, 255, 0.75); }
.seek .hint { color: @dim; font-size: 12px; }
.seek list { background: transparent; }
.seek .seek-preview { border-left: 1px solid rgba(128, 128, 128, 0.22); padding: 8px 4px 8px 18px; }
.seek .seek-preview-title { font-size: 17px; font-weight: bold; color: @ink; }
.seek .seek-preview-text { font-family: monospace; font-size: 11px; color: @dim; }
.help-panel list, .help-panel row { background-color: transparent; }
.help-panel row { padding: 2px 4px; border-radius: 5px; }
.help-panel row:selected { background-color: @theme_selected_bg_color; }
.help-panel row:selected label { color: white; }
/* Glyph, the emoji and symbols panel (Control-⌘-Space). */
.glyph {
  background-color: @panel;
  border: 1px solid @edge;
  border-radius: 14px;
  padding: 10px;
  color: @ink;
}
.glyph entry { min-height: 30px; }
.glyph scrolledwindow, .glyph viewport, .glyph flowbox { background: none; }
.glyph flowboxchild { padding: 0; border-radius: 7px; background: none; }
.glyph flowboxchild:hover { background-color: rgba(128, 128, 128, 0.18); }
.glyph flowboxchild:selected { background-color: @theme_selected_bg_color; }
.glyph .glyph-emoji { font-size: 24px; min-width: 36px; min-height: 36px; }
.glyph .glyph-tabs button { padding: 2px 0; min-width: 0; border-radius: 7px; font-size: 16px; background: none; border: none; box-shadow: none; }
.glyph .glyph-tabs button:checked { background-color: rgba(128, 128, 128, 0.22); }
.glyph .glyph-heading { font-weight: 600; font-size: 11px; color: @dim; }
.glyph .glyph-name { font-size: 12px; color: @dim; }
"""

LIGHT = {"bar": "rgba(246, 246, 248, 0.66)", "ink": "#1d1d1f", "hover": "rgba(0, 0, 0, 0.09)",
         "shelf": "rgba(255, 255, 255, 0.36)", "edge": "rgba(255, 255, 255, 0.50)",
         "panel": "rgba(246, 246, 248, 0.985)", "dim": "rgba(29, 29, 31, 0.55)"}
DARK = {"bar": "rgba(30, 30, 33, 0.60)", "ink": "#ececef", "hover": "rgba(255, 255, 255, 0.13)",
        "shelf": "rgba(40, 40, 44, 0.50)", "edge": "rgba(255, 255, 255, 0.16)",
        "panel": "rgba(38, 38, 42, 0.985)", "dim": "rgba(236, 236, 239, 0.55)"}

# Accessibility > Reduce transparency (shell.json "reduce_transparency"):
# the menu bar, the Dock and the panels turn solid.
SOLID_LIGHT = {"bar": "rgb(234, 234, 237)", "shelf": "rgb(226, 226, 231)",
               "edge": "rgba(0, 0, 0, 0.12)", "panel": "rgb(246, 246, 248)"}
SOLID_DARK = {"bar": "rgb(36, 36, 39)", "shelf": "rgb(48, 48, 52)",
              "edge": "rgba(255, 255, 255, 0.16)", "panel": "rgb(38, 38, 42)"}

PREFS = os.path.expanduser("~/.config/freemac/shell.json")


def prefs():
    """Shell preferences written by Dials (for example the clock format)."""
    try:
        with open(PREFS) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def h24(values=None):
    """Whether times are shown on a 24-hour clock: the choice in Dials >
    Date & Time, or else the region's own (Language & Region)."""
    values = prefs() if values is None else values
    if values.get("clock") in ("12", "24"):
        return values["clock"] == "24"
    from . import region
    return region.uses_24_hour()


def save_prefs(**changes):
    """Change some shell preferences, keeping the rest (as Dials does)."""
    values = prefs()
    values.update(changes)
    try:
        os.makedirs(os.path.dirname(PREFS), exist_ok=True)
        tmp = f"{PREFS}.{os.getpid()}-tmp"
        with open(tmp, "w") as f:
            json.dump(values, f, indent=2)
        os.replace(tmp, PREFS)
    except OSError:
        pass


def watch_prefs(callback):
    """Call callback() whenever Dials changes shell.json; keep the monitor."""
    monitor = Gio.File.new_for_path(PREFS).monitor_file(Gio.FileMonitorFlags.NONE, None)
    monitor.connect("changed", lambda *_: callback())
    return monitor


_provider = None
_settings = None
_solid = None
_prefs_watch = None
_listeners = []


def interface_settings():
    """org.gnome.desktop.interface, or None if the schema is missing."""
    source = Gio.SettingsSchemaSource.get_default()
    if source and source.lookup("org.gnome.desktop.interface", True):
        return Gio.Settings.new("org.gnome.desktop.interface")
    return None


# Dials > Appearance > Accent colour (shell.json "accent"): the colour of
# selections, switches and default buttons in every app. Each has its own pair
# of GTK themes (art/gtk-theme/make-theme.py); this is the swatch Dials shows.
ACCENTS = (("blue", "Blue", "#2f7bf5"), ("purple", "Purple", "#8f52d9"), ("pink", "Pink", "#de4a80"),
           ("red", "Red", "#dc3d42"), ("orange", "Orange", "#ea7a17"), ("yellow", "Yellow", "#d39a07"),
           ("green", "Green", "#2c9f4c"), ("graphite", "Graphite", "#7d7d84"))


def accent():
    chosen = prefs().get("accent", "blue")
    return chosen if chosen in {name for name, _label, _colour in ACCENTS} else "blue"


def theme_name(dark, chosen=None):
    """The GTK theme for light or dark mode in the accent colour chosen:
    freemac, freemac-dark, freemac-purple, freemac-dark-purple…"""
    chosen = chosen or accent()
    return "freemac" + ("-dark" if dark else "") + ("" if chosen == "blue" else "-" + chosen)


def is_dark():
    settings = _settings or interface_settings()
    return bool(settings) and settings.get_string("color-scheme") == "prefer-dark"


def solid():
    """Reduce transparency is on."""
    return bool(prefs().get("reduce_transparency"))


def palette(dark=None):
    """The shell's colours for light or dark mode, solid when Reduce
    transparency is on."""
    dark = is_dark() if dark is None else dark
    colours = dict(DARK if dark else LIGHT)
    if solid():
        colours.update(SOLID_DARK if dark else SOLID_LIGHT)
    return colours


def css(dark):
    text = TEMPLATE
    for key, value in palette(dark).items():
        text = text.replace("@" + key + ";", value + ";").replace("@" + key + " ", value + " ")
    return text.encode()


def apply(on_change=None):
    """Load the shell's style and follow light/dark and Reduce transparency
    changes from Dials. on_change(dark) is called after each."""
    global _provider, _settings, _solid, _prefs_watch
    screen = Gdk.Screen.get_default()
    if on_change:
        _listeners.append(on_change)
    if _provider is None:
        _provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_screen(screen, _provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        _settings = interface_settings()

        def changed(*_args):
            _provider.load_from_data(css(is_dark()))
            for listener in _listeners:
                listener(is_dark())
        if _settings:
            _settings.connect("changed::color-scheme", changed)

        def prefs_changed():
            global _solid
            if solid() != _solid:
                _solid = solid()
                changed()
        _prefs_watch = watch_prefs(prefs_changed)
    _solid = solid()
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


def sideways_wheel(scroller):
    """Let a mouse wheel's up and down move a row that only scrolls sideways,
    until the row reaches its end."""
    def scrolled(_w, event):
        adjustment = scroller.get_hadjustment()
        if event.direction == Gdk.ScrollDirection.SMOOTH:
            ok, dx, dy = event.get_scroll_deltas()
            if not ok or abs(dx) >= abs(dy):
                return False
            step = dy * 40
        elif event.direction in (Gdk.ScrollDirection.UP, Gdk.ScrollDirection.DOWN):
            step = 60 if event.direction == Gdk.ScrollDirection.DOWN else -60
        else:
            return False
        top = adjustment.get_upper() - adjustment.get_page_size()
        value = adjustment.get_value()
        if (step < 0 and value <= 0) or (step > 0 and value >= top):
            return False      # at the end: let the page around it scroll
        adjustment.set_value(max(0, min(top, adjustment.get_value() + step)))
        return True

    scroller.add_events(Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK)
    scroller.connect("scroll-event", scrolled)
    return scroller
