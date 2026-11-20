# SPDX-License-Identifier: GPL-3.0-or-later
"""Seek: freemac's search launcher (Super+Space).

Finds applications, settings, Guide topics, the front app's menu items,
files in your home folder (by name, and by the text inside them through
seek_index), and answers simple sums.
"""
import ast
import datetime as dt
import operator
import os
import re
import threading
import time
import urllib.parse

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import calendar_store, contacts_store, dials_pages, guide_topics, seek_index, style  # noqa: E402

MAX_RESULTS = 8
PREVIEW = 280      # width of the preview beside the results
PICTURE = 240      # most a picture's preview may measure
TEXT_LINES = 12    # lines of a text file shown in its preview
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


def short(path):
    home = os.path.expanduser("~")
    return "~" + path[len(home):] if path == home or path.startswith(home + os.sep) else path


def open_path(path):
    Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(path).get_uri(), None)


TOPLINE = ("org.freemac.Topline", "/org/freemac/Topline", "org.freemac.Topline")


def launch(*argv):
    try:
        GLib.spawn_async(list(argv), flags=GLib.SpawnFlags.SEARCH_PATH)
    except GLib.Error:
        pass


def _topline(method, args, reply):
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        return bus.call_sync(*TOPLINE, method, args, GLib.VariantType.new(reply) if reply else None,
                             Gio.DBusCallFlags.NO_AUTO_START, 300, None)
    except GLib.Error:
        return None


def menu_items(query):
    """(name, where, shortcut) of the front app's menu items that match, from
    the menu bar, and the app's icon; nothing if the bar isn't there to ask."""
    answer = _topline("SearchMenus", GLib.Variant("(s)", (query,)), "(a(sss)s)")
    if answer is None:
        return [], None
    found, icon = answer.unpack()
    try:
        return found, Gio.Icon.new_for_string(icon)
    except GLib.Error:
        return found, None


def run_menu_item(index):
    _topline("RunMenuItem", GLib.Variant("(u)", (index,)), None)


class Result:
    """One line of results. about is a sentence for the preview; path, a
    file whose preview shows what's in it."""

    def __init__(self, title, subtitle, icon, action, about="", path=None):
        self.title, self.subtitle, self.icon, self.action = title, subtitle, icon, action
        self.about, self.path = about, path


def size_text(size):
    for unit in ("bytes", "KB", "MB", "GB"):
        if size < 1000 or unit == "GB":
            return f"{size:,} {unit}" if unit == "bytes" else f"{size:,.1f} {unit}"
        size /= 1000
    return ""


def file_facts(path):
    """Kind, size and when changed, for a file's preview."""
    try:
        info = Gio.File.new_for_path(path).query_info("standard::content-type,standard::size,time::modified",
                                                      Gio.FileQueryInfoFlags.NONE, None)
    except GLib.Error:
        return []
    kind = Gio.content_type_get_description(info.get_content_type() or "") or "Document"
    facts = ["Folder" if os.path.isdir(path) else kind]
    if not os.path.isdir(path):
        facts.append(size_text(info.get_size()))
    changed = info.get_attribute_uint64("time::modified")
    if changed:
        facts.append("Modified " + time.strftime("%-d %b %Y, %-I:%M %p", time.localtime(changed)))
    return facts


def first_lines(path):
    """The start of a text file, or "" for anything else."""
    kind, _uncertain = Gio.content_type_guess(path, None)
    if not Gio.content_type_is_a(kind or "", "text/plain") or os.path.isdir(path):
        return ""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = [f.readline().rstrip("\n")[:60] for _ in range(TEXT_LINES)]
    except OSError:
        return ""
    return "\n".join(lines).rstrip()


def picture(path):
    """A small version of a picture file, or of a PDF's first page, or None."""
    kind, _uncertain = Gio.content_type_guess(path, None)
    if Gio.content_type_is_a(kind or "", "application/pdf"):
        from . import pdf   # Poppler loads only when a PDF is chosen
        return pdf.first_page(path, PICTURE)
    if not (kind or "").startswith("image/"):
        return None
    try:
        return GdkPixbuf.Pixbuf.new_from_file_at_size(path, PICTURE, PICTURE)
    except GLib.Error:
        return None


class SeekWindow(Gtk.Window):
    def __init__(self, app):
        super().__init__(application=app, title="Seek")
        style.make_transparent(self)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "freemac-seek")
        # Seek covers the screen, see-through but for its own panel, so a
        # click anywhere else closes it. (It has the keyboard to itself, so it
        # never hears that another window was clicked.)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                     GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_exclusive_zone(self, -1)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)

        box = self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, halign=Gtk.Align.CENTER,
                                 valign=Gtk.Align.START, margin_top=160)
        box.set_size_request(600 + PREVIEW, -1)
        box.get_style_context().add_class("seek")
        self.add(box)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.connect("button-press-event", self._pressed)
        self.entry = Gtk.SearchEntry(placeholder_text="Search apps, files and what's in them")
        self.entry.connect("search-changed", self._changed)
        self.entry.connect("activate", lambda _e: self._run(0))
        box.pack_start(self.entry, False, False, 0)
        # The results, and beside them a preview of the one chosen, as on a Mac.
        middle = Gtk.Box(spacing=0)
        self.listbox = Gtk.ListBox(valign=Gtk.Align.START)
        self.listbox.connect("row-activated", lambda _l, row: self._run(row.get_index()))
        self.listbox.connect("row-selected", lambda _l, row: self._preview(row))
        middle.pack_start(self.listbox, True, True, 0)
        self.preview = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.preview.set_size_request(PREVIEW, -1)
        self.preview.get_style_context().add_class("seek-preview")
        middle.pack_start(self.preview, False, False, 0)
        box.pack_start(middle, False, False, 0)
        self.hint = Gtk.Label(label="Enter to open · Esc to close", xalign=0)
        self.hint.get_style_context().add_class("hint")
        box.pack_start(self.hint, False, False, 0)
        self.connect("key-press-event", self._key)
        self.results = []
        self.query = ""
        self.apps = [a for a in Gio.AppInfo.get_all() if a.should_show()]
        # Bring the index of words in files up to date while the person types.
        self.stop = threading.Event()
        threading.Thread(target=self._index, daemon=True).start()
        self.connect("destroy", lambda *_: self.stop.set())

    def _index(self):
        try:
            changed = seek_index.update(stop=self.stop)
        except Exception:   # a broken index must never break the launcher
            return
        if changed and not self.stop.is_set():
            GLib.idle_add(lambda: self.query and self._changed(self.entry) and False)

    def _pressed(self, _w, event):
        inside = self.box.get_allocation()
        if not (inside.x <= event.x < inside.x + inside.width and inside.y <= event.y < inside.y + inside.height):
            self.close()
        return False

    def _key(self, _w, event):

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
                                      lambda a=answer: Gtk.Clipboard.get_default(self.get_display()).set_text(a, -1),
                                      about="Press Return to copy the answer."))
            scored = sorted(((score_app(a, query), a.get_name(), a) for a in self.apps
                             if score_app(a, query) is not None), key=lambda t: (t[0], t[1].lower()))
            apps = [Result(info.get_name(), "Application", info.get_icon(),
                           lambda i=info: i.launch([], None), about=info.get_description() or "")
                    for _score, _name, info in scored[:MAX_RESULTS]]
            # Apps whose name matches come first; one found only by what it's
            # for (Dials for "wallpaper") comes after the settings page itself.
            named_apps = sum(1 for score, _name, _info in scored[:MAX_RESULTS] if score < 3)
            results += apps[:named_apps]
            # Settings by name or by what's on the page ("wallpaper", "night
            # light"), opened in Dials at that page.
            for name in dials_pages.matching(query)[:2]:
                title, _symbol = dials_pages.PAGES[name]
                results.append(Result(title, "Settings", Gio.ThemedIcon.new("freemac-dials"),
                                      lambda n=name: launch("freemac-dials", "--panel", n),
                                      about=f"Opens Dials at {title}."))
            # How-to topics in Guide ("screenshot", "wifi").
            if len(query) >= 3:
                for name in guide_topics.matching(query)[:1]:
                    title, _usual, body = guide_topics.TOPICS[name]
                    results.append(Result(title, "Guide", Gio.ThemedIcon.new("freemac-guide"),
                                          lambda n=name: launch("freemac-guide", "--topic", n),
                                          about=body[0].lstrip("- ")))
            # The app in front's own menu items, as its Help menu finds them.
            if len(query) >= 2:
                found, app_icon = menu_items(query)
                for index, (name, where, keys) in enumerate(found[:2]):
                    results.append(Result(name, f"Menu item: {where}" + (f"  {keys}" if keys else ""),
                                          app_icon or Gio.ThemedIcon.new("application-x-executable"),
                                          lambda i=index: run_menu_item(i),
                                          about=f"Does {name} in {where}, as choosing it in the menu does."))
            # People from Crew and coming events from Tide.
            if len(query) >= 2:
                results += self._people(query)[:2]
                results += self._events(query)[:2]
            results += apps[named_apps:]
            if len(query) >= 2:
                named = find_files(query, MAX_RESULTS - len(results))
                for path in named:
                    results.append(Result(os.path.basename(path), short(path),
                                          Gio.ThemedIcon.new("folder" if os.path.isdir(path) else "text-x-generic"),
                                          lambda p=path: open_path(p), path=path))
                room = MAX_RESULTS - len(results)
                for path, words in seek_index.search(query, room, exclude=set(named)) if room > 0 else []:
                    results.append(Result(os.path.basename(path), f"{short(os.path.dirname(path))}: {words}",
                                          Gio.ThemedIcon.new("text-x-generic"), lambda p=path: open_path(p),
                                          path=path))
        self._show(results[:MAX_RESULTS])

    @staticmethod
    def _people(query):
        found = []
        for person in contacts_store.load():
            if person.matches(query):
                reach = (person.phones[0][1] if person.phones else
                         person.emails[0][1] if person.emails else person.company)
                found.append(Result(person.name, "Contact" + (f": {reach}" if reach else ""),
                                    Gio.ThemedIcon.new("freemac-crew"),
                                    lambda p=person.path: launch("freemac-crew", p),
                                    about=f"Opens {person.name}'s card in Crew."))
        return found

    @staticmethod
    def _events(query):
        """Events from today on, over the next year, whose title or place
        has every word typed."""
        words = query.lower().split()
        today = dt.date.today()
        found, seen = [], set()
        for occ in calendar_store.occurrences(calendar_store.load(), today, today + dt.timedelta(days=366)):
            event = occ.event
            hay = f"{event.title} {event.location}".lower()
            if event.uid in seen or not all(w in hay for w in words):
                continue
            seen.add(event.uid)
            day = occ.start.date()
            when = f"{day:%a %b} {day.day}" + ("" if occ.all_day else f", {calendar_store.time_text(occ.start)}")
            uri = "tide-event:" + urllib.parse.quote(event.uid, safe="") + "@@" + day.isoformat()
            found.append(Result(event.title, f"Event: {when}", Gio.ThemedIcon.new("freemac-tide"),
                                lambda u=uri: launch("freemac-tide", u),
                                about=f"{when}" + (f", {event.location}" if event.location else "")
                                + ". Opens that day in Tide."))
        return found

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
            sub = Gtk.Label(label=res.subtitle, xalign=0, ellipsize=3, max_width_chars=70)
            sub.get_style_context().add_class("hint")
            text.pack_start(title, False, False, 0)
            text.pack_start(sub, False, False, 0)
            row.pack_start(text, True, True, 0)
            self.listbox.add(row)
        self.listbox.show_all()
        if not results:
            self._preview(None)
        if results:
            self.listbox.select_row(self.listbox.get_row_at_index(0))

    def _preview(self, row):
        for child in self.preview.get_children():
            self.preview.remove(child)
        res = self.results[row.get_index()] if row is not None and row.get_index() < len(self.results) else None
        if res is None:
            self.preview.hide()
            return
        shown = picture(res.path) if res.path else None
        if shown is not None:
            image = Gtk.Image.new_from_pixbuf(shown)
        else:
            icon = res.icon or Gio.ThemedIcon.new("application-x-executable")
            if res.path:
                try:
                    icon = Gio.File.new_for_path(res.path).query_info(
                        "standard::icon", Gio.FileQueryInfoFlags.NONE, None).get_icon() or icon
                except GLib.Error:
                    pass
            image = Gtk.Image.new_from_gicon(icon, Gtk.IconSize.DIALOG)
            image.set_pixel_size(96)
        image.set_margin_top(12)
        self.preview.pack_start(image, False, False, 0)
        title = Gtk.Label(label=res.title, wrap=True, max_width_chars=28, justify=Gtk.Justification.CENTER)
        title.get_style_context().add_class("seek-preview-title")
        self.preview.pack_start(title, False, False, 0)
        lines = file_facts(res.path) if res.path else ([res.about] if res.about else [])
        for line in lines:
            label = Gtk.Label(label=line, wrap=True, max_width_chars=34, justify=Gtk.Justification.CENTER)
            label.get_style_context().add_class("hint")
            self.preview.pack_start(label, False, False, 0)
        text = first_lines(res.path) if res.path and shown is None else ""
        if text:
            start = Gtk.Label(label=text, xalign=0, yalign=0, ellipsize=3, max_width_chars=40)
            start.get_style_context().add_class("seek-preview-text")
            self.preview.pack_start(start, False, False, 6)
        self.preview.show_all()

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
        win.preview.hide()
        win.entry.grab_focus()


def main():
    Seek().run(None)
