#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""A small HTTP server on 127.0.0.1 for Ferry's URL loading tests.

    http_server.py PORTFILE

Listens on a free port of the loopback address and writes "PORT CLOSED"
to PORTFILE once it is ready, where CLOSED is a port nothing listens on
(for the "could not connect" tests). Runs until it is killed. It never
talks to anything but the programs under test."""
import gzip
import os
import http.server
import socket
import sys
import time
import urllib.parse


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
        try:
            if path == "/hello":
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
    with open(sys.argv[1] + ".tmp", "w") as f:
        f.write("%d %d\n" % (server.server_address[1], closed))
    os.rename(sys.argv[1] + ".tmp", sys.argv[1])
    server.serve_forever()


if __name__ == "__main__":
    main()
