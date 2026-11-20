# SPDX-License-Identifier: GPL-3.0-or-later
"""Marina: every app on one full-screen grid.

Opens over everything (F4, the Marina icon in Pier, or a hot corner), with the
wallpaper softly blurred behind large app icons and their names, a page at a
time. Typing filters the apps; Enter or a click opens one. Esc, a click on
an empty spot, or F4 again closes it. Scrolling, a swipe, the arrow keys or
the dots at the bottom turn the page.

freemac's own apps come first, then everything else from A to Z, the way a
new computer lists the apps it came with before the ones you add.
"""
import os

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, GtkLayerShell, Pango  # noqa: E402

from . import backdrop, style  # noqa: E402

CSS = b"""
.marina label { color: white; text-shadow: 0 1px 3px rgba(0, 0, 0, 0.45); }
.marina-search { background-color: rgba(255, 255, 255, 0.20); border: 1px solid rgba(255, 255, 255, 0.18);
                 border-radius: 9px; color: white; caret-color: white; min-height: 30px; box-shadow: none; }
.marina-search image { color: rgba(255, 255, 255, 0.75); }
.marina-app { background: none; border: none; box-shadow: none; border-radius: 16px; padding: 8px 4px; }
.marina-app:hover, .marina-app:focus { background-color: rgba(255, 255, 255, 0.14); }
.marina-app label { font-size: 13px; }
.marina-dot { min-width: 8px; min-height: 8px; border-radius: 4px; padding: 0; margin: 0 5px;
              background-color: rgba(255, 255, 255, 0.35); border: none; box-shadow: none; }
.marina-dot.current { background-color: white; }
.marina-empty { font-size: 15px; color: rgba(255, 255, 255, 0.85); }
"""

ICON = 96          # icon size on a large screen
NAME_CHARS = 16


def apps():
    """Apps that show in menus: freemac's own first, then A to Z."""
    found = [a for a in Gio.AppInfo.get_all() if a.should_show() and a.get_id()]
    hidden = {"freemac-marina.desktop"}
    found = [a for a in found if a.get_id() not in hidden]

    def key(info):
        own = (info.get_id() or "").startswith("freemac-")
        return (0 if own else 1, (info.get_display_name() or info.get_name() or "").lower())

    return sorted(found, key=key)


def matches(info, words):
    text = " ".join(filter(None, [info.get_display_name(), info.get_name(), info.get_generic_name(),
                                  info.get_description(), " ".join(info.get_keywords() or [])])).lower()
    return all(w in text for w in words)


class Marina(Gtk.Window):
    def __init__(self, app):
        super().__init__(application=app, title="Marina")
        style.make_transparent(self)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "freemac-marina")
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                     GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_exclusive_zone(self, -1)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        self.get_style_context().add_class("marina")

        self.wallpaper, self.soft = None, None
        image = backdrop.read_settings().get("image") or backdrop.DEFAULT_IMAGE
        try:
            self.wallpaper = GdkPixbuf.Pixbuf.new_from_file(os.path.expanduser(image))
        except GLib.Error:
            pass
        self.connect("draw", self._draw_background)

        events = Gtk.EventBox()
        events.set_visible_window(False)
        events.add_events(Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK)
        events.connect("button-release-event", self._empty_click)
        events.connect("scroll-event", self._scroll)
        self.add(events)
        column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        events.add(column)

        self.search = Gtk.SearchEntry(placeholder_text="Search", halign=Gtk.Align.CENTER, margin_top=36)
        self.search.get_style_context().add_class("marina-search")
        self.search.set_size_request(260, -1)
        self.search.connect("search-changed", lambda *_: self.fill())
        self.search.connect("activate", self._open_first)
        column.pack_start(self.search, False, False, 0)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
                               transition_duration=260)
        self.stack.set_vexpand(True)
        self.stack.connect("notify::visible-child", lambda *_: self._mark_dot())
        column.pack_start(self.stack, True, True, 0)
        self.dots = Gtk.Box(spacing=0, halign=Gtk.Align.CENTER, margin_bottom=40, margin_top=12)
        column.pack_start(self.dots, False, False, 0)

        self.swipe = Gtk.GestureSwipe.new(events)
        self.swipe.connect("swipe", self._swiped)
        self.connect("key-press-event", self._key)
        self.all_apps = apps()
        self.shown = []
        self.layout = None
        self.connect("size-allocate", self._resized)

    # ---- layout ------------------------------------------------------------
    def _resized(self, _w, alloc):
        cols = max(4, min(8, (alloc.width - 160) // 150))
        rows = max(2, min(5, (alloc.height - 220) // 150))
        icon = ICON if alloc.height >= 820 else 72
        layout = (cols, rows, icon)
        if layout != self.layout:
            self.layout = layout
            GLib.idle_add(lambda: self.fill() or False)

    def fill(self):
        if not self.layout:
            return
        cols, rows, icon = self.layout
        words = self.search.get_text().lower().split()
        self.shown = [a for a in self.all_apps if matches(a, words)] if words else list(self.all_apps)
        current = self.stack.get_visible_child_name()
        for child in self.stack.get_children():
            self.stack.remove(child)
        for child in self.dots.get_children():
            self.dots.remove(child)
        per_page = cols * rows
        pages = max(1, (len(self.shown) + per_page - 1) // per_page)
        for page in range(pages):
            grid = Gtk.Grid(column_homogeneous=True, row_homogeneous=True, row_spacing=10, column_spacing=18,
                            halign=Gtk.Align.CENTER, valign=Gtk.Align.START, margin_top=48)
            for n, info in enumerate(self.shown[page * per_page:(page + 1) * per_page]):
                grid.attach(self._tile(info, icon), n % cols, n // cols, 1, 1)
            if not self.shown:
                empty = Gtk.Label(label="No apps match.")
                empty.get_style_context().add_class("marina-empty")
                grid.attach(empty, 0, 0, 1, 1)
            self.stack.add_named(grid, str(page))
            if pages > 1:
                dot = Gtk.Button()
                dot.get_style_context().add_class("marina-dot")
                dot.set_can_focus(False)
                dot.set_valign(Gtk.Align.CENTER)
                dot.connect("clicked", lambda _b, p=page: self.stack.set_visible_child_name(str(p)))
                self.dots.pack_start(dot, False, False, 0)
        self.stack.show_all()
        self.dots.show_all()
        if current and self.stack.get_child_by_name(current) and not words:
            self.stack.set_visible_child_name(current)
        else:
            self.stack.set_visible_child_name("0")
        self._mark_dot()

    def _tile(self, info, size):
        button = Gtk.Button()
        button.get_style_context().add_class("marina-app")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        gicon = info.get_icon() or Gio.ThemedIcon.new("application-x-executable")
        image = Gtk.Image.new_from_gicon(gicon, Gtk.IconSize.DIALOG)
        image.set_pixel_size(size)
        box.pack_start(image, False, False, 0)
        name = Gtk.Label(label=info.get_display_name() or info.get_name(), max_width_chars=NAME_CHARS,
                         ellipsize=Pango.EllipsizeMode.END, width_chars=NAME_CHARS - 4)
        box.pack_start(name, False, False, 0)
        button.add(box)
        button.set_tooltip_text(info.get_description() or None)
        button.connect("clicked", lambda *_: self.open(info))
        return button

    def _mark_dot(self):
        current = self.stack.get_visible_child_name() or "0"
        for n, dot in enumerate(self.dots.get_children()):
            context = dot.get_style_context()
            (context.add_class if str(n) == current else context.remove_class)("current")

    # ---- actions -------------------------------------------------------------
    def open(self, info):
        try:
            info.launch([], None)
        except GLib.Error:
            pass
        self.close()

    def _open_first(self, *_):
        if self.shown:
            self.open(self.shown[0])

    def turn(self, by):
        pages = len(self.stack.get_children())
        current = int(self.stack.get_visible_child_name() or 0)
        target = max(0, min(pages - 1, current + by))
        if target != current:
            self.stack.set_visible_child_name(str(target))

    def _scroll(self, _w, event):
        if self.stack.get_transition_running():
            return True
        direction = event.direction
        if direction == Gdk.ScrollDirection.SMOOTH:
            ok, dx, dy = event.get_scroll_deltas()
            delta = dx if abs(dx) > abs(dy) else dy
            if abs(delta) < 0.5:
                return True
            self.turn(1 if delta > 0 else -1)
        elif direction in (Gdk.ScrollDirection.DOWN, Gdk.ScrollDirection.RIGHT):
            self.turn(1)
        elif direction in (Gdk.ScrollDirection.UP, Gdk.ScrollDirection.LEFT):
            self.turn(-1)
        return True

    def _swiped(self, _gesture, vx, _vy):
        if abs(vx) > 300:
            self.swiped = True
            self.turn(1 if vx < 0 else -1)

    swiped = False

    def _empty_click(self, _w, event):
        # A click that no app tile took lands here: close, as on the desktop
        # (but not at the end of a swipe that turned the page).
        if self.swiped:
            self.swiped = False
        elif event.button == 1:
            self.close()
        return False

    def _key(self, _w, event):
        key = event.keyval
        if key == Gdk.KEY_Escape:
            if self.search.get_text():
                self.search.set_text("")
            else:
                self.close()
            return True
        if key in (Gdk.KEY_Page_Down,) or (key == Gdk.KEY_Right and event.state & Gdk.ModifierType.CONTROL_MASK):
            self.turn(1)
            return True
        if key in (Gdk.KEY_Page_Up,) or (key == Gdk.KEY_Left and event.state & Gdk.ModifierType.CONTROL_MASK):
            self.turn(-1)
            return True
        if key == Gdk.KEY_F4:
            self.close()
            return True
        return False

    def _draw_background(self, widget, cr):
        width, height = widget.get_allocated_width(), widget.get_allocated_height()
        if self.wallpaper:
            if self.soft is None or (self.soft.get_width(), self.soft.get_height()) < (width, height):
                self.soft = style.blurred(self.wallpaper, width, height)
            Gdk.cairo_set_source_pixbuf(cr, self.soft, (width - self.soft.get_width()) / 2,
                                        (height - self.soft.get_height()) / 2)
            cr.paint()
            cr.set_source_rgba(0, 0, 0, 0.18)
        else:
            cr.set_source_rgba(0.08, 0.09, 0.16, 0.92)
        cr.paint()
        return False


class MarinaApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.freemac.Marina")

    def do_activate(self):
        windows = self.get_windows()
        if windows:  # F4 or the dock icon again closes it.
            windows[0].close()
            return
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        win = Marina(self)
        win.show_all()
        win.search.grab_focus()


def main():
    MarinaApp().run(None)
