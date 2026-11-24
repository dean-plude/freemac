#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""A small HTTP server on 127.0.0.1 for Ferry's URL loading tests.

    http_server.py PORTFILE [CERTFILE KEYFILE]

Listens on a free port of the loopback address and writes "PORT CLOSED"
to PORTFILE once it is ready, where CLOSED is a port nothing listens on
(for the "could not connect" tests). Given a certificate and its key, it
also serves the same pages over TLS on another port, and writes "PORT
CLOSED TLSPORT". Runs until it is killed. It never talks to anything but
the programs under test.

Besides the plain pages, it has pages for redirects (/redirect-to), HTTP
Basic and Digest authentication (/basic, /digest), cookies (/cookies/...)
and caching (/cache/...); /hits tells how often a page was asked for and
how often it answered 304."""
import base64
import gzip
import hashlib
import os
import http.server
import socket
import ssl
import sys
import threading
import time
import urllib.parse

hits = {}       # path with its query -> requests
not_modified = {}  # path with its query -> 304 answers
lock = threading.Lock()
LAST_MODIFIED = "Mon, 02 Jan 2023 03:04:05 GMT"
DIGEST_REALM = "ferry-digest"
DIGEST_NONCE = "ferrynonce0123456789"
DIGEST_OPAQUE = "ferryopaque"


def digest_params(header):
    """The parameters of a Digest Authorization field."""
    out = {}
    rest = header[len("Digest "):]
    while rest:
        rest = rest.lstrip(" ,")
        if "=" not in rest:
            break
        k, rest = rest.split("=", 1)
        if rest.startswith('"'):
            v, rest = rest[1:].split('"', 1)
        else:
            v, _, rest = rest.partition(",")
        out[k.strip().lower()] = v.strip()
    return out


def md5(s):
    return hashlib.md5(s.encode()).hexdigest()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "FerryTest/1"
    sys_version = ""

    def log_message(self, *args):
        pass

    def send(self, status, body=b"", ctype="text/plain; charset=utf-8", extra=()):
        self.send_response(status)
        if ctype:
            self.send_header("Content-Type", ctype)
        for k, v in extra:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def handle_any(self):
        url = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(url.query)
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        path = url.path
        first = lambda name, default="": query.get(name, [default])[0]
        with lock:
            hits[self.path] = hits.get(self.path, 0) + 1
            count = hits[self.path]
        try:
            if path == "/hits":
                u = first("u")
                with lock:
                    text = "requests=%d notmodified=%d\n" % (hits.get(u, 0), not_modified.get(u, 0))
                self.send(200, text.encode(), extra=[("Cache-Control", "no-store")])
            elif path == "/headers":
                # the fields that loading adds by itself
                lines = ["method=" + self.command]
                for name in ("Authorization", "Cookie", "If-None-Match", "If-Modified-Since", "Content-Type"):
                    lines.append(name.lower() + "=" + (self.headers.get(name) or "(none)"))
                lines.append("body=" + body.decode("utf-8", "replace"))
                self.send(200, ("\n".join(lines) + "\n").encode(), extra=[("Cache-Control", "no-store")])
            elif path == "/redirect-to":
                self.send(int(first("code", "302")), b"redirecting\n", extra=[("Location", first("to", "/hello"))])
            elif path == "/basic":
                want = "Basic " + base64.b64encode(("%s:%s" % (first("user"), first("pass"))).encode()).decode()
                if self.headers.get("Authorization") == want:
                    self.send(200, ("basic ok %s\n" % first("user")).encode())
                else:
                    self.send(401, b"need basic\n", extra=[("WWW-Authenticate", 'Basic realm="ferry"')])
            elif path == "/digest":
                got = self.headers.get("Authorization") or ""
                ok = False
                if got.startswith("Digest "):
                    p = digest_params(got)
                    ha1 = md5("%s:%s:%s" % (first("user"), DIGEST_REALM, first("pass")))
                    ha2 = md5("%s:%s" % (self.command, p.get("uri", "")))
                    want = md5(":".join([ha1, DIGEST_NONCE, p.get("nc", ""), p.get("cnonce", ""), "auth", ha2]))
                    ok = (p.get("username") == first("user") and p.get("realm") == DIGEST_REALM and
                          p.get("nonce") == DIGEST_NONCE and p.get("uri") == self.path and
                          p.get("qop") == "auth" and p.get("opaque") == DIGEST_OPAQUE and
                          p.get("response") == want)
                if ok:
                    self.send(200, ("digest ok %s\n" % first("user")).encode())
                else:
                    challenge = 'Digest realm="%s", qop="auth", nonce="%s", opaque="%s", algorithm=MD5' % (
                        DIGEST_REALM, DIGEST_NONCE, DIGEST_OPAQUE)
                    self.send(401, b"need digest\n",
                              extra=[("WWW-Authenticate", 'Basic realm="other"'), ("WWW-Authenticate", challenge)])
            elif path == "/cookies/set":
                # each h is a Set-Cookie field, as it is
                self.send(200, b"set\n", extra=[("Set-Cookie", h) for h in query.get("h", [])] +
                          [("Cache-Control", "no-store")])
            elif path == "/cookies/redirect":
                self.send(302, b"moved\n", extra=[("Set-Cookie", "hop=%s; Path=/" % first("v", "1")),
                                                  ("Location", "/headers")])
            elif path.startswith("/cookies/"):
                self.send(200, ("cookie=%s\n" % (self.headers.get("Cookie") or "(none)")).encode(),
                          extra=[("Cache-Control", "no-store")])
            elif path == "/cache/maxage":
                self.send(200, ("maxage %s, answer %d\n" % (first("key"), count)).encode(),
                          extra=[("Cache-Control", "max-age=%s" % first("age", "3600"))])
            elif path == "/cache/etag":
                tag = '"v1-%s"' % first("key")
                if self.headers.get("If-None-Match") == tag:
                    with lock:
                        not_modified[self.path] = not_modified.get(self.path, 0) + 1
                    self.send(304, b"", ctype=None, extra=[("ETag", tag), ("Cache-Control", "no-cache"),
                                                           ("X-Revalidated", "yes")])
                else:
                    self.send(200, ("etag %s, answer %d\n" % (first("key"), count)).encode(),
                              extra=[("ETag", tag), ("Cache-Control", "no-cache")])
            elif path == "/cache/lastmod":
                if self.headers.get("If-Modified-Since") == LAST_MODIFIED:
                    with lock:
                        not_modified[self.path] = not_modified.get(self.path, 0) + 1
                    self.send(304, b"", ctype=None, extra=[("Last-Modified", LAST_MODIFIED),
                                                           ("Cache-Control", "max-age=0")])
                else:
                    self.send(200, ("lastmod %s, answer %d\n" % (first("key"), count)).encode(),
                              extra=[("Last-Modified", LAST_MODIFIED), ("Cache-Control", "max-age=0")])
            elif path == "/cache/nostore":
                self.send(200, ("nostore %s, answer %d\n" % (first("key"), count)).encode(),
                          extra=[("Cache-Control", "no-store")])
            elif path == "/cache/expires":
                self.send(200, ("expires %s, answer %d\n" % (first("key"), count)).encode(),
                          extra=[("Expires", self.date_time_string(time.time() + 3600))])
            elif path == "/cache/big":
                n = int(first("n", "100000"))
                self.send(200, b"x" * n, ctype="application/octet-stream",
                          extra=[("Cache-Control", "max-age=3600")])
            elif path == "/hello":
                self.send(200, b"Hello, Ferry!\n", extra=[("X-Ferry-Test", "yes")])
            elif path == "/echo":
                lines = ["method=" + self.command, "path=" + self.path]
                for name in ("Content-Type", "X-Custom", "X-Session", "X-Both", "Accept", "User-Agent"):
                    if self.headers.get(name) is not None:
                        lines.append(name.lower() + "=" + self.headers.get(name))
                lines.append("body=" + body.decode("utf-8", "replace"))
                self.send(200, ("\n".join(lines) + "\n").encode())
            elif path.startswith("/status/"):
                code = int(path[8:])
                self.send(code, ("status %d\n" % code).encode() if code not in (204, 304) else b"")
            elif path == "/redirect":
                self.send(302, b"moved\n", extra=[("Location", "/hello")])
            elif path == "/loop":
                self.send(302, b"again\n", extra=[("Location", "/loop")])
            elif path == "/slow":
                time.sleep(int(query.get("ms", ["1000"])[0]) / 1000)
                self.send(200, b"slow\n")
            elif path == "/stall":
                # half the body, then nothing for a while
                self.send_response(200)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", "10")
                self.end_headers()
                self.wfile.write(b"12345")
                self.wfile.flush()
                time.sleep(3)
                self.wfile.write(b"67890")
            elif path == "/big":
                n = int(query.get("n", ["100000"])[0])
                data = bytes(i % 251 for i in range(n))
                self.send(200, data, ctype="application/octet-stream",
                          extra=[("Content-Disposition", 'attachment; filename="big.bin"')])
            elif path == "/gzip":
                self.send(200, gzip.compress(b"squeezed and unsqueezed\n", mtime=0),
                          extra=[("Content-Encoding", "gzip")])
            elif path == "/latin1":
                self.send(200, "café\n".encode("latin-1"), ctype="text/plain; charset=ISO-8859-1")
            elif path == "/close":
                self.close_connection = True
            else:
                self.send(404, b"no such page\n")
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_HEAD = handle_any


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        pass


def main():
    server = Server(("127.0.0.1", 0), Handler)
    unused = socket.socket()
    unused.bind(("127.0.0.1", 0))
    closed = unused.getsockname()[1]
    unused.close()
    ports = "%d %d" % (server.server_address[1], closed)
    if len(sys.argv) >= 4:
        secure = Server(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(sys.argv[2], sys.argv[3])
        secure.socket = context.wrap_socket(secure.socket, server_side=True)
        threading.Thread(target=secure.serve_forever, daemon=True).start()
        ports += " %d" % secure.server_address[1]
    with open(sys.argv[1] + ".tmp", "w") as f:
        f.write(ports + "\n")
    os.rename(sys.argv[1] + ".tmp", sys.argv[1])
    server.serve_forever()


if __name__ == "__main__":
    main()
