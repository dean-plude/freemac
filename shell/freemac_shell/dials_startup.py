# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Startup Disk, as on a Mac: the systems this computer can start up
from, each as a disk you click, with Restart in it once, or Always Start Up
from it. startup_disk.py reads them; /usr/libexec/freemac-startup-disk
changes them as root, after an administrator's password.

Original freemac code.
"""
import os

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import alert, startup_disk  # noqa: E402

HELPER = "/usr/libexec/freemac-startup-disk"
MENU_KEYS = ("Most PCs also show their own start-up menu if you hold a key as they start: often F12, F11, F10, "
             "F9, F8 or Esc, depending on the maker.")

CSS = b"""
.startup-disks { background: transparent; }
.startup-disks flowboxchild { padding: 10px 8px; border-radius: 10px; background: transparent; }
.startup-disks flowboxchild:selected { background: alpha(@theme_selected_bg_color, 0.18); }
.startup-disks flowboxchild:selected label { color: @theme_fg_color; }
.startup-disks .dials-caption { font-size: 0.85em; }
"""
_css_done = False


def install_css():
    global _css_done
    if _css_done:
        return
    from gi.repository import Gdk
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                             Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    _css_done = True


def caption(text):
    label = Gtk.Label(label=text, xalign=0, wrap=True, max_width_chars=60)
    label.get_style_context().add_class("dials-caption")
    return label


def run_helper(window, args, done):
    """The helper through pkexec, without freezing Dials. done() is called
    afterwards, whether or not anything changed."""
    if not os.path.exists(HELPER):
        alert.tell(window, "The start-up disk can't be changed here",
                   "This copy of freemac doesn't have the helper that changes it.")
        done()
        return
    flags = Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
    try:
        proc = Gio.Subprocess.new(["pkexec", HELPER, *args], flags)
    except GLib.Error as e:
        alert.tell(window, "The start-up disk wasn't changed", e.message)
        done()
        return

    def finished(p, result):
        err = ""
        try:
            _ok, _out, err = p.communicate_utf8_finish(result)
        except GLib.Error as e:
            err = e.message
        code = p.get_exit_status() if p.get_if_exited() else 1
        if code in (126, 127):
            alert.tell(window, "The start-up disk wasn't changed",
                       "The administrator's password wasn't given, so nothing changed.")
        elif code:
            alert.tell(window, "The start-up disk wasn't changed", (err or "").strip())
        done()

    proc.communicate_utf8_async(None, None, finished)


class StartupDisk:
    def __init__(self, window):
        self.window = window
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        self.chosen = None
        install_css()
        self.fill()

    def fill(self):
        for child in self.box.get_children():
            child.destroy()
        entries = startup_disk.read()
        if entries is None:
            self.box.pack_start(caption(
                "This computer starts up the older way (BIOS), so the disk it starts up from is chosen in its "
                "own firmware settings. " + MENU_KEYS), False, False, 0)
            self.box.show_all()
            return
        if not entries:
            self.box.pack_start(caption("The firmware doesn't list any disk to start up from. " + MENU_KEYS),
                                False, False, 0)
            self.box.show_all()
            return
        self.entries = {e["num"]: e for e in entries}
        if self.chosen not in self.entries:
            self.chosen = next((e["num"] for e in entries if e["default"]), entries[0]["num"])
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.SINGLE, homogeneous=True, max_children_per_line=5,
                           min_children_per_line=2, column_spacing=8, row_spacing=8,
                           activate_on_single_click=True)
        for entry in entries:
            tile = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            icon = startup_disk.icon(entry)
            if not Gtk.IconTheme.get_default().has_icon(icon):
                icon = startup_disk.FALLBACK.get(icon, "drive-harddisk")
            image = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.DIALOG)
            image.set_pixel_size(64)
            tile.pack_start(image, False, False, 0)
            name = Gtk.Label(label=entry["title"], ellipsize=3, max_width_chars=16)
            tile.pack_start(name, False, False, 0)
            notes = []
            if entry["current"]:
                notes.append("In use now")
            if entry["once"]:
                notes.append("Next start-up")
            elif entry["default"]:
                notes.append("Starts up")
            note = caption(", ".join(notes) or " ")
            note.set_xalign(0.5)
            tile.pack_start(note, False, False, 0)
            child = Gtk.FlowBoxChild()
            child.num = entry["num"]
            child.add(tile)
            flow.add(child)
            if entry["num"] == self.chosen:
                flow.select_child(child)
        flow.get_style_context().add_class("startup-disks")
        flow.connect("child-activated", self.picked)
        frame = Gtk.Frame()
        frame.get_style_context().add_class("dials-group")
        flow.set_margin_top(8)
        flow.set_margin_bottom(8)
        flow.set_margin_start(8)
        flow.set_margin_end(8)
        frame.add(flow)
        self.box.pack_start(frame, False, False, 0)

        chosen = self.entries[self.chosen]
        current = next((e for e in entries if e["current"]), None)
        default = next(e for e in entries if e["default"])
        once = next((e for e in entries if e["once"]), None)
        lines = []
        if current:
            lines.append(f"You're using freemac, started from {current['title']}.")
        lines.append(f"Your computer starts up from {default['title']}.")
        if once:
            lines.append(f"Next time only, it will start up from {once['title']}.")
        self.box.pack_start(caption(" ".join(lines)), False, False, 0)

        buttons = Gtk.Box(spacing=8)
        restart = Gtk.Button(label=f"Restart in {chosen['title']}…")
        restart.get_style_context().add_class("suggested-action")
        restart.connect("clicked", lambda *_: self.restart_once(chosen))
        buttons.pack_start(restart, False, False, 0)
        always = Gtk.Button(label="Always Start Up from This")
        always.set_sensitive(not chosen["default"])
        always.connect("clicked", lambda *_: self.always(chosen))
        buttons.pack_start(always, False, False, 0)
        if once:
            forget = Gtk.Button(label="Cancel Next Start-up")
            forget.connect("clicked", lambda *_: self.change("cancel-once"))
            buttons.pack_start(forget, False, False, 0)
        self.box.pack_start(buttons, False, False, 0)
        self.box.pack_start(caption(
            "Restart in a disk to start up from it just once; after that the computer goes back to the one it "
            "always starts up from. " + MENU_KEYS), False, False, 0)
        self.box.show_all()

    def change(self, *args):
        """Asking for the password and the firmware's change take a few
        seconds; the page waits, greyed, and then shows what's set now."""
        self.box.set_sensitive(False)

        def done():
            self.box.set_sensitive(True)
            self.fill()

        run_helper(self.window, list(args), done)

    def picked(self, _flow, child):
        if child.num != self.chosen:
            self.chosen = child.num
            GLib.idle_add(lambda: self.fill() and False)

    def restart_once(self, entry):
        if entry["current"] and not any(e["once"] for e in self.entries.values()):
            text = "The computer restarts and starts up from the same disk again."
        else:
            text = (f"The computer restarts in {entry['title']}, just this once. After that it starts up from "
                    f"{next(e for e in self.entries.values() if e['default'])['title']} again. "
                    "Save your work first: open apps are closed.")
        answer = alert.ask(self.window, f"Restart in {entry['title']}?", text,
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Restart", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK)
        if answer == Gtk.ResponseType.OK:
            self.change("once", entry["num"])

    def always(self, entry):
        text = f"Your computer will start up from {entry['title']} from now on."
        if entry["kind"] != "freemac":
            text += (" To come back to freemac, hold the key for your PC's start-up menu as it starts, or choose "
                     "freemac in that system's own settings.")
        answer = alert.ask(self.window, f"Always start up from {entry['title']}?", text,
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Always", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK)
        if answer == Gtk.ResponseType.OK:
            self.change("always", entry["num"])


def startup_disk_page(window):
    _group, _row, page, _slider, _switch = window.helpers
    panel = StartupDisk(window)
    return page("Startup Disk", panel.box)
