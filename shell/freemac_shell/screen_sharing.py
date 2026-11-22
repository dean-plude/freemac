# SPDX-License-Identifier: GPL-3.0-or-later
"""Screen Sharing, as on a Mac (Dials > Sharing): someone at another computer
on the same network can see this screen and use it, after signing in with the
name and password of the person logged in here. Handy for helping someone
from the next room.

wayvnc does the sharing, speaking the standard VNC protocol, always encrypted
(TLS, or RSA-AES for viewers that prefer it), and checking the password
through PAM (/etc/pam.d/wayvnc, which never accepts an empty one). It runs
inside the person's own session, so it shows exactly their screen and stops
when they log out. The firewall opening for it, and the switch itself, ask
for an administrator's password (freemac-system-helper screen-sharing).

    freemac-screen-sharing --serve   start sharing if it's on (at log in)
    freemac-screen-sharing --on      turn it on now (after the helper)
    freemac-screen-sharing --off     turn it off now

Topline shows who is connected and can disconnect them. Original freemac
code."""
import json
import os
import shutil
import socket
import subprocess
import sys
import time

from gi.repository import GLib

DIR = os.path.join(GLib.get_user_config_dir(), "freemac", "screen-sharing")
CONFIG = os.path.join(DIR, "config")
ON = os.path.join(DIR, "on")
PORT = 5900
PROGRAM = "freemac-screen-sharing"


def socket_path():
    return os.path.join(GLib.get_user_runtime_dir(), "freemac-screen-sharing.sock")


def available():
    return shutil.which("wayvnc") is not None and shutil.which("openssl") is not None


def enabled():
    return os.path.exists(ON)


def running():
    """Whether wayvnc is sharing now: its control socket answers (one left
    behind by a crash doesn't)."""
    path = socket_path()
    if not os.path.exists(path):
        return False
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        probe.settimeout(1)
        probe.connect(path)
        return True
    except OSError:
        return False
    finally:
        probe.close()


def _openssl(*args):
    subprocess.run(["openssl", *args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def ensure_keys():
    """This computer's own certificate and keys, made the first time. The
    certificate names the computer, so a viewer can tell it's the same one
    next time."""
    os.makedirs(DIR, mode=0o700, exist_ok=True)
    os.chmod(DIR, 0o700)
    cert, key, rsa = (os.path.join(DIR, name) for name in ("tls_cert.pem", "tls_key.pem", "rsa_key.pem"))
    host = socket.gethostname() or "freemac"
    if not (os.path.exists(cert) and os.path.exists(key)):
        _openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                 "-days", "3650", "-subj", f"/CN={host}",
                 "-addext", f"subjectAltName=DNS:{host},DNS:{host}.local")
    if not os.path.exists(rsa):
        try:
            _openssl("genrsa", "-traditional", "-out", rsa, "2048")
        except subprocess.CalledProcessError:
            _openssl("genrsa", "-out", rsa, "2048")
    for path in (key, rsa):
        os.chmod(path, 0o600)
    with open(CONFIG, "w", encoding="utf-8") as f:
        f.write("# freemac: Dials > Sharing > Screen Sharing\n"
                f"address=0.0.0.0\nport={PORT}\n"
                "enable_auth=true\nenable_pam=true\n"
                f"private_key_file={key}\ncertificate_file={cert}\nrsa_private_key_file={rsa}\n")


def serve():
    """Share the screen if Screen Sharing is on; returns when wayvnc ends."""
    if not enabled() or not available() or running():
        return 0
    try:
        ensure_keys()
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"{PROGRAM}: couldn't make the keys: {error}", file=sys.stderr)
        return 1
    # Keep sharing while it's on: if wayvnc ever stops by itself (a crash),
    # start it again, but give up if it keeps failing.
    failures = []
    while enabled():
        try:
            os.unlink(socket_path())
        except OSError:
            pass
        started = time.monotonic()
        try:
            code = subprocess.call(["wayvnc", "-C", CONFIG, "-S", socket_path()])
        except OSError:
            return 1
        if code == 0 or not enabled():
            return 0               # turned off (wayvnc-exit), or the session ended
        failures = [t for t in failures if started - t < 60] + [started]
        if len(failures) >= 5:
            print(f"{PROGRAM}: wayvnc keeps stopping; giving up", file=sys.stderr)
            return 1
        time.sleep(2)
    return 0


def _ctl(*args):
    try:
        out = subprocess.run(["wayvncctl", "-S", socket_path(), "--json", *args], capture_output=True,
                             text=True, timeout=3)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return out.stdout if out.returncode == 0 else None


class Watcher:
    """Calls changed(viewers) as computers start and stop looking at this
    screen; viewers is [{id, username, address}]. It listens to wayvnc's own
    events rather than asking for its list now and then: asking while a viewer
    is still connecting crashes wayvnc 0.7. Keep a reference to it."""

    EVERY = 2   # seconds between checks that sharing has started

    def __init__(self, changed):
        self.changed = changed
        self.viewers = {}
        self.process = None
        GLib.timeout_add_seconds(self.EVERY, self._check)
        self._check()

    def _check(self):
        if self.process is None and running():
            self._listen()
        return True

    def _listen(self):
        from gi.repository import Gio

        try:
            self.process = Gio.Subprocess.new(
                ["wayvncctl", "-S", socket_path(), "--json", "event-receive"],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE)
        except GLib.Error:
            self.process = None
            return
        stream = Gio.DataInputStream.new(self.process.get_stdout_pipe())
        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self._line, self.process)

    def _line(self, stream, result, process):
        try:
            line, _length = stream.read_line_finish_utf8(result)
        except GLib.Error:
            line = None
        if process is not self.process:
            return
        if line is None:                      # wayvnc stopped
            self.process = None
            self._set({})
            return
        try:
            event = json.loads(line)
        except ValueError:
            event = {}
        method = event.get("method") if isinstance(event, dict) else None
        params = event.get("params") or {} if isinstance(event, dict) else {}
        viewers = dict(self.viewers)
        if method == "client-connected" and isinstance(params, dict):
            viewers[str(params.get("id"))] = params
        elif method == "client-disconnected" and isinstance(params, dict):
            viewers.pop(str(params.get("id")), None)
        elif method in ("wayvnc-shutdown", "wayvnc-startup"):
            viewers = {}
        self._set(viewers)
        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self._line, process)

    def _set(self, viewers):
        if viewers.keys() != self.viewers.keys():
            self.viewers = viewers
            self.changed(list(viewers.values()))
        else:
            self.viewers = viewers


def disconnect(client_id):
    _ctl("client-disconnect", str(client_id))


def turn_on():
    os.makedirs(DIR, mode=0o700, exist_ok=True)
    open(ON, "w").close()
    if not running():
        subprocess.Popen([PROGRAM, "--serve"], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def turn_off():
    try:
        os.unlink(ON)
    except OSError:
        pass
    if running():
        _ctl("wayvnc-exit")


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv == ["--serve"]:
        return serve()
    if argv == ["--on"]:
        turn_on()
        return 0
    if argv == ["--off"]:
        turn_off()
        return 0
    print(__doc__.split("\n\n")[2], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
