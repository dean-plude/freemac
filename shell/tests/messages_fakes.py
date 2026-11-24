# SPDX-License-Identifier: GPL-3.0-or-later
"""Stand-ins for Messages' tests, all on localhost: a phone that speaks KDE
Connect (UDP, TCP, TLS with its own certificate, pairing and the SMS
packets), a BlueBubbles server (its REST API and a Socket.IO websocket), and
a listener that records what backends tell the app. Made-up people and
messages only; nothing here reaches the internet or a real device.
"""
import base64
import hashlib
import json
import os
import queue
import socket
import ssl
import struct
import sys
import threading
import time
import urllib.parse
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from freemac_shell import messages_kdeconnect as kdc  # noqa: E402


def wait_until(check, seconds=5.0):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if check():
            return True
        time.sleep(0.02)
    return check()


class Recorder:
    """A backend listener that keeps every call."""
    def __init__(self):
        self.calls = []
        self.lock = threading.Lock()

    def __getattr__(self, name):
        if not name.startswith("backend_"):
            raise AttributeError(name)

        def record(*args):
            with self.lock:
                self.calls.append((name, args))
        return record

    def of(self, name):
        with self.lock:
            return [args for n, args in self.calls if n == name]

    def last(self, name):
        found = self.of(name)
        return found[-1] if found else None


# -- KDE Connect ----------------------------------------------------------------------
class FakePhone:
    """An Android phone running KDE Connect, as far as Messages sees it."""

    def __init__(self, folder, device_id=None, name="Test Phone", version=8):
        self.device_id = device_id or uuid.uuid4().hex
        self.name = name
        self.version = version
        self.cert, self.key = kdc.make_certificate(folder, self.device_id)
        with open(self.cert) as f:
            self.cert_der = ssl.PEM_cert_to_DER_cert(f.read())
        self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp.bind(("127.0.0.1", 0))
        self.udp_port = self.udp.getsockname()[1]
        self.packets = queue.Queue()
        self.tls = None
        self.desktop = None
        self.running = True
        threading.Thread(target=self._udp, daemon=True).start()

    def identity(self):
        return {"deviceId": self.device_id, "deviceName": self.name, "deviceType": "phone",
                "protocolVersion": self.version,
                "incomingCapabilities": ["kdeconnect.sms.request", "kdeconnect.sms.request_conversations",
                                         "kdeconnect.sms.request_conversation", "kdeconnect.sms.request_attachment"],
                "outgoingCapabilities": ["kdeconnect.sms.messages", "kdeconnect.sms.attachment_file"],
                "tcpPort": 1716}

    def broadcast_to(self, port):
        """Send our identity to the desktop's UDP port, as the phone's broadcast would."""
        self.udp.sendto(kdc.make_packet("kdeconnect.identity", self.identity()), ("127.0.0.1", port))

    def _udp(self):
        while self.running:
            try:
                data, _addr = self.udp.recvfrom(65536)
            except OSError:
                return
            packet = kdc.parse_packet(data.strip())
            if packet and packet["type"] == "kdeconnect.identity" and self.tls is None:
                self.desktop = packet["body"]
                threading.Thread(target=self._connect, args=(packet["body"]["tcpPort"],), daemon=True).start()

    def _connect(self, port):
        """Connect to the desktop and become the TLS server, as the phone does."""
        raw = socket.create_connection(("127.0.0.1", port), timeout=5)
        raw.sendall(kdc.make_packet("kdeconnect.identity", self.identity()))
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.cert, self.key)
        tls = context.wrap_socket(raw, server_side=True)
        if self.version >= 8:
            line = self._line(tls)
            self.desktop = kdc.parse_packet(line)["body"]
            tls.sendall(kdc.make_packet("kdeconnect.identity", self.identity()))
        tls.settimeout(None)
        self.tls = tls
        threading.Thread(target=self._read, daemon=True).start()

    @staticmethod
    def _line(sock):
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = sock.recv(1)
            if not chunk:
                raise OSError("closed")
            buf += chunk
        return buf.strip()

    def _read(self):
        buf = b""
        try:
            while True:
                chunk = self.tls.recv(65536)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if line.strip():
                        self.packets.put(kdc.parse_packet(line))
        except (OSError, ssl.SSLError):
            pass

    def connected(self):
        return self.tls is not None

    def send(self, kind, body, **extra):
        self.tls.sendall(kdc.make_packet(kind, body, **extra))

    def expect(self, kind, seconds=5):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            try:
                packet = self.packets.get(timeout=max(0.01, end - time.monotonic()))
            except queue.Empty:
                break
            if packet["type"] == kind:
                return packet
        raise AssertionError(f"the phone got no {kind}")

    def serve_file(self, data):
        """A one-off TLS server with a file for the desktop to fetch; its port."""
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.cert, self.key)

        def run():
            conn, _ = server.accept()
            tls = context.wrap_socket(conn, server_side=True)
            tls.sendall(data)
            tls.close()
            server.close()
        threading.Thread(target=run, daemon=True).start()
        return server.getsockname()[1]

    def close(self):
        self.running = False
        for sock in (self.tls, self.udp):
            try:
                if sock is not None:
                    sock.close()
            except OSError:
                pass


def sms(_id, thread, body, address, date, kind=1, read=0, attachments=None):
    return {"_id": _id, "thread_id": thread, "body": body, "addresses": [{"address": address}],
            "date": date, "type": kind, "read": read, "event": 1, "sub_id": 1,
            "attachments": attachments or []}


# -- BlueBubbles ----------------------------------------------------------------------
WS_MAGIC = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def ws_frame(text):
    data = text.encode("utf-8")
    head = bytes([0x81])
    if len(data) < 126:
        head += bytes([len(data)])
    elif len(data) < 65536:
        head += bytes([126]) + struct.pack(">H", len(data))
    else:
        head += bytes([127]) + struct.pack(">Q", len(data))
    return head + data


def ws_read(sock):
    """One frame from the client (always masked); (opcode, text)."""
    def exact(n):
        buf = b""
        while len(buf) < n:
            chunk = sock.recv(n - len(buf))
            if not chunk:
                raise OSError("closed")
            buf += chunk
        return buf
    first, second = exact(2)
    length = second & 0x7F
    if length == 126:
        length = struct.unpack(">H", exact(2))[0]
    elif length == 127:
        length = struct.unpack(">Q", exact(8))[0]
    mask = exact(4) if second & 0x80 else b"\0\0\0\0"
    data = bytes(b ^ mask[i % 4] for i, b in enumerate(exact(length)))
    return first & 0x0F, data.decode("utf-8", "replace")


class FakeBlueBubbles:
    """A BlueBubbles server with two conversations, on localhost."""
    PASSWORD = "correct horse"

    def __init__(self, socket_on=True):
        self.requests = []
        self.sent = []
        self.sockets = []
        self.socket_on = socket_on
        self.socket_frames = queue.Queue()
        now = int(time.time() * 1000)
        self.chats = [
            {"guid": "iMessage;-;+15550100001", "chatIdentifier": "+15550100001", "displayName": "",
             "participants": [{"address": "+15550100001", "service": "iMessage"}]},
            {"guid": "SMS;-;+15550100002", "chatIdentifier": "+15550100002", "displayName": "",
             "participants": [{"address": "+15550100002", "service": "SMS"}]},
        ]
        self.messages = {
            "iMessage;-;+15550100001": [
                self.message("m1", "Are we still on for the pier at noon?", now - 3_600_000, False, "+15550100001"),
                self.message("m2", "Yes! See you there", now - 3_500_000, True, "+15550100001",
                             delivered=now - 3_499_000, read=now - 3_400_000),
            ],
            "SMS;-;+15550100002": [
                self.message("m3", "Your table for two is ready", now - 7_200_000, False, "+15550100002",
                             service="SMS"),
            ],
        }
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_a):
                pass

            def _reply(self, status, data):
                body = json.dumps({"status": status, "message": "ok" if status == 200 else "error",
                                   "data": data}).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def _route(self, method):
                parts = urllib.parse.urlsplit(self.path)
                query = urllib.parse.parse_qs(parts.query)
                length = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(length) or b"null") if length else None
                fake.requests.append((method, parts.path, query, body))
                if parts.path == "/socket.io/":
                    return fake._websocket(self, query)
                if query.get("password", [""])[0] != fake.PASSWORD:
                    return self._reply(401, None)
                return fake.route(self, method, urllib.parse.unquote(parts.path), query, body)

            def do_GET(self):
                self._route("GET")

            def do_POST(self):
                self._route("POST")

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    @staticmethod
    def message(guid, text, date, from_me, address, service="iMessage", delivered=None, read=None, attachments=None):
        return {"guid": guid, "text": text, "dateCreated": date, "isFromMe": from_me,
                "handle": {"address": address, "service": service}, "dateDelivered": delivered,
                "dateRead": read, "error": 0, "attachments": attachments or [],
                "associatedMessageGuid": None, "associatedMessageType": None}

    def route(self, handler, method, path, query, body):
        if path == "/api/v1/ping":
            return handler._reply(200, "pong")
        if path == "/api/v1/server/info":
            return handler._reply(200, {"private_api": False, "os_version": "test"})
        if path == "/api/v1/chat/query":
            out = []
            for chat in self.chats:
                item = dict(chat)
                item["lastMessage"] = self.messages[chat["guid"]][-1]
                out.append(item)
            return handler._reply(200, out)
        if path.startswith("/api/v1/chat/") and path.endswith("/message"):
            guid = path[len("/api/v1/chat/"):-len("/message")]
            return handler._reply(200, list(reversed(self.messages.get(guid, []))))
        if path == "/api/v1/message/query":
            after = body.get("after", 0)
            found = []
            for guid, msgs in self.messages.items():
                for m in msgs:
                    if m["dateCreated"] > after:
                        found.append(dict(m, chats=[{"guid": guid}]))
            return handler._reply(200, sorted(found, key=lambda m: m["dateCreated"]))
        if path == "/api/v1/message/text":
            self.sent.append(body)
            m = self.message("sent-" + str(len(self.sent)), body["message"], int(time.time() * 1000), True,
                             body["chatGuid"].split(";")[-1])
            m["tempGuid"] = body["tempGuid"]
            self.messages.setdefault(body["chatGuid"], []).append(m)
            return handler._reply(200, m)
        if path == "/api/v1/chat/new":
            self.sent.append(body)
            guid = "iMessage;-;" + body["addresses"][0]
            m = self.message("new-" + str(len(self.sent)), body["message"], int(time.time() * 1000), True,
                             body["addresses"][0])
            self.chats.append({"guid": guid, "chatIdentifier": body["addresses"][0], "displayName": "",
                               "participants": [{"address": body["addresses"][0], "service": "iMessage"}]})
            self.messages[guid] = [m]
            return handler._reply(200, dict(self.chats[-1], lastMessage=m))
        if path.startswith("/api/v1/attachment/") and path.endswith("/download"):
            data = b"\x89PNG fake picture"
            handler.send_response(200)
            handler.send_header("Content-Type", "image/png")
            handler.send_header("Content-Length", str(len(data)))
            handler.end_headers()
            handler.wfile.write(data)
            return None
        return handler._reply(404, None)

    def _websocket(self, handler, query):
        if not self.socket_on or query.get("guid", [""])[0] != self.PASSWORD or \
                query.get("EIO", [""])[0] != "4":
            return handler._reply(401, None)
        key = handler.headers["Sec-WebSocket-Key"].encode()
        accept = base64.b64encode(hashlib.sha1(key + WS_MAGIC).digest()).decode()
        handler.send_response(101)
        handler.send_header("Upgrade", "websocket")
        handler.send_header("Connection", "Upgrade")
        handler.send_header("Sec-WebSocket-Accept", accept)
        handler.end_headers()
        handler.wfile.flush()
        sock = handler.connection
        sock.sendall(ws_frame('0{"sid":"abc","upgrades":[],"pingInterval":25000,"pingTimeout":20000}'))
        self.sockets.append(sock)
        handler.close_connection = True
        try:
            while True:
                op, text = ws_read(sock)
                if op == 8:
                    break
                self.socket_frames.put(text)
                if text.startswith("40"):
                    sock.sendall(ws_frame('40{"sid":"xyz"}'))
        except OSError:
            pass

    def emit(self, name, data):
        frame = ws_frame("42" + json.dumps([name, data]))
        for sock in list(self.sockets):
            try:
                sock.sendall(frame)
            except OSError:
                self.sockets.remove(sock)

    def ping(self):
        for sock in list(self.sockets):
            sock.sendall(ws_frame("2"))

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        for sock in self.sockets:
            try:
                sock.close()
            except OSError:
                pass
