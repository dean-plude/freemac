# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Storage, as on a Mac: a bar of what fills the disk, coloured by
kind (apps, documents, pictures, music, movies, downloads, the Trash, the
system), how much is available, and recommendations to free space: empty
the Trash, have it emptied of what's been there 30 days, and review the
biggest files. The measuring is storage.py's, done on a thread so the page
opens at once. Original freemac code."""
import threading
import time

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, GObject, Gtk  # noqa: E402

from . import drawer_settings, sounds, storage, transfer  # noqa: E402

BAR_HEIGHT = 20


def _rgba(colour):
    rgba = Gdk.RGBA()
    rgba.parse(colour)
    return rgba


def _launch(*cmd):
    try:
        Gio.Subprocess.new(list(cmd), Gio.SubprocessFlags.NONE)
    except GLib.Error:
        pass


class Bar(Gtk.DrawingArea):
    """The disk as one rounded bar: a stretch of colour for each kind, the
    rest left empty for what's available."""

    def __init__(self):
        super().__init__()
        self.set_size_request(-1, BAR_HEIGHT)
        self.parts = []
        self.connect("draw", self._draw)
        self.set_has_tooltip(True)
        self.connect("query-tooltip", self._tooltip)

    def show_parts(self, parts):
        self.parts = parts
        self.queue_draw()

    def _spans(self, width):
        x, spans = 0.0, []
        for key, fraction, size in self.parts:
            w = max(2.0, fraction * width) if size > 0 else 0
            spans.append((key, x, w, size))
            x += w
        return spans

    def _draw(self, widget, cr):
        width, height = widget.get_allocated_width(), widget.get_allocated_height()
        radius = min(6, height / 2)
        cr.new_sub_path()
        cr.arc(width - radius, radius, radius, -1.5708, 0)
        cr.arc(width - radius, height - radius, radius, 0, 1.5708)
        cr.arc(radius, height - radius, radius, 1.5708, 3.1416)
        cr.arc(radius, radius, radius, 3.1416, 4.7124)
        cr.close_path()
        cr.save()
        cr.clip_preserve()
        # The empty part, in a faint grey that suits light and dark alike.
        cr.set_source_rgba(0.5, 0.5, 0.5, 0.18)
        cr.fill()
        for key, x, w, _size in self._spans(width):
            Gdk.cairo_set_source_rgba(cr, _rgba(storage.COLOURS[key]))
            cr.rectangle(x, 0, w, height)
            cr.fill()
            # A thin gap between kinds, as on a Mac.
            cr.set_source_rgba(1, 1, 1, 0.6)
            cr.rectangle(x + w - 1, 0, 1, height)
            cr.fill()
        cr.restore()
        return False

    def _tooltip(self, widget, x, _y, _keyboard, tooltip):
        for key, left, w, size in self._spans(widget.get_allocated_width()):
            if left <= x < left + w:
                tooltip.set_text(f"{storage.TITLES[key]}: {storage.human(size)}")
                return True
        return False


def _dot(colour):
    dot = Gtk.DrawingArea()
    dot.set_size_request(10, 10)
    dot.set_valign(Gtk.Align.CENTER)

    def draw(widget, cr):
        Gdk.cairo_set_source_rgba(cr, _rgba(colour))
        cr.arc(5, 5, 5, 0, 6.2832)
        cr.fill()
        return False

    dot.connect("draw", draw)
    return dot


def ask_empty(parent, size):
    """Empty the Trash, asking first unless Drawer's settings say not to."""
    if drawer_settings.get("warn_empty_trash"):
        from . import alert
        answer = alert.ask(parent, "Are you sure you want to permanently erase the items in the Trash?",
                           f"That frees {storage.human(size)}. You can’t undo this action.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Empty Trash", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK, destructive=Gtk.ResponseType.OK,
                           icon="user-trash-full")
        if answer != Gtk.ResponseType.OK:
            return False
    transfer.empty_trash()
    sounds.effect("trash")
    return True


class ReviewFiles(Gtk.Dialog):
    """The biggest files in your home folder, to show in Drawer or move to
    the Trash: Review Files, as on a Mac."""

    def __init__(self, parent, changed):
        super().__init__(title="Large Files", transient_for=parent, modal=True)
        self.changed = changed
        self.set_default_size(620, 440)
        box = self.get_content_area()
        box.set_spacing(8)
        for side in ("top", "bottom", "start", "end"):
            getattr(box, "set_margin_" + side)(12)
        self.note = Gtk.Label(label="Looking for large files…", xalign=0, wrap=True)
        self.note.get_style_context().add_class("dials-caption")
        box.pack_start(self.note, False, False, 0)
        # path, name, size text, date text, size (for sorting), date (for sorting)
        self.store = Gtk.ListStore(str, str, str, str, GObject.TYPE_INT64, GObject.TYPE_DOUBLE)
        self.view = Gtk.TreeView(model=self.store, headers_visible=True)
        self.view.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE)
        for title, text, sort, expand in (("Name", 1, 1, True), ("Size", 2, 4, False),
                                          ("Last Modified", 3, 5, False)):
            cell = Gtk.CellRendererText()
            if text == 1:
                cell.set_property("ellipsize", 2)   # in the middle
            column = Gtk.TreeViewColumn(title, cell, text=text)
            column.set_sort_column_id(sort)
            column.set_expand(expand)
            column.set_resizable(True)
            self.view.append_column(column)
        self.view.set_tooltip_column(0)
        self.view.connect("row-activated", lambda *_: self._show())
        self.view.get_selection().connect("changed", lambda *_: self._chosen())
        scroll = Gtk.ScrolledWindow(vexpand=True)
        scroll.add(self.view)
        box.pack_start(scroll, True, True, 0)
        buttons = Gtk.Box(spacing=6)
        self.show_button = Gtk.Button(label="Show in Drawer")
        self.show_button.connect("clicked", lambda *_: self._show())
        self.trash_button = Gtk.Button(label="Move to Trash")
        self.trash_button.connect("clicked", lambda *_: self._trash())
        done = Gtk.Button(label="Done")
        done.get_style_context().add_class("suggested-action")
        done.connect("clicked", lambda *_: self.destroy())
        buttons.pack_start(self.show_button, False, False, 0)
        buttons.pack_start(self.trash_button, False, False, 0)
        buttons.pack_end(done, False, False, 0)
        box.pack_start(buttons, False, False, 0)
        self._chosen()
        threading.Thread(target=self._find, daemon=True).start()

    def _find(self):
        found = storage.large_files()
        GLib.idle_add(self._fill, found)

    def _fill(self, found):
        self.found = found
        self.store.clear()
        home = storage.HOME
        for size, modified, path in found:
            shown = path[len(home) + 1:] if path.startswith(home + "/") else path
            self.store.append([path, shown, storage.human(size),
                               time.strftime("%-d %b %Y", time.localtime(modified)), size, modified])
        if found:
            total = sum(size for size, _m, _p in found)
            self.note.set_label(f"{len(found)} files of {storage.human(storage.LARGE)} or more, "
                                f"{storage.human(total)} in all. Choose one to show it in Drawer, "
                                "or move the ones you don't need to the Trash.")
        else:
            self.note.set_label(f"No files of {storage.human(storage.LARGE)} or more in your home folder.")
        return False

    def _paths(self):
        model, rows = self.view.get_selection().get_selected_rows()
        return [model[r][0] for r in rows]

    def _chosen(self):
        some = bool(self._paths())
        self.show_button.set_sensitive(some)
        self.trash_button.set_sensitive(some)

    def _show(self):
        paths = self._paths()
        if paths:
            _launch("freemac-drawer", paths[0])

    def _trash(self):
        paths = self._paths()
        went, _error = transfer.to_trash(paths)
        if went:
            sounds.effect("trash")
        # Nothing chosen afterwards, so a second click can't move the next one.
        self.view.get_selection().unselect_all()
        self._fill([f for f in self.found if f[2] not in went])
        self.changed()


def storage_page(window):
    group, row, page, _slider, switch = window.helpers

    # The disk: its name, what's used, the bar and its key.
    title = Gtk.Label(label="This Computer", xalign=0)
    title.get_style_context().add_class("dials-section")
    used = Gtk.Label(label="Calculating…", xalign=0)
    available = Gtk.Label(label="", xalign=1)
    available.get_style_context().add_class("dials-caption")
    top = Gtk.Box(spacing=8)
    top.pack_start(used, True, True, 0)
    top.pack_end(available, False, False, 0)
    bar = Bar()
    key = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=8,
                      column_spacing=14, row_spacing=4, homogeneous=False)
    key.get_style_context().add_class("storage-key")
    for name, label, colour, _folders in storage.CATEGORIES:
        item = Gtk.Box(spacing=5)
        item.pack_start(_dot(colour), False, False, 0)
        text = Gtk.Label(label=label)
        text.get_style_context().add_class("dials-caption")
        item.pack_start(text, False, False, 0)
        key.add(item)
    disk_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    for side in ("top", "bottom", "start", "end"):
        getattr(disk_box, "set_margin_" + side)(4)
    disk_box.pack_start(top, False, False, 0)
    disk_box.pack_start(bar, False, False, 0)
    disk_box.pack_start(key, False, False, 0)
    disk_row = Gtk.ListBoxRow(activatable=False)
    disk_row.add(disk_box)

    # Recommendations.
    empty_button = Gtk.Button(label="Empty Trash…")
    empty_row = row("Empty Trash", empty_button, "The Trash holds nothing.")
    review_button = Gtk.Button(label="Review Files…")
    auto = switch(drawer_settings.get("trash_after_30_days"),
                  lambda on: drawer_settings.put("trash_after_30_days", on))
    recommendations = group(
        row("Empty Trash Automatically", auto,
            "Save space by erasing items that have been in the Trash for more than 30 days."),
        empty_row,
        row("Review Files", review_button,
            "See the biggest files in your home folder and move the ones you don't need to the Trash."),
    )
    rec_heading = Gtk.Label(label="Recommendations", xalign=0)
    rec_heading.get_style_context().add_class("dials-section")

    # Each kind, with its size and a way to look at it.
    kinds = group()
    sizes = {}
    for name, label, colour, folders in storage.CATEGORIES:
        line = Gtk.Box(spacing=10)
        line.pack_start(_dot(colour), False, False, 0)
        line.pack_start(Gtk.Label(label=label, xalign=0), True, True, 0)
        size = Gtk.Label(label="—")
        size.get_style_context().add_class("dials-caption")
        sizes[name] = size
        target = None
        if folders:
            target = ("freemac-drawer", f"{storage.HOME}/{folders[0]}")
        elif name == "trash":
            target = ("freemac-drawer", f"{storage.TRASH}/files")
        elif name == "apps":
            target = ("freemac-harbor",)
        if target:
            show = Gtk.Button(label="Show" if name != "apps" else "Manage…")
            show.set_relief(Gtk.ReliefStyle.NONE)
            show.connect("clicked", lambda *_, t=target: _launch(*t))
            line.pack_end(show, False, False, 0)
        line.pack_end(size, False, False, 0)
        item = Gtk.ListBoxRow(activatable=False)
        item.add(line)
        kinds.add(item)
    kinds_heading = Gtk.Label(label="What's Using Space", xalign=0)
    kinds_heading.get_style_context().add_class("dials-section")

    state = {"busy": False, "again": False}

    def measured(result):
        state["busy"] = False
        sizes_now = result["sizes"]
        used.set_markup(f"<b>{storage.human(result['used'])}</b> used of {storage.human(result['total'])}")
        available.set_label(f"{storage.human(result['free'])} available")
        total = result["total"] or 1
        bar.show_parts([(k, sizes_now.get(k, 0) / total, sizes_now.get(k, 0))
                        for k, _t, _c, _f in storage.CATEGORIES])
        for name, label in sizes.items():
            label.set_label(storage.human(sizes_now.get(name, 0)))
        trash = sizes_now.get("trash", 0)
        empty_button.set_sensitive(trash > 0)
        empty_button.trash = trash
        caption = empty_row.get_child().get_children()[0].get_children()[-1]
        caption.set_label(f"The Trash holds {storage.human(trash)}." if trash else "The Trash is empty.")
        if state["again"]:
            state["again"] = False
            refresh()
        return False

    def refresh(*_args):
        if state["busy"]:
            state["again"] = True
            return
        state["busy"] = True
        threading.Thread(target=lambda: GLib.idle_add(measured, storage.measure()), daemon=True).start()

    def empty(*_args):
        if ask_empty(window, getattr(empty_button, "trash", 0)):
            refresh()

    empty_button.connect("clicked", empty)
    review_button.connect("clicked", lambda *_: ReviewFiles(window, refresh).show_all())
    refresh()
    content = page("Storage", title, group(disk_row), rec_heading, recommendations, kinds_heading, kinds)
    # Measure again when the page is shown, since files come and go.
    content.connect("map", lambda *_: refresh())
    return content
