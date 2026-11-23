# SPDX-License-Identifier: GPL-3.0-or-later
"""Fast user switching, as on a Mac: someone else logs in while your apps
keep running, and you come back to them later just as you left them.

Each person's session runs on its own virtual terminal: the first on 7,
others on 8 to 12, each started by its own login screen (greetd with Gangway,
freemac-greeter@N.service). Switching locks the session you leave and shows
the other terminal (freemac-switch-to@N.service); polkit lets the person at
the computer and the login screen start both
(build/overlay/usr/libexec/freemac-switch-helper does the root part).

Topline's user menu and Gangway use this; it needs no GTK. Original freemac
code.
"""
import json
import os
import pwd
import subprocess

FIRST, LAST = 8, 12
# Who was picked in the user menu, for the login screen to show first: one
# small file per person in /tmp (only its owner can replace it).
CHOICE = "/tmp/freemac-switch-choice-{uid}"


def accounts():
    """Accounts that can log in, as pwd entries, the oldest first."""
    found = [e for e in pwd.getpwall()
             if 1000 <= e.pw_uid < 60000 and not e.pw_shell.endswith(("nologin", "false"))]
    return sorted(found, key=lambda e: e.pw_uid)


def full_name(entry):
    return entry.pw_gecos.split(",")[0] or entry.pw_name


def _run(*command, timeout=10):
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None


def sessions():
    """{user name: VT} for the graphical sessions on this computer's screen.
    The login screens (greetd's own user) are left out."""
    out = _run("loginctl", "list-sessions", "--no-legend", "--no-pager", "-o", "json")
    try:
        rows = json.loads(out.stdout) if out and out.returncode == 0 else []
    except ValueError:
        rows = []
    found = {}
    for row in rows if isinstance(rows, list) else []:
        sid, user = str(row.get("session", "")), row.get("user") or ""
        if not sid or not user or user == "_greetd" or row.get("seat") != "seat0":
            continue
        props = _run("loginctl", "show-session", sid, "-p", "VTNr", "-p", "Type", "-p", "State",
                     "-p", "Class")
        if not props or props.returncode != 0:
            continue
        values = dict(line.split("=", 1) for line in props.stdout.splitlines() if "=" in line)
        if values.get("Class") != "user" or values.get("State") == "closing":
            continue
        if values.get("Type") not in ("wayland", "x11", "tty") or not values.get("VTNr", "0").isdigit():
            continue
        vt = int(values["VTNr"])
        if vt >= 7:
            found.setdefault(user, vt)
    return found


def greeters():
    """VTs where an extra login screen is running."""
    out = _run("systemctl", "list-units", "--no-legend", "--plain", "--state=active",
               "freemac-greeter@*.service")
    found = []
    for line in (out.stdout.splitlines() if out and out.returncode == 0 else []):
        unit = line.split()[0] if line.split() else ""
        number = unit[len("freemac-greeter@"):-len(".service")]
        if unit.startswith("freemac-greeter@") and number.isdigit():
            found.append(int(number))
    return sorted(found)


def free_terminal(taken):
    for vt in range(FIRST, LAST + 1):
        if vt not in taken:
            return vt
    return None


def _start(unit):
    out = _run("systemctl", "start", "--no-ask-password", unit, timeout=30)
    return bool(out and out.returncode == 0)


def show(vt):
    return _start(f"freemac-switch-to@{vt}.service")


def lock_first():
    """Lock this session before leaving it (freemac-lock returns once the
    lock is up)."""
    _run("freemac-lock", timeout=20)


def _remember_choice(name):
    path = CHOICE.format(uid=os.getuid())
    try:
        with open(path + ".tmp", "w") as f:
            f.write(name)
        os.chmod(path + ".tmp", 0o644)
        os.replace(path + ".tmp", path)
    except OSError:
        pass


def latest_choice(newer_than=0, within=120):
    """(when, name) of the latest pick from anyone's user menu in the last
    two minutes, newer than newer_than, or None."""
    import glob
    import time
    best = None
    for path in glob.glob(CHOICE.format(uid="*")):
        try:
            when = os.stat(path).st_mtime
            if when <= newer_than or when < time.time() - within:
                continue
            with open(path) as f:
                name = f.read(64).strip()
        except OSError:
            continue
        if name and (best is None or when > best[0]):
            best = (when, name)
    return best


def to_user(name, lock=True):
    """Switch to name's session if they're logged in, else to a login screen
    with them chosen. Returns False when nothing could be shown."""
    running = sessions()
    if name in running:
        if lock:
            lock_first()
        return show(running[name])
    _remember_choice(name)
    return login_window(lock=lock)


def login_window(lock=True):
    """Show a login screen: one already open on another terminal, else a
    new one on the first free terminal."""
    open_ones = greeters()
    if lock:
        lock_first()
    if open_ones:
        return show(open_ones[0])
    vt = free_terminal(set(sessions().values()) | {7})
    return vt is not None and _start(f"freemac-greeter@{vt}.service")


def available():
    """Whether switching can work here: the helper and its services are
    installed and more than one account can log in."""
    return (os.path.exists("/usr/libexec/freemac-switch-helper")
            and os.path.exists("/etc/systemd/system/freemac-greeter@.service")
            and len(accounts()) > 1)
