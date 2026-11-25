#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   apps/macpass.sh [WORK]
#
# MacPass (github.com/MacPass/MacPass, GPL-3.0), a KeePass password
# manager, built for Ferry (freemac 1.236, Ferry 0.60.0; it first ran in
# freemac 1.225). It is fetched at the commit freemac's rounds were built
# from, with DDHotKey (its submodule, at the commit it pins) and the
# frameworks its Cartfile names, at the commits those rounds built:
# KissXML and TransformerKit at the commits its Cartfile.resolved pins,
# KeePassKit and HNHUi a little past the 3.3.2 and 6.0.1 it asks for at
# least, and Sparkle 2.6.4, which its Cartfile.resolved takes as a built
# binary, built from its source. Run it with
#
#   ./ferry WORK/build/MacPass/MacPass.app
#
# See apps/recipe.sh for WORK and what a recipe needs.
recipe_name=macpass
. "$(dirname "$0")/recipe.sh"

fetch MacPass https://github.com/MacPass/MacPass 98cc411ac524bbb6f171775e06ca55c9e577f4cc
submodule MacPass DDHotKey https://github.com/mstarke/DDHotKey
fetch KissXML https://github.com/MacPass/KissXML 503fc012b73a4507965019720cbf1c157e849657
fetch TransformerKit https://github.com/MacPass/TransformerKit 3232b04c568df7f98b33ceb21a2090a9ccbc2065
fetch KeePassKit https://github.com/MacPass/KeePassKit b5cf50ee4ebd67cb355792d7813965fe3ac7125e
fetch HNHUi https://github.com/mstarke/HNHUi 83e63ed1e005bdc3404b7952f9b88d06381ab49d
submodule KeePassKit Argon2 https://github.com/P-H-C/phc-winner-argon2
fetch Sparkle https://github.com/sparkle-project/Sparkle 0ef1ee0220239b3776f433314515fd849025673f

build=$work/build/MacPass
rm -rf "$build"
mkdir -p "$build"

sparkle2 "$src/Sparkle"
xcbuild "$src/KissXML/KissXML.xcodeproj" "KissXML (macOS)" --name KissXML \
    --ldflags '-framework Foundation -lxml2'
xcbuild "$src/TransformerKit/TransformerKit.xcodeproj" "TransformerKit macOS" --name TransformerKit \
    --ldflags '-framework Foundation -framework Security'
xcbuild "$src/KeePassKit/KeePassKit.xcodeproj" "KeePassKit macOS" --name KeePassKit \
    --ldflags '-framework Cocoa -framework Security -framework KissXML -framework TransformerKit -lz'
xcbuild "$src/HNHUi/HNHUi.xcodeproj" HNHUi --ldflags '-framework Cocoa'
xcbuild "$src/MacPass/MacPass.xcodeproj" MacPass \
    --ldflags '-framework Cocoa -framework Carbon -framework Security -framework QuartzCore -framework CoreImage
               -framework UniformTypeIdentifiers
               -framework KeePassKit -framework KissXML -framework TransformerKit -framework HNHUi -framework Sparkle'
a=$build/MacPass.app
embed "$a" "$build/KeePassKit.framework" "$build/KissXML.framework" "$build/TransformerKit.framework" \
    "$build/HNHUi.framework" "$build/Sparkle.framework"
say "done: $a"
