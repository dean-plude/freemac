# SPDX-License-Identifier: GPL-3.0-or-later
"""Force Quit: end an app that has stopped answering (Option+Command+Escape).

Lists the apps with windows open, by name and icon. Force Quit asks once,
then Strata ends the program behind the app's windows at once; anything
unsaved in it is lost. Original freemac code.
"""
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import alert, apps, style  # noqa: E402
from .wfipc import Wayfire  # noqa: E402

APP_ID = "org.freemac.ForceQuit"
# Its own window (GTK names it after the program) stays off the list.
OWN_IDS = {APP_ID.lower(), "freemac-force-quit"}
ICON = 32


def running_apps(wf):
    """[(app_id, name, icon, [view ids])], by name, without freemac's own bar,
    Dock and this window."""
    found = {}
    for view in wf.views():
        app_id = view.get("app-id") or ""
        if not app_id or app_id.lower() in OWN_IDS:
            continue
        found.setdefault(app_id, []).append(view["id"])
    out = [(app_id, apps.display_name(app_id), apps.icon_for(app_id), ids) for app_id, ids in found.items()]
    return sorted(out, key=lambda a: a[1].lower())


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Force Quit Applications")
        self.set_default_size(380, 420)
        self.set_resizable(False)
        self.wf = Wayfire()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=18)
        hint = Gtk.Label(label="If an app doesn't respond for a while, select its name and click Force Quit.",
                         xalign=0, wrap=True, max_width_chars=44)
        box.pack_start(hint, False, False, 0)
        frame = Gtk.Frame()
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
        self.list.connect("row-selected", lambda *_: self._update_button())
        self.list.connect("row-activated", lambda *_: self._ask())
        scroll.add(self.list)
        frame.add(scroll)
        box.pack_start(frame, True, True, 0)
        buttons = Gtk.Box(spacing=8)
        self.button = Gtk.Button(label="Force Quit")
        self.button.get_style_context().add_class("suggested-action")
        self.button.connect("clicked", lambda *_: self._ask())
        buttons.pack_end(self.button, False, False, 0)
        box.pack_start(buttons, False, False, 0)
        self.add(box)
        box.show_all()
        self.refill()
        # Apps come and go while it's open; keep the list current.
        self._timer = GLib.timeout_add_seconds(2, self._tick)
        self.connect("destroy", lambda *_: GLib.source_remove(self._timer))

    def _tick(self):
        now = [a[0] for a in running_apps(self.wf)]
        if now != [row.app[0] for row in self.list.get_children()]:
            self.refill()
        return True

    def refill(self):
        keep = self._selected()
        for row in self.list.get_children():
            self.list.remove(row)
        for app_id, name, icon, ids in running_apps(self.wf):
            row = Gtk.ListBoxRow()
            row.app = (app_id, name, ids)
            line = Gtk.Box(spacing=10, margin=6)
            image = Gtk.Image.new_from_gicon(icon, Gtk.IconSize.DND)
            image.set_pixel_size(ICON)
            line.pack_start(image, False, False, 0)
            line.pack_start(Gtk.Label(label=name, xalign=0), True, True, 0)
            row.add(line)
            self.list.add(row)
            if keep and keep[0] == app_id:
                self.list.select_row(row)
        self.list.show_all()
        if self.list.get_selected_row() is None and self.list.get_row_at_index(0):
            self.list.select_row(self.list.get_row_at_index(0))
        self._update_button()

    def _selected(self):
        row = self.list.get_selected_row()
        return row.app if row is not None else None

    def _update_button(self):
        self.button.set_sensitive(self._selected() is not None)

    def _ask(self):
        chosen = self._selected()
        if not chosen:
            return
        app_id, name, ids = chosen
        # The app's own icon, not a warning sign, as on a Mac.
        answer = alert.ask(self, f"Do you want to force {name} to quit?",
                           "You'll lose any changes you haven't saved.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Force Quit", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK, destructive=Gtk.ResponseType.OK,
                           icon=apps.icon_for(app_id))
        if answer == Gtk.ResponseType.OK:
            ended = set()
            for view_id in ids:
                reply = self.wf.force_quit(view_id)
                if isinstance(reply, dict) and reply.get("pid"):
                    ended.add(reply["pid"])
            # The windows go once the compositor sees the program gone.
            GLib.timeout_add(400, lambda: self.refill() or False)


class ForceQuit(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        close = Gio.SimpleAction.new("close", None)
        close.connect("activate", lambda *_: self.window and self.window.close())
        self.add_action(close)
        self.set_accels_for_action("app.close", ["<Control>w", "Escape"])

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
        else:
            self.window.refill()
        self.window.present()


def main():
    ForceQuit().run(sys.argv)


if __name__ == "__main__":
    main()
