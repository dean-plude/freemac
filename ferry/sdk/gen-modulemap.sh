#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes sdk/include/module.modulemap (freemac 1.222, Ferry 0.46.0): a
# module for each of Ferry's frameworks, holding every header in its
# folder, so that "@import Foundation;" works and "#import
# <AppKit/AppKit.h>" is a module import when modules are on, as on a Mac.
# Each module links its framework, as a Mac's do; HIServices' is
# ApplicationServices, and CommonCrypto's is libSystem. The C library's
# headers stay outside any module.
#
#   sdk/gen-modulemap.sh sdk/include > sdk/include/module.modulemap
set -eu
inc=$1
cat << 'EOF'
// SPDX-License-Identifier: GPL-3.0-or-later
// Ferry SDK: a module for each of Ferry's frameworks, for "@import
// Foundation;" and the like (freemac 1.222, Ferry 0.46.0). Written by
// sdk/gen-modulemap.sh; run it again after adding a header.
EOF
for dir in AppKit ApplicationServices CFNetwork Carbon Cocoa CommonCrypto CoreData CoreFoundation CoreGraphics \
           CloudKit CoreServices CoreText Foundation HIServices IOKit ImageIO JavaScriptCore Quartz QuartzCore QuickLook \
           ScriptingBridge Security \
           ServiceManagement SystemConfiguration UserNotifications WebKit; do
    [ -d "$inc/$dir" ] || continue
    case $dir in
        HIServices) link=ApplicationServices ;;
        CommonCrypto) link= ;;
        *) link=$dir ;;
    esac
    echo
    echo "module $dir [system] {"
    # the umbrella header first, then the rest in order
    if [ -f "$inc/$dir/$dir.h" ]; then echo "    header \"$dir/$dir.h\""; fi
    for h in $(cd "$inc/$dir" && ls *.h | LC_ALL=C sort); do
        [ "$h" = "$dir.h" ] || echo "    header \"$dir/$h\""
    done
    echo "    export *"
    if [ -n "$link" ]; then echo "    link framework \"$link\""; fi
    echo "}"
done
