# SPDX-License-Identifier: GPL-3.0-or-later
"""Speak selection, as on a Mac: select some words in any app and press
Option-Escape, and the computer reads them out loud. Press it again to stop.

    freemac-speak            read the selected words, or stop reading
    freemac-speak --stop     stop reading
    freemac-speak "words"    read these words (Dials' Play button)

It is on when Dials > Accessibility > Speak selection is. The words come from
the selection (Wayland's primary selection), which every app keeps up to
date as you select; the voice is eSpeak NG's. Original freemac code.
"""
import json
import os
import signal
import subprocess
import sys
import threading

PROGRAM = "freemac-speak"
PREFS = os.path.expanduser("~/.config/freemac/shell.json")
PIDFILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "freemac-speak.pid")
ESPEAK = "/usr/bin/espeak-ng"
# Words per minute: Dials' Speaking rate slider goes from SLOW to FAST.
SLOW, NORMAL, FAST = 100, 175, 330
LIMIT = 20000          # characters read at a time; a whole book would never end
# The voices offered in Dials: eSpeak NG's names for them.
VOICES = (("en-us", "American English"), ("en-gb", "British English"), ("en-gb-scotland", "Scottish English"),
          ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"), ("pt-br", "Portuguese (Brazil)"),
          ("nl", "Dutch"), ("pl", "Polish"), ("hi", "Hindi"), ("cmn", "Chinese (Mandarin)"))


def prefs():
    try:
        with open(PREFS) as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    return data if isinstance(data, dict) else {}


def enabled():
    return bool(prefs().get("speak_selection"))


def available():
    return os.access(ESPEAK, os.X_OK)


def rate():
    try:
        value = int(prefs().get("speak_rate", NORMAL))
    except (TypeError, ValueError):
        value = NORMAL
    return max(SLOW, min(FAST, value))


def voice():
    value = prefs().get("speak_voice")
    return value if value in dict(VOICES) else "en-us"


def _speaking_pid():
    """The process reading out loud now, or None."""
    try:
        with open(PIDFILE) as f:
            pid = int(f.read().strip())
    except (OSError, ValueError):
        return None
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            if os.path.basename(f.read().split(b"\0")[0]) != b"espeak-ng":
                return None
    except OSError:
        return None
    return pid


def stop():
    """Stop reading. True if something was being read."""
    pid = _speaking_pid()
    try:
        os.remove(PIDFILE)
    except OSError:
        pass
    if pid is None:
        return False
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return False
    return True


def selected_text():
    """The words selected in the app in front, or ""."""
    for argv in (["wl-paste", "--primary", "--no-newline", "--type", "text/plain;charset=utf-8"],
                 ["wl-paste", "--primary", "--no-newline"]):
        try:
            found = subprocess.run(argv, capture_output=True, timeout=2)
        except (OSError, subprocess.SubprocessError):
            return ""
        if found.returncode == 0:
            return found.stdout.decode("utf-8", "replace").strip()
    return ""


def say(text):
    """Start reading text out loud in the background, after stopping any
    reading already going. Returns the process, or None."""
    stop()
    text = " ".join(text.split())[:LIMIT]
    if not text or not available():
        return None
    process = subprocess.Popen([ESPEAK, "-s", str(rate()), "-v", voice(), "--stdin"],
                               stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    try:
        with open(PIDFILE, "w") as f:
            f.write(str(process.pid))
    except OSError:
        pass
    process.stdin.write(text.encode("utf-8"))
    process.stdin.close()
    # Reap it when it's done, so a long-running caller such as Dials isn't
    # left with a finished reader hanging about.
    threading.Thread(target=process.wait, daemon=True).start()
    return process


def _tell(title, body):
    try:
        subprocess.Popen(["notify-send", "--app-name=Speech", "--icon=audio-speakers-symbolic", title, body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if args[:1] == ["--stop"]:
        stop()
        return 0
    if args:
        process = say(" ".join(args))
        return 0 if process is not None else 1
    if not enabled():
        return 0
    if stop():                      # the key again while reading: stop
        return 0
    if not available():
        _tell("Speech isn't installed", "Install espeak-ng in Harbor to have the computer read out loud.")
        return 1
    text = selected_text()
    if not text:
        _tell("Nothing is selected", "Select some words, then press ⌥Esc to hear them.")
        return 1
    process = say(text)
    return 0 if process is not None else 1


if __name__ == "__main__":
    sys.exit(main())
