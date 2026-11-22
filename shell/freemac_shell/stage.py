# SPDX-License-Identifier: GPL-3.0-or-later
"""Stage Manager, as a Mac has it: the app you're using stands alone in the
middle of the screen, and the apps you used just before it wait as small
pictures down the left side. Click a picture to bring that app forward; the
one you were using takes its place in the strip.

Turn it on in Quick Settings or in Dials > Dock and Menu Bar (pier.json's
"stage"). The Dock hosts it, since the Dock is always running: when another
app comes forward, the windows of every other app are hidden through Strata
(strata/hide, so they don't shrink into the Dock), after a picture of each
app's front window is taken (strata/snapshot). Clicking a picture, the app's
Dock icon or ⌘Tab brings that app's windows back. Windows you hid or
minimized yourself are left as they are. Turning it off brings every window
it hid back where it was.

Original freemac code.
"""
import json
import os

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import apps, style  # noqa: E402
from .wfipc import is_minimized, snapshot_dir  # noqa: E402

CONFIG = os.path.expanduser("~/.config/freemac/pier.json")
WIDTH = 188            # the strip, from the screen's left edge
CARD_W, CARD_H = 152, 104  # the box each app's picture is fitted into
GAP = 14               # between the pictures
MOST = 5               # apps shown in the strip
BADGE = 34             # the app icon over a picture's lower left corner
# Windows that belong to the desktop, never put on or off the stage.
DESKTOP = {"freemac-pier", "org.freemac.pier", "freemac-backdrop", "freemac-topline",
           "freemac-glyph", "freemac-stage"}

CSS = b"""
.stage-strip { background: none; }
.stage-card { background: none; border: none; box-shadow: none; padding: 0; }
"""


# ---- the setting ---------------------------------------------------------------
def is_on():
    """Whether Stage Manager is on (pier.json)."""
    try:
        with open(CONFIG) as f:
            return bool(json.load(f).get("stage"))
    except (OSError, ValueError, AttributeError):
        return False


def set_on(on):
    """Turn Stage Manager on or off; the Dock watches pier.json and follows."""
    try:
        with open(CONFIG) as f:
            config = json.load(f)
        if not isinstance(config, dict):
            config = {}
    except (OSError, ValueError):
        config = {}
    config["stage"] = bool(on)
    try:
        os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
        tmp = CONFIG + ".tmp"
        with open(tmp, "w") as f:
            json.dump(config, f, indent=2)
        os.replace(tmp, CONFIG)
    except OSError:
        pass


def next_recents(recents, leaving, coming):
    """The strip's order once `coming` takes the stage from `leaving`: the
    app just left first, the rest as they were, never the app on stage."""
    out = [leaving] if leaving and leaving != coming else []
    return out + [a for a in recents if a not in (leaving, coming)]


def card_slots(count, height, card=CARD_H + GAP):
    """How many pictures fit down a strip this tall (at least one)."""
    return max(1, min(count, MOST, (height + GAP) // card))


def _state_file():
    return os.path.join(snapshot_dir(), "stage.json")


def _picture_path(app_id):
    safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in app_id)[:80]
    return os.path.join(snapshot_dir(), f"stage-{safe}.png")


class Card(Gtk.Button):
    """One app in the strip: a picture of its front window, with its icon."""

    def __init__(self, stage, app_id):
        super().__init__()
        self.stage, self.app_id = stage, app_id
        self.set_relief(Gtk.ReliefStyle.NONE)
        self.set_can_focus(False)
        self.get_style_context().add_class("stage-card")
        self.hover = False
        path = _picture_path(app_id)
        try:
            self.picture = GdkPixbuf.Pixbuf.new_from_file(path) if os.path.exists(path) else None
        except GLib.Error:
            self.picture = None
        self.icon = apps.icon_for(app_id)
        area = Gtk.DrawingArea()
        area.set_size_request(CARD_W + 16, CARD_H + 12)
        area.connect("draw", self._draw)
        self.area = area
        self.add(area)
        name = apps.display_name(app_id)
        self.set_tooltip_text(name)
        self.get_accessible().set_name(name)
        self.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        self.connect("enter-notify-event", lambda *_: self._hovered(True))
        self.connect("leave-notify-event", lambda *_: self._hovered(False))
        self.connect("clicked", lambda *_: stage.bring(app_id))

    def _hovered(self, on):
        self.hover = on
        self.area.queue_draw()
        return False

    def _draw(self, widget, cr):
        alloc = widget.get_allocation()
        grow = 1.08 if self.hover else 1.0
        box_w, box_h = CARD_W * grow, CARD_H * grow
        cx, cy = alloc.width / 2, (alloc.height - 6) / 2
        if self.picture is not None:
            width, height = self.picture.get_width(), self.picture.get_height()
            fit = min(box_w / width, box_h / height)
            shown = self.picture.scale_simple(max(1, int(width * fit)), max(1, int(height * fit)),
                                              GdkPixbuf.InterpType.BILINEAR)
            # The picture carries the window's own shadow, so none is added.
            Gdk.cairo_set_source_pixbuf(cr, shown, cx - shown.get_width() / 2, cy - shown.get_height() / 2)
            cr.paint()
            bottom = cy + shown.get_height() / 2
            left = cx - shown.get_width() / 2
        else:
            # No picture yet: a plain card the shape of a window.
            w, h, r = box_w * 0.9, box_h * 0.8, 8
            x, y = cx - w / 2, cy - h / 2
            cr.new_sub_path()
            for ax, ay, a0 in ((x + w - r, y + r, -1.5708), (x + w - r, y + h - r, 0),
                               (x + r, y + h - r, 1.5708), (x + r, y + r, 3.1416)):
                cr.arc(ax, ay, r, a0, a0 + 1.5708)
            cr.close_path()
            cr.set_source_rgba(1, 1, 1, 0.55)
            cr.fill_preserve()
            cr.set_source_rgba(0, 0, 0, 0.18)
            cr.set_line_width(1)
            cr.stroke()
            bottom, left = y + h, x
        if self.icon is not None:
            theme = Gtk.IconTheme.get_default()
            info = theme.lookup_by_gicon_for_scale(self.icon, BADGE, widget.get_scale_factor(),
                                                   Gtk.IconLookupFlags.FORCE_SIZE)
            pixbuf = None
            if info is not None:
                try:
                    pixbuf = info.load_icon()
                except GLib.Error:
                    pixbuf = None
            if pixbuf is not None:
                cr.save()
                cr.translate(max(0, left - BADGE * 0.3), min(alloc.height - BADGE, bottom - BADGE * 0.7))
                scale = BADGE / max(pixbuf.get_width(), 1)
                cr.scale(scale, scale)
                Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
                cr.paint()
                cr.restore()
        return False


class Strip(Gtk.Window):
    """The column of recent apps down the left side of the screen."""

    def __init__(self, stage):
        super().__init__(title="Stage Manager")
        self.stage = stage
        style.make_transparent(self)
        GtkLayerShell.init_for_window(self)
        # Under the windows, as on a Mac: a window moved or zoomed over the
        # strip covers it, and the Dock keeps its place in the middle.
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.BOTTOM)
        GtkLayerShell.set_namespace(self, "freemac-stage")
        for edge in (GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_exclusive_zone(self, 0)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)
        self.set_size_request(WIDTH, -1)
        self.get_style_context().add_class("stage-strip")
        self.column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=GAP,
                              halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        self.add(self.column)
        self.shown = None
        self.connect("draw", self._draw)
        self.wanted, self.height = [], 0
        self.connect_after("size-allocate", self._allocated)
        self.connect("map-event", lambda *_: self._set_input())

    def _allocated(self, _widget, alloc):
        if alloc.height != self.height:
            # Now we know how many pictures fit.
            self.height, self.shown = alloc.height, None
            GLib.idle_add(lambda: self.show_apps(self.wanted) or False)
        GLib.idle_add(self._set_input)

    @staticmethod
    def _draw(widget, cr):
        cr.set_operator(0)   # clear: only the cards are drawn
        cr.paint()
        cr.set_operator(2)
        return False

    def show_apps(self, app_ids):
        self.wanted = list(app_ids)
        height = self.get_allocated_height()
        app_ids = app_ids[:card_slots(len(app_ids), height if height > 200 else 640)]
        key = [(a, self._mtime(a)) for a in app_ids]
        if key == self.shown:
            return
        self.shown = key
        for child in self.column.get_children():
            child.destroy()
        for app_id in app_ids:
            self.column.pack_start(Card(self.stage, app_id), False, False, 0)
        self.column.show_all()
        GLib.idle_add(self._set_input)

    @staticmethod
    def _mtime(app_id):
        try:
            return os.path.getmtime(_picture_path(app_id))
        except OSError:
            return 0

    def _set_input(self):
        """Only the pictures take clicks; the rest of the strip lets them
        through to the desktop."""
        window = self.get_window()
        if window is None:
            return False
        import cairo
        region = cairo.Region()
        for card in self.column.get_children():
            alloc = card.get_allocation()
            coords = card.translate_coordinates(self, 0, 0)
            if coords:
                region.union(cairo.RectangleInt(coords[0], coords[1], alloc.width, alloc.height))
        window.input_shape_combine_region(region, 0, 0)
        return False


class StageManager:
    """Keeps one app on the stage and the others in the strip."""

    def __init__(self, wf):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.wf = wf
        self.on = False
        self.current = None      # the app on the stage
        self.recents = []        # apps in the strip, newest first
        self.hid = {}            # app id: ids of the windows Stage Manager hid
        self.strip = None
        self._pending = None
        self._pictures, self._picture_source = {}, None   # app id: window still to draw
        self._load_state()

    # -- remembering what was hidden, across a restart of the Dock --
    def _load_state(self):
        try:
            with open(_state_file()) as f:
                data = json.load(f)
        except (OSError, ValueError):
            return
        if isinstance(data, dict):
            self.hid = {a: [i for i in ids if isinstance(i, int)]
                        for a, ids in (data.get("hid") or {}).items() if isinstance(ids, list)}
            self.recents = [a for a in data.get("recents") or [] if isinstance(a, str)]
            self.current = data.get("current") if isinstance(data.get("current"), str) else None

    def _save_state(self):
        try:
            with open(_state_file(), "w") as f:
                json.dump({"hid": self.hid, "recents": self.recents, "current": self.current}, f)
        except OSError:
            pass

    # -- on and off --
    def set_enabled(self, on):
        on = bool(on) and self.wf is not None
        if on == self.on:
            return
        self.on = on
        if on:
            if self.strip is None:
                self.strip = Strip(self)
            self.strip.show_all()
            front = self.wf.focused()
            app = self._app(front) if front else None
            if app is None:
                views = self._views()
                shown = [v for v in views if not is_minimized(v) and self._app(v)]
                if shown:
                    app = self._app(max(shown, key=lambda v: v.get("last-focus-timestamp", 0)))
            if app:
                self.current = None
                self._stage(app)
            self.refresh()
        else:
            self._bring_all_back()
            if self.strip is not None:
                self.strip.hide()

    def _bring_all_back(self):
        live = {v["id"]: v for v in self._views()}
        # The least recent first, so the newest end up on top.
        order = list(reversed(self.recents)) + [a for a in self.hid if a not in self.recents]
        for app in order:
            for view_id in self.hid.get(app, []):
                if view_id in live and is_minimized(live[view_id]):
                    self._unminimize(view_id)
        self.hid, self.recents = {}, []
        front = [v for v in live.values() if self._app(v) == self.current]
        if front:
            self._focus(max(front, key=lambda v: v.get("last-focus-timestamp", 0))["id"])
        self._save_state()

    # -- following the focus --
    def event(self, event):
        if not self.on or event.get("event") not in ("view-focused", "view-mapped", "view-unmapped"):
            return
        # Several events come at once as a window opens or the focus moves:
        # look once they have settled.
        if self._pending is None:
            self._pending = GLib.timeout_add(80, self._settle)

    def _settle(self):
        self._pending = None
        if not self.on:
            return False
        front = self.wf.focused()
        app = self._app(front) if front else None
        if app and app != self.current:
            self._stage(app)
        self.refresh()
        return False

    def _stage(self, app):
        """Put `app` on the stage: its windows come back, the others go to
        the strip."""
        views = self._views()
        leaving = self.current
        self.current = app
        self.recents = next_recents(self.recents, leaving, app)
        # The app coming forward gets all of its windows back.
        ours = set(self.hid.pop(app, []))
        self._pictures.pop(app, None)
        for view in views:
            if view["id"] in ours and is_minimized(view):
                self._unminimize(view["id"])
        # Every other app's windows go, after a picture of its front one.
        by_app = {}
        for view in views:
            other = self._app(view)
            if other and other != app and not is_minimized(view):
                by_app.setdefault(other, []).append(view)
        for other, windows in by_app.items():
            front = max(windows, key=lambda v: v.get("last-focus-timestamp", 0))
            for view in windows:
                self.wf.hide(view["id"])
            # Its picture is taken a moment later: Strata can draw a hidden
            # window, and the switch itself shouldn't wait for it.
            self._pictures[other] = front["id"]
            self.hid.setdefault(other, [])
            self.hid[other] += [v["id"] for v in windows if v["id"] not in self.hid[other]]
            if other not in self.recents:
                self.recents.append(other)
        self._clear_strip(app, views)
        self._save_state()
        if self._pictures and self._picture_source is None:
            self._picture_source = GLib.timeout_add(30, self._take_picture)

    def _take_picture(self):
        """Draw the next app's picture for the strip, one per turn of the loop."""
        if not self._pictures or not self.on:
            self._picture_source = None
            return False
        app, view_id = self._pictures.popitem()
        self.wf.snapshot(view_id, _picture_path(app), size=2 * CARD_W)
        self.refresh()
        if not self._pictures:
            self._picture_source = None
            return False
        return True

    def _clear_strip(self, app, views):
        """Move the stage app's windows off the strip if they sit over it and
        there is room beside it (a zoomed window stays as it is)."""
        area = self._work_area()
        if area is None:
            return
        ax, _ay, aw, _ah = area
        clear = ax + WIDTH
        for view in views:
            if self._app(view) != app or (view.get("tiled-edges") or 0) or view.get("fullscreen"):
                continue
            g = view.get("geometry") or {}
            x, width = g.get("x", clear), g.get("width", 0)
            if x < clear and width and clear + width <= ax + aw:
                new_x = clear
                self.wf.move_to(view["id"], new_x, g.get("y", 0), width, g.get("height", 0))

    def bring(self, app):
        """A picture in the strip was clicked: that app comes forward."""
        if not self.wf:
            return
        ids = self.hid.get(app, [])
        live = {v["id"]: v for v in self._views()}
        mine = [live[i] for i in ids if i in live]
        if not mine:
            mine = [v for v in live.values() if self._app(v) == app]
        if not mine:
            self.recents = [a for a in self.recents if a != app]
            self.refresh()
            return
        for view in sorted(mine, key=lambda v: v.get("last-focus-timestamp", 0)):
            if is_minimized(view):
                self._unminimize(view["id"])
        self._focus(max(mine, key=lambda v: v.get("last-focus-timestamp", 0))["id"])
        # The focus event puts it on the stage; don't wait for it.
        self._stage(app)
        self.refresh()

    # -- the strip --
    def refresh(self):
        if not self.on or self.strip is None:
            return
        views = self._views()
        live = {v["id"] for v in views}
        apps_open = {self._app(v) for v in views}
        # Forget windows that have closed, and apps with none left.
        self.hid = {a: [i for i in ids if i in live] for a, ids in self.hid.items()}
        self.hid = {a: ids for a, ids in self.hid.items() if ids}
        self.recents = [a for a in self.recents if a in self.hid and a in apps_open and a != self.current]
        self.strip.show_apps(self.recents)

    # -- Wayfire --
    def _views(self):
        return [v for v in (self.wf.views() if self.wf else []) if self._app(v)]

    @staticmethod
    def _app(view):
        app = (view or {}).get("app-id") or ""
        return app if app and app.lower() not in DESKTOP else None

    def _work_area(self):
        for output in self.wf.outputs() if self.wf else []:
            area = output.get("workarea") if isinstance(output, dict) else None
            if isinstance(area, dict):
                return (area.get("x", 0), area.get("y", 0), area.get("width", 0), area.get("height", 0))
        return None

    def _unminimize(self, view_id):
        try:
            self.wf.set_minimized(view_id, False)
        except (ConnectionError, OSError, ValueError):
            pass

    def _focus(self, view_id):
        try:
            self.wf.focus(view_id)
        except (ConnectionError, OSError, ValueError):
            pass
