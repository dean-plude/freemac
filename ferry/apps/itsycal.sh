#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   apps/itsycal.sh [WORK]
#
# Itsycal (github.com/sfsam/Itsycal, MIT), a menu bar calendar, built for
# Ferry (freemac 1.236, Ferry 0.60.0; it first ran in freemac 1.232). It
# is fetched at its 0.29.0 tag's commit, with MASShortcut 2.4.0 and Sparkle
# 1.27.1, the versions its project takes, built from their source
# (Sparkle as for Spectacle). Its fonts, which it registers itself, are
# copied in with its resources. Run it with
#
#   ./ferry WORK/build/Itsycal/Itsycal.app
#
# and click its status item; its agenda reads freemac's own calendar and
# reminders files (Tide's and Nudge's) through Ferry's EventKit. See
# apps/recipe.sh for WORK and what a recipe needs.
recipe_name=itsycal
. "$(dirname "$0")/recipe.sh"

fetch Itsycal https://github.com/sfsam/Itsycal 287576c50d81574b465039119acad3fca2a5d9da
fetch MASShortcut https://github.com/cocoabits/MASShortcut 10001acbf66522a20dedfc6002b750b99e1dd982

build=$work/build/Itsycal
rm -rf "$build"
mkdir -p "$build"

sparkle1 7918c1c8fc68baa37917eeaa67286b077ad5e393 1.27.1
xcbuild "$src/MASShortcut/MASShortcut.xcodeproj" MASShortcut --ldflags '-framework Cocoa -framework Carbon'
xcbuild "$src/Itsycal/Itsycal.xcodeproj" Itsycal \
    --ldflags '-framework Cocoa -framework EventKit -framework AudioToolbox -framework CoreAudio -framework Carbon
               -framework QuartzCore -framework ScriptingBridge -framework UniformTypeIdentifiers
               -framework MASShortcut -framework Sparkle'
a=$build/Itsycal.app
mkdir -p "$a/Contents/Resources/Fonts"
cp "$src/Itsycal/Itsycal/Fonts/"* "$a/Contents/Resources/Fonts/"
embed "$a" "$build/MASShortcut.framework" "$build/Sparkle.framework"
say "done: $a"
