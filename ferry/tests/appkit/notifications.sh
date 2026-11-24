#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Run inside dbus-run-session (on a bus with no services of its own):
# starts fake_notify.py, the stand-in notification server and Dock, then a
# notification test program, and prints what the server was sent, a line of
# dashes, and the program's own output.
#
#   notifications.sh PYTHON FERRY PROGRAM LOG [fake_notify.py options...]
set -u
python=$1; ferry=$2; exe=$3; log=$4; shift 4
here=$(dirname "$0")
rm -f "$log.ready" "$log.server"
"$python" "$here/fake_notify.py" --log "$log.server" --ready "$log.ready" "$@" 2> "$log.server.err" &
fake=$!
for i in $(seq 100); do
    [ -e "$log.ready" ] && break
    "$python" -c "import time; time.sleep(0.05)"
done
[ -e "$log.ready" ] || { echo "the stand-in server didn't start"; cat "$log.server.err"; kill $fake; exit 1; }
"$ferry" "$exe" > "$log" 2> "$log.err"
status=$?
"$python" -c "import time; time.sleep(0.2)"
kill $fake
wait $fake
cat "$log.server"
echo "----"
cat "$log"
echo "app exit=$status"
