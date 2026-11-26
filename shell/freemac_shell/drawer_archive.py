# SPDX-License-Identifier: GPL-3.0-or-later
"""Compressing and expanding archives in Drawer.

Compress makes a .zip next to the selected items ("Archive.zip" for several,
"<name>.zip" for one). Opening a .zip or a tar archive (.tar, .tar.gz, .tgz,
.tar.bz2, .tar.xz) expands it into a folder next to it, named after it.
Nothing is ever written outside that folder: entries with absolute paths or
"..", and links pointing out of it, are skipped.

Symbolic links are kept both ways (freemac 1.243): a Mac app's frameworks
need theirs (Versions/Current and the links beside it), and Mac apps often
come as .zip files. A link in a .zip is kept only when it points inside the
folder, as in a tar archive.
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


def _link_entry(archive, link, arcname):
    """Store a symbolic link as a link, as Info-ZIP and a Mac's Archive Utility do."""
    info = zipfile.ZipInfo(arcname)
    info.create_system = 3                       # Unix, so the mode is read
    info.external_attr = (stat.S_IFLNK | 0o777) << 16
    archive.writestr(info, os.readlink(link))


def _link_inside(folder, name, target):
    """Whether a link at name (inside folder) pointing at target stays inside."""
    if os.path.isabs(target):
        return False
    return _inside(folder, os.path.join(os.path.dirname(name), target))


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
                    # links to folders are listed with the folders, and not walked into
                    for dir_name in [d for d in dirs if os.path.islink(os.path.join(root, d))]:
                        _link_entry(archive, os.path.join(root, dir_name), os.path.join(rel_root, dir_name))
                    for file_name in sorted(files):
                        full = os.path.join(root, file_name)
                        if stop is not None and stop.is_set():
                            raise InterruptedError
                        if os.path.islink(full):
                            _link_entry(archive, full, os.path.join(rel_root, file_name))
                        elif os.path.isfile(full):
                            archive.write(full, os.path.join(rel_root, file_name))
            elif os.path.islink(path):
                _link_entry(archive, path, os.path.basename(path))
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
                    target = archive.read(info).decode("utf-8", "replace")
                    where = os.path.join(folder, name.rstrip("/"))
                    if (target and "\0" not in target and _link_inside(folder, name.rstrip("/"), target)
                            and not os.path.lexists(where)):
                        os.makedirs(os.path.dirname(where), exist_ok=True)
                        os.symlink(target, where)
                    continue
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
