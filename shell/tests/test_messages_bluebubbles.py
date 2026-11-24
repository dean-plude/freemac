# SPDX-License-Identifier: GPL-3.0-or-later
"""Messages' BlueBubbles client against a stand-in server on localhost: the
REST calls, sending, attachments and the Socket.IO websocket's events.
Run with python3 -m unittest discover -s shell/tests."""
import os
import shutil
import tempfile
import time
import unittest

from messages_fakes import FakeBlueBubbles, Recorder, wait_until

from freemac_shell import messages_bluebubbles as bb


class Converting(unittest.TestCase):
    def test_services(self):
        self.assertEqual(bb.service_of("iMessage;-;+15550100001"), "imessage")
        self.assertEqual(bb.service_of("SMS;-;+15550100001"), "sms")
        self.assertEqual(bb.service_of("RCS;-;+15550100001"), "rcs")
        self.assertEqual(bb.service_of("odd"), "imessage")

    def test_urls(self):
        self.assertEqual(bb.normalise_url("192.168.1.20:1234/"), "http://192.168.1.20:1234")
        self.assertEqual(bb.normalise_url("https://example.test"), "https://example.test")
        with self.assertRaises(ValueError):
            bb.normalise_url("ftp://example.test")
        client = bb.BlueBubbles(Recorder(), "https://example.test/base", "p w")
        self.assertEqual(client.socket_url(),
                         "wss://example.test/base/socket.io/?EIO=4&transport=websocket&guid=p+w&password=p+w")

    def test_status_marks(self):
        m = FakeBlueBubbles.message
        read = bb.convert_message(m("a", "hi", 1, True, "x", delivered=2, read=3), "iMessage;-;x")
        self.assertEqual((read.status, read.status_date), ("read", 3))
        delivered = bb.convert_message(m("b", "hi", 1, True, "x", delivered=2), "iMessage;-;x")
        self.assertEqual((delivered.status, delivered.status_date), ("delivered", 2))
        failed = dict(m("c", "hi", 1, True, "x"), error=4)
        self.assertEqual(bb.convert_message(failed, "iMessage;-;x").status, "failed")
        got = bb.convert_message(m("d", "hi", 1, False, "+15550100001"), "SMS;-;+15550100001")
        self.assertEqual((got.status, got.sender, got.service, got.read), ("received", "+15550100001", "sms", False))

    def test_reactions_left_out(self):
        tapback = dict(FakeBlueBubbles.message("e", "Loved “hi”", 1, False, "x"),
                       associatedMessageGuid="p:0/a", associatedMessageType="love")
        self.assertIsNone(bb.convert_message(tapback, "iMessage;-;x"))


class AgainstAServer(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.server = FakeBlueBubbles()
        self.listener = Recorder()
        self.client = None

    def tearDown(self):
        if self.client:
            self.client.stop()
        self.server.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def connect(self, password=FakeBlueBubbles.PASSWORD, **kw):
        self.client = bb.BlueBubbles(self.listener, self.server.url, password,
                                     attachments_dir=os.path.join(self.dir, "files"), **kw)
        return self.client

    def test_wrong_password(self):
        client = self.connect("wrong")
        with self.assertRaises(bb.ServerError) as caught:
            client.check()
        self.assertIn("password", str(caught.exception))

    def test_unreachable(self):
        client = bb.BlueBubbles(self.listener, "http://127.0.0.1:9", "x")
        with self.assertRaises(bb.ServerError):
            client.check()

    def test_chats_and_messages(self):
        client = self.connect()
        client.check()
        chats, last = client.fetch_chats()
        self.assertEqual([c.id for c in chats], ["bb:iMessage;-;+15550100001", "bb:SMS;-;+15550100002"])
        self.assertEqual([c.service for c in chats], ["imessage", "sms"])
        self.assertEqual(chats[0].title, "(555) 010-0001")
        self.assertEqual(chats[0].last_text, "Yes! See you there")
        self.assertEqual(len(last), 2)
        messages = client.fetch_messages("iMessage;-;+15550100001")
        self.assertEqual([m.text for m in sorted(messages, key=lambda m: m.date)],
                         ["Are we still on for the pier at noon?", "Yes! See you there"])
        method, path, query, _body = self.server.requests[-1]
        self.assertEqual(path, "/api/v1/chat/iMessage%3B-%3B%2B15550100001/message")
        self.assertEqual(query["password"], [FakeBlueBubbles.PASSWORD])

    def test_send_into_a_chat(self):
        client = self.connect()
        chats, _ = client.fetch_chats()
        client.send_to_chat(chats[0], "Running five minutes late", "tmp:1")
        self.assertTrue(wait_until(lambda: self.listener.of("backend_sent")))
        _kind, temp, message, error, chat_id = self.listener.last("backend_sent")
        self.assertEqual((temp, error, chat_id), ("tmp:1", "", "bb:iMessage;-;+15550100001"))
        self.assertEqual(message.text, "Running five minutes late")
        self.assertTrue(message.from_me)
        body = self.server.sent[-1]
        self.assertEqual(body["chatGuid"], "iMessage;-;+15550100001")
        self.assertEqual(body["tempGuid"], "tmp:1")
        self.assertEqual(body["method"], "apple-script")

    def test_new_conversation(self):
        client = self.connect()
        client.send_new(["+15550100009"], "Hello from the new number", "tmp:2")
        self.assertTrue(wait_until(lambda: self.listener.of("backend_sent")))
        _kind, chats, _m = self.listener.last("backend_data")
        self.assertEqual(chats[0].id, "bb:iMessage;-;+15550100009")
        _kind, temp, message, error, chat_id = self.listener.last("backend_sent")
        self.assertEqual((temp, error, message.chat_id), ("tmp:2", "", "bb:iMessage;-;+15550100009"))
        self.assertEqual(self.server.sent[-1]["addresses"], ["+15550100009"])

    def test_send_fails(self):
        client = self.connect()
        self.server.close()
        chat = bb.convert_chat(self.server.chats[0])[0]
        client.send_to_chat(chat, "hello?", "tmp:3")
        self.assertTrue(wait_until(lambda: self.listener.of("backend_sent")))
        _kind, temp, message, error, _chat = self.listener.last("backend_sent")
        self.assertEqual((temp, message), ("tmp:3", None))
        self.assertIn("reach", error)

    def test_attachment_download(self):
        client = self.connect()
        client.download("bb:m9", {"id": "att-1234567890abcdef", "name": "beach day.png"})
        self.assertTrue(wait_until(lambda: self.listener.of("backend_attachment")))
        _kind, message_id, attachment_id, path = self.listener.last("backend_attachment")
        self.assertEqual((message_id, attachment_id), ("bb:m9", "att-1234567890abcdef"))
        self.assertTrue(path.endswith("beach_day.png"))
        with open(path, "rb") as f:
            self.assertTrue(f.read().startswith(b"\x89PNG"))

    @unittest.skipIf(bb.websocket is None, "needs python3-websocket")
    def test_live_events_over_the_websocket(self):
        client = self.connect()
        client.start()
        self.assertTrue(wait_until(lambda: self.server.sockets and client.socket_up), "no socket")
        first = self.server.socket_frames.get(timeout=3)
        self.assertTrue(first.startswith("40"))
        self.assertTrue(wait_until(lambda: self.listener.of("backend_data")))
        self.assertEqual(self.listener.of("backend_status")[-1][1:], ("Connected to BlueBubbles", True))
        # The server pings; the client answers.
        self.server.ping()
        self.assertEqual(self.server.socket_frames.get(timeout=3), "3")
        before = len(self.listener.of("backend_data"))
        incoming = dict(FakeBlueBubbles.message("live1", "Did you see the sunset?", int(time.time() * 1000),
                                                False, "+15550100001"),
                        chats=[{"guid": "iMessage;-;+15550100001"}])
        self.server.emit("new-message", incoming)
        self.assertTrue(wait_until(lambda: len(self.listener.of("backend_data")) > before))
        _kind, _chats, messages = self.listener.last("backend_data")
        self.assertEqual([m.text for m in messages], ["Did you see the sunset?"])
        # Read marks come as updated-message.
        before = len(self.listener.of("backend_data"))
        now = int(time.time() * 1000)
        updated = dict(FakeBlueBubbles.message("m2", "Yes! See you there", now - 3_500_000, True, "+15550100001",
                                               delivered=now - 1000, read=now),
                       chats=[{"guid": "iMessage;-;+15550100001"}])
        self.server.emit("updated-message", updated)
        self.assertTrue(wait_until(lambda: len(self.listener.of("backend_data")) > before))
        self.assertEqual(self.listener.last("backend_data")[2][0].status, "read")

    def test_polls_without_a_socket(self):
        self.server.socket_on = False
        client = self.connect(poll_every=0.2)
        client.start(since=int(time.time() * 1000) - 60_000)
        self.assertTrue(wait_until(lambda: self.listener.of("backend_data")))
        before = len(self.listener.of("backend_data"))
        self.server.messages["SMS;-;+15550100002"].append(
            FakeBlueBubbles.message("late", "We saved you a seat", int(time.time() * 1000) + 5, False,
                                    "+15550100002", service="SMS"))
        self.assertTrue(wait_until(lambda: len(self.listener.of("backend_data")) > before, 4))
        texts = [m.text for args in self.listener.of("backend_data")[before:] for m in args[2]]
        self.assertIn("We saved you a seat", texts)


if __name__ == "__main__":
    unittest.main()
