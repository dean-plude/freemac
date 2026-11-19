# SPDX-License-Identifier: GPL-3.0-or-later
"""Pier: freemac's dock, with magnification as the pointer passes over it."""
import json
import math
import os

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import apps, style  # noqa: E402
from .wfipc import Wayfire  # noqa: E402

BASE = 48          # icon size at rest
PEAK = 80          # icon size right under the pointer
REACH = 150        # pixels over which magnification fades out
MARGIN = 8
CONFIG = os.path.expanduser("~/.config/freemac/pier.json")
DEFAULT_PINNED = ["freemac-drawer.desktop", "freemac-seek.desktop", "org.gnome.Epiphany.desktop", "org.codeberg.dnkl.foot.desktop",
                  "freemac-dials.desktop", "freemac-welcome.desktop"]


def load_config():
    """Pier settings, written by Dials: pinned apps, icon size, magnification."""
    config = {"pinned": DEFAULT_PINNED, "size": BASE, "magnify": True, "peak": PEAK}
    try:
        with open(CONFIG) as f:
            config.update(json.load(f))
    except (OSError, ValueError):
        pass
    config["size"] = max(32, min(80, int(config["size"])))
    config["peak"] = max(config["size"], min(128, int(config["peak"])))
    return config


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
        self.connect("clicked", self._clicked)

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

    def _clicked(self, _button):
        if self.views:
            latest = max(self.views, key=lambda v: v.get("last-focus-timestamp", 0))
            if latest.get("minimized"):
                self.pier.wf.set_minimized(latest["id"], False)
            self.pier.wf.focus(latest["id"])
        elif self.info:
            self.info.launch([], None)


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
        holder = Gtk.Box()
        holder.set_valign(Gtk.Align.END)
        holder.pack_start(self.shelf, True, False, 0)
        outer.add(holder)
        outer.add_events(1 << 2 | 1 << 13)  # pointer motion, leave
        outer.connect("motion-notify-event", self._motion)
        outer.connect("leave-notify-event", lambda *_: self._magnify(None))
        self.add(outer)

        self.pinned = []
        self.extra = {}
        self.running_sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        self.running_sep.get_style_context().add_class("pier-sep")
        self.shelf.pack_start(self.running_sep, False, False, 0)
        self.config = None
        self.load()
        self.monitor = Gio.File.new_for_path(CONFIG).monitor_file(Gio.FileMonitorFlags.NONE, None)
        self.monitor.connect("changed", lambda *_: GLib.timeout_add(200, self._reload))

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
        self.config = config
        for item in self.items():
            item.image.set_pixel_size(self.base)

    def _reload(self):
        self.load()
        self.refresh()
        return False

    def items(self):
        return self.pinned + list(self.extra.values())

    def refresh(self):
        views = self.wf.views() if self.wf else []
        claimed = set()
        for item in self.pinned:
            mine = [v for v in views if item.matches(v)]
            claimed.update(v["id"] for v in mine)
            item.set_views(mine)
        unpinned = {}
        for view in views:
            if view["id"] in claimed:
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
