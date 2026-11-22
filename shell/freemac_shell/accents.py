# SPDX-License-Identifier: GPL-3.0-or-later
"""Press and hold a letter for its accents, as on a Mac: hold e in a text
field and a small panel by the text cursor offers è é ê ë ē ė ę, each with a
number under it. Press the number, or click the letter, and it takes the
place of the e you typed. The arrow keys and Return pick one too; Escape, or
any other key, closes the panel.

Strata watches the keyboard (strata/shell/press-hold.hpp) and tells Topline
over its socket: "accent show LETTER X Y H" (the text cursor's place in the
layout and its height, 0 when only the window is known), then "accent pick
N", "accent move -1|1", "accent enter", "accent close" and "accent click"
(a click somewhere). Topline asks Strata to type the pick
(strata/accent-type), or types it with wtype when the app has no text field
Strata can reach, and says when the panel has gone (strata/accent-closed).

freemac-im, a quiet input method Topline starts, is what makes apps say
which text field has the keyboard and where its cursor is.
Dials > Keyboard can turn this off, so held letters repeat instead.
Original freemac code.
"""
import shutil
import subprocess

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, Gtk, GtkLayerShell  # noqa: E402

from . import style  # noqa: E402
from .wfipc import Connection  # noqa: E402

# Each letter's accented forms, in the order the panel shows them.
ACCENTS = {
    "a": "àáâäæãåā",
    "c": "çćč",
    "e": "èéêëēėę",
    "i": "îïíīįì",
    "l": "ł",
    "n": "ñń",
    "o": "ôöòóœøōõ",
    "s": "ßśš",
    "u": "ûüùúū",
    "y": "ÿ",
    "z": "žźż",
}

GAP = 6          # between the panel and the text cursor
TOP_BAR = 32     # the menu bar; the panel goes under the cursor rather than behind it

CSS = b"""
window.accents-window, window.accents-window > * { background: transparent; }
.accents-panel {
    margin: 4px 14px 16px 14px;
    padding: 4px;
    border-radius: 9px;
    background-color: rgba(250, 250, 252, 0.96);
    border: 1px solid rgba(0, 0, 0, 0.12);
    box-shadow: 0 3px 10px rgba(0, 0, 0, 0.22);
}
.accents-panel.dark { background-color: rgba(48, 48, 52, 0.96); border-color: rgba(255, 255, 255, 0.14); }
.accents-pick { padding: 2px 6px 1px 6px; border-radius: 6px; border: none; background: transparent;
                box-shadow: none; min-width: 26px; }
.accents-pick:hover { background-color: rgba(0, 0, 0, 0.07); }
.accents-panel.dark .accents-pick:hover { background-color: rgba(255, 255, 255, 0.10); }
.accents-pick.chosen, .accents-pick.chosen:hover { background-color: @theme_selected_bg_color; }
.accents-letter { font-size: 19px; }
.accents-number { font-size: 10px; color: rgba(0, 0, 0, 0.45); }
.accents-panel.dark .accents-number { color: rgba(255, 255, 255, 0.5); }
.accents-pick.chosen .accents-letter, .accents-pick.chosen .accents-number { color: white; }
"""


def choices(letter):
    """The accents to offer for `letter` (upper case gives upper case)."""
    lower = letter.lower()
    forms = ACCENTS.get(lower, "")
    if letter == lower:
        return list(forms)
    # ß has no capital of its own here: a held S offers Ś Š.
    return [form.upper() for form in forms if len(form.upper()) == 1]


def parse(line):
    """("show", letter, x, y, height), ("pick", n), ("move", step),
    ("enter",), ("close",) or ("click",); None for anything else."""
    words = line.split()
    if len(words) < 2 or words[0] != "accent":
        return None
    try:
        if words[1] == "show" and len(words) == 6 and len(words[2]) == 1:
            return ("show", words[2], int(words[3]), int(words[4]), int(words[5]))
        if words[1] == "pick" and len(words) == 3:
            return ("pick", int(words[2]))
        if words[1] == "move" and len(words) == 3 and words[2] in ("-1", "1"):
            return ("move", int(words[2]))
    except ValueError:
        return None
    if len(words) == 2 and words[1] in ("enter", "close", "click"):
        return (words[1],)
    return None


def place(x, y, height, width, panel_height, screen):
    """Where the panel's top-left goes, in the screen's coordinates: above
    the text cursor with its first letter over it, or under the cursor when
    there's no room above; centred on (x, y) when only the window is known.
    `screen` is (width, height)."""
    if height <= 0:
        left, top = x - width // 2, y - panel_height // 2
    else:
        left = x - 22
        top = y - GAP - panel_height
        if top < TOP_BAR:
            top = y + height + GAP
    left = max(0, min(left, screen[0] - width))
    top = max(0, min(top, screen[1] - panel_height))
    return left, top


class AccentPanel(Gtk.Window):
    def __init__(self):
        super().__init__(title="Accents")
        style.make_transparent(self)
        self.get_style_context().add_class("accents-window")
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "freemac-accents")
        # The app keeps the keyboard; Strata passes the panel its keys.
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)
        GtkLayerShell.set_exclusive_zone(self, -1)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.LEFT):
            GtkLayerShell.set_anchor(self, edge, True)
        self.forms = []
        self.buttons = []
        self.chosen = -1
        self.inside = False
        self.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        self.connect("enter-notify-event", self._entered)
        self.connect("leave-notify-event", self._left)

    # -- what Strata says
    def handle(self, line):
        message = parse(line)
        if message is None:
            return
        kind = message[0]
        if kind == "show":
            self.open(*message[1:])
        elif not self.get_visible():
            return
        elif kind == "pick":
            if 1 <= message[1] <= len(self.forms):
                self.pick(message[1] - 1)
        elif kind == "move":
            self._choose((self.chosen + message[1]) % len(self.forms) if self.chosen >= 0
                         else (0 if message[1] > 0 else len(self.forms) - 1))
        elif kind == "enter":
            if self.chosen >= 0:
                self.pick(self.chosen)
            else:
                self.close()
        elif kind == "close":
            self.close()
        elif kind == "click" and not self.inside:
            self.close()

    def open(self, letter, x, y, height):
        forms = choices(letter)
        if not forms:
            self.close()
            return
        self.forms = forms
        self.chosen = -1
        self.inside = False
        child = self.get_child()
        if child:
            self.remove(child)
        self.add(self._build())
        display = Gdk.Display.get_default()
        monitor = display.get_monitor_at_point(x, y) if display else None
        screen = (1 << 16, 1 << 16)
        if monitor is not None:
            GtkLayerShell.set_monitor(self, monitor)
            geometry = monitor.get_geometry()
            x, y = x - geometry.x, y - geometry.y
            screen = (geometry.width, geometry.height)
        self.get_child().show_all()
        width, panel_height = self.get_preferred_size()[1].width, self.get_preferred_size()[1].height
        left, top = place(x, y, height, width, panel_height, screen)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, left)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, top)
        self.show_all()

    def close(self):
        was = self.get_visible()
        self.hide()
        self.inside = False
        if was:
            try:
                Connection().call("strata/accent-closed")
            except (OSError, ValueError):
                pass

    def pick(self, index):
        text = self.forms[index]
        # Type first, then hide: the app is told about its text field again
        # as the panel goes.
        typed = False
        try:
            typed = bool(Connection().call("strata/accent-type", text=text).get("typed"))
        except (OSError, ValueError):
            pass
        self.hide()
        self.inside = False
        if not typed and shutil.which("wtype"):
            # The app doesn't say where its text is: take the letter back with
            # Backspace and type the accent, as a keyboard would.
            subprocess.Popen(["wtype", "-k", "BackSpace", "--", text],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # -- the panel's contents
    def _build(self):
        panel = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=1)
        context = panel.get_style_context()
        context.add_class("accents-panel")
        if style.is_dark():
            context.add_class("dark")
        self.buttons = []
        for index, form in enumerate(self.forms):
            button = Gtk.Button()
            button.get_style_context().add_class("accents-pick")
            button.set_relief(Gtk.ReliefStyle.NONE)
            button.set_can_focus(False)
            column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
            glyph = Gtk.Label(label=form)
            glyph.get_style_context().add_class("accents-letter")
            number = Gtk.Label(label=str(index + 1))
            number.get_style_context().add_class("accents-number")
            column.pack_start(glyph, False, False, 0)
            column.pack_start(number, False, False, 0)
            button.add(column)
            button.connect("clicked", lambda _b, i=index: self.pick(i))
            button.connect("enter-notify-event", lambda _b, _e, i=index: self._choose(i))
            panel.pack_start(button, False, False, 0)
            self.buttons.append(button)
        return panel

    def _choose(self, index):
        for i, button in enumerate(self.buttons):
            context = button.get_style_context()
            if i == index:
                context.add_class("chosen")
            else:
                context.remove_class("chosen")
        self.chosen = index
        return False

    def _entered(self, _widget, event):
        if event.window == self.get_window():
            self.inside = True
        return False

    def _left(self, _widget, event):
        if event.window == self.get_window() and event.detail != Gdk.NotifyType.INFERIOR:
            self.inside = False
        return False


def start_input_method():
    """Start freemac-im, so apps say which text field has the keyboard. A
    second copy leaves by itself, so starting it again does no harm."""
    if shutil.which("freemac-im"):
        try:
            subprocess.Popen(["freemac-im"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
        except OSError:
            pass
