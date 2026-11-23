# SPDX-License-Identifier: GPL-3.0-or-later
"""Sound devices, volume, balance and mono audio, as on a Mac.

freemac's sound is PipeWire, run by WirePlumber, with PipeWire's PulseAudio
server alongside it. This module talks to that server with `pactl`
(pulseaudio-utils), which can set each channel of a device, list devices by
name and load the remap module that mono audio needs. Without pactl it falls
back on WirePlumber's `wpctl`, which has no balance or mono.

  Volume        the loudest channel; changing it keeps the balance, as a
                Mac does (wpctl would set every channel alike).
  Balance       -1 (all left) to 1 (all right), PulseAudio's own measure:
                at -0.4 the right channel is at 60% of the left.
  Mono audio    Dials > Accessibility > Audio, "Play stereo audio as mono":
                a one-channel device, freemac-mono, stands in front of the
                real output. Stereo sound sent to it is mixed down to one
                channel, which then plays from both speakers. Topline keeps it
                in front of whichever output is chosen (keep_mono()).

This module imports no GTK, so the volume keys (keys.py) answer quickly.
Original freemac code.
"""
import json
import os
import re
import shutil
import subprocess

DEFAULT_SINK = "@DEFAULT_SINK@"
MONO = "freemac-mono"
# The balance each output was last set to, for when its volume reaches 0
# and its channels no longer show it.
SAVED = os.path.expanduser("~/.config/freemac/sound.json")
MONO_ARGS = f"sink_name={MONO} channels=1 channel_map=mono sink_properties=device.description=Mono"


def available():
    return shutil.which("pactl") is not None


def _pactl(*args, timeout=3):
    """pactl's output, or None when it fails or isn't there."""
    if not available():
        return None
    try:
        result = subprocess.run(("pactl",) + args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout if result.returncode == 0 else None


def _wpctl(*args):
    if shutil.which("wpctl"):
        try:
            subprocess.run(("wpctl",) + args, capture_output=True, timeout=3)
        except (OSError, subprocess.SubprocessError):
            pass


def _listing(kind):
    out = _pactl("-f", "json", "list", kind)
    try:
        return json.loads(out) if out else []
    except ValueError:
        return []


# ---- devices ---------------------------------------------------------------
def device_icon(device):
    """A symbol for an output or input: speakers, headphones, a display."""
    props = device.get("properties", {})
    words = " ".join(str(x) for x in (device.get("description"), props.get("device.form_factor"),
                                      device.get("active_port"), props.get("device.bus"))).lower()
    if any(w in words for w in ("headphone", "headset", "earbud", "handsfree")):
        return "audio-headphones-symbolic"
    if any(w in words for w in ("hdmi", "displayport", "monitor", "tv")):
        return "video-display-symbolic"
    if "microphone" in words or "mic" in words.split() or device.get("_kind") == "sources":
        return "audio-input-microphone-symbolic"
    return "audio-speakers-symbolic"


def _devices(kind):
    """[(name, description, icon)] of real outputs or inputs: not mono's own
    device, and not the monitors that record what an output plays."""
    found = []
    for device in _listing(kind):
        name = device.get("name", "")
        props = device.get("properties", {})
        if not name or name == MONO or name.endswith(".monitor") or props.get("device.class") == "monitor":
            continue
        device["_kind"] = kind
        found.append((name, device.get("description") or name, device_icon(device)))
    return found


def outputs():
    return _devices("sinks")


def inputs():
    return _devices("sources")


def default_input():
    out = _pactl("get-default-source")
    return out.strip() if out else None


def current_output():
    """The output that plays: the real device behind mono when it's on."""
    out = _pactl("get-default-sink")
    name = out.strip() if out else None
    if name == MONO:
        return mono_master() or name
    return name


def set_output(name):
    """Play through this output from now on, mono or not."""
    if mono_module() is not None:
        _load_mono(name)
    else:
        _pactl("set-default-sink", name)


def set_input(name):
    _pactl("set-default-source", name)


# ---- volume and balance ----------------------------------------------------
def channels(sink=DEFAULT_SINK):
    """[(channel, percent)] for each of a device's channels, or []."""
    out = _pactl("get-sink-volume", sink)
    if not out:
        return []
    return [(name, int(percent)) for name, percent in re.findall(r"([\w-]+):\s*\d+\s*/\s*(\d+)%", out)]


def _side(channel):
    return -1 if "left" in channel else (1 if "right" in channel else 0)


def balance_of(chans):
    """PulseAudio's balance of a device's channels, -1..1."""
    left = max((p for c, p in chans if _side(c) < 0), default=None)
    right = max((p for c, p in chans if _side(c) > 0), default=None)
    if left is None or right is None or left == right:
        return 0.0
    if left > right:
        return right / left - 1.0
    return 1.0 - left / right


def spread(level, balance, chans):
    """Each channel's percent for this volume and balance."""
    balance = max(-1.0, min(1.0, balance))
    result = []
    for channel, _percent in chans:
        side = _side(channel)
        scale = 1.0
        if side < 0 and balance > 0:
            scale = 1.0 - balance
        elif side > 0 and balance < 0:
            scale = 1.0 + balance
        result.append(round(level * scale))
    return result


def _write(sink, chans, percents):
    _pactl("set-sink-volume", sink, *[f"{max(0, min(100, p))}%" for p in percents])


def _saved():
    try:
        with open(SAVED) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _save_balance(sink, value):
    data = _saved()
    data.setdefault("balance", {})[sink] = round(value, 3)
    try:
        os.makedirs(os.path.dirname(SAVED), exist_ok=True)
        with open(SAVED + ".new", "w") as f:
            json.dump(data, f, indent=2)
        os.replace(SAVED + ".new", SAVED)
    except OSError:
        pass


def _balance_for(sink, chans):
    """The balance the channels show, or the one saved while they're silent."""
    if chans and max(p for _c, p in chans) > 0:
        return balance_of(chans)
    name = current_output() if sink == DEFAULT_SINK else sink
    try:
        return float(_saved().get("balance", {}).get(name, 0.0))
    except (TypeError, ValueError):
        return 0.0


def level(sink=DEFAULT_SINK):
    chans = channels(sink)
    return max(p for _c, p in chans) if chans else None


def set_level(percent, sink=DEFAULT_SINK):
    """Set the volume (0..100), keeping the balance."""
    percent = int(max(0, min(100, percent)))
    chans = channels(sink)
    if not chans:
        _wpctl("set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@" if sink == DEFAULT_SINK else sink, f"{percent}%")
        return
    _write(sink, chans, spread(percent, _balance_for(sink, chans), chans))


def muted(sink=DEFAULT_SINK):
    out = _pactl("get-sink-mute", sink)
    return bool(out) and "yes" in out.lower()


def set_muted(on, sink=DEFAULT_SINK):
    if _pactl("set-sink-mute", sink, "1" if on else "0") is None:
        _wpctl("set-mute", "@DEFAULT_AUDIO_SINK@" if sink == DEFAULT_SINK else sink, "1" if on else "0")


def state(sink=DEFAULT_SINK):
    """(volume, muted) of the output, or None when pactl can't tell."""
    volume = level(sink)
    return None if volume is None else (volume, muted(sink))


def step(delta, sink=DEFAULT_SINK):
    """Turn the volume up or down by delta percent, keeping the balance."""
    chans = channels(sink)
    if not chans:
        sign = "+" if delta >= 0 else "-"
        _wpctl("set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", f"{abs(delta)}%{sign}")
        return
    set_level(max(p for _c, p in chans) + delta, sink)


def balance(sink=None):
    """The balance of the output that plays (not mono's device)."""
    sink = sink or current_output() or DEFAULT_SINK
    return _balance_for(sink, channels(sink))


def set_balance(value, sink=None):
    sink = sink or current_output() or DEFAULT_SINK
    chans = channels(sink)
    if len(chans) < 2:
        return
    _save_balance(sink, value)
    _write(sink, chans, spread(max(p for _c, p in chans), value, chans))


def has_balance(sink=None):
    """Whether the output has a left and a right to balance."""
    sides = {_side(c) for c, _p in channels(sink or current_output() or DEFAULT_SINK)}
    return -1 in sides and 1 in sides


# ---- mono audio ------------------------------------------------------------
def mono_wanted(prefs=None):
    if prefs is None:
        from . import style   # GTK: only Topline and Dials ask without prefs
        prefs = style.prefs()
    return bool(prefs.get("mono_audio"))


def _remap_modules():
    """[(index, args)] of the remap modules that make freemac-mono."""
    out = _pactl("list", "modules", "short") or ""
    found = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) >= 3 and parts[1] == "module-remap-sink" and f"sink_name={MONO}" in parts[2]:
            found.append((parts[0], parts[2]))
    return found


def mono_module():
    modules = _remap_modules()
    return modules[0][0] if modules else None


def mono_master():
    for _index, args in _remap_modules():
        match = re.search(r"master=(\S+)", args)
        if match:
            return match.group(1)
    return None


def _unload_mono():
    for index, _args in _remap_modules():
        _pactl("unload-module", index)


def _load_mono(master):
    _unload_mono()
    if not master or _pactl("load-module", "module-remap-sink", f"master={master}", *MONO_ARGS.split()) is None:
        if master:
            _pactl("set-default-sink", master)
        return False
    _pactl("set-default-sink", MONO)
    return True


def set_mono(on):
    """Turn mono audio on or off now (Dials saves the choice first)."""
    if on:
        master = current_output()
        if master and master != MONO:
            _load_mono(master)
    else:
        master = mono_master()
        if master:
            _pactl("set-default-sink", master)
        _unload_mono()


def keep_mono(prefs=None):
    """Put mono audio right after a change: on at login, in front of the
    output again if that output went away, off if Dials turned it off.
    Returns True if it changed anything."""
    if not available():
        return False
    wanted = mono_wanted(prefs)
    modules = _remap_modules()
    if not wanted:
        if modules:
            set_mono(False)
            return True
        return False
    names = [name for name, _d, _i in outputs()]
    master = mono_master()
    default = (_pactl("get-default-sink") or "").strip()
    if len(modules) == 1 and master in names:
        if default not in (MONO, master) and default in names:
            _load_mono(default)   # another output was chosen elsewhere
            return True
        if default != MONO:
            _pactl("set-default-sink", MONO)
            return True
        return False
    choice = default if default in names else (names[0] if names else None)
    if choice:
        _load_mono(choice)
        return True
    return False
