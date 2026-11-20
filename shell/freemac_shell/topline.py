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

from . import apps, beacon, mac_accel, quick, status, style  # noqa: E402
from .wfipc import Wayfire, is_minimized  # noqa: E402

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
        self.mark.set_popup(self._watch_menu(self._system_menu()))
        bar.pack_start(self.mark, False, False, 4)
        self._slide(self.mark)

        # Focused application's name and menu.
        self.app_button = Gtk.MenuButton(label="freemac")
        self.app_button.get_style_context().add_class("app-name")
        self.app_menu = self._watch_menu(Gtk.Menu())
        self.app_button.set_popup(self.app_menu)
        bar.pack_start(self.app_button, False, False, 0)
        self._slide(self.app_button)

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
        for name in ("hide", "hide-others", "show-all", "quit"):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", lambda _a, _p, n=name: self._own_action(n))
            self._own_actions.add_action(action)

        self.window_button = Gtk.MenuButton(label="Window")
        self.window_menu = self._watch_menu(Gtk.Menu())
        self.window_button.set_popup(self.window_menu)
        bar.pack_start(self.window_button, False, False, 0)
        self._slide(self.window_button)

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

    def _item(self, menu, label, callback=None, sensitive=True, shortcut="", check=None):
        """A menu item; shortcut is shown on the right in Mac symbols (it's
        only a reminder: the keys themselves are Strata's). check True or
        False puts a plain tick, or the room for one, before the name."""
        item = Gtk.MenuItem()
        if shortcut or check is not None:
            box = Gtk.Box(spacing=24 if shortcut else 0)
            if check is not None:
                tick = Gtk.Label(label="\u2713" if check else "", xalign=0)
                tick.set_size_request(18, -1)
                box.pack_start(tick, False, False, 0)
            box.pack_start(Gtk.Label(label=label, xalign=0), True, True, 0)
            keys = Gtk.Label(label=shortcut, xalign=1)
            keys.get_style_context().add_class("dim-label")
            box.pack_end(keys, False, False, 0)
            item.add(box)
        else:
            item.set_label(label)
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
        self._item(menu, "Force Quit\u2026", lambda: run("freemac-force-quit"), shortcut="\u2325\u2318\u238b")
        menu.append(Gtk.SeparatorMenuItem())
        self._item(menu, "Lock Screen", lambda: run("freemac-lock"), shortcut="\u2303\u2318Q")
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

    def _menu_buttons(self):
        yield self.mark
        yield self.app_button
        yield from self.menus_box.get_children()
        yield self.window_button

    def _slide(self, button):
        """As on a Mac, once one menu is open, moving the pointer onto
        another title in the bar opens that menu instead, with no click."""
        button.connect("enter-notify-event", self._slide_to)
        button.connect("toggled", self._menu_toggled)
        return button

    def _menu_toggled(self, button):
        """The first click on a title right after Esc closed a menu opens the
        new menu and has it shut again at once (the compositor turns down
        its grab). A menu that closes that fast, untouched, opens again."""
        now = time.monotonic()
        if button.get_active():
            if now - getattr(button, "_fm_opened", 0) > 1:
                button._fm_retried = False
            button._fm_opened = now
            return
        if (now - getattr(button, "_fm_opened", 0) < 0.3 and not getattr(button, "_fm_retried", True)
                and not any(other.get_active() for other in self._menu_buttons())):
            button._fm_retried = True
            GLib.timeout_add(60, self._open_untouched, button)

    def _slide_to(self, button, _event):
        if any(other is not button and other.get_active() for other in self._menu_buttons()):
            self._switch_menu(button)
        return False

    def _watch_menu(self, menu):
        menu.connect("deactivate", lambda *_: GLib.idle_add(self._after_menu))
        menu.connect("motion-notify-event", self._menu_motion)
        return menu

    def _menu_motion(self, _menu, event):
        """While a menu is open it gets the pointer's moves, also those over
        the bar; over another menu title, open that menu instead."""
        # The bar sits at the screen's top left, so the pointer's place on the
        # screen is its place in the bar.
        x, y = event.x_root, event.y_root
        if y >= HEIGHT:
            return False
        for button in self._menu_buttons():
            menu = button.get_popup()
            if not button.get_visible() or (menu is not None and menu.get_visible()):
                continue
            spot = button.translate_coordinates(self, 0, 0)
            if spot is None:
                continue
            bx, by = spot
            size = button.get_allocation()
            if bx <= x < bx + size.width and by <= y < by + size.height:
                GLib.idle_add(self._switch_menu, button)
                break
        return False

    def _switch_menu(self, button):
        for other in self._menu_buttons():
            if other is button:
                continue
            menu = other.get_popup()
            if menu is not None and menu.get_visible():
                menu.popdown()
            if other.get_active():
                other.set_active(False)
            # The pointer left it during the menu's grab, so GTK never saw it
            # go: drop the hover look by hand, or every title stays lit.
            other.unset_state_flags(Gtk.StateFlags.PRELIGHT)
        return self._open_untouched(button)

    def _open_untouched(self, button):
        """Open a title's menu with nothing in it chosen yet (opened from
        code, GTK picks the first item, as if the keyboard had opened it)."""
        button.set_active(True)
        menu = button.get_popup()
        if menu is not None:
            GLib.idle_add(lambda: menu.deselect() and False)
        return False

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
                        # The app's About and Settings join the app menu once
                        # its actions have arrived.
                        self._groups[prefix].connect(
                            "action-added", lambda *_: GLib.idle_add(self._refill_app_menu))
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
        menu = mac_accel.macify(Gtk.Menu.new_from_model(model))
        menu.connect("motion-notify-event", self._menu_motion)
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
            self._slide(button)
            self.menus_box.pack_start(button, False, False, 0)
            button.show_all()
        self.menus_box.set_visible(bool(menus))

    def _own_action(self, name):
        view = self.focused
        if not view or not self.wf:
            return
        if name == "hide":
            self._hide_app(view)
        elif name == "hide-others":
            self._hide_others(view)
        elif name == "show-all":
            self._show_all()
        elif name == "quit":
            self._quit(view)

    def _views_of(self, app_id, same=True):
        return [v for v in (self.wf.views() if self.wf else [])
                if ((v.get("app-id") or "") == app_id) == same]

    def _hide_app(self, view):
        for other in self._views_of(view.get("app-id") or ""):
            self.wf.set_minimized(other["id"], True)

    def _hide_others(self, view):
        for other in self._views_of(view.get("app-id") or "", same=False):
            if not is_minimized(other):
                self.wf.set_minimized(other["id"], True)

    def _show_all(self):
        for other in (self.wf.views() if self.wf else []):
            if is_minimized(other):
                self.wf.set_minimized(other["id"], False)

    def _app_about(self, view):
        app_id = view.get("app-id") or ""
        name = apps.display_name(app_id)
        dialog = Gtk.AboutDialog(program_name=name, comments="")
        icon = apps.icon_for(app_id)
        theme = Gtk.IconTheme.get_default()
        info = theme.lookup_by_gicon(icon, 128, 0) if icon is not None else None
        if info is not None:
            try:
                dialog.set_logo(info.load_icon())
            except GLib.Error:
                pass
        dialog.run()
        dialog.destroy()

    def _quit(self, view):
        """Close the app's windows (it may ask to save first); with no Strata,
        end its process."""
        if self.wf and self.wf.quit(view.get("app-id") or ""):
            return
        if view.get("pid"):
            os.kill(view["pid"], signal.SIGTERM)

    SETTINGS_ACTIONS = ("preferences", "settings", "prefs", "show-preferences", "show-settings")
    ABOUT_ACTIONS = ("about", "show-about")

    def _app_action(self, names):
        """(group, name) of the first of these actions the app offers."""
        for prefix in ("app", "win"):
            group = self._groups.get(prefix)
            if group is None:
                continue
            for name in names:
                if group.has_action(name) and group.get_action_enabled(name):
                    return group, name
        return None

    def _refill_app_menu(self):
        if not self._menu_open():
            self._fill_app_menu(self.focused)
        return False

    def _fill_app_menu(self, view):
        # An app with an old-style app menu: its items, then Hide and Quit.
        if view and self._app_model is not None and self._app_model.get_n_items():
            name = apps.display_name(view.get("app-id"))
            combined = Gio.Menu()
            combined.append_section(None, self._app_model)
            hiding = Gio.Menu()
            for label, action, accel in ((f"Hide {name}", "topline.hide", "<Super>h"),
                                         ("Hide Others", "topline.hide-others", "<Super><Alt>h"),
                                         ("Show All", "topline.show-all", None)):
                item = Gio.MenuItem.new(label, action)
                if accel:
                    item.set_attribute_value("accel", GLib.Variant.new_string(accel))
                hiding.append_item(item)
            combined.append_section(None, hiding)
            quitting = Gio.Menu()
            item = Gio.MenuItem.new(f"Quit {name}", "topline.quit")
            item.set_attribute_value("accel", GLib.Variant.new_string("<Super>q"))
            quitting.append_item(item)
            combined.append_section(None, quitting)
            self.app_button.set_popup(self._menu_from_model(combined))
            return
        if self.app_button.get_popup() is not self.app_menu:
            self.app_button.set_popup(self.app_menu)
        menu = self.app_menu
        self._clear(menu)
        if not view:
            self._item(menu, "About freemac", self._about)
        else:
            # The same menu in every app, as on a Mac.
            name = apps.display_name(view.get("app-id"))
            about = self._app_action(self.ABOUT_ACTIONS)
            self._item(menu, f"About {name}", (lambda: about[0].activate_action(about[1], None))
                       if about else (lambda: self._app_about(view)))
            settings = self._app_action(self.SETTINGS_ACTIONS)
            if settings:
                # Command+comma reaches the app as Ctrl+comma, the shortcut
                # most apps use for their settings.
                menu.append(Gtk.SeparatorMenuItem())
                self._item(menu, "Settings\u2026", lambda: settings[0].activate_action(settings[1], None),
                           shortcut="\u2318,")
            menu.append(Gtk.SeparatorMenuItem())
            self._item(menu, f"Hide {name}", lambda: self._hide_app(view), shortcut="\u2318H")
            self._item(menu, "Hide Others", lambda: self._hide_others(view), shortcut="\u2325\u2318H")
            self._item(menu, "Show All", self._show_all)
            menu.append(Gtk.SeparatorMenuItem())
            self._item(menu, f"Quit {name}", lambda: self._quit(view), shortcut="\u2318Q")
        menu.show_all()

    def _fill_window_menu(self, view):
        """Minimize, Zoom and Bring All to Front, then the app's windows with
        a tick by the front one (other apps' windows are in the dock and
        ⌘Tab, as on a Mac)."""
        menu = self.window_menu
        self._clear(menu)
        vid = view["id"] if view else None
        self._item(menu, "Minimize", (lambda: self.wf.set_minimized(vid, True)) if view else None,
                   shortcut="\u2318M")
        self._item(menu, "Zoom", (lambda: self._zoom(vid)) if view else None)
        menu.append(Gtk.SeparatorMenuItem())
        self._item(menu, "Bring All to Front", (lambda: self._bring_all(view)) if view else None)
        if view and self.wf:
            windows = self._views_of(view.get("app-id") or "")
            if windows:
                menu.append(Gtk.SeparatorMenuItem())
            for other in windows:
                oid = other["id"]
                title = other.get("title") or apps.display_name(other.get("app-id"))
                self._item(menu, title[:60], lambda oid=oid: self._front(oid), check=(oid == vid))
        menu.show_all()

    def _front(self, view_id):
        self.wf.set_minimized(view_id, False)
        self.wf.focus(view_id)

    def _zoom(self, view_id):
        """Fill the screen's free area, or go back (the green button's job)."""
        # Wait for the menu to close first: an app asked to change size while
        # the menu still holds the pointer can keep its old size.
        def zoom():
            self.wf.focus(view_id)
            self.wf.zoom(view_id)
            return False
        GLib.timeout_add(250, zoom)

    def _bring_all(self, view):
        others = [v for v in self._views_of(view.get("app-id") or "") if v["id"] != view["id"]]
        for other in others:
            self.wf.set_minimized(other["id"], False)
            self.wf.focus(other["id"])
        self.wf.focus(view["id"])


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
