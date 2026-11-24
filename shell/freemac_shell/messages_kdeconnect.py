# SPDX-License-Identifier: GPL-3.0-or-later
"""Messages' phone backend: an Android phone's texts over KDE Connect (no GTK).

KDE Connect is an open protocol (kdeconnect-kde and kdeconnect-android are
GPL software; the packets are described in their public sources and on
KDE's community wiki). This is freemac's own small client for the part
Messages needs, written from that documentation:

* Discovery. Each side announces itself with an identity packet, a line of
  JSON, sent over UDP to port 1716 (broadcast, or straight to an address the
  person typed). A device that hears one connects over TCP to the tcpPort in
  it and sends its own identity, in plain text.
* TLS. On that TCP connection the side that connected becomes the TLS
  server and the side that accepted becomes the TLS client; each uses a
  self-signed certificate whose common name is its device id. Protocol
  version 8 sends the identity once more inside TLS.
* Pairing. A "kdeconnect.pair" packet with pair true asks; the same packet
  back says yes. Both screens show a code made from the two certificates'
  public keys (and, in version 8, the request's timestamp), so the person can
  see that they are talking to their own phone. Once paired the phone's
  certificate is kept, and a different one later is turned away.
* The SMS plugin: "kdeconnect.sms.request_conversations" (the newest
  message of every conversation), "kdeconnect.sms.request_conversation" (one
  conversation's messages), "kdeconnect.sms.request" (send a text) and
  "kdeconnect.sms.request_attachment"; the phone answers with
  "kdeconnect.sms.messages", which it also sends by itself when a text comes
  in or goes out, and "kdeconnect.sms.attachment_file", whose file comes on a
  second TLS connection to the port the packet names.

Python's ssl module can't accept an unknown certificate from a TLS *client*
(it has no verify callback), so this client always ends up as the TLS
client: it answers every identity it hears with its own, so the phone is the
one that connects, and it reads the phone's certificate itself and checks it
against the one kept at pairing.

If KDE's own kdeconnectd is already running, Messages uses it over D-Bus
instead (KdeConnectDaemon below), so the phone never sees two computers.

Original freemac code.
"""
import hashlib
import json
import os
import re
import socket
import ssl
import subprocess
import threading
import time
import uuid

from . import messages_store as store

PROTOCOL_VERSION = 8
UDP_PORT = 1716
TCP_PORTS = range(1716, 1765)
MAX_LINE = 4 * 1024 * 1024        # the phone's longest packet (a big conversation)
MAX_ATTACHMENT = 200 * 1024 * 1024  # bigger files are left on the phone
VALID_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
OUR_ID = re.compile(r"^[A-Za-z0-9_]{32,38}$")
INCOMING = ["kdeconnect.sms.messages", "kdeconnect.sms.attachment_file"]
OUTGOING = ["kdeconnect.sms.request", "kdeconnect.sms.request_conversations",
            "kdeconnect.sms.request_conversation", "kdeconnect.sms.request_attachment"]
# Android's message types (Telephony.TextBasedSmsColumns.TYPE).
TYPE_INBOX, TYPE_SENT, TYPE_OUTBOX, TYPE_FAILED, TYPE_QUEUED = 1, 2, 4, 5, 6


def make_packet(kind, body, **extra):
    packet = {"id": int(time.time() * 1000), "type": kind, "body": body}
    packet.update(extra)
    return (json.dumps(packet, separators=(",", ":")) + "\n").encode("utf-8")


def parse_packet(line):
    try:
        packet = json.loads(line.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        return None
    if not isinstance(packet, dict) or not isinstance(packet.get("type"), str):
        return None
    if not isinstance(packet.get("body"), dict):
        packet["body"] = {}
    return packet


# -- certificates -----------------------------------------------------------------
def make_certificate(folder, device_id):
    """(cert.pem, key.pem) in folder, made once with OpenSSL (as KDE Connect
    makes its own: O=KDE, OU=Kde connect, CN=the device id)."""
    os.makedirs(folder, mode=0o700, exist_ok=True)
    cert, key = os.path.join(folder, "cert.pem"), os.path.join(folder, "key.pem")
    if not (os.path.exists(cert) and os.path.exists(key)):
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256",
                        "-keyout", key, "-out", cert, "-days", "3650", "-set_serial", "10",
                        "-subj", f"/O=KDE/OU=Kde connect/CN={device_id}"],
                       check=True, capture_output=True)
        os.chmod(key, 0o600)
    return cert, key


def _der_item(data, pos):
    """(tag, start of content, end) of the DER item at pos."""
    tag = data[pos]
    length = data[pos + 1]
    pos += 2
    if length & 0x80:
        count = length & 0x7F
        length = int.from_bytes(data[pos:pos + count], "big")
        pos += count
    return tag, pos, pos + length


def public_key_der(cert_der):
    """The SubjectPublicKeyInfo of a DER certificate, as DER: what both KDE
    Connect apps hash for the pairing code."""
    _t, start, _e = _der_item(cert_der, 0)            # Certificate
    tag, pos, end = _der_item(cert_der, start)        # TBSCertificate
    fields = []
    while pos < end:
        tag, content, stop = _der_item(cert_der, pos)
        fields.append((tag, pos, stop))
        pos = stop
    if fields and fields[0][0] == 0xA0:               # [0] version
        fields = fields[1:]
    # serial, signature, issuer, validity, subject, subjectPublicKeyInfo
    _tag, begin, stop = fields[5]
    return cert_der[begin:stop]


def verification_code(our_der, their_der, timestamp=None):
    """The eight characters both screens show while pairing."""
    a, b = public_key_der(our_der), public_key_der(their_der)
    if a < b:
        a, b = b, a
    digest = hashlib.sha256(a + b)
    if timestamp is not None:
        digest.update(str(int(timestamp)).encode("ascii"))
    return digest.hexdigest()[:8].upper()


def fingerprint(der):
    return hashlib.sha256(der).hexdigest()


# -- normalising the phone's messages ----------------------------------------------
def addresses_of(message):
    out = []
    for item in message.get("addresses") or []:
        if isinstance(item, dict) and item.get("address"):
            out.append(str(item["address"]))
        elif isinstance(item, str):
            out.append(item)
    return out


def convert(device_id, raw_messages, names=None):
    """The phone's message dicts -> ([Chat], [Message])."""
    names = names or {}
    chats, messages = {}, []
    for raw in raw_messages:
        if not isinstance(raw, dict) or "thread_id" not in raw:
            continue
        thread = str(raw.get("thread_id"))
        chat_id = f"kdc:{device_id}:{thread}"
        kind = int(raw.get("type") or TYPE_INBOX)
        from_me = kind != TYPE_INBOX
        addresses = addresses_of(raw)
        date = int(raw.get("date") or 0)
        status = {TYPE_INBOX: "received", TYPE_SENT: "sent", TYPE_OUTBOX: "sending",
                  TYPE_QUEUED: "sending", TYPE_FAILED: "failed"}.get(kind, "sent")
        attachments = []
        for part in raw.get("attachments") or []:
            if isinstance(part, dict):
                attachments.append({"id": str(part.get("unique_identifier") or part.get("part_id")),
                                    "part_id": part.get("part_id"), "name": part.get("unique_identifier") or "",
                                    "mime": part.get("mime_type") or "", "path": ""})
        text = raw.get("body") or ""
        messages.append(store.Message(
            id=f"kdc:{device_id}:{raw.get('_id')}:{date}", chat_id=chat_id, text=text, date=date,
            from_me=from_me, sender="" if from_me else (addresses[0] if addresses else ""),
            service="sms", status=status, read=bool(raw.get("read", 1)) or from_me,
            attachments=attachments, remote_id=str(raw.get("_id"))))
        chat = chats.get(chat_id)
        if chat is None:
            chat = chats[chat_id] = store.Chat(id=chat_id, backend="kdeconnect", service="sms",
                                               remote_id=thread)
        for a in addresses:
            if store.normalise_address(a) not in {store.normalise_address(x) for x in chat.addresses}:
                chat.addresses.append(a)
        if date >= chat.last_date:
            chat.last_date = date
            chat.last_text = text or store.attachment_summary(messages[-1])
    for chat in chats.values():
        chat.title = ", ".join(names.get(store.normalise_address(a)) or store.format_address(a)
                               for a in chat.addresses)
    return list(chats.values()), messages


# -- the connection to one phone -----------------------------------------------------
class Link:
    def __init__(self, owner, sock, identity, cert_der, address):
        self.owner = owner
        self.sock = sock
        self.identity = identity
        self.device_id = identity["deviceId"]
        self.name = identity.get("deviceName") or "Phone"
        self.cert_der = cert_der
        self.address = address
        self.lock = threading.Lock()
        self.closed = False
        self.pair_timestamp = None

    def send(self, kind, body, **extra):
        data = make_packet(kind, body, **extra)
        with self.lock:
            self.sock.sendall(data)

    def read_loop(self):
        buf = b""
        try:
            while True:
                chunk = self.sock.recv(65536)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if line.strip():
                        packet = parse_packet(line)
                        if packet is not None:
                            self.owner._packet(self, packet)
                if len(buf) > MAX_LINE:
                    break
        except (OSError, ssl.SSLError):
            pass
        finally:
            self.close()

    def close(self):
        if self.closed:
            return
        self.closed = True
        try:
            self.sock.close()
        except OSError:
            pass
        self.owner._link_closed(self)


class KdeConnect:
    """freemac's own KDE Connect client. listener gets, on this backend's
    threads (the app moves them to the main loop):

      backend_status(backend, text, connected)
      backend_devices(backend, [{"id", "name", "paired", "connected"}])
      backend_pair_request(backend, device_id, name, code)   the phone asks
      backend_paired(backend, device_id, name, ok)
      backend_data(backend, [Chat], [Message])
      backend_attachment(backend, message_id, attachment_id, path)
    """
    kind = "kdeconnect"

    def __init__(self, listener, state_dir=None, name=None, udp_port=UDP_PORT, tcp_ports=TCP_PORTS,
                 announce_to=None, names=None, broadcast_every=30):
        self.listener = listener
        self.state_dir = state_dir or os.path.join(store.data_dir(), "kdeconnect")
        self.name = name or socket.gethostname() or "freemac"
        self.udp_port = udp_port
        self.tcp_ports = tcp_ports
        # Where identities go: the broadcast address, and phones typed in.
        self.announce_to = list(announce_to) if announce_to is not None else [("255.255.255.255", UDP_PORT)]
        self.names = names or {}
        self.broadcast_every = broadcast_every
        self.reply_port = UDP_PORT    # where phones hear identities (1716)
        self.links = {}
        self.seen = {}              # device id -> identity, for unpaired phones found
        self.pending = {}           # device id -> time we asked to pair
        self.stopping = threading.Event()
        self.tcp = self.udp = None
        self.tcp_port = None
        self.lock = threading.RLock()
        os.makedirs(self.state_dir, mode=0o700, exist_ok=True)
        self.device_id = self._device_id()
        self.cert, self.key = make_certificate(self.state_dir, self.device_id)
        with open(self.cert) as f:
            self.cert_der = ssl.PEM_cert_to_DER_cert(f.read())

    # -- set-up -----------------------------------------------------------------
    def _device_id(self):
        path = os.path.join(self.state_dir, "device-id")
        try:
            with open(path) as f:
                found = f.read().strip()
            if OUR_ID.match(found):
                return found
        except OSError:
            pass
        found = uuid.uuid4().hex
        with open(path, "w") as f:
            f.write(found)
        return found

    def paired(self):
        return store._read_json(os.path.join(self.state_dir, "paired.json"), {})

    def _save_paired(self, paired):
        store._write_json(os.path.join(self.state_dir, "paired.json"), paired, private=True)

    def identity(self):
        return {"deviceId": self.device_id, "deviceName": self.name, "deviceType": "desktop",
                "protocolVersion": PROTOCOL_VERSION, "incomingCapabilities": INCOMING,
                "outgoingCapabilities": OUTGOING, "tcpPort": self.tcp_port}

    def start(self):
        for port in self.tcp_ports:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                sock.bind(("", port))
            except OSError:
                sock.close()
                continue
            sock.listen(8)
            self.tcp, self.tcp_port = sock, sock.getsockname()[1]
            break
        if self.tcp is None:
            self.listener.backend_status(self.kind, "Couldn't open a network port for KDE Connect.", False)
            return
        self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.udp.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        try:
            self.udp.bind(("", self.udp_port))
        except OSError:
            pass        # another program hears 1716; we can still announce ourselves
        for target in (self._accept_loop, self._udp_loop, self._announce_loop):
            threading.Thread(target=target, daemon=True).start()
        self._status()

    def stop(self):
        self.stopping.set()
        for sock in (self.tcp, self.udp):
            if sock is not None:
                try:
                    sock.close()
                except OSError:
                    pass
        for link in list(self.links.values()):
            link.close()

    def add_address(self, host):
        """A phone typed in by its address, for networks where broadcasts don't reach."""
        target = (host, UDP_PORT)
        if target not in self.announce_to:
            self.announce_to.append(target)
        self.announce()

    # -- discovery ----------------------------------------------------------------
    def announce(self, to=None):
        data = make_packet("kdeconnect.identity", self.identity())
        for target in ([to] if to else self.announce_to):
            try:
                self.udp.sendto(data, target)
            except (OSError, AttributeError):
                pass

    def _announce_loop(self):
        while not self.stopping.is_set():
            if not any(l.device_id in self.paired() for l in self.links.values()):
                self.announce()
            self.stopping.wait(self.broadcast_every)

    def _udp_loop(self):
        last = {}
        while not self.stopping.is_set():
            try:
                data, (host, _port) = self.udp.recvfrom(65536)
            except OSError:
                if self.stopping.is_set():
                    return
                time.sleep(0.2)
                continue
            packet = parse_packet(data.strip())
            if not packet or packet["type"] != "kdeconnect.identity":
                continue
            body = packet["body"]
            device = str(body.get("deviceId") or "")
            if device == self.device_id or not VALID_ID.match(device) or device in self.links:
                continue
            if time.time() - last.get(device, 0) < 1:
                continue
            last[device] = time.time()
            # Answer straight back, so the phone connects to us (we stay TLS client).
            self.announce((host, self.reply_port))

    def _accept_loop(self):
        while not self.stopping.is_set():
            try:
                sock, address = self.tcp.accept()
            except OSError:
                return
            threading.Thread(target=self._handshake, args=(sock, address), daemon=True).start()

    def _read_line(self, sock, limit=65536):
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(1)
            if not chunk:
                raise OSError("closed")
            buf += chunk
            if len(buf) > limit:
                raise OSError("too long")
        return buf

    def _handshake(self, sock, address):
        try:
            sock.settimeout(10)
            packet = parse_packet(self._read_line(sock).strip())
            if not packet or packet["type"] != "kdeconnect.identity":
                sock.close()
                return
            identity = packet["body"]
            device = str(identity.get("deviceId") or "")
            if not VALID_ID.match(device) or device == self.device_id:
                sock.close()
                return
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE     # checked by hand below, against the paired certificate
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            context.load_cert_chain(self.cert, self.key)
            tls = context.wrap_socket(sock, server_side=False)
            their_der = tls.getpeercert(binary_form=True)
            if not their_der:
                tls.close()
                return
            version = min(int(identity.get("protocolVersion") or 7), PROTOCOL_VERSION)
            if version >= 8:
                tls.sendall(make_packet("kdeconnect.identity", self.identity()))
                again = parse_packet(self._read_line(tls).strip())
                if not again or again["type"] != "kdeconnect.identity" or \
                        str(again["body"].get("deviceId")) != device:
                    tls.close()
                    return
                identity = again["body"]
            known = self.paired().get(device)
            if known and known.get("fingerprint") != fingerprint(their_der):
                self.listener.backend_status(self.kind, f"“{identity.get('deviceName') or device}” has a new "
                                             "security certificate. Unpair it and pair it again.", False)
                tls.close()
                return
            tls.settimeout(None)
            sock_opt(tls)
        except (OSError, ssl.SSLError, ValueError):
            try:
                sock.close()
            except OSError:
                pass
            return
        link = Link(self, tls, identity, their_der, address[0])
        with self.lock:
            old = self.links.get(device)
            self.links[device] = link
        if old is not None:
            old.closed = True
            try:
                old.sock.close()
            except OSError:
                pass
        if not known:
            self.seen[device] = identity
        self._devices()
        self._status()
        if known:
            self.refresh()
        link.read_loop()

    def _link_closed(self, link):
        with self.lock:
            if self.links.get(link.device_id) is link:
                del self.links[link.device_id]
        if not self.stopping.is_set():
            self._devices()
            self._status()

    # -- what the listener sees ---------------------------------------------------
    def devices(self):
        paired = self.paired()
        out = []
        for device, info in paired.items():
            out.append({"id": device, "name": info.get("name") or "Phone", "paired": True,
                        "connected": device in self.links})
        for device, identity in self.seen.items():
            if device not in paired and device in self.links:
                out.append({"id": device, "name": identity.get("deviceName") or "Phone",
                            "paired": False, "connected": True})
        return out

    def _devices(self):
        self.listener.backend_devices(self.kind, self.devices())

    def _status(self):
        paired = self.paired()
        on = [l for d, l in self.links.items() if d in paired]
        if on:
            self.listener.backend_status(self.kind, f"Connected to “{on[0].name}”", True)
        elif paired:
            name = next(iter(paired.values())).get("name") or "your phone"
            self.listener.backend_status(self.kind, f"Looking for “{name}”…", False)
        else:
            self.listener.backend_status(self.kind, "No phone paired", False)

    # -- pairing ------------------------------------------------------------------
    def pair(self, device_id):
        """Ask the phone to pair; returns the code its screen should show."""
        link = self.links.get(device_id)
        if link is None:
            raise ConnectionError("That phone isn't in reach.")
        stamp = int(time.time())
        link.pair_timestamp = stamp
        self.pending[device_id] = time.time()
        link.send("kdeconnect.pair", {"pair": True, "timestamp": stamp})
        return self.code_for(link)

    def code_for(self, link):
        version = min(int(link.identity.get("protocolVersion") or 7), PROTOCOL_VERSION)
        return verification_code(self.cert_der, link.cert_der,
                                 link.pair_timestamp if version >= 8 else None)

    def accept_pair(self, device_id, ok=True):
        """Answer the phone's own request to pair."""
        link = self.links.get(device_id)
        if link is None:
            return
        link.send("kdeconnect.pair", {"pair": bool(ok)})
        if ok:
            self._paired(link)

    def unpair(self, device_id):
        link = self.links.get(device_id)
        if link is not None:
            try:
                link.send("kdeconnect.pair", {"pair": False})
            except OSError:
                pass
        paired = self.paired()
        paired.pop(device_id, None)
        self._save_paired(paired)
        self._devices()
        self._status()

    def _paired(self, link):
        paired = self.paired()
        paired[link.device_id] = {"name": link.name, "fingerprint": fingerprint(link.cert_der),
                                  "address": link.address}
        self._save_paired(paired)
        self.pending.pop(link.device_id, None)
        self.listener.backend_paired(self.kind, link.device_id, link.name, True)
        self._devices()
        self._status()
        self.refresh()

    def _pair_packet(self, link, body):
        wants = bool(body.get("pair"))
        paired = link.device_id in self.paired()
        if not wants:
            self.pending.pop(link.device_id, None)
            if paired:
                self.unpair(link.device_id)
            self.listener.backend_paired(self.kind, link.device_id, link.name, False)
            return
        if link.device_id in self.pending:
            self._paired(link)        # the phone said yes to our request
        elif paired:
            link.send("kdeconnect.pair", {"pair": True})
        else:
            link.pair_timestamp = int(body.get("timestamp") or 0) or None
            self.listener.backend_pair_request(self.kind, link.device_id, link.name, self.code_for(link))

    # -- texts ----------------------------------------------------------------------
    def phone(self):
        paired = self.paired()
        return next((l for d, l in self.links.items() if d in paired), None)

    def refresh(self):
        link = self.phone()
        if link is not None:
            try:
                link.send("kdeconnect.sms.request_conversations", {})
            except OSError:
                pass

    def load_conversation(self, chat, before=None, count=100):
        link = self.phone()
        if link is None:
            return
        body = {"threadID": int(chat.remote_id), "numberToRequest": count}
        if before:
            body["rangeStartTimestamp"] = int(before)
        link.send("kdeconnect.sms.request_conversation", body)

    def send(self, addresses, text):
        link = self.phone()
        if link is None:
            raise ConnectionError("Your phone isn't connected.")
        link.send("kdeconnect.sms.request", {"version": 2, "addresses": [{"address": a} for a in addresses],
                                             "messageBody": text})

    def request_attachment(self, message, attachment):
        link = self.phone()
        if link is None:
            raise ConnectionError("Your phone isn't connected.")
        self._wanted = getattr(self, "_wanted", {})
        self._wanted[attachment["id"]] = message.id
        link.send("kdeconnect.sms.request_attachment", {"part_id": attachment.get("part_id"),
                                                        "unique_identifier": attachment["id"]})

    def _packet(self, link, packet):
        kind, body = packet["type"], packet["body"]
        if kind == "kdeconnect.pair":
            self._pair_packet(link, body)
            return
        if link.device_id not in self.paired():
            return                    # nothing but pairing from a phone we don't know
        if kind == "kdeconnect.sms.messages":
            chats, messages = convert(link.device_id, body.get("messages") or [], self.names)
            self.listener.backend_data(self.kind, chats, messages)
        elif kind == "kdeconnect.sms.attachment_file":
            info = packet.get("payloadTransferInfo") or {}
            size = int(packet.get("payloadSize") or 0)
            name = str(body.get("filename") or "")
            if info.get("port") and 0 <= size <= MAX_ATTACHMENT and name:
                threading.Thread(target=self._download, args=(link, int(info["port"]), size, name),
                                 daemon=True).start()

    def _download(self, link, port, size, name):
        folder = os.path.join(self.state_dir, "attachments")
        os.makedirs(folder, mode=0o700, exist_ok=True)
        safe = re.sub(r"[^\w.\-]+", "_", os.path.basename(name)) or "attachment"
        path = os.path.join(folder, safe)
        try:
            raw = socket.create_connection((link.address, port), timeout=15)
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
            context.load_cert_chain(self.cert, self.key)
            tls = context.wrap_socket(raw, server_side=False)
            if tls.getpeercert(binary_form=True) != link.cert_der:
                tls.close()
                return
            got = 0
            with open(path + ".part", "wb") as out:
                while got < size:
                    chunk = tls.recv(min(65536, size - got))
                    if not chunk:
                        break
                    out.write(chunk)
                    got += len(chunk)
            tls.close()
            if got != size:
                os.remove(path + ".part")
                return
            os.replace(path + ".part", path)
        except (OSError, ssl.SSLError):
            return
        message_id = getattr(self, "_wanted", {}).pop(name, "")
        self.listener.backend_attachment(self.kind, message_id, name, path)


def sock_opt(sock):
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    except OSError:
        pass


# -- KDE's own daemon over D-Bus ------------------------------------------------------
DAEMON_BUS = "org.kde.kdeconnect"
DAEMON_PATH = "/modules/kdeconnect"
DAEMON_IFACE = "org.kde.kdeconnect.daemon"
CONVERSATIONS_IFACE = "org.kde.kdeconnect.device.conversations"
DEVICE_IFACE = "org.kde.kdeconnect.device"


def daemon_running(bus):
    """True when kdeconnectd owns its name on the session bus."""
    try:
        from gi.repository import GLib
        out = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                            "NameHasOwner", GLib.Variant("(s)", (DAEMON_BUS,)), None, 0, 2000, None)
        return bool(out.unpack()[0])
    except Exception:   # noqa: BLE001 - no bus
        return False


def daemon_message(value):
    """One ConversationMessage as kdeconnectd's D-Bus gives it (a struct of
    event, body, addresses, date, type, read, threadID, uID, subID,
    attachments) -> the same dict the phone's own packets have."""
    while hasattr(value, "unpack"):
        value = value.unpack()
    if isinstance(value, dict):
        return value
    if not isinstance(value, (tuple, list)) or len(value) < 8:
        return None
    fields = list(value) + [None] * (10 - len(value))
    event, body, addresses, date, kind, read, thread, uid, sub, parts = fields[:10]
    return {"event": event, "body": body, "addresses": [{"address": a[0] if isinstance(a, (tuple, list)) else a}
                                                        for a in addresses or []],
            "date": date, "type": kind, "read": read, "thread_id": thread, "_id": uid, "sub_id": sub,
            "attachments": [{"part_id": p[0], "mime_type": p[1], "unique_identifier": p[3]}
                            for p in parts or [] if isinstance(p, (tuple, list)) and len(p) >= 4]}


class KdeConnectDaemon:
    """The same backend, through a kdeconnectd that is already running
    (paired and set up with KDE's own tools). Every call is asynchronous, so
    the window never waits on the daemon; answers and signals arrive on the
    GLib main loop, so listener is called directly."""
    kind = "kdeconnect"

    def __init__(self, listener, bus, names=None):
        self.listener = listener
        self.bus = bus
        self.names = names or {}
        self.subscriptions = []
        self.device = None
        self.device_name = "Phone"
        self.stopped = False

    def _call(self, path, iface, method, args=None, reply=None, done=None):
        from gi.repository import GLib

        def finish(bus, result, _data):
            try:
                value = bus.call_finish(result)
            except GLib.Error as e:
                if done and not self.stopped:
                    done(None, e)
                return
            if done and not self.stopped:
                done(value, None)
        self.bus.call(DAEMON_BUS, path, iface, method, args, GLib.VariantType(reply) if reply else None,
                      0, 15000, None, finish, None)

    def start(self):
        from gi.repository import GLib
        self.listener.backend_status(self.kind, "Asking KDE Connect for your phone…", False)
        self._call(DAEMON_PATH, DAEMON_IFACE, "devices", GLib.Variant("(bb)", (False, True)), "(as)",
                   self._got_devices)

    def _got_devices(self, value, error):
        from gi.repository import GLib
        found = value.unpack()[0] if value is not None else []
        if not found:
            self.listener.backend_status(self.kind, "KDE Connect is running, but no phone is paired with it.", False)
            return
        self.device = found[0]
        for signal in ("conversationCreated", "conversationUpdated"):
            self.subscriptions.append(self.bus.signal_subscribe(
                DAEMON_BUS, CONVERSATIONS_IFACE, signal, self._path(), None, 0, self._signal, None))
        self._call(self._path(), "org.freedesktop.DBus.Properties", "Get",
                   GLib.Variant("(ss)", (DEVICE_IFACE, "name")), "(v)", self._got_name)

    def _got_name(self, value, error):
        if value is not None:
            self.device_name = value.unpack()[0]
        self.listener.backend_status(self.kind, f"Connected to “{self.device_name}” through KDE Connect", True)
        self.listener.backend_devices(self.kind, self.devices())
        self.refresh()

    def stop(self):
        self.stopped = True
        for sub in self.subscriptions:
            self.bus.signal_unsubscribe(sub)
        self.subscriptions = []

    def _path(self):
        return f"{DAEMON_PATH}/devices/{self.device}"

    def _signal(self, _bus, _sender, _path, _iface, _signal, params, _data):
        raw = daemon_message(params.unpack()[0]) if params.n_children() else None
        if raw:
            self._deliver([raw])

    def _deliver(self, raws):
        chats, messages = convert(self.device, raws, self.names)
        if chats or messages:
            self.listener.backend_data(self.kind, chats, messages)

    def refresh(self):
        if not self.device:
            return
        self._call(self._path(), CONVERSATIONS_IFACE, "requestAllConversationThreads")
        self._call(self._path(), CONVERSATIONS_IFACE, "activeConversations", None, "(av)",
                   lambda value, _e: value is not None and
                   self._deliver([r for r in (daemon_message(v) for v in value.unpack()[0]) if r]))

    def load_conversation(self, chat, before=None, count=100):
        from gi.repository import GLib
        if self.device:
            self._call(self._path(), CONVERSATIONS_IFACE, "requestConversation",
                       GLib.Variant("(xii)", (int(chat.remote_id), 0, count)))

    def send(self, addresses, text):
        from gi.repository import GLib
        if not self.device:
            raise ConnectionError("KDE Connect has no phone paired.")

        def done(_value, error):
            if error is not None:
                self.listener.backend_status(self.kind, "KDE Connect couldn't send the text.", False)
        self._call(self._path(), CONVERSATIONS_IFACE, "sendWithoutConversation",
                   GLib.Variant("(avsav)", ([GLib.Variant("s", a) for a in addresses], text, [])), None, done)

    def devices(self):
        return [{"id": self.device, "name": self.device_name, "paired": True, "connected": True}] if self.device else []

    def pair(self, device_id):
        raise ConnectionError("Pair the phone with KDE Connect's own settings while kdeconnectd is running.")

    def unpair(self, device_id):
        pass

    def accept_pair(self, device_id, ok=True):
        pass

    def add_address(self, host):
        pass

    def request_attachment(self, message, attachment):
        raise ConnectionError("Attachments aren't available through kdeconnectd yet.")
