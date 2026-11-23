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
    # freemac-session puts it in the person's runtime folder (1.138); older
    # sessions, and plain Wayfire, use /tmp.
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime and os.path.exists(os.path.join(runtime, "wayfire.socket")):
        return os.path.join(runtime, "wayfire.socket")
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
        return [v for v in _owned(views, views) if is_app_window(v)]

    def held_modifiers(self):
        """{command, alt, control, shift}: the modifier keys held down now
        (Strata's answer), or None when Strata can't say."""
        try:
            reply = self.req.call("strata/held-modifiers")
        except (ConnectionError, OSError, ValueError):
            return None
        held = reply.get("held") if isinstance(reply, dict) else None
        return held if isinstance(held, dict) else None

    def focused(self):
        try:
            info = self.req.call("window-rules/get-focused-view").get("info")
        except (ConnectionError, OSError, ValueError, AttributeError):
            return None
        if info:
            # The focused-view answer has no parent; the full list does.
            try:
                every = self.req.call("window-rules/list-views")
            except (ConnectionError, OSError, ValueError):
                every = []
            every = every if isinstance(every, list) else []
            mine = next((v for v in every if v.get("id") == info.get("id")), None)
            if mine and "parent" in mine:
                info = _owned([dict(info, parent=mine["parent"])], every)[0]
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

    def desktops(self):
        """Strata's strata/desktops for the active output (grid, current,
        windows), or None."""
        try:
            result = self.req.call("strata/desktops")
        except (ConnectionError, OSError, ValueError):
            return None
        return result if isinstance(result, dict) and "grid" in result else None

    def app_expose(self, app_id):
        """App Exposé: every window of the app, side by side (Strata)."""
        try:
            return self.req.call("strata/app-expose", **{"app-id": app_id}).get("result") == "ok"
        except (ConnectionError, OSError, ValueError, AttributeError):
            return False

    def assignments(self):
        """{app-id: "all" or a desktop index} for apps assigned to desktops."""
        try:
            result = self.req.call("strata/assignments")
        except (ConnectionError, OSError, ValueError):
            return {}
        apps = result.get("apps") if isinstance(result, dict) else None
        return apps if isinstance(apps, dict) else {}

    def assign(self, app_id, to):
        """Assign an app to "all" desktops, one desktop (an index) or "none"."""
        try:
            return self.req.call("strata/assign", **{"app-id": app_id, "to": to}).get("result") == "ok"
        except (ConnectionError, OSError, ValueError, AttributeError):
            return False

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

    def close(self, view_id):
        """Ask a window to close, as its close button does (Strata)."""
        try:
            result = self.req.call("strata/close", id=view_id)
        except (ConnectionError, OSError, ValueError):
            return False
        return isinstance(result, dict) and result.get("result") == "ok"

    def press(self, key, ctrl=False, shift=False, alt=False):
        """Press a key (an evdev code) in the window that has the keyboard."""
        try:
            result = self.req.call("strata/press", key=key, ctrl=ctrl, shift=shift, alt=alt)
        except (ConnectionError, OSError, ValueError):
            return False
        return isinstance(result, dict) and result.get("result") == "ok"

    def front_app(self, app_id, keys=None):
        """Tell Strata which app is in front with no window open ("" for
        none), so ⌘Q quits it; with keys ({"command+n": "new-note"}), the
        shortcuts that still work while it has no window."""
        data = {"app-id": app_id or ""}
        if keys is not None:
            data["keys"] = keys
        try:
            self.req.call("strata/front-app", **data)
        except (ConnectionError, OSError, ValueError):
            pass

    def front_app_now(self):
        """The app Strata keeps in front with no window open, or ""."""
        try:
            reply = self.req.call("strata/front-app")
        except (ConnectionError, OSError, ValueError):
            return ""
        return (reply.get("app-id") or "") if isinstance(reply, dict) else ""

    def quit(self, app_id):
        """Close every window of an app: Quit in the menu bar and the dock."""
        closed = False
        for view in self.views():
            if (view.get("app-id") or "") == app_id:
                closed = self.close(view["id"]) or closed
        return closed

    def force_quit(self, view_id):
        """End the program behind a window at once (Strata's strata/force-quit)."""
        try:
            return self.req.call("strata/force-quit", id=view_id)
        except (ConnectionError, OSError, ValueError):
            return None

    def view_pids(self):
        """{window id: process id} from Strata, or None where it can't say."""
        try:
            reply = self.req.call("strata/view-pids")
        except (ConnectionError, OSError, ValueError):
            return None
        if not isinstance(reply, dict) or not isinstance(reply.get("views"), list):
            return None
        return {v["id"]: v["pid"] for v in reply["views"] if isinstance(v, dict) and "id" in v and "pid" in v}

    def outputs(self):
        try:
            result = self.req.call("window-rules/list-outputs")
        except (ConnectionError, OSError, ValueError):
            return []
        return result if isinstance(result, list) else []

    def move_to(self, view_id, x, y, width, height):
        """Put a window at this place and size (Window > Center)."""
        try:
            return self.req.call("window-rules/configure-view", id=view_id,
                                 geometry={"x": int(x), "y": int(y), "width": int(width), "height": int(height)})
        except (ConnectionError, OSError, ValueError):
            return None

    def zoom(self, view_id):
        try:
            return self.req.call("strata/zoom", id=view_id)
        except (ConnectionError, OSError, ValueError):
            return None

    def set_minimized(self, view_id, state=True):
        return self.req.call("wm-actions/set-minimized", view_id=view_id, state=state)

    def hide(self, view_id):
        """Hide a window, as Hide in the app menu does (Strata): it goes away
        without shrinking into the Dock or getting a picture there, which is
        for minimized windows. Falls back to minimizing without Strata."""
        try:
            result = self.req.call("strata/hide", id=view_id)
        except (ConnectionError, OSError, ValueError):
            result = None
        if not isinstance(result, dict) or result.get("result") != "ok":
            return self.set_minimized(view_id, True)
        return result

    def hidden(self):
        """The ids of the windows hidden now (Strata), as a set."""
        try:
            result = self.req.call("strata/hidden")
        except (ConnectionError, OSError, ValueError):
            return set()
        if not isinstance(result, dict) or result.get("result") != "ok":
            return set()
        return {i for i in result.get("ids") or [] if isinstance(i, int)}

    def snapshot(self, view_id, path, size=256):
        """Draw a small picture of a window into path, a file in the Dock's own
        folder (snapshot_dir()); (width, height) or None."""
        try:
            result = self.req.call("strata/snapshot", id=view_id, path=path, size=int(size))
        except (ConnectionError, OSError, ValueError):
            return None
        if not isinstance(result, dict) or result.get("result") != "ok":
            return None
        return result.get("width"), result.get("height")


def snapshot_dir():
    """Where Strata may draw pictures of minimized windows for the Dock."""
    path = os.path.join(GLib.get_user_runtime_dir(), "freemac-pier")
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def is_minimized(view):
    return bool((view.get("state") or {}).get("minimized", view.get("minimized", False)))


def is_app_window(view):
    kind = view.get("type") or view.get("role")
    return kind == "toplevel" and view.get("mapped", True)


def _owned(views, every):
    """A dialog belongs to the app whose window opened it, as on a Mac: the
    browser's Preferences window (app id "epiphany") counts as the browser
    ("org.gnome.Epiphany"), so the menu bar and the Dock say the same app.
    Its own id is kept as "own-app-id"."""
    by_id = {v.get("id"): v for v in every}
    out = []
    for view in views:
        top, seen = view, set()
        while (top.get("parent") or -1) in by_id and top["id"] not in seen:
            seen.add(top["id"])
            top = by_id[top["parent"]]
        if top is not view and top.get("app-id") and top.get("app-id") != view.get("app-id"):
            view = dict(view, **{"own-app-id": view.get("app-id"), "app-id": top.get("app-id")})
        out.append(view)
    return out
