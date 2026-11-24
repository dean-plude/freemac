# SPDX-License-Identifier: GPL-3.0-or-later
"""Get Info for Drawer (Command+I): one small window per item with its icon,
name, kind, size, where it is, when it was made and changed, and who can open
it. A document also shows the app that opens it, and Change All… makes that
app open every document of its kind. Click the icon and paste a picture
(⌘V), or drop one on it, to give the item its own icon; Delete takes it off
again. Comments are kept with the item and Seek finds them. Locked keeps the
item from being changed, renamed or thrown away. Sharing and permissions sets
who may read or change it, and a folder can pass its privileges to everything
inside. A folder's size is added up in the
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

from . import aliases, alert, app_list, comments, custom_icons, default_apps, locks, macapps, permissions, tags  # noqa: E402
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
    def __init__(self, path, parent=None, inspector=False):
        super().__init__(title=f"{os.path.basename(path.rstrip('/')) or path} Info")
        self.set_default_size(300, -1)
        self.set_resizable(False)
        if parent is not None:
            self.set_transient_for(None)  # its own window, as on a Mac
        self.inspector = inspector
        self.stop = threading.Event()
        self.connect("destroy", lambda *_: self.stop.set())
        self._keep_comment = None
        self.connect("delete-event", self._keep_now)
        self.connect("destroy", self._keep_now)
        self.connect("key-press-event", self._key)
        # Nothing chosen when it opens: GTK would otherwise focus the Kind
        # line and highlight it.
        self.connect("map", lambda *_: GLib.idle_add(self._unfocus))
        self.path = None
        self._build(path)

    def show_path(self, path):
        """The Inspector (⌥⌘I): show another item in the same window."""
        if path == self.path:
            return
        if getattr(self, "_keep_comment", None) is not None:
            self._keep_comment()
            self._keep_comment = None
        self.stop.set()
        self.stop = threading.Event()
        self.comment_view = None
        self.perm_combos = {}
        child = self.get_child()
        if child is not None:
            self.remove(child)
            child.destroy()
        self._build(path)
        self.get_child().show_all()
        self.resize(1, 1)   # as small as the new item's facts allow
        self._unfocus()

    def _screen_height(self):
        from gi.repository import Gdk
        display = Gdk.Display.get_default()
        monitor = display.get_primary_monitor() or display.get_monitor(0) if display else None
        return monitor.get_workarea().height if monitor is not None else 700

    def _keep_now(self, *_):
        if self._keep_comment is not None:
            self._keep_comment()
        return False

    def _build(self, path):
        self.path = path
        self.set_title(f"{os.path.basename(path.rstrip('/')) or path} Info")
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
        is_alias = aliases.is_alias(path)
        if is_alias:
            kind = "Alias"
        if app is not None:
            name, kind = app.get_display_name() or name, "Application"
            self.set_title(f"{name} Info")

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=18)
        top = Gtk.Box(spacing=12)
        image = Gtk.Image()
        self.path, self.image = path, image
        self.kind_icon = None     # the item's own icon, under any custom one
        pixbuf = macapps.cached_icon(path, 64) if is_bundle else None
        if pixbuf is not None:
            image.set_from_pixbuf(pixbuf)
        elif app is not None and app.get_icon() is not None:
            image.set_from_gicon(app.get_icon(), Gtk.IconSize.DIALOG)
            image.set_pixel_size(64)
        elif is_alias:
            # The original's icon, with the alias's arrow.
            theme = Gtk.IconTheme.get_default()
            try:
                real = Gio.File.new_for_path(path).query_info("standard::icon", Gio.FileQueryInfoFlags.NONE, None)
                found = theme.lookup_by_gicon(real.get_icon(), 64, Gtk.IconLookupFlags.FORCE_SIZE)
            except GLib.Error:
                found = None
            found = found or theme.lookup_icon("text-x-generic", 64, Gtk.IconLookupFlags.FORCE_SIZE)
            if found is not None:
                image.set_from_pixbuf(aliases.badge(found.load_icon()))
        elif info.get_icon() is not None:
            image.set_from_gicon(info.get_icon(), Gtk.IconSize.DIALOG)
            image.set_pixel_size(64)
        self.can_change_icon = app is None and not is_alias
        if self.can_change_icon:
            self.kind_icon = self._image_state()
            custom = custom_icons.pixbuf(path, 64)
            if custom is not None:
                image.set_from_pixbuf(custom)
        top.pack_start(self._icon_well(image) if self.can_change_icon else image, False, False, 0)
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
            threading.Thread(target=self._add_up, args=(path, is_bundle, self.stop), daemon=True).start()
        else:
            size = info.get_size()
            self.size_value.set_text(f"{size:,} bytes" if size < 1000 else f"{nice_size(size)} ({size:,} bytes)")
            self.size_line.set_text(nice_size(size))
        rows.append(("Size", self.size_value))
        if is_alias:
            rows.append(("Original", self._original_row(path)))
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

        self.lock_check = None
        if app is None and not is_alias:
            # Locked, as on a Mac: nothing can change, rename or throw it away.
            self.lock_check = Gtk.CheckButton(label="Locked", active=locks.is_locked(path))
            self.lock_check.set_sensitive(locks.can_lock(path))
            self.lock_check.connect("toggled", self._lock_toggled)
            box.pack_start(self.lock_check, False, False, 0)

        if app is None and not is_alias:
            box.pack_start(Gtk.Separator(), False, False, 0)
            box.pack_start(self._comments(path), False, False, 0)
            self.comment_view.set_editable(not locks.is_locked(path))

        content = info.get_content_type() or ""
        if not is_dir and not is_bundle and app is None and info.get_file_type() == Gio.FileType.REGULAR \
                and content:
            box.pack_start(Gtk.Separator(), False, False, 0)
            box.pack_start(self._open_with(content, kind), False, False, 0)

        box.pack_start(Gtk.Separator(), False, False, 0)
        heading = Gtk.Label(label="Sharing and permissions", xalign=0)
        heading.get_style_context().add_class("drawer-heading")
        box.pack_start(heading, False, False, 0)
        box.pack_start(self._permissions(path, is_dir and not is_alias, info), False, False, 0)
        if self.inspector:
            # The Inspector stays on screen: a long one scrolls.
            scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER,
                                          propagate_natural_height=True, propagate_natural_width=True)
            # (On Wayland GTK only knows the whole screen, so leave room
            # for the menu bar, the Dock and the title bar.)
            scroller.set_max_content_height(self._screen_height() - 230)
            scroller.add(box)
            self.add(scroller)
        else:
            self.add(box)

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

    def _original_row(self, path):
        """Where the alias's original is, or that it can't be found, with
        Select New Original… to point it elsewhere."""
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        where = Gtk.Label(xalign=0, selectable=True, wrap=True, max_width_chars=30)

        def show():
            found = aliases.original(path)
            home = GLib.get_home_dir()
            if found:
                where.set_text("Home" + found[len(home):] if found.startswith(home + "/") else found)
            else:
                where.set_text("Can’t be found")
        show()
        box.pack_start(where, False, False, 0)
        button = Gtk.Button(label="Select New Original…", halign=Gtk.Align.START)
        button.connect("clicked", lambda _b: aliases.choose_original(self, path) and show())
        box.pack_start(button, False, False, 0)
        return box

    @staticmethod
    def _row(grid, row, label, value):
        name = Gtk.Label(label=f"{label}:", xalign=1, yalign=0)
        name.get_style_context().add_class("dim-label")
        grid.attach(name, 0, row, 1, 1)
        if isinstance(value, str):
            value = Gtk.Label(label=value, xalign=0, selectable=True, wrap=True, max_width_chars=30)
        grid.attach(value, 1, row, 1, 1)

    def _add_up(self, path, is_bundle, stop):
        result = folder_total(path, stop)
        if result is None or stop.is_set():
            return

        def show():
            total, items = result
            if is_bundle:
                text = nice_size(total) if total >= 1000 else f"{total:,} bytes"
            else:
                count = f"{items:,} item" + ("" if items == 1 else "s")
                text = ("Empty" if not items else f"{nice_size(total)} for {count}" if total >= 1000
                        else f"{total:,} bytes for {count}")
            if not stop.is_set():
                self.size_value.set_text(text)
                self.size_line.set_text(text)
            return False

        GLib.idle_add(show)

    # ---- the icon -------------------------------------------------------

    def _image_state(self):
        """What the image shows now, to put back when a custom icon goes."""
        kind = self.image.get_storage_type()
        if kind == Gtk.ImageType.PIXBUF:
            return ("pixbuf", self.image.get_pixbuf())
        if kind == Gtk.ImageType.GICON:
            return ("gicon", self.image.get_gicon()[0])
        return None

    def _show_kind_icon(self):
        state = self.kind_icon
        if state is None:
            self.image.clear()
        elif state[0] == "pixbuf":
            self.image.set_from_pixbuf(state[1])
        else:
            self.image.set_from_gicon(state[1], Gtk.IconSize.DIALOG)
            self.image.set_pixel_size(64)

    def _icon_well(self, image):
        """The icon, which a click chooses, as in Finder, so ⌘C, ⌘V and
        Delete act on it, and which takes a picture dropped on it."""
        from gi.repository import Gdk
        well = Gtk.EventBox(can_focus=True, valign=Gtk.Align.CENTER)
        well.get_style_context().add_class("info-icon")
        provider = Gtk.CssProvider()
        provider.load_from_data(b".info-icon { border-radius: 8px; padding: 4px; }"
                                b".info-icon:focus { background-color: alpha(#3a8ef6, 0.28); }")
        well.get_style_context().add_provider(provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        well.add(image)
        well.set_tooltip_text("Click, then paste a picture (⌘V) to change the icon")
        well.connect("button-press-event", lambda w, _e: w.grab_focus() or False)
        well.drag_dest_set(Gtk.DestDefaults.ALL, [Gtk.TargetEntry.new("text/uri-list", 0, 0)],
                           Gdk.DragAction.COPY)
        well.drag_dest_add_image_targets()
        well.connect("drag-data-received", self._dropped)
        self.well = well
        return well

    def _dropped(self, _w, _context, _x, _y, data, _info, _time):
        picture = data.get_pixbuf()
        if picture is None:
            for uri in data.get_uris() or []:
                path = Gio.File.new_for_uri(uri).get_path()
                picture = custom_icons.picture_of(path) if path else None
                if picture is not None:
                    break
        if picture is None:
            alert.tell(self, "That item can’t be used as an icon.", "Drop a picture, such as a PNG or JPEG file.")
            return
        self._set_icon(picture)

    def _locked_say(self):
        """Say that a locked item's icon can't change; True if it is locked."""
        if not locks.is_locked(self.path):
            return False
        alert.tell(self, f"The icon of “{os.path.basename(self.path)}” can’t be changed because it is locked.",
                   "Untick Locked first.")
        return True

    def _lock_toggled(self, check):
        on = check.get_active()
        if on and getattr(self, "comment_view", None) is not None:
            self._keep_comment()   # the words go in before writing is taken away
        try:
            locks.set_locked(self.path, on)
        except OSError as err:
            alert.tell(self, f"“{os.path.basename(self.path)}” couldn’t be {'locked' if on else 'unlocked'}.",
                       err.strerror or "")
            check.handler_block_by_func(self._lock_toggled)
            check.set_active(not on)
            check.handler_unblock_by_func(self._lock_toggled)
            return
        if getattr(self, "comment_view", None) is not None:
            self.comment_view.set_editable(not on)
        self._refresh_permissions()

    # ---- Sharing and permissions ---------------------------------------------

    def _permissions(self, path, is_dir, info):
        """The Name and Privilege table, as on a Mac: a pop-up for each when
        the item is yours, words otherwise."""
        self.perm_combos = {}
        self.perm_apply = None
        self.perm_dir = is_dir
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        try:
            found = permissions.rows(path)
        except OSError:
            for row, (label, value) in enumerate(who_can_open(info, path)):
                grid = Gtk.Grid(column_spacing=10, row_spacing=6)
                self._row(grid, row, label, value)
                box.pack_start(grid, False, False, 0)
            return box
        self.perm_note = Gtk.Label(xalign=0)
        self.perm_note.get_style_context().add_class("dim-label")
        box.pack_start(self.perm_note, False, False, 0)
        grid = Gtk.Grid(column_spacing=16, row_spacing=4)
        for col, title in enumerate(("Name", "Privilege")):
            head = Gtk.Label(label=title, xalign=0)
            head.get_style_context().add_class("dim-label")
            grid.attach(head, col, 0, 1, 1)
        for row, (who, name, level) in enumerate(found, start=1):
            grid.attach(Gtk.Label(label=name, xalign=0, ellipsize=3, max_width_chars=18), 0, row, 1, 1)
            combo = Gtk.ComboBoxText()
            for key, words in permissions.LEVELS:
                combo.append(key, words)
            if level == "w":
                combo.append(*permissions.WRITE_ONLY)
            combo.set_active_id(level)
            combo.connect("changed", self._level_changed, who)
            self.perm_combos[who] = combo
            grid.attach(combo, 1, row, 1, 1)
        box.pack_start(grid, False, False, 0)
        if is_dir:
            self.perm_apply = Gtk.Button(label="Apply to Enclosed Items…", halign=Gtk.Align.START)
            self.perm_apply.connect("clicked", self._apply_enclosed)
            box.pack_start(self.perm_apply, False, False, 0)
        self._refresh_permissions()
        return box

    def _refresh_permissions(self):
        combos = getattr(self, "perm_combos", None)
        if not combos:
            return
        mine = permissions.can_change(self.path)
        self.perm_note.set_text("You can read and change it" if os.access(self.path, os.W_OK)
                                else "You can read it, not change it" if os.access(self.path, os.R_OK)
                                else "You can’t open it")
        try:
            found = {who: level for who, _n, level in permissions.rows(self.path)}
        except OSError:
            found = {}
        for who, combo in combos.items():
            combo.handler_block_by_func(self._level_changed)
            if who in found:
                combo.set_active_id(found[who])
            combo.handler_unblock_by_func(self._level_changed)
            combo.set_sensitive(mine)
        if self.perm_apply is not None:
            self.perm_apply.set_sensitive(mine)

    def _level_changed(self, combo, who):
        level = combo.get_active_id()
        if not level:
            return
        try:
            permissions.set_level(self.path, who, level)
        except OSError as err:
            alert.tell(self, f"The privileges of “{os.path.basename(self.path)}” couldn’t be changed.",
                       err.strerror or "")
        self._refresh_permissions()

    def _apply_enclosed(self, _button):
        name = os.path.basename(self.path.rstrip("/")) or self.path
        answer = alert.ask(self, f"Are you sure you want to apply the privileges of “{name}” to all enclosed items?",
                           "You can’t undo this action.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("OK", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK)
        if answer != Gtk.ResponseType.OK:
            return
        self.perm_apply.set_sensitive(False)
        path, stop = self.path, self.stop

        def work():
            result = permissions.apply_to_enclosed(path, stop)
            GLib.idle_add(done, result)

        def done(result):
            if stop.is_set():
                return False
            self._refresh_permissions()
            _changed, skipped = result
            if skipped:
                alert.tell(self, f"{skipped} item{'s' if skipped != 1 else ''} in “{name}” couldn’t be changed.",
                           "They belong to someone else, are locked, or can’t be opened.")
            return False

        threading.Thread(target=work, daemon=True).start()

    def _set_icon(self, picture):
        if self._locked_say():
            return
        try:
            custom_icons.put(self.path, picture)
        except OSError as err:
            alert.tell(self, f"The icon of “{os.path.basename(self.path)}” couldn’t be changed.",
                       "This disk can’t keep custom icons." if err.errno in (95, 1) else err.strerror or "")
            return
        self.image.set_from_pixbuf(custom_icons.pixbuf(self.path, 64))
        self.well.grab_focus()

    def _icon_key(self, event):
        """⌘C, ⌘X, ⌘V and Delete on the chosen icon."""
        from gi.repository import Gdk
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        key = Gdk.keyval_to_lower(event.keyval)
        clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        if ctrl and key in (Gdk.KEY_c, Gdk.KEY_x):
            found = custom_icons.get(self.path)
            picture = custom_icons.picture_of(found) if found else self.image.get_pixbuf()
            if picture is None:
                theme = Gtk.IconTheme.get_default()
                state = self.kind_icon
                looked = theme.lookup_by_gicon(state[1], 256, Gtk.IconLookupFlags.FORCE_SIZE) \
                    if state and state[0] == "gicon" else None
                picture = looked.load_icon() if looked else None
            if picture is not None:
                clipboard.set_image(picture)
                clipboard.store()
            if key == Gdk.KEY_x:
                self._clear_icon()
            return True
        if ctrl and key == Gdk.KEY_v:
            picture = custom_icons.from_clipboard()
            if picture is None:
                alert.tell(self, "There’s no picture to paste.",
                           "Copy a picture, or a picture file in Drawer, then click the icon and press ⌘V.")
            else:
                self._set_icon(picture)
            return True
        if event.keyval in (Gdk.KEY_Delete, Gdk.KEY_BackSpace, Gdk.KEY_KP_Delete):
            self._clear_icon()
            return True
        return False

    def _clear_icon(self):
        if not custom_icons.has(self.path) or self._locked_say():
            return
        try:
            custom_icons.clear(self.path)
        except OSError as err:
            alert.tell(self, f"The icon of “{os.path.basename(self.path)}” couldn’t be changed.", err.strerror or "")
            return
        self._show_kind_icon()

    # ---- comments -------------------------------------------------------

    def _comments(self, path):
        section = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        heading = Gtk.Label(label="Comments", xalign=0)
        heading.get_style_context().add_class("drawer-heading")
        section.pack_start(heading, False, False, 0)
        view = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=6, right_margin=6,
                            top_margin=4, bottom_margin=4)
        view.get_buffer().set_text(comments.get(path))
        frame = Gtk.Frame()
        frame.set_size_request(-1, 54)
        frame.add(view)
        section.pack_start(frame, False, False, 0)
        self.comment_view = view

        buffer = view.get_buffer()

        def keep(*_):
            text = buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), False)
            if text.strip() == comments.get(path) or locks.is_locked(path):
                return False
            try:
                comments.put(path, text)
            except OSError:
                pass        # a disk that can't keep them; nothing to lose but the words
            return False
        self._keep_comment = keep
        view.connect("focus-out-event", keep)
        return section

    def _key(self, _w, event):
        from gi.repository import Gdk
        if getattr(self, "well", None) is not None and self.well.has_focus() and self._icon_key(event):
            return True
        if event.keyval == Gdk.KEY_Escape or (event.state & Gdk.ModifierType.CONTROL_MASK and
                                              event.keyval in (Gdk.KEY_w, Gdk.KEY_W, Gdk.KEY_i, Gdk.KEY_I)):
            self.destroy()
            return True
        return False


INSPECTOR = [None]   # the one Inspector window, while it is open


def inspector(path, parent=None):
    """The Inspector (⌥⌘I), as on a Mac: one Info window that changes as the
    selection does. Choosing it again closes it."""
    if INSPECTOR[0] is not None:
        INSPECTOR[0].destroy()
        return
    window = InfoWindow(path, parent, inspector=True)
    INSPECTOR[0] = window
    window.connect("map", lambda *_: GLib.timeout_add(200, _float, window))
    window.connect("destroy", lambda *_: INSPECTOR.__setitem__(0, None))
    if parent is not None and parent.get_application() is not None:
        parent.get_application().add_window(window)
    window.show_all()


def _float(window):
    """Keep the Inspector over the other windows, at the right of the screen,
    as a Mac's floating panel is (through Wayfire, as Picture in Picture)."""
    from . import wfipc
    try:
        wf = wfipc.Wayfire()
        known = getattr(window, "view_id", None)
        views = [v for v in wf.req.call("window-rules/list-views")
                 if isinstance(v, dict) and v.get("role") == "toplevel"
                 and (v.get("id") == known if known is not None
                      else v.get("title") == window.get_title())]
        if not views:
            window.float_tries = getattr(window, "float_tries", 0) + 1
            return window.float_tries < 10     # not there yet: look again
        view = max(views, key=lambda v: v.get("id", 0))
        window.view_id = view["id"]
        outputs = wf.req.call("window-rules/list-outputs")
        area = next((o.get("workarea") for o in outputs if isinstance(o, dict) and o.get("workarea")), None)
        geometry = view.get("geometry") or {}
        if area and geometry:
            wf.req.call("window-rules/configure-view", id=view["id"], geometry={
                "x": int(area["x"] + area["width"] - geometry.get("width", 340) - 24),
                "y": int(area["y"] + 24),
                "width": int(geometry.get("width", 340)), "height": int(geometry.get("height", 600))})
        wf.req.call("wm-actions/set-always-on-top", view_id=view["id"], state=True)
    except (ConnectionError, OSError, ValueError, AttributeError, KeyError, TypeError) as err:
        print("drawer_info: couldn't float the Inspector:", err, file=sys.stderr)
    return False


def inspect(path):
    """Show path in the Inspector, if it is open."""
    if INSPECTOR[0] is not None and path and os.path.lexists(path):
        INSPECTOR[0].show_path(path)


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
