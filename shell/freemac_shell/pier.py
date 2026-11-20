# SPDX-License-Identifier: GPL-3.0-or-later
"""Pier: freemac's dock, with magnification as the pointer passes over it.

Pinned apps come first, then apps that are open but not pinned. At the right
end are folder stacks (Downloads by default: click to see the newest files)
and the Trash, which shows when it has something in it, takes files dropped
on it, and can be emptied from its right-click menu.

Apps can be dragged along the Dock to move them, dragged up and out of it to
take them off, and a running app dragged in among the pinned ones stays.
A file dropped on an app opens in that app.
"""
import json
import math
import os
import shutil
import subprocess

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import apps, login_items, style  # noqa: E402
from .wfipc import Wayfire, is_minimized  # noqa: E402

BASE = 48          # icon size at rest
PEAK = 80          # icon size right under the pointer
REACH = 150        # pixels over which magnification fades out
BOUNCE_PERIOD = 0.62   # seconds per hop while an app starts
BOUNCE_HEIGHT = 0.42   # share of the icon size
BOUNCE_LIMIT = 6.0     # stop hopping after this long even if no window shows
HOLD_MS = 550        # hold an app in the dock this long to open its menu
# Parts of the desktop that open without a window of their own don't hop.
SHADOW_ROOM = 22   # px each side of the shelf for its shadow
NO_BOUNCE = {"freemac-marina.desktop", "freemac-seek.desktop"}
MARGIN = 8
CONFIG = os.path.expanduser("~/.config/freemac/pier.json")
# The desktop's own dialogs (like "Empty the Trash?") are not apps of their own.
SHELL_APP_IDS = {"freemac-pier", "freemac-topline", "freemac-force-quit"}
DEFAULT_PINNED = ["freemac-drawer.desktop", "freemac-marina.desktop", "freemac-seek.desktop", "org.gnome.Epiphany.desktop", "org.codeberg.dnkl.foot.desktop",
                  "freemac-jot.desktop",
                  "freemac-harbor.desktop", "freemac-dials.desktop", "freemac-welcome.desktop"]


# Dragging an app along the Dock (only within this program).
DOCK_TYPE = "application/x-freemac-dock-item"
DOCK_TARGET = Gtk.TargetEntry.new(DOCK_TYPE, Gtk.TargetFlags.SAME_APP, 1)
URI_TARGET = Gtk.TargetEntry.new("text/uri-list", 0, 0)

STACK_LIMIT = 15   # newest files shown when a folder stack is opened
TRASH = os.path.join(GLib.get_user_data_dir(), "Trash")


def default_stacks():
    downloads = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD)
    return [downloads or os.path.expanduser("~/Downloads")]


def load_config():
    """Pier settings, written by Dials: pinned apps, icon size, magnification,
    folder stacks and whether the Trash is shown."""
    config = {"pinned": DEFAULT_PINNED, "size": BASE, "magnify": True, "peak": PEAK,
              "stacks": default_stacks(), "trash": True}
    try:
        with open(CONFIG) as f:
            config.update(json.load(f))
    except (OSError, ValueError):
        pass
    config["size"] = max(32, min(80, int(config["size"])))
    config["peak"] = max(config["size"], min(128, int(config["peak"])))
    config["stacks"] = [os.path.expanduser(p) for p in config["stacks"] if isinstance(p, str)]
    return config


def open_in_drawer(path):
    subprocess.Popen(["freemac-drawer", path], start_new_session=True)


def newest_files(folder, limit=STACK_LIMIT):
    """(path, mtime) of the newest visible entries in folder, newest first."""
    found = []
    try:
        with os.scandir(folder) as entries:
            for entry in entries:
                if entry.name.startswith(".") or entry.name.endswith((".part", ".crdownload")):
                    continue
                try:
                    found.append((entry.path, entry.stat().st_mtime))
                except OSError:
                    pass
    except OSError:
        return []
    found.sort(key=lambda pair: pair[1], reverse=True)
    return found[:limit]


def trash_items():
    try:
        return [name for name in os.listdir(os.path.join(TRASH, "files"))]
    except OSError:
        return []


def empty_trash():
    """Delete everything in the Trash for good (the files and their notes)."""
    for part in ("files", "info", "expunged"):
        folder = os.path.join(TRASH, part)
        try:
            names = os.listdir(folder)
        except OSError:
            continue
        for name in names:
            path = os.path.join(folder, name)
            try:
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)
            except OSError:
                pass
    try:
        os.unlink(os.path.join(TRASH, "directorysizes"))
    except OSError:
        pass


def file_icon(path):
    try:
        info = Gio.File.new_for_path(path).query_info("standard::icon", Gio.FileQueryInfoFlags.NONE, None)
        return info.get_icon()
    except GLib.Error:
        return Gio.ThemedIcon.new("text-x-generic")


class Place(Gtk.Button):
    """A dock button for a place rather than an app: a folder or the Trash."""

    def __init__(self, pier, icon_name, title):
        super().__init__()
        self.pier = pier
        self.get_style_context().add_class("pier-item")
        self.set_relief(Gtk.ReliefStyle.NONE)
        self.image = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.DIALOG)
        self.image.set_pixel_size(pier.base)
        spacer = Gtk.Label(label="●")   # keeps icons level with the app items
        spacer.get_style_context().add_class("pier-dot")
        spacer.set_opacity(0.0)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.set_valign(Gtk.Align.END)
        box.pack_start(self.image, False, False, 0)
        box.pack_start(spacer, False, False, 0)
        self.add(box)
        self.set_tooltip_text(title)

    def popup(self, menu):
        menu.show_all()
        menu.popup_at_widget(self, Gdk.Gravity.NORTH, Gdk.Gravity.SOUTH, None)


class Stack(Place):
    """A folder on the dock. Clicking shows its newest files."""

    def __init__(self, pier, folder):
        name = os.path.basename(folder.rstrip("/")) or folder
        downloads = folder == default_stacks()[0]
        super().__init__(pier, "folder-download" if downloads else "folder", name)
        self.folder = folder
        self.menu = None
        self.connect("clicked", lambda *_: self.show_files())

    def show_files(self):
        self.menu = Gtk.Menu()
        files = newest_files(self.folder)
        if not files:
            empty = Gtk.MenuItem(label="Nothing here yet")
            empty.set_sensitive(False)
            self.menu.append(empty)
        for path, _mtime in files:
            item = Gtk.MenuItem()
            row = Gtk.Box(spacing=8)
            row.pack_start(Gtk.Image.new_from_gicon(file_icon(path), Gtk.IconSize.LARGE_TOOLBAR), False, False, 0)
            label = Gtk.Label(label=os.path.basename(path), xalign=0)
            label.set_ellipsize(3)
            label.set_max_width_chars(36)
            row.pack_start(label, True, True, 0)
            item.add(row)
            item.connect("activate", lambda _i, p=path: self.open_file(p))
            self.menu.append(item)
        self.menu.append(Gtk.SeparatorMenuItem())
        more = Gtk.MenuItem(label=f"Open {os.path.basename(self.folder.rstrip('/'))} in Drawer")
        more.connect("activate", lambda *_: open_in_drawer(self.folder))
        self.menu.append(more)
        self.popup(self.menu)

    @staticmethod
    def open_file(path):
        if os.path.isdir(path):
            open_in_drawer(path)
            return
        try:
            Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(path).get_uri(), None)
        except GLib.Error:
            open_in_drawer(os.path.dirname(path))


class TrashCan(Place):
    """The Trash: opens in Drawer, takes dropped files, and empties."""

    def __init__(self, pier):
        super().__init__(pier, "user-trash", "Trash")
        self.menu = None
        self.connect("clicked", lambda *_: open_in_drawer(os.path.join(TRASH, "files")))
        self.connect("button-press-event", self._press)
        self.drag_dest_set(Gtk.DestDefaults.ALL, [Gtk.TargetEntry.new("text/uri-list", 0, 0)], Gdk.DragAction.MOVE)
        self.connect("drag-data-received", self._dropped)
        os.makedirs(os.path.join(TRASH, "files"), exist_ok=True)
        self.watch = Gio.File.new_for_path(os.path.join(TRASH, "files")).monitor_directory(
            Gio.FileMonitorFlags.NONE, None)
        self.watch.connect("changed", lambda *_: self.update())
        self.update()

    def update(self):
        full = bool(trash_items())
        self.image.set_from_icon_name("user-trash-full" if full else "user-trash", Gtk.IconSize.DIALOG)
        self.image.set_pixel_size(self.pier.base)
        self.set_tooltip_text("Trash" if full else "Trash (empty)")

    def _press(self, _widget, event):
        if event.button != 3:
            return False
        self.menu = Gtk.Menu()
        opener = Gtk.MenuItem(label="Open")
        opener.connect("activate", lambda *_: open_in_drawer(os.path.join(TRASH, "files")))
        empty = Gtk.MenuItem(label="Empty Trash…")
        empty.set_sensitive(bool(trash_items()))
        empty.connect("activate", lambda *_: self.ask_to_empty())
        self.menu.append(opener)
        self.menu.append(empty)
        self.popup(self.menu)
        return True

    def ask_to_empty(self):
        count = len(trash_items())
        dialog = Gtk.MessageDialog(message_type=Gtk.MessageType.WARNING, buttons=Gtk.ButtonsType.NONE,
                                   text="Empty the Trash?")
        what = "the item" if count == 1 else f"all {count} items"
        dialog.format_secondary_text(f"This deletes {what} in the Trash for good. It can't be undone.")
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        button = dialog.add_button("Empty Trash", Gtk.ResponseType.ACCEPT)
        button.get_style_context().add_class("destructive-action")
        dialog.set_default_response(Gtk.ResponseType.CANCEL)
        answer = dialog.run()
        dialog.destroy()
        if answer == Gtk.ResponseType.ACCEPT:
            empty_trash()
            self.update()

    def _dropped(self, _widget, _context, _x, _y, data, _info, _time):
        for uri in data.get_uris() or []:
            target = Gio.File.new_for_uri(uri)
            if target.get_path():
                try:
                    target.trash(None)
                except GLib.Error:
                    pass
        self.update()


class Item(Gtk.Button):
    def __init__(self, pier, desktop_id=None, app_id=None):
        super().__init__()
        self.pier = pier
        self.desktop_id = desktop_id
        self.app_id = app_id
        self.views = []
        self.get_style_context().add_class("pier-item")
        self.set_relief(Gtk.ReliefStyle.NONE)

        info = None
        if desktop_id:
            try:
                info = Gio.DesktopAppInfo.new(desktop_id)
            except TypeError:
                info = None
        if not info and app_id:
            info = apps.app_info(app_id)
        self.info = info
        icon = info.get_icon() if info and info.get_icon() else apps.icon_for(app_id)
        self.image = Gtk.Image.new_from_gicon(icon, Gtk.IconSize.DIALOG)
        self.image.set_pixel_size(pier.base)
        self.dot = Gtk.Label(label="●")
        self.dot.get_style_context().add_class("pier-dot")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.set_valign(Gtk.Align.END)
        box.pack_start(self.image, False, False, 0)
        box.pack_start(self.dot, False, False, 0)
        self.add(box)
        self.set_tooltip_text(info.get_name() if info else apps.display_name(app_id))
        self.menu = None
        self.hold = 0
        self.icon = icon
        self.connect("clicked", self._clicked)
        self.connect("button-press-event", self._press)
        self.connect("button-release-event", self._release)
        # Drag along the Dock to move it; drag it up and out to take it off.
        self.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, [DOCK_TARGET], Gdk.DragAction.MOVE)
        # Darkened while a file it can open is held over it, as on a Mac.
        self.drop_glow = False
        self.connect_after("draw", self._draw_drop_glow)
        self.connect("drag-begin", self._drag_begin)
        self.connect("drag-failed", self._drag_failed)
        self.connect("drag-end", self._drag_end)

    @property
    def ok(self):
        return self.info is not None or self.app_id is not None

    def matches(self, view):
        app_id = (view.get("app-id") or "").lower()
        if self.app_id and self.app_id.lower() == app_id:
            return True
        if self.desktop_id:
            stem = self.desktop_id[: -len(".desktop")].lower()
            info = apps.app_info(view.get("app-id"))
            return stem == app_id or (info is not None and info.get_id() == self.desktop_id)
        return False

    def set_views(self, views):
        self.views = views
        self.dot.set_opacity(1.0 if views else 0.0)
        if views:
            self.stop_bounce()

    def _clicked(self, _button):
        if self.menu and self.menu.get_visible():
            return
        if self.views:
            latest = max(self.views, key=lambda v: v.get("last-focus-timestamp", 0))
            self.show_window(latest)
        elif self.info:
            self.info.launch([], None)
            self.bounce()

    def show_window(self, view):
        if is_minimized(view):
            self.pier.wf.set_minimized(view["id"], False)
        self.pier.wf.focus(view["id"])

    # ---- the app's menu: right-click, or hold the button down ---------------
    def _press(self, _widget, event):
        if event.type != Gdk.EventType.BUTTON_PRESS:
            return False
        if event.button == 3:
            self.show_menu()
            return True
        if event.button == 1:
            self.hold = GLib.timeout_add(HOLD_MS, self._held)
        return False

    def _release(self, _widget, _event):
        if self.hold:
            GLib.source_remove(self.hold)
            self.hold = 0
        elif self.menu and self.menu.get_visible():
            return True   # the hold opened the menu; don't also click
        return False

    def _held(self):
        self.hold = 0
        self.show_menu()
        return False

    def set_drop_glow(self, on):
        if on != self.drop_glow:
            self.drop_glow = on
            self.queue_draw()

    def _draw_drop_glow(self, _widget, cr):
        if not self.drop_glow:
            return False
        alloc = self.image.get_allocation()
        origin = self.image.translate_coordinates(self, 0, 0)
        if not origin:
            return False
        size = min(alloc.width, alloc.height)
        x = origin[0] + (alloc.width - size) / 2
        y = origin[1] + (alloc.height - size) / 2
        radius = size * 0.22
        cr.new_sub_path()
        cr.arc(x + size - radius, y + radius, radius, -math.pi / 2, 0)
        cr.arc(x + size - radius, y + size - radius, radius, 0, math.pi / 2)
        cr.arc(x + radius, y + size - radius, radius, math.pi / 2, math.pi)
        cr.arc(x + radius, y + radius, radius, math.pi, 3 * math.pi / 2)
        cr.close_path()
        cr.set_source_rgba(0, 0, 0, 0.32)
        cr.fill()
        return False

    @property
    def pin_id(self):
        """The desktop file this app is kept in the Dock by, if it has one."""
        return self.desktop_id or (self.info.get_id() if self.info else None)

    # ---- dragging it along or off the Dock ----------------------------------
    def _drag_begin(self, _widget, context):
        if self.hold:
            GLib.source_remove(self.hold)
            self.hold = 0
        self.pier.start_drag(self)
        # The icon itself follows the pointer, at its size in the Dock.
        size = self.pier.base
        found = Gtk.IconTheme.get_default().lookup_by_gicon(self.icon, size, Gtk.IconLookupFlags.FORCE_SIZE)
        if found is not None:
            try:
                Gtk.drag_set_icon_pixbuf(context, found.load_icon(), size // 2, size // 2)
            except GLib.Error:
                pass
        # A gap stays where it was, and moves with it along the Dock.
        self.set_opacity(0.0)

    def _drag_failed(self, _widget, _context, result):
        # Let go away from the Dock: a kept app comes off it, as on a Mac.
        # (An app that's open stays, as a running app, until it quits.)
        # On Wayland a drop nobody takes comes back as an error, not "no target".
        away = result in (Gtk.DragResult.NO_TARGET, Gtk.DragResult.ERROR) and self.pier.drag_outside
        if away and self in self.pier.pinned and self.pin_id:
            self.pier.removed = True
            self.pier.set_pinned(self.pin_id, False)
            return True   # no fly-back to where it was
        return False

    def _drag_end(self, _widget, _context):
        self.set_opacity(1.0)
        self.show()
        self.pier.end_drag()

    def show_menu(self):
        name = self.info.get_name() if self.info else apps.display_name(self.app_id)
        self.menu = Gtk.Menu()

        def labelled(label, tick=""):
            # Every item lines up after the tick column the window list uses.
            item = Gtk.MenuItem()
            box = Gtk.Box(spacing=0)
            mark = Gtk.Label(label=tick, xalign=0)
            mark.set_size_request(18 if self.views else 0, -1)
            box.pack_start(mark, False, False, 0)
            box.pack_start(Gtk.Label(label=label, xalign=0), True, True, 0)
            item.add(box)
            return item

        def add(label, action=None):
            item = labelled(label)
            if action:
                item.connect("activate", lambda *_: action())
            else:
                item.set_sensitive(False)
            self.menu.append(item)
            return item

        views = sorted(self.views, key=lambda v: (v.get("title") or "").lower())
        # The app's front window is the one it last had in focus.
        front = max(views, key=lambda v: v.get("last-focus-timestamp", 0)).get("id") if views else None
        for view in views:
            title = (view.get("title") or name)[:60]
            # The front window gets a tick, as on a Mac.
            item = labelled(title, "\u2713" if view.get("id") == front else "")
            item.connect("activate", lambda *_, view=view: self.show_window(view))
            self.menu.append(item)
        if views:
            self.menu.append(Gtk.SeparatorMenuItem())
        desktop_id = self.desktop_id or (self.info.get_id() if self.info else None)
        options = labelled("Options")
        options.set_sensitive(desktop_id is not None)
        sub = Gtk.Menu()
        # Ticks, not boxes, as a Mac's Dock shows them.
        for label, on, turn in (
                ("Keep in Dock", self in self.pier.pinned,
                 lambda now: self.pier.set_pinned(desktop_id, now)),
                ("Open at Login", login_items.is_on(desktop_id),
                 lambda now: login_items.set_on(desktop_id, now))):
            choice = Gtk.MenuItem()
            box = Gtk.Box(spacing=0)
            mark = Gtk.Label(label="\u2713" if on else "", xalign=0)
            mark.set_size_request(18, -1)
            box.pack_start(mark, False, False, 0)
            box.pack_start(Gtk.Label(label=label, xalign=0), True, True, 0)
            choice.add(box)
            choice.connect("activate", lambda *_, on=on, turn=turn: turn(not on))
            sub.append(choice)
        options.set_submenu(sub)
        self.menu.append(options)
        if views:
            self.menu.append(Gtk.SeparatorMenuItem())
            add("Hide", lambda: [self.pier.wf.set_minimized(v["id"], True) for v in self.views])
            add("Quit", lambda: self.pier.wf.quit(self.views[0].get("app-id") or ""))
        elif self.info:
            add("Open", lambda: self._clicked(None))
        self.popup(self.menu)

    def popup(self, menu):
        menu.show_all()
        menu.popup_at_widget(self, Gdk.Gravity.NORTH, Gdk.Gravity.SOUTH, None)

    # ---- the launch bounce -------------------------------------------------
    # While an app starts, its icon hops up and down until its first window
    # shows (or for BOUNCE_LIMIT seconds), so a click always gets an answer.
    bouncing = None

    def bounce(self):
        settings = Gtk.Settings.get_default()
        if self.bouncing or self.desktop_id in NO_BOUNCE or (settings and not settings.props.gtk_enable_animations):
            return
        self.dot.set_opacity(1.0)
        self.bouncing = (GLib.get_monotonic_time(), GLib.timeout_add(16, self._bounce_step))

    def _bounce_step(self):
        started, _source = self.bouncing
        elapsed = (GLib.get_monotonic_time() - started) / 1e6
        if elapsed > BOUNCE_LIMIT:
            self.bouncing = None
            self.image.set_margin_bottom(0)
            self.dot.set_opacity(1.0 if self.views else 0.0)
            return False
        phase = (elapsed % BOUNCE_PERIOD) / BOUNCE_PERIOD
        # Up fast, ease at the top, down with a little weight: one sine arch per hop.
        height = int(round(self.pier.base * BOUNCE_HEIGHT * math.sin(math.pi * phase)))
        self.image.set_margin_bottom(height)
        return True

    def stop_bounce(self):
        if self.bouncing:
            GLib.source_remove(self.bouncing[1])
            self.bouncing = None
            self.image.set_margin_bottom(0)


class Pier(Gtk.Window):
    def __init__(self):
        super().__init__(title="Pier")
        style.make_transparent(self)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_namespace(self, "freemac-pier")
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.BOTTOM, MARGIN)

        self.shelf = Gtk.Box(spacing=0)
        self.shelf.set_valign(Gtk.Align.END)
        self.shelf.set_halign(Gtk.Align.CENTER)
        self.shelf.get_style_context().add_class("pier-shelf")
        outer = Gtk.EventBox()
        self.outer = outer
        outer.set_visible_window(False)
        # The dock's background is painted here at a fixed height, beneath
        # the icons, so magnified and bouncing icons rise out of it, as on a
        # Mac, instead of stretching it.
        outer.connect("draw", self._draw_backing)
        holder = Gtk.Box()
        holder.set_valign(Gtk.Align.END)
        # Room at the sides for the shelf's soft shadow, so the window's own
        # edge never cuts it off in a straight line.
        holder.set_margin_start(SHADOW_ROOM)
        holder.set_margin_end(SHADOW_ROOM)
        holder.pack_start(self.shelf, True, False, 0)
        outer.add(holder)
        outer.add_events(1 << 2 | 1 << 13)  # pointer motion, leave
        outer.connect("motion-notify-event", self._motion)
        outer.connect("leave-notify-event", lambda *_: self._magnify(None))
        # Apps dragged along the Dock, and files dropped on an app to open them.
        outer.drag_dest_set(0, [DOCK_TARGET, URI_TARGET], Gdk.DragAction.MOVE | Gdk.DragAction.COPY)
        outer.connect("drag-motion", self._drag_motion)
        outer.connect("drag-leave", self._drag_leave)
        outer.connect("drag-drop", self._drag_drop)
        outer.connect("drag-data-received", self._drag_data)
        self.dragging, self.drag_at, self.dropped, self.removed = None, None, False, False
        self.drop_on, self.glowing, self.drag_outside = None, None, False
        self.drop_candidate = None
        # What kind of files a drag carries, read as it first comes over the
        # Dock, so only apps that can open them light up.
        self.peek_context, self.peek_types, self.peek_at = None, None, None
        self.peeked = (None, [])   # (drag, its files), kept for the drop
        self.add(outer)

        self.pinned = []
        self.extra = {}
        self.running_sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        self.running_sep.get_style_context().add_class("pier-sep")
        self.shelf.pack_start(self.running_sep, False, False, 0)
        # Folders and the Trash sit at the right end, after their own line.
        self.places_sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        self.places_sep.get_style_context().add_class("pier-sep")
        self.shelf.pack_end(self.places_sep, False, False, 0)
        self.places = []
        self.config = None
        self.load()
        self.monitor = Gio.File.new_for_path(CONFIG).monitor_file(Gio.FileMonitorFlags.NONE, None)
        self.monitor.connect("changed", lambda *_: GLib.timeout_add(200, self._reload))

        self._hint_pending, self.own_id, self.hints = 0, None, {}
        try:
            self.wf = Wayfire(on_event=lambda _e: self.refresh())
        except OSError:
            self.wf = None
        self.refresh()

    def load(self):
        """(Re)read pier.json: sizes, magnification and the pinned apps."""
        config = load_config()
        self.base = config["size"]
        self.peak = config["peak"] if config["magnify"] else config["size"]
        # Windows avoid the resting dock; magnified icons may overlap them.
        GtkLayerShell.set_exclusive_zone(self, self.base + 28)
        self.outer.set_size_request(-1, self.peak + 30)
        # Icon, the running dot under it and the shelf's top and bottom padding.
        self.rest_height = self.base + 22
        if self.config is None or config["pinned"] != self.config["pinned"]:
            for item in self.pinned:
                self.shelf.remove(item)
            self.pinned = []
            for desktop_id in config["pinned"]:
                item = Item(self, desktop_id=desktop_id)
                if item.info:
                    self.pinned.append(item)
                    self.shelf.pack_start(item, False, False, 0)
                    self.shelf.reorder_child(item, len(self.pinned) - 1)
                    item.show_all()
        if self.config is None or (config["stacks"], config["trash"]) != (self.config["stacks"], self.config["trash"]):
            for place in self.places:
                self.shelf.remove(place)
            self.places = [Stack(self, folder) for folder in config["stacks"]]
            if config["trash"]:
                self.places.append(TrashCan(self))
            # pack_end fills from the right, so add them in reverse.
            for place in reversed(self.places):
                self.shelf.pack_end(place, False, False, 0)
                place.show_all()
            self.shelf.reorder_child(self.places_sep, -1)
        self.config = config
        for item in self.items():
            item.image.set_pixel_size(self.base)

    def _draw_backing(self, widget, cr):
        alloc = self.shelf.get_allocation()
        origin = self.shelf.translate_coordinates(widget, 0, 0)
        if not origin or alloc.width <= 1:
            return False
        x, bottom = origin[0], origin[1] + alloc.height
        context = self.shelf.get_style_context()
        context.save()
        context.add_class("pier-shelf-bg")
        Gtk.render_background(context, cr, x, bottom - self.rest_height, alloc.width, self.rest_height)
        Gtk.render_frame(context, cr, x, bottom - self.rest_height, alloc.width, self.rest_height)
        context.restore()
        return False

    def _reload(self):
        self.load()
        self.refresh()
        return False

    def items(self):
        return self.pinned + list(self.extra.values()) + self.places

    def refresh(self):
        views = self.wf.views() if self.wf else []
        claimed = set()
        for item in self.pinned:
            mine = [v for v in views if item.matches(v)]
            claimed.update(v["id"] for v in mine)
            item.set_views(mine)
        unpinned = {}
        for view in views:
            if view["id"] in claimed or (view.get("app-id") or "").lower() in SHELL_APP_IDS:
                continue
            unpinned.setdefault(view.get("app-id") or f"view-{view['id']}", []).append(view)
        for app_id in list(self.extra):
            if app_id not in unpinned:
                self.shelf.remove(self.extra.pop(app_id))
        for app_id, its_views in unpinned.items():
            if app_id not in self.extra:
                item = Item(self, app_id=app_id)
                self.extra[app_id] = item
                self.shelf.pack_start(item, False, False, 0)
                item.show_all()
            self.extra[app_id].set_views(its_views)
        self.running_sep.set_visible(bool(self.extra))
        self.places_sep.set_visible(bool(self.places))
        if not self._hint_pending:
            self._hint_pending = GLib.timeout_add(200, self._send_hints)
        return False

    def set_pinned(self, desktop_id, keep):
        """Keep in Dock: add the app to (or take it off) the pinned list in
        pier.json; the file watch then rebuilds the dock."""
        pinned = self._saved_pinned()
        if keep and desktop_id not in pinned:
            pinned.append(desktop_id)
        elif not keep and desktop_id in pinned:
            pinned.remove(desktop_id)
        self._save_pinned(pinned)

    def _saved_pinned(self):
        try:
            with open(CONFIG) as f:
                saved = json.load(f)
        except (OSError, ValueError):
            saved = {}
        return list(saved.get("pinned", self.config["pinned"] if self.config else DEFAULT_PINNED))

    def _save_pinned(self, pinned):
        try:
            with open(CONFIG) as f:
                saved = json.load(f)
        except (OSError, ValueError):
            saved = {}
        saved["pinned"] = pinned
        os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
        tmp = CONFIG + ".tmp"
        with open(tmp, "w") as f:
            json.dump(saved, f, indent=1)
        os.replace(tmp, CONFIG)

    # ---- dragging apps along the Dock, and files onto apps -------------------
    def _center(self, widget, relative_to):
        alloc = widget.get_allocation()
        coords = widget.translate_coordinates(relative_to, alloc.width // 2, 0)
        return coords[0] if coords else None

    def _item_at(self, x, relative_to):
        for item in self.items():
            alloc = item.get_allocation()
            coords = item.translate_coordinates(relative_to, 0, 0)
            if coords and coords[0] <= x < coords[0] + alloc.width:
                return item
        return None

    def start_drag(self, item):
        self.dragging, self.drag_at, self.dropped, self.removed = item, None, False, False
        self.drag_outside = False

    def end_drag(self):
        item, self.dragging = self.dragging, None
        if not self.dropped and not self.removed and item is not None:
            self._restore_order()
        self.dropped = self.removed = False

    def _restore_order(self):
        for index, item in enumerate(self.pinned):
            self.shelf.reorder_child(item, index)
        line = self.shelf.get_children().index(self.running_sep)
        for item in self.extra.values():
            if self.shelf.get_children().index(item) < line:
                self.shelf.reorder_child(item, -1)

    def _move_dragged(self, x, widget):
        """Slide the dragged app's gap to where the pointer is, among the
        kept apps. A running app moves in among them only if it can be kept."""
        item = self.dragging
        item.show()
        others = [p for p in self.pinned if p is not item]
        line = self._center(self.running_sep, widget) if self.running_sep.get_visible() else None
        if item not in self.pinned and (not item.pin_id or (line is not None and x > line)):
            if self.drag_at is not None:
                self.drag_at = None
                self.shelf.reorder_child(item, -1)
            return
        index = 0
        for other in others:
            center = self._center(other, widget)
            if center is not None and center < x:
                index += 1
        if index != self.drag_at:
            self.drag_at = index
            self.shelf.reorder_child(item, index)

    def _mark_drop(self, item):
        if self.glowing is not None and self.glowing is not item:
            self.glowing.set_drop_glow(False)
        self.glowing = item
        if item is not None:
            item.set_drop_glow(True)

    @staticmethod
    def _opens_files(item, types=None):
        """Whether this app can open files of these types. An app that names
        the kinds of file it opens takes only those, as on a Mac."""
        if not isinstance(item, Item) or item.info is None:
            return False
        if not (item.info.supports_files() or item.info.supports_uris()):
            return False
        accepts = item.info.get_supported_types() or []
        if not accepts or not types:
            return True
        return all(any(Gio.content_type_is_a(kind, ok) for ok in accepts) for kind in types)

    @staticmethod
    def _types_of(uris):
        kinds = []
        for uri in uris:
            path = Gio.File.new_for_uri(uri).get_path()
            if path and os.path.isdir(path):
                kinds.append("inode/directory")
            else:
                kind, _uncertain = Gio.content_type_guess(path or uri, None)
                kinds.append(kind)
        return kinds

    def _show_drop_target(self, context, x, widget, time):
        item = self._item_at(x, widget)
        # Kept for the drop: by then the icons have shrunk back, so the
        # pointer's spot may be over a different one.
        self.drop_candidate = item
        if self._opens_files(item, self.peek_types):
            self._mark_drop(item)
            Gdk.drag_status(context, Gdk.DragAction.COPY, time)
        else:
            self._mark_drop(None)
            Gdk.drag_status(context, 0, time)

    def _drag_motion(self, widget, context, x, _y, time):
        target = widget.drag_dest_find_target(context, None)
        if target is None:
            Gdk.drag_status(context, 0, time)
            return False
        if target.name() == DOCK_TYPE and self.dragging is not None:
            self.drag_outside = False
            self._move_dragged(x, widget)
            self._magnify(x, widget)
            Gdk.drag_status(context, Gdk.DragAction.MOVE, time)
            return True
        self._magnify(x, widget)
        self.peek_at = x
        if self.peek_context is not context:
            # First look: ask for the file list, and answer once it comes.
            self.peek_context, self.peek_types, self.peeked = context, None, (None, [])
            self.drop_candidate = None
            widget.drag_get_data(context, target, time)
            return True
        if self.peek_types is not None:
            self._show_drop_target(context, x, widget, time)
        return True

    def _drag_leave(self, _widget, _context, _time):
        self._mark_drop(None)
        self.peek_context, self.peek_types = None, None
        self._magnify(None)
        # Dragged up and out: its gap closes, as it will if it's let go there.
        if self.dragging is not None:
            self.drag_outside = True
            self.dragging.hide()

    def _drag_drop(self, widget, context, x, _y, time):
        target = widget.drag_dest_find_target(context, None)
        if target is None:
            return False
        if target.name() == DOCK_TYPE and self.dragging is not None:
            item = self.dragging
            self.drag_outside = False
            # Where its gap was last is where it goes.
            item.show()
            children = self.shelf.get_children()
            line = children.index(self.running_sep)
            kept = [c.pin_id for c in children[:line] if isinstance(c, Item) and c.pin_id]
            # Apps kept in the list but not shown (not installed now) stay kept.
            kept += [d for d in self._saved_pinned() if d not in kept and d not in [
                p.pin_id for p in self.pinned]]
            self.dropped = True
            if kept != self._saved_pinned():
                self._save_pinned(kept)
            Gtk.drag_finish(context, True, False, time)
            return True
        item = self.drop_candidate or self._item_at(x, widget)
        self.drop_candidate = None
        if not self._opens_files(item):
            self._mark_drop(None)
            Gtk.drag_finish(context, False, False, time)
            return True
        if self.peeked[1]:
            # The files were already read on the way over.
            self._open_dropped(item, context, self.peeked[1], time)
            return True
        self.drop_on = item
        widget.drag_get_data(context, target, time)
        return True

    def _drag_data(self, widget, context, _x, _y, data, _info, time):
        uris = data.get_uris() or []
        if self.drop_on is None:
            # The first look while dragging over: note the kinds of file.
            if context is self.peek_context:
                self.peeked = (context, uris)
                self.peek_types = self._types_of(uris)
                if self.peek_at is not None:
                    self._show_drop_target(context, self.peek_at, widget, time)
            return
        item, self.drop_on = self.drop_on, None
        self._open_dropped(item, context, uris, time)

    def _open_dropped(self, item, context, uris, time):
        self.peeked = (None, [])
        self._mark_drop(None)
        if not self._opens_files(item, self._types_of(uris)) or not uris:
            Gtk.drag_finish(context, False, False, time)
            return
        try:
            item.info.launch_uris(uris, None)
            if not item.views:
                item.bounce()
            Gtk.drag_finish(context, True, False, time)
        except GLib.Error:
            Gtk.drag_finish(context, False, False, time)

    def _send_hints(self):
        """Tell Strata where each window's icon sits, so minimizing a window
        shrinks it into its icon here and restoring grows it back out."""
        self._hint_pending = 0
        if not self.wf:
            return False
        if self.own_id is None:
            self.own_id = self.wf.own_view("freemac-pier")
            if self.own_id is None:
                return False
        sent = {}
        for item in self.pinned + list(self.extra.values()):
            alloc = item.image.get_allocation()
            origin = item.image.translate_coordinates(self, 0, 0)
            if not origin or alloc.width <= 1:
                continue
            size = self.base
            x = origin[0] + (alloc.width - size) // 2
            y = origin[1] + alloc.height - size
            for view in item.views:
                rect = (x, y, size, size)
                sent[view["id"]] = rect
                if self.hints.get(view["id"]) != rect:
                    if not self.wf.minimize_hint(view["id"], *rect, relative_to=self.own_id):
                        self.own_id = None   # Pier's surface may be new; look again next time
                        rect = None
                    sent[view["id"]] = rect
        self.hints = sent
        return False

    def _motion(self, widget, event):
        self._magnify(event.x, widget)

    def _magnify(self, pointer_x, widget=None):
        """Grow icons near the pointer along a cosine curve."""
        for item in self.items():
            size = self.base
            if pointer_x is not None and widget is not None:
                alloc = item.get_allocation()
                coords = item.translate_coordinates(widget, alloc.width // 2, 0)
                if coords:
                    distance = abs(pointer_x - coords[0])
                    if distance < REACH:
                        size = int(self.base + (self.peak - self.base) * math.cos(distance / REACH * math.pi / 2))
            item.image.set_pixel_size(size)


def main():
    style.apply()
    win = Pier()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    win.refresh()
    GLib.timeout_add_seconds(5, lambda: win.refresh() or True)
    Gtk.main()
