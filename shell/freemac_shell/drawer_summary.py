# SPDX-License-Identifier: GPL-3.0-or-later
"""Summary Info, as on a Mac (File > Get Summary Info, or ⌃⌘I in Drawer):
one Info window for everything chosen, with how many items there are, what
kind they are, their size all together (folders added up in the
background), where they are, their tags and whether they're locked. A tag
or the Locked box set here is set on every item. Original freemac code.
"""
import os
import stat
import threading

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import aliases, alert, locks, macapps, tags  # noqa: E402
from .drawer_info import folder_total, nice_size  # noqa: E402


def kind_of(path):
    """The Kind line Get Info would show for one item."""
    if macapps.is_bundle(path):
        return "Mac app"
    if aliases.is_alias(path):
        return "Alias"
    if os.path.isdir(path):
        return "Folder"
    content, _uncertain = Gio.content_type_guess(path, None)
    return Gio.content_type_get_description(content or "") or "Document"


def common_kind(paths):
    kinds = {kind_of(p) for p in paths}
    return kinds.pop() if len(kinds) == 1 else "Multiple kinds"


def where_text(paths, home=None):
    """The folder they're all in, or Several folders."""
    home = home or GLib.get_home_dir()
    places = {os.path.dirname(os.path.abspath(p)) for p in paths}
    if len(places) != 1:
        return "Several folders"
    where = places.pop()
    if where == home or where.startswith(home.rstrip(os.sep) + os.sep):
        return "Home" + where[len(home.rstrip(os.sep)):]
    return where


def total(paths, stop):
    """(bytes, items) for everything chosen, folders added up; None if stopped."""
    size = count = 0
    for path in paths:
        if stop.is_set():
            return None
        try:
            info = os.lstat(path)
        except OSError:
            continue
        count += 1
        if stat.S_ISDIR(info.st_mode):
            found = folder_total(path, stop)
            if found is None:
                return None
            size += found[0]
            count += found[1]
        elif stat.S_ISREG(info.st_mode):
            size += info.st_size
    return size, count


def lock_state(paths):
    """True, False, or None when some are locked and some aren't."""
    states = {locks.is_locked(p) for p in paths if not aliases.is_alias(p)}
    return states.pop() if len(states) == 1 else (None if states else False)


class SummaryWindow(Gtk.Window):
    def __init__(self, paths):
        super().__init__(title="Summary Info")
        self.paths = [p for p in paths if os.path.lexists(p)]
        self.set_default_size(300, -1)
        self.set_resizable(False)
        self.stop = threading.Event()
        self.connect("destroy", lambda *_: self.stop.set())
        self.connect("key-press-event", self._key)
        # Nothing chosen when it opens, as in Get Info.
        self.connect("map", lambda *_: GLib.idle_add(self._unfocus))

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=18)
        top = Gtk.Box(spacing=12)
        top.pack_start(self._stack_icon(), False, False, 0)
        titles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
        count = len(self.paths)
        title = Gtk.Label(label=f"{count} item{'s' if count != 1 else ''}", xalign=0)
        title.get_style_context().add_class("drawer-preview-name")
        titles.pack_start(title, False, False, 0)
        self.size_line = Gtk.Label(label="Adding up…", xalign=0)
        self.size_line.get_style_context().add_class("dim-label")
        titles.pack_start(self.size_line, False, False, 0)
        top.pack_start(titles, True, True, 0)
        box.pack_start(top, False, False, 0)
        box.pack_start(Gtk.Separator(), False, False, 0)

        grid = Gtk.Grid(column_spacing=10, row_spacing=6)
        self.size_value = Gtk.Label(label="Adding up…", xalign=0, selectable=True, wrap=True,
                                    max_width_chars=30)
        rows = [("Kind", common_kind(self.paths)), ("Size", self.size_value),
                ("Where", where_text(self.paths)), ("Tags", tags.picker(self.paths))]
        for row, (label, value) in enumerate(rows):
            name = Gtk.Label(label=f"{label}:", xalign=1, yalign=0)
            name.get_style_context().add_class("dim-label")
            grid.attach(name, 0, row, 1, 1)
            if isinstance(value, str):
                value = Gtk.Label(label=value, xalign=0, selectable=True, wrap=True, max_width_chars=30)
            grid.attach(value, 1, row, 1, 1)
        box.pack_start(grid, False, False, 0)

        # Locked for all of them: a dash when only some are.
        lockable = [p for p in self.paths if self._lockable(p)]
        state = lock_state(self.paths)
        self.lock_check = Gtk.CheckButton(label="Locked", active=bool(state))
        self.lock_check.set_inconsistent(state is None)
        self.lock_check.set_sensitive(bool(lockable))
        self.lock_check.connect("toggled", self._lock_toggled)
        box.pack_start(self.lock_check, False, False, 0)
        self.add(box)
        threading.Thread(target=self._add_up, daemon=True).start()

    @staticmethod
    def _lockable(path):
        """As in Get Info: yours, and not an alias (which has no lock)."""
        return locks.can_lock(path) and not aliases.is_alias(path)

    def _unfocus(self):
        focus = self.get_focus()
        if isinstance(focus, Gtk.Label):
            focus.select_region(0, 0)
        self.set_focus(None)
        return False

    def _stack_icon(self):
        """The first few items' icons, fanned out like a small pile."""
        theme = Gtk.IconTheme.get_default()
        pictures = []
        for path in self.paths[:3]:
            try:
                info = Gio.File.new_for_path(path).query_info(
                    "standard::icon", Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, None)
                found = theme.lookup_by_gicon(info.get_icon(), 48, Gtk.IconLookupFlags.FORCE_SIZE)
                pictures.append(found.load_icon() if found is not None else None)
            except GLib.Error:
                pictures.append(None)
        pictures = [p for p in pictures if p is not None]
        area = Gtk.DrawingArea(valign=Gtk.Align.CENTER)
        area.set_size_request(64, 64)

        def draw(_w, cr):
            # The last one first, so the first item is on top.
            for i, picture in reversed(list(enumerate(pictures))):
                Gdk.cairo_set_source_pixbuf(cr, picture, 2 + i * 6, 12 - i * 5)
                cr.paint_with_alpha(1.0 - i * 0.2)
            return False

        from gi.repository import Gdk
        area.connect("draw", draw)
        return area

    def _add_up(self):
        found = total(self.paths, self.stop)
        if found is None:
            return

        def show():
            size, items = found
            words = f"{items:,} item" + ("" if items == 1 else "s")
            text = (f"{nice_size(size)} for {words}" if size >= 1000 else f"{size:,} bytes for {words}")
            if not self.stop.is_set():
                self.size_value.set_text(text)
                self.size_line.set_text(nice_size(size) if size >= 1000 else f"{size:,} bytes")
            return False

        GLib.idle_add(show)

    def _lock_toggled(self, check):
        # From a dash, the first click locks them all.
        on = True if check.get_inconsistent() else check.get_active()
        check.handler_block_by_func(self._lock_toggled)
        check.set_inconsistent(False)
        check.set_active(on)
        check.handler_unblock_by_func(self._lock_toggled)
        failed = []
        for path in self.paths:
            if not self._lockable(path):
                continue
            try:
                locks.set_locked(path, on)
            except OSError:
                failed.append(os.path.basename(path))
        if failed:
            alert.tell(self, f"{len(failed)} item{'s' if len(failed) != 1 else ''} couldn’t be "
                       f"{'locked' if on else 'unlocked'}.", ", ".join(failed[:5]))
            state = lock_state(self.paths)
            check.handler_block_by_func(self._lock_toggled)
            check.set_active(bool(state))
            check.set_inconsistent(state is None)
            check.handler_unblock_by_func(self._lock_toggled)

    def _key(self, _w, event):
        from gi.repository import Gdk
        if event.keyval == Gdk.KEY_Escape or (event.state & Gdk.ModifierType.CONTROL_MASK and
                                              event.keyval in (Gdk.KEY_w, Gdk.KEY_W)):
            self.destroy()
            return True
        return False


def show(paths, parent=None):
    window = SummaryWindow(paths)
    if parent is not None and parent.get_application() is not None:
        parent.get_application().add_window(window)
    window.show_all()
    return window
