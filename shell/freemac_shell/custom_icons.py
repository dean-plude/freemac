# SPDX-License-Identifier: GPL-3.0-or-later
"""Custom icons, as on a Mac: give a file or folder any picture as its icon
by pasting or dropping it on the icon in its Info window, and take it off
again with Delete.

The picture is kept, at most 512 pixels on a side, in
~/.local/share/freemac/icons/, named by a digest of its pixels so one
picture used for many items is kept once. The item points at it with the
user.freemac.icon extended attribute, which stays with it when it is moved
or renamed on the same disk. Drawer, the Desktop and Get Info show it in
place of the item's kind icon. Original freemac code.
"""
import hashlib
import os

from gi.repository import GLib

ATTR = "user.freemac.icon"
FOLDER = os.path.join(GLib.get_user_data_dir(), "freemac", "icons")
LARGEST = 512


def get(path):
    """The picture file of the item's custom icon, or None."""
    try:
        name = os.getxattr(path, ATTR, follow_symlinks=False).decode("utf-8", "replace")
    except OSError:
        return None
    # Only a plain name in our own folder, never a path from elsewhere.
    if not name or os.sep in name or name.startswith("."):
        return None
    found = os.path.join(FOLDER, name)
    return found if os.path.isfile(found) else None


def has(path):
    return get(path) is not None


def put(path, pixbuf):
    """Make pixbuf the item's icon; raises OSError when the disk can't keep
    it, as on a FAT USB stick."""
    from gi.repository import GdkPixbuf
    w, h = pixbuf.get_width(), pixbuf.get_height()
    if max(w, h) > LARGEST:
        ratio = LARGEST / max(w, h)
        pixbuf = pixbuf.scale_simple(max(1, round(w * ratio)), max(1, round(h * ratio)),
                                     GdkPixbuf.InterpType.HYPER)
    if not pixbuf.get_has_alpha():
        pixbuf = pixbuf.add_alpha(False, 0, 0, 0)
    digest = hashlib.sha256(bytes(pixbuf.get_pixels()) +
                            f"{pixbuf.get_width()}x{pixbuf.get_height()}".encode()).hexdigest()[:24]
    name = digest + ".png"
    os.makedirs(FOLDER, exist_ok=True)
    target = os.path.join(FOLDER, name)
    if not os.path.exists(target):
        try:
            pixbuf.savev(target + ".part", "png", [], [])
        except GLib.Error as err:
            raise OSError(5, err.message) from None
        os.replace(target + ".part", target)
    os.setxattr(path, ATTR, name.encode(), follow_symlinks=False)
    return target


def clear(path):
    """Back to the kind's own icon. The picture itself is kept, as another
    item may use it too."""
    try:
        os.removexattr(path, ATTR, follow_symlinks=False)
    except OSError as err:
        if err.errno not in (61, 95):   # none set, or none possible
            raise


def pixbuf(path, size, cache=None):
    """The custom icon drawn to fit size by size, centred, or None."""
    found = get(path)
    if found is None:
        return None
    key = (found, size)
    if cache is not None and key in cache:
        return cache[key]
    from gi.repository import GdkPixbuf
    try:
        small = GdkPixbuf.Pixbuf.new_from_file_at_scale(found, size, size, True)
    except GLib.Error:
        return None
    if small.get_width() != size or small.get_height() != size:
        # A square, so a wide picture lines up with the icons beside it.
        square = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, size, size)
        square.fill(0)
        small.copy_area(0, 0, small.get_width(), small.get_height(), square,
                        (size - small.get_width()) // 2, (size - small.get_height()) // 2)
        small = square
    if cache is not None:
        if len(cache) > 500:
            cache.clear()
        cache[key] = small
    return small


def picture_of(path):
    """A file dropped or pasted on an icon gives its picture: its own custom
    icon, the picture itself for an image, else None."""
    from gi.repository import GdkPixbuf
    found = get(path)
    if found:
        path = found
    try:
        picture = GdkPixbuf.Pixbuf.new_from_file(path)
    except GLib.Error:
        return None
    return picture.apply_embedded_orientation() or picture


def from_clipboard():
    """The picture on the clipboard, or that of an image file copied in
    Drawer, or None."""
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gdk, Gtk
    from . import transfer
    clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
    image = clipboard.wait_for_image()
    if image is not None:
        return image
    for path in transfer.pasted_files()[:1]:
        return picture_of(path)
    return None
