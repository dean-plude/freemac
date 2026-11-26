#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs portal.m on a Wayland desktop of its own (freemac 1.240, Ferry 0.64.0):
#
#   portal_test.sh FERRY PROGRAM PRODUCER HOME PYTHON
#
# A session bus of its own (dbus-daemon), PipeWire and WirePlumber on it,
# two of PRODUCER (pw_producer.c) in the compositor's place, fake_portal.py
# answering for xdg-desktop-portal, and tools/fake_wayfire.py with one
# display and one window; no X display. The program runs in a home of its
# own, asking with appkit/fake_asker.sh; the portal's dialog answers "the
# user picked" each time but the fourth, where the user says no. Then it
# runs once more with FERRY_PIPEWIRE naming a library that isn't there.
# The runtime folder is a short one in /tmp: PipeWire's and Wayfire's
# sockets have to fit in a socket address.
set -u
ferry=$1; exe=$2; producer=$3; home=$4; python=$5
here=$(cd "$(dirname "$0")/.." && pwd)
rm -rf "$home"; mkdir -p "$home/config"; chmod 700 "$home"
run=$(mktemp -d /tmp/ferry-wl.XXXXXX)
pids=
cleanup() {
    for p in $pids; do kill "$p" 2> /dev/null; done
    for p in $pids; do wait "$p" 2> /dev/null; done
    rm -rf "$run"
}
trap cleanup EXIT
export XDG_RUNTIME_DIR="$run" DBUS_SESSION_BUS_ADDRESS="unix:path=$run/bus" HOME="$home" \
    XDG_CONFIG_HOME="$home/config" PIPEWIRE_RUNTIME_DIR="$run"
unset PIPEWIRE_REMOTE DISPLAY WAYLAND_DISPLAY
dbus-daemon --session --nofork --nopidfile --address="$DBUS_SESSION_BUS_ADDRESS" > "$home/dbus.log" 2>&1 &
pids="$pids $!"
for i in $(seq 1 50); do [ -S "$run/bus" ] && break; sleep 0.1; done
pipewire > "$home/pipewire.log" 2>&1 &
pids="$pids $!"
for i in $(seq 1 50); do [ -S "$run/pipewire-0" ] && break; sleep 0.1; done
wireplumber > "$home/wireplumber.log" 2>&1 &
pids="$pids $!"
node() { # NAME FORMAT W H PATTERN: the producer's node id
    "$producer" "$@" > "$home/$1.out" 2> "$home/$1.err" &
    pids="$pids $!"
    for i in $(seq 1 100); do grep -q "^node" "$home/$1.out" 2> /dev/null && break; sleep 0.1; done
    sed -n 's/^node //p' "$home/$1.out"
}
monitor=$(node screen BGRx 640 400 quarters)
window=$(node cyan RGBx 200 100 cyan)
if [ -z "$monitor" ] || [ -z "$window" ]; then
    echo "the producers didn't start"
    exit 1
fi
: > "$home/portal.log"
"$python" -I "$here/screencapture/fake_portal.py" "$home/portal.log" --monitor "$monitor" --window "$window" \
    --size 320x200 --answers ok,ok,ok,cancel > "$home/portal.out" 2> "$home/portal.err" &
pids="$pids $!"
for i in $(seq 1 100); do grep -q "^ready" "$home/portal.out" 2> /dev/null && break; sleep 0.1; done
cat > "$home/scene.json" << 'EOF'
{"outputs": [{"id": 1, "name": "eDP-1", "geometry": {"x": 0, "y": 0, "width": 320, "height": 200},
              "workarea": {"x": 0, "y": 0, "width": 320, "height": 200}}],
 "views": [{"id": 7, "app-id": "org.example.Viewer", "title": "Cyan", "output": 1,
            "geometry": {"x": 100, "y": 50, "width": 100, "height": 50}, "focus": 10}],
 "pids": {"7": 4343}}
EOF
sock="$run/wayfire.sock"
python3 -I "$here/tools/fake_wayfire.py" "$sock" "$home/wayfire.log" --scene "$home/scene.json" \
    > "$home/wayfire.out" 2>&1 &
pids="$pids $!"
for i in $(seq 1 50); do [ -S "$sock" ] && break; sleep 0.1; done
go() {
    env -u FERRY_CAPTURE -u FERRY_PIPEWIRE WAYLAND_DISPLAY=wayland-ferry-test NO_AT_BRIDGE=1 GDK_SCALE= \
        FERRY_WAYFIRE_SOCKET="$sock" FERRY_ACCESS_ASKER="$here/appkit/fake_asker.sh" \
        FERRY_TEST_PORTAL_LOG="$home/portal.log" "$@"
}
go timeout 120 "$ferry" "$exe"
status=$?
go FERRY_PIPEWIRE=/nonexistent/libpipewire-0.3.so.0 timeout 60 "$ferry" "$exe" missing 2>&1
[ $? -eq 0 ] || status=1
exit $status
