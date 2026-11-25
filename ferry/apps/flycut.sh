#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   apps/flycut.sh [WORK]
#
# Flycut (github.com/TermiT/Flycut, MIT), a clipboard history in the menu
# bar, built for Ferry (freemac 1.236, Ferry 0.60.0; it first ran in
# freemac 1.223). It is fetched at the commit freemac's rounds were built
# from, with its CloudKit sync framework (MJCloudKitUserDefaultsSync, in its
# own repository) built first. Run it with
#
#   ./ferry WORK/build/Flycut/Flycut.app
#
# See apps/recipe.sh for WORK and what a recipe needs.
recipe_name=flycut
. "$(dirname "$0")/recipe.sh"

fetch Flycut https://github.com/TermiT/Flycut 8a2401470eda37de3e5774a5aa8bb2d249c8bbf6

build=$work/build/Flycut
rm -rf "$build"
mkdir -p "$build"
f=$src/Flycut

xcbuild "$f/MJCloudKitUserDefaultsSync/MJCloudKitUserDefaultsSync.xcodeproj" MJCloudKitUserDefaultsSync \
    --ldflags '-framework Foundation -framework CloudKit -framework Security'
xcbuild "$f/Flycut.xcodeproj" Flycut --cflags '-Wno-error=int-conversion' \
    --ldflags '-framework Cocoa -framework Carbon -framework ApplicationServices -framework ServiceManagement
               -framework CloudKit -framework MJCloudKitUserDefaultsSync'
embed "$build/Flycut.app" "$build/MJCloudKitUserDefaultsSync.framework"
say "done: $build/Flycut.app"
