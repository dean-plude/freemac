#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""A stand-in for Wayfire's IPC socket, with freemac's Strata loaded, for
Ferry's hotkey and Accessibility tests (freemac 1.215, Ferry 0.41.0).

    fake_wayfire.py SOCKET LOG [--no-strata]

It listens on SOCKET and answers as Wayfire does (a 4-byte little-endian
length, then JSON {"method": ..., "data": ...}), from two displays and a
few windows of its own:

  window-rules/list-outputs, list-views, view-info, get-focused-view,
  configure-view, focus-view; wm-actions/set-minimized, set-fullscreen;
  strata/view-pids; strata/hotkeys/register, unregister, clear (checked as
  Strata checks them: the app's own socket in $XDG_RUNTIME_DIR/ferry/, a
  modifier, at most 100 each, no combination twice)

and two calls for the test itself:

  fake/press {"key": EVDEV, "modifiers": [...]}  as if the user pressed it:
      the matching hotkey's datagram is sent ({"sent": true}), or nothing
  fake/log                                       {"log": [the calls that changed something]}

Each call that changes something is also written to LOG, one line each.
With --no-strata, Strata's calls answer "No such method found!", as a
Wayfire without Strata does.
"""
import json
import os
import socket
import stat
import struct
import sys
import threading

OUTPUTS = [
    {"id": 1, "name": "DP-1", "geometry": {"x": 0, "y": 0, "width": 1920, "height": 1080},
     "workarea": {"x": 0, "y": 0, "width": 1920, "height": 1080}},
    {"id": 2, "name": "eDP-1", "geometry": {"x": 1920, "y": 0, "width": 1280, "height": 800},
     "workarea": {"x": 0, "y": 28, "width": 1280, "height": 772}},
]


def view(vid, app_id, title, output, geometry, focus, kind="toplevel", parent=-1):
    return {"id": vid, "app-id": app_id, "title": title, "output-id": output, "type": kind,
            "role": kind, "mapped": True, "geometry": geometry, "last-focus-timestamp": focus,
            "minimized": False, "fullscreen": False, "parent": parent}


VIEWS = [
    view(10, "org.example.Editor", "Notes", 2, {"x": 100, "y": 60, "width": 600, "height": 400}, 300),
    view(11, "org.example.Editor", "Other notes", 1, {"x": 50, "y": 50, "width": 500, "height": 300}, 100),
    view(12, "org.example.Browser", "Web", 1, {"x": 0, "y": 0, "width": 1920, "height": 1080}, 200),
    view(13, "org.example.Editor", "Save changes?", 2, {"x": 200, "y": 100, "width": 300, "height": 120}, 50,
         parent=10),
    view(20, "strata-panel", "", 2, {"x": 0, "y": 0, "width": 1280, "height": 28}, 0, kind="background"),
]
PIDS = {10: 4242, 11: 4242, 12: 5151, 13: 4242}
MODS = ("command", "option", "control", "shift")


class Fake:
    def __init__(self, log_path, strata):
        self.lock = threading.Lock()
        self.log_path = log_path
        self.strata = strata
        self.log = []
        self.views = {v["id"]: v for v in VIEWS}
        self.focused = 10
        self.hotkeys = {}
        self.next_id = 1
        self.sender = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)

    def note(self, line):
        self.log.append(line)
        with open(self.log_path, "a") as f:
            f.write(line + "\n")

    def call(self, method, data):
        with self.lock:
            return self._call(method, data or {})

    def _call(self, method, data):
        if method == "window-rules/list-outputs":
            return OUTPUTS
        if method == "window-rules/list-views":
            return list(self.views.values())
        if method == "window-rules/view-info":
            v = self.views.get(data.get("id"))
            return {"result": "ok", "info": v} if v else {"error": "no such view"}
        if method == "window-rules/get-focused-view":
            return {"result": "ok", "info": self.views.get(self.focused)}
        if method == "window-rules/configure-view":
            v = self.views.get(data.get("id"))
            if not v:
                return {"error": "no such view"}
            g = data.get("geometry")
            if g:
                v["geometry"] = {k: int(g[k]) for k in ("x", "y", "width", "height")}
            line = "configure-view %d %d,%d %dx%d" % (v["id"], g["x"], g["y"], g["width"], g["height"])
            if "output_id" in data:
                v["output-id"] = data["output_id"]
                line += " output %d" % data["output_id"]
            self.note(line)
            return {"result": "ok"}
        if method == "window-rules/focus-view":
            if data.get("id") not in self.views:
                return {"error": "no such view"}
            self.focused = data["id"]
            self.note("focus-view %d" % self.focused)
            return {"result": "ok"}
        if method in ("wm-actions/set-minimized", "wm-actions/set-fullscreen"):
            v = self.views.get(data.get("view_id"))
            if not v:
                return {"error": "no such view"}
            what = method.split("-", 2)[-1]
            v[what] = bool(data.get("state"))
            self.note("set-%s %d %s" % (what, v["id"], str(v[what]).lower()))
            return {"result": "ok"}
        if method == "fake/log":
            return {"result": "ok", "log": self.log}
        if method == "fake/press":
            return self.press(data)
        if method.startswith("strata/") and self.strata:
            if method == "strata/view-pids":
                return {"result": "ok", "views": [{"id": k, "pid": p} for k, p in PIDS.items()]}
            if method == "strata/hotkeys/register":
                return self.register(data)
            if method == "strata/hotkeys/unregister":
                if self.hotkeys.pop(data.get("id"), None) is None:
                    return {"error": "no such hotkey"}
                self.note("unregister %d" % data["id"])
                return {"result": "ok"}
            if method == "strata/hotkeys/clear":
                for k in [k for k, h in self.hotkeys.items() if h["socket"] == data.get("socket")]:
                    del self.hotkeys[k]
                return {"result": "ok"}
        return {"error": "No such method found!"}

    @staticmethod
    def allowed_socket(path):
        runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        folder = os.path.join(runtime, "ferry") + "/"
        if not runtime or not path.startswith(folder) or "/" in path[len(folder):]:
            return False
        if not os.path.basename(path).startswith("hotkeys-"):
            return False
        try:
            st = os.lstat(path)
        except OSError:
            return False
        return stat.S_ISSOCK(st.st_mode) and st.st_uid == os.getuid()

    def register(self, data):
        key, path, tag = data.get("key"), data.get("socket"), data.get("tag")
        if not isinstance(key, int) or not isinstance(path, str) or not isinstance(tag, int):
            return {"error": "Missing or wrong json type"}
        if not 0 < key <= 0x2ff:
            return {"error": "no such key"}
        if not self.allowed_socket(path):
            return {"error": "not an app's hotkey socket"}
        mods = data.get("modifiers", [])
        if any(m not in MODS for m in mods):
            return {"error": "no such modifier"}
        function_key = 59 <= key <= 68 or key in (87, 88) or 183 <= key <= 194
        if not set(mods) & {"command", "option", "control"} and not function_key:
            return {"error": "a hotkey needs Command, Option or Control"}
        combo = (key, frozenset(mods))
        if any(h["combo"] == combo for h in self.hotkeys.values()):
            return {"error": "taken"}
        if sum(h["socket"] == path for h in self.hotkeys.values()) >= 100:
            return {"error": "too many hotkeys"}
        hid = self.next_id
        self.next_id += 1
        self.hotkeys[hid] = {"combo": combo, "socket": path, "tag": tag}
        self.note("register %d key %d %s" % (hid, key, "+".join(m for m in MODS if m in mods) or "-"))
        return {"result": "ok", "id": hid}

    def press(self, data):
        combo = (data.get("key"), frozenset(data.get("modifiers", [])))
        for hid, h in self.hotkeys.items():
            if h["combo"] == combo:
                msg = json.dumps({"event": "hotkey", "tag": h["tag"], "id": hid}).encode()
                try:
                    self.sender.sendto(msg, h["socket"])
                except OSError:
                    return {"result": "ok", "sent": False}
                return {"result": "ok", "sent": True}
        return {"result": "ok", "sent": False}


def read_exact(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return buf


def serve(conn, fake):
    with conn:
        while True:
            head = read_exact(conn, 4)
            if head is None:
                return
            body = read_exact(conn, struct.unpack("<I", head)[0])
            if body is None:
                return
            try:
                req = json.loads(body)
                reply = fake.call(req.get("method", ""), req.get("data"))
            except ValueError:
                reply = {"error": "bad json"}
            out = json.dumps(reply).encode()
            conn.sendall(struct.pack("<I", len(out)) + out)


def main():
    path, log_path = sys.argv[1], sys.argv[2]
    fake = Fake(log_path, "--no-strata" not in sys.argv[3:])
    open(log_path, "w").close()
    try:
        os.unlink(path)
    except OSError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(8)
    while True:
        conn, _ = server.accept()
        threading.Thread(target=serve, args=(conn, fake), daemon=True).start()


if __name__ == "__main__":
    main()
