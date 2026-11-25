#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   swift/build-runtime.sh SWIFT_SOURCE [TOOLCHAIN]
#
# Builds the Swift runtime and standard library for an Intel Mac (freemac
# 1.227), from the open-source Swift project's own sources
# (github.com/swiftlang/swift, at the release tag that matches the
# toolchain's compiler: swift-6.1.3-RELEASE for Swift 6.1.3), with Ferry's
# SDK, into Ferry's frameworks folder:
#
#   frameworks/swift/libswiftCore.dylib                the runtime and the standard library
#   frameworks/swift/libswiftSwiftOnoneSupport.dylib   what unoptimized programs link
#   frameworks/swift/usr/lib/swift/                    the compiler's resource folder for them:
#       macosx/Swift.swiftmodule/x86_64-apple-macos.{swiftmodule,swiftinterface}
#       macosx/SwiftOnoneSupport.swiftmodule/...
#       shims/                                         SwiftShims, as a toolchain lays them out
#       clang                                          the toolchain's clang headers (a link)
#
# The runtime's C++ and Objective-C++ are compiled with ferry-cc, as any
# Mac program's are, and the Swift parts with the toolchain's
# swift-frontend aimed at x86_64-apple-macosx, so libswiftCore.dylib is a
# Mac library like a Mac's /usr/lib/swift/libswiftCore.dylib, with
# Objective-C interoperability on, and Ferry loads it for programs that
# link /usr/lib/swift/libswiftCore.dylib (src/swiftsupport.c). Nothing
# here is Ferry's code: it is Swift's (Apache 2.0 with the Runtime Library
# Exception), built unchanged; Ferry's part is this script's settings.
#
# TOOLCHAIN is a Swift toolchain for Linux (the folder holding usr/bin), by
# default $FERRY_SWIFT_TOOLCHAIN. Neither is needed to build or run Ferry
# itself; swift/build-modules.sh then builds Ferry's overlays and SwiftUI.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
src=$(cd "${1:?usage: build-runtime.sh SWIFT_SOURCE [TOOLCHAIN]}" && pwd)
tc=${2:-${FERRY_SWIFT_TOOLCHAIN:-}}
[ -n "$tc" ] && tc=$(cd "$tc" && pwd)
build=${FERRY_SWIFT_BUILD:-$here/build}
dest=${FERRY_FRAMEWORKS:-$top/frameworks}/swift
res=$dest/usr/lib/swift
obj=$build/obj
jobs=${JOBS:-$(nproc 2>/dev/null || echo 4)}
mkdir -p "$obj" "$build/include/swift/Runtime" "$build/gen" "$res/macosx"
cc="$top/sdk/ferry-cc"

# ---- settings ------------------------------------------------------------------
# As Swift's own build sets them for macOS, except: threads through plain
# pthreads (not the Darwin-only reserved thread-specific keys and
# os_unfair_lock), memory through malloc (not malloc zones), no crash
# reporter, no OS version checks, and no backtracer.
defs="-DNDEBUG -DSWIFT_RUNTIME -DSWIFT_TARGET_LIBRARY_NAME=swiftRuntime -DswiftCore_EXPORTS -DSWIFT_OBJC_INTEROP=1
 -DSWIFT_LIBRARY_EVOLUTION=1 -DSWIFT_ENABLE_REFLECTION -DSWIFT_STDLIB_HAS_DLADDR -DSWIFT_STDLIB_HAS_DLSYM=1
 -DSWIFT_STDLIB_HAS_FILESYSTEM -DSWIFT_STDLIB_HAS_DARWIN_LIBMALLOC=0 -DSWIFT_STDLIB_HAS_STDIN
 -DSWIFT_STDLIB_HAS_ENVIRON -DSWIFT_STDLIB_HAS_LOCALE -DSWIFT_THREADING_PTHREADS -DSWIFT_STDLIB_HAS_TYPE_PRINTING
 -DSWIFT_STDLIB_ENABLE_UNICODE_DATA -DSWIFT_STDLIB_SHORT_MANGLING_LOOKUPS -DSWIFT_SUPPORT_OLD_MANGLING
 -DSWIFT_RUNTIME_ENABLE_LEAK_CHECKER=0 -DSWIFT_RUNTIME_CLOBBER_FREED_OBJECTS=0
 -DSWIFT_LIB_SUBDIR=\"macosx\" -DSWIFT_ARCH=\"x86_64\" -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS
 -D__STDC_LIMIT_MACROS"
incs="-I$build/include -I$src/include -I$src/stdlib/include -I$src/stdlib/public/SwiftShims -I$src/stdlib/public/runtime"
cflags="-O2 -fPIC -fvisibility=hidden -funwind-tables -fno-modules -w"
export cc defs incs cflags src build obj

cat > "$build/include/swift/Runtime/CMakeConfig.h" <<EOF
#ifndef SWIFT_RUNTIME_CMAKECONFIG_H
#define SWIFT_RUNTIME_CMAKECONFIG_H
#define SWIFT_BNI_OS_BUILD 0
#define SWIFT_BNI_XCODE_BUILD 0
#define SWIFT_VERSION_MAJOR "6"
#define SWIFT_VERSION_MINOR "1"
#endif
EOF

gyb() { python3 "$src/utils/gyb.py" -DCMAKE_SIZEOF_VOID_P=8 --line-directive= -o "$2" "$1"; }

# ---- the C, C++ and Objective-C++ parts -----------------------------------------
gyb "$src/stdlib/public/stubs/SwiftNativeNSXXXBase.mm.gyb" "$build/gen/SwiftNativeNSXXXBase.mm"
rt=$src/stdlib/public/runtime
st=$src/stdlib/public/stubs
{
    echo "$src/stdlib/public/CompatibilityOverride/CompatibilityOverride.cpp"
    for f in AnyHashableSupport Array AutoDiffSupport Bincompat BytecodeLayouts Casting CrashReporter Demangle \
        DynamicCast Enum EnvironmentVariables ErrorObjectCommon ErrorObjectNative Errors ErrorDefaultImpls Exception \
        Exclusivity ExistentialContainer Float16Support FoundationSupport FunctionReplacement GenericMetadataBuilder \
        Heap HeapObject ImageInspectionCommon ImageInspectionMachO SymbolInfo KeyPaths KnownMetadata \
        LibPrespecialized Metadata MetadataLookup Numeric Once Paths Portability ProtocolConformance RefCount \
        ReflectionMirror RuntimeInvocationsTracking SwiftDtoa SwiftTLSContext ThreadingError Tracing \
        AccessibleFunction; do echo "$rt/$f.cpp"; done
    for f in ErrorObject SwiftObject SwiftValue ReflectionMirrorObjC ObjCRuntimeGetImageNameFromClass; do
        echo "$rt/$f.mm"
    done
    for f in ThreadSanitizer Pthreads; do echo "$src/lib/Threading/$f.cpp"; done
    for f in Assert GlobalObjects LibcShims Random Stubs ThreadLocalStorage MathStubs Unicode/UnicodeData \
        Unicode/UnicodeGrapheme Unicode/UnicodeNormalization Unicode/UnicodeScalarProps Unicode/UnicodeWord; do
        echo "$st/$f.cpp"
    done
    for f in Availability FoundationHelpers OptionalBridgingHelper Reflection SwiftNativeNSObject; do echo "$st/$f.mm"; done
    echo "$st/SwiftNativeNSXXXBaseARC.m"
    echo "$build/gen/SwiftNativeNSXXXBase.mm"
    echo "$src/stdlib/public/CommandLineSupport/CommandLine.cpp"
    for f in ErrorHandling Hashing MemAlloc SmallPtrSet SmallVector StringRef; do
        echo "$src/stdlib/public/LLVMSupport/$f.cpp"
    done
    for f in Context Demangler ManglingUtils NodePrinter Punycode Remangler NodeDumper Errors OldDemangler OldRemangler; do
        echo "$src/lib/Demangling/$f.cpp"
    done
} > "$build/gen/files.txt"

# one file: its object is obj/<path with / as _>.o
cat > "$build/gen/compile-one.sh" <<'EOF'
f=$1
o=$obj/$(echo "$f" | sed "s|^$src/||; s|^$build/||; s|/|_|g").o
[ "$o" -nt "$f" ] && exit 0
case $f in
    *.cpp) lang="-std=c++17 -fno-rtti -fno-exceptions" ;;
    *ARC.m) lang="-fobjc-arc" ;;
    *.mm) lang="-std=c++17 -fno-rtti -fno-exceptions -fno-objc-arc" ;;
    *) lang= ;;
esac
# shellcheck disable=SC2086
exec "$cc" -c $cflags $lang $defs $incs -o "$o" "$f"
EOF
echo "build-runtime: compiling the runtime's C++ and Objective-C++ ($(wc -l < "$build/gen/files.txt") files)"
xargs -P "$jobs" -n 1 sh "$build/gen/compile-one.sh" < "$build/gen/files.txt"
objs=
while read -r f; do
    o=$obj/$(echo "$f" | sed "s|^$src/||; s|^$build/||; s|/|_|g").o
    [ -f "$o" ] || { echo "build-runtime: $f didn't compile" >&2; exit 1; }
    objs="$objs $o"
done < "$build/gen/files.txt"

# ---- the standard library, in Swift -----------------------------------------------
if [ -z "$tc" ] || [ ! -x "$tc/usr/bin/swift-frontend" ]; then
    echo "build-runtime: no Swift toolchain (give its folder, or set FERRY_SWIFT_TOOLCHAIN); stopping after the C++ parts" >&2
    exit 1
fi
frontend=$tc/usr/bin/swift-frontend
core=$src/stdlib/public/core
mkdir -p "$build/gen/core"
for g in "$core"/*.swift.gyb; do
    out=$build/gen/core/$(basename "$g" .gyb)
    [ "$out" -nt "$g" ] || gyb "$g" "$out"
done
# the sources in the order Swift's own build lists them (Runtimes/Core/core)
list=$src/Runtimes/Core/core/CMakeLists.txt
swift_files=$(sed -n '/^add_library(swiftCore/,/)/p' "$list" | sed 's/#.*//' | tr -d '"' | grep -o '[^ ]*\.swift' |
    sed "s|\${CMAKE_CURRENT_BINARY_DIR}|$build/gen/core|; t; s|^|$core/|")
swift_files=$(echo $swift_files)
swift_files="$swift_files $core/SIMDVector.swift $build/gen/core/SIMDConcreteOperations.swift $build/gen/core/SIMDVectorTypes.swift"
avail=
while IFS= read -r line; do
    case $line in ''|'#'*) continue ;; esac
    avail="$avail -define-availability \"$line\""
done < "$src/utils/availability-macros.def"
common="-target x86_64-apple-macosx10.13 -resource-dir $res -sdk $top/sdk -O -enable-library-evolution -disable-legacy-type-info -suppress-warnings
 -swift-version 5 -enable-objc-interop -Xcc -nostdlibinc -Xcc -isystem -Xcc $top/sdk/include
 -plugin-path $tc/usr/lib/swift/host/plugins -module-cache-path $build/module-cache
 -disable-implicit-concurrency-module-import -disable-implicit-string-processing-module-import
 -enable-experimental-feature NoncopyableGenerics2 -enable-experimental-feature SuppressedAssociatedTypes
 -enable-experimental-feature SE427NoInferenceOnExtension -enable-experimental-feature AllowUnsafeAttribute
 -enable-experimental-feature MemberImportVisibility -enable-experimental-feature TypedThrows
 -enable-experimental-feature Macros -enable-experimental-feature FreestandingMacros
 -enable-experimental-feature BitwiseCopyable -enable-experimental-feature Extern"
common=$(printf '%s' "$common" | tr '\n' ' ')  # one line: eval reads a newline as the end of the command
# Ferry's resource folder: SwiftShims, where the compiler looks for them beside the modules
mkdir -p "$res"; rm -rf "$res/shims"
cp -r "$src/stdlib/public/SwiftShims/swift/shims" "$res/shims"
ln -sfn "$tc/usr/lib/swift/clang" "$res/clang"

mod=$res/macosx/Swift.swiftmodule
mkdir -p "$mod"
if [ ! -f "$obj/Swift.o" ] || [ -n "$(find "$core" "$build/gen/core" -newer "$obj/Swift.o" -name '*.swift' | head -1)" ]; then
    echo "build-runtime: compiling the standard library (this takes a few minutes)"
    # shellcheck disable=SC2086
    eval "\"$frontend\" -frontend -c $swift_files $common $avail -module-name Swift -module-link-name swiftCore \
        -D SWIFT_ENABLE_REFLECTION -D SWIFT_STDLIB_HAS_STDIN -D SWIFT_STDLIB_HAS_COMMANDLINE -D SWIFT_STDLIB_ENABLE_VECTOR_TYPES \
        -parse-stdlib -nostdimport -library-level api -runtime-compatibility-version none \
        -disable-autolinking-runtime-compatibility-dynamic-replacements -disable-autolinking-runtime-compatibility-concurrency \
        -warn-implicit-overrides -group-info-path $core/GroupInfo.json -enable-experimental-concise-pound-file \
        -disable-objc-attr-requires-foundation-module -enforce-exclusivity=unchecked -enable-ossa-modules \
        -target-min-inlining-version min -enable-lexical-lifetimes=false -empty-abi-descriptor \
        -prespecialize-generic-metadata -Xllvm -sil-inline-generics -Xllvm -sil-partial-specialization \
        -Xcc -DswiftCore_EXPORTS -Xcc -DSWIFT_OBJC_INTEROP=1 \
        -emit-module-path $mod/x86_64-apple-macos.swiftmodule \
        -emit-module-interface-path $mod/x86_64-apple-macos.swiftinterface \
        -o $obj/Swift.o"
fi

echo "build-runtime: linking libswiftCore.dylib"
# shellcheck disable=SC2086
"$cc" -dynamiclib -install_name /usr/lib/swift/libswiftCore.dylib -compatibility_version 1.0.0 -current_version 6.1.3 \
    -o "$dest/libswiftCore.dylib" "$obj/Swift.o" $objs -lc++ -lobjc

# SwiftOnoneSupport, which -Onone programs link
onone=$res/macosx/SwiftOnoneSupport.swiftmodule
mkdir -p "$onone"
if [ ! -f "$obj/SwiftOnoneSupport.o" ] || [ "$obj/Swift.o" -nt "$obj/SwiftOnoneSupport.o" ]; then
    # shellcheck disable=SC2086
    eval "\"$frontend\" -frontend -c $src/stdlib/public/SwiftOnoneSupport/SwiftOnoneSupport.swift $common $avail \
        -module-name SwiftOnoneSupport -module-link-name swiftSwiftOnoneSupport -parse-stdlib -runtime-compatibility-version none -I $res/macosx \
        -Xllvm -sil-inline-generics=false -disable-access-control -check-onone-completeness \
        -emit-module-path $onone/x86_64-apple-macos.swiftmodule \
        -emit-module-interface-path $onone/x86_64-apple-macos.swiftinterface -o $obj/SwiftOnoneSupport.o"
fi
"$cc" -dynamiclib -install_name /usr/lib/swift/libswiftSwiftOnoneSupport.dylib \
    -o "$dest/libswiftSwiftOnoneSupport.dylib" "$obj/SwiftOnoneSupport.o" "$dest/libswiftCore.dylib"

# Darwin, Swift's own overlay for the C library (stdlib/public/Platform):
# errno, the type-generic maths (sqrt of a Float and the like), POSIX and
# Mach errors as Swift errors. Built unchanged against Ferry's C headers.
plat=$src/stdlib/public/Platform
darwin=$res/macosx/Darwin.swiftmodule
mkdir -p "$darwin" "$build/gen/platform"
for g in tgmath Darwin; do
    [ "$build/gen/platform/$g.swift" -nt "$plat/$g.swift.gyb" ] || gyb "$plat/$g.swift.gyb" "$build/gen/platform/$g.swift"
done
if [ ! -f "$obj/Darwin.o" ] || [ "$obj/Swift.o" -nt "$obj/Darwin.o" ] ||
   [ -n "$(find "$top/sdk/include" -newer "$obj/Darwin.o" \( -name "*.h" -o -name "*.modulemap" \) | head -1)" ]; then
    echo "build-runtime: compiling Darwin, Swift's overlay for the C library"
    # shellcheck disable=SC2086
    eval "\"$frontend\" -frontend -c $plat/Platform.swift $plat/TiocConstants.swift $plat/POSIXError.swift \
        $plat/MachError.swift $build/gen/platform/tgmath.swift $build/gen/platform/Darwin.swift $common $avail \
        -module-name Darwin -module-link-name swiftDarwin -parse-as-library -I $res/macosx -D SWIFT_ENABLE_REFLECTION \
        -disable-objc-attr-requires-foundation-module -runtime-compatibility-version none \
        -emit-module-path $darwin/x86_64-apple-macos.swiftmodule \
        -emit-module-interface-path $darwin/x86_64-apple-macos.swiftinterface -o $obj/Darwin.o"
fi
"$cc" -dynamiclib -install_name /usr/lib/swift/libswiftDarwin.dylib \
    -o "$dest/libswiftDarwin.dylib" "$obj/Darwin.o" -L"$dest" -lswiftCore
echo "build-runtime: done; Swift's runtime is in $dest"
