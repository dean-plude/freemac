# SPDX-License-Identifier: GPL-3.0-or-later
"""Messages and the firewall: the rules freemac-system-helper would give ufw
for KDE Connect (run against a stand-in ufw that only writes them down, with
the helper's notes in a folder of the test's own), and when Messages asks for
them. This machine's real firewall is never touched.
Run with python3 -m unittest discover -s shell/tests."""
import os
import shutil
import tempfile
import unittest

from messages_fakes import FakeHelper

from freemac_shell import messages_firewall as firewall

LANS = ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
COMMENT = "comment freemac: messages (kde connect)"


def allow(proto, net, port):
    return f"allow in proto {proto} from {net} to any port {port} {COMMENT}"


@unittest.skipUnless(shutil.which("sh"), "needs a shell")
class HelperRules(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.helper = FakeHelper(self.dir)
        self.mark = os.path.join(self.helper.state, "kde-connect")

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_on_lets_kde_connect_in_from_the_local_network_only(self):
        done = self.helper.run("kde-connect", "on")
        self.assertEqual(done.returncode, 0, done.stderr)
        want = []
        for net in LANS:
            want += [allow("udp", net, "1716"), allow("tcp", net, "1716:1764")]
        self.assertEqual(self.helper.calls(), want)
        self.assertTrue(os.path.exists(self.mark))
        for line in self.helper.calls():
            # Nothing but these openings: no default, enable or disable, no "from any".
            self.assertTrue(line.startswith("allow in proto "), line)
            self.assertNotIn("from any", line)

    def test_off_takes_the_same_rules_out(self):
        self.helper.run("kde-connect", "on")
        self.helper.clear()
        done = self.helper.run("kde-connect", "off")
        self.assertEqual(done.returncode, 0, done.stderr)
        want = []
        for net in LANS:
            want += [f"delete allow in proto udp from {net} to any port 1716",
                     f"delete allow in proto tcp from {net} to any port 1716:1764"]
        self.assertEqual(self.helper.calls(), want)
        self.assertFalse(os.path.exists(self.mark))

    def test_turning_the_firewall_on_keeps_them_while_the_phone_is_on(self):
        done = self.helper.run("firewall", "on")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertFalse([c for c in self.helper.calls() if "kde connect" in c])
        self.assertIn("--force enable", self.helper.calls())
        self.helper.run("kde-connect", "on")
        self.helper.clear()
        self.helper.run("firewall", "on")
        calls = self.helper.calls()
        for net in LANS:
            self.assertIn(allow("udp", net, "1716"), calls)
            self.assertIn(allow("tcp", net, "1716:1764"), calls)
        # Opened before ufw is turned on, so there's no moment without them.
        self.assertLess(calls.index(allow("tcp", LANS[-1], "1716:1764")), calls.index("--force enable"))

    def test_nothing_else(self):
        done = self.helper.run("kde-connect", "wide-open")
        self.assertEqual(done.returncode, 2)
        self.assertEqual(self.helper.calls(), [])


class WhenMessagesAsks(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.saved = (firewall.UFW_CONF, firewall.MARK)
        firewall.UFW_CONF = os.path.join(self.dir, "ufw.conf")
        firewall.MARK = os.path.join(self.dir, "kde-connect")

    def tearDown(self):
        firewall.UFW_CONF, firewall.MARK = self.saved
        shutil.rmtree(self.dir, ignore_errors=True)

    def firewall(self, on):
        with open(firewall.UFW_CONF, "w") as f:
            f.write(f"# made up\nENABLED={'yes' if on else 'no'}\nLOGLEVEL=low\n")

    def test_changes(self):
        self.assertIsNone(firewall.change_for(True))          # no firewall here at all
        self.firewall(False)
        self.assertIsNone(firewall.change_for(True))          # Firewall off: nothing to open
        self.firewall(True)
        self.assertIs(firewall.change_for(True), True)        # on, and the ports closed
        open(firewall.MARK, "w").close()
        self.assertIsNone(firewall.change_for(True))          # already open
        self.assertIs(firewall.change_for(False), False)      # phone off: close them
        self.firewall(False)
        self.assertIs(firewall.change_for(False), False)      # even with the firewall off since
        os.remove(firewall.MARK)
        self.assertIsNone(firewall.change_for(False))

    def test_command_goes_through_pkexec_and_the_helper(self):
        self.assertEqual(firewall.command(True),
                         ["pkexec", "/usr/libexec/freemac-system-helper", "kde-connect", "on"])
        self.assertEqual(firewall.command(False)[-2:], ["kde-connect", "off"])


if __name__ == "__main__":
    unittest.main()
