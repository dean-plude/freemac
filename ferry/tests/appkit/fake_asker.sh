#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# A stand-in for freemac-allow-control in accessibility.m (freemac 1.215,
# Ferry 0.41.0): freemac's own program, answering Allow as the user would,
# with no dialog. It notes each time it is asked.
here=$(cd "$(dirname "$0")" && pwd)
echo "asked $*" | sed 's/--app-id [^ ]*/--app-id APP/' >> "$HOME/asker.log"
PYTHONPATH="$here/../../../shell" exec python3 -m freemac_shell.window_control --answer allow "$@"
