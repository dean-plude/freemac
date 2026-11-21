# SPDX-License-Identifier: GPL-3.0-or-later
"""Lifeboat: backups of your home folder to a drive, and bringing files back.

One process does both jobs. Started at login with --watch, it keeps an eye
on the backup drive chosen in Dials and backs up every hour while it's
plugged in, writing how it's going to a status file that Dials reads.
Opened from the Dock, Drawer or Dials, it shows a window with every backup
by date: choose a time, find the folder, choose files and click Restore,
and copies come back to where they were.

The watcher has no window of its own, so it isn't listed in held.py and
never shows in the Dock or the menu bar while it works. Original freemac
code.
"""
import os
import shutil
import sys
import tempfile
import threading
import time

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import alert, menus, style, transfer, volumes  # noqa: E402
from . import backup_store as store  # noqa: E402

APP_ID = "org.freemac.Lifeboat"
FIRST_LOOK = 45          # seconds after login or plugging in before backing up
LOOK_EVERY = 60

CSS = b"""
.lifeboat-side { background: alpha(currentColor, 0.04); }
.lifeboat-side row { padding: 5px 14px; }
.lifeboat-day { font-size: 11px; font-weight: 700; color: alpha(currentColor, 0.5);
                padding: 10px 14px 3px 14px; }
.lifeboat-time { font-size: 13px; }
.lifeboat-bar { padding: 8px 12px; border-top: 1px solid alpha(currentColor, 0.1); }
.lifeboat-path button { padding: 2px 6px; min-height: 0; }
.lifeboat-path .lifeboat-sep { color: alpha(currentColor, 0.4); }
.lifeboat-when { font-weight: 600; }
.lifeboat-note { color: alpha(currentColor, 0.6); }
.lifeboat-empty-title { font-size: 17px; font-weight: 600; }
.lifeboat-empty-text { color: alpha(currentColor, 0.65); }
"""


# ---- the drive -------------------------------------------------------------

def drive_id(mount):
    """What identifies a drive from one plug-in to the next: its uuid."""
    uuid = mount.get_uuid()
    if not uuid and mount.get_volume() is not None:
        uuid = mount.get_volume().get_uuid() or mount.get_volume().get_identifier("uuid")
    return uuid or volumes.path_of(mount)


def chosen_drive():
    """(mount, path) of the chosen drive when it's plugged in, else None."""
    wanted = store.settings().get("drive")
    if not wanted:
        return None
    for mount in volumes.drives():
        path = volumes.path_of(mount)
        if path and drive_id(mount) == wanted:
            return mount, path
    return None


# ---- the watcher -------------------------------------------------------------

class Watcher:
    """Backs up every hour while the chosen drive is plugged in."""

    def __init__(self, app):
        self.app = app
        self.thread = None
        self.stop = threading.Event()
        self.warned = False
        self.handlers = volumes.watch(self._drives_changed)
        volumes.monitor().connect("mount-pre-unmount", self._unmounting)
        store.save_status(state="idle", pid=os.getpid(), files=0, bytes=0, current="")
        GLib.timeout_add_seconds(FIRST_LOOK, self._first_look)
        GLib.timeout_add_seconds(LOOK_EVERY, self.look)

    def busy(self):
        return self.thread is not None and self.thread.is_alive()

    def _first_look(self):
        self.look()
        return False

    def _drives_changed(self):
        found = chosen_drive()
        store.save_status(plugged=found is not None)
        if found is None:
            self.warned = False
        else:
            GLib.timeout_add_seconds(FIRST_LOOK, self._first_look)

    def _unmounting(self, _monitor, mount):
        # Let the drive go when someone ejects it, as a Mac does.
        found = chosen_drive()
        if found is not None and found[0] == mount and self.busy():
            self.stop.set()

    def look(self, now=False):
        """Back up if it's time (or now), the drive is here and nothing's running."""
        settings = store.settings()
        if self.busy() or not settings.get("drive"):
            return True
        found = chosen_drive()
        if found is None:
            return True
        last = store.status().get("last_ok") or 0
        if not last:
            newest = store.latest(found[1])
            last = newest[0] if newest else 0
        if now or (settings.get("auto", True) and time.time() - last >= store.EVERY):
            self.start(found[1], found[0].get_name())
        return True

    def start(self, root, name):
        self.stop.clear()
        self.app.hold()
        store.save_status(state="backing-up", started=time.time(), files=0, bytes=0, current="",
                          error=None, drive_name=name)
        self.thread = threading.Thread(target=self._work, args=(root, name), daemon=True)
        self.thread.start()

    def cancel(self):
        if self.busy():
            self.stop.set()

    def _work(self, root, name):
        first = not store.backups(root)
        last_note = [0.0]

        def progress(files, copied, rel):
            now = time.monotonic()
            if now - last_note[0] >= 1:
                last_note[0] = now
                store.save_status(files=files, bytes=copied, current=rel)

        try:
            if not store.can_link(root):
                raise OSError(0, "This drive can't hold backups. Erase it in Dials > Lifeboat to use it.")
            summary = store.back_up(root, progress=progress, stop=self.stop)
        except store.Stopped:
            GLib.idle_add(self._ended, None, "Stopped", name, False)
            return
        except store.NoRoom:
            GLib.idle_add(self._ended, None, "The backup drive is full.", name, False)
            return
        except OSError as error:
            text = error.strerror or str(error)
            if chosen_drive() is None:
                text = "The drive was unplugged during the backup."
            GLib.idle_add(self._ended, None, text, name, False)
            return
        GLib.idle_add(self._ended, summary, None, name, first)

    def _ended(self, summary, error, name, first):
        self.app.release()
        found = chosen_drive()
        everything = store.backups(found[1]) if found else []
        details = {"count": len(everything), "oldest": everything[0][0] if everything else None,
                   "newest": everything[-1][0] if everything else None,
                   "free": store.free(found[1]) if found else None}
        if summary is not None:
            store.save_status(state="idle", last_ok=summary["time"], error=None, current="",
                              last_files=summary["files"], last_bytes=summary["bytes"],
                              skipped=len(summary["errors"]), **details)
            if first:
                self._notify("backed-up", "Lifeboat finished the first backup",
                             f"Your files are backed up on “{name}”. Lifeboat backs up every hour "
                             "while it's plugged in.")
        else:
            store.save_status(state="stopped" if error == "Stopped" else "error",
                              error=None if error == "Stopped" else error, current="", **details)
            if error != "Stopped" and not self.warned:
                self.warned = True
                self._notify("failed", "Lifeboat couldn't finish the backup", error)
        for window in self.app.get_windows():
            if isinstance(window, Window):
                window.refresh_backups()
        return False

    def _notify(self, tag, title, body):
        note = Gio.Notification.new(title)
        note.set_body(body)
        note.set_icon(Gio.ThemedIcon.new("freemac-lifeboat"))
        self.app.send_notification("lifeboat-" + tag, note)


# ---- the window: backups by date, and Restore --------------------------------

def _icon_for(path, is_dir):
    if is_dir:
        return Gio.ThemedIcon.new("folder")
    kind, _uncertain = Gio.content_type_guess(path, None)
    return Gio.content_type_get_icon(kind)


def _what_now(old_path, now_path, is_dir):
    """How the item in the backup compares with the one there now."""
    try:
        now = os.lstat(now_path)
    except OSError:
        return "Gone now"
    if is_dir:
        return ""
    try:
        old = os.lstat(old_path)
    except OSError:
        return ""
    if old.st_size != now.st_size or abs(old.st_mtime - now.st_mtime) >= 1:
        return "Changed since"
    return "Same now"


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Lifeboat")
        self.set_default_size(980, 620)
        self.app = app
        self.rel = ""                # the folder shown, relative to home
        self.chosen = None           # the backup's folder
        self.root = None
        self.select_after = None

        header = Gtk.HeaderBar(show_close_button=True, title="Lifeboat")
        self.back_button = Gtk.Button.new_from_icon_name("go-previous-symbolic", Gtk.IconSize.BUTTON)
        self.back_button.set_tooltip_text("Enclosing Folder (⌘↑)")
        self.back_button.connect("clicked", lambda _b: self.go_up())
        header.pack_start(self.back_button)
        self.search = Gtk.SearchEntry(placeholder_text="Search")
        self.search.set_width_chars(18)
        self.search.connect("search-changed", lambda _e: self.filter.refilter())
        header.pack_end(self.search)
        self.set_titlebar(header)
        self.header = header

        self.stack = Gtk.Stack()
        paned = Gtk.Paned()
        self.side = Gtk.ListBox()
        self.side.get_style_context().add_class("lifeboat-side")
        self.side.set_header_func(self._day_header)
        self.side.connect("row-selected", self._backup_chosen)
        side_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        side_scroll.get_style_context().add_class("lifeboat-side")
        side_scroll.add(self.side)
        side_scroll.set_size_request(200, -1)
        paned.pack1(side_scroll, False, False)

        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.path_bar = Gtk.Box(spacing=0)
        self.path_bar.get_style_context().add_class("lifeboat-path")
        self.path_bar.set_margin_start(8)
        self.path_bar.set_margin_top(6)
        self.path_bar.set_margin_bottom(6)
        right.pack_start(self.path_bar, False, False, 0)
        # name, icon, modified, size words, size (sorting), is folder, compared, path in backup
        self.model = Gtk.ListStore(str, Gio.Icon, str, str, float, bool, str, str)
        self.filter = self.model.filter_new()
        self.filter.set_visible_func(self._visible)
        self.sorted = Gtk.TreeModelSort(model=self.filter)
        self.sorted.set_sort_func(0, self._by_name)
        self.sorted.set_sort_column_id(0, Gtk.SortType.ASCENDING)
        self.tree = Gtk.TreeView(model=self.sorted, headers_clickable=True, enable_search=False)
        self.tree.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE)
        self.tree.get_selection().connect("changed", lambda _s: self._update_bar())
        name_col = Gtk.TreeViewColumn("Name")
        icon_cell = Gtk.CellRendererPixbuf()
        name_col.pack_start(icon_cell, False)
        name_col.add_attribute(icon_cell, "gicon", 1)
        text_cell = Gtk.CellRendererText(ellipsize=Pango.EllipsizeMode.END)
        name_col.pack_start(text_cell, True)
        name_col.add_attribute(text_cell, "text", 0)
        name_col.set_expand(True)
        name_col.set_sort_column_id(0)
        name_col.set_resizable(True)
        self.tree.append_column(name_col)
        for title, column, sort, width in (("Date Modified", 2, 2, 200), ("Size", 3, 4, 90),
                                           ("Now", 6, 6, 120)):
            cell = Gtk.CellRendererText()
            if title == "Size":
                cell.set_property("xalign", 1)
            col = Gtk.TreeViewColumn(title, cell, text=column)
            col.set_sort_column_id(sort)
            col.set_fixed_width(width)
            col.set_resizable(True)
            self.tree.append_column(col)
        self.tree.connect("row-activated", self._activated)
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.tree)
        self.files_stack = Gtk.Stack()
        self.files_stack.add_named(scroll, "files")
        self.missing = Gtk.Label(wrap=True, justify=Gtk.Justification.CENTER)
        self.missing.get_style_context().add_class("lifeboat-empty-text")
        self.files_stack.add_named(self.missing, "missing")
        right.pack_start(self.files_stack, True, True, 0)

        bar = Gtk.Box(spacing=10)
        bar.get_style_context().add_class("lifeboat-bar")
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.when_label = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.when_label.get_style_context().add_class("lifeboat-when")
        self.note_label = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.note_label.get_style_context().add_class("lifeboat-note")
        words.pack_start(self.when_label, False, False, 0)
        words.pack_start(self.note_label, False, False, 0)
        bar.pack_start(words, True, True, 0)
        self.restore_button = Gtk.Button(label="Restore")
        self.restore_button.get_style_context().add_class("suggested-action")
        self.restore_button.connect("clicked", lambda _b: self.restore())
        bar.pack_end(self.restore_button, False, False, 0)
        right.pack_end(bar, False, False, 0)
        paned.pack2(right, True, False)
        paned.set_position(210)
        self.stack.add_named(paned, "backups")
        self.stack.add_named(self._empty_page(), "empty")
        self.add(self.stack)

        menus.add_actions(self, {"close": self.close, "restore": self.restore, "up": self.go_up,
                                 "find": self.search.grab_focus, "newer": lambda: self.step(-1),
                                 "older": lambda: self.step(1), "home": lambda: self.open_rel(""),
                                 "show-now": self.show_now, "back-up-now": self.app.back_up_now,
                                 "settings": lambda: _run("freemac-dials", "--panel", "lifeboat")})
        self.connect("key-press-event", self._key)
        self.handlers = volumes.watch(lambda: GLib.idle_add(self.refresh_backups))
        self.connect("destroy", self._gone)
        self.show_all()
        self.refresh_backups()

    def _gone(self, _w):
        for handler in self.handlers:
            volumes.monitor().disconnect(handler)

    def _empty_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, valign=Gtk.Align.CENTER,
                      halign=Gtk.Align.CENTER)
        icon = Gtk.Image.new_from_icon_name("freemac-lifeboat", Gtk.IconSize.DIALOG)
        icon.set_pixel_size(96)
        self.empty_title = Gtk.Label()
        self.empty_title.get_style_context().add_class("lifeboat-empty-title")
        self.empty_text = Gtk.Label(wrap=True, max_width_chars=52, justify=Gtk.Justification.CENTER)
        self.empty_text.get_style_context().add_class("lifeboat-empty-text")
        self.empty_button = Gtk.Button(halign=Gtk.Align.CENTER)
        self.empty_button.connect("clicked", lambda _b: self.empty_action())
        for widget in (icon, self.empty_title, self.empty_text, self.empty_button):
            box.pack_start(widget, False, False, 0)
        return box

    def _empty(self, title, text, button=None, action=None):
        self.empty_title.set_text(title)
        self.empty_text.set_text(text)
        self.empty_button.set_visible(button is not None)
        if button:
            self.empty_button.set_label(button)
        self.empty_action = action or (lambda: None)
        self.stack.set_visible_child_name("empty")
        self.search.set_sensitive(False)
        self.back_button.set_sensitive(False)

    # -- the list of backups --

    def refresh_backups(self):
        settings = store.settings()
        if not settings.get("drive"):
            self._empty("Choose a backup drive",
                        "Plug in a USB drive or another disk, and choose it in Dials > Lifeboat. "
                        "Your files are then backed up every hour while it's plugged in.",
                        "Open Lifeboat Settings…", lambda: _run("freemac-dials", "--panel", "lifeboat"))
            return False
        found = chosen_drive()
        if found is None:
            self.root = None
            self._empty(f"Plug in “{settings.get('name') or 'your backup drive'}”",
                        "Your backups are on it. They show here as soon as it's plugged in.")
            return False
        self.root = found[1]
        everything = store.backups(self.root)
        if not everything:
            busy = store.status().get("state") == "backing-up"
            self._empty("No backups yet",
                        "The first backup is being made now. It takes a while; later ones are quick."
                        if busy else "The first one starts soon, or start it now.",
                        None if busy else "Back Up Now", self.app.back_up_now)
            return False
        self.stack.set_visible_child_name("backups")
        self.search.set_sensitive(True)
        keep = self.chosen
        for child in self.side.get_children():
            child.destroy()
        for when, path in reversed(everything):
            row = Gtk.ListBoxRow()
            row.when, row.path = when, path
            label = Gtk.Label(label=time.strftime("%I:%M %p", time.localtime(when)).lstrip("0"), xalign=0)
            label.get_style_context().add_class("lifeboat-time")
            row.add(label)
            self.side.add(row)
        self.side.show_all()
        rows = self.side.get_children()
        pick = next((r for r in rows if r.path == keep), rows[0])
        self.side.select_row(pick)
        if pick.path == keep:
            self.show_folder()
        return False

    def _day_header(self, row, before):
        day = store.describe(row.when).split(",")[0]
        if before is None or store.describe(before.when).split(",")[0] != day:
            label = Gtk.Label(label=day, xalign=0)
            label.get_style_context().add_class("lifeboat-day")
            row.set_header(label)
        else:
            row.set_header(None)

    def _backup_chosen(self, _list, row):
        if row is None:
            return
        self.chosen = row.path
        self.chosen_when = row.when
        self.show_folder()

    def step(self, by):
        rows = self.side.get_children()
        current = self.side.get_selected_row()
        if not rows or current is None:
            return
        at = max(0, min(len(rows) - 1, rows.index(current) + by))
        self.side.select_row(rows[at])
        rows[at].grab_focus()

    # -- the folder in the chosen backup --

    def open_rel(self, rel, select=None):
        self.rel = rel.strip("/")
        self.select_after = select
        self.search.set_text("")
        self.show_folder()

    def go_up(self):
        if self.rel:
            parent, name = os.path.split(self.rel)
            self.open_rel(parent, select=name)

    def show_folder(self):
        if not self.chosen:
            return
        folder = os.path.join(self.chosen, self.rel)
        self.model.clear()
        self._path_bar()
        self.back_button.set_sensitive(bool(self.rel))
        self.header.set_title(os.path.basename(self.rel) or "Home")
        self.header.set_subtitle(store.describe(self.chosen_when))
        if not os.path.isdir(folder):
            self.missing.set_text("This folder wasn't there at the time of this backup.\n"
                                  "Choose a later time on the left.")
            self.files_stack.set_visible_child_name("missing")
            self._update_bar()
            return
        self.files_stack.set_visible_child_name("files")
        now_folder = os.path.join(store.home(), self.rel)
        try:
            names = os.listdir(folder)
        except OSError:
            names = []
        for name in names:
            if name.startswith("."):
                continue
            path = os.path.join(folder, name)
            try:
                st = os.lstat(path)
            except OSError:
                continue
            is_dir = os.path.isdir(path) and not os.path.islink(path)
            modified = time.strftime("%d %b %Y, %I:%M %p", time.localtime(st.st_mtime)).lstrip("0")
            size = "" if is_dir else store.size_words(st.st_size)
            self.model.append([name, _icon_for(path, is_dir), modified, size,
                               -1 if is_dir else st.st_size, is_dir,
                               _what_now(path, os.path.join(now_folder, name), is_dir), path])
        if self.select_after:
            for row in self.sorted:
                if row[0] == self.select_after:
                    self.tree.get_selection().select_iter(row.iter)
                    self.tree.scroll_to_cell(row.path, None, True, 0.3, 0)
                    break
            self.select_after = None
        self._update_bar()

    def _path_bar(self):
        for child in self.path_bar.get_children():
            child.destroy()
        parts = [p for p in self.rel.split("/") if p]
        steps = [("Home", "")] + [(p, "/".join(parts[:i + 1])) for i, p in enumerate(parts)]
        for at, (label, rel) in enumerate(steps):
            if at:
                sep = Gtk.Label(label="›")
                sep.get_style_context().add_class("lifeboat-sep")
                self.path_bar.pack_start(sep, False, False, 2)
            button = Gtk.Button(label=label, relief=Gtk.ReliefStyle.NONE)
            button.connect("clicked", lambda _b, r=rel: self.open_rel(r))
            self.path_bar.pack_start(button, False, False, 0)
        self.path_bar.show_all()

    def _visible(self, model, it, _data):
        text = self.search.get_text().strip().lower()
        return not text or text in (model[it][0] or "").lower()

    @staticmethod
    def _by_name(model, a, b, _data=None):
        one = (not model[a][5], (model[a][0] or "").lower())
        two = (not model[b][5], (model[b][0] or "").lower())
        return (one > two) - (one < two)

    def chosen_rows(self):
        model, paths = self.tree.get_selection().get_selected_rows()
        return [model[p] for p in paths]

    def _update_bar(self):
        if not self.chosen:
            return
        rows = self.chosen_rows()
        self.when_label.set_text(store.describe(self.chosen_when))
        if rows:
            what = f"“{rows[0][0]}”" if len(rows) == 1 else f"{len(rows)} items"
            self.note_label.set_text(f"Restore puts a copy of {what} back in "
                                     f"{os.path.basename(self.rel) or 'your home folder'}.")
        else:
            self.note_label.set_text("Choose what to bring back, then click Restore.")
        self.restore_button.set_sensitive(bool(rows))

    def _activated(self, _tree, path, _col):
        row = self.sorted[path]
        if row[5]:
            self.open_rel(os.path.join(self.rel, row[0]))
        else:
            self.peek(row[7])

    def peek(self, path):
        """Open a copy, so nothing can change the file in the backup (unchanged
        files are shared by every backup)."""
        folder = tempfile.mkdtemp(prefix="lifeboat-")
        copy = os.path.join(folder, os.path.basename(path))
        try:
            shutil.copy2(path, copy)
            os.chmod(copy, 0o444)
            Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(copy).get_uri(), None)
        except (OSError, GLib.Error) as error:
            alert.tell(self, "The file couldn't be opened.", getattr(error, "message", None) or str(error))

    def show_now(self):
        """Show the folder as it is now, in Drawer."""
        _run("freemac-drawer", os.path.join(store.home(), self.rel))

    def restore(self):
        rows = self.chosen_rows()
        if not rows:
            return
        target = os.path.join(store.home(), self.rel)
        try:
            os.makedirs(target, exist_ok=True)
        except OSError as error:
            alert.tell(self, "The files couldn't be restored.", error.strerror or str(error))
            return
        paths = [row[7] for row in rows]

        def done(job):
            if job.made and not job.errors:
                count = len(job.made)
                self.note_label.set_text(("Restored " + (f"“{os.path.basename(job.made[0])}”" if count == 1
                                                         else f"{count} items")) + ".")
                self.show_folder()

        transfer.Job(paths, target, parent=self, done=done).start()

    def _key(self, _w, event):
        mods = event.state & Gtk.accelerator_get_default_mod_mask()
        key = event.keyval
        if self.search.has_focus() and key != Gdk.KEY_Escape:
            return False
        if mods == Gdk.ModifierType.CONTROL_MASK and key == Gdk.KEY_Up:
            self.go_up()
            return True
        if mods == Gdk.ModifierType.CONTROL_MASK and key == Gdk.KEY_Down:
            rows = self.chosen_rows()
            if rows:
                self._activated(None, self.sorted.get_path(rows[0].iter), None)
            return True
        if key == Gdk.KEY_BackSpace and not mods:
            self.go_up()
            return True
        if key == Gdk.KEY_Escape:
            self.search.set_text("")
            return False
        return False


def _run(*cmd):
    try:
        Gio.Subprocess.new(list(cmd), Gio.SubprocessFlags.NONE)
    except GLib.Error:
        pass


def menubar():
    return menus.menubar([
        ("_File", [[("Restore", "win.restore", "<Ctrl>r")],
                   [("Show Current Folder in Drawer", "win.show-now", None)],
                   [("Back Up Now", "win.back-up-now", None)],
                   [("Close Window", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Find", "win.find", "<Ctrl>f")]]),
        ("_Go", [[("Enclosing Folder", "win.up", "<Ctrl>Up"), ("Home", "win.home", "<Shift><Ctrl>h")],
                 [("Later Backup", "win.newer", None), ("Earlier Backup", "win.older", None)]]),
    ])


class Lifeboat(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.watcher = None
        self.add_main_option("watch", 0, GLib.OptionFlags.NONE, GLib.OptionArg.NONE,
                             "Back up every hour in the background", None)
        self.add_main_option("now", 0, GLib.OptionFlags.NONE, GLib.OptionArg.NONE, "Back up now", None)
        self.add_main_option("stop", 0, GLib.OptionFlags.NONE, GLib.OptionArg.NONE, "Stop the backup", None)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        # Quit closes the windows; the hourly backups go on.
        menus.add_actions(self, {"quit": self.close_windows})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.set_menubar(menubar())
        self.watcher = Watcher(self)
        self.hold()

    def close_windows(self):
        for window in self.get_windows():
            window.destroy()

    def back_up_now(self):
        self.watcher.look(now=True)
        for window in self.get_windows():
            if isinstance(window, Window):
                GLib.timeout_add(400, window.refresh_backups)

    def do_command_line(self, command_line):
        options = command_line.get_options_dict().end().unpack()
        args = command_line.get_arguments()[1:]
        if options.get("now"):
            self.back_up_now()
            return 0
        if options.get("stop"):
            self.watcher.cancel()
            return 0
        if options.get("watch") and not args:
            return 0
        window = next((w for w in self.get_windows() if isinstance(w, Window)), None) or Window(self)
        if args:
            path = os.path.abspath(command_line.create_file_for_arg(args[0]).get_path() or args[0])
            home = store.home()
            if path == home or path.startswith(home + "/"):
                rel = os.path.relpath(path, home)
                rel = "" if rel == "." else rel
                if os.path.isdir(path):
                    window.open_rel(rel)
                else:
                    window.open_rel(os.path.dirname(rel), select=os.path.basename(rel))
        window.present()
        return 0


def main():
    GLib.set_prgname("freemac-lifeboat")
    return Lifeboat().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
