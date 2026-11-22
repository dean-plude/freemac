# SPDX-License-Identifier: GPL-3.0-or-later
"""Clipboard history: the last things you copied, a key press away.

At login, `wl-paste --type text --watch freemac-clips --store` hands each
newly copied text to this module, which keeps the last KEEP of them in
~/.local/state/freemac/clips.json. Super+Shift+V (`freemac-clips`) opens a
small list to search; Enter or a click copies the chosen text again, ready to
paste.

Text that a password manager marks as secret (the x-kde-passwordManagerHint
type, or a password freemac's own apps copy and mark) is never kept, and nothing is kept while history is turned off in
Dials (the "clipboard_history" key in shell.json). The history stays on this
computer and Clear History empties it.
"""
import json
import os
import shutil
import subprocess
import sys
import time

from gi.repository import GLib

HISTORY = os.path.join(GLib.get_user_state_dir(), "freemac", "clips.json")
KEEP = 50
MAX_CHARS = 20000
SECRET_TYPES = ("x-kde-passwordManagerHint",)


def load():
    try:
        with open(HISTORY) as f:
            items = json.load(f)
        return [i for i in items if isinstance(i, dict) and isinstance(i.get("text"), str)]
    except (OSError, ValueError):
        return []


def save(items):
    os.makedirs(os.path.dirname(HISTORY), exist_ok=True)
    tmp = HISTORY + ".tmp"
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
        json.dump(items[:KEEP], f)
    os.replace(tmp, HISTORY)


def add(items, text, now=None):
    """items with text at the front (moved up if it was there already)."""
    if not text.strip() or len(text) > MAX_CHARS:
        return items
    rest = [i for i in items if i["text"] != text]
    return ([{"text": text, "time": now or time.time()}] + rest)[:KEEP]


def enabled():
    from . import style

    return style.prefs().get("clipboard_history", True)


def offered_types():
    try:
        return subprocess.run(["wl-paste", "--list-types"], capture_output=True, text=True,
                              timeout=2).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return []


# freemac's own apps mark a password they copy here (a hash, never the text),
# because a GTK app can't offer the x-kde-passwordManagerHint type itself.
SECRET_MARK = os.path.join(GLib.get_user_runtime_dir(), "freemac-clips-secret")
SECRET_FOR = 30   # seconds a mark counts


def _digest(text):
    import hashlib
    return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()


def mark_secret(text):
    """Have the next copy of this text left out of the history."""
    try:
        fd = os.open(SECRET_MARK, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(_digest(text))
    except OSError:
        pass


def marked_secret(text):
    try:
        if time.time() - os.path.getmtime(SECRET_MARK) > SECRET_FOR:
            return False
        with open(SECRET_MARK) as f:
            return f.read().strip() == _digest(text)
    except OSError:
        return False


def store(stream=None):
    """Called by wl-paste for each new copy, with the text on stdin."""
    stream = stream or sys.stdin
    data = stream.buffer.read(MAX_CHARS * 4 + 1) if hasattr(stream, "buffer") else stream.read()
    if not enabled():
        return
    if any(t in SECRET_TYPES for t in offered_types()):
        return
    text = data.decode("utf-8", "replace") if isinstance(data, bytes) else data
    if marked_secret(text) or marked_secret(text.rstrip("\n")):
        return
    save(add(load(), text))


def clear():
    save([])


def copy(text):
    if shutil.which("wl-copy"):
        subprocess.run(["wl-copy"], input=text.encode(), stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=5)


def one_line(text, width=90):
    flat = " ".join(text.split())
    return flat if len(flat) <= width else flat[:width - 1] + "…"


def ago(stamp, now=None):
    seconds = max(0, int((now or time.time()) - stamp))
    if seconds < 60:
        return "now"
    if seconds < 3600:
        return f"{seconds // 60} min"
    if seconds < 86400:
        return f"{seconds // 3600} h"
    return f"{seconds // 86400} d"


def picker():
    import gi

    gi.require_version("Gdk", "3.0")
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gdk, Gtk, Pango

    from . import style

    style.apply()
    window = Gtk.Window(title="Clipboard History")
    window.set_default_size(520, 440)
    window.set_position(Gtk.WindowPosition.CENTER)
    window.set_icon_name("edit-paste")
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=12)
    window.add(box)
    search = Gtk.SearchEntry(placeholder_text="Search what you copied")
    box.pack_start(search, False, False, 0)
    listbox = Gtk.ListBox(activate_on_single_click=True)
    scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
    scroll.add(listbox)
    box.pack_start(scroll, True, True, 0)
    footer = Gtk.Box(spacing=8)
    hint = Gtk.Label(xalign=0)
    hint.get_style_context().add_class("dim-label")
    footer.pack_start(hint, True, True, 0)
    clear_button = Gtk.Button(label="Clear History")
    footer.pack_end(clear_button, False, False, 0)
    box.pack_start(footer, False, False, 0)

    def fill():
        for row in listbox.get_children():
            listbox.remove(row)
        items = load()
        for item in items:
            row = Gtk.ListBoxRow()
            row.text = item["text"]
            line = Gtk.Box(spacing=8, margin=6)
            label = Gtk.Label(label=one_line(item["text"]), xalign=0, ellipsize=Pango.EllipsizeMode.END)
            when = Gtk.Label(label=ago(item.get("time", 0)))
            when.get_style_context().add_class("dim-label")
            line.pack_start(label, True, True, 0)
            line.pack_end(when, False, False, 0)
            row.add(line)
            row.set_tooltip_text(item["text"][:500])
            listbox.add(row)
        listbox.show_all()
        if not enabled():
            hint.set_text("History is off. Turn it on in Settings › Keyboard.")
        elif not items:
            hint.set_text("Nothing copied yet.")
        else:
            hint.set_text("Enter copies it again, ready to paste.")
        first = listbox.get_row_at_index(0)
        if first:
            listbox.select_row(first)

    def visible_rows():
        return [r for r in listbox.get_children() if r.get_child_visible()]

    def filt(row):
        words = search.get_text().lower().split()
        return all(w in row.text.lower() for w in words)

    def changed(*_args):
        listbox.invalidate_filter()
        rows = visible_rows()
        if rows:
            listbox.select_row(rows[0])

    def chosen(_box, row):
        copy(row.text)
        window.destroy()

    def key(_w, event):
        if event.keyval == Gdk.KEY_Escape:
            window.destroy()
            return True
        if event.keyval in (Gdk.KEY_Down, Gdk.KEY_Up):
            rows = visible_rows()
            if not rows:
                return True
            current = listbox.get_selected_row()
            at = rows.index(current) if current in rows else -1
            at = min(len(rows) - 1, at + 1) if event.keyval == Gdk.KEY_Down else max(0, at - 1)
            listbox.select_row(rows[at])
            rows[at].grab_focus()
            search.grab_focus_without_selecting()
            return True
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            row = listbox.get_selected_row()
            if row is not None and row.get_child_visible():
                chosen(listbox, row)
            return True
        return False

    def clear_clicked(*_args):
        clear()
        fill()

    listbox.set_filter_func(filt)
    listbox.connect("row-activated", chosen)
    search.connect("search-changed", changed)
    clear_button.connect("clicked", clear_clicked)
    window.connect("key-press-event", key)
    window.connect("destroy", Gtk.main_quit)
    fill()
    window.show_all()
    search.grab_focus()
    Gtk.main()


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if "--store" in argv:
        store()
    elif "--clear" in argv:
        clear()
    else:
        picker()
    return 0


if __name__ == "__main__":
    sys.exit(main())
