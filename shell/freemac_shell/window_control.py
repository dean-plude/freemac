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

From freemac 1.220 (Ferry 0.44.0) the same answer also lets an app list
other apps' windows (CGWindowListCopyWindowInfo) and press keys in them
(CGEventPost and CGEventPostToPid, through Strata's press-key), as
clipboard managers such as Flycut do to paste; CGRequestPostEventAccess
asks this same question.

From freemac 1.238 (Ferry 0.62.0) the same program asks a second
question, kept apart in ~/.config/freemac/screen-recording.json in the same
form: whether an app may record the screen and other apps' windows
(ScreenCaptureKit, CGDisplayStream, CGWindowListCreateImage), as OBS
Studio does. Ferry runs it with --kind screen-recording when an app first
asks (CGRequestScreenCaptureAccess, or SCShareableContent).

From freemac 1.241 it asks two more, each in a file of its own beside the
others: --kind microphone (microphone.json) and --kind camera (camera.json),
for AVCaptureDevice's requestAccessForMediaType:, as OBS Studio's microphone
and camera sources ask.

The answer is a choice the user makes, not a wall: every program of the
user's can reach Wayfire's IPC socket. Original freemac code.
"""
import argparse
import json
import os
import sys

FILE = "window-control.json"
# the questions this program asks, and the file each answer is kept in
KINDS = {"control": FILE, "screen-recording": "screen-recording.json",
         "microphone": "microphone.json", "camera": "camera.json"}


def path(kind="control"):
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "freemac", KINDS[kind])


def load(kind="control"):
    """{app id: {"name": str, "allowed": bool}}."""
    try:
        with open(path(kind)) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    found = data.get("apps") if isinstance(data, dict) else None
    if not isinstance(found, dict):
        return {}
    return {k: v for k, v in found.items()
            if isinstance(k, str) and isinstance(v, dict) and isinstance(v.get("allowed"), bool)}


def _save(entries, kind="control"):
    target = path(kind)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    temp = target + ".new"
    with open(temp, "w") as f:
        json.dump({"apps": entries}, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(temp, target)


def answer(app_id, kind="control"):
    """True or False once the user has answered for the app, None before."""
    entry = load(kind).get(app_id)
    return entry["allowed"] if entry else None


def set_allowed(app_id, allowed, name=None, kind="control"):
    entries = load(kind)
    entry = dict(entries.get(app_id) or {})
    entry["allowed"] = bool(allowed)
    entry["name"] = name or entry.get("name") or display_name(app_id)
    entries[app_id] = entry
    _save(entries, kind)


def forget(app_id, kind="control"):
    entries = load(kind)
    if entries.pop(app_id, None) is not None:
        _save(entries, kind)


def apps(kind="control"):
    """[(app id, name, allowed)] sorted by name, for Dials."""
    rows = [(k, v.get("name") or display_name(k), v["allowed"]) for k, v in load(kind).items()]
    return sorted(rows, key=lambda r: r[1].lower())


def display_name(app_id):
    """A name for an app id with no name kept: its last part."""
    base = app_id.rstrip("/").rsplit("/", 1)[-1]
    if "/" not in app_id and "." in base:
        base = base.rsplit(".", 1)[-1]
    return base or app_id


def question(name, kind="control"):
    if kind == "screen-recording":
        return f"Allow “{name}” to record this computer's screen?"
    if kind == "microphone":
        return f"Allow “{name}” to use the microphone?"
    if kind == "camera":
        return f"Allow “{name}” to use the camera?"
    return f"Allow “{name}” to control other windows?"


DETAIL = ("It wants to move and resize the windows of other apps, list them and read their titles, "
          "and press keys in them. You can change this in Dials > Privacy & Security.")
RECORDING_DETAIL = ("It wants to see everything on the screen and in other apps' windows, "
                    "and record it. You can change this in Dials > Privacy & Security.")
MICROPHONE_DETAIL = ("It wants to hear and record what the microphone picks up. "
                     "You can change this in Dials > Privacy & Security.")
CAMERA_DETAIL = ("It wants to see and record what the camera shows. "
                 "You can change this in Dials > Privacy & Security.")
DETAILS = {"control": (DETAIL, "preferences-desktop-accessibility"),
           "screen-recording": (RECORDING_DETAIL, "camera-video"),
           "microphone": (MICROPHONE_DETAIL, "audio-input-microphone"),
           "camera": (CAMERA_DETAIL, "camera-web")}


def ask(app_id, name, kind="control"):
    """Show the question and keep the answer. Returns it (True or False)."""
    import gi

    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk

    from . import alert, style

    style.apply()
    detail, icon = DETAILS[kind]
    response = alert.ask(None, question(name, kind), detail,
                         [("Don't Allow", Gtk.ResponseType.CANCEL), ("Allow", Gtk.ResponseType.OK)],
                         default=Gtk.ResponseType.CANCEL, icon=icon)
    allowed = response == Gtk.ResponseType.OK
    set_allowed(app_id, allowed, name, kind)
    return allowed


def main(argv=None):
    parser = argparse.ArgumentParser(prog="freemac-allow-control",
                                     description="Ask whether a Mac app may control other windows.")
    parser.add_argument("--app-id", required=True, help="the app's bundle identifier or program path")
    parser.add_argument("--name", help="the app's name, as the question shows it")
    parser.add_argument("--answer", choices=("allow", "deny"),
                        help="keep this answer without asking (for scripts and tests)")
    parser.add_argument("--kind", choices=sorted(KINDS), default="control",
                        help="what is asked: controlling other windows (the default), recording the screen, "
                             "or using the microphone or camera")
    args = parser.parse_args(argv)
    name = args.name or display_name(args.app_id)
    known = answer(args.app_id, args.kind)
    if known is not None:          # asked once already: Dials changes it
        return 0 if known else 1
    if args.answer:
        allowed = args.answer == "allow"
        set_allowed(args.app_id, allowed, name, args.kind)
    else:
        allowed = ask(args.app_id, name) if args.kind == "control" else ask(args.app_id, name, args.kind)
    return 0 if allowed else 1


if __name__ == "__main__":
    sys.exit(main())
