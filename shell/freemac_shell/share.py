# SPDX-License-Identifier: GPL-3.0-or-later
"""Share: send files to a device nearby (Hail), by mail in Post, or copy
them to a drive.

Drawer, Cove and Frame offer it the same way: a Share button in the
toolbar, Share in the right-click menu, and File > Share. Mail opens a new
message in Post with the files attached (a mailto: link with attach=
fields, which Post reads); a drive copy runs in the background and says
when it is done, or why it failed. Original freemac code.
"""
import mimetypes
import os
import shutil
import subprocess
import threading
import urllib.parse

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

from . import volumes  # noqa: E402

ICON = "freemac-share-symbolic"


def _kind(paths):
    pictures = all((mimetypes.guess_type(p)[0] or "").startswith("image/") for p in paths)
    return "photo" if pictures else "file"


def subject_for(paths):
    if len(paths) == 1:
        return os.path.basename(paths[0].rstrip("/"))
    return f"{len(paths)} {_kind(paths)}s"


def mailto_for(paths):
    """The mailto: link that opens a message in Post with these files attached."""
    fields = [("subject", subject_for(paths))] + [("attach", p) for p in paths]
    return "mailto:?" + urllib.parse.urlencode(fields, quote_via=urllib.parse.quote)


def can_mail(paths):
    return bool(paths) and all(os.path.isfile(p) for p in paths)


def mail(paths):
    uri = mailto_for(paths)
    app = Gio.DesktopAppInfo.new("freemac-post.desktop")
    try:
        if app is not None and app.launch_uris([uri], None):
            return
    except GLib.Error:
        pass
    try:
        subprocess.Popen(["freemac-post", uri], start_new_session=True)
    except OSError:
        pass


def nearby(paths):
    """Send the files to a computer or phone nearby, with Hail."""
    try:
        subprocess.Popen(["freemac-hail", "--send", *paths], start_new_session=True)
    except OSError:
        pass


def free_name(folder, name):
    """name, or "name 2", "name 3"… when the folder already has one."""
    if not os.path.lexists(os.path.join(folder, name)):
        return name
    stem, ext = os.path.splitext(name)
    if name.startswith(".") and not ext:
        stem, ext = name, ""
    n = 2
    while os.path.lexists(os.path.join(folder, f"{stem} {n}{ext}")):
        n += 1
    return f"{stem} {n}{ext}"


def copy_into(paths, folder):
    """Copy files and folders into folder, renaming any that would replace
    one already there. Returns the names they got."""
    made = []
    for path in paths:
        name = free_name(folder, os.path.basename(path.rstrip("/")))
        target = os.path.join(folder, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.copytree(path, target, symlinks=True)
        else:
            shutil.copy2(path, target)
        made.append(name)
    os.sync()
    return made


def _described(paths):
    if len(paths) == 1:
        return f"“{os.path.basename(paths[0].rstrip('/'))}”"
    return f"{len(paths)} items"


def copy_to(parent, paths, mount, told=None):
    """Copy to a drive on a thread. told(text) says how it went; without it,
    a notification does when the copy is done."""
    from . import alert
    folder, drive = volumes.path_of(mount), mount.get_name()
    what = _described(paths)
    if told:
        told(f"Copying {what} to “{drive}”…")

    def finished(error):
        if error is not None:
            if told:
                told(f"Couldn’t copy {what} to “{drive}”.")
            alert.tell(parent, f"{what[0].upper() + what[1:]} couldn’t be copied to “{drive}”.",
                       getattr(error, "strerror", None) or str(error), icon=mount.get_icon())
            return False
        text = f"Copied {what} to “{drive}”."
        if told:
            told(text)
        else:
            app = parent.get_application() if parent is not None else None
            if app is not None:
                note = Gio.Notification.new(text)
                note.set_icon(mount.get_icon())
                app.send_notification(None, note)
        return False

    def work():
        try:
            copy_into(paths, folder)
            error = None
        except (OSError, shutil.Error) as err:
            error = err
        GLib.idle_add(finished, error)
    threading.Thread(target=work, daemon=True).start()


def _drives_for(paths):
    """The drives to offer: each one with files on it, but not the one the
    files are already on."""
    held = {volumes.key_of(m) for m in (volumes.mount_of(p) for p in paths) if m is not None}
    return [m for m in volumes.drives() if volumes.path_of(m) and volumes.key_of(m) not in held]


def menu(parent, paths, told=None):
    """The Share menu: Nearby, Mail, then Copy to each drive that is plugged in."""
    shown = Gtk.Menu()
    item = Gtk.MenuItem(label="Nearby\u2026", sensitive=bool(paths))
    item.connect("activate", lambda *_: nearby(paths))
    shown.append(item)
    item = Gtk.MenuItem(label="Mail", sensitive=can_mail(paths))
    item.connect("activate", lambda *_: mail(paths))
    shown.append(item)
    drives = _drives_for(paths)
    if drives:
        shown.append(Gtk.SeparatorMenuItem())
    for mount in drives:
        item = Gtk.MenuItem(label=f"Copy to “{mount.get_name()}”", sensitive=bool(paths))
        item.connect("activate", lambda _i, m=mount: copy_to(parent, paths, m, told))
        shown.append(item)
    shown.show_all()
    return shown


def menu_item(parent, paths, told=None):
    """“Share” with its menu beside it, for a right-click menu."""
    item = Gtk.MenuItem(label="Share", sensitive=bool(paths))
    item.set_submenu(menu(parent, paths, told))
    return item


def popup(parent, paths, widget=None, told=None):
    """Show the Share menu: under a toolbar button as a popover, or at the
    pointer as a menu."""
    if widget is None or not widget.get_mapped():
        shown = menu(parent, paths, told)
        shown.attach_to_widget(parent, None)
        shown.popup_at_pointer(Gtk.get_current_event())
        return
    actions = Gio.SimpleActionGroup()
    model = Gio.Menu()

    def add(section, label, name, run, enabled=True):
        action = Gio.SimpleAction.new(name, None)
        action.connect("activate", lambda *_: run())
        action.set_enabled(enabled)
        actions.add_action(action)
        section.append(label, "share." + name)

    first = Gio.Menu()
    add(first, "Nearby\u2026", "nearby", lambda: nearby(paths), bool(paths))
    add(first, "Mail", "mail", lambda: mail(paths), can_mail(paths))
    model.append_section(None, first)
    drives = _drives_for(paths)
    if drives:
        second = Gio.Menu()
        for n, mount in enumerate(drives):
            add(second, f"Copy to “{mount.get_name()}”", f"copy{n}",
                lambda m=mount: copy_to(parent, paths, m, told), bool(paths))
        model.append_section(None, second)
    widget.insert_action_group("share", actions)
    shown = Gtk.Popover.new_from_model(widget, model)
    shown.set_position(Gtk.PositionType.BOTTOM)
    shown.popup()


def button(parent, paths_of, told=None):
    """A toolbar button that shows the Share menu for paths_of()."""
    shown = Gtk.Button.new_from_icon_name(ICON, Gtk.IconSize.BUTTON)
    shown.set_tooltip_text("Share")
    shown.connect("clicked", lambda b: popup(parent, paths_of(), b, told))
    return shown
