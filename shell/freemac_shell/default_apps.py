# SPDX-License-Identifier: GPL-3.0-or-later
"""Which app opens what: the default web browser and email app (Dials > Dock
and Menu Bar, as on a Mac) and "Open with" in Drawer's Get Info, whose Change
All… makes one app open every document of that kind.

Choices go in the freedesktop list of default apps (~/.config/mimeapps.list)
through GIO, so xdg-open, links in every app and double-clicks in Drawer all
follow them. Original freemac code.
"""
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

# A browser opens web links and web pages; an email app opens mailto: links.
BROWSER = ("x-scheme-handler/http", "x-scheme-handler/https", "text/html", "application/xhtml+xml")
MAIL = ("x-scheme-handler/mailto",)


def apps_for(content_type):
    """[Gio.AppInfo] that can open this kind of thing, the default first,
    each once, leaving out ones hidden from menus."""
    default = Gio.AppInfo.get_default_for_type(content_type, False)
    found, seen = [], set()
    for app in ([default] if default else []) + list(Gio.AppInfo.get_all_for_type(content_type)):
        if app is None or app.get_id() in seen or not app.should_show():
            continue
        seen.add(app.get_id())
        found.append(app)
    return found


def default_id(content_type):
    app = Gio.AppInfo.get_default_for_type(content_type, False)
    return app.get_id() if app else None


def set_default(app_id, content_types):
    """Make app_id open every one of these kinds. Returns an error message,
    or None."""
    try:
        app = Gio.DesktopAppInfo.new(app_id)
    except TypeError:
        app = None
    if app is None:
        return "That app isn't installed any more."
    for content_type in content_types:
        try:
            app.set_as_default_for_type(content_type)
        except GLib.Error as err:
            return err.message
    return None


def name_of(app):
    return app.get_display_name() or app.get_name()


def chooser(content_types, on_change=None):
    """A pop-up menu of the apps that can open the first kind, with an icon
    beside each, showing the one in use. Choosing one makes it the default
    for all the kinds given."""
    store = Gtk.ListStore(str, str, Gio.Icon)
    combo = Gtk.ComboBox(model=store, id_column=0, valign=Gtk.Align.CENTER)
    icon = Gtk.CellRendererPixbuf()
    combo.pack_start(icon, False)
    combo.add_attribute(icon, "gicon", 2)
    text = Gtk.CellRendererText()
    combo.pack_start(text, True)
    combo.add_attribute(text, "text", 1)
    apps = apps_for(content_types[0])
    for app in apps:
        store.append([app.get_id(), name_of(app), app.get_icon()])
    current = default_id(content_types[0])
    if current:
        combo.set_active_id(current)
    if not apps:
        store.append(["", "None installed", None])
        combo.set_active_id("")
        combo.set_sensitive(False)

    def changed(widget):
        chosen = widget.get_active_id()
        if not chosen or chosen == default_id(content_types[0]):
            return
        error = set_default(chosen, content_types)
        if on_change is not None:
            on_change(chosen, error)

    combo.connect("changed", changed)
    return combo
