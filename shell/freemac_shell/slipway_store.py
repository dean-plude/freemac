# SPDX-License-Identifier: GPL-3.0-or-later
"""What Slipway needs to know about a downloaded app package (.deb) before
installing it: its name, version, publisher, size, description, the app it
adds (its .desktop file) and that app's icon, whether this computer can run
it, what is installed already, and where it was downloaded from.

Everything is read with dpkg-deb, without installing or running anything
from the package. Original freemac code.
"""
import configparser
import os
import re
import subprocess
import tarfile
import time
from urllib.parse import urlparse

ICON_LIMIT = 2 * 1024 * 1024        # a bigger "icon" is not an icon
ICONS_KEPT = 64 * 1024 * 1024       # at most this much held while reading


class NotAPackage(Exception):
    pass


def _run(*args, timeout=60):
    try:
        done = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None
    return done.stdout if done.returncode == 0 else None


def control(path):
    """The package's control fields: Package, Version, Architecture,
    Maintainer, Installed-Size, Description, Homepage, Depends..."""
    text = _run("dpkg-deb", "--field", path)
    if not text:
        raise NotAPackage(path)
    fields, key = {}, None
    for line in text.splitlines():
        if line.startswith((" ", "\t")) and key:
            fields[key] += "\n" + line[1:]
        elif ":" in line:
            key, _, value = line.partition(":")
            key = key.strip()
            fields[key] = value.strip()
    if not fields.get("Package"):
        raise NotAPackage(path)
    return fields


def description(fields):
    """(summary, the long description as paragraphs)."""
    lines = fields.get("Description", "").split("\n")
    summary = lines[0].strip()
    paragraphs, current = [], []
    for line in lines[1:]:
        if line.strip() == ".":
            if current:
                paragraphs.append(" ".join(current))
            current = []
        else:
            current.append(line.strip())
    if current:
        paragraphs.append(" ".join(current))
    return summary, [p for p in paragraphs if p]


def publisher(fields):
    """The maintainer's name, without the email address."""
    name = re.sub(r"\s*<[^>]*>", "", fields.get("Maintainer", "")).strip()
    return name or None


def size_words(fields):
    try:
        kb = int(fields.get("Installed-Size", ""))
    except ValueError:
        return None
    size = kb * 1024
    for unit in ("bytes", "KB", "MB", "GB"):
        if size < 1000 or unit == "GB":
            return f"{size:.0f} {unit}" if unit in ("bytes", "KB") else f"{size:.1f} {unit}"
        size /= 1000
    return None


def machine():
    return (_run("dpkg", "--print-architecture") or "amd64").strip()


ARCH_WORDS = {"arm64": "ARM computers (arm64)", "armhf": "older ARM computers (armhf)",
              "i386": "older 32-bit PCs (i386)", "amd64": "64-bit PCs (amd64)"}


def runs_here(fields):
    arch = fields.get("Architecture", "all")
    return arch in ("all", machine())


def installed_version(name):
    out = _run("dpkg-query", "-W", "-f", "${db:Status-Abbrev}\t${Version}", name, timeout=15)
    if not out:
        return None
    status, _, version = out.partition("\t")
    return version.strip() if status.startswith("ii") else None


def compare(a, b):
    """-1, 0 or 1 as version a is older than, the same as or newer than b."""
    if a == b:
        return 0
    try:
        if subprocess.run(["dpkg", "--compare-versions", a, "lt", b], timeout=10).returncode == 0:
            return -1
    except (OSError, subprocess.SubprocessError):
        return 0
    return 1


def origin(path):
    """(site, when) the file was downloaded from, as browsers note it on the
    file (user.xdg.origin.url); (None, None) when it doesn't say."""
    site = None
    try:
        url = os.getxattr(path, "user.xdg.origin.url").decode("utf-8", "replace")
        site = urlparse(url).hostname
    except (OSError, AttributeError, ValueError):
        pass
    try:
        when = os.stat(path).st_mtime
    except OSError:
        when = None
    return site, when


def when_words(when):
    if not when:
        return ""
    days = (time.time() - when) / 86400
    if days < 1 and time.localtime(when).tm_yday == time.localtime().tm_yday:
        return "today"
    if days < 2:
        return "yesterday"
    return time.strftime("on %-d %B %Y", time.localtime(when))


def _desktop(text):
    parser = configparser.RawConfigParser(strict=False, interpolation=None)
    parser.optionxform = str
    try:
        parser.read_string(text)
        return dict(parser["Desktop Entry"])
    except (configparser.Error, KeyError):
        return None


def contents(path, package):
    """The app the package adds: {"desktop": file name, "name", "comment",
    "icon": (file name, bytes) or None}. Reads the package's files without
    unpacking them; None when it adds no app to the menus."""
    try:
        proc = subprocess.Popen(["dpkg-deb", "--fsys-tarfile", path], stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL)
    except OSError:
        return None
    desktops, icons, kept = {}, {}, 0
    try:
        with tarfile.open(fileobj=proc.stdout, mode="r|*") as tar:
            for member in tar:
                if not member.isfile():
                    continue
                name = member.name.lstrip("./")
                if name.startswith("usr/share/applications/") and name.endswith(".desktop"):
                    data = tar.extractfile(member).read(256 * 1024)
                    entry = _desktop(data.decode("utf-8", "replace"))
                    if entry:
                        desktops[os.path.basename(name)] = entry
                elif name.endswith((".png", ".svg", ".xpm")) and member.size <= ICON_LIMIT and \
                        kept + member.size <= ICONS_KEPT and \
                        (name.startswith(("usr/share/icons/", "usr/share/pixmaps/")) or "icon" in name.lower()
                         or "logo" in name.lower() or name.startswith("opt/")):
                    icons[name] = tar.extractfile(member).read()
                    kept += member.size
    except (tarfile.TarError, OSError, EOFError):
        pass
    finally:
        proc.stdout.close()
        proc.wait()
    shown = {k: v for k, v in desktops.items()
             if v.get("Type", "Application") == "Application" and v.get("NoDisplay", "false") != "true"}
    if not shown:
        return None
    # The package's own app first: the one named like it, else the first.
    key = next((k for k in shown if k.split(".desktop")[0].lower().endswith(package.lower())), sorted(shown)[0])
    entry = shown[key]
    return {"desktop": key, "name": entry.get("Name"), "comment": entry.get("Comment"),
            "icon": pick_icon(entry.get("Icon", ""), icons)}


def _icon_size(name):
    match = re.search(r"/(\d+)x\d+/", name)
    if match:
        return int(match.group(1))
    return 1000 if name.endswith(".svg") or "/scalable/" in name else 48


def pick_icon(icon, icons):
    """The best file for the .desktop file's Icon= among the package's."""
    if not icon:
        return None
    if icon.startswith("/"):
        data = icons.get(icon.lstrip("/"))
        return (os.path.basename(icon), data) if data else None
    found = [n for n in icons if os.path.splitext(os.path.basename(n))[0] == icon]
    if not found:
        return None
    best = max(found, key=lambda n: (min(_icon_size(n), 512), not n.endswith(".xpm")))
    return os.path.basename(best), icons[best]


def read(path):
    """Everything the first page shows, in one dict. Raises NotAPackage."""
    fields = control(path)
    summary, paragraphs = description(fields)
    app = contents(path, fields["Package"])
    site, when = origin(path)
    name = (app or {}).get("name") or fields["Package"]
    return {
        "path": path, "package": fields["Package"], "version": fields.get("Version", ""),
        "name": name, "summary": summary, "paragraphs": paragraphs, "publisher": publisher(fields),
        "homepage": fields.get("Homepage"), "size": size_words(fields),
        "arch": fields.get("Architecture", "all"), "runs_here": runs_here(fields),
        "installed": installed_version(fields["Package"]), "app": app, "site": site, "when": when,
    }


def icon_pixbuf(info, size):
    """The app's own icon at size, or None."""
    app = info.get("app") or {}
    if not app.get("icon"):
        return None
    import gi
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf, GLib
    try:
        loader = GdkPixbuf.PixbufLoader()
        loader.set_size(size, size)
        loader.write(app["icon"][1])
        loader.close()
        pixbuf = loader.get_pixbuf()
    except GLib.Error:
        return None
    if pixbuf and (pixbuf.get_width() != size or pixbuf.get_height() != size):
        pixbuf = pixbuf.scale_simple(size, size, GdkPixbuf.InterpType.BILINEAR)
    return pixbuf

