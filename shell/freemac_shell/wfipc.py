# SPDX-License-Identifier: GPL-3.0-or-later
"""Minimal client for Wayfire's IPC socket (ipc + ipc-rules plugins).

Messages are a 4-byte little-endian length followed by a JSON object.
"""
import json
import os
import socket
import struct

from gi.repository import GLib


def socket_path():
    path = os.environ.get("WAYFIRE_SOCKET")
    if path:
        return path
    display = os.environ.get("WAYLAND_DISPLAY", "wayland-1")
    return f"/tmp/wayfire-{display}.socket"


class Connection:
    def __init__(self, path=None):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path or socket_path())

    def _read(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("Wayfire IPC socket closed")
            buf += chunk
        return buf

    def send(self, method, **data):
        raw = json.dumps({"method": method, "data": data}).encode()
        self.sock.sendall(struct.pack("<I", len(raw)) + raw)

    def receive(self):
        (length,) = struct.unpack("<I", self._read(4))
        return json.loads(self._read(length))

    def call(self, method, **data):
        self.send(method, **data)
        return self.receive()


class Wayfire:
    """Request connection plus an event connection hooked into the GLib loop."""

    def __init__(self, on_event=None):
        self.req = Connection()
        self.on_event = on_event
        if on_event:
            self.events = Connection()
            self.events.call("window-rules/events/watch")
            GLib.io_add_watch(self.events.sock.fileno(), GLib.IO_IN | GLib.IO_HUP, self._on_readable)

    def _on_readable(self, _fd, condition):
        if condition & GLib.IO_HUP:
            return False
        try:
            msg = self.events.receive()
        except (ConnectionError, ValueError):
            return False
        if self.on_event and "event" in msg:
            self.on_event(msg)
        return True

    def views(self):
        try:
            result = self.req.call("window-rules/list-views")
        except (ConnectionError, OSError, ValueError):
            return []
        views = result if isinstance(result, list) else result.get("views", [])
        return [v for v in views if is_app_window(v)]

    def focused(self):
        try:
            info = self.req.call("window-rules/get-focused-view").get("info")
        except (ConnectionError, OSError, ValueError, AttributeError):
            return None
        return info if info and is_app_window(info) else None

    def focus(self, view_id):
        return self.req.call("window-rules/focus-view", id=view_id)

    def app_menus(self, view_id):
        """Where the window's app publishes its menus on the session bus, as
        Strata's strata-shell plugin heard it from the app: a dict with
        bus-name, menubar-path, app-menu-path, window-path and
        application-path, or None (no menus, or no strata-shell)."""
        try:
            result = self.req.call("strata/app-menus", id=view_id)
        except (ConnectionError, OSError, ValueError):
            return None
        if not isinstance(result, dict) or result.get("result") != "ok" or not result.get("bus-name"):
            return None
        return result

    def minimize_hint(self, view_id, x, y, width, height, relative_to=None):
        """Where the window shrinks to when minimized (Strata's strata-shell);
        False when that isn't available."""
        data = {"id": view_id, "x": int(x), "y": int(y), "width": int(width), "height": int(height)}
        if relative_to is not None:
            data["relative-to"] = relative_to
        try:
            result = self.req.call("strata/minimize-hint", **data)
        except (ConnectionError, OSError, ValueError):
            return False
        return isinstance(result, dict) and result.get("result") == "ok"

    def own_view(self, app_id):
        """The id of a shell surface (by its app id), such as Pier's."""
        try:
            views = self.req.call("window-rules/list-views")
        except (ConnectionError, OSError, ValueError):
            return None
        for view in views if isinstance(views, list) else []:
            if view.get("app-id") == app_id:
                return view.get("id")
        return None

    def set_minimized(self, view_id, state=True):
        return self.req.call("wm-actions/set-minimized", view_id=view_id, state=state)


def is_app_window(view):
    kind = view.get("type") or view.get("role")
    return kind == "toplevel" and view.get("mapped", True)
