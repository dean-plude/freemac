#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   apps/spectacle.sh [WORK]
#
# Spectacle (github.com/eczarny/spectacle, MIT), window moving and sizing
# by shortcut from the menu bar, built for Ferry (freemac 1.236, Ferry
# 0.60.0; it first ran in freemac 1.223). It is fetched at the commit
# freemac's rounds were built from, with Sparkle 1.22.0, the version its
# Cartfile.resolved names, built first. Run it with
#
#   ./ferry WORK/build/Spectacle/Spectacle.app
#
# See apps/recipe.sh for WORK and what a recipe needs.
recipe_name=spectacle
. "$(dirname "$0")/recipe.sh"

fetch spectacle https://github.com/eczarny/spectacle e75c341ec2cba179c1bb8aa726a870c4132207df

build=$work/build/Spectacle
rm -rf "$build"
mkdir -p "$build"

sparkle1 d5222353e6d6ee7baf4c18711e5b897fe2ed886a 1.22.0
xcbuild "$src/spectacle/Spectacle.xcodeproj" Spectacle --cflags '-Wno-error=int-conversion' \
    --ldflags '-framework Cocoa -framework Carbon -framework ApplicationServices -framework ServiceManagement
               -framework JavaScriptCore -framework Sparkle'
embed "$build/Spectacle.app" "$build/Sparkle.framework"
say "done: $build/Spectacle.app"
