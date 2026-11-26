#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Make the update bundle that installed freemac computers download from
Dials > Software Update (see build/overlay/usr/libexec/freemac-update-helper).

  make-update-bundle.py ROOTFS VERSION BASE OUTDIR

build-iso.sh runs it on the finished image, so the bundle holds exactly the
freemac files the ISO has: the shell, the apps' launchers and icons, the
helpers, themes, wallpapers, sounds, Strata's plugins, Ferry (freemac's runner
for Mac apps, when the image has it), freemac's own files in /etc, and /etc/os-release with the new version. It writes
freemac-update-VERSION-BASE-amd64.tar.xz and its .sha256 into OUTDIR.
Original freemac code.
"""
import glob
import hashlib
import io
import json
import os
import stat
import sys
import tarfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "scripts"))
import whats_new  # noqa: E402

HELPER = os.path.join(REPO, "build", "overlay", "usr", "libexec", "freemac-update-helper")
ARCH = "amd64"

# Folders that are freemac's own, whole.
FOLDERS = (
    "usr/lib/python3/dist-packages/freemac_shell",
    "usr/share/icons/freemac",
    "usr/share/freemac",
    "usr/share/backgrounds/freemac",
    "usr/share/sounds/freemac",
    "usr/share/plymouth/themes/freemac",
    # Ferry, freemac's runner for Mac apps: its frameworks, Installer and SDK.
    "usr/lib/ferry",
    "usr/share/ferry",
)
# Other freemac files in the image, as patterns.
PATTERNS = (
    "usr/share/themes/freemac*/**",
    "usr/share/Kvantum/freemac*/**",
    "usr/lib/*/wayfire/libstrata-*.so",
    "usr/share/wayfire/metadata/strata-*.xml",
    "usr/lib/*/gtk-3.0/modules/libfreemac-zoom.so",
    "usr/lib/gtklock/freemac-latch.so",
    "usr/local/bin/freemac-*",
    "usr/libexec/freemac-*",
    "usr/share/polkit-1/actions/org.freemac.*",
    "etc/os-release",
    "usr/bin/ferry",
    "usr/bin/ferry-*",
    "usr/lib/binfmt.d/ferry.conf",
    "usr/share/applications/ferry-installer.desktop",
)


def _helper():
    from importlib.machinery import SourceFileLoader
    return SourceFileLoader("freemac_update_helper", HELPER).load_module()


def from_repo():
    """Files the build copies straight from the checkout."""
    paths = []
    for name in os.listdir(os.path.join(REPO, "shell", "bin")):
        paths.append("usr/bin/" + name)
    for name in os.listdir(os.path.join(REPO, "shell", "applications")):
        paths.append("usr/share/applications/" + name)
    for name in os.listdir(os.path.join(REPO, "art", "icons")):
        paths.append("usr/share/icons/hicolor/scalable/apps/" + name)
    overlay = os.path.join(REPO, "build", "overlay")
    for top, dirs, files in os.walk(overlay):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for name in files:
            paths.append(os.path.relpath(os.path.join(top, name), overlay))
    return paths


def collect(rootfs):
    helper = _helper()
    found = set()
    for folder in FOLDERS:
        for top, dirs, files in os.walk(os.path.join(rootfs, folder)):
            dirs[:] = [d for d in dirs if d != "__pycache__"]
            for name in files:
                found.add(os.path.relpath(os.path.join(top, name), rootfs))
    for pattern in PATTERNS:
        for path in glob.glob(os.path.join(rootfs, pattern), recursive=True):
            if not os.path.isdir(path) or os.path.islink(path):
                found.add(os.path.relpath(path, rootfs))
    for path in from_repo():
        if os.path.lexists(os.path.join(rootfs, path)):
            found.add(path)
    return sorted(p for p in found if helper.allowed(p) and "__pycache__" not in p.split("/"))


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def make(rootfs, version, kind, outdir):
    paths = collect(rootfs)
    files, links = {}, {}
    for path in paths:
        here = os.path.join(rootfs, path)
        if os.path.islink(here):
            links[path] = os.readlink(here)
        elif os.path.isfile(here):
            files[path] = {"sha256": sha256(here), "mode": stat.S_IMODE(os.stat(here).st_mode),
                           "size": os.path.getsize(here)}
    manifest = {"version": version, "base": kind, "arch": ARCH, "files": files, "links": links,
                "whats_new": whats_new.items(version)}
    os.makedirs(outdir, exist_ok=True)
    name = f"freemac-update-{version}-{kind}-{ARCH}.tar.xz"
    target = os.path.join(outdir, name)
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH", "0"))
    with tarfile.open(target, "w:xz", preset=6) as tar:
        data = json.dumps(manifest, indent=1, sort_keys=True).encode()
        info = tarfile.TarInfo("manifest.json")
        info.size, info.mtime, info.mode = len(data), epoch, 0o644
        tar.addfile(info, io.BytesIO(data))
        for path in sorted(files):
            info = tar.gettarinfo(os.path.join(rootfs, path), "files/" + path)
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            info.mtime = epoch
            with open(os.path.join(rootfs, path), "rb") as f:
                tar.addfile(info, f)
    with open(target + ".sha256", "w") as f:
        f.write(f"{sha256(target)}  {name}\n")
    total = sum(i["size"] for i in files.values())
    print(f"{name}: {len(files)} files, {len(links)} links, {total / 1e6:.1f} MB unpacked, "
          f"{os.path.getsize(target) / 1e6:.1f} MB to download")
    return target


if __name__ == "__main__":
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(2)
    make(*sys.argv[1:5])
