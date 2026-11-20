# SPDX-License-Identifier: GPL-3.0-or-later
"""Frame: freemac's image and PDF viewer.

Opens a picture and lets you step through the others in the same folder, or
a PDF and lets you step through its pages (pdf.py draws them).
Keys: Left/Right previous/next, + / - zoom, 0 or F fit, 1 actual size,
R rotate right, Shift+R rotate left, Delete move to Trash, F11 full screen.

Markup (Shift+Command+A, or the pen button) shows a row of tools: choose and
move marks, draw, draw a box, add text, and sign with a signature drawn once
on a pad. Save a Copy (Command+S) writes the picture or PDF with the marks
on it next to the original, which is left as it was (markup.py).
"""
import copy
import os
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

from . import alert, markup, menus, pdf, style  # noqa: E402

TOOLS = (("select", "edit-select-symbolic", "Choose and move marks"),
         ("ink", "document-edit-symbolic", "Draw"),
         ("box", "checkbox-symbolic", "Box"),
         ("text", "insert-text-symbolic", "Text"),
         ("sign", "signature-symbolic", "Sign"))

APP_ID = "org.freemac.Frame"


def readable_types():
    exts = set()
    for fmt in GdkPixbuf.Pixbuf.get_formats():
        exts.update(e.lower() for e in fmt.get_extensions())
    return exts


def siblings(path, exts=None):
    """Pictures in the same folder as path, in name order."""
    exts = exts or readable_types()
    folder = os.path.dirname(path) or "."
    try:
        names = sorted(os.listdir(folder), key=str.lower)
    except OSError:
        return [path]
    found = [os.path.join(folder, n) for n in names
             if not n.startswith(".") and os.path.splitext(n)[1][1:].lower() in exts]
    return found or [path]


class Viewer(Gtk.ApplicationWindow):
    def __init__(self, app, path=None):
        super().__init__(application=app, title="Frame")
        self.set_default_size(960, 680)
        self.files, self.index = [], 0
        self.original = None   # the picture as loaded (after rotation)
        self.animation = None
        self.zoom = None        # None means "fit to window"
        self.fullscreen_on = False
        self.document, self.page = None, 0   # the PDF open, and its page shown
        self.marks_by_page = {}   # (path, page) -> marks on it, in its own pixels
        self.undo_marks = []      # (key, marks before a change)
        self.tool, self.color = "ink", markup.COLORS[0][1]
        self.chosen = None        # the mark chosen with the arrow
        self.drawing = None       # the mark being drawn
        self.drag_from = None
        self.unsaved = False
        self.last_copy = None     # (file, the copy last saved from it)
        self.scale = 1.0

        header = Gtk.HeaderBar(show_close_button=True)
        self.set_titlebar(header)
        self.header = header
        nav = Gtk.Box()
        nav.get_style_context().add_class("linked")
        for icon, tip, step in (("go-previous-symbolic", "Previous", -1), ("go-next-symbolic", "Next", 1)):
            button = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
            button.set_tooltip_text(tip)
            button.connect("clicked", lambda _b, s=step: self.step(s))
            nav.pack_start(button, False, False, 0)
        header.pack_start(nav)
        for icon, tip, callback in (("object-rotate-right-symbolic", "Rotate", lambda: self.rotate(-90)),
                                    ("zoom-fit-best-symbolic", "Fit to Window", lambda: self.set_zoom(None)),
                                    ("zoom-in-symbolic", "Zoom In", lambda: self.zoom_by(1.25)),
                                    ("zoom-out-symbolic", "Zoom Out", lambda: self.zoom_by(0.8))):
            button = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
            button.set_tooltip_text(tip)
            button.connect("clicked", lambda _b, c=callback: c())
            header.pack_end(button)
        opener = Gtk.Button(label="Open")
        opener.connect("clicked", lambda *_: self.open_dialog())
        header.pack_start(opener)
        self.markup_button = Gtk.ToggleButton()
        self.markup_button.add(Gtk.Image.new_from_icon_name("document-edit-symbolic", Gtk.IconSize.BUTTON))
        self.markup_button.set_tooltip_text("Markup (⇧⌘A)")
        self.markup_button.connect("toggled", lambda b: self.show_markup(b.get_active()))
        header.pack_end(self.markup_button)

        self.scroller = Gtk.ScrolledWindow()
        self.scroller.connect("size-allocate", lambda *_: self._refit())
        self.image = Gtk.Image()   # animated pictures
        self.canvas = Gtk.DrawingArea()   # still pictures and PDF pages, with marks
        self.canvas.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_MOTION_MASK
                               | Gdk.EventMask.BUTTON_RELEASE_MASK)
        self.canvas.connect("draw", self._draw_canvas)
        self.canvas.connect("button-press-event", self._press)
        self.canvas.connect("motion-notify-event", self._motion)
        self.canvas.connect("button-release-event", self._release)
        self.scaled = None
        self.view = Gtk.Stack()
        self.view.add_named(self.canvas, "canvas")
        self.view.add_named(self.image, "image")
        self.scroller.add(self.view)
        self.empty = Gtk.Label(label="Open a picture or a PDF, or drop one here.")
        self.empty.get_style_context().add_class("dim-label")
        self.stack = Gtk.Stack()
        self.stack.add_named(self.empty, "empty")
        self.stack.add_named(self.scroller, "image")
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.toolbar = Gtk.Revealer()
        self.toolbar.add(self._build_toolbar())
        outer.pack_start(self.toolbar, False, False, 0)
        outer.pack_start(self.stack, True, True, 0)
        self.add(outer)
        # A stack only switches to children that are already shown.
        self.stack.show_all()
        self.connect("delete-event", self._closing)
        self._last_size = None

        self.drag_dest_set(Gtk.DestDefaults.ALL, [], Gdk.DragAction.COPY)
        self.drag_dest_add_uri_targets()
        self.connect("drag-data-received", self._dropped)
        self.connect("key-press-event", self._on_key)
        self.connect("scroll-event", self._on_scroll)
        self.add_events(Gdk.EventMask.SCROLL_MASK)
        self._add_actions()
        if path:
            self.open_path(path)

    def _add_actions(self):
        menus.add_actions(self, {
            "open": self.open_dialog,
            "close": self.close,
            "trash": self.trash,
            "next": lambda: self.step(1),
            "previous": lambda: self.step(-1),
            "zoom-in": lambda: self.zoom_by(1.25),
            "zoom-out": lambda: self.zoom_by(0.8),
            "fit": lambda: self.set_zoom(None),
            "actual-size": lambda: self.set_zoom(1.0),
            "rotate-right": lambda: self.rotate(-90),
            "rotate-left": lambda: self.rotate(90),
            "full-screen": self.toggle_fullscreen,
            "markup": lambda: self.markup_button.set_active(not self.markup_button.get_active()),
            "save-copy": self.save_copy,
            "undo": self.undo,
        })

    def toggle_fullscreen(self):
        self.fullscreen_on = not self.fullscreen_on
        (self.fullscreen if self.fullscreen_on else self.unfullscreen)()

    # --- files -----------------------------------------------------------
    def open_path(self, path):
        if not self._may_leave():
            return
        self.marks_by_page, self.undo_marks, self.unsaved = {}, [], False
        path = os.path.abspath(path)
        self.document, self.page = None, 0
        if pdf.is_pdf(path):
            # A PDF steps through its own pages, not the folder.
            self.files, self.index = [path], 0
            self.document = pdf.open_document(path)
            self.show_current()
            return
        self.files = siblings(path)
        self.index = self.files.index(path) if path in self.files else 0
        if path not in self.files:
            self.files.insert(0, path)
        self.show_current()

    def show_current(self):
        if not self.files:
            self.stack.set_visible_child_name("empty")
            self.header.set_title("Frame")
            self.header.set_subtitle(None)
            return
        path = self.files[self.index]
        self.animation = None
        if pdf.is_pdf(path):
            self._show_page(path)
            return
        try:
            if path.lower().endswith(".gif"):
                anim = GdkPixbuf.PixbufAnimation.new_from_file(path)
                if not anim.is_static_image():
                    self.animation = anim
                pixbuf = anim.get_static_image()
            else:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file(path)
                pixbuf = pixbuf.apply_embedded_orientation() or pixbuf
        except GLib.Error:
            self.original = None
            self.image.clear()
            self.empty.set_text(f"“{os.path.basename(path)}” can’t be shown.")
            self.stack.set_visible_child_name("empty")
            self.header.set_title(os.path.basename(path))
            return
        self.original = pixbuf
        self.zoom = None
        self.stack.set_visible_child_name("image")
        self.header.set_title(os.path.basename(path))
        self.header.set_subtitle(f"{pixbuf.get_width()} × {pixbuf.get_height()}   "
                                 f"{self.index + 1} of {len(self.files)}")
        self._last_size = None
        self._render()

    def _show_page(self, path):
        pixbuf = pdf.page_pixbuf(self.document, self.page, 2000)
        self.header.set_title(os.path.basename(path))
        if pixbuf is None:
            self.original = None
            self.image.clear()
            self.empty.set_text(f"“{os.path.basename(path)}” can’t be shown.")
            self.stack.set_visible_child_name("empty")
            self.header.set_subtitle(None)
            return
        self.original = pixbuf
        self.zoom = None
        self.stack.set_visible_child_name("image")
        self.header.set_subtitle(f"Page {self.page + 1} of {self.document.get_n_pages()}")
        self._last_size = None
        self._render()

    def step(self, delta):
        if self.document is not None:
            page = max(0, min(self.document.get_n_pages() - 1, self.page + delta))
            if page != self.page:
                self.page = page
                self.show_current()
            return
        if len(self.files) > 1:
            self.index = (self.index + delta) % len(self.files)
            self.show_current()

    def open_dialog(self):
        dialog = Gtk.FileChooserNative.new("Open", self, Gtk.FileChooserAction.OPEN, "Open", "Cancel")
        pictures = Gtk.FileFilter()
        pictures.set_name("Pictures and PDFs")
        pictures.add_pixbuf_formats()
        pictures.add_mime_type("application/pdf")
        dialog.add_filter(pictures)
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            self.open_path(dialog.get_filename())

    def trash(self):
        if not self.files:
            return
        path = self.files[self.index]
        try:
            Gio.File.new_for_path(path).trash(None)
        except GLib.Error:
            return
        del self.files[self.index]
        self.document, self.page = None, 0
        self.index = min(self.index, len(self.files) - 1)
        self.show_current()

    def _dropped(self, _widget, _context, _x, _y, data, _info, _time):
        uris = data.get_uris()
        if uris:
            path = Gio.File.new_for_uri(uris[0]).get_path()
            if path:
                self.open_path(path)

    # --- zoom and rotate ---------------------------------------------------
    def fit_scale(self):
        alloc = self.scroller.get_allocation()
        if not self.original or alloc.width < 2:
            return 1.0
        return min(1.0, alloc.width / self.original.get_width(), alloc.height / self.original.get_height())

    def set_zoom(self, value):
        self.zoom = value
        self._render()

    def zoom_by(self, factor):
        current = self.zoom or self.fit_scale()
        self.set_zoom(max(0.05, min(16.0, current * factor)))

    def rotate(self, degrees):
        if not self.original or self.marks():
            return   # marks are kept in the picture's pixels as it is turned now
        angle = GdkPixbuf.PixbufRotation.CLOCKWISE if degrees < 0 else GdkPixbuf.PixbufRotation.COUNTERCLOCKWISE
        self.original = self.original.rotate_simple(angle)
        self.animation = None
        self._render()

    def _refit(self):
        alloc = self.scroller.get_allocation()
        size = (alloc.width, alloc.height)
        if self.zoom is None and size != self._last_size:
            self._last_size = size
            GLib.idle_add(self._render)

    def _render(self):
        if not self.original:
            return False
        if self.animation and self.zoom is None and self.fit_scale() >= 1.0 and not self.toolbar.get_reveal_child():
            self.image.set_from_animation(self.animation)
            self.view.set_visible_child_name("image")
            return False
        scale = self.zoom or self.fit_scale()
        w = max(1, round(self.original.get_width() * scale))
        h = max(1, round(self.original.get_height() * scale))
        interp = GdkPixbuf.InterpType.BILINEAR if scale < 1 else GdkPixbuf.InterpType.NEAREST \
            if scale >= 3 else GdkPixbuf.InterpType.BILINEAR
        self.scale = w / self.original.get_width()
        self.scaled = self.original.scale_simple(w, h, interp)
        # Fitted, the canvas just fills the view, so its size never feeds
        # back into the window's; zoomed in, it asks for room to scroll.
        if self.zoom is None:
            self.canvas.set_size_request(-1, -1)
        else:
            self.canvas.set_size_request(w, h)
        self.view.set_visible_child_name("canvas")
        self.canvas.queue_draw()
        return False

    # --- markup ------------------------------------------------------------
    def _build_toolbar(self):
        bar = Gtk.Box(spacing=6)
        bar.get_style_context().add_class("frame-markup")
        bar.set_border_width(6)
        tools = Gtk.Box()
        tools.get_style_context().add_class("linked")
        self.tool_buttons = {}
        group = None
        for name, icon, tip in TOOLS:
            button = Gtk.RadioButton.new_from_widget(group)
            group = group or button
            button.set_mode(False)
            if name == "sign":
                button.set_label("Sign")
            elif name == "select":
                button.add(self._arrow_icon())
            elif name == "text":
                letter = Gtk.Label()
                letter.set_markup("<span size='large' weight='bold' font_family='Serif'>A</span>")
                button.add(letter)
            else:
                button.set_image(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON))
            button.set_tooltip_text(tip)
            button.connect("toggled", lambda b, n=name: b.get_active() and self.choose_tool(n))
            tools.pack_start(button, False, False, 0)
            self.tool_buttons[name] = button
        bar.pack_start(tools, False, False, 0)
        colors = Gtk.Box(spacing=4)
        colors.set_margin_start(10)
        group = None
        for name, rgb in markup.COLORS:
            button = Gtk.RadioButton.new_from_widget(group)
            group = group or button
            button.set_mode(False)
            button.set_tooltip_text(name)
            swatch = Gtk.DrawingArea()
            swatch.set_size_request(16, 16)
            swatch.connect("draw", lambda _w, cr, c=rgb: (cr.arc(8, 8, 7, 0, 6.2832),
                                                          cr.set_source_rgb(*c), cr.fill()))
            button.add(swatch)
            button.connect("toggled", lambda b, c=rgb: b.get_active() and self.set_color(c))
            colors.pack_start(button, False, False, 0)
        bar.pack_start(colors, False, False, 0)
        undo = Gtk.Button.new_from_icon_name("edit-undo-symbolic", Gtk.IconSize.BUTTON)
        undo.set_tooltip_text("Undo (⌘Z)")
        undo.connect("clicked", lambda *_: self.undo())
        bar.pack_start(undo, False, False, 8)
        save = Gtk.Button(label="Save a Copy")
        save.set_tooltip_text("Save a copy with the marks (⌘S)")
        save.connect("clicked", lambda *_: self.save_copy())
        bar.pack_end(save, False, False, 0)
        self.tool_buttons["ink"].set_active(True)
        return bar

    @staticmethod
    def _arrow_icon():
        """A pointer arrow, drawn in the button's own colour."""
        area = Gtk.DrawingArea()
        area.set_size_request(16, 16)

        def draw(widget, cr):
            ink = widget.get_style_context().get_color(widget.get_state_flags())
            cr.set_source_rgba(ink.red, ink.green, ink.blue, ink.alpha)
            for x, y in ((4, 1), (4, 14), (7.2, 10.8), (9.6, 15.2), (11.4, 14.2), (9.1, 9.9), (13, 9.6)):
                cr.line_to(x, y)
            cr.close_path()
            cr.fill()
            return False
        area.connect("draw", draw)
        return area

    def show_markup(self, on):
        self.toolbar.set_reveal_child(on)
        if self.markup_button.get_active() != on:
            self.markup_button.set_active(on)
        self.chosen = None
        self._render()

    def choose_tool(self, name):
        self.tool = name
        if name != "select":
            self.chosen = None
        self.canvas.queue_draw()
        if name == "sign" and self.original is not None:
            GLib.idle_add(self._sign_here, None)

    def set_color(self, rgb):
        self.color = rgb
        if self.chosen is not None:
            self._remember()
            self.chosen["color"] = rgb
            self.canvas.queue_draw()

    def key(self):
        return (self.files[self.index] if self.files else None, self.page)

    def marks(self):
        return self.marks_by_page.setdefault(self.key(), [])

    def _remember(self):
        self.undo_marks.append((self.key(), copy.deepcopy(self.marks())))
        self.undo_marks = self.undo_marks[-100:]
        self.unsaved = True

    def undo(self):
        if not self.undo_marks:
            return
        key, marks = self.undo_marks.pop()
        self.marks_by_page[key] = marks
        self.chosen = None
        self.canvas.queue_draw()

    def _offset(self):
        if self.scaled is None:
            return 0, 0
        return (max(0, (self.canvas.get_allocated_width() - self.scaled.get_width()) // 2),
                max(0, (self.canvas.get_allocated_height() - self.scaled.get_height()) // 2))

    def _to_picture(self, event):
        ox, oy = self._offset()
        return (event.x - ox) / self.scale, (event.y - oy) / self.scale

    def _draw_canvas(self, area, cr):
        if self.scaled is None:
            return False
        ox, oy = self._offset()
        Gdk.cairo_set_source_pixbuf(cr, self.scaled, ox, oy)
        cr.paint()
        cr.translate(ox, oy)
        cr.scale(self.scale, self.scale)
        markup.draw_marks(cr, self.marks())
        if self.drawing is not None:
            markup.draw_mark(cr, self.drawing)
        if self.chosen is not None and self.toolbar.get_reveal_child():
            markup.outline(cr, self.chosen, self.scale)
        return False

    def _pen(self):
        return markup.line_width(self.original.get_width(), self.original.get_height())

    def _press(self, _w, event):
        if not self.toolbar.get_reveal_child() or self.original is None or event.button != 1:
            return False
        x, y = self._to_picture(event)
        if self.tool == "select" or event.type == Gdk.EventType._2BUTTON_PRESS:
            cr = self.canvas.get_window().cairo_create() if self.canvas.get_window() else None
            self.chosen = markup.hit(self.marks(), x, y, 6 / self.scale, cr)
            if self.chosen is not None:
                self._remember()
                self.drag_from = (x, y)
            self.canvas.queue_draw()
        elif self.tool == "ink":
            self.drawing = {"kind": "ink", "color": self.color, "width": self._pen(), "points": [(x, y)]}
        elif self.tool == "box":
            self.drawing = {"kind": "box", "color": self.color, "width": self._pen(), "rect": (x, y, 0, 0)}
            self.drag_from = (x, y)
        elif self.tool == "text":
            self._ask_text(event, x, y)
        elif self.tool == "sign":
            self._sign_here((x, y))
        return True

    def _motion(self, _w, event):
        if self.original is None:
            return False
        x, y = self._to_picture(event)
        if self.drawing is not None and self.drawing["kind"] == "ink":
            self.drawing["points"].append((x, y))
        elif self.drawing is not None and self.drawing["kind"] == "box":
            x0, y0 = self.drag_from
            self.drawing["rect"] = (min(x0, x), min(y0, y), abs(x - x0), abs(y - y0))
        elif self.chosen is not None and self.drag_from is not None:
            markup.move(self.chosen, x - self.drag_from[0], y - self.drag_from[1])
            self.drag_from = (x, y)
        else:
            return False
        self.canvas.queue_draw()
        return True

    def _release(self, _w, _event):
        mark, self.drawing, self.drag_from = self.drawing, None, None
        if mark is None:
            return False
        if mark["kind"] == "box" and min(mark["rect"][2:]) < 2 / self.scale:
            self.canvas.queue_draw()
            return True
        self._remember()
        self.marks().append(mark)
        self.canvas.queue_draw()
        return True

    def _ask_text(self, event, x, y):
        pop = Gtk.Popover(relative_to=self.canvas)
        rect = Gdk.Rectangle()
        rect.x, rect.y, rect.width, rect.height = int(event.x), int(event.y), 1, 1
        pop.set_pointing_to(rect)
        entry = Gtk.Entry(placeholder_text="Text", width_chars=24)
        entry.set_margin_top(6)
        entry.set_margin_bottom(6)
        entry.set_margin_start(6)
        entry.set_margin_end(6)
        pop.add(entry)

        def done(*_):
            words = entry.get_text().strip()
            if words:
                self._remember()
                size = self._pen() * 8
                self.marks().append({"kind": "text", "color": self.color, "size": size,
                                     "x": x, "y": y - size * 0.65, "text": words})
                self.canvas.queue_draw()
            pop.popdown()
        entry.connect("activate", done)
        pop.show_all()
        pop.popup()
        entry.grab_focus()

    def _sign_here(self, at):
        """Put the saved signature (drawing one first if there is none) at
        at, or in the lower middle of the page, then choose it to move."""
        signatures = markup.load_signatures()
        signature = signatures[0] if signatures else markup.ask_signature(self)
        if signature is None or self.original is None:
            self.tool_buttons["select"].set_active(True)
            return False
        width = self.original.get_width() * 0.28
        height = width * signature.get("aspect", 0.4)
        if at is None:
            at = (self.original.get_width() * 0.6, self.original.get_height() * 0.8)
        mark = {"kind": "sign", "color": markup.INK, "width": self._pen() * 0.9,
                "x": at[0] - width / 2, "y": at[1] - height / 2, "w": width,
                "aspect": signature.get("aspect", 0.4), "strokes": signature["strokes"]}
        self._remember()
        self.marks().append(mark)
        self.chosen = mark
        self.tool_buttons["select"].set_active(True)
        self.canvas.queue_draw()
        return False

    def delete_chosen(self):
        if self.chosen is None:
            return False
        self._remember()
        marks = self.marks()
        if self.chosen in marks:
            marks.remove(self.chosen)
        self.chosen = None
        self.canvas.queue_draw()
        return True

    # --- saving a copy with the marks ---------------------------------------
    def _copy_path(self, path):
        stem, ext = os.path.splitext(path)
        if ext.lower() not in (".png", ".jpg", ".jpeg", ".pdf"):
            ext = ".png"
        candidate = f"{stem} (marked up){ext}"
        n = 2
        while os.path.exists(candidate):
            candidate = f"{stem} (marked up {n}){ext}"
            n += 1
        return candidate

    def save_copy(self):
        if not self.files or self.original is None:
            return
        path = self.files[self.index]
        if not self.unsaved and self.last_copy and self.last_copy[0] == path and os.path.exists(self.last_copy[1]):
            return   # nothing new since the last copy (a held ⌘S repeats)
        target = self._copy_path(path)
        try:
            if self.document is not None:
                self._save_pdf(path, target)
            else:
                self._save_picture(target)
        except (OSError, GLib.Error) as error:
            alert.tell(self, "The copy couldn’t be saved.", str(error))
            return
        self.unsaved = False
        self.last_copy = (path, target)
        self.header.set_subtitle(f"Saved “{os.path.basename(target)}”")

    def _save_picture(self, target):
        import cairo
        w, h = self.original.get_width(), self.original.get_height()
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
        cr = cairo.Context(surface)
        Gdk.cairo_set_source_pixbuf(cr, self.original, 0, 0)
        cr.paint()
        markup.draw_marks(cr, self.marks())
        surface.flush()
        out = Gdk.pixbuf_get_from_surface(surface, 0, 0, w, h)
        if target.lower().endswith((".jpg", ".jpeg")):
            out.savev(target, "jpeg", ["quality"], ["92"])
        else:
            out.savev(target, "png", [], [])

    def _save_pdf(self, path, target):
        """Every page drawn as it is (sharp text and all), with the marks on
        top, scaled from the page pictures they were drawn on."""
        import cairo
        doc = self.document
        surface = None
        for index in range(doc.get_n_pages()):
            page = doc.get_page(index)
            w, h = page.get_size()
            if surface is None:
                surface = cairo.PDFSurface(target, w, h)
            else:
                surface.set_size(w, h)
            cr = cairo.Context(surface)
            page.render_for_printing(cr)
            marks = self.marks_by_page.get((path, index))
            if marks:
                # Marks are in the pixels of the page picture (pdf.page_pixbuf
                # at 2000 across its longer side).
                k = max(w, h) / min(2000, pdf.LARGEST)
                cr.scale(k, k)
                markup.draw_marks(cr, marks)
            cr.show_page()
        surface.finish()

    def _may_leave(self):
        """Ask about marks not yet saved; False to stay."""
        if not self.unsaved or not any(self.marks_by_page.values()):
            return True
        answer = alert.ask(self, "Save a copy with your markup?",
                           "Your marks will be lost if you don’t save them.",
                           [("Don’t Save", Gtk.ResponseType.NO), ("Cancel", Gtk.ResponseType.CANCEL),
                            ("Save a Copy", Gtk.ResponseType.OK)], default=Gtk.ResponseType.OK)
        if answer == Gtk.ResponseType.OK:
            self.save_copy()
            return not self.unsaved
        return answer == Gtk.ResponseType.NO

    def _closing(self, *_):
        return not self._may_leave()

    # --- input -----------------------------------------------------------
    def _on_key(self, _widget, event):
        key = event.keyval
        shift = event.state & Gdk.ModifierType.SHIFT_MASK
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        marking = self.toolbar.get_reveal_child()
        if ctrl and shift and key in (Gdk.KEY_a, Gdk.KEY_A):
            self.markup_button.set_active(not marking)
        elif ctrl and key in (Gdk.KEY_s, Gdk.KEY_S):
            self.save_copy()
        elif ctrl and key in (Gdk.KEY_z, Gdk.KEY_Z) and marking:
            self.undo()
        elif marking and key in (Gdk.KEY_Delete, Gdk.KEY_BackSpace) and self.chosen is not None:
            self.delete_chosen()
        elif marking and key == Gdk.KEY_Escape:
            if self.chosen is not None:
                self.chosen = None
                self.canvas.queue_draw()
            else:
                self.markup_button.set_active(False)
        elif ctrl and key in (Gdk.KEY_o, Gdk.KEY_O):
            self.open_dialog()
        elif ctrl and key in (Gdk.KEY_w, Gdk.KEY_W):
            self.close()
        elif marking and isinstance(self.get_focus(), Gtk.Entry):
            return False
        elif key in (Gdk.KEY_Right, Gdk.KEY_Page_Down, Gdk.KEY_space):
            self.step(1)
        elif key in (Gdk.KEY_Left, Gdk.KEY_Page_Up, Gdk.KEY_BackSpace):
            self.step(-1)
        elif key in (Gdk.KEY_plus, Gdk.KEY_equal, Gdk.KEY_KP_Add):
            self.zoom_by(1.25)
        elif key in (Gdk.KEY_minus, Gdk.KEY_KP_Subtract):
            self.zoom_by(0.8)
        elif key in (Gdk.KEY_0, Gdk.KEY_f, Gdk.KEY_F):
            self.set_zoom(None)
        elif key == Gdk.KEY_1:
            self.set_zoom(1.0)
        elif key in (Gdk.KEY_r, Gdk.KEY_R):
            self.rotate(90 if shift else -90)
        elif key == Gdk.KEY_Delete:
            self.trash()
        elif key == Gdk.KEY_F11 or (key == Gdk.KEY_Escape and self.fullscreen_on):
            self.toggle_fullscreen()
        else:
            return False
        return True

    def _on_scroll(self, _widget, event):
        if event.state & Gdk.ModifierType.CONTROL_MASK:
            ok, _dx, dy = event.get_scroll_deltas()
            up = event.direction == Gdk.ScrollDirection.UP or (ok and dy < 0)
            self.zoom_by(1.1 if up else 1 / 1.1)
            return True
        return False


def menubar():
    return menus.menubar([
        ("_File", [
            [("New Window", "app.new-window", None), ("Open…", "win.open", "<Ctrl>o")],
            [("Save a Copy", "win.save-copy", "<Ctrl>s")],
            [("Move to Trash", "win.trash", "Delete")],
            [("Close Window", "win.close", "<Ctrl>w")],
        ]),
        ("_Edit", [
            [("Undo", "win.undo", "<Ctrl>z")],
        ]),
        ("_Tools", [
            [("Show Markup", "win.markup", "<Shift><Ctrl>a")],
        ]),
        ("_View", [
            [("Zoom In", "win.zoom-in", "plus"), ("Zoom Out", "win.zoom-out", "minus"),
             ("Fit to Window", "win.fit", "0"), ("Actual Size", "win.actual-size", "1")],
            [("Rotate Right", "win.rotate-right", "r"), ("Rotate Left", "win.rotate-left", "<Shift>r")],
            [("Full Screen", "win.full-screen", "F11")],
        ]),
        ("_Go", [
            [("Previous", "win.previous", "Left"), ("Next", "win.next", "Right")],
        ]),
    ])


class Frame(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"new-window": lambda: Viewer(self).show_all()})
        self.set_menubar(menubar())

    def do_activate(self):
        Viewer(self).show_all()

    def do_open(self, files, _n, _hint):
        for f in files:
            if f.get_path():
                Viewer(self, f.get_path()).show_all()


def main():
    Frame().run(sys.argv)


if __name__ == "__main__":
    main()
