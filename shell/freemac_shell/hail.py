# SPDX-License-Identifier: GPL-3.0-or-later
"""Hail: send files to computers and phones nearby, over the same Wi-Fi.

    freemac-hail --background    listen for nearby devices (started at log in)
    freemac-hail --send FILE...  show nearby devices and send them the files

Hail speaks the LocalSend protocol (version 2, an open, published protocol),
so besides other freemac computers it reaches phones, tablets and other
computers that have the free LocalSend app. Devices find each other with a
short "who's there?" message to the local network; files go straight from
one device to the other over an encrypted connection, never through the
internet.

Receiving is off until the person turns it on (in the Nearby window or Dials
> General). When it is on, every offer asks first: "“Sam's Phone” would like
to share 3 photos." Accepted files land in Downloads. Original freemac code.
"""
import hashlib
import http.client
import http.server
import ipaddress
import json
import mimetypes
import os
import pwd
import secrets
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import threading
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk, Pango  # noqa: E402

from . import alert, beacon, style  # noqa: E402

PROGRAM = "freemac-hail"
APP_ID = "org.freemac.Hail"
PORT = 53317
GROUP = "224.0.0.167"
API = "/api/localsend/v2"
VERSION = "2.0"
ASK_FOR = 60           # seconds an offer waits for Accept or Decline
SEEN_FOR = 30          # seconds a device stays listed after it was last heard
CHUNK = 1 << 16
STATE = os.path.join(GLib.get_user_data_dir(), "freemac", "hail")
ICON = "freemac-share-symbolic"


# -- who this computer is -------------------------------------------------------

def receiving():
    """True while nearby devices may offer files to this computer."""
    return style.prefs().get("hail_receive", "off") == "everyone"


def set_receiving(on):
    path = style.PREFS
    prefs = style.prefs()
    prefs["hail_receive"] = "everyone" if on else "off"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w") as f:
        json.dump(prefs, f, indent=1)
    os.replace(path + ".tmp", path)


def device_name():
    """What other devices call this computer: "Dean's freemac"."""
    chosen = style.prefs().get("hail_name")
    if chosen:
        return chosen
    try:
        full = pwd.getpwuid(os.getuid()).pw_gecos.split(",")[0].strip()
    except KeyError:
        full = ""
    first = full.split()[0] if full else ""
    return f"{first}’s freemac" if first else (socket.gethostname() or "freemac")


def certificate():
    """This computer's own certificate and key (made once), and its
    fingerprint, which other devices use to tell it apart."""
    os.makedirs(STATE, mode=0o700, exist_ok=True)
    cert, key = os.path.join(STATE, "cert.pem"), os.path.join(STATE, "key.pem")
    if not (os.path.exists(cert) and os.path.exists(key)):
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256",
                        "-keyout", key, "-out", cert, "-days", "3650", "-subj", "/CN=freemac"],
                       check=True, capture_output=True)
        os.chmod(key, 0o600)
    with open(cert) as f:
        der = ssl.PEM_cert_to_DER_cert(f.read())
    return cert, key, hashlib.sha256(der).hexdigest().upper()


def describe(names):
    """'a photo', '3 photos', '“Report.pdf”' or '4 files' for an offer."""
    names = list(names)
    pictures = all((mimetypes.guess_type(n)[0] or "").startswith("image/") for n in names)
    videos = all((mimetypes.guess_type(n)[0] or "").startswith("video/") for n in names)
    kind = "photo" if pictures else ("video" if videos else "")
    if len(names) == 1:
        return f"a {kind}" if kind else f"“{os.path.basename(names[0])}”"
    return f"{len(names)} {kind or 'file'}s"


def safe_parts(name):
    """The folders and file name of an offered file, with nothing that could
    climb out of Downloads."""
    parts = [p for p in name.replace("\\", "/").split("/") if p not in ("", ".", "..")]
    parts = [p.lstrip(".") or "file" for p in parts]   # no hidden files sneaked in
    return parts[-8:] or ["file"]


def free_path(folder, name):
    """folder/name, or folder/name 2.ext if that is taken."""
    path = os.path.join(folder, name)
    stem, ext = os.path.splitext(name)
    n = 2
    while os.path.exists(path) or os.path.exists(path + ".part"):
        path = os.path.join(folder, f"{stem} {n}{ext}")
        n += 1
    return path


def downloads():
    return GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD) or os.path.expanduser("~/Downloads")


def local_addresses():
    """This computer's IPv4 addresses on the local network."""
    found = []
    try:
        out = subprocess.run(["ip", "-4", "-o", "addr", "show", "scope", "global"],
                             capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return found
    for line in out.splitlines():
        fields = line.split()
        if "inet" in fields:
            try:
                found.append(ipaddress.ip_interface(fields[fields.index("inet") + 1]))
            except ValueError:
                pass
    return [a for a in found if a.ip.is_private]


# -- talking to other devices -----------------------------------------------------

def _connection(peer, timeout=10):
    if peer.get("protocol", "https") == "https":
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE   # every device's certificate is its own
        return http.client.HTTPSConnection(peer["ip"], peer.get("port", PORT), timeout=timeout, context=context)
    return http.client.HTTPConnection(peer["ip"], peer.get("port", PORT), timeout=timeout)


def request(peer, method, path, body=None, timeout=10):
    """(status, decoded JSON or None)."""
    conn = _connection(peer, timeout)
    try:
        data = json.dumps(body).encode() if body is not None else b""
        conn.request(method, API + path, body=data, headers={"Content-Type": "application/json"})
        reply = conn.getresponse()
        raw = reply.read()
        try:
            return reply.status, json.loads(raw) if raw else None
        except ValueError:
            return reply.status, None
    finally:
        conn.close()


class Hail(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.peers = {}          # fingerprint -> peer dict (ip, port, protocol, alias, deviceType, seen)
        self.listeners = []      # windows that show the peers
        self.session = None      # the offer being received
        self.lock = threading.Lock()
        self.background = False
        self.started = False

    # The information other devices are given about this computer.
    def info(self, with_address=True):
        me = {"alias": device_name(), "version": VERSION, "deviceModel": "freemac",
              "deviceType": "desktop", "fingerprint": self.fingerprint, "download": False}
        if with_address:
            me.update(port=PORT, protocol="https")
        return me

    def do_command_line(self, line):
        args = line.get_arguments()[1:]
        if not self.started:
            self.started = True
            self.start()
        if "--background" in args:
            if not self.background:
                self.background = True
                self.hold()
        paths = [a for a in args if not a.startswith("--")]
        if "--send" in args:
            here = line.get_cwd() or os.getcwd()
            NearbyWindow(self, [os.path.join(here, p) for p in paths]).present()
        return 0

    # -- listening --------------------------------------------------------------

    def start(self):
        try:
            self.cert, self.key, self.fingerprint = certificate()
        except (OSError, subprocess.CalledProcessError, ValueError):
            self.cert = None
            self.fingerprint = secrets.token_hex(16).upper()
        self.server = None
        if self.cert:
            try:
                self.server = Server(self)
                threading.Thread(target=self.server.serve_forever, daemon=True).start()
            except OSError:
                self.server = None   # another copy is already listening
        try:
            self.udp = self._udp_socket()
            threading.Thread(target=self._listen_udp, daemon=True).start()
        except OSError:
            self.udp = None
        self.announce()
        GLib.timeout_add_seconds(5, self._forget_old)

    def _udp_socket(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("", PORT))
        membership = struct.pack("4s4s", socket.inet_aton(GROUP), socket.inet_aton("0.0.0.0"))
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
        return sock

    def announce(self, asking=True):
        """Tell the network this computer is here. With asking, devices that
        let others find them answer. A computer that isn't receiving only
        asks while the Nearby window is open."""
        if not self.udp or not (receiving() or self.listeners or not asking):
            return False
        message = dict(self.info(), announce=asking)
        try:
            self.udp.sendto(json.dumps(message).encode(), (GROUP, PORT))
        except OSError:
            pass
        return False

    def _listen_udp(self):
        while True:
            try:
                data, (ip, _port) = self.udp.recvfrom(65536)
                message = json.loads(data)
            except (OSError, ValueError):
                continue
            if not isinstance(message, dict) or message.get("fingerprint") == self.fingerprint:
                continue
            self.saw(ip, message)
            if message.get("announce") and receiving():
                threading.Thread(target=self._answer, args=(ip, message), daemon=True).start()

    def _answer(self, ip, message):
        """Answer a device that asked who's there: over HTTP if it can be
        reached, else on the network as the protocol asks."""
        peer = {"ip": ip, "port": int(message.get("port") or PORT), "protocol": message.get("protocol", "https")}
        try:
            request(peer, "POST", "/register", self.info(), timeout=3)
        except (OSError, http.client.HTTPException, ssl.SSLError):
            self.announce(asking=False)

    def saw(self, ip, message):
        """Remember a device that was heard from."""
        key = message.get("fingerprint") or ip
        alias = str(message.get("alias") or "Unknown device")[:60]
        peer = {"ip": ip, "port": int(message.get("port") or PORT), "alias": alias,
                "protocol": message.get("protocol") if message.get("protocol") in ("http", "https") else "https",
                "deviceType": message.get("deviceType") or "desktop", "seen": time.monotonic()}
        with self.lock:
            old = self.peers.get(key)
            if old:
                peer["port"] = message.get("port") and peer["port"] or old["port"]
                peer["protocol"] = message.get("protocol") and peer["protocol"] or old["protocol"]
            self.peers[key] = peer
        GLib.idle_add(self._changed)

    def _forget_old(self):
        now = time.monotonic()
        with self.lock:
            gone = [k for k, p in self.peers.items() if now - p["seen"] > SEEN_FOR]
            for key in gone:
                del self.peers[key]
        if gone:
            self._changed()
        return True

    def _changed(self):
        for window in list(self.listeners):
            window.refresh()
        return False

    def scan(self):
        """Ask every address on the local network directly, for devices that
        miss the network-wide message (some phones do)."""
        def ask(ip):
            for protocol in ("https", "http"):
                try:
                    status, reply = request({"ip": ip, "port": PORT, "protocol": protocol},
                                            "POST", "/register", self.info(), timeout=1.5)
                except (OSError, http.client.HTTPException, ssl.SSLError):
                    continue
                if status == 200 and isinstance(reply, dict) and reply.get("fingerprint") != self.fingerprint:
                    self.saw(ip, dict(reply, port=PORT, protocol=protocol))
                return
        mine = {str(a.ip) for a in local_addresses()}
        hosts = []
        for address in local_addresses():
            network = address.network if address.network.prefixlen >= 22 else \
                ipaddress.ip_network(f"{address.ip}/24", strict=False)
            hosts += [str(h) for h in network.hosts() if str(h) not in mine]
        with ThreadPoolExecutor(max_workers=64) as pool:
            list(pool.map(ask, hosts[:1024]))

    # -- receiving ---------------------------------------------------------------

    def offer(self, sender, files, ip):
        """Called from the server's thread: ask the person, wait for the
        answer, and return (status, reply)."""
        if not receiving():
            return 403, None
        with self.lock:
            if self.session is not None:
                return 409, None
            self.session = {"id": "pending"}
        try:
            names = [f.get("fileName") or "file" for f in files.values()]
            total = sum(int(f.get("size") or 0) for f in files.values())
            folder = downloads()
            os.makedirs(folder, exist_ok=True)
            if total > shutil.disk_usage(folder).free - (200 << 20):
                GLib.idle_add(lambda: beacon.send("Not enough space", f"{sender} tried to send "
                              f"{describe(names)}, but there isn't room in Downloads.", icon=ICON) and False)
                return 403, None
            answered, answer = threading.Event(), []
            GLib.idle_add(self._ask, sender, names, answered, answer)
            answered.wait(ASK_FOR + 2)
            if not answer or not answer[0]:
                return 403, None
            tokens = {fid: secrets.token_urlsafe(16) for fid in files}
            session = {"id": secrets.token_urlsafe(12), "ip": ip, "sender": sender, "files": files,
                       "tokens": tokens, "folder": folder, "done": {}, "names": names}
            with self.lock:
                self.session = session
            return 200, {"sessionId": session["id"], "files": tokens}
        finally:
            with self.lock:
                if self.session is not None and self.session.get("id") == "pending":
                    self.session = None

    def _ask(self, sender, names, answered, answer):
        dialog = alert.build(None, f"“{sender}” would like to share {describe(names)}.",
                             "Accepted files go in your Downloads folder.",
                             (("Decline", Gtk.ResponseType.CANCEL), ("Accept", Gtk.ResponseType.OK)),
                             default=Gtk.ResponseType.OK, icon=ICON)
        dialog.set_keep_above(True)

        def done(_d, response):
            if not answered.is_set():
                answer.append(response == Gtk.ResponseType.OK)
                answered.set()
            dialog.destroy()
        dialog.connect("response", done)
        GLib.timeout_add_seconds(ASK_FOR, lambda: dialog.response(Gtk.ResponseType.CANCEL) or False
                                 if not answered.is_set() else False)
        dialog.show()
        return False

    def receive(self, session_id, file_id, token, ip, length, stream):
        """Save one file of the accepted offer. Returns an HTTP status."""
        with self.lock:
            session = self.session
        if not session or session.get("id") != session_id:
            return 409
        if session["ip"] != ip or session["tokens"].get(file_id) != token or file_id in session["done"]:
            return 403
        offered = session["files"][file_id]
        parts = safe_parts(offered.get("fileName") or "file")
        folder = session["folder"]
        for part in parts[:-1]:
            folder = os.path.join(folder, part)
            os.makedirs(folder, exist_ok=True)
        path = free_path(folder, parts[-1])
        digest = hashlib.sha256()
        left = length if length is not None else int(offered.get("size") or 0)
        try:
            with open(path + ".part", "wb") as out:
                while left > 0:
                    data = stream.read(min(CHUNK, left))
                    if not data:
                        break
                    out.write(data)
                    digest.update(data)
                    left -= len(data)
        except OSError:
            self._drop(path + ".part")
            return 500
        if left > 0:
            self._drop(path + ".part")
            return 400
        wanted = offered.get("sha256")
        if wanted and wanted.lower() != digest.hexdigest():
            self._drop(path + ".part")
            return 422
        os.replace(path + ".part", path)
        with self.lock:
            session["done"][file_id] = path
            finished = len(session["done"]) == len(session["files"])
            if finished:
                self.session = None
        if finished:
            GLib.idle_add(self._received, session)
        return 200

    @staticmethod
    def _drop(path):
        try:
            os.remove(path)
        except OSError:
            pass

    def _received(self, session):
        paths = list(session["done"].values())
        beacon.send(f"Received {describe(session['names'])} from {session['sender']}",
                    "Click to see it in Downloads." if len(paths) > 1 else "Click to open it.",
                    icon=ICON, app="Hail", open_path=paths[0] if len(paths) == 1 else session["folder"])
        return False

    def cancelled(self, session_id):
        with self.lock:
            session = self.session
            if session and session.get("id") == session_id:
                self.session = None
            else:
                return
        if session["done"]:
            GLib.idle_add(lambda: beacon.send(f"{session['sender']} stopped sending",
                                              f"{len(session['done'])} of {len(session['files'])} arrived "
                                              "in Downloads.", icon=ICON, app="Hail") and False)


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "freemac-hail"
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    def _reply(self, status, body=None):
        data = json.dumps(body).encode() if body is not None else b""
        self.send_response(status)
        if body is not None:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _length(self):
        try:
            return int(self.headers.get("Content-Length"))
        except (TypeError, ValueError):
            return None

    def _json(self):
        length = self._length()
        if length is None or length > (8 << 20):
            return None
        try:
            return json.loads(self.rfile.read(length) or b"null")
        except ValueError:
            return None

    def do_GET(self):
        hail = self.server.hail
        path = urllib.parse.urlparse(self.path).path
        if path == API + "/info":
            return self._reply(200, hail.info(with_address=False))
        self._reply(404)

    def do_POST(self):
        hail = self.server.hail
        url = urllib.parse.urlparse(self.path)
        query = dict(urllib.parse.parse_qsl(url.query))
        ip = self.client_address[0]
        if url.path == API + "/register":
            body = self._json()
            if isinstance(body, dict) and body.get("fingerprint") != hail.fingerprint:
                hail.saw(ip, body)
            return self._reply(200, hail.info(with_address=False))
        if url.path == API + "/prepare-upload":
            body = self._json()
            if not isinstance(body, dict) or not isinstance(body.get("files"), dict) \
                    or not isinstance(body.get("info"), dict) or not body["files"]:
                return self._reply(400)
            hail.saw(ip, body["info"])
            sender = str(body["info"].get("alias") or "A nearby device")[:60]
            status, reply = hail.offer(sender, body["files"], ip)
            return self._reply(status, reply)
        if url.path == API + "/upload":
            if not all(query.get(k) for k in ("sessionId", "fileId", "token")):
                return self._reply(400)
            status = hail.receive(query["sessionId"], query["fileId"], query["token"], ip,
                                  self._length(), self.rfile)
            if status != 200:
                self.close_connection = True
            return self._reply(status)
        if url.path == API + "/cancel":
            hail.cancelled(query.get("sessionId"))
            return self._reply(200)
        self._reply(404)


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 32

    def __init__(self, hail):
        self.hail = hail
        super().__init__(("0.0.0.0", PORT), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(hail.cert, hail.key)
        self.socket = context.wrap_socket(self.socket, server_side=True, do_handshake_on_connect=False)

    def get_request(self):
        sock, address = super().get_request()
        return sock, address

    def finish_request(self, request_sock, client_address):
        try:
            request_sock.settimeout(30)
            request_sock.do_handshake()
        except (OSError, ssl.SSLError):
            return
        super().finish_request(request_sock, client_address)


# -- sending -------------------------------------------------------------------------

def gather(paths):
    """[(path, name to send)] for the files, with each folder's files named
    under the folder."""
    found = []
    for path in paths:
        path = path.rstrip("/")
        if os.path.isdir(path):
            top = os.path.dirname(path)
            for folder, dirs, files in os.walk(path):
                dirs[:] = sorted(d for d in dirs if not d.startswith("."))
                for name in sorted(files):
                    if not name.startswith("."):
                        full = os.path.join(folder, name)
                        found.append((full, os.path.relpath(full, top)))
        elif os.path.isfile(path):
            found.append((path, os.path.basename(path)))
    return found


class Sender:
    """Sends the files to one device in a thread of its own; reports
    through on_state(text, fraction or None, finished) on the main loop."""

    def __init__(self, hail, peer, files, on_state):
        self.hail, self.peer, self.files, self.on_state = hail, dict(peer), files, on_state
        self.stopped = False
        self.session = None
        threading.Thread(target=self.run, daemon=True).start()

    def state(self, text, fraction=None, finished=False):
        GLib.idle_add(lambda: self.on_state(text, fraction, finished) and False)

    def stop(self):
        self.stopped = True
        if self.session:
            threading.Thread(target=lambda: self._quietly("POST", f"/cancel?sessionId={self.session}"),
                             daemon=True).start()

    def _quietly(self, method, path):
        try:
            request(self.peer, method, path, timeout=3)
        except (OSError, http.client.HTTPException, ssl.SSLError):
            pass

    def run(self):
        offered = {}
        for n, (path, name) in enumerate(self.files):
            fid = f"f{n}"
            offered[fid] = {"id": fid, "fileName": name, "size": os.path.getsize(path),
                            "fileType": mimetypes.guess_type(path)[0] or "application/octet-stream",
                            "sha256": None, "preview": None}
        self.state("Waiting…")
        try:
            status, reply = request(self.peer, "POST", "/prepare-upload",
                                    {"info": self.hail.info(), "files": offered}, timeout=ASK_FOR + 30)
        except (OSError, http.client.HTTPException, ssl.SSLError):
            return self.state("Couldn’t reach it", finished=True)
        if self.stopped:
            return
        if status == 204:
            return self.state("Sent", 1.0, True)
        if status == 403:
            return self.state("Declined", finished=True)
        if status == 409:
            return self.state("Busy, try again", finished=True)
        if status == 401:
            return self.state("Needs a PIN", finished=True)
        if status != 200 or not isinstance(reply, dict):
            return self.state("Couldn’t send", finished=True)
        self.session = reply.get("sessionId")
        tokens = reply.get("files") or {}
        total = sum(f["size"] for f in offered.values()) or 1
        sent = 0
        for n, (path, _name) in enumerate(self.files):
            fid = f"f{n}"
            if fid not in tokens:
                sent += offered[fid]["size"]
                continue   # the other device already has it
            query = urllib.parse.urlencode({"sessionId": self.session, "fileId": fid, "token": tokens[fid]})
            try:
                sent = self._upload(path, query, sent, total)
            except (OSError, http.client.HTTPException, ssl.SSLError, RuntimeError):
                if not self.stopped:
                    self.state("Couldn’t send", finished=True)
                return
            if self.stopped:
                return
        self.state("Sent", 1.0, True)

    def _upload(self, path, query, sent, total):
        conn = _connection(self.peer, timeout=60)
        try:
            conn.putrequest("POST", f"{API}/upload?{query}")
            conn.putheader("Content-Type", "application/octet-stream")
            conn.putheader("Content-Length", str(os.path.getsize(path)))
            conn.endheaders()
            last = 0
            with open(path, "rb") as f:
                while not self.stopped:
                    data = f.read(CHUNK)
                    if not data:
                        break
                    conn.send(data)
                    sent += len(data)
                    if time.monotonic() - last > 0.2:
                        last = time.monotonic()
                        self.state("Sending…", sent / total)
            if self.stopped:
                return sent
            reply = conn.getresponse()
            reply.read()
            if reply.status != 200:
                raise RuntimeError(reply.status)
            return sent
        finally:
            conn.close()


class DeviceTile(Gtk.Button):
    """One nearby device: a round icon, its name, and how sending to it goes."""

    def __init__(self, peer):
        super().__init__(relief=Gtk.ReliefStyle.NONE)
        self.get_style_context().add_class("hail-device")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        icon = "phone-symbolic" if peer.get("deviceType") == "mobile" else "computer-symbolic"
        self.image = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.DIALOG)
        self.image.set_pixel_size(36)
        self.image.get_style_context().add_class("hail-round")
        self.image.set_halign(Gtk.Align.CENTER)
        box.pack_start(self.image, False, False, 0)
        self.name = Gtk.Label(label=peer["alias"], max_width_chars=12, wrap=True, lines=2,
                              ellipsize=Pango.EllipsizeMode.END, justify=Gtk.Justification.CENTER)
        box.pack_start(self.name, False, False, 0)
        self.status = Gtk.Label()
        self.status.get_style_context().add_class("dim-label")
        box.pack_start(self.status, False, False, 0)
        self.bar = Gtk.ProgressBar(no_show_all=True)
        box.pack_start(self.bar, False, False, 0)
        self.add(box)
        self.set_size_request(110, -1)

    def show_state(self, text, fraction, _finished):
        self.status.set_text(text)
        if fraction is None or fraction >= 1.0:
            self.bar.hide()
        else:
            self.bar.set_fraction(fraction)
            self.bar.show()


class NearbyWindow(Gtk.ApplicationWindow):
    def __init__(self, hail, paths):
        super().__init__(application=hail, title="Nearby")
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(self.get_screen(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.hail = hail
        self.files = gather(paths)
        self.tiles, self.senders = {}, {}
        self.set_default_size(460, 330)
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=18)
        title = Gtk.Label(xalign=0)
        title.set_markup(f"<b>Send {GLib.markup_escape_text(describe(n for _p, n in self.files))} to:</b>"
                         if self.files else "<b>Nearby devices</b>")
        outer.pack_start(title, False, False, 0)
        self.flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, homogeneous=True,
                                column_spacing=8, row_spacing=8, max_children_per_line=4)
        self.flow.set_valign(Gtk.Align.START)
        self.empty = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, valign=Gtk.Align.CENTER)
        spinner = Gtk.Spinner(active=True)
        spinner.set_size_request(24, 24)
        self.empty.pack_start(spinner, False, False, 0)
        hint = Gtk.Label(label="Looking for nearby devices…\nThey need to be on the same Wi-Fi, with "
                         "receiving turned on. Phones need the free LocalSend app.",
                         justify=Gtk.Justification.CENTER, wrap=True, max_width_chars=44)
        hint.get_style_context().add_class("dim-label")
        self.empty.pack_start(hint, False, False, 0)
        self.stack = Gtk.Stack()
        self.stack.add_named(self.empty, "empty")
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.get_style_context().add_class("hail-devices")
        scroll.set_size_request(430, 170)
        scroll.add(self.flow)
        self.stack.add_named(scroll, "devices")
        outer.pack_start(self.stack, True, True, 0)
        outer.pack_start(Gtk.Separator(), False, False, 0)
        bottom = Gtk.Box(spacing=10)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        words.pack_start(Gtk.Label(label="Let nearby devices send files here", xalign=0), False, False, 0)
        self.who = Gtk.Label(xalign=0)
        self.who.get_style_context().add_class("dim-label")
        words.pack_start(self.who, False, False, 0)
        bottom.pack_start(words, True, True, 0)
        switch = Gtk.Switch(active=receiving(), valign=Gtk.Align.CENTER)
        switch.connect("notify::active", self._receiving)
        bottom.pack_start(switch, False, False, 0)
        outer.pack_start(bottom, False, False, 0)
        self.add(outer)
        self._name_line()
        hail.listeners.append(self)
        self.connect("destroy", self._closed)
        self.show_all()
        self.refresh()
        self._ask_around()
        self.timer = GLib.timeout_add_seconds(3, self._ask_around)
        GLib.timeout_add_seconds(4, self._scan_if_alone)

    def _name_line(self):
        self.who.set_text(f"Others see this computer as “{device_name()}”." if receiving()
                          else "Off: only you can send from here.")

    def _receiving(self, switch, _param):
        set_receiving(switch.get_active())
        self._name_line()
        if switch.get_active():
            self.hail.announce()

    def _ask_around(self):
        self.hail.announce()
        return True

    def _scan_if_alone(self):
        if not self.hail.peers and self.get_mapped():
            threading.Thread(target=self.hail.scan, daemon=True).start()
        return False

    def refresh(self):
        with self.hail.lock:
            peers = dict(self.hail.peers)
        for key, peer in peers.items():
            if key not in self.tiles:
                tile = DeviceTile(peer)
                tile.connect("clicked", self._send, key)
                self.tiles[key] = tile
                self.flow.add(tile)
                tile.show_all()
                tile.bar.hide()
        for key in list(self.tiles):
            if key not in peers and key not in self.senders:
                self.flow.remove(self.tiles.pop(key).get_parent())
        self.stack.set_visible_child_name("devices" if self.tiles else "empty")

    def _send(self, tile, key):
        sending = self.senders.get(key)
        if sending and not sending.finished:
            sending.stop()
            sending.finished = True
            tile.show_state("Stopped", None, True)
            return
        if not self.files:
            tile.show_state("Nothing to send", None, True)
            return
        peer = self.hail.peers.get(key)
        if not peer:
            return

        def state(text, fraction, finished, sender=None):
            tile.show_state(text, fraction, finished)
            if finished and key in self.senders:
                self.senders[key].finished = True

        sender = Sender(self.hail, peer, self.files, state)
        sender.finished = False
        self.senders[key] = sender

    def _closed(self, *_):
        GLib.source_remove(self.timer)
        if self in self.hail.listeners:
            self.hail.listeners.remove(self)
        for sender in self.senders.values():
            if not sender.finished:
                sender.stop()


CSS = b"""
.hail-devices, .hail-devices viewport, .hail-devices flowbox, .hail-devices flowboxchild { background: transparent; border: none; }
.hail-device { padding: 8px; border-radius: 10px; }
.hail-device:hover { background: alpha(@theme_fg_color, 0.06); }
.hail-round { background: @theme_selected_bg_color; color: white; border-radius: 999px;
              padding: 14px; min-width: 36px; min-height: 36px; }
"""


def main():
    if len(sys.argv) < 2:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    return Hail().run(sys.argv)
