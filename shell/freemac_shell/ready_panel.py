# SPDX-License-Identifier: GPL-3.0-or-later
"""A full-screen panel (Seek, Glyph) that is already on screen when its
shortcut is pressed.

Mapping a new surface takes the compositor a moment, and keys typed in that
moment went to the app behind. So the panel's window is mapped ahead of time:
while closed it draws nothing, lets every click through and doesn't take the
keyboard; opening only shows its contents and takes the keyboard. Closing
unmaps it for a moment, which hands the keyboard straight back to the app in
front, then maps it again, ready. Original freemac code.
"""
import cairo
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import GLib, Gtk, GtkLayerShell  # noqa: E402


REMAP_AFTER = 600   # ms after closing; long enough for the app to have the keyboard back


class ReadyPanel:
    """Mixed into a layer-shell Gtk.Window whose visible part is `panel`."""

    is_open = False

    def map_ready(self, panel):
        """Put the window on screen, closed: call once, after building it."""
        self._ready_panel = panel
        panel.show_all()
        self.realize()
        self._set_open(False)
        self.show()

    def _set_open(self, opened):
        self.is_open = opened
        self._ready_panel.set_visible(opened)
        GtkLayerShell.set_keyboard_mode(
            self, GtkLayerShell.KeyboardMode.EXCLUSIVE if opened else GtkLayerShell.KeyboardMode.NONE)
        # An empty input shape lets clicks fall through to the windows below.
        self.input_shape_combine_region(None if opened else cairo.Region())

    def show_ready(self):
        self._set_open(True)
        self.show()   # already on screen, unless it has only just closed

    def hide_ready(self):
        self._set_open(False)
        self.hide()
        GLib.timeout_add(REMAP_AFTER, self._remap)

    def _remap(self):
        if not self.is_open and not self.get_visible():
            self.show()
        return False
