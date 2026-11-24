# SPDX-License-Identifier: GPL-3.0-or-later
"""Locked files and folders, as on a Mac: tick Locked in an item's Info
window (⌘I) and it can't be changed, renamed or moved to the Trash by
mistake.

Locking takes away the item's write permission, so no app can change a
locked file and nothing can be added to or taken out of a locked folder.
The permission it had is kept in the item's user.freemac.locked extended
attribute, which also marks it as locked, and unlocking puts it back.
Drawer and the Desktop show a small padlock on its icon, ask before
moving it to the Trash, and say that it can't be renamed. Original freemac
code.
"""
import math
import os
import stat

ATTR = "user.freemac.locked"
WRITE = stat.S_IWUSR | stat.S_IWGRP | stat.S_IWOTH
LOCK_SHARE = 0.34    # the padlock's size, as a share of the icon


def is_locked(path):
    try:
        os.getxattr(path, ATTR, follow_symlinks=False)
        return True
    except OSError:
        return False


def can_lock(path):
    """Only the owner can lock or unlock an item, and an alias has no lock."""
    try:
        info = os.lstat(path)
    except OSError:
        return False
    return not stat.S_ISLNK(info.st_mode) and info.st_uid == os.getuid()


def lock(path):
    """Lock path: keep its permission, then take away writing."""
    if is_locked(path):
        return
    mode = stat.S_IMODE(os.stat(path).st_mode)
    # The attribute first: writing it needs the permission that is about to go.
    os.setxattr(path, ATTR, oct(mode).encode())
    os.chmod(path, mode & ~WRITE)


def unlock(path):
    """Unlock path: give back the permission it had before it was locked."""
    try:
        saved = os.getxattr(path, ATTR, follow_symlinks=False).decode()
        mode = int(saved, 8) & 0o7777
    except OSError:
        return
    except ValueError:
        mode = stat.S_IMODE(os.stat(path).st_mode)
    os.chmod(path, mode | stat.S_IWUSR)
    try:
        os.removexattr(path, ATTR)
    except OSError:
        pass


def set_locked(path, on):
    if on:
        lock(path)
    else:
        unlock(path)


def locked_among(paths):
    return [p for p in paths if is_locked(p)]


# ---- the padlock on an icon ---------------------------------------------

def badge(pixbuf):
    """The icon with a small padlock in its lower-left corner."""
    if pixbuf is None:
        return None
    import cairo
    import gi
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk
    w, h = pixbuf.get_width(), pixbuf.get_height()
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    cr = cairo.Context(surface)
    Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
    cr.paint()
    size = max(8, round(min(w, h) * LOCK_SHARE))
    draw_padlock(cr, 0, h - size, size)
    return Gdk.pixbuf_get_from_surface(surface, 0, 0, w, h)


def draw_padlock(cr, x, y, size):
    """A dark padlock: a rounded body with a keyhole, under an arched shackle,
    with a thin white edge so it shows on dark icons too."""
    cr.save()
    body_w, body_h = size * 0.78, size * 0.52
    bx, by = x + (size - body_w) / 2, y + size - body_h - size * 0.04
    r = size * 0.1

    def body():
        cr.new_sub_path()
        cr.arc(bx + body_w - r, by + r, r, -math.pi / 2, 0)
        cr.arc(bx + body_w - r, by + body_h - r, r, 0, math.pi / 2)
        cr.arc(bx + r, by + body_h - r, r, math.pi / 2, math.pi)
        cr.arc(bx + r, by + r, r, math.pi, 3 * math.pi / 2)
        cr.close_path()

    def shackle():
        cr.new_sub_path()
        cr.arc(x + size / 2, by - size * 0.02, size * 0.24, math.pi, 0)
        cr.line_to(x + size / 2 + size * 0.24, by + size * 0.05)
        cr.move_to(x + size / 2 - size * 0.24, by + size * 0.05)
        cr.line_to(x + size / 2 - size * 0.24, by - size * 0.02)

    cr.set_line_cap(1)   # round
    # The white edge.
    cr.set_source_rgba(1, 1, 1, 0.95)
    cr.set_line_width(max(2.0, size * 0.22))
    shackle()
    cr.stroke()
    body()
    cr.set_line_width(max(1.5, size * 0.1))
    cr.stroke_preserve()
    cr.fill()
    # The lock itself.
    cr.set_source_rgb(0.16, 0.16, 0.2)
    cr.set_line_width(max(1.0, size * 0.11))
    shackle()
    cr.stroke()
    body()
    cr.fill()
    # The keyhole.
    cr.set_source_rgb(1, 1, 1)
    cr.arc(x + size / 2, by + body_h * 0.42, max(0.6, size * 0.06), 0, 2 * math.pi)
    cr.fill()
    cr.rectangle(x + size / 2 - max(0.4, size * 0.025), by + body_h * 0.42,
                 max(0.8, size * 0.05), body_h * 0.32)
    cr.fill()
    cr.restore()


# ---- in windows ----------------------------------------------------------

def ask_trash(parent, paths):
    """Ask before moving locked items to the Trash, as a Mac does. Returns the
    paths to move: all of them (unlocked first) on Continue, the others on
    Stop."""
    locked = locked_among(paths)
    if not locked:
        return paths
    from . import alert
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk
    if len(locked) == 1:
        title = f"“{os.path.basename(locked[0])}” is locked. Do you want to move it to the Trash anyway?"
    else:
        title = f"{len(locked)} items are locked. Do you want to move them to the Trash anyway?"
    answer = alert.ask(parent, title, "", [("Stop", Gtk.ResponseType.CANCEL), ("Continue", Gtk.ResponseType.OK)],
                       default=Gtk.ResponseType.OK)
    if answer != Gtk.ResponseType.OK:
        return [p for p in paths if p not in locked]
    for path in locked:
        try:
            unlock(path)
        except OSError:
            pass
    return paths


def tell_cant_rename(parent, path):
    from . import alert
    alert.tell(parent, f"The name of “{os.path.basename(path)}” can’t be changed because it is locked.",
               "To change it, choose File > Get Info and untick Locked.")
