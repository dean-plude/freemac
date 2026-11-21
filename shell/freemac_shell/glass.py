# SPDX-License-Identifier: GPL-3.0-or-later
"""Glass: scanning.

Glass finds scanners connected by USB or on the same network (most
all-in-one printers included) through SANE's scanimage. Click Preview for a
quick look at the whole glass, drag over the preview to scan only part of
it, pick colour or black and white and how sharp the scan should be, then
click Scan. Each scan becomes a page; save the pages as one PDF, or each as
a picture.

Original freemac code; scanning itself is done by scanimage (sane-utils)
with the sane-airscan driver.
"""
import datetime
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading

import cairo
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, Pango  # noqa: E402

from . import alert, menus, style  # noqa: E402

APP_ID = "org.freemac.Glass"
SCANIMAGE = os.environ.get("FREEMAC_SCANIMAGE") or "scanimage"
PREVIEW_DPI = 75
RESOLUTIONS = (150, 300, 600)
DEFAULT_RESOLUTION = 300
MODES = (("color", "Colour"), ("gray", "Grey"), ("lineart", "Black & White"))
DEFAULT_AREA = (215.9, 297.0)      # millimetres; letter width, A4 height
MM_PER_INCH = 25.4
LOOK_TIMEOUT = 40
SCAN_TIMEOUT = 600


# scanimage's output --------------------------------------------------------

DEVICE_LINE = re.compile(r"device `([^']+)' is an? (.+)")
RANGE_OPTION = re.compile(r"^\s*(-[lxyt]|--[a-z-]+)\s+(?:auto\|+)?(-?[\d.]+)\.\.(-?[\d.]+)\s*(mm|dpi)?", re.M)
LIST_OPTION = re.compile(r"^\s*(--mode|--resolution)\s+([^\s\[]+)", re.M)
PROGRESS = re.compile(rb"Progress:\s*([\d.]+)%")


def parse_devices(text):
    """[(device name, description)] from `scanimage -L`."""
    found = []
    for line in text.splitlines():
        match = DEVICE_LINE.search(line)
        if match:
            name, what = match.group(1), match.group(2).strip()
            what = re.sub(r"\s+(ip|uri)=\S+$", "", what)
            found.append((name, what))
    # One machine is often listed twice by sane-airscan (eSCL and WSD) and once
    # more by a vendor driver; keep the first of each description.
    seen, unique = set(), []
    for name, what in found:
        key = re.sub(r"^(eSCL|WSD)\s+", "", what)
        if key not in seen:
            seen.add(key)
            unique.append((name, what))
    return unique


def friendly_name(description):
    name = re.sub(r"^(eSCL|WSD)\s+", "", description)
    name = re.sub(r"\s+(flatbed scanner|scanner|multi-function peripheral)$", "", name, flags=re.I)
    return name.strip() or description


def parse_options(text):
    """What a device offers, from `scanimage -A`."""
    info = {"area": None, "modes": [], "resolutions": [], "range": None}
    width = height = None
    for match in RANGE_OPTION.finditer(text):
        flag, low, high, unit = match.group(1), float(match.group(2)), float(match.group(3)), match.group(4)
        if flag == "-x" and unit == "mm":
            width = high
        elif flag == "-y" and unit == "mm":
            height = high
        elif flag == "--resolution":
            info["range"] = (low, high)
    if width and height:
        info["area"] = (width, height)
    for match in LIST_OPTION.finditer(text):
        if ".." in match.group(2):
            continue
        values = [v for v in match.group(2).split("|") if v and v != "auto"]
        if match.group(1) == "--mode":
            info["modes"] = values
        else:
            info["resolutions"] = [int(re.sub(r"\D", "", v)) for v in values if re.sub(r"\D", "", v)]
    return info


def offered_resolutions(info):
    if info["resolutions"]:
        # The device's own steps nearest to 150, 300 and 600.
        steps = sorted(set(info["resolutions"]))
        offered = sorted({min(steps, key=lambda s, r=r: (abs(s - r), -s)) for r in RESOLUTIONS})
        return offered
    if info["range"]:
        low, high = info["range"]
        return [r for r in RESOLUTIONS if low <= r <= high] or list(RESOLUTIONS)
    return list(RESOLUTIONS)


def mode_value(info, mode):
    """The device's own word for a mode: Color, Colour, Gray, Grey, Lineart, Binary…"""
    words = {"color": ("color", "colour", "24bit color", "rgb"),
             "gray": ("gray", "grey", "grayscale", "greyscale", "8bit gray"),
             "lineart": ("lineart", "binary", "black & white", "black and white", "halftone")}[mode]
    for value in info["modes"]:
        if value.lower() in words:
            return value
    return None


def scan_command(device, mode_word, resolution, area, out):
    """The scanimage command for one scan. area is (left, top, width, height) in mm, or None."""
    argv = [SCANIMAGE, "-d", device, "--format=png", "-o", out, "--progress", "--resolution", str(resolution)]
    if mode_word:
        argv += ["--mode", mode_word]
    if area:
        left, top, width, height = area
        argv += ["-l", f"{left:.1f}", "-t", f"{top:.1f}", "-x", f"{width:.1f}", "-y", f"{height:.1f}"]
    return argv


def scan_error(text):
    text = text.lower()
    if "device busy" in text:
        return "The scanner is busy. Wait for it to finish what it's doing, then try again."
    if "cover open" in text:
        return "The scanner's lid is open. Close it and try again."
    if "jammed" in text:
        return "Paper is stuck in the scanner. Clear it and try again."
    if "no documents" in text or "document feeder out of documents" in text:
        return "The document feeder is empty."
    if "invalid argument" in text or "no such device" in text or "error during device i/o" in text:
        return "The scanner didn't answer. Check that it's on and connected, then click Look Again."
    if "access to resource has been denied" in text or "permission" in text:
        return "freemac wasn't allowed to use the scanner. Unplug it and plug it in again."
    return "The scan didn't finish. Check that the scanner is on and connected, then try again."


def default_folder():
    folder = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOCUMENTS)
    return folder if folder and os.path.isdir(folder) else os.path.expanduser("~")


def default_name():
    return datetime.datetime.now().strftime("Scan %Y-%m-%d at %H.%M.%S")


def write_pdf(pages, target):
    """pages: [(png path, dpi)]. Each page is embedded as JPEG at its real size."""
    surface = None
    try:
        for path, dpi in pages:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file(path)
            w_pt = pixbuf.get_width() * 72.0 / dpi
            h_pt = pixbuf.get_height() * 72.0 / dpi
            if surface is None:
                surface = cairo.PDFSurface(target, w_pt, h_pt)
            else:
                surface.set_size(w_pt, h_pt)
            image = cairo.ImageSurface(cairo.FORMAT_RGB24, pixbuf.get_width(), pixbuf.get_height())
            cr = cairo.Context(image)
            Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
            cr.paint()
            ok, jpeg = pixbuf.save_to_bufferv("jpeg", ["quality"], ["88"])
            if ok:
                image.set_mime_data(cairo.MIME_TYPE_JPEG, bytes(jpeg))
            cr = cairo.Context(surface)
            cr.scale(72.0 / dpi, 72.0 / dpi)
            cr.set_source_surface(image, 0, 0)
            cr.paint()
            cr.show_page()
    finally:
        if surface is not None:
            surface.finish()


# The window ---------------------------------------------------------------

CSS = b"""
.glass-bed { background-color: alpha(@theme_fg_color, 0.06); }
.glass-heading { font-size: 11px; font-weight: 700; color: alpha(@theme_fg_color, 0.55); }
.glass-note { font-size: 12px; color: alpha(@theme_fg_color, 0.6); }
.glass-empty-title { font-size: 20px; font-weight: 700; }
.glass-page { padding: 2px; }
.glass-page image { border: 1px solid alpha(@theme_fg_color, 0.18); background-color: white; }
scrolledwindow.glass-pages, scrolledwindow.glass-pages viewport, flowbox.glass-pages { background-color: transparent; }
flowbox.glass-pages flowboxchild { padding: 4px 6px; border-radius: 8px; background-color: transparent; color: @theme_fg_color; }
flowbox.glass-pages flowboxchild:selected { background-color: alpha(@theme_selected_bg_color, 0.22); color: @theme_fg_color; }
.glass-page-number { font-size: 11px; color: alpha(@theme_fg_color, 0.6); }
"""


class Bed(Gtk.DrawingArea):
    """The scanner's glass: the preview, if any, and the part to scan."""

    def __init__(self, changed):
        super().__init__()
        self.changed = changed
        self.size = DEFAULT_AREA
        self.preview = None
        self.selection = None          # (left, top, width, height) in mm
        self.drag = None
        self.message = None
        self.set_size_request(320, 360)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("motion-notify-event", self._motion)
        self.connect("button-release-event", self._release)

    def frame(self):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        bw, bh = self.size
        scale = min((w - 40) / bw, (h - 40) / bh)
        scale = max(scale, 0.1)
        x0 = (w - bw * scale) / 2
        y0 = (h - bh * scale) / 2
        return x0, y0, scale

    def to_mm(self, x, y):
        x0, y0, scale = self.frame()
        bw, bh = self.size
        return (min(max((x - x0) / scale, 0), bw), min(max((y - y0) / scale, 0), bh))

    def _draw(self, _w, cr):
        x0, y0, scale = self.frame()
        bw, bh = self.size
        pw, ph = bw * scale, bh * scale
        cr.set_source_rgba(0, 0, 0, 0.22)
        cr.rectangle(x0 + 2, y0 + 4, pw, ph)
        cr.fill()
        cr.set_source_rgb(1, 1, 1)
        cr.rectangle(x0, y0, pw, ph)
        cr.fill()
        if self.preview is not None:
            cr.save()
            cr.rectangle(x0, y0, pw, ph)
            cr.clip()
            cr.translate(x0, y0)
            k = pw / self.preview.get_width()
            cr.scale(k, k)
            Gdk.cairo_set_source_pixbuf(cr, self.preview, 0, 0)
            cr.get_source().set_filter(cairo.FILTER_GOOD)
            cr.paint()
            cr.restore()
        elif self.message:
            cr.set_source_rgba(0, 0, 0, 0.4)
            cr.select_font_face("Inter", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
            cr.set_font_size(13)
            for n, line in enumerate(self.message.split("\n")):
                ext = cr.text_extents(line)
                cr.move_to(x0 + (pw - ext.width) / 2 - ext.x_bearing, y0 + ph / 2 - 10 + n * 20)
                cr.show_text(line)
        cr.set_source_rgba(0, 0, 0, 0.25)
        cr.set_line_width(1)
        cr.rectangle(x0 + 0.5, y0 + 0.5, pw - 1, ph - 1)
        cr.stroke()
        if self.selection:
            left, top, width, height = self.selection
            sx, sy, sw, sh = x0 + left * scale, y0 + top * scale, width * scale, height * scale
            cr.set_source_rgba(0, 0, 0, 0.35)
            cr.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
            cr.rectangle(x0, y0, pw, ph)
            cr.rectangle(sx, sy, sw, sh)
            cr.fill()
            cr.set_fill_rule(cairo.FILL_RULE_WINDING)
            rgba = self.get_style_context().lookup_color("theme_selected_bg_color")
            color = rgba[1] if rgba[0] else Gdk.RGBA(0.2, 0.45, 1, 1)
            cr.set_source_rgba(color.red, color.green, color.blue, 1)
            cr.set_line_width(2)
            cr.rectangle(sx, sy, sw, sh)
            cr.stroke()
            for hx, hy in ((sx, sy), (sx + sw, sy), (sx, sy + sh), (sx + sw, sy + sh)):
                cr.arc(hx, hy, 4.5, 0, 6.2832)
                cr.fill()
        return False

    def _press(self, _w, event):
        if event.button != 1 or self.preview is None:
            return False
        self.drag = self.to_mm(event.x, event.y)
        return True

    def _motion(self, _w, event):
        if self.drag is None:
            return False
        ax, ay = self.drag
        bx, by = self.to_mm(event.x, event.y)
        left, top = min(ax, bx), min(ay, by)
        width, height = abs(bx - ax), abs(by - ay)
        self.selection = (left, top, width, height) if width > 3 and height > 3 else None
        self.queue_draw()
        return True

    def _release(self, _w, _event):
        if self.drag is None:
            return False
        self.drag = None
        self.changed()
        return True

    def clear(self):
        self.selection = None
        self.queue_draw()
        self.changed()


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Glass")
        self.set_default_size(1000, 680)
        self.devices = []
        self.device = None
        self.info = {"area": None, "modes": [], "resolutions": [], "range": None}
        self.mode = "color"
        self.resolution = DEFAULT_RESOLUTION
        self.pages = []                 # [(png path, dpi)]
        self.unsaved = False
        self.work = tempfile.mkdtemp(prefix="freemac-glass-")
        self.process = None
        self.busy = None
        self.token = 0
        self.count = 0

        header = Gtk.HeaderBar(show_close_button=True, title="Glass")
        self.set_titlebar(header)
        self.save_button = Gtk.MenuButton(label="Save")
        save_menu = Gtk.Popover()
        save_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        for label, action in (("Save as PDF…", "win.save-pdf"), ("Save as Pictures…", "win.save-pictures")):
            item = Gtk.ModelButton(text=label, action_name=action)
            save_box.pack_start(item, False, False, 0)
        save_box.show_all()
        save_menu.add(save_box)
        self.save_button.set_popover(save_menu)
        self.save_button.get_style_context().add_class("suggested-action")
        header.pack_end(self.save_button)

        body = Gtk.Box()
        self.add(body)
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=16)
        side.set_size_request(250, -1)
        body.pack_start(side, False, False, 0)
        body.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)

        side.pack_start(self.heading("SCANNER"), False, False, 0)
        self.device_button = Gtk.MenuButton()
        self.device_label = Gtk.Label(label="Looking…", xalign=0, ellipsize=Pango.EllipsizeMode.END, max_width_chars=22)
        inner = Gtk.Box(spacing=6)
        inner.pack_start(self.device_label, True, True, 0)
        inner.pack_start(Gtk.Image.new_from_icon_name("pan-down-symbolic", Gtk.IconSize.BUTTON), False, False, 0)
        self.device_button.add(inner)
        self.device_popover = Gtk.Popover()
        self.device_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        self.device_popover.add(self.device_box)
        self.device_button.set_popover(self.device_popover)
        side.pack_start(self.device_button, False, False, 0)
        self.look_button = Gtk.Button(label="Look Again")
        self.look_button.connect("clicked", lambda _b: self.look())
        side.pack_start(self.look_button, False, False, 0)

        side.pack_start(self.heading("COLOUR"), False, False, 8)
        self.mode_buttons = {}
        self.mode_row = self.choice_row([(key, name) for key, name in MODES], self.mode, self._pick_mode,
                                        self.mode_buttons)
        side.pack_start(self.mode_row, False, False, 0)

        side.pack_start(self.heading("RESOLUTION"), False, False, 8)
        self.resolution_holder = Gtk.Box()
        side.pack_start(self.resolution_holder, False, False, 0)
        self.resolution_note = Gtk.Label(xalign=0, wrap=True, max_width_chars=28)
        self.resolution_note.get_style_context().add_class("glass-note")
        side.pack_start(self.resolution_note, False, False, 0)
        self.set_resolutions(list(RESOLUTIONS))

        side.pack_start(self.heading("AREA"), False, False, 8)
        self.area_note = Gtk.Label(xalign=0, wrap=True, max_width_chars=28)
        self.area_note.get_style_context().add_class("glass-note")
        side.pack_start(self.area_note, False, False, 0)
        self.whole = Gtk.Button(label="Scan the Whole Glass")
        self.whole.connect("clicked", lambda _b: self.bed.clear())
        side.pack_start(self.whole, False, False, 0)

        actions = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.status = Gtk.Label(xalign=0, wrap=True, max_width_chars=28)
        self.status.get_style_context().add_class("glass-note")
        self.progress = Gtk.ProgressBar()
        self.progress.set_no_show_all(True)
        buttons = Gtk.Box(spacing=8, homogeneous=True)
        self.preview_button = Gtk.Button(label="Preview")
        self.preview_button.connect("clicked", lambda _b: self.scan(preview=True))
        self.scan_button = Gtk.Button(label="Scan")
        self.scan_button.get_style_context().add_class("suggested-action")
        self.scan_button.connect("clicked", lambda _b: self.scan(preview=False))
        buttons.pack_start(self.preview_button, True, True, 0)
        buttons.pack_start(self.scan_button, True, True, 0)
        self.cancel_button = Gtk.Button(label="Stop")
        self.cancel_button.set_no_show_all(True)
        self.cancel_button.connect("clicked", lambda _b: self.stop())
        actions.pack_start(self.status, False, False, 0)
        actions.pack_start(self.progress, False, False, 0)
        actions.pack_start(buttons, False, False, 0)
        actions.pack_start(self.cancel_button, False, False, 0)
        side.pack_end(actions, False, False, 0)

        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        body.pack_start(right, True, True, 0)
        self.bed = Bed(self.area_changed)
        self.bed.get_style_context().add_class("glass-bed")
        right.pack_start(self.bed, True, True, 0)
        right.pack_start(Gtk.Separator(), False, False, 0)
        strip = Gtk.Box(spacing=10, margin=10)
        self.pages_note = Gtk.Label(xalign=0)
        self.pages_note.get_style_context().add_class("glass-note")
        self.page_flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.SINGLE, max_children_per_line=40,
                                     min_children_per_line=40, homogeneous=False, column_spacing=6)
        self.page_flow.set_orientation(Gtk.Orientation.HORIZONTAL)
        self.page_flow.set_valign(Gtk.Align.START)
        self.page_flow.set_halign(Gtk.Align.START)
        self.page_flow.get_style_context().add_class("glass-pages")
        pages_scroll = Gtk.ScrolledWindow(vscrollbar_policy=Gtk.PolicyType.NEVER)
        pages_scroll.set_size_request(-1, 118)
        pages_scroll.get_style_context().add_class("glass-pages")
        pages_scroll.add(self.page_flow)
        page_tools = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, valign=Gtk.Align.CENTER)
        self.remove_button = Gtk.Button(label="Remove Page")
        self.remove_button.connect("clicked", lambda _b: self.remove_page())
        self.clear_button = Gtk.Button(label="Remove All")
        self.clear_button.connect("clicked", lambda _b: self.clear_pages())
        page_tools.pack_start(self.pages_note, False, False, 0)
        page_tools.pack_start(self.remove_button, False, False, 0)
        page_tools.pack_start(self.clear_button, False, False, 0)
        strip.pack_start(page_tools, False, False, 0)
        strip.pack_start(pages_scroll, True, True, 0)
        right.pack_start(strip, False, False, 0)

        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), css,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        menus.add_actions(self, {"close": self.close, "preview": lambda: self.scan(preview=True),
                                 "scan": lambda: self.scan(preview=False), "save-pdf": self.save_pdf,
                                 "save-pictures": self.save_pictures, "look": self.look,
                                 "whole": self.bed.clear})
        self.connect("destroy", lambda _w: self.cleanup())
        self.show_all()
        self.area_changed()
        self.pages_changed()
        self.look()

    def heading(self, text):
        label = Gtk.Label(label=text, xalign=0)
        label.get_style_context().add_class("glass-heading")
        return label

    def choice_row(self, choices, current, picked, store):
        row = Gtk.Box()
        row.get_style_context().add_class("linked")
        first = None
        for key, name in choices:
            button = Gtk.RadioButton(label=name, group=first, draw_indicator=False)
            first = first or button
            button.set_active(key == current)
            button.connect("toggled", lambda b, k=key: b.get_active() and picked(k))
            store[key] = button
            row.pack_start(button, True, True, 0)
        return row

    def set_resolutions(self, offered):
        for child in self.resolution_holder.get_children():
            self.resolution_holder.remove(child)
        if self.resolution not in offered:
            self.resolution = min(offered, key=lambda r: abs(r - DEFAULT_RESOLUTION))
        self.resolution_buttons = {}
        row = self.choice_row([(r, f"{r} dpi") for r in offered], self.resolution, self._pick_resolution,
                              self.resolution_buttons)
        self.resolution_holder.pack_start(row, True, True, 0)
        row.show_all()
        self._describe_resolution()

    def _pick_mode(self, key):
        self.mode = key

    def _pick_resolution(self, value):
        self.resolution = value
        self._describe_resolution()

    def _describe_resolution(self):
        if self.resolution <= 200:
            words = "Good for sharing on screen."
        elif self.resolution <= 400:
            words = "Good for documents and printing."
        else:
            words = "Fine detail, for photos. Slower and larger."
        self.resolution_note.set_text(words)

    def area_changed(self):
        selection = self.bed.selection
        if selection:
            _l, _t, width, height = selection
            self.area_note.set_text(f"Just the part you marked: {width / 10:.1f} × {height / 10:.1f} cm.")
        elif self.bed.preview is not None:
            self.area_note.set_text("The whole glass. Drag over the preview to scan only part of it.")
        else:
            self.area_note.set_text("The whole glass. Click Preview, then drag over it to scan only part.")
        self.whole.set_sensitive(selection is not None)

    # Scanners -------------------------------------------------------------------

    def set_busy(self, what):
        self.busy = what
        working = what is not None
        for widget in (self.preview_button, self.scan_button, self.look_button, self.device_button,
                       self.mode_row, self.resolution_holder):
            widget.set_sensitive(not working and (widget in (self.look_button, self.mode_row,
                                                             self.resolution_holder) or self.device is not None))
        self.cancel_button.set_visible(what in ("preview", "scan"))
        self.progress.set_visible(what in ("preview", "scan"))
        self.pages_changed()

    def look(self):
        if self.busy:
            return
        if shutil.which(SCANIMAGE) is None:
            self.devices = []
            self.device = None
            self.device_label.set_text("None")
            self.show_message("Scanner support isn't installed.\n"
                              "Install the sane-utils and sane-airscan packages.")
            self.status.set_text("")
            self.set_busy(None)
            return
        self.set_busy("look")
        self.device_label.set_text("Looking…")
        self.status.set_text("Looking for scanners. Network scanners can take a few seconds to answer.")
        self.show_message("Looking for scanners…")
        self.token += 1
        token = self.token

        def work():
            try:
                done = subprocess.run([SCANIMAGE, "-L"], capture_output=True, text=True, timeout=LOOK_TIMEOUT)
                found = parse_devices(done.stdout)
            except (OSError, subprocess.SubprocessError):
                found = []
            GLib.idle_add(self._looked, token, found)
        threading.Thread(target=work, daemon=True).start()

    def _looked(self, token, found):
        if token != self.token:
            return False
        self.devices = found
        for child in self.device_box.get_children():
            self.device_box.remove(child)
        for name, what in found:
            item = Gtk.ModelButton(text=friendly_name(what))
            item.connect("clicked", lambda _b, n=name: self.choose(n))
            self.device_box.pack_start(item, False, False, 0)
        self.device_box.show_all()
        self.set_busy(None)
        if not found:
            self.device = None
            self.device_label.set_text("None found")
            self.status.set_text("")
            self.show_message("No scanner found.\nTurn your scanner on, connect it by USB or to the same\n"
                              "network as this computer, then click Look Again.")
            self.set_busy(None)
            return False
        names = [n for n, _w in found]
        self.choose(self.device if self.device in names else names[0])
        return False

    def choose(self, name):
        self.device_popover.popdown()
        self.device = name
        what = next((w for n, w in self.devices if n == name), name)
        self.device_label.set_text(friendly_name(what))
        self.device_button.set_tooltip_text(what)
        self.status.set_text("")
        self.bed.preview = None
        self.bed.selection = None
        self.show_message("Click Preview to see what's on the glass.")
        self.area_changed()
        self.set_busy("options")
        self.token += 1
        token = self.token

        def work():
            try:
                done = subprocess.run([SCANIMAGE, "-d", name, "-A"], capture_output=True, text=True,
                                      timeout=LOOK_TIMEOUT)
                info = parse_options(done.stdout)
            except (OSError, subprocess.SubprocessError):
                info = parse_options("")
            GLib.idle_add(self._options, token, info)
        threading.Thread(target=work, daemon=True).start()

    def _options(self, token, info):
        if token != self.token:
            return False
        self.info = info
        self.bed.size = info["area"] or DEFAULT_AREA
        self.bed.queue_draw()
        for key, button in self.mode_buttons.items():
            button.set_visible(not info["modes"] or mode_value(info, key) is not None)
        if info["modes"] and mode_value(info, self.mode) is None:
            for key, _name in MODES:
                if mode_value(info, key):
                    self.mode_buttons[key].set_active(True)
                    break
        self.set_resolutions(offered_resolutions(info))
        self.set_busy(None)
        return False

    def show_message(self, text):
        self.bed.message = text
        self.bed.queue_draw()

    # Scanning -------------------------------------------------------------------

    def scan(self, preview):
        if self.busy or self.device is None:
            return
        self.token += 1
        token = self.token
        self.count += 1
        out = os.path.join(self.work, f"{'preview' if preview else 'page'}-{self.count}.png")
        mode = mode_value(self.info, "color" if preview else self.mode)
        dpi = PREVIEW_DPI if preview else self.resolution
        if preview and self.info["resolutions"] and PREVIEW_DPI not in self.info["resolutions"]:
            dpi = min(self.info["resolutions"])
        elif preview and self.info["range"]:
            dpi = max(int(self.info["range"][0]), PREVIEW_DPI)
        area = None if preview else self.bed.selection
        argv = scan_command(self.device, mode, dpi, area, out)
        self.set_busy("preview" if preview else "scan")
        self.progress.set_fraction(0)
        self.status.set_text("Previewing…" if preview else "Scanning…")
        try:
            self.process = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                            start_new_session=True)
        except OSError:
            self.process = None
            self.set_busy(None)
            self.status.set_text("The scanner couldn't be started.")
            return
        process = self.process

        def work():
            errors = bytearray()
            buffer = b""
            try:
                while True:
                    chunk = process.stderr.read1(256) if hasattr(process.stderr, "read1") else \
                        process.stderr.read(256)
                    if not chunk:
                        break
                    buffer = (buffer + chunk)[-512:]
                    if len(errors) < 8192:
                        errors.extend(chunk)
                    found = PROGRESS.findall(buffer)
                    if found:
                        GLib.idle_add(self._progress, token, float(found[-1]) / 100)
                process.wait(timeout=SCAN_TIMEOUT)
            except (OSError, subprocess.SubprocessError):
                pass
            GLib.idle_add(self._scanned, token, process, preview, out, dpi, area,
                          PROGRESS.sub(b"", bytes(errors)).decode("utf-8", "replace"))
        threading.Thread(target=work, daemon=True).start()

    def _progress(self, token, fraction):
        if token == self.token:
            self.progress.set_fraction(min(max(fraction, 0), 1))
        return False

    def _scanned(self, token, process, preview, out, dpi, area, errors):
        if process is self.process:
            self.process = None
        if token != self.token:
            return False
        stopped = self.busy == "stopping"
        self.set_busy(None)
        pixbuf = None
        if not stopped and process.returncode == 0 and os.path.exists(out):
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file(out)
            except GLib.Error:
                pixbuf = None
        if pixbuf is None:
            self.status.set_text("Stopped." if stopped else scan_error(errors))
            try:
                os.remove(out)
            except OSError:
                pass
            return False
        self.status.set_text("")
        if preview:
            self.bed.preview = pixbuf
            self.bed.message = None
            # The preview tells the real size of the glass when -A didn't.
            if not self.info["area"]:
                self.bed.size = (pixbuf.get_width() * MM_PER_INCH / dpi, pixbuf.get_height() * MM_PER_INCH / dpi)
            self.bed.queue_draw()
            self.area_changed()
            os.remove(out)
        else:
            self.pages.append((out, dpi))
            self.add_thumbnail(out, pixbuf)
            self.status.set_text(f"Page {len(self.pages)} scanned.")
        self.pages_changed()
        return False

    def stop(self):
        process = self.process
        if process is None or self.busy not in ("preview", "scan"):
            return
        self.busy = "stopping"
        self.status.set_text("Stopping…")
        try:
            os.killpg(process.pid, signal.SIGINT)
        except OSError:
            pass
        GLib.timeout_add_seconds(5, self._kill, process)

    def _kill(self, process):
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except OSError:
                pass
        return False

    # Pages -----------------------------------------------------------------------

    def add_thumbnail(self, path, pixbuf):
        scale = 90 / max(pixbuf.get_width(), pixbuf.get_height())
        thumb = pixbuf.scale_simple(max(1, int(pixbuf.get_width() * scale)),
                                    max(1, int(pixbuf.get_height() * scale)), GdkPixbuf.InterpType.BILINEAR)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.get_style_context().add_class("glass-page")
        box.pack_start(Gtk.Image.new_from_pixbuf(thumb), False, False, 0)
        number = Gtk.Label(label=str(len(self.pages)))
        number.get_style_context().add_class("glass-page-number")
        box.pack_start(number, False, False, 0)
        child = Gtk.FlowBoxChild()
        child.path = path
        child.add(box)
        child.show_all()
        self.unsaved = True
        self.page_flow.add(child)
        self.page_flow.select_child(child)

    def renumber(self):
        for n, child in enumerate(self.page_flow.get_children(), 1):
            child.get_child().get_children()[1].set_text(str(n))

    def remove_page(self):
        selected = self.page_flow.get_selected_children()
        if not selected:
            return
        child = selected[0]
        self.pages = [(p, d) for p, d in self.pages if p != child.path]
        try:
            os.remove(child.path)
        except OSError:
            pass
        self.page_flow.remove(child)
        self.renumber()
        self.pages_changed()

    def clear_pages(self):
        if not self.pages:
            return
        answer = alert.ask(self, f"Remove all {len(self.pages)} pages?", "Pages you haven't saved are lost.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Remove All", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.CANCEL, destructive=Gtk.ResponseType.OK)
        if answer != Gtk.ResponseType.OK:
            return
        for child in self.page_flow.get_children():
            self.page_flow.remove(child)
        for path, _dpi in self.pages:
            try:
                os.remove(path)
            except OSError:
                pass
        self.pages = []
        self.pages_changed()

    def pages_changed(self):
        count = len(self.pages)
        self.pages_note.set_text("No pages yet" if not count else f"{count} page" + ("" if count == 1 else "s"))
        idle = self.busy is None
        self.save_button.set_sensitive(bool(count) and idle)
        self.remove_button.set_sensitive(bool(count) and idle)
        self.clear_button.set_sensitive(count > 1 and idle)
        for name in ("save-pdf", "save-pictures"):
            action = self.lookup_action(name)
            if action:
                action.set_enabled(bool(count) and idle)

    def ask_target(self, title, name, kind, patterns):
        chooser = Gtk.FileChooserNative.new(title, self, Gtk.FileChooserAction.SAVE, "Save", "Cancel")
        chooser.set_do_overwrite_confirmation(True)
        chooser.set_current_folder(default_folder())
        chooser.set_current_name(name)
        files = Gtk.FileFilter()
        files.set_name(kind)
        for pattern in patterns:
            files.add_pattern(pattern)
            files.add_pattern(pattern.upper())
        chooser.add_filter(files)
        if chooser.run() != Gtk.ResponseType.ACCEPT:
            return None
        return chooser.get_filename()

    def save_pdf(self):
        if not self.pages or self.busy:
            return False
        target = self.ask_target("Save as PDF", default_name() + ".pdf", "PDF documents", ["*.pdf"])
        if not target:
            return False
        if not target.lower().endswith(".pdf"):
            target += ".pdf"
        try:
            write_pdf(self.pages, target)
        except (OSError, GLib.Error, cairo.Error):
            alert.tell(self, "The PDF couldn't be saved", "Check that there's room and you can save there.")
            return False
        self.status.set_text(f"Saved {os.path.basename(target)}.")
        self.unsaved = False
        return True

    def save_pictures(self):
        if not self.pages or self.busy:
            return
        many = len(self.pages) > 1
        target = self.ask_target("Save as Pictures" if many else "Save as Picture", default_name() + ".png",
                                 "PNG or JPEG pictures", ["*.png", "*.jpg", "*.jpeg"])
        if not target:
            return
        stem, ext = os.path.splitext(target)
        ext = ext.lower() if ext.lower() in (".png", ".jpg", ".jpeg") else ".png"
        try:
            for n, (path, _dpi) in enumerate(self.pages, 1):
                out = f"{stem} {n}{ext}" if many else stem + ext
                if ext == ".png":
                    shutil.copyfile(path, out)
                else:
                    GdkPixbuf.Pixbuf.new_from_file(path).savev(out, "jpeg", ["quality"], ["92"])
        except (OSError, GLib.Error):
            alert.tell(self, "The pictures couldn't be saved", "Check that there's room and you can save there.")
            return
        self.status.set_text(f"Saved {len(self.pages)} pictures." if many else f"Saved {os.path.basename(out)}.")
        self.unsaved = False

    def cleanup(self):
        process = self.process
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGINT)
            except OSError:
                pass
        shutil.rmtree(self.work, ignore_errors=True)

    def confirm_close(self):
        if not self.pages or not self.unsaved:
            return True
        answer = alert.ask(self, "Save your scanned pages before closing?",
                           "Pages you haven't saved are lost when Glass closes.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Don't Save", Gtk.ResponseType.NO),
                            ("Save as PDF…", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK, destructive=Gtk.ResponseType.NO)
        if answer == Gtk.ResponseType.OK:
            return self.save_pdf()
        return answer == Gtk.ResponseType.NO

    def about(self):
        alert.tell(self, "About Glass", "Glass scans with scanners and all-in-one printers. Part of freemac.")


def menubar():
    return menus.menubar([
        ("_File", [[("Save as PDF…", "win.save-pdf", "<Ctrl>s"),
                    ("Save as Pictures…", "win.save-pictures", "<Shift><Ctrl>s")],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_Scan", [[("Preview", "win.preview", "<Ctrl>p"), ("Scan", "win.scan", "<Ctrl>Return")],
                   [("Scan the Whole Glass", "win.whole", None), ("Look for Scanners Again", "win.look", None)]]),
    ])


class Glass(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": self.quit_politely,
                                 "about": lambda: self.window and self.window.about()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.set_accels_for_action("win.save-pdf", ["<Control>s"])
        self.set_accels_for_action("win.save-pictures", ["<Shift><Control>s"])
        self.set_accels_for_action("win.preview", ["<Control>p"])
        self.set_accels_for_action("win.scan", ["<Control>Return"])
        self.set_accels_for_action("win.close", ["<Control>w"])
        self.set_menubar(menubar())

    def quit_politely(self):
        if self.window:
            self.window.close()

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("delete-event", lambda w, _e: not w.confirm_close())
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-glass")
    return Glass().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
