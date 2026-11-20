# SPDX-License-Identifier: GPL-3.0-or-later
"""Moving and copying files, the way a Mac's file manager does it.

Drawer and the Desktop both use this:

* copy_files() and pasted_files(): ⌘C puts files on the clipboard, ⌘V pastes
  copies of them and ⌥⌘V moves them. Other apps see the files' names as
  text; Drawer windows and the Desktop (separate programs) find the files
  themselves through a small note beside the clipboard.
* Job: a copy or a move run on a thread. A name already taken asks Keep
  Both, Stop or Replace (Replace puts the old item in the Trash); anything
  that takes more than a moment shows a small window with its progress and
  a Stop button. A move on the same disk is a rename; onto another disk it
  is a copy, then the original goes.
* Undo (⌘Z): every move, copy, rename, new folder and Move to Trash is
  noted, and undo_last() takes the newest one back, from any window.

Original freemac code.
"""
import json
import os
import shutil
import threading
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

CHUNK = 1 << 20
SYNC_EVERY = 16 << 20
SHOW_AFTER = 600        # ms before a job shows its window
UNDO_KEPT = 20
KEEP, STOP, REPLACE = 1, 2, 3


def _cache(name):
    folder = os.path.join(GLib.get_user_cache_dir(), "freemac")
    os.makedirs(folder, exist_ok=True)
    return os.path.join(folder, name)


def _read(path, empty):
    try:
        with open(path, encoding="utf-8") as fh:
            found = json.load(fh)
        return found if isinstance(found, type(empty)) else empty
    except (OSError, ValueError):
        return empty


def _write(path, data):
    tmp = path + ".new"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh)
        os.replace(tmp, path)
    except OSError:
        pass


# ---- names -----------------------------------------------------------------
def _split(name):
    stem, ext = os.path.splitext(name)
    if name.startswith(".") and not ext:
        stem, ext = name, ""
    return stem, ext


def free_name(folder, name):
    """name, or "name 2", "name 3"… when the folder already has one."""
    if not os.path.lexists(os.path.join(folder, name)):
        return name
    stem, ext = _split(name)
    n = 2
    while os.path.lexists(os.path.join(folder, f"{stem} {n}{ext}")):
        n += 1
    return f"{stem} {n}{ext}"


def copy_name(folder, name):
    """A copy beside its original: "name copy", then "name copy 2"…"""
    stem, ext = _split(name)
    if os.path.isdir(os.path.join(folder, name)):
        stem, ext = name, ""
    first = f"{stem} copy{ext}"
    if not os.path.lexists(os.path.join(folder, first)):
        return first
    n = 2
    while os.path.lexists(os.path.join(folder, f"{stem} copy {n}{ext}")):
        n += 1
    return f"{stem} copy {n}{ext}"


def inside(path, folder):
    """Is folder path itself, or somewhere inside it?"""
    path, folder = os.path.abspath(path), os.path.abspath(folder)
    return folder == path or folder.startswith(path.rstrip(os.sep) + os.sep)


def same_disk(path, folder):
    try:
        return os.lstat(path).st_dev == os.stat(folder).st_dev
    except OSError:
        return False


def _described(paths):
    if len(paths) == 1:
        return f"“{os.path.basename(paths[0].rstrip(os.sep))}”"
    return f"{len(paths)} items"


def _place(folder):
    home = GLib.get_home_dir()
    if os.path.abspath(folder) == home:
        return "Home"
    return os.path.basename(folder.rstrip(os.sep)) or "Computer"


# ---- the clipboard ---------------------------------------------------------
NOTE = "file-clipboard.json"


def copy_files(paths):
    """⌘C on files: their names go on the clipboard as text, the files
    themselves in the note beside it."""
    paths = [os.path.abspath(p) for p in paths if os.path.lexists(p)]
    if not paths:
        return False
    text = "\n".join(os.path.basename(p.rstrip(os.sep)) for p in paths)
    _write(_cache(NOTE), {"paths": paths, "text": text, "stamp": time.time()})
    clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
    clipboard.set_text(text, -1)
    clipboard.store()
    return True


def pasted_files():
    """The files on the clipboard: ours, or ones another app copied."""
    clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
    uris = clipboard.wait_for_uris() or []
    found = [Gio.File.new_for_uri(u).get_path() for u in uris]
    found = [p for p in found if p and os.path.lexists(p)]
    if found:
        return found
    text = clipboard.wait_for_text()
    if text is None:
        return []
    note = _read(_cache(NOTE), {})
    if note.get("text") == text:
        return [p for p in note.get("paths", []) if isinstance(p, str) and os.path.lexists(p)]
    # Text that is nothing but paths, one a line, as some apps copy them.
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    paths = [Gio.File.new_for_uri(line).get_path() if line.startswith("file://") else line for line in lines]
    if paths and all(p and os.path.isabs(p) and os.path.lexists(p) for p in paths):
        return paths
    return []


# ---- undo ------------------------------------------------------------------
UNDO = "file-undo.json"


UNDO_FOR = 2 * 3600      # how long something done can still be undone, in seconds


def _undo_stack():
    now = time.time()
    return [r for r in _read(_cache(UNDO), []) if isinstance(r, dict) and now - r.get("stamp", 0) < UNDO_FOR]


def note_done(record):
    """Remember something done, for Undo."""
    stack = _undo_stack()
    record = dict(record, stamp=time.time())
    stack.append(record)
    _write(_cache(UNDO), stack[-UNDO_KEPT:])


def last_done():
    stack = _undo_stack()
    return stack[-1] if stack else None


def undo_label(record=None):
    record = record if record is not None else last_done()
    if not record:
        return "Undo"
    kind = record.get("kind")
    if kind == "move":
        return f"Undo Move of {_described([b for _a, b in record.get('pairs', [])])}"
    if kind == "copy":
        return f"Undo Copy of {_described(record.get('made', []))}"
    if kind == "rename":
        return "Undo Rename"
    if kind == "trash":
        return "Undo Move to Trash"
    if kind == "new-folder":
        return "Undo New Folder"
    return "Undo"


def restore_from_trash(paths):
    """Put items back where they were before they went to the Trash. Returns
    the ones that came back."""
    wanted = {os.path.abspath(p) for p in paths}
    trash = Gio.File.new_for_uri("trash:///")
    latest = {}
    try:
        enum = trash.enumerate_children("standard::name,trash::orig-path,trash::deletion-date",
                                        Gio.FileQueryInfoFlags.NONE, None)
    except GLib.Error:
        return []
    for info in enum:
        orig = info.get_attribute_byte_string("trash::orig-path")
        if orig not in wanted:
            continue
        date = info.get_deletion_date()
        stamp = date.to_unix() if date else 0
        if orig not in latest or stamp > latest[orig][0]:
            latest[orig] = (stamp, trash.get_child(info.get_name()))
    enum.close(None)
    back = []
    for orig, (_stamp, item) in latest.items():
        if os.path.lexists(orig):
            continue
        try:
            item.move(Gio.File.new_for_path(orig), Gio.FileCopyFlags.NOFOLLOW_SYMLINKS, None, None, None)
            back.append(orig)
        except GLib.Error:
            pass
    return back


def to_trash(paths):
    """Move to the Trash; returns the ones that went and the first error."""
    went, error = [], None
    for path in paths:
        try:
            Gio.File.new_for_path(path).trash(None)
            went.append(path)
        except GLib.Error as err:
            error = error or err
    return went, error


def undo_last(parent=None, done=None):
    """Take back the newest thing done. done(text) says what happened."""
    stack = _undo_stack()
    if not stack:
        return False
    record = stack.pop()
    _write(_cache(UNDO), stack)
    kind = record.get("kind")
    say = done or (lambda _t: None)
    if kind == "rename":
        old, new = record.get("old"), record.get("new")
        if old and new and os.path.lexists(new) and not os.path.lexists(old):
            try:
                os.rename(new, old)
                say(f"Renamed back to “{os.path.basename(old)}”.")
            except OSError as err:
                say(f"Couldn’t undo the rename: {err.strerror}.")
        return True
    if kind == "trash":
        back = restore_from_trash(record.get("paths", []))
        say(f"Put back {_described(back)}." if back else "Nothing could be put back from the Trash.")
        return True
    if kind == "new-folder":
        path = record.get("path")
        if path and os.path.isdir(path):
            to_trash([path])
            say(f"Moved “{os.path.basename(path)}” to the Trash.")
        return True
    if kind == "copy":
        made = [p for p in record.get("made", []) if os.path.lexists(p)]
        went, _error = to_trash(made)
        restore_from_trash(record.get("replaced", []))
        say(f"Moved the copies of {_described(went)} to the Trash." if went else "The copies are gone already.")
        return True
    if kind == "move":
        pairs = [(b, a) for a, b in record.get("pairs", []) if os.path.lexists(b) and not os.path.lexists(a)]
        replaced = record.get("replaced", [])

        def finished(job):
            restore_from_trash(replaced)
            say(f"Moved {_described([b for b, _a in pairs])} back." if job.made else "Nothing was moved back.")
        if pairs:
            Job([a for a, _b in pairs], None, move=True, parent=parent, done=finished,
                pairs=pairs, record=False).start()
        else:
            say("Nothing was moved back.")
        return True
    return False


# ---- a copy or a move ------------------------------------------------------
class Job:
    """Copy or move paths into folder on a thread. done(job) runs on the
    main loop when it ends; job.made holds where each item went."""

    def __init__(self, paths, folder, move=False, parent=None, done=None, duplicate=False,
                 pairs=None, record=True):
        self.paths = [os.path.abspath(p) for p in paths]
        self.folder = os.path.abspath(folder) if folder else None
        self.move, self.parent, self.done = move, parent, done
        self.duplicate, self.given, self.record = duplicate, pairs, record
        self.made, self.moved, self.replaced, self.errors = [], [], [], []
        self.total, self.copied, self.count, self.index = 0, 0, 0, 0
        self.current = ""
        self.stopped = threading.Event()
        self.window = None
        self.finished = False
        self.apply_all = None
        self.asking = self.planned = False

    # -- the main loop side --
    def start(self):
        app = self._app()
        if app is not None:
            app.hold()
        threading.Thread(target=self._work, daemon=True).start()
        self.timer = GLib.timeout_add(SHOW_AFTER, self._show_window)
        return self

    def _app(self):
        parent = self.parent
        if parent is not None and hasattr(parent, "get_application") and parent.get_application():
            return parent.get_application()
        return Gio.Application.get_default()

    def stop(self):
        self.stopped.set()

    def _show_window(self):
        if self.finished or self.stopped.is_set():
            self.timer = 0
            return False
        if self.asking or not self.planned:
            return True      # not while a question is up; look again soon
        self.timer = 0
        self.window = Progress(self)
        self.window.show_all()
        return False

    def _ask(self, name, is_dir, more):
        """Ask on the main loop what to do about a name that's taken; the
        thread waits for the answer."""
        answer = {}
        ready = threading.Event()
        self.asking = True

        def ask():
            answer["value"], answer["all"] = ask_taken(self.parent, name, is_dir, self.move,
                                                       self.folder or "", more)
            ready.set()
            return False
        GLib.idle_add(ask)
        ready.wait()
        self.asking = False
        return answer["value"], answer["all"]

    def _end(self):
        self.finished = True
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = 0
        if self.window is not None:
            self.window.destroy()
            self.window = None
        if self.record and (self.made or self.moved):
            if self.move:
                note_done({"kind": "move", "pairs": self.moved, "replaced": self.replaced})
            else:
                note_done({"kind": "copy", "made": self.made, "replaced": self.replaced})
        if self.errors:
            from . import alert
            what, err = self.errors[0]
            verb = "moved" if self.move else "copied"
            more = len(self.errors) - 1
            text = err if not more else f"{err} ({more} more couldn’t be {verb} either.)"
            alert.tell(self.parent, f"“{os.path.basename(what)}” couldn’t be {verb}.", text,
                       icon="dialog-warning")
        if self.done:
            self.done(self)
        app = self._app()
        if app is not None:
            app.release()
        return False

    # -- the thread side --
    def _plan(self):
        if self.given is not None:
            return [(a, b) for a, b in self.given]
        plan = []
        for n, src in enumerate(self.paths):
            if self.stopped.is_set():
                break
            name = os.path.basename(src.rstrip(os.sep))
            if not os.path.lexists(src):
                continue
            here = os.path.dirname(src) == self.folder
            if self.move and here:
                continue
            if os.path.isdir(src) and not os.path.islink(src) and inside(src, self.folder):
                verb = "moved" if self.move else "copied"
                self.errors.append((src, f"A folder can’t be {verb} into itself."))
                continue
            if self.duplicate or (here and not self.move):
                plan.append((src, os.path.join(self.folder, copy_name(self.folder, name))))
                continue
            dest = os.path.join(self.folder, name)
            if os.path.lexists(dest):
                choice = self.apply_all
                if choice is None:
                    choice, every = self._ask(name, os.path.isdir(dest), len(self.paths) - n - 1)
                    if every:
                        self.apply_all = choice
                if choice == STOP:
                    self.stopped.set()
                    break
                if choice == KEEP:
                    dest = os.path.join(self.folder, free_name(self.folder, name))
                elif inside(dest, src):
                    self.errors.append((src, f"It is inside “{name}”, which it would replace."))
                    continue
                else:
                    went, error = to_trash([dest])
                    if error is not None:
                        self.errors.append((src, error.message))
                        continue
                    self.replaced.append(dest)
            plan.append((src, dest))
        return plan

    def _measure(self, plan):
        total = count = 0
        for src, dest in plan:
            if self.move and same_disk(src, os.path.dirname(dest)):
                count += 1
                continue
            if os.path.isdir(src) and not os.path.islink(src):
                for top, dirs, files in os.walk(src):
                    for f in files:
                        try:
                            total += os.lstat(os.path.join(top, f)).st_size
                        except OSError:
                            pass
                    count += len(files) + len(dirs)
            else:
                try:
                    total += os.lstat(src).st_size
                except OSError:
                    pass
            count += 1
        self.total, self.count = total, count

    def _work(self):
        plan = self._plan()
        self._measure(plan)
        self.planned = True
        if plan and self.total and self.folder:
            try:
                free = shutil.disk_usage(self.folder).free
            except OSError:
                free = None
            if free is not None and self.total > free:
                self.errors.append((plan[0][0], f"“{_place(self.folder)}” doesn’t have enough room: this "
                                    f"needs {_size(self.total)}, and {_size(free)} is free."))
                plan = []
        for src, dest in plan:
            if self.stopped.is_set():
                break
            self.current = os.path.basename(src.rstrip(os.sep))
            existed = os.path.lexists(dest)
            try:
                if self.move and same_disk(src, os.path.dirname(dest)):
                    os.rename(src, dest)
                    self.index += 1
                else:
                    self._copy(src, dest)
                    if self.stopped.is_set():
                        _remove(dest)
                        break
                    if self.move:
                        _remove(src)
            except (OSError, shutil.Error) as err:
                if not existed and src != dest and os.path.lexists(src):
                    _remove(dest)   # only what this copy made, never what was there
                self.errors.append((src, getattr(err, "strerror", None) or str(err)))
                continue
            self.made.append(dest)
            if self.move:
                self.moved.append([src, dest])
        if not self.move or self.made:
            try:
                os.sync()
            except OSError:
                pass
        GLib.idle_add(self._end)

    def _copy(self, src, dest):
        if os.path.islink(src):
            os.symlink(os.readlink(src), dest)
            self.index += 1
            return
        if os.path.isdir(src):
            os.mkdir(dest)
            self.index += 1
            for entry in sorted(os.scandir(src), key=lambda e: e.name):
                if self.stopped.is_set():
                    return
                self._copy(entry.path, os.path.join(dest, entry.name))
            shutil.copystat(src, dest, follow_symlinks=False)
            return
        since = 0
        with open(src, "rb") as reader, open(dest, "xb") as writer:
            while True:
                if self.stopped.is_set():
                    return
                block = reader.read(CHUNK)
                if not block:
                    break
                writer.write(block)
                self.copied += len(block)
                since += len(block)
                if since >= SYNC_EVERY:
                    # Onto a USB stick, the progress shows what's really
                    # written, not what waits in memory.
                    writer.flush()
                    os.fdatasync(writer.fileno())
                    since = 0
        shutil.copystat(src, dest)
        self.index += 1


def _remove(path):
    try:
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        elif os.path.lexists(path):
            os.remove(path)
    except OSError:
        pass


# ---- asking about a name that's taken ---------------------------------------
def ask_taken(parent, name, is_dir, move, folder, more):
    """Keep Both, Stop or Replace, and whether to do the same for the rest."""
    from . import alert
    kind = "a folder" if is_dir else "an item"
    verb = "moving" if move else "copying"
    title = f"{kind[0].upper() + kind[1:]} named “{name}” already exists in “{_place(folder)}”."
    text = f"Do you want to replace it with the one you’re {verb}?"
    dialog = alert.build(parent, title, text,
                         [("Keep Both", KEEP), ("Stop", STOP), ("Replace", REPLACE)],
                         default=REPLACE, icon="dialog-warning")
    check = None
    if more > 0:
        check = Gtk.CheckButton(label="Apply to All")
        check.set_halign(Gtk.Align.CENTER)
        body = dialog.get_content_area().get_children()[0]
        body.pack_start(check, False, False, 0)
        body.reorder_child(check, len(body.get_children()) - 2)
        check.show()
    answer = dialog.run()
    every = bool(check and check.get_active())
    dialog.destroy()
    if answer not in (KEEP, STOP, REPLACE):
        answer = STOP
    return answer, every


# ---- the progress window ---------------------------------------------------
def _size(n):
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if n < 1000 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "bytes" else f"{n:.1f} {unit}"
        n /= 1000
    return f"{n} bytes"


def _icon_of(paths):
    """The first item's own icon, as a Mac's copy window shows it."""
    if len(paths) > 1:
        return Gio.ThemedIcon.new("folder-documents")
    try:
        info = Gio.File.new_for_path(paths[0]).query_info("standard::icon", Gio.FileQueryInfoFlags.NONE, None)
        if info.get_icon() is not None:
            return info.get_icon()
    except (GLib.Error, IndexError):
        pass
    return Gio.ThemedIcon.new("text-x-generic")


class Progress(Gtk.Window):
    def __init__(self, job):
        super().__init__(title="Copy")
        self.job = job
        app = job._app()
        if isinstance(app, Gtk.Application):
            self.set_application(app)
        self.set_default_size(420, -1)
        self.set_resizable(False)
        self.set_icon_name("system-file-manager")
        self.get_style_context().add_class("freemac-progress")
        grid = Gtk.Grid(column_spacing=14, row_spacing=4, margin=16)
        icon = Gtk.Image.new_from_gicon(_icon_of(job.paths), Gtk.IconSize.DIALOG)
        icon.set_pixel_size(48)
        grid.attach(icon, 0, 0, 1, 3)
        self.heading = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.MIDDLE, max_width_chars=40)
        grid.attach(self.heading, 1, 0, 1, 1)
        self.bar = Gtk.ProgressBar(hexpand=True, valign=Gtk.Align.CENTER)
        grid.attach(self.bar, 1, 1, 1, 1)
        stop = Gtk.Button(relief=Gtk.ReliefStyle.NONE, tooltip_text="Stop", valign=Gtk.Align.CENTER)
        stop.add(Gtk.Image.new_from_icon_name("process-stop-symbolic", Gtk.IconSize.BUTTON))
        stop.get_style_context().add_class("circular")
        stop.connect("clicked", lambda *_: self._stop())
        grid.attach(stop, 2, 1, 1, 1)
        self.detail = Gtk.Label(xalign=0)
        self.detail.get_style_context().add_class("dim-label")
        grid.attach(self.detail, 1, 2, 1, 1)
        self.add(grid)
        # Closing the window leaves the copy going, as on a Mac; Stop stops it.
        self.connect("delete-event", lambda *_: self.hide() or True)
        self.began = time.monotonic()
        self._update()
        self.ticker = GLib.timeout_add(150, self._update)
        self.connect("destroy", lambda *_: GLib.source_remove(self.ticker))

    def _stop(self):
        self.job.stop()
        self.heading.set_text("Stopping…")

    def _update(self):
        job = self.job
        if job.stopped.is_set():
            return True
        verb = "Moving" if job.move else "Copying"
        what = _described(job.paths)
        target = _place(job.folder) if job.folder else "where they were"
        self.set_title("Move" if job.move else "Copy")
        self.heading.set_text(f"{verb} {what} to “{target}”" if job.folder else f"{verb} {what} back")
        if job.total:
            share = min(1, job.copied / job.total)
            self.bar.set_fraction(share)
            spent = time.monotonic() - self.began
            left = ""
            if share > 0.02 and spent > 2:
                seconds = spent / share - spent
                left = f" — about {int(seconds // 60) + 1} min left" if seconds >= 60 else \
                    f" — about {max(1, int(seconds))} s left"
            self.detail.set_text(f"{_size(job.copied)} of {_size(job.total)}{left}")
        else:
            self.bar.pulse()
            self.detail.set_text(job.current)
        return True
