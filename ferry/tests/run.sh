#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds each test as an Intel Mac program with ferry-cc, runs it through
# ./ferry and compares what it prints (plus its exit status) with NAME.out.
set -u
here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
build="$here/build"
mkdir -p "$build"
export FERRY_SDK="$top/sdk"
pass=0
fail=0
run_one() {
    name=$1; src=$2; expected=$3; shift 3
    exe="$build/$name"
    if ! "$top/sdk/ferry-cc" -O1 -o "$exe" "$src" "$@" 2> "$build/$name.cc.log"; then
        echo "FAIL $name (did not compile)"; sed 's/^/    /' "$build/$name.cc.log"
        fail=$((fail + 1)); return
    fi
    case $name in
        hello*) FERRY_TEST_VALUE=tide "$top/ferry" "$exe" boat > "$build/$name.got" 2> "$build/$name.err" ;;
        system) "$top/ferry" "$exe" -a -b val file > "$build/$name.got" 2> "$build/$name.err" ;;
        foundation_system)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            HOME="$build/home_$name" XDG_CONFIG_HOME= XDG_DATA_HOME= XDG_CACHE_HOME= \
                "$top/ferry" "$exe" -Mode fast > "$build/$name.got" 2> "$build/$name.err" ;;
        *) "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
    esac
    echo "exit=$?" >> "$build/$name.got"
    if diff -u "$expected" "$build/$name.got" > "$build/$name.diff"; then
        echo "ok   $name"; pass=$((pass + 1))
    else
        echo "FAIL $name"; sed 's/^/    /' "$build/$name.diff"; sed 's/^/    stderr: /' "$build/$name.err"
        fail=$((fail + 1))
    fi
}
for t in hello files errors memory signals system; do
    run_one "$t" "$here/$t.c" "$here/$t.out"
done
# A call Ferry doesn't have is left for the loader to find, as a Mac linker
# would with -undefined dynamic_lookup.
run_one unsupported "$here/unsupported.c" "$here/unsupported.out" -Wl,-undefined,dynamic_lookup
# The same programs linked with chained fixups, the newer Mach-O layout.
for t in hello files; do
    run_one "${t}_chained" "$here/$t.c" "$here/$t.out" -Wl,-fixup_chains
done
# Blocks from plain C, and the Objective-C runtime (M1).
run_one blocks "$here/blocks.c" "$here/blocks.out" -fblocks
run_one objc_basic "$here/objc_basic.m" "$here/objc_basic.out" -lobjc
run_one objc_arc "$here/objc_arc.m" "$here/objc_arc.out" -fobjc-arc -lobjc
run_one objc_unknown "$here/objc_unknown.m" "$here/objc_unknown.out" -lobjc
run_one objc_basic_chained "$here/objc_basic.m" "$here/objc_basic.out" -lobjc -Wl,-fixup_chains
run_one objc_arc_chained "$here/objc_arc.m" "$here/objc_arc.out" -fobjc-arc -lobjc -Wl,-fixup_chains
# Unoptimized code sends messages differently (no tail calls, more stack).
run_one objc_basic_O0 "$here/objc_basic.m" "$here/objc_basic.out" -O0 -lobjc
# A program using a Mac library (dylib) of its own, found through @rpath,
# with both relocation formats.
for fmt in classic chained; do
    flags=; [ $fmt = chained ] && flags=-Wl,-fixup_chains
    mkdir -p "$build/lib_$fmt"
    if "$top/sdk/ferry-cc" -O1 -dynamiclib -install_name @rpath/libgreet.dylib $flags \
            -o "$build/lib_$fmt/libgreet.dylib" "$here/dylib/greet.m" -lobjc 2> "$build/greet_$fmt.cc.log"; then
        run_one "dylib_$fmt" "$here/dylib_main.m" "$here/dylib_main.out" -lobjc $flags \
            -L"$build/lib_$fmt" -lgreet -Wl,-rpath,@executable_path/lib_$fmt
    else
        echo "FAIL dylib_$fmt (library did not compile)"; sed 's/^/    /' "$build/greet_$fmt.cc.log"
        fail=$((fail + 1))
    fi
done
# Foundation (M2), Ferry's own, loaded as a Mac framework.
for t in strings collections system runloop exception; do
    run_one "foundation_$t" "$here/foundation/$t.m" "$here/foundation/$t.out" -framework Foundation
done
# CoreFoundation from plain C, linked under CoreFoundation's own Mac name.
run_one foundation_corefoundation "$here/foundation/corefoundation.c" "$here/foundation/corefoundation.out" \
    -framework CoreFoundation
run_one foundation_arc "$here/foundation/arc.m" "$here/foundation/arc.out" -fobjc-arc -framework Foundation
run_one foundation_collections_chained "$here/foundation/collections.m" "$here/foundation/collections.out" \
    -framework Foundation -Wl,-fixup_chains
run_one foundation_attributed "$here/foundation/attributed.m" "$here/foundation/attributed.out" -framework Foundation
# Core Graphics and Core Text (M3), drawn by this system's Cairo and Pango.
run_one graphics_geometry "$here/graphics/geometry.c" "$here/graphics/geometry.out" \
    -framework CoreGraphics -framework CoreFoundation
run_one graphics_drawing "$here/graphics/drawing.c" "$here/graphics/drawing.out" -framework CoreGraphics
run_one graphics_text "$here/graphics/text.m" "$here/graphics/text.out" \
    -framework CoreText -framework CoreGraphics -framework Foundation
# The same, linked under ApplicationServices' Mac name, which CoreGraphics' file also serves.
run_one graphics_appservices "$here/graphics/geometry.c" "$here/graphics/geometry.out" \
    -framework ApplicationServices -framework CoreFoundation
run_one graphics_drawing_chained "$here/graphics/drawing.c" "$here/graphics/drawing.out" \
    -framework CoreGraphics -Wl,-fixup_chains
# Cairo is loaded only by programs that draw (glibc's LD_DEBUG lists each library loaded).
if LD_DEBUG=libs "$top/ferry" "$build/foundation_strings" 2>&1 >/dev/null | grep -q "libcairo"; then
    echo "FAIL foundation_strings loads Cairo"; fail=$((fail + 1))
elif ! LD_DEBUG=libs "$top/ferry" "$build/graphics_drawing" 2>&1 >/dev/null | grep -q "libcairo"; then
    echo "FAIL graphics_drawing doesn't load Cairo"; fail=$((fail + 1))
else
    echo "ok   Cairo loaded only when drawing"; pass=$((pass + 1))
fi
# A program inside a Mac app bundle: Info.plist, resources, localized strings.
app="$build/Hello.app"
rm -rf "$app"; cp -r "$here/foundation/Hello.app" "$app"; mkdir -p "$app/Contents/MacOS"
if "$top/sdk/ferry-cc" -O1 -o "$app/Contents/MacOS/Hello" "$here/foundation/bundle.m" -framework Foundation \
        2> "$build/foundation_bundle.cc.log"; then
    rm -rf "$build/home_bundle"; mkdir -p "$build/home_bundle"
    for lang in C fr_FR.UTF-8; do
        HOME="$build/home_bundle" XDG_CONFIG_HOME= LANG=$lang LC_ALL= LC_MESSAGES= "$top/ferry" "$app/Contents/MacOS/Hello" \
            > "$build/foundation_bundle_$lang.got" 2> "$build/foundation_bundle.err"
        echo "exit=$?" >> "$build/foundation_bundle_$lang.got"
        expected="$here/foundation/bundle.out"; [ $lang = C ] || expected="$here/foundation/bundle_fr.out"
        if diff -u "$expected" "$build/foundation_bundle_$lang.got" > "$build/foundation_bundle.diff"; then
            echo "ok   foundation_bundle ($lang)"; pass=$((pass + 1))
        else
            echo "FAIL foundation_bundle ($lang)"; sed 's/^/    /' "$build/foundation_bundle.diff"
            sed 's/^/    stderr: /' "$build/foundation_bundle.err"; fail=$((fail + 1))
        fi
    done
else
    echo "FAIL foundation_bundle (did not compile)"; sed 's/^/    /' "$build/foundation_bundle.cc.log"
    fail=$((fail + 1))
fi
# An exception nobody catches ends the program with the Mac's message.
if grep -q "Terminating app due to uncaught exception 'NSRangeException'" "$build/foundation_exception.err" 2>/dev/null; then
    echo "ok   foundation_exception message"; pass=$((pass + 1))
else
    echo "FAIL foundation_exception message"; fail=$((fail + 1))
fi
# An unknown selector must be reported as a Mac reports it.
if grep -q "unrecognized selector sent to instance" "$build/objc_unknown.err" 2>/dev/null; then
    echo "ok   objc_unknown message"; pass=$((pass + 1))
else
    echo "FAIL objc_unknown message"; fail=$((fail + 1))
fi
# The unsupported program must also say what was missing.
if grep -q "pthread_yield_np" "$build/unsupported.err" 2>/dev/null; then
    echo "ok   unsupported message"; pass=$((pass + 1))
else
    echo "FAIL unsupported message"; fail=$((fail + 1))
fi
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
