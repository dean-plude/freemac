# SPDX-License-Identifier: GPL-3.0-or-later
"""Drawer's Compress and archive opening (drawer_archive.py), above all the
symbolic links a Mac app's frameworks need (freemac 1.243). Run from the
repository with

    python3 -m unittest discover -s shell/tests
"""
import os
import stat
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from freemac_shell import drawer_archive  # noqa: E402


def make_app(parent):
    """A Mac app laid out as OBS's is: a framework with Versions/Current and
    links beside it, and an executable."""
    app = os.path.join(parent, "Demo.app")
    fw = os.path.join(app, "Contents", "Frameworks", "QtCore.framework")
    os.makedirs(os.path.join(fw, "Versions", "A", "Resources"))
    with open(os.path.join(fw, "Versions", "A", "QtCore"), "w") as f:
        f.write("library")
    with open(os.path.join(fw, "Versions", "A", "Resources", "Info.plist"), "w") as f:
        f.write("plist")
    os.symlink("A", os.path.join(fw, "Versions", "Current"))
    os.symlink("Versions/Current/QtCore", os.path.join(fw, "QtCore"))
    os.symlink("Versions/Current/Resources", os.path.join(fw, "Resources"))
    os.makedirs(os.path.join(app, "Contents", "MacOS"))
    exe = os.path.join(app, "Contents", "MacOS", "Demo")
    with open(exe, "w") as f:
        f.write("program")
    os.chmod(exe, 0o755)
    return app


class Links(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = os.path.realpath(self.dir.name)

    def tearDown(self):
        self.dir.cleanup()

    def test_an_app_keeps_its_framework_links_through_compress_and_open(self):
        src = os.path.join(self.root, "src")
        os.makedirs(src)
        app = make_app(src)
        archive = drawer_archive.compress([app])
        self.assertEqual(os.path.basename(archive), "Demo.app.zip")
        out = os.path.join(self.root, "out")
        os.makedirs(out)
        moved = os.path.join(out, "Demo.app.zip")
        os.rename(archive, moved)
        opened = drawer_archive.extract(moved)
        self.assertEqual(os.path.basename(opened), "Demo.app")
        fw = os.path.join(opened, "Contents", "Frameworks", "QtCore.framework")
        self.assertEqual(os.readlink(os.path.join(fw, "Versions", "Current")), "A")
        self.assertEqual(os.readlink(os.path.join(fw, "QtCore")), "Versions/Current/QtCore")
        self.assertEqual(os.readlink(os.path.join(fw, "Resources")), "Versions/Current/Resources")
        with open(os.path.join(fw, "QtCore")) as f:
            self.assertEqual(f.read(), "library")
        with open(os.path.join(fw, "Resources", "Info.plist")) as f:
            self.assertEqual(f.read(), "plist")
        self.assertTrue(os.access(os.path.join(opened, "Contents", "MacOS", "Demo"), os.X_OK))

    def test_links_out_of_the_folder_are_skipped(self):
        path = os.path.join(self.root, "bad.zip")
        with zipfile.ZipFile(path, "w") as z:
            for name, target in (("up", "../outside"), ("abs", "/etc/passwd"), ("deep", "a/../../x"),
                                 ("ok", "file.txt")):
                info = zipfile.ZipInfo(name)
                info.create_system = 3
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                z.writestr(info, target)
            z.writestr("file.txt", "hello")
            z.writestr("up/escape.txt", "no")
        folder = drawer_archive.extract(path)
        self.assertEqual(sorted(os.listdir(folder)), ["file.txt", "ok", "up"])
        self.assertTrue(os.path.isdir(os.path.join(folder, "up")))       # a plain folder, not the link
        self.assertFalse(os.path.islink(os.path.join(folder, "up")))
        self.assertEqual(os.readlink(os.path.join(folder, "ok")), "file.txt")
        self.assertFalse(os.path.exists(os.path.join(self.root, "outside")))

    def test_a_link_given_alone_is_zipped_as_a_link(self):
        target = os.path.join(self.root, "notes.txt")
        with open(target, "w") as f:
            f.write("x")
        link = os.path.join(self.root, "Notes")
        os.symlink("notes.txt", link)
        with zipfile.ZipFile(drawer_archive.compress([link])) as z:
            info = z.getinfo("Notes")
            self.assertTrue(stat.S_ISLNK(info.external_attr >> 16))
            self.assertEqual(z.read(info), b"notes.txt")


if __name__ == "__main__":
    unittest.main()
