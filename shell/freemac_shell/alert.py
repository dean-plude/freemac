# SPDX-License-Identifier: GPL-3.0-or-later
"""Alerts the way a Mac shows them: a small window with no title bar, the
app's icon on top, the question in bold under it, a line of detail, and the
buttons below, side by side and the same width (stacked when there are three
or more). The default button is blue; Return presses it, Escape cancels.

    answer = alert.ask(window, "Empty the Trash?", "This can't be undone.",
                       [("Cancel", Gtk.ResponseType.CANCEL),
                        ("Empty Trash", Gtk.ResponseType.OK)],
                       default=Gtk.ResponseType.OK, destructive=Gtk.ResponseType.OK)

Original freemac code.
"""
import os
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, Gtk  # noqa: E402

from . import apps  # noqa: E402

WIDTH = 260
ICON = 64

CANCEL_ANSWERS = (Gtk.ResponseType.CANCEL, Gtk.ResponseType.CLOSE, Gtk.ResponseType.NO)


def _app_icon(parent, icon):
    """The icon to show: one given, else the app's own, else a plain one."""
    if icon is not None:
        return Gio.ThemedIcon.new(icon) if isinstance(icon, str) else icon
    app = Gio.Application.get_default()
    if app is None and parent is not None and hasattr(parent, "get_application"):
        app = parent.get_application()
    names = []
    if app is not None and app.get_application_id():
        names.append(app.get_application_id())
    names.append(os.path.basename(sys.argv[0] or ""))
    for name in names:
        info = apps.app_info(name) if name else None
        if info is not None and info.get_icon() is not None:
            return info.get_icon()
    return Gio.ThemedIcon.new("dialog-information")


def build(parent, title, text="", buttons=(("OK", Gtk.ResponseType.OK),), default=None,
          destructive=None, icon=None):
    """The alert as a Gtk.Dialog, not yet shown."""
    dialog = Gtk.Dialog(transient_for=parent, modal=True, title=title)
    # An empty title bar of its own: GTK then draws the frame (a rounded
    # panel with a shadow) and Strata adds no title bar or window buttons.
    empty = Gtk.Box()
    empty.set_size_request(-1, 0)
    if parent is None:
        # A sheet's title bar is hidden under its window's; a free-standing
        # alert's would show as an empty grey band, so it takes no room.
        flat = Gtk.CssProvider()
        flat.load_from_data(b"* { min-height: 0; padding: 0; margin: 0; border: none; "
                            b"background: none; box-shadow: none; }")
        empty.get_style_context().add_provider(flat, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    dialog.set_titlebar(empty)
    visual = dialog.get_screen().get_rgba_visual()
    if visual is not None:
        dialog.set_visual(visual)   # see-through corners, room for the shadow
    dialog.set_resizable(False)
    dialog.set_default_size(WIDTH, -1)
    dialog.get_style_context().add_class("freemac-alert")
    area = dialog.get_content_area()
    area.set_spacing(0)
    # Gtk.Dialog's own button row is not used; the buttons sit in the body.
    action = dialog.get_action_area() if hasattr(dialog, "get_action_area") else None
    if action is not None:
        action.hide()
        action.set_no_show_all(True)

    body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
    body.get_style_context().add_class("alert-body")
    image = Gtk.Image.new_from_gicon(_app_icon(parent, icon), Gtk.IconSize.DIALOG)
    image.set_pixel_size(ICON)
    body.pack_start(image, False, False, 0)
    heading = Gtk.Label(label=title, wrap=True, max_width_chars=28, justify=Gtk.Justification.CENTER)
    heading.get_style_context().add_class("alert-title")
    body.pack_start(heading, False, False, 0)
    if text:
        detail = Gtk.Label(label=text, wrap=True, max_width_chars=34, justify=Gtk.Justification.CENTER)
        detail.get_style_context().add_class("alert-text")
        body.pack_start(detail, False, False, 0)

    stacked = len(buttons) > 2
    row = Gtk.Box(orientation=Gtk.Orientation.VERTICAL if stacked else Gtk.Orientation.HORIZONTAL,
                  spacing=8, homogeneous=True)
    row.get_style_context().add_class("alert-buttons")
    # Two buttons: Cancel on the left, the answer on the right. Three or
    # more: one above the other, the default on top.
    order = list(buttons)
    if stacked and default is not None:
        order.sort(key=lambda b: b[1] != default)
    default_button = None
    for label, response in order:
        button = Gtk.Button(label=label, use_underline=True)
        button.set_can_default(True)
        if response == default:
            button.get_style_context().add_class("suggested-action")
            default_button = button
        if response == destructive:
            button.get_style_context().add_class("destructive-action")
        button.connect("clicked", lambda _b, r=response: dialog.response(r))
        row.pack_start(button, True, True, 0)
    body.pack_start(row, False, False, 6)
    area.pack_start(body, True, True, 0)
    body.show_all()

    cancel = next((r for _l, r in buttons if r in CANCEL_ANSWERS), None)

    def key(_widget, event):
        if event.keyval == Gdk.KEY_Escape:
            dialog.response(cancel if cancel is not None else Gtk.ResponseType.DELETE_EVENT)
            return True
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) and default_button is not None:
            # Return presses the default button even when another has focus,
            # as on a Mac; Space presses the focused one.
            dialog.response(default)
            return True
        return False

    dialog.connect("key-press-event", key)
    if default_button is not None:
        dialog.set_default(default_button)
        default_button.grab_focus()
    return dialog


def ask(parent, title, text="", buttons=(("OK", Gtk.ResponseType.OK),), default=None,
        destructive=None, icon=None):
    """Show the alert, wait for an answer and return its response."""
    dialog = build(parent, title, text, buttons, default, destructive, icon)
    answer = dialog.run()
    dialog.destroy()
    if answer == Gtk.ResponseType.DELETE_EVENT:
        cancel = next((r for _l, r in buttons if r in CANCEL_ANSWERS), None)
        return cancel if cancel is not None else answer
    return answer


def tell(parent, title, text="", button="OK", icon=None):
    """An alert with one button, for news rather than a question."""
    ask(parent, title, text, [(button, Gtk.ResponseType.OK)], default=Gtk.ResponseType.OK, icon=icon)
