#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes sdk/include/module.modulemap (freemac 1.222, Ferry 0.46.0): a
# module for each of Ferry's frameworks, holding every header in its
# folder, so that "@import Foundation;" works and "#import
# <AppKit/AppKit.h>" is a module import when modules are on, as on a Mac.
# Each module links its framework, as a Mac's do; HIServices' is
# ApplicationServices, AudioToolbox's CoreAudio (1.232), as are AudioUnit's and
# CoreAudioTypes' (1.234), and CommonCrypto's is libSystem. The C library's
# headers stay outside any module; Darwin's and ObjectiveC's submodules
# (freemac 1.225, Ferry 0.49.0), for "@import Darwin.C.time;" and
# "@import ObjectiveC.runtime;", each hold a header of their own folder
# that includes the C one, so that a plain "#include <time.h>" stays
# textual.
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
for dir in Accelerate AppKit ApplicationServices AudioToolbox AudioUnit AVFoundation Carbon CFNetwork CloudKit \
           Cocoa CommonCrypto CoreAudio CoreAudioTypes CoreData CoreFoundation CoreGraphics CoreImage CoreServices \
           CoreText DiskArbitration EventKit Foundation HIServices ImageIO IOKit IOSurface JavaScriptCore Metal \
           MetalKit Network Quartz QuartzCore QuickLook \
           ScriptingBridge Security \
           ServiceManagement SystemConfiguration UniformTypeIdentifiers UserNotifications WebKit; do
    [ -d "$inc/$dir" ] || continue
    case $dir in
        HIServices) link=ApplicationServices ;;
        AudioToolbox|AudioUnit|CoreAudioTypes) link=CoreAudio ;;
        CommonCrypto) link= ;;
        MetalKit) link=Metal ;;
        *) link=$dir ;;
    esac
    echo
    echo "module $dir [system] {"
    # Carbon's one header is HIToolbox's too, for Swift's "import
    # Carbon.HIToolbox" (freemac 1.230); a submodule that isn't explicit
    # comes with "import Carbon"
    if [ "$dir" = Carbon ]; then
        echo "    module HIToolbox {"
        echo "        header \"Carbon/Carbon.h\""
        echo "        export *"
        echo "    }"
        echo "    export *"
        echo "    link framework \"Carbon\""
        echo "}"
        continue
    fi
    # the umbrella header first, then the rest in order; a header that only
    # brings in the umbrella is a submodule of that name, for Swift's
    # "import AppKit.NSMenu" (freemac 1.230)
    if [ -f "$inc/$dir/$dir.h" ]; then echo "    header \"$dir/$dir.h\""; fi
    for h in $(cd "$inc/$dir" && ls *.h | LC_ALL=C sort); do
        [ "$h" = "$dir.h" ] && continue
        if grep -q '^/\* Ferry submodule' "$inc/$dir/$h"; then
            echo "    module ${h%.h} {"
            echo "        header \"$dir/$h\""
            echo "        export *"
            echo "    }"
        else
            echo "    header \"$dir/$h\""
        fi
    done
    echo "    export *"
    if [ -n "$link" ]; then echo "    link framework \"$link\""; fi
    echo "}"
done

# Dispatch and os.log, which Swift imports by those names (freemac 1.230):
# Ferry's Dispatch and os overlays sit on them. Both are libSystem's.
if [ -f "$inc/dispatch/dispatch.h" ]; then
    echo
    echo "module Dispatch [system] {"
    echo "    header \"dispatch/dispatch.h\""
    echo "    export *"
    echo "}"
fi
if [ -f "$inc/os/log.h" ]; then
    echo
    echo "module os [system] {"
    echo "    module log {"
    echo "        header \"os/log.h\""
    echo "        export *"
    echo "    }"
    echo "}"
fi

# Darwin: the C library, which is libSystem, so it links nothing more
if [ -d "$inc/Darwin" ]; then
    echo
    echo "module Darwin [system] {"
    for h in $(cd "$inc/Darwin" && ls *.h | LC_ALL=C sort); do
        echo "    module ${h%.h} {"
        echo "        header \"Darwin/$h\""
        echo "        export *"
        echo "    }"
    done
    echo "    module C {"
    for h in $(cd "$inc/Darwin/C" && ls *.h | LC_ALL=C sort); do
        echo "        module ${h%.h} {"
        echo "            header \"Darwin/C/$h\""
        echo "            export *"
        echo "        }"
    done
    echo "    }"
    echo "}"
fi

# ObjectiveC: the runtime's headers, which link libobjc
if [ -d "$inc/ObjectiveC" ]; then
    echo
    echo "module ObjectiveC [system] {"
    # each submodule holds the runtime's own header (objc/NSObject.h), so
    # that a framework header's "#include <objc/NSObject.h>" imports it
    # rather than copying it: Swift then sees one NSObject, the one its
    # ObjectiveC overlay extends (freemac 1.227)
    for h in $(cd "$inc/ObjectiveC" && ls *.h | LC_ALL=C sort); do
        hdr=ObjectiveC/$h
        [ -f "$inc/objc/$h" ] && hdr=objc/$h
        echo "    module ${h%.h} {"
        echo "        header \"$hdr\""
        echo "        export *"
        echo "    }"
    done
    echo "    link \"objc\""
    echo "}"
fi
