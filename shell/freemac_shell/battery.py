# SPDX-License-Identifier: GPL-3.0-or-later
"""The battery as a Mac's Battery settings show it: its level over the last
day, how long the computer ran on it each of the last ten days, its health,
and Low Power Mode.

The kernel lists batteries and chargers in /sys/class/power_supply
(FREEMAC_POWER_SUPPLY points somewhere else, to try all this without a real
battery). Topline reads the battery every 30 seconds and keeps a sample at
most every 5 minutes, and whenever charging starts or stops, in
~/.local/state/freemac/battery-history.json, for ten days. A gap in the
samples is time the computer was off or asleep.

Health is how much the battery holds when full now, against what it held
new (energy_full / energy_full_design), and how many times it has gone
through a full charge (cycle_count), where the battery reports them.

Low Power Mode is power-profiles-daemon's Power Saver profile, chosen by
shell.json's `low_power_mode`: never, always, only on battery, or only on
the power adapter. Topline switches it as the computer is plugged in or
unplugged; it hands back Balanced only if it was the one that chose Power
Saver. This module imports no GTK. Original freemac code.
"""
import glob
import json
import os
import shutil
import subprocess
import time

POWER_SUPPLY = os.environ.get("FREEMAC_POWER_SUPPLY", "/sys/class/power_supply")
STATE = os.path.expanduser("~/.local/state/freemac")
HISTORY = os.path.join(STATE, "battery-history.json")
CHOSE_SAVER = os.path.join(STATE, "low-power-mode")   # Topline turned Power Saver on

SAMPLE_EVERY = 5 * 60       # seconds between samples while nothing changes
KEEP = 10 * 24 * 3600       # ten days
GAP = 20 * 60               # more than this between samples: off or asleep
HEALTHY = 80                # below this much of its first capacity, service it

LOW_POWER_MODES = (("never", "Never"), ("always", "Always"),
                   ("battery", "Only on Battery"), ("adapter", "Only on Power Adapter"))


def read(path, name):
    try:
        with open(os.path.join(path, name)) as f:
            return f.read().strip()
    except OSError:
        return None


def _number(path, name):
    try:
        return int(read(path, name) or "")
    except ValueError:
        return None


def find():
    """The path of the first battery that's there, or None."""
    for path in sorted(glob.glob(os.path.join(POWER_SUPPLY, "*"))):
        if read(path, "type") == "Battery" and read(path, "present") != "0" and read(path, "scope") != "Device":
            return path
    return None


def on_adapter(battery=None):
    """Whether the computer is plugged in: a charger says it's online, or
    the battery says it's charging or full."""
    for path in glob.glob(os.path.join(POWER_SUPPLY, "*")):
        if read(path, "type") in ("Mains", "USB") and read(path, "online") == "1":
            return True
    battery = battery or find()
    return bool(battery) and read(battery, "status") in ("Charging", "Full", "Not charging")


def health(battery=None):
    """{"maximum": percent of its first capacity or None, "cycles": count
    or None, "condition": "Normal" or "Service Recommended" or None}."""
    battery = battery or find()
    if not battery:
        return None
    maximum = None
    for full, design in (("energy_full", "energy_full_design"), ("charge_full", "charge_full_design")):
        now, new = _number(battery, full), _number(battery, design)
        if now and new:
            maximum = min(100, round(now * 100 / new))
            break
    cycles = _number(battery, "cycle_count")
    if cycles is not None and cycles <= 0:
        cycles = None      # many batteries report 0 when they don't count
    condition = None
    if maximum is not None:
        condition = "Normal" if maximum >= HEALTHY else "Service Recommended"
    return {"maximum": maximum, "cycles": cycles, "condition": condition}


# ---- history ---------------------------------------------------------------
def history(path=HISTORY):
    """[(time, percent, charging)], oldest first."""
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return []
    samples = []
    for item in data if isinstance(data, list) else []:
        try:
            samples.append((float(item[0]), int(item[1]), bool(item[2])))
        except (TypeError, ValueError, IndexError):
            continue
    return sorted(samples)


def _save(samples, path=HISTORY):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path + ".new", "w") as f:
            json.dump([[round(t), p, int(c)] for t, p, c in samples], f, separators=(",", ":"))
        os.replace(path + ".new", path)
    except OSError:
        pass


def record(percent, charging, now=None, path=HISTORY):
    """Keep a sample if 5 minutes have passed or charging started or
    stopped. Returns True if it kept one."""
    now = time.time() if now is None else now
    samples = history(path)
    if samples:
        last_time, _last_percent, last_charging = samples[-1]
        if now - last_time < SAMPLE_EVERY and last_charging == charging:
            return False
    samples.append((now, int(percent), bool(charging)))
    _save([s for s in samples if now - s[0] <= KEEP], path)
    return True


def last_charged(samples):
    """(percent, time) where the battery last stopped charging, or None."""
    for (t, percent, charging), (_t2, _p2, next_charging) in zip(reversed(samples[:-1]), reversed(samples[1:])):
        if charging and not next_charging:
            return percent, t
    if samples and samples[-1][2]:
        return None    # charging now
    return None


def levels(samples, now=None, hours=24, step=15 * 60):
    """The last day in 15-minute slots, oldest first: (percent, charging)
    from the last sample in each slot, or None where the computer was off
    or asleep."""
    now = time.time() if now is None else now
    count = hours * 3600 // step
    start = now - count * step
    slots = [None] * count
    previous = None
    for t, percent, charging in samples:
        if t < start - GAP:
            previous = (t, percent, charging)
            continue
        if previous and t - previous[0] <= GAP:
            # Fill the slots between two samples close together.
            a = max(0, int((previous[0] - start) // step))
            b = min(count, int((t - start) // step))
            for i in range(a, b):
                if slots[i] is None:
                    slots[i] = (previous[1], previous[2])
        i = int((t - start) // step)
        if 0 <= i < count:
            slots[i] = (percent, charging)
        previous = (t, percent, charging)
    # The slot we're in carries on from the last sample until now.
    if previous and now - previous[0] <= GAP:
        a = max(0, int((previous[0] - start) // step))
        for i in range(a, count):
            if slots[i] is None:
                slots[i] = (previous[1], previous[2])
    return slots


def days_on_battery(samples, now=None, days=10):
    """[(midnight, seconds on battery)] for the last ten days, oldest first,
    counting only the time between samples close together."""
    now = time.time() if now is None else now
    today = time.localtime(now)
    midnight = time.mktime((today.tm_year, today.tm_mon, today.tm_mday, 0, 0, 0, 0, 0, -1))
    starts = []
    for back in range(days - 1, -1, -1):
        day = time.localtime(midnight - back * 86400 + 3600 * 12)   # noon: safe across DST
        starts.append(time.mktime((day.tm_year, day.tm_mon, day.tm_mday, 0, 0, 0, 0, 0, -1)))
    totals = [0.0] * days
    pairs = list(zip(samples, samples[1:]))
    if samples and now - samples[-1][0] <= GAP:
        pairs.append((samples[-1], (now, samples[-1][1], samples[-1][2])))
    for (t1, _p1, c1), (t2, _p2, _c2) in pairs:
        if c1 or t2 - t1 > GAP:
            continue
        for i, start in enumerate(starts):
            end = starts[i + 1] if i + 1 < days else midnight + 86400
            overlap = min(t2, end) - max(t1, start)
            if overlap > 0:
                totals[i] += overlap
    return list(zip(starts, totals))


def duration(seconds):
    """'3 hr 20 min', '45 min', as Mac settings write a length of time."""
    minutes = int(round(seconds / 60))
    hours, minutes = divmod(minutes, 60)
    if hours and minutes:
        return f"{hours} hr {minutes} min"
    if hours:
        return f"{hours} hr"
    return f"{minutes} min"


# ---- Low Power Mode --------------------------------------------------------
def low_power_wanted(mode, plugged):
    return mode == "always" or (mode == "battery" and not plugged) or (mode == "adapter" and plugged)


def profile():
    if not shutil.which("powerprofilesctl"):
        return None
    try:
        result = subprocess.run(("powerprofilesctl", "get"), capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def set_profile(name):
    """Whether power-profiles-daemon took it (it lets only the person at the
    computer change it)."""
    try:
        return subprocess.run(("powerprofilesctl", "set", name), capture_output=True, timeout=5).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def apply_low_power(mode, plugged):
    """Turn Power Saver on or off for this mode now. Returns whether Low
    Power Mode is on afterwards."""
    current = profile()
    if current is None:
        return False
    if low_power_wanted(mode, plugged):
        if current != "power-saver":
            if not set_profile("power-saver"):
                return False
            try:
                os.makedirs(STATE, exist_ok=True)
                open(CHOSE_SAVER, "w").close()
            except OSError:
                pass
        return True
    if current == "power-saver" and os.path.exists(CHOSE_SAVER) and set_profile("balanced"):
        current = "balanced"
    try:
        os.remove(CHOSE_SAVER)
    except OSError:
        pass
    return current == "power-saver"
