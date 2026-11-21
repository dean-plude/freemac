# SPDX-License-Identifier: GPL-3.0-or-later
"""Glance: a quick look at the selected files, opened and closed with Space,
in Drawer and on the desktop.

Pictures are scaled to fit the window, PDFs show every page to scroll
through, movies and music play straight away with a play button and a time
bar, text files show their first lines, folders say how much is in them, and
anything else shows its icon and details. With several files selected, the
arrows at the top (or Left and Right) step through them. The full-screen
button (or Control+Command+F) fills the screen; Esc leaves it. The button at
the bottom opens the file in its usual app.
"""
import os
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk  # noqa: E402

Gst = None   # GStreamer loads the first time a movie or song is shown


def load_gst():
    global Gst
    if Gst is None:
        try:
            gi.require_version("Gst", "1.0")
            from gi.repository import Gst as gst
            gst.init(None)
            Gst = gst
        except (ImportError, ValueError):
            return False
    return True

TEXT_BYTES = 64 * 1024
WIDTH, HEIGHT = 640, 480
PICTURE_MOST = 2400      # longest side a picture is loaded at
PDF_PAGES = 60           # pages drawn at most
PDF_WIDTH = 900          # pages are drawn this wide and scaled to the window


def human_size(size):
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if size < 1000 or unit == "TB":
            return f"{size} {unit}" if unit == "bytes" else f"{size:.1f} {unit}"
        size /= 1000
    return ""


def clock(seconds):
    seconds = max(0, int(seconds))
    hours, rest = divmod(seconds, 3600)
    return f"{hours}:{rest // 60:02d}:{rest % 60:02d}" if hours else f"{rest // 60}:{rest % 60:02d}"


def content_type(path):
    try:
        info = Gio.File.new_for_path(path).query_info("standard::content-type", Gio.FileQueryInfoFlags.NONE, None)
        return info.get_content_type() or ""
    except GLib.Error:
        return Gio.content_type_guess(path, None)[0] or ""


def is_text(kind, path):
    if Gio.content_type_is_a(kind, "text/plain"):
        return True
    try:
        with open(path, "rb") as f:
            head = f.read(4096)
    except OSError:
        return False
    return bool(head) and b"\0" not in head and kind in ("application/octet-stream", "application/x-zerosize", "")


class Picture(Gtk.DrawingArea):
    """A picture scaled to fit whatever room it has, never past twice its
    own size, so it fills the screen in full screen."""

    def __init__(self, pixbuf):
        super().__init__(hexpand=True, vexpand=True)
        self.pixbuf = pixbuf
        self.cache = None
        self.connect("draw", self._draw)

    def _draw(self, widget, cr):
        room_w, room_h = widget.get_allocated_width(), widget.get_allocated_height()
        pw, ph = self.pixbuf.get_width(), self.pixbuf.get_height()
        scale = min(room_w / pw, room_h / ph, 2.0)
        w, h = max(1, round(pw * scale)), max(1, round(ph * scale))
        if self.cache is None or (self.cache.get_width(), self.cache.get_height()) != (w, h):
            self.cache = self.pixbuf.scale_simple(w, h, GdkPixbuf.InterpType.BILINEAR)
        Gdk.cairo_set_source_pixbuf(cr, self.cache, (room_w - w) / 2, (room_h - h) / 2)
        cr.paint()
        return False


class Pages(Gtk.ScrolledWindow):
    """Every page of a PDF, one under another, each as wide as the room."""

    def __init__(self, document):
        super().__init__(hexpand=True, vexpand=True)
        self.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.document = document
        self.column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=6)
        self.add(self.column)
        self.pictures = []
        self.next_page = 0
        self.count = min(document.get_n_pages(), PDF_PAGES)
        GLib.idle_add(self._draw_next)

    def _draw_next(self):
        from . import pdf
        if self.next_page >= self.count or self.get_parent() is None and self.next_page:
            return False
        pixbuf = pdf.page_pixbuf(self.document, self.next_page, PDF_WIDTH)
        self.next_page += 1
        if pixbuf is not None:
            picture = Picture(pixbuf)
            picture.set_vexpand(False)
            ratio = pixbuf.get_height() / pixbuf.get_width()
            picture.connect("size-allocate", lambda w, a, r=ratio: self._fit(w, a, r))
            picture.set_size_request(-1, round((WIDTH - 60) * ratio))
            self.column.pack_start(picture, False, False, 0)
            picture.show()
        return self.next_page < self.count

    @staticmethod
    def _fit(widget, allocation, ratio):
        want = round(allocation.width * ratio)
        if abs(want - allocation.height) > 2:
            GLib.idle_add(lambda: widget.set_size_request(-1, want) and False)


class Glance(Gtk.Window):
    def __init__(self, parent, on_open, on_arrow=None):
        super().__init__(title="Glance")
        if parent is not None:
            self.set_transient_for(parent)
            self.set_destroy_with_parent(True)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.set_default_size(WIDTH, HEIGHT)
        self.on_open = on_open
        self.on_arrow = on_arrow   # arrows with one file move the owner's selection
        self.paths = []
        self.index = 0
        self.path = None
        self.full = False
        self.playbin = None
        self.video_widget = None
        self.length = 0
        self.ticking = False
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=12)
        self.add(outer)

        top = Gtk.Box(spacing=6)
        self.back = self._button("go-previous-symbolic", "Previous file (Left)", lambda *_: self.step(-1))
        self.forward = self._button("go-next-symbolic", "Next file (Right)", lambda *_: self.step(1))
        self.counter = Gtk.Label()
        self.counter.get_style_context().add_class("dim-label")
        for widget in (self.back, self.forward, self.counter):
            top.pack_start(widget, False, False, 0)
        self.full_button = self._button("view-fullscreen-symbolic", "Full screen (Control+Command+F)",
                                        lambda *_: self.toggle_full())
        top.pack_end(self.full_button, False, False, 0)
        outer.pack_start(top, False, False, 0)

        self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        outer.pack_start(self.body, True, True, 0)

        self.player = Gtk.Box(spacing=8)
        self.play_button = self._button("media-playback-pause-symbolic", "Play or pause (K)",
                                        lambda *_: self.play_pause())
        self.player.pack_start(self.play_button, False, False, 0)
        self.at_label = Gtk.Label(label="0:00", width_chars=5)
        self.player.pack_start(self.at_label, False, False, 0)
        self.bar = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 1, 1)
        self.bar.set_draw_value(False)
        self.bar.set_hexpand(True)
        self.bar.set_can_focus(False)
        self.bar_moving = False
        self.bar.connect("change-value", self._seek_to)
        self.player.pack_start(self.bar, True, True, 0)
        self.length_label = Gtk.Label(label="0:00", width_chars=5)
        self.player.pack_start(self.length_label, False, False, 0)
        outer.pack_start(self.player, False, False, 0)

        footer = Gtk.Box(spacing=8)
        self.details = Gtk.Label(xalign=0, wrap=True, max_width_chars=56)
        self.details.get_style_context().add_class("dim-label")
        footer.pack_start(self.details, True, True, 0)
        self.open_button = Gtk.Button(label="Open", can_focus=False)
        self.open_button.connect("clicked", lambda *_: self.on_open(self.path))
        footer.pack_end(self.open_button, False, False, 0)
        outer.pack_start(footer, False, False, 0)

        self.connect("key-press-event", self._key)
        self.connect("delete-event", lambda *_: self.hide() or True)
        self.connect("hide", lambda *_: self._stop())
        self.connect("window-state-event", self._state)

    @staticmethod
    def _button(icon, tip, action):
        button = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
        button.set_relief(Gtk.ReliefStyle.NONE)
        button.set_can_focus(False)   # the Space that opened Glance mustn't press it
        button.set_tooltip_text(tip)
        button.connect("clicked", action)
        return button

    # ---- keys and full screen ------------------------------------------------
    def _key(self, _w, event):
        key = event.keyval
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        if key == Gdk.KEY_Escape and self.full:
            self.unfullscreen()
        elif key in (Gdk.KEY_space, Gdk.KEY_Escape):
            if key == Gdk.KEY_space and event.state & Gdk.ModifierType.MOD1_MASK:
                self.toggle_full()
            else:
                self.hide()
        elif key in (Gdk.KEY_f, Gdk.KEY_F) and ctrl:
            self.toggle_full()
        elif key == Gdk.KEY_Left and len(self.paths) > 1:
            self.step(-1)
        elif key == Gdk.KEY_Right and len(self.paths) > 1:
            self.step(1)
        elif key in (Gdk.KEY_Left, Gdk.KEY_Right, Gdk.KEY_Up, Gdk.KEY_Down) and self.on_arrow \
                and len(self.paths) <= 1 and not (key in (Gdk.KEY_Up, Gdk.KEY_Down) and self._scrolls()):
            self.on_arrow(key)
        elif key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) or (key == Gdk.KEY_o and ctrl):
            self.on_open(self.path)
        elif key in (Gdk.KEY_k, Gdk.KEY_K) and self.player.get_visible():
            self.play_pause()
        else:
            return False
        return True

    def _scrolls(self):
        """Whether what's shown scrolls (text, PDFs), so Up and Down are its."""
        return any(isinstance(child, Gtk.ScrolledWindow) for child in self.body.get_children())

    def toggle_full(self):
        if self.full:
            self.unfullscreen()
        else:
            self.fullscreen()

    def _state(self, _w, event):
        self.full = bool(event.new_window_state & Gdk.WindowState.FULLSCREEN)
        self.full_button.set_image(Gtk.Image.new_from_icon_name(
            "view-restore-symbolic" if self.full else "view-fullscreen-symbolic", Gtk.IconSize.BUTTON))
        return False

    # ---- which file ------------------------------------------------------------
    def show_path(self, path):
        self.show_paths([path])

    def show_paths(self, paths, index=0):
        self.paths = list(paths)
        self.index = max(0, min(index, len(self.paths) - 1))
        self._show()

    def step(self, by):
        if len(self.paths) > 1:
            self.index = (self.index + by) % len(self.paths)
            self._show()

    def _show(self):
        several = len(self.paths) > 1
        for widget in (self.back, self.forward, self.counter):
            widget.set_visible(several)
        self.counter.set_text(f"{self.index + 1} of {len(self.paths)}")
        self._show_one(self.paths[self.index])

    # ---- one file ----------------------------------------------------------------
    def _show_one(self, path):
        self._stop()
        self.path = path
        for child in self.body.get_children():
            self.body.remove(child)
        name = os.path.basename(path) or path
        self.set_title(name)
        playing = False
        try:
            st = os.stat(path)
        except OSError:
            st = None
        stamp = time.strftime("%b %-d, %Y %-I:%M %p", time.localtime(st.st_mtime)) if st else ""
        if os.path.isdir(path):
            try:
                count = len([n for n in os.listdir(path) if not n.startswith(".")])
            except OSError:
                count = 0
            self._icon_and_text("folder", name, f"{count} item{'s' if count != 1 else ''}")
            self.details.set_text(f"Folder · Modified {stamp}")
            self.open_button.set_label("Open Folder")
        else:
            kind = content_type(path)
            description = Gio.content_type_get_description(kind) if kind else "File"
            size = human_size(st.st_size) if st else ""
            shown = False
            if kind.startswith("image/"):
                try:
                    pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, PICTURE_MOST, PICTURE_MOST, True)
                    pixbuf = pixbuf.apply_embedded_orientation() or pixbuf
                    self.body.pack_start(Picture(pixbuf), True, True, 0)
                    shown = True
                    _format, width, height = GdkPixbuf.Pixbuf.get_file_info(path)
                    if width:
                        description += f", {width}×{height}"
                except GLib.Error:
                    shown = False
            elif Gio.content_type_is_a(kind or "", "application/pdf"):
                from . import pdf   # Poppler loads only when a PDF is shown
                document = pdf.open_document(path)
                if document is not None and document.get_n_pages() > 0:
                    self.body.pack_start(Pages(document), True, True, 0)
                    shown = True
                    pages = document.get_n_pages()
                    description += f", {pages} page{'s' if pages != 1 else ''}"
            elif kind.startswith(("video/", "audio/")) and self._make_bin():
                video = kind.startswith("video/")
                if video:
                    self.body.pack_start(self.video_widget, True, True, 0)
                else:
                    icon = Gio.content_type_get_icon(kind)
                    self._icon_and_text(icon, name, description)
                self.video_widget.set_visible(video)
                self.playbin.set_property("uri", Gio.File.new_for_path(path).get_uri())
                self.playbin.set_state(Gst.State.PLAYING)
                self.length = 0
                self.bar.set_range(0, 1)
                self.bar.set_value(0)
                self.at_label.set_text("0:00")
                self.length_label.set_text("0:00")
                self._show_playing(True)
                if not self.ticking:
                    self.ticking = True
                    GLib.timeout_add(250, self._tick)
                shown = playing = True
            elif is_text(kind, path):
                try:
                    with open(path, "rb") as f:
                        text = f.read(TEXT_BYTES).decode("utf-8", "replace")
                    view = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                                        wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=8, top_margin=8)
                    view.get_buffer().set_text(text)
                    scroll = Gtk.ScrolledWindow()
                    scroll.add(view)
                    self.body.pack_start(scroll, True, True, 0)
                    shown = True
                except OSError:
                    shown = False
            if not shown:
                icon = Gio.content_type_get_icon(kind) if kind else Gio.ThemedIcon.new("text-x-generic")
                self._icon_and_text(icon, name, description)
            self.details.set_text(" · ".join(p for p in (description if shown else "", size,
                                                         f"Modified {stamp}" if stamp else "") if p))
            app = Gio.AppInfo.get_default_for_type(kind, False) if kind else None
            self.open_button.set_label(f"Open with {app.get_name()}" if app else "Open")
        self.get_child().show_all()
        self.player.set_visible(playing)
        if self.video_widget is not None and not playing:
            self.video_widget.hide()
        for widget in (self.back, self.forward, self.counter):
            widget.set_visible(len(self.paths) > 1)
        self.present()

    def _icon_and_text(self, icon, title, subtitle):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, valign=Gtk.Align.CENTER)
        gicon = Gio.ThemedIcon.new(icon) if isinstance(icon, str) else icon
        image = Gtk.Image.new_from_gicon(gicon, Gtk.IconSize.DIALOG)
        image.set_pixel_size(128)
        box.pack_start(image, False, False, 0)
        heading = Gtk.Label(label=title, wrap=True, max_width_chars=40)
        heading.get_style_context().add_class("drawer-preview-name")
        box.pack_start(heading, False, False, 0)
        line = Gtk.Label(label=subtitle)
        line.get_style_context().add_class("dim-label")
        box.pack_start(line, False, False, 0)
        self.body.pack_start(box, True, True, 0)

    # ---- movies and music ------------------------------------------------------
    def _make_bin(self):
        """A playbin drawing into a GTK widget, made once; False if
        GStreamer or its GTK output is missing."""
        if self.playbin is not None:
            return True
        if not load_gst():
            return False
        playbin = Gst.ElementFactory.make("playbin", None)
        sink = Gst.ElementFactory.make("gtksink", None)
        if playbin is None or sink is None:
            return False
        playbin.set_property("video-sink", sink)
        self.video_widget = sink.get_property("widget")
        self.video_widget.set_hexpand(True)
        self.video_widget.set_vexpand(True)
        bus = playbin.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self._message)
        self.playbin = playbin
        return True

    def _message(self, _bus, message):
        if message.type == Gst.MessageType.EOS:
            self.playbin.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH, 0)
            self.playbin.set_state(Gst.State.PAUSED)
            self._show_playing(False)
        elif message.type == Gst.MessageType.ERROR:
            self.playbin.set_state(Gst.State.NULL)
            self.player.hide()
            self.details.set_text("This can't be played here.")

    def _tick(self):
        if self.playbin is None or not self.player.get_visible() or not self.get_visible():
            self.ticking = False
            return False
        ok, length = self.playbin.query_duration(Gst.Format.TIME)
        if ok and length > 0 and abs(length / Gst.SECOND - self.length) > 0.5:
            self.length = length / Gst.SECOND
            self.bar.set_range(0, max(1, self.length))
            self.length_label.set_text(clock(self.length))
        ok, at = self.playbin.query_position(Gst.Format.TIME)
        if ok and not self.bar_moving:
            self.bar.set_value(at / Gst.SECOND)
            self.at_label.set_text(clock(at / Gst.SECOND))
        return True

    def _seek_to(self, _scale, _scroll, value):
        if self.playbin is not None and self.length:
            value = max(0, min(value, self.length))
            self.playbin.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT,
                                     int(value * Gst.SECOND))
            self.at_label.set_text(clock(value))
        return False

    def play_pause(self):
        if self.playbin is None:
            return
        _ok, state, _pending = self.playbin.get_state(0)
        playing = state != Gst.State.PLAYING
        self.playbin.set_state(Gst.State.PLAYING if playing else Gst.State.PAUSED)
        self._show_playing(playing)

    def _show_playing(self, playing):
        self.play_button.set_image(Gtk.Image.new_from_icon_name(
            "media-playback-pause-symbolic" if playing else "media-playback-start-symbolic", Gtk.IconSize.BUTTON))

    def _stop(self):
        if self.playbin is not None:
            self.playbin.set_state(Gst.State.NULL)
