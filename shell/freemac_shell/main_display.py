# SPDX-License-Identifier: GPL-3.0-or-later
"""The main display, as on a Mac: the one with the menu bar, the Dock and
the files on the Desktop. Dials > Displays sets it (Use as: Main display),
kept in ~/.config/freemac/shell.json as "main_display", the display's
connector name (HDMI-A-1, eDP-1).

With no choice made, or the chosen display unplugged, the built-in display
is the main one, then the first one Wayfire lists.

follow(window) keeps a layer-shell window (Topline, Pier) on the main
display, moving it when displays come and go or the choice changes.
Displays are matched to GDK's by their place in the layout, which is the
same in both. Original freemac code.
"""
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib  # noqa: E402

from . import style  # noqa: E402
from .wfipc import Connection  # noqa: E402

KEY = "main_display"


def chosen():
    """The connector name Dials saved, or ''."""
    value = style.prefs().get(KEY)
    return value if isinstance(value, str) else ""


def outputs():
    try:
        reply = Connection().call("strata/outputs")
    except (OSError, ValueError):
        return []
    found = reply.get("outputs") if isinstance(reply, dict) else None
    return [o for o in found or [] if isinstance(o, dict) and o.get("name")]


def main_output(listed=None, name=None):
    """The output (as strata/outputs gives it) that is the main display."""
    shown = [o for o in (outputs() if listed is None else listed) if o.get("source") == "self"]
    if not shown:
        return None
    name = chosen() if name is None else name
    for rule in (lambda o: o["name"] == name, lambda o: o.get("built_in")):
        for output in shown:
            if rule(output):
                return output
    return shown[0]


def monitor(display=None):
    """The Gdk.Monitor of the main display (the first one when Strata can't
    be asked or no place matches)."""
    display = display or Gdk.Display.get_default()
    count = display.get_n_monitors()
    if count == 0:
        return None
    if count > 1:
        output = main_output()
        if output is not None:
            for index in range(count):
                place = display.get_monitor(index).get_geometry()
                if (place.x, place.y) == (output.get("x"), output.get("y")):
                    return display.get_monitor(index)
    return display.get_monitor(0)


def follow(window, on_move=None):
    """Keep a layer-shell window on the main display from now on."""
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import GtkLayerShell
    state = {"monitor": None, "pending": None}

    def place():
        state["pending"] = None
        target = monitor()
        if target is None or target == state["monitor"]:
            return False
        state["monitor"] = target
        visible = window.get_visible()
        if visible:
            # A layer surface takes a new output only when it is mapped again.
            window.hide()
        GtkLayerShell.set_monitor(window, target)
        if visible:
            window.show()
        if on_move:
            on_move(target)
        return False

    def soon(*_args):
        # A new display is listed before it has its place; wait a moment.
        if state["pending"]:
            GLib.source_remove(state["pending"])
        state["pending"] = GLib.timeout_add(600, place)

    display = Gdk.Display.get_default()
    display.connect("monitor-added", soon)
    display.connect("monitor-removed", soon)
    window._main_display_watch = style.watch_prefs(soon)
    place()
