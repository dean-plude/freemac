# SPDX-License-Identifier: GPL-3.0-or-later
"""freemac's start-up sound: four soft bell notes as the desktop first comes
up after the computer starts (not again on a later log-in until the next
start). Turned off and on in Dials > Sound.

    freemac-startup-sound            play it, if it's on and not yet played since start-up
    freemac-startup-sound --preview  play it now
    freemac-startup-sound --on/--off

The sound is made by art/sounds/make-sounds.py. Original freemac code.
"""
import os
import shutil
import subprocess
import sys

SOUND = "/usr/share/sounds/freemac/startup.wav"
OFF = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
                   "freemac", "startup-sound-off")
# /tmp is emptied at each start-up, so this marks "already played since then".
PLAYED = f"/tmp/.freemac-startup-sound-{os.getuid()}"
PLAYERS = (("pw-play",), ("paplay",), ("aplay", "-q"))


def enabled():
    return not os.path.exists(OFF)


def set_enabled(on):
    if on:
        try:
            os.unlink(OFF)
        except FileNotFoundError:
            pass
    else:
        os.makedirs(os.path.dirname(OFF), exist_ok=True)
        with open(OFF, "w") as marker:
            marker.write("The start-up sound is off (Dials > Sound).\n")


def play(wait=False):
    """Play the sound with the first player found; False if none could."""
    if not os.path.exists(SOUND):
        return False
    for player in PLAYERS:
        if shutil.which(player[0]):
            try:
                proc = subprocess.Popen([*player, SOUND], stdin=subprocess.DEVNULL,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError:
                continue
            if wait:
                proc.wait(timeout=10)
            return True
    return False


def first_since_start_up():
    try:
        fd = os.open(PLAYED, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return False
    except OSError:
        return True
    os.close(fd)
    return True


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if "--on" in args or "--off" in args:
        set_enabled("--on" in args)
    elif "--preview" in args:
        play(wait=True)
    elif enabled() and first_since_start_up():
        play(wait=True)


if __name__ == "__main__":
    main()
