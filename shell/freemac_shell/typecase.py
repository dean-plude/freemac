# SPDX-License-Identifier: GPL-3.0-or-later
"""Typecase: every font on the computer.

    freemac-typecase            browse the fonts: each family with all of its
                                styles, in a sample you can type
    freemac-typecase FILE...    a font file someone double-clicked: shows it,
                                with Install Font

A font you add is copied into ~/.local/share/fonts, where every app finds it.
Fonts you added can be removed again (they go to the Trash); the ones freemac
comes with stay. Original freemac code: it reads the font list from Pango and
fontconfig (fc-list, fc-scan, fc-cache).
"""
import os
import shutil
import subprocess
import sys
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gio, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Typecase"
USER_FONTS = os.path.join(GLib.get_user_data_dir(), "fonts")
FONT_TYPES = (".ttf", ".otf", ".ttc", ".otc", ".woff", ".woff2", ".pfb")
SAMPLE = "The quick brown fox jumps over the lazy dog."
CHARACTERS = "ABCDEFGHIJKLM\nNOPQRSTUVWXYZ\nabcdefghijklm\nnopqrstuvwxyz\n1234567890\n.,:;!?&@#%$€£()[]{}\"'*+-=/"
COLLECTIONS = (("all", "All Fonts"), ("mine", "My Fonts"), ("fixed", "Fixed Width"))


def font_files():
    """family -> files of that family, from fontconfig."""
    try:
        out = subprocess.run(["fc-list", "--format", "%{family[0]}\t%{file}\n"],
                             capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    files = {}
    for line in out.splitlines():
        family, _, path = line.partition("\t")
        if family and path:
            files.setdefault(family, set()).add(path)
    return files


def mine(path):
    home = os.path.expanduser("~")
    return path.startswith(USER_FONTS + os.sep) or path.startswith(os.path.join(home, ".fonts") + os.sep)


def scan(path):
    """(family, style) of a font file, or None when it isn't one."""
    try:
        out = subprocess.run(["fc-scan", "--format", "%{family[0]}\t%{style[0]}\n", path],
                             capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    first = out.splitlines()[0] if out.strip() else ""
    family, _, style_name = first.partition("\t")
    return (family, style_name) if family else None


def fonts_changed():
    """Tell this app's GTK that fontconfig has new fonts (other apps see them
    the next time they start)."""
    settings = Gtk.Settings.get_default()
    try:
        settings.set_property("gtk-fontconfig-timestamp", int(time.time()))
    except TypeError:
        pass


def face_key(face):
    """Lightest to heaviest, each upright style before its italic."""
    desc = face.describe()
    return (int(desc.get_stretch() != Pango.Stretch.NORMAL), int(desc.get_weight()),
            int(desc.get_style() != Pango.Style.NORMAL), face.get_face_name())


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Typecase")
        self.set_default_size(1040, 680)
        self.size = 36
        self.files = {}
        self.families = {}
        self.collection = "all"
        self.current = None
        self.pending = []    # files opened that aren't installed yet

        header = Gtk.HeaderBar(show_close_button=True, title="Typecase")
        self.set_titlebar(header)
        add = Gtk.Button.new_from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON)
        add.set_tooltip_text("Add fonts")
        add.set_action_name("win.add")
        header.pack_start(add)
        self.search = Gtk.SearchEntry(placeholder_text="Search")
        self.search.set_width_chars(22)
        self.search.connect("search-changed", lambda _e: self.fill_families())
        header.pack_end(self.search)
        self.sample = Gtk.Entry(placeholder_text="Type a sample")
        self.sample.set_width_chars(26)
        self.sample.connect("changed", lambda _e: self.show_family(self.current))
        header.pack_end(self.sample)

        panes = Gtk.Box()
        self.add(panes)
        # Collections
        self.collections = Gtk.ListBox()
        self.collections.get_style_context().add_class("sidebar")
        self.collections.set_size_request(170, -1)
        heading = Gtk.Label(label="COLLECTIONS", xalign=0)
        heading.get_style_context().add_class("dim-label")
        heading.set_margin_start(12)
        heading.set_margin_top(10)
        heading.set_margin_bottom(4)
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.get_style_context().add_class("sidebar")
        side.pack_start(heading, False, False, 0)
        for key, label in COLLECTIONS:
            row = Gtk.ListBoxRow()
            row.key = key
            text = Gtk.Label(label=label, xalign=0)
            text.set_margin_start(12)
            text.set_margin_top(5)
            text.set_margin_bottom(5)
            row.add(text)
            self.collections.add(row)
        self.collections.connect("row-selected", self._collection_selected)
        side.pack_start(self.collections, True, True, 0)
        panes.pack_start(side, False, False, 0)
        panes.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)
        # Families
        self.family_list = Gtk.ListBox()
        self.family_list.connect("row-selected", self._family_selected)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.set_size_request(230, -1)
        scroll.add(self.family_list)
        middle = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        middle.pack_start(scroll, True, True, 0)
        self.count = Gtk.Label(xalign=0.5)
        self.count.get_style_context().add_class("dim-label")
        self.count.set_margin_top(6)
        self.count.set_margin_bottom(6)
        middle.pack_start(Gtk.Separator(), False, False, 0)
        middle.pack_start(self.count, False, False, 0)
        panes.pack_start(middle, False, False, 0)
        panes.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)
        # Preview
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.banner = Gtk.InfoBar(message_type=Gtk.MessageType.INFO, show_close_button=True)
        self.banner_text = Gtk.Label(xalign=0, wrap=True)
        self.banner.get_content_area().add(self.banner_text)
        self.banner.add_button("Install Font", Gtk.ResponseType.OK)
        self.banner.connect("response", self._banner_answer)
        self.banner.set_no_show_all(True)
        right.pack_start(self.banner, False, False, 0)
        self.preview = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.preview.set_border_width(26)
        preview_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        preview_scroll.get_style_context().add_class("typecase-page")
        preview_scroll.add(self.preview)
        right.pack_start(preview_scroll, True, True, 0)
        bottom = Gtk.Box(spacing=8)
        bottom.set_border_width(8)
        small = Gtk.Label(label="A")
        big = Gtk.Label()
        big.set_markup("<span size='large'>A</span>")
        self.slider = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 9, 144, 1)
        self.slider.set_value(self.size)
        self.slider.set_draw_value(False)
        self.slider.set_size_request(220, -1)
        self.slider.connect("value-changed", self._size_changed)
        self.size_label = Gtk.Label(label=f"{self.size} pt")
        self.size_label.set_width_chars(7)
        self.remove_button = Gtk.Button(label="Remove Font…")
        self.remove_button.set_action_name("win.remove")
        bottom.pack_start(self.remove_button, False, False, 0)
        bottom.pack_end(self.size_label, False, False, 0)
        bottom.pack_end(big, False, False, 0)
        bottom.pack_end(self.slider, False, False, 0)
        bottom.pack_end(small, False, False, 0)
        right.pack_start(Gtk.Separator(), False, False, 0)
        right.pack_start(bottom, False, False, 0)
        panes.pack_start(right, True, True, 0)

        css = Gtk.CssProvider()
        css.load_from_data(b".typecase-page, .typecase-page viewport { background-color: @theme_base_color; }")
        self.get_style_context().add_provider_for_screen(self.get_screen(), css,
                                                         Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        menus.add_actions(self, {"add": self.add_fonts, "close": self.close,
                                 "find": self.search.grab_focus,
                                 "bigger": lambda: self.slider.set_value(min(144, self.size + 6)),
                                 "smaller": lambda: self.slider.set_value(max(9, self.size - 6)),
                                 "remove": self.remove_family})
        self.load()
        self.show_all()
        self.collections.select_row(self.collections.get_row_at_index(0))
        self.fill_families()

    # ------------------------------------------------------------ the list

    def load(self):
        self.files = font_files()
        fontmap = PangoCairo.FontMap.get_default()
        self.families = {f.get_name(): f for f in fontmap.list_families()}

    def _collection_selected(self, _box, row):
        if row:
            self.collection = row.key
            self.fill_families()

    def visible_families(self):
        words = self.search.get_text().lower().split()
        names = []
        for name, family in self.families.items():
            if self.files and name not in self.files:
                continue    # removed a moment ago: fontconfig no longer has it
            if self.collection == "mine" and not any(mine(p) for p in self.files.get(name, ())):
                continue
            if self.collection == "fixed" and not family.is_monospace():
                continue
            if name.lower() in ("sans", "serif", "monospace", "system-ui", "cursive", "fantasy", "emoji"):
                continue    # the generic names, not fonts of their own
            if all(w in name.lower() for w in words):
                names.append(name)
        return sorted(names, key=str.lower)

    def fill_families(self, select=None):
        keep = select or self.current
        for row in self.family_list.get_children():
            self.family_list.remove(row)
        names = self.visible_families()
        chosen = None
        for name in names:
            row = Gtk.ListBoxRow()
            row.family = name
            label = Gtk.Label(label=name, xalign=0, ellipsize=Pango.EllipsizeMode.END)
            label.set_margin_start(12)
            label.set_margin_end(8)
            label.set_margin_top(4)
            label.set_margin_bottom(4)
            row.add(label)
            self.family_list.add(row)
            if name == keep:
                chosen = row
        self.family_list.show_all()
        self.count.set_text(f"{len(names)} font{'s' if len(names) != 1 else ''}")
        row = chosen or self.family_list.get_row_at_index(0)
        if row:
            self.family_list.select_row(row)
            if chosen:
                GLib.idle_add(lambda: row.get_parent() is not None and row.grab_focus() and False)
        else:
            self.show_family(None)

    def _family_selected(self, _box, row):
        self.show_family(row.family if row else None)

    # ------------------------------------------------------------ the preview

    def _size_changed(self, scale):
        self.size = int(scale.get_value())
        self.size_label.set_text(f"{self.size} pt")
        self.show_family(self.current)

    def show_family(self, name):
        self.current = name
        for child in self.preview.get_children():
            self.preview.remove(child)
        family = self.families.get(name) if name else None
        files = self.files.get(name, set()) if name else set()
        self.remove_button.set_visible(bool(files) and all(mine(p) for p in files))
        if family is None:
            empty = Gtk.Label(label="No fonts match." if self.search.get_text() else "No fonts here yet.")
            empty.get_style_context().add_class("dim-label")
            empty.set_vexpand(True)
            self.preview.pack_start(empty, True, True, 0)
            self.preview.show_all()
            return
        faces = sorted(family.list_faces(), key=face_key)
        title = Gtk.Label(xalign=0)
        title.set_markup(f"<span size='22000' weight='700'>{GLib.markup_escape_text(name)}</span>")
        self.preview.pack_start(title, False, False, 0)
        facts = [f"{len(faces)} style{'s' if len(faces) != 1 else ''}"]
        if family.is_monospace():
            facts.append("fixed width")
        if files:
            facts.append("added by you" if all(mine(p) for p in files) else "comes with freemac")
        info = Gtk.Label(label=" · ".join(facts), xalign=0)
        info.get_style_context().add_class("dim-label")
        info.set_margin_bottom(18)
        self.preview.pack_start(info, False, False, 0)
        text = self.sample.get_text() or SAMPLE
        for face in faces:
            caption = Gtk.Label(label=face.get_face_name(), xalign=0)
            caption.get_style_context().add_class("dim-label")
            caption.set_margin_top(6)
            self.preview.pack_start(caption, False, False, 0)
            self.preview.pack_start(self._specimen(face.describe(), text), False, False, 0)
        heading = Gtk.Label(label="Characters", xalign=0)
        heading.get_style_context().add_class("dim-label")
        heading.set_margin_top(22)
        self.preview.pack_start(heading, False, False, 0)
        self.preview.pack_start(self._specimen(faces[0].describe() if faces else None, CHARACTERS,
                                               size=max(18, min(self.size, 48))), False, False, 0)
        self.preview.show_all()

    def _specimen(self, desc, text, size=None):
        label = Gtk.Label(label=text, xalign=0, wrap=True, selectable=True)
        label.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
        attrs = Pango.AttrList()
        if desc is not None:
            desc = desc.copy()
            desc.set_size(int((size or self.size) * Pango.SCALE))
            attrs.insert(Pango.attr_font_desc_new(desc))
        attrs.insert(Pango.attr_fallback_new(False))
        label.set_attributes(attrs)
        return label

    # ------------------------------------------------------------ adding and removing

    def add_fonts(self):
        chooser = Gtk.FileChooserNative.new("Add Fonts", self, Gtk.FileChooserAction.OPEN, "Add", "Cancel")
        chooser.set_select_multiple(True)
        found = Gtk.FileFilter()
        found.set_name("Fonts")
        for ending in FONT_TYPES:
            found.add_pattern("*" + ending)
            found.add_pattern("*" + ending.upper())
        chooser.add_filter(found)
        if chooser.run() == Gtk.ResponseType.ACCEPT:
            self.install([f.get_path() for f in chooser.get_files() if f.get_path()])
        chooser.destroy()

    def install(self, paths):
        os.makedirs(USER_FONTS, exist_ok=True)
        added, problems = [], []
        for path in paths:
            what = scan(path)
            if not what:
                problems.append(os.path.basename(path))
                continue
            target = os.path.join(USER_FONTS, os.path.basename(path))
            try:
                if os.path.abspath(path) != os.path.abspath(target):
                    shutil.copyfile(path, target)
            except OSError:
                problems.append(os.path.basename(path))
                continue
            added.append(what[0])
        if added:
            self.refresh_fonts(added[0])
        if problems:
            self.tell("Some files couldn't be added",
                      "These aren't fonts Typecase can read: " + ", ".join(problems))

    def refresh_fonts(self, select=None):
        try:
            subprocess.run(["fc-cache", "-f", USER_FONTS], timeout=60, capture_output=True)
        except (OSError, subprocess.SubprocessError):
            pass
        fonts_changed()
        self.load()
        self.fill_families(select=select)

    def remove_family(self):
        name = self.current
        files = sorted(self.files.get(name, ()))
        if not files or not all(mine(p) for p in files):
            return
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
                                   text=f"Remove “{name}”?")
        dialog.format_secondary_text("Its files go to the Trash. Documents that use it show "
                                     "another font instead.")
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Remove", Gtk.ResponseType.OK).get_style_context().add_class("destructive-action")
        answer = dialog.run()
        dialog.destroy()
        if answer != Gtk.ResponseType.OK:
            return
        for path in files:
            try:
                Gio.File.new_for_path(path).trash(None)
            except GLib.Error:
                pass
        self.current = None
        self.refresh_fonts()

    def open_files(self, paths):
        """Font files someone opened: show the ones already here, offer to
        install the rest."""
        self.pending = []
        first = None
        for path in paths:
            what = scan(path)
            if not what:
                continue
            if what[0] in self.families:
                first = first or what[0]
            else:
                self.pending.append((path, what[0]))
        if self.pending:
            names = sorted({family for _p, family in self.pending})
            self.banner_text.set_markup(
                f"<b>{GLib.markup_escape_text(', '.join(names))}</b> isn't installed yet. "
                "Install it to use it in every app.")
            self.banner_text.show()
            self.banner.show()
        if first:
            self.search.set_text("")
            self.collections.select_row(self.collections.get_row_at_index(0))
            self.fill_families(select=first)
        elif paths and not self.pending:
            self.tell("This isn't a font", "Typecase can't read " + os.path.basename(paths[0]) + ".")

    def _banner_answer(self, bar, answer):
        bar.hide()
        if answer == Gtk.ResponseType.OK and self.pending:
            paths = [p for p, _f in self.pending]
            self.pending = []
            self.search.set_text("")
            self.collections.select_row(self.collections.get_row_at_index(0))
            self.install(paths)

    def tell(self, text, more):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK, text=text)
        dialog.format_secondary_text(more)
        dialog.run()
        dialog.destroy()

    def about(self):
        self.tell("About Typecase", "Typecase is part of freemac. It shows every font on this computer, "
                                    "and adds and removes your own.")


def menubar():
    return menus.menubar([
        ("_File", [[("Add Fonts…", "win.add", "<Ctrl>o")], [("Remove Font…", "win.remove", None)],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Find", "win.find", "<Ctrl>f")]]),
        ("_View", [[("Bigger", "win.bigger", "<Ctrl>plus"), ("Smaller", "win.smaller", "<Ctrl>minus")]]),
    ])


class Typecase(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close(),
                                 "about": lambda: self.window and self.window.about()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.add", "<Control>o"), ("win.close", "<Control>w"), ("win.find", "<Control>f"),
                             ("win.bigger", "<Control>plus"), ("win.smaller", "<Control>minus")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def _window(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()
        return self.window

    def do_activate(self):
        self._window()

    def do_open(self, files, _n, _hint):
        window = self._window()
        window.open_files([f.get_path() for f in files if f.get_path()])


def main():
    GLib.set_prgname("freemac-typecase")
    return Typecase().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
