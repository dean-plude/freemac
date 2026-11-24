#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs one test program against the stand-in Wayfire (tests/tools/
# fake_wayfire.py), in a home and runtime folder of its own, with no display
# (freemac 1.215, Ferry 0.41.0):
#
#   wayfire_test.sh FERRY PROGRAM HOME [fake_wayfire.py options] [-- program arguments]
#
# When the program asks whether it may control other windows, fake_asker.sh
# answers.
set -u
ferry=$1; exe=$2; home=$3; shift 3
fake_opts=
while [ $# -gt 0 ] && [ "$1" != -- ]; do fake_opts="$fake_opts $1"; shift; done
[ $# -gt 0 ] && shift
here=$(cd "$(dirname "$0")/.." && pwd)
rm -rf "$home"; mkdir -p "$home"
# a short runtime folder: a socket's path has room for about 100 characters
run=$(mktemp -d /tmp/ferry-wf.XXXXXX) || exit 1
sock="$run/wayfire.socket"
XDG_RUNTIME_DIR="$run" python3 -I "$here/tools/fake_wayfire.py" "$sock" "$home/wayfire.log" $fake_opts \
    2> "$home/fake.err" &
fake=$!
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -S "$sock" ] && break; sleep 0.1; done
env -u WAYLAND_DISPLAY -u DISPLAY -u WAYFIRE_SOCKET HOME="$home" XDG_CONFIG_HOME= XDG_RUNTIME_DIR="$run" \
    FERRY_WAYFIRE_SOCKET="$sock" FERRY_ACCESS_ASKER="$here/appkit/fake_asker.sh" timeout 60 "$ferry" "$exe" "$@"
status=$?
kill "$fake" 2> /dev/null
wait "$fake" 2> /dev/null
rm -rf "$run"
exit $status
