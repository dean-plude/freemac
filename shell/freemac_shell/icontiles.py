# SPDX-License-Identifier: GPL-3.0-or-later
"""Give every app icon the same rounded-square tile.

Apps bring icons in every shape: circles, loose drawings, squares with sharp
corners. freemac shows them all the same way, so the dock, search and Drawer
look like one family. For each installed app this reads the app's own icon,
then writes a tile into the freemac icon theme under the same name, so it is
used in place of the original:

* an icon that already fills a square gets rounded corners and a soft shadow;
* any other shape is set, at a uniform size, on a light rounded tile with
  the same shadow.

Nothing is drawn by hand and no icon ships with freemac: tiles are made on
this computer from the apps installed on it. freemac's own app icons are left
alone, since they are already tiles.

    freemac-icon-tiles --system   apps for everyone (run as root after apt)
    freemac-icon-tiles --user     apps in your home folder and Flatpak apps

An icon given as a file path in the app's .desktop file gets a tile under a
new name and a copy of the .desktop file that points at it (in
/usr/local/share/applications, or ~/.local/share/applications for --user).
"""
import base64
import configparser
import glob
import hashlib
import json
import os
import subprocess
import sys

import gi

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, GLib  # noqa: E402

SIZE = 128          # canvas of the tile SVG, the same grid as freemac's own icons
TILE = (8, 8, 112, 112)
RADIUS = 24
SAMPLE = 256        # pixels used to read the app's icon
INNER = 0.70        # share of the tile a loose icon may fill
SKIP_PREFIXES = ("freemac", "ferry-")
ICON_SIZES = ("scalable", "1024x1024", "512x512", "256x256", "192x192", "128x128", "96x96",
              "72x72", "64x64", "48x48", "32x32")


def base_dirs(system):
    """Folders holding applications/ and icons/, most specific first."""
    if system:
        return ["/usr/local/share", "/usr/share", "/var/lib/flatpak/exports/share"]
    home = GLib.get_user_data_dir()
    return [home, os.path.join(home, "flatpak", "exports", "share"), "/var/lib/flatpak/exports/share",
            "/usr/local/share", "/usr/share"]


def theme_dir(system):
    root = "/usr/share/icons" if system else os.path.join(GLib.get_user_data_dir(), "icons")
    return os.path.join(root, "freemac", "scalable", "apps")


def apps_dir(system):
    return "/usr/local/share/applications" if system else os.path.join(GLib.get_user_data_dir(), "applications")


def desktop_files(system):
    seen = {}
    dirs = base_dirs(system) if system else [GLib.get_user_data_dir(),
                                             os.path.join(GLib.get_user_data_dir(), "flatpak", "exports", "share"),
                                             "/var/lib/flatpak/exports/share"]
    for base in dirs:
        for path in sorted(glob.glob(os.path.join(base, "applications", "*.desktop"))):
            seen.setdefault(os.path.basename(path), path)
    return list(seen.values())


def read_icon_name(path):
    parser = configparser.RawConfigParser(strict=False, interpolation=None)
    parser.optionxform = str
    try:
        parser.read(path, encoding="utf-8")
        return parser.get("Desktop Entry", "Icon", fallback="").strip()
    except (configparser.Error, UnicodeDecodeError, OSError):
        return ""


def find_icon(name, system):
    """The best file for an icon name: hicolor at the largest size, then pixmaps."""
    if os.path.isabs(name):
        return name if os.path.isfile(name) else None
    for base in base_dirs(system):
        for size in ICON_SIZES:
            for ext in (".svg", ".png"):
                path = os.path.join(base, "icons", "hicolor", size, "apps", name + ext)
                if os.path.isfile(path):
                    return path
        for ext in (".svg", ".png", ".xpm"):
            path = os.path.join(base, "pixmaps", name + ext)
            if os.path.isfile(path):
                return path
    return None


SMALL = 96         # raster icons smaller than this are never stretched to fill a tile


def load(path):
    """(pixbuf, native size or None for drawings that scale)."""
    native = None
    if not path.endswith((".svg", ".svgz")):
        info = GdkPixbuf.Pixbuf.get_file_info(path)
        if info and info[0] is not None:
            native = max(info[1], info[2])
    try:
        if native and native < SAMPLE:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file(path)
        else:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, SAMPLE, SAMPLE, True)
    except GLib.Error:
        return None, None
    if not pixbuf.get_has_alpha():
        pixbuf = pixbuf.add_alpha(False, 0, 0, 0)
    return pixbuf, native


def measure(pixbuf):
    """(bounding box of visible pixels, share of that box that is solid)."""
    width, height = pixbuf.get_width(), pixbuf.get_height()
    stride, data = pixbuf.get_rowstride(), pixbuf.get_pixels()
    left, top, right, bottom, solid = width, height, -1, -1, 0
    for y in range(height):
        row = y * stride
        for x in range(width):
            alpha = data[row + x * 4 + 3]
            if alpha > 24:
                if x < left:
                    left = x
                if x > right:
                    right = x
                if y < top:
                    top = y
                if y > bottom:
                    bottom = y
                if alpha > 200:
                    solid += 1
    if right < 0:
        return None, 0.0
    box = (left, top, right - left + 1, bottom - top + 1)
    return box, solid / float(box[2] * box[3])


def is_square_tile(pixbuf, box, fill):
    """Already a full square (or near enough) that only needs rounding."""
    w, h = pixbuf.get_width(), pixbuf.get_height()
    return box[2] >= 0.84 * w and box[3] >= 0.84 * h and abs(box[2] - box[3]) <= 0.06 * w and fill >= 0.93


def png_data(pixbuf):
    ok, data = pixbuf.save_to_bufferv("png", [], [])
    return base64.b64encode(data).decode("ascii")


SHADOW = """<filter id="shadow" x="-20%" y="-20%" width="140%" height="150%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="2.2" result="blur"/>
      <feOffset in="blur" dy="2" result="moved"/>
      <feComponentTransfer in="moved" result="soft"><feFuncA type="linear" slope="0.32"/></feComponentTransfer>
      <feMerge><feMergeNode in="soft"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>"""


def tile_svg(pixbuf, native=None):
    """The tile for one icon, as SVG text."""
    x, y, w, h = TILE
    box, fill = measure(pixbuf)
    if box is None:
        return None
    small = native is not None and native < SMALL
    if not small and is_square_tile(pixbuf, box, fill):
        crop = pixbuf.new_subpixbuf(*box)
        body = (f'<g filter="url(#shadow)"><g clip-path="url(#round)">'
                f'<image x="{x}" y="{y}" width="{w}" height="{h}" preserveAspectRatio="none" '
                f'href="data:image/png;base64,{png_data(crop)}"/></g></g>')
    else:
        crop = pixbuf.new_subpixbuf(*box)
        scale = INNER * w / max(box[2], box[3])
        if small:
            # A small picture is shown no bigger than twice its own size, so it stays sharp.
            scale = min(scale, 2.0)   # the picture is at its own size here
        iw, ih = box[2] * scale, box[3] * scale
        ix, iy = x + (w - iw) / 2, y + (h - ih) / 2
        body = (f'<g filter="url(#shadow)"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{RADIUS}" '
                f'fill="url(#paper)"/></g>'
                f'<rect x="{x + 0.5}" y="{y + 0.5}" width="{w - 1}" height="{h - 1}" rx="{RADIUS - 0.5}" '
                f'fill="none" stroke="#000000" stroke-opacity="0.09"/>'
                f'<image x="{ix:.2f}" y="{iy:.2f}" width="{iw:.2f}" height="{ih:.2f}" '
                f'href="data:image/png;base64,{png_data(crop)}"/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" '
            f'viewBox="0 0 {SIZE} {SIZE}">\n'
            f'  <!-- Made by freemac-icon-tiles from this app\'s own icon. -->\n'
            f'  <defs>\n    {SHADOW}\n'
            f'    <linearGradient id="paper" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#e8e8ed"/></linearGradient>\n'
            f'    <clipPath id="round"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{RADIUS}"/></clipPath>\n'
            f'  </defs>\n  {body}\n</svg>\n')


def tile_name(icon):
    if os.path.isabs(icon):
        stem = os.path.splitext(os.path.basename(icon))[0]
        return f"tile-{stem}-{hashlib.sha1(icon.encode()).hexdigest()[:8]}"
    return icon


def stamp(path):
    try:
        st = os.stat(path)
        return f"{int(st.st_mtime)}:{st.st_size}"
    except OSError:
        return ""


def write_if_changed(path, text):
    try:
        with open(path) as f:
            if f.read() == text:
                return False
    except OSError:
        pass
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)
    return True


def redirect_desktop(source, icon, name, system):
    """A copy of a .desktop file whose Icon is a file path, pointing at the tile."""
    folder = apps_dir(system)
    os.makedirs(folder, exist_ok=True)
    target = os.path.join(folder, os.path.basename(source))
    if os.path.realpath(target) == os.path.realpath(source):
        return
    with open(source, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    out, in_entry = [], False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("["):
            in_entry = stripped == "[Desktop Entry]"
        if in_entry and stripped.startswith("Icon=") and stripped[5:].strip() == icon:
            line = "Icon=" + name
        out.append(line)
    out.append("X-freemac-Tiled=true")
    write_if_changed(target, "\n".join(out) + "\n")


def run(system):
    folder = theme_dir(system)
    os.makedirs(folder, exist_ok=True)
    manifest_path = os.path.join(folder, ".tiles.json")
    try:
        with open(manifest_path) as f:
            manifest = json.load(f)
    except (OSError, ValueError):
        manifest = {}
    made, kept = 0, {}
    for desktop in desktop_files(system):
        icon = read_icon_name(desktop)
        if not icon or icon.startswith(SKIP_PREFIXES) or os.path.basename(icon).startswith(SKIP_PREFIXES):
            continue
        with open(desktop, errors="replace") as f:
            if "X-freemac-Tiled=true" in f.read():
                continue
        source = find_icon(icon, system)
        if not source:
            continue
        name = tile_name(icon)
        key = f"{source}|{stamp(source)}"
        out = os.path.join(folder, name + ".svg")
        kept[name] = key
        if manifest.get(name) == key and os.path.isfile(out):
            continue
        pixbuf, native = load(source)
        if pixbuf is None:
            kept.pop(name)
            continue
        svg = tile_svg(pixbuf, native)
        if svg is None:
            kept.pop(name)
            continue
        if write_if_changed(out, svg):
            made += 1
        if os.path.isabs(icon):
            redirect_desktop(desktop, icon, name, system)
    # Tiles of apps that were removed.
    for name in set(manifest) - set(kept):
        try:
            os.remove(os.path.join(folder, name + ".svg"))
            made += 1
        except OSError:
            pass
    with open(manifest_path, "w") as f:
        json.dump(kept, f, indent=0, sort_keys=True)
    if system and made and os.path.exists(os.path.join(os.path.dirname(os.path.dirname(folder)), "icon-theme.cache")):
        subprocess.run(["gtk-update-icon-cache", "-f", "-t", os.path.dirname(os.path.dirname(folder))],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return made


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    system = "--system" in argv
    made = run(system)
    if "--quiet" not in argv:
        print(f"{made} icon tile(s) made or removed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
