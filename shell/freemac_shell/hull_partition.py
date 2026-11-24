# SPDX-License-Identifier: GPL-3.0-or-later
"""Hull's Partition sheet: a pie of the drive, one slice for each volume.

Click a slice to choose it, then give it a name, a format and a size. + splits
the chosen volume in two and − takes it away. Drag the white dots between
slices to change their sizes. Apply hands the layout back; nothing on the
drive changes until Hull has asked once more.

Original freemac code; the arithmetic is in partition_plan.
"""
import math

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, Gtk, Pango, PangoCairo  # noqa: E402

from . import hull_store, partition_plan  # noqa: E402
from .hull_store import size_words  # noqa: E402

COLOURS = [(0.26, 0.55, 0.96), (0.30, 0.74, 0.42), (0.98, 0.62, 0.20), (0.62, 0.42, 0.90),
           (0.18, 0.72, 0.76), (0.94, 0.38, 0.62), (0.92, 0.76, 0.18), (0.90, 0.32, 0.30)]
PIE = 250                 # the pie's size, in pixels
TOP = -math.pi / 2        # slices start at twelve o'clock, going clockwise
GRAB = 0.12               # how near a dot (in radians) a press picks it up
GB = 1000 ** 3
MB = 1000 ** 2


class Pie(Gtk.DrawingArea):
    def __init__(self, sheet):
        super().__init__()
        self.sheet = sheet
        self.set_size_request(PIE + 28, PIE + 28)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK)
        self.dragging = None
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("motion-notify-event", self._motion)
        self.connect("button-release-event", self._release)

    # -- where things are --

    def _centre(self):
        return self.get_allocated_width() / 2, self.get_allocated_height() / 2, PIE / 2

    def _lines(self):
        """The angle of each line between two slices."""
        layout = self.sheet.layout
        total = layout.total or 1
        return [TOP + 2 * math.pi * layout.start(k + 1) / total for k in range(len(layout) - 1)]

    def _angle(self, x, y):
        cx, cy, _r = self._centre()
        angle = math.atan2(y - cy, x - cx)
        while angle < TOP:
            angle += 2 * math.pi
        return angle

    def _slice_at(self, x, y):
        cx, cy, r = self._centre()
        if math.hypot(x - cx, y - cy) > r:
            return None
        part = (self._angle(x, y) - TOP) / (2 * math.pi) * self.sheet.layout.total
        for i in range(len(self.sheet.layout)):
            if part < self.sheet.layout.start(i + 1):
                return i
        return len(self.sheet.layout) - 1

    # -- the mouse --

    def _press(self, _w, event):
        cx, cy, r = self._centre()
        near_edge = math.hypot(event.x - cx, event.y - cy) > r * 0.55
        if near_edge:
            angle = self._angle(event.x, event.y)
            for k, line in enumerate(self._lines()):
                if abs(angle - line) < GRAB:
                    self.dragging = k
                    return True
        i = self._slice_at(event.x, event.y)
        if i is not None:
            self.sheet.choose(i)
        return True

    def _motion(self, _w, event):
        if self.dragging is None:
            return False
        position = (self._angle(event.x, event.y) - TOP) / (2 * math.pi) * self.sheet.layout.total
        self.sheet.layout.move_line(self.dragging, position)
        self.sheet.changed()
        return True

    def _release(self, *_a):
        self.dragging = None
        return False

    # -- drawing --

    def _draw(self, widget, cr):
        layout = self.sheet.layout
        cx, cy, r = self._centre()
        total = layout.total or 1
        for i, part in enumerate(layout.parts):
            a0 = TOP + 2 * math.pi * layout.start(i) / total
            a1 = TOP + 2 * math.pi * layout.start(i + 1) / total
            cr.set_source_rgb(*COLOURS[i % len(COLOURS)])
            if len(layout) == 1:
                cr.arc(cx, cy, r, 0, 2 * math.pi)
            else:
                cr.move_to(cx, cy)
                cr.arc(cx, cy, r, a0, a1)
                cr.close_path()
            cr.fill()
        # The lines between slices, then the chosen slice's outline.
        cr.set_source_rgb(1, 1, 1)
        cr.set_line_width(2)
        for line in self._lines() if len(layout) > 1 else []:
            cr.move_to(cx, cy)
            cr.line_to(cx + r * math.cos(line), cy + r * math.sin(line))
            cr.stroke()
        # The chosen slice: a band of its colour just outside the pie.
        chosen = self.sheet.chosen
        a0 = TOP + 2 * math.pi * layout.start(chosen) / total
        a1 = TOP + 2 * math.pi * layout.start(chosen + 1) / total
        red, green, blue = COLOURS[chosen % len(COLOURS)]
        cr.set_source_rgb(red * 0.75, green * 0.75, blue * 0.75)
        cr.set_line_width(5)
        if len(layout) > 1:
            cr.new_sub_path()
            cr.arc(cx, cy, r + 5, a0 + 0.02, a1 - 0.02)
            cr.stroke()
        # Each slice's name and size, where there's room.
        for i, part in enumerate(layout.parts):
            a0 = TOP + 2 * math.pi * layout.start(i) / total
            a1 = TOP + 2 * math.pi * layout.start(i + 1) / total
            if a1 - a0 < 0.5:
                continue
            middle = (a0 + a1) / 2
            far = 0 if len(layout) == 1 else r * 0.58
            text = widget.create_pango_layout("")       # the desktop's own font
            text.set_markup(f"<b>{_escape(part.name)}</b>\n{size_words(part.size)}", -1)
            text.set_alignment(Pango.Alignment.CENTER)
            text.set_width(int(r * 0.9 * Pango.SCALE))
            text.set_ellipsize(Pango.EllipsizeMode.END)
            w, h = text.get_pixel_size()
            cr.move_to(cx + far * math.cos(middle) - r * 0.45, cy + far * math.sin(middle) - h / 2)
            cr.set_source_rgb(1, 1, 1)
            PangoCairo.show_layout(cr, text)
        # The dots to drag.
        for line in self._lines():
            x, y = cx + r * math.cos(line), cy + r * math.sin(line)
            cr.new_path()
            cr.arc(x, y, 6, 0, 2 * math.pi)
            cr.set_source_rgb(1, 1, 1)
            cr.fill_preserve()
            cr.set_source_rgba(0, 0, 0, 0.35)
            cr.set_line_width(1)
            cr.stroke()
        return True


def _escape(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


class Sheet(Gtk.Dialog):
    """Run it: the Layout to apply, or None."""

    def __init__(self, parent, drive, icon):
        super().__init__(title="Partition", transient_for=parent, modal=True, resizable=False)
        self.drive = drive
        fstype = next((v.fstype for v in drive.volumes if v.fstype in ("exfat", "vfat", "ext4")), "exfat")
        name = "UNTITLED" if fstype == "vfat" else "Untitled"
        self.layout = partition_plan.Layout(drive.size, name, fstype)
        self.chosen = 0
        self.unit = GB if drive.size >= 4 * GB else MB
        self._quiet = False

        header = Gtk.HeaderBar(title=f"Partition “{drive.name}”", show_close_button=False)
        cancel = Gtk.Button(label="Cancel")
        cancel.connect("clicked", lambda *_: self.response(Gtk.ResponseType.CANCEL))
        header.pack_start(cancel)
        self.apply = Gtk.Button(label="Apply")
        self.apply.get_style_context().add_class("suggested-action")
        self.apply.connect("clicked", lambda *_: self.response(Gtk.ResponseType.OK))
        header.pack_end(self.apply)
        self.set_titlebar(header)
        header.show_all()

        area = self.get_content_area()
        box = Gtk.Box(spacing=24)
        for side in ("start", "end", "top", "bottom"):
            getattr(box, "set_margin_" + side)(20)
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.pie = Pie(self)
        left.pack_start(self.pie, False, False, 0)
        buttons = Gtk.Box(halign=Gtk.Align.START)
        buttons.get_style_context().add_class("linked")
        self.add_button_ = Gtk.Button.new_from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON)
        self.add_button_.set_tooltip_text("Add a volume")
        self.add_button_.connect("clicked", lambda *_: self.add())
        self.remove_button = Gtk.Button.new_from_icon_name("list-remove-symbolic", Gtk.IconSize.BUTTON)
        self.remove_button.set_tooltip_text("Remove this volume")
        self.remove_button.connect("clicked", lambda *_: self.remove())
        buttons.pack_start(self.add_button_, False, False, 0)
        buttons.pack_start(self.remove_button, False, False, 0)
        left.pack_start(buttons, False, False, 0)
        box.pack_start(left, False, False, 0)

        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        intro = Gtk.Label(label="Click + to add a volume, then choose each one’s name, format and size. "
                                "Drag the white dots to change sizes.",
                          xalign=0, wrap=True, max_width_chars=34)
        intro.get_style_context().add_class("hull-what")
        right.pack_start(intro, False, False, 0)
        self.heading = Gtk.Label(xalign=0)
        self.heading.get_style_context().add_class("hull-drive-name")
        right.pack_start(self.heading, False, False, 0)
        grid = Gtk.Grid(column_spacing=8, row_spacing=10)
        grid.attach(Gtk.Label(label="Name:", xalign=1), 0, 0, 1, 1)
        self.name = Gtk.Entry(width_chars=18, activates_default=False)
        self.name.connect("changed", self._named)
        grid.attach(self.name, 1, 0, 2, 1)
        grid.attach(Gtk.Label(label="Format:", xalign=1), 0, 1, 1, 1)
        self.format = Gtk.ComboBoxText()
        for title, fstype_, _what, _longest in hull_store.FORMATS:
            self.format.append(fstype_, title)
        self.format.connect("changed", self._formatted)
        grid.attach(self.format, 1, 1, 2, 1)
        grid.attach(Gtk.Label(label="Size:", xalign=1), 0, 2, 1, 1)
        digits = 1 if self.unit == GB else 0
        self.size = Gtk.SpinButton(digits=digits, numeric=True)
        self.size.set_increments(0.1 if self.unit == GB else 1, 1 if self.unit == GB else 10)
        self.size.connect("value-changed", self._sized)
        grid.attach(self.size, 1, 2, 1, 1)
        grid.attach(Gtk.Label(label="GB" if self.unit == GB else "MB", xalign=0), 2, 2, 1, 1)
        right.pack_start(grid, False, False, 0)
        self.about = Gtk.Label(xalign=0, wrap=True, max_width_chars=34)
        self.about.get_style_context().add_class("hull-shared")
        right.pack_start(self.about, False, False, 0)
        self.whole = Gtk.Label(xalign=0, wrap=True, max_width_chars=34)
        self.whole.get_style_context().add_class("hull-what")
        right.pack_end(self.whole, False, False, 0)
        box.pack_start(right, True, True, 0)
        area.pack_start(box, True, True, 0)
        area.show_all()
        self.set_default_response(Gtk.ResponseType.OK)
        self.choose(0)

    # -- the chosen volume --

    def choose(self, i):
        self.chosen = max(0, min(i, len(self.layout) - 1))
        self.show_part()
        self.pie.queue_draw()

    def show_part(self):
        part = self.layout.parts[self.chosen]
        self._quiet = True
        self.heading.set_text(f"Volume {self.chosen + 1} of {len(self.layout)}")
        if self.name.get_text() != part.name:
            self.name.set_text(part.name)
        longest = next((f[3] for f in hull_store.FORMATS if f[1] == part.fstype), 16)
        self.name.set_max_length(longest)
        self.format.set_active_id(part.fstype)
        self.about.set_text(next((f[2] for f in hull_store.FORMATS if f[1] == part.fstype), ""))
        one = len(self.layout) == 1
        lowest = partition_plan.MINIMUM / self.unit
        highest = (self.layout.total - partition_plan.MINIMUM * (len(self.layout) - 1)) / self.unit
        self.size.set_range(lowest if not one else part.size / self.unit, highest)
        self.size.set_value(part.size / self.unit)
        self.size.set_sensitive(not one)
        self.add_button_.set_sensitive(self.layout.can_add(self.chosen))
        self.remove_button.set_sensitive(self.layout.can_remove())
        n = len(self.layout)
        self.whole.set_text(f"{size_words(self.layout.total)} in {n} volume{'s' if n != 1 else ''}. "
                            "Everything on the drive now will be erased.")
        self.apply.set_sensitive(all(p.name.strip() for p in self.layout.parts))
        self._quiet = False

    def changed(self):
        self.show_part()
        self.pie.queue_draw()

    def _named(self, entry):
        if self._quiet:
            return
        part = self.layout.parts[self.chosen]
        text = entry.get_text()
        if part.fstype == "vfat" and text != text.upper():
            entry.set_text(text.upper())       # MS-DOS names are capital letters
            return
        part.name = text.strip()
        self.apply.set_sensitive(all(p.name.strip() for p in self.layout.parts))
        self.pie.queue_draw()

    def _formatted(self, combo):
        if self._quiet or combo.get_active_id() is None:
            return
        part = self.layout.parts[self.chosen]
        part.fstype = combo.get_active_id()
        longest = next((f[3] for f in hull_store.FORMATS if f[1] == part.fstype), 16)
        name = part.name.upper() if part.fstype == "vfat" else part.name
        part.name = name.encode()[:longest].decode(errors="ignore") if len(name.encode()) > longest else name
        self.changed()

    def _sized(self, spin):
        if self._quiet:
            return
        self.layout.resize(self.chosen, spin.get_value() * self.unit)
        self.changed()

    def add(self):
        i = self.layout.add(self.chosen)
        if i is not None:
            self.choose(i)

    def remove(self):
        self.choose(self.layout.remove(self.chosen))

    def run_sheet(self):
        answer = self.run()
        self.destroy()
        return self.layout if answer == Gtk.ResponseType.OK else None


def summary(layout):
    """'“A” (ExFAT, 2 GB), “B” (ext4, 6 GB)' for the last question."""
    names = {"exfat": "ExFAT", "vfat": "MS-DOS", "ext4": "ext4"}
    return ", ".join(f"“{p.name}” ({names.get(p.fstype, p.fstype)}, {size_words(p.size)})"
                     for p in layout.parts)
