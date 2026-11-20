# SPDX-License-Identifier: GPL-3.0-or-later
"""The files in the Desktop folder, shown as icons on the wallpaper.

Backdrop puts this layer over the picture on the first screen. Icons fill a
grid from the top right corner down, then leftwards; dragging one moves it
(the place is kept in ~/.config/freemac/desktop.json), and dragging it onto
the dock's Trash, a Drawer window or a folder works like any file. Files
dropped on the desktop from elsewhere are moved into the Desktop folder.

Click selects, double-click opens, Return renames, Delete moves the selection
to the Trash; ⌘C, ⌘V, ⌥⌘V, ⌘D and ⌘Z copy, paste, move, duplicate and undo
as in Drawer (transfer.py), and files dropped on a folder go into it. The right button gives Open, Rename, Show in Drawer and Move to
Trash for a file, and New Folder and Change Wallpaper on the empty desktop.
Screenshots (Lens) land here too.

Plugged-in drives, memory cards and phones show here as well, first in the
top right corner: double-click opens one in Drawer, and Eject (the right
button, Command-E, or a drag onto the dock's Trash) takes it away.
"""
import json
import os
import subprocess
from urllib.parse import unquote, urlparse

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango  # noqa: E402

from . import transfer, volumes  # noqa: E402

LAYOUT = os.path.join(GLib.get_user_config_dir(), "freemac", "desktop.json")
CELL_W, CELL_H = 100, 104   # one place on the grid
TOP, RIGHT = 40, 14         # below the menu bar, in from the right edge
BOTTOM = 96                 # above the dock
ICON = 64
URI_TARGETS = [Gtk.TargetEntry.new("text/uri-list", 0, 0)]

CSS = b"""
.desk-icon { padding: 2px; border-radius: 7px; }
.desk-icon.selected { background-color: rgba(0, 0, 0, 0.22); }
.desk-label { color: white; font-size: 12px; padding: 1px 5px; border-radius: 5px;
              text-shadow: 0 1px 2px rgba(0, 0, 0, 0.75); }
.desk-label.selected { background-color: #2f7bf5; text-shadow: none; }
"""


def desktop_dir():
    return GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DESKTOP) or os.path.expanduser("~/Desktop")


def path_of(uri):
    parsed = urlparse(uri)
    return unquote(parsed.path) if parsed.scheme == "file" else None


def load_places():
    try:
        with open(LAYOUT) as f:
            places = json.load(f).get("places", {})
        return {k: (int(v[0]), int(v[1])) for k, v in places.items()}
    except (OSError, ValueError, AttributeError, TypeError, IndexError):
        return {}


def save_places(places):
    os.makedirs(os.path.dirname(LAYOUT), exist_ok=True)
    tmp = LAYOUT + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"places": {k: list(v) for k, v in places.items()}}, f, indent=1)
    os.replace(tmp, LAYOUT)


def picture_for(path, info, icon=None):
    """A small picture of the file: a thumbnail for pictures, else its icon."""
    kind = info.get_content_type() if info else ""
    if kind and kind.startswith("image/") and info.get_size() < 40_000_000:
        try:
            return GdkPixbuf.Pixbuf.new_from_file_at_scale(path, ICON, ICON, True)
        except GLib.Error:
            pass
    if icon is None:
        icon = info.get_icon() if info else None
    theme = Gtk.IconTheme.get_default()
    if icon is not None:
        found = theme.lookup_by_gicon(icon, ICON, Gtk.IconLookupFlags.FORCE_SIZE)
        if found:
            try:
                return found.load_icon()
            except GLib.Error:
                pass
    try:
        return theme.load_icon("text-x-generic", ICON, Gtk.IconLookupFlags.FORCE_SIZE)
    except GLib.Error:
        return None


class DesktopIcon(Gtk.EventBox):
    mount = None   # a drive, for DriveIcon

    def __init__(self, owner, path, info, title=None, icon=None):
        super().__init__()
        self.owner, self.path = owner, path
        self.set_visible_window(False)
        self.set_size_request(CELL_W - 8, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, halign=Gtk.Align.CENTER)
        self.frame = Gtk.Box(halign=Gtk.Align.CENTER)
        self.frame.get_style_context().add_class("desk-icon")
        self.pixbuf = picture_for(path, info, icon)
        image = Gtk.Image.new_from_pixbuf(self.pixbuf) if self.pixbuf else Gtk.Image()
        image.set_size_request(ICON, ICON)
        self.frame.add(image)
        box.pack_start(self.frame, False, False, 0)
        name = title or (info.get_display_name() if info else os.path.basename(path))
        self.label = Gtk.Label(label=name, justify=Gtk.Justification.CENTER, max_width_chars=13,
                               ellipsize=Pango.EllipsizeMode.MIDDLE, lines=2, halign=Gtk.Align.CENTER)
        self.label.set_line_wrap(True)
        self.label.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
        self.label.get_style_context().add_class("desk-label")
        box.pack_start(self.label, False, False, 0)
        self.add(box)
        self.connect("button-press-event", self._press)
        self.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, URI_TARGETS, Gdk.DragAction.MOVE | Gdk.DragAction.COPY)
        self.connect("drag-begin", self._drag_begin)
        self.connect("drag-data-get", self._drag_data_get)
        self.connect("drag-end", lambda *_: self.owner.drag_ended())

    @property
    def name(self):
        return os.path.basename(self.path)

    def set_selected(self, selected):
        for widget in (self.frame, self.label):
            (widget.get_style_context().add_class if selected else
             widget.get_style_context().remove_class)("selected")

    def _press(self, _widget, event):
        if event.type == Gdk.EventType._2BUTTON_PRESS and event.button == 1:
            self.owner.open([self])
            return True
        if event.button == 1:
            additive = event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)
            self.owner.click(self, bool(additive))
            return False  # let a drag start
        if event.button == 3:
            if self not in self.owner.selected:
                self.owner.click(self, False)
            self.owner.file_menu(event)
            return True
        return False

    def _drag_begin(self, _widget, context):
        if self not in self.owner.selected:
            self.owner.click(self, False)
        self.owner.drag_started(self)
        if self.pixbuf:
            Gtk.drag_set_icon_pixbuf(context, self.pixbuf, self.pixbuf.get_width() // 2,
                                     self.pixbuf.get_height() // 2)

    def _drag_data_get(self, _widget, _context, data, _info, _time):
        data.set_uris([icon.uri for icon in self.owner.selected])

    @property
    def uri(self):
        return Gio.File.new_for_path(self.path).get_uri()


class DriveIcon(DesktopIcon):
    """A plugged-in drive, memory card or phone."""

    def __init__(self, owner, mount):
        self.mount = mount
        super().__init__(owner, volumes.path_of(mount) or "", None, mount.get_name(), mount.get_icon())

    @property
    def name(self):
        return "drive:" + volumes.key_of(self.mount)

    @property
    def uri(self):
        return volumes.key_of(self.mount)


class DesktopIcons(Gtk.Layout):
    def __init__(self, monitor=None):
        super().__init__()
        self.screen_size = None
        if monitor is not None:
            area = monitor.get_geometry()
            self.screen_size = (area.width, area.height)
        self.folder = desktop_dir()
        self.places = load_places()
        self.icons = {}           # file name -> DesktopIcon
        self.selected = []
        self.dragging = None
        self._pending = None
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.set_hexpand(True)
        self.set_vexpand(True)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.KEY_PRESS_MASK)
        self.set_can_focus(True)
        self.connect("button-press-event", self._press_empty)
        self.connect("key-press-event", self._key)
        self.connect("size-allocate", lambda *_: self._arrange())
        self.drag_dest_set(Gtk.DestDefaults.ALL, URI_TARGETS, Gdk.DragAction.MOVE | Gdk.DragAction.COPY)
        self.connect("drag-data-received", self._dropped)
        os.makedirs(self.folder, exist_ok=True)
        self.monitor = Gio.File.new_for_path(self.folder).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
        self.monitor.connect("changed", lambda *_: self._soon())
        volumes.watch(self.refresh_drives)
        self.refresh()
        self.refresh_drives()

    # ---- the grid -----------------------------------------------------------------
    def size(self):
        """The screen's size: our own once GTK has laid us out, else the monitor's."""
        width, height = self.get_allocated_width(), self.get_allocated_height()
        if (width < CELL_W * 3 or height < TOP + BOTTOM + CELL_H * 2) and self.screen_size:
            return self.screen_size
        return width, height

    def rows(self):
        return max(1, (self.size()[1] - TOP - BOTTOM) // CELL_H)

    def cell_xy(self, cell):
        col, row = cell
        return self.size()[0] - RIGHT - CELL_W * (col + 1), TOP + CELL_H * row

    def nearest_cell(self, x, y):
        col = round((self.size()[0] - RIGHT - CELL_W - x) / CELL_W)
        row = round((y - TOP) / CELL_H)
        return max(0, col), max(0, min(self.rows() - 1, row))

    def free_cell(self, taken, near=None):
        """The free place nearest `near`, or the first free one in order."""
        rows = self.rows()
        if near is not None:
            best = None
            for col in range(near[0] + 4):
                for row in range(rows):
                    if (col, row) in taken:
                        continue
                    distance = (col - near[0]) ** 2 + (row - near[1]) ** 2
                    if best is None or distance < best[0]:
                        best = (distance, (col, row))
            if best:
                return best[1]
        col = 0
        while True:
            for row in range(rows):
                if (col, row) not in taken:
                    return col, row
            col += 1

    def _arrange(self):
        width, height = self.size()
        if width < CELL_W * 3 or height < TOP + BOTTOM + CELL_H * 2:
            return  # not laid out on the screen yet
        taken, changed = set(), False
        rows = self.rows()
        for name in sorted(self.icons, key=lambda n: (n not in self.places, not n.startswith("drive:"), n.lower())):
            cell = self.places.get(name)
            if cell is None or cell in taken or cell[1] >= rows:
                cell = self.free_cell(taken, cell if cell and cell[1] < rows else None)
                if self.places.get(name) != cell:
                    self.places[name] = cell
                    changed = True
            taken.add(cell)
            x, y = self.cell_xy(cell)
            icon = self.icons[name]
            if self.child_get(icon, "x", "y") != (x + 4, y):
                self.move(icon, x + 4, y)
        if changed:
            self._save()

    def _save(self):
        try:
            save_places({k: v for k, v in self.places.items() if k in self.icons})
        except OSError:
            pass

    # ---- the files ----------------------------------------------------------------
    def _soon(self):
        if not self._pending:
            self._pending = GLib.timeout_add(150, self.refresh)

    def refresh(self):
        self._pending = None
        try:
            names = sorted(n for n in os.listdir(self.folder) if not n.startswith("."))
        except OSError:
            names = []
        for name in list(self.icons):
            if name not in names and not name.startswith("drive:"):
                icon = self.icons.pop(name)
                if icon in self.selected:
                    self.selected.remove(icon)
                icon.destroy()
        for name in names:
            path = os.path.join(self.folder, name)
            try:
                info = Gio.File.new_for_path(path).query_info(
                    "standard::content-type,standard::icon,standard::display-name,standard::size",
                    Gio.FileQueryInfoFlags.NONE, None)
            except GLib.Error:
                info = None
            old = self.icons.get(name)
            if old is not None and old.info_key == self._key_of(path):
                continue
            if old is not None:
                old.destroy()
            icon = DesktopIcon(self, path, info)
            icon.info_key = self._key_of(path)
            self.icons[name] = icon
            self.put(icon, 0, 0)
            icon.show_all()
        self._arrange()
        return False

    def refresh_drives(self):
        """Put an icon up for each drive, and take down the ones ejected."""
        mounts = {"drive:" + volumes.key_of(m): m for m in volumes.drives()}
        for name in [n for n in self.icons if n.startswith("drive:")]:
            if name not in mounts or self.icons[name].mount.get_name() != mounts[name].get_name():
                icon = self.icons.pop(name)
                if icon in self.selected:
                    self.selected.remove(icon)
                icon.destroy()
        for name, mount in mounts.items():
            if name not in self.icons:
                icon = DriveIcon(self, mount)
                self.icons[name] = icon
                self.put(icon, 0, 0)
                icon.show_all()
                # A drive takes the first free place; it doesn't keep one from last time.
                self.places.pop(name, None)
        self._arrange()

    @staticmethod
    def _key_of(path):
        try:
            st = os.stat(path)
            return st.st_mtime_ns, st.st_size
        except OSError:
            return None

    # ---- choosing and opening --------------------------------------------------------
    def click(self, icon, additive):
        self.grab_focus()
        if additive:
            if icon in self.selected:
                self.selected.remove(icon)
                icon.set_selected(False)
            else:
                self.selected.append(icon)
                icon.set_selected(True)
            return
        if self.selected == [icon]:
            return
        self.clear_selection()
        self.selected = [icon]
        icon.set_selected(True)

    def clear_selection(self):
        for icon in self.selected:
            icon.set_selected(False)
        self.selected = []

    def open(self, icons):
        for icon in icons:
            if icon.mount is not None and icon.path:
                subprocess.Popen(["freemac-drawer", icon.path], start_new_session=True)
                continue
            try:
                Gio.AppInfo.launch_default_for_uri(icon.uri, None)
            except GLib.Error:
                subprocess.Popen(["xdg-open", icon.path], start_new_session=True)

    def _press_empty(self, _widget, event):
        if event.window != self.get_bin_window():
            return False  # a press on an icon, passed up to us
        if event.button == 1:
            self.clear_selection()
            self.grab_focus()
        elif event.button == 3:
            self.clear_selection()
            self.desktop_menu(event)
        return True

    def _key(self, _widget, event):
        key = event.keyval
        files = [icon for icon in self.selected if icon.mount is None]
        if key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) and len(self.selected) == 1 and files:
            self.rename(self.selected[0])
        elif key == Gdk.KEY_Delete or (key == Gdk.KEY_BackSpace and event.state & Gdk.ModifierType.CONTROL_MASK):
            self.trash(files)
        elif key in (Gdk.KEY_c, Gdk.KEY_C) and event.state & Gdk.ModifierType.CONTROL_MASK:
            transfer.copy_files([icon.path for icon in files])
        elif key in (Gdk.KEY_v, Gdk.KEY_V) and event.state & Gdk.ModifierType.CONTROL_MASK:
            self.paste(move=bool(event.state & Gdk.ModifierType.MOD1_MASK))
        elif key in (Gdk.KEY_d, Gdk.KEY_D) and event.state & Gdk.ModifierType.CONTROL_MASK:
            self.run_job([icon.path for icon in files], self.folder, duplicate=True)
        elif key in (Gdk.KEY_z, Gdk.KEY_Z) and event.state & Gdk.ModifierType.CONTROL_MASK:
            transfer.undo_last(self.get_toplevel(), lambda _t: self.refresh())
        elif key == Gdk.KEY_e and event.state & Gdk.ModifierType.CONTROL_MASK:
            self.eject([icon for icon in self.selected if icon.mount is not None])
        elif key == Gdk.KEY_o and event.state & Gdk.ModifierType.CONTROL_MASK:
            self.open(list(self.selected))
        elif key == Gdk.KEY_a and event.state & Gdk.ModifierType.CONTROL_MASK:
            self.clear_selection()
            for icon in self.icons.values():
                self.selected.append(icon)
                icon.set_selected(True)
        elif key == Gdk.KEY_Escape:
            self.clear_selection()
        else:
            return False
        return True

    # ---- menus ----------------------------------------------------------------------------
    def _menu(self, items, event):
        menu = Gtk.Menu()
        menu.attach_to_widget(self, None)
        for label, action in items:
            if label is None:
                menu.append(Gtk.SeparatorMenuItem())
                continue
            item = Gtk.MenuItem(label=label)
            item.connect("activate", lambda _i, a=action: a())
            menu.append(item)
        menu.show_all()
        menu.popup_at_pointer(event)
        return menu

    def file_menu(self, event):
        drives = [icon for icon in self.selected if icon.mount is not None]
        if drives:
            what = f"“{drives[0].mount.get_name()}”" if len(drives) == 1 else f"{len(drives)} Disks"
            self.menu = self._menu([("Open", lambda: self.open(drives)), (None, None),
                                    (f"Eject {what}", lambda: self.eject(drives))], event)
            return
        icons = list(self.selected)
        items = [("Open", lambda: self.open(icons))]
        if len(icons) == 1:
            items.append(("Rename…", lambda: self.rename(icons[0])))
        items += [("Show in Drawer", self.show_folder), (None, None),
                  ("Duplicate", lambda: self.run_job([i.path for i in icons], self.folder, duplicate=True)),
                  ("Copy", lambda: transfer.copy_files([i.path for i in icons])), (None, None),
                  ("Move to Trash", lambda: self.trash(icons))]
        self.menu = self._menu(items, event)

    def desktop_menu(self, event):
        self.menu = self._menu([("New Folder", self.new_folder), ("Paste Item", self.paste), (None, None),
                                ("Change Wallpaper…", self.change_wallpaper)], event)

    # ---- copy and paste -------------------------------------------------------------------
    def run_job(self, paths, folder, move=False, duplicate=False, near=None):
        """Copy or move onto the desktop (or into a folder on it); new icons
        go in free places near the drop."""
        if not paths:
            return

        def done(job):
            if os.path.abspath(folder) == os.path.abspath(self.folder):
                for path in job.made:
                    taken = {v for k, v in self.places.items() if k in self.icons}
                    self.places[os.path.basename(path)] = self.free_cell(taken, near)
                self._save()
            self.refresh()
        transfer.Job(paths, folder, move=move, parent=self.get_toplevel(), done=done, duplicate=duplicate).start()

    def paste(self, move=False):
        self.run_job(transfer.pasted_files(), self.folder, move=move)

    def show_folder(self):
        subprocess.Popen(["freemac-drawer", self.folder], start_new_session=True)

    def change_wallpaper(self):
        subprocess.Popen(["freemac-dials", "--panel", "wallpaper"], start_new_session=True)

    # ---- changes to files -----------------------------------------------------------------
    def new_folder(self):
        name, n = "untitled folder", 2
        while os.path.exists(os.path.join(self.folder, name)):
            name = f"untitled folder {n}"
            n += 1
        try:
            os.mkdir(os.path.join(self.folder, name))
        except OSError:
            return
        transfer.note_done({"kind": "new-folder", "path": os.path.join(self.folder, name)})
        self.refresh()
        icon = self.icons.get(name)
        if icon:
            self.click(icon, False)
            GLib.idle_add(lambda: self.rename(icon) and False)

    def eject(self, icons):
        for icon in icons:
            volumes.eject(icon.mount, self.get_toplevel())

    def trash(self, icons):
        went, _error = transfer.to_trash([icon.path for icon in icons])
        if went:
            transfer.note_done({"kind": "trash", "paths": went})
        self.refresh()

    def rename(self, icon):
        popover = Gtk.Popover(relative_to=icon.label, position=Gtk.PositionType.BOTTOM)
        entry = Gtk.Entry(text=icon.name, width_chars=22)
        popover.add(entry)
        stem = os.path.splitext(icon.name)[0] if os.path.isfile(icon.path) else icon.name
        entry.connect("activate", lambda e: self._apply_rename(icon, e.get_text().strip(), popover))
        popover.show_all()
        entry.grab_focus()
        entry.select_region(0, len(stem))
        return True

    def _apply_rename(self, icon, new, popover):
        popover.popdown()
        if not new or new == icon.name or "/" in new:
            return
        old = icon.name
        try:
            Gio.File.new_for_path(icon.path).set_display_name(new, None)
        except GLib.Error:
            return
        transfer.note_done({"kind": "rename", "old": icon.path, "new": os.path.join(self.folder, new)})
        if old in self.places:
            self.places[new] = self.places.pop(old)
        self.refresh()

    # ---- dragging ---------------------------------------------------------------------------
    def drag_started(self, icon):
        self.dragging = icon

    def drag_ended(self):
        self.dragging = None

    def _folder_at(self, x, y):
        """The folder icon under a drop, if one is there and not being dragged."""
        for icon in self.icons.values():
            if icon.mount is not None or icon is self.dragging or icon in (self.selected if self.dragging else []):
                continue
            if not os.path.isdir(icon.path):
                continue
            ix, iy = icon.translate_coordinates(self, 0, 0) or (None, None)
            if ix is None:
                continue
            if ix <= x < ix + icon.get_allocated_width() and iy <= y < iy + icon.get_allocated_height():
                return icon.path
        return None

    def _alt_held(self):
        window, seat = self.get_window(), Gdk.Display.get_default().get_default_seat()
        if window is None or seat is None:
            return False
        return bool(window.get_device_position(seat.get_pointer())[3] & Gdk.ModifierType.MOD1_MASK)

    def _dropped(self, _widget, context, x, y, data, _info, time):
        uris = data.get_uris() or []
        into = self._folder_at(x, y)
        if into is not None:
            paths = [p for p in (path_of(u) for u in uris) if p and os.path.abspath(p) != into]
            move = not self._alt_held() and all(transfer.same_disk(p, into) for p in paths)
            self.run_job(paths, into, move=move)
            return
        moved = False
        incoming = []
        dragged = self.dragging.name if self.dragging else None
        anchor = self.places.get(dragged) if dragged else None
        target = self.nearest_cell(x - CELL_W // 2, y - ICON // 2)
        for uri in uris:
            drive = next((n for n, icon in self.icons.items() if icon.mount is not None and icon.uri.rstrip("/")
                          == uri.rstrip("/")), None)
            path = path_of(uri)
            if not path and drive is None:
                continue
            name = drive or os.path.basename(path)
            if drive is not None or os.path.dirname(os.path.abspath(path)) == os.path.abspath(self.folder):
                # One of ours, moved on the desktop: the others keep their
                # place next to it.
                cell = self.places.get(name)
                if anchor is not None and cell is not None:
                    cell = (max(0, target[0] + cell[0] - anchor[0]), max(0, target[1] + cell[1] - anchor[1]))
                else:
                    cell = target
                taken = {v for k, v in self.places.items() if k != name and k in self.icons}
                self.places[name] = cell if cell not in taken else self.free_cell(taken, cell)
                moved = True
                continue
            incoming.append(path)
        if moved:
            self._save()
            self.refresh()
        if incoming:
            # From another disk, files are copied, not moved, as on a Mac; ⌥ copies too.
            move = not self._alt_held() and all(self._same_disk(p) for p in incoming)
            self.run_job(incoming, self.folder, move=move, near=target)

    def _same_disk(self, path):
        try:
            return os.stat(path).st_dev == os.stat(self.folder).st_dev
        except OSError:
            return False
