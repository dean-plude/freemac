# SPDX-License-Identifier: GPL-3.0-or-later
"""Lantern: freemac's presentations.

A presentation is a row of slides. Each slide has a title, some points and,
if you like, a picture; the slide's layout puts them in place and the theme
colours them. Play shows the slides full screen, moved on with the arrow keys,
the space bar or a click. Presentations are kept as .lantern files (JSON, with
the pictures inside so a file can be copied to another computer), and can be
saved as PDF to print or hand in. Original freemac code and themes.
"""
import base64
import copy
import json
import math
import os
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import alert, menus, savesheet, spelling, style  # noqa: E402

APP_ID = "org.freemac.Lantern"
W, H = 1600, 900            # a slide's own size; it is scaled to fit wherever it's drawn
THUMB_W = 168
LAYOUTS = (("title", "Title"), ("points", "Title and Points"), ("picture", "Title and Picture"),
           ("both", "Points and Picture"), ("blank-picture", "Picture Only"))
MAX_PICTURE = 8 * 1024 * 1024

# Each theme: background stops (top, bottom), title colour, text colour, accent.
THEMES = {
    "paper": {"name": "Paper", "bg": ((1, 1, 1), (0.95, 0.95, 0.96)), "title": (0.10, 0.11, 0.13),
              "text": (0.24, 0.25, 0.28), "accent": (0.13, 0.46, 0.93), "font": "Sans"},
    "midnight": {"name": "Midnight", "bg": ((0.09, 0.11, 0.20), (0.03, 0.04, 0.08)), "title": (1, 1, 1),
                 "text": (0.80, 0.83, 0.92), "accent": (0.45, 0.70, 1.0), "font": "Sans"},
    "meadow": {"name": "Meadow", "bg": ((0.86, 0.96, 0.86), (0.62, 0.85, 0.64)), "title": (0.07, 0.30, 0.15),
               "text": (0.12, 0.27, 0.17), "accent": (0.95, 0.60, 0.12), "font": "Sans"},
    "sunset": {"name": "Sunset", "bg": ((1.0, 0.62, 0.35), (0.86, 0.27, 0.48)), "title": (1, 1, 1),
               "text": (1, 0.96, 0.93), "accent": (1, 0.93, 0.45), "font": "Sans"},
    "chalk": {"name": "Chalkboard", "bg": ((0.17, 0.30, 0.24), (0.11, 0.21, 0.16)), "title": (0.98, 0.98, 0.92),
              "text": (0.90, 0.92, 0.85), "accent": (0.99, 0.85, 0.35), "font": "Serif"},
    "ocean": {"name": "Ocean", "bg": ((0.10, 0.52, 0.80), (0.04, 0.27, 0.52)), "title": (1, 1, 1),
              "text": (0.88, 0.95, 1.0), "accent": (0.55, 0.95, 0.85), "font": "Sans"},
}

CSS = b"""
.lantern-side { background-color: alpha(@theme_fg_color, 0.04); border-right: 1px solid alpha(@theme_fg_color, 0.1); }
.lantern-side row { padding: 6px 10px; border-radius: 8px; margin: 2px 6px; }
.lantern-side row:selected { background-color: alpha(@theme_selected_bg_color, 0.25); }
.lantern-number { font-size: 11px; color: alpha(@theme_fg_color, 0.6); }
.lantern-stage { background-color: alpha(@theme_fg_color, 0.08); }
.lantern-inspector { padding: 14px; border-left: 1px solid alpha(@theme_fg_color, 0.1); }
.lantern-inspector .heading { font-weight: 600; font-size: 12px; color: alpha(@theme_fg_color, 0.65); }
.lantern-points { border: 1px solid alpha(@theme_fg_color, 0.18); border-radius: 6px; }
"""


def new_slide(layout="points"):
    return {"layout": layout, "title": "", "points": "", "picture": None}


def new_presentation():
    first = new_slide("title")
    return {"version": 1, "theme": "paper", "slides": [first]}


# --- drawing ---------------------------------------------------------------------------------
_picture_cache = {}


def picture_pixbuf(data):
    """A GdkPixbuf from a slide's picture (base64 text), or None."""
    if not data:
        return None
    key = hash(data)
    if key in _picture_cache:
        return _picture_cache[key]
    try:
        loader = GdkPixbuf.PixbufLoader()
        loader.write(base64.b64decode(data))
        loader.close()
        pixbuf = loader.get_pixbuf()
        pixbuf = pixbuf.apply_embedded_orientation() or pixbuf
    except (GLib.Error, ValueError):
        pixbuf = None
    if len(_picture_cache) > 40:
        _picture_cache.clear()
    _picture_cache[key] = pixbuf
    return pixbuf


def _layout(cr, text, font, size, width, bold=False, align=Pango.Alignment.LEFT):
    layout = PangoCairo.create_layout(cr)
    desc = Pango.FontDescription.from_string(font)
    desc.set_absolute_size(size * Pango.SCALE)
    if bold:
        desc.set_weight(Pango.Weight.BOLD)
    layout.set_font_description(desc)
    layout.set_width(int(width * Pango.SCALE))
    layout.set_wrap(Pango.WrapMode.WORD_CHAR)
    layout.set_alignment(align)
    layout.set_text(text, -1)
    return layout


def _fit(cr, text, font, size, width, height, bold=False, align=Pango.Alignment.LEFT, smallest=18):
    """A layout of `text` whose size comes down until it fits the box."""
    while True:
        layout = _layout(cr, text, font, size, width, bold, align)
        if layout.get_pixel_size()[1] <= height or size <= smallest:
            return layout, size
        size = max(smallest, int(size * 0.9))


def _picture(cr, data, x, y, w, h):
    pixbuf = picture_pixbuf(data)
    if pixbuf is None:
        return
    pw, ph = pixbuf.get_width(), pixbuf.get_height()
    scale = min(w / pw, h / ph)
    dw, dh = pw * scale, ph * scale
    left, top = x + (w - dw) / 2, y + (h - dh) / 2
    cr.save()
    cr.set_source_rgba(0, 0, 0, 0.22)
    rounded(cr, left + 4, top + 8, dw, dh, 14)
    cr.fill()
    rounded(cr, left, top, dw, dh, 14)
    cr.clip()
    cr.translate(left, top)
    cr.scale(scale, scale)
    Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
    cr.get_source().set_filter(1)  # cairo.FILTER_GOOD
    cr.paint()
    cr.restore()


def rounded(cr, x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


def draw_slide(cr, slide, theme_key, placeholders=False):
    """Draw one slide into a W×H box at the origin."""
    import cairo
    theme = THEMES.get(theme_key, THEMES["paper"])
    gradient = cairo.LinearGradient(0, 0, 0, H)
    gradient.add_color_stop_rgb(0, *theme["bg"][0])
    gradient.add_color_stop_rgb(1, *theme["bg"][1])
    cr.set_source(gradient)
    cr.rectangle(0, 0, W, H)
    cr.fill()
    font = theme["font"]
    layout_kind = slide.get("layout", "points")
    title = slide.get("title", "")
    points = [p.strip() for p in slide.get("points", "").split("\n") if p.strip()]
    picture = slide.get("picture")
    hint = (*theme["text"], 0.35)

    def text(layout, x, y, colour):
        cr.set_source_rgba(*colour) if len(colour) == 4 else cr.set_source_rgb(*colour)
        cr.move_to(x, y)
        PangoCairo.show_layout(cr, layout)

    if layout_kind == "title":
        shown = title or ("Click to add a title" if placeholders else "")
        layout, _size = _fit(cr, shown, font, 112, W - 240, 420, bold=True, align=Pango.Alignment.CENTER)
        tw, th = layout.get_pixel_size()
        top = (H - th) / 2 - (60 if points else 0)
        text(layout, 120, top, theme["title"] if title else hint)
        cr.set_source_rgb(*theme["accent"])
        rounded(cr, W / 2 - 60, top + th + 28, 120, 8, 4)
        cr.fill()
        subtitle = "\n".join(points) or ("Add a subtitle in Points" if placeholders else "")
        if subtitle:
            sub, _s = _fit(cr, subtitle, font, 48, W - 320, 220, align=Pango.Alignment.CENTER)
            text(sub, 160, top + th + 72, theme["text"] if points else hint)
        return
    if layout_kind == "blank-picture":
        if picture:
            _picture(cr, picture, 60, 60, W - 120, H - 120)
        elif placeholders:
            _picture_hint(cr, 60, 60, W - 120, H - 120, hint, font)
        return

    # a title across the top
    shown = title or ("Click to add a title" if placeholders else "")
    layout, _size = _fit(cr, shown, font, 76, W - 200, 200, bold=True)
    text(layout, 100, 70, theme["title"] if title else hint)
    title_h = max(layout.get_pixel_size()[1], 90)
    if shown:
        cr.set_source_rgb(*theme["accent"])
        rounded(cr, 100, 70 + title_h + 18, 90, 7, 3.5)
        cr.fill()
        top = 70 + title_h + 64
    else:
        top = 70
    space = H - top - 70
    with_picture = layout_kind in ("picture", "both")
    with_points = layout_kind in ("points", "both")
    text_w = W - 200
    if with_picture and with_points:
        text_w = (W - 200) * 0.52
    if with_points:
        shown_points = points or (["Type your points, one on each line"] if placeholders else [])
        colour = theme["text"] if points else hint
        _bullets(cr, shown_points, font, 100, top, text_w, space, colour, theme["accent"] if points else hint)
    if with_picture:
        if with_points:
            box = (100 + text_w + 50, top, W - 200 - text_w - 50, space)
        else:
            box = (100, top, W - 200, space)
        if picture:
            _picture(cr, picture, *box)
        elif placeholders:
            _picture_hint(cr, *box, hint, font)


def _bullets(cr, points, font, x, y, width, height, colour, dot):
    size = 52
    while True:
        layouts = [_layout(cr, p, font, size, width - size * 1.1) for p in points]
        gap = size * 0.55
        total = sum(l.get_pixel_size()[1] for l in layouts) + gap * max(0, len(layouts) - 1)
        if total <= height or size <= 20:
            break
        size = max(20, int(size * 0.9))
    for layout in layouts:
        line = layout.get_iter().get_baseline() / Pango.SCALE
        cr.set_source_rgb(*dot) if len(dot) == 3 else cr.set_source_rgba(*dot)
        cr.arc(x + size * 0.28, y + line - size * 0.32, size * 0.14, 0, 2 * math.pi)
        cr.fill()
        cr.set_source_rgb(*colour) if len(colour) == 3 else cr.set_source_rgba(*colour)
        cr.move_to(x + size * 1.1, y)
        PangoCairo.show_layout(cr, layout)
        y += layout.get_pixel_size()[1] + size * 0.55
        if y > H:
            break


def _picture_hint(cr, x, y, w, h, colour, font):
    cr.set_source_rgba(*colour)
    cr.set_line_width(4)
    cr.set_dash([16, 12])
    rounded(cr, x, y, w, h, 18)
    cr.stroke()
    cr.set_dash([])
    layout = _layout(cr, "Choose a picture", font, 40, w, align=Pango.Alignment.CENTER)
    cr.move_to(x, y + (h - layout.get_pixel_size()[1]) / 2)
    PangoCairo.show_layout(cr, layout)


def paint_scaled(cr, slide, theme, width, height, placeholders=False):
    """Draw a slide centred and scaled into a width×height area."""
    scale = min(width / W, height / H)
    cr.save()
    cr.translate((width - W * scale) / 2, (height - H * scale) / 2)
    cr.scale(scale, scale)
    cr.rectangle(0, 0, W, H)
    cr.clip()
    draw_slide(cr, slide, theme, placeholders)
    cr.restore()
    return scale


# --- the full-screen show ------------------------------------------------------------------------
class Show(Gtk.Window):
    def __init__(self, document, start=0):
        super().__init__(title="Lantern")
        self.document = document
        self.index = start
        self.set_decorated(False)
        self.set_app_paintable(True)
        self.area = Gtk.DrawingArea()
        self.area.connect("draw", self._draw)
        self.area.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.area.connect("button-press-event", self._click)
        self.add(self.area)
        self.connect("key-press-event", self._key)
        self.fullscreen()
        self.show_all()
        self.present()
        window = self.get_window()
        if window:
            window.set_cursor(Gdk.Cursor.new_from_name(window.get_display(), "none"))

    def _count(self):
        return len(self.document["slides"])

    def _draw(self, widget, cr):
        width, height = widget.get_allocated_width(), widget.get_allocated_height()
        cr.set_source_rgb(0, 0, 0)
        cr.paint()
        if self.index >= self._count():
            layout = _layout(cr, "End of show. Click or press Esc to leave.", "Sans", 22, width,
                             align=Pango.Alignment.CENTER)
            cr.set_source_rgba(1, 1, 1, 0.6)
            cr.move_to(0, height / 2 - 14)
            PangoCairo.show_layout(cr, layout)
            return False
        paint_scaled(cr, self.document["slides"][self.index], self.document["theme"], width, height)
        return False

    def go(self, step):
        self.index = max(0, min(self._count(), self.index + step))
        self.area.queue_draw()

    def _click(self, _widget, event):
        if self.index >= self._count():
            self.destroy()
        elif event.button == 3:
            self.go(-1)
        else:
            self.go(1)
        return True

    def _key(self, _widget, event):
        key = event.keyval
        if key in (Gdk.KEY_Escape, Gdk.KEY_q):
            self.destroy()
        elif key in (Gdk.KEY_Right, Gdk.KEY_Down, Gdk.KEY_space, Gdk.KEY_Page_Down, Gdk.KEY_Return, Gdk.KEY_n):
            if self.index >= self._count():
                self.destroy()
            else:
                self.go(1)
        elif key in (Gdk.KEY_Left, Gdk.KEY_Up, Gdk.KEY_Page_Up, Gdk.KEY_BackSpace, Gdk.KEY_p):
            self.go(-1)
        elif key == Gdk.KEY_Home:
            self.index = 0
            self.area.queue_draw()
        elif key == Gdk.KEY_End:
            self.index = self._count() - 1
            self.area.queue_draw()
        return True


# --- the editing window ----------------------------------------------------------------------------
class Thumb(Gtk.ListBoxRow):
    def __init__(self, window):
        super().__init__()
        self.win = window
        box = Gtk.Box(spacing=8)
        self.number = Gtk.Label(xalign=1, valign=Gtk.Align.START)
        self.number.set_size_request(18, -1)
        self.number.get_style_context().add_class("lantern-number")
        self.area = Gtk.DrawingArea()
        self.area.set_size_request(THUMB_W, int(THUMB_W * H / W))
        self.area.connect("draw", self._draw)
        box.pack_start(self.number, False, False, 0)
        box.pack_start(self.area, False, False, 0)
        self.add(box)

    def _draw(self, widget, cr):
        index = self.get_index()
        slides = self.win.doc["slides"]
        if not 0 <= index < len(slides):
            return False
        width, height = widget.get_allocated_width(), widget.get_allocated_height()
        cr.set_source_rgba(0, 0, 0, 0.25)
        cr.rectangle(0, 1, width, height)
        cr.fill()
        paint_scaled(cr, slides[index], self.win.doc["theme"], width, height)
        self.number.set_text(str(index + 1))
        return False


class Window(Gtk.ApplicationWindow):
    def __init__(self, app, path=None):
        super().__init__(application=app, title="Untitled")
        self.set_default_size(1180, 720)
        self.doc = new_presentation()
        self.path = None
        self.modified = False
        self.current = 0
        self.undo_stack, self.redo_stack = [], []
        self._typing = None       # (slide index, field) being typed in, so typing undoes as one step
        self._loading = False

        header = Gtk.HeaderBar(show_close_button=True)
        self.header = header
        self.set_titlebar(header)
        add = Gtk.MenuButton()
        add_box = Gtk.Box(spacing=4)
        add_box.pack_start(Gtk.Image.new_from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON), False, False, 0)
        add_box.pack_start(Gtk.Label(label="Add Slide"), False, False, 0)
        add.add(add_box)
        add.set_popover(self._popover([(label, lambda k=key: self.add_slide(k)) for key, label in LAYOUTS]))
        header.pack_start(add)
        play = Gtk.Button()
        play_box = Gtk.Box(spacing=4)
        play_box.pack_start(Gtk.Image.new_from_icon_name("media-playback-start-symbolic", Gtk.IconSize.BUTTON),
                            False, False, 0)
        play_box.pack_start(Gtk.Label(label="Play"), False, False, 0)
        play.add(play_box)
        play.set_tooltip_text("Show the slides full screen (⌥⌘P)")
        play.connect("clicked", lambda _b: self.play())
        header.pack_start(play)
        save = Gtk.Button(label="Save")
        save.get_style_context().add_class("suggested-action")
        save.connect("clicked", lambda _b: self.save())
        header.pack_end(save)
        theme = Gtk.MenuButton()
        theme_box = Gtk.Box(spacing=4)
        theme_box.pack_start(Gtk.Image.new_from_icon_name("applications-graphics-symbolic", Gtk.IconSize.BUTTON),
                             False, False, 0)
        theme_box.pack_start(Gtk.Label(label="Theme"), False, False, 0)
        theme.add(theme_box)
        theme.set_popover(self._theme_popover())
        header.pack_end(theme)

        panes = Gtk.Box()
        self.add(panes)
        side_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        side_scroll.get_style_context().add_class("lantern-side")
        side_scroll.set_size_request(THUMB_W + 56, -1)
        self.list = Gtk.ListBox()
        self.list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.list.connect("row-selected", self._row_selected)
        self.list.add_events(Gdk.EventMask.KEY_PRESS_MASK)
        self.list.connect("key-press-event", self._list_key)
        self.list.connect("button-press-event", self._list_press)
        side_scroll.add(self.list)
        panes.pack_start(side_scroll, False, False, 0)

        self.stage = Gtk.DrawingArea()
        self.stage.get_style_context().add_class("lantern-stage")
        self.stage.connect("draw", self._draw_stage)
        self.stage.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.stage.connect("button-press-event", self._stage_click)
        panes.pack_start(self.stage, True, True, 0)

        inspector = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        inspector.get_style_context().add_class("lantern-inspector")
        inspector.set_size_request(280, -1)

        def heading(text):
            label = Gtk.Label(label=text, xalign=0)
            label.get_style_context().add_class("heading")
            return label

        inspector.pack_start(heading("Layout"), False, False, 0)
        self.layout_combo = Gtk.ComboBoxText()
        for key, label in LAYOUTS:
            self.layout_combo.append(key, label)
        self.layout_combo.connect("changed", self._layout_changed)
        inspector.pack_start(self.layout_combo, False, False, 0)
        inspector.pack_start(heading("Title"), False, False, 6)
        self.title_entry = Gtk.Entry(placeholder_text="The slide's title")
        self.title_entry.connect("changed", lambda e: self._typed("title", e.get_text()))
        inspector.pack_start(self.title_entry, False, False, 0)
        self.points_heading = heading("Points (one on each line)")
        inspector.pack_start(self.points_heading, False, False, 6)
        self.points_view = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=6, right_margin=6,
                                        top_margin=6, bottom_margin=6)
        spelling.attach(self.points_view)
        self.points_view.get_buffer().connect("changed", self._points_changed)
        points_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        points_scroll.get_style_context().add_class("lantern-points")
        points_scroll.set_min_content_height(160)
        points_scroll.add(self.points_view)
        inspector.pack_start(points_scroll, True, True, 0)
        inspector.pack_start(heading("Picture"), False, False, 6)
        pictures = Gtk.Box(spacing=6)
        choose = Gtk.Button(label="Choose…")
        choose.connect("clicked", lambda _b: self.choose_picture())
        self.remove_picture = Gtk.Button(label="Remove")
        self.remove_picture.connect("clicked", lambda _b: self.set_picture(None))
        pictures.pack_start(choose, True, True, 0)
        pictures.pack_start(self.remove_picture, True, True, 0)
        inspector.pack_start(pictures, False, False, 0)
        panes.pack_start(inspector, False, False, 0)

        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        menus.add_actions(self, {
            "open": self.open_dialog, "save": self.save, "save-as": self.save_as, "export-pdf": self.export_pdf,
            "close": self.close, "undo": self.undo, "redo": self.redo, "play": self.play,
            "play-start": lambda: self.play(0),
            "new-slide": lambda: self.add_slide("points"), "duplicate": self.duplicate_slide,
            "delete-slide": self.delete_slide, "move-up": lambda: self.move_slide(-1),
            "move-down": lambda: self.move_slide(1), "picture": self.choose_picture,
        })
        self.connect("delete-event", lambda *_: not self.confirm_close())
        self.connect("key-press-event", self._window_key)
        if path:
            self.load(path)
        self.rebuild()

    def _popover(self, entries):
        popover = Gtk.Popover()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        for text, callback in entries:
            item = Gtk.ModelButton(text=text)
            item.connect("clicked", lambda _b, c=callback: (popover.popdown(), c()))
            box.pack_start(item, False, False, 0)
        box.show_all()
        popover.add(box)
        return popover

    def _theme_popover(self):
        popover = Gtk.Popover()
        grid = Gtk.FlowBox(max_children_per_line=3, min_children_per_line=3, selection_mode=Gtk.SelectionMode.NONE,
                           margin=8, row_spacing=6, column_spacing=6)
        sample = {"layout": "points", "title": "Title", "points": "A point\nAnother", "picture": None}
        for key, theme in THEMES.items():
            button = Gtk.Button()
            button.set_relief(Gtk.ReliefStyle.NONE)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            area = Gtk.DrawingArea()
            area.set_size_request(128, 72)
            area.connect("draw", lambda w, cr, k=key: paint_scaled(cr, sample, k, w.get_allocated_width(),
                                                                    w.get_allocated_height()) and False)
            box.pack_start(area, False, False, 0)
            box.pack_start(Gtk.Label(label=theme["name"]), False, False, 0)
            button.add(box)
            button.connect("clicked", lambda _b, k=key: (popover.popdown(), self.set_theme(k)))
            grid.add(button)
        grid.show_all()
        popover.add(grid)
        return popover

    # --- showing the document ------------------------------------------------------------
    def slide(self):
        return self.doc["slides"][self.current]

    def rebuild(self):
        """Make the thumbnails match the slides."""
        rows = self.list.get_children()
        count = len(self.doc["slides"])
        for row in rows[count:]:
            self.list.remove(row)
        for _ in range(len(rows), count):
            self.list.add(Thumb(self))
        self.list.show_all()
        self.current = max(0, min(self.current, count - 1))
        row = self.list.get_row_at_index(self.current)
        if row is not self.list.get_selected_row():
            self.list.select_row(row)
        self._show_current()
        for row in self.list.get_children():
            row.area.queue_draw()

    def _show_current(self):
        slide = self.slide()
        self._loading = True
        self.layout_combo.set_active_id(slide.get("layout", "points"))
        if self.title_entry.get_text() != slide.get("title", ""):
            self.title_entry.set_text(slide.get("title", ""))
        buffer = self.points_view.get_buffer()
        if buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), False) != slide.get("points", ""):
            buffer.set_text(slide.get("points", ""))
        self.remove_picture.set_sensitive(bool(slide.get("picture")))
        layout = slide.get("layout", "points")
        self.points_heading.set_text("Subtitle" if layout == "title" else "Points (one on each line)")
        self._loading = False
        self.stage.queue_draw()

    def _redraw_current(self):
        self.stage.queue_draw()
        row = self.list.get_row_at_index(self.current)
        if row:
            row.area.queue_draw()

    def _draw_stage(self, widget, cr):
        width, height = widget.get_allocated_width(), widget.get_allocated_height()
        margin = 36
        scale = min((width - 2 * margin) / W, (height - 2 * margin) / H)
        if scale <= 0:
            return False
        sw, sh = W * scale, H * scale
        x, y = (width - sw) / 2, (height - sh) / 2
        cr.set_source_rgba(0, 0, 0, 0.18)
        cr.rectangle(x + 2, y + 6, sw, sh)
        cr.fill()
        cr.save()
        cr.translate(x, y)
        paint_scaled(cr, self.slide(), self.doc["theme"], sw, sh, placeholders=True)
        cr.restore()
        self._stage_box = (x, y, sw, sh)
        return False

    def _stage_click(self, _widget, event):
        box = getattr(self, "_stage_box", None)
        if not box:
            return False
        x, y, sw, sh = box
        sx, sy = (event.x - x) / sw * W, (event.y - y) / sh * H
        if not (0 <= sx <= W and 0 <= sy <= H):
            return False
        layout = self.slide().get("layout")
        on_picture = (layout == "blank-picture" or (layout == "picture" and sy > 260)
                      or (layout == "both" and sx > W * 0.58 and sy > 260))
        if on_picture:
            if event.type == Gdk.EventType._2BUTTON_PRESS or not self.slide().get("picture"):
                self.choose_picture()
        elif (layout == "title" and sy < H * 0.55) or (layout != "title" and sy < 260):
            self.title_entry.grab_focus()
        else:
            self.points_view.grab_focus()
        return True

    # --- edits -----------------------------------------------------------------------------
    def _snapshot(self):
        return (copy.deepcopy(self.doc), self.current)

    def _record(self, typing=None):
        """Remember how things were before a change, for Undo. Typing in the
        same field of the same slide stays one step."""
        if typing is not None and typing == self._typing:
            return
        self._typing = typing
        self.undo_stack.append(self._snapshot())
        del self.undo_stack[:-100]
        self.redo_stack.clear()

    def _changed(self):
        self.modified = True
        self._update_title()

    def _typed(self, field, value):
        if self._loading or self.slide().get(field) == value:
            return
        self._record((self.current, field))
        self.slide()[field] = value
        self._changed()
        self._redraw_current()

    def _points_changed(self, buffer):
        self._typed("points", buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), False))

    def _layout_changed(self, combo):
        key = combo.get_active_id()
        if self._loading or not key or key == self.slide().get("layout"):
            return
        self._record()
        self.slide()["layout"] = key
        self._changed()
        self._show_current()
        self._redraw_current()

    def set_theme(self, key):
        if key == self.doc["theme"]:
            return
        self._record()
        self.doc["theme"] = key
        self._changed()
        self.rebuild()

    def add_slide(self, layout):
        self._record()
        slide = new_slide(layout)
        self.doc["slides"].insert(self.current + 1, slide)
        self.current += 1
        self._changed()
        self.rebuild()
        self.title_entry.grab_focus()

    def duplicate_slide(self):
        self._record()
        self.doc["slides"].insert(self.current + 1, copy.deepcopy(self.slide()))
        self.current += 1
        self._changed()
        self.rebuild()

    def delete_slide(self):
        self._record()
        del self.doc["slides"][self.current]
        if not self.doc["slides"]:
            self.doc["slides"].append(new_slide("title"))
        self.current = min(self.current, len(self.doc["slides"]) - 1)
        self._changed()
        self.rebuild()

    def move_slide(self, step):
        target = self.current + step
        if not 0 <= target < len(self.doc["slides"]):
            return
        self._record()
        slides = self.doc["slides"]
        slides[self.current], slides[target] = slides[target], slides[self.current]
        self.current = target
        self._changed()
        self.rebuild()

    def choose_picture(self):
        dialog = Gtk.FileChooserNative.new("Choose a Picture", self, Gtk.FileChooserAction.OPEN, "Choose", "Cancel")
        pictures = Gtk.FileFilter()
        pictures.set_name("Pictures")
        pictures.add_pixbuf_formats()
        dialog.add_filter(pictures)
        folder = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)
        if folder and os.path.isdir(folder):
            dialog.set_current_folder(folder)
        if dialog.run() != Gtk.ResponseType.ACCEPT:
            return
        path = dialog.get_filename()
        data = read_picture(path)
        if data is None:
            alert.tell(self, f"“{os.path.basename(path)}” couldn’t be used.",
                       "Lantern takes pictures such as PNG and JPEG files.")
            return
        self.set_picture(data)
        if self.slide().get("layout") in ("title", "points"):
            self._loading = True
            self.slide()["layout"] = "both" if self.slide().get("points") else "picture"
            self._loading = False
            self._show_current()

    def set_picture(self, data):
        self._record()
        self.slide()["picture"] = data
        self._changed()
        self._show_current()
        self._redraw_current()

    def undo(self):
        self._swap(self.undo_stack, self.redo_stack)

    def redo(self):
        self._swap(self.redo_stack, self.undo_stack)

    def _swap(self, source, target):
        if not source:
            return
        target.append(self._snapshot())
        self.doc, self.current = source.pop()
        self._typing = None
        self._changed()
        self.rebuild()

    # --- moving around -----------------------------------------------------------------------
    def _row_selected(self, _list, row):
        if row is None:
            return
        index = row.get_index()
        if index != self.current:
            self.current = index
            self._typing = None
            self._show_current()

    def _list_key(self, _widget, event):
        if event.keyval in (Gdk.KEY_Delete, Gdk.KEY_BackSpace):
            self.delete_slide()
            return True
        if event.keyval == Gdk.KEY_Return:
            self.add_slide("points")
            return True
        return False

    def _list_press(self, _widget, event):
        if event.button != 3:
            return False
        row = self.list.get_row_at_y(int(event.y))
        if row:
            self.list.select_row(row)
        menu = Gtk.Popover(relative_to=self.list)
        rect = Gdk.Rectangle()
        rect.x, rect.y, rect.width, rect.height = int(event.x), int(event.y), 1, 1
        menu.set_pointing_to(rect)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        for label, action in (("New Slide", "win.new-slide"), ("Duplicate Slide", "win.duplicate"),
                              ("Move Up", "win.move-up"), ("Move Down", "win.move-down"),
                              ("Delete Slide", "win.delete-slide"), ("Play from This Slide", "win.play")):
            item = Gtk.ModelButton(text=label)
            item.set_action_name(action)
            box.pack_start(item, False, False, 0)
        box.show_all()
        menu.add(box)
        menu.popup()
        return True

    def _window_key(self, _widget, event):
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        if not ctrl:
            return False
        typing = isinstance(self.get_focus(), (Gtk.Entry, Gtk.TextView))
        name = Gdk.keyval_name(Gdk.keyval_to_lower(event.keyval)) or ""
        if name in ("z", "y") and typing:
            # one undo history for the whole presentation, typing included
            self.activate_action("redo" if name == "y" or event.state & Gdk.ModifierType.SHIFT_MASK else "undo",
                                 None)
            return True
        return False

    def play(self, start=None):
        self._typing = None
        Show(copy.deepcopy(self.doc), self.current if start is None else start)

    # --- files -----------------------------------------------------------------------------------
    def _update_title(self):
        name = os.path.basename(self.path) if self.path else "Untitled"
        self.set_title(("• " if self.modified else "") + name)
        self.header.set_title(name)
        self.header.set_subtitle("Edited" if self.modified else None)

    def load(self, path):
        try:
            with open(path, "rb") as f:
                raw = f.read(200 * 1024 * 1024)
            doc = check_document(json.loads(raw.decode("utf-8")))
        except OSError as err:
            alert.tell(self, f"“{os.path.basename(path)}” couldn’t be opened.", str(err.strerror or err))
            return False
        except (ValueError, TypeError, AttributeError, KeyError):
            alert.tell(self, f"“{os.path.basename(path)}” isn’t a presentation Lantern can read.")
            return False
        self.doc = doc
        self.path = os.path.abspath(path)
        self.modified = False
        self.current = 0
        self.undo_stack.clear()
        self.redo_stack.clear()
        Gtk.RecentManager.get_default().add_item(Gio.File.new_for_path(self.path).get_uri())
        self._update_title()
        return True

    def write(self, path):
        tmp = path + ".lantern-tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(self.doc, f, ensure_ascii=False)
            os.replace(tmp, path)
        except OSError as err:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            alert.tell(self, f"“{os.path.basename(path)}” couldn’t be saved.", str(err.strerror or err))
            return False
        return True

    def save(self):
        if not self.path:
            return self.save_as()
        if self.write(self.path):
            self.modified = False
            self._typing = None
            self._update_title()
            return True
        return False

    def _stem(self):
        if self.path:
            return os.path.splitext(os.path.basename(self.path))[0]
        title = self.doc["slides"][0].get("title", "").strip()
        return "".join(c for c in title if c not in '/\\:*?"<>|')[:60] or "Untitled"

    def save_as(self):
        folder = os.path.dirname(self.path) if self.path else None
        path = savesheet.ask(self, self._stem() + ".lantern", folder)
        if not path:
            return False
        if not path.lower().endswith(".lantern"):
            path += ".lantern"
        if self.write(path):
            self.path = os.path.abspath(path)
            self.modified = False
            self._update_title()
            return True
        return False

    def export_pdf(self):
        path = savesheet.ask(self, self._stem() + ".pdf", os.path.dirname(self.path) if self.path else None)
        if not path:
            return
        if not path.lower().endswith(".pdf"):
            path += ".pdf"
        try:
            write_pdf(self.doc, path)
        except (OSError, Exception) as err:  # cairo raises its own errors
            alert.tell(self, f"“{os.path.basename(path)}” couldn’t be saved.", str(err))

    def open_dialog(self):
        dialog = Gtk.FileChooserNative.new("Open", self, Gtk.FileChooserAction.OPEN, "Open", "Cancel")
        decks = Gtk.FileFilter()
        decks.set_name("Presentations")
        decks.add_pattern("*.lantern")
        decks.add_pattern("*.LANTERN")
        dialog.add_filter(decks)
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            path = dialog.get_filename()
            if self.path is None and not self.modified:
                if self.load(path):
                    self.rebuild()
            else:
                Window(self.get_application(), path).show_all()

    def confirm_close(self):
        if not self.modified:
            return True
        name = os.path.basename(self.path) if self.path else "Untitled"
        answer = alert.ask(self, f"Do you want to keep the changes you made to “{name}”?",
                           "Your changes will be lost if you don’t save them.",
                           [("Save", Gtk.ResponseType.ACCEPT), ("Cancel", Gtk.ResponseType.CANCEL),
                            ("Don’t Save", Gtk.ResponseType.REJECT)],
                           default=Gtk.ResponseType.ACCEPT)
        if answer == Gtk.ResponseType.ACCEPT:
            return self.save()
        return answer == Gtk.ResponseType.REJECT


def read_picture(path):
    """A picture file as base64 text, made smaller first if it is big."""
    try:
        if os.path.getsize(path) <= MAX_PICTURE:
            with open(path, "rb") as f:
                data = f.read()
            if picture_pixbuf(base64.b64encode(data).decode("ascii")) is not None and \
                    max(picture_pixbuf(base64.b64encode(data).decode("ascii")).get_width(),
                        picture_pixbuf(base64.b64encode(data).decode("ascii")).get_height()) <= 2400:
                return base64.b64encode(data).decode("ascii")
        pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, 2400, 2400, True)
        pixbuf = pixbuf.apply_embedded_orientation() or pixbuf
        kind = "png" if pixbuf.get_has_alpha() else "jpeg"
        options = ([], []) if kind == "png" else (["quality"], ["88"])
        ok, data = pixbuf.save_to_bufferv(kind, *options)
        return base64.b64encode(data).decode("ascii") if ok else None
    except (OSError, GLib.Error):
        return None


def check_document(doc):
    """Keep only what Lantern knows from a file, so a damaged or odd file can't upset it."""
    slides = []
    for raw in doc["slides"][:500]:
        layout = raw.get("layout") if raw.get("layout") in dict(LAYOUTS) else "points"
        picture = raw.get("picture") if isinstance(raw.get("picture"), str) else None
        slides.append({"layout": layout, "title": str(raw.get("title", ""))[:500],
                       "points": str(raw.get("points", ""))[:5000], "picture": picture})
    if not slides:
        slides.append(new_slide("title"))
    theme = doc.get("theme") if doc.get("theme") in THEMES else "paper"
    return {"version": 1, "theme": theme, "slides": slides}


def write_pdf(doc, path):
    import cairo
    page_w, page_h = 960, 540
    surface = cairo.PDFSurface(path, page_w, page_h)
    cr = cairo.Context(surface)
    for slide in doc["slides"]:
        paint_scaled(cr, slide, doc["theme"], page_w, page_h)
        cr.show_page()
    surface.finish()


def menubar():
    return menus.menubar([
        ("_File", [
            [("New", "app.new", "<Ctrl>n"), ("Open…", "win.open", "<Ctrl>o")],
            [("Save", "win.save", "<Ctrl>s"), ("Save As…", "win.save-as", "<Ctrl><Shift>s"),
             ("Export as PDF…", "win.export-pdf", None)],
            [("Close", "win.close", "<Ctrl>w")],
        ]),
        ("_Edit", [
            [("Undo", "win.undo", "<Ctrl>z"), ("Redo", "win.redo", "<Ctrl><Shift>z")],
        ]),
        ("_Slide", [
            [("New Slide", "win.new-slide", "<Ctrl><Shift>n"), ("Duplicate Slide", "win.duplicate", "<Ctrl><Shift>d"),
             ("Delete Slide", "win.delete-slide", None)],
            [("Move Slide Up", "win.move-up", "<Ctrl><Alt>Up"), ("Move Slide Down", "win.move-down", "<Ctrl><Alt>Down")],
            [("Choose Picture…", "win.picture", None)],
        ]),
        ("_Play", [
            [("Play Slideshow", "win.play", "<Ctrl><Alt>p"), ("Play from Start", "win.play-start", None)],
        ]),
    ])


class Lantern(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"new": lambda: Window(self).show_all(), "quit": self._quit})
        self.set_menubar(menubar())

    def _quit(self):
        for window in list(self.get_windows()):
            if isinstance(window, Window):
                window.present()
                if not window.confirm_close():
                    return
                window.destroy()
        self.quit()

    def do_activate(self):
        Window(self).show_all()

    def do_open(self, files, _n, _hint):
        for f in files:
            path = f.get_path()
            if path:
                Window(self, path).show_all()


def main():
    GLib.set_prgname("freemac-lantern")
    Lantern().run(sys.argv)


if __name__ == "__main__":
    main()
