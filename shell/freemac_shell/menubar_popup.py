# SPDX-License-Identifier: GPL-3.0-or-later
"""A menu that opens under a symbol in the menu bar (Battery, Bluetooth).

A small layer-shell window of its own, since Topline's window is only as
tall as the bar, drawn like the Sound and Wi-Fi menus. A layer surface isn't
told about clicks elsewhere, so it closes a little after the pointer leaves
it, a few seconds after opening if it is never pointed at, on Escape, or
when its symbol is clicked again.
"""
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

from . import style  # noqa: E402


class Popup:
    def __init__(self, namespace, width=290):
        self.width = width
        self.window = Gtk.Window(title=namespace)
        style.make_transparent(self.window)
        GtkLayerShell.init_for_window(self.window)
        GtkLayerShell.set_layer(self.window, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(self.window, namespace)
        GtkLayerShell.set_anchor(self.window, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self.window, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_margin(self.window, GtkLayerShell.Edge.TOP, 32)
        GtkLayerShell.set_keyboard_mode(self.window, GtkLayerShell.KeyboardMode.ON_DEMAND)
        self.menu = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.menu.get_style_context().add_class("topline-popup")
        self.menu.get_style_context().add_class("sound-menu")
        self.menu.set_size_request(width, -1)
        self.window.add(self.menu)
        self.window.connect("key-press-event", self._key)
        self.window.connect("leave-notify-event", self._leave)
        self.window.connect("enter-notify-event", self._stay)
        # A pointer already over the menu when it appears gets no enter event.
        self.window.add_events(Gdk.EventMask.POINTER_MOTION_MASK)
        self.window.connect("motion-notify-event", self._stay)
        self.timer = None

    # -- contents -----------------------------------------------------------

    def clear(self):
        for child in self.menu.get_children():
            child.destroy()

    def add(self, widget, padding=0):
        self.menu.pack_start(widget, False, False, padding)
        return widget

    def separator(self):
        return self.add(Gtk.Separator(), 4)

    def title(self, words, right=None):
        """The menu's bold title, with a widget (a switch, a figure) at its right."""
        row = Gtk.Box(spacing=8)
        label = Gtk.Label(label=words, xalign=0)
        label.get_style_context().add_class("sound-menu-title")
        row.pack_start(label, True, True, 0)
        if right is not None:
            row.pack_end(right, False, False, 6)
        return self.add(row)

    def heading(self, words):
        label = Gtk.Label(label=words, xalign=0, wrap=True, max_width_chars=34)
        label.get_style_context().add_class("sound-menu-heading")
        return self.add(label)

    def note(self, words):
        """A plain line of information, like Power Source: Battery."""
        label = Gtk.Label(label=words, xalign=0, wrap=True, max_width_chars=34)
        label.get_style_context().add_class("menu-note")
        return self.add(label)

    def item(self, words, action, icon=None, gicon=None, round_icon=False, on=False):
        """A row that does something and closes the menu."""
        button = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
        button.get_style_context().add_class("sound-menu-item")
        line = Gtk.Box(spacing=10)
        if icon or gicon:
            image = (Gtk.Image.new_from_gicon(gicon, Gtk.IconSize.MENU) if gicon
                     else Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU))
            image.set_pixel_size(16)
            if round_icon:
                image.get_style_context().add_class("sound-device")
                if on:
                    image.get_style_context().add_class("sound-device-on")
            line.pack_start(image, False, False, 0)
        line.pack_start(Gtk.Label(label=words, xalign=0, ellipsize=3, max_width_chars=30), True, True, 0)
        button.add(line)
        button.connect("clicked", lambda *_: (self.hide(), action()))
        return self.add(button)

    def switch_row(self, words, active, changed):
        """A row with a switch at its right, like Low Power Mode."""
        row = Gtk.Box(spacing=8)
        label = Gtk.Label(label=words, xalign=0)
        label.get_style_context().add_class("sound-menu-item")
        row.pack_start(label, True, True, 0)
        switch = Gtk.Switch(active=active, valign=Gtk.Align.CENTER)
        switch.set_can_focus(False)
        switch.connect("notify::active", lambda s, _p: changed(s.get_active()))
        row.pack_end(switch, False, False, 6)
        return self.add(row)

    # -- showing ------------------------------------------------------------

    def visible(self):
        return self.window.get_visible()

    def show_under(self, button):
        """Open centred under the menu-bar symbol, kept on screen."""
        top = button.get_toplevel()
        alloc = button.get_allocation()
        x, _y = button.translate_coordinates(top, 0, 0)
        right = top.get_allocated_width() - (x + alloc.width // 2) - self.width // 2
        GtkLayerShell.set_margin(self.window, GtkLayerShell.Edge.RIGHT, max(8, right))
        self.menu.show_all()
        self.window.show()
        self._stay()
        self.timer = GLib.timeout_add(6000, self._close)

    def hide(self):
        self._stay()
        self.window.hide()

    def _key(self, _window, event):
        if event.keyval == Gdk.KEY_Escape:
            self.hide()
        return False

    def _stay(self, *_args):
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = None
        return False

    def _leave(self, _window, event):
        if event.detail == Gdk.NotifyType.INFERIOR:
            return False
        self._stay()
        self.timer = GLib.timeout_add(2500, self._close)
        return False

    def _close(self):
        self.timer = None
        self.window.hide()
        return False
