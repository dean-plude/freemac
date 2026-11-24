# SPDX-License-Identifier: GPL-3.0-or-later
"""Hatch opens a disk image you double-click (.iso or .img): its disk
appears on the Desktop and in Drawer's sidebar, and its window opens, the
way a Mac opens a disk image. Eject it like a USB drive when you're done.

There's nothing to see unless opening takes a moment, when a small window
says what's being opened. Opening the same image again just shows its window.

Original freemac code; the udisks2 side is in disk_images.
"""
import os
import sys
import threading

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import alert, disk_images, style  # noqa: E402

APP_ID = "org.freemac.Hatch"
SHOW_AFTER = 700        # milliseconds before the "Opening…" window appears


def image_icon(path):
    return "media-optical" if path.lower().endswith(".iso") else "drive-removable-media"


class Opening(Gtk.Window):
    def __init__(self, app, name, icon):
        super().__init__(application=app, title="Hatch", resizable=False)
        self.set_position(Gtk.WindowPosition.CENTER)
        box = Gtk.Box(spacing=14)
        box.set_margin_start(20)
        box.set_margin_end(20)
        box.set_margin_top(18)
        box.set_margin_bottom(18)
        image = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.DIALOG)
        image.set_pixel_size(48)
        box.pack_start(image, False, False, 0)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, valign=Gtk.Align.CENTER)
        label = Gtk.Label(label=f"Opening “{name}”…", xalign=0, max_width_chars=40, ellipsize=2)
        words.pack_start(label, False, False, 0)
        self.bar = Gtk.ProgressBar()
        self.bar.set_size_request(300, -1)
        words.pack_start(self.bar, False, False, 0)
        box.pack_start(words, True, True, 0)
        self.add(box)
        self.connect("delete-event", lambda *_: True)     # it closes itself when done
        self.timer = GLib.timeout_add(100, lambda: self.bar.pulse() or True)
        self.connect("destroy", lambda *_: GLib.source_remove(self.timer))


class Hatch(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()

    def do_activate(self):
        # Opened on its own, from Seek or Marina: choose an image.
        dialog = Gtk.FileChooserNative(title="Open Disk Image", action=Gtk.FileChooserAction.OPEN,
                                       accept_label="Open")
        only = Gtk.FileFilter()
        only.set_name("Disk images (.iso, .img)")
        for suffix in disk_images.TYPES:
            only.add_pattern("*" + suffix)
        for mime in disk_images.MIME_TYPES:
            only.add_mime_type(mime)
        dialog.add_filter(only)
        downloads = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD)
        if downloads and os.path.isdir(downloads):
            dialog.set_current_folder(downloads)
        self.hold()
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            self.open_image(dialog.get_filename())
        self.release()

    def do_open(self, files, _n, _hint):
        for file in files:
            path = file.get_path()
            if path:
                self.open_image(path)

    def open_image(self, path):
        name = os.path.basename(path)
        self.hold()
        state = {"window": None, "done": False}

        def show_window():
            if not state["done"]:
                state["window"] = Opening(self, name, image_icon(path))
                state["window"].show_all()
            return False

        def finished(places, why):
            state["done"] = True
            if state["window"] is not None:
                state["window"].destroy()
            if places:
                for place in places:
                    try:
                        Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(place).get_uri(), None)
                    except GLib.Error as e:
                        print("hatch:", place, e.message, file=sys.stderr)
            elif why is not None:
                alert.tell(None, f"“{name}” couldn’t be opened.", why, icon=Gio.ThemedIcon.new(image_icon(path)))
            self.release()
            return False

        def work():
            try:
                places, why = disk_images.open_image(path), None
            except disk_images.Failed as e:
                places, why = None, (str(e) or None)
            except GLib.Error as e:
                places, why = None, e.message
            GLib.idle_add(finished, places, why)

        GLib.timeout_add(SHOW_AFTER, show_window)
        threading.Thread(target=work, daemon=True).start()


def main():
    GLib.set_prgname("freemac-hatch")
    return Hatch().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
