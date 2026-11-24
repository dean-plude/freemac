#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# A stand-in for pw-play in more_controls.m: it notes what it was given
# (the volume and the file's name) and then "plays" for a moment.
name=$(basename "$2" | sed 's/^ferry-sound-[0-9]*-0x[0-9a-f]*/ferry-sound/')
printf '%s %s\n' "$1" "$name" >> "$FERRY_FAKE_PLAYER_LOG"
exec sleep 0.3
