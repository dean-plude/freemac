# SPDX-License-Identifier: GPL-3.0-or-later
"""Quick Note, as on a Mac: a small note that opens over whatever you're
doing, from a hot corner (the bottom right, unless you choose another),
from Jot's File menu or with freemac-jot --quick.

A quick note is an ordinary Jot note kept in ~/Documents/Notes/Quick Notes,
so Jot lists it with the others. Quick Note opens the note you had last
(File > Always Resume to Last Quick Note in Jot); with that off, it opens
the last one only if you closed it within five minutes, and otherwise a new
one. The window floats above the others
in the bottom right of the screen, put there through Wayfire
(window-rules/configure-view, wm-actions/set-always-on-top), and can be
dragged anywhere. Original freemac code.
"""
import json
import os
import time

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk, Pango  # noqa: E402

from . import spelling, wfipc  # noqa: E402

FOLDER_NAME = "Quick Notes"
PREFS = os.path.expanduser("~/.config/freemac/jot.json")
RESUME_WITHIN = 5 * 60      # seconds: a note closed this recently is opened again
WIDTH, HEIGHT = 340, 300
MARGIN = 24
APP_IDS = ("org.freemac.Jot", "freemac-jot")
SAVE_DELAY = 800


def folder(notes_dir):
    return os.path.join(notes_dir, FOLDER_NAME)


def prefs():
    try:
        with open(PREFS, encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write_prefs(**changes):
    data = prefs()
    data.update(changes)
    os.makedirs(os.path.dirname(PREFS), exist_ok=True)
    temporary = PREFS + ".new"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
    os.replace(temporary, PREFS)


def always_resume():
    return bool(prefs().get("quick_resume", True))


def note_to_open(quick_folder, now=None, settings=None):
    """The quick note to open: the last one if it still exists and Always
    Resume is on or it was left a moment ago; otherwise None for a new one."""
    settings = prefs() if settings is None else settings
    last = settings.get("quick_last")
    if not isinstance(last, str) or os.path.dirname(last) != quick_folder or not os.path.isfile(last):
        return None
    if settings.get("quick_resume", True):
        return last
    left = settings.get("quick_left", 0)
    now = time.time() if now is None else now
    return last if isinstance(left, (int, float)) and now - left < RESUME_WITHIN else None


def corner(area, width=WIDTH, height=HEIGHT, margin=MARGIN):
    x, y, area_w, area_h = area
    return x + area_w - width - margin, y + area_h - height - margin


class QuickNote(Gtk.ApplicationWindow):
    """The floating note. `jot` is Jot's module, for its file naming."""

    def __init__(self, app, jot, open_in_jot):
        super().__init__(application=app, title="Quick Note")
        self.jot = jot
        self.open_in_jot = open_in_jot
        self.folder = folder(jot.notes_dir())
        os.makedirs(self.folder, exist_ok=True)
        self.path = None
        self.save_timer = None
        self.set_default_size(WIDTH, HEIGHT)
        self.set_icon_name("freemac-jot")
        self.set_keep_above(True)

        header = Gtk.HeaderBar(title="Quick Note", show_close_button=True)
        new = Gtk.Button.new_from_icon_name("document-new-symbolic", Gtk.IconSize.BUTTON)
        new.set_tooltip_text("New Quick Note")
        new.connect("clicked", lambda _b: self.start(None))
        header.pack_end(new)
        jot_button = Gtk.Button.new_from_icon_name("freemac-jot", Gtk.IconSize.BUTTON)
        jot_button.set_tooltip_text("Open in Jot")
        jot_button.connect("clicked", lambda _b: self.to_jot())
        header.pack_end(jot_button)
        self.set_titlebar(header)

        self.view = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=14, right_margin=14,
                                 top_margin=12, bottom_margin=12, pixels_below_lines=2)
        spelling.attach(self.view)
        self.view.get_style_context().add_class("jot-page")
        self.buffer = self.view.get_buffer()
        self.title_tag = self.buffer.create_tag("title", weight=Pango.Weight.BOLD, scale=1.25,
                                                pixels_below_lines=4)
        self.changed = self.buffer.connect("changed", self._changed)
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.view)
        self.add(scroll)
        self.connect("delete-event", self._closing)
        self.connect("key-press-event", self._key)

    # -- which note ------------------------------------------------------------
    def start(self, path):
        """Show `path`, or a new empty quick note when it is None."""
        self.save_now()
        self.path = path
        with self.buffer.handler_block(self.changed):
            self.buffer.set_text(self.jot.read(path) if path else "")
            self._style_title()
            self.buffer.place_cursor(self.buffer.get_end_iter())
        write_prefs(quick_last=path)
        self.view.grab_focus()

    def show_up(self):
        self.show_all()
        self.present()
        self.float_tries = 0
        GLib.timeout_add(120, self._float)

    # -- saving ----------------------------------------------------------------
    def _style_title(self):
        start, end = self.buffer.get_bounds()
        self.buffer.remove_tag(self.title_tag, start, end)
        line_end = self.buffer.get_start_iter()
        if not line_end.ends_line():
            line_end.forward_to_line_end()
        self.buffer.apply_tag(self.title_tag, self.buffer.get_start_iter(), line_end)

    def _changed(self, _buffer):
        self._style_title()
        if self.save_timer:
            GLib.source_remove(self.save_timer)
        self.save_timer = GLib.timeout_add(SAVE_DELAY, self.save_now)

    def text(self):
        return self.buffer.get_text(self.buffer.get_start_iter(), self.buffer.get_end_iter(), True)

    def save_now(self):
        if not self.save_timer:
            return False
        GLib.source_remove(self.save_timer)
        self.save_timer = None
        text = self.text()
        if self.path is None:
            if not text.strip():
                return False      # nothing typed yet: no file
            self.path = self.jot.file_name_for(text, self.folder)
        else:
            # The file follows the title, as Jot's notes do.
            wanted = self.jot.file_name_for(text, self.folder, current=self.path)
            if wanted != self.path and os.path.exists(self.path):
                try:
                    os.rename(self.path, wanted)
                    self.path = wanted
                except OSError:
                    pass
        temporary = os.path.join(self.folder, "." + os.path.basename(self.path) + ".tmp")
        with open(temporary, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(temporary, self.path)
        write_prefs(quick_last=self.path)
        return False

    def to_jot(self):
        self.save_now()
        path = self.path
        self.close()
        self.open_in_jot(path)

    def _closing(self, *_args):
        self.save_now()
        write_prefs(quick_left=time.time())
        return False

    def _key(self, _widget, event):
        from gi.repository import Gdk
        if event.keyval == Gdk.KEY_Escape or (
                event.state & Gdk.ModifierType.CONTROL_MASK and Gdk.keyval_to_lower(event.keyval) == Gdk.KEY_w):
            self.close()
            return True
        return False

    # -- floating in the corner ------------------------------------------------
    def _float(self):
        try:
            wf = wfipc.Wayfire()
        except (ConnectionError, OSError):
            return False
        try:
            return self._place(wf)
        finally:
            try:
                wf.req.sock.close()
            except (AttributeError, OSError):
                pass

    def _place(self, wf):
        def call(method, **data):
            try:
                return wf.req.call(method, **data)
            except (ConnectionError, OSError, ValueError, AttributeError):
                return None

        views = call("window-rules/list-views")
        mine = [v for v in views if isinstance(v, dict) and v.get("app-id") in APP_IDS
                and v.get("title") == "Quick Note"] if isinstance(views, list) else []
        if not mine:
            # Not mapped yet: try again for a second or so.
            self.float_tries += 1
            return self.float_tries < 12
        view = mine[0]
        area = (0, 0, 1280, 800)
        outputs = call("window-rules/list-outputs")
        for output in outputs if isinstance(outputs, list) else []:
            work = output.get("workarea") if isinstance(output, dict) else None
            if isinstance(work, dict) and output.get("id") in (view.get("output-id"), view.get("output")):
                area = (work.get("x", 0), work.get("y", 0), work.get("width", 1280), work.get("height", 800))
                break
        x, y = corner(area)
        call("window-rules/configure-view", id=view["id"],
             geometry={"x": int(x), "y": int(y), "width": WIDTH, "height": HEIGHT})
        call("wm-actions/set-always-on-top", view_id=view["id"], state=True)
        return False
