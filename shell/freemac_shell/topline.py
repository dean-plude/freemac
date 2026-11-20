# SPDX-License-Identifier: GPL-3.0-or-later
"""Topline: freemac's menu bar along the top of the screen."""
import os
import signal
import subprocess
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gio, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import apps, beacon, quick, status, style  # noqa: E402
from .wfipc import Wayfire  # noqa: E402

MARK = "/usr/share/freemac/freemac-mark.svg"
HEIGHT = 28


def run(*cmd):
    subprocess.Popen(cmd, start_new_session=True)


class Topline(Gtk.Window):
    def __init__(self):
        super().__init__(title="Topline")
        style.make_transparent(self)
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_namespace(self, "freemac-topline")
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.auto_exclusive_zone_enable(self)
        self.set_size_request(-1, HEIGHT)

        bar = Gtk.Box(spacing=2)
        bar.get_style_context().add_class("topline")
        self.add(bar)

        # System menu behind the freemac mark.
        self.mark = Gtk.MenuButton()
        self.mark.set_image(self._mark_image())
        self.mark.set_popup(self._system_menu())
        bar.pack_start(self.mark, False, False, 4)

        # Focused application's name and menu.
        self.app_button = Gtk.MenuButton(label="freemac")
        self.app_button.get_style_context().add_class("app-name")
        self.app_menu = self._watch_menu(Gtk.Menu())
        self.app_button.set_popup(self.app_menu)
        bar.pack_start(self.app_button, False, False, 0)

        # The focused app's own menus (File, Edit, ...), when it publishes
        # them; Strata tells us where to find them.
        self.menus_box = Gtk.Box(spacing=0)
        self.menus_box.set_no_show_all(True)
        bar.pack_start(self.menus_box, False, False, 0)
        self._menu_key = None
        self._menubar = None
        self._app_model = None
        self._groups = {}
        self._bus = None
        self._own_actions = Gio.SimpleActionGroup()
        for name in ("hide", "quit"):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", lambda _a, _p, n=name: self._own_action(n))
            self._own_actions.add_action(action)

        self.window_button = Gtk.MenuButton(label="Window")
        self.window_menu = self._watch_menu(Gtk.Menu())
        self.window_button.set_popup(self.window_menu)
        bar.pack_start(self.window_button, False, False, 0)

        # The clock opens Beacon's notification centre.
        self.clock = Gtk.Label()
        clock_button = Gtk.Button()
        clock_button.add(self.clock)
        clock_button.get_style_context().add_class("clock")
        clock_button.set_tooltip_text("Notifications and calendar")
        clock_button.connect("clicked", lambda *_: beacon.call("ToggleCenter"))
        bar.pack_end(clock_button, False, False, 0)
        quick_settings = quick.QuickSettings()
        quick_settings.get_style_context().add_class("status")
        bar.pack_end(quick_settings, False, False, 0)
        self.dnd = Gtk.Image.new_from_icon_name("notifications-disabled-symbolic", Gtk.IconSize.MENU)
        self.dnd.set_tooltip_text("Do Not Disturb is on")
        self.dnd.set_no_show_all(True)
        bar.pack_end(self.dnd, False, False, 4)
        # Status icons sit just left of the clock; each hides itself when the
        # computer has nothing to show (no battery, no sound server).
        for indicator in (status.Battery(), status.Sound(), status.Network(), status.Bluetooth(),
                          status.Printing(), status.Recording()):
            indicator.get_style_context().add_class("status")
            bar.pack_end(indicator, False, False, 0)
        self._tick()
        self._prefs_monitor = style.watch_prefs(self._prefs_changed)
        self._prefs_changed()

        self.focused = None
        try:
            self.wf = Wayfire(on_event=lambda _e: self.refresh())
        except OSError:
            self.wf = None
        self.refresh()

    def _mark_image(self):
        image = Gtk.Image()
        try:
            from gi.repository import GdkPixbuf

            image.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_size(MARK, 18, 18))
        except GLib.Error:
            image.set_from_icon_name("start-here", Gtk.IconSize.MENU)
        return image

    def _item(self, menu, label, callback=None, sensitive=True):
        item = Gtk.MenuItem(label=label)
        item.set_sensitive(sensitive and callback is not None)
        if callback:
            item.connect("activate", lambda _i: callback())
        menu.append(item)
        return item

    def _system_menu(self):
        menu = Gtk.Menu()
        self._item(menu, "About freemac", self._about)
        self._item(menu, "Settings…", lambda: run("freemac-dials"))
        menu.append(Gtk.SeparatorMenuItem())
        self._item(menu, "Search…", lambda: run("freemac-seek"))
        self._item(menu, "Terminal", lambda: run("foot"))
        menu.append(Gtk.SeparatorMenuItem())
        self._item(menu, "Lock Screen", lambda: run("freemac-lock"))
        self._item(menu, "Restart…", lambda: run("systemctl", "reboot"))
        self._item(menu, "Shut Down…", lambda: run("systemctl", "poweroff"))
        self._item(menu, "Log Out", lambda: run("pkill", "-u", str(os.getuid()), "-x", "wayfire"))
        menu.show_all()
        return menu

    def _about(self):
        dialog = Gtk.AboutDialog(
            program_name="freemac",
            version=_os_version(),
            comments="A free desktop for your PC.",
            website="https://github.com/dean-plude/freemac",
            license_type=Gtk.License.GPL_3_0,
        )
        dialog.set_logo_icon_name("freemac-welcome")
        dialog.run()
        dialog.destroy()

    def _prefs_changed(self, *_args):
        self._show_time()
        self.dnd.set_visible(bool(style.prefs().get("dnd")))

    def _show_time(self, *_args):
        fmt = "%a %b %-d   %H:%M" if style.prefs().get("clock") == "24" else "%a %b %-d   %-I:%M %p"
        self.clock.set_text(time.strftime(fmt, time.localtime()))

    def _tick(self):
        self._show_time()
        GLib.timeout_add_seconds(60 - time.localtime().tm_sec, self._tick)
        return False

    def refresh(self):
        view = self.wf.focused() if self.wf else None
        # Opening one of our menus takes the focus from the app; keep showing
        # that app's menus until the menu closes.
        if view is None and self.focused is not None and self._menu_open():
            return
        self.focused = view
        self._fill_app_menus(view)
        app_id = view.get("app-id") if view else None
        self.app_button.set_label(apps.display_name(app_id, view.get("title", "") if view else "") if view else "freemac")
        self._fill_app_menu(view)
        self._fill_window_menu(view)

    def _clear(self, menu):
        for child in menu.get_children():
            menu.remove(child)

    def _menus(self):
        yield self.app_button.get_popup()
        yield self.window_menu
        for button in self.menus_box.get_children():
            yield button.get_popup()

    def _menu_open(self):
        return any(menu is not None and menu.get_visible() for menu in self._menus())

    def _watch_menu(self, menu):
        menu.connect("deactivate", lambda *_: GLib.idle_add(self._after_menu))
        return menu

    def _after_menu(self):
        self.refresh()
        return False

    # --- the app's own menus -------------------------------------------
    def _session_bus(self):
        if self._bus is None:
            self._bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        return self._bus

    def _fill_app_menus(self, view):
        info = self.wf.app_menus(view["id"]) if (self.wf and view) else None
        key = None
        if info:
            key = tuple(info.get(k) or "" for k in
                        ("bus-name", "menubar-path", "app-menu-path", "window-path", "application-path"))
        if key == self._menu_key:
            return
        self._menu_key = key
        self._menubar = None
        self._app_model = None
        for prefix in ("app", "win"):
            self.menus_box.insert_action_group(prefix, None)
        self._groups = {}
        if key:
            bus_name, menubar_path, app_menu_path, window_path, application_path = key
            try:
                conn = self._session_bus()
                for prefix, path in (("app", application_path), ("win", window_path)):
                    if path:
                        self._groups[prefix] = Gio.DBusActionGroup.get(conn, bus_name, path)
                        self.menus_box.insert_action_group(prefix, self._groups[prefix])
                if menubar_path:
                    self._menubar = Gio.DBusMenuModel.get(conn, bus_name, menubar_path)
                    self._menubar.connect("items-changed", lambda *_: self._build_menubar())
                if app_menu_path:
                    self._app_model = Gio.DBusMenuModel.get(conn, bus_name, app_menu_path)
                    self._app_model.connect("items-changed", lambda *_: self._fill_app_menu(self.focused))
            except GLib.Error:
                self._menubar = self._app_model = None
        self._build_menubar()

    def _top_level(self, model):
        """(label, submenu) for each menu of a menu bar model; items inside
        sections count as top-level too."""
        string = GLib.VariantType.new("s")
        for i in range(model.get_n_items()):
            section = model.get_item_link(i, Gio.MENU_LINK_SECTION)
            if section is not None:
                yield from self._top_level(section)
                continue
            submenu = model.get_item_link(i, Gio.MENU_LINK_SUBMENU)
            label = model.get_item_attribute_value(i, Gio.MENU_ATTRIBUTE_LABEL, string)
            if submenu is not None and label is not None:
                yield label.get_string(), submenu

    def _menu_from_model(self, model):
        menu = Gtk.Menu.new_from_model(model)
        for prefix, group in self._groups.items():
            menu.insert_action_group(prefix, group)
        menu.insert_action_group("topline", self._own_actions)
        return self._watch_menu(menu)

    def _build_menubar(self):
        for child in self.menus_box.get_children():
            self.menus_box.remove(child)
        # Asking for the items is also what makes the model load them; it
        # calls back (items-changed) once they've arrived.
        menus = list(self._top_level(self._menubar)) if self._menubar is not None else []
        for label, submenu in menus:
            button = Gtk.MenuButton(label=label, use_underline=True)
            button.set_popup(self._menu_from_model(submenu))
            self.menus_box.pack_start(button, False, False, 0)
            button.show_all()
        self.menus_box.set_visible(bool(menus))

    def _own_action(self, name):
        view = self.focused
        if not view or not self.wf:
            return
        if name == "hide":
            self.wf.set_minimized(view["id"], True)
        elif name == "quit" and view.get("pid"):
            os.kill(view["pid"], signal.SIGTERM)

    def _fill_app_menu(self, view):
        # An app with an old-style app menu: its items, then Hide and Quit.
        if view and self._app_model is not None and self._app_model.get_n_items():
            name = apps.display_name(view.get("app-id"))
            combined = Gio.Menu()
            combined.append_section(None, self._app_model)
            ours = Gio.Menu()
            ours.append(f"Hide {name}", "topline.hide")
            ours.append(f"Quit {name}", "topline.quit")
            combined.append_section(None, ours)
            self.app_button.set_popup(self._menu_from_model(combined))
            return
        if self.app_button.get_popup() is not self.app_menu:
            self.app_button.set_popup(self.app_menu)
        menu = self.app_menu
        self._clear(menu)
        if not view:
            self._item(menu, "About freemac", self._about)
        else:
            name = apps.display_name(view.get("app-id"))
            self._item(menu, f"Hide {name}", lambda: self.wf.set_minimized(view["id"], True))
            pid = view.get("pid")
            self._item(menu, f"Quit {name}", (lambda: os.kill(pid, signal.SIGTERM)) if pid else None)
        menu.show_all()

    def _fill_window_menu(self, view):
        menu = self.window_menu
        self._clear(menu)
        self._item(menu, "Minimize", (lambda: self.wf.set_minimized(view["id"], True)) if view else None)
        menu.append(Gtk.SeparatorMenuItem())
        if self.wf:
            for other in self.wf.views():
                vid = other["id"]
                title = other.get("title") or apps.display_name(other.get("app-id"))
                self._item(menu, title[:60], lambda vid=vid: self.wf.focus(vid))
        menu.show_all()


def _os_version():
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("VERSION="):
                    return line.split("=", 1)[1].strip().strip('"')
    except OSError:
        pass
    return ""


def main():
    style.apply()
    win = Topline()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()
