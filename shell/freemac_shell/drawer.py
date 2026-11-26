# SPDX-License-Identifier: GPL-3.0-or-later
"""Drawer: freemac's file manager.

Icon, list and column views over local folders, tabs, a sidebar of
favourite folders you can change, a preview of the selected files on Space
(Glance), and the everyday file operations: open, new folder, rename, move
to trash, copy and paste (⌘C, ⌘V, ⌥⌘V to move), Duplicate, drag onto a
folder, and Undo (see transfer.py). Like Finder it also sorts by name, kind,
date or size, shows a path bar, goes to a typed folder (⇧⌘G), opens a file
with another app (Open With), and puts things back from the Trash.
"""
import json
import os
import subprocess
import threading
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango  # noqa: E402

from . import aliases, app_list, custom_icons, batch_rename, drawer_archive, drawer_background, drawer_clipboard, drawer_settings, drawer_info, drawer_summary, locks, macapps, menus, neighbours, quick_actions, recent_folders, recents, servers, services, share, smart_folders, tags, transfer, volumes  # noqa: E402
from .drawer_glance import Glance  # noqa: E402

CONFIG = os.path.join(GLib.get_user_config_dir(), "freemac", "drawer.json")
TRASH = os.path.join(GLib.get_user_data_dir(), "Trash", "files")
TO_TRASH, TO_SIDEBAR = "\0trash", "\0sidebar"   # drop places that aren't folders
URI_TARGETS = [Gtk.TargetEntry.new("text/uri-list", 0, 0)]

ATTRS = ",".join([
    "standard::name", "standard::display-name", "standard::type", "standard::icon",
    "standard::size", "standard::is-hidden", "standard::content-type", "time::modified",
])
# ListStore columns.
C_ICON, C_NAME, C_PATH, C_IS_DIR, C_SIZE, C_MODIFIED, C_KIND, C_SORT, C_SMALL, C_STAMP, C_BYTES, C_MARKUP = range(12)
SORTS = (("name", "Name"), ("kind", "Kind"), ("date", "Date Modified"), ("size", "Size"))
VIEWS = (("icons", "view-grid-symbolic", "Icons"),
         ("list", "view-list-symbolic", "List"),
         ("columns", "view-dual-symbolic", "Columns"),
         ("gallery", "view-paged-symbolic", "Gallery"))
ICONISH = ("icons", "gallery")   # both show the files in the icon view
CSS = b"""
box.drawer-sidebar { background-color: rgba(120, 120, 150, 0.08); }
viewport { background-color: transparent; }
list.drawer-sidebar { background-color: transparent; }
.drawer-sidebar row { padding: 4px 8px; border-radius: 6px; margin: 0 8px; background-color: transparent; }
.drawer-sidebar row image { color: @theme_selected_bg_color; }
.drawer-sidebar row:hover { background-color: rgba(120, 120, 150, 0.10); }
.drawer-sidebar row:selected { background-color: rgba(120, 120, 150, 0.24); color: inherit; }
.drawer-sidebar row:selected label { color: inherit; }
.drawer-eject { padding: 0 2px; min-height: 0; min-width: 0; }
.drawer-sidebar row .drawer-eject image { color: rgba(120, 120, 150, 0.9); }
.drawer-heading { font-size: 11px; font-weight: bold; opacity: 0.5; margin: 14px 16px 3px; }
.drawer-column { border-right: 1px solid rgba(120, 120, 150, 0.18); }
.drawer-preview-name { font-weight: bold; font-size: 15px; }
.drawer-status { font-size: 11px; opacity: 0.7; padding: 3px 10px; }
.drawer-gallery-name { font-weight: bold; padding-top: 4px; }
.drawer-preview { padding: 12px 14px; border-left: 1px solid rgba(120, 120, 140, 0.18); }
.drawer-preview-heading { font-weight: bold; font-size: 12px; }
.drawer-tabs { padding: 4px 6px 0; }
.drawer-tabs button { padding: 2px 8px; }
.drawer-tab-close { padding: 0 2px; min-width: 0; min-height: 0; }
.drawer-pathbar { padding: 1px 6px; border-top: 1px solid rgba(120, 120, 150, 0.18); }
.drawer-pathbar button { padding: 0 4px; min-height: 0; font-size: 11px; }
.drawer-pathbar button image { color: @theme_selected_bg_color; }
.drawer-crumb-gap { font-size: 11px; opacity: 0.45; }
.drawer-trashbar { padding: 6px 12px; border-bottom: 1px solid rgba(120, 120, 150, 0.18);
                   background-color: rgba(120, 120, 150, 0.06); }
.drawer-trashbar label.title { font-weight: bold; }
.drawer-scopebar { padding: 5px 8px; border-bottom: 1px solid rgba(120, 120, 150, 0.18);
                   background-color: rgba(120, 120, 150, 0.06); }
.drawer-scopebar button, .drawer-scopebar combobox button { padding: 1px 10px; min-height: 0; font-size: 12px; }
.drawer-scopebar label { font-size: 12px; }
.drawer-scopebar button:checked { background-image: none; background-color: @theme_selected_bg_color;
                                  color: @theme_selected_fg_color; }
.drawer-go-hint { font-size: 11px; opacity: 0.65; }
.drawer-go-hint.error { color: #d93a2b; opacity: 1; }
"""


def human_size(size):
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if size < 1000 or unit == "TB":
            return f"{size} {unit}" if unit == "bytes" else f"{size:.1f} {unit}"
        size /= 1000
    return ""


RELATIVE_DATES = [True]   # View Options > Use relative dates


def when(stamp):
    if not stamp:
        return ""
    if not RELATIVE_DATES[0]:
        return time.strftime("%b %-d, %Y at %-I:%M %p", time.localtime(stamp))
    now = time.localtime()
    day = time.localtime(stamp)
    yesterday = time.localtime(time.time() - 86400)
    if day[:3] == now[:3]:
        return time.strftime("Today %-I:%M %p", day)
    if day[:3] == yesterday[:3]:
        return time.strftime("Yesterday %-I:%M %p", day)
    return time.strftime("%b %-d, %Y", day)


def applications_folder():
    """~/Applications: Mac apps added with Ferry are kept here, and every
    installed app shows in it too, as in a Mac's Applications folder."""
    path = os.path.join(GLib.get_home_dir(), "Applications")
    try:
        os.makedirs(path, exist_ok=True)
    except OSError:
        pass
    return path


def places():
    home = GLib.get_home_dir()
    found = [("Home", home, "user-home-symbolic")]
    apps = applications_folder()
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


def load_config():
    """Drawer's settings: the sidebar, how folders are sorted, the path bar."""
    try:
        with open(CONFIG) as f:
            config = json.load(f)
        return config if isinstance(config, dict) else {}
    except (OSError, ValueError):
        return {}


def save_setting(key, value):
    config = load_config()
    config[key] = value
    try:
        os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
        with open(CONFIG, "w") as f:
            json.dump(config, f, indent=2)
    except OSError:
        pass


def load_favourites():
    """The sidebar's folders: [(name, path)]. The list Drawer starts with is
    the home folder and its usual folders; people add, remove and reorder."""
    saved = load_config().get("favourites")
    if isinstance(saved, list):
        return [(str(e[0]), str(e[1])) for e in saved if isinstance(e, list) and len(e) == 2]
    return [(name, path) for name, path, _icon in places()]


def save_favourites(entries):
    save_setting("favourites", [[name, path] for name, path in entries])


# Keep folders on top, whatever the sort (Drawer > Settings > Advanced).
FOLDERS_ON_TOP = [drawer_settings.get("folders_on_top")]


def sort_key(model, it, sort):
    """How a row sorts: by name, by kind, newest first, or largest first
    (folders last, as in Finder), with folders on top unless that's off."""
    is_dir, key, kind, stamp, size = model.get(it, C_IS_DIR, C_SORT, C_KIND, C_STAMP, C_BYTES)
    key = key or ""
    first = (not is_dir,) if FOLDERS_ON_TOP[0] else ()
    if sort == "kind":
        return first + ((kind or "").lower(), key[1:])
    if sort == "date":
        return first + (-(stamp or 0), key[1:])
    if sort == "size":
        if FOLDER_SIZES[0]:
            return (-(size or 0), key[1:])   # folders added up sort among the files
        return (bool(is_dir), -(size or 0), key[1:])
    return first + (key[1:],)


FOLDER_SIZES = [False]   # View Options > Calculate all sizes


def date_width():
    """Room for the longest date the Modified column shows."""
    return 150 if RELATIVE_DATES[0] else 196


def compare_rows(model, a, b, sort):
    ka, kb = sort_key(model, a, sort), sort_key(model, b, sort)
    return (ka > kb) - (ka < kb)


def complete_path(text, base):
    """Tab in Go to Folder: finish the name being typed, as far as the names
    that start that way agree. Returns the new text, or None."""
    if text.strip() == "~":
        return "~/"
    full = os.path.expanduser(text)
    if not os.path.isabs(full):
        full = os.path.join(base, full)
    folder, start = os.path.split(full)
    try:
        names = sorted(n for n in os.listdir(folder or "/")
                       if n.lower().startswith(start.lower()) and (start.startswith(".") or not n.startswith(".")))
    except OSError:
        return None
    if not names:
        return None
    if len(names) == 1:
        done = names[0] + ("/" if os.path.isdir(os.path.join(folder, names[0])) else "")
    else:
        common = len(os.path.commonprefix([n.lower() for n in names]))
        if common <= len(start):
            return None
        done = names[0][:common]
    return text[:len(text) - len(start)] + done


def place_icon(path):
    for _name, known, icon in places():
        if known == path:
            return icon
    return "folder-symbolic"


MAC_APP = "Mac App"
APPLICATION = "Application"
SPRING_DELAY = 900   # ms a drag rests on a folder before it springs open
TEXT_SIZES = (10, 11, 12, 13, 14, 16)   # points, for names in icon view
THUMB_LARGEST = 60_000_000   # bytes; bigger pictures keep their kind's icon


class Folder:
    """Reads one folder into a Gtk.ListStore."""

    icon_cache = {}
    badged = {}        # an icon -> the same icon with an alias's arrow
    locked = {}        # an icon -> the same icon with a padlock
    custom = {}        # (custom icon file, size) -> its picture
    thumb_cache = {}   # (path, modified, size) -> the file's own small picture

    def __init__(self, path, show_hidden=False, sort="name", icon_size=48, item_info=False):
        self.path = path
        self.icon_size, self.item_info = icon_size, item_info
        self.store = Gtk.ListStore(GdkPixbuf.Pixbuf, str, str, bool, str, str, str, str, GdkPixbuf.Pixbuf,
                                   float, float, str)
        self.store.set_sort_func(C_SORT, compare_rows, sort)
        self.store.set_sort_column_id(C_SORT, Gtk.SortType.ASCENDING)
        self.error = None
        self.waiting = []
        if path == recents.PLACE:
            # Recents: the files opened lately, newest first, from all over.
            self.store.set_sort_column_id(Gtk.TREE_SORTABLE_UNSORTED_SORT_COLUMN_ID, Gtk.SortType.ASCENDING)
            for full in recents.files():
                try:
                    info = Gio.File.new_for_path(full).query_info(ATTRS, Gio.FileQueryInfoFlags.NONE, None)
                except GLib.Error:
                    continue
                self._add(info, full)
        elif neighbours.is_place(path):
            # Network: the computers nearby, found as they answer (or the
            # folders one computer shares).
            self.browsing, self.on_change = True, None
            neighbours.browse(self._add_neighbour, self._browsed, uri=neighbours.uri_of(path))
        elif smart_folders.is_place(path):
            # A search, or a Smart Folder: files from all over, found by a
            # walk through the home folder in the background.
            self.browsing, self.on_change = True, None
            query = smart_folders.query_of(path)
            if query is None:
                self.error, self.browsing = "This Smart Folder isn’t there any more.", False
            elif smart_folders.is_empty(query):
                self.browsing = False
            else:
                self._search(query)
        elif path.startswith(tags.PREFIX):
            # A tag in the sidebar: every file with that tag, wherever it is.
            for full in tags.tagged(path[len(tags.PREFIX):]):
                try:
                    info = Gio.File.new_for_path(full).query_info(ATTRS, Gio.FileQueryInfoFlags.NONE, None)
                except GLib.Error:
                    continue
                self._add(info, full)
        else:
            try:
                enum = Gio.File.new_for_path(path).enumerate_children(ATTRS, Gio.FileQueryInfoFlags.NONE, None)
            except GLib.Error as err:
                self.error = err.message
                return
            found = {}
            for info in enum:
                # Read softly: some network folders leave is-hidden out.
                hidden = info.get_attribute_boolean("standard::is-hidden") or info.get_name().startswith(".")
                if hidden and not show_hidden:
                    continue
                full = os.path.join(path, info.get_name())
                names = self._add(info, full)
                if names:
                    found[full] = names
            enum.close(None)
            tags.note_folder(path, found)
            if os.path.realpath(path) == os.path.realpath(applications_folder()):
                self._add_apps()
        if self.waiting:
            GLib.idle_add(self._thumbnails, self.waiting)

    def _search(self, query):
        self.stop = threading.Event()
        self.pending, lock = [], threading.Lock()

        def found(full):
            try:
                info = Gio.File.new_for_path(full).query_info(ATTRS, Gio.FileQueryInfoFlags.NONE, None)
            except GLib.Error:
                return
            with lock:
                self.pending.append((info, full))

        def run():
            try:
                smart_folders.find(query, found, self.stop)
            finally:
                self.finished = True

        def show():
            with lock:
                batch, self.pending = self.pending, []
            for info, full in batch:
                self._add(info, full)
            if self.waiting:
                GLib.idle_add(self._thumbnails, self.waiting)
                self.waiting = []
            done = self.finished and not self.pending
            if done:
                self.browsing = False
            if (batch or done) and self.on_change:
                self.on_change()
            return not done and not self.stop.is_set()
        self.finished = False
        threading.Thread(target=run, daemon=True).start()
        GLib.timeout_add(120, show)

    def cancel(self):
        stop = getattr(self, "stop", None)
        if stop is not None:
            stop.set()
        sizing = getattr(self, "sizing", None)
        if sizing is not None:
            sizing.set()

    def add_up_folders(self, done=None):
        """Calculate all sizes: each folder's size, added up in the
        background, as Finder's list view does with that option on."""
        rows = [(Gtk.TreeRowReference.new(self.store, row.path), row[C_PATH]) for row in self.store
                if row[C_IS_DIR] and row[C_PATH] and os.path.isdir(row[C_PATH])]
        if not rows:
            return
        self.sizing = stop = threading.Event()
        for ref, _path in rows:
            self.store.set(self.store.get_iter(ref.get_path()), {C_SIZE: "Adding up\u2026"})

        def run():
            for ref, path in rows:
                if stop.is_set():
                    return
                found = drawer_info.folder_total(path, stop)
                if found is None:
                    return
                GLib.idle_add(show, ref, found[0])
            if done is not None:
                GLib.idle_add(done)

        def show(ref, total):
            if not stop.is_set() and ref.valid():
                it = self.store.get_iter(ref.get_path())
                self.store.set(it, {C_SIZE: human_size(total) if total else "Zero bytes", C_BYTES: float(total)})
            return False
        threading.Thread(target=run, daemon=True).start()

    def _add_neighbour(self, name, address, icon):
        """One computer in the Network place; opening it connects."""
        if not icon or not Gtk.IconTheme.get_default().lookup_by_gicon(icon, 16, 0):
            icon = Gio.ThemedIcon.new("network-server")
        self.store.append([
            self.icon(icon, self.icon_size), name, neighbours.PREFIX + address, True, "", "",
            "Computer", "0" + name.lower(), self.icon(icon, 20), 0.0, 0.0, GLib.markup_escape_text(name),
        ])
        if self.on_change:
            self.on_change()

    def _browsed(self):
        self.browsing = False
        if self.on_change:
            self.on_change()

    def _add(self, info, full):
        """One row for the file; returns its tags."""
        is_dir = info.get_file_type() == Gio.FileType.DIRECTORY
        modified = info.get_modification_date_time()
        stamp = modified.to_unix() if modified else 0
        kind = "Folder" if is_dir else Gio.content_type_get_description(info.get_content_type() or "")
        name = info.get_display_name()
        big, small = self.icon(info.get_icon(), self.icon_size), self.icon(info.get_icon(), 20)
        if is_dir and macapps.is_bundle(full):
            # A Mac app is a folder, but it shows and opens as one app, with its own icon.
            is_dir, kind = False, MAC_APP
            name = macapps.display_name(full)
            big, small = self.app_icon(full, self.icon_size), self.app_icon(full, 20)
        alias = aliases.is_alias(full)
        # An icon of its own, pasted in Get Info (an alias shows its original's).
        own_path = aliases.original(full) if alias else full
        own = custom_icons.pixbuf(own_path, self.icon_size, self.custom) if own_path else None
        if own is not None:
            big, small = own, custom_icons.pixbuf(own_path, 20, self.custom)
        if alias:
            # An alias shows its original's icon with a small arrow; a broken
            # one, a plain document's.
            kind = "Alias"
            if info.get_file_type() == Gio.FileType.SYMBOLIC_LINK:
                plain = Gio.ThemedIcon.new("text-x-generic")
                big, small = self.icon(plain, self.icon_size), self.icon(plain, 20)
            big, small = self.with_arrow(big), self.with_arrow(small)
        elif locks.is_locked(full):
            big, small = self.with_lock(big), self.with_lock(small)
        names = tags.get(full)
        it = self.store.append([
            big, name, full, is_dir,
            "" if is_dir or alias or kind == MAC_APP else human_size(info.get_size()), when(stamp), kind,
            ("0" if is_dir else "1") + name.lower(), small,
            float(stamp), 0.0 if is_dir or kind == MAC_APP else float(info.get_size()),
            self._markup(name, names, full, is_dir, info),
        ])
        content = info.get_content_type() or ""
        if own is None and not is_dir and (content.startswith("image/") or Gio.content_type_is_a(content, "application/pdf")) \
                and info.get_size() < THUMB_LARGEST:
            self.waiting.append((Gtk.TreeRowReference.new(self.store, self.store.get_path(it)), full, stamp))
        return names

    def _add_apps(self):
        """Every installed app, as its own icon, in Applications."""
        for name, full, gicon in app_list.installed_apps():
            try:
                stamp = os.stat(full).st_mtime
            except OSError:
                stamp = 0
            gicon = gicon or Gio.ThemedIcon.new("application-x-executable")
            self.store.append([
                self.icon(gicon, self.icon_size), name, full, False, "", when(stamp), APPLICATION,
                "1" + name.lower(), self.icon(gicon, 20), float(stamp), 0.0,
                tags.markup(name, tags.get(full)),
            ])

    def _markup(self, name, names, full, is_dir, info):
        """The name under an icon, with its tags' dots and, with Show Item
        Info, a folder's item count or a picture's size in blue below."""
        markup = tags.markup(name, names)
        if self.item_info and (is_dir or (info.get_content_type() or "").startswith("image/")):
            extra = drawer_info.item_info(full, info.get_content_type())
            if extra:
                markup += f"\n<span size='smaller' foreground='#2f6fd6'>{GLib.markup_escape_text(extra)}</span>"
        return markup

    def _thumbnails(self, waiting):
        """Pictures and PDFs show a small picture of themselves instead of
        their kind's icon, as in Finder, a few at a time so the folder
        shows at once."""
        for _ in range(4):
            if not waiting:
                return False
            ref, path, stamp = waiting.pop(0)
            if not ref.valid():
                continue
            big = self.thumbnail(path, stamp, self.icon_size)
            if big is not None:
                small = self.thumbnail(path, stamp, 20)
                if aliases.is_alias(path):
                    big, small = self.with_arrow(big), self.with_arrow(small)
                elif locks.is_locked(path):
                    big, small = self.with_lock(big), self.with_lock(small)
                it = self.store.get_iter(ref.get_path())
                self.store.set(it, {C_ICON: big, C_SMALL: small})
        return bool(waiting)

    @classmethod
    def thumbnail(cls, path, stamp, size):
        key = (path, stamp, size)
        if key not in cls.thumb_cache:
            pixbuf = None
            try:
                if path.lower().endswith(".pdf"):
                    from . import pdf
                    pixbuf = pdf.first_page(path, size * 4)
                    if pixbuf is not None:
                        ratio = size / max(pixbuf.get_width(), pixbuf.get_height())
                        pixbuf = pixbuf.scale_simple(max(1, round(pixbuf.get_width() * ratio)),
                                                     max(1, round(pixbuf.get_height() * ratio)),
                                                     GdkPixbuf.InterpType.BILINEAR)
                        # A thin grey edge, so a white page shows on a white window.
                        framed = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8,
                                                      pixbuf.get_width() + 2, pixbuf.get_height() + 2)
                        framed.fill(0xb4b4b8ff)
                        pixbuf.copy_area(0, 0, pixbuf.get_width(), pixbuf.get_height(), framed, 1, 1)
                        pixbuf = framed
                else:
                    pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, size, size, True)
                    pixbuf = pixbuf.apply_embedded_orientation() or pixbuf
            except GLib.Error:
                pixbuf = None
            if len(cls.thumb_cache) > 2000:
                cls.thumb_cache.clear()
            cls.thumb_cache[key] = pixbuf
        return cls.thumb_cache[key]

    @classmethod
    def app_icon(cls, path, size):
        pixbuf = macapps.cached_icon(path, size)
        return pixbuf or cls.icon(Gio.ThemedIcon.new(macapps.GENERIC_ICON), size)

    @classmethod
    def with_arrow(cls, pixbuf):
        if pixbuf is None:
            return None
        if pixbuf not in cls.badged:
            if len(cls.badged) > 500:
                cls.badged.clear()
            cls.badged[pixbuf] = aliases.badge(pixbuf)
        return cls.badged[pixbuf]

    @classmethod
    def with_lock(cls, pixbuf):
        if pixbuf is None:
            return None
        if pixbuf not in cls.locked:
            if len(cls.locked) > 500:
                cls.locked.clear()
            cls.locked[pixbuf] = locks.badge(pixbuf)
        return cls.locked[pixbuf]

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
    col.add_attribute(text, "markup", C_MARKUP)
    col.set_expand(True)
    col.set_sort_column_id(C_SORT)
    return col


def gallery_pixbuf(path, fallback=None):
    """The chosen file as large as Gallery shows it: a picture or a PDF's
    first page, or else its kind's icon, large."""
    kind, _uncertain = Gio.content_type_guess(path, None)
    try:
        if path.lower().endswith(".pdf"):
            from . import pdf
            page = pdf.first_page(path, 900)
            if page is not None:
                return page
        elif kind and kind.startswith("image/") and os.path.isfile(path):
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, 1600, 1600, True)
            return pixbuf.apply_embedded_orientation() or pixbuf
    except GLib.Error:
        pass
    try:
        info = Gio.File.new_for_path(path).query_info("standard::icon", Gio.FileQueryInfoFlags.NONE, None)
        if macapps.is_bundle(path):
            return Folder.app_icon(path, 256)
        if app_list.is_installed_app(path):
            app = Gio.DesktopAppInfo.new_from_filename(path)
            if app is not None and app.get_icon() is not None:
                return Folder.icon(app.get_icon(), 256) or fallback
        return Folder.icon(info.get_icon(), 256) or fallback
    except GLib.Error:
        return fallback


class GalleryPicture(Gtk.DrawingArea):
    """Gallery's large picture, fitted to the room it has, never past its
    own size."""

    def __init__(self):
        super().__init__(hexpand=True, vexpand=True)
        self.pixbuf, self.cache = None, None
        self.connect("draw", self._draw)

    def show_pixbuf(self, pixbuf):
        self.pixbuf, self.cache = pixbuf, None
        self.queue_draw()

    def _draw(self, widget, cr):
        if self.pixbuf is None:
            return False
        room_w, room_h = widget.get_allocated_width() - 40, widget.get_allocated_height() - 24
        pw, ph = self.pixbuf.get_width(), self.pixbuf.get_height()
        scale = min(room_w / pw, room_h / ph, 1.0)
        w, h = max(1, round(pw * scale)), max(1, round(ph * scale))
        if self.cache is None or (self.cache.get_width(), self.cache.get_height()) != (w, h):
            self.cache = self.pixbuf.scale_simple(w, h, GdkPixbuf.InterpType.BILINEAR)
        Gdk.cairo_set_source_pixbuf(cr, self.cache, (widget.get_allocated_width() - w) / 2,
                                    (widget.get_allocated_height() - h) / 2)
        cr.paint()
        return False


class DrawerWindow(Gtk.ApplicationWindow):
    dragging = None       # the files being dragged out of a Drawer window, while they are

    def __init__(self, app, path):
        super().__init__(application=app, title="Drawer")
        self.set_default_size(980, 600)
        self.history, self.future = [], []
        self.path = None
        self.view_mode = "icons"
        self.show_hidden = False
        self.filter_text = ""
        # Searching: the folder a search began in, the Smart Folder being
        # changed, and a search waiting for the typing to pause.
        self.search_from, self.editing_smart, self.search_soon, self.quiet = None, None, 0, False
        self.tabs = []        # one dict per tab; the open tab's state lives on self
        self.current = 0
        self.glance = None
        self.monitor, self.watched, self.soon, self.told_at = None, None, 0, 0
        config = load_config()
        self.sort = config.get("sort") if config.get("sort") in dict(SORTS) else "name"
        self.path_bar_shown = bool(config.get("path_bar", False))
        self.status_shown = bool(config.get("status_bar", True))
        self.sidebar_shown = bool(config.get("sidebar", True))
        self.preview_shown = bool(config.get("preview", False))
        size = config.get("icon_size", 48)
        self.icon_size = min(128, max(32, int(size) // 8 * 8)) if isinstance(size, (int, float)) else 48
        spacing = config.get("grid_spacing", 6)
        self.grid_spacing = min(40, max(0, int(spacing))) if isinstance(spacing, (int, float)) else 6
        self.text_size = config.get("text_size") if config.get("text_size") in TEXT_SIZES else None
        self.item_info_shown = bool(config.get("item_info", False))
        FOLDER_SIZES[0] = bool(config.get("calculate_sizes", False))
        RELATIVE_DATES[0] = bool(config.get("relative_dates", True))
        self.hidden_columns = {c for c in config.get("hidden_columns", []) if isinstance(c, str)}
        self.view_options = None
        self.text_css = Gtk.CssProvider()
        # View Options > Background: one provider behind the icons, one on them.
        self.bg_css, self.bg_icon_css, self.bg_shown = Gtk.CssProvider(), Gtk.CssProvider(), None
        self.bg_widgets = None

        header = Gtk.HeaderBar(show_close_button=True)
        self.set_titlebar(header)
        nav = Gtk.Box(spacing=0)
        nav.get_style_context().add_class("linked")
        self.back = self._button("go-previous-symbolic", "Back", lambda *_: self._history_click(True))
        self.forward = self._button("go-next-symbolic", "Forward", lambda *_: self._history_click(False))
        # Hold the button down, or right-click it, for the folders it goes
        # back (or forward) through, as on a Mac.
        self._history_popped, self._history_hold = False, None
        for button, back in ((self.back, True), (self.forward, False)):
            button.connect("button-press-event", self._history_press, back)
            button.connect("button-release-event", self._history_release)
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
        self.search = Gtk.SearchEntry(placeholder_text="Search", width_chars=16)
        self.search.connect("search-changed", self._filter_changed)
        header.pack_end(self.search)
        header.pack_end(views)
        self.share_button = share.button(self, self.selected_paths, self.notify)
        header.pack_end(self.share_button)
        header.pack_end(self._button("folder-new-symbolic", "New Folder", lambda *_: self.new_folder()))

        paned = Gtk.Paned()
        self.add(paned)
        # The sidebar scrolls when its places, Smart Folders and tags don't fit.
        self.side = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, propagate_natural_width=True)
        self.side.add(self._sidebar())
        self.side.get_child().set_shadow_type(Gtk.ShadowType.NONE)
        self.side.set_no_show_all(not self.sidebar_shown)
        paned.pack1(self.side, False, False)
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.tab_bar = Gtk.Box(spacing=4, homogeneous=True)
        self.tab_bar.get_style_context().add_class("drawer-tabs")
        self.tab_bar.set_no_show_all(True)
        right.pack_start(self.tab_bar, False, False, 0)
        right.pack_start(self._trash_bar(), False, False, 0)
        right.pack_start(self._scope_bar(), False, False, 0)
        self.content = Gtk.Stack(transition_type=Gtk.StackTransitionType.NONE)
        middle = Gtk.Box()
        middle.pack_start(self.content, True, True, 0)
        self.preview = self._build_preview()
        middle.pack_end(self.preview, False, False, 0)
        right.pack_start(middle, True, True, 0)
        self.path_bar = Gtk.Box(spacing=0)
        self.path_bar.get_style_context().add_class("drawer-pathbar")
        self.path_bar.set_no_show_all(True)
        right.pack_start(self.path_bar, False, False, 0)
        # The status bar: how many items, how many are chosen, and the space
        # left on the disk, as at the foot of a Finder window (View > Show
        # Status Bar, ⌘/).
        self.status = Gtk.Label(xalign=0.5, ellipsize=Pango.EllipsizeMode.MIDDLE)
        self.status.get_style_context().add_class("drawer-status")
        self.status.set_no_show_all(not self.status_shown)
        right.pack_start(self.status, False, False, 0)
        paned.pack2(right, True, False)
        paned.set_position(190)

        self._build_icon_view()
        self._build_list_view()
        self._build_column_view()
        self._build_gallery_view()
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
        self.tabs.append({"path": self._real(path or self.path), "history": [], "future": [],
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
        if path and path.startswith(tags.PREFIX):
            return path[len(tags.PREFIX):]
        if path == recents.PLACE:
            return "Recents"
        if neighbours.is_place(path):
            return neighbours.title(path)
        if smart_folders.is_place(path):
            return smart_folders.title(path)
        if path and os.path.realpath(path) == os.path.realpath(TRASH):
            return "Trash"
        return servers.title_of(path) or os.path.basename(path) or "Computer"

    # ---- Glance (Space) -------------------------------------------------
    def toggle_glance(self):
        if self.glance and self.glance.get_visible():
            self.glance.hide()
            return
        paths = self.selected_paths()
        if not paths:
            return
        if self.glance is None:
            self.glance = Glance(self, lambda p: (self.glance.hide(), self.open_or_enter(p)),
                                 on_arrow=self._glance_arrow)
        self.glance.show_paths(paths)

    def _glance_arrow(self, key):
        """An arrow pressed in Glance moves the selection here, as in Finder."""
        across = key in (Gdk.KEY_Left, Gdk.KEY_Right)
        step = Gtk.MovementStep.VISUAL_POSITIONS if across else Gtk.MovementStep.DISPLAY_LINES
        count = -1 if key in (Gdk.KEY_Left, Gdk.KEY_Up) else 1
        if self.view_mode in ICONISH:
            self.icon_view.emit("move-cursor", step, count)
        elif self.view_mode == "list" and not across:
            self.list_view.emit("move-cursor", step, count)

    def _status_text(self):
        folder = getattr(self, "folder", None)
        if folder is not None and folder.error:
            return folder.error
        model = None
        if self.view_mode == "columns" and not self.in_virtual() and self.columns_box.get_children():
            model = self.columns_box.get_children()[-1].view.get_model()
        elif folder is not None:
            model = self.icon_view.get_model()
        count = len(model) if model is not None else 0
        if neighbours.is_place(self.path) and not count:
            if folder is not None and folder.browsing:
                return "Looking\u2026"
            return ("No shared computers found on this network" if self.path == neighbours.PLACE
                    else "This computer shares no folders you can open")
        if self.in_search() and folder is not None and not folder.error:
            query = smart_folders.query_of(self.path)
            if smart_folders.is_empty(query):
                return "Type a name, or choose a kind or a time"
            if folder.browsing:
                return f"Searching\u2026 {count} found" if count else "Searching\u2026"
            if not count:
                return smart_folders.describe(query, lead="No")
        chosen = len(self.selected_paths())
        text = f"{chosen} of {count} selected" if chosen else f"{count} item{'s' if count != 1 else ''}"
        if not self.in_virtual() and self.path:
            try:
                disk = os.statvfs(self.path)
                text += f", {GLib.format_size(disk.f_bavail * disk.f_frsize)} available"
            except OSError:
                pass
        return text

    def _show_status(self, *_args):
        """The counts and free space, unless a message was just shown there."""
        if time.monotonic() - self.told_at >= 4:
            self.status.set_text(self._status_text())
        return False

    def _set_status_bar(self, shown):
        self.status_shown = shown
        save_setting("status_bar", shown)
        self.status.set_visible(shown)

    def _set_sidebar(self, shown):
        self.sidebar_shown = shown
        save_setting("sidebar", shown)
        self.side.set_no_show_all(False)
        self.side.set_visible(shown)
        if shown:
            self.side.show_all()

    def _selection_changed(self, *_args):
        if drawer_info.INSPECTOR[0] is not None:
            chosen = self.selected_paths()
            drawer_info.inspect(chosen[0] if chosen else self.path)
        self._show_status()
        self._show_gallery()
        self._show_preview()
        if self.glance and self.glance.get_visible():
            paths = self.selected_paths()
            if paths and paths != self.glance.paths:
                self.glance.show_paths(paths)
                self.present()   # keep the keys going to the file list

    # ---- dragging files out ---------------------------------------------
    def _drag_get(self, _widget, _context, data, _info, _time):
        # The files picked up when the drag began: a spring-loaded folder may
        # have opened since, leaving nothing chosen in the window.
        paths = DrawerWindow.dragging or self.selected_paths()
        data.set_uris([Gio.File.new_for_path(p).get_uri() for p in paths])

    def _drag_source(self, widget):
        widget.connect("drag-data-get", self._drag_get)
        widget.connect("drag-begin", lambda *_: setattr(DrawerWindow, "dragging", self.selected_paths()))
        widget.connect("drag-end", lambda *_: setattr(DrawerWindow, "dragging", None))

    # ---- dropping files in ----------------------------------------------
    def _accept_drops(self, widget, find):
        """widget takes dropped files. find(x, y) says where they would go:
        (folder, light) with light(on) showing the place, or None."""
        widget.drag_dest_set(0, URI_TARGETS, Gdk.DragAction.COPY | Gdk.DragAction.MOVE | Gdk.DragAction.LINK)
        lit = {"light": None}
        spring = {"folder": None, "timer": 0}

        def unspring():
            if spring["timer"]:
                GLib.source_remove(spring["timer"])
            spring.update(folder=None, timer=0)

        def sprung(folder):
            # Spring-loaded folders: files held over a folder for a moment
            # open it, so they can be dropped further in, as in Finder.
            spring.update(folder=None, timer=0)
            light(None)
            if os.path.isdir(folder) and folder != self.path:
                self.navigate(folder)
            return False

        def wait_on(folder):
            if folder == spring["folder"]:
                return
            unspring()
            if folder and folder != self.path and os.path.isdir(folder):
                spring.update(folder=folder, timer=GLib.timeout_add(SPRING_DELAY, sprung, folder))

        def light(show):
            if lit["light"] is not None and lit["light"] is not show:
                lit["light"](False)
            lit["light"] = show
            if show is not None:
                show(True)

        def motion(_w, context, x, y, time):
            found = find(x, y)
            action = self._drop_action(found[0]) if found else 0
            light(found[1] if found and action else None)
            wait_on(found[0] if found and action else None)
            Gdk.drag_status(context, action, time)
            return True

        def drop(_w, context, _x, _y, time):
            widget.drag_get_data(context, Gdk.Atom.intern("text/uri-list", False), time)
            return True

        def received(_w, context, x, y, data, _info, time):
            light(None)
            unspring()
            found = find(x, y)
            paths = [Gio.File.new_for_uri(u).get_path() for u in data.get_uris() or []]
            paths = [p for p in paths if p]
            # Never let the source delete anything: a move is done here.
            Gtk.drag_finish(context, bool(found and paths), False, time)
            if found and paths:
                GLib.idle_add(lambda: self._dropped(paths, found[0]) and False)

        widget.connect("drag-motion", motion)
        widget.connect("drag-leave", lambda *_: (light(None), unspring()))
        widget.connect("drag-drop", drop)
        widget.connect("drag-data-received", received)

    def _alt_held(self):
        window, seat = self.get_window(), Gdk.Display.get_default().get_default_seat()
        if window is None or seat is None:
            return False
        mask = window.get_device_position(seat.get_pointer())[3]
        return bool(mask & Gdk.ModifierType.MOD1_MASK)

    def _alias_held(self):
        """⌥⌘ held while dragging: the drop makes aliases, as on a Mac."""
        window, seat = self.get_window(), Gdk.Display.get_default().get_default_seat()
        if window is None or seat is None:
            return False
        mask = window.get_device_position(seat.get_pointer())[3]
        both = Gdk.ModifierType.MOD1_MASK | Gdk.ModifierType.CONTROL_MASK
        return mask & both == both

    def _drop_action(self, folder):
        paths = DrawerWindow.dragging or []
        if folder.startswith(tags.PREFIX):
            return Gdk.DragAction.LINK   # tags them; nothing moves
        if folder == TO_SIDEBAR:
            return Gdk.DragAction.LINK
        if folder == TO_TRASH:
            return Gdk.DragAction.MOVE
        if paths and (folder in paths or all(os.path.dirname(p) == folder for p in paths)):
            return 0     # where they are already
        if paths and self._alias_held():
            return Gdk.DragAction.LINK
        if self._alt_held():
            return Gdk.DragAction.COPY
        if paths and not all(transfer.same_disk(p, folder) for p in paths):
            return Gdk.DragAction.COPY
        return Gdk.DragAction.MOVE

    def _dropped(self, paths, folder):
        if folder.startswith(tags.PREFIX):
            self._tags_changed(tags.toggle(paths, folder[len(tags.PREFIX):], adding=True), [])
        elif folder == TO_SIDEBAR:
            self.add_to_sidebar(paths)
        elif folder == TO_TRASH:
            self.trash(paths)
        elif self._alias_held() and os.path.isdir(folder) and not self.in_trash():
            try:
                made = aliases.make(paths, folder)
            except OSError as err:
                self.notify(f"The alias couldn’t be made ({err.strerror}).")
                return
            if folder == self.path:
                self.refresh()
                GLib.idle_add(lambda: self.select_paths(made) and False)
        elif not all(os.path.dirname(p) == folder for p in paths):
            # A move on the same disk, a copy onto another one; ⌥ copies.
            move = not self._alt_held() and all(transfer.same_disk(p, folder) for p in paths)
            self.run_job(paths, folder, move)

    def _item_target(self, path, is_dir):
        """A folder under the pointer takes the drop, unless it's being dragged."""
        dragged = DrawerWindow.dragging or []
        return is_dir and path not in dragged

    def _find_in_icons(self, x, y):
        found = self.icon_view.get_dest_item_at_pos(x, y)
        model = self.icon_view.get_model()
        if found:
            item = found[0]
            row = model[item]
            if self._item_target(row[C_PATH], row[C_IS_DIR]):
                return row[C_PATH], lambda on: self.icon_view.set_drag_dest_item(
                    item if on else None, Gtk.IconViewDropPosition.DROP_INTO)
        return self.path, lambda on: None

    def _find_in_tree(self, view, folder_of):
        def find(x, y):
            found = view.get_dest_row_at_pos(x, y)
            model = view.get_model()
            if found:
                tree_path = found[0]
                row = model[tree_path]
                if self._item_target(row[C_PATH], row[C_IS_DIR]):
                    return row[C_PATH], lambda on: view.set_drag_dest_row(
                        tree_path if on else None, Gtk.TreeViewDropPosition.INTO_OR_AFTER)
            return folder_of(), lambda on: None
        return find

    def _find_in_sidebar(self, listbox, places_only=False):
        def find(_x, y):
            row = listbox.get_row_at_y(int(y))
            if row is not None and getattr(row, "path", ""):
                if row.path == TRASH:
                    target = TO_TRASH
                elif places_only and getattr(row, "mount", None) is None:
                    return None     # Computer: not a place to drop files
                else:
                    target = row.path
                return target, lambda on: listbox.drag_highlight_row(row) if on else listbox.drag_unhighlight_row()
            if places_only:
                return None
            # Below the rows: add folders to the sidebar.
            return TO_SIDEBAR, lambda on: listbox.drag_highlight() if on else listbox.drag_unhighlight()
        return find

    # ---- copy, paste, duplicate, undo -------------------------------------
    def run_job(self, paths, folder, move=False, duplicate=False):
        def done(job):
            self.refresh()
            self.select_paths([p for p in job.made if os.path.dirname(p) == self.path])
        transfer.Job(paths, folder, move=move, parent=self, done=done, duplicate=duplicate).start()

    def copy(self):
        paths = self.selected_paths()
        if transfer.copy_files(paths):
            one = len(paths) == 1
            self.notify(f"Copied {len(paths)} item{'' if one else 's'}. ⌘V pastes {'it' if one else 'them'} "
                        f"somewhere else, ⌥⌘V moves {'it' if one else 'them'}.")

    def paste(self, move=False):
        if self.in_virtual():
            self.notify("Open a folder to paste into.")
            return
        paths = transfer.pasted_files()
        if not paths:
            self.notify("There are no files to paste. Copy some first with ⌘C.")
            return
        self.run_job(paths, self.path, move=move)

    def duplicate(self):
        paths = self.selected_paths()
        if paths:
            self.run_job(paths, os.path.dirname(paths[0]) if len(set(map(os.path.dirname, paths))) == 1
                         else self.path, duplicate=True)

    def make_alias(self):
        """File > Make Alias: an alias of each selected item, beside it."""
        paths = [p for p in self.selected_paths() if os.path.lexists(p)]
        if not paths or self.in_trash():
            return
        try:
            made = aliases.make(paths)
        except OSError as err:
            self.notify(f"The alias couldn’t be made ({err.strerror}).")
            return
        self.refresh()
        GLib.idle_add(lambda: self.select_paths(made) and False)

    def show_original(self):
        """File > Show Original: the folder the alias's original is in, with
        it chosen."""
        alias = next((p for p in self.selected_paths() if aliases.is_alias(p)), None)
        if alias is None:
            return
        found = aliases.original(alias) or aliases.ask_broken(self, alias)
        if not found:
            self.refresh()
            return
        self.navigate(os.path.dirname(found))
        GLib.idle_add(lambda: self.select_paths([found]) and False)

    def undo(self):
        def told(text):
            self.refresh()
            self.notify(text)
        if not transfer.undo_last(self, told):
            self.notify("There’s nothing to undo.")

    def select_paths(self, paths):
        """Select these files in the view, the first one scrolled into view."""
        wanted = set(paths)
        if not wanted:
            return
        if self.view_mode in ICONISH:
            model = self.icon_view.get_model()
            self.icon_view.unselect_all()
            first = None
            for row in model:
                if row[C_PATH] in wanted:
                    self.icon_view.select_path(row.path)
                    first = first or row.path
            if first is not None:
                self.icon_view.scroll_to_path(first, False, 0, 0)
        elif self.view_mode == "list":
            selection = self.list_view.get_selection()
            selection.unselect_all()
            first = None
            for row in self.list_view.get_model():
                if row[C_PATH] in wanted:
                    selection.select_path(row.path)
                    first = first or row.path
            if first is not None:
                self.list_view.scroll_to_cell(first, None, False, 0, 0)

    # ---- keeping up with changes made elsewhere ---------------------------
    def _watch(self):
        if self.watched == self.path:
            return
        if self.monitor is not None:
            self.monitor.cancel()
            self.monitor = None
        self.watched = self.path
        if neighbours.is_place(self.path):
            self.monitor = neighbours.watch(self._changed_soon, neighbours.uri_of(self.path))
            return
        if self.in_virtual():
            return   # files from all over; changed tags refresh it themselves
        try:
            self.monitor = Gio.File.new_for_path(self.path).monitor_directory(
                Gio.FileMonitorFlags.WATCH_MOVES, None)
        except GLib.Error:
            return
        self.monitor.connect("changed", lambda *_: self._changed_soon())

    def _changed_soon(self):
        if not self.soon:
            self.soon = GLib.timeout_add(300, self._changed)

    def _changed(self):
        self.soon = 0
        if self.view_mode == "columns" or not self.get_visible():
            return False
        keep, told = self.selected_paths(), self.status.get_text()
        self.refresh()
        self.select_paths(keep)
        if time.monotonic() - self.told_at < 4:
            self.status.set_text(told)
        return False

    def _add_actions(self):
        """The window's actions, for the menu bar."""
        menus.add_actions(self, {
            "share": lambda: share.popup(self, self.selected_paths(), self.share_button, self.notify),
            "new-folder": self.new_folder,
            "open": lambda: [self.open_or_enter(p) for p in self.selected_paths()],
            "rename": self.rename,
            "trash": self.trash,
            "close": self.close,
            "select-all": self.select_all,
            "filter": self.find,
            "new-smart-folder": self.new_smart_folder,
            "save-search": self.save_search,
            "back": self.go_back,
            "forward": self.go_forward,
            "up": self.go_up,
            "view-icons": lambda: self.view_buttons["icons"].set_active(True),
            "view-list": lambda: self.view_buttons["list"].set_active(True),
            "view-columns": lambda: self.view_buttons["columns"].set_active(True),
            "view-gallery": lambda: self.view_buttons["gallery"].set_active(True),
            "new-tab": self.new_tab,
            "close-tab": self.close_tab,
            "next-tab": lambda: self.switch_tab((self.current + 1) % len(self.tabs)),
            "previous-tab": lambda: self.switch_tab((self.current - 1) % len(self.tabs)),
            "glance": self.toggle_glance,
            "add-to-sidebar": self.add_to_sidebar,
            "compress": self.compress,
            "get-info": self.get_info,
            "show-inspector": self.show_inspector,
            "summary-info": self.summary_info,
            "show-clipboard": lambda: drawer_clipboard.show(self),
            "copy-pathname": self.copy_pathname,
            "eject": self.eject,
            "copy": self.copy,
            "paste": self.paste,
            "move-here": lambda: self.paste(move=True),
            "duplicate": self.duplicate,
            "make-alias": self.make_alias,
            "show-original": self.show_original,
            "undo": self.undo,
            "browse-backups": self.browse_backups,
            "put-back": self.put_back,
            "go-to-folder": self.go_to_folder,
            "connect-to-server": self.connect_to_server,
            "go-network": lambda: self.navigate(neighbours.PLACE),
            "go-recents": lambda: self.navigate(recents.PLACE),
            "new-folder-with": self.new_folder_with,
            "show-enclosing": self.show_enclosing,
            "view-options": self.show_view_options,
        })
        # Go > Recent Folders: each item opens its folder in this window.
        recent = Gio.SimpleAction.new("go-recent", GLib.VariantType.new("s"))
        recent.connect("activate", lambda _a, value: self.navigate(value.get_string()))
        self.add_action(recent)
        for name, path in (("go-home", GLib.get_home_dir()),
                           ("go-documents", GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOCUMENTS)),
                           ("go-downloads", GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD)),
                           ("go-desktop", GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DESKTOP)),
                           ("go-computer", "/"), ("go-applications", applications_folder())):
            menus.add_actions(self, {name: lambda p=path or GLib.get_home_dir(): self.navigate(p)})
        self.hidden_action = menus.add_toggle(self, "show-hidden", False, self._set_hidden)
        self.path_bar_action = menus.add_toggle(self, "path-bar", self.path_bar_shown, self._set_path_bar)
        self.status_bar_action = menus.add_toggle(self, "status-bar", self.status_shown, self._set_status_bar)
        self.sidebar_action = menus.add_toggle(self, "sidebar", self.sidebar_shown, self._set_sidebar)
        self.preview_action = menus.add_toggle(self, "preview", self.preview_shown, self._set_preview)
        # View › Sort By: one choice of four, kept for every window.
        self.sort_action = Gio.SimpleAction.new_stateful("sort-by", GLib.VariantType.new("s"),
                                                         GLib.Variant("s", self.sort))
        self.sort_action.connect("change-state", lambda act, value: (act.set_state(value),
                                                                    self.set_sort(value.get_string())))
        self.add_action(self.sort_action)

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

        heading = Gtk.Label(label="Favorites", xalign=0)
        heading.get_style_context().add_class("drawer-heading")
        box.pack_start(heading, False, False, 0)
        self.recent_list = Gtk.ListBox(can_focus=False)
        self.recent_list.get_style_context().add_class("drawer-sidebar")
        self.recent_list.connect("row-activated", lambda _l, row: self.navigate(row.path))
        row = Gtk.ListBoxRow(can_focus=False)
        row.path, row.mount = recents.PLACE, "recents"
        line = Gtk.Box(spacing=8)
        line.pack_start(Gtk.Image.new_from_icon_name("document-open-recent-symbolic", Gtk.IconSize.MENU),
                        False, False, 0)
        line.pack_start(Gtk.Label(label="Recents", xalign=0), True, True, 0)
        row.add(line)
        self.recent_list.add(row)
        self.place_rows.append((self.recent_list, row))
        box.pack_start(self.recent_list, False, False, 0)
        self.fav_list = Gtk.ListBox(can_focus=False)
        self.fav_list.get_style_context().add_class("drawer-sidebar")
        self.fav_list.connect("row-activated", lambda _l, row: self.navigate(row.path))
        self.fav_list.connect("button-press-event", self._sidebar_button)
        # Drop files on a place to move them there, or folders below the
        # places to add them.
        self._accept_drops(self.fav_list, self._find_in_sidebar(self.fav_list))
        box.pack_start(self.fav_list, False, False, 0)
        self._fill_favourites()
        self.smart_heading = Gtk.Label(label="Smart Folders", xalign=0, no_show_all=True)
        self.smart_heading.get_style_context().add_class("drawer-heading")
        box.pack_start(self.smart_heading, False, False, 0)
        self.smart_list = Gtk.ListBox(can_focus=False, no_show_all=True)
        self.smart_list.get_style_context().add_class("drawer-sidebar")
        self.smart_list.connect("row-activated", lambda _l, row: self.navigate(row.path))
        self.smart_list.connect("button-press-event", self._smart_button)
        box.pack_start(self.smart_list, False, False, 0)
        self._fill_smart()
        heading = Gtk.Label(label="Locations", xalign=0)
        heading.get_style_context().add_class("drawer-heading")
        box.pack_start(heading, False, False, 0)
        self.loc_list = Gtk.ListBox(can_focus=False)
        self.loc_list.get_style_context().add_class("drawer-sidebar")
        self.loc_list.connect("row-activated", lambda _l, row: self._open_location(row))
        self.loc_list.connect("button-press-event", self._location_button)
        self._accept_drops(self.loc_list, self._find_in_sidebar(self.loc_list, places_only=True))
        box.pack_start(self.loc_list, False, False, 0)
        self._fill_locations()
        heading = Gtk.Label(label="Tags", xalign=0)
        heading.get_style_context().add_class("drawer-heading")
        box.pack_start(heading, False, False, 0)
        self.tag_list = Gtk.ListBox(can_focus=False)
        self.tag_list.get_style_context().add_class("drawer-sidebar")
        self.tag_list.connect("row-activated", lambda _l, row: self.navigate(row.path))
        # Drop files on a tag to give them that tag.
        self._accept_drops(self.tag_list, self._find_in_sidebar(self.tag_list, places_only=True))
        box.pack_start(self.tag_list, False, False, 0)
        self._fill_tags()
        # Drives come and go: the list follows, and a window on a drive that
        # went away goes back to the home folder.
        handlers = volumes.watch(self._drives_changed)
        self.connect("destroy", lambda *_: [volumes.monitor().disconnect(h) for h in handlers])
        return box

    def _fill_locations(self):
        """Computer, each drive and connected server with its Eject button,
        then the Trash."""
        self.place_rows = [(lb, row) for lb, row in self.place_rows if lb is not self.loc_list]
        for child in self.loc_list.get_children():
            self.loc_list.remove(child)
        trash = TRASH
        entries = [("Computer", "/", Gio.ThemedIcon.new("drive-harddisk-symbolic"), None),
                   ("Network", neighbours.PLACE, Gio.ThemedIcon.new("network-workgroup-symbolic"), None)]
        for mount in volumes.drives():
            entries.append((mount.get_name(), volumes.path_of(mount), mount.get_symbolic_icon(), mount))
        for mount in servers.servers():
            entries.append((servers.title(mount), volumes.path_of(mount),
                            Gio.ThemedIcon.new("network-server-symbolic"), mount))
        entries.append(("Trash", trash, Gio.ThemedIcon.new("user-trash-symbolic"), None))
        for name, path, icon, mount in entries:
            row = Gtk.ListBoxRow(can_focus=False)
            row.path, row.mount = path or "", mount
            line = Gtk.Box(spacing=8)
            line.pack_start(Gtk.Image.new_from_gicon(icon, Gtk.IconSize.MENU), False, False, 0)
            line.pack_start(Gtk.Label(label=name, xalign=0, ellipsize=Pango.EllipsizeMode.END), True, True, 0)
            if mount is not None and (mount.can_eject() or mount.can_unmount()):
                eject = Gtk.Button(relief=Gtk.ReliefStyle.NONE, can_focus=False, tooltip_text=f"Eject “{name}”")
                eject.add(Gtk.Image.new_from_icon_name("media-eject-symbolic", Gtk.IconSize.MENU))
                eject.get_style_context().add_class("drawer-eject")
                eject.connect("clicked", lambda _b, m=mount: self.eject(m))
                line.pack_end(eject, False, False, 0)
            row.add(line)
            self.loc_list.add(row)
            if path:
                self.place_rows.append((self.loc_list, row))
        self.loc_list.show_all()

    def _fill_tags(self):
        """The seven colours, then any other tags in use."""
        self.place_rows = [(lb, row) for lb, row in self.place_rows if lb is not self.tag_list]
        for child in self.tag_list.get_children():
            self.tag_list.remove(child)
        for name in [n for n, _c in tags.COLORS] + tags.used():
            row = Gtk.ListBoxRow(can_focus=False)
            row.path, row.mount = tags.PREFIX + name, "tag"
            line = Gtk.Box(spacing=6)
            line.pack_start(tags.dot(tags.COLOR.get(name, "#9a9aa0"), 11), False, False, 1)
            line.pack_start(Gtk.Label(label=name, xalign=0, ellipsize=Pango.EllipsizeMode.END), True, True, 0)
            row.add(line)
            self.tag_list.add(row)
            self.place_rows.append((self.tag_list, row))
        self.tag_list.show_all()

    def in_tag(self):
        return bool(self.path) and self.path.startswith(tags.PREFIX)

    def in_virtual(self):
        """A tag or Recents: files gathered from all over, not one folder."""
        return (self.in_tag() or self.path == recents.PLACE or neighbours.is_place(self.path)
                or self.in_search())

    def in_search(self):
        """A search, or a Smart Folder."""
        return smart_folders.is_place(self.path)

    def _tags_changed(self, error, keep):
        if error is not None:
            self.notify("This disk can’t keep tags." if error.errno in (1, 95) else
                        f"Couldn’t change the tags: {error.strerror}.")
        if len(tags.used()) + len(tags.COLORS) != len(self.tag_list.get_children()):
            self._fill_tags()
        self.refresh()
        self.select_paths(keep)

    def _open_location(self, row):
        if row.path:
            self.navigate(row.path)
        else:   # a phone with no folder of its own: let the system open it
            Gio.AppInfo.launch_default_for_uri_async(row.mount.get_root().get_uri(), None, None, None, None)

    def _drives_changed(self):
        self._fill_locations()
        if self.path and self.path != "/" and not os.path.isdir(self.path):
            self.history.clear()
            self.future.clear()
            self.navigate(GLib.get_home_dir(), remember=False)
        else:
            self._show_place()

    def eject(self, mount=None):
        """Eject a drive: the one given, else the one the window is showing."""
        mount = mount or volumes.mount_of(self.path) or servers.mount_of(self.path)
        if mount is not None:
            volumes.eject(mount, self)

    def _location_button(self, listbox, event):
        if event.button != 3:
            return False
        row = listbox.get_row_at_y(int(event.y))
        if row is None or row.mount is None:
            return True
        menu = Gtk.Menu()
        menu.attach_to_widget(listbox, None)
        for label, action in (("Open", lambda: self._open_location(row)),
                              (None, None),
                              (f"Eject “{row.mount.get_name()}”", lambda: self.eject(row.mount))):
            item = Gtk.SeparatorMenuItem() if label is None else Gtk.MenuItem(label=label)
            if label is not None:
                item.connect("activate", lambda _i, a=action: a())
            menu.append(item)
        menu.show_all()
        menu.popup_at_pointer(event)
        self._location_menu = menu
        return True

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
        # A search shows what it found; the box's words aren't a filter there.
        model.set_visible_func(lambda m, it, _d: not self.filter_text or self.in_search()
                               or self.filter_text in m[it][C_NAME].lower())
        return model

    def _build_icon_view(self):
        self.icon_view = Gtk.IconView(item_width=96, margin=12, column_spacing=6, row_spacing=6)
        self.icon_view.set_pixbuf_column(C_ICON)
        self.icon_view.set_markup_column(C_MARKUP)   # the name, with its tags' dots
        self.icon_view.set_selection_mode(Gtk.SelectionMode.MULTIPLE)
        self.icon_view.get_style_context().add_provider(self.text_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self._apply_text_size()
        self.icon_view.connect("item-activated", lambda v, p: self._activate(v.get_model(), p))
        self.icon_view.connect("button-press-event", self._icon_button)
        self.icon_view.connect("selection-changed", self._selection_changed)
        self.icon_view.enable_model_drag_source(Gdk.ModifierType.BUTTON1_MASK, URI_TARGETS,
                                                Gdk.DragAction.COPY | Gdk.DragAction.MOVE)
        self._drag_source(self.icon_view)
        self._accept_drops(self.icon_view, self._find_in_icons)
        self.icon_view.get_style_context().add_provider(self.bg_icon_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        scroll = Gtk.ScrolledWindow()
        scroll.get_style_context().add_provider(self.bg_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        scroll.add(self.icon_view)
        self.content.add_named(scroll, "icons")

    def _build_list_view(self):
        self.list_view = Gtk.TreeView(headers_visible=True, enable_search=False)
        self.list_view.get_style_context().add_provider(self.text_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.list_view.append_column(name_column())
        self.list_columns = {}
        for title, col, by in (("Modified", C_MODIFIED, C_STAMP), ("Size", C_SIZE, C_BYTES), ("Kind", C_KIND, C_KIND)):
            renderer = Gtk.CellRendererText(ellipsize=Pango.EllipsizeMode.END)
            renderer.set_property("foreground-rgba", Gdk.RGBA(0.45, 0.45, 0.5, 1))
            column = Gtk.TreeViewColumn(title, renderer, text=col)
            column.set_min_width(110)
            if col == C_MODIFIED:
                column.set_min_width(date_width())
            column.set_sort_column_id(by)   # a click on the heading sorts by it
            column.set_visible(title.lower() not in self.hidden_columns)
            self.list_columns[title.lower()] = column
            self.list_view.append_column(column)
        self.list_view.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE)
        self.list_view.connect("row-activated", lambda v, p, _c: self._activate(v.get_model(), p))
        self.list_view.connect("button-press-event", self._tree_button)
        self.list_view.get_selection().connect("changed", self._selection_changed)
        self.list_view.enable_model_drag_source(Gdk.ModifierType.BUTTON1_MASK, URI_TARGETS,
                                                Gdk.DragAction.COPY | Gdk.DragAction.MOVE)
        self._drag_source(self.list_view)
        self._accept_drops(self.list_view, self._find_in_tree(self.list_view, lambda: self.path))
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.list_view)
        self.content.add_named(scroll, "list")

    def _build_column_view(self):
        self.columns_box = Gtk.Box()
        self.column_scroll = Gtk.ScrolledWindow(vscrollbar_policy=Gtk.PolicyType.NEVER)
        self.column_scroll.add(self.columns_box)
        self.column_paths = []
        self.content.add_named(self.column_scroll, "columns")

    # ---- the preview pane ----------------------------------------------------
    def _build_preview(self):
        """View > Show Preview (⇧⌘P): the chosen file large at the window's
        right, with its name, kind and size, and what is known about it, as
        Finder's preview pane shows. Gallery has its own, below the file."""
        pane = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        pane.get_style_context().add_class("drawer-preview")
        pane.set_size_request(250, -1)
        self.preview_picture = GalleryPicture()
        self.preview_picture.set_size_request(-1, 220)
        self.preview_picture.set_vexpand(False)
        pane.pack_start(self.preview_picture, False, False, 0)
        self.preview_name = Gtk.Label(xalign=0, wrap=True, max_width_chars=26)
        self.preview_name.get_style_context().add_class("drawer-gallery-name")
        pane.pack_start(self.preview_name, False, False, 0)
        self.preview_kind = Gtk.Label(xalign=0, wrap=True, max_width_chars=30)
        self.preview_kind.get_style_context().add_class("dim-label")
        pane.pack_start(self.preview_kind, False, False, 0)
        self.preview_heading = heading = Gtk.Label(label="Information", xalign=0)
        heading.get_style_context().add_class("drawer-preview-heading")
        pane.pack_start(heading, False, False, 6)
        self.preview_facts = Gtk.Grid(column_spacing=10, row_spacing=4)
        pane.pack_start(self.preview_facts, False, False, 0)
        pane.set_no_show_all(True)
        for child in pane.get_children():
            child.show()
        return pane

    def _set_preview(self, shown):
        self.preview_shown = shown
        save_setting("preview", shown)
        self._show_preview()

    def _show_preview(self):
        shown = self.preview_shown and self.view_mode != "gallery"
        self.preview.set_visible(shown)
        if not shown:
            return
        chosen = self.selected_paths()
        path = chosen[0] if len(chosen) == 1 else (None if chosen else self.path)
        for child in self.preview_facts.get_children():
            self.preview_facts.remove(child)
        self.preview_heading.set_visible(bool(path) and not (self.in_virtual() and path == self.path))
        if not path or self.in_virtual() and path == self.path:
            self.preview_picture.show_pixbuf(None)
            self.preview_name.set_text(f"{len(chosen)} items" if chosen else self._label(self.path or ""))
            self.preview_kind.set_text("")
            return
        name = macapps.display_name(path) if macapps.is_bundle(path) else os.path.basename(path) or path
        self.preview_name.set_text(name)
        self.preview_picture.show_pixbuf(gallery_pixbuf(path))
        try:
            info = os.stat(path)
        except OSError:
            self.preview_kind.set_text("")
            return
        kind, _uncertain = Gio.content_type_guess(path, None)
        is_dir = os.path.isdir(path) and not macapps.is_bundle(path)
        described = "Folder" if is_dir else Gio.content_type_get_description(kind or "")
        self.preview_kind.set_text(described if is_dir else f"{described} \u2014 {human_size(info.st_size)}")
        facts = [("Created", when(getattr(info, "st_birthtime", 0) or info.st_ctime)),
                 ("Modified", when(info.st_mtime))]
        if is_dir:
            try:
                count = sum(1 for n in os.listdir(path) if not n.startswith("."))
                facts.append(("Items", str(count)))
            except OSError:
                pass
        elif kind and kind.startswith("image/"):
            found = GdkPixbuf.Pixbuf.get_file_info(path)
            if found and found[0] is not None and found[1] > 0:
                facts.append(("Dimensions", f"{found[1]} \u00d7 {found[2]}"))
        names = tags.get(path)
        if names:
            facts.append(("Tags", ", ".join(names)))
        for row, (label, value) in enumerate(facts):
            title = Gtk.Label(label=label, xalign=1)
            title.get_style_context().add_class("dim-label")
            self.preview_facts.attach(title, 0, row, 1, 1)
            self.preview_facts.attach(Gtk.Label(label=value, xalign=0, selectable=True), 1, row, 1, 1)
        self.preview_facts.show_all()

    # ---- gallery view -----------------------------------------------------
    def _build_gallery_view(self):
        """Finder's Gallery: the chosen file large, with its name and kind,
        over a strip of every file in the folder. The strip is the icon view
        itself, moved in and laid out in one row, so choosing, opening and
        dragging work as they do with icons."""
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        page.get_style_context().add_class("drawer-gallery")
        self.gallery_picture = GalleryPicture()
        page.pack_start(self.gallery_picture, True, True, 0)
        self.gallery_name = Gtk.Label(xalign=0.5, ellipsize=Pango.EllipsizeMode.MIDDLE)
        self.gallery_name.get_style_context().add_class("drawer-gallery-name")
        page.pack_start(self.gallery_name, False, False, 0)
        self.gallery_kind = Gtk.Label(xalign=0.5, ellipsize=Pango.EllipsizeMode.END)
        self.gallery_kind.get_style_context().add_class("drawer-status")
        page.pack_start(self.gallery_kind, False, False, 0)
        self.gallery_strip = Gtk.ScrolledWindow(vscrollbar_policy=Gtk.PolicyType.NEVER)
        self.gallery_strip.set_size_request(-1, 104)
        page.pack_start(self.gallery_strip, False, False, 0)
        self.content.add_named(page, "gallery")

    def _place_icon_view(self):
        """Put the icon view where the current view needs it."""
        gallery = self.view_mode == "gallery"
        home = self.gallery_strip if gallery else self.content.get_child_by_name("icons")
        if self.icon_view.get_parent() is not home:
            self.icon_view.get_parent().remove(self.icon_view)
            home.add(self.icon_view)
            self.icon_view.show()
        if gallery:
            self.icon_view.set_markup_column(-1)
            self.icon_view.set_item_width(64)
            self.icon_view.set_margin(6)
            self.icon_view.set_columns(max(1, len(self.icon_view.get_model() or [])))
        else:
            self.icon_view.set_markup_column(C_MARKUP)
            self.icon_view.set_item_width(max(96, self.icon_size + 40))
            self.icon_view.set_margin(12)
            self.icon_view.set_column_spacing(self.grid_spacing)
            self.icon_view.set_row_spacing(self.grid_spacing)
            self.icon_view.set_columns(-1)
        self._apply_background()

    # ---- View Options > Background ---------------------------------------
    def _background_folder(self):
        """The folder whose background shows, or None where there is none:
        other views, the Trash, searches, tags and the like."""
        if self.view_mode != "icons" or not self.path or self.in_virtual() or self.in_trash():
            return None
        return self.path

    def _apply_background(self):
        folder = self._background_folder()
        setting = drawer_background.of(folder) if folder else dict(drawer_background.WHITE)
        picture = setting.get("picture")
        try:
            stamp = os.stat(picture).st_mtime if picture else None
        except OSError:
            stamp = None
        key = (repr(sorted(setting.items())), stamp)
        if key != self.bg_shown:
            self.bg_shown = key
            behind, icons = drawer_background.styles(setting)
            self.bg_css.load_from_data(behind.encode())
            self.bg_icon_css.load_from_data(icons.encode())
        self._sync_background_panel(folder, setting)

    def _set_background(self, setting):
        folder = self._background_folder()
        if folder is None:
            return
        drawer_background.put(folder, setting)
        self._apply_background()

    def _sync_background_panel(self, folder, setting):
        """Keep the open View Options panel showing this folder's background."""
        if not self.bg_widgets:
            return
        radios, colour, chooser, label = self.bg_widgets
        self.bg_widgets = None   # setting the controls below mustn't save
        for kind, radio in radios.items():
            radio.set_sensitive(folder is not None)
            if kind == setting["kind"]:
                radio.set_active(True)
        colour.set_rgba(drawer_background.parse(setting.get("color") or drawer_background.DEFAULT_COLOR))
        colour.set_sensitive(folder is not None and setting["kind"] == "color")
        chooser.set_sensitive(folder is not None and setting["kind"] == "picture")
        picture = setting.get("picture") if setting["kind"] == "picture" else None
        label.set_text(os.path.basename(picture) if picture else "")
        self.bg_widgets = (radios, colour, chooser, label)

    def _background_row(self, box):
        """The Background choices at the foot of View Options, as on a Mac."""
        heading = Gtk.Label(label="Background:", xalign=0)
        heading.get_style_context().add_class("drawer-preview-heading")
        box.pack_start(heading, False, False, 0)
        radios, group = {}, None
        colour = Gtk.ColorButton(use_alpha=False, title="Background Color")
        chooser = Gtk.Button(label="Choose…")
        label = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.MIDDLE, max_width_chars=16)
        label.get_style_context().add_class("dim-label")
        for kind, title in drawer_background.KINDS:
            radio = Gtk.RadioButton.new_with_label_from_widget(group, title)
            group = group or radio
            radios[kind] = radio
            row = Gtk.Box(spacing=8, margin_start=8)
            row.pack_start(radio, False, False, 0)
            if kind == "color":
                row.pack_end(colour, False, False, 0)
            elif kind == "picture":
                row.pack_end(chooser, False, False, 0)
            box.pack_start(row, False, False, 0)
            if kind == "picture":
                label.set_margin_start(32)
                box.pack_start(label, False, False, 0)

        def current():
            return drawer_background.of(self._background_folder()) if self._background_folder() else {}

        def picked(radio, kind):
            if self.bg_widgets is None or not radio.get_active():
                return
            if kind == "white":
                self._set_background({"kind": "white"})
            elif kind == "color":
                self._set_background({"kind": "color", "color": drawer_background.hex_of(colour.get_rgba())})
            elif current().get("picture"):
                self._set_background(dict(current(), kind="picture"))
            else:
                GLib.idle_add(choose)   # after the click, so the chooser opens in front

        def coloured(button):
            if self.bg_widgets is not None:
                self._set_background({"kind": "color", "color": drawer_background.hex_of(button.get_rgba())})

        def choose(*_):
            if self.bg_widgets is None:
                return
            dialog = Gtk.FileChooserDialog(title="Choose a Picture", transient_for=self.view_options or self,
                                           modal=True, action=Gtk.FileChooserAction.OPEN)
            dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Choose", Gtk.ResponseType.ACCEPT)
            dialog.set_default_response(Gtk.ResponseType.ACCEPT)
            pictures = Gtk.FileFilter()
            pictures.set_name("Pictures")
            pictures.add_pixbuf_formats()
            dialog.add_filter(pictures)
            start = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)
            if start and os.path.isdir(start):
                dialog.set_current_folder(start)
            if dialog.run() == Gtk.ResponseType.ACCEPT and dialog.get_filename():
                self._set_background({"kind": "picture", "picture": dialog.get_filename()})
            else:
                self._apply_background()   # nothing chosen: the panel shows what's kept
            dialog.destroy()
            return False

        for kind, radio in radios.items():
            radio.connect("toggled", picked, kind)
        colour.connect("color-set", coloured)
        chooser.connect("clicked", choose)
        self.bg_widgets = (radios, colour, chooser, label)
        folder = self._background_folder()
        self._sync_background_panel(folder, drawer_background.of(folder) if folder else dict(drawer_background.WHITE))

    def _show_gallery(self):
        if self.view_mode != "gallery":
            return
        chosen = self.selected_paths()
        model = self.icon_view.get_model()
        if not chosen and model is not None and len(model):
            # Gallery always shows something: the first file, as in Finder.
            first = model.get_iter_first()
            self.icon_view.select_path(model.get_path(first))
            return   # selecting calls this again
        if not chosen:
            self.gallery_picture.show_pixbuf(None)
            self.gallery_name.set_text("")
            self.gallery_kind.set_text("")
            return
        path = chosen[0]
        row = next((r for r in model if r[C_PATH] == path), None)
        self.gallery_name.set_text(row[C_NAME] if row else os.path.basename(path))
        kind = row[C_KIND] if row else ""
        size = row[C_SIZE] if row else ""
        self.gallery_kind.set_text(" \u2014 ".join(t for t in (kind, size, row[C_MODIFIED] if row else "") if t))
        self.gallery_picture.show_pixbuf(gallery_pixbuf(path, row[C_ICON] if row else None))
        self.icon_view.scroll_to_path(self.icon_view.get_selected_items()[0], False, 0, 0)

    # ---- navigation -----------------------------------------------------
    @staticmethod
    def _real(path):
        """The path tidied, unless it's a place that isn't a folder."""
        if (path.startswith(tags.PREFIX) or path == recents.PLACE or neighbours.is_place(path)
                or smart_folders.is_place(path)):
            return path
        return os.path.abspath(os.path.expanduser(path))

    def navigate(self, path, remember=True):
        path = self._real(path)
        if remember and self.path and path != self.path:
            self.history.append(self.path)
            self.future.clear()
        self.path = path
        self.refresh()

    # ---- Back and Forward's lists ---------------------------------------
    def _history_click(self, back):
        if self._history_popped:
            self._history_popped = False   # the list was shown instead
            return
        self.go_back() if back else self.go_forward()

    def _history_press(self, button, event, back):
        if event.type != Gdk.EventType.BUTTON_PRESS:
            return False
        if event.button == 3:
            self._history_menu(button, back, event)
            return True
        if event.button == 1:
            # A new press: the list shown last time (whose release may never
            # have reached the button) no longer stands in for a click.
            self._history_popped = False
            self._history_stop()
            self._history_hold = GLib.timeout_add(450, self._history_held, button, back, event.copy())
        return False

    def _history_release(self, *_):
        self._history_stop()
        return False

    def _history_stop(self):
        if self._history_hold:
            GLib.source_remove(self._history_hold)
            self._history_hold = None

    def _history_held(self, button, back, event):
        self._history_hold = None
        if self._history_menu(button, back, event):
            self._history_popped = True
        return False

    def _history_menu(self, button, back, event):
        """The folders Back (or Forward) goes through, nearest first; choosing
        one goes straight there. Returns True if there was a list to show."""
        stack = self.history if back else self.future
        if not stack:
            return False
        # A popover under the button, kept inside the window: a menu popped
        # from the header bar comes out above the window on Wayland.
        popover = Gtk.Popover(relative_to=button, position=Gtk.PositionType.BOTTOM)
        popover.get_style_context().add_class("menu")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        for count, path in enumerate(list(reversed(stack))[:20], 1):
            row = Gtk.Box(spacing=8)
            row.pack_start(Gtk.Image.new_from_icon_name(self._history_icon(path), Gtk.IconSize.MENU),
                           False, False, 0)
            row.pack_start(Gtk.Label(label=self._label(path), xalign=0), True, True, 0)
            item = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
            item.get_style_context().add_class("flat")
            item.add(row)
            item.connect("clicked", lambda _b, n=count: (popover.popdown(), self._history_jump(back, n)))
            box.pack_start(item, False, False, 0)
        popover.add(box)
        popover.connect("closed", lambda p: GLib.idle_add(p.destroy))
        box.show_all()
        popover.popup()
        return True

    def _history_icon(self, path):
        if path == recents.PLACE:
            return "document-open-recent-symbolic"
        if path and path.startswith(tags.PREFIX):
            return "tag-symbolic"
        if neighbours.is_place(path):
            return "network-workgroup-symbolic"
        if smart_folders.is_place(path):
            return "folder-saved-search-symbolic"
        if path == GLib.get_home_dir():
            return "user-home-symbolic"
        return "folder-symbolic"

    def _history_jump(self, back, steps):
        """Go back (or forward) steps folders at once."""
        source, target = (self.history, self.future) if back else (self.future, self.history)
        steps = min(steps, len(source))
        if not steps:
            return
        for _n in range(steps):
            target.append(self.path)
            self.path = source.pop()
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
        label = self._label(self.path)
        self._draw_tabs()
        self.title.set_text(label)
        self.set_title(f"{label} — Drawer")
        self._show_place()
        old = getattr(self, "folder", None)
        if old is not None:
            old.cancel()   # a search still looking is no longer wanted
            if smart_folders.is_place(old.path) and not self.in_search():
                # Out of a search: the box is empty again, not a filter here.
                self.quiet = True
                self.search.set_text("")
                self.quiet = False
                self.filter_text, self.editing_smart = "", None
        if not self.in_virtual() and not self.in_trash():
            self.search_from = self.path   # where “this folder” is, when searching
        self._show_scope()
        folder = Folder(self.path, self.show_hidden, self.sort, self.icon_size, self.item_info_shown)
        self.folder = folder
        if neighbours.is_place(self.path) or self.in_search():
            folder.on_change = lambda: self.folder is folder and self._show_status()
        elif FOLDER_SIZES[0] and self.view_mode == "list" and not self.in_virtual():
            folder.add_up_folders()
        model = self._model(folder)
        self.icon_view.set_model(model)
        self.list_view.set_model(Gtk.TreeModelSort(model=model))
        self._place_icon_view()
        if self.view_mode == "columns" and not self.in_virtual():
            self._reset_columns()
        self._show_status()
        count = len(model)
        # A tag's files come from many folders, so it has no columns: a list.
        self.content.set_visible_child_name("list" if self.in_virtual() and self.view_mode == "columns"
                                            else self.view_mode)
        self._show_gallery()
        self._show_preview()
        in_trash = self.in_trash()
        self.trash_bar.set_visible(in_trash)
        self.empty_button.set_sensitive(in_trash and count > 0)
        self.lookup_action("put-back").set_enabled(in_trash)
        self.lookup_action("new-folder-with").set_enabled(not self.in_virtual() and not in_trash)
        self.lookup_action("show-enclosing").set_enabled(self.in_virtual() and not neighbours.is_place(self.path))
        self._draw_path_bar()
        self._watch()
        if not self.in_virtual() and not in_trash and recent_folders.note(self.path):
            app = self.get_application()
            if app is not None and hasattr(app, "show_recent_folders"):
                app.show_recent_folders()

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
        folder = Folder(path, self.show_hidden, self.sort)
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
        view.enable_model_drag_source(Gdk.ModifierType.BUTTON1_MASK, URI_TARGETS,
                                      Gdk.DragAction.COPY | Gdk.DragAction.MOVE)
        self._drag_source(view)
        self._accept_drops(view, self._find_in_tree(view, lambda: path))
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
        GLib.idle_add(self._show_status)
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
            self._draw_path_bar()
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
        if neighbours.address_of(path):
            self.connect_to(neighbours.address_of(path), model[it][C_NAME])
        elif aliases.is_alias(path):
            self.open_or_enter(path)
        elif is_dir:
            self.navigate(path)
        else:
            self.open_file(path)

    def open_file(self, path):
        if app_list.is_installed_app(path):
            app = Gio.DesktopAppInfo.new_from_filename(path)
            if app is not None:
                try:
                    app.launch([], self.get_display().get_app_launch_context())
                except GLib.Error as err:
                    self.notify(f"“{app.get_display_name()}” couldn’t be opened ({err.message}).")
                return
        if macapps.is_bundle(path):
            GLib.spawn_async(["freemac-mac-app", "open", path], flags=GLib.SpawnFlags.SEARCH_PATH)
            return
        if drawer_archive.is_archive(path):
            self.expand(path)
            return
        try:
            Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(path).get_uri(), None)
            recents.note(path)
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
                if os.path.dirname(folder) == os.path.realpath(self.path):
                    self.select_paths([os.path.join(self.path, os.path.basename(folder))])
                if macapps.is_bundle(folder):
                    # a Mac app that came as a .zip (freemac 1.243): it opens from here
                    self.notify(f"“{macapps.display_name(folder)}” is ready. Open it, or drag it "
                                "to Applications to keep it in the app grid.")
                else:
                    self.notify(f"Expanded into “{os.path.basename(folder)}”.")

        self._in_background(lambda: drawer_archive.extract(path), done,
                            f"Expanding “{os.path.basename(path)}”…")

    def notify(self, text):
        self.status.set_text(text)
        self.told_at = time.monotonic()

    def browse_backups(self):
        """Lifeboat, at this folder (and the chosen file) as it was."""
        chosen = self.selected_paths()
        target = chosen[0] if len(chosen) == 1 else self.path
        try:
            Gio.Subprocess.new(["freemac-lifeboat", target], Gio.SubprocessFlags.NONE)
        except GLib.Error:
            pass

    def selected_paths(self):
        if self.view_mode in ICONISH:
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
        if self.in_virtual():
            self.notify("Open a folder to make a new folder in.")
            return
        base = self.path
        name, n = "untitled folder", 2
        while os.path.exists(os.path.join(base, name)):
            name, n = f"untitled folder {n}", n + 1
        try:
            os.mkdir(os.path.join(base, name))
        except OSError as err:
            self.notify(f"Couldn’t make a folder here: {err.strerror}.")
            return
        transfer.note_done({"kind": "new-folder", "path": os.path.join(base, name)})
        self.refresh()
        self.rename(os.path.join(base, name))

    def new_folder_with(self):
        """New Folder with Selection: the chosen items go into a new folder
        beside them, which is then ready to be named."""
        paths = self.selected_paths()
        if not paths or self.in_virtual() or self.in_trash():
            return
        folder, error = transfer.folder_with(paths)
        if error is not None:
            self.notify(f"Couldn’t move everything into the new folder: {error.strerror}.")
        if folder is None:
            return
        self.refresh()
        self.select_paths([folder])
        self.rename(folder)

    def show_enclosing(self):
        """From Recents or a tag: open the folder a file is in, with it chosen."""
        paths = self.selected_paths()
        if not paths:
            return
        self.navigate(os.path.dirname(paths[0]))
        GLib.idle_add(lambda: self.select_paths([paths[0]]) and False)

    def forget_recent(self):
        recents.forget(self.selected_paths())
        self.refresh()

    def rename(self, path=None):
        paths = [path] if path else self.selected_paths()
        locked = locks.locked_among(paths)
        if len(paths) > 1 and locked:
            locks.tell_cant_rename(self, locked[0])
            return
        if len(paths) > 1:
            batch_rename.ask(self, paths, self.notify)
            self.refresh()
            return
        if not paths:
            return
        path = paths[0]
        if locks.is_locked(path):
            locks.tell_cant_rename(self, path)
            return
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
                        if os.path.isdir(target):
                            drawer_background.moved(path, target)   # its background goes with it
                        transfer.note_done({"kind": "rename", "old": path, "new": target})
                    except OSError as err:
                        self.notify(f"Couldn’t rename: {err.strerror}.")
        dialog.destroy()
        self.refresh()

    def trash(self, paths=None):
        paths = paths if paths is not None else self.selected_paths()
        if self.in_trash():
            self.put_back(paths)   # ⌘⌫ in the Trash puts things back, as in Finder
            return
        apps = [p for p in paths if app_list.is_installed_app(p)]
        if apps:
            # An installed app isn't a file to throw away: Harbor removes it.
            names = [n for n, f, _i in app_list.installed_apps() if f in apps]
            what = f"“{names[0]}”" if len(names) == 1 else "These apps"
            from . import alert
            alert.tell(self, f"{what} can’t be moved to the Trash.",
                       "To remove an app, open Harbor, find the app and click Remove. Apps that come with "
                       "freemac can’t be removed.")
            paths = [p for p in paths if p not in apps]
            if not paths:
                return
        paths = locks.ask_trash(self, paths)
        if not paths:
            return
        went, error = transfer.to_trash(paths)
        if went:
            transfer.note_done({"kind": "trash", "paths": went})
        self.refresh()
        if error is not None:
            self.notify(f"Couldn’t move everything to the Trash: {error.message}")
        elif went:
            self.notify(f"Moved {len(went)} item{'s' if len(went) != 1 else ''} to the Trash. ⌘Z puts "
                        f"{'it' if len(went) == 1 else 'them'} back.")

    # ---- the Trash -----------------------------------------------------
    def in_trash(self):
        return bool(self.path) and os.path.realpath(self.path) == os.path.realpath(TRASH)

    def _trash_bar(self):
        """The strip along the top of the Trash, with its Empty button."""
        self.trash_bar = Gtk.Box(spacing=10)
        self.trash_bar.get_style_context().add_class("drawer-trashbar")
        self.trash_bar.set_no_show_all(True)
        title = Gtk.Label(label="Trash", xalign=0)
        title.get_style_context().add_class("title")
        hint = Gtk.Label(label="Select an item and choose Put Back to return it to where it was.", xalign=0,
                         ellipsize=Pango.EllipsizeMode.END)
        hint.get_style_context().add_class("dim-label")
        self.empty_button = Gtk.Button(label="Empty")
        self.empty_button.connect("clicked", lambda *_: self.empty_trash())
        self.trash_bar.pack_start(title, False, False, 0)
        self.trash_bar.pack_start(hint, True, True, 0)
        self.trash_bar.pack_end(self.empty_button, False, False, 0)
        for child in (title, hint, self.empty_button):
            child.show()
        return self.trash_bar

    def empty_trash(self):
        from . import alert
        if not drawer_settings.get("warn_empty_trash"):
            transfer.empty_trash()
            self.refresh()
            return
        answer = alert.ask(self, "Are you sure you want to permanently erase the items in the Trash?",
                           "You can’t undo this action.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Empty Trash", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK, destructive=Gtk.ResponseType.OK, icon="user-trash-full")
        if answer == Gtk.ResponseType.OK:
            transfer.empty_trash()
            self.refresh()

    def put_back(self, paths=None):
        """Return items in the Trash to the folders they came from."""
        if not self.in_trash():
            return
        paths = paths if paths is not None else self.selected_paths()
        if not paths:
            return
        went, error = transfer.put_back(paths)
        self.refresh()
        if error is not None:
            self.notify(f"Couldn’t put everything back: {error.strerror or error}.")
        elif len(went) == 1:
            where = os.path.basename(os.path.dirname(went[0])) or "Computer"
            self.notify(f"Put “{os.path.basename(went[0])}” back in “{where}”.")
        elif went:
            self.notify(f"Put back {len(went)} items.")

    # ---- View Options (⌘J) ---------------------------------------------------
    def _apply_text_size(self):
        css = f"iconview, treeview {{ font-size: {self.text_size}pt; }}" if self.text_size else "iconview {}"
        self.text_css.load_from_data(css.encode())

    def show_view_options(self):
        """A small panel, as Finder's View Options: icon size, grid spacing,
        text size, Show Item Info and Sort By for icon view. Changes show at
        once and are kept for every Drawer window."""
        if self.view_options is not None:
            self.view_options.present()
            return
        panel = Gtk.Window(title="View Options", transient_for=self, resizable=False,
                           type_hint=Gdk.WindowTypeHint.UTILITY, destroy_with_parent=True)
        panel.set_default_size(260, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=14)
        panel.add(box)

        def heading(text):
            label = Gtk.Label(label=text, xalign=0)
            label.get_style_context().add_class("drawer-preview-heading")
            box.pack_start(label, False, False, 0)

        def slider(low, high, step, value, small_icon, big_icon, changed):
            row = Gtk.Box(spacing=6)
            row.pack_start(Gtk.Image.new_from_icon_name(small_icon, Gtk.IconSize.MENU), False, False, 0)
            scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, low, high, step)
            scale.set_draw_value(False)
            scale.set_value(value)
            scale.connect("value-changed", changed)
            row.pack_start(scale, True, True, 0)
            row.pack_start(Gtk.Image.new_from_icon_name(big_icon, Gtk.IconSize.LARGE_TOOLBAR), False, False, 0)
            box.pack_start(row, False, False, 0)
            return scale

        listing = self.view_mode == "list"
        panel.set_title("View Options: List" if listing else "View Options")
        if not listing:
            heading("Icon size:")
            slider(32, 128, 8, self.icon_size, "image-x-generic-symbolic", "image-x-generic-symbolic",
                   lambda s: self._set_icon_size(int(round(s.get_value() / 8)) * 8))
            heading("Grid spacing:")
            slider(0, 40, 2, self.grid_spacing, "view-grid-symbolic", "view-grid-symbolic",
                   lambda s: self._set_grid_spacing(int(s.get_value())))
        row = Gtk.Box(spacing=8)
        row.pack_start(Gtk.Label(label="Text size:", xalign=0), False, False, 0)
        sizes = Gtk.ComboBoxText()
        sizes.append("", "Standard")
        for size in TEXT_SIZES:
            sizes.append(str(size), f"{size} pt")
        sizes.set_active_id(str(self.text_size) if self.text_size else "")
        sizes.connect("changed", lambda c: self._set_text_size(int(c.get_active_id()) if c.get_active_id() else None))
        row.pack_end(sizes, False, False, 0)
        box.pack_start(row, False, False, 4)
        if listing:
            # List view's own options, as in Finder: which columns show,
            # relative dates and folder sizes.
            heading("Show Columns:")
            for key, title in (("modified", "Date Modified"), ("size", "Size"), ("kind", "Kind")):
                shown = Gtk.CheckButton(label=title, active=key not in self.hidden_columns, margin_start=8)
                shown.connect("toggled", lambda b, k=key: self._show_column(k, b.get_active()))
                box.pack_start(shown, False, False, 0)
            relative = Gtk.CheckButton(label="Use relative dates", active=RELATIVE_DATES[0])
            relative.connect("toggled", lambda b: self._set_relative_dates(b.get_active()))
            box.pack_start(relative, False, False, 0)
            sizes_box = Gtk.CheckButton(label="Calculate all sizes", active=FOLDER_SIZES[0])
            sizes_box.connect("toggled", lambda b: self._set_folder_sizes(b.get_active()))
            box.pack_start(sizes_box, False, False, 0)
        else:
            info = Gtk.CheckButton(label="Show item info", active=self.item_info_shown)
            info.connect("toggled", lambda b: self._set_item_info(b.get_active()))
            box.pack_start(info, False, False, 0)
        background = not listing and self.view_mode == "icons"
        row = Gtk.Box(spacing=8)
        row.pack_start(Gtk.Label(label="Sort By:", xalign=0), False, False, 0)
        sorts = Gtk.ComboBoxText()
        for key, title in SORTS:
            sorts.append(key, title)
        sorts.set_active_id(self.sort)
        sorts.connect("changed", lambda c: self.set_sort(c.get_active_id()))
        row.pack_end(sorts, False, False, 0)
        box.pack_start(row, False, False, 4)
        if background:
            self._background_row(box)

        def closed(*_):
            self.view_options = None
            self.bg_widgets = None
        panel.connect("destroy", closed)
        panel.connect("key-press-event", lambda w, e: e.keyval == Gdk.KEY_Escape and (w.destroy() or True))
        self.view_options = panel
        panel.show_all()

    def _set_icon_size(self, size):
        if size == self.icon_size:
            return
        self.icon_size = size
        save_setting("icon_size", size)
        if getattr(self, "_resize_soon", 0):
            GLib.source_remove(self._resize_soon)
        self._resize_soon = GLib.timeout_add(120, self._refill_kept)

    def _refill_kept(self):
        self._resize_soon = 0
        keep = self.selected_paths()
        self.refresh()
        self.select_paths(keep)
        return False

    def _set_grid_spacing(self, spacing):
        self.grid_spacing = spacing
        save_setting("grid_spacing", spacing)
        self._place_icon_view()

    def _set_text_size(self, size):
        self.text_size = size
        save_setting("text_size", size)
        self._apply_text_size()
        self.icon_view.queue_resize()

    def _show_column(self, key, on):
        if on:
            self.hidden_columns.discard(key)
        else:
            self.hidden_columns.add(key)
        save_setting("hidden_columns", sorted(self.hidden_columns))
        self.list_columns[key].set_visible(on)

    def _set_relative_dates(self, on):
        RELATIVE_DATES[0] = on
        save_setting("relative_dates", on)
        self.list_columns["modified"].set_min_width(date_width())
        self._refill_kept()

    def _set_folder_sizes(self, on):
        FOLDER_SIZES[0] = on
        save_setting("calculate_sizes", on)
        if self.view_mode == "list":
            self._refill_kept()

    def _set_item_info(self, on):
        self.item_info_shown = on
        save_setting("item_info", on)
        self._refill_kept()

    # ---- sorting and the path bar ----------------------------------------
    def set_sort(self, sort):
        if sort not in dict(SORTS) or sort == self.sort:
            return
        self.sort = sort
        save_setting("sort", sort)
        keep = self.selected_paths()
        self.refresh()
        self.select_paths(keep)

    def _sort_item(self):
        item = Gtk.MenuItem(label="Sort By")
        menu = Gtk.Menu()
        group = None
        for key, title in SORTS:
            choice = Gtk.RadioMenuItem.new_with_label_from_widget(group, title)
            group = group or choice
            choice.set_active(key == self.sort)
            choice.connect("toggled", lambda c, k=key: c.get_active() and self.sort_action.change_state(
                GLib.Variant("s", k)))
            menu.append(choice)
        item.set_submenu(menu)
        return item

    def _set_path_bar(self, shown):
        self.path_bar_shown = shown
        save_setting("path_bar", shown)
        self._draw_path_bar()

    def _draw_path_bar(self):
        """Along the bottom: each folder from the top down to this one, as in
        Finder's path bar. A click on one goes there."""
        for child in self.path_bar.get_children():
            child.destroy()
        if not self.path_bar_shown or not self.path:
            self.path_bar.hide()
            return
        home = GLib.get_home_dir()
        path = self.path
        if path == recents.PLACE:
            crumbs = [("Recents", path, "document-open-recent-symbolic")]
        elif neighbours.is_place(path):
            crumbs = [("Network", neighbours.PLACE, "network-workgroup-symbolic")]
            if path != neighbours.PLACE:
                crumbs.append((neighbours.title(path), path, "network-server-symbolic"))
        elif self.in_virtual():
            crumbs = [(self._label(path), path, None)]
        elif self.in_trash():
            crumbs = [("Trash", TRASH, "user-trash-symbolic")]
        elif path == home or path.startswith(home.rstrip(os.sep) + os.sep):
            crumbs = [("Home", home, "user-home-symbolic")]
            base = home
        elif servers.mount_of(path):
            # A connected server: from its top, not from where it's kept.
            mount = servers.mount_of(path)
            base = mount.get_root().get_path()
            crumbs = [(servers.title(mount), base, "network-server-symbolic")]
        else:
            crumbs = [("Computer", "/", "drive-harddisk-symbolic")]
            base = "/"
        if not self.in_trash() and not self.in_virtual():
            for part in os.path.relpath(path, base).split(os.sep):
                if part in ("", "."):
                    continue
                base = os.path.join(base, part)
                crumbs.append((part, base, "folder-symbolic"))
        for index, (label, target, icon) in enumerate(crumbs):
            if index:
                gap = Gtk.Label(label="›")
                gap.get_style_context().add_class("drawer-crumb-gap")
                self.path_bar.pack_start(gap, False, False, 0)
            button = Gtk.Button(relief=Gtk.ReliefStyle.NONE, can_focus=False)
            inside = Gtk.Box(spacing=4)
            inside.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU) if icon else
                              tags.dot(tags.COLOR.get(label, "#9a9aa0"), 9), False, False, 0)
            inside.pack_start(Gtk.Label(label=label, max_width_chars=20, ellipsize=Pango.EllipsizeMode.MIDDLE),
                              False, False, 0)
            button.add(inside)
            button.set_tooltip_text(target)
            button.connect("clicked", lambda _b, t=target: self.navigate(t) if t != self.path else None)
            self.path_bar.pack_start(button, False, False, 0)
        for child in self.path_bar.get_children():
            child.show_all()   # (show_all skips a box that is set not to show with its window)
        self.path_bar.show()

    # ---- Connect to Server -----------------------------------------------
    def connect_to_server(self):
        """⌘K: open a shared folder on another computer, like a drive."""
        servers.connect_dialog(self, self.navigate, lambda uri: self.navigate(neighbours.place_for(uri)))

    def connect_to(self, address, name=None):
        """Open a computer from the Network place: sign in if it asks. One
        that shares several folders shows them, to pick one."""
        self.notify("Connecting\u2026")
        if name:
            neighbours.NAMES[address] = name

        def done(path, problem):
            if path or problem == servers.NO_FOLDER:
                self.told_at = 0          # "Connecting…" is over
            if path:
                if name:
                    servers.NAMES.setdefault(path, name)
                self._fill_locations()
                self.navigate(path)
            elif problem == servers.NO_FOLDER:
                self.navigate(neighbours.place_for(address))
            elif problem:
                self.notify(problem)
        servers.connect(address, self, done, name)

    # ---- Go to Folder ----------------------------------------------------
    last_typed = "~/"

    def go_to_folder(self):
        """⇧⌘G: type where to go. Tab finishes a name; ~ is the home folder.
        A file opens its folder with the file chosen."""
        dialog = Gtk.Dialog(title="Go to Folder", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Go", Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        box = dialog.get_content_area()
        box.set_spacing(6)
        box.set_border_width(14)
        box.pack_start(Gtk.Label(label="Go to the folder:", xalign=0), False, False, 0)
        entry = Gtk.Entry(activates_default=True, width_chars=46, text=DrawerWindow.last_typed)
        box.pack_start(entry, False, False, 0)
        hint = Gtk.Label(label="Tab finishes a name. ~ is your home folder.", xalign=0)
        hint.get_style_context().add_class("drawer-go-hint")
        box.pack_start(hint, False, False, 0)

        def tab(_e, event):
            if event.keyval not in (Gdk.KEY_Tab, Gdk.KEY_ISO_Left_Tab):
                return False
            done = complete_path(entry.get_text(), self.path)
            if done is None:
                Gdk.Display.get_default().beep()
            else:
                entry.set_text(done)
                entry.set_position(-1)
            return True   # Tab stays in the box

        entry.connect("key-press-event", tab)
        dialog.show_all()
        entry.grab_focus()
        while dialog.run() == Gtk.ResponseType.OK:
            typed = entry.get_text().strip()
            target = os.path.expanduser(typed)
            if typed and not os.path.isabs(target):
                target = os.path.join(self.path, target)
            target = os.path.normpath(target) if typed else ""
            if typed and os.path.isdir(target):
                DrawerWindow.last_typed = typed
                dialog.destroy()
                self.navigate(target)
                return
            if typed and os.path.lexists(target):
                DrawerWindow.last_typed = typed
                dialog.destroy()
                self.navigate(os.path.dirname(target))
                GLib.idle_add(lambda: self.select_paths([target]) and False)
                return
            hint.set_text("There’s no folder there. Check the name and try again.")
            hint.get_style_context().add_class("error")
            entry.grab_focus()
        dialog.destroy()

    # ---- Open With ------------------------------------------------------
    def _open_with_item(self, selected):
        """Open With ›: the apps that can open these files, the usual one
        first, then Other… to choose any app."""
        files = [p for p in selected if not os.path.isdir(p)]
        if not files or len(files) != len(selected):
            return None
        try:
            info = Gio.File.new_for_path(files[0]).query_info("standard::content-type",
                                                             Gio.FileQueryInfoFlags.NONE, None)
            content = info.get_content_type() or "application/octet-stream"
        except GLib.Error:
            content = "application/octet-stream"
        default = Gio.AppInfo.get_default_for_type(content, False)
        apps, seen = [], set()
        for app in ([default] if default else []) + list(Gio.AppInfo.get_all_for_type(content)):
            if app.get_id() in seen or not app.should_show():
                continue
            seen.add(app.get_id())
            apps.append(app)
        item = Gtk.MenuItem(label="Open With")
        menu = Gtk.Menu()
        for index, app in enumerate(apps):
            row = Gtk.MenuItem()
            inside = Gtk.Box(spacing=8)
            icon = app.get_icon()
            image = Gtk.Image.new_from_gicon(icon, Gtk.IconSize.MENU) if icon else Gtk.Image()
            image.set_pixel_size(16)
            inside.pack_start(image, False, False, 0)
            name = app.get_display_name() or app.get_name()
            inside.pack_start(Gtk.Label(label=f"{name} (default)" if index == 0 and default else name, xalign=0),
                              False, False, 0)
            row.add(inside)
            row.connect("activate", lambda _i, a=app: self._open_with(a, files))
            menu.append(row)
            if index == 0 and default and len(apps) > 1:
                menu.append(Gtk.SeparatorMenuItem())
        if apps:
            menu.append(Gtk.SeparatorMenuItem())
        other = Gtk.MenuItem(label="Other…")
        other.connect("activate", lambda *_: self._open_with_other(files))
        menu.append(other)
        item.set_submenu(menu)
        return item

    def _quick_actions_item(self, paths):
        """Rotate Left, Rotate Right and Create PDF, for pictures."""
        item = Gtk.MenuItem(label="Quick Actions")
        menu = Gtk.Menu()
        for label, action, enabled in (
                ("Rotate Left", lambda: self._rotate(paths, False), quick_actions.can_rotate(paths)),
                ("Rotate Right", lambda: self._rotate(paths, True), quick_actions.can_rotate(paths)),
                ("Create PDF", lambda: self._make_pdf(paths), True)):
            entry = Gtk.MenuItem(label=label)
            entry.set_sensitive(enabled)
            entry.connect("activate", lambda _i, a=action: a())
            menu.append(entry)
        item.set_submenu(menu)
        return item

    def _rotate(self, paths, clockwise):
        error = quick_actions.rotate(paths, clockwise)
        if error is not None:
            self.notify(f"Couldn’t turn it: {getattr(error, 'message', None) or error.strerror}.")
        Folder.thumb_cache.clear()
        self.refresh()
        self.select_paths(paths)

    def _make_pdf(self, paths):
        pdf, error = quick_actions.make_pdf(paths)
        if error is not None:
            self.notify(f"Couldn’t add every picture: {getattr(error, 'message', None) or error}.")
        if pdf:
            self.refresh()
            self.select_paths([pdf])
            if error is None:
                self.notify(f"Made “{os.path.basename(pdf)}”.")

    def _open_with(self, app, files):
        try:
            app.launch([Gio.File.new_for_path(f) for f in files], None)
            for f in files:
                recents.note(f)
        except GLib.Error as err:
            self.notify(f"{app.get_display_name()} couldn’t open it ({err.message}).")

    def _open_with_other(self, files):
        dialog = Gtk.AppChooserDialog.new(self, Gtk.DialogFlags.MODAL, Gio.File.new_for_path(files[0]))
        dialog.set_heading(f"Choose an app to open “{os.path.basename(files[0])}”.")
        widget = dialog.get_widget()
        widget.set_show_all(True)
        app = dialog.get_app_info() if dialog.run() == Gtk.ResponseType.OK else None
        dialog.destroy()
        if app is not None:
            self._open_with(app, files)

    def get_info(self):
        paths = self.selected_paths() or [self.path]
        drawer_info.show(paths, self)

    def summary_info(self):
        """⌃⌘I: one Info window for everything chosen."""
        paths = self.selected_paths() or [self.path]
        paths = [p for p in paths if os.path.isabs(p) and os.path.lexists(p)]
        if paths:
            drawer_summary.show(paths, self)

    def show_inspector(self):
        """⌥⌘I: one Info window that follows what is selected."""
        drawer_info.inspector((self.selected_paths() or [self.path])[0], self)

    def copy_pathname(self):
        """⌥⌘C: put the selected items' full paths on the clipboard, one a
        line, as a Mac's Copy as Pathname does."""
        paths = self.selected_paths() or ([self.path] if self.path and os.path.isabs(self.path) else [])
        if not paths:
            return
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text("\n".join(paths), -1)

    def toggle_hidden(self):
        self.hidden_action.change_state(GLib.Variant("b", not self.show_hidden))

    def _set_hidden(self, shown):
        self.show_hidden = shown
        self.refresh()

    def select_all(self):
        if self.view_mode in ICONISH:
            self.icon_view.select_all()
        elif self.view_mode == "list":
            self.list_view.get_selection().select_all()

    def go_up(self):
        if self.in_virtual():
            return
        parent = os.path.dirname(self.path)
        if parent != self.path:
            self.navigate(parent)

    # ---- events ---------------------------------------------------------
    def _view_toggled(self, button, mode):
        if button.get_active():
            keep = self.selected_paths() if self.path else []
            self.view_mode = mode
            if self.view_options is not None:
                # The panel shows the options of the view in front.
                self.view_options.destroy()
                self.show_view_options()
            if self.path:
                self.refresh()
                if keep and mode != "columns":
                    self.select_paths(keep)   # the same files stay chosen, as in Finder
            GLib.idle_add(self._focus_view)

    def _focus_view(self):
        """Keyboard focus follows the view, so arrow keys move through files."""
        if self.view_mode in ICONISH:
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
        if self.quiet:
            return
        self.filter_text = entry.get_text().strip().lower()
        if self.in_search():
            # Look again once the typing pauses.
            if self.search_soon:
                GLib.source_remove(self.search_soon)
            self.search_soon = GLib.timeout_add(350, self._search_typed)
            return
        self.icon_view.get_model().refilter()
        if self.view_mode == "columns":
            self._reset_columns()
        self._show_scope()
        self._show_status()

    # ---- searching and Smart Folders --------------------------------------
    def _scope_bar(self):
        """Under the toolbar while searching, as in Finder: where to look
        (This Mac, or just this folder), what kind of file, changed when,
        and Save to keep the search as a Smart Folder."""
        bar = Gtk.Box(spacing=6)
        bar.get_style_context().add_class("drawer-scopebar")
        bar.set_no_show_all(True)
        bar.pack_start(Gtk.Label(label="Search:"), False, False, 4)
        scopes = Gtk.Box()
        scopes.get_style_context().add_class("linked")
        self.scope_mac = Gtk.RadioButton.new_with_label_from_widget(None, "This Mac")
        self.scope_here = Gtk.RadioButton.new_with_label_from_widget(self.scope_mac, "")
        for button in (self.scope_mac, self.scope_here):
            button.set_mode(False)
            button.connect("toggled", self._scope_toggled)
            scopes.add(button)
        bar.pack_start(scopes, False, False, 0)
        self.scope_kind = Gtk.ComboBoxText(tooltip_text="Kind")
        for key, name in smart_folders.KINDS:
            self.scope_kind.append(key, name)
        self.scope_when = Gtk.ComboBoxText(tooltip_text="Last changed")
        for key, name in smart_folders.WHEN:
            self.scope_when.append(key, name)
        for combo in (self.scope_kind, self.scope_when):
            combo.connect("changed", lambda _c: self._criteria_changed())
        self.scope_save = Gtk.Button(label="Save", tooltip_text="Keep this search as a Smart Folder in the sidebar")
        self.scope_save.connect("clicked", lambda _b: self.save_search())
        bar.pack_end(self.scope_save, False, False, 4)
        bar.pack_end(self.scope_when, False, False, 0)
        bar.pack_end(self.scope_kind, False, False, 0)
        for child in bar.get_children():
            child.show_all()   # the bar itself shows only while searching
        self.scope_bar = bar
        return bar

    def _show_scope(self):
        """Show the scope bar when there's a search, set to match it."""
        searching = self.in_search()
        typed = bool(self.search.get_text().strip())
        if not searching and not typed:
            self.scope_bar.hide()
            return
        self.quiet = True
        try:
            if searching:
                query = smart_folders.query_of(self.path) or smart_folders.blank()
                self.scope_mac.set_active(True)
                self.scope_kind.set_active_id(query["kind"])
                self.scope_when.set_active_id(query["when"])
                if self.search.get_text().strip() != query["text"] and not self.search_soon:
                    self.search.set_text(query["text"])
                self.filter_text = query["text"].lower()
            else:
                self.scope_here.set_active(True)
            here = self.search_from if searching else self.path
            self.scope_here.set_label(f"“{self._label(here)}”" if here else "")
        finally:
            self.quiet = False
        self.scope_save.set_sensitive(searching and not smart_folders.is_empty(
            smart_folders.query_of(self.path) or smart_folders.blank()))
        self.scope_bar.show()
        self.scope_here.set_visible(bool(here) and (not searching or here != GLib.get_home_dir()))
        for widget in (self.scope_kind, self.scope_when, self.scope_save):
            widget.set_visible(searching)

    def _current_query(self):
        query = dict(smart_folders.query_of(self.path) or smart_folders.blank()) if self.in_search() \
            else smart_folders.blank()
        query["text"] = self.search.get_text().strip()
        query["kind"] = self.scope_kind.get_active_id() or "any"
        query["when"] = self.scope_when.get_active_id() or "any"
        return query

    def _show_search(self, query):
        """Go to the search; while searching, a change replaces the search
        rather than adding a step to Back."""
        place = smart_folders.place(query)
        if place == self.path or (self.in_search() and smart_folders.query_of(self.path) == smart_folders.clean(query)):
            return
        if self.in_search():
            if self.path.startswith(smart_folders.SAVED):
                self.editing_smart = self.path[len(smart_folders.SAVED):]
            self.path = place
            self.refresh()
        else:
            self.editing_smart = None
            self.navigate(place)

    def _search_typed(self):
        self.search_soon = 0
        if self.in_search():
            self._show_search(self._current_query())
        return False

    def _criteria_changed(self):
        if not self.quiet and self.in_search():
            self._show_search(self._current_query())

    def _scope_toggled(self, button):
        if self.quiet or not button.get_active():
            return
        if button is self.scope_mac and not self.in_search():
            self._show_search(dict(smart_folders.blank(), text=self.search.get_text().strip()))
        elif button is self.scope_here and self.in_search() and self.search_from:
            text = self.search.get_text()
            self.navigate(self.search_from)
            self.search.set_text(text)   # filters that folder

    def new_smart_folder(self):
        """File › New Smart Folder: an empty search of This Mac, ready to type."""
        self.editing_smart = None
        self.quiet = True
        self.search.set_text("")
        self.quiet = False
        self.navigate(smart_folders.place({}))
        self.search.grab_focus()

    def find(self):
        """⌘F: search, starting with This Mac as Finder does."""
        if not self.in_search() and not self.search.get_text().strip():
            self._show_scope()
            self.scope_bar.show()
            self.quiet = True
            self.scope_here.set_active(True)
            self.scope_here.set_label(f"“{self._label(self.path)}”")
            self.quiet = False
            for widget in (self.scope_kind, self.scope_when, self.scope_save):
                widget.hide()
        self.search.grab_focus()

    def save_search(self):
        """Save: name the search, and it's kept in the sidebar."""
        if not self.in_search():
            return
        query = self._current_query()
        popover = Gtk.Popover(relative_to=self.scope_save, position=Gtk.PositionType.BOTTOM)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=12)
        box.pack_start(Gtk.Label(label="Save this search as a Smart Folder:", xalign=0), False, False, 0)
        default = self.editing_smart or (self.path[len(smart_folders.SAVED):]
                                         if self.path.startswith(smart_folders.SAVED) else None)
        entry = Gtk.Entry(activates_default=True, width_chars=28,
                          text=default or (query["text"].capitalize() if query["text"] else
                                           smart_folders.unused_name()))
        box.pack_start(entry, False, False, 0)
        problem = Gtk.Label(xalign=0, no_show_all=True)
        problem.get_style_context().add_class("dim-label")
        box.pack_start(problem, False, False, 0)
        save = Gtk.Button(label="Save", can_default=True)
        save.get_style_context().add_class("suggested-action")
        line = Gtk.Box()
        line.pack_end(save, False, False, 0)
        box.pack_start(line, False, False, 0)

        def done(*_):
            name = " ".join(entry.get_text().replace("/", "-").split())
            if not name:
                problem.set_text("Give it a name.")
                problem.show()
                return
            if name != default and any(e["name"] == name for e in smart_folders.load()):
                problem.set_text(f"There’s already a Smart Folder called “{name}”.")
                problem.show()
                return
            try:
                place = smart_folders.save(name, query)
            except OSError as error:
                problem.set_text(f"Couldn’t save it: {error.strerror}.")
                problem.show()
                return
            popover.hide()
            popover.destroy()
            self._save_popover = None
            self.editing_smart = None
            self._smart_folders_changed()
            self.path = place
            self.refresh()
            self.notify(f"Saved “{name}” in the sidebar. It looks again each time you open it.")
        save.connect("clicked", done)
        entry.connect("activate", done)
        popover.add(box)
        box.show_all()
        popover.popup()
        entry.grab_focus()
        save.grab_default()
        self._save_popover = popover

    def _fill_smart(self):
        self.place_rows = [(lb, row) for lb, row in self.place_rows if lb is not self.smart_list]
        for child in self.smart_list.get_children():
            self.smart_list.remove(child)
        entries = smart_folders.load()
        for entry in entries:
            row = Gtk.ListBoxRow(can_focus=False)
            row.path, row.mount = smart_folders.SAVED + entry["name"], "smart"
            line = Gtk.Box(spacing=8)
            line.pack_start(Gtk.Image.new_from_icon_name("folder-saved-search-symbolic", Gtk.IconSize.MENU),
                            False, False, 0)
            line.pack_start(Gtk.Label(label=entry["name"], xalign=0, ellipsize=Pango.EllipsizeMode.END),
                            True, True, 0)
            row.add(line)
            row.show_all()
            self.smart_list.add(row)
            self.place_rows.append((self.smart_list, row))
        self.smart_heading.set_visible(bool(entries))
        self.smart_list.set_visible(bool(entries))

    def _smart_folders_changed(self):
        """Every Drawer window shows the same sidebar."""
        for window in self.get_application().get_windows() if self.get_application() else [self]:
            if isinstance(window, DrawerWindow):
                window._fill_smart()
                window._show_place()

    def _smart_button(self, listbox, event):
        if event.button != 3:
            return False
        row = listbox.get_row_at_y(int(event.y))
        if row is None:
            return True
        name = row.path[len(smart_folders.SAVED):]
        menu = Gtk.Menu()
        menu.attach_to_widget(listbox, None)
        for label, action in (("Open", lambda: self.navigate(row.path)),
                              ("Open in New Tab", lambda: self.new_tab(row.path)),
                              (None, None),
                              ("Remove Smart Folder", lambda: self.remove_smart(name))):
            item = Gtk.SeparatorMenuItem() if label is None else Gtk.MenuItem(label=label)
            if label is not None:
                item.connect("activate", lambda _i, a=action: a())
            menu.append(item)
        menu.show_all()
        menu.popup_at_pointer(event)
        self._smart_menu = menu
        return True

    def remove_smart(self, name):
        """Only the search goes; the files it found stay where they are."""
        try:
            smart_folders.remove(name)
        except OSError as error:
            self.notify(f"Couldn’t remove it: {error.strerror}.")
            return
        self._smart_folders_changed()
        for window in self.get_application().get_windows() if self.get_application() else [self]:
            if isinstance(window, DrawerWindow) and window.path == smart_folders.SAVED + name:
                window.navigate(window.search_from or GLib.get_home_dir())
        self.notify(f"Removed the Smart Folder “{name}”. The files it showed are where they were.")

    def _menu(self, event):
        if neighbours.is_place(self.path):
            self._network_menu(event)
            return
        menu = Gtk.Menu()
        has_selection = bool(self.selected_paths())
        has_folder = any(os.path.isdir(p) for p in self.selected_paths()[:1])
        selected = self.selected_paths()
        # Holding Option changes some items, as on a Mac.
        option = bool((getattr(event, "state", 0) or 0) & Gdk.ModifierType.MOD1_MASK)
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
        in_trash = self.in_trash()
        extra = ()
        if self.in_virtual():
            extra += (("Show in Enclosing Folder", lambda *_: self.show_enclosing(), has_selection),)
        if self.path == recents.PLACE:
            extra += (("Remove from Recents", lambda *_: self.forget_recent(), has_selection),)
        if selected and not self.in_virtual() and not in_trash:
            extra += ((f"New Folder with Selection ({len(selected)} Item{'s' if len(selected) != 1 else ''})",
                       lambda *_: self.new_folder_with(), True),)
        if extra:
            extra += ((None, None, True),)
        for label, handler, enabled in app_items + (
            ("Open", lambda *_: [self.open_or_enter(p) for p in self.selected_paths()], has_selection),
            ("Open With", None, has_selection),
            ("Show Inspector", lambda *_: self.show_inspector(), True) if option else
            ("Get Info", lambda *_: self.get_info(), True),
            ("Rename…" if len(selected) < 2 else f"Rename {len(selected)} Items…", lambda *_: self.rename(), has_selection),
            ("Put Back" if in_trash else "Move to Trash",
             (lambda *_: self.put_back()) if in_trash else (lambda *_: self.trash()), has_selection),
            (None, None, True),
        ) + extra + (
            ("Duplicate", lambda *_: self.duplicate(), has_selection),
            ("Make Alias", lambda *_: self.make_alias(), has_selection and not in_trash and not self.in_virtual()),
            ("Show Original", lambda *_: self.show_original(), len(selected) == 1 and aliases.is_alias(selected[0])),
            ((f"Copy “{os.path.basename(selected[0])}” as Pathname" if len(selected) == 1
              else f"Copy {len(selected)} Items as Pathnames"), lambda *_: self.copy_pathname(), has_selection)
            if option else ("Copy", lambda *_: self.copy(), has_selection),
            ("Paste Item", lambda *_: self.paste(), True),
            (None, None, True),
            ("Expand" if one_archive else "Compress",
             (lambda *_: self.expand(selected[0])) if one_archive else (lambda *_: self.compress()), has_selection),
            ("Share", None, has_selection),
            (None, None, True),
            ("Open in New Tab", lambda *_: self.new_tab(self.selected_paths()[0]), has_folder),
            ("Add to Sidebar", lambda *_: self.add_to_sidebar(), has_folder),
            ("Glance", lambda *_: self.toggle_glance(), has_selection),
            ("Quick Actions", None, not in_trash and quick_actions.can_make_pdf(selected)),
            ("Services", None, not in_trash),
            (None, None, True),
            ("Tags", None, has_selection and not in_trash),
            (None, None, has_selection and not in_trash),
            ("New Folder", lambda *_: self.new_folder(), True),
            ("Sort By", None, True),
            ("Hide Hidden Files" if self.show_hidden else "Show Hidden Files", lambda *_: self.toggle_hidden(), True),
        ):
            if label == "Share":
                menu.append(share.menu_item(self, selected, self.notify))
                continue
            if label == "Open With":
                item = self._open_with_item(selected)
                if item is not None:
                    menu.append(item)
                continue
            if label == "Sort By":
                menu.append(self._sort_item())
                continue
            if label == "Quick Actions":
                if enabled:
                    menu.append(self._quick_actions_item(selected))
                continue
            if label == "Services":
                item = self._services_item(selected) if enabled else None
                if item is not None:
                    menu.append(item)
                continue
            if label == "Tags":
                if enabled:
                    menu.append(tags.menu_item(selected, lambda err, keep=selected: self._tags_changed(err, keep)))
                continue
            if (label is None or label == "Show Original") and not enabled:
                continue
            item = Gtk.SeparatorMenuItem() if label is None else Gtk.MenuItem(label=label)
            if handler:
                item.connect("activate", handler)
            item.set_sensitive(enabled)
            menu.append(item)
        menu.show_all()
        menu.attach_to_widget(self, None)
        menu.popup_at_pointer(event)

    def _services_item(self, selected):
        """Services ›: the file services (services.py) that suit what's
        selected, or this folder when nothing is; None when none do."""
        chosen = list(selected) or ([self.path] if self.path and os.path.isdir(self.path) else [])
        fitting = [s for s in services.shown("files") if services.suits(s[0], chosen)]
        if not fitting:
            return None
        item = Gtk.MenuItem(label="Services")
        sub = Gtk.Menu()
        for service_id, title, _kind, _suits, _keys in fitting:
            entry = Gtk.MenuItem(label=title)
            entry.connect("activate", lambda _i, s=service_id: self._run_service(s, chosen))
            sub.append(entry)
        sub.append(Gtk.SeparatorMenuItem())
        settings = Gtk.MenuItem(label="Services Settings\u2026")
        settings.connect("activate", lambda _i: subprocess.Popen(["freemac-dials", "--panel", "keyboard"],
                                                                 start_new_session=True))
        sub.append(settings)
        item.set_submenu(sub)
        return item

    def _run_service(self, service_id, paths):
        subprocess.Popen(["freemac-service", service_id, *paths], start_new_session=True)

    def _network_menu(self, event):
        """In Network, a computer can only be connected to."""
        menu = Gtk.Menu()
        chosen = [neighbours.address_of(p) for p in self.selected_paths() if neighbours.address_of(p)]
        for label, handler, enabled in (("Connect", lambda *_: self.connect_to(chosen[0]), bool(chosen)),
                                        ("Connect to Server\u2026", lambda *_: self.connect_to_server(), True)):
            item = Gtk.MenuItem(label=label)
            item.connect("activate", handler)
            item.set_sensitive(enabled)
            menu.append(item)
        menu.show_all()
        menu.attach_to_widget(self, None)
        menu.popup_at_pointer(event)

    def open_or_enter(self, path):
        if aliases.is_alias(path):
            # An alias opens its original; a folder's opens where it really is.
            found = aliases.original(path)
            if not found:
                aliases.ask_broken(self, path)   # Fix Alias… points it again, without opening
                self.refresh()
                return
            path = found
        if neighbours.address_of(path):
            self.connect_to(neighbours.address_of(path))
        elif os.path.isdir(path) and not macapps.is_bundle(path):
            self.navigate(path)
        else:
            self.open_file(path)

    def _icon_button(self, view, event):
        if event.button != 3:
            return False
        item = view.get_path_at_pos(int(event.x), int(event.y))
        if item is None:
            view.unselect_all()   # a click on empty space is about the folder
        elif not view.path_is_selected(item):
            view.unselect_all()
            view.select_path(item)
        self._menu(event)
        return True

    def _tree_button(self, view, event):
        if event.button != 3:
            return False
        hit = view.get_path_at_pos(int(event.x), int(event.y))
        if hit is None and view is self.list_view:
            view.get_selection().unselect_all()
        elif hit and not view.get_selection().path_is_selected(hit[0]):
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
        elif ctrl and event.state & (Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.MOD4_MASK
                                     | Gdk.ModifierType.META_MASK) and key in (Gdk.KEY_i, Gdk.KEY_I):
            self.summary_info()   # ⌃⌘I
        elif ctrl and event.state & Gdk.ModifierType.MOD1_MASK and key in (Gdk.KEY_i, Gdk.KEY_I):
            self.show_inspector()
        elif ctrl and key in (Gdk.KEY_i, Gdk.KEY_I):
            self.get_info()
        elif ctrl and event.state & Gdk.ModifierType.MOD1_MASK and key in (Gdk.KEY_c, Gdk.KEY_C):
            self.copy_pathname()
        elif ctrl and not shift and key in (Gdk.KEY_c, Gdk.KEY_C):
            self.copy()
        elif ctrl and not shift and key in (Gdk.KEY_v, Gdk.KEY_V):
            self.paste(move=bool(event.state & Gdk.ModifierType.MOD1_MASK))
        elif ctrl and not shift and key in (Gdk.KEY_d, Gdk.KEY_D):
            self.duplicate()
        elif ctrl and not shift and key in (Gdk.KEY_z, Gdk.KEY_Z):
            self.undo()
        elif key == Gdk.KEY_F2:
            self.rename()
        elif ctrl and event.state & Gdk.ModifierType.MOD1_MASK and key in (Gdk.KEY_N, Gdk.KEY_n):
            self.new_smart_folder()
        elif ctrl and shift and key in (Gdk.KEY_N, Gdk.KEY_n):
            self.new_folder()
        elif (ctrl and key in (Gdk.KEY_h, Gdk.KEY_H)) or (ctrl and shift and key in (Gdk.KEY_period,
                                                                                    Gdk.KEY_greater)):
            self.toggle_hidden()
        elif ctrl and key in (Gdk.KEY_1, Gdk.KEY_2, Gdk.KEY_3, Gdk.KEY_4):
            self.view_buttons[VIEWS[key - Gdk.KEY_1][0]].set_active(True)
        elif ctrl and shift and key in (Gdk.KEY_f, Gdk.KEY_F):
            self.navigate(recents.PLACE)
        elif ctrl and key in (Gdk.KEY_f, Gdk.KEY_F):
            self.find()
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
        elif ctrl and shift and key in (Gdk.KEY_g, Gdk.KEY_G):
            self.go_to_folder()
        elif ctrl and shift and key in (Gdk.KEY_p, Gdk.KEY_P) and not event.state & Gdk.ModifierType.MOD1_MASK:
            self.preview_action.change_state(GLib.Variant("b", not self.preview_shown))
        elif ctrl and not shift and key in (Gdk.KEY_j, Gdk.KEY_J):
            self.show_view_options()
        elif ctrl and key in (Gdk.KEY_slash, Gdk.KEY_question):
            self.status_bar_action.change_state(GLib.Variant("b", not self.status_shown))
        elif ctrl and event.state & Gdk.ModifierType.MOD1_MASK and key in (Gdk.KEY_p, Gdk.KEY_P):
            self.path_bar_action.change_state(GLib.Variant("b", not self.path_bar_shown))
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


# Go > Recent Folders, kept up to date by the app (see Drawer.show_recent_folders).
RECENT_MENU = Gio.Menu()


def menubar():
    return menus.menubar([
        ("_File", [
            [("New Window", "app.new-window", "<Ctrl>n"), ("New Tab", "win.new-tab", "<Ctrl>t"),
             ("New Folder", "win.new-folder", "<Ctrl><Shift>n"),
             ("New Folder with Selection", "win.new-folder-with", None),
             ("New Smart Folder", "win.new-smart-folder", "<Ctrl><Alt>n")],
            [("Open", "win.open", "<Ctrl>o"), ("Glance", "win.glance", "space")],
            [("Show in Enclosing Folder", "win.show-enclosing", None)],
            [("Duplicate", "win.duplicate", "<Ctrl>d"), ("Make Alias", "win.make-alias", None),
             ("Show Original", "win.show-original", "<Ctrl>r")],
            [("Get Info", "win.get-info", "<Ctrl>i"), ("Get Summary Info", "win.summary-info", None),
             ("Show Inspector", "win.show-inspector", "<Ctrl><Alt>i")],
            [("Rename…", "win.rename", "F2"), ("Compress", "win.compress", None),
             ("Move to Trash", "win.trash", "<Ctrl>BackSpace"), ("Put Back", "win.put-back", None)],
            [("Share…", "win.share", None)],
            [("Add to Sidebar", "win.add-to-sidebar", "<Ctrl><Shift>d")],
            [("Eject", "win.eject", "<Ctrl>e")],
            [("Close Tab", "win.close-tab", "<Ctrl>w"), ("Close Window", "win.close", "<Ctrl><Shift>w")],
        ]),
        ("_Edit", [
            [("Undo", "win.undo", "<Ctrl>z")],
            [("Copy", "win.copy", "<Ctrl>c"), ("Copy as Pathname", "win.copy-pathname", "<Ctrl><Alt>c"),
             ("Paste Item", "win.paste", "<Ctrl>v"),
             ("Move Item Here", "win.move-here", "<Ctrl><Alt>v")],
            [("Select All", "win.select-all", "<Ctrl>a")],
            [("Show Clipboard", "win.show-clipboard", None)],
            [("Find…", "win.filter", "<Ctrl>f"), ("Save Search…", "win.save-search", None)],
        ]),
        ("_View", [
            [("as Icons", "win.view-icons", "<Ctrl>1"), ("as List", "win.view-list", "<Ctrl>2"),
             ("as Columns", "win.view-columns", "<Ctrl>3"), ("as Gallery", "win.view-gallery", "<Ctrl>4")],
            [("Sort by " + title, f"win.sort-by::{key}", None) for key, title in SORTS],
            [("Show Sidebar", "win.sidebar", None), ("Show Path Bar", "win.path-bar", "<Ctrl><Alt>p"),
             ("Show Status Bar", "win.status-bar", "<Ctrl>slash"), ("Show Preview", "win.preview", "<Ctrl><Shift>p"),
             ("Show Hidden Files", "win.show-hidden", "<Ctrl><Shift>period")],
            [("Show View Options", "win.view-options", "<Ctrl>j")],
            [("Next Tab", "win.next-tab", "<Ctrl>Tab"), ("Previous Tab", "win.previous-tab", "<Ctrl><Shift>Tab")],
        ]),
        ("_Go", [
            [("Back", "win.back", "<Ctrl>bracketleft"), ("Forward", "win.forward", "<Ctrl>bracketright"),
             ("Enclosing Folder", "win.up", "<Ctrl>Up")],
            [("Recents", "win.go-recents", "<Ctrl><Shift>f"), ("Documents", "win.go-documents", "<Ctrl><Shift>o"),
             ("Desktop", "win.go-desktop", None), ("Downloads", "win.go-downloads", "<Ctrl><Alt>l"),
             ("Home", "win.go-home", "<Ctrl><Shift>h"), ("Computer", "win.go-computer", "<Ctrl><Shift>c"),
             ("Network", "win.go-network", "<Ctrl><Shift>k"), ("Applications", "win.go-applications", "<Ctrl><Shift>a")],
            [("Recent Folders", RECENT_MENU, None)],
            [("Go to Folder…", "win.go-to-folder", "<Ctrl><Shift>g"),
             ("Connect to Server…", "win.connect-to-server", "<Ctrl>k")],
            [("Browse Backups", "win.browse-backups", None)],
        ]),
    ])


SELECT_ONLY = [False]   # set by --select


class Drawer(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.freemac.Drawer",
                         flags=Gio.ApplicationFlags.HANDLES_OPEN | Gio.ApplicationFlags.NON_UNIQUE)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        menus.add_actions(self, {"new-window": lambda: DrawerWindow(self, self.start_folder()).show_all(),
                                 "settings": self.show_settings,
                                 "clear-recent-folders": self.clear_recent_folders})
        self.show_recent_folders()
        # Another Drawer may have opened folders meanwhile: look again when
        # a window of this one comes to the front.
        self.connect("window-added", lambda _app, window: window.connect(
            "notify::is-active", lambda w, _p: w.is_active() and self.show_recent_folders()))
        self.set_accels_for_action("app.settings", ["<Control>comma"])
        self.set_menubar(menubar())
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    @staticmethod
    def start_folder():
        return drawer_settings.start_folder(recents.PLACE)

    def show_recent_folders(self):
        """Fill Go > Recent Folders: the folders, then Clear Menu."""
        folders = recent_folders.labels(recent_folders.listed())
        shown = getattr(self, "_recent_shown", None)
        if shown == folders:
            return
        self._recent_shown = folders
        RECENT_MENU.remove_all()
        items = Gio.Menu()
        for folder, words in folders:
            item = Gio.MenuItem.new(words, None)
            item.set_action_and_target_value("win.go-recent", GLib.Variant("s", folder))
            item.set_icon(Gio.ThemedIcon.new("folder"))
            items.append_item(item)
        RECENT_MENU.append_section(None, items)
        RECENT_MENU.append_section(None, menus.section([("Clear Menu", "app.clear-recent-folders", None)]))
        action = self.lookup_action("clear-recent-folders")
        if action is not None:
            action.set_enabled(bool(folders))

    def clear_recent_folders(self):
        recent_folders.clear()
        self.show_recent_folders()

    def show_settings(self):
        window = getattr(self, "settings_window", None)
        if window is None:
            window = self.settings_window = drawer_settings.SettingsWindow(self._setting_changed)
            window.set_application(self)
            window.connect("destroy", lambda *_: setattr(self, "settings_window", None))
        window.show_all()
        window.present()

    def _setting_changed(self, key):
        if key == "folders_on_top":
            FOLDERS_ON_TOP[0] = drawer_settings.get(key)
            for window in self.get_windows():
                if isinstance(window, DrawerWindow):
                    window.refresh()

    def do_activate(self):
        DrawerWindow(self, self.start_folder()).show_all()

    def do_open(self, files, _n, _hint):
        # Another app asked (Hatch, Seek, the Dock): the new window comes to
        # the front even when one of Drawer's own windows is there already.
        before = self._my_views()
        if before is not None:
            GLib.timeout_add(120, self._bring_forward, before, 25)
        for file in files:
            path = file.get_path()
            chosen = None
            if path and (os.path.isfile(path) or (SELECT_ONLY[0] and os.path.lexists(path))):
                path, chosen = os.path.dirname(path), path
            window = DrawerWindow(self, path or GLib.get_home_dir())
            window.show_all()
            if chosen:   # opened with a file: show it chosen in its folder
                GLib.idle_add(lambda w=window, c=chosen: w.select_paths([c]) and False)


    @staticmethod
    def _my_views():
        """The ids of Drawer's windows the compositor knows, or None without it."""
        try:
            from .wfipc import Connection
            views = Connection().call("window-rules/list-views")
        except (ConnectionError, OSError, ValueError, ImportError):
            return None
        mine = os.getpid()
        return {v.get("id") for v in views if isinstance(v, dict) and v.get("pid") == mine} \
            if isinstance(views, list) else None

    def _bring_forward(self, before, tries):
        now = self._my_views()
        new = sorted((now or set()) - before)
        if new:
            try:
                from .wfipc import Connection
                Connection().call("window-rules/focus-view", id=new[-1])
            except (ConnectionError, OSError, ValueError):
                pass
            return False
        if tries > 1:
            GLib.timeout_add(120, self._bring_forward, before, tries - 1)
        return False


def main():
    import sys

    GLib.set_prgname("freemac-drawer")
    argv = list(sys.argv)
    if "--select" in argv:
        # freemac-drawer --select PATH: PATH's folder, with PATH chosen,
        # even when PATH is a folder (Show Original on the Desktop).
        argv.remove("--select")
        SELECT_ONLY[0] = True
    Drawer().run(argv)
