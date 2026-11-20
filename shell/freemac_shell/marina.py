# SPDX-License-Identifier: GPL-3.0-or-later
"""Marina: every app on one full-screen grid.

Opens over everything (F4, the Marina icon in Pier, or a hot corner), with the
wallpaper softly blurred behind large app icons and their names, a page at a
time. Typing filters the apps; Enter or a click opens one. Esc, a click on
an empty spot, or F4 again closes it. Scrolling, a swipe, the arrow keys or
the dots at the bottom turn the page.

freemac's own apps come first, then everything else from A to Z, the way a
new computer lists the apps it came with before the ones you add.

Drag an app to move it; drop it on another app to put both in a folder, or on
a folder to add it. A click opens a folder; its name can be changed there, and
dragging an app out of the open folder takes it out again. Hold a dragged app
at the left or right edge to move it to another page. The arrangement is kept
in ~/.config/freemac/marina.json; apps installed later join at the end.
"""
import json
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
.marina-target { background-color: rgba(255, 255, 255, 0.24); }
.marina-folder-icon { background-color: rgba(255, 255, 255, 0.24); border-radius: 22%; }
.marina-folder-panel { background-color: rgba(236, 238, 246, 0.26); border-radius: 30px; padding: 28px 34px; }
.marina-folder-name { background: none; border: none; box-shadow: none; color: white; caret-color: white;
                      font-size: 26px; font-weight: 600; text-shadow: 0 1px 3px rgba(0, 0, 0, 0.35); }
.marina-folder-name:focus { background-color: rgba(255, 255, 255, 0.14); border-radius: 10px; }
"""

LAYOUT = os.path.expanduser("~/.config/freemac/marina.json")
DRAG_TARGET = "application/x-freemac-marina-item"

# A new folder takes its name from what the two apps have in common.
FOLDER_NAMES = (("Game", "Games"), ("Office", "Productivity"), ("Graphics", "Creativity"),
                ("AudioVideo", "Entertainment"), ("Development", "Developer"), ("Network", "Internet"),
                ("Education", "Education"), ("Settings", "System"), ("System", "System"),
                ("Utility", "Utilities"))


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


def folder_name(apps_in):
    each = [set(filter(None, (info.get_categories() or "").split(";"))) for info in apps_in]
    shared = set.intersection(*each) if each else set()
    # What they all share; failing that, what the first one is.
    for cats in (shared, each[0] if each else set()):
        for cat, name in FOLDER_NAMES:
            if cat in cats:
                return name
    return "Folder"


def load_layout(all_apps):
    """The saved arrangement as a list of entries: {"app": info} or
    {"folder": name, "apps": [info, ...]}. Apps that are gone are left out;
    apps not placed yet come at the end, in the usual order."""
    by_id = {a.get_id(): a for a in all_apps}
    try:
        with open(LAYOUT) as f:
            saved = json.load(f).get("items", [])
    except (OSError, ValueError, AttributeError):
        saved = []
    entries, placed = [], set()
    for item in saved if isinstance(saved, list) else []:
        if isinstance(item, str) and item in by_id and item not in placed:
            entries.append({"app": by_id[item]})
            placed.add(item)
        elif isinstance(item, dict) and isinstance(item.get("apps"), list):
            inside = [by_id[i] for i in item["apps"] if i in by_id and i not in placed]
            placed.update(a.get_id() for a in inside)
            if len(inside) > 1:
                entries.append({"folder": str(item.get("name") or folder_name(inside)), "apps": inside})
            elif inside:
                entries.append({"app": inside[0]})
    entries += [{"app": a} for a in all_apps if a.get_id() not in placed]
    return entries


def save_layout(entries):
    items = []
    for entry in entries:
        if "app" in entry:
            items.append(entry["app"].get_id())
        else:
            items.append({"name": entry["folder"], "apps": [a.get_id() for a in entry["apps"]]})
    os.makedirs(os.path.dirname(LAYOUT), exist_ok=True)
    tmp = LAYOUT + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"items": items}, f, indent=1)
    os.replace(tmp, LAYOUT)


def gicon_of(info):
    return info.get_icon() or Gio.ThemedIcon.new("application-x-executable")


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

        self.overlay = Gtk.Overlay()
        self.add(self.overlay)
        events = Gtk.EventBox()
        events.set_visible_window(False)
        events.add_events(Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK)
        events.connect("button-release-event", self._empty_click)
        events.connect("scroll-event", self._scroll)
        self._drop_target(events, None)
        events.connect("drag-motion", self._edge_motion)
        events.connect("drag-leave", lambda *_: self._stop_edge())
        self.overlay.add(events)
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
        self.entries = load_layout(self.all_apps)
        self.shown = []
        self.layout = None
        self.tokens = {}         # drag token -> (entry, folder entry or None)
        self.next_token = 0
        self.open_folder = None  # the folder entry shown, and its panel
        self.panel = None
        self.edge_timer = None
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
        self.tokens = {t: v for t, v in self.tokens.items() if v[1] is not None and v[1] is self.open_folder}
        if words:  # a search lists matching apps, from folders too
            self.shown = [a for a in self.all_apps if matches(a, words)]
            items = [{"app": a} for a in self.shown]
        else:
            self.shown = [a for e in self.entries for a in ([e["app"]] if "app" in e else e["apps"])]
            items = self.entries
        current = self.stack.get_visible_child_name()
        for child in self.stack.get_children():
            self.stack.remove(child)
        for child in self.dots.get_children():
            self.dots.remove(child)
        per_page = cols * rows
        pages = max(1, (len(items) + per_page - 1) // per_page)
        for page in range(pages):
            grid = Gtk.Grid(column_homogeneous=True, row_homogeneous=True, row_spacing=10, column_spacing=18,
                            halign=Gtk.Align.CENTER, valign=Gtk.Align.START, margin_top=48)
            for n, entry in enumerate(items[page * per_page:(page + 1) * per_page]):
                tile = self._tile(entry, icon, None if words else entry, None)
                grid.attach(tile, n % cols, n // cols, 1, 1)
            if not items:
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

    def _tile(self, entry, size, movable, folder):
        """An app or a folder: its picture and name. movable is the entry to
        drag (None while searching); folder is the open folder it sits in."""
        button = Gtk.Button()
        button.get_style_context().add_class("marina-app")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        if "app" in entry:
            info = entry["app"]
            image = Gtk.Image.new_from_gicon(gicon_of(info), Gtk.IconSize.DIALOG)
            image.set_pixel_size(size)
            title = info.get_display_name() or info.get_name()
            button.connect("clicked", lambda *_: self.open(info))
        else:
            image = self._folder_icon(entry, size)
            title = entry["folder"]
            button.connect("clicked", lambda *_: self._tile_took_click() or self.show_folder(entry))
        image.set_halign(Gtk.Align.CENTER)
        box.pack_start(image, False, False, 0)
        name = Gtk.Label(label=title, max_width_chars=NAME_CHARS,
                         ellipsize=Pango.EllipsizeMode.END, width_chars=NAME_CHARS - 4)
        box.pack_start(name, False, False, 0)
        button.add(box)
        if movable is not None:
            self.next_token += 1
            token = str(self.next_token)
            self.tokens[token] = (movable, folder)
            button.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, [], Gdk.DragAction.MOVE)
            button.drag_source_add_text_targets()
            if "app" in entry:
                button.drag_source_set_icon_gicon(gicon_of(entry["app"]))
            button.connect("drag-data-get", lambda _w, _c, data, _i, _t, tok=token: data.set_text(tok, -1))
            self._drop_target(button, token)
        return button

    def _folder_icon(self, entry, size):
        """A rounded square showing the first nine apps inside, small."""
        frame = Gtk.Box()
        frame.get_style_context().add_class("marina-folder-icon")
        frame.set_size_request(size, size)
        small = max(12, int(size * 0.26))
        grid = Gtk.Grid(row_spacing=max(2, size // 20), column_spacing=max(2, size // 20),
                        halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER, hexpand=True)
        for n, info in enumerate(entry["apps"][:9]):
            image = Gtk.Image.new_from_gicon(gicon_of(info), Gtk.IconSize.DIALOG)
            image.set_pixel_size(small)
            grid.attach(image, n % 3, n // 3, 1, 1)
        frame.pack_start(grid, True, True, 0)
        return frame

    # ---- rearranging -----------------------------------------------------------
    def _drop_target(self, widget, token):
        # Tiles say themselves where a drop would go; the background takes any.
        flags = Gtk.DestDefaults.DROP if token is not None else Gtk.DestDefaults.DROP | Gtk.DestDefaults.MOTION
        widget.drag_dest_set(flags, [], Gdk.DragAction.MOVE)
        widget.drag_dest_add_text_targets()
        if token is not None:
            widget.connect("drag-motion", self._tile_motion)
            widget.connect("drag-leave", lambda w, *_: w.get_style_context().remove_class("marina-target"))
        widget.connect("drag-data-received", self._dropped, token)

    @staticmethod
    def _where(widget, x):
        """Dropped on the middle of a tile: into it; else before or after."""
        width = widget.get_allocated_width()
        if width * 0.25 <= x <= width * 0.75:
            return "into"
        return "before" if x < width / 2 else "after"

    def _tile_motion(self, widget, context, x, y, time):
        into = self._where(widget, x) == "into"
        (widget.get_style_context().add_class if into else widget.get_style_context().remove_class)("marina-target")
        Gdk.drag_status(context, Gdk.DragAction.MOVE, time)
        return True

    def _dropped(self, widget, context, x, y, data, _info, time, target_token):
        source = self.tokens.get(data.get_text() or "")
        widget.get_style_context().remove_class("marina-target")
        if not source or (target_token is not None and target_token == data.get_text()):
            Gtk.drag_finish(context, False, False, time)
            return
        target = self.tokens.get(target_token) if target_token is not None else None
        self.move(source, target, self._where(widget, x) if target else "end")
        Gtk.drag_finish(context, True, False, time)

    def _take(self, entry, folder):
        """Remove an entry from where it is; returns it."""
        if folder is None:
            self.entries = [e for e in self.entries if e is not entry]
        else:
            folder["apps"] = [a for a in folder["apps"] if a is not entry["app"]]
        return entry

    def _tidy(self):
        """A folder left with one app becomes that app; an empty one goes."""
        tidy = []
        for e in self.entries:
            if "folder" in e and len(e["apps"]) < 2:
                tidy += [{"app": a} for a in e["apps"]]
            else:
                tidy.append(e)
        self.entries = tidy

    def move(self, source, target, where):
        entry, from_folder = source
        to_entry, to_folder = target if target else (None, None)
        if to_folder is not None and from_folder is to_folder:
            # Rearranging inside the open folder.
            apps_in = [a for a in to_folder["apps"] if a is not entry["app"]]
            index = next((i for i, a in enumerate(apps_in) if a is to_entry["app"]), len(apps_in))
            apps_in.insert(index + (where == "after"), entry["app"])
            to_folder["apps"] = apps_in
        else:
            if to_folder is not None:  # dropped on an app in another folder: next to that folder
                to_entry, where = to_folder, "after"
            if from_folder is not None:
                entry = {"app": entry["app"]}  # out of its folder, as an app of its own
            self._take(source[0], from_folder)
            if to_entry is None:
                self.entries.append(entry)
            elif where == "into" and "app" in entry:
                if "folder" in to_entry:
                    to_entry["apps"].append(entry["app"])
                else:
                    index = self.entries.index(to_entry)
                    pair = [to_entry["app"], entry["app"]]
                    self.entries[index] = {"folder": folder_name(pair), "apps": pair}
            else:
                index = self.entries.index(to_entry) if to_entry in self.entries else len(self.entries)
                self.entries.insert(index + (where == "after"), entry)
        self._tidy()
        try:
            save_layout(self.entries)
        except OSError:
            pass
        reopen = None
        if self.open_folder is not None and from_folder is self.open_folder and to_folder is self.open_folder:
            reopen = self.open_folder  # still rearranging inside it
        self._close_panel()
        self.fill()
        if reopen is not None and any(e is reopen for e in self.entries):
            self.show_folder(reopen)

    def _edge_motion(self, widget, context, x, y, time):
        """Holding a dragged app at the left or right edge turns the page."""
        width = widget.get_allocated_width()
        by = -1 if x < 70 else (1 if x > width - 70 else 0)
        if by and self.edge_timer is None:
            self.edge_timer = GLib.timeout_add(550, self._edge_turn, by)
        elif not by:
            self._stop_edge()
        Gdk.drag_status(context, Gdk.DragAction.MOVE, time)
        return True

    def _edge_turn(self, by):
        self.edge_timer = None
        self.turn(by)
        return False

    def _stop_edge(self):
        if self.edge_timer is not None:
            GLib.source_remove(self.edge_timer)
            self.edge_timer = None

    # ---- folders -----------------------------------------------------------
    def show_folder(self, folder):
        self._close_panel()
        self.open_folder = folder
        # Clicking or dropping outside the panel closes it (or takes the
        # dragged app out of the folder).
        backdrop_box = Gtk.EventBox()
        backdrop_box.set_visible_window(False)
        backdrop_box.connect("button-release-event", lambda *_: self.hide_folder() or True)
        self._drop_target(backdrop_box, None)
        backdrop_box.set_app_paintable(True)
        backdrop_box.connect("draw", self._dim)
        # The name above, then the apps on a frosted panel.
        column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18,
                         halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        name = Gtk.Entry(text=folder["folder"], xalign=0.5, has_frame=False, width_chars=16)
        name.get_style_context().add_class("marina-folder-name")
        name.connect("changed", self._renamed)
        name.connect("activate", lambda *_: self.grab_focus_none())
        column.pack_start(name, False, False, 0)
        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        panel.get_style_context().add_class("marina-folder-panel")
        size = (self.layout[2] if self.layout else ICON)
        cols = min(4, len(folder["apps"]))
        grid = Gtk.Grid(column_homogeneous=True, row_spacing=10, column_spacing=18, halign=Gtk.Align.CENTER)
        for n, info in enumerate(folder["apps"]):
            grid.attach(self._tile({"app": info}, size, {"app": info}, folder), n % cols, n // cols, 1, 1)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER,
                                      vscrollbar_policy=Gtk.PolicyType.AUTOMATIC, propagate_natural_height=True,
                                      propagate_natural_width=True)
        scroller.set_max_content_height(int(self.get_allocated_height() * 0.6) or 500)
        scroller.add(grid)
        scroller.set_size_request(int(size * 5.2), -1)  # a short folder still looks like a panel
        panel.pack_start(scroller, True, True, 0)
        column.pack_start(panel, False, False, 0)
        stop = Gtk.EventBox()  # clicks on the name or the panel don't close it
        stop.set_halign(Gtk.Align.CENTER)
        stop.set_valign(Gtk.Align.CENTER)
        stop.connect("button-release-event", lambda *_: True)
        stop.add(column)
        layer = Gtk.Overlay()
        layer.add(backdrop_box)
        layer.add_overlay(stop)
        self.panel = layer
        self.overlay.add_overlay(layer)
        layer.show_all()

    @staticmethod
    def _dim(_widget, cr):
        cr.set_source_rgba(0, 0, 0, 0.32)
        cr.paint()
        return False

    def grab_focus_none(self):
        self.set_focus(None)

    def _renamed(self, entry):
        if self.open_folder is not None:
            self.open_folder["folder"] = entry.get_text().strip() or "Folder"
            try:
                save_layout(self.entries)
            except OSError:
                pass

    def _close_panel(self):
        if self.panel is not None:
            self.panel.destroy()
            self.panel = None
        self.open_folder = None

    def hide_folder(self):
        if self.panel is not None:
            self._close_panel()
            self.fill()  # the folder's name may have changed
            self.search.grab_focus()

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

    tile_clicked = False

    def _tile_took_click(self):
        # The release that clicked a tile still reaches the background after.
        self.tile_clicked = True

    def _empty_click(self, _w, event):
        # A click that no app tile took lands here: close, as on the desktop
        # (but not at the end of a swipe that turned the page).
        if self.tile_clicked:
            self.tile_clicked = False
        elif self.swiped:
            self.swiped = False
        elif event.button == 1:
            self.close()
        return False

    def _key(self, _w, event):
        key = event.keyval
        if key == Gdk.KEY_Escape:
            if self.panel is not None:
                self.hide_folder()
            elif self.search.get_text():
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
