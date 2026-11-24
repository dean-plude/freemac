# SPDX-License-Identifier: GPL-3.0-or-later
"""Messages' KDE Connect client against a stand-in phone on localhost:
discovery, TLS, pairing both ways, the SMS packets and an attachment.
Run with python3 -m unittest discover -s shell/tests (needs openssl)."""
import base64
import os
import shutil
import subprocess
import tempfile
import time
import unittest

from messages_fakes import FakePhone, Recorder, sms, wait_until

from freemac_shell import messages_kdeconnect as kdc
from freemac_shell import messages_store as store

HAVE_OPENSSL = shutil.which("openssl") is not None


@unittest.skipUnless(HAVE_OPENSSL, "needs openssl to make certificates")
class Certificates(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def der(self, name):
        cert, _key = kdc.make_certificate(os.path.join(self.dir, name), "a" * 32)
        with open(cert) as f:
            import ssl
            return cert, ssl.PEM_cert_to_DER_cert(f.read())

    def test_public_key_is_what_openssl_says(self):
        cert, der = self.der("one")
        pem = subprocess.run(["openssl", "x509", "-in", cert, "-pubkey", "-noout"],
                             check=True, capture_output=True, text=True).stdout
        body = "".join(l for l in pem.splitlines() if not l.startswith("-----"))
        self.assertEqual(kdc.public_key_der(der), base64.b64decode(body))

    def test_certificate_names_the_device(self):
        cert, _der = self.der("two")
        subject = subprocess.run(["openssl", "x509", "-in", cert, "-subject", "-noout"],
                                 check=True, capture_output=True, text=True).stdout
        self.assertIn("CN = " + "a" * 32, subject)
        self.assertIn("O = KDE", subject)
        self.assertEqual(os.stat(os.path.join(self.dir, "two", "key.pem")).st_mode & 0o777, 0o600)

    def test_code_is_the_same_on_both_sides(self):
        _c, a = self.der("a")
        _c, b = self.der("b")
        self.assertEqual(kdc.verification_code(a, b), kdc.verification_code(b, a))
        self.assertEqual(len(kdc.verification_code(a, b)), 8)
        self.assertNotEqual(kdc.verification_code(a, b, 1700000000), kdc.verification_code(a, b))
        self.assertEqual(kdc.verification_code(a, b, 1700000000), kdc.verification_code(b, a, 1700000000))


class Packets(unittest.TestCase):
    def test_round_trip(self):
        data = kdc.make_packet("kdeconnect.sms.request", {"messageBody": "hi"})
        self.assertTrue(data.endswith(b"\n"))
        packet = kdc.parse_packet(data.strip())
        self.assertEqual(packet["type"], "kdeconnect.sms.request")
        self.assertEqual(packet["body"], {"messageBody": "hi"})
        self.assertIsInstance(packet["id"], int)
        self.assertIsNone(kdc.parse_packet(b"not json"))
        self.assertIsNone(kdc.parse_packet(b"[1, 2]"))

    def test_convert_messages(self):
        chats, messages = kdc.convert("dev", [
            sms(10, 4, "Lunch at the harbour?", "+1 555 010 0003", 1000),
            sms(11, 4, "On my way", "+1 555 010 0003", 2000, kind=2, read=1),
            sms(12, 7, "", "+15550100004", 1500, attachments=[{"part_id": 3, "mime_type": "image/jpeg",
                                                               "unique_identifier": "pic.jpg"}]),
        ], names={store.normalise_address("+15550100003"): "Rosa Marin"})
        by_id = {c.id: c for c in chats}
        self.assertEqual(by_id["kdc:dev:4"].title, "Rosa Marin")
        self.assertEqual(by_id["kdc:dev:4"].last_text, "On my way")
        self.assertEqual(by_id["kdc:dev:7"].title, "(555) 010-0004")
        self.assertEqual(by_id["kdc:dev:7"].last_text, "Attachment")
        first, second, third = messages
        self.assertFalse(first.from_me)
        self.assertEqual(first.sender, "+1 555 010 0003")
        self.assertFalse(first.read)
        self.assertTrue(second.from_me)
        self.assertEqual(second.status, "sent")
        self.assertEqual(third.attachments[0]["part_id"], 3)
        self.assertEqual(third.attachments[0]["mime"], "image/jpeg")


@unittest.skipUnless(HAVE_OPENSSL, "needs openssl to make certificates")
class OverTheNetwork(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.phone = FakePhone(os.path.join(self.dir, "phone"), name="Pixel Test")
        self.listener = Recorder()
        self.desktop = self.start_desktop()

    def start_desktop(self, listener=None):
        desktop = kdc.KdeConnect(listener or self.listener, state_dir=os.path.join(self.dir, "desktop"),
                                 name="freemac test", udp_port=0, tcp_ports=[0],
                                 announce_to=[("127.0.0.1", self.phone.udp_port)], broadcast_every=0.5)
        desktop.reply_port = self.phone.udp_port
        desktop.start()
        return desktop

    def tearDown(self):
        self.desktop.stop()
        self.phone.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def found_phone(self):
        return any(d["id"] == self.phone.device_id for d in self.desktop.devices())

    def pair(self):
        self.assertTrue(wait_until(self.found_phone), "the desktop never saw the phone")
        code = self.desktop.pair(self.phone.device_id)
        packet = self.phone.expect("kdeconnect.pair")
        self.phone.send("kdeconnect.pair", {"pair": True})
        self.assertTrue(wait_until(lambda: self.listener.of("backend_paired")))
        return code, packet

    def test_identity_and_tls(self):
        self.assertTrue(wait_until(self.phone.connected))
        self.assertTrue(wait_until(self.found_phone))
        device = next(d for d in self.desktop.devices() if d["id"] == self.phone.device_id)
        self.assertEqual(device["name"], "Pixel Test")
        self.assertFalse(device["paired"])
        body = self.phone.desktop
        self.assertEqual(body["deviceId"], self.desktop.device_id)
        self.assertEqual(body["protocolVersion"], 8)
        self.assertIn("kdeconnect.sms.messages", body["incomingCapabilities"])
        self.assertIn("kdeconnect.sms.request", body["outgoingCapabilities"])

    def test_we_ask_to_pair(self):
        code, packet = self.pair()
        self.assertTrue(packet["body"]["pair"])
        stamp = packet["body"]["timestamp"]
        self.assertLess(abs(stamp - time.time()), 30)
        # The phone works the code out from the same two certificates.
        self.assertEqual(code, kdc.verification_code(self.phone.cert_der, self.desktop.cert_der, stamp))
        self.assertEqual(self.listener.last("backend_paired")[1:], (self.phone.device_id, "Pixel Test", True))
        self.assertIn(self.phone.device_id, self.desktop.paired())
        # Once paired the desktop asks for the conversations.
        self.phone.expect("kdeconnect.sms.request_conversations")
        self.assertTrue(wait_until(lambda: (self.listener.last("backend_status") or [None, ""])[1]
                                   .startswith("Connected")))

    def test_phone_asks_to_pair(self):
        self.assertTrue(wait_until(self.phone.connected))
        self.assertTrue(wait_until(self.found_phone))
        self.phone.send("kdeconnect.pair", {"pair": True, "timestamp": 1700000000})
        self.assertTrue(wait_until(lambda: self.listener.of("backend_pair_request")))
        _kind, device, name, code = self.listener.last("backend_pair_request")
        self.assertEqual((device, name), (self.phone.device_id, "Pixel Test"))
        self.assertEqual(code, kdc.verification_code(self.phone.cert_der, self.desktop.cert_der, 1700000000))
        self.desktop.accept_pair(device)
        self.assertTrue(self.phone.expect("kdeconnect.pair")["body"]["pair"])
        self.assertIn(device, self.desktop.paired())

    def test_texts_ignored_until_paired(self):
        self.assertTrue(wait_until(self.phone.connected))
        self.assertTrue(wait_until(self.found_phone))
        self.phone.send("kdeconnect.sms.messages", {"messages": [sms(1, 1, "hello", "+15550100005", 1)]})
        time.sleep(0.3)
        self.assertEqual(self.listener.of("backend_data"), [])

    def test_conversations_live_texts_and_sending(self):
        self.pair()
        self.phone.expect("kdeconnect.sms.request_conversations")
        now = int(time.time() * 1000)
        self.phone.send("kdeconnect.sms.messages", {"messages": [
            sms(1, 21, "Is the ferry running today?", "+15550100006", now - 60_000),
            sms(2, 22, "Thanks for the photos", "+15550100007", now - 120_000, read=1),
        ]})
        self.assertTrue(wait_until(lambda: self.listener.of("backend_data")))
        _kind, chats, messages = self.listener.last("backend_data")
        self.assertEqual(sorted(c.remote_id for c in chats), ["21", "22"])
        self.assertEqual(len(messages), 2)
        # A text that comes in by itself.
        self.phone.send("kdeconnect.sms.messages", {"messages": [
            sms(3, 21, "Last one leaves at six", "+15550100006", now)]})
        self.assertTrue(wait_until(lambda: len(self.listener.of("backend_data")) == 2))
        _kind, _chats, live = self.listener.last("backend_data")
        self.assertEqual(live[0].text, "Last one leaves at six")
        # Opening a conversation asks for its messages.
        chat = next(c for c in chats if c.remote_id == "21")
        self.desktop.load_conversation(chat, before=now, count=50)
        asked = self.phone.expect("kdeconnect.sms.request_conversation")["body"]
        self.assertEqual(asked, {"threadID": 21, "numberToRequest": 50, "rangeStartTimestamp": now})
        # Sending.
        self.desktop.send(["+15550100006"], "See you there")
        sent = self.phone.expect("kdeconnect.sms.request")["body"]
        self.assertEqual(sent, {"version": 2, "addresses": [{"address": "+15550100006"}],
                                "messageBody": "See you there"})

    def test_attachment(self):
        self.pair()
        message = store.Message(id="kdc:x:1:1", chat_id="kdc:x:1")
        attachment = {"id": "photo.jpg", "part_id": 9, "name": "photo.jpg"}
        self.desktop.request_attachment(message, attachment)
        asked = self.phone.expect("kdeconnect.sms.request_attachment")["body"]
        self.assertEqual(asked, {"part_id": 9, "unique_identifier": "photo.jpg"})
        data = b"\xff\xd8 not really a jpeg " * 100
        port = self.phone.serve_file(data)
        self.phone.send("kdeconnect.sms.attachment_file", {"filename": "photo.jpg"},
                        payloadSize=len(data), payloadTransferInfo={"port": port})
        self.assertTrue(wait_until(lambda: self.listener.of("backend_attachment")))
        _kind, message_id, attachment_id, path = self.listener.last("backend_attachment")
        self.assertEqual((message_id, attachment_id), ("kdc:x:1:1", "photo.jpg"))
        with open(path, "rb") as f:
            self.assertEqual(f.read(), data)

    def test_known_phone_reconnects_and_refreshes(self):
        self.pair()
        self.phone.expect("kdeconnect.sms.request_conversations")
        self.desktop.stop()
        self.phone.close()
        # The same phone (same id and certificate) comes back to a new desktop process.
        phone = FakePhone(os.path.join(self.dir, "phone"), device_id=self.phone.device_id, name="Pixel Test")
        self.phone = phone
        listener = Recorder()
        self.desktop = self.start_desktop(listener)
        self.assertTrue(wait_until(phone.connected))
        phone.expect("kdeconnect.sms.request_conversations")

    def test_changed_certificate_turned_away(self):
        self.pair()
        self.desktop.stop()
        self.phone.close()
        # Same device id, a different certificate: someone else pretending.
        impostor = FakePhone(os.path.join(self.dir, "impostor"), device_id=self.phone.device_id, name="Pixel Test")
        self.phone = impostor
        listener = Recorder()
        self.desktop = self.start_desktop(listener)
        self.assertTrue(wait_until(lambda: any("new security certificate" in a[1]
                                               for a in listener.of("backend_status"))))
        self.assertFalse(any(d["connected"] for d in self.desktop.devices()))

    def test_unpair(self):
        self.pair()
        self.desktop.unpair(self.phone.device_id)
        self.assertFalse(self.phone.expect("kdeconnect.pair")["body"]["pair"])
        self.assertNotIn(self.phone.device_id, self.desktop.paired())


if __name__ == "__main__":
    unittest.main()
