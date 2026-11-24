# SPDX-License-Identifier: GPL-3.0-or-later
"""Messages' offline store (SQLite), settings and saved passwords.
Run with python3 -m unittest discover -s shell/tests."""
import os
import shutil
import stat
import tempfile
import unittest

import messages_fakes  # noqa: F401 - puts the shell on the path

from freemac_shell import messages_store as store
from freemac_shell.messages_store import Chat, Message


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.path = os.path.join(self.dir, "messages.db")
        self.store = store.Store(self.path)
        self.store.upsert_chats([
            Chat(id="bb:iMessage;-;a", backend="bluebubbles", title="Rosa Marin", addresses=["+15550100001"],
                 service="imessage"),
            Chat(id="kdc:p:4", backend="kdeconnect", title="(555) 010-0002", addresses=["+1 555 010 0002"],
                 remote_id="4"),
        ])
        self.store.upsert_messages([
            Message(id="bb:1", chat_id="bb:iMessage;-;a", text="Bring the kite", date=1000, read=False,
                    sender="+15550100001", service="imessage"),
            Message(id="kdc:p:1:2000", chat_id="kdc:p:4", text="Dinner is at seven", date=2000, read=False,
                    sender="+15550100002"),
        ])

    def tearDown(self):
        self.store.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_newest_first_and_unread(self):
        self.assertEqual([c.id for c in self.store.chats()], ["kdc:p:4", "bb:iMessage;-;a"])
        self.assertEqual(self.store.unread_total(), 2)
        self.store.mark_read("kdc:p:4")
        self.assertEqual(self.store.unread_total(), 1)
        self.assertTrue(self.store.messages("kdc:p:4")[0].read)

    def test_last_message_follows(self):
        chat = self.store.chat("bb:iMessage;-;a")
        self.assertEqual((chat.last_date, chat.last_text), (1000, "Bring the kite"))
        self.store.upsert_messages([Message(id="bb:2", chat_id="bb:iMessage;-;a", text="And snacks", date=3000,
                                            from_me=True, status="sent")])
        chat = self.store.chat("bb:iMessage;-;a")
        self.assertEqual((chat.last_date, chat.last_text), (3000, "And snacks"))
        # A refresh with an older last message doesn't take it back.
        self.store.upsert_chats([Chat(id="bb:iMessage;-;a", backend="bluebubbles", last_date=1000,
                                      last_text="Bring the kite")])
        self.assertEqual(self.store.chat("bb:iMessage;-;a").last_text, "And snacks")
        self.assertEqual(self.store.chat("bb:iMessage;-;a").title, "Rosa Marin")

    def test_same_message_twice_is_kept_once(self):
        again = Message(id="bb:1", chat_id="bb:iMessage;-;a", text="Bring the kite", date=1000, read=False)
        self.assertEqual(self.store.upsert_messages([again]), [])
        self.assertEqual(len(self.store.messages("bb:iMessage;-;a")), 1)
        self.assertEqual(self.store.chat("bb:iMessage;-;a").unread, 1)

    def test_search(self):
        self.assertEqual([c.id for c in self.store.chats("rosa")], ["bb:iMessage;-;a"])
        self.assertEqual([c.id for c in self.store.chats("seven")], ["kdc:p:4"])
        self.assertEqual([c.id for c in self.store.chats("010-0002")], ["kdc:p:4"])
        self.assertEqual(self.store.chats("nothing like this"), [])

    def test_pending_message_replaced_by_the_real_one(self):
        self.store.upsert_messages([Message(id="tmp:x", chat_id="kdc:p:4", text="On my way", date=5000,
                                            from_me=True, status="sending")])
        self.store.upsert_messages([Message(id="kdc:p:9:5100", chat_id="kdc:p:4", text="On my way", date=5100,
                                            from_me=True, status="sent")])
        self.assertEqual([m.id for m in self.store.messages("kdc:p:4")], ["kdc:p:1:2000", "kdc:p:9:5100"])

    def test_find_chat_by_addresses(self):
        self.assertEqual(self.store.find_chat("kdeconnect", ["(555) 010-0002"]).id, "kdc:p:4")
        self.assertIsNone(self.store.find_chat("bluebubbles", ["(555) 010-0002"]))

    def test_survives_reopening(self):
        self.store.close()
        self.store = store.Store(self.path)
        self.assertEqual(len(self.store.chats()), 2)
        self.assertEqual(self.store.messages("kdc:p:4")[0].text, "Dinner is at seven")

    def test_forget_backend(self):
        self.store.forget_backend("bluebubbles")
        self.assertEqual([c.id for c in self.store.chats()], ["kdc:p:4"])
        self.assertEqual(self.store.messages("bb:iMessage;-;a"), [])

    def test_attachment_path_kept(self):
        m = Message(id="bb:5", chat_id="bb:iMessage;-;a", date=6000, attachments=[{"id": "a1", "name": "x.png"}])
        self.store.upsert_messages([m])
        self.store.set_attachment_path("bb:5", "a1", "/tmp/x.png")
        again = Message(id="bb:5", chat_id="bb:iMessage;-;a", date=6000, attachments=[{"id": "a1", "name": "x.png"}])
        self.store.upsert_messages([again])
        self.assertEqual(self.store.message("bb:5").attachments[0]["path"], "/tmp/x.png")
        self.assertEqual(self.store.chat("bb:iMessage;-;a").last_text, "Attachment")


class Addresses(unittest.TestCase):
    def test_normalise(self):
        self.assertEqual(store.normalise_address("+1 (555) 010-0001"), "5550100001")
        self.assertEqual(store.normalise_address("555.010.0001"), "5550100001")
        self.assertEqual(store.normalise_address("Sam@Example.TEST"), "sam@example.test")

    def test_format(self):
        self.assertEqual(store.format_address("+15550100001"), "(555) 010-0001")
        self.assertEqual(store.format_address("+44 20 7946 0000"), "+44 20 7946 0000")
        self.assertEqual(store.format_address("sam@example.test"), "sam@example.test")


class Passwords(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.old = os.environ.get("XDG_CONFIG_HOME")
        os.environ["XDG_CONFIG_HOME"] = self.dir
        store.KEYRING = False

    def tearDown(self):
        if self.old is None:
            os.environ.pop("XDG_CONFIG_HOME", None)
        else:
            os.environ["XDG_CONFIG_HOME"] = self.old
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_file_only_the_user_reads(self):
        self.assertEqual(store.save_password("bluebubbles:http://x", "s3cret"), "file")
        path = os.path.join(store.config_dir(), "passwords.json")
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
        self.assertEqual(store.load_password("bluebubbles:http://x"), "s3cret")
        store.delete_password("bluebubbles:http://x")
        self.assertEqual(store.load_password("bluebubbles:http://x"), "")

    def test_settings(self):
        store.save_settings({"welcomed": True, "bluebubbles": {"url": "http://x"}})
        self.assertEqual(store.load_settings()["bluebubbles"]["url"], "http://x")


if __name__ == "__main__":
    unittest.main()
