# SPDX-License-Identifier: GPL-3.0-or-later
"""Hull: the drives, how full each is, and what to do with them.

The sidebar lists the disks inside the computer, then the ones plugged in,
each with the volumes on it. Choosing one shows how much of it is used,
what kind of disk or file system it is and where it's connected. The
buttons at the top mount or unmount a volume, erase a volume or a whole
drive (asking for a name and a format first), and eject a drive. Double-
click a volume, or choose Edit > Rename, to give it a new name.

The disk freemac is running from can be looked at but not changed.

Original freemac code; the udisks2 side is in hull_store.
"""
import os
import sys
import threading

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import alert, disk_images, hull_store, menus, style  # noqa: E402
from .hull_store import size_words  # noqa: E402

APP_ID = "org.freemac.Hull"

CSS = b"""
.hull-side { background: alpha(currentColor, 0.04); border-right: 1px solid alpha(currentColor, 0.1); }
.hull-side list { background: transparent; }
.hull-side row { border-radius: 6px; margin: 0 6px; padding: 4px 6px; background: transparent; }
.hull-side row:selected { background: @theme_selected_bg_color; color: white; }
.hull-side row:selected image { opacity: 1; }
.hull-section { font-weight: bold; font-size: 0.85em; opacity: 0.55; margin: 12px 14px 4px 14px; }
.hull-drive-name { font-weight: 600; }
.hull-name { font-size: 1.45em; font-weight: bold; }
.hull-what { opacity: 0.65; }
.hull-size { font-size: 1.45em; font-weight: 300; }
.hull-shared { font-size: 0.8em; opacity: 0.55; }
.hull-note { opacity: 0.7; }
.hull-facts { border: 1px solid alpha(currentColor, 0.12); border-radius: 8px; }
.hull-fact-label { opacity: 0.6; }
.hull-fact { border-bottom: 1px solid alpha(currentColor, 0.08); padding: 7px 12px; }
.hull-legend-dot { border-radius: 5px; min-width: 10px; min-height: 10px; }
.hull-tool { padding: 2px 8px; }
"""

USED = (0.26, 0.55, 0.96)
FREE_ALPHA = 0.10
ERASE, RENAME = 10, 11


def drive_icon(drive):
    image = getattr(drive, "image", None)
    if image:
        return "media-optical" if image.lower().endswith(".iso") else "drive-removable-media"
    if drive.optical:
        return "media-optical"
    if drive.bus == "sdio":
        return "media-flash"
    return "drive-removable-media" if drive.external else "drive-harddisk"


def volume_icon(vol):
    return drive_icon(vol.drive) if vol.drive else "drive-harddisk"


class Bar(Gtk.DrawingArea):
    """How full it is: one rounded bar, the used part coloured."""

    def __init__(self):
        super().__init__()
        self.set_size_request(-1, 22)
        self.fraction = None
        self.connect("draw", self._draw)

    def show_fraction(self, fraction):
        self.fraction = fraction
        self.queue_draw()

    def _draw(self, widget, cr):
        w, h = widget.get_allocated_width(), widget.get_allocated_height()
        r = h / 2

        def rounded(x, width):
            cr.new_sub_path()
            cr.arc(x + r, r, r, 1.5708, 4.7124)
            cr.arc(x + width - r, r, r, 4.7124, 1.5708)
            cr.close_path()

        fg = widget.get_style_context().get_color(Gtk.StateFlags.NORMAL)
        cr.set_source_rgba(fg.red, fg.green, fg.blue, FREE_ALPHA)
        rounded(0, w)
        cr.fill()
        if self.fraction:
            cr.save()
            rounded(0, w)
            cr.clip()
            cr.set_source_rgb(*USED)
            cr.rectangle(0, 0, max(h, w * min(1.0, self.fraction)), h)
            cr.fill()
            cr.restore()
        return True


def ask_name_and_format(parent, title, text, button, name, with_format, icon):
    """An alert with a Name field (and a Format menu): (name, fstype) or None."""
    buttons = [("Cancel", Gtk.ResponseType.CANCEL), (button, Gtk.ResponseType.OK)]
    dialog = alert.build(parent, title, text, buttons, default=Gtk.ResponseType.OK, icon=icon)
    body = dialog.get_content_area().get_children()[0]
    grid = Gtk.Grid(column_spacing=8, row_spacing=8, halign=Gtk.Align.CENTER)
    grid.attach(Gtk.Label(label="Name:", xalign=1), 0, 0, 1, 1)
    entry = Gtk.Entry(text=name, activates_default=True, width_chars=18)
    grid.attach(entry, 1, 0, 1, 1)
    chosen = {"fstype": None}
    if with_format:
        grid.attach(Gtk.Label(label="Format:", xalign=1, valign=Gtk.Align.START), 0, 1, 1, 1)
        choices = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        first = None
        for title_, fstype, what, longest in hull_store.FORMATS:
            radio = Gtk.RadioButton.new_from_widget(first)
            first = first or radio
            words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            words.pack_start(Gtk.Label(label=title_, xalign=0), False, False, 0)
            about = Gtk.Label(label=what, xalign=0, wrap=True, max_width_chars=26)
            about.get_style_context().add_class("hull-shared")
            words.pack_start(about, False, False, 0)
            radio.add(words)

            def picked(button, fstype=fstype, longest=longest):
                if button.get_active():
                    chosen["fstype"] = fstype
                    entry.set_max_length(longest)
            radio.connect("toggled", picked)
            choices.pack_start(radio, False, False, 0)
        picked_first = hull_store.FORMATS[0]
        chosen["fstype"] = picked_first[1]
        entry.set_max_length(picked_first[3])
        grid.attach(choices, 1, 1, 1, 1)
    else:
        entry.set_max_length(16)
    body.pack_start(grid, False, False, 4)
    body.reorder_child(grid, len(body.get_children()) - 2)
    grid.show_all()
    entry.grab_focus()

    def check(*_a):
        ok = bool(entry.get_text().strip())
        for child in body.get_children()[-1].get_children():
            if child.get_label() == button:
                child.set_sensitive(ok)
    entry.connect("changed", check)
    check()
    answer = dialog.run()
    result = None
    if answer == Gtk.ResponseType.OK and entry.get_text().strip():
        fstype = chosen["fstype"]
        label = entry.get_text().strip()
        if fstype == "vfat":
            label = label.upper()        # MS-DOS names are capital letters
        result = (label, fstype)
    dialog.destroy()
    return result


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Hull")
        self.set_default_size(880, 560)
        self.actions = hull_store.Actions()
        self.drives = []
        self.chosen = None             # ("drive" | "volume", object path)
        self.busy = False
        self._pending = 0

        header = Gtk.HeaderBar(show_close_button=True, title="Hull")
        self.set_titlebar(header)
        self.mount_button = self._tool("drive-harddisk-symbolic", "Mount", self.toggle_mount)
        self.erase_button = self._tool("edit-clear-all-symbolic", "Erase", self.erase)
        self.eject_button = self._tool("media-eject-symbolic", "Eject", self.eject)
        self.info_button = self._tool("document-edit-symbolic", "Rename", self.rename)
        for button in (self.eject_button, self.info_button, self.erase_button, self.mount_button):
            header.pack_end(button)
        self.spinner = Gtk.Spinner()
        header.pack_start(self.spinner)

        paned = Gtk.Paned()
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.get_style_context().add_class("hull-side")
        side.set_size_request(230, -1)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.sidebar = Gtk.ListBox()
        self.sidebar.set_header_func(self._section)
        self.sidebar.connect("row-selected", self._selected)
        self.sidebar.connect("row-activated", lambda _l, row: row.kind == "volume" and self.rename())
        scroll.add(self.sidebar)
        side.pack_start(scroll, True, True, 0)
        paned.pack1(side, False, False)

        detail = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        detail.set_margin_start(24)
        detail.set_margin_end(24)
        detail.set_margin_top(20)
        detail.set_margin_bottom(20)
        top = Gtk.Box(spacing=14)
        self.big_icon = Gtk.Image(pixel_size=64)
        top.pack_start(self.big_icon, False, False, 0)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
        self.name_label = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.name_label.get_style_context().add_class("hull-name")
        self.what_label = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.what_label.get_style_context().add_class("hull-what")
        words.pack_start(self.name_label, False, False, 0)
        words.pack_start(self.what_label, False, False, 0)
        top.pack_start(words, True, True, 0)
        sizes = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
        self.size_label = Gtk.Label(xalign=1)
        self.size_label.get_style_context().add_class("hull-size")
        self.shared_label = Gtk.Label(xalign=1)
        self.shared_label.get_style_context().add_class("hull-shared")
        sizes.pack_start(self.size_label, False, False, 0)
        sizes.pack_start(self.shared_label, False, False, 0)
        top.pack_end(sizes, False, False, 0)
        detail.pack_start(top, False, False, 0)

        self.bar = Bar()
        detail.pack_start(self.bar, False, False, 0)
        legend = Gtk.Box(spacing=24)
        self.used_label = self._legend(legend, "used")
        self.free_label = self._legend(legend, "free")
        self.legend = legend
        detail.pack_start(legend, False, False, 0)

        self.note = Gtk.Label(xalign=0, wrap=True)
        self.note.get_style_context().add_class("hull-note")
        detail.pack_start(self.note, False, False, 0)

        self.facts = Gtk.Grid(column_homogeneous=True)
        self.facts.get_style_context().add_class("hull-facts")
        detail.pack_start(self.facts, False, False, 0)

        self.empty = Gtk.Label(label="No drive chosen")
        self.empty.get_style_context().add_class("hull-what")
        self.stack = Gtk.Stack()
        self.stack.add_named(detail, "detail")
        self.stack.add_named(self.empty, "empty")
        paned.pack2(self.stack, True, False)
        self.add(paned)

        menus.add_actions(self, {"close": self.close, "mount": self.toggle_mount, "erase": self.erase,
                                 "eject": self.eject, "rename": self.rename, "open-image": self.open_image,
                                 "new-image": self.new_image})
        self.bus, self._watch = hull_store.watch(self._changed)
        self.connect("destroy", lambda *_: [self.bus.signal_unsubscribe(i) for i in self._watch])
        header.show_all()
        paned.show_all()
        self.reload()

    # -- building --

    def _tool(self, icon, label, callback):
        button = Gtk.Button(tooltip_text=label)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON), False, False, 0)
        text = Gtk.Label(label=label)
        text.get_style_context().add_class("hull-shared")
        box.pack_start(text, False, False, 0)
        button.add(box)
        button.text = text
        button.get_style_context().add_class("hull-tool")
        button.set_relief(Gtk.ReliefStyle.NONE)
        button.connect("clicked", lambda _b: callback())
        return button

    def _legend(self, box, what):
        part = Gtk.Box(spacing=6)
        dot = Gtk.DrawingArea()
        dot.set_size_request(10, 10)
        dot.set_valign(Gtk.Align.CENTER)

        def draw(widget, cr, used=(what == "used")):
            fg = widget.get_style_context().get_color(Gtk.StateFlags.NORMAL)
            if used:
                cr.set_source_rgb(*USED)
            else:
                cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.25)
            cr.arc(5, 5, 5, 0, 6.2832)
            cr.fill()
        dot.connect("draw", draw)
        part.pack_start(dot, False, False, 0)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        title = Gtk.Label(label="Used" if what == "used" else "Free", xalign=0)
        title.get_style_context().add_class("hull-shared")
        value = Gtk.Label(xalign=0)
        words.pack_start(title, False, False, 0)
        words.pack_start(value, False, False, 0)
        part.pack_start(words, False, False, 0)
        box.pack_start(part, False, False, 0)
        return value

    def _section(self, row, before):
        title = row.section
        if before is None or before.section != title:
            label = Gtk.Label(label=title, xalign=0)
            label.get_style_context().add_class("hull-section")
            row.set_header(label)
        else:
            row.set_header(None)

    # -- reading --

    def _changed(self):
        # udisks sends a burst of signals for one change: read once after.
        self._pending += 1
        GLib.timeout_add(400, self._settle)

    def _settle(self):
        self._pending -= 1
        if self._pending == 0:
            self.reload()
        return False

    def reload(self):
        try:
            self.drives = hull_store.read(self.bus)
        except GLib.Error:
            self.drives = []
        chosen = self.chosen
        for row in self.sidebar.get_children():
            self.sidebar.remove(row)
        rows = []
        for drive in self.drives:
            section = "Disk Images" if getattr(drive, "image", None) else \
                ("External" if drive.external else ("Disc" if drive.optical else "Internal"))
            rows.append(self._row("drive", drive, drive.name, drive_icon(drive), section, 0))
            for vol in drive.volumes:
                rows.append(self._row("volume", vol, vol.name, volume_icon(vol), section, 18))
        for row in rows:
            self.sidebar.add(row)
        self.sidebar.show_all()
        wanted = next((r for r in rows if chosen and (r.kind, r.item.path) == chosen), None)
        if wanted is None:
            # First an external volume (what someone opening Hull usually means), else the first one.
            wanted = next((r for r in rows if r.kind == "volume" and r.item.drive.external), None) or \
                next((r for r in rows if r.kind == "volume"), None) or (rows[0] if rows else None)
        if wanted is not None:
            self.sidebar.select_row(wanted)
        self.show_chosen()

    def _row(self, kind, item, name, icon, section, indent):
        row = Gtk.ListBoxRow()
        row.kind, row.item, row.section = kind, item, section
        box = Gtk.Box(spacing=7)
        box.set_margin_start(indent)
        image = Gtk.Image.new_from_icon_name(icon + "-symbolic", Gtk.IconSize.MENU)
        image.get_style_context().add_class("hull-fact-label")
        box.pack_start(image, False, False, 0)
        label = Gtk.Label(label=name, xalign=0, ellipsize=Pango.EllipsizeMode.END)
        if kind == "drive":
            label.get_style_context().add_class("hull-drive-name")
        box.pack_start(label, True, True, 0)
        row.add(box)
        return row

    def _selected(self, _list, row):
        self.chosen = (row.kind, row.item.path) if row is not None else None
        self.show_chosen()

    def _current(self):
        row = self.sidebar.get_selected_row()
        return (row.kind, row.item) if row is not None else (None, None)

    # -- showing --

    def show_chosen(self):
        kind, item = self._current()
        if item is None:
            self.stack.set_visible_child_name("empty")
            self._update_buttons()
            return
        self.stack.set_visible_child_name("detail")
        for child in self.facts.get_children():
            self.facts.remove(child)
        if kind == "drive":
            self._show_drive(item)
        else:
            self._show_volume(item)
        self.facts.show_all()
        self._update_buttons()

    def _show_drive(self, drive):
        self.big_icon.set_from_icon_name(drive_icon(drive), Gtk.IconSize.DIALOG)
        self.big_icon.set_pixel_size(64)
        self.name_label.set_text(drive.name)
        image = getattr(drive, "image", None)
        where = "Disk image" if image else ("External" if drive.external else "Internal")
        what = "Disk Image" + (" (read-only)" if image and drive.read_only else "") if image else \
            " ".join(p for p in (drive.connection, where, "Physical Disk") if p)
        if drive.whole is not None and drive.whole.is_table:
            what += f" • {drive.scheme}"
        self.what_label.set_text(what)
        self.size_label.set_text(size_words(drive.size))
        count = len(drive.volumes)
        self.shared_label.set_text(f"{count} VOLUME{'S' if count != 1 else ''}")
        spaces = [s for s in (v.space() for v in drive.volumes) if s]
        used = sum(s[1] for s in spaces)
        self._show_space(used if drive.mounted else None, drive.size)
        self._note(drive)
        if image:
            self._fill_facts([
                ("Location:", where), ("Capacity:", size_words(drive.size)),
                ("Image:", image), ("Child count:", str(count)),
                ("Partition Map:", drive.scheme), ("Writable:", "No" if drive.read_only else "Yes"),
                ("Device:", drive.whole.device if drive.whole else "—"), ("Removable:", "Yes"),
            ])
            return
        self._fill_facts([
            ("Location:", where), ("Capacity:", size_words(drive.size)),
            ("Connection:", drive.connection or "—"), ("Child count:", str(count)),
            ("Partition Map:", drive.scheme), ("Type:", drive.medium or "Disk"),
            ("Device:", drive.whole.device if drive.whole else "—"),
            ("Removable:", "Yes" if drive.removable else "No"),
        ])

    def _show_volume(self, vol):
        drive = vol.drive
        self.big_icon.set_from_icon_name(volume_icon(vol), Gtk.IconSize.DIALOG)
        self.big_icon.set_pixel_size(64)
        self.name_label.set_text(vol.name)
        image = getattr(drive, "image", None)
        where = "Disk image" if image else ("External" if drive.external else "Internal")
        self.what_label.set_text(("Disk Image Volume" if image else
                                  " ".join(p for p in (drive.connection, where, "Physical Volume") if p))
                                 + f" • {vol.kind}")
        space = vol.space()
        self.size_label.set_text(size_words(space[0] if space else vol.size))
        self.shared_label.set_text("" if vol.mounts else "NOT MOUNTED")
        self._show_space(space[1] if space else None, space[0] if space else vol.size,
                         space[2] if space else None)
        self._note(vol)
        self._fill_facts([
            ("Mount Point:", vol.mount_point or "Not Mounted"), ("Type:", f"{where} Volume"),
            ("Capacity:", size_words(space[0] if space else vol.size)),
            ("Available:", size_words(space[2]) if space else "—"),
            ("Used:", size_words(space[1]) if space else "—"), ("Device:", vol.device),
            ("Format:", vol.kind), ("Connection:", drive.connection or "—"),
        ])

    def _show_space(self, used, total, free=None):
        known = used is not None and total
        self.bar.show_fraction(used / total if known else None)
        self.legend.set_visible(bool(known))
        if known:
            self.used_label.set_text(size_words(used))
            self.free_label.set_text(size_words(free if free is not None else max(0, total - used)))

    def _note(self, item):
        if item.system:
            text = "freemac is running from this disk, so it can't be changed while freemac is using it."
        elif getattr(item, "has_fs", True) is False and not item.fstype:
            text = "Nothing on this volume can be read. Erase it to use it."
        else:
            text = ""
        self.note.set_text(text)
        self.note.set_visible(bool(text))

    def _fill_facts(self, facts):
        for i, (label, value) in enumerate(facts):
            cell = Gtk.Box(spacing=8)
            cell.get_style_context().add_class("hull-fact")
            name = Gtk.Label(label=label, xalign=0)
            name.get_style_context().add_class("hull-fact-label")
            text = Gtk.Label(label=value, xalign=1, selectable=True, ellipsize=Pango.EllipsizeMode.MIDDLE)
            cell.pack_start(name, False, False, 0)
            cell.pack_end(text, True, True, 0)
            self.facts.attach(cell, i % 2, i // 2, 1, 1)

    def _update_buttons(self):
        kind, item = self._current()
        free = item is not None and not self.busy and not item.system
        vol = item if kind == "volume" else None
        drive = item if kind == "drive" else (vol.drive if vol else None)
        locked = bool(drive and getattr(drive, "read_only", False))
        can_mount = bool(vol and vol.has_fs)
        self.mount_button.set_sensitive(free and can_mount)
        self.mount_button.text.set_text("Unmount" if vol and vol.mounts else "Mount")
        self.mount_button.set_tooltip_text("Unmount" if vol and vol.mounts else "Mount")
        self.erase_button.set_sensitive(free and not locked and not (item and getattr(item, "optical", False))
                                        and not (vol and vol.drive.optical))
        self.info_button.set_sensitive(free and not locked and bool(vol and vol.has_fs))
        self.eject_button.set_sensitive(free and bool(drive and (drive.external or drive.ejectable)))
        for name, on in (("mount", self.mount_button), ("erase", self.erase_button),
                         ("rename", self.info_button), ("eject", self.eject_button)):
            action = self.lookup_action(name)
            if action:
                action.set_enabled(on.get_sensitive())

    # -- doing --

    def _working(self, on):
        self.busy = on
        (self.spinner.start if on else self.spinner.stop)()
        self._update_buttons()

    def _done(self, failure_title, icon):
        def finished(error):
            self._working(False)
            if error is not None:
                words = hull_store.Actions.words(error)
                if words:
                    alert.tell(self, failure_title, words, icon=icon)
            self.reload()
        return finished

    def _gicon(self, name):
        return Gio.ThemedIcon.new(name)

    def toggle_mount(self):
        kind, vol = self._current()
        if kind != "volume" or vol.system or self.busy:
            return
        self._working(True)
        if vol.mounts:
            self.actions.unmount(vol, self._done(f"“{vol.name}” wasn’t unmounted.", self._gicon(volume_icon(vol))))
        else:
            self.actions.mount(vol, self._done(f"“{vol.name}” couldn’t be mounted.", self._gicon(volume_icon(vol))))

    def eject(self):
        kind, item = self._current()
        drive = item if kind == "drive" else (item.drive if item else None)
        if drive is None or drive.system or self.busy:
            return
        self._working(True)
        self.actions.eject(drive, self._done(f"The disk “{drive.name}” wasn’t ejected.",
                                             self._gicon(drive_icon(drive))))

    def rename(self):
        kind, vol = self._current()
        if kind != "volume" or vol.system or not vol.has_fs or self.busy:
            return
        answer = ask_name_and_format(self, f"Rename “{vol.name}”", "", "Rename", vol.label or vol.name,
                                     False, self._gicon(volume_icon(vol)))
        if not answer or answer[0] == vol.label:
            return
        label = answer[0].upper() if vol.fstype == "vfat" else answer[0]
        self._working(True)
        self.actions.rename(vol, label, self._done(f"“{vol.name}” wasn’t renamed.", self._gicon(volume_icon(vol))))

    def erase(self):
        kind, item = self._current()
        if item is None or item.system or self.busy:
            return
        name = item.name
        whole = kind == "drive"
        text = (f"Erasing “{name}” will permanently delete everything on it, and can’t be undone. "
                "Give it a name and choose a format.")
        if whole and len(item.volumes) > 1:
            text = (f"Erasing “{name}” will permanently delete all {len(item.volumes)} volumes on it, "
                    "and can’t be undone. Give it a name and choose a format.")
        start = "Untitled" if whole else (item.label or "Untitled")
        icon = self._gicon(drive_icon(item) if whole else volume_icon(item))
        answer = ask_name_and_format(self, f"Erase “{name}”?", text, "Erase", start, True, icon)
        if not answer:
            return
        label, fstype = answer
        self._working(True)
        done = self._done(f"“{name}” wasn’t erased.", icon)
        if whole:
            self.chosen = ("drive", item.path)     # stay on the drive while its volumes change
            self.actions.erase_drive(item, fstype, label, done)
        else:
            self.actions.erase_volume(item, fstype, label, done)


    # -- disk images --

    def open_image(self):
        dialog = Gtk.FileChooserNative(title="Open Disk Image", transient_for=self,
                                       action=Gtk.FileChooserAction.OPEN, accept_label="Open")
        only = Gtk.FileFilter()
        only.set_name("Disk images (.iso, .img)")
        for suffix in disk_images.TYPES:
            only.add_pattern("*" + suffix)
        for mime in disk_images.MIME_TYPES:
            only.add_mime_type(mime)
        dialog.add_filter(only)
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            try:
                Gio.Subprocess.new(["freemac-hatch", dialog.get_filename()], Gio.SubprocessFlags.NONE)
            except GLib.Error as e:
                alert.tell(self, "The disk image couldn’t be opened.", e.message)

    def new_image(self):
        chooser = Gtk.FileChooserNative(title="Choose a Folder to Make an Image Of", transient_for=self,
                                        action=Gtk.FileChooserAction.SELECT_FOLDER, accept_label="Choose")
        chooser.set_current_folder(GLib.get_home_dir())
        if chooser.run() != Gtk.ResponseType.ACCEPT:
            return
        folder = chooser.get_filename()
        name = os.path.basename(folder.rstrip("/")) or "Untitled"
        saver = Gtk.FileChooserNative(title="Save Disk Image As", transient_for=self,
                                      action=Gtk.FileChooserAction.SAVE, accept_label="Save")
        saver.set_do_overwrite_confirmation(True)
        saver.set_current_folder(os.path.dirname(folder.rstrip("/")) or GLib.get_home_dir())
        saver.set_current_name(name + ".img")
        if saver.run() != Gtk.ResponseType.ACCEPT:
            return
        image = saver.get_filename()
        if not image.lower().endswith(disk_images.TYPES):
            image += ".img"
        if os.path.exists(image):
            try:
                os.unlink(image)      # the save dialog has asked to replace it
            except OSError as e:
                alert.tell(self, f"“{os.path.basename(image)}” couldn’t be replaced.", e.strerror or "")
                return
        self._working(True)

        def finished(why):
            self._working(False)
            if why is not None:
                alert.tell(self, f"The disk image of “{name}” couldn’t be made.", why,
                           icon=self._gicon("drive-removable-media"))
            else:
                answer = alert.ask(self, f"“{os.path.basename(image)}” is ready.",
                                   f"It holds a copy of “{name}”. Double-click it to open it as a disk.",
                                   [("Show in Drawer", Gtk.ResponseType.APPLY), ("Open", Gtk.ResponseType.OK)],
                                   default=Gtk.ResponseType.OK, icon=self._gicon("drive-removable-media"))
                if answer == Gtk.ResponseType.OK:
                    Gio.Subprocess.new(["freemac-hatch", image], Gio.SubprocessFlags.NONE)
                elif answer == Gtk.ResponseType.APPLY:
                    try:
                        Gio.AppInfo.launch_default_for_uri(
                            Gio.File.new_for_path(os.path.dirname(image)).get_uri(), None)
                    except GLib.Error:
                        pass
            return False

        def work():
            try:
                disk_images.make_from_folder(folder, image)
                why = None
            except disk_images.Failed as e:
                why = str(e) or "Something went wrong while it was being made."
            GLib.idle_add(finished, why)
        threading.Thread(target=work, daemon=True).start()


def menubar():
    return menus.menubar([
        ("_File", [[("Open Disk Image…", "win.open-image", "<Shift><Ctrl>o"),
                    ("New Image from Folder…", "win.new-image", "<Shift><Ctrl>n")],
                   [("Mount", "win.mount", None), ("Eject", "win.eject", "<Ctrl>e")],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Rename…", "win.rename", None), ("Erase…", "win.erase", "<Shift><Ctrl>e")]]),
    ])


class Hull(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.close", ["<Control>w"]), ("win.eject", ["<Control>e"]),
                             ("win.erase", ["<Shift><Control>e"]),
                             ("win.open-image", ["<Shift><Control>o"]), ("win.new-image", ["<Shift><Control>n"])):
            self.set_accels_for_action(action, keys)
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda *_: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-hull")
    return Hull().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
