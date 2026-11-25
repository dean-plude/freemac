#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   apps/keycastr.sh [WORK]
#
# KeyCastr (github.com/keycastr/keycastr, BSD-3-Clause), which shows the
# keys pressed, built for Ferry (freemac 1.236, Ferry 0.60.0; it first ran
# in freemac 1.224). It is fetched at the commit freemac's rounds were
# built from, with its two submodules, ShortcutRecorder and Sparkle 2, at
# the commits it pins. They are built as frameworks, then its KCVisualizer
# framework, its three visualizers as plug-ins (Default, Minimal and
# Svelte, in Contents/PlugIns) and the app. Run it with
#
#   ./ferry WORK/build/KeyCastr/KeyCastr.app
#
# See apps/recipe.sh for WORK and what a recipe needs.
recipe_name=keycastr
. "$(dirname "$0")/recipe.sh"

fetch keycastr https://github.com/keycastr/keycastr 1e552a150afdf8f73fa4a12ba3cca1bbf09eb6ab
submodule keycastr keycastr/Externals/ShortcutRecorder https://github.com/Kentzo/ShortcutRecorder
submodule keycastr keycastr/Externals/Sparkle https://github.com/sparkle-project/Sparkle

build=$work/build/KeyCastr
rm -rf "$build"
mkdir -p "$build"
k=$src/keycastr/keycastr
sr=$k/Externals/ShortcutRecorder
sp=$k/Externals/Sparkle

xcbuild "$sr/ShortcutRecorder.xcodeproj" ShortcutRecorder.framework --name ShortcutRecorder --kind framework \
    --ldflags '-framework Cocoa -framework Carbon'
sparkle2 "$sp"
xcbuild "$k/KeyCastr.xcodeproj" KCVisualizer --ldflags '-framework Cocoa -framework QuartzCore'
for v in KCDefaultVisualizer Minimal Svelte; do
    xcbuild "$k/KeyCastr.xcodeproj" "$v" --kind bundle --ext kcplugin \
        --ldflags '-framework Cocoa -framework QuartzCore -framework KCVisualizer'
done
xcbuild "$k/KeyCastr.xcodeproj" KeyCastr \
    --ldflags '-framework Cocoa -framework Carbon -framework ApplicationServices -framework QuartzCore
               -framework Quartz -framework KCVisualizer -framework ShortcutRecorder -framework Sparkle'
a=$build/KeyCastr.app
embed "$a" "$build/KCVisualizer.framework" "$build/ShortcutRecorder.framework" "$build/Sparkle.framework"
mkdir -p "$a/Contents/PlugIns"
for v in KCDefaultVisualizer Minimal Svelte; do cp -R "$build/$v.kcplugin" "$a/Contents/PlugIns/"; done
say "done: $a"
