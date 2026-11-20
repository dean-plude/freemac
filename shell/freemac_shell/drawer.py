# SPDX-License-Identifier: GPL-3.0-or-later
"""Drawer: freemac's file manager.

Icon, list and column views over local folders, tabs, a sidebar of
favourite folders you can change, a preview of the selected file on Space
(Glance), and the everyday file operations (open, new folder, rename, move
to trash).
"""
import json
import os
import threading
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango  # noqa: E402

from . import drawer_archive, drawer_info, macapps, menus  # noqa: E402
from .drawer_glance import Glance  # noqa: E402

CONFIG = os.path.join(GLib.get_user_config_dir(), "freemac", "drawer.json")
URI_TARGETS = [Gtk.TargetEntry.new("text/uri-list", 0, 0)]

ATTRS = ",".join([
    "standard::name", "standard::display-name", "standard::type", "standard::icon",
    "standard::size", "standard::is-hidden", "standard::content-type", "time::modified",
])
# ListStore columns.
C_ICON, C_NAME, C_PATH, C_IS_DIR, C_SIZE, C_MODIFIED, C_KIND, C_SORT, C_SMALL = range(9)
VIEWS = (("icons", "view-grid-symbolic", "Icons"),
         ("list", "view-list-symbolic", "List"),
         ("columns", "view-dual-symbolic", "Columns"))
CSS = b"""
box.drawer-sidebar { background-color: rgba(120, 120, 150, 0.08); }
list.drawer-sidebar { background-color: transparent; }
.drawer-sidebar row { padding: 4px 8px; border-radius: 6px; margin: 0 8px; background-color: transparent; }
.drawer-sidebar row image { color: #2f7bf5; }
.drawer-sidebar row:hover { background-color: rgba(120, 120, 150, 0.10); }
.drawer-sidebar row:selected { background-color: rgba(120, 120, 150, 0.24); color: inherit; }
.drawer-sidebar row:selected label { color: inherit; }
.drawer-heading { font-size: 11px; font-weight: bold; opacity: 0.5; margin: 14px 16px 3px; }
.drawer-column { border-right: 1px solid rgba(120, 120, 150, 0.18); }
.drawer-preview-name { font-weight: bold; font-size: 15px; }
.drawer-status { font-size: 11px; opacity: 0.7; padding: 3px 10px; }
.drawer-tabs { padding: 4px 6px 0; }
.drawer-tabs button { padding: 2px 8px; }
.drawer-tab-close { padding: 0 2px; min-width: 0; min-height: 0; }
"""


def human_size(size):
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if size < 1000 or unit == "TB":
            return f"{size} {unit}" if unit == "bytes" else f"{size:.1f} {unit}"
        size /= 1000
    return ""


def when(stamp):
    if not stamp:
        return ""
    now = time.time()
    if now - stamp < 86400 and time.localtime(now).tm_mday == time.localtime(stamp).tm_mday:
        return time.strftime("Today %-I:%M %p", time.localtime(stamp))
    return time.strftime("%b %-d, %Y", time.localtime(stamp))


def places():
    home = GLib.get_home_dir()
    found = [("Home", home, "user-home-symbolic")]
    apps = os.path.join(home, "Applications")
    if os.path.isdir(apps):
        found.append(("Applications", apps, "folder-symbolic"))
    special = [
        (GLib.UserDirectory.DIRECTORY_DESKTOP, "Desktop", "user-desktop-symbolic"),
        (GLib.UserDirectory.DIRECTORY_DOCUMENTS, "Documents", "folder-documents-symbolic"),
        (GLib.UserDirectory.DIRECTORY_DOWNLOAD, "Downloads", "folder-download-symbolic"),
        (GLib.UserDirectory.DIRECTORY_MUSIC, "Music", "folder-music-symbolic"),
        (GLib.UserDirectory.DIRECTORY_PICTURES, "Pictures", "folder-pictures-symbolic"),
        (GLib.UserDirectory.DIRECTORY_VIDEOS, "Videos", "folder-videos-symbolic"),
    ]
    for kind, fallback, icon in special:
        path = GLib.get_user_special_dir(kind) or os.path.join(home, fallback)
        if path and path != home and os.path.isdir(path):
            found.append((os.path.basename(path), path, icon))
    return found


def load_favourites():
    """The sidebar's folders: [(name, path)]. The list Drawer starts with is
    the home folder and its usual folders; people add, remove and reorder."""
    try:
        with open(CONFIG) as f:
            saved = json.load(f).get("favourites")
        if isinstance(saved, list):
            return [(str(e[0]), str(e[1])) for e in saved if isinstance(e, list) and len(e) == 2]
    except (OSError, ValueError, AttributeError):
        pass
    return [(name, path) for name, path, _icon in places()]


def save_favourites(entries):
    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    try:
        with open(CONFIG) as f:
            config = json.load(f)
    except (OSError, ValueError):
        config = {}
    config["favourites"] = [[name, path] for name, path in entries]
    with open(CONFIG, "w") as f:
        json.dump(config, f, indent=2)


def place_icon(path):
    for _name, known, icon in places():
        if known == path:
            return icon
    return "folder-symbolic"


MAC_APP = "Mac App"


class Folder:
    """Reads one folder into a Gtk.ListStore."""

    icon_cache = {}

    def __init__(self, path, show_hidden=False):
        self.path = path
        self.store = Gtk.ListStore(GdkPixbuf.Pixbuf, str, str, bool, str, str, str, str, GdkPixbuf.Pixbuf)
        self.store.set_sort_column_id(C_SORT, Gtk.SortType.ASCENDING)
        self.error = None
        try:
            enum = Gio.File.new_for_path(path).enumerate_children(ATTRS, Gio.FileQueryInfoFlags.NONE, None)
        except GLib.Error as err:
            self.error = err.message
            return
        for info in enum:
            if info.get_is_hidden() and not show_hidden:
                continue
            is_dir = info.get_file_type() == Gio.FileType.DIRECTORY
            modified = info.get_modification_date_time()
            stamp = modified.to_unix() if modified else 0
            kind = "Folder" if is_dir else Gio.content_type_get_description(info.get_content_type() or "")
            name = info.get_display_name()
            full = os.path.join(path, info.get_name())
            big, small = self.icon(info.get_icon(), 48), self.icon(info.get_icon(), 20)
            if is_dir and macapps.is_bundle(full):
                # A Mac app is a folder, but it shows and opens as one app, with its own icon.
                is_dir, kind = False, MAC_APP
                name = macapps.display_name(full)
                big, small = self.app_icon(full, 48), self.app_icon(full, 20)
            self.store.append([
                big, name, full, is_dir,
                "" if is_dir or kind == MAC_APP else human_size(info.get_size()), when(stamp), kind,
                ("0" if is_dir else "1") + name.lower(), small,
            ])
        enum.close(None)

    @classmethod
    def app_icon(cls, path, size):
        pixbuf = macapps.cached_icon(path, size)
        return pixbuf or cls.icon(Gio.ThemedIcon.new(macapps.GENERIC_ICON), size)

    @classmethod
    def icon(cls, gicon, size):
        key = (gicon.to_string() if gicon else "", size)
        if key not in cls.icon_cache:
            theme = Gtk.IconTheme.get_default()
            found = theme.lookup_by_gicon(gicon, size, Gtk.IconLookupFlags.FORCE_SIZE) if gicon else None
            if not found:
                found = theme.lookup_icon("text-x-generic", size, Gtk.IconLookupFlags.FORCE_SIZE)
            try:
                cls.icon_cache[key] = found.load_icon() if found else None
            except GLib.Error:
                cls.icon_cache[key] = None
        return cls.icon_cache[key]


def name_column(title="Name"):
    col = Gtk.TreeViewColumn(title)
    icon = Gtk.CellRendererPixbuf()
    text = Gtk.CellRendererText(ellipsize=Pango.EllipsizeMode.END)
    col.pack_start(icon, False)
    col.pack_start(text, True)
    col.add_attribute(icon, "pixbuf", C_SMALL)
    col.add_attribute(text, "text", C_NAME)
    col.set_expand(True)
    col.set_sort_column_id(C_SORT)
    return col


class DrawerWindow(Gtk.ApplicationWindow):
    def __init__(self, app, path):
        super().__init__(application=app, title="Drawer")
        self.set_default_size(980, 600)
        self.history, self.future = [], []
        self.path = None
        self.view_mode = "icons"
        self.show_hidden = False
        self.filter_text = ""
        self.tabs = []        # one dict per tab; the open tab's state lives on self
        self.current = 0
        self.glance = None

        header = Gtk.HeaderBar(show_close_button=True)
        self.set_titlebar(header)
        nav = Gtk.Box(spacing=0)
        nav.get_style_context().add_class("linked")
        self.back = self._button("go-previous-symbolic", "Back", self.go_back)
        self.forward = self._button("go-next-symbolic", "Forward", self.go_forward)
        nav.add(self.back)
        nav.add(self.forward)
        header.pack_start(nav)
        self.title = Gtk.Label()
        self.title.get_style_context().add_class("title")
        header.set_custom_title(self.title)

        views = Gtk.Box()
        views.get_style_context().add_class("linked")
        self.view_buttons = {}
        group = None
        for mode, icon, tip in VIEWS:
            button = Gtk.RadioButton.new_from_widget(group)
            group = group or button
            button.set_mode(False)
            button.set_image(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON))
            button.set_tooltip_text(tip)
            button.connect("toggled", self._view_toggled, mode)
            views.add(button)
            self.view_buttons[mode] = button
        self.search = Gtk.SearchEntry(placeholder_text="Filter", width_chars=16)
        self.search.connect("search-changed", self._filter_changed)
        header.pack_end(self.search)
        header.pack_end(views)
        header.pack_end(self._button("folder-new-symbolic", "New Folder", lambda *_: self.new_folder()))

        paned = Gtk.Paned()
        self.add(paned)
        paned.pack1(self._sidebar(), False, False)
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.tab_bar = Gtk.Box(spacing=4, homogeneous=True)
        self.tab_bar.get_style_context().add_class("drawer-tabs")
        self.tab_bar.set_no_show_all(True)
        right.pack_start(self.tab_bar, False, False, 0)
        self.content = Gtk.Stack(transition_type=Gtk.StackTransitionType.NONE)
        right.pack_start(self.content, True, True, 0)
        self.status = Gtk.Label(xalign=0)
        self.status.get_style_context().add_class("drawer-status")
        right.pack_start(self.status, False, False, 0)
        paned.pack2(right, True, False)
        paned.set_position(190)

        self._build_icon_view()
        self._build_list_view()
        self._build_column_view()
        self.connect("key-press-event", self._key)
        self._add_actions()
        self.tabs.append({})
        self.navigate(path, remember=False)
        # GTK lights the first sidebar row as the window shows; put it right.
        self.connect("map", lambda *_: GLib.idle_add(lambda: self._show_place() and False))

    # ---- tabs -----------------------------------------------------------
    def _save_tab(self):
        self.tabs[self.current] = {"path": self.path, "history": self.history, "future": self.future,
                                   "view": self.view_mode, "filter": self.search.get_text()}

    def _load_tab(self, index):
        self.current = index
        tab = self.tabs[index]
        self.path, self.history, self.future = tab["path"], tab["history"], tab["future"]
        self.search.set_text(tab["filter"])
        if self.view_mode != tab["view"]:
            self.view_buttons[tab["view"]].set_active(True)   # refreshes
        else:
            self.refresh()

    def new_tab(self, path=None):
        self._save_tab()
        self.tabs.append({"path": os.path.abspath(path or self.path), "history": [], "future": [],
                          "view": self.view_mode, "filter": ""})
        self._load_tab(len(self.tabs) - 1)

    def switch_tab(self, index):
        if 0 <= index < len(self.tabs) and index != self.current:
            self._save_tab()
            self._load_tab(index)

    def close_tab(self, index=None):
        index = self.current if index is None else index
        if len(self.tabs) <= 1:
            self.close()
            return
        self._save_tab()
        del self.tabs[index]
        self._load_tab(min(self.current if index > self.current else max(0, self.current - 1),
                           len(self.tabs) - 1))

    def _draw_tabs(self):
        for child in self.tab_bar.get_children():
            self.tab_bar.remove(child)
        if len(self.tabs) < 2:
            self.tab_bar.hide()
            return
        for index, tab in enumerate(self.tabs):
            path = self.path if index == self.current else tab["path"]
            box = Gtk.Box()
            box.get_style_context().add_class("linked")
            button = Gtk.ToggleButton(label=self._label(path), active=index == self.current)
            button.get_child().set_ellipsize(Pango.EllipsizeMode.MIDDLE)
            button.connect("clicked", lambda b, i=index: (self.switch_tab(i), b.set_active(i == self.current)))
            close = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.MENU)
            close.get_style_context().add_class("drawer-tab-close")
            close.set_tooltip_text("Close Tab")
            close.connect("clicked", lambda _b, i=index: self.close_tab(i))
            box.pack_start(button, True, True, 0)
            box.pack_start(close, False, False, 0)
            self.tab_bar.pack_start(box, True, True, 0)
            box.show_all()
        self.tab_bar.show()

    @staticmethod
    def _label(path):
        if path == GLib.get_home_dir():
            return "Home"
        return os.path.basename(path) or "Computer"

    # ---- Glance (Space) -------------------------------------------------
    def toggle_glance(self):
        if self.glance and self.glance.get_visible():
            self.glance.hide()
            return
        paths = self.selected_paths()
        if not paths:
            return
        if self.glance is None:
            self.glance = Glance(self, lambda p: (self.glance.hide(), self.open_or_enter(p)))
        self.glance.show_path(paths[0])

    def _selection_changed(self, *_args):
        if self.glance and self.glance.get_visible():
            paths = self.selected_paths()
            if paths and paths[0] != self.glance.path:
                self.glance.show_path(paths[0])
                self.present()   # keep the keys going to the file list

    # ---- dragging files out ---------------------------------------------
    def _drag_get(self, _widget, _context, data, _info, _time):
        data.set_uris([Gio.File.new_for_path(p).get_uri() for p in self.selected_paths()])

    def _add_actions(self):
        """The window's actions, for the menu bar."""
        menus.add_actions(self, {
            "new-folder": self.new_folder,
            "open": lambda: [self.open_or_enter(p) for p in self.selected_paths()],
            "rename": self.rename,
            "trash": self.trash,
            "close": self.close,
            "select-all": self.select_all,
            "filter": self.search.grab_focus,
            "back": self.go_back,
            "forward": self.go_forward,
            "up": self.go_up,
            "view-icons": lambda: self.view_buttons["icons"].set_active(True),
            "view-list": lambda: self.view_buttons["list"].set_active(True),
            "view-columns": lambda: self.view_buttons["columns"].set_active(True),
            "new-tab": self.new_tab,
            "close-tab": self.close_tab,
            "next-tab": lambda: self.switch_tab((self.current + 1) % len(self.tabs)),
            "previous-tab": lambda: self.switch_tab((self.current - 1) % len(self.tabs)),
            "glance": self.toggle_glance,
            "add-to-sidebar": self.add_to_sidebar,
            "compress": self.compress,
            "get-info": self.get_info,
        })
        for name, path in (("go-home", GLib.get_home_dir()),
                           ("go-documents", GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOCUMENTS)),
                           ("go-downloads", GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD)),
                           ("go-desktop", GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DESKTOP)),
                           ("go-computer", "/")):
            menus.add_actions(self, {name: lambda p=path or GLib.get_home_dir(): self.navigate(p)})
        self.hidden_action = menus.add_toggle(self, "show-hidden", False, self._set_hidden)

    # ---- building -------------------------------------------------------
    def _button(self, icon, tip, handler):
        button = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
        button.set_tooltip_text(tip)
        button.connect("clicked", handler)
        return button

    def _sidebar(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.get_style_context().add_class("drawer-sidebar")
        box.set_size_request(170, -1)
        self.place_rows = []

        def section(title, entries):
            label = Gtk.Label(label=title, xalign=0)
            label.get_style_context().add_class("drawer-heading")
            box.pack_start(label, False, False, 0)
            listbox = Gtk.ListBox(can_focus=False)
            listbox.get_style_context().add_class("drawer-sidebar")
            listbox.connect("row-activated", lambda _l, row: self.navigate(row.path))
            for name, path, icon in entries:
                row = Gtk.ListBoxRow(can_focus=False)
                row.path = path
                line = Gtk.Box(spacing=8)
                line.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU), False, False, 0)
                line.pack_start(Gtk.Label(label=name, xalign=0), True, True, 0)
                row.add(line)
                listbox.add(row)
                self.place_rows.append((listbox, row))
            box.pack_start(listbox, False, False, 0)

        heading = Gtk.Label(label="Favorites", xalign=0)
        heading.get_style_context().add_class("drawer-heading")
        box.pack_start(heading, False, False, 0)
        self.fav_list = Gtk.ListBox(can_focus=False)
        self.fav_list.get_style_context().add_class("drawer-sidebar")
        self.fav_list.connect("row-activated", lambda _l, row: self.navigate(row.path))
        self.fav_list.connect("button-press-event", self._sidebar_button)
        # Drop folders here to add them.
        self.fav_list.drag_dest_set(Gtk.DestDefaults.ALL, URI_TARGETS, Gdk.DragAction.COPY | Gdk.DragAction.LINK)
        self.fav_list.connect("drag-data-received", self._sidebar_drop)
        box.pack_start(self.fav_list, False, False, 0)
        self._fill_favourites()
        trash = os.path.join(GLib.get_user_data_dir(), "Trash", "files")
        section("Locations", [("Computer", "/", "drive-harddisk-symbolic"), ("Trash", trash, "user-trash-symbolic")])
        return box

    def _show_place(self):
        """Light up the sidebar row for the folder on show, and no other.
        Inside a folder the sidebar doesn't list, no row is lit."""
        lists = {listbox for listbox, _row in self.place_rows}
        for listbox in lists:
            listbox.unselect_all()
        for listbox, row in self.place_rows:
            if os.path.normpath(row.path) == self.path:
                listbox.select_row(row)
                break

    def _fill_favourites(self):
        self.place_rows = [(lb, row) for lb, row in self.place_rows if lb is not self.fav_list]
        for child in self.fav_list.get_children():
            self.fav_list.remove(child)
        for name, path in load_favourites():
            row = Gtk.ListBoxRow(can_focus=False)
            row.path = path
            line = Gtk.Box(spacing=8)
            line.pack_start(Gtk.Image.new_from_icon_name(place_icon(path), Gtk.IconSize.MENU), False, False, 0)
            line.pack_start(Gtk.Label(label=name, xalign=0, ellipsize=Pango.EllipsizeMode.END), True, True, 0)
            row.add(line)
            self.fav_list.add(row)
            self.place_rows.insert(0, (self.fav_list, row))
        self.fav_list.show_all()

    def _change_favourites(self, change):
        entries = load_favourites()
        change(entries)
        save_favourites(entries)
        # Every Drawer window shows the same sidebar.
        for window in self.get_application().get_windows() if self.get_application() else [self]:
            if isinstance(window, DrawerWindow):
                window._fill_favourites()
                if window.path:
                    window.refresh()

    def add_to_sidebar(self, paths=None):
        folders = [p for p in (paths or self.selected_paths() or [self.path]) if os.path.isdir(p)]

        def change(entries):
            known = {path for _name, path in entries}
            entries.extend((self._label(p), p) for p in folders if p not in known)
        if folders:
            self._change_favourites(change)

    def _sidebar_drop(self, _widget, _context, _x, _y, data, _info, _time):
        paths = [Gio.File.new_for_uri(u).get_path() for u in data.get_uris() or []]
        self.add_to_sidebar([p for p in paths if p])

    def _sidebar_button(self, listbox, event):
        if event.button != 3:
            return False
        row = listbox.get_row_at_y(int(event.y))
        if row is None:
            return False
        index = row.get_index()
        count = len(listbox.get_children())

        def move(by):
            def change(entries):
                entries.insert(index + by, entries.pop(index))
            self._change_favourites(change)

        menu = Gtk.Menu()
        for label, handler, enabled in (
            ("Open in New Tab", lambda *_: self.new_tab(row.path), True),
            (None, None, True),
            ("Move Up", lambda *_: move(-1), index > 0),
            ("Move Down", lambda *_: move(1), index < count - 1),
            ("Remove from Sidebar", lambda *_: self._change_favourites(lambda e: e.pop(index)), True),
        ):
            item = Gtk.SeparatorMenuItem() if label is None else Gtk.MenuItem(label=label)
            if handler:
                item.connect("activate", handler)
            item.set_sensitive(enabled)
            menu.append(item)
        menu.show_all()
        menu.attach_to_widget(listbox, None)
        menu.popup_at_pointer(event)
        return True

    def _model(self, folder):
        model = folder.store.filter_new()
        model.set_visible_func(lambda m, it, _d: not self.filter_text or self.filter_text in m[it][C_NAME].lower())
        return model

    def _build_icon_view(self):
        self.icon_view = Gtk.IconView(item_width=96, margin=12, column_spacing=6, row_spacing=6)
        self.icon_view.set_pixbuf_column(C_ICON)
        self.icon_view.set_text_column(C_NAME)
        self.icon_view.set_selection_mode(Gtk.SelectionMode.MULTIPLE)
        self.icon_view.connect("item-activated", lambda v, p: self._activate(v.get_model(), p))
        self.icon_view.connect("button-press-event", self._icon_button)
        self.icon_view.connect("selection-changed", self._selection_changed)
        self.icon_view.enable_model_drag_source(Gdk.ModifierType.BUTTON1_MASK, URI_TARGETS,
                                                Gdk.DragAction.COPY | Gdk.DragAction.MOVE)
        self.icon_view.connect("drag-data-get", self._drag_get)
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.icon_view)
        self.content.add_named(scroll, "icons")

    def _build_list_view(self):
        self.list_view = Gtk.TreeView(headers_visible=True, enable_search=False)
        self.list_view.append_column(name_column())
        for title, col in (("Modified", C_MODIFIED), ("Size", C_SIZE), ("Kind", C_KIND)):
            renderer = Gtk.CellRendererText(ellipsize=Pango.EllipsizeMode.END)
            renderer.set_property("foreground-rgba", Gdk.RGBA(0.45, 0.45, 0.5, 1))
            column = Gtk.TreeViewColumn(title, renderer, text=col)
            column.set_min_width(110)
            self.list_view.append_column(column)
        self.list_view.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE)
        self.list_view.connect("row-activated", lambda v, p, _c: self._activate(v.get_model(), p))
        self.list_view.connect("button-press-event", self._tree_button)
        self.list_view.get_selection().connect("changed", self._selection_changed)
        self.list_view.enable_model_drag_source(Gdk.ModifierType.BUTTON1_MASK, URI_TARGETS,
                                                Gdk.DragAction.COPY | Gdk.DragAction.MOVE)
        self.list_view.connect("drag-data-get", self._drag_get)
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.list_view)
        self.content.add_named(scroll, "list")

    def _build_column_view(self):
        self.columns_box = Gtk.Box()
        self.column_scroll = Gtk.ScrolledWindow(vscrollbar_policy=Gtk.PolicyType.NEVER)
        self.column_scroll.add(self.columns_box)
        self.column_paths = []
        self.content.add_named(self.column_scroll, "columns")

    # ---- navigation -----------------------------------------------------
    def navigate(self, path, remember=True):
        path = os.path.abspath(os.path.expanduser(path))
        if remember and self.path and path != self.path:
            self.history.append(self.path)
            self.future.clear()
        self.path = path
        self.refresh()

    def go_back(self, *_):
        if self.history:
            self.future.append(self.path)
            self.path = self.history.pop()
            self.refresh()

    def go_forward(self, *_):
        if self.future:
            self.history.append(self.path)
            self.path = self.future.pop()
            self.refresh()

    def refresh(self):
        self.back.set_sensitive(bool(self.history))
        self.forward.set_sensitive(bool(self.future))
        home = GLib.get_home_dir()
        label = "Home" if self.path == home else (os.path.basename(self.path) or "Computer")
        self._draw_tabs()
        self.title.set_text(label)
        self.set_title(f"{label} — Drawer")
        self._show_place()
        folder = Folder(self.path, self.show_hidden)
        self.folder = folder
        model = self._model(folder)
        self.icon_view.set_model(model)
        self.list_view.set_model(Gtk.TreeModelSort(model=model))
        if self.view_mode == "columns":
            self._reset_columns()
        count = len(model)
        self.status.set_text(folder.error or f"{count} item{'s' if count != 1 else ''}")
        self.content.set_visible_child_name(self.view_mode)

    # ---- column (Miller) view ------------------------------------------
    def _reset_columns(self):
        # Show the chain from the nearest sensible root down to the folder.
        home = GLib.get_home_dir()
        root = home if self.path == home or self.path.startswith(home + os.sep) else "/"
        chain = [self.path]
        while chain[0] != root and os.path.dirname(chain[0]) != chain[0]:
            chain.insert(0, os.path.dirname(chain[0]))
        for child in self.columns_box.get_children():
            self.columns_box.remove(child)
        self.column_paths = []
        # Selecting a folder in a column opens the next column itself.
        self._add_column(chain[0])
        for index, path in enumerate(chain[1:]):
            self._select_in_column(index, path)
        self.path = chain[-1]

    def _add_column(self, path):
        folder = Folder(path, self.show_hidden)
        view = Gtk.TreeView(headers_visible=False, enable_search=False, model=self._model(folder))
        view.append_column(name_column())
        arrow = Gtk.CellRendererText(xalign=1)
        arrow_col = Gtk.TreeViewColumn("", arrow)
        arrow_col.set_cell_data_func(arrow, lambda c, cell, m, it, _d: cell.set_property(
            "text", "›" if m[it][C_IS_DIR] else ""))
        view.append_column(arrow_col)
        index = len(self.column_paths)
        view.get_selection().connect("changed", self._column_changed, index)
        view.connect("row-activated", lambda v, p, _c: self._activate(v.get_model(), p))
        view.connect("button-press-event", self._tree_button)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.set_size_request(220, -1)
        scroll.get_style_context().add_class("drawer-column")
        scroll.add(view)
        scroll.view = view
        self.columns_box.pack_start(scroll, False, False, 0)
        self.column_paths.append(path)
        self.columns_box.show_all()
        GLib.idle_add(self._scroll_columns_end)

    def _scroll_columns_end(self):
        adj = self.column_scroll.get_hadjustment()
        adj.set_value(adj.get_upper() - adj.get_page_size())
        return False

    def _select_in_column(self, index, path):
        view = self.columns_box.get_children()[index].view
        model = view.get_model()
        for row in model:
            if row[C_PATH] == path:
                view.get_selection().select_iter(row.iter)
                view.scroll_to_cell(row.path, None, False, 0, 0)
                return

    def _column_changed(self, selection, index):
        model, it = selection.get_selected()
        children = self.columns_box.get_children()
        for extra in children[index + 1:]:
            self.columns_box.remove(extra)
        del self.column_paths[index + 1:]
        if it is None:
            return
        path, is_dir = model[it][C_PATH], model[it][C_IS_DIR]
        if is_dir:
            self._add_column(path)
            label = os.path.basename(path)
            self.title.set_text(label)
            self.path = path
        else:
            self._add_preview(path, model[it])

    def _add_preview(self, path, row):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, margin=24)
        box.set_size_request(260, -1)
        pixbuf = None
        try:
            if row[C_KIND] == MAC_APP:
                pixbuf = Folder.app_icon(path, 128)
            elif (row[C_KIND] or "").lower().find("image") >= 0:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, 220, 220, True)
        except GLib.Error:
            pixbuf = None
        if pixbuf is None:
            gicon = Gio.content_type_get_icon(Gio.content_type_guess(path, None)[0])
            pixbuf = Folder.icon(gicon, 128)
        box.pack_start(Gtk.Image.new_from_pixbuf(pixbuf), False, False, 12)
        name = Gtk.Label(label=row[C_NAME], wrap=True, max_width_chars=24)
        name.get_style_context().add_class("drawer-preview-name")
        box.pack_start(name, False, False, 0)
        for text in (row[C_KIND], row[C_SIZE], f"Modified {row[C_MODIFIED]}"):
            label = Gtk.Label(label=text, wrap=True)
            label.get_style_context().add_class("dim-label")
            box.pack_start(label, False, False, 0)
        self.columns_box.pack_start(box, False, False, 0)
        self.columns_box.show_all()
        GLib.idle_add(self._scroll_columns_end)

    # ---- actions --------------------------------------------------------
    def _activate(self, model, tree_path):
        it = model.get_iter(tree_path)
        path, is_dir = model[it][C_PATH], model[it][C_IS_DIR]
        if is_dir:
            self.navigate(path)
        else:
            self.open_file(path)

    def open_file(self, path):
        if macapps.is_bundle(path):
            GLib.spawn_async(["freemac-mac-app", "open", path], flags=GLib.SpawnFlags.SEARCH_PATH)
            return
        if drawer_archive.is_archive(path):
            self.expand(path)
            return
        try:
            Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(path).get_uri(), None)
        except GLib.Error as err:
            self.notify(f"No app can open “{os.path.basename(path)}” ({err.message}).")

    # ---- archives -------------------------------------------------------
    def _in_background(self, work, done, busy_text):
        """Run work() in a thread; done(result, error) back on the main loop."""
        self.notify(busy_text)

        def run():
            try:
                result, error = work(), None
            except (OSError, EOFError, ValueError, RuntimeError) as err:
                result, error = None, err
            except Exception as err:   # zipfile/tarfile raise their own kinds
                result, error = None, err
            GLib.idle_add(lambda: done(result, error) or False)

        threading.Thread(target=run, daemon=True).start()

    def add_to_applications(self, path):
        name = macapps.display_name(path)

        def done(_target, error):
            if error:
                self.notify(f"Couldn't add “{name}” to Applications: {error}")
            else:
                self.refresh()
                self.notify(f"“{name}” is in Applications and the app grid now.")

        self._in_background(lambda: macapps.install(path), done, f"Adding “{name}” to Applications…")

    def compress(self):
        paths = self.selected_paths()
        if not paths:
            return

        def done(target, error):
            if error:
                self.notify(f"Couldn't compress: {error}")
            else:
                self.refresh()
                self.notify(f"Made “{os.path.basename(target)}”.")

        self._in_background(lambda: drawer_archive.compress(paths), done,
                            f"Compressing {len(paths)} item{'s' if len(paths) != 1 else ''}…")

    def expand(self, path):
        def done(folder, error):
            if error:
                self.notify(f"Couldn't expand “{os.path.basename(path)}”: {error}")
            else:
                self.refresh()
                self.notify(f"Expanded into “{os.path.basename(folder)}”.")

        self._in_background(lambda: drawer_archive.extract(path), done,
                            f"Expanding “{os.path.basename(path)}”…")

    def notify(self, text):
        self.status.set_text(text)

    def selected_paths(self):
        if self.view_mode == "icons":
            model = self.icon_view.get_model()
            return [model[p][C_PATH] for p in self.icon_view.get_selected_items()]
        if self.view_mode == "list":
            model, paths = self.list_view.get_selection().get_selected_rows()
            return [model[p][C_PATH] for p in paths]
        for scroll in reversed(self.columns_box.get_children()):
            if hasattr(scroll, "view"):
                model, it = scroll.view.get_selection().get_selected()
                if it is not None:
                    return [model[it][C_PATH]]
        return []

    def new_folder(self):
        base = self.path
        name, n = "untitled folder", 2
        while os.path.exists(os.path.join(base, name)):
            name, n = f"untitled folder {n}", n + 1
        try:
            os.mkdir(os.path.join(base, name))
        except OSError as err:
            self.notify(f"Couldn’t make a folder here: {err.strerror}.")
            return
        self.refresh()
        self.rename(os.path.join(base, name))

    def rename(self, path=None):
        paths = [path] if path else self.selected_paths()
        if len(paths) != 1:
            return
        path = paths[0]
        dialog = Gtk.Dialog(title="Rename", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Rename", Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        entry = Gtk.Entry(text=os.path.basename(path), activates_default=True, width_chars=32)
        dialog.get_content_area().pack_start(entry, True, True, 12)
        dialog.show_all()
        stem = os.path.splitext(os.path.basename(path))[0] if not os.path.isdir(path) else entry.get_text()
        entry.select_region(0, len(stem))
        if dialog.run() == Gtk.ResponseType.OK:
            new = entry.get_text().strip()
            if new and "/" not in new and new != os.path.basename(path):
                target = os.path.join(os.path.dirname(path), new)
                if os.path.exists(target):
                    self.notify(f"“{new}” already exists.")
                else:
                    try:
                        os.rename(path, target)
                    except OSError as err:
                        self.notify(f"Couldn’t rename: {err.strerror}.")
        dialog.destroy()
        self.refresh()

    def trash(self):
        paths = self.selected_paths()
        moved = 0
        for path in paths:
            try:
                Gio.File.new_for_path(path).trash(None)
                moved += 1
            except GLib.Error as err:
                self.notify(f"Couldn’t move “{os.path.basename(path)}” to the Trash: {err.message}")
        self.refresh()
        if moved:
            self.notify(f"Moved {moved} item{'s' if moved != 1 else ''} to the Trash.")

    def get_info(self):
        paths = self.selected_paths() or [self.path]
        drawer_info.show(paths, self)

    def toggle_hidden(self):
        self.hidden_action.change_state(GLib.Variant("b", not self.show_hidden))

    def _set_hidden(self, shown):
        self.show_hidden = shown
        self.refresh()

    def select_all(self):
        if self.view_mode == "icons":
            self.icon_view.select_all()
        elif self.view_mode == "list":
            self.list_view.get_selection().select_all()

    def go_up(self):
        parent = os.path.dirname(self.path)
        if parent != self.path:
            self.navigate(parent)

    # ---- events ---------------------------------------------------------
    def _view_toggled(self, button, mode):
        if button.get_active():
            self.view_mode = mode
            if self.path:
                self.refresh()
            GLib.idle_add(self._focus_view)

    def _focus_view(self):
        """Keyboard focus follows the view, so arrow keys move through files."""
        if self.view_mode == "icons":
            self.icon_view.grab_focus()
        elif self.view_mode == "list":
            self.list_view.grab_focus()
        else:
            # Focus the column holding the open folder, on its selected row;
            # focusing a column with no cursor would select (and open) its
            # first row.
            for column in reversed(self.columns_box.get_children()):
                model, it = column.view.get_selection().get_selected()
                if it:
                    column.view.set_cursor(model.get_path(it), None, False)
                    column.view.grab_focus()
                    break
        return False

    def _filter_changed(self, entry):
        self.filter_text = entry.get_text().strip().lower()
        self.icon_view.get_model().refilter()
        if self.view_mode == "columns":
            self._reset_columns()

    def _menu(self, event):
        menu = Gtk.Menu()
        has_selection = bool(self.selected_paths())
        has_folder = any(os.path.isdir(p) for p in self.selected_paths()[:1])
        selected = self.selected_paths()
        one_archive = len(selected) == 1 and drawer_archive.is_archive(selected[0])
        one_app = len(selected) == 1 and macapps.is_bundle(selected[0])
        app_items = ()
        if one_app:
            app_items = (
                ("Show Package Contents", lambda *_: self.navigate(selected[0]), True),
                ("Add to Applications", lambda *_: self.add_to_applications(selected[0]),
                 not macapps.in_applications(selected[0])),
                (None, None, True),
            )
        for label, handler, enabled in app_items + (
            ("Open", lambda *_: [self.open_or_enter(p) for p in self.selected_paths()], has_selection),
            ("Get Info", lambda *_: self.get_info(), True),
            ("Rename…", lambda *_: self.rename(), has_selection),
            ("Move to Trash", lambda *_: self.trash(), has_selection),
            (None, None, True),
            ("Expand" if one_archive else "Compress",
             (lambda *_: self.expand(selected[0])) if one_archive else (lambda *_: self.compress()), has_selection),
            (None, None, True),
            ("Open in New Tab", lambda *_: self.new_tab(self.selected_paths()[0]), has_folder),
            ("Add to Sidebar", lambda *_: self.add_to_sidebar(), has_folder),
            ("Glance", lambda *_: self.toggle_glance(), has_selection),
            (None, None, True),
            ("New Folder", lambda *_: self.new_folder(), True),
            ("Hide Hidden Files" if self.show_hidden else "Show Hidden Files", lambda *_: self.toggle_hidden(), True),
        ):
            item = Gtk.SeparatorMenuItem() if label is None else Gtk.MenuItem(label=label)
            if handler:
                item.connect("activate", handler)
            item.set_sensitive(enabled)
            menu.append(item)
        menu.show_all()
        menu.attach_to_widget(self, None)
        menu.popup_at_pointer(event)

    def open_or_enter(self, path):
        if os.path.isdir(path) and not macapps.is_bundle(path):
            self.navigate(path)
        else:
            self.open_file(path)

    def _icon_button(self, view, event):
        if event.button != 3:
            return False
        item = view.get_path_at_pos(int(event.x), int(event.y))
        if item and not view.path_is_selected(item):
            view.unselect_all()
            view.select_path(item)
        self._menu(event)
        return True

    def _tree_button(self, view, event):
        if event.button != 3:
            return False
        hit = view.get_path_at_pos(int(event.x), int(event.y))
        if hit and not view.get_selection().path_is_selected(hit[0]):
            view.get_selection().unselect_all()
            view.get_selection().select_path(hit[0])
        self._menu(event)
        return True

    def _key(self, _w, event):
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        shift = event.state & Gdk.ModifierType.SHIFT_MASK
        key = event.keyval
        if self.search.has_focus() and key not in (Gdk.KEY_Escape,):
            return False
        if key == Gdk.KEY_space and not ctrl:
            self.toggle_glance()
        elif ctrl and key in (Gdk.KEY_t, Gdk.KEY_T):
            self.new_tab()
        elif ctrl and key in (Gdk.KEY_Tab, Gdk.KEY_ISO_Left_Tab, Gdk.KEY_Page_Down, Gdk.KEY_Page_Up):
            back = shift or key == Gdk.KEY_Page_Up
            self.switch_tab((self.current + (-1 if back else 1)) % len(self.tabs))
        elif key == Gdk.KEY_Delete or (ctrl and key == Gdk.KEY_BackSpace):
            self.trash()  # Command+Backspace, as on a Mac
        elif ctrl and key in (Gdk.KEY_i, Gdk.KEY_I):
            self.get_info()
        elif key == Gdk.KEY_F2:
            self.rename()
        elif ctrl and shift and key in (Gdk.KEY_N, Gdk.KEY_n):
            self.new_folder()
        elif (ctrl and key in (Gdk.KEY_h, Gdk.KEY_H)) or (ctrl and shift and key in (Gdk.KEY_period,
                                                                                    Gdk.KEY_greater)):
            self.toggle_hidden()
        elif ctrl and key in (Gdk.KEY_1, Gdk.KEY_2, Gdk.KEY_3):
            self.view_buttons[VIEWS[key - Gdk.KEY_1][0]].set_active(True)
        elif ctrl and key in (Gdk.KEY_f, Gdk.KEY_F):
            self.search.grab_focus()
        elif (ctrl and key == Gdk.KEY_bracketleft) or key == Gdk.KEY_BackSpace or (
                event.state & Gdk.ModifierType.MOD1_MASK and key == Gdk.KEY_Left):
            self.go_back()
        elif (ctrl and key == Gdk.KEY_bracketright) or (event.state & Gdk.ModifierType.MOD1_MASK and
                                                        key == Gdk.KEY_Right):
            self.go_forward()
        elif ctrl and key in (Gdk.KEY_Up, Gdk.KEY_Home):
            # Command+Up: the folder it's in (Strata sends Command+Up as Ctrl+Home).
            self.go_up()
        elif ctrl and key in (Gdk.KEY_n, Gdk.KEY_N):
            self.get_application().activate_action("new-window", None)
        elif ctrl and shift and key in (Gdk.KEY_d, Gdk.KEY_D):
            self.add_to_sidebar()
        elif ctrl and key in (Gdk.KEY_w, Gdk.KEY_W):
            self.close_tab()
        elif ctrl and key in (Gdk.KEY_o, Gdk.KEY_O, Gdk.KEY_Down, Gdk.KEY_End):
            for p in self.selected_paths():
                self.open_or_enter(p)
        elif key == Gdk.KEY_Escape and self.search.get_text():
            self.search.set_text("")
        else:
            return False
        return True


def menubar():
    return menus.menubar([
        ("_File", [
            [("New Window", "app.new-window", "<Ctrl>n"), ("New Tab", "win.new-tab", "<Ctrl>t"),
             ("New Folder", "win.new-folder", "<Ctrl><Shift>n")],
            [("Open", "win.open", "<Ctrl>o"), ("Glance", "win.glance", "space")],
            [("Get Info", "win.get-info", "<Ctrl>i")],
            [("Rename…", "win.rename", "F2"), ("Compress", "win.compress", None),
             ("Move to Trash", "win.trash", "<Ctrl>BackSpace")],
            [("Add to Sidebar", "win.add-to-sidebar", "<Ctrl><Shift>d")],
            [("Close Tab", "win.close-tab", "<Ctrl>w"), ("Close Window", "win.close", "<Ctrl><Shift>w")],
        ]),
        ("_Edit", [
            [("Select All", "win.select-all", "<Ctrl>a")],
            [("Filter…", "win.filter", "<Ctrl>f")],
        ]),
        ("_View", [
            [("as Icons", "win.view-icons", "<Ctrl>1"), ("as List", "win.view-list", "<Ctrl>2"),
             ("as Columns", "win.view-columns", "<Ctrl>3")],
            [("Show Hidden Files", "win.show-hidden", "<Ctrl><Shift>period")],
            [("Next Tab", "win.next-tab", "<Ctrl>Tab"), ("Previous Tab", "win.previous-tab", "<Ctrl><Shift>Tab")],
        ]),
        ("_Go", [
            [("Back", "win.back", "<Ctrl>bracketleft"), ("Forward", "win.forward", "<Ctrl>bracketright"),
             ("Enclosing Folder", "win.up", "<Ctrl>Up")],
            [("Home", "win.go-home", None), ("Desktop", "win.go-desktop", None),
             ("Documents", "win.go-documents", None), ("Downloads", "win.go-downloads", None),
             ("Computer", "win.go-computer", None)],
        ]),
    ])


class Drawer(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.freemac.Drawer",
                         flags=Gio.ApplicationFlags.HANDLES_OPEN | Gio.ApplicationFlags.NON_UNIQUE)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        menus.add_actions(self, {"new-window": lambda: DrawerWindow(self, GLib.get_home_dir()).show_all()})
        self.set_menubar(menubar())
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def do_activate(self):
        DrawerWindow(self, GLib.get_home_dir()).show_all()

    def do_open(self, files, _n, _hint):
        for file in files:
            path = file.get_path()
            if path and os.path.isfile(path):
                path = os.path.dirname(path)
            DrawerWindow(self, path or GLib.get_home_dir()).show_all()


def main():
    import sys

    GLib.set_prgname("freemac-drawer")
    Drawer().run(sys.argv)
