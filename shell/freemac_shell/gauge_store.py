# SPDX-License-Identifier: GPL-3.0-or-later
"""What the computer is busy with, read from /proc, with no GTK, for Gauge.

A Sampler reads every process each time it's asked and works out how much
of the processor each used since the time before, the way a Mac's Activity
Monitor does: 100% is one whole core, so a busy program on a four-core
machine can show up to 400%. Memory is each process's resident size.

Apps are the programs behind windows (Strata says which program owns each
window) together with every program they started, so a browser's many
helpers count as one browser.

Original freemac code.
"""
import collections
import os
import pwd
import re
import time

HISTORY = 60                 # samples kept for the graphs
TICK = os.sysconf("SC_CLK_TCK") if hasattr(os, "sysconf") else 100
PAGE = os.sysconf("SC_PAGE_SIZE") if hasattr(os, "sysconf") else 4096
CORES = os.cpu_count() or 1

# Interpreters whose program is the script they run: "python3 /usr/bin/freemac-reel"
# is freemac-reel to a person.
INTERPRETERS = ("python", "python3", "perl", "ruby", "node", "gjs")

Process = collections.namedtuple("Process", "pid ppid name command uid ticks rss threads started")


def _read(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return None


def friendly_name(comm, cmdline):
    """The program's name as a person would know it."""
    args = [a for a in cmdline.split(b"\0") if a] if cmdline else []
    first = args[0].decode(errors="replace").split(" ")[0] if args else ""
    base = os.path.basename(first)
    if base.rstrip("0123456789.") in INTERPRETERS and len(args) > 1:
        rest = [a.decode(errors="replace") for a in args[1:]]
        if rest[0] in ("-c", "-m") and len(rest) > 1:
            # "-c 'from freemac_shell.glyph import main'" or "-m freemac_shell.glyph"
            found = (re.search(r"from\s+([\w.]+)\s+import", rest[1])
                     or re.search(r"import\s+([\w.]+)", rest[1])) if rest[0] == "-c" else None
            module = found.group(1) if found else rest[1] if rest[0] == "-m" else ""
            part = module.rsplit(".", 1)[-1]
            if module.startswith("freemac_shell.") and part:
                return "freemac-" + part
            return part or base
        for text in rest:
            if not text.startswith("-"):
                return os.path.basename(text)
    # comm is cut to 15 characters; the command line has the whole name.
    # A program can give itself a name of its own, and keeps it in comm.
    if base and (base.startswith(comm[:15]) or len(comm) <= 2):
        return base
    return comm or base or "?"


def read_process(pid):
    raw = _read(f"/proc/{pid}/stat")
    if not raw:
        return None
    try:
        text = raw.decode(errors="replace")
        open_at, close_at = text.index("("), text.rindex(")")
        comm = text[open_at + 1:close_at]
        fields = text[close_at + 2:].split()
        ppid = int(fields[1])
        ticks = int(fields[11]) + int(fields[12])
        threads = int(fields[17])
        started = int(fields[19])
        rss = int(fields[21]) * PAGE
        uid = os.stat(f"/proc/{pid}").st_uid
    except (ValueError, IndexError, OSError):
        return None
    cmdline = _read(f"/proc/{pid}/cmdline") or b""
    command = cmdline.replace(b"\0", b" ").decode(errors="replace").strip()
    return Process(pid, ppid, friendly_name(comm, cmdline), command or f"[{comm}]",
                   uid, ticks, rss, threads, started)


def all_processes():
    found = {}
    for name in os.listdir("/proc"):
        if name.isdigit():
            proc = read_process(int(name))
            if proc is not None:
                found[proc.pid] = proc
    return found


def cpu_times():
    """(user, system, idle, total) clock ticks since boot, all cores."""
    line = (_read("/proc/stat") or b"cpu 0 0 0 0").split(b"\n", 1)[0].split()
    values = [int(v) for v in line[1:]] + [0] * 10
    user, nice, system, idle, iowait, irq, softirq, steal = values[:8]
    busy_user = user + nice
    busy_system = system + irq + softirq + steal
    rest = idle + iowait
    return busy_user, busy_system, rest, busy_user + busy_system + rest


def memory():
    """Bytes: total, used, cached, swap total, swap used."""
    info = {}
    for line in (_read("/proc/meminfo") or b"").decode().splitlines():
        key, _, value = line.partition(":")
        try:
            info[key] = int(value.split()[0]) * 1024
        except (ValueError, IndexError):
            pass
    total = info.get("MemTotal", 0)
    available = info.get("MemAvailable", info.get("MemFree", 0))
    cached = info.get("Cached", 0) + info.get("Buffers", 0)
    swap_total = info.get("SwapTotal", 0)
    swap_used = swap_total - info.get("SwapFree", 0)
    return {"total": total, "used": max(0, total - available), "cached": cached,
            "swap_total": swap_total, "swap_used": max(0, swap_used)}


_users = {}


def user_name(uid):
    if uid not in _users:
        try:
            _users[uid] = pwd.getpwuid(uid).pw_name
        except KeyError:
            _users[uid] = str(uid)
    return _users[uid]


def descendants(roots, processes):
    """Every pid started (directly or not) by one of roots, roots included."""
    children = collections.defaultdict(list)
    for proc in processes.values():
        children[proc.ppid].append(proc.pid)
    seen, stack = set(), [p for p in roots if p in processes]
    while stack:
        pid = stack.pop()
        if pid in seen:
            continue
        seen.add(pid)
        stack.extend(children.get(pid, ()))
    return seen


class Sampler:
    def __init__(self):
        self.last_ticks = {}
        self.last_cpu = None
        self.last_time = None
        self.cpu_history = collections.deque(maxlen=HISTORY)     # (user %, system %) of the whole machine
        self.memory_history = collections.deque(maxlen=HISTORY)  # fraction of memory used
        self.processes = {}
        self.usage = {}          # pid -> % of one core since the sample before
        self.summary = {}

    def sample(self):
        now = time.monotonic()
        processes = all_processes()
        cpu = cpu_times()
        usage = {}
        if self.last_time is not None:
            elapsed = max(0.001, now - self.last_time) * TICK
            for pid, proc in processes.items():
                before = self.last_ticks.get((pid, proc.started))
                usage[pid] = max(0.0, (proc.ticks - before) / elapsed * 100) if before is not None else 0.0
        self.last_ticks = {(pid, p.started): p.ticks for pid, p in processes.items()}
        self.last_time = now
        user = system = 0.0
        if self.last_cpu is not None:
            spent = max(1, cpu[3] - self.last_cpu[3])
            user = (cpu[0] - self.last_cpu[0]) / spent * 100
            system = (cpu[1] - self.last_cpu[1]) / spent * 100
            self.cpu_history.append((user, system))
        self.last_cpu = cpu
        mem = memory()
        if mem["total"]:
            self.memory_history.append(mem["used"] / mem["total"])
        self.processes, self.usage = processes, usage
        self.summary = dict(mem, user=user, system=system, idle=max(0.0, 100 - user - system),
                            count=len(processes), threads=sum(p.threads for p in processes.values()))
        return self.summary

    def rows(self, every=True, uid=None):
        """One row per process: dict of pid, name, command, cpu, memory,
        threads, user."""
        out = []
        for pid, proc in self.processes.items():
            if not every and proc.uid != uid:
                continue
            if proc.rss == 0 and proc.command.startswith("["):
                continue     # the kernel's own threads
            out.append({"key": f"pid:{pid}", "pids": [pid], "pid": pid, "name": proc.name,
                        "command": proc.command, "cpu": self.usage.get(pid, 0.0), "memory": proc.rss,
                        "threads": proc.threads, "user": user_name(proc.uid), "app_id": None})
        return out

    def app_rows(self, windows):
        """One row per app with windows. windows: {app_id: [pids of its windows]}."""
        out = []
        for app_id, roots in windows.items():
            pids = descendants(roots, self.processes)
            if not pids:
                continue
            procs = [self.processes[p] for p in pids]
            first = min(roots)
            out.append({"key": f"app:{app_id}", "pids": sorted(roots), "pid": first, "name": None,
                        "command": self.processes[first].command if first in self.processes else "",
                        "cpu": sum(self.usage.get(p, 0.0) for p in pids),
                        "memory": sum(p.rss for p in procs), "threads": sum(p.threads for p in procs),
                        "user": user_name(procs[0].uid), "app_id": app_id, "count": len(pids)})
        return out


def size_words(n):
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if n < 1000 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "bytes" else f"{n:.1f} {unit}"
        n /= 1000
    return ""


if __name__ == "__main__":
    s = Sampler()
    s.sample()
    time.sleep(1)
    print(s.sample())
    for row in sorted(s.rows(), key=lambda r: -r["cpu"])[:8]:
        print(f'{row["cpu"]:6.1f}% {size_words(row["memory"]):>10} {row["pid"]:>7} {row["name"]}')
