# SPDX-License-Identifier: GPL-3.0-or-later
"""Compressing and expanding archives in Drawer.

Compress makes a .zip next to the selected items ("Archive.zip" for several,
"<name>.zip" for one). Opening a .zip or a tar archive (.tar, .tar.gz, .tgz,
.tar.bz2, .tar.xz) expands it into a folder next to it, named after it.
Nothing is ever written outside that folder: entries with absolute paths or
"..", and links pointing out of it, are skipped.
"""
import os
import stat
import tarfile
import zipfile

TAR_ENDINGS = (".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2", ".tar.xz", ".txz")


def is_archive(path):
    lower = path.lower()
    return os.path.isfile(path) and (lower.endswith(".zip") or lower.endswith(TAR_ENDINGS))


def base_name(path):
    name = os.path.basename(path)
    lower = name.lower()
    for ending in (".zip",) + TAR_ENDINGS:
        if lower.endswith(ending):
            return name[: -len(ending)] or name
    return name


def unused(path):
    """path, or 'path 2', 'path 3', ... if it exists (keeping an extension)."""
    if not os.path.exists(path):
        return path
    root, ext = os.path.splitext(path) if os.path.isfile(path) or path.endswith(".zip") else (path, "")
    n = 2
    while os.path.exists(f"{root} {n}{ext}"):
        n += 1
    return f"{root} {n}{ext}"


def _inside(folder, name):
    target = os.path.realpath(os.path.join(folder, name))
    return target == folder or target.startswith(folder + os.sep)


def compress(paths, stop=None):
    """Zip paths into one archive beside the first. Returns the archive path."""
    paths = [p.rstrip(os.sep) for p in paths]
    parent = os.path.dirname(paths[0])
    name = os.path.basename(paths[0]) + ".zip" if len(paths) == 1 else "Archive.zip"
    target = unused(os.path.join(parent, name))
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in paths:
            if os.path.isdir(path) and not os.path.islink(path):
                for root, dirs, files in os.walk(path):
                    dirs.sort()
                    rel_root = os.path.relpath(root, parent)
                    if not files and not dirs:
                        archive.writestr(rel_root + "/", "")
                    for file_name in sorted(files):
                        full = os.path.join(root, file_name)
                        if stop is not None and stop.is_set():
                            raise InterruptedError
                        if os.path.islink(full) or not os.path.isfile(full):
                            continue
                        archive.write(full, os.path.join(rel_root, file_name))
            elif os.path.isfile(path):
                archive.write(path, os.path.basename(path))
    return target


def extract(path):
    """Expand an archive into a new folder beside it. Returns the folder."""
    folder = os.path.realpath(unused(os.path.join(os.path.dirname(path), base_name(path))))
    os.makedirs(folder)
    if path.lower().endswith(".zip"):
        with zipfile.ZipFile(path) as archive:
            for info in archive.infolist():
                name = info.filename
                if name.startswith("/") or not _inside(folder, name):
                    continue
                mode = info.external_attr >> 16
                if stat.S_ISLNK(mode):
                    continue      # links in zips are rare and easy to misuse
                archive.extract(info, folder)
                if mode & 0o111 and not info.is_dir():
                    os.chmod(os.path.join(folder, name), 0o755)
    else:
        with tarfile.open(path) as archive:
            members = [m for m in archive.getmembers()
                       if not m.name.startswith("/") and _inside(folder, m.name)
                       and not m.isdev() and not ((m.issym() or m.islnk())
                                                  and not _inside(folder, os.path.join(os.path.dirname(m.name),
                                                                                       m.linkname)))]
            try:
                archive.extractall(folder, members=members, filter="data")
            except TypeError:      # Pythons without extraction filters
                archive.extractall(folder, members=members)
    # An archive holding just one folder expands to that folder, not a folder in a folder.
    inside = os.listdir(folder)
    if len(inside) == 1 and os.path.isdir(os.path.join(folder, inside[0])):
        tmp = unused(folder + ".freemac-tmp")
        os.rename(folder, tmp)
        final = unused(os.path.join(os.path.dirname(folder), inside[0]))
        os.rename(os.path.join(tmp, inside[0]), final)
        os.rmdir(tmp)
        return final
    return folder
