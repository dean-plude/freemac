# SPDX-License-Identifier: GPL-3.0-or-later
"""Accessibility Shortcuts, as on a Mac: press Option-Command-F5 anywhere for
a small panel of the accessibility features, each turned on or off with a
click (or the arrow keys and Space), then Done.

Which features the panel lists is chosen in Dials > Accessibility >
Shortcut (shell.json "accessibility_shortcuts"). With only one chosen, the
keys turn that one on or off at once, with no panel, as a Mac does.

    freemac-accessibility-shortcuts            the panel (Option-Command-F5)
    freemac-accessibility-shortcuts --list     what each feature is set to

Each feature is the same setting Dials changes, so the panel, Dials and the
features' own keys (Command-F5, Shift five times) always agree. Original
freemac code.
"""
import os
import sys

from . import style
from .ini import ini_get, ini_set

APP_ID = "org.freemac.AccessibilityShortcuts"
WAYFIRE_INI = os.path.expanduser("~/.config/wayfire.ini")
INVERT_KEY = "<ctrl> <alt> <super> KEY_8"
PREF = "accessibility_shortcuts"


def _truthy(value, default):
    return (value or default).strip().lower() not in ("false", "0", "no", "off")


def _strata(key, path=None):
    """(is it on, turn it on or off) for a strata-shell switch."""
    path = path or WAYFIRE_INI
    return (lambda: _truthy(ini_get(path, "strata-shell", key, "false"), "false"),
            lambda on: ini_set(path, "strata-shell", key, "true" if on else "false"))


def _plugins(path):
    return (ini_get(path, "core", "plugins", "") or "").split()


def _plugin(name, path=None, first=None):
    """(is it on, turn it on or off) for a Wayfire plugin, as Dials does."""
    path = path or WAYFIRE_INI

    def turn(on):
        if first:
            first()
        names = [n for n in _plugins(path) if n != name]
        if on:
            names.append(name)
        ini_set(path, "core", "plugins", " ".join(names))
    return (lambda: name in _plugins(path), turn)


def _pref(key):
    return (lambda: bool(style.prefs().get(key, False)), lambda on: style.save_prefs(**{key: bool(on)}))


def _colour_filters(path=None):
    """On is the filter chosen last in Dials (greys if none was), and off
    keeps that choice for next time."""
    path = path or WAYFIRE_INI

    def current():
        return (ini_get(path, "strata-shell", "colour_filter", "none") or "none").strip()

    def turn(on):
        now = current()
        if on:
            chosen = style.prefs().get("colour_filter_last") or "greyscale"
            ini_set(path, "strata-shell", "colour_filter", chosen if chosen != "none" else "greyscale")
        else:
            if now != "none":
                style.save_prefs(colour_filter_last=now)
            ini_set(path, "strata-shell", "colour_filter", "none")
    return (lambda: current() != "none", turn)


def _contrast():
    def theme():
        settings = style.interface_settings()
        return settings, (settings.get_string("gtk-theme") if settings else "")

    def turn(on):
        settings, _name = theme()
        if not settings:
            return
        if on:
            settings.set_string("gtk-theme", "HighContrast")
        else:
            from .dials import theme_for   # the accent colour's theme, as Dials picks it
            settings.set_string("gtk-theme", theme_for(style.is_dark()))
    return (lambda: theme()[1] == "HighContrast", turn)


def _reader():
    from . import screen_reader
    return (lambda: screen_reader.running() or screen_reader.wanted(), screen_reader.set_on)


def features(path=None):
    """[(id, name, is on, turn on or off)] for every feature this computer has,
    in a Mac's order."""
    path = path or WAYFIRE_INI
    from . import livetext, screen_reader
    out = []
    if screen_reader.available():
        out.append(("screen_reader", "Screen Reader", *_reader()))
    out += [
        ("zoom", "Zoom", *_plugin("zoom", path)),
        ("sticky_keys", "Sticky Keys", *_strata("sticky_keys", path)),
        ("slow_keys", "Slow Keys", *_strata("slow_keys", path)),
        ("mouse_keys", "Mouse Keys", *_strata("mouse_keys", path)),
        ("accessibility_keyboard", "Accessibility Keyboard", *_pref("accessibility_keyboard")),
    ]
    if livetext.available():
        out.append(("hover_text", "Hover Text", *_strata("hover_text", path)))
    out += [
        ("invert", "Invert Colours", *_plugin("invert", path,
                                              first=lambda: ini_set(path, "invert", "toggle", INVERT_KEY))),
        ("colour_filters", "Colour Filters", *_colour_filters(path)),
        ("contrast", "Increase Contrast", *_contrast()),
        ("reduce_transparency", "Reduce Transparency", *_pref("reduce_transparency")),
    ]
    return out


def chosen(all_features=None):
    """The features the panel lists: those picked in Dials, in order, or all."""
    all_features = features() if all_features is None else all_features
    picked = style.prefs().get(PREF)
    if not isinstance(picked, list):
        return all_features
    return [f for f in all_features if f[0] in picked]


def run_panel(argv):
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gio, GLib, Gtk

    class Panel(Gtk.ApplicationWindow):
        def __init__(self, app):
            super().__init__(application=app, title="Accessibility Shortcuts")
            self.set_resizable(False)
            self.set_keep_above(True)
            self.set_position(Gtk.WindowPosition.CENTER)
            self.set_default_size(320, -1)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=16)
            title = Gtk.Label(xalign=0)
            title.set_markup("<b>Accessibility Shortcuts</b>")
            box.pack_start(title, False, False, 0)
            hint = Gtk.Label(label="Click a feature to turn it on or off.", xalign=0, wrap=True,
                             max_width_chars=40)
            hint.get_style_context().add_class("dim-label")
            box.pack_start(hint, False, False, 0)
            frame = Gtk.Frame()
            self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
            self.list.connect("row-activated", self._activated)
            frame.add(self.list)
            box.pack_start(frame, False, False, 0)
            buttons = Gtk.Box(spacing=8)
            settings = Gtk.Button(label="Accessibility Settings…")
            settings.connect("clicked", self._settings)
            buttons.pack_start(settings, False, False, 0)
            done = Gtk.Button(label="Done")
            done.get_style_context().add_class("suggested-action")
            done.connect("clicked", lambda _b: self.close())
            buttons.pack_end(done, False, False, 0)
            box.pack_start(buttons, False, False, 0)
            self.add(box)
            self.fill()
            box.show_all()
            # Command-F5 or Shift five times can change a feature while it's open.
            self._timer = GLib.timeout_add(1000, self._tick)
            self.connect("destroy", lambda *_: GLib.source_remove(self._timer))

        def fill(self):
            for row in self.list.get_children():
                self.list.remove(row)
            for ident, name, is_on, turn in chosen():
                row = Gtk.ListBoxRow()
                row.feature = (ident, is_on, turn)
                line = Gtk.Box(spacing=8, margin=7)
                mark = Gtk.Label(label="\u2713", width_chars=2)
                row.mark = mark
                line.pack_start(mark, False, False, 0)
                line.pack_start(Gtk.Label(label=name, xalign=0), True, True, 0)
                row.add(line)
                self.list.add(row)
                self._show(row)
            first = self.list.get_row_at_index(0)
            if first is not None:
                self.list.select_row(first)
                first.grab_focus()
            self.list.show_all()

        def _show(self, row):
            try:
                on = row.feature[1]()
            except Exception:   # a feature that can't say stays shown as off
                on = False
            if getattr(row, "on", None) == on:
                return
            row.on = on
            # The mark stays in place, unseen, so the row keeps its look.
            row.mark.set_opacity(1.0 if on else 0.0)
            row.get_accessible().set_description("on" if on else "off")

        def _tick(self):
            for row in self.list.get_children():
                self._show(row)
            return True

        def _activated(self, _list, row):
            row.feature[2](not row.on)
            self._show(row)

        def _settings(self, _button):
            Gio.Subprocess.new(["freemac-dials", "--panel", "accessibility"], Gio.SubprocessFlags.NONE)
            self.close()

    GLib.set_prgname("freemac-accessibility-shortcuts")

    class App(Gtk.Application):
        def __init__(self):
            super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
            self.window = None

        def do_startup(self):
            Gtk.Application.do_startup(self)
            style.apply()
            close = Gio.SimpleAction.new("close", None)
            close.connect("activate", lambda *_: self.window and self.window.close())
            self.add_action(close)
            self.set_accels_for_action("app.close", ["<Control>w", "Escape"])

        def do_activate(self):
            if self.window is None:
                self.window = Panel(self)
                self.window.connect("destroy", lambda *_: setattr(self, "window", None))
            self.window.present()

    return App().run(argv[:1])


def main(argv=None):
    argv = sys.argv if argv is None else argv
    if "--list" in argv[1:]:
        for ident, name, is_on, _turn in features():
            print(f"{ident}\t{'on' if is_on() else 'off'}\t{name}")
        return 0
    listed = chosen()
    if len(listed) == 1:
        # One feature chosen: the keys turn it on or off straight away.
        _ident, _name, is_on, turn = listed[0]
        turn(not is_on())
        return 0
    if not listed:
        return 0
    return run_panel(argv)


if __name__ == "__main__":
    sys.exit(main())
