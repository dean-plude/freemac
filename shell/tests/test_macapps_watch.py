# SPDX-License-Identifier: GPL-3.0-or-later
"""The app grid follows the Applications folders while the session lasts
(freemac 1.243): an app copied in is added once it has stopped growing, and
one taken out goes. Run from the repository with

    python3 -m unittest discover -s shell/tests
"""
import os
import plistlib
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

try:
    from freemac_shell import macapps
except (ImportError, ValueError):   # no gi bindings (or no GdkPixbuf's) for this Python
    raise unittest.SkipTest("needs Python's gi bindings, with GdkPixbuf")


class Watching(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.apps = os.path.join(self.dir.name, "Applications")
        self.scans = 0
        self.watcher = macapps.Watcher([self.apps, os.path.join(self.dir.name, "none")], self.count)

    def tearDown(self):
        self.dir.cleanup()

    def count(self):
        self.scans += 1

    def write(self, path, text="x"):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)

    def test_a_missing_folder_is_watched_once_it_exists(self):
        self.assertFalse(self.watcher.poll())
        os.makedirs(self.apps)
        self.assertFalse(self.watcher.poll())

    def test_an_app_is_added_once_it_stops_growing_and_dropped_when_it_goes(self):
        app = os.path.join(self.apps, "Player.app")
        self.write(os.path.join(app, "Contents", "MacOS", "Player"))
        self.assertFalse(self.watcher.poll())          # new: looked at
        self.write(os.path.join(app, "Contents", "Resources", "Player.icns"))
        self.assertFalse(self.watcher.poll())          # still growing
        with open(os.path.join(app, "Contents", "Info.plist"), "wb") as f:
            plistlib.dump({"CFBundleExecutable": "Player"}, f)
        self.assertFalse(self.watcher.poll())          # still growing
        self.assertTrue(self.watcher.poll())           # settled: added
        self.assertEqual(self.scans, 1)
        self.assertFalse(self.watcher.poll())          # nothing new
        os.rename(app, os.path.join(self.dir.name, "Player.app"))
        self.assertTrue(self.watcher.poll())           # gone
        self.assertEqual(self.scans, 2)

    def test_a_plain_folder_is_left_alone_until_it_becomes_an_app(self):
        folder = os.path.join(self.apps, "Tools.app")   # Info.plist copied last
        self.write(os.path.join(folder, "readme.txt"))
        self.assertFalse(self.watcher.poll())
        self.assertFalse(self.watcher.poll())          # settled, not an app
        self.assertFalse(self.watcher.poll())
        self.write(os.path.join(folder, "Contents", "Info.plist"), "")
        self.assertFalse(self.watcher.poll())          # now looks like one: wait for it to settle
        self.assertTrue(self.watcher.poll())
        self.assertEqual(self.scans, 1)


if __name__ == "__main__":
    unittest.main()
