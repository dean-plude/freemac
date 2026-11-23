# SPDX-License-Identifier: GPL-3.0-or-later
"""More Dials panels: Sound, Power, Accessibility, Notifications and Screen Saver.

Each builder takes the Dials window (for its helpers and settings) and returns
the panel widget.
"""
import glob
import os
import re
import shutil
import subprocess

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402

from . import alert, announce, awake, background_sounds, dials_pointer, notify_rules, screen_reader, sounds, speak, startup_sound, style  # noqa: E402


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return None


# ---- Sound ----------------------------------------------------------------------
def parse_wpctl_status(text):
    """Sinks and sources from `wpctl status`: {"sinks": [(id, name, default)], ...}."""
    found = {"sinks": [], "sources": []}
    section, in_audio = None, False
    for line in text.splitlines():
        stripped = line.strip(" │├└─")
        if not line.startswith(" "):
            in_audio = line.strip() == "Audio"
            section = None
            continue
        if not in_audio:
            continue
        heading = stripped.rstrip(":").strip()
        if heading in ("Sinks", "Sources"):
            section = heading.lower()
            continue
        if heading in ("Devices", "Filters", "Streams", "Sink endpoints", "Source endpoints"):
            section = None
            continue
        match = re.match(r"(\*)?\s*(\d+)\.\s+(.+?)(\s+\[vol:.*\])?$", stripped.strip())
        if section and match:
            found[section].append((int(match.group(2)), match.group(3).strip(), bool(match.group(1))))
    return found


def volume_of(target):
    result = run("wpctl", "get-volume", target)
    if not result or result.returncode != 0:
        return None, False
    match = re.search(r"Volume:\s*([\d.]+)", result.stdout)
    return (float(match.group(1)) * 100 if match else None), "MUTED" in result.stdout


def sound_effects_group(window, group, row, slider, switch):
    """Sound Effects, as on a Mac: the alert sound and its volume, the pop as
    the volume changes, interface sounds and the start-up sound."""
    heading = Gtk.Label(label="Sound Effects", xalign=0)
    heading.get_style_context().add_class("dials-caption")

    choice = Gtk.ComboBoxText()
    for name, title in sounds.ALERTS:
        choice.append(name, title)
    choice.set_active_id(sounds.alert_name())

    def picked(combo):
        window.save_prefs(alert_sound=combo.get_active_id())
        sounds.alert(combo.get_active_id())
    choice.connect("changed", picked)

    level = slider(0, 100, 5, sounds.alert_volume(),
                   lambda v: window.save_prefs(alert_volume=int(v)))
    # Let go of the slider to hear the alert at the new level.
    level.connect("button-release-event", lambda *_: sounds.alert(volume=int(level.get_value())) and False)

    def on_start_up(on):
        startup_sound.set_enabled(on)
        if on:
            startup_sound.play()

    return heading, group(
        row("Alert sound", choice, "Plays when something can’t be done."),
        row("Alert volume", level),
        row("Play sound on start-up", switch(startup_sound.enabled(), on_start_up),
            "freemac’s own chime as the desktop first appears after the computer starts."),
        row("Play user interface sound effects", switch(sounds.ui_sounds(), lambda on: window.save_prefs(ui_sounds=on)),
            "A crumple when you empty the Trash and a shutter for a screenshot."),
        row("Play feedback when volume is changed", switch(sounds.volume_feedback(),
                                                           lambda on: window.save_prefs(volume_feedback=on)),
            "A little pop at the new level."))


def sound(window):
    group, row, page, slider, switch = window.helpers
    if not shutil.which("wpctl"):
        return page("Sound", group(row("Sound isn't running", None,
                                       "freemac uses PipeWire for sound; its control tool wasn't found.")),
                    *sound_effects_group(window, group, row, slider, switch))
    status = run("wpctl", "status")
    devices = parse_wpctl_status(status.stdout if status else "")
    groups = []
    for kind, target, title in (("sinks", "@DEFAULT_AUDIO_SINK@", "Output"),
                                ("sources", "@DEFAULT_AUDIO_SOURCE@", "Input")):
        rows = []
        combo = Gtk.ComboBoxText()
        for dev_id, name, default in devices[kind]:
            combo.append(str(dev_id), name)
            if default:
                combo.set_active_id(str(dev_id))
        combo.connect("changed", lambda c: c.get_active_id() and run("wpctl", "set-default", c.get_active_id()))
        if not devices[kind]:
            groups.append(group(row(f"No {title.lower()} devices", None)))
            continue
        rows.append(row(f"{title} device", combo))
        level, muted = volume_of(target)
        if level is not None:
            rows.append(row(f"{title} volume", slider(
                0, 100, 1, level, lambda v, t=target: run("wpctl", "set-volume", "-l", "1.0", t, f"{int(v)}%"))))
            rows.append(row("Mute", switch(muted, lambda on, t=target: run(
                "wpctl", "set-mute", t, "1" if on else "0"))))
        groups.append(group(*rows))
    return page("Sound", *sound_effects_group(window, group, row, slider, switch), *groups)


# ---- Power ----------------------------------------------------------------------
BLANK_CHOICES = (("-1", "Never"), ("60", "1 minute"), ("120", "2 minutes"), ("300", "5 minutes"),
                 ("600", "10 minutes"), ("900", "15 minutes"), ("1800", "30 minutes"))


def battery_state():
    from .status import POWER_SUPPLY, battery_time
    for path in sorted(glob.glob(os.path.join(POWER_SUPPLY, "*"))):
        def read(name):
            try:
                with open(os.path.join(path, name)) as f:
                    return f.read().strip()
            except OSError:
                return None
        if read("type") == "Battery" and read("present") != "0":
            state = read("status")
            left = battery_time(path, lambda p, n: read(n))
            return read("capacity"), (state, left)
    return None


def battery_words(state):
    """'On battery, 2:15 left' for the Battery row."""
    status, left = state
    if status == "Discharging":
        return f"On battery, {left} left" if left else "On battery"
    if status == "Charging":
        return f"Charging, {left} until full" if left else "Charging"
    if status in ("Full", "Not charging"):
        return "Plugged in"
    return status or None


LOCK_CHOICES = (("0", "Never"), ("1", "1 minute"), ("2", "2 minutes"), ("5", "5 minutes"),
                ("10", "10 minutes"), ("15", "15 minutes"), ("30", "30 minutes"))


def power(window):
    group, row, page, _slider, _switch = window.helpers
    groups = []
    battery = battery_state()
    if battery:
        capacity, state = battery
        prefs = style.prefs()
        percent = _switch(bool(prefs.get("battery_percent", True)),
                          lambda active: window.save_prefs(battery_percent=active))
        groups.append(group(row("Battery", Gtk.Label(label=f"{capacity}%"), battery_words(state)),
                            row("Show percentage in the menu bar", percent),
                            row("Low battery", Gtk.Label(label="Warns at 10% and 5%"),
                                "At 2% the computer goes to sleep so nothing is lost.")))
    blank = Gtk.ComboBoxText()
    for value, label in BLANK_CHOICES:
        blank.append(value, label)
    blank.set_active_id(window.ini_get("idle", "dpms_timeout", "600") or "600")
    if not blank.get_active_id():
        blank.set_active_id("600")
    blank.connect("changed", lambda c: window.ini_set("idle", "dpms_timeout", c.get_active_id()))
    awake_rows = [row("Turn the screen off after", blank, "When nothing has been touched for this long.")]
    holds = awake.holds_now()
    if holds:
        # What a Mac's Activity Monitor calls "Preventing Sleep".
        names = ", ".join(dict.fromkeys(app for app, _reason in holds))
        reasons = "; ".join(dict.fromkeys(reason for _app, reason in holds if reason))
        awake_rows.append(row("Keeping the screen on", Gtk.Label(label=names),
                              (reasons + ". " if reasons else "") +
                              "The screen stays on and doesn't lock until they're done."))
    groups.append(group(*awake_rows))
    prefs = style.prefs()
    lock_after = Gtk.ComboBoxText()
    for value, label in LOCK_CHOICES:
        lock_after.append(value, label)
    lock_after.set_active_id(str(prefs.get("lock_after", 5)))
    if not lock_after.get_active_id():
        lock_after.set_active_id("5")
    lock_after.connect("changed", lambda c: window.save_prefs(lock_after=int(c.get_active_id())))
    on_sleep = _switch(bool(prefs.get("lock_on_sleep", True)),
                       lambda active: window.save_prefs(lock_on_sleep=active))
    groups.append(group(row("Lock the screen after", lock_after,
                            "You'll need your password to get back in. \u2303\u2318Q locks at once."),
                        row("Lock before sleeping", on_sleep)))
    if shutil.which("powerprofilesctl"):
        mode = Gtk.ComboBoxText()
        for value, label in (("power-saver", "Power Saver"), ("balanced", "Balanced"),
                             ("performance", "Performance")):
            mode.append(value, label)
        current = run("powerprofilesctl", "get")
        mode.set_active_id(current.stdout.strip() if current and current.returncode == 0 else "balanced")
        mode.connect("changed", lambda c: run("powerprofilesctl", "set", c.get_active_id()))
        groups.append(group(row("Power mode", mode, "Power Saver makes a battery last longer.")))
    buttons = Gtk.Box(spacing=8)
    for label, action in (("Sleep", "suspend"), ("Restart…", "reboot"), ("Shut Down…", "poweroff")):
        button = Gtk.Button(label=label)
        button.connect("clicked", lambda _b, a=action: window.confirm_power(a))
        buttons.pack_start(button, False, False, 0)
    groups.append(buttons)
    recovery = Gtk.Button(label="Restart in Recovery…")
    if can_restart_in_recovery():
        recovery.connect("clicked", lambda _b: restart_in_recovery(window))
        groups.append(group(row("freemac Recovery", recovery,
                                "Bring back files from a Lifeboat backup, reset a password or check a disk. "
                                "You can also hold Ctrl while the computer starts.")))
    else:
        groups.append(group(row("freemac Recovery", Gtk.Label(label="Hold Ctrl as it starts"),
                                "Bring back files from a Lifeboat backup, reset a password or check a disk.")))
    return page("Power", *groups)


RECOVERY_HELPER = "/usr/libexec/freemac-recovery-helper"


def can_restart_in_recovery():
    """Only a freemac installed on a disk can choose what the next start-up
    starts; a USB stick's menu can't be changed."""
    if os.path.isdir("/run/live/medium") or not os.access(RECOVERY_HELPER, os.X_OK):
        return False
    try:
        with open("/boot/grub/grub.cfg") as f:
            return "freemac-recovery" in f.read()
    except OSError:
        return os.path.exists("/boot/grub/grubenv")


def restart_in_recovery(window):
    answer = alert.ask(window, "Restart in Recovery?",
                       "The computer restarts into freemac Recovery, where you can bring back files from a "
                       "Lifeboat backup, reset a password or check a disk. It starts as usual the time after. "
                       "Unsaved work in open apps will be lost.",
                       [("Cancel", Gtk.ResponseType.CANCEL), ("Restart", Gtk.ResponseType.OK)],
                       default=Gtk.ResponseType.OK)
    if answer != Gtk.ResponseType.OK:
        return
    try:
        process = Gio.Subprocess.new(["pkexec", RECOVERY_HELPER], Gio.SubprocessFlags.STDERR_PIPE)
    except GLib.Error as error:
        alert.tell(window, "The computer couldn\u2019t restart in Recovery.", error.message)
        return

    def finished(proc, result):
        try:
            _ok, _out, err = proc.communicate_utf8_finish(result)
        except GLib.Error:
            return
        # 126 is the password dialog being cancelled: nothing to say then.
        if proc.get_exit_status() not in (0, 126):
            alert.tell(window, "The computer couldn\u2019t restart in Recovery.", (err or "").strip())
    process.communicate_utf8_async(None, None, finished)


# ---- Accessibility ---------------------------------------------------------------
INVERT_KEY = "<ctrl> <alt> <super> KEY_8"


def accessibility(window):
    group, row, page, _slider, switch = window.helpers
    settings = window.settings

    def get(key, default):
        try:
            return settings.get_value(key).unpack() if settings else default
        except TypeError:
            return default

    def larger_text(on):
        if settings:
            settings.set_double("text-scaling-factor", 1.25 if on else 1.0)

    def reduce_motion(on):
        if settings:
            settings.set_boolean("enable-animations", not on)
        window.ini_set("animate", "open_animation", "fade" if on else "zoom")
        window.ini_set("animate", "close_animation", "fade" if on else "zoom")
        window.ini_set("animate", "duration", "120" if on else "220")
        # Windows no longer wobble at all (that's not how a Mac behaves); this
        # only cleans it up on systems set up before 1.2.
        plugins = (window.ini_get("core", "plugins", "") or "").split()
        if "wobbly" in plugins:
            plugins.remove("wobbly")
            window.ini_set("core", "plugins", " ".join(plugins))

    def high_contrast(on):
        from .dials import theme_for   # dials imports this module

        if settings:
            dark = style.is_dark()
            settings.set_string("gtk-theme", "HighContrast" if on else theme_for(dark))

    def big_pointer(size):
        if settings:
            settings.set_int("cursor-size", size)
        window.ini_set("input", "cursor_size", str(size))

    pointer = Gtk.ComboBoxText()
    for value, label in (("24", "Default"), ("32", "Large"), ("48", "Larger"), ("64", "Largest")):
        pointer.append(value, label)
    pointer.set_active_id(str(get("cursor-size", 24)))
    if not pointer.get_active_id():
        pointer.set_active_id("24")
    pointer.connect("changed", lambda c: big_pointer(int(c.get_active_id())))
    def plugins():
        return (window.ini_get("core", "plugins", "") or "").split()

    def zoom_switch(on):
        names = [n for n in plugins() if n != "zoom"]
        if on:
            names.append("zoom")
        window.ini_set("core", "plugins", " ".join(names))
        zoom_keys.set_sensitive(on)

    # Hold a key and scroll to zoom in on the part of the screen under the
    # pointer, as a Mac's Zoom does with its scroll gesture.
    zoom_keys = Gtk.ComboBoxText()
    for value, label in (("<super>", "⌘ Command"), ("<alt>", "⌥ Option"), ("<ctrl>", "⌃ Control")):
        zoom_keys.append(value, label)
    zoom_keys.set_active_id((window.ini_get("zoom", "modifier", "<super>") or "<super>").strip())
    if not zoom_keys.get_active_id():
        zoom_keys.set_active_id("<super>")
    zoom_keys.connect("changed", lambda c: window.ini_set("zoom", "modifier", c.get_active_id()))
    zoom_on = "zoom" in plugins()
    zoom_keys.set_sensitive(zoom_on)

    # Strata watches for the shake itself (strata-shell/shake_to_locate).
    shake_on = (window.ini_get("strata-shell", "shake_to_locate", "true") or "true").strip().lower() \
        not in ("false", "0", "no", "off")

    def shake_switch(on):
        window.ini_set("strata-shell", "shake_to_locate", "true" if on else "false")

    def invert_switch(on):
        # The key is set first: Wayfire's own default for it is ⌘I, which
        # is Get Info in freemac.
        window.ini_set("invert", "toggle", INVERT_KEY)
        names = [n for n in plugins() if n != "invert"]
        if on:
            names.append("invert")
        window.ini_set("core", "plugins", " ".join(names))
    return page("Accessibility", group(
        row("Larger text", switch(get("text-scaling-factor", 1.0) > 1.05, larger_text)),
        row("High contrast", switch(get("gtk-theme", "freemac") == "HighContrast", high_contrast),
            "Stronger borders and colours in apps."),
        row("Reduce motion", switch(not get("enable-animations", True), reduce_motion),
            "Windows fade instead of zooming and don't wobble."),
        row("Reduce transparency", switch(style.solid(), lambda on: window.save_prefs(reduce_transparency=on)),
            "The menu bar, the Dock and panels are solid instead of see-through."),
        row("Invert colours with \u2303\u2325\u23188", switch("invert" in plugins(), invert_switch),
            "Press Control-Option-Command-8 to swap the screen's colours, and again to put them back."),
        row("Pointer size", pointer),
        *dials_pointer.rows(window, row),
        row("Shake mouse pointer to locate", switch(shake_on, shake_switch),
            "Move the mouse quickly back and forth and the pointer grows big for a moment."),
    ), group(
        row("Zoom", switch(zoom_on, zoom_switch),
            "Hold a key and scroll to zoom in on the part of the screen under the pointer."),
        row("Zoom with", zoom_keys, "Apps also zoom their own pages with \u2303 Control and scrolling."),
    ), *hover_text_group(window), *reader_group(window), colour_filters(window), sticky_keys(window), slow_keys(window), mouse_keys(window), screen_keyboard_group(window),
        audio(window), *spoken_content(window))


HOVER_KEYS = (("command", "\u2318 Command"), ("option", "\u2325 Option"), ("control", "\u2303 Control"))
HOVER_SIZES = (("24", "Small"), ("36", "Medium"), ("48", "Large"), ("64", "Huge"))


def hover_text_group(window):
    """Hover Text: hold a key and point at words to see them large (Strata
    watches the key, Topline reads and shows the words: hover_text.py)."""
    group, row, _page, _slider, switch = window.helpers
    from . import livetext
    if not livetext.available():
        return []
    on = (window.ini_get("strata-shell", "hover_text", "false") or "false").strip().lower() \
        in ("true", "1", "yes", "on")
    keys = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
    for value, label in HOVER_KEYS:
        keys.append(value, label)
    keys.set_active_id((window.ini_get("strata-shell", "hover_text_key", "command") or "command").strip())
    if not keys.get_active_id():
        keys.set_active_id("command")
    keys.connect("changed", lambda c: window.ini_set("strata-shell", "hover_text_key", c.get_active_id()))
    size = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
    for value, label in HOVER_SIZES:
        size.append(value, label)
    size.set_active_id(str(style.prefs().get("hover_text_size", 36)))
    if not size.get_active_id():
        size.set_active_id("36")
    size.connect("changed", lambda c: window.save_prefs(hover_text_size=int(c.get_active_id())))

    def turned(active):
        window.ini_set("strata-shell", "hover_text", "true" if active else "false")
        size.set_sensitive(active)
    # The key also speaks the words under the pointer (Spoken Content), so it
    # stays open to change with Hover Text off.
    size.set_sensitive(on)
    return [group(
        row("Hover Text", switch(on, turned),
            "Hold a key and point at some words to see them large above the pointer."),
        row("Hold", keys),
        row("Text size", size),
    )]


def reader_group(window):
    """The screen reader: on or off (as Command-F5 does anywhere), and Orca's
    own settings for its voice, how much it says and its keys."""
    group, row, _page, _slider, switch = window.helpers
    if not screen_reader.available():
        return []
    options = Gtk.Button(label="Screen Reader Settings\u2026", valign=Gtk.Align.CENTER)
    options.connect("clicked", lambda _b: screen_reader.settings())
    on = screen_reader.running() or screen_reader.wanted()
    options.set_sensitive(on)

    def turned(active):
        screen_reader.set_on(active)
        options.set_sensitive(active)
    return [group(
        row("Screen reader", switch(on, turned),
            "Speaks what's on the screen and what you type. Press \u2318F5 to turn it on or off "
            "anywhere."),
        row("Voice, speed and keys", options,
            "Insert is the screen reader key: hold it with other keys to hear where you are."),
    )]


COLOUR_FILTERS = (("none", "Off"), ("greyscale", "Greyscale"),
                  ("protanopia", "Red/green filter (protanopia)"),
                  ("deuteranopia", "Green/red filter (deuteranopia)"),
                  ("tritanopia", "Blue/yellow filter (tritanopia)"),
                  ("tint", "Colour tint"))
DEFAULT_TINT = "0.85 0.45 0.55 1.0"


def parse_colour(text, default=DEFAULT_TINT):
    """An RGBA from a Wayfire colour ("r g b a" from 0 to 1, or #RRGGBB[AA])."""
    rgba = Gdk.RGBA()
    text = (text or default).strip()
    parts = text.split()
    try:
        if len(parts) == 4:
            rgba.red, rgba.green, rgba.blue, rgba.alpha = (float(p) for p in parts)
            return rgba
    except ValueError:
        pass
    if not rgba.parse(text[:7] if text.startswith("#") else text):
        return parse_colour(default)
    return rgba


def colour_filters(window):
    """Colour filters, as on a Mac: the screen in greys, adjusted for colour
    blindness, or tinted, at a chosen strength. Strata draws it
    (strata-shell/colour_filter, strata/shell/colour-filters.hpp)."""
    group, row, _page, slider, _switch = window.helpers
    kind = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
    for value, label in COLOUR_FILTERS:
        kind.append(value, label)
    current = (window.ini_get("strata-shell", "colour_filter", "none") or "none").strip()
    if not kind.set_active_id(current):
        kind.set_active_id("none")
    try:
        strength = float(window.ini_get("strata-shell", "colour_filter_intensity", "1.0") or 1.0)
    except ValueError:
        strength = 1.0
    intensity = slider(0.1, 1.0, 0.05, max(0.1, min(1.0, strength)),
                       lambda v: window.ini_set("strata-shell", "colour_filter_intensity", f"{v:.2f}"),
                       marks=((0.1, "Less"), (1.0, "More")))
    tint = Gtk.ColorButton(valign=Gtk.Align.CENTER, use_alpha=False)
    tint.set_rgba(parse_colour(window.ini_get("strata-shell", "colour_filter_tint", DEFAULT_TINT)))

    def tint_set(button):
        c = button.get_rgba()
        window.ini_set("strata-shell", "colour_filter_tint", f"{c.red:.3f} {c.green:.3f} {c.blue:.3f} 1.0")

    tint.connect("color-set", tint_set)

    def sensitive():
        chosen = kind.get_active_id()
        intensity.set_sensitive(chosen != "none")
        tint.set_sensitive(chosen == "tint")

    def kind_set(combo):
        window.ini_set("strata-shell", "colour_filter", combo.get_active_id() or "none")
        sensitive()

    kind.connect("changed", kind_set)
    sensitive()
    return group(
        row("Colour filters", kind,
            "Show the screen in greys, adjusted for colour blindness, or tinted with a colour."),
        row("Intensity", intensity),
        row("Tint colour", tint))


def sticky_keys(window):
    """Sticky Keys, as on a Mac: a modifier key tapped on its own stays down
    for the next key (strata-shell/sticky_keys, done by Strata), with what
    Topline shows and plays while one is set (sticky.py)."""
    group, row, _page, _slider, switch = window.helpers

    def on(key, default):
        value = window.ini_get("strata-shell", key, default) or default
        return value.strip().lower() not in ("false", "0", "no", "off")

    def setter(key):
        return lambda value: window.ini_set("strata-shell", key, "true" if value else "false")

    prefs = style.prefs()
    return group(
        row("Sticky Keys", switch(on("sticky_keys", "false"), setter("sticky_keys")),
            "Tap \u21e7 Shift, \u2303 Control, \u2325 Option or \u2318 Command and it stays down for "
            "the next key you press. Tap it twice to lock it, and once more to let it go."),
        row("Press Shift five times to turn Sticky Keys on or off",
            switch(on("sticky_keys_shift", "true"), setter("sticky_keys_shift"))),
        row("Beep when a modifier key is set",
            switch(prefs.get("sticky_beep", True), lambda value: window.save_prefs(sticky_beep=value))),
        row("Show pressed modifier keys on screen",
            switch(prefs.get("sticky_show", True), lambda value: window.save_prefs(sticky_show=value)),
            "Their symbols show in the top-right corner while they're set."))


def slow_keys(window):
    """Slow Keys, as on a Mac: a key counts only once it has been held for
    the acceptance delay (strata-shell/slow_keys and slow_keys_delay, done by
    Strata), with a click as each key goes down and counts (slow_keys.py)."""
    group, row, _page, slider, switch = window.helpers

    def on(key, default):
        value = window.ini_get("strata-shell", key, default) or default
        return value.strip().lower() not in ("false", "0", "no", "off")

    def setter(key):
        return lambda value: window.ini_set("strata-shell", key, "true" if value else "false")

    try:
        delay = int(window.ini_get("strata-shell", "slow_keys_delay", "500") or 500)
    except ValueError:
        delay = 500
    delay = max(100, min(2000, delay))
    acceptance = slider(100, 2000, 100, delay,
                        lambda value: window.ini_set("strata-shell", "slow_keys_delay", str(int(value))),
                        marks=((100, "Short"), (2000, "Long")))
    return group(
        row("Slow Keys", switch(on("slow_keys", "false"), setter("slow_keys")),
            "A key counts only once you've held it down for a moment, so a key brushed by "
            "accident isn't typed. Shift, Control, Option and Command work at once."),
        row("Acceptance delay", acceptance),
        row("Use click key sounds", switch(on("slow_keys_click", "true"), setter("slow_keys_click")),
            "A soft click as a key goes down, and another once it counts."))


def mouse_keys(window):
    """Mouse Keys, as on a Mac: the keypad moves the pointer and clicks
    (strata-shell/mouse_keys and the rest, done by Strata)."""
    group, row, _page, slider, switch = window.helpers

    def on(key, default):
        value = window.ini_get("strata-shell", key, default) or default
        return value.strip().lower() not in ("false", "0", "no", "off")

    def setter(key):
        return lambda value: window.ini_set("strata-shell", key, "true" if value else "false")

    def number(key, default, low, high):
        try:
            value = int(window.ini_get("strata-shell", key, str(default)) or default)
        except ValueError:
            value = default
        return max(low, min(high, value))

    delay = slider(0, 2000, 100, number("mouse_keys_delay", 300, 0, 2000),
                   lambda value: window.ini_set("strata-shell", "mouse_keys_delay", str(int(value))),
                   marks=((0, "Short"), (2000, "Long")))
    speed = slider(1, 10, 1, number("mouse_keys_speed", 5, 1, 10),
                   lambda value: window.ini_set("strata-shell", "mouse_keys_speed", str(int(value))),
                   marks=((1, "Slow"), (10, "Fast")))
    return group(
        row("Mouse Keys", switch(on("mouse_keys", "false"), setter("mouse_keys")),
            "Move the pointer with the number keypad: 8, 2, 4 and 6 go up, down, left and right, "
            "5 clicks, 0 holds the button down to drag and the full stop lets it go."),
        row("Press Option five times to turn Mouse Keys on or off",
            switch(on("mouse_keys_option", "true"), setter("mouse_keys_option"))),
        row("Use the letter keys too", switch(on("mouse_keys_letters", "false"), setter("mouse_keys_letters")),
            "For a keyboard without a keypad: 8, K, U and O move, 7, 9, J and L go diagonally, "
            "I clicks, M holds and the full stop lets go. Those keys don't type while Mouse Keys is on."),
        row("Initial delay", delay),
        row("Maximum speed", speed))


def screen_keyboard_group(window):
    """The Accessibility Keyboard, as on a Mac: a keyboard on the screen to
    type with the pointer alone (screen_keyboard.py in Topline, which follows
    shell.json "accessibility_keyboard")."""
    group, row, _page, _slider, switch = window.helpers
    prefs = style.prefs()
    return group(
        row("Accessibility Keyboard",
            switch(bool(prefs.get("accessibility_keyboard", False)),
                   lambda value: window.save_prefs(accessibility_keyboard=value)),
            "A keyboard on the screen, to type with the mouse, a trackpad or a touch screen. "
            "Shift, Control, Option and Command stay down for the next key you click."))


def audio(window):
    """Audio: flash the screen with the alert sound, as a Mac can, for
    anyone who can't hear it, with a button to see what it looks like; and
    Background Sounds, a steady sound behind everything else, its sound and
    its volume (background_sounds.py plays it from Topline)."""
    group, row, _page, slider, switch = window.helpers
    test = Gtk.Button(label="Test Screen Flash", valign=Gtk.Align.CENTER)
    test.connect("clicked", lambda _b: sounds.flash())

    on, sound, volume = background_sounds.wanted()
    choice = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
    for name, title in background_sounds.SOUNDS:
        choice.append(name, title)
    choice.set_active_id(sound)
    choice.connect("changed", lambda c: window.save_prefs(background_sound=c.get_active_id()))
    level = slider(0, 100, 5, volume, lambda v: window.save_prefs(background_volume=int(v)))

    def turned(active):
        window.save_prefs(background_sounds=active)
        choice.set_sensitive(active)
        level.set_sensitive(active)
    choice.set_sensitive(on)
    level.set_sensitive(on)
    return group(
        row("Flash the screen when an alert sound occurs",
            switch(sounds.flash_screen(), lambda on: window.save_prefs(flash_screen=on)),
            "Every display flashes when there's an alert, even with the sound turned down."),
        row("See how it looks", test),
        row("Background sounds", switch(on, turned),
            "Plays a steady sound behind everything else, to mask noise around you "
            "and help you focus or rest."),
        row("Sound", choice),
        row("Volume", level))


def spoken_content(window):
    """Spoken Content: Speak selection with Option-Escape, speak the words
    under the pointer (with the Hover Text key), announce notifications and
    the time (announce.py), the voice and how fast it talks, and a Play
    button to hear them."""
    group, row, _page, _slider, switch = window.helpers
    if not speak.available():
        return []
    prefs = style.prefs()
    voice = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
    for value, label in speak.VOICES:
        voice.append(value, label)
    voice.set_active_id(speak.voice())
    voice.connect("changed", lambda c: window.save_prefs(speak_voice=c.get_active_id()))
    speed = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, speak.SLOW, speak.FAST, 5)
    speed.set_draw_value(False)
    speed.set_size_request(200, -1)
    speed.set_value(speak.rate())
    speed.add_mark(speak.SLOW, Gtk.PositionType.BOTTOM, "Slow")
    speed.add_mark(speak.FAST, Gtk.PositionType.BOTTOM, "Fast")
    speed.connect("value-changed", lambda s: window.save_prefs(speak_rate=int(s.get_value())))
    play = Gtk.Button(label="Play", valign=Gtk.Align.CENTER)
    play.connect("clicked", lambda _b: speak.say(SAMPLE))
    voice_box = Gtk.Box(spacing=8)
    voice_box.pack_start(voice, False, False, 0)
    voice_box.pack_start(play, False, False, 0)

    def turned(on):
        window.save_prefs(speak_selection=on)
        if not on:
            speak.stop()

    pointer_on = (window.ini_get("strata-shell", "hover_speak", "false") or "false").strip().lower() \
        in ("true", "1", "yes", "on")
    from . import livetext
    pointer_rows = [row(
        "Speak items under the pointer",
        switch(pointer_on, lambda on: window.ini_set("strata-shell", "hover_speak", "true" if on else "false")),
        "Hold the Hover Text key (\u2318 unless you chose another) and point at some words to hear them.")] \
        if livetext.available() else []
    every = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
    for value, label in announce.EVERY:
        every.append(value, label)
    every.set_active_id(announce.time_every(prefs))
    every.connect("changed", lambda c: window.save_prefs(announce_time=c.get_active_id()))

    heading = Gtk.Label(label="Spoken Content", xalign=0)
    heading.get_style_context().add_class("dials-section")
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    box.pack_start(heading, False, False, 0)
    box.pack_start(group(
        row("Speak selection", switch(bool(prefs.get("speak_selection")), turned),
            "Select some words in any app and press \u2325Esc to hear them. Press it again to stop."),
        *pointer_rows,
        row("Announce notifications",
            switch(bool(prefs.get("announce_notifications")), lambda on: window.save_prefs(announce_notifications=on)),
            "Read out each notification as it shows. Not while a Focus is on."),
        row("Announce the time", every, "Say the time out loud. Not while a Focus is on."),
        row("Voice", voice_box),
        row("Speaking rate", speed),
    ), False, False, 0)
    return [box]


SAMPLE = "This is how freemac reads the words you select."


# ---- Notifications ----------------------------------------------------------------
def notifications(window):
    group, row, page, _slider, switch = window.helpers
    prefs = style.prefs()
    seconds = Gtk.ComboBoxText()
    for value, label in (("3", "3 seconds"), ("5", "5 seconds"), ("8", "8 seconds"), ("12", "12 seconds")):
        seconds.append(value, label)
    seconds.set_active_id(str(int(prefs.get("banner_seconds", 5))))
    if not seconds.get_active_id():
        seconds.set_active_id("5")
    seconds.connect("changed", lambda c: window.save_prefs(banner_seconds=int(c.get_active_id())))
    clear = Gtk.Button(label="Clear")

    def clear_history(_button):
        from . import beacon

        beacon.call("ClearAll")
        clear.set_sensitive(False)
        GLib.timeout_add_seconds(2, lambda: clear.set_sensitive(True) or False)

    clear.connect("clicked", clear_history)

    # One row for each app that has sent a notification.
    from . import beacon

    apps = notify_rules.known_apps(beacon.APPS)
    app_rows = []
    for app in sorted(apps, key=str.casefold):
        combo = Gtk.ComboBoxText()
        for key, label in notify_rules.STYLES:
            combo.append(key, label)
        combo.set_active_id(notify_rules.app_style(prefs, app))

        def chosen(c, app=app):
            choices = style.prefs().get("notify_apps")
            choices = dict(choices) if isinstance(choices, dict) else {}
            if c.get_active_id() == "banners":
                choices.pop(app, None)
            else:
                choices[app] = c.get_active_id()
            window.save_prefs(notify_apps=choices)
        combo.connect("changed", chosen)
        line = row(app, combo)
        icon = _app_icon(apps[app])
        line.get_child().pack_start(icon, False, False, 0)
        line.get_child().reorder_child(icon, 0)
        app_rows.append(line)
    if not app_rows:
        app_rows.append(row("No apps have sent notifications yet."))
    to_focus = Gtk.Button(label="Focus Settings…")
    to_focus.connect("clicked", lambda *_: window.show_panel("focus"))
    return page("Notifications", group(
        row("Focus", to_focus,
            "Do Not Disturb, Sleep, Work and Personal quiet banners, at set times or whenever you like."),
        row("Show banners for", seconds),
    ), group(*app_rows), group(
        row("Notification history", clear, "Click the clock in the menu bar to see recent notifications."),
    ))


def _time_choice(value):
    """A drop-down of times on the half hour, showing value."""
    combo = Gtk.ComboBoxText()
    for minutes in range(0, 24 * 60, 30):
        text = f"{minutes // 60:02d}:{minutes % 60:02d}"
        combo.append(text, text)
    combo.set_active_id(value)
    if not combo.get_active_id():          # a time set by hand, not on the half hour
        combo.append(value, value)
        combo.set_active_id(value)
    return combo


# ---- Focus ------------------------------------------------------------------------
FOCUS_ABOUT = {
    "dnd": "Quiet everything, for as long as you like.",
    "sleep": "Quiet the evening and night, so the computer doesn't wake you.",
    "work": "Hear only from the apps you work with.",
    "personal": "Leave work behind and hear from the apps you choose.",
}


def focus(window):
    """Focus, as on a Mac: Do Not Disturb, Sleep, Work and Personal. Each
    hides banners while it's on (they still collect in the notification
    centre), lets the apps you choose through, and can come on by itself at
    set times on set days (notify_rules.py has the rules)."""
    from . import beacon

    group, row, page, _slider, switch = window.helpers
    prefs = style.prefs()
    apps = notify_rules.known_apps(beacon.APPS)
    on_switches = {}
    syncing = {"busy": False}

    def turn(focus_id, on):
        if syncing["busy"]:
            return
        now = style.prefs()
        if on:
            window.save_prefs(**notify_rules.focus_writes(focus_id))
        elif notify_rules.active_focus(now) == focus_id:
            window.save_prefs(**notify_rules.focus_writes(None, now))
        # Only one Focus is on at a time: the others' switches follow.
        syncing["busy"] = True
        current = notify_rules.active_focus(style.prefs())
        for key, other in on_switches.items():
            other.set_active(key == current)
        syncing["busy"] = False

    def save_schedule(focus_id, **change):
        now = style.prefs()
        rule = notify_rules.schedule(now, focus_id)
        rule.update(change)
        if focus_id == "dnd":
            window.save_prefs(dnd_schedule=rule)
        else:
            window.save_prefs(focus_settings=notify_rules.with_focus_setting(now, focus_id, "schedule", rule))

    def save_allowed(focus_id, app, on):
        now = style.prefs()
        allowed = [a for a in notify_rules.allowed_apps(now, focus_id) if a != app]
        if on:
            allowed.append(app)
        window.save_prefs(focus_settings=notify_rules.with_focus_setting(now, focus_id, "allow", sorted(allowed)))

    groups = []
    active = notify_rules.active_focus(prefs)
    for focus_id, name, icon, _start in notify_rules.FOCUSES:
        rule = notify_rules.schedule(prefs, focus_id)
        on = switch(active == focus_id, lambda value, f=focus_id: turn(f, value))
        on_switches[focus_id] = on
        head = row(name, on, FOCUS_ABOUT[focus_id])
        symbol = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR)
        head.get_child().pack_start(symbol, False, False, 0)
        head.get_child().reorder_child(symbol, 0)

        # Allowed apps: their banners still show while this Focus is on.
        allowed = notify_rules.allowed_apps(prefs, focus_id)
        if apps:
            flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=3,
                               min_children_per_line=2, column_spacing=6, row_spacing=2)
            flow.get_style_context().add_class("dials-flow")
            for app in sorted(apps, key=str.casefold):
                check = Gtk.CheckButton(label=app, active=app in allowed)
                check.connect("toggled", lambda c, f=focus_id, a=app: save_allowed(f, a, c.get_active()))
                flow.add(check)
            allow = row("Allowed apps", None, "Banners from these apps still show while it's on.")
            allow.get_child().get_children()[0].pack_start(flow, False, False, 4)
        else:
            allow = row("Allowed apps", None, "Apps show here once they've sent a notification.")

        # Turn on at set times, on the days chosen.
        start, end = _time_choice(rule["from"]), _time_choice(rule["to"])
        span = Gtk.Box(spacing=6)
        span.pack_start(Gtk.Label(label="From"), False, False, 0)
        span.pack_start(start, False, False, 0)
        span.pack_start(Gtk.Label(label="to"), False, False, 0)
        span.pack_start(end, False, False, 0)
        days = Gtk.Box(spacing=2)
        days.get_style_context().add_class("linked")
        days.get_style_context().add_class("dials-days")
        for number, letter in enumerate(notify_rules.DAY_NAMES):
            day = Gtk.ToggleButton(label=letter, active=number in rule["days"])
            day.set_tooltip_text(("Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                                  "Saturday", "Sunday")[number])

            def picked(_button, f=focus_id, box=days):
                chosen = [i for i, b in enumerate(box.get_children()) if b.get_active()]
                save_schedule(f, days=chosen)
            day.connect("toggled", picked)
            days.pack_start(day, False, False, 0)
        when = Gtk.Box(spacing=12)
        when.pack_start(span, False, False, 0)
        when.pack_start(days, False, False, 0)
        when.set_sensitive(rule["on"])

        def timed(value, f=focus_id, box=when):
            save_schedule(f, on=value)
            box.set_sensitive(value)
        start.connect("changed", lambda c, f=focus_id: save_schedule(f, **{"from": c.get_active_id()}))
        end.connect("changed", lambda c, f=focus_id: save_schedule(f, to=c.get_active_id()))
        times = row("Turn on at set times", switch(rule["on"], timed))
        times_detail = row("", when)
        groups.append(group(head, allow, times, times_detail))

    intro = Gtk.Label(label="A Focus hides banners so you can get on with things; they still collect in "
                            "the notification centre, and urgent ones always show. Turn one on here, from "
                            "Quick Settings or from the notification centre.", xalign=0, wrap=True)
    intro.get_style_context().add_class("dials-caption")
    return page("Focus", intro, *groups)


def _app_icon(icon):
    """A notifying app's icon for its row: a file or an icon name."""
    if icon and os.path.isabs(icon) and os.path.exists(icon):
        try:
            from gi.repository import GdkPixbuf

            return Gtk.Image.new_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(icon, 24, 24, True))
        except GLib.Error:
            pass
    name = icon if icon and not os.path.isabs(icon) else "preferences-system-notifications"
    image = Gtk.Image.new_from_icon_name(name, Gtk.IconSize.LARGE_TOOLBAR)
    image.set_pixel_size(24)
    return image


# ---- Screen Saver -----------------------------------------------------------------
SAVER_AFTER_CHOICES = (("0", "Never"), ("1", "1 minute"), ("2", "2 minutes"), ("3", "3 minutes"),
                       ("5", "5 minutes"), ("10", "10 minutes"), ("20", "20 minutes"), ("30", "30 minutes"))
SAVER_ABOUT = {
    "drift": "Soft lights drift over a dark sky.",
    "clock": "The time and date, large and quiet.",
    "album": "Your photos from Pictures, one after another.",
}


def screen_saver(window):
    from . import saver
    group, row, page, _slider, _switch = window.helpers
    name, after = saver.settings()
    flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=3,
                       column_spacing=12, row_spacing=12, homogeneous=True)
    buttons = {}
    about = Gtk.Label(label=SAVER_ABOUT[name], xalign=0)
    about.get_style_context().add_class("dials-caption")

    def choose(chosen):
        window.save_prefs(saver=chosen)
        for key, button in buttons.items():
            context = button.get_style_context()
            (context.add_class if key == chosen else context.remove_class)("dials-chosen")
        about.set_text(SAVER_ABOUT[chosen])

    for key, title in saver.SAVERS:
        button = Gtk.Button()
        button.get_style_context().add_class("dials-choice")
        if key == name:
            button.get_style_context().add_class("dials-chosen")
        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        try:
            picture = Gtk.Image.new_from_surface(saver.still(key, 176, 110))
        except Exception:  # noqa: BLE001 - the name alone will do
            picture = Gtk.Image.new_from_icon_name("video-display-symbolic", Gtk.IconSize.DIALOG)
        inner.pack_start(picture, False, False, 0)
        inner.pack_start(Gtk.Label(label=title), False, False, 0)
        button.add(inner)
        button.connect("clicked", lambda _b, k=key: choose(k))
        flow.add(button)
        buttons[key] = button

    start = Gtk.ComboBoxText()
    for value, label in SAVER_AFTER_CHOICES:
        start.append(value, label)
    start.set_active_id(str(after))
    if not start.get_active_id():
        start.set_active_id("0")
    start.connect("changed", lambda c: window.save_prefs(saver_after=int(c.get_active_id())))

    preview = Gtk.Button(label="Preview", halign=Gtk.Align.START)

    def show_preview(_button):
        program = shutil.which("freemac-screensaver")
        command = [program] if program else ["python3", "-m", "freemac_shell.saver"]
        try:
            subprocess.Popen(command + [saver.settings()[0]])
        except OSError:
            pass
    preview.connect("clicked", show_preview)

    return page("Screen Saver", flow, about, preview, group(
        row("Start the screen saver after", start,
            "When nothing has been touched for this long. Move the pointer or press a key to end it. "
            "If the screen should lock (Dials > Power), it locks when the screen saver ends."),
    ))
