# SPDX-License-Identifier: GPL-3.0-or-later
"""Which apps are using significant energy, for the Battery menu.

Like a Mac's "Using Significant Energy", this counts the processor time each
app with a window has used since the last look: the app's own processes and
every process they started (a browser's tabs, say), read from /proc. Wayfire
doesn't say which process a window belongs to, so an app's processes are
found by their program's name: the window's app id, or the program its
.desktop file runs.
"""
import os

SHELL_APPS = {"freemac-pier", "freemac-topline", "freemac-backdrop", "freemac-force-quit", "freemac-power"}
SIGNIFICANT = 15.0      # percent of one processor core, on average since the last look
PROC = "/proc"
INTERPRETERS = ("python", "perl", "ruby", "node", "bash", "sh", "env", "gjs")


def names_of(cmdline, comm=""):
    """The program names a process goes by: its own, and for a script, the
    script's ("/usr/bin/python3 /usr/bin/freemac-easel" is freemac-easel)."""
    args = [a for a in cmdline.split("\0") if a]
    names = {comm.strip().lower()} if comm.strip() else set()
    if args:
        first = os.path.basename(args[0]).lower()
        names.add(first)
        if first.startswith(INTERPRETERS):
            script = next((a for a in args[1:] if not a.startswith("-")), None)
            if script:
                names.add(os.path.basename(script).lower())
    return names


def processes(proc=PROC):
    """{pid: (parent pid, processor ticks used, program names)} for this
    person's processes."""
    me = os.getuid()
    found = {}
    try:
        entries = os.listdir(proc)
    except OSError:
        return found
    for entry in entries:
        if not entry.isdigit():
            continue
        path = os.path.join(proc, entry)
        try:
            if os.stat(path).st_uid != me:
                continue
            with open(os.path.join(path, "stat")) as f:
                text = f.read()
            with open(os.path.join(path, "cmdline")) as f:
                cmdline = f.read()
        except OSError:
            continue
        # The name in brackets may hold spaces or brackets of its own.
        comm = text[text.find("(") + 1:text.rfind(")")]
        rest = text[text.rfind(")") + 2:].split()
        try:
            parent, ticks = int(rest[1]), int(rest[11]) + int(rest[12])
        except (IndexError, ValueError):
            continue
        found[int(entry)] = (parent, ticks, names_of(cmdline, comm))
    return found


def app_ticks(procs, app_ids, programs=None):
    """{app id: ticks}, adding up each app's processes and their descendants;
    one process is counted once. programs(app id) gives more names its
    program may go by (from its .desktop file)."""
    children = {}
    for pid, (parent, *_rest) in procs.items():
        children.setdefault(parent, []).append(pid)
    owner = {}            # pid: the app whose program it is
    for app_id in app_ids:
        if not app_id or app_id.lower() in SHELL_APPS:
            continue
        wanted = {app_id.lower(), app_id.split(".")[-1].lower()}
        wanted.update(n.lower() for n in (programs(app_id) if programs else ()) if n)
        for pid, (_parent, _ticks, names) in procs.items():
            if names & wanted:
                owner.setdefault(pid, app_id)
    totals, counted = {}, set()
    for pid, app_id in owner.items():
        # An app opened from another (from Drawer, say) is a child process of
        # it, but its time is its own.
        todo = [pid]
        while todo:
            p = todo.pop()
            if p in counted or p not in procs or owner.get(p, app_id) != app_id:
                continue
            counted.add(p)
            totals[app_id] = totals.get(app_id, 0) + procs[p][1]
            todo.extend(children.get(p, ()))
    return totals


def windows():
    """The app ids of the windows Wayfire shows, or []."""
    try:
        from .wfipc import Connection
        views = Connection().call("window-rules/list-views")
    except (ConnectionError, OSError, ValueError, ImportError):
        return []
    if not isinstance(views, list):
        return []
    return sorted({v.get("app-id") for v in views
                   if isinstance(v, dict) and v.get("role") == "toplevel" and v.get("app-id")})


class Sampler:
    """Call sample() now and then; significant() names the apps that used a
    lot of processor time between the last two samples, busiest first."""

    def __init__(self, ticks_per_second=None, clock=None, programs=None):
        self.hz = ticks_per_second or os.sysconf("SC_CLK_TCK")
        self.clock = clock
        self.programs = programs
        self.last = None          # (time, {app id: ticks})
        self.busy = []

    def sample(self, now=None, procs=None, views=None):
        import time
        now = now if now is not None else (self.clock or time.monotonic)()
        if self.last is not None and now - self.last[0] < 5:
            return self.busy       # too soon to say: keep the longer look
        totals = app_ticks(procs if procs is not None else processes(),
                           views if views is not None else windows(), self.programs)
        if self.last is not None:
            seconds = now - self.last[0]
            use = []
            for app_id, ticks in totals.items():
                before = self.last[1].get(app_id)
                if before is None or ticks < before:
                    continue
                percent = 100.0 * (ticks - before) / self.hz / seconds
                if percent >= SIGNIFICANT:
                    use.append((percent, app_id))
            self.busy = [app_id for _p, app_id in sorted(use, reverse=True)]
        self.last = (now, totals)
        return self.busy

    def significant(self):
        return list(self.busy)
