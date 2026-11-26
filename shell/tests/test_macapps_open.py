# SPDX-License-Identifier: GPL-3.0-or-later
"""Mac apps and the documents they open: the kinds of file a Mac app's
Info.plist lists go in its app grid entry (so Drawer's Open With, its Get
Info and the Dock offer the app for them), the files go to Ferry when the
app opens, and to the copy that's already running when there is one. Run
from the repository with

    python3 -m unittest discover -s shell/tests

(with a Python that has the gi bindings and GdkPixbuf's).
"""
import os
import plistlib
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

try:
    from gi.repository import Gio

    from freemac_shell import apps, macapps
except (ImportError, ValueError):   # no gi bindings (or no GdkPixbuf's) for this Python
    raise unittest.SkipTest("needs Python's gi bindings, with GdkPixbuf")

PLAYER = {
    "CFBundleIdentifier": "org.example.player",
    "CFBundleName": "Player",
    "CFBundleExecutable": "Player",
    "CFBundleDocumentTypes": [
        {"CFBundleTypeName": "Folder", "CFBundleTypeRole": "Viewer", "LSItemContentTypes": ["public.folder"]},
        {"CFBundleTypeName": "MPEG-4", "CFBundleTypeRole": "Viewer", "LSItemContentTypes": ["public.mpeg-4"]},
        {"CFBundleTypeName": "Matroska", "CFBundleTypeRole": "Viewer", "CFBundleTypeExtensions": ["mkv"]},
        {"CFBundleTypeName": "Wave", "CFBundleTypeRole": "Viewer", "CFBundleTypeMIMETypes": ["audio/x-wav"]},
        {"CFBundleTypeName": "Anything", "CFBundleTypeRole": "Viewer", "CFBundleTypeExtensions": ["*"]},
        {"CFBundleTypeName": "Its own", "CFBundleTypeRole": "Viewer",
         "LSItemContentTypes": ["org.example.player.list"], "CFBundleTypeExtensions": ["zzplayerlist"]},
        {"CFBundleTypeName": "Exported", "CFBundleTypeRole": "None", "CFBundleTypeExtensions": ["webm"]},
    ],
}


def make_app(folder, plist):
    app = os.path.join(folder, "Player.app")
    os.makedirs(os.path.join(app, "Contents", "MacOS"))
    with open(os.path.join(app, "Contents", "Info.plist"), "wb") as f:
        plistlib.dump(plist, f)
    program = os.path.join(app, "Contents", "MacOS", "Player")
    with open(program, "w") as f:
        f.write("")
    os.chmod(program, 0o755)
    return app


class DocumentTypes(unittest.TestCase):
    def test_kinds_of_file(self):
        found = macapps.document_types(PLAYER)
        # by identifier, by extension and by MIME type (an alias becomes the
        # system's own name for it)
        self.assertIn("video/mp4", found)
        self.assertIn("video/x-matroska", found)
        self.assertIn(macapps.known_mime("audio/x-wav"), found)
        self.assertEqual(found, sorted(found))
        # not folders, not "anything", not the app's own unknown kinds, not a
        # kind it only exports
        for left_out in ("inode/directory", "application/octet-stream", "video/webm"):
            self.assertNotIn(left_out, found)
        self.assertEqual(len(found), 3)

    def test_nothing_listed(self):
        self.assertEqual(macapps.document_types({}), [])
        self.assertEqual(macapps.document_types({"CFBundleDocumentTypes": "junk"}), [])


class Installing(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir)
        self.data = os.path.join(self.dir, "data")
        apps = os.path.join(self.dir, "Applications")
        patcher = mock.patch.object(macapps, "places", lambda system: (apps, self.data))
        patcher.start()
        self.addCleanup(patcher.stop)

    def entry(self, plist):
        app = make_app(self.dir, plist)
        macapps.install(app, copy=False)
        with open(os.path.join(self.data, "applications", macapps.item_name(app) + ".desktop")) as f:
            return dict(line.split("=", 1) for line in f.read().splitlines() if "=" in line)

    def test_entry_opens_files(self):
        entry = self.entry(PLAYER)
        self.assertTrue(entry["Exec"].endswith(" %F"))
        self.assertIn("video/mp4;", entry["MimeType"])
        self.assertIn("video/x-matroska;", entry["MimeType"])

    def test_no_document_types(self):
        entry = self.entry({"CFBundleIdentifier": "org.example.plain", "CFBundleExecutable": "Player"})
        self.assertNotIn("MimeType", entry)


class Opening(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir)
        self.app = make_app(self.dir, PLAYER)
        self.socket = os.path.join(self.dir, "ferry", "org.example.player.open")
        os.makedirs(os.path.dirname(self.socket))
        patcher = mock.patch.object(macapps.GLib, "get_user_runtime_dir", return_value=self.dir)
        patcher.start()
        self.addCleanup(patcher.stop)

    def listen(self):
        """A stand-in for the running app: notes what it's sent, answers ok."""
        got = []
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(self.socket)
        server.listen(1)
        self.addCleanup(server.close)

        def serve():
            conn, _ = server.accept()
            with conn:
                data = b""
                while True:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                got.append(data.decode())
                conn.sendall(b"ok\n")
        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        return got, thread

    def test_socket_name(self):
        self.assertEqual(macapps.open_socket(self.app), self.socket)
        self.assertIsNone(macapps.open_socket(self.app, {"CFBundleName": "No identifier"}))

    def test_files_go_to_the_running_copy(self):
        got, thread = self.listen()
        with mock.patch.object(subprocess, "Popen") as popen:
            self.assertEqual(macapps.open_app(self.app, ["/films/a.mkv", "b.mp4"]), 0)
        thread.join(5)
        popen.assert_not_called()
        self.assertEqual(got, [f"/films/a.mkv\n{os.path.abspath('b.mp4')}\n"])

    def test_opening_again_brings_it_forward(self):
        got, thread = self.listen()
        with mock.patch.object(subprocess, "Popen") as popen:
            self.assertEqual(macapps.open_app(self.app), 0)
        thread.join(5)
        popen.assert_not_called()
        self.assertEqual(got, [""])

    def test_started_with_the_files(self):
        """No copy running (or a socket left by one that crashed): Ferry runs
        the app with the files."""
        stale = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        stale.bind(self.socket)
        stale.close()
        child = mock.Mock()
        child.wait.side_effect = subprocess.TimeoutExpired("ferry", 3)
        with mock.patch.object(macapps.shutil, "which", return_value="/usr/bin/ferry"), \
                mock.patch.object(macapps, "LOG_DIR", self.dir), \
                mock.patch.object(subprocess, "Popen", return_value=child) as popen:
            self.assertEqual(macapps.open_app(self.app, ["/films/a.mkv"]), 0)
        program = os.path.join(self.app, "Contents", "MacOS", "Player")
        self.assertEqual(popen.call_args[0][0], ["ferry", program, "/films/a.mkv"])


class DockEntry(unittest.TestCase):
    """The Dock finds a Mac app's running windows by the entry Ferry writes
    for them; when the app is in the app grid, its entry there stands in."""

    def test_app_grid_entry_stands_in(self):
        folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, folder)
        app = make_app(folder, PLAYER)

        def write(name, lines):
            path = os.path.join(folder, name)
            with open(path, "w") as f:
                f.write("\n".join(["[Desktop Entry]", "Type=Application"] + lines) + "\n")
            return Gio.DesktopAppInfo.new_from_filename(path)
        ferry = write("org.example.player.desktop", ["Name=Player", "Exec=true", "NoDisplay=true",
                                                     "X-Ferry-Bundle=" + app])
        grid = write("ferry-org-example-player.desktop", ["Name=Player", "Exec=true %F",
                                                          "MimeType=video/mp4;", "X-freemac-MacApp=" + app])
        other = write("other.desktop", ["Name=Other", "Exec=true", "X-Ferry-Bundle=/nowhere/Other.app"])
        with mock.patch.object(Gio.AppInfo, "get_all", return_value=[other, ferry, grid]):
            self.assertEqual(apps._mac_app_entry(ferry).get_filename(), grid.get_filename())
            self.assertEqual(apps._mac_app_entry(other).get_filename(), other.get_filename())
        self.assertIsNone(apps._mac_app_entry(None))


if __name__ == "__main__":
    unittest.main()
