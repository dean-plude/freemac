# SPDX-License-Identifier: GPL-3.0-or-later
"""Which Mac apps may control other apps' windows (freemac 1.215, Ferry
0.41.0).

A Mac asks the user before an app may use the Accessibility API to move
and resize other apps' windows, as window managers such as Spectacle and
ShiftIt do. Ferry asks the same way: the first time such an app asks
(AXIsProcessTrustedWithOptions with the prompt option), Ferry runs
freemac-allow-control, which shows

    Allow “Spectacle” to control other windows?

with Don't Allow and Allow, and keeps the answer here, in
~/.config/freemac/window-control.json:

    {"apps": {"com.example.Spectacle": {"name": "Spectacle", "allowed": true}}}

keyed by the app's bundle identifier (or its program's path, for a program
outside a bundle). AXIsProcessTrusted answers from this file, and an app
that was answered is never asked again. Dials > Privacy & Security >
Control Other Windows lists the apps, with a switch to turn each off or on
and a button to forget it (it is then asked again).

The answer is a choice the user makes, not a wall: every program of the
user's can reach Wayfire's IPC socket. Original freemac code.
"""
import argparse
import json
import os
import sys

FILE = "window-control.json"


def path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "freemac", FILE)


def load():
    """{app id: {"name": str, "allowed": bool}}."""
    try:
        with open(path()) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    found = data.get("apps") if isinstance(data, dict) else None
    if not isinstance(found, dict):
        return {}
    return {k: v for k, v in found.items()
            if isinstance(k, str) and isinstance(v, dict) and isinstance(v.get("allowed"), bool)}


def _save(entries):
    target = path()
    os.makedirs(os.path.dirname(target), exist_ok=True)
    temp = target + ".new"
    with open(temp, "w") as f:
        json.dump({"apps": entries}, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(temp, target)


def answer(app_id):
    """True or False once the user has answered for the app, None before."""
    entry = load().get(app_id)
    return entry["allowed"] if entry else None


def set_allowed(app_id, allowed, name=None):
    entries = load()
    entry = dict(entries.get(app_id) or {})
    entry["allowed"] = bool(allowed)
    entry["name"] = name or entry.get("name") or display_name(app_id)
    entries[app_id] = entry
    _save(entries)


def forget(app_id):
    entries = load()
    if entries.pop(app_id, None) is not None:
        _save(entries)


def apps():
    """[(app id, name, allowed)] sorted by name, for Dials."""
    rows = [(k, v.get("name") or display_name(k), v["allowed"]) for k, v in load().items()]
    return sorted(rows, key=lambda r: r[1].lower())


def display_name(app_id):
    """A name for an app id with no name kept: its last part."""
    base = app_id.rstrip("/").rsplit("/", 1)[-1]
    if "/" not in app_id and "." in base:
        base = base.rsplit(".", 1)[-1]
    return base or app_id


def question(name):
    return f"Allow “{name}” to control other windows?"


DETAIL = ("It wants to move and resize the windows of other apps and read their titles. "
          "You can change this in Dials > Privacy & Security.")


def ask(app_id, name):
    """Show the question and keep the answer. Returns it (True or False)."""
    import gi

    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk

    from . import alert, style

    style.apply()
    response = alert.ask(None, question(name), DETAIL,
                         [("Don't Allow", Gtk.ResponseType.CANCEL), ("Allow", Gtk.ResponseType.OK)],
                         default=Gtk.ResponseType.CANCEL, icon="preferences-desktop-accessibility")
    allowed = response == Gtk.ResponseType.OK
    set_allowed(app_id, allowed, name)
    return allowed


def main(argv=None):
    parser = argparse.ArgumentParser(prog="freemac-allow-control",
                                     description="Ask whether a Mac app may control other windows.")
    parser.add_argument("--app-id", required=True, help="the app's bundle identifier or program path")
    parser.add_argument("--name", help="the app's name, as the question shows it")
    parser.add_argument("--answer", choices=("allow", "deny"),
                        help="keep this answer without asking (for scripts and tests)")
    args = parser.parse_args(argv)
    name = args.name or display_name(args.app_id)
    known = answer(args.app_id)
    if known is not None:          # asked once already: Dials changes it
        return 0 if known else 1
    if args.answer:
        allowed = args.answer == "allow"
        set_allowed(args.app_id, allowed, name)
    else:
        allowed = ask(args.app_id, name)
    return 0 if allowed else 1


if __name__ == "__main__":
    sys.exit(main())
