# SPDX-License-Identifier: GPL-3.0-or-later
"""Mac app bundles (.app folders) on freemac: their names and their own icons.

A Mac app is a folder named Something.app. Its Contents/Info.plist says what
it is called and which icon it uses: CFBundleIconFile names an .icns file in
Contents/Resources. freemac reads that icon so the app looks like itself in
the dock, the app grid, search and Drawer, the way it does on a Mac.

The .icns format is publicly documented: a header ("icns" and a length), then
entries, each a four-letter type, a length and data. Newer entries hold PNG
images; older ones hold run-length-encoded RGB with a separate 8-bit mask.
This reads both, from the app's own file on this computer; nothing is copied
from anywhere else, and no Apple code is used. Apps whose icon only lives in
a compiled asset catalogue (Assets.car, CFBundleIconName) get freemac's
generic app icon instead.

    freemac-mac-app install Foo.app [--system]   copy it to Applications and add it to the app grid
    freemac-mac-app remove Foo.app               the opposite
    freemac-mac-app open Foo.app [FILE...]       run it with Ferry, if it can be, and open the files in it
    freemac-mac-app icon Foo.app out.png         write its icon as a PNG
    freemac-mac-app scan                         add apps found in Applications to the app grid

Ferry runs Mac apps built only on the frameworks it has so far; when it can't
run one, opening it says so plainly instead of failing silently. What Ferry
said the last time an app was opened is kept in
~/.cache/freemac/ferry/<app name>.log.
"""
import hashlib
import os
import plistlib
import re
import shutil
import socket
import struct
import subprocess
import sys

import gi

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, Gio, GLib  # noqa: E402

GENERIC_ICON = "freemac-mac-app"
ICON_PREFIX = "ferry-"     # icon and .desktop names; the icon tiler leaves these alone
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"

# Legacy RGB entries and their masks: type -> (size, mask type)
LEGACY = {
    b"it32": (128, b"t8mk"),
    b"ih32": (48, b"h8mk"),
    b"il32": (32, b"l8mk"),
    b"is32": (16, b"s8mk"),
}


# ---- bundles -----------------------------------------------------------
def is_bundle(path):
    return (path.rstrip("/").lower().endswith(".app") and os.path.isdir(path)
            and os.path.isfile(os.path.join(path, "Contents", "Info.plist")))


def info(path):
    try:
        with open(os.path.join(path, "Contents", "Info.plist"), "rb") as f:
            data = plistlib.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, plistlib.InvalidFileException, ValueError, TypeError):
        return {}


def display_name(path, plist=None):
    plist = info(path) if plist is None else plist
    for key in ("CFBundleDisplayName", "CFBundleName"):
        value = plist.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return os.path.basename(path.rstrip("/"))[:-4]


def bundle_id(path, plist=None):
    plist = info(path) if plist is None else plist
    value = plist.get("CFBundleIdentifier")
    if not isinstance(value, str) or not value:
        value = "local." + display_name(path, plist)
    return re.sub(r"[^A-Za-z0-9._-]", "-", value)


def item_name(path, plist=None):
    """Name of the app's icon and .desktop file: ferry-org-example-app (dots
    become dashes, so a name never ends in something like ".png")."""
    return ICON_PREFIX + bundle_id(path, plist).replace(".", "-").lower()


def icon_file(path, plist=None):
    """The bundle's .icns file, or None."""
    plist = info(path) if plist is None else plist
    resources = os.path.join(path, "Contents", "Resources")
    names = []
    value = plist.get("CFBundleIconFile")
    if isinstance(value, str) and value:
        names.append(value if value.lower().endswith(".icns") else value + ".icns")
    value = plist.get("CFBundleIconName")
    if isinstance(value, str) and value:
        names.append(value + ".icns")      # some apps ship both
    for name in names:
        candidate = os.path.join(resources, os.path.basename(name))
        if os.path.isfile(candidate):
            return candidate
    return None


def executable(path, plist=None):
    plist = info(path) if plist is None else plist
    name = plist.get("CFBundleExecutable")
    if not isinstance(name, str) or not name:
        name = display_name(path, plist)
    candidate = os.path.join(path, "Contents", "MacOS", os.path.basename(name))
    return candidate if os.path.isfile(candidate) else None


# ---- .icns -------------------------------------------------------------
def icns_entries(data):
    """{type: data} for each entry of an .icns file's bytes."""
    if len(data) < 8 or data[:4] != b"icns":
        raise ValueError("not an .icns file")
    total = min(struct.unpack(">I", data[4:8])[0], len(data))
    entries, at = {}, 8
    while at + 8 <= total:
        kind, length = data[at:at + 4], struct.unpack(">I", data[at + 4:at + 8])[0]
        if length < 8 or at + length > total:
            break
        entries.setdefault(kind, data[at + 8:at + length])
        at += length
    return entries


def unpack_rle(data, pixels):
    """The three channels of a legacy RGB entry: runs of literal bytes
    (a count byte under 0x80, then count+1 bytes) or repeats (a count byte of
    0x80 or more, then one byte repeated count-125 times), red, then green,
    then blue. it32 data starts with four zero bytes."""
    out = bytearray()
    at, need = 0, pixels * 3
    while at < len(data) and len(out) < need:
        n = data[at]
        at += 1
        if n < 0x80:
            out += data[at:at + n + 1]
            at += n + 1
        else:
            if at >= len(data):
                break
            out += bytes([data[at]]) * (n - 125)
            at += 1
    if len(out) < need:
        raise ValueError("short RGB data")
    return out[:pixels], out[pixels:2 * pixels], out[2 * pixels:need]


def legacy_pixbuf(entries, kind):
    size, mask_kind = LEGACY[kind]
    data = entries[kind]
    if kind == b"it32" and data[:4] == b"\0\0\0\0":
        data = data[4:]
    pixels = size * size
    if len(data) == pixels * 3:
        red, green, blue = data[:pixels], data[pixels:2 * pixels], data[2 * pixels:]
    else:
        red, green, blue = unpack_rle(data, pixels)
    mask = entries.get(mask_kind)
    alpha = mask if mask is not None and len(mask) >= pixels else b"\xff" * pixels
    rgba = bytearray(pixels * 4)
    rgba[0::4], rgba[1::4], rgba[2::4], rgba[3::4] = red, green, blue, alpha[:pixels]
    return GdkPixbuf.Pixbuf.new_from_bytes(GLib.Bytes.new(bytes(rgba)), GdkPixbuf.Colorspace.RGB,
                                           True, 8, size, size, size * 4)


def png_pixbuf(data):
    loader = GdkPixbuf.PixbufLoader.new_with_type("png")
    loader.write(data)
    loader.close()
    return loader.get_pixbuf()


def icns_pixbuf(path):
    """The largest picture in an .icns file, as a GdkPixbuf, or None."""
    with open(path, "rb") as f:
        data = f.read(64 * 1024 * 1024)
    entries = icns_entries(data)
    best = None
    for kind, body in entries.items():
        if body.startswith(PNG_MAGIC):
            try:
                pixbuf = png_pixbuf(body)
            except GLib.Error:
                continue
            if pixbuf and (best is None or pixbuf.get_width() > best.get_width()):
                best = pixbuf
    if best is not None and best.get_width() >= 128:
        return best
    for kind in LEGACY:            # largest first
        if kind in entries:
            try:
                legacy = legacy_pixbuf(entries, kind)
            except (ValueError, GLib.Error):
                continue
            if best is None or legacy.get_width() > best.get_width():
                best = legacy
            break
    return best


def bundle_pixbuf(path, size):
    """The app's own icon at size px, or None (then use GENERIC_ICON)."""
    source = icon_file(path)
    if not source:
        return None
    try:
        pixbuf = icns_pixbuf(source)
    except (OSError, ValueError, GLib.Error):
        return None
    if pixbuf is None:
        return None
    return pixbuf.scale_simple(size, size, GdkPixbuf.InterpType.HYPER)


def cached_icon(path, size):
    """bundle_pixbuf, kept in ~/.cache/freemac/app-icons between runs."""
    try:
        stamp = os.stat(os.path.join(path, "Contents", "Info.plist")).st_mtime
    except OSError:
        return None
    key = hashlib.sha1(f"{os.path.realpath(path)}|{stamp}|{size}".encode()).hexdigest()
    folder = os.path.join(GLib.get_user_cache_dir(), "freemac", "app-icons")
    cached = os.path.join(folder, key + ".png")
    if os.path.isfile(cached):
        try:
            return GdkPixbuf.Pixbuf.new_from_file(cached)
        except GLib.Error:
            pass
    pixbuf = bundle_pixbuf(path, size)
    if pixbuf is not None:
        try:
            os.makedirs(folder, exist_ok=True)
            pixbuf.savev(cached, "png", [], [])
        except (OSError, GLib.Error):
            pass
    return pixbuf


# ---- the documents an app opens -------------------------------------------
# A Mac app lists the kinds of file it opens in CFBundleDocumentTypes: by MIME
# type, by file extension, or by Uniform Type Identifier. freemac's app list
# (and so Drawer's Open With, its Get Info and the Dock) knows kinds of file
# by MIME type, so each is turned into one. Extensions are looked up in the
# system's own list of file types (shared-mime-info); identifiers by this
# table of Apple's published public ones and common third-party ones.
UTI_MIME = {
    "public.plain-text": "text/plain", "public.utf8-plain-text": "text/plain", "public.html": "text/html",
    "public.xml": "application/xml", "public.json": "application/json", "public.rtf": "text/rtf",
    "public.comma-separated-values-text": "text/csv", "public.markdown": "text/markdown",
    "net.daringfireball.markdown": "text/markdown", "com.adobe.pdf": "application/pdf",
    "public.jpeg": "image/jpeg", "public.png": "image/png", "com.compuserve.gif": "image/gif",
    "public.tiff": "image/tiff", "com.microsoft.bmp": "image/bmp", "public.heic": "image/heic",
    "org.webmproject.webp": "image/webp", "public.svg-image": "image/svg+xml",
    "com.microsoft.ico": "image/vnd.microsoft.icon",
    "public.mp3": "audio/mpeg", "public.mpeg-4-audio": "audio/mp4", "com.apple.m4a-audio": "audio/mp4",
    "public.aac-audio": "audio/aac", "public.aiff-audio": "audio/x-aiff", "public.aifc-audio": "audio/x-aifc",
    "com.microsoft.waveform-audio": "audio/x-wav", "public.midi-audio": "audio/midi",
    "org.xiph.flac": "audio/flac", "org.xiph.opus": "audio/x-opus+ogg", "org.xiph.ogg-audio": "audio/ogg",
    "org.xiph.ogg-video": "video/ogg", "public.ac3-audio": "audio/ac3",
    "org.3gpp.adaptive-multi-rate-audio": "audio/AMR", "com.microsoft.windows-media-wma": "audio/x-ms-wma",
    "com.microsoft.windows-media-wmv": "video/x-ms-wmv", "com.microsoft.windows-media-wm": "video/x-ms-asf",
    "com.microsoft.advanced-systems-format": "video/x-ms-asf",
    "com.microsoft.advanced-stream-redirector": "audio/x-ms-asx",
    "com.real.realmedia": "application/vnd.rn-realmedia", "com.real.realmedia-vbr": "application/vnd.rn-realmedia",
    "com.real.realaudio": "audio/vnd.rn-realaudio", "public.mpeg-4": "video/mp4",
    "com.apple.m4v-video": "video/x-m4v", "com.apple.quicktime-movie": "video/quicktime",
    "public.avi": "video/x-msvideo", "public.mpeg": "video/mpeg", "public.mpeg-2-video": "video/mpeg",
    "public.mpeg-2-transport-stream": "video/mp2t", "public.3gpp": "video/3gpp", "public.3gpp2": "video/3gpp2",
    "public.dv-movie": "video/dv", "com.adobe.flash.video": "video/x-flv", "org.matroska.mkv": "video/x-matroska",
    "org.matroska.mka": "audio/x-matroska", "org.webmproject.webm": "video/webm",
    "public.m3u-playlist": "audio/x-mpegurl", "public.pls-playlist": "audio/x-scpls",
    "public.iso-image": "application/x-cd-image", "com.rarlab.rar-archive": "application/vnd.rar",
    "public.zip-archive": "application/zip", "org.gnu.gnu-zip-archive": "application/gzip",
    "public.tar-archive": "application/x-tar",
}
# Kinds of file no app takes over just by listing them: anything at all, and
# folders and disks, which Drawer opens itself.
NOT_CLAIMED = {"application/octet-stream", "inode/directory", "inode/mount-point"}


def known_mime(mime):
    """The system's own name for a MIME type (aliases resolved), or None when
    the system doesn't know the type."""
    if not isinstance(mime, str) or "/" not in mime:
        return None
    canonical = Gio.content_type_from_mime_type(mime.strip())
    if not canonical or canonical not in _registered():
        return None
    return Gio.content_type_get_mime_type(canonical) or canonical


_REGISTERED = None


def _registered():
    global _REGISTERED
    if _REGISTERED is None:
        _REGISTERED = set(Gio.content_types_get_registered())
    return _REGISTERED


def document_types(plist):
    """The MIME types of the documents the app says it opens, sorted."""
    found = set()
    kinds = plist.get("CFBundleDocumentTypes")
    for kind in kinds if isinstance(kinds, list) else []:
        if not isinstance(kind, dict) or kind.get("CFBundleTypeRole") == "None":
            continue
        names = []
        for mime in kind.get("CFBundleTypeMIMETypes") or []:
            names.append(mime)
        for uti in kind.get("LSItemContentTypes") or []:
            names.append(UTI_MIME.get(uti) if isinstance(uti, str) else None)
        for ext in kind.get("CFBundleTypeExtensions") or []:
            if isinstance(ext, str) and ext.strip(". ") and ext not in ("*", "****"):
                guess, uncertain = Gio.content_type_guess("file." + ext.strip(". ").lower(), None)
                if not uncertain:
                    names.append(Gio.content_type_get_mime_type(guess) or guess)
        for name in names:
            mime = known_mime(name)
            if mime and mime not in NOT_CLAIMED:
                found.add(mime)
    return sorted(found)


# ---- installing ----------------------------------------------------------
def places(system):
    if system:
        return "/Applications", "/usr/local/share"
    home = os.path.expanduser("~")
    return os.path.join(home, "Applications"), GLib.get_user_data_dir()


def desktop_escape(text):
    return text.replace("\\", "\\\\").replace("\n", " ")


def exec_quote(arg):
    return '"' + re.sub(r'(["`$\\])', r"\\\1", arg) + '"'


def install(source, system=False, copy=True):
    """Put an app in Applications and in the app grid. Returns its new path."""
    source = os.path.abspath(source.rstrip("/"))
    if not is_bundle(source):
        raise ValueError(f"{os.path.basename(source)} isn't a Mac app (no Contents/Info.plist).")
    apps_folder, data = places(system)
    target = os.path.join(apps_folder, os.path.basename(source))
    if copy and os.path.realpath(source) != os.path.realpath(target):
        os.makedirs(apps_folder, exist_ok=True)
        if os.path.exists(target):
            shutil.rmtree(target)
        shutil.copytree(source, target, symlinks=True)
    elif not copy:
        target = source
    plist = info(target)
    name = display_name(target, plist)
    icon_name = item_name(target, plist)
    pixbuf = bundle_pixbuf(target, 512)
    icon_dir = os.path.join(data, "icons", "hicolor", "512x512", "apps")
    icon_path = os.path.join(icon_dir, icon_name + ".png")
    if pixbuf is not None:
        os.makedirs(icon_dir, exist_ok=True)
        pixbuf.savev(icon_path, "png", [], [])
    elif os.path.exists(icon_path):
        os.remove(icon_path)
    apps = os.path.join(data, "applications")
    os.makedirs(apps, exist_ok=True)
    version = plist.get("CFBundleShortVersionString")
    lines = [
        "[Desktop Entry]",
        "Type=Application",
        f"Name={desktop_escape(name)}",
        "Comment=" + desktop_escape(f"Mac app{' ' + version if isinstance(version, str) else ''}"),
        "Exec=freemac-mac-app open " + exec_quote(target) + " %F",
        f"Icon={icon_name if pixbuf is not None else GENERIC_ICON}",
        "Categories=Utility;",
        "X-freemac-MacApp=" + desktop_escape(target),
    ]
    # The documents it opens, so Drawer offers it for them (Open With, a
    # file dropped on its Dock icon), as a Mac's Finder does.
    mimes = document_types(plist)
    if mimes:
        lines.insert(-1, "MimeType=" + "".join(m + ";" for m in mimes))
    with open(os.path.join(apps, icon_name + ".desktop"), "w") as f:
        f.write("\n".join(lines) + "\n")
    refresh(data)
    return target


def remove(path, system=False):
    path = os.path.abspath(path.rstrip("/"))
    apps_folder, data = places(system)
    item = item_name(path) if is_bundle(path) else None
    if item:
        for leftover in (os.path.join(data, "applications", item + ".desktop"),
                         os.path.join(data, "icons", "hicolor", "512x512", "apps", item + ".png")):
            if os.path.exists(leftover):
                os.remove(leftover)
    if os.path.dirname(path) == apps_folder and os.path.isdir(path):
        shutil.rmtree(path)
    refresh(data)


def refresh(data):
    for cmd in (["update-desktop-database", os.path.join(data, "applications")],
                ["gtk-update-icon-cache", "-f", "-t", "-q", os.path.join(data, "icons", "hicolor")]):
        if shutil.which(cmd[0]) and os.path.isdir(cmd[-1]):
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def scan():
    """Bring the app grid in line with the Applications folders: add every Mac
    app found there (without copying it) and drop entries whose app is gone.
    Run at login, so an app dragged into Applications shows up like on a Mac."""
    added = 0
    for system in (False, True):
        apps_folder, data = places(system)
        if system and not os.access(os.path.join(data, "applications"), os.W_OK):
            continue
        listed = os.path.join(data, "applications")
        known = set()
        if os.path.isdir(listed):
            for name in os.listdir(listed):
                if not (name.startswith(ICON_PREFIX) and name.endswith(".desktop")):
                    continue
                target = None
                try:
                    with open(os.path.join(listed, name)) as f:
                        for line in f:
                            if line.startswith("X-freemac-MacApp="):
                                target = line.split("=", 1)[1].strip()
                except OSError:
                    continue
                if target and is_bundle(target):
                    known.add(os.path.realpath(target))
                elif target:
                    os.remove(os.path.join(listed, name))
                    stale_icon = os.path.join(data, "icons", "hicolor", "512x512", "apps", name[:-8] + ".png")
                    if os.path.exists(stale_icon):
                        os.remove(stale_icon)
        if os.path.isdir(apps_folder):
            for name in sorted(os.listdir(apps_folder)):
                path = os.path.join(apps_folder, name)
                if is_bundle(path) and os.path.realpath(path) not in known:
                    try:
                        install(path, system, copy=False)
                        added += 1
                    except (OSError, ValueError):
                        pass
    return added


def in_applications(path):
    folder = os.path.dirname(os.path.realpath(path))
    return folder in {os.path.realpath(places(s)[0]) for s in (False, True)}


# ---- opening -------------------------------------------------------------
def notify(title, body):
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", "--app-name=Drawer", "--icon=" + GENERIC_ICON, title, body],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        print(f"{title}: {body}", file=sys.stderr)


def open_socket(path, plist=None):
    """Where the app, once running under Ferry, listens for files to open
    (Ferry's AppKit makes it): $XDG_RUNTIME_DIR/ferry/<bundle id>.open."""
    plist = info(path) if plist is None else plist
    ident = plist.get("CFBundleIdentifier")
    if not isinstance(ident, str) or not ident:
        return None
    return os.path.join(GLib.get_user_runtime_dir(), "ferry", re.sub(r"[^A-Za-z0-9._-]", "-", ident) + ".open")


def hand_to_running(path, files, plist=None):
    """Give the files to the copy of the app that's already running, as a Mac
    does (with none, it comes to the front). True when one took them."""
    where = open_socket(path, plist)
    if not where or not os.path.exists(where):
        return False
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.settimeout(3)
            conn.connect(where)
            conn.sendall("".join(f + "\n" for f in files).encode("utf-8", "surrogateescape"))
            conn.shutdown(socket.SHUT_WR)
            return conn.recv(16).startswith(b"ok")
    except OSError:
        return False


def open_app(path, files=()):
    files = [os.path.abspath(f) for f in files if "\n" not in f]
    plist = info(path)
    if hand_to_running(path, files, plist):
        return 0
    name = display_name(path, plist)
    program = executable(path, plist)
    if program is None:
        notify(f"“{name}” can't be opened", "It has no program inside it.")
        return 1
    if not shutil.which("ferry"):
        notify(f"“{name}” is a Mac app",
               "Mac apps open with Ferry, freemac's runner for Mac apps, which isn't on this "
               "computer. Software Update adds it.")
        return 1
    # Ferry stops at once, with a message naming the reason, when a program
    # needs something it doesn't have yet (a Mac framework such as AppKit).
    # What it says goes to a log file rather than a pipe: an app that keeps
    # running and keeps writing would otherwise fill the pipe and freeze.
    log = log_path(name)
    with open(log, "wb") as sink:
        child = subprocess.Popen(["ferry", program] + files, stdout=sink, stderr=subprocess.STDOUT,
                                 start_new_session=True, cwd=os.path.dirname(program))
    try:
        status = child.wait(timeout=3)
    except subprocess.TimeoutExpired:
        return 0
    if status != 0:
        reason = last_line(log)
        notify(f"“{name}” can't open yet",
               ((reason + " ") if reason else "") + "Ferry can't run this app yet.")
        return 1
    return 0


LOG_DIR = os.path.join(GLib.get_user_cache_dir(), "freemac", "ferry")


def log_path(name):
    """~/.cache/freemac/ferry/<name>.log: what Ferry said the last time this
    app was opened, for anyone who wants to see why it stopped."""
    os.makedirs(LOG_DIR, exist_ok=True)
    safe = re.sub(r"[^\w .-]", "_", name).strip(" .") or "app"
    return os.path.join(LOG_DIR, safe[:80] + ".log")


def last_line(path):
    try:
        with open(path, "rb") as handle:
            handle.seek(0, os.SEEK_END)
            handle.seek(max(0, handle.tell() - 4096))
            lines = handle.read().decode("utf-8", "replace").strip().splitlines()
    except OSError:
        return ""
    return lines[-1].strip() if lines else ""


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    system = "--system" in argv
    args = [a for a in argv if not a.startswith("--")]
    if args[:1] == ["scan"]:
        scan()
        return 0
    if len(args) < 2 or args[0] not in ("install", "remove", "open", "icon"):
        print(__doc__.split("\n\n")[3], file=sys.stderr)
        return 2
    action, path = args[0], args[1]
    try:
        if action == "install":
            print(install(path, system))
        elif action == "remove":
            remove(path, system)
        elif action == "open":
            return open_app(path, args[2:])
        elif action == "icon":
            pixbuf = bundle_pixbuf(path, int(args[3]) if len(args) > 3 else 512)
            if pixbuf is None:
                print("This app has no icon freemac can read; it gets the generic app icon.", file=sys.stderr)
                return 1
            pixbuf.savev(args[2] if len(args) > 2 else "icon.png", "png", [], [])
    except (OSError, ValueError) as err:
        print(err, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
