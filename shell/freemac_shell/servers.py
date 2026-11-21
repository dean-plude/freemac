# SPDX-License-Identifier: GPL-3.0-or-later
"""Connect to Server, as on a Mac (Drawer's Go > Connect to Server, ⌘K): type
the address of a shared folder on another computer or a network drive
(smb://, sftp://, ftp://, a WebDAV dav://, or just a name, which means a
Windows or Mac shared folder, smb), sign in if it asks, and it opens like a
drive, under Locations with an Eject button. GVfs does the work, and its FUSE
folder gives every app a path to the files. Favourite Servers are kept in
~/.config/freemac/servers.json. Original freemac code."""
import json
import os

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

SCHEMES = ("smb", "sftp", "ssh", "ftp", "ftps", "dav", "davs", "afp", "nfs")
FAVOURITES = os.path.expanduser("~/.config/freemac/servers.json")
# A server that answered but has no one folder to open, such as a Windows or
# Mac computer that shares several: the caller shows its shared folders.
NO_FOLDER = "no-folder"


def normalise(address):
    """What was typed, as a GIO address, or None if it can't be one."""
    text = address.strip()
    if not text:
        return None
    if text.startswith("\\\\"):   # \\host\share, as Windows writes it
        text = "smb://" + text.lstrip("\\").replace("\\", "/")
    if "://" not in text:
        text = "smb://" + text
    scheme = text.split("://", 1)[0].lower()
    if scheme not in SCHEMES:
        return None
    if scheme == "ssh":
        text = "sftp://" + text.split("://", 1)[1]
    if not text.split("://", 1)[1].strip("/"):
        return None
    return text


def is_server(mount):
    """A connected server (not a disk), for Drawer's Locations."""
    if mount.is_shadowed():
        return False
    root = mount.get_root()
    return root.get_uri_scheme() in SCHEMES and root.get_path() is not None


def servers():
    from . import volumes
    return [m for m in volumes.monitor().get_mounts() if is_server(m)]


def favourites():
    try:
        with open(FAVOURITES, encoding="utf-8") as f:
            items = json.load(f)
        return [str(a) for a in items if isinstance(a, str) and normalise(a)]
    except (OSError, ValueError):
        return []


def save_favourites(items):
    os.makedirs(os.path.dirname(FAVOURITES), exist_ok=True)
    tmp = FAVOURITES + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(list(dict.fromkeys(items)), f, indent=2)
    os.replace(tmp, FAVOURITES)


def path_for(gfile):
    """The folder an app can open for a mounted address."""
    path = gfile.get_path()
    if path:
        return path
    try:
        return gfile.find_enclosing_mount(None).get_root().get_path()
    except GLib.Error:
        return None


def host_of(uri):
    host = uri.split("://", 1)[1].split("/", 1)[0].rsplit("@", 1)[-1]
    return host.rsplit(":", 1)[0] if host.count(":") == 1 else host


def explain(uri, error, name=None):
    """What went wrong, in plain words; the system's own message is technical."""
    if error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.PERMISSION_DENIED):
        return "The name or password wasn\u2019t accepted. Check them, and then try again."
    return (f"There was a problem connecting to the server \u201c{name or host_of(uri)}\u201d. Check the "
            "server name or IP address, and then try again.")


def connect(uri, parent, done, name=None):
    """Mount uri, asking for a name and password if the server wants one, then
    call done(path, None) or done(None, message)."""
    gfile = Gio.File.new_for_uri(uri)
    operation = Gtk.MountOperation(parent=parent)
    tried_guest = []

    def ask_password(op, _message, _user, _domain, flags):
        # A folder shared for everyone (such as freemac's File Sharing) opens
        # as a guest without asking; only if that's refused does the sign-in
        # ask for a name and password.
        if tried_guest or not flags & Gio.AskPasswordFlags.ANONYMOUS_SUPPORTED:
            return
        tried_guest.append(True)
        op.stop_emission_by_name("ask-password")
        op.set_anonymous(True)
        op.reply(Gio.MountOperationResult.HANDLED)
    operation.connect("ask-password", ask_password)

    def finished(source, result, _data):
        try:
            source.mount_enclosing_volume_finish(result)
        except GLib.Error as error:
            if error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.ALREADY_MOUNTED):
                pass
            elif error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.FAILED_HANDLED):
                done(None, "")   # the person cancelled the sign-in
                return
            else:
                done(None, explain(uri, error, name))
                return
        path = path_for(source)
        done(path, None if path else NO_FOLDER)

    gfile.mount_enclosing_volume(Gio.MountMountFlags.NONE, operation, None, finished, None)


def connect_dialog(parent, open_path, open_server=None):
    """The Connect to Server window: an address, Favourite Servers, Connect."""
    dialog = Gtk.Dialog(title="Connect to Server", transient_for=parent, modal=True)
    dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
    go = dialog.add_button("Connect", Gtk.ResponseType.OK)
    go.get_style_context().add_class("suggested-action")
    dialog.set_default_response(Gtk.ResponseType.OK)
    dialog.set_default_size(440, 340)
    box = dialog.get_content_area()
    box.set_spacing(8)
    box.set_border_width(14)
    line = Gtk.Box(spacing=6)
    entry = Gtk.Entry(activates_default=True, hexpand=True,
                      placeholder_text="smb://computer-name/shared-folder")
    add = Gtk.Button(label="+", tooltip_text="Add to Favourite Servers")
    line.pack_start(entry, True, True, 0)
    line.pack_start(add, False, False, 0)
    box.pack_start(line, False, False, 0)
    heading = Gtk.Label(label="Favourite Servers:", xalign=0)
    box.pack_start(heading, False, False, 0)
    listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
    scroll = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
    scroll.set_shadow_type(Gtk.ShadowType.IN)
    scroll.add(listbox)
    box.pack_start(scroll, True, True, 0)
    under = Gtk.Box(spacing=6)
    remove = Gtk.Button(label="\u2212", tooltip_text="Remove from Favourite Servers", valign=Gtk.Align.START)
    under.pack_start(remove, False, False, 0)
    status = Gtk.Label(label="A name on its own means a Windows or Mac shared folder (smb).",
                       xalign=0, wrap=True)
    status.get_style_context().add_class("dim-label")
    under.pack_start(status, True, True, 4)
    box.pack_start(under, False, False, 0)

    def fill():
        for child in listbox.get_children():
            listbox.remove(child)
        for address in favourites():
            row = Gtk.ListBoxRow()
            row.address = address
            row.add(Gtk.Label(label=address, xalign=0, margin=5))
            listbox.add(row)
        listbox.show_all()
        remove.set_sensitive(bool(favourites()))

    def add_favourite(*_):
        if normalise(entry.get_text()):
            save_favourites(favourites() + [entry.get_text().strip()])
            fill()
        entry.grab_focus()

    def remove_favourite(*_):
        row = listbox.get_selected_row()
        if row is not None:
            save_favourites([a for a in favourites() if a != row.address])
            fill()

    add.connect("clicked", add_favourite)
    remove.connect("clicked", remove_favourite)
    listbox.connect("row-selected", lambda _l, row: row is not None and entry.set_text(row.address))
    listbox.connect("row-activated", lambda *_: dialog.response(Gtk.ResponseType.OK))
    fill()
    dialog.show_all()
    entry.grab_focus()
    state = {"busy": False}

    def answered(_d, response):
        if response != Gtk.ResponseType.OK:
            dialog.destroy()
            return
        if state["busy"]:
            return
        uri = normalise(entry.get_text())
        if uri is None:
            status.set_text("Type an address such as smb://computer-name/shared-folder.")
            return
        state["busy"] = True
        go.set_sensitive(False)
        status.set_text("Connecting\u2026")

        def done(path, problem):
            state["busy"] = False
            go.set_sensitive(True)
            if path:
                dialog.destroy()
                open_path(path)
            elif problem == NO_FOLDER and open_server:
                dialog.destroy()
                open_server(uri)
            elif problem == NO_FOLDER:
                status.set_text("Type the shared folder's name after the computer's, such as smb://office-pc/Photos.")
            elif problem is not None:
                status.set_text(problem or "Not connected.")
                entry.grab_focus()

        connect(uri, dialog, done)

    dialog.connect("response", answered)
    return dialog


NAMES = {}                    # a connected folder's path -> the name it was opened by


def title(mount):
    """What to call a connected server or shared folder: the name it was
    opened by in Network ("Public"), else the share or server's own name."""
    root = mount.get_root().get_path() or ""
    if root in NAMES:
        return NAMES[root]
    base = os.path.basename(root)
    if base.startswith("smb-share:"):
        fields = dict(f.split("=", 1) for f in base.split(":", 1)[1].split(",") if "=" in f)
        if fields.get("share"):
            return fields["share"]
    name = mount.get_name()
    return name.split(" on ", 1)[0] if " on " in name else name


def title_of(path):
    """The title for a folder that is a connected server's top, else None."""
    mount = mount_of(path)
    if mount and mount.get_root().get_path() == path:
        return title(mount)
    return None


def mount_of(path):
    """The connected server that holds this path, or None."""
    best = None
    for mount in servers() if path else ():
        root = mount.get_root().get_path()
        if path == root or path.startswith(root.rstrip("/") + "/"):
            if best is None or len(root) > len(best.get_root().get_path()):
                best = mount
    return best
