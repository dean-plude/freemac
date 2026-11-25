#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   apps/shiftit.sh [WORK]
#
# ShiftIt (github.com/fikovnik/ShiftIt, GPL-3.0), which moves and sizes
# other apps' windows from the menu bar, built for Ferry (freemac 1.236,
# Ferry 0.60.0; it first ran in freemac 1.223). It is fetched at the commit
# freemac's rounds were built from, and its "ShiftIt NoX11" target is built,
# the one without the X11 driver. ShortcutRecorder is the framework
# ShiftIt's repository carries built (an open-source one, from 2011); its
# updater is Sparkle 1.22.0, built from source as for Spectacle. That target
# copies no Localizable.strings, so the ShiftIt target's are copied in. Run
# it with
#
#   ./ferry WORK/build/ShiftIt/ShiftIt.app
#
# See apps/recipe.sh for WORK and what a recipe needs.
recipe_name=shiftit
. "$(dirname "$0")/recipe.sh"

fetch ShiftIt https://github.com/fikovnik/ShiftIt fb7699aa491a6b81656f152f74b638bb6f9514eb

build=$work/build/ShiftIt
rm -rf "$build"
mkdir -p "$build"
s=$src/ShiftIt/ShiftIt

sparkle1 d5222353e6d6ee7baf4c18711e5b897fe2ed886a 1.22.0
rm -rf "$build/ShortcutRecorder.framework"
cp -R "$s/ShortcutRecorder.framework" "$build/"
xcbuild "$s/ShiftIt.xcodeproj" "ShiftIt NoX11" --name ShiftIt --cflags '-Wno-error=int-conversion' \
    --ldflags '-framework Cocoa -framework Carbon -framework ApplicationServices -framework ScriptingBridge
               -framework IOKit -framework ShortcutRecorder -framework Sparkle'
a=$build/ShiftIt.app
for l in "$s"/*.lproj; do
    [ -f "$l/Localizable.strings" ] || continue
    mkdir -p "$a/Contents/Resources/$(basename "$l")"
    cp "$l/Localizable.strings" "$a/Contents/Resources/$(basename "$l")/"
done
embed "$a" "$build/ShortcutRecorder.framework" "$build/Sparkle.framework"
say "done: $a"
