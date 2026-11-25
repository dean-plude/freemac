#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   swift/build-modules.sh [TOOLCHAIN]
#
# Builds Ferry's own Swift modules (freemac 1.227), after
# swift/build-runtime.sh has built Swift's runtime and standard library:
#
#   the overlays, which give the Objective-C frameworks the Swift side that
#   Swift code expects of them (swift/overlays/NAME/*.swift):
#       ObjectiveC     BOOL as Bool, selectors, NSObject's == and hashing
#       CoreGraphics   CGFloat and the geometry helpers
#       Foundation     String, Array, Dictionary and Set to and from their
#                      NS classes, Error and NSError, and the rest
#       AppKit         what AppKit's Swift side adds
#   SwiftUI           Ferry's own SwiftUI, drawn with AppKit (swift/SwiftUI)
#
# Each goes into the "swift" folder of Ferry's frameworks, as Swift's own
# libraries do on a Mac: /usr/lib/swift/libswiftNAME.dylib there, and its
# module in usr/lib/swift/macosx/NAME.swiftmodule for ferry-swiftc.
#
# The toolchain is the swift.org one build-runtime.sh used: the folder
# given, FERRY_SWIFT_TOOLCHAIN, or swift-frontend on PATH.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
dest=${FERRY_FRAMEWORKS:-$top/frameworks}/swift
res=$dest/usr/lib/swift
build=${FERRY_SWIFT_BUILD:-$here/build}/modules
sdk=$top/sdk
tc=${1:-${FERRY_SWIFT_TOOLCHAIN:-}}
if [ -n "$tc" ]; then frontend=$tc/usr/bin/swift-frontend
else frontend=$(command -v swift-frontend 2>/dev/null || true)
fi
[ -n "$frontend" ] && [ -x "$frontend" ] || { echo "build-modules: no Swift toolchain" >&2; exit 1; }
[ -f "$dest/libswiftCore.dylib" ] || { echo "build-modules: build Swift's runtime first (swift/build-runtime.sh)" >&2; exit 1; }
mkdir -p "$build"
# clang's modules of the SDK's headers, for this module map and these API notes
cache=$build/module-cache-$(cat "$sdk/include/module.modulemap" "$sdk"/include/*.apinotes | cksum | cut -d' ' -f1)

# module NAME LINK-FLAGS SOURCES...: compile one module and link its library,
# unless it is newer than its sources and the modules before it.
stamp=$build/.none
module() {
    name=$1 link=$2
    shift 2
    mod=$res/macosx/$name.swiftmodule
    lib=$dest/libswift$name.dylib
    if [ -f "$lib" ] && { [ ! -e "$stamp" ] || [ "$lib" -nt "$stamp" ]; } && [ -z "$(find "$@" -newer "$lib" | head -1)" ] &&
       [ -z "$(find "$sdk/include" -newer "$lib" \( -name '*.h' -o -name '*.modulemap' -o -name '*.apinotes' \) | head -1)" ]; then
        stamp=$lib
        return 0
    fi
    echo "build-modules: $name"
    mkdir -p "$mod"
    # shellcheck disable=SC2086
    "$frontend" -frontend -c "$@" -module-name "$name" -module-link-name "swift$name" -parse-as-library \
        -target x86_64-apple-macosx11.0 -resource-dir "$res" -sdk "$sdk" -O -enable-objc-interop \
        -swift-version 5 -Xcc -nostdlibinc -Xcc -isystem -Xcc "$sdk/include" \
        -Xcc -fmodules-validate-system-headers -I "$res/macosx" \
        -module-cache-path "$cache" -runtime-compatibility-version none \
        -disable-implicit-concurrency-module-import -disable-implicit-string-processing-module-import \
        -disable-autolinking-runtime-compatibility-dynamic-replacements \
        -disable-autolinking-runtime-compatibility-concurrency \
        -enable-library-evolution -emit-module-path "$mod/x86_64-apple-macos.swiftmodule" \
        -emit-module-interface-path "$mod/x86_64-apple-macos.swiftinterface" \
        -o "$build/$name.o"
    # shellcheck disable=SC2086
    "$sdk/ferry-cc" -dynamiclib -install_name "/usr/lib/swift/libswift$name.dylib" -o "$lib" "$build/$name.o" \
        -L"$dest" -F"${FERRY_FRAMEWORKS:-$top/frameworks}" -lobjc $link 2>&1 | grep -v 'which is newer than target minimum' || true
    [ -f "$lib" ] && [ "$lib" -nt "$build/$name.o" ] || { echo "build-modules: $name didn't link" >&2; exit 1; }
    stamp=$lib
}

o=$here/overlays
module ObjectiveC "-lswiftCore" "$o"/ObjectiveC/*.swift
module CoreGraphics "-lswiftCore -framework CoreGraphics" "$o"/CoreGraphics/*.swift
if [ -d "$o/Foundation" ] && [ -n "$(ls "$o/Foundation")" ]; then
    module Foundation "-lswiftCore -framework Foundation" "$o"/Foundation/*.swift
fi
if [ -d "$o/AppKit" ] && [ -n "$(ls "$o/AppKit")" ]; then
    module AppKit "-lswiftCore -framework AppKit" "$o"/AppKit/*.swift
fi
if [ -d "$here/SwiftUI" ]; then
    module SwiftUI "-lswiftCore -lswiftObjectiveC -lswiftCoreGraphics -lswiftFoundation -lswiftDarwin -framework AppKit" "$here"/SwiftUI/*.swift
fi
echo "build-modules: done; Ferry's Swift modules are in $res/macosx"
