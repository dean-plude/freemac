# SPDX-License-Identifier: GPL-3.0-or-later
"""Seek: freemac's search launcher (Super+Space).

Finds applications, files in your home folder, and answers simple sums.
"""
import ast
import operator
import os
import re

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gio, Gtk, GtkLayerShell  # noqa: E402

from . import style  # noqa: E402

MAX_RESULTS = 8
OPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
       ast.Div: operator.truediv, ast.Pow: operator.pow, ast.Mod: operator.mod,
       ast.USub: operator.neg, ast.UAdd: operator.pos}


def calculate(text):
    """Evaluate plain arithmetic safely; return None if it isn't a sum."""
    text = text.replace("x", "*").replace("×", "*").replace("^", "**")
    if not re.fullmatch(r"[0-9.+\-*/%() ]+", text) or re.fullmatch(r"\d{4}-\d{1,2}-\d{1,2}", text):
        return None
    if not any(ch.isdigit() for ch in text) or not any(ch in "+-*/%" for ch in text):
        return None
    try:
        tree = ast.parse(text, mode="eval")
    except SyntaxError:
        return None

    def ev(node):
        if isinstance(node, ast.Expression):
            return ev(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            return node.value
        if isinstance(node, ast.BinOp) and type(node.op) in OPS:
            if isinstance(node.op, ast.Pow) and abs(ev(node.right)) > 100:
                raise ValueError("exponent too large")
            return OPS[type(node.op)](ev(node.left), ev(node.right))
        if isinstance(node, ast.UnaryOp) and type(node.op) in OPS:
            return OPS[type(node.op)](ev(node.operand))
        raise ValueError("not arithmetic")

    try:
        value = ev(tree)
    except (ValueError, ZeroDivisionError, OverflowError):
        return None
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    return f"{value:,}" if isinstance(value, int) else f"{value:,.6g}"


def score_app(info, query):
    q = query.lower()
    name = (info.get_name() or "").lower()
    if name.startswith(q):
        return 0
    if any(word.startswith(q) for word in name.split()):
        return 1
    if q in name:
        return 2
    extra = " ".join(filter(None, [info.get_description() or "", " ".join(info.get_keywords() or []),
                                   info.get_executable() or ""])).lower()
    return 3 if q in extra else None


def find_files(query, limit):
    home = os.path.expanduser("~")
    q = query.lower()
    found = []
    for root, dirs, files in os.walk(home):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in dirs + files:
            if q in name.lower():
                found.append(os.path.join(root, name))
                if len(found) >= limit:
                    return found
        if root.count(os.sep) - home.count(os.sep) > 4:
            dirs[:] = []
    return found


class Result:
    def __init__(self, title, subtitle, icon, action):
        self.title, self.subtitle, self.icon, self.action = title, subtitle, icon, action


class SeekWindow(Gtk.Window):
    def __init__(self, app):
        super().__init__(application=app, title="Seek")
        style.make_transparent(self)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "freemac-seek")
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 160)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        self.set_size_request(640, -1)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.get_style_context().add_class("seek")
        self.add(box)
        self.entry = Gtk.SearchEntry(placeholder_text="Search apps and files")
        self.entry.connect("search-changed", self._changed)
        self.entry.connect("activate", lambda _e: self._run(0))
        box.pack_start(self.entry, False, False, 0)
        self.listbox = Gtk.ListBox()
        self.listbox.connect("row-activated", lambda _l, row: self._run(row.get_index()))
        box.pack_start(self.listbox, False, False, 0)
        self.hint = Gtk.Label(label="Enter to open · Esc to close", xalign=0)
        self.hint.get_style_context().add_class("hint")
        box.pack_start(self.hint, False, False, 0)
        self.connect("key-press-event", self._key)
        self.results = []
        self.query = ""
        self.apps = [a for a in Gio.AppInfo.get_all() if a.should_show()]

    def _key(self, _w, event):
        from gi.repository import Gdk

        if event.keyval == Gdk.KEY_Escape:
            self.close()
            return True
        if event.keyval in (Gdk.KEY_Down, Gdk.KEY_Up) and self.results:
            row = self.listbox.get_selected_row()
            index = row.get_index() if row else -1
            index += 1 if event.keyval == Gdk.KEY_Down else -1
            index = max(0, min(len(self.results) - 1, index))
            self.listbox.select_row(self.listbox.get_row_at_index(index))
            return True
        if event.keyval == Gdk.KEY_Return:
            if self.entry.get_text().strip() != self.query:
                # Typed faster than the search updates: search now so Enter
                # opens the best match for what's in the field.
                self._changed(self.entry)
            row = self.listbox.get_selected_row()
            self._run(row.get_index() if row else 0)
            return True
        return False

    def _changed(self, _entry):
        query = self.query = self.entry.get_text().strip()
        results = []
        if query:
            answer = calculate(query)
            if answer is not None:
                results.append(Result(answer, f"{query} =", Gio.ThemedIcon.new("accessories-calculator"),
                                      lambda a=answer: Gtk.Clipboard.get_default(self.get_display()).set_text(a, -1)))
            scored = sorted(((score_app(a, query), a.get_name(), a) for a in self.apps
                             if score_app(a, query) is not None), key=lambda t: (t[0], t[1].lower()))
            for _score, _name, info in scored[:MAX_RESULTS]:
                results.append(Result(info.get_name(), "Application", info.get_icon(),
                                      lambda i=info: i.launch([], None)))
            if len(query) >= 2:
                for path in find_files(query, MAX_RESULTS - len(results)):
                    results.append(Result(os.path.basename(path), path.replace(os.path.expanduser("~"), "~", 1),
                                          Gio.ThemedIcon.new("folder" if os.path.isdir(path) else "text-x-generic"),
                                          lambda p=path: Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(p).get_uri(), None)))
        self._show(results[:MAX_RESULTS])

    def _show(self, results):
        for child in self.listbox.get_children():
            self.listbox.remove(child)
        self.results = results
        for res in results:
            row = Gtk.Box(spacing=12)
            image = Gtk.Image.new_from_gicon(res.icon or Gio.ThemedIcon.new("application-x-executable"),
                                             Gtk.IconSize.DND)
            image.set_pixel_size(32)
            row.pack_start(image, False, False, 0)
            text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            title = Gtk.Label(label=res.title, xalign=0)
            sub = Gtk.Label(label=res.subtitle, xalign=0)
            sub.get_style_context().add_class("hint")
            text.pack_start(title, False, False, 0)
            text.pack_start(sub, False, False, 0)
            row.pack_start(text, True, True, 0)
            self.listbox.add(row)
        self.listbox.show_all()
        if results:
            self.listbox.select_row(self.listbox.get_row_at_index(0))
        self.resize(640, 1)

    def _run(self, index):
        if 0 <= index < len(self.results):
            self.results[index].action()
            self.close()


class Seek(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.freemac.Seek")

    def do_activate(self):
        windows = self.get_windows()
        if windows:  # Super+Space again closes it.
            windows[0].close()
            return
        style.apply()
        win = SeekWindow(self)
        win.show_all()
        win.entry.grab_focus()


def main():
    Seek().run(None)
