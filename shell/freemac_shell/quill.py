# SPDX-License-Identifier: GPL-3.0-or-later
"""Quill: freemac's text editor.

One document per window. Syntax colours and line numbers come from
GtkSourceView; the colour scheme follows freemac's light/dark setting.
Keys: Ctrl+N new, Ctrl+O open, Ctrl+S save, Ctrl+Shift+S save as, Ctrl+F find,
Ctrl+H replace, Ctrl+G next match, Ctrl+L go to line, Ctrl+= / Ctrl+- text
size, Ctrl+W close.

Quill also publishes a File / Edit / View menu bar. On freemac Topline shows it
at the top of the screen (Strata passes on where to find it); elsewhere GTK
shows it in the window.
"""
import os
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkSource", "4")
from gi.repository import Gdk, Gio, GLib, Gtk, GtkSource  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Quill"
LIGHT_SCHEME, DARK_SCHEME = "classic", "oblivion"


def scheme_for(dark):
    manager = GtkSource.StyleSchemeManager.get_default()
    return manager.get_scheme(DARK_SCHEME if dark else LIGHT_SCHEME) or manager.get_scheme("classic")


def guess_language(path, content_type):
    manager = GtkSource.LanguageManager.get_default()
    language = manager.guess_language(path, content_type)
    if language and language.get_id() == "python":
        language = manager.get_language("python3") or language
    return language


class Editor(Gtk.ApplicationWindow):
    def __init__(self, app, path=None):
        super().__init__(application=app, title="Untitled")
        self.set_default_size(820, 620)
        self.path = None
        self.font_size = 11

        header = Gtk.HeaderBar(show_close_button=True)
        self.set_titlebar(header)
        open_button = Gtk.Button(label="Open")
        open_button.connect("clicked", lambda *_: self.open_dialog())
        header.pack_start(open_button)
        save = Gtk.Button(label="Save")
        save.get_style_context().add_class("suggested-action")
        save.connect("clicked", lambda *_: self.save())
        header.pack_end(save)
        header.pack_end(self._menu_button())
        self.header = header

        self.buffer = GtkSource.Buffer()
        self.buffer.set_highlight_matching_brackets(True)
        self.buffer.connect("modified-changed", lambda *_: self._update_title())
        self.view = GtkSource.View.new_with_buffer(self.buffer)
        self.view.set_show_line_numbers(True)
        self.view.set_highlight_current_line(True)
        self.view.set_auto_indent(True)
        self.view.set_tab_width(4)
        self.view.set_insert_spaces_instead_of_tabs(True)
        self.view.set_smart_home_end(GtkSource.SmartHomeEndType.BEFORE)
        self.view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.view.set_left_margin(6)
        self.view.set_top_margin(6)
        self._css = Gtk.CssProvider()
        self.view.get_style_context().add_provider(self._css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self._apply_font()

        self.search_settings = GtkSource.SearchSettings(wrap_around=True)
        self.search = GtkSource.SearchContext.new(self.buffer, self.search_settings)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(box)
        box.pack_start(self._find_bar(), False, False, 0)
        scroller = Gtk.ScrolledWindow()
        scroller.add(self.view)
        box.pack_start(scroller, True, True, 0)
        self.status = Gtk.Label(xalign=1, margin=4, margin_end=12)
        self.status.get_style_context().add_class("dim-label")
        box.pack_start(self.status, False, False, 0)
        self.buffer.connect("notify::cursor-position", lambda *_: self._update_status())

        self.connect("delete-event", self._on_delete)
        self.connect("key-press-event", self._on_key)
        self.follow_theme()
        if path:
            self.load(path)
        self._update_title()
        self._update_status()

    # --- widgets ---------------------------------------------------------
    def _menu_button(self):
        menu = Gio.Menu()
        menu.append("New Window", "app.new")
        menu.append("Save As…", "win.save-as")
        section = Gio.Menu()
        section.append("Find and Replace…", "win.replace")
        section.append("Go to Line…", "win.goto")
        section.append("Wrap Long Lines", "win.wrap")
        menu.append_section(None, section)
        button = Gtk.MenuButton()
        button.set_image(Gtk.Image.new_from_icon_name("open-menu-symbolic", Gtk.IconSize.BUTTON))
        button.set_menu_model(menu)
        self._add_actions()
        return button

    def _add_actions(self):
        """The window's actions, used by the header menu and the menu bar."""
        for name, callback in (("open", self.open_dialog),
                               ("save", self.save),
                               ("save-as", self.save_as),
                               ("close", self.close),
                               ("undo", lambda: self.buffer.can_undo() and self.buffer.undo()),
                               ("redo", lambda: self.buffer.can_redo() and self.buffer.redo()),
                               ("cut", lambda: self._clipboard("cut")),
                               ("copy", lambda: self._clipboard("copy")),
                               ("paste", lambda: self._clipboard("paste")),
                               ("select-all", lambda: self._clipboard("select-all")),
                               ("find", lambda: self.show_find(False)),
                               ("replace", lambda: self.show_find(replace=True)),
                               ("find-next", self.find_next),
                               ("find-previous", self.find_previous),
                               ("goto", self.goto_line),
                               ("bigger", lambda: self.zoom(1)),
                               ("smaller", lambda: self.zoom(-1)),
                               ("actual-size", lambda: self.zoom(0))):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", lambda _a, _p, c=callback: c())
            self.add_action(action)
        wrap = Gio.SimpleAction.new_stateful("wrap", None, GLib.Variant("b", True))
        wrap.connect("change-state", self._toggle_wrap)
        self.add_action(wrap)

    def _clipboard(self, what):
        """Cut, copy, paste or select all in whatever has the keyboard: the
        find fields or the document."""
        focus = self.get_focus()
        if isinstance(focus, Gtk.Editable):
            if what == "select-all":
                focus.select_region(0, -1)
            else:
                getattr(focus, f"{what}_clipboard")()
        elif what == "select-all":
            self.view.emit("select-all", True)
        else:
            self.view.emit(f"{what}-clipboard")

    def _find_bar(self):
        self.revealer = Gtk.Revealer()
        grid = Gtk.Grid(column_spacing=6, row_spacing=6, margin=6)
        self.find_entry = Gtk.SearchEntry(placeholder_text="Find", hexpand=True)
        self.find_entry.connect("search-changed", self._find_changed)
        self.find_entry.connect("activate", lambda *_: self.find_next())
        self.find_entry.connect("stop-search", lambda *_: self.hide_find())
        grid.attach(self.find_entry, 0, 0, 1, 1)
        for i, (label, callback) in enumerate((("Previous", self.find_previous), ("Next", self.find_next))):
            button = Gtk.Button(label=label)
            button.connect("clicked", lambda _b, c=callback: c())
            grid.attach(button, 1 + i, 0, 1, 1)
        self.case = Gtk.CheckButton(label="Match case")
        self.case.connect("toggled", lambda b: self.search_settings.set_case_sensitive(b.get_active()))
        grid.attach(self.case, 3, 0, 1, 1)
        self.matches = Gtk.Label()
        self.matches.get_style_context().add_class("dim-label")
        grid.attach(self.matches, 4, 0, 1, 1)
        self.replace_entry = Gtk.Entry(placeholder_text="Replace with", hexpand=True)
        self.replace_entry.connect("activate", lambda *_: self.replace_one())
        grid.attach(self.replace_entry, 0, 1, 1, 1)
        one = Gtk.Button(label="Replace")
        one.connect("clicked", lambda *_: self.replace_one())
        grid.attach(one, 1, 1, 1, 1)
        every = Gtk.Button(label="Replace All")
        every.connect("clicked", lambda *_: self.replace_all())
        grid.attach(every, 2, 1, 1, 1)
        self.replace_row = [self.replace_entry, one, every]
        self.revealer.add(grid)
        self.search.connect("notify::occurrences-count", lambda *_: self._show_count())
        return self.revealer

    # --- files -----------------------------------------------------------
    def load(self, path):
        try:
            with open(path, "rb") as f:
                raw = f.read()
        except OSError as err:
            self.alert(f"“{os.path.basename(path)}” couldn’t be opened.", str(err.strerror or err))
            return False
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            text = raw.decode("latin-1")
        self.buffer.begin_not_undoable_action()
        self.buffer.set_text(text)
        self.buffer.end_not_undoable_action()
        self.buffer.set_modified(False)
        self.buffer.place_cursor(self.buffer.get_start_iter())
        self.path = os.path.abspath(path)
        content_type, _uncertain = Gio.content_type_guess(path, raw[:4096])
        self.buffer.set_language(guess_language(path, content_type))
        Gtk.RecentManager.get_default().add_item(Gio.File.new_for_path(self.path).get_uri())
        self._update_title()
        return True

    def write(self, path):
        start, end = self.buffer.get_bounds()
        text = self.buffer.get_text(start, end, True)
        tmp = path + ".quill-tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(text)
            if os.path.exists(path):
                os.chmod(tmp, os.stat(path).st_mode & 0o7777)
            os.replace(tmp, path)
        except OSError as err:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            self.alert(f"“{os.path.basename(path)}” couldn’t be saved.", str(err.strerror or err))
            return False
        self.path = os.path.abspath(path)
        self.buffer.set_modified(False)
        if not self.buffer.get_language():
            self.buffer.set_language(guess_language(path, None))
        self._update_title()
        return True

    def save(self):
        return self.write(self.path) if self.path else self.save_as()

    def save_as(self):
        dialog = Gtk.FileChooserNative.new("Save As", self, Gtk.FileChooserAction.SAVE, "Save", "Cancel")
        dialog.set_do_overwrite_confirmation(True)
        if self.path:
            dialog.set_filename(self.path)
        else:
            dialog.set_current_name("Untitled.txt")
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            return self.write(dialog.get_filename())
        return False

    def open_dialog(self):
        dialog = Gtk.FileChooserNative.new("Open", self, Gtk.FileChooserAction.OPEN, "Open", "Cancel")
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            path = dialog.get_filename()
            if self.path is None and not self.buffer.get_modified():
                self.load(path)
            else:
                Editor(self.get_application(), path).show_all()

    # --- find and replace -------------------------------------------------
    def show_find(self, replace=False):
        bounds = self.buffer.get_selection_bounds()
        if bounds:
            self.find_entry.set_text(self.buffer.get_text(bounds[0], bounds[1], False))
        for widget in self.replace_row:
            widget.set_visible(replace)
        self.revealer.set_reveal_child(True)
        self.find_entry.grab_focus()

    def hide_find(self):
        self.revealer.set_reveal_child(False)
        self.search_settings.set_search_text(None)
        self.view.grab_focus()

    def _find_changed(self, entry):
        self.search_settings.set_search_text(entry.get_text() or None)
        self.find_next(from_start=True)

    def _show_count(self):
        count = self.search.get_occurrences_count()
        self.matches.set_text("" if count < 0 or not self.find_entry.get_text()
                              else "No matches" if count == 0 else f"{count} found")

    def find_next(self, from_start=False):
        insert = self.buffer.get_iter_at_mark(self.buffer.get_insert())
        if not from_start:
            bounds = self.buffer.get_selection_bounds()
            if bounds:
                insert = bounds[1]
        found, start, end, _wrapped = self.search.forward(insert)
        if found:
            self.buffer.select_range(start, end)
            self.view.scroll_to_iter(start, 0.2, False, 0, 0)
        return found

    def find_previous(self):
        insert = self.buffer.get_iter_at_mark(self.buffer.get_insert())
        found, start, end, _wrapped = self.search.backward(insert)
        if found:
            self.buffer.select_range(start, end)
            self.view.scroll_to_iter(start, 0.2, False, 0, 0)

    def replace_one(self):
        bounds = self.buffer.get_selection_bounds()
        if bounds:
            try:
                self.search.replace(bounds[0], bounds[1], self.replace_entry.get_text(), -1)
            except GLib.Error:
                pass
        self.find_next()

    def replace_all(self):
        if self.search_settings.get_search_text():
            self.search.replace_all(self.replace_entry.get_text(), -1)

    def goto_line(self):
        dialog = Gtk.Dialog(title="Go to Line", transient_for=self, modal=True)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Go", Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        spin = Gtk.SpinButton.new_with_range(1, max(1, self.buffer.get_line_count()), 1)
        spin.set_activates_default(True)
        spin.set_value(self.buffer.get_iter_at_mark(self.buffer.get_insert()).get_line() + 1)
        box = dialog.get_content_area()
        box.set_border_width(12)
        box.set_spacing(8)
        box.add(Gtk.Label(label=f"Line (1 to {self.buffer.get_line_count()})", xalign=0))
        box.add(spin)
        dialog.show_all()
        if dialog.run() == Gtk.ResponseType.OK:
            line = self.buffer.get_iter_at_line(int(spin.get_value()) - 1)
            self.buffer.place_cursor(line)
            self.view.scroll_to_iter(line, 0.2, True, 0, 0.3)
        dialog.destroy()
        self.view.grab_focus()

    # --- look ------------------------------------------------------------
    def follow_theme(self, dark=None):
        self.buffer.set_style_scheme(scheme_for(style.is_dark() if dark is None else dark))

    def _apply_font(self):
        self._css.load_from_data(
            f"textview {{ font-family: monospace; font-size: {self.font_size}pt; }}".encode())

    def _toggle_wrap(self, action, value):
        action.set_state(value)
        self.view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR if value.get_boolean() else Gtk.WrapMode.NONE)

    def _update_title(self):
        name = os.path.basename(self.path) if self.path else "Untitled"
        mark = "• " if self.buffer.get_modified() else ""
        self.set_title(f"{mark}{name}")
        self.header.set_title(f"{mark}{name}")
        self.header.set_subtitle(os.path.dirname(self.path).replace(os.path.expanduser("~"), "~", 1)
                                 if self.path else None)

    def _update_status(self):
        it = self.buffer.get_iter_at_mark(self.buffer.get_insert())
        lang = self.buffer.get_language()
        self.status.set_text(f"{lang.get_name() + '   ' if lang else 'Plain Text   '}"
                             f"Line {it.get_line() + 1}, Column {it.get_line_offset() + 1}")

    # --- keys and closing -------------------------------------------------
    def _on_key(self, _widget, event):
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        shift = event.state & Gdk.ModifierType.SHIFT_MASK
        if not ctrl:
            if event.keyval == Gdk.KEY_Escape and self.revealer.get_reveal_child():
                self.hide_find()
                return True
            return False
        key = Gdk.keyval_to_lower(event.keyval)
        actions = {
            Gdk.KEY_s: (lambda: self.save_as()) if shift else (lambda: self.save()),
            Gdk.KEY_o: self.open_dialog,
            Gdk.KEY_n: lambda: Editor(self.get_application()).show_all(),
            Gdk.KEY_f: lambda: self.show_find(False),
            Gdk.KEY_h: lambda: self.show_find(True),
            Gdk.KEY_g: (lambda: self.find_previous()) if shift else (lambda: self.find_next()),
            Gdk.KEY_l: self.goto_line,
            Gdk.KEY_w: self.close,
            Gdk.KEY_equal: lambda: self.zoom(1),
            Gdk.KEY_plus: lambda: self.zoom(1),
            Gdk.KEY_minus: lambda: self.zoom(-1),
            Gdk.KEY_0: lambda: self.zoom(0),
        }
        if key in actions:
            actions[key]()
            return True
        return False

    def zoom(self, step):
        self.font_size = 11 if step == 0 else max(6, min(48, self.font_size + step))
        self._apply_font()

    def _on_delete(self, *_args):
        if not self.buffer.get_modified():
            return False
        name = os.path.basename(self.path) if self.path else "Untitled"
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.WARNING,
                                   text=f"Save changes to “{name}” before closing?",
                                   secondary_text="If you don’t save, your changes will be lost.")
        dialog.add_buttons("Don’t Save", Gtk.ResponseType.REJECT, "Cancel", Gtk.ResponseType.CANCEL,
                           "Save", Gtk.ResponseType.ACCEPT)
        dialog.set_default_response(Gtk.ResponseType.ACCEPT)
        answer = dialog.run()
        dialog.destroy()
        if answer == Gtk.ResponseType.ACCEPT:
            return not self.save()
        return answer != Gtk.ResponseType.REJECT

    def alert(self, text, detail=""):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.ERROR,
                                   buttons=Gtk.ButtonsType.CLOSE, text=text, secondary_text=detail)
        dialog.run()
        dialog.destroy()


def menubar():
    """File, Edit and View. The editor window handles the keys itself."""
    return menus.menubar([
        ("_File", [
            [("New Window", "app.new", "<Ctrl>n"), ("Open…", "win.open", "<Ctrl>o")],
            [("Save", "win.save", "<Ctrl>s"), ("Save As…", "win.save-as", "<Ctrl><Shift>s")],
            [("Close Window", "win.close", "<Ctrl>w")],
        ]),
        ("_Edit", [
            [("Undo", "win.undo", "<Ctrl>z"), ("Redo", "win.redo", "<Ctrl><Shift>z")],
            [("Cut", "win.cut", "<Ctrl>x"), ("Copy", "win.copy", "<Ctrl>c"),
             ("Paste", "win.paste", "<Ctrl>v"), ("Select All", "win.select-all", "<Ctrl>a")],
            [("Find…", "win.find", "<Ctrl>f"), ("Find and Replace…", "win.replace", "<Ctrl>h"),
             ("Find Next", "win.find-next", "<Ctrl>g"), ("Find Previous", "win.find-previous", "<Ctrl><Shift>g")],
            [("Go to Line…", "win.goto", "<Ctrl>l")],
        ]),
        ("_View", [
            [("Wrap Long Lines", "win.wrap", None)],
            [("Bigger Text", "win.bigger", "<Ctrl>equal"), ("Smaller Text", "win.smaller", "<Ctrl>minus"),
             ("Actual Size", "win.actual-size", "<Ctrl>0")],
        ]),
    ])


class Quill(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        new = Gio.SimpleAction.new("new", None)
        new.connect("activate", lambda *_: Editor(self).show_all())
        self.add_action(new)
        self.set_menubar(menubar())
        settings = style.interface_settings()
        if settings:
            settings.connect("changed::color-scheme", lambda *_: self._retheme())
            self._settings = settings
        GtkSource.init()

    def _retheme(self):
        for window in self.get_windows():
            if isinstance(window, Editor):
                window.follow_theme()

    def do_activate(self):
        Editor(self).show_all()

    def do_open(self, files, _n, _hint):
        for f in files:
            path = f.get_path()
            if path:
                if not os.path.exists(path):
                    open(path, "a").close()
                Editor(self, path).show_all()


def main():
    Quill().run(sys.argv)


if __name__ == "__main__":
    main()
