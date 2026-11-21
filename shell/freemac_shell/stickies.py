# SPDX-License-Identifier: GPL-3.0-or-later
"""Stickies: little coloured notes that stay on the desktop.

Each note sits on the desktop, above the wallpaper and the desktop's icons
and under the windows, like a note stuck to the screen. Drag a note by its
top strip, and drag its bottom-right corner to make it bigger. Type straight
into it. The strip has a × to throw the note away (asking first when it has
anything written on it) and a + for a new note; the dots change its colour.
Right-click the strip to keep the note in front of the windows (Float on Top).

Notes are kept in ~/.local/share/freemac/stickies.json as they change, and
come back at the next login (freemac-stickies --restore starts with the
session). Opening Stickies from the Dock adds a new note.

Each note is a layer-shell surface on the bottom layer (or the top layer when
it floats); its place is the surface's margin from the top-left of the screen.
Original freemac code.
"""
import json
import os
import sys
import time
import uuid

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import spelling, style  # noqa: E402

APP_ID = "org.freemac.Stickies"
STORE = os.path.join(GLib.get_user_data_dir(), "freemac", "stickies.json")
MIN_W, MIN_H = 150, 110
DEFAULT_W, DEFAULT_H = 230, 210

# name -> (paper, strip, dot)
COLOURS = {
    "yellow": ("#fff7a8", "#f5e46e", "#f2d43a"),
    "blue": ("#c9e7ff", "#a6d3fb", "#6cb4f5"),
    "green": ("#d2f5c4", "#b2e8a0", "#7fd162"),
    "pink": ("#ffd3e6", "#fbb5d3", "#f483b6"),
    "purple": ("#e4d6ff", "#cfb9fb", "#a98af2"),
    "gray": ("#ececec", "#d8d8d8", "#b3b3b3"),
}
ORDER = ["yellow", "blue", "green", "pink", "purple", "gray"]

CSS = b"""
.sticky { border-radius: 3px; }
.sticky-strip { min-height: 22px; padding: 0 4px; }
.sticky-strip button { min-width: 16px; min-height: 16px; padding: 0 3px; border: none;
  background: none; box-shadow: none; color: alpha(black, 0.55); }
.sticky-strip button:hover { color: black; background: alpha(black, 0.08); }
button.sticky-dot { min-width: 11px; min-height: 11px; border-radius: 7px; padding: 0; margin: 0 2px;
  border: 1px solid alpha(black, 0.18); box-shadow: none; background-image: none; }
.sticky textview, .sticky textview text { background: transparent; color: #2b2b2b; font-size: 1.05em; }
.sticky-ask { background: alpha(black, 0.07); padding: 6px; }
.sticky-ask label { color: #2b2b2b; }
"""


def load():
    try:
        with open(STORE) as f:
            data = json.load(f)
        return [n for n in data.get("notes", []) if isinstance(n, dict) and "id" in n]
    except (OSError, ValueError, AttributeError):
        return []


def save(notes):
    os.makedirs(os.path.dirname(STORE), exist_ok=True)
    temp = STORE + ".new"
    with open(temp, "w") as f:
        json.dump({"notes": notes}, f, indent=1)
    os.replace(temp, STORE)


def screen_size():
    display = Gdk.Display.get_default()
    monitor = display.get_primary_monitor() or display.get_monitor(0)
    area = monitor.get_workarea() if monitor else None
    return (area.width, area.height) if area else (1280, 800)


class Note(Gtk.Window):
    def __init__(self, app, data):
        super().__init__()
        self.app = app
        self.data = data
        self.drag = None          # ("move" | "size", start x, start y, start a, start b)
        self.set_application(app)
        self.set_title("Sticky Note")

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_namespace(self, "freemac-sticky")
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)
        self._apply_layer()
        self._apply_place()

        self.provider = Gtk.CssProvider()
        self.get_style_context().add_provider(self.provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        self.get_style_context().add_class("sticky")

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(box)

        strip = Gtk.EventBox()
        strip.get_style_context().add_class("sticky-strip")
        self.strip_provider = Gtk.CssProvider()
        strip.get_style_context().add_provider(self.strip_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        strip.connect("button-press-event", self._strip_pressed)
        strip.connect("button-release-event", self._released)
        strip.connect("motion-notify-event", self._moved)
        line = Gtk.Box(spacing=2)
        line.set_size_request(-1, 22)
        strip.add(line)
        close = Gtk.Button(label="×")
        close.set_tooltip_text("Throw Away This Note")
        close.connect("clicked", lambda _b: self.ask_delete())
        line.pack_start(close, False, False, 0)
        self.dots = Gtk.Box()
        for name in ORDER:
            dot = Gtk.Button(valign=Gtk.Align.CENTER)
            dot.get_style_context().add_class("sticky-dot")
            dot.provider = Gtk.CssProvider()
            dot.get_style_context().add_provider(dot.provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 2)
            dot.set_tooltip_text(name.capitalize())
            dot.colour = name
            dot.connect("clicked", lambda b: self.set_colour(b.colour))
            self.dots.pack_start(dot, False, False, 0)
        line.set_center_widget(self.dots)
        add = Gtk.Button(label="+")
        add.set_tooltip_text("New Note")
        add.connect("clicked", lambda _b: app.new_note(near=self))
        line.pack_end(add, False, False, 0)
        box.pack_start(strip, False, False, 0)

        self.ask = Gtk.Revealer()
        ask = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        ask.get_style_context().add_class("sticky-ask")
        ask.pack_start(Gtk.Label(label="Throw this note away?", xalign=0, wrap=True, max_width_chars=16),
                       False, False, 0)
        buttons = Gtk.Box(spacing=6, halign=Gtk.Align.END)
        keep = Gtk.Button(label="Keep")
        keep.connect("clicked", lambda _b: self.ask.set_reveal_child(False))
        toss = Gtk.Button(label="Throw Away")
        toss.get_style_context().add_class("destructive-action")
        toss.connect("clicked", lambda _b: app.delete_note(self))
        buttons.pack_start(keep, False, False, 0)
        buttons.pack_start(toss, False, False, 0)
        ask.pack_start(buttons, False, False, 0)
        self.ask.add(ask)
        box.pack_start(self.ask, False, False, 0)

        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.text = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=10, right_margin=10,
                                 top_margin=6, bottom_margin=6)
        spelling.attach(self.text)
        self.text.get_buffer().set_text(data.get("text", ""))
        self.text.get_buffer().connect("changed", self._typed)
        self.text.connect("key-press-event", self._key)
        scroller.add(self.text)
        overlay = Gtk.Overlay()
        overlay.add(scroller)
        grip = Gtk.EventBox(halign=Gtk.Align.END, valign=Gtk.Align.END)
        grip.set_size_request(16, 16)
        grip.connect("button-press-event", self._grip_pressed)
        grip.connect("button-release-event", self._released)
        grip.connect("motion-notify-event", self._moved)
        grip.connect("realize", lambda w: w.get_window().set_cursor(
            Gdk.Cursor.new_from_name(w.get_display(), "se-resize")))
        grip.connect("draw", self._draw_grip)
        overlay.add_overlay(grip)
        box.pack_start(overlay, True, True, 0)

        self._apply_colour()
        self.save_timer = 0
        self.show_all()

    # -- where it is --

    def _apply_layer(self):
        layer = GtkLayerShell.Layer.TOP if self.data.get("float") else GtkLayerShell.Layer.BOTTOM
        GtkLayerShell.set_layer(self, layer)

    def _apply_place(self):
        width, height = screen_size()
        w = max(MIN_W, min(int(self.data.get("w", DEFAULT_W)), width))
        h = max(MIN_H, min(int(self.data.get("h", DEFAULT_H)), height))
        x = max(0, min(int(self.data.get("x", 80)), width - w))
        y = max(0, min(int(self.data.get("y", 60)), height - 40))
        self.data.update(x=x, y=y, w=w, h=h)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, x)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, y)
        self.set_size_request(w, h)
        self.resize(w, h)

    def _strip_pressed(self, _w, event):
        if event.button == 3:
            self._menu(event)
            return True
        if event.button != 1:
            return False
        if event.type == Gdk.EventType._2BUTTON_PRESS:
            return True
        self.drag = ("move", event.x_root, event.y_root, self.data["x"], self.data["y"])
        return True

    def _grip_pressed(self, _w, event):
        if event.button != 1:
            return False
        self.drag = ("size", event.x_root, event.y_root, self.data["w"], self.data["h"])
        return True

    def _moved(self, _w, event):
        if self.drag is None:
            return False
        kind, x0, y0, a, b = self.drag
        if kind == "move":
            # The surface moves under the pointer, so the pointer's place in
            # it stays put: measure how far it is from where it was pressed.
            dx, dy = event.x_root - x0, event.y_root - y0
            self.data["x"], self.data["y"] = int(self.data["x"] + dx), int(self.data["y"] + dy)
        else:
            self.data["w"], self.data["h"] = int(a + event.x_root - x0), int(b + event.y_root - y0)
        self._apply_place()
        return True

    def _released(self, _w, _event):
        if self.drag is not None:
            self.drag = None
            self.app.changed()
        return False

    def _draw_grip(self, widget, cr):
        w, h = widget.get_allocated_width(), widget.get_allocated_height()
        cr.set_source_rgba(0, 0, 0, 0.28)
        cr.set_line_width(1)
        for d in (4, 8, 12):
            cr.move_to(w - d, h - 1.5)
            cr.line_to(w - 1.5, h - d)
        cr.stroke()
        return False

    # -- what it looks like --

    def _apply_colour(self):
        name = self.data.get("colour") if self.data.get("colour") in COLOURS else "yellow"
        paper, strip, _dot = COLOURS[name]
        # A widget's own CSS provider doesn't reach its children, so the
        # window, the strip and each dot get their own.
        self.provider.load_from_data(
            f".sticky {{ background: {paper}; border: 1px solid alpha(black, 0.12); }}".encode())
        self.strip_provider.load_from_data(f".sticky-strip {{ background: {strip}; }}".encode())
        for dot in self.dots.get_children():
            ring = "border: 2px solid alpha(black, 0.5);" if dot.colour == name else ""
            dot.provider.load_from_data(
                f"button.sticky-dot {{ background: {COLOURS[dot.colour][2]}; {ring} }}".encode())

    def set_colour(self, name):
        self.data["colour"] = name
        self._apply_colour()
        self.app.changed()

    def set_float(self, on):
        self.data["float"] = on
        self._apply_layer()
        self.app.changed()

    def _menu(self, event):
        menu = Gtk.Menu()
        for name in ORDER:
            item = Gtk.CheckMenuItem(label=name.capitalize(), draw_as_radio=True,
                                     active=self.data.get("colour", "yellow") == name)
            item.connect("activate", lambda _i, n=name: self.set_colour(n))
            menu.append(item)
        menu.append(Gtk.SeparatorMenuItem())
        floating = Gtk.CheckMenuItem(label="Float on Top", active=bool(self.data.get("float")))
        floating.connect("toggled", lambda i: self.set_float(i.get_active()))
        menu.append(floating)
        new = Gtk.MenuItem(label="New Note")
        new.connect("activate", lambda _i: self.app.new_note(near=self))
        menu.append(new)
        menu.append(Gtk.SeparatorMenuItem())
        toss = Gtk.MenuItem(label="Throw Away Note")
        toss.connect("activate", lambda _i: self.ask_delete())
        menu.append(toss)
        menu.show_all()
        menu.attach_to_widget(self, None)
        menu.popup_at_pointer(event)

    # -- what's on it --

    def _typed(self, buffer):
        self.data["text"] = buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), False)
        self.data["changed"] = time.time()
        self.app.changed()

    def _key(self, _w, event):
        mods = event.state & Gtk.accelerator_get_default_mod_mask()
        if mods == Gdk.ModifierType.CONTROL_MASK and event.keyval in (Gdk.KEY_n, Gdk.KEY_N):
            self.app.new_note(near=self)
            return True
        return False

    def ask_delete(self):
        if self.data.get("text", "").strip():
            self.ask.set_reveal_child(True)
        else:
            self.app.delete_note(self)

    def focus_text(self):
        self.present()
        self.text.grab_focus()


class Stickies(Gtk.Application):
    def __init__(self, restore=False):
        super().__init__(application_id=APP_ID)
        self.restore = restore
        self.notes = []
        self.save_timer = 0

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.hold()
        for data in load():
            self.notes.append(Note(self, data))

    def do_activate(self):
        if self.restore:          # started with the session: only bring back the notes
            self.restore = False
            return
        # From the Dock: a new note, or the empty one that's already there.
        for note in self.notes:
            if not note.data.get("text", "").strip():
                note.focus_text()
                return
        self.new_note()

    def new_note(self, near=None):
        width, height = screen_size()
        if near is not None:
            x, y = near.data["x"] + 30, near.data["y"] + 30
            colour = near.data.get("colour", "yellow")
        else:
            count = len(self.notes)
            x, y = 80 + 30 * (count % 8), 70 + 30 * (count % 8)
            colour = ORDER[count % len(ORDER)]
        if x + DEFAULT_W > width or y + DEFAULT_H > height:
            x, y = 80, 70
        data = {"id": uuid.uuid4().hex, "text": "", "colour": colour, "x": x, "y": y,
                "w": DEFAULT_W, "h": DEFAULT_H, "float": False, "created": time.time()}
        note = Note(self, data)
        self.notes.append(note)
        self.changed()
        GLib.idle_add(lambda: note.focus_text() and False)
        return note

    def delete_note(self, note):
        if note in self.notes:
            self.notes.remove(note)
        note.destroy()
        self.changed()

    def changed(self):
        if self.save_timer:
            GLib.source_remove(self.save_timer)
        self.save_timer = GLib.timeout_add(400, self._save)

    def _save(self):
        self.save_timer = 0
        try:
            save([n.data for n in self.notes])
        except OSError as error:
            print(f"stickies: couldn't keep the notes: {error}", file=sys.stderr)
        return False


def main(argv=None):
    argv = sys.argv if argv is None else argv
    GLib.set_prgname("freemac-stickies")
    return Stickies(restore="--restore" in argv).run(None)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
