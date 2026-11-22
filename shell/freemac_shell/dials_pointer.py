# SPDX-License-Identifier: GPL-3.0-or-later
"""Pointer colours, as on a Mac (Dials > Accessibility > Pointer outline
colour and Pointer fill colour): the pointer in colours that are easier to
see, or just more fun.

freemac's pointer is drawn from scratch by make-cursors.py, which the image
keeps in /usr/share/freemac. Choosing colours runs it again into a theme of
the person's own in ~/.icons, named after the colours (a new name is what
makes Wayfire and apps load it afresh), and switches to it: Wayfire's
[input] cursor_theme, GTK's cursor-theme, and Strata's pointer_fill and
pointer_outline, so the big pointer that a shake shows matches. Reset goes
back to the "freemac" theme. The choices are in shell.json as
"pointer_fill" and "pointer_outline". Original freemac code.
"""
import os
import shutil

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402

from . import style  # noqa: E402

MAKER = "/usr/share/freemac/make-cursors.py"
ICONS = os.path.join(GLib.get_home_dir(), ".icons")
PREFIX = "freemac-pointer-"
DEFAULT_THEME = "freemac"
DEFAULT_FILL = "#000000"
DEFAULT_OUTLINE = "#ffffff"


def hex_colour(text, default):
    text = (text or "").strip().lower()
    if len(text) == 7 and text[0] == "#" and all(c in "0123456789abcdef" for c in text[1:]):
        return text
    return default


def chosen(prefs=None):
    """(fill, outline) as #rrggbb."""
    prefs = style.prefs() if prefs is None else prefs
    return (hex_colour(prefs.get("pointer_fill"), DEFAULT_FILL),
            hex_colour(prefs.get("pointer_outline"), DEFAULT_OUTLINE))


def theme_name(fill, outline):
    """The theme for these colours: freemac's own for its own colours."""
    if (fill, outline) == (DEFAULT_FILL, DEFAULT_OUTLINE):
        return DEFAULT_THEME
    return PREFIX + fill[1:] + outline[1:]


def wayfire_colour(hex_text):
    """'#ff8800' as Wayfire's '1.000 0.533 0.000 1.0'."""
    r, g, b = (int(hex_text[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return f"{r:.3f} {g:.3f} {b:.3f} 1.0"


def to_hex(rgba):
    return "#{:02x}{:02x}{:02x}".format(*(max(0, min(255, round(v * 255))) for v in
                                         (rgba.red, rgba.green, rgba.blue)))


def to_rgba(hex_text):
    rgba = Gdk.RGBA()
    rgba.parse(hex_text)
    return rgba


def drawn(name):
    return name == DEFAULT_THEME or os.path.exists(os.path.join(ICONS, name, "cursors", "default"))


def tidy(keep):
    """Themes drawn for colours no longer chosen go."""
    try:
        names = os.listdir(ICONS)
    except OSError:
        return
    for name in names:
        if name.startswith(PREFIX) and name != keep:
            shutil.rmtree(os.path.join(ICONS, name), ignore_errors=True)


class Pointer:
    """Draws the pointer in the chosen colours and switches to it."""

    def __init__(self, window, on_busy=None):
        self.window = window
        self.on_busy = on_busy or (lambda busy: None)
        self.process = None
        self.wanted = None

    def use(self, fill, outline):
        self.window.save_prefs(pointer_fill=fill, pointer_outline=outline)
        name = theme_name(fill, outline)
        self.wanted = (name, fill, outline)
        if drawn(name):
            self._switch(name, fill, outline)
            return
        if self.process is not None:
            return          # the drawing under way picks up self.wanted when it ends
        self._draw(name, fill, outline)

    def _draw(self, name, fill, outline):
        if not os.path.exists(MAKER):
            return
        os.makedirs(ICONS, exist_ok=True)
        temporary = os.path.join(ICONS, "." + name + ".new")
        shutil.rmtree(temporary, ignore_errors=True)
        try:
            self.process = Gio.Subprocess.new(
                ["python3", MAKER, temporary, "--fill", fill, "--outline", outline, "--name", name],
                Gio.SubprocessFlags.STDERR_SILENCE)
        except GLib.Error:
            self.process = None
            return
        self.on_busy(True)
        self.process.wait_check_async(None, self._drawn, (name, fill, outline, temporary))

    def _drawn(self, process, result, job):
        name, fill, outline, temporary = job
        self.process = None
        try:
            ok = process.wait_check_finish(result)
        except GLib.Error:
            ok = False
        if ok:
            final = os.path.join(ICONS, name)
            shutil.rmtree(final, ignore_errors=True)
            os.replace(temporary, final)
        else:
            shutil.rmtree(temporary, ignore_errors=True)
        wanted = self.wanted
        if wanted and wanted[0] != name and not drawn(wanted[0]):
            self._draw(*wanted)     # other colours were picked meanwhile
            return
        self.on_busy(False)
        if wanted and drawn(wanted[0]):
            self._switch(*wanted)

    def _switch(self, name, fill, outline):
        self.window.ini_set("input", "cursor_theme", name)
        self.window.ini_set("strata-shell", "pointer_fill", wayfire_colour(fill))
        self.window.ini_set("strata-shell", "pointer_outline", wayfire_colour(outline))
        source = Gio.SettingsSchemaSource.get_default()
        if source and source.lookup("org.gnome.desktop.interface", True):
            Gio.Settings.new("org.gnome.desktop.interface").set_string("cursor-theme", name)
        tidy(name)


def rows(window, row):
    """Dials' Pointer outline colour and Pointer fill colour rows, with Reset."""
    fill, outline = chosen()
    fill_button = Gtk.ColorButton(rgba=to_rgba(fill), use_alpha=False, title="Pointer Fill Colour")
    outline_button = Gtk.ColorButton(rgba=to_rgba(outline), use_alpha=False, title="Pointer Outline Colour")
    reset = Gtk.Button(label="Reset")
    note = Gtk.Label(label="", xalign=0)
    note.get_style_context().add_class("dim-label")

    def busy(on):
        note.set_text("Drawing the pointer…" if on else "")

    pointer = Pointer(window, busy)

    def picked(_button):
        pointer.use(to_hex(fill_button.get_rgba()), to_hex(outline_button.get_rgba()))

    def reset_colours(_button):
        fill_button.set_rgba(to_rgba(DEFAULT_FILL))
        outline_button.set_rgba(to_rgba(DEFAULT_OUTLINE))
        pointer.use(DEFAULT_FILL, DEFAULT_OUTLINE)

    fill_button.connect("color-set", picked)
    outline_button.connect("color-set", picked)
    reset.connect("clicked", reset_colours)
    tools = Gtk.Box(spacing=8)
    tools.pack_start(note, False, False, 0)
    tools.pack_start(reset, False, False, 0)
    return [row("Pointer outline colour", outline_button),
            row("Pointer fill colour", fill_button),
            row("Pointer colours", tools, "Colours that stand out make the pointer easier to see.")]
