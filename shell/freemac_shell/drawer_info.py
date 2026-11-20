# SPDX-License-Identifier: GPL-3.0-or-later
"""Get Info for Drawer (Command+I): one small window per item with its icon,
name, kind, size, where it is, when it was made and changed, and who can open
it. A folder's size is added up in the background, so the window opens at
once. Original freemac code.
"""
import os
import pwd
import stat
import threading
import time

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import macapps  # noqa: E402

ATTRS = ",".join((
    "standard::display-name", "standard::content-type", "standard::icon", "standard::size",
    "standard::type", "time::created", "time::modified", "unix::mode", "unix::uid",
    "access::can-read", "access::can-write",
))


def nice_size(size):
    """Sizes as a Mac shows them: 1,234,567 bytes (1.2 MB on disk)."""
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if size < 1000 or unit == "TB":
            short = f"{size:,.0f} {unit}" if unit == "bytes" else f"{size:.1f} {unit}"
            break
        size /= 1000
    return short


def stamp_text(stamp):
    if not stamp:
        return "Not known"
    return time.strftime("%A, %-d %B %Y at %-I:%M %p", time.localtime(stamp))


def folder_total(path, stop):
    """(bytes, items) under a folder, not following links."""
    total, items = 0, 0
    for root, dirs, files in os.walk(path, onerror=lambda _e: None):
        if stop.is_set():
            return None
        for name in files + dirs:
            items += 1
            try:
                info = os.lstat(os.path.join(root, name))
            except OSError:
                continue
            if stat.S_ISREG(info.st_mode):
                total += info.st_size
    return total, items


def who_can_open(info, path):
    mode = info.get_attribute_uint32("unix::mode") if info.has_attribute("unix::mode") else 0
    uid = info.get_attribute_uint32("unix::uid") if info.has_attribute("unix::uid") else os.getuid()
    try:
        owner = pwd.getpwuid(uid).pw_gecos.split(",")[0] or pwd.getpwuid(uid).pw_name
    except KeyError:
        owner = str(uid)
    mine = uid == os.getuid()
    can_write = info.get_attribute_boolean("access::can-write")
    can_read = info.get_attribute_boolean("access::can-read")
    you = ("You can read and change it" if can_write else "You can read it, not change it" if can_read
           else "You can't open it")
    others = "Others on this computer can read it" if mode & stat.S_IROTH else "Others on this computer can't open it"
    return [("Owner", "You" if mine else owner), ("You", you), ("Others", others)]


class InfoWindow(Gtk.Window):
    def __init__(self, path, parent=None):
        super().__init__(title=f"{os.path.basename(path.rstrip('/')) or path} Info")
        self.set_default_size(300, -1)
        self.set_resizable(False)
        if parent is not None:
            self.set_transient_for(None)  # its own window, as on a Mac
        self.stop = threading.Event()
        self.connect("destroy", lambda *_: self.stop.set())
        gfile = Gio.File.new_for_path(path)
        try:
            info = gfile.query_info(ATTRS, Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, None)
        except GLib.Error as err:
            self.add(Gtk.Label(label=err.message, margin=18))
            return
        is_bundle = macapps.is_bundle(path)
        is_dir = info.get_file_type() == Gio.FileType.DIRECTORY and not is_bundle
        name = macapps.display_name(path) if is_bundle else info.get_display_name()
        kind = ("Mac app" if is_bundle else "Folder" if is_dir
                else Gio.content_type_get_description(info.get_content_type() or "") or "Document")

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=18)
        top = Gtk.Box(spacing=12)
        image = Gtk.Image()
        pixbuf = macapps.cached_icon(path, 64) if is_bundle else None
        if pixbuf is not None:
            image.set_from_pixbuf(pixbuf)
        elif info.get_icon() is not None:
            image.set_from_gicon(info.get_icon(), Gtk.IconSize.DIALOG)
            image.set_pixel_size(64)
        top.pack_start(image, False, False, 0)
        titles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
        title = Gtk.Label(label=name, xalign=0, wrap=True, max_width_chars=24)
        title.get_style_context().add_class("drawer-preview-name")
        titles.pack_start(title, False, False, 0)
        self.size_line = Gtk.Label(xalign=0)
        self.size_line.get_style_context().add_class("dim-label")
        titles.pack_start(self.size_line, False, False, 0)
        top.pack_start(titles, True, True, 0)
        box.pack_start(top, False, False, 0)
        box.pack_start(Gtk.Separator(), False, False, 0)

        grid = Gtk.Grid(column_spacing=10, row_spacing=6)
        rows = [("Kind", kind)]
        self.size_value = Gtk.Label(xalign=0, selectable=True, wrap=True, max_width_chars=30)
        if is_dir or is_bundle:
            self.size_value.set_text("Adding up…")
            self.size_line.set_text("Adding up…")
            threading.Thread(target=self._add_up, args=(path, is_bundle), daemon=True).start()
        else:
            size = info.get_size()
            self.size_value.set_text(f"{size:,} bytes" if size < 1000 else f"{nice_size(size)} ({size:,} bytes)")
            self.size_line.set_text(nice_size(size))
        rows.append(("Size", self.size_value))
        where = os.path.dirname(os.path.abspath(path))
        home = GLib.get_home_dir()
        rows.append(("Where", "Home" + where[len(home):] if where.startswith(home) else where))
        created = info.get_creation_date_time() if hasattr(info, "get_creation_date_time") else None
        modified = info.get_modification_date_time()
        rows.append(("Created", stamp_text(created.to_unix() if created else 0)))
        rows.append(("Modified", stamp_text(modified.to_unix() if modified else 0)))
        for row, (label, value) in enumerate(rows):
            self._row(grid, row, label, value)
        box.pack_start(grid, False, False, 0)

        box.pack_start(Gtk.Separator(), False, False, 0)
        heading = Gtk.Label(label="Sharing and permissions", xalign=0)
        heading.get_style_context().add_class("drawer-heading")
        box.pack_start(heading, False, False, 0)
        perms = Gtk.Grid(column_spacing=10, row_spacing=6)
        for row, (label, value) in enumerate(who_can_open(info, path)):
            self._row(perms, row, label, value)
        box.pack_start(perms, False, False, 0)
        self.add(box)
        self.connect("key-press-event", self._key)

    @staticmethod
    def _row(grid, row, label, value):
        name = Gtk.Label(label=f"{label}:", xalign=1, yalign=0)
        name.get_style_context().add_class("dim-label")
        grid.attach(name, 0, row, 1, 1)
        if isinstance(value, str):
            value = Gtk.Label(label=value, xalign=0, selectable=True, wrap=True, max_width_chars=30)
        grid.attach(value, 1, row, 1, 1)

    def _add_up(self, path, is_bundle):
        result = folder_total(path, self.stop)
        if result is None:
            return

        def show():
            total, items = result
            if is_bundle:
                text = nice_size(total) if total >= 1000 else f"{total:,} bytes"
            else:
                count = f"{items:,} item" + ("" if items == 1 else "s")
                text = ("Empty" if not items else f"{nice_size(total)} for {count}" if total >= 1000
                        else f"{total:,} bytes for {count}")
            self.size_value.set_text(text)
            self.size_line.set_text(text)
            return False

        GLib.idle_add(show)

    def _key(self, _w, event):
        from gi.repository import Gdk
        if event.keyval == Gdk.KEY_Escape or (event.state & Gdk.ModifierType.CONTROL_MASK and
                                              event.keyval in (Gdk.KEY_w, Gdk.KEY_W, Gdk.KEY_i, Gdk.KEY_I)):
            self.destroy()
            return True
        return False


def show(paths, parent=None):
    """One Info window for each item (as on a Mac, at most ten at once)."""
    for path in paths[:10]:
        window = InfoWindow(path, parent)
        if parent is not None and parent.get_application() is not None:
            parent.get_application().add_window(window)
        window.show_all()
