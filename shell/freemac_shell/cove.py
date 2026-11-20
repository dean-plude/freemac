# SPDX-License-Identifier: GPL-3.0-or-later
"""Cove: your photos.

Every picture in the Pictures folder, newest first, in months under a large
heading, as square tiles that a slider (or ⌘+ and ⌘−) makes bigger or
smaller. Double-click (or Return) opens a photo large in the window; the
arrow keys go to the next and previous, Escape goes back. A photo can be
marked a favourite (the heart, or the full stop key), shown with its details
(⌘I), opened in Frame for markup, or moved to the Trash (⌘⌫). Tiles can be
dragged into mail, folders and other apps.

The sidebar has Library, Favourites and Recently Added, and, while one is
plugged in, each camera, phone or memory card with photos on it: choosing
it shows its pictures, with those already brought in dimmed, and Import All
New Items copies the rest into Pictures, in a folder for each day. The work
is in photos_store.py. Original freemac code.
"""
import collections
import os
import subprocess
import sys
import threading
import time

import cairo
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

from . import alert, menus, style  # noqa: E402
from . import photos_store as store  # noqa: E402

APP_ID = "org.freemac.Cove"
SIZES = (90, 120, 160, 210, 260)   # tile sizes, smallest to largest
START_SIZE = 2
KEEP_TILES = 700                   # small pictures kept in memory at once
ACCENT = (0.18, 0.48, 0.96)

CSS = b"""
.cove-side { background: alpha(currentColor, 0.04); }
list.cove-side { background: transparent; }
.cove-side row { padding: 5px 10px; border-radius: 7px; margin: 0 6px; background: transparent; }
.cove-side row:selected { background: alpha(@theme_fg_color, 0.12); }
.cove-side row:selected label { color: @theme_fg_color; }
.cove-side image { color: #2f7bf5; }
.cove-side-head { font-size: 12px; font-weight: 700; color: alpha(currentColor, 0.5); padding: 12px 14px 2px 14px; }
.cove-count { color: alpha(currentColor, 0.5); font-size: 12px; }
.cove-grid { background: @theme_base_color; }
.cove-month { font-size: 22px; font-weight: 700; }
.cove-month-sub { font-size: 13px; color: alpha(currentColor, 0.5); }
.cove-grid flowboxchild { padding: 0; background: transparent; outline: none; }
.cove-viewer { background: @theme_base_color; }
.cove-empty-title { font-size: 20px; font-weight: 700; color: alpha(currentColor, 0.55); }
.cove-empty-text { font-size: 13px; color: alpha(currentColor, 0.5); }
.cove-bar { padding: 10px 20px; border-bottom: 1px solid alpha(currentColor, 0.1); background: @theme_base_color; }
.cove-bar-title { font-size: 18px; font-weight: 700; }
.cove-info { padding: 14px; }
.cove-info-key { color: alpha(currentColor, 0.55); font-size: 12px; }
.cove-info-value { font-size: 13px; }
.cove-fav:checked image, .cove-fav:checked { color: #f04d3e; }
"""


def plural(n, one, many=None):
    return f"{n} {one if n == 1 else (many or one + 's')}"


def human_size(size):
    for unit in ("bytes", "KB", "MB", "GB"):
        if size < 1000 or unit == "GB":
            return f"{size:.0f} {unit}" if unit == "bytes" else f"{size:.1f} {unit}"
        size /= 1000
    return ""


def long_date(when):
    return time.strftime("%B %-d, %Y", time.localtime(when))


def clock(when):
    return time.strftime("%-I:%M %p", time.localtime(when))


def square_crop(picture, side):
    """The middle square of a picture, side pixels across."""
    w, h = picture.get_width(), picture.get_height()
    edge = min(w, h)
    middle = picture.new_subpixbuf((w - edge) // 2, (h - edge) // 2, edge, edge)
    side = min(side, edge)
    return middle.scale_simple(side, side, GdkPixbuf.InterpType.BILINEAR)


# -- small pictures, made away from the window ---------------------------------

class Loader:
    """Makes tiles' small pictures on one worker thread, the most recently
    drawn first (so whatever is on screen comes first), and keeps only the
    last KEEP_TILES in memory."""

    def __init__(self):
        self.waiting = []
        self.wanted = set()
        self.kept = collections.OrderedDict()
        self.lock = threading.Lock()
        self.wake = threading.Event()
        threading.Thread(target=self._work, daemon=True).start()

    def want(self, tile):
        with self.lock:
            if tile not in self.wanted:
                self.wanted.add(tile)
                self.waiting.append(tile)
        self.wake.set()

    def forget_all(self):
        with self.lock:
            self.waiting.clear()
            self.wanted.clear()
        self.kept.clear()

    def keep(self, tile):
        self.kept[tile] = True
        self.kept.move_to_end(tile)
        while len(self.kept) > KEEP_TILES:
            old, _ = self.kept.popitem(last=False)
            old.picture = None

    def _work(self):
        while True:
            self.wake.wait()
            with self.lock:
                if not self.waiting:
                    self.wake.clear()
                    continue
                tile = self.waiting.pop()
            try:
                picture = tile.make_picture()
            except Exception:   # an unreadable file gets a blank tile, not a dead loader
                picture = None
            GLib.idle_add(self._done, tile, picture)

    def _done(self, tile, picture):
        with self.lock:
            self.wanted.discard(tile)
        if tile.get_parent() is None:   # its grid was replaced meanwhile
            return False
        tile.set_picture(picture)
        if picture is not None:
            self.keep(tile)
        return False


class Tile(Gtk.FlowBoxChild):
    """One square photo in a grid: a photo in the library, or an item on a
    camera or phone."""

    def __init__(self, window, item, size, device=False, dimmed=False):
        super().__init__()
        self.window, self.item, self.device, self.dimmed = window, item, device, dimmed
        self.picture, self.failed = None, False
        self.side = SIZES[-1] * window.get_scale_factor()   # read here, not on the loader's thread
        self.area = Gtk.DrawingArea()
        self.area.connect("draw", self._draw)
        self.add(self.area)
        self.resize(size)
        if not device:
            self.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, [], Gdk.DragAction.COPY)
            self.drag_source_add_uri_targets()
            self.connect("drag-data-get", self._drag_data)
            self.connect("drag-begin", self._drag_begin)

    def resize(self, size):
        self.size = size
        self.area.set_size_request(size, size)

    def make_picture(self):   # on the loader's thread
        side = self.side
        if self.device:
            found = store.device_thumbnail(self.item)
        else:
            found = store.thumbnail(self.item.path, self.item.mtime)
        return square_crop(found, side) if found is not None else None

    def set_picture(self, picture):
        self.picture = picture
        self.failed = picture is None
        self.area.queue_draw()

    def _drag_data(self, _w, _ctx, data, _info, _time):
        data.set_uris([Gio.File.new_for_path(self.item.path).get_uri()])

    def _drag_begin(self, _w, ctx):
        if self.picture is not None:
            icon = self.picture.scale_simple(80, 80, GdkPixbuf.InterpType.BILINEAR)
            Gtk.drag_set_icon_pixbuf(ctx, icon, 40, 40)

    def _draw(self, area, cr):
        size = self.size
        if self.picture is None:
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.14)
            cr.rectangle(0, 0, size, size)
            cr.fill()
            if not self.failed:
                self.window.loader.want(self)
        else:
            cr.save()
            scale = size / self.picture.get_width()
            cr.scale(scale, scale)
            Gdk.cairo_set_source_pixbuf(cr, self.picture, 0, 0)
            cr.get_source().set_filter(cairo.FILTER_GOOD)
            cr.paint_with_alpha(0.45 if self.dimmed else 1)
            cr.restore()
            self.window.loader.keep(self)
        if self.dimmed:   # already imported: a tick in the corner
            cr.set_source_rgba(0.13, 0.65, 0.33, 1)
            cr.arc(size - 13, size - 13, 9, 0, 6.2832)
            cr.fill()
            cr.set_source_rgb(1, 1, 1)
            cr.set_line_width(2)
            cr.move_to(size - 17, size - 13)
            cr.line_to(size - 14, size - 10)
            cr.line_to(size - 9, size - 16)
            cr.stroke()
        if not self.device and self.item.path in self.window.favourite_paths:
            self._heart(cr, 8, size - 20)
        if self.get_state_flags() & Gtk.StateFlags.SELECTED:
            cr.set_source_rgb(*ACCENT)
            cr.set_line_width(4)
            cr.rectangle(2, 2, size - 4, size - 4)
            cr.stroke()
        return False

    @staticmethod
    def _heart(cr, x, y):
        cr.save()
        cr.translate(x, y)
        cr.move_to(6, 11)
        cr.curve_to(-2, 5, 1, -1, 6, 3)
        cr.curve_to(11, -1, 14, 5, 6, 11)
        cr.close_path()
        cr.set_source_rgb(1, 1, 1)
        cr.fill_preserve()
        cr.set_source_rgba(0, 0, 0, 0.3)
        cr.set_line_width(1)
        cr.stroke()
        cr.restore()


# -- the large view -----------------------------------------------------------

class Viewer(Gtk.DrawingArea):
    def __init__(self):
        super().__init__()
        self.get_style_context().add_class("cove-viewer")
        self.picture = None
        self.small = False   # showing the small copy until the full picture is read
        self.token = 0
        self.connect("draw", self._draw)

    def show_photo(self, photo, placeholder):
        """Show the small picture at once, then the full one when it's read."""
        self.token += 1
        token = self.token
        self.picture, self.small = placeholder, True
        self.queue_draw()
        scale = self.get_scale_factor()
        room = self.get_parent() or self
        width = max(800, room.get_allocated_width() * scale)
        height = max(600, room.get_allocated_height() * scale)

        def work():
            try:
                big = store.full_picture(photo.path, width, height)
            except GLib.Error:
                big = None
            GLib.idle_add(self._loaded, token, big)
        threading.Thread(target=work, daemon=True).start()

    def _loaded(self, token, big):
        if token == self.token and big is not None:
            self.picture, self.small = big, False
            self.queue_draw()
        return False

    def _draw(self, area, cr):
        ctx = self.get_style_context()
        width, height = self.get_allocated_width(), self.get_allocated_height()
        Gtk.render_background(ctx, cr, 0, 0, width, height)
        if self.picture is None:
            return False
        pw, ph = self.picture.get_width(), self.picture.get_height()
        room_w, room_h = width - 40, height - 40
        scale = min(room_w / pw, room_h / ph)
        if not self.small:   # never blown up past the photo's own pixels
            scale = min(scale, 1 / self.get_scale_factor())
        w, h = pw * scale, ph * scale
        cr.translate((width - w) / 2, (height - h) / 2)
        cr.scale(scale, scale)
        Gdk.cairo_set_source_pixbuf(cr, self.picture, 0, 0)
        cr.get_source().set_filter(cairo.FILTER_GOOD)
        cr.paint()
        return False


# -- the window ---------------------------------------------------------------

class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Cove")
        self.set_default_size(1060, 700)
        self.set_icon_name("freemac-cove")
        self.loader = Loader()
        self.photos, self.shown, self.tiles = [], [], []
        self.favourite_paths = store.favourites()
        self.size_at = START_SIZE
        self.view = "library"
        self.current = None        # index into self.shown in the large view
        self.device = None
        self.importing = False
        self.last_scan = 0
        self.choosing = False

        header = Gtk.HeaderBar(show_close_button=True)
        self.header = header
        self.back = Gtk.Button.new_from_icon_name("go-previous-symbolic", Gtk.IconSize.BUTTON)
        self.back.set_tooltip_text("Back (Escape)")
        self.back.connect("clicked", lambda *_: self.close_photo())
        self.back.set_no_show_all(True)
        header.pack_start(self.back)
        self.zoom = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, len(SIZES) - 1, 1)
        self.zoom.set_draw_value(False)
        self.zoom.set_size_request(110, -1)
        self.zoom.set_value(self.size_at)
        self.zoom.set_tooltip_text("Tile size (⌘+ and ⌘−)")
        self.zoom.connect("value-changed", lambda s: self.set_size(int(round(s.get_value()))))
        header.pack_start(self.zoom)
        self.delete_button = self._header_button("user-trash-symbolic", "Move to Trash (⌘⌫)", self.delete_photo)
        self.info_button = Gtk.MenuButton()
        self.info_button.add(Gtk.Image(icon_name="help-about-symbolic", icon_size=Gtk.IconSize.BUTTON, visible=True))
        self.info_button.set_tooltip_text("Info (⌘I)")
        self.info_button.set_no_show_all(True)
        self.info_popover = Gtk.Popover()
        self.info_button.set_popover(self.info_popover)
        self.fav_button = Gtk.ToggleButton()
        self.fav_button.add(Gtk.Image(icon_name="emblem-favorite-symbolic", icon_size=Gtk.IconSize.BUTTON, visible=True))
        self.fav_button.get_style_context().add_class("cove-fav")
        self.fav_button.set_tooltip_text("Favourite (.)")
        self.fav_button.set_no_show_all(True)
        self.fav_handler = self.fav_button.connect("toggled", lambda b: self.set_favourite(b.get_active()))
        for widget in (self.delete_button, self.info_button, self.fav_button):
            header.pack_end(widget)
        self.import_all = Gtk.Button(label="Import All New Items")
        self.import_all.get_style_context().add_class("suggested-action")
        self.import_all.connect("clicked", lambda *_: self.start_import(None))
        self.import_some = Gtk.Button(label="Import Selected")
        self.import_some.connect("clicked", lambda *_: self.start_import(self._chosen_items()))
        for widget in (self.import_all, self.import_some):
            widget.set_no_show_all(True)
            header.pack_end(widget)
        self.set_titlebar(header)

        paned = Gtk.Paned()
        side_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        side_scroll.get_style_context().add_class("cove-side")
        side_scroll.set_size_request(200, -1)
        self.sidebar = Gtk.ListBox()
        self.sidebar.get_style_context().add_class("cove-side")
        self.sidebar.set_header_func(self._side_header)
        self.sidebar.connect("row-selected", self._side_selected)
        side_scroll.add(self.sidebar)
        paned.pack1(side_scroll, False, False)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=120)
        self.grid_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.grid_scroll.get_style_context().add_class("cove-grid")
        self.grid_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.grid_box.get_style_context().add_class("cove-grid")
        self.grid_scroll.add(self.grid_box)
        self.stack.add_named(self.grid_scroll, "grid")
        self.viewer = Viewer()
        self.stack.add_named(self.viewer, "viewer")
        self.empty_title = Gtk.Label()
        self.empty_title.get_style_context().add_class("cove-empty-title")
        self.empty_text = Gtk.Label(wrap=True, max_width_chars=46, justify=Gtk.Justification.CENTER)
        self.empty_text.get_style_context().add_class("cove-empty-text")
        empty_icon = Gtk.Image.new_from_icon_name("camera-photo-symbolic", Gtk.IconSize.DIALOG)
        empty_icon.set_pixel_size(64)
        empty_icon.set_opacity(0.3)
        empty = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, valign=Gtk.Align.CENTER)
        empty.get_style_context().add_class("cove-grid")
        for widget in (empty_icon, self.empty_title, self.empty_text):
            empty.pack_start(widget, False, False, 0)
        self.stack.add_named(empty, "empty")
        self.busy = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, valign=Gtk.Align.CENTER)
        self.busy_spinner = Gtk.Spinner()
        self.busy_spinner.set_size_request(32, 32)
        self.busy_label = Gtk.Label()
        self.busy_label.get_style_context().add_class("cove-empty-text")
        self.busy_bar = Gtk.ProgressBar(halign=Gtk.Align.CENTER)
        self.busy_bar.set_size_request(260, -1)
        self.busy_bar.set_no_show_all(True)
        for widget in (self.busy_spinner, self.busy_label, self.busy_bar):
            self.busy.pack_start(widget, False, False, 0)
        self.stack.add_named(self.busy, "busy")
        paned.pack2(self.stack, True, False)
        self.add(paned)

        menus.add_actions(self, {
            "import": self.import_from_menu, "show-folder": self.show_in_folder,
            "open-frame": self.open_in_frame, "close": self.close,
            "delete": self.delete_photo, "favourite": self.toggle_favourite,
            "info": self.show_info, "bigger": lambda: self.set_size(self.size_at + 1),
            "smaller": lambda: self.set_size(self.size_at - 1),
            "library": lambda: self.choose_view("library"),
            "favourites": lambda: self.choose_view("favourites"),
            "recent": lambda: self.choose_view("recent"),
        })
        self.connect("key-press-event", self._key)
        self.connect("notify::is-active", self._activated)
        monitor = Gio.VolumeMonitor.get()
        self.volume_monitor = monitor   # kept, so its signals keep coming
        for signal in ("mount-added", "mount-removed", "mount-changed"):
            monitor.connect(signal, lambda *_: GLib.timeout_add(600, self._devices_changed))
        monitor.connect("volume-added", lambda *_: self._mount_new())
        self.devices = []
        self.fill_sidebar()
        self.show_all()
        self.rescan(first=True)
        self._mount_new()

    def _mount_new(self):
        """Phones, cameras and cards that are plugged in but not yet open:
        open them, so their photos can be seen (a phone may ask first)."""
        for volume in self.volume_monitor.get_volumes():
            if volume.get_mount() is None and volume.can_mount() and volume.should_automount():
                volume.mount(Gio.MountMountFlags.NONE, Gtk.MountOperation.new(self), None, self._mounted)

    def _mounted(self, volume, result):
        try:
            volume.mount_finish(result)
        except GLib.Error:
            pass   # locked, or the phone said no: it can be plugged in again
        GLib.timeout_add(600, self._devices_changed)

    def _header_button(self, icon, tip, callback):
        button = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
        button.set_tooltip_text(tip)
        button.connect("clicked", lambda *_: callback())
        button.set_no_show_all(True)
        return button

    # -- sidebar ----------------------------------------------------------------

    def fill_sidebar(self):
        self.choosing = True
        for row in self.sidebar.get_children():
            row.destroy()
        rows = [("library", "Library", "camera-photo-symbolic", "Photos"),
                ("favourites", "Favourites", "emblem-favorite-symbolic", "Photos"),
                ("recent", "Recently Added", "document-open-recent-symbolic", "Photos")]
        for n, device in enumerate(self.devices):
            rows.append((f"device:{n}", device.name, "camera-photo-symbolic", "Devices"))
        for key, title, icon, group in rows:
            row = Gtk.ListBoxRow()
            row.key, row.group = key, group
            box = Gtk.Box(spacing=8)
            box.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU), False, False, 0)
            box.pack_start(Gtk.Label(label=title, xalign=0, ellipsize=3), True, True, 0)
            row.add(box)
            self.sidebar.add(row)
            if key == self.view:
                self.sidebar.select_row(row)
        self.sidebar.show_all()
        self.choosing = False

    def _side_header(self, row, before):
        if row.group == "Devices" and (before is None or before.group != "Devices"):
            label = Gtk.Label(label="Devices", xalign=0)
            label.get_style_context().add_class("cove-side-head")
            row.set_header(label)
        else:
            row.set_header(None)

    def _side_selected(self, _box, row):
        if row is None or self.choosing:
            return
        self.choose_view(row.key, from_sidebar=True)

    def choose_view(self, key, from_sidebar=False):
        if self.importing:
            return
        if not from_sidebar:
            for row in self.sidebar.get_children():
                if row.key == key:
                    self.choosing = True
                    self.sidebar.select_row(row)
                    self.choosing = False
        self.view = key
        self.current = None
        if key.startswith("device:"):
            self.device = self.devices[int(key.split(":")[1])]
            self.read_device()
        else:
            self.device = None
            self.show_grid()

    def _devices_changed(self):
        keys = [d.key for d in self.devices]
        self.devices = store.devices()
        if [d.key for d in self.devices] == keys:
            return False
        if self.view.startswith("device:") and not self.importing:
            gone = self.device is None or self.device.key not in [d.key for d in self.devices]
            if gone:
                self.view = "library"
                self.fill_sidebar()
                self.show_grid()
                return False
            self.view = f"device:{[d.key for d in self.devices].index(self.device.key)}"
        self.fill_sidebar()
        return False

    # -- the library ------------------------------------------------------------

    def rescan(self, first=False):
        self.last_scan = time.monotonic()
        if first:
            self.busy_label.set_text("Finding your photos…")
            self.busy_spinner.start()
            self.stack.set_visible_child_name("busy")
            self.devices = store.devices()
            self.fill_sidebar()

        def work():
            photos = store.scan()
            GLib.idle_add(self._scanned, photos, first)
        threading.Thread(target=work, daemon=True).start()

    def _scanned(self, photos, first):
        self.busy_spinner.stop()
        before = [(p.path, p.mtime) for p in self.photos]
        self.photos = photos
        if first or before != [(p.path, p.mtime) for p in photos]:
            if self.device is None and (self.current is None or first):
                self.show_grid(keep=self._photo_in_hand())
        return False

    def _activated(self, *_):
        # Back in front: pick up photos added in Drawer or another app.
        if self.is_active() and time.monotonic() - self.last_scan > 4 and not self.importing:
            self.rescan()

    def chosen_photos(self):
        if self.view == "favourites":
            return [p for p in self.photos if p.path in self.favourite_paths]
        if self.view == "recent":
            return store.recently_added(self.photos)
        return self.photos

    def show_grid(self, keep=None):
        """Lay out the tiles for the chosen view, in months."""
        self.loader.forget_all()
        for child in self.grid_box.get_children():
            child.destroy()
        self.tiles = []
        self.shown = self.chosen_photos()
        self._chrome("grid")
        if not self.shown:
            texts = {"favourites": ("No Favourites", "Open a photo and click the heart to keep it here."),
                     "recent": ("Nothing Added Lately", "Photos added in the last 30 days show here.")}
            title, text = texts.get(self.view, (
                "No Photos", "Put pictures in your Pictures folder, or connect a camera or phone and "
                "import from it."))
            self.empty_title.set_text(title)
            self.empty_text.set_text(text)
            self.stack.set_visible_child_name("empty")
            return
        if self.view == "recent":
            groups = [("Recently Added", "", self.shown)]
        else:
            groups = []
            for photo in self.shown:
                month = photo.month()
                if not groups or groups[-1][0] != month:
                    groups.append((month, "", []))
                groups[-1][2].append(photo)
            groups = [(time.strftime("%B", time.localtime(g[2][0].taken)),
                       time.strftime("%Y", time.localtime(g[2][0].taken)), g[2]) for g in groups]
        for title, year, photos in groups:
            self.grid_box.pack_start(self._heading(title, year, len(photos)), False, False, 0)
            self.grid_box.pack_start(self._flow(photos), False, False, 0)
        self.grid_box.show_all()
        self.stack.set_visible_child_name("grid")
        if keep is not None:
            self._select_tile(keep)

    def _heading(self, title, year, count):
        box = Gtk.Box(spacing=8, margin_start=20, margin_end=20, margin_top=18, margin_bottom=8)
        name = Gtk.Label(label=title, xalign=0)
        name.get_style_context().add_class("cove-month")
        box.pack_start(name, False, False, 0)
        if year:
            when = Gtk.Label(label=year, xalign=0, valign=Gtk.Align.BASELINE)
            when.get_style_context().add_class("cove-month")
            when.set_opacity(0.45)
            box.pack_start(when, False, False, 0)
        count_label = Gtk.Label(label=plural(count, "photo"), valign=Gtk.Align.BASELINE)
        count_label.get_style_context().add_class("cove-month-sub")
        box.pack_end(count_label, False, False, 0)
        return box

    def _flow(self, items, device=False, done=()):
        flow = Gtk.FlowBox(homogeneous=True, column_spacing=3, row_spacing=3, margin_start=20,
                           margin_end=20, valign=Gtk.Align.START, halign=Gtk.Align.START,
                           max_children_per_line=60, activate_on_single_click=False)
        flow.set_selection_mode(Gtk.SelectionMode.MULTIPLE if device else Gtk.SelectionMode.SINGLE)
        size = SIZES[self.size_at]
        for item in items:
            tile = Tile(self, item, size, device=device, dimmed=device and item.key() in done)
            flow.add(tile)
            self.tiles.append(tile)
        flow.connect("child-activated", self._tile_activated)
        flow.connect("selected-children-changed", self._selection_changed)
        return flow

    def _selection_changed(self, flow):
        if self.choosing:
            return
        if flow.get_selection_mode() == Gtk.SelectionMode.SINGLE and flow.get_selected_children():
            self.choosing = True   # one photo chosen across all the months
            for other in self.grid_box.get_children():
                if isinstance(other, Gtk.FlowBox) and other is not flow:
                    other.unselect_all()
            self.choosing = False
        for tile in self.tiles:
            tile.area.queue_draw()
        if self.device is not None:
            self._update_import_buttons()

    def _tile_activated(self, _flow, tile):
        if tile.device:
            return
        self.open_photo(self.shown.index(tile.item))

    def _selected_tile(self):
        for tile in self.tiles:
            if tile.is_selected():
                return tile
        return None

    def _select_tile(self, photo):
        for tile in self.tiles:
            if not tile.device and tile.item.path == photo.path:
                tile.get_parent().select_child(tile)
                tile.grab_focus()
                return

    def set_size(self, at):
        at = max(0, min(len(SIZES) - 1, at))
        if at == self.size_at:
            return
        self.size_at = at
        self.zoom.set_value(at)
        for tile in self.tiles:
            tile.resize(SIZES[at])

    # -- the large view -----------------------------------------------------------

    def open_photo(self, index):
        if not self.shown:
            return
        self.current = max(0, min(len(self.shown) - 1, index))
        photo = self.shown[self.current]
        placeholder = store.thumbnail(photo.path, photo.mtime)   # kept on disk, so quick
        self.stack.set_visible_child_name("viewer")
        self.viewer.show_photo(photo, placeholder)
        self._chrome("viewer")
        self.header.set_title(long_date(photo.taken))
        self.header.set_subtitle(f"{clock(photo.taken)}  ·  {self.current + 1} of {len(self.shown)}")
        self.fav_button.handler_block(self.fav_handler)
        self.fav_button.set_active(photo.path in self.favourite_paths)
        self.fav_button.handler_unblock(self.fav_handler)
        self._fill_info(photo)

    def close_photo(self):
        if self.current is None:
            return
        photo = self.shown[self.current] if self.current < len(self.shown) else None
        self.current = None
        self.stack.set_visible_child_name("grid" if self.shown else "empty")
        self._chrome("grid")
        if photo is not None:
            self._select_tile(photo)

    def _chrome(self, page):
        """The header's buttons and title for the grid, the large view or a device."""
        viewing = page == "viewer"
        device = self.device is not None and not viewing
        self.back.set_visible(viewing)
        self.zoom.set_visible(not viewing)
        for widget in (self.fav_button, self.info_button, self.delete_button):
            widget.set_visible(viewing)
        self.import_all.set_visible(device and not self.importing)
        self.import_some.set_visible(False)
        if not viewing:
            if device:
                self.header.set_title(self.device.name)
            else:
                self.header.set_title({"favourites": "Favourites", "recent": "Recently Added"}.get(self.view, "Library"))
            shown = self.shown if not device else []
            if shown and self.view == "library":
                first, last = shown[-1].taken, shown[0].taken
                span = (long_date(first) if long_date(first) == long_date(last)
                        else f"{time.strftime('%b %-d, %Y', time.localtime(first))} – "
                             f"{time.strftime('%b %-d, %Y', time.localtime(last))}")
                self.header.set_subtitle(span)
            elif shown:
                self.header.set_subtitle(plural(len(shown), "photo"))
            else:
                self.header.set_subtitle("")

    def _fill_info(self, photo):
        old = self.info_popover.get_child()
        if old:
            old.destroy()
        grid = Gtk.Grid(column_spacing=12, row_spacing=6)
        grid.get_style_context().add_class("cove-info")
        width, height = store.picture_size(photo.path)
        rows = (("Name", photo.name), ("Taken", f"{long_date(photo.taken)}, {clock(photo.taken)}"),
                ("Size", f"{width} × {height}" if width else "—"), ("File", human_size(photo.size)),
                ("Folder", os.path.dirname(photo.path).replace(os.path.expanduser("~"), "~", 1)))
        for n, (key, value) in enumerate(rows):
            k = Gtk.Label(label=key, xalign=1)
            k.get_style_context().add_class("cove-info-key")
            v = Gtk.Label(label=value, xalign=0, ellipsize=2, max_width_chars=34)
            v.get_style_context().add_class("cove-info-value")
            grid.attach(k, 0, n, 1, 1)
            grid.attach(v, 1, n, 1, 1)
        grid.show_all()
        self.info_popover.add(grid)

    def show_info(self):
        if self.current is not None:
            self.info_button.set_active(not self.info_button.get_active())

    def set_favourite(self, on):
        if self.current is None:
            return
        path = self.shown[self.current].path
        (self.favourite_paths.add if on else self.favourite_paths.discard)(path)
        store.set_favourite(path, on)
        for tile in self.tiles:
            tile.area.queue_draw()

    def toggle_favourite(self):
        if self.current is not None:
            self.fav_button.set_active(not self.fav_button.get_active())
        else:
            tile = self._selected_tile()
            if tile is not None and not tile.device:
                on = tile.item.path not in self.favourite_paths
                (self.favourite_paths.add if on else self.favourite_paths.discard)(tile.item.path)
                store.set_favourite(tile.item.path, on)
                tile.area.queue_draw()

    def _photo_in_hand(self):
        if self.current is not None:
            return self.shown[self.current]
        tile = self._selected_tile()
        return tile.item if tile is not None and not tile.device else None

    def delete_photo(self):
        photo = self._photo_in_hand()
        if photo is None:
            return
        answer = alert.ask(self, "Move this photo to the Trash?", photo.name,
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Move to Trash", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK, icon="freemac-cove")
        if answer != Gtk.ResponseType.OK:
            return
        try:
            Gio.File.new_for_path(photo.path).trash(None)
        except GLib.Error as error:
            alert.tell(self, "The photo couldn't be moved to the Trash.", error.message, icon="freemac-cove")
            return
        store.forget(photo.path)
        self.favourite_paths.discard(photo.path)
        at = self.shown.index(photo)
        self.photos = [p for p in self.photos if p.path != photo.path]
        viewing = self.current is not None
        self.current = None
        self.show_grid()
        if viewing and self.shown:
            self.open_photo(min(at, len(self.shown) - 1))
        elif self.shown:
            self._select_tile(self.shown[min(at, len(self.shown) - 1)])

    def show_in_folder(self):
        photo = self._photo_in_hand()
        folder = os.path.dirname(photo.path) if photo else store.library_dir()
        try:
            Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(folder).get_uri(), None)
        except GLib.Error:
            pass

    def open_in_frame(self):
        photo = self._photo_in_hand()
        if photo is None:
            return
        try:
            subprocess.Popen(["freemac-frame", photo.path], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass

    # -- cameras and phones -------------------------------------------------------

    def import_from_menu(self):
        self.devices = store.devices()
        self.fill_sidebar()
        if not self.devices:
            alert.tell(self, "No camera or phone is connected.",
                       "Connect one with its cable (on a phone, allow access to photos when it asks), "
                       "or put in its memory card. It shows in the sidebar under Devices.", icon="freemac-cove")
            return
        self.choose_view("device:0")

    def read_device(self):
        device = self.device
        self.busy_label.set_text(f"Looking for photos on {device.name}…")
        self.busy_bar.hide()
        self.busy_spinner.start()
        self.stack.set_visible_child_name("busy")
        self.loader.forget_all()
        for child in self.grid_box.get_children():
            child.destroy()
        self.tiles = []
        self.shown = []
        self._chrome("device")
        self.import_all.set_visible(False)

        def work():
            items = store.device_items(device)
            GLib.idle_add(self._device_read, device, items)
        threading.Thread(target=work, daemon=True).start()

    def _device_read(self, device, items):
        if device is not self.device:
            return False
        self.busy_spinner.stop()
        self.device_items = items
        done = store.already_imported(device)
        fresh = [i for i in items if i.key() not in done]
        if not items:
            self.empty_title.set_text("No Photos")
            self.empty_text.set_text(f"There are no photos on {device.name}.")
            self.stack.set_visible_child_name("empty")
            return False
        bar = Gtk.Box(spacing=8, margin_start=20, margin_end=20, margin_top=18, margin_bottom=8)
        title = Gtk.Label(label="New Items" if fresh else "All Imported", xalign=0)
        title.get_style_context().add_class("cove-month")
        bar.pack_start(title, False, False, 0)
        count = Gtk.Label(label=f"{plural(len(fresh), 'new photo')} of {len(items)}", valign=Gtk.Align.BASELINE)
        count.get_style_context().add_class("cove-month-sub")
        bar.pack_end(count, False, False, 0)
        self.grid_box.pack_start(bar, False, False, 0)
        self.grid_box.pack_start(self._flow(items, device=True, done=done), False, False, 0)
        self.grid_box.show_all()
        self.stack.set_visible_child_name("grid")
        self._chrome("device")
        self.import_all.set_label(f"Import All New Items ({len(fresh)})" if fresh else "Import All New Items")
        self.import_all.set_sensitive(bool(fresh))
        return False

    def _chosen_items(self):
        return [t.item for t in self.tiles if t.device and t.is_selected()]

    def _update_import_buttons(self):
        chosen = self._chosen_items()
        self.import_some.set_visible(bool(chosen) and not self.importing)
        self.import_some.set_label(f"Import {len(chosen)} Selected")

    def start_import(self, items):
        device = self.device
        if device is None or self.importing:
            return
        if items is None:
            done = store.already_imported(device)
            items = [i for i in getattr(self, "device_items", []) if i.key() not in done]
        if not items:
            return
        self.importing = True
        self.import_all.hide()
        self.import_some.hide()
        self.busy_label.set_text(f"Importing {plural(len(items), 'photo')} from {device.name}…")
        self.busy_spinner.start()
        self.busy_bar.set_fraction(0)
        self.busy_bar.show()
        self.stack.set_visible_child_name("busy")

        def progress(done, total):
            GLib.idle_add(self._import_progress, done, total)

        def work():
            made = store.import_items(device, items, progress)
            GLib.idle_add(self._imported, len(items), made)
        threading.Thread(target=work, daemon=True).start()

    def _import_progress(self, done, total):
        self.busy_bar.set_fraction(done / max(1, total))
        self.busy_label.set_text(f"Importing {done} of {total}…")
        return False

    def _imported(self, wanted, made):
        self.importing = False
        self.busy_spinner.stop()
        self.busy_bar.hide()
        if len(made) < wanted:
            alert.tell(self, f"{plural(wanted - len(made), 'photo')} couldn't be imported.",
                       "The device may have been disconnected, or the disk is full.", icon="freemac-cove")
        self.view = "recent"
        self.device = None
        self.fill_sidebar()
        self.photos = store.scan()
        self.last_scan = time.monotonic()
        self.show_grid()
        return False

    # -- keys -------------------------------------------------------------------

    def _key(self, _w, event):
        key = event.keyval
        command = bool(event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK))
        if command:
            actions = {Gdk.KEY_BackSpace: self.delete_photo, Gdk.KEY_i: self.show_info,
                       Gdk.KEY_plus: lambda: self.set_size(self.size_at + 1),
                       Gdk.KEY_equal: lambda: self.set_size(self.size_at + 1),
                       Gdk.KEY_minus: lambda: self.set_size(self.size_at - 1),
                       Gdk.KEY_1: lambda: self.choose_view("library"),
                       Gdk.KEY_2: lambda: self.choose_view("favourites"),
                       Gdk.KEY_3: lambda: self.choose_view("recent"),
                       Gdk.KEY_w: self.close, Gdk.KEY_r: self.show_in_folder}
            if key in actions:
                actions[key]()
                return True
            return False
        if self.current is not None:
            if key in (Gdk.KEY_Right, Gdk.KEY_Down):
                self.open_photo(self.current + 1)
            elif key in (Gdk.KEY_Left, Gdk.KEY_Up):
                self.open_photo(self.current - 1)
            elif key in (Gdk.KEY_Escape, Gdk.KEY_space, Gdk.KEY_Return):
                self.close_photo()
            elif key == Gdk.KEY_period:
                self.toggle_favourite()
            else:
                return False
            return True
        if key == Gdk.KEY_space:
            tile = self._selected_tile()
            if tile is not None and not tile.device:
                self.open_photo(self.shown.index(tile.item))
                return True
        if key == Gdk.KEY_period:
            self.toggle_favourite()
            return True
        return False


def menubar():
    return menus.menubar([
        ("_File", [[("Import…", "win.import", None)],
                   [("Show in Drawer", "win.show-folder", "<Ctrl>r"), ("Open With Frame", "win.open-frame", None)],
                   [("Close Window", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Move to Trash", "win.delete", "<Ctrl>BackSpace")]]),
        ("_Image", [[("Favourite", "win.favourite", "period"), ("Get Info", "win.info", "<Ctrl>i")]]),
        ("_View", [[("Library", "win.library", "<Ctrl>1"), ("Favourites", "win.favourites", "<Ctrl>2"),
                    ("Recently Added", "win.recent", "<Ctrl>3")],
                   [("Bigger Tiles", "win.bigger", "<Ctrl>plus"), ("Smaller Tiles", "win.smaller", "<Ctrl>minus")]]),
    ])


class Cove(Gtk.Application):
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
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.hold()   # stays open with no window, as a Mac app does; Quit ends it
        self.set_menubar(menubar())

    def do_activate(self):
        (self.get_active_window() or Window(self)).present()


def main():
    return Cove().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
