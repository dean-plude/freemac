# SPDX-License-Identifier: GPL-3.0-or-later
"""Jot: quick notes.

Each note is a plain text file in ~/Documents/Notes, so notes are ordinary
files: Drawer shows them, Seek finds the words in them, and any editor opens
them. The first line is the note's title. The list on the left shows the
newest first and narrows as you type in the search field; the note on the
right saves itself a moment after you stop typing.
"""
import os
import re
import sys
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Jot"
SAVE_DELAY = 800   # ms after the last key press


def notes_dir():
    docs = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOCUMENTS) or os.path.expanduser("~/Documents")
    return os.path.join(docs, "Notes")


def title_of(text):
    for line in text.splitlines():
        line = line.strip().lstrip("#").strip()
        if line:
            return line[:80]
    return "New Note"


def file_name_for(text, folder, current=None):
    """A file name from the title, unique in folder (current keeps its own)."""
    base = re.sub(r"[^\w\- ]+", "", title_of(text)).strip()[:60] or "Note"
    name = f"{base}.txt"
    n = 2
    while os.path.exists(os.path.join(folder, name)) and os.path.join(folder, name) != current:
        name = f"{base} {n}.txt"
        n += 1
    return os.path.join(folder, name)


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def list_notes(folder):
    """[(path, mtime, text)] newest first."""
    try:
        names = [n for n in os.listdir(folder) if n.endswith((".txt", ".md")) and not n.startswith(".")]
    except OSError:
        return []
    found = []
    for name in names:
        path = os.path.join(folder, name)
        try:
            found.append((path, os.stat(path).st_mtime, read(path)))
        except OSError:
            pass
    return sorted(found, key=lambda n: n[1], reverse=True)


def when(stamp):
    now = time.localtime()
    t = time.localtime(stamp)
    if t[:3] == now[:3]:
        return time.strftime("%-I:%M %p", t)
    if t.tm_year == now.tm_year:
        return time.strftime("%b %-d", t)
    return time.strftime("%b %-d, %Y", t)


def preview(text):
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    return " ".join(lines[1:])[:120] if len(lines) > 1 else "No more text"


class Row(Gtk.ListBoxRow):
    def __init__(self, path, mtime, text):
        super().__init__()
        self.path = path
        self.text = text
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, margin=8)
        self.title = Gtk.Label(label=title_of(text), xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.title.get_style_context().add_class("jot-title")
        line = Gtk.Box(spacing=6)
        self.stamp = Gtk.Label(label=when(mtime), xalign=0)
        self.snippet = Gtk.Label(label=preview(text), xalign=0, ellipsize=Pango.EllipsizeMode.END)
        for label in (self.stamp, self.snippet):
            label.get_style_context().add_class("dim-label")
        line.pack_start(self.stamp, False, False, 0)
        line.pack_start(self.snippet, True, True, 0)
        box.pack_start(self.title, False, False, 0)
        box.pack_start(line, False, False, 0)
        self.add(box)

    def update(self, text, mtime):
        self.text = text
        self.title.set_text(title_of(text))
        self.stamp.set_text(when(mtime))
        self.snippet.set_text(preview(text))


CSS = b"""
.jot-title { font-weight: bold; }
.jot-sidebar { border-right: 1px solid alpha(currentColor, 0.12); }
.jot-page { font-size: 15px; }
"""


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Jot")
        self.set_default_size(820, 540)
        self.set_icon_name("freemac-jot")
        self.folder = notes_dir()
        os.makedirs(self.folder, exist_ok=True)
        self.current = None       # the Row being edited
        self.save_timer = None
        self.check_timer = None

        paned = Gtk.Paned()
        self.add(paned)
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.get_style_context().add_class("jot-sidebar")
        side.set_size_request(250, -1)
        top = Gtk.Box(spacing=6, margin=8)
        self.search = Gtk.SearchEntry(placeholder_text="Search notes")
        self.search.connect("search-changed", lambda *_: self.listbox.invalidate_filter())
        new = Gtk.Button.new_from_icon_name("document-new-symbolic", Gtk.IconSize.BUTTON)
        new.set_tooltip_text("New Note (⌘N)")
        new.connect("clicked", lambda *_: self.new_note())
        top.pack_start(self.search, True, True, 0)
        top.pack_start(new, False, False, 0)
        side.pack_start(top, False, False, 0)
        self.listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.BROWSE)
        self.listbox.set_filter_func(self._filter)
        self.listbox.connect("row-selected", self._selected)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.add(self.listbox)
        side.pack_start(scroll, True, True, 0)
        self.count = Gtk.Label(margin=6)
        self.count.get_style_context().add_class("dim-label")
        side.pack_start(self.count, False, False, 0)
        paned.pack1(side, False, False)

        self.stack = Gtk.Stack()
        self.view = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=24, right_margin=24,
                                 top_margin=20, bottom_margin=20, pixels_below_lines=2)
        self.view.get_style_context().add_class("jot-page")
        self.buffer = self.view.get_buffer()
        self.title_tag = self.buffer.create_tag("title", weight=Pango.Weight.BOLD, scale=1.35,
                                                pixels_below_lines=6)
        self.changed_handler = self.buffer.connect("changed", self._changed)
        page = Gtk.ScrolledWindow()
        page.add(self.view)
        self.stack.add_named(page, "note")
        empty = Gtk.Label(label="No note selected.\nPress ⌘N for a new one.", justify=Gtk.Justification.CENTER)
        empty.get_style_context().add_class("dim-label")
        self.stack.add_named(empty, "empty")
        paned.pack2(self.stack, True, False)

        menus.add_actions(self, {
            "new-note": self.new_note,
            "delete-note": self.delete_note,
            "find": self.search.grab_focus,
            "show-folder": self.show_folder,
            "close": self.close,
        })
        self.connect("key-press-event", self._key)
        self.connect("delete-event", lambda *_: self.save_now() and False)
        self.monitor = Gio.File.new_for_path(self.folder).monitor_directory(Gio.FileMonitorFlags.NONE, None)
        self.monitor.connect("changed", self._folder_changed)
        self.reload()
        self.show_all()
        if self.current is None:
            self.stack.set_visible_child_name("empty")

    # -- the list -------------------------------------------------------------
    def reload(self, keep=None):
        keep = keep or (self.current.path if self.current else None)
        for row in self.listbox.get_children():
            self.listbox.remove(row)
        chosen = None
        for path, mtime, text in list_notes(self.folder):
            row = Row(path, mtime, text)
            self.listbox.add(row)
            if path == keep:
                chosen = row
                if self.current is not None and self.current.path == path:
                    self.current = row    # same note: keep what's in the editor
        self.listbox.show_all()
        rows = self.listbox.get_children()
        self.count.set_text(f"{len(rows)} note{'s' if len(rows) != 1 else ''}")
        if chosen is None and rows:
            chosen = rows[0]
        if chosen is not None:
            self.listbox.select_row(chosen)
        else:
            self.current = None
            self.stack.set_visible_child_name("empty")

    def _filter(self, row):
        words = self.search.get_text().strip().lower().split()
        return all(w in row.text.lower() for w in words)

    def _selected(self, _box, row):
        if row is None or row is self.current:
            return
        self.save_now()
        self.current = row
        with self.buffer.handler_block(self.changed_handler):
            self.buffer.set_text(read(row.path))
            self.buffer.place_cursor(self.buffer.get_start_iter())
            self._style_title()
        self.stack.set_visible_child_name("note")
        self.set_title(f"{title_of(row.text)} – Jot")

    def _folder_changed(self, _monitor, _file, _other, event):
        if event in (Gio.FileMonitorEvent.CREATED, Gio.FileMonitorEvent.DELETED,
                     Gio.FileMonitorEvent.MOVED_IN, Gio.FileMonitorEvent.MOVED_OUT):
            if not self.check_timer:
                self.check_timer = GLib.timeout_add(400, self._check_folder)

    def _check_folder(self):
        """Reload only when notes were added or removed by something else."""
        self.check_timer = None
        on_disk = {path for path, _m, _t in list_notes(self.folder)}
        if on_disk != {row.path for row in self.listbox.get_children()}:
            self.reload()
        return False

    # -- editing --------------------------------------------------------------
    def _style_title(self):
        """The first line is the title, so it is shown larger."""
        start, end = self.buffer.get_bounds()
        self.buffer.remove_tag(self.title_tag, start, end)
        line_end = self.buffer.get_start_iter()
        if not line_end.ends_line():
            line_end.forward_to_line_end()
        self.buffer.apply_tag(self.title_tag, self.buffer.get_start_iter(), line_end)

    def _changed(self, _buffer):
        self._style_title()
        if self.save_timer:
            GLib.source_remove(self.save_timer)
        self.save_timer = GLib.timeout_add(SAVE_DELAY, self.save_now)

    def text(self):
        return self.buffer.get_text(self.buffer.get_start_iter(), self.buffer.get_end_iter(), True)

    def save_now(self):
        if self.save_timer:
            GLib.source_remove(self.save_timer)
            self.save_timer = None
            row = self.current
            if row is not None:
                text = self.text()
                path = row.path
                # The file follows the title, as long as it isn't the user's own name for it.
                if os.path.basename(path).startswith(re.sub(r"[^\w\- ]+", "", title_of(row.text))[:60] or "Note"):
                    wanted = file_name_for(text, self.folder, current=path)
                    if wanted != path:
                        try:
                            os.rename(path, wanted)
                            path = row.path = wanted
                        except OSError:
                            pass
                tmp = os.path.join(self.folder, "." + os.path.basename(path) + ".tmp")
                with open(tmp, "w", encoding="utf-8") as f:
                    f.write(text)
                os.replace(tmp, path)
                row.update(text, os.stat(path).st_mtime)
                self.set_title(f"{title_of(text)} – Jot")
                if self.listbox.get_children()[0] is not row:
                    self.listbox.remove(row)
                    self.listbox.prepend(row)
                    self.listbox.select_row(row)
        return False

    def new_note(self):
        self.save_now()
        self.search.set_text("")
        path = file_name_for("New Note", self.folder)
        with open(path, "w", encoding="utf-8") as f:
            f.write("")
        self.reload(keep=path)
        self.view.grab_focus()

    def delete_note(self):
        row = self.current
        if row is None:
            return
        if self.save_timer:
            GLib.source_remove(self.save_timer)
            self.save_timer = None
        try:
            Gio.File.new_for_path(row.path).trash(None)
        except GLib.Error:
            try:
                os.remove(row.path)
            except OSError:
                return
        self.current = None
        self.reload()

    def show_folder(self):
        Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(self.folder).get_uri(), None)

    def _key(self, _w, event):
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        key = Gdk.keyval_to_lower(event.keyval)
        if ctrl and key == Gdk.KEY_n:
            self.new_note()
        elif ctrl and key == Gdk.KEY_f:
            self.search.grab_focus()
        elif ctrl and key == Gdk.KEY_w:
            self.close()
        elif ctrl and key == Gdk.KEY_Delete:
            self.delete_note()
        else:
            return False
        return True


def menubar():
    return menus.menubar([
        ("_File", [[("New Note", "app.new-note", "<Ctrl>n")],
                   [("Show Notes Folder", "win.show-folder", None)],
                   [("Move Note to Trash", "win.delete-note", "<Ctrl>Delete")],
                   [("Close Window", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Find", "win.find", "<Ctrl>f")]]),
    ])


class Jot(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        quit_action = Gio.SimpleAction.new("quit", None)
        quit_action.connect("activate", lambda *_: GLib.idle_add(self.quit))
        self.add_action(quit_action)
        # Jot stays open with no window, as a Mac app does; Quit ends it.
        # New Note works from the menu bar even with no window open.
        new_note = Gio.SimpleAction.new("new-note", None)
        new_note.connect("activate", lambda *_: self._new_note())
        self.add_action(new_note)
        self.hold()
        self.set_menubar(menubar())

    def _new_note(self):
        window = self.get_active_window() or Window(self)
        window.present()
        window.activate_action("new-note", None)

    def do_activate(self):
        (self.get_active_window() or Window(self)).present()


def main():
    return Jot().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
