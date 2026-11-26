#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs capture.m on an X display of its own (freemac 1.238, Ferry 0.62.0):
#
#   capture_test.sh FERRY PROGRAM HOME [no-shm]
#
# Xvfb at 320x240 with no window manager and a black screen, another copy
# of the program showing another app's window, and the program itself in a
# home of its own, asking with appkit/fake_asker.sh (freemac's own
# freemac-allow-control answering Allow), and Core Audio's null device,
# whose recording hears what it plays. With no-shm the screen is read
# with XGetImage alone, as when the X server is on another machine.
set -u
ferry=$1; exe=$2; home=$3
noshm=; [ "${4:-}" = no-shm ] && noshm=1
here=$(cd "$(dirname "$0")/.." && pwd)
rm -rf "$home"; mkdir -p "$home"; chmod 700 "$home"
Xvfb -displayfd 3 -screen 0 320x240x24 -nolisten tcp -br 3> "$home/display" > "$home/xvfb.log" 2>&1 &
xvfb=$!
for i in $(seq 1 50); do [ -s "$home/display" ] && break; sleep 0.1; done
display=":$(cat "$home/display")"
run() {
    env -u WAYLAND_DISPLAY -u FERRY_CAPTURE -u FERRY_CAPTURE_NO_SHM -u FERRY_AUDIO_INPUT_FILE -u FERRY_AUDIO_OUTPUT_FILE \
        DISPLAY="$display" GDK_BACKEND=x11 NO_AT_BRIDGE=1 HOME="$home" XDG_RUNTIME_DIR="$home" XDG_CONFIG_HOME= \
        XDG_CACHE_HOME= XDG_DATA_HOME= GDK_SCALE= FERRY_ACCESS_ASKER="$here/appkit/fake_asker.sh" FERRY_AUDIO=null \
        ${noshm:+FERRY_CAPTURE_NO_SHM=1} "$@"
}
run timeout 120 "$ferry" "$exe" other > "$home/other.out" 2> "$home/other.err" &
other=$!
for i in $(seq 1 200); do grep -q "^shown" "$home/other.out" 2> /dev/null && break; sleep 0.1; done
FERRY_TEST_OTHER_PID=$(sed -n 's/^shown //p' "$home/other.out") run timeout 120 "$ferry" "$exe"
status=$?
kill "$other" 2> /dev/null; wait "$other" 2> /dev/null
kill "$xvfb" 2> /dev/null; wait "$xvfb" 2> /dev/null
exit $status
