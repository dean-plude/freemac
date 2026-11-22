# SPDX-License-Identifier: GPL-3.0-or-later
"""Mission Control's row of desktops, as on a Mac.

While the overview of windows is open (Ctrl+Up, a 4-finger swipe up), the
desktops are named along the top of the screen: "Desktop 1", "Desktop 2"…
with the one you're on picked out. Move the pointer up to them and the row
opens out into small pictures of each desktop, its wallpaper with its
windows on it (pictures of the windows themselves, from strata/snapshot,
filled in one at a time once the row shows); click one to go there.

The overview takes all of the pointer while it's open, so this row never
sees it. Strata does the watching (strata/shell/mission-control.hpp) and
tells Topline over its socket: "spaces open OUTPUT", "spaces close",
"spaces changed" and "spaces pointer X Y". Topline draws the row, works out
which desktop the pointer is over, and tells Strata where each desktop is
drawn (strata/spaces-areas), so that a click there goes to that desktop.
The desktops and their windows come from strata/desktops.

Opened out, the row has a "+" at its right end that adds a desktop, and a
round button on the corner of the desktop under the pointer that closes it
(its windows go to the first desktop). Strata changes the desktops and says
"spaces desktops N"; the count is saved in wayfire.ini as [core] vwidth.
Original freemac code.
"""
import os

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import apps, backdrop, style  # noqa: E402

# Below the menu bar, inside the overview's own spacing from the top.
TOP = 30
# The row as names only, and opened out into pictures.
NAMES_H = 38
PICTURE_H = 92
OPEN_H = PICTURE_H + 44
LABEL_W, LABEL_H, GAP = 112, 26, 12
# How long the row stays open after the pointer leaves it.
CLOSE_MS = 350
REACH = 40          # how far below the names the pointer opens them out
# The "+" at the right end of the opened row, and the button that closes a desktop.
ADD_W = 64
CLOSE_D = 20
MOST_DESKTOPS = 16
WAYFIRE_INI = os.path.join(os.path.expanduser("~/.config"), "wayfire.ini")


def parse(line):
    """("open", output) / ("close",) / ("changed",) / ("pointer", x, y), or None."""
    words = line.split()
    if len(words) < 2 or words[0] != "spaces":
        return None
    kind = words[1]
    if kind == "open" and len(words) == 3:
        return ("open", words[2])
    if kind in ("close", "changed") and len(words) == 2:
        return (kind,)
    if kind == "desktops" and len(words) == 3:
        try:
            count = int(words[2])
        except ValueError:
            return None
        return ("desktops", count) if 1 <= count <= MOST_DESKTOPS else None
    if kind == "pointer" and len(words) == 4:
        try:
            return ("pointer", int(words[2]), int(words[3]))
        except ValueError:
            return None
    return None


def desktop_names(grid):
    """[(x, y, "Desktop N"), …] along the rows of the grid, as a Mac names them."""
    columns, rows = grid
    return [(x, y, "Desktop %d" % (y * columns + x + 1)) for y in range(rows) for x in range(columns)]


def row_boxes(count, width, box_w, box_h, gap, top):
    """Where `count` boxes of box_w × box_h go, centred along a row `width`
    wide, `top` from its top edge: [(x, y, w, h), …]. Shrinks them to fit."""
    if count <= 0:
        return []
    room = width - 2 * gap
    if count * box_w + (count - 1) * gap > room:
        scale = room / (count * box_w + (count - 1) * gap)
        box_w, box_h, gap = int(box_w * scale), int(box_h * scale), max(4, int(gap * scale))
    total = count * box_w + (count - 1) * gap
    left = (width - total) // 2
    return [(left + i * (box_w + gap), top, box_w, box_h) for i in range(count)]


def add_box(width, height, gap, top):
    """Where the "+" goes in the opened row: (x, y, w, h) at its right end."""
    return (width - gap - ADD_W, top, ADD_W, height)


def close_box(box):
    """The round button on a desktop's top-left corner: (x, y, d, d)."""
    x, y, _w, _h = box
    return (x - CLOSE_D // 2 + 2, y - CLOSE_D // 2 + 2, CLOSE_D, CLOSE_D)


def can_change(grid):
    """Desktops are added and closed only along a single row, as on a Mac."""
    return len(grid) == 2 and grid[1] == 1


def save_count(count):
    """The number of desktops, kept for the next time you log in."""
    from .ini import ini_set
    ini_set(WAYFIRE_INI, "core", "vwidth", count)


def scaled_window(geometry, screen, box):
    """A window's place on its desktop, `geometry` = (x, y, w, h) on a screen
    `screen` = (w, h), drawn into `box` = (x, y, w, h); None when it lies
    wholly off the desktop."""
    gx, gy, gw, gh = geometry
    sw, sh = screen
    if sw <= 0 or sh <= 0 or gw <= 0 or gh <= 0:
        return None
    x0, y0 = max(0, gx), max(0, gy)
    x1, y1 = min(sw, gx + gw), min(sh, gy + gh)
    if x1 <= x0 or y1 <= y0:
        return None
    bx, by, bw, bh = box
    return (bx + x0 * bw / sw, by + y0 * bh / sh, (x1 - x0) * bw / sw, (y1 - y0) * bh / sh)


def opaque_box(alphas, width, height, threshold=230):
    """The smallest (x, y, w, h) holding every pixel at least `threshold`
    opaque, from a picture's alpha values row by row; None if there's none.
    A window's picture comes with its soft shadow round it, which a desktop's
    small picture leaves out."""
    rows = [y for y in range(height) if max(alphas[y * width:(y + 1) * width]) >= threshold]
    if not rows:
        return None
    band = alphas[rows[0] * width:(rows[-1] + 1) * width]
    columns = [x for x in range(width) if max(band[x::width]) >= threshold]
    return columns[0], rows[0], columns[-1] - columns[0] + 1, rows[-1] - rows[0] + 1


def without_shadow(pixbuf):
    """The picture cut down to the window itself."""
    if not pixbuf.get_has_alpha() or pixbuf.get_n_channels() != 4:
        return pixbuf
    width, height, stride = pixbuf.get_width(), pixbuf.get_height(), pixbuf.get_rowstride()
    data = pixbuf.get_pixels()
    alphas = b"".join(data[y * stride + 3:y * stride + width * 4:4] for y in range(height))
    box = opaque_box(alphas, width, height)
    if box is None or box == (0, 0, width, height):
        return pixbuf
    return pixbuf.new_subpixbuf(*box)


def _rounded(cr, x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -1.5708, 0)
    cr.arc(x + w - r, y + h - r, r, 0, 1.5708)
    cr.arc(x + r, y + h - r, r, 1.5708, 3.1416)
    cr.arc(x + r, y + r, r, 3.1416, 4.7124)
    cr.close_path()


def _hex(colour):
    colour = colour.lstrip("#")
    return tuple(int(colour[i:i + 2], 16) / 255 for i in (0, 2, 4))


class SpacesRow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Desktops")
        style.make_transparent(self)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self, "freemac-spaces")
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)
        GtkLayerShell.set_exclusive_zone(self, -1)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, TOP)
        self.area = Gtk.DrawingArea()
        self.area.connect("draw", self._draw)
        self.add(self.area)
        self.set_size_request(-1, NAMES_H)
        self.connect("realize", self._pass_clicks)
        self.connect("size-allocate", lambda *_: self._send_areas())
        self.wf = None
        self.output = None
        self.origin = (0, 0)
        self.info = None
        self.opened = False
        self.hover = None
        self.close_timer = 0
        self.wallpaper = None
        self.wallpaper_path = None
        self.icons = {}
        self.boxes = []
        self.add = None
        # Small pictures of the windows, taken one at a time once the row shows.
        self.pictures = {}
        self.to_picture = []
        self.picture_timer = 0

    # Strata's messages -------------------------------------------------

    def handle(self, line):
        message = parse(line)
        if message is None:
            return
        kind = message[0]
        if kind == "open":
            self.output = message[1]
            self.opened, self.hover = False, None
            self._load()
            self._place()
            self.set_size_request(-1, NAMES_H)
            self.show_all()
            self._layout()
        elif kind == "close":
            self._cancel_close()
            self.hide()
            self.info = None
            self.to_picture = []
        elif kind == "changed":
            if self.get_visible():
                self._load()
                self._layout()
        elif kind == "desktops":
            save_count(message[1])
        elif kind == "pointer" and self.get_visible():
            self._pointer(message[1] - self.origin[0], message[2] - self.origin[1] - TOP)

    # Data -------------------------------------------------------------

    def _ipc(self):
        if self.wf is None:
            from .wfipc import Connection
            self.wf = Connection()
        return self.wf

    def _call(self, method, **data):
        try:
            return self._ipc().call(method, **data)
        except (ConnectionError, OSError, ValueError):
            self.wf = None
            return {}

    def _load(self):
        reply = self._call("strata/desktops", output=self.output or "")
        if not isinstance(reply, dict) or "grid" not in reply:
            self.info = None
            return
        self.info = reply
        windows = [w for w in reply.get("windows", []) if isinstance(w, dict) and "id" in w]
        alive = {w["id"] for w in windows}
        self.pictures = {k: v for k, v in self.pictures.items() if k in alive}
        self.to_picture = [w["id"] for w in windows]
        if not self.picture_timer:
            self.picture_timer = GLib.timeout_add(30, self._take_picture)
        path = os.path.expanduser(backdrop.read_settings().get("image") or backdrop.DEFAULT_IMAGE)
        if path != self.wallpaper_path:
            self.wallpaper_path = path
            try:
                self.wallpaper = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, 480, 300, False)
            except GLib.Error:
                self.wallpaper = None

    def _place(self):
        """Show the row on the output the overview is on."""
        display = Gdk.Display.get_default()
        target = None
        for output in self._call("window-rules/list-outputs") or []:
            if isinstance(output, dict) and output.get("name") == self.output:
                target = output.get("geometry")
        if not target:
            return
        for i in range(display.get_n_monitors()):
            monitor = display.get_monitor(i)
            g = monitor.get_geometry()
            if (g.x, g.y) == (target.get("x"), target.get("y")) or display.get_n_monitors() == 1:
                GtkLayerShell.set_monitor(self, monitor)
                self.origin = (target.get("x", 0), target.get("y", 0))
                return

    # Layout and the pointer -------------------------------------------

    def _layout(self):
        if not self.info:
            self.boxes = []
            return
        width = self.get_allocated_width()
        if width < 100:
            width = self.info.get("size", [1280, 800])[0]
        names = desktop_names(self.info["grid"])
        self.add = None
        if self.opened:
            sw, sh = self.info.get("size", [1280, 800])
            pw = int(PICTURE_H * sw / sh) if sh else 147
            room = width
            if can_change(self.info["grid"]) and len(names) < MOST_DESKTOPS:
                # Keep the pictures clear of the "+" on either side, so they stay centred.
                room = width - 2 * (ADD_W + 22)
                self.add = add_box(width, PICTURE_H, 22, 10)
            spots = row_boxes(len(names), room, pw, PICTURE_H, 22, 10)
            shift = (width - room) // 2
            spots = [(x + shift, y, w, h) for x, y, w, h in spots]
        else:
            spots = row_boxes(len(names), width, LABEL_W, LABEL_H, GAP, (NAMES_H - LABEL_H) // 2)
        self.boxes = [(spot, (x, y), name) for spot, (x, y, name) in zip(spots, names)]
        self.area.queue_draw()
        self._send_areas()

    def _send_areas(self):
        if not self.get_visible() or not self.boxes:
            return
        ox, oy = self.origin
        areas = []
        if self.opened and self.add is not None:
            x, y, w, h = self.add
            areas.append([ox + x, oy + TOP + y, w, h, -1, 0])
        if self.opened and can_change(self.info["grid"]) and len(self.boxes) > 1:
            # Before the desktops, so a click on the button closes rather than goes there.
            for i, (box, _desk, _name) in enumerate(self.boxes):
                x, y, w, h = close_box(box)
                areas.append([ox + x, oy + TOP + y, w, h, -2, i])
        for (x, y, w, h), (dx, dy), _name in self.boxes:
            # The name under a picture counts too.
            extra = 24 if self.opened else 0
            areas.append([ox + x, oy + TOP + y, w, h + extra, dx, dy])
        self._call("strata/spaces-areas", areas=areas)

    def _pointer(self, x, y):
        # The names open out a little before the pointer reaches them, so a
        # window dragged up towards them gets there too.
        height = OPEN_H if self.opened else NAMES_H + REACH
        inside = 0 <= y < height
        if inside:
            self._cancel_close()
            if not self.opened:
                self.opened = True
                self.set_size_request(-1, OPEN_H)
                self._layout()
        elif self.opened and not self.close_timer:
            self.close_timer = GLib.timeout_add(CLOSE_MS, self._close_row)
        hover = None
        # The close button pokes out past the picture's corner.
        edge = CLOSE_D // 2 if self.opened else 0
        for i, ((bx, by, bw, bh), _desk, _name) in enumerate(self.boxes):
            if inside and bx - edge <= x < bx + bw and by - edge <= y < by + bh + (24 if self.opened else 0):
                hover = i
        if self.opened and self.add is not None and inside:
            ax, ay, aw, ah = self.add
            if ax <= x < ax + aw and ay <= y < ay + ah:
                hover = "add"
        if hover != self.hover:
            self.hover = hover
            self.area.queue_draw()

    def _cancel_close(self):
        if self.close_timer:
            GLib.source_remove(self.close_timer)
            self.close_timer = 0

    def _close_row(self):
        self.close_timer = 0
        self.opened, self.hover = False, None
        self.set_size_request(-1, NAMES_H)
        self.resize(1, NAMES_H)
        self._layout()
        return False

    def _take_picture(self):
        """One window's picture per tick, so the row shows straight away."""
        if not self.to_picture:
            self.picture_timer = 0
            return False
        view_id = self.to_picture.pop(0)
        from .wfipc import snapshot_dir
        path = os.path.join(snapshot_dir(), "spaces-%d.png" % view_id)
        reply = self._call("strata/snapshot", id=view_id, path=path, size=320)
        if isinstance(reply, dict) and reply.get("result") == "ok":
            try:
                self.pictures[view_id] = without_shadow(GdkPixbuf.Pixbuf.new_from_file(path))
            except GLib.Error:
                pass
            try:
                os.unlink(path)
            except OSError:
                pass
            if self.opened:
                self.area.queue_draw()
        return True

    def _pass_clicks(self, _widget):
        # Strata takes the clicks; the overview gets everything else.
        import cairo
        self.get_window().input_shape_combine_region(cairo.Region(), 0, 0)

    # Drawing -----------------------------------------------------------

    def _icon(self, app_id, size):
        key = (app_id, size)
        if key not in self.icons:
            pixbuf = None
            try:
                info = Gtk.IconTheme.get_default().lookup_by_gicon(
                    apps.icon_for(app_id), size, Gtk.IconLookupFlags.FORCE_SIZE)
                pixbuf = info.load_icon() if info else None
            except (GLib.Error, TypeError):
                pixbuf = None
            self.icons[key] = pixbuf
        return self.icons[key]

    def _draw(self, _widget, cr):
        if not self.info:
            return False
        accent = _hex(dict((n, c) for n, _l, c in style.ACCENTS).get(style.accent(), "#2f7bf5"))
        current = tuple(self.info.get("current", [0, 0]))
        if self.opened:
            # A soft band behind the pictures, like the top of a Mac's Mission Control.
            cr.set_source_rgba(0, 0, 0, 0.28)
            _rounded(cr, 8, 0, self.get_allocated_width() - 16, OPEN_H - 6, 16)
            cr.fill()
        for i, ((x, y, w, h), desk, name) in enumerate(self.boxes):
            here = desk == current
            hovered = i == self.hover
            if self.opened:
                self._draw_desktop(cr, (x, y, w, h), desk)
                if here or hovered:
                    cr.set_line_width(3)
                    cr.set_source_rgba(*(accent if here else (1, 1, 1)), 1 if here else 0.8)
                    _rounded(cr, x - 2, y - 2, w + 4, h + 4, 9)
                    cr.stroke()
                self._label(cr, name, x + w / 2, y + h + 14, bold=here)
                if hovered and can_change(self.info["grid"]) and len(self.boxes) > 1:
                    self._draw_close(cr, close_box((x, y, w, h)))
            else:
                cr.set_source_rgba(1, 1, 1, 0.92 if here else (0.42 if hovered else 0.22))
                _rounded(cr, x, y, w, h, h / 2)
                cr.fill()
                self._label(cr, name, x + w / 2, y + h / 2, bold=here, dark=here)
        if self.opened and self.add is not None:
            self._draw_add(cr, self.add, self.hover == "add")
        return False

    def _draw_add(self, cr, box, hovered):
        x, y, w, h = box
        cr.set_source_rgba(1, 1, 1, 0.34 if hovered else 0.18)
        _rounded(cr, x, y, w, h, 9)
        cr.fill()
        cx, cy, arm = x + w / 2, y + h / 2, 11
        cr.set_source_rgba(1, 1, 1, 0.95)
        cr.set_line_width(3)
        cr.set_line_cap(1)  # round
        cr.move_to(cx - arm, cy)
        cr.line_to(cx + arm, cy)
        cr.move_to(cx, cy - arm)
        cr.line_to(cx, cy + arm)
        cr.stroke()

    def _draw_close(self, cr, box):
        x, y, d, _d = box
        cx, cy, r = x + d / 2, y + d / 2, d / 2
        cr.new_sub_path()
        cr.arc(cx, cy, r, 0, 6.2832)
        cr.set_source_rgba(0.24, 0.24, 0.26, 0.96)
        cr.fill_preserve()
        cr.set_source_rgba(1, 1, 1, 0.5)
        cr.set_line_width(1)
        cr.stroke()
        arm = r * 0.42
        cr.set_source_rgba(1, 1, 1, 0.95)
        cr.set_line_width(2)
        cr.set_line_cap(1)
        cr.move_to(cx - arm, cy - arm)
        cr.line_to(cx + arm, cy + arm)
        cr.move_to(cx + arm, cy - arm)
        cr.line_to(cx - arm, cy + arm)
        cr.stroke()

    def _draw_desktop(self, cr, box, desk):
        x, y, w, h = box
        cr.save()
        _rounded(cr, x, y, w, h, 7)
        cr.clip()
        if self.wallpaper is not None:
            pw, ph = self.wallpaper.get_width(), self.wallpaper.get_height()
            scale = max(w / pw, h / ph)
            cr.translate(x + (w - pw * scale) / 2, y + (h - ph * scale) / 2)
            cr.scale(scale, scale)
            Gdk.cairo_set_source_pixbuf(cr, self.wallpaper, 0, 0)
            cr.paint()
        else:
            cr.set_source_rgb(*backdrop.FALLBACK)
            cr.paint()
        cr.restore()
        screen = tuple(self.info.get("size", [1280, 800]))
        for window in self.info.get("windows", []):
            if tuple(window.get("desktop", [-1, -1])) != desk:
                continue
            spot = scaled_window(tuple(window.get("geometry", [0, 0, 0, 0])), screen, box)
            if spot is None:
                continue
            wx, wy, ww, wh = spot
            cr.set_source_rgba(0, 0, 0, 0.18)
            _rounded(cr, wx, wy + 1, ww, wh, 3)
            cr.fill()
            picture = self.pictures.get(window.get("id"))
            if picture is not None:
                cr.save()
                _rounded(cr, wx, wy, ww, wh, 3)
                cr.clip()
                cr.translate(wx, wy)
                cr.scale(ww / picture.get_width(), wh / picture.get_height())
                Gdk.cairo_set_source_pixbuf(cr, picture, 0, 0)
                cr.paint()
                cr.restore()
                continue
            cr.set_source_rgba(0.97, 0.97, 0.98, 1)
            _rounded(cr, wx, wy, ww, wh, 3)
            cr.fill()
            cr.set_source_rgba(0.82, 0.82, 0.85, 1)
            cr.rectangle(wx, wy, ww, min(5, wh))
            cr.fill()
            size = int(min(ww, wh) * 0.55)
            if size >= 10:
                icon = self._icon(window.get("app-id", ""), min(48, size))
                if icon is not None:
                    Gdk.cairo_set_source_pixbuf(cr, icon, wx + (ww - icon.get_width()) / 2,
                                                wy + (wh - icon.get_height()) / 2)
                    cr.paint()

    def _label(self, cr, text, cx, cy, bold=False, dark=False):
        layout = self.area.create_pango_layout(text)
        from gi.repository import Pango
        description = Pango.FontDescription.from_string("Sans %s 10" % ("Bold" if bold else ""))
        layout.set_font_description(description)
        tw, th = layout.get_pixel_size()
        cr.move_to(cx - tw / 2, cy - th / 2)
        if dark:
            cr.set_source_rgba(0.1, 0.1, 0.12, 1)
        else:
            cr.set_source_rgba(1, 1, 1, 1)
        from gi.repository import PangoCairo
        PangoCairo.show_layout(cr, layout)
