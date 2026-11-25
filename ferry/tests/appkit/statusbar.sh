#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Run inside dbus-run-session: starts the statusbar test program and does
# what a desktop's menu bar does with its items over D-Bus (reads them,
# reads their menus, clicks), printing what it sees. The program's own
# output follows, after a line of dashes.
set -u
ferry=$1; exe=$2; log=$3
"$ferry" "$exe" > "$log" 2> "$log.err" &
app=$!
name=
for i in $(seq 100); do
    for n in $(gdbus call --session -d org.freedesktop.DBus -o /org/freedesktop/DBus \
                   -m org.freedesktop.DBus.ListNames | grep -o "':1\.[0-9]*'" | tr -d "'"); do
        if gdbus introspect --session -d "$n" -o /StatusNotifierItem/2 2> /dev/null | grep -q StatusNotifierItem; then
            name=$n
        fi
    done
    [ -n "$name" ] && break
    python3 -c "import time; time.sleep(0.1)"
done
[ -n "$name" ] || { echo "no items on the bus"; kill $app; exit 1; }
call() { gdbus call --session -d "$name" "$@"; }
prop() { call -o "$1" -m org.freedesktop.DBus.Properties.Get org.kde.StatusNotifierItem "$2"; }
for p in Category Title Status ItemIsMenu Menu ToolTip; do
    echo "item 1 $p: $(prop /StatusNotifierItem/1 $p)"
done
echo "item 1 Id: $(prop /StatusNotifierItem/1 Id | sed 's/-1/-N/')"
for i in 1 2; do
    sizes=$(prop /StatusNotifierItem/$i IconPixmap | grep -oE '\([0-9]+, [0-9]+, ' | tr -d '(,' | tr '\n' ' ')
    ink=no; prop /StatusNotifierItem/$i IconPixmap | grep -q '0xff' && ink=yes
    echo "item $i pictures (width height): $sizes; drawn: $ink"
done
echo "item 2 ItemIsMenu: $(prop /StatusNotifierItem/2 ItemIsMenu), Menu: $(prop /StatusNotifierItem/2 Menu)"
menu() { call -o /MenuBar/1 -m com.canonical.dbusmenu."$@"; }
echo "version: $(call -o /MenuBar/1 -m org.freedesktop.DBus.Properties.Get com.canonical.dbusmenu Version)"
echo "about to show: $(menu AboutToShow 0)"
echo "layout: $(menu GetLayout -- 0 -1 '[]' | sed 's/^(uint32 [0-9]*, /(rev, /')"
echo "branch: $(menu GetLayout -- 5 -1 '[]' | sed 's/^(uint32 [0-9]*, /(rev, /')"
echo "properties: $(menu GetGroupProperties '[3, 4]' '[]')"
menu Event 3 clicked '<0>' 0 > /dev/null
menu Event 4 clicked '<0>' 0 > /dev/null
menu Event 7 clicked '<0>' 0 > /dev/null
python3 -c "import time; time.sleep(0.3)"
echo "after toggle: $(menu GetGroupProperties '[3]' '[]')"
call -o /StatusNotifierItem/1 -m org.kde.StatusNotifierItem.Activate 0 0 > /dev/null
call -o /StatusNotifierItem/2 -m org.kde.StatusNotifierItem.Activate 300 5 > /dev/null
python3 -c "import time; time.sleep(0.3)"
echo "item 2 Status after click: $(prop /StatusNotifierItem/2 Status)"
menu Event 9 clicked '<0>' 0 > /dev/null
for i in $(seq 50); do
    kill -0 $app 2> /dev/null || break
    python3 -c "import time; time.sleep(0.1)"
done
if kill -0 $app 2> /dev/null; then echo "still running after Quit"; kill $app; fi
wait $app
echo "app exit=$?"
echo "----"
cat "$log"
