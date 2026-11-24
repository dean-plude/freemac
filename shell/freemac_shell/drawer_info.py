# SPDX-License-Identifier: GPL-3.0-or-later
"""Get Info for Drawer (Command+I): one small window per item with its icon,
name, kind, size, where it is, when it was made and changed, and who can open
it. A document also shows the app that opens it, and Change All… makes that
app open every document of its kind. A folder's size is added up in the
background, so the window opens at once. Original freemac code.
"""
import os
import pwd
import stat
import sys
import threading
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gio, GdkPixbuf, GLib, Gtk  # noqa: E402

from . import alert, app_list, default_apps, macapps, tags  # noqa: E402
from .apps import DESKTOP_WINDOW  # noqa: E402

ATTRS = ",".join((
    "standard::display-name", "standard::content-type", "standard::icon", "standard::size",
    "standard::type", "time::created", "time::modified", "unix::mode", "unix::uid",
    "access::can-read", "access::can-write",
))


def item_info(path, content_type):
    """The line Show Item Info puts under a name: how many items a folder
    holds, or a picture's width and height, as a Mac's desktop does."""
    if os.path.isdir(path):
        try:
            count = sum(1 for n in os.listdir(path) if not n.startswith("."))
        except OSError:
            return ""
        return f"{count} item{'s' if count != 1 else ''}"
    if (content_type or "").startswith("image/"):
        found = GdkPixbuf.Pixbuf.get_file_info(path)
        if found and found[0] is not None and found[1] > 0:
            return f"{found[1]} \u00d7 {found[2]}"
    return ""


def nice_size(size):
    """Sizes as a Mac shows them: 1,234,567 bytes (1.2 MB on disk)."""
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if size < 1000 or unit == "TB":
            short = f"{size:,.0f} {unit}" if unit == "bytes" else f"{size:.1f} {unit}"
            break
        size /= 1000
    return short


def stamp_text(stamp):
    if not stamp:
        return "Not known"
    return time.strftime("%A, %-d %B %Y at %-I:%M %p", time.localtime(stamp))


def folder_total(path, stop):
    """(bytes, items) under a folder, not following links."""
    total, items = 0, 0
    for root, dirs, files in os.walk(path, onerror=lambda _e: None):
        if stop.is_set():
            return None
        for name in files + dirs:
            items += 1
            try:
                info = os.lstat(os.path.join(root, name))
            except OSError:
                continue
            if stat.S_ISREG(info.st_mode):
                total += info.st_size
    return total, items


def who_can_open(info, path):
    mode = info.get_attribute_uint32("unix::mode") if info.has_attribute("unix::mode") else 0
    uid = info.get_attribute_uint32("unix::uid") if info.has_attribute("unix::uid") else os.getuid()
    try:
        owner = pwd.getpwuid(uid).pw_gecos.split(",")[0] or pwd.getpwuid(uid).pw_name
    except KeyError:
        owner = str(uid)
    mine = uid == os.getuid()
    can_write = info.get_attribute_boolean("access::can-write")
    can_read = info.get_attribute_boolean("access::can-read")
    you = ("You can read and change it" if can_write else "You can read it, not change it" if can_read
           else "You can't open it")
    others = "Others on this computer can read it" if mode & stat.S_IROTH else "Others on this computer can't open it"
    return [("Owner", "You" if mine else owner), ("You", you), ("Others", others)]


OTHER = "other…"   # the pop-up's last row, which asks for any app


class InfoWindow(Gtk.Window):
    def __init__(self, path, parent=None):
        super().__init__(title=f"{os.path.basename(path.rstrip('/')) or path} Info")
        self.set_default_size(300, -1)
        self.set_resizable(False)
        if parent is not None:
            self.set_transient_for(None)  # its own window, as on a Mac
        self.stop = threading.Event()
        self.connect("destroy", lambda *_: self.stop.set())
        gfile = Gio.File.new_for_path(path)
        try:
            info = gfile.query_info(ATTRS, Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, None)
        except GLib.Error as err:
            self.add(Gtk.Label(label=err.message, margin=18))
            return
        is_bundle = macapps.is_bundle(path)
        is_dir = info.get_file_type() == Gio.FileType.DIRECTORY and not is_bundle
        name = macapps.display_name(path) if is_bundle else info.get_display_name()
        kind = ("Mac app" if is_bundle else "Folder" if is_dir
                else Gio.content_type_get_description(info.get_content_type() or "") or "Document")
        # An app in Applications is shown as the app, not as its .desktop file.
        app = Gio.DesktopAppInfo.new_from_filename(path) if app_list.is_installed_app(path) else None
        if app is not None:
            name, kind = app.get_display_name() or name, "Application"
            self.set_title(f"{name} Info")

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=18)
        top = Gtk.Box(spacing=12)
        image = Gtk.Image()
        pixbuf = macapps.cached_icon(path, 64) if is_bundle else None
        if pixbuf is not None:
            image.set_from_pixbuf(pixbuf)
        elif app is not None and app.get_icon() is not None:
            image.set_from_gicon(app.get_icon(), Gtk.IconSize.DIALOG)
            image.set_pixel_size(64)
        elif info.get_icon() is not None:
            image.set_from_gicon(info.get_icon(), Gtk.IconSize.DIALOG)
            image.set_pixel_size(64)
        top.pack_start(image, False, False, 0)
        titles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
        title = Gtk.Label(label=name, xalign=0, wrap=True, max_width_chars=24)
        title.get_style_context().add_class("drawer-preview-name")
        titles.pack_start(title, False, False, 0)
        self.size_line = Gtk.Label(xalign=0, wrap=True, max_width_chars=30)
        self.size_line.get_style_context().add_class("dim-label")
        titles.pack_start(self.size_line, False, False, 0)
        top.pack_start(titles, True, True, 0)
        box.pack_start(top, False, False, 0)
        box.pack_start(Gtk.Separator(), False, False, 0)

        grid = Gtk.Grid(column_spacing=10, row_spacing=6)
        rows = [("Kind", kind)]
        self.size_value = Gtk.Label(xalign=0, selectable=True, wrap=True, max_width_chars=30)
        if app is not None:
            self.size_value.set_text("Adding up…")
            self.size_line.set_text(app.get_description() or "")
            self.version_value = Gtk.Label(label="—", xalign=0, selectable=True)
            threading.Thread(target=self._app_package, args=(path,), daemon=True).start()
        elif is_dir or is_bundle:
            self.size_value.set_text("Adding up…")
            self.size_line.set_text("Adding up…")
            threading.Thread(target=self._add_up, args=(path, is_bundle), daemon=True).start()
        else:
            size = info.get_size()
            self.size_value.set_text(f"{size:,} bytes" if size < 1000 else f"{nice_size(size)} ({size:,} bytes)")
            self.size_line.set_text(nice_size(size))
        rows.append(("Size", self.size_value))
        where = os.path.dirname(os.path.abspath(path))
        home = GLib.get_home_dir()
        if app is not None:
            rows.append(("Version", self.version_value))
            rows.append(("Where", "Applications"))
        else:
            rows.append(("Where", "Home" + where[len(home):] if where.startswith(home) else where))
        created = info.get_creation_date_time() if hasattr(info, "get_creation_date_time") else None
        modified = info.get_modification_date_time()
        rows.append(("Created", stamp_text(created.to_unix() if created else 0)))
        rows.append(("Modified", stamp_text(modified.to_unix() if modified else 0)))
        self.tag_note = Gtk.Label(xalign=0)
        self.tag_note.get_style_context().add_class("dim-label")
        tag_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        tag_box.pack_start(tags.picker([path], self._tagged), False, False, 0)
        tag_box.pack_start(self.tag_note, False, False, 0)
        self.tag_note.set_no_show_all(True)
        rows.append(("Tags", tag_box))
        for row, (label, value) in enumerate(rows):
            self._row(grid, row, label, value)
        box.pack_start(grid, False, False, 0)

        content = info.get_content_type() or ""
        if not is_dir and not is_bundle and app is None and info.get_file_type() == Gio.FileType.REGULAR \
                and content:
            box.pack_start(Gtk.Separator(), False, False, 0)
            box.pack_start(self._open_with(content, kind), False, False, 0)

        box.pack_start(Gtk.Separator(), False, False, 0)
        heading = Gtk.Label(label="Sharing and permissions", xalign=0)
        heading.get_style_context().add_class("drawer-heading")
        box.pack_start(heading, False, False, 0)
        perms = Gtk.Grid(column_spacing=10, row_spacing=6)
        for row, (label, value) in enumerate(who_can_open(info, path)):
            self._row(perms, row, label, value)
        box.pack_start(perms, False, False, 0)
        self.add(box)
        self.connect("key-press-event", self._key)
        # Nothing chosen when it opens: GTK would otherwise focus the Kind
        # line and highlight it.
        self.connect("map", lambda *_: GLib.idle_add(self._unfocus))

    def _app_package(self, path):
        """An app's size and version are its package's."""
        found = app_list.package_of(path)

        def show():
            if found is None:
                self.size_value.set_text("—")
                return False
            package, version, size = found
            self.version_value.set_text((f"freemac {version}" if package == "freemac" else version) or "—")
            self.size_value.set_text(f"{nice_size(size)} on disk" if size else
                                     "Part of freemac" if package == "freemac" else "—")
            return False
        GLib.idle_add(show)

    def _open_with(self, content, kind):
        """Open with: the app that opens this kind of document, and Change
        All… to make another one open them all."""
        section = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        heading = Gtk.Label(label="Open with", xalign=0)
        heading.get_style_context().add_class("drawer-heading")
        section.pack_start(heading, False, False, 0)
        apps = default_apps.apps_for(content)
        store = Gtk.ListStore(str, str, Gio.Icon)
        for app in apps:
            store.append([app.get_id(), default_apps.name_of(app), app.get_icon()])
        store.append(["-", "", None])          # a line
        store.append([OTHER, "Other…", None])
        combo = Gtk.ComboBox(model=store, id_column=0)
        combo.set_row_separator_func(lambda model, it: model[it][0] == "-")
        icon = Gtk.CellRendererPixbuf()
        combo.pack_start(icon, False)
        combo.add_attribute(icon, "gicon", 2)
        text = Gtk.CellRendererText()
        combo.pack_start(text, True)
        combo.add_attribute(text, "text", 1)
        if apps:
            combo.set_active_id(default_apps.default_id(content) or apps[0].get_id())
        section.pack_start(combo, False, False, 0)
        hint = Gtk.Label(xalign=0, wrap=True, max_width_chars=34)
        hint.get_style_context().add_class("dim-label")
        change = Gtk.Button(label="Change All…", halign=Gtk.Align.START)
        kind_name = kind[:1].lower() + kind[1:] if kind[:2] != kind[:2].upper() else kind

        last = [combo.get_active_id()]

        def explain(*_):
            chosen = combo.get_active_id()
            if chosen == OTHER:
                app = self._choose_other(content, kind_name)
                if app is None:
                    if last[0]:
                        combo.set_active_id(last[0])
                    else:
                        combo.set_active(-1)
                    return
                if not any(r[0] == app.get_id() for r in store):
                    store.insert(len(store) - 2, [app.get_id(), default_apps.name_of(app), app.get_icon()])
                combo.set_active_id(app.get_id())
                return
            last[0] = chosen
            if chosen is None:
                change.set_sensitive(False)
                hint.set_text("No app says it opens this kind of document. Choose Other… to pick one.")
                return
            same = chosen == default_apps.default_id(content)
            change.set_sensitive(not same)
            name = store[combo.get_active_iter()][1] if combo.get_active_iter() else ""
            hint.set_text(f"Every {kind_name} opens with {name}." if same else
                          f"Click Change All… to open every {kind_name} with {name}.")

        def change_all(_b):
            chosen = combo.get_active_id()
            name = store[combo.get_active_iter()][1]
            answer = alert.ask(self, f"Open every {kind_name} with {name}?",
                               f"Documents of this kind will open with {name} when you double-click them, "
                               "in Drawer and everywhere else.",
                               [("Cancel", Gtk.ResponseType.CANCEL), ("Continue", Gtk.ResponseType.OK)],
                               default=Gtk.ResponseType.OK)
            if answer != Gtk.ResponseType.OK:
                return
            error = default_apps.set_default(chosen, (content,))
            if error:
                alert.tell(self, "The app couldn't be changed.", error)
            explain()

        combo.connect("changed", explain)
        change.connect("clicked", change_all)
        section.pack_start(change, False, False, 0)
        section.pack_start(hint, False, False, 0)
        explain()
        return section

    def _unfocus(self):
        focus = self.get_focus()
        if isinstance(focus, Gtk.Label):
            focus.select_region(0, 0)
        self.set_focus(None)
        return False

    def _choose_other(self, content, kind_name):
        """Any app on the computer, for a kind of document no app says it
        opens."""
        dialog = Gtk.AppChooserDialog.new_for_content_type(self, Gtk.DialogFlags.MODAL, content)
        dialog.set_heading(f"Choose an app to open every {kind_name}.")
        dialog.get_widget().set_show_all(True)
        app = dialog.get_app_info() if dialog.run() == Gtk.ResponseType.OK else None
        dialog.destroy()
        return app

    def _tagged(self, error):
        if error is not None:
            self.tag_note.set_text("This disk can’t keep tags.")
            self.tag_note.show()

    @staticmethod
    def _row(grid, row, label, value):
        name = Gtk.Label(label=f"{label}:", xalign=1, yalign=0)
        name.get_style_context().add_class("dim-label")
        grid.attach(name, 0, row, 1, 1)
        if isinstance(value, str):
            value = Gtk.Label(label=value, xalign=0, selectable=True, wrap=True, max_width_chars=30)
        grid.attach(value, 1, row, 1, 1)

    def _add_up(self, path, is_bundle):
        result = folder_total(path, self.stop)
        if result is None:
            return

        def show():
            total, items = result
            if is_bundle:
                text = nice_size(total) if total >= 1000 else f"{total:,} bytes"
            else:
                count = f"{items:,} item" + ("" if items == 1 else "s")
                text = ("Empty" if not items else f"{nice_size(total)} for {count}" if total >= 1000
                        else f"{total:,} bytes for {count}")
            self.size_value.set_text(text)
            self.size_line.set_text(text)
            return False

        GLib.idle_add(show)

    def _key(self, _w, event):
        from gi.repository import Gdk
        if event.keyval == Gdk.KEY_Escape or (event.state & Gdk.ModifierType.CONTROL_MASK and
                                              event.keyval in (Gdk.KEY_w, Gdk.KEY_W, Gdk.KEY_i, Gdk.KEY_I)):
            self.destroy()
            return True
        return False


def show(paths, parent=None):
    """One Info window for each item (as on a Mac, at most ten at once)."""
    for path in paths[:10]:
        window = InfoWindow(path, parent)
        if parent is not None and parent.get_application() is not None:
            parent.get_application().add_window(window)
        window.show_all()


def main(argv=None):
    """`python3 -m freemac_shell.drawer_info PATH...`: Info windows on their
    own, for the desktop, which gives windows it opens itself the wrong frame."""
    paths = [p for p in (argv if argv is not None else sys.argv[1:]) if os.path.lexists(p)]
    if not paths:
        return 0
    GLib.set_prgname(DESKTOP_WINDOW)   # the desktop's window: the menu bar says Drawer
    open_windows = []

    def closed(window):
        open_windows.remove(window)
        if not open_windows:
            Gtk.main_quit()
    for path in paths[:10]:
        window = InfoWindow(path, None)
        open_windows.append(window)
        window.connect("destroy", closed)
        window.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
