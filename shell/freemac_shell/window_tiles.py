# SPDX-License-Identifier: GPL-3.0-or-later
"""The green button's menu, as on a Mac: rest the pointer on a window's
green button and a small panel opens under it, with pictures to click:

    Move & Resize     left half, right half, top half, bottom half,
                      and the four quarters of the screen
    Fill & Arrange    fill the screen, centre the window, or put it on the
                      left with the window used before it on the right
    Return to Previous Size, after one of those

Strata's decorator tells Topline over a small socket when the pointer has
rested on the button ("tiles VIEW X Y", X and Y under the button in the
layout) and when it has left ("leave VIEW"). Topline, which is always
running, shows the panel, so it opens at once, and moves the window with the
same code as its Window > Move & Resize menu.

GTK apps draw their own title bar, so for them freemac's GTK module
(strata/gtk/freemac-zoom.c) says "hover PID" when the pointer reaches the
green button and "unhover PID" when it leaves; Topline waits the same moment,
then asks Strata where the pointer is and which window is under it.
Original freemac code.
"""
import math
import os
import socket

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import style  # noqa: E402
from .wfipc import Connection, is_minimized  # noqa: E402

SOCKET = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}",
                      "freemac-topline.sock")

LEAVE_MS = 350      # the pointer has this long to reach the panel from the button
HOVER_MS = 550      # how long the pointer rests on an app's own button first
ICON_W, ICON_H = 30, 22

# (tooltip, place) for each picture; a place is what Topline._place takes.
HALVES = (("Left", "left"), ("Right", "right"), ("Top", "top"), ("Bottom", "bottom"))
QUARTERS = (("Top Left", "tl"), ("Top Right", "tr"), ("Bottom Left", "bl"), ("Bottom Right", "br"))

# The part of the screen picture each choice fills, as (x, y, width, height)
# fractions; "centre" and "pair" have pictures of their own.
SHAPES = {"left": (0, 0, .5, 1), "right": (.5, 0, .5, 1), "top": (0, 0, 1, .5), "bottom": (0, .5, 1, .5),
          "tl": (0, 0, .5, .5), "tr": (.5, 0, .5, .5), "bl": (0, .5, .5, .5), "br": (.5, .5, .5, .5),
          "fill": (0, 0, 1, 1), "centre": (.2, .18, .6, .64)}

CSS = b"""
window.tiles-window, window.tiles-window > * { background: transparent; }
.tiles-panel {
    margin: 8px 20px 20px 20px;
    padding: 8px 8px 6px 8px;
    border-radius: 12px;
    background-color: rgba(246, 246, 248, 0.86);
    border: 1px solid rgba(0, 0, 0, 0.10);
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.22);
}
.tiles-panel.dark { background-color: rgba(44, 44, 48, 0.86); border-color: rgba(255, 255, 255, 0.14); }
.tiles-panel.solid { background-color: rgb(240, 240, 243); }
.tiles-panel.dark.solid { background-color: rgb(44, 44, 48); }
.tiles-heading { font-size: 11px; font-weight: 600; color: rgba(0, 0, 0, 0.5); margin: 2px 4px 4px 4px; }
.tiles-panel.dark .tiles-heading { color: rgba(255, 255, 255, 0.55); }
.tiles-pick { padding: 4px; border-radius: 6px; border: none; background: transparent; box-shadow: none; }
.tiles-pick:hover { background-color: rgba(0, 0, 0, 0.08); }
.tiles-panel.dark .tiles-pick:hover { background-color: rgba(255, 255, 255, 0.12); }
.tiles-back { font-size: 13px; padding: 3px 6px; border-radius: 6px; border: none; background: transparent;
              box-shadow: none; }
.tiles-back:hover { background-color: @theme_selected_bg_color; color: white; }
"""


def send(line):
    """Tell the running Topline something; False when it isn't running."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect(SOCKET)
            s.sendall(line.encode() + b"\n")
        return True
    except OSError:
        return False


def parse(line):
    """("tiles", view id, x, y), ("leave", view id), ("hover", pid),
    ("unhover", pid) or None."""
    words = line.split()
    try:
        if len(words) == 4 and words[0] == "tiles":
            return ("tiles", int(words[1]), int(float(words[2])), int(float(words[3])))
        if len(words) == 2 and words[0] in ("leave", "hover", "unhover"):
            return (words[0], int(words[1]))
    except ValueError:
        pass
    return None


def under_pointer(reply):
    """(view id, x, y) for the panel from Strata's strata/pointer reply: the
    window under the pointer, and the point the panel hangs from (the
    button's left edge, just below it, taking the pointer to be on the
    button's middle). None when no window is there."""
    if not isinstance(reply, dict):
        return None
    try:
        view, x, y = int(reply.get("view") or 0), int(reply["x"]), int(reply["y"])
    except (KeyError, TypeError, ValueError):
        return None
    if view <= 0:
        return None
    return (view, x - 7, y + 9)


def on_button(reply, anchor):
    """Whether Strata's strata/pointer reply puts the pointer on the green
    button that the panel at `anchor` (as open() takes it) hangs from."""
    if not isinstance(reply, dict) or anchor is None:
        return False
    try:
        x, y = int(reply["x"]), int(reply["y"])
    except (KeyError, TypeError, ValueError):
        return False
    return abs(x - (anchor[0] + 7)) <= 12 and abs(y - (anchor[1] - 8)) <= 12


def partner(views, view_id):
    """The window to put beside this one: the one used most recently before
    it on the same display, not minimized; None when there isn't one."""
    this = next((v for v in views if v.get("id") == view_id), None)
    if this is None:
        return None
    output = this.get("output-id", this.get("output"))
    others = [v for v in views if v.get("id") != view_id and not is_minimized(v)
              and v.get("output-id", v.get("output")) == output and v.get("mapped", True)]
    others.sort(key=lambda v: v.get("last-focus-timestamp", 0), reverse=True)
    return others[0] if others else None


def _rounded(cr, x, y, w, h, r):
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


def picture(shape, dark):
    """A small picture of the screen with the part a choice fills shaded."""
    area = Gtk.DrawingArea()
    area.set_size_request(ICON_W, ICON_H)

    def draw(_w, cr):
        ink = (1, 1, 1) if dark else (0.11, 0.11, 0.12)
        cr.set_line_width(1.2)
        _rounded(cr, 1, 1, ICON_W - 2, ICON_H - 2, 3.5)
        cr.set_source_rgba(*ink, 0.75)
        cr.stroke()
        inner = (3, 3, ICON_W - 6, ICON_H - 6)
        if shape == "pair":
            parts = [((0, 0, .5, 1), 0.75), ((.5, 0, .5, 1), 0.35)]
        else:
            parts = [(SHAPES[shape], 0.75)]
        for (fx, fy, fw, fh), alpha in parts:
            x = inner[0] + fx * inner[2] + (0.75 if fx else 0)
            w = fw * inner[2] - (0.75 if fx or fw < 1 else 0)
            y = inner[1] + fy * inner[3] + (0.75 if fy else 0)
            h = fh * inner[3] - (0.75 if fy or fh < 1 else 0)
            _rounded(cr, x, y, w, h, 1.5)
            cr.set_source_rgba(*ink, alpha)
            cr.fill()
        return False

    area.connect("draw", draw)
    return area


class TilesPanel(Gtk.Window):
    """The panel itself. `owner` is Topline, whose _place, _fill, _center
    and _unplace move the window."""

    def __init__(self, owner):
        super().__init__(title="Move & Resize")
        self.owner = owner
        style.make_transparent(self)
        self.get_style_context().add_class("tiles-window")
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "freemac-tiles")
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)
        GtkLayerShell.set_exclusive_zone(self, -1)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.LEFT):
            GtkLayerShell.set_anchor(self, edge, True)
        self.view_id = None
        self.anchor = None
        self.inside = False
        self._close_source = 0
        self._hover_source = 0
        self.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        self.connect("enter-notify-event", self._entered)
        self.connect("leave-notify-event", self._left)

    # -- what the decorator says
    def handle(self, line):
        message = parse(line)
        if message is None:
            return
        kind = message[0]
        if kind == "tiles":
            self._cancel_hover()
            self.open(*message[1:])
        elif kind == "hover":
            self._cancel_hover()
            self._hover_source = GLib.timeout_add(HOVER_MS, self._hover_done)
        elif kind == "unhover":
            self._cancel_hover()
            if self.get_visible() and not self.inside:
                self._close_soon()
        elif message[1] == self.view_id and not self.inside:
            self._close_soon()

    def _hover_done(self):
        self._hover_source = 0
        try:
            reply = Connection().call("strata/pointer")
        except (OSError, ValueError):
            return False
        found = under_pointer(reply)
        if found is not None:
            self.open(*found)
        return False

    def _cancel_hover(self):
        if self._hover_source:
            GLib.source_remove(self._hover_source)
            self._hover_source = 0

    def open(self, view_id, x, y):
        if self.view_id == view_id and self.get_visible():
            self._cancel_close()
            return
        self.view_id = view_id
        self.anchor = (x, y)
        self.inside = False
        self._cancel_close()
        child = self.get_child()
        if child:
            self.remove(child)
        self.add(self._build())
        display = Gdk.Display.get_default()
        monitor = display.get_monitor_at_point(x, y) if display else None
        if monitor is not None:
            GtkLayerShell.set_monitor(self, monitor)
            place = monitor.get_geometry()
            x, y = x - place.x, y - place.y
        # The panel's margin (20 px at the sides and bottom, so its shadow
        # fades out before the window's edge; 8 px on top, so the window
        # stays clear of the button) and padding (8 px) put its pictures in
        # line with the button's left side; it hangs 10 px below the button.
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, max(0, x - 28))
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, max(0, y + 2))
        self.show_all()
        # Had the pointer gone before the panel showed, close it again.
        self._close_source = GLib.timeout_add(2500, self._check_pointer)

    def close(self):
        self._cancel_close()
        self.inside = False
        self.view_id = None
        self.hide()
        return False

    # -- the panel's contents
    def _build(self):
        dark = style.is_dark()
        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        context = panel.get_style_context()
        context.add_class("tiles-panel")
        if dark:
            context.add_class("dark")
        if style.solid():
            context.add_class("solid")
        view = {"id": self.view_id}

        def heading(text):
            label = Gtk.Label(label=text, xalign=0)
            label.get_style_context().add_class("tiles-heading")
            panel.pack_start(label, False, False, 0)

        def row(picks):
            box = Gtk.Box(spacing=2)
            for tip, shape, act in picks:
                button = Gtk.Button(relief=Gtk.ReliefStyle.NONE, tooltip_text=tip)
                button.get_style_context().add_class("tiles-pick")
                button.add(picture(shape, dark))
                button.connect("clicked", lambda _b, act=act: self._do(act))
                box.pack_start(button, False, False, 0)
            panel.pack_start(box, False, False, 0)

        place = self.owner._place
        heading("Move & Resize")
        row([(tip, how, lambda how=how: place(view, how)) for tip, how in HALVES])
        row([(tip, how, lambda how=how: place(view, how)) for tip, how in QUARTERS])
        heading("Fill & Arrange")
        arrange = [("Fill", "fill", lambda: self.owner._fill(view)),
                   ("Centre", "centre", lambda: self.owner._center(view))]
        other = partner(self.owner.wf.views(), self.view_id) if self.owner.wf else None
        if other is not None:
            arrange.append(("Left & Right", "pair", lambda: self._pair(view["id"], other["id"])))
        row(arrange)
        if self.view_id in self.owner.before_place:
            back = Gtk.Button(label="Return to Previous Size", relief=Gtk.ReliefStyle.NONE, xalign=0)
            back.get_style_context().add_class("tiles-back")
            back.connect("clicked", lambda _b: self._do(lambda: self.owner._unplace(view)))
            panel.pack_start(back, False, False, 2)
        return panel

    def _do(self, act):
        self.close()
        act()

    def _pair(self, view_id, other_id):
        # The panel has closed (and forgotten its window) by now.
        self.owner._place({"id": other_id}, "right")
        self.owner._place({"id": view_id}, "left")

    # -- opening and closing
    # Only the panel's own window counts: its buttons' crossings bubble up
    # too. The pointer can land straight on a button, and then the panel
    # hears only that it went into one of its parts ("inferior").
    def _entered(self, _w, event):
        if event.window == self.get_window():
            self.inside = True
            self._cancel_close()
        return False

    def _left(self, _w, event):
        if event.window != self.get_window():
            return False
        if event.detail == Gdk.NotifyType.INFERIOR:
            self.inside = True
            self._cancel_close()
        else:
            self.inside = False
            self._close_soon()
        return False

    def _close_soon(self):
        self._cancel_close()
        self._close_source = GLib.timeout_add(LEAVE_MS, self._close_if_outside)

    def _check_pointer(self):
        """Close the panel unless the pointer is in it or still on the
        button; look again a little later while it is."""
        self._close_source = 0
        if self.inside:
            return False
        try:
            reply = Connection().call("strata/pointer")
        except (OSError, ValueError):
            reply = None
        if on_button(reply, self.anchor):
            self._close_source = GLib.timeout_add(1000, self._check_pointer)
        else:
            self.close()
        return False

    def _close_if_outside(self):
        self._close_source = 0
        if not self.inside:
            self.close()
        return False

    def _cancel_close(self):
        if self._close_source:
            GLib.source_remove(self._close_source)
            self._close_source = 0


def listen(panel, others=None):
    """Take the decorator's messages for `panel` from now on. `others` maps
    a message's first word to what handles it instead ("accent" for the
    press-and-hold panel, accents.py)."""
    try:
        os.unlink(SOCKET)
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET)
    os.chmod(SOCKET, 0o600)
    server.listen(8)

    def on_connect(_fd, _condition):
        conn, _ = server.accept()
        with conn:
            conn.settimeout(0.5)
            try:
                line = conn.recv(128).decode()
            except (OSError, UnicodeDecodeError):
                return True
        line = line.strip()
        word = line.split(" ", 1)[0]
        if others and word in others:
            others[word](line)
        else:
            panel.handle(line)
        return True

    GLib.io_add_watch(server.fileno(), GLib.IO_IN, on_connect)
    return server
