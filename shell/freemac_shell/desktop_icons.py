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

Use Stacks (the right button on the desktop, or Control-Command-0) gathers
files of one kind into a pile: Images, Screenshots, Documents, PDF
Documents, Movies, Music and so on. A click on a stack fans its files out in
place, and another click gathers them up again; new files go straight into
their stack. Clean Up By and Get Info (Command-I) work as on a Mac.

Space opens Glance (drawer_glance.py) on the selected files, and the arrow
keys move the selection from icon to icon.

Edit Widgets… on the same menu puts a clock, the calendar, the weather and
reminders on the desktop (desktop_widgets.py).
"""
import json
import os
import subprocess
from urllib.parse import unquote, urlparse

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango  # noqa: E402

from . import desktop_widgets, drawer_info, quick_actions, recents, tags, transfer, volumes  # noqa: E402
from .drawer_glance import Glance  # noqa: E402

try:
    import cairo
except ImportError:   # only the pictures of the stacks need it
    cairo = None

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
.desk-info { color: #a8d4ff; font-size: 10px; text-shadow: 0 1px 2px rgba(0, 0, 0, 0.75); }
.desk-icon.fanned { background-color: rgba(255, 255, 255, 0.16); }
.desk-icon.stack-open { background-color: rgba(255, 255, 255, 0.28); }
"""

# The kinds files are stacked by, in the order a Mac lists them. Folders
# and drives are never stacked.
STACK_KINDS = ("Documents", "Images", "Movies", "Music", "PDF Documents", "Presentations",
               "Screenshots", "Spreadsheets", "Disk Images", "Developer", "Other")
CODE_ENDINGS = (".py", ".sh", ".c", ".h", ".cpp", ".js", ".ts", ".rs", ".go", ".java", ".rb", ".swift",
                ".m", ".json", ".yaml", ".yml", ".toml", ".html", ".css")


def desktop_dir():
    return GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DESKTOP) or os.path.expanduser("~/Desktop")


def path_of(uri):
    parsed = urlparse(uri)
    return unquote(parsed.path) if parsed.scheme == "file" else None


def load_layout():
    """The saved places of the icons, and whether stacks are on."""
    try:
        with open(LAYOUT) as f:
            data = json.load(f)
        stacks = bool(data.get("stacks", False))
    except (OSError, ValueError, AttributeError):
        return {}, False
    try:
        places = {k: (int(v[0]), int(v[1])) for k, v in data.get("places", {}).items()}
    except (ValueError, AttributeError, TypeError, IndexError):
        places = {}
    return places, stacks


def load_places():
    return load_layout()[0]


def load_item_info():
    """Whether the desktop shows a line of info under each name."""
    try:
        with open(LAYOUT) as f:
            return bool(json.load(f).get("item_info", False))
    except (OSError, ValueError, AttributeError):
        return False


def save_places(places, stacks=False, item_info=False):
    os.makedirs(os.path.dirname(LAYOUT), exist_ok=True)
    tmp = LAYOUT + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"places": {k: list(v) for k, v in places.items()}, "stacks": bool(stacks),
                   "item_info": bool(item_info)}, f, indent=1)
    os.replace(tmp, LAYOUT)


def item_info(path, content_type):
    """The line Show Item Info puts under a name: how many items a folder
    holds, or a picture's width and height, as a Mac's desktop does."""
    if os.path.isdir(path):
        try:
            count = sum(1 for n in os.listdir(path) if not n.startswith("."))
        except OSError:
            return ""
        return f"{count} item{'s' if count != 1 else ''}"
    if (content_type or "").startswith("image/"):
        found = GdkPixbuf.Pixbuf.get_file_info(path)
        if found and found[0] is not None and found[1] > 0:
            return f"{found[1]} \u00d7 {found[2]}"
    return ""


def kind_of(name, path, content_type):
    """The stack a file goes in, or None for a folder."""
    if os.path.isdir(path):
        return None
    kind = (content_type or "").lower()
    low = name.lower()
    if name.startswith(("Screenshot ", "Screen Recording ", "Screen Shot ")):
        return "Screenshots"
    if kind == "application/pdf" or low.endswith(".pdf"):
        return "PDF Documents"
    if kind.startswith("image/"):
        return "Images"
    if kind.startswith("video/"):
        return "Movies"
    if kind.startswith("audio/"):
        return "Music"
    if any(w in kind for w in ("spreadsheet", "excel", "csv")) or low.endswith((".csv", ".xlsx", ".xls", ".ods")):
        return "Spreadsheets"
    if any(w in kind for w in ("presentation", "powerpoint")) or low.endswith((".pptx", ".ppt", ".odp", ".key")):
        return "Presentations"
    if any(w in kind for w in ("cd-image", "disk-image", "apple-diskimage")) or low.endswith((".iso", ".dmg", ".img")):
        return "Disk Images"
    if low.endswith(CODE_ENDINGS):
        return "Developer"
    if (kind.startswith("text/") or any(w in kind for w in ("document", "msword", "rtf", "opendocument.text"))
            or low.endswith((".txt", ".md", ".rtf", ".doc", ".docx", ".odt", ".pages"))):
        return "Documents"
    return "Other"


def stack_picture(cards):
    """Up to three of the files' pictures, piled a little askew. Each card
    is (pixbuf, framed): photos get a white edge, icons stand as they are."""
    cards = [c for c in cards if c[0] is not None][:3]
    if cairo is None or not cards:
        return cards[0][0] if cards else None
    size = ICON
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    cr = cairo.Context(surface)
    tilts = (-0.17, 0.13, 0.0)[-len(cards):]
    for (pixbuf, framed), tilt in zip(reversed(cards), tilts):
        scale = 0.8 * size / max(pixbuf.get_width(), pixbuf.get_height(), 1)
        w, h = pixbuf.get_width() * scale, pixbuf.get_height() * scale
        cr.save()
        cr.translate(size / 2, size / 2)
        cr.rotate(tilt)
        if framed:
            cr.set_source_rgba(0, 0, 0, 0.3)
            cr.rectangle(-w / 2 - 1.5, -h / 2 - 0.5, w + 3, h + 3)
            cr.fill()
            cr.set_source_rgb(1, 1, 1)
            cr.rectangle(-w / 2 - 1.5, -h / 2 - 1.5, w + 3, h + 3)
            cr.fill()
        cr.scale(scale, scale)
        Gdk.cairo_set_source_pixbuf(cr, pixbuf, -pixbuf.get_width() / 2, -pixbuf.get_height() / 2)
        cr.paint()
        cr.restore()
    surface.flush()
    return Gdk.pixbuf_get_from_surface(surface, 0, 0, size, size)


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
        self.content_type = info.get_content_type() if info else ""
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
        self.title = name
        self.show_tags()
        box.pack_start(self.label, False, False, 0)
        # Show Item Info: a picture's size, or how many items a folder holds.
        self.info_label = Gtk.Label(justify=Gtk.Justification.CENTER, halign=Gtk.Align.CENTER)
        self.info_label.get_style_context().add_class("desk-info")
        self.info_label.set_no_show_all(True)
        box.pack_start(self.info_label, False, False, 0)
        self.show_info(getattr(owner, "item_info", False))
        self.add(box)
        self.connect("button-press-event", self._press)
        self.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, URI_TARGETS, Gdk.DragAction.MOVE | Gdk.DragAction.COPY)
        self.connect("drag-begin", self._drag_begin)
        self.connect("drag-data-get", self._drag_data_get)
        self.connect("drag-end", lambda *_: self.owner.drag_ended())

    @property
    def name(self):
        return os.path.basename(self.path)

    def show_tags(self):
        """The name, with a coloured dot for each of the file's tags."""
        names = tags.get(self.path) if self.path else []
        if names:
            self.label.set_markup(tags.markup(self.title, names))
        else:
            self.label.set_text(self.title)

    def show_info(self, on):
        text = item_info(self.path, self.content_type) if on and self.path and type(self) is DesktopIcon else ""
        self.info_label.set_text(text)
        self.info_label.set_visible(bool(text))

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


class StackIcon(DesktopIcon):
    """A pile of files of one kind. A click fans them out on the desktop and
    another gathers them up; dragging it drags all of them."""

    def __init__(self, owner, kind, members):
        self.kind, self.members = kind, list(members)
        super().__init__(owner, "", None, kind, Gio.ThemedIcon.new("folder"))
        self.update(members)

    @property
    def name(self):
        return "stack:" + self.kind

    def update(self, members):
        self.members = list(members)
        cards = [(m.pixbuf, (m.content_type or "").startswith("image/")) for m in self.members[:3]]
        picture = stack_picture(cards)
        if picture is not None:
            self.pixbuf = picture
            image = self.frame.get_children()[0]
            image.set_from_pixbuf(picture)
        count = len(self.members)
        self.set_tooltip_text(f"{self.kind}: {count} item{'s' if count != 1 else ''}")

    def set_open(self, opened):
        (self.frame.get_style_context().add_class if opened else
         self.frame.get_style_context().remove_class)("stack-open")

    def _press(self, _widget, event):
        if event.type == Gdk.EventType._2BUTTON_PRESS:
            return True   # the first press already opened or closed it
        if event.button == 1:
            self.owner.toggle_stack(self.kind)
            return False  # let a drag start
        if event.button == 3:
            self.owner.stack_menu(self, event)
            return True
        return False

    def _drag_begin(self, _widget, context):
        self.owner.drag_started(self)
        if self.pixbuf:
            Gtk.drag_set_icon_pixbuf(context, self.pixbuf, self.pixbuf.get_width() // 2,
                                     self.pixbuf.get_height() // 2)

    def _drag_data_get(self, _widget, _context, data, _info, _time):
        data.set_uris([m.uri for m in self.members])

    @property
    def uri(self):
        return ""


class DesktopIcons(Gtk.Layout):
    def __init__(self, monitor=None):
        super().__init__()
        self.screen_size = None
        if monitor is not None:
            area = monitor.get_geometry()
            self.screen_size = (area.width, area.height)
        self.folder = desktop_dir()
        self.places, self.stacks_on = load_layout()
        self.item_info = load_item_info()
        self.icons = {}           # file name -> DesktopIcon
        self.stack_icons = {}     # kind -> StackIcon, while stacks are on
        self.open_stacks = set()  # the kinds fanned out
        self.selected = []
        self.dragging = None
        self._pending = None
        self.glance = None
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
        self.widgets = desktop_widgets.WidgetHost(self)

    # ---- the grid -----------------------------------------------------------------
    def size(self):
        """The screen's size: our own once GTK has laid us out, else the monitor's."""
        width, height = self.get_allocated_width(), self.get_allocated_height()
        if (width < CELL_W * 3 or height < TOP + BOTTOM + CELL_H * 2) and self.screen_size:
            return self.screen_size
        return width, height

    def rows(self):
        return max(1, (self.size()[1] - TOP - BOTTOM) // self.cell_h)

    def cell_xy(self, cell):
        col, row = cell
        return self.size()[0] - RIGHT - CELL_W * (col + 1), TOP + self.cell_h * row

    def nearest_cell(self, x, y):
        col = round((self.size()[0] - RIGHT - CELL_W - x) / CELL_W)
        row = round((y - TOP) / self.cell_h)
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
        if self.stacks_on:
            self._arrange_stacks()
            return
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
        # Moving a child doesn't always redraw a layer-shell surface by itself.
        self.queue_resize()
        if changed:
            self._save()

    def _arrange_stacks(self):
        """With stacks on, the desktop keeps itself tidy as a Mac's does:
        drives, then folders, then each stack (its files after it when it is
        fanned out), then the files that have no others of their kind."""
        order = sorted((i for n, i in self.icons.items() if n.startswith("drive:")), key=lambda i: i.name)
        stacked = self._stacked()
        loose = [i for i in self.icons.values() if i.mount is None and i not in stacked]
        order += sorted((i for i in loose if os.path.isdir(i.path)), key=lambda i: i.name.lower())
        for kind in STACK_KINDS:
            stack = self.stack_icons.get(kind)
            if stack is None:
                continue
            order.append(stack)
            if kind in self.open_stacks:
                order += stack.members
        order += sorted((i for i in loose if not os.path.isdir(i.path)), key=lambda i: i.name.lower())
        rows = self.rows()
        for n, icon in enumerate(order):
            x, y = self.cell_xy((n // rows, n % rows))
            if self.child_get(icon, "x", "y") != (x + 4, y):
                self.move(icon, x + 4, y)
        self.queue_resize()

    def _stacked(self):
        return {m for stack in self.stack_icons.values() for m in stack.members}

    def _restack(self):
        """Gather the files into stacks by kind (two or more make a stack),
        or put every file back on its own when stacks are off."""
        groups = {}
        if self.stacks_on:
            for name, icon in self.icons.items():
                if icon.mount is None:
                    kind = kind_of(name, icon.path, icon.content_type)
                    if kind:
                        groups.setdefault(kind, []).append(icon)
        groups = {k: sorted(v, key=lambda i: i.name.lower()) for k, v in groups.items() if len(v) >= 2}
        for kind in list(self.stack_icons):
            if kind not in groups:
                stack = self.stack_icons.pop(kind)
                if stack in self.selected:
                    self.selected.remove(stack)
                stack.destroy()
                self.open_stacks.discard(kind)
        for kind, members in groups.items():
            stack = self.stack_icons.get(kind)
            if stack is None:
                stack = StackIcon(self, kind, members)
                self.stack_icons[kind] = stack
                self.put(stack, 0, 0)
                stack.show_all()
            elif stack.members != members:
                stack.update(members)
            stack.set_open(kind in self.open_stacks)
        stacked = {m: k for k, s in self.stack_icons.items() for m in s.members}
        for icon in self.icons.values():
            kind = stacked.get(icon)
            fanned = kind is not None and kind in self.open_stacks
            icon.set_visible(kind is None or fanned)
            (icon.frame.get_style_context().add_class if fanned else
             icon.frame.get_style_context().remove_class)("fanned")
            if kind is not None and not fanned and icon in self.selected:
                self.selected.remove(icon)
                icon.set_selected(False)

    def toggle_stack(self, kind):
        self.grab_focus()
        self.clear_selection()
        if kind in self.open_stacks:
            self.open_stacks.discard(kind)
        else:
            self.open_stacks.add(kind)
        self._restack()
        self._arrange()

    def set_stacks(self, on):
        self.stacks_on = bool(on)
        self.open_stacks.clear()
        self.clear_selection()
        self._restack()
        self._arrange()
        self._save()

    @property
    def cell_h(self):
        # The rows move apart to make room for Show Item Info's extra line.
        return CELL_H + (14 if self.item_info else 0)

    def set_item_info(self, on):
        self.item_info = bool(on)
        for icon in self.icons.values():
            icon.show_info(self.item_info)
        self._arrange()
        self._save()

    def clean_up_by(self, how):
        """Put every icon back on the grid in order, from the top right down."""
        def modified(icon):
            try:
                return -os.stat(icon.path).st_mtime
            except OSError:
                return 0
        keys = {
            "name": lambda i: i.name.lower(),
            "kind": lambda i: ((kind_of(i.name, i.path, i.content_type) or " ").lower(), i.name.lower()),
            "modified": modified,
        }
        files = sorted((i for i in self.icons.values() if i.mount is None), key=keys[how])
        drives = sorted((i for i in self.icons.values() if i.mount is not None), key=lambda i: i.name)
        rows = self.rows()
        self.places = {icon.name: (n // rows, n % rows) for n, icon in enumerate(drives + files)}
        if self.stacks_on:
            self.set_stacks(False)
        self._arrange()
        self._save()

    def get_info(self, icons):
        paths = [icon.path for icon in icons if icon.path]
        if paths:
            drawer_info.show(paths)

    def _save(self):
        try:
            save_places({k: v for k, v in self.places.items() if k in self.icons}, self.stacks_on, self.item_info)
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
        self._restack()
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
            return st.st_mtime_ns, st.st_ctime_ns, st.st_size   # (a new tag changes the ctime)
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
            self._glance_follow()
            return
        if self.selected == [icon]:
            return
        self.clear_selection()
        self.selected = [icon]
        icon.set_selected(True)
        self._glance_follow()

    def clear_selection(self):
        for icon in self.selected:
            icon.set_selected(False)
        self.selected = []

    # ---- Glance (Space) and the arrow keys -----------------------------------------
    def glance_paths(self):
        """The selected files to look at: a stack stands for its files."""
        paths = []
        for icon in self.selected:
            if isinstance(icon, StackIcon):
                paths += [member.path for member in icon.members if member.path]
            elif icon.path:
                paths.append(icon.path)
        return paths

    def toggle_glance(self):
        if self.glance is not None and self.glance.get_visible():
            self.glance.hide()
            return
        paths = self.glance_paths()
        if not paths:
            return
        if self.glance is None:
            self.glance = Glance(None, self._glance_open, on_arrow=self.arrow)
        self.glance.show_paths(paths)

    def _glance_open(self, path):
        self.glance.hide()
        icons = [icon for icon in self.icons.values() if icon.path == path]
        if icons:
            self.open(icons)
        else:
            try:
                Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(path).get_uri(), None)
            except GLib.Error:
                pass

    def _glance_follow(self):
        if self.glance is not None and self.glance.get_visible():
            paths = self.glance_paths()
            if paths and paths != self.glance.paths:
                self.glance.show_paths(paths)

    def arrow(self, key):
        """Select the nearest icon left, right, above or below the selected
        one (the top-right icon when none is), as the Mac's desktop does."""
        shown = [icon for icon in list(self.icons.values()) + list(self.stack_icons.values())
                 if icon.get_visible() and icon.get_parent() is self]
        if not shown:
            return

        def where(icon):
            return self.child_get_property(icon, "x"), self.child_get_property(icon, "y")

        if not self.selected:
            pick = min(shown, key=lambda i: (where(i)[1], -where(i)[0]))
        else:
            x0, y0 = where(self.selected[-1])
            dx, dy = {Gdk.KEY_Left: (-1, 0), Gdk.KEY_Right: (1, 0),
                      Gdk.KEY_Up: (0, -1), Gdk.KEY_Down: (0, 1)}[key]
            best = None
            for icon in shown:
                x, y = where(icon)
                ahead = (x - x0) * dx + (y - y0) * dy
                if icon is self.selected[-1] or ahead <= 0:
                    continue
                aside = abs((x - x0) * dy) + abs((y - y0) * dx)
                score = ahead + aside * 3
                if best is None or score < best[0]:
                    best = (score, icon)
            if best is None:
                return
            pick = best[1]
        self.click(pick, False)

    def open(self, icons):
        for icon in icons:
            if icon.mount is not None and icon.path:
                subprocess.Popen(["freemac-drawer", icon.path], start_new_session=True)
                continue
            try:
                Gio.AppInfo.launch_default_for_uri(icon.uri, None)
                if icon.path and not os.path.isdir(icon.path):
                    recents.note(icon.path)
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
        elif key in (Gdk.KEY_i, Gdk.KEY_I) and event.state & Gdk.ModifierType.CONTROL_MASK:
            self.get_info(files)
        elif key in (Gdk.KEY_0, Gdk.KEY_KP_0) and event.state & Gdk.ModifierType.CONTROL_MASK:
            self.set_stacks(not self.stacks_on)
        elif key == Gdk.KEY_o and event.state & Gdk.ModifierType.CONTROL_MASK:
            self.open(list(self.selected))
        elif key == Gdk.KEY_a and event.state & Gdk.ModifierType.CONTROL_MASK:
            self.clear_selection()
            for icon in self.icons.values():
                if icon.get_visible():
                    self.selected.append(icon)
                    icon.set_selected(True)
        elif key == Gdk.KEY_space and self.selected:
            self.toggle_glance()
        elif key in (Gdk.KEY_Left, Gdk.KEY_Right, Gdk.KEY_Up, Gdk.KEY_Down) and not event.state & (
                Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK):
            self.arrow(key)
        elif key == Gdk.KEY_Escape:
            self.clear_selection()
        else:
            return False
        return True

    # ---- menus ----------------------------------------------------------------------------
    def _menu(self, items, event):
        menu = self._fill(Gtk.Menu(), items)
        menu.attach_to_widget(self, None)
        menu.show_all()
        menu.popup_at_pointer(event)
        return menu

    def _fill(self, menu, items):
        """Items are (label, action); an action that is (True/False, action)
        is a tick."""
        for label, action in items:
            if label is None:
                menu.append(Gtk.SeparatorMenuItem())
                continue
            if label == "\0tags":   # the row of tag colours
                menu.append(tags.menu_item(action, self._tags_changed))
                continue
            if isinstance(action, tuple):
                item = Gtk.CheckMenuItem(label=label, active=action[0])
                item.connect("activate", lambda _i, a=action[1]: a())
            else:
                item = Gtk.MenuItem(label=label)
                item.connect("activate", lambda _i, a=action: a())
            menu.append(item)
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
        items += [("Get Info", lambda: self.get_info(icons)), ("Show in Drawer", self.show_folder),
                  ("Glance" if len(icons) == 1 else f"Glance at {len(icons)} Items", self.toggle_glance), (None, None),
                  ("\0tags", [i.path for i in icons]), (None, None),
                  ] + self._quick_items([i.path for i in icons]) + [
                  (f"New Folder with Selection ({len(icons)} Item{'s' if len(icons) != 1 else ''})",
                   lambda: self.new_folder_with(icons)),
                  ("Duplicate", lambda: self.run_job([i.path for i in icons], self.folder, duplicate=True)),
                  ("Copy", lambda: transfer.copy_files([i.path for i in icons])), (None, None),
                  ("Move to Trash", lambda: self.trash(icons))]
        self.menu = self._menu(items, event)

    def _tags_changed(self, error):
        if error is not None:
            from . import alert
            alert.ask(None, "The tags couldn’t be changed.",
                      "This disk can’t keep tags." if error.errno in (1, 95) else error.strerror or "")
        for icon in self.icons.values():
            if type(icon) is DesktopIcon:
                icon.show_tags()

    def desktop_menu(self, event):
        # Spelled out rather than a submenu: a submenu of the desktop's menu
        # does not take the pointer under Wayland.
        clean_up = [("Clean Up By Name", lambda: self.clean_up_by("name")),
                    ("Clean Up By Kind", lambda: self.clean_up_by("kind")),
                    ("Clean Up By Date Modified", lambda: self.clean_up_by("modified"))]
        items = [("New Folder", self.new_folder), ("Paste Item", self.paste), (None, None),
                 ("Change Wallpaper…", self.change_wallpaper), ("Edit Widgets…", self.widgets.edit), (None, None),
                 ("Use Stacks", (self.stacks_on, lambda: self.set_stacks(not self.stacks_on))),
                 ("Show Item Info", (self.item_info, lambda: self.set_item_info(not self.item_info)))]
        if not self.stacks_on:
            items += [(None, None)] + clean_up
        self.menu = self._menu(items, event)

    def stack_menu(self, stack, event):
        opened = stack.kind in self.open_stacks
        self.menu = self._menu([
            ("Collapse Stack" if opened else "Expand Stack", lambda: self.toggle_stack(stack.kind)),
            ("Get Info", lambda: self.get_info(stack.members)),
            ("Glance", lambda: (self.click(stack, False), self.toggle_glance())), (None, None),
            ("Move to Trash", lambda: self.trash(list(stack.members))), (None, None),
            ("Use Stacks", (True, lambda: self.set_stacks(False)))], event)

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

    def _quick_items(self, paths):
        """Quick Actions for pictures, spelled out (no submenus on the desktop)."""
        if not quick_actions.can_make_pdf(paths):
            return []
        items = []
        if quick_actions.can_rotate(paths):
            items += [("Rotate Left", lambda: self._rotate(paths, False)),
                      ("Rotate Right", lambda: self._rotate(paths, True))]
        return items + [("Create PDF", lambda: self._make_pdf(paths)), (None, None)]

    def _rotate(self, paths, clockwise):
        quick_actions.rotate(paths, clockwise)
        self.refresh()

    def _make_pdf(self, paths):
        pdf, _error = quick_actions.make_pdf(paths)
        self.refresh()
        icon = self.icons.get(os.path.basename(pdf)) if pdf else None
        if icon:
            self.click(icon, False)

    def new_folder_with(self, icons):
        """New Folder with Selection: the chosen icons go into a new folder."""
        folder, _error = transfer.folder_with([i.path for i in icons])
        self.refresh()
        icon = self.icons.get(os.path.basename(folder)) if folder else None
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
                # place next to it. (With stacks on, the desktop keeps its own order.)
                if self.stacks_on:
                    continue
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
