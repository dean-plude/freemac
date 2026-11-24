# SPDX-License-Identifier: GPL-3.0-or-later
"""Tender: bring your files over from another computer.

Like a Mac's Migration Assistant, in four steps: choose where the files are
(a Lifeboat backup, a Windows PC's disk, another computer's disk or any
folder), choose what to bring, watch it copy, and see what came over.
Nothing is ever deleted, and no file already here is overwritten. The
copying itself is in tender_store.

Original freemac code.
"""
import os
import subprocess
import sys
import threading

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import alert, menus, style, volumes  # noqa: E402
from . import backup_store as store  # noqa: E402
from . import tender_store as tender  # noqa: E402

APP_ID = "org.freemac.Tender"
CSS = b"""
.tender-page { padding: 24px 32px; }
.tender-title { font-size: 22px; font-weight: 800; }
.tender-lead { font-size: 14px; }
.tender-row { padding: 9px 12px; }
.tender-row-title { font-weight: 600; }
.tender-caption { color: alpha(currentColor, 0.6); font-size: 12px; }
.tender-size { color: alpha(currentColor, 0.6); font-feature-settings: "tnum"; }
.tender-warning { color: #b3261e; font-weight: 600; }
.tender-big { font-size: 15px; }
"""
ICONS = {"backup": "freemac-lifeboat", "windows": "drive-harddisk", "linux": "drive-harddisk",
         "folder": "folder"}


def page(title, lead=None):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
    box.get_style_context().add_class("tender-page")
    heading = Gtk.Label(label=title, xalign=0)
    heading.get_style_context().add_class("tender-title")
    box.pack_start(heading, False, False, 0)
    if lead:
        text = Gtk.Label(label=lead, xalign=0, wrap=True, max_width_chars=68)
        text.get_style_context().add_class("tender-lead")
        box.pack_start(text, False, False, 0)
    return box


def caption(text, css="tender-caption"):
    label = Gtk.Label(label=text, xalign=0, wrap=True, max_width_chars=68)
    label.get_style_context().add_class(css)
    return label


def plural(n, one, many=None):
    return f"{n:,} {one if n == 1 else (many or one + 's')}"


class Window(Gtk.ApplicationWindow):
    def __init__(self, app, folder=None):
        super().__init__(application=app, title="Tender")
        self.set_default_size(680, 500)
        header = Gtk.HeaderBar(show_close_button=True, title="Tender")
        self.set_titlebar(header)
        self.back = Gtk.Button(label="Back")
        self.back.connect("clicked", lambda *_: self.go_back())
        header.pack_start(self.back)
        self.next = Gtk.Button(label="Continue")
        self.next.get_style_context().add_class("suggested-action")
        self.next.connect("clicked", lambda *_: self.go_on())
        header.pack_end(self.next)
        menus.add_actions(self, {"close": self.close, "choose-folder": self.choose_folder,
                                 "look-again": self.load_sources})

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.add(self.stack)
        self.source = None
        self.kinds = []
        self.sizes = {}
        self.measuring = None
        self.stop = threading.Event()
        self.copying = False
        self.settings_chosen = False
        self.checks = []
        self.result = None
        self.stack.add_named(self.source_page(), "source")
        self.stack.add_named(self.choose_page(), "choose")
        self.stack.add_named(self.progress_page(), "progress")
        self.stack.add_named(self.done_page(), "done")
        self._watch = volumes.watch(lambda: GLib.timeout_add(600, self._drives_changed))
        self.connect("destroy", self._gone)
        self.connect("delete-event", self._closing)
        self.show_all()
        self.load_sources()
        if folder:
            self.use(tender.folder_source(folder))
        else:
            self.show("source")

    def _gone(self, *_):
        self.stop.set()
        for handler in self._watch:
            volumes.monitor().disconnect(handler)

    def _closing(self, *_):
        if not self.copying:
            return False
        answer = alert.ask(self, "Stop bringing files over?",
                           "The files already copied stay. You can open Tender again to bring the rest; "
                           "it skips what's already here.",
                           [("Keep Going", Gtk.ResponseType.CANCEL), ("Stop", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.CANCEL)
        if answer == Gtk.ResponseType.OK:
            self.stop.set()
        return True

    def show(self, name):
        self.stack.set_visible_child_name(name)
        self.back.set_visible(name == "choose")
        self.next.set_visible(name in ("source", "choose", "done"))
        self.next.set_label({"source": "Continue", "choose": "Bring Over", "done": "Done"}.get(name, ""))
        self.update_buttons()

    def update_buttons(self):
        name = self.stack.get_visible_child_name()
        if name == "source":
            self.next.set_sensitive(self.source_list.get_selected_row() is not None)
        elif name == "choose":
            need, _count, counting = self.chosen_size()
            room = tender.free_space()
            enough = need <= room
            self.next.set_sensitive(bool(self.chosen()) and not counting and enough)
            words = "Counting…" if counting else store.size_words(need)
            self.total.set_text(f"Chosen: {words}    Free on this computer: {store.size_words(room)}")
            self.room_warning.set_visible(not counting and not enough)

    def go_back(self):
        if self.stack.get_visible_child_name() == "choose":
            self.stop.set()
            self.show("source")

    def go_on(self):
        name = self.stack.get_visible_child_name()
        if name == "source":
            row = self.source_list.get_selected_row()
            if row is not None:
                self.use(row.source)
        elif name == "choose":
            self.start()
        elif name == "done":
            self.close()

    # ---- 1. where the files are -------------------------------------------------
    def source_page(self):
        box = page("Bring your files over",
                   "Tender copies your documents, pictures, music and other files from your old "
                   "computer to this one. Plug in the drive with your Lifeboat backup, or your old "
                   "computer's disk, then choose it here.")
        self.source_list = Gtk.ListBox(activate_on_single_click=False)
        self.source_list.connect("row-selected", lambda *_: self.update_buttons())
        self.source_list.connect("row-activated", lambda _l, row: self.use(row.source))
        frame = Gtk.Frame()
        frame.add(self.source_list)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, propagate_natural_height=True,
                                      max_content_height=260)
        scroller.add(frame)
        box.pack_start(scroller, False, False, 0)
        self.no_sources = caption("No backups or old disks were found. Plug in the drive, and it shows here "
                                  "in a moment. A Windows PC's disk can be taken out and plugged in with a "
                                  "USB case, or read while it's still in this computer.")
        box.pack_start(self.no_sources, False, False, 0)
        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.START)
        again = Gtk.Button(label="Look Again")
        again.connect("clicked", lambda *_: self.load_sources())
        buttons.pack_start(again, False, False, 0)
        folder = Gtk.Button(label="Choose a Folder…")
        folder.connect("clicked", lambda *_: self.choose_folder())
        buttons.pack_start(folder, False, False, 0)
        box.pack_start(buttons, False, False, 0)
        box.pack_start(caption("Tender never deletes anything, here or on the drive, and never replaces a "
                               "file you already have: one with the same name is kept beside it."),
                       False, False, 0)
        return box

    def _drives_changed(self):
        if self.stack.get_visible_child_name() == "source":
            self.load_sources()
        return False

    def load_sources(self):
        volumes.mount_new(self)
        chosen = self.source_list.get_selected_row()
        keep = chosen.source["path"] if chosen is not None else None
        for child in self.source_list.get_children():
            self.source_list.remove(child)

        def find():
            found = []
            for mount in volumes.drives():
                root = volumes.path_of(mount)
                if root:
                    found += tender.sources_on(root, mount.get_name())
            return found

        def show(found):
            for source in found:
                self.source_list.add(self.source_row(source))
            self.source_list.show_all()
            self.no_sources.set_visible(not found)
            for row in self.source_list.get_children():
                if row.source["path"] == keep:
                    self.source_list.select_row(row)
            self.update_buttons()
            return False

        threading.Thread(target=lambda: GLib.idle_add(show, find()), daemon=True).start()

    def source_row(self, source):
        row = Gtk.ListBoxRow()
        row.source = source
        line = Gtk.Box(spacing=12)
        line.get_style_context().add_class("tender-row")
        line.pack_start(Gtk.Image.new_from_icon_name(ICONS.get(source["kind"], "folder"), Gtk.IconSize.DND),
                        False, False, 0)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title = Gtk.Label(label=source["title"], xalign=0)
        title.get_style_context().add_class("tender-row-title")
        words.pack_start(title, False, False, 0)
        words.pack_start(caption(source["detail"]), False, False, 0)
        line.pack_start(words, True, True, 0)
        row.add(line)
        return row

    def choose_folder(self):
        chooser = Gtk.FileChooserNative(title="Choose the Folder to Bring Over", transient_for=self,
                                        action=Gtk.FileChooserAction.SELECT_FOLDER, accept_label="Choose")
        if chooser.run() == Gtk.ResponseType.ACCEPT:
            path = chooser.get_filename()
            if path and os.path.realpath(path) == os.path.realpath(store.home()):
                alert.tell(self, "That's your home folder",
                           "Choose a folder from another drive or computer, such as an old home folder.")
            elif path:
                self.use(tender.folder_source(path))
        chooser.destroy()

    # ---- 2. what to bring -------------------------------------------------------
    def choose_page(self):
        box = page("Choose what to bring")
        self.from_label = caption("", "tender-lead")
        box.pack_start(self.from_label, False, False, 0)
        self.kind_list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        frame = Gtk.Frame()
        frame.add(self.kind_list)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, propagate_natural_height=True,
                                      max_content_height=300)
        scroller.add(frame)
        box.pack_start(scroller, False, False, 0)
        self.total = Gtk.Label(xalign=0)
        box.pack_start(self.total, False, False, 0)
        self.room_warning = caption("There isn't room for all of this on this computer. Untick something, "
                                    "or make room first.", "tender-warning")
        box.pack_start(self.room_warning, False, False, 0)
        self.settings_note = caption("Settings and app data replace this account's own: the desktop, Dials, "
                                     "your apps' settings and browser bookmarks. The ones replaced are kept in "
                                     "case you want them back. Log out and back in afterwards for them to "
                                     "take effect.")
        box.pack_start(self.settings_note, False, False, 0)
        return box

    def use(self, source):
        self.stop.set()
        self.source = source
        self.kinds = tender.kinds(source)
        self.sizes = {}
        for child in self.kind_list.get_children():
            self.kind_list.remove(child)
        detail = source["detail"]
        if detail.startswith("On "):
            detail = "on " + detail[3:]
        self.from_label.set_text(f"{source['title']}, {detail}"
                                 if source["kind"] != "folder" else f"From the folder {source['path']}")
        self.checks = []
        for kind in self.kinds:
            row = Gtk.ListBoxRow(activatable=False)
            line = Gtk.Box(spacing=12)
            line.get_style_context().add_class("tender-row")
            check = Gtk.CheckButton(active=not kind.get("settings"))
            check.kind = kind
            check.connect("toggled", lambda *_: self.update_buttons())
            line.pack_start(check, False, False, 0)
            line.pack_start(Gtk.Image.new_from_icon_name(kind["icon"], Gtk.IconSize.LARGE_TOOLBAR),
                            False, False, 0)
            words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
            title = Gtk.Label(label=kind["title"], xalign=0)
            title.get_style_context().add_class("tender-row-title")
            words.pack_start(title, False, False, 0)
            if kind["key"] == "other":
                names = kind["names"]
                text = ", ".join(names[:4]) + (f" and {len(names) - 4} more" if len(names) > 4 else "")
                words.pack_start(caption(text), False, False, 0)
            elif self.source["kind"] == "windows" and len(kind["copies"]) > 1:
                words.pack_start(caption("Including what's in OneDrive on that PC"), False, False, 0)
            line.pack_start(words, True, True, 0)
            size = Gtk.Label(label="Counting…", xalign=1)
            size.get_style_context().add_class("tender-size")
            line.pack_end(size, False, False, 0)
            check.size_label = size
            row.add(line)
            self.kind_list.add(row)
            self.checks.append(check)
        self.kind_list.show_all()
        self.settings_note.set_visible(any(k.get("settings") for k in self.kinds))
        if not self.kinds:
            self.kind_list.add(Gtk.Label(label="There's nothing here to bring over.", margin=16))
            self.kind_list.show_all()
        self.show("choose")
        self.measure()

    def measure(self):
        self.stop = stop = threading.Event()
        windows = self.source["kind"] == "windows"
        checks = list(self.checks)

        def work():
            for check in checks:
                if stop.is_set():
                    return
                size, count = tender.measure(check.kind, windows, stop.is_set)
                if not stop.is_set():
                    GLib.idle_add(self._measured, check, size, count)

        threading.Thread(target=work, daemon=True).start()

    def _measured(self, check, size, count):
        self.sizes[check.kind["key"]] = (size, count)
        check.size_label.set_text(f"{store.size_words(size)}, {plural(count, 'file')}" if count else "Empty")
        if not count:
            check.set_active(False)
            check.set_sensitive(False)
        self.update_buttons()
        return False

    def chosen(self):
        return [c.kind for c in getattr(self, "checks", []) if c.get_active()]

    def chosen_size(self):
        need = count = 0
        counting = False
        for kind in self.chosen():
            if kind["key"] not in self.sizes:
                counting = True
                continue
            need += self.sizes[kind["key"]][0]
            count += self.sizes[kind["key"]][1]
        return need, count, counting

    # ---- 3. copying ---------------------------------------------------------------
    def progress_page(self):
        box = page("Bringing your files over")
        self.progress_text = caption("", "tender-lead")
        box.pack_start(self.progress_text, False, False, 0)
        self.bar = Gtk.ProgressBar()
        box.pack_start(self.bar, False, False, 0)
        self.now_file = caption("")
        self.now_file.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        self.now_file.set_line_wrap(False)
        box.pack_start(self.now_file, False, False, 0)
        stop = Gtk.Button(label="Stop", halign=Gtk.Align.START)
        stop.connect("clicked", lambda *_: self._closing())
        box.pack_start(stop, False, False, 0)
        box.pack_start(caption("You can keep using the computer while this goes on."), False, False, 0)
        return box

    def start(self):
        chosen = self.chosen()
        need, count, _counting = self.chosen_size()
        self.stop = stop = threading.Event()
        self.copying = True
        self.settings_chosen = any(k.get("settings") for k in chosen)
        self.progress_text.set_text(f"Copying {plural(count, 'file')} ({store.size_words(need)}) from "
                                    f"{self.source['title']}.")
        self.bar.set_fraction(0)
        self.show("progress")
        windows = self.source["kind"] == "windows"

        def progress(done, path):
            GLib.idle_add(self._progress, done, need, path)

        def work():
            try:
                result = tender.bring(chosen, windows, progress, stop.is_set)
            except OSError as e:
                result = tender.Result()
                result.failed.append(("", e.strerror or str(e)))
            GLib.idle_add(self._finished, result)

        threading.Thread(target=work, daemon=True).start()

    def _progress(self, done, need, path):
        self.bar.set_fraction(min(1.0, done / need) if need else 1.0)
        self.now_file.set_text(os.path.basename(path) if path else "")
        return False

    def _finished(self, result):
        self.copying = False
        self.result = result
        self.fill_done(result)
        self.show("done")
        return False

    # ---- 4. done ------------------------------------------------------------------
    def done_page(self):
        self.done_box = page("Your files are here")
        self.done_lines = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.done_box.pack_start(self.done_lines, False, False, 0)
        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.START)
        show = Gtk.Button(label="Show in Drawer")
        show.connect("clicked", lambda *_: subprocess.Popen(["freemac-drawer", store.home()],
                                                            start_new_session=True))
        buttons.pack_start(show, False, False, 0)
        self.again = Gtk.Button(label="Bring More…")
        self.again.connect("clicked", lambda *_: (self.load_sources(), self.show("source")))
        buttons.pack_start(self.again, False, False, 0)
        self.logout = Gtk.Button(label="Log Out…")
        self.logout.connect("clicked", lambda *_: subprocess.Popen(["freemac-power", "logout"],
                                                                   start_new_session=True))
        buttons.pack_start(self.logout, False, False, 0)
        self.done_box.pack_start(buttons, False, False, 0)
        return self.done_box

    def fill_done(self, r):
        for child in self.done_lines.get_children():
            self.done_lines.remove(child)
        title = self.done_box.get_children()[0]
        title.set_text("Bringing files over was stopped" if r.stopped else
                       ("Some files couldn't be brought over" if r.failed else "Your files are here"))
        lines = []
        if r.copied:
            lines.append(f"{plural(r.copied, 'file')} ({store.size_words(r.bytes)}) came over.")
        elif not r.failed:
            lines.append("There was nothing new to bring: everything was already here.")
        if r.same and r.copied:
            lines.append(f"{plural(r.same, 'file was', 'files were')} already here, so they were left alone.")
        if r.renamed:
            lines.append(f"{plural(r.renamed, 'file has', 'files have')} the same name as one that was "
                         "already here, so both are kept: the one brought over has a number after its name.")
        if r.replaced:
            lines.append(f"{plural(r.replaced, 'setting was', 'settings were')} replaced. The ones from "
                         "before are kept in your home folder, in .local/share/freemac-tender.")
        if r.stopped:
            lines.append("Open Tender again to bring the rest; it skips what's already here.")
        for line in lines:
            self.done_lines.pack_start(caption(line, "tender-big"), False, False, 0)
        if r.failed:
            first = r.failed[:3]
            more = len(r.failed) - len(first)
            text = "\n".join(f"{os.path.basename(p) or 'Copying'}: {why}" for p, why in first)
            if more:
                text += f"\n…and {plural(more, 'other')}"
            self.done_lines.pack_start(caption(text, "tender-warning"), False, False, 0)
        if self.settings_chosen and r.copied:
            self.done_lines.pack_start(caption("Log out and back in for the settings to take effect.",
                                               "tender-big"), False, False, 0)
        self.done_lines.show_all()
        self.logout.set_visible(bool(self.settings_chosen and r.copied))


def menubar():
    return menus.menubar([
        ("_File", [[("Choose a Folder…", "win.choose-folder", "<Ctrl>o"),
                    ("Look Again", "win.look-again", "<Ctrl>r")],
                   [("Close Window", "win.close", "<Ctrl>w")]]),
    ])


class Tender(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        menus.add_actions(self, {"quit": self.quit})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        self.set_menubar(menubar())

    def do_activate(self):
        windows = self.get_windows()
        if windows:
            windows[0].present()
        else:
            Window(self).present()

    def do_open(self, files, _n, _hint):
        path = files[0].get_path() if files else None
        windows = self.get_windows()
        if windows and path and not windows[0].copying:
            windows[0].use(tender.folder_source(path))
            windows[0].present()
        elif not windows:
            Window(self, folder=path).present()
        else:
            windows[0].present()


def main():
    GLib.set_prgname("freemac-tender")
    return Tender().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
