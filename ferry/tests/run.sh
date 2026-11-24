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
# For the URL loading tests: the test server on 127.0.0.1, reached directly,
# never through a proxy, and a home of the test's own (for cookies and caches).
url_env() {
    env -u http_proxy -u HTTP_PROXY -u https_proxy -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
        NO_PROXY=127.0.0.1 no_proxy=127.0.0.1 TMPDIR="$build/home_$name" \
        HOME="$build/home_$name" XDG_CONFIG_HOME= XDG_CACHE_HOME= XDG_DATA_HOME= \
        FERRY_TEST_HTTP="127.0.0.1:$http_port" FERRY_TEST_CLOSED_PORT="$closed_port" \
        FERRY_TEST_HTTPS="${tls_port:+127.0.0.1:$tls_port}" "$@"
}

run_one() {
    name=$1; src=$2; expected=$3; shift 3
    exe="$build/$name"
    if ! "$top/sdk/ferry-cc" -O1 -o "$exe" "$src" "$@" 2> "$build/$name.cc.log"; then
        echo "FAIL $name (did not compile)"; sed 's/^/    /' "$build/$name.cc.log"
        fail=$((fail + 1)); return
    fi
    if [ "$name" = hello_unixthread ]; then
        python3 "$here/tools/unixthread.py" "$exe" "$(llvm-nm "$exe" | awk '/ T _old_start$/ {print $1}')"
    fi
    case $name in
        hello*) FERRY_TEST_VALUE=tide "$top/ferry" "$exe" boat > "$build/$name.got" 2> "$build/$name.err" ;;
        system) "$top/ferry" "$exe" -a -b val file > "$build/$name.got" 2> "$build/$name.err" ;;
        foundation_system)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            HOME="$build/home_$name" XDG_CONFIG_HOME= XDG_DATA_HOME= XDG_CACHE_HOME= \
                "$top/ferry" "$exe" -Mode fast > "$build/$name.got" 2> "$build/$name.err" ;;
        foundation_dates|foundation_calendar|foundation_numbers|foundation_iso8601)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            HOME="$build/home_$name" XDG_CONFIG_HOME= TZ=Europe/Paris TZDIR= LANG=en_US.UTF-8 LC_ALL= LC_MESSAGES= \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        foundation_archive*) FERRY_TEST_DATA="$here/foundation" "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        foundation_urlcookies|foundation_urlcache)
            # twice in one home: what the first run keeps, the second finds
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            url_env "$top/ferry" "$exe" first > "$build/$name.got" 2> "$build/$name.err" &&
                url_env "$top/ferry" "$exe" second >> "$build/$name.got" 2>> "$build/$name.err" ;;
        foundation_url*)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            url_env "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_panes|appkit_tables|appkit_controls|appkit_binding_controls|appkit_array_controller|appkit_tree_controller|appkit_nib_controllers|appkit_binding_validation)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            HOME="$build/home_$name" XDG_CONFIG_HOME= FERRY_TEST_DATA="$here/appkit" env -u WAYLAND_DISPLAY -u DISPLAY \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_more_controls)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            HOME="$build/home_$name" XDG_CONFIG_HOME= TMPDIR="$build/home_$name" FERRY_TEST_DATA="$here/appkit" \
                FERRY_SOUND_PLAYER="$here/appkit/fake_player.sh" FERRY_FAKE_PLAYER_LOG="$build/home_$name/player.log" \
                TZ=Europe/Paris LANG=en_US.UTF-8 env -u WAYLAND_DISPLAY -u DISPLAY -u FERRY_COLOR_ANSWER \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_hidpi)
            XDG_RUNTIME_DIR="$xdg" WAYLAND_DISPLAY=ferry-hidpi DISPLAY= \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_window*)
            XDG_RUNTIME_DIR="$xdg" WAYLAND_DISPLAY=ferry-test DISPLAY= \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_bindings)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            env -u WAYLAND_DISPLAY -u DISPLAY HOME="$build/home_$name" XDG_CONFIG_HOME= TMPDIR="$build/home_$name" \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_autosave)
            rm -rf "$build/home_$name"; mkdir -p "$build/home_$name"
            env -u WAYLAND_DISPLAY -u DISPLAY -u FERRY_ALERT_ANSWER HOME="$build/home_$name" XDG_CONFIG_HOME= \
                XDG_DATA_HOME= TMPDIR="$build/home_$name" \
                "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        appkit_*) env -u WAYLAND_DISPLAY -u DISPLAY "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
        twins) "$top/ferry" "$exe" < /dev/null > "$build/$name.got" 2>&1 ;;
        atomics) "$top/ferry" "$exe" > "$build/$name.got" 2>&1 ;;
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
# The start-up format of Mac OS X 10.7 and earlier (LC_UNIXTHREAD).
run_one hello_unixthread "$here/unixthread.c" "$here/unixthread.out" -Wl,-headerpad,0x400
run_one twins "$here/twins.c" "$here/twins.out" -lz -lbz2 -licucore
run_one atomics "$here/atomics.c" "$here/atomics.out"
# Blocks from plain C, and the Objective-C runtime (M1).
run_one blocks "$here/blocks.c" "$here/blocks.out" -fblocks
# Grand Central Dispatch from plain C (M6).
run_one dispatch "$here/dispatch.c" "$here/dispatch.out" -fblocks
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
run_one foundation_dispatch "$here/foundation/dispatch.m" "$here/foundation/dispatch.out" -fobjc-arc -framework Foundation
# Exceptions a program catches (M7), unwound through frame-pointer and
# frameless functions, and through Foundation's frames.
run_one foundation_trycatch "$here/foundation/trycatch.m" "$here/foundation/trycatch.out" -fobjc-arc \
    -framework Foundation
run_one foundation_trycatch_frameless "$here/foundation/trycatch.m" "$here/foundation/trycatch.out" -O2 \
    -fomit-frame-pointer -fobjc-arc -framework Foundation
run_one foundation_trycatch_mrc "$here/foundation/trycatch.m" "$here/foundation/trycatch.out" -O0 \
    -framework Foundation -Wl,-fixup_chains
# Linked against a system framework Ferry doesn't have (only its .tbd exists).
run_one foundation_missing "$here/foundation/missing.m" "$here/foundation/missing.out" -framework Foundation \
    -F"$here/foundation" -framework Imaginary
run_one foundation_collections_chained "$here/foundation/collections.m" "$here/foundation/collections.out" \
    -framework Foundation -Wl,-fixup_chains
run_one foundation_attributed "$here/foundation/attributed.m" "$here/foundation/attributed.out" -framework Foundation
run_one foundation_kvo "$here/foundation/kvo.m" "$here/foundation/kvo.out" -framework Foundation
# Automatic notification through the hidden subclass, dependent keys, key
# paths, to-many changes and key-value coding's search (Ferry 0.17.0).
run_one foundation_kvo_auto "$here/foundation/kvo_auto.m" "$here/foundation/kvo_auto.out" -framework Foundation
# Set mutations, collection operators, removing an observer that isn't
# registered, and predicates (Ferry 0.18.0).
run_one foundation_kvc_collections "$here/foundation/kvc_collections.m" "$here/foundation/kvc_collections.out" \
    -fobjc-arc -fblocks -framework Foundation
# NSInvocation, NSMethodSignature, NSProxy and forwarding, and undo through
# prepareWithInvocationTarget: (Ferry 0.14.0), also unoptimized and with
# chained fixups. The program ends on a message nothing implements.
run_one foundation_invocation "$here/foundation/invocation.m" "$here/foundation/invocation.out" -framework Foundation
run_one foundation_invocation_O0 "$here/foundation/invocation.m" "$here/foundation/invocation.out" -O0 \
    -framework Foundation -Wl,-fixup_chains
# JSON reading and writing, and dates: time zones, locales and date
# formatting (Ferry 0.14.0).
run_one foundation_json "$here/foundation/json.m" "$here/foundation/json.out" -framework Foundation
run_one foundation_dates "$here/foundation/dates.m" "$here/foundation/dates.out" -framework Foundation
# Calendars and date components, number and byte count formatters, ISO 8601
# dates, relative dates and date components formatters (Ferry 0.15.0).
run_one foundation_calendar "$here/foundation/calendar.m" "$here/foundation/calendar.out" -framework Foundation -fblocks
run_one foundation_numbers "$here/foundation/numbers.m" "$here/foundation/numbers.out" -framework Foundation
run_one foundation_iso8601 "$here/foundation/iso8601.m" "$here/foundation/iso8601.out" -framework Foundation
# Tasks and pipes, regular expressions (ICU), scanners, XML (libxml2: events and trees), operations, locks, caches, progress.
for t in task regex scanner xmlparser xmldocument operation cache; do
    run_one "foundation_$t" "$here/foundation/$t.m" "$here/foundation/$t.out" -fblocks -framework Foundation
done
# Keyed archives (M5), the format of nib files.
run_one foundation_archive "$here/foundation/archive.m" "$here/foundation/archive.out" -framework Foundation
# URL loading through this system's libcurl: NSURLSession, NSURLConnection and
# NSData's and NSString's ...ContentsOfURL:, against a small HTTP server
# started here on 127.0.0.1 (nothing goes past the loopback address).
if command -v python3 > /dev/null 2>&1; then
    rm -f "$build/http.port" "$build/tls.crt" "$build/tls.key"
    # with openssl, a certificate of its own for a TLS port too, which this system doesn't trust
    tls_files=
    if command -v openssl > /dev/null 2>&1 &&
        openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=127.0.0.1 -addext subjectAltName=IP:127.0.0.1 \
            -keyout "$build/tls.key" -out "$build/tls.crt" > "$build/openssl.log" 2>&1; then
        tls_files="$build/tls.crt $build/tls.key"
    fi
    python3 -I "$here/tools/http_server.py" "$build/http.port" $tls_files > "$build/http_server.log" 2>&1 &
    http_pid=$!
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -s "$build/http.port" ] && break; sleep 0.25; done
    tls_port=
    read http_port closed_port tls_port < "$build/http.port"
    run_one foundation_urlsession "$here/foundation/urlsession.m" "$here/foundation/urlsession.out" -fobjc-arc \
        -framework Foundation
    run_one foundation_urlconnection "$here/foundation/urlconnection.m" "$here/foundation/urlconnection.out" \
        -framework Foundation
    # redirects, authentication, cookies and caching decided as a Mac does,
    # data: URLs, and a server's certificate as a challenge
    for t in urlredirects urlauth urlcookies urlcache urldata; do
        run_one "foundation_$t" "$here/foundation/$t.m" "$here/foundation/$t.out" -fobjc-arc -framework Foundation
    done
    if [ -n "$tls_port" ]; then
        run_one foundation_urltrust "$here/foundation/urltrust.m" "$here/foundation/urltrust.out" -fobjc-arc \
            -framework Foundation
    else
        echo "skip foundation_urltrust (needs openssl, to make the test server a certificate)"
    fi
    kill "$http_pid" 2> /dev/null; wait "$http_pid" 2> /dev/null
else
    echo "skip foundation_urlsession, foundation_urlconnection and the other URL tests (need python3, for a test server)"
fi
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
# Core Animation: layers drawn with Core Graphics, and animations stepped by
# the test clock.
run_one quartzcore_layers "$here/quartzcore/layers.m" "$here/quartzcore/layers.out" -fobjc-arc \
    -framework QuartzCore -framework Foundation -framework CoreGraphics
run_one quartzcore_animations "$here/quartzcore/animations.m" "$here/quartzcore/animations.out" -fobjc-arc -fblocks \
    -framework QuartzCore -framework Foundation -framework CoreGraphics
# AppKit (M4). First with no display, where windows are drawn off screen,
# linked through Cocoa and through AppKit itself.
run_one appkit_views "$here/appkit/views.m" "$here/appkit/views.out" -fblocks -framework Cocoa
run_one appkit_views_appkit "$here/appkit/views.m" "$here/appkit/views.out" -fblocks \
    -framework AppKit -framework Foundation -framework CoreGraphics -framework CoreText
# Then on a real Wayland display: a headless Weston compositor, when installed.
if command -v weston > /dev/null 2>&1; then
    xdg="$build/xdg"
    rm -rf "$xdg"; mkdir -p "$xdg"; chmod 700 "$xdg"
    XDG_RUNTIME_DIR="$xdg" weston --backend=headless --socket=ferry-test > "$build/weston.log" 2>&1 &
    weston_pid=$!
    for i in 1 2 3 4 5 6 7 8 9 10; do [ -S "$xdg/ferry-test" ] && break; sleep 0.5; done
    run_one appkit_window "$here/appkit/window.m" "$here/appkit/window.out" -framework Cocoa
    # The app's icon for the dock (M7): an app bundle with an icon, on the display
    app="$build/IconApp.app"
    rm -rf "$app" "$build/home_icon"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$build/home_icon"
    cp "$here/appkit/NibApp.app/Contents/Resources/dot.png" "$app/Contents/Resources/"
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<plist version="1.0"><dict>' \
        '<key>CFBundleExecutable</key><string>IconApp</string>' \
        '<key>CFBundleIdentifier</key><string>org.freemac.ferry.iconapp</string>' \
        '<key>CFBundleName</key><string>Icon App</string>' \
        '<key>CFBundleIconFile</key><string>dot.png</string>' '</dict></plist>' > "$app/Contents/Info.plist"
    if "$top/sdk/ferry-cc" -O1 -fobjc-arc -o "$app/Contents/MacOS/IconApp" "$here/appkit/icon.m" -framework Cocoa \
            2> "$build/appkit_icon.cc.log"; then
        HOME="$build/home_icon" XDG_DATA_HOME= XDG_RUNTIME_DIR="$xdg" WAYLAND_DISPLAY=ferry-test DISPLAY= \
            "$top/ferry" "$app/Contents/MacOS/IconApp" > "$build/appkit_icon.got" 2> "$build/appkit_icon.err"
        echo "exit=$?" >> "$build/appkit_icon.got"
        if diff -u "$here/appkit/icon.out" "$build/appkit_icon.got" > "$build/appkit_icon.diff"; then
            echo "ok   appkit_icon"; pass=$((pass + 1))
        else
            echo "FAIL appkit_icon"; sed 's/^/    /' "$build/appkit_icon.diff"; sed 's/^/    stderr: /' "$build/appkit_icon.err"
            fail=$((fail + 1))
        fi
    else
        echo "FAIL appkit_icon (did not compile)"; sed 's/^/    /' "$build/appkit_icon.cc.log"
        fail=$((fail + 1))
    fi
    kill "$weston_pid" 2> /dev/null; wait "$weston_pid" 2> /dev/null
    # and a screen at scale 2 (M7)
    XDG_RUNTIME_DIR="$xdg" weston --backend=headless --socket=ferry-hidpi --scale=2 > "$build/weston-hidpi.log" 2>&1 &
    weston_pid=$!
    for i in 1 2 3 4 5 6 7 8 9 10; do [ -S "$xdg/ferry-hidpi" ] && break; sleep 0.5; done
    run_one appkit_hidpi "$here/appkit/hidpi.m" "$here/appkit/hidpi.out" -fobjc-arc -framework Cocoa
    kill "$weston_pid" 2> /dev/null; wait "$weston_pid" 2> /dev/null
else
    echo "skip appkit_window, appkit_icon, appkit_hidpi (need weston, for a test display)"
fi
# Cairo is loaded only by programs that draw, and GTK only by AppKit's
# (glibc's LD_DEBUG lists each library loaded).
if LD_DEBUG=libs "$top/ferry" "$build/foundation_strings" 2>&1 >/dev/null | grep -q "libcairo"; then
    echo "FAIL foundation_strings loads Cairo"; fail=$((fail + 1))
elif ! LD_DEBUG=libs "$top/ferry" "$build/graphics_drawing" 2>&1 >/dev/null | grep -q "libcairo"; then
    echo "FAIL graphics_drawing doesn't load Cairo"; fail=$((fail + 1))
elif LD_DEBUG=libs "$top/ferry" "$build/graphics_drawing" 2>&1 >/dev/null | grep -q "libgtk"; then
    echo "FAIL graphics_drawing loads GTK"; fail=$((fail + 1))
else
    echo "ok   Cairo loaded only when drawing, GTK only for AppKit"; pass=$((pass + 1))
fi
# libcurl only by programs that load URLs from the network.
if LD_DEBUG=libs "$top/ferry" "$build/foundation_strings" 2>&1 >/dev/null | grep -q "libcurl"; then
    echo "FAIL foundation_strings loads libcurl"; fail=$((fail + 1))
else
    echo "ok   libcurl loaded only when loading URLs"; pass=$((pass + 1))
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
# Key paths, value transformers and bindings (M6).
run_one appkit_bindings "$here/appkit/bindings.m" "$here/appkit/bindings.out" -fobjc-arc -framework Cocoa
# An exception left uncaught in the event loop is reported, not fatal (M7).
run_one appkit_scrolling "$here/appkit/scrolling.m" "$here/appkit/scrolling.out" -fobjc-arc -framework Cocoa
# Split views and tab views, built in code and from a nib (after M7).
run_one appkit_panes "$here/appkit/panes.m" "$here/appkit/panes.out" -fobjc-arc -framework Cocoa
run_one appkit_tables "$here/appkit/tables.m" "$here/appkit/tables.out" -fobjc-arc -framework Cocoa
# Editing table and outline cells in place (Ferry 0.16.0).
run_one appkit_editing "$here/appkit/editing.m" "$here/appkit/editing.out" -fobjc-arc -framework Cocoa
# Formatters on text fields, cells and edited table cells (Ferry 0.17.0).
run_one appkit_formatters "$here/appkit/formatters.m" "$here/appkit/formatters.out" -fobjc-arc -framework Cocoa
# Bindings that follow and write back: controls, NSObjectController,
# NSUserDefaultsController and bindings loaded from a nib (Ferry 0.17.0).
run_one appkit_binding_controls "$here/appkit/binding_controls.m" "$here/appkit/binding_controls.out" -fobjc-arc \
    -framework Cocoa
# NSArrayController, and a table whose columns are bound to it (Ferry 0.18.0).
run_one appkit_array_controller "$here/appkit/array_controller.m" "$here/appkit/array_controller.out" -fobjc-arc \
    -framework Cocoa
# NSTreeController and NSTreeNode, an outline view bound to one, per-row
# editable and enabled column bindings, and NSDictionaryController (Ferry 0.19.0).
run_one appkit_tree_controller "$here/appkit/tree_controller.m" "$here/appkit/tree_controller.out" -fobjc-arc \
    -framework Cocoa
# Controllers loaded from a nib written with the keyed archiver, and
# bindings in view-based tables' and outlines' cell views (Ferry 0.20.0).
run_one appkit_nib_controllers "$here/appkit/nib_controllers.m" "$here/appkit/nib_controllers.out" -fobjc-arc \
    -framework Cocoa
# Validation through bindings, NSRaisesForNotApplicableKeys, conditionally
# set enabled and editable, and the array controller's content options
# (Ferry 0.20.0).
run_one appkit_binding_validation "$here/appkit/binding_validation.m" "$here/appkit/binding_validation.out" \
    -fobjc-arc -framework Cocoa
# NSDocument autosaving, in a home of its own (Ferry 0.16.0).
run_one appkit_autosave "$here/appkit/autosave.m" "$here/appkit/autosave.out" -fobjc-arc -framework Cocoa
# Pop-up buttons, segmented controls, search fields, stack views and
# toolbars, built in code and from a nib (1.161).
run_one appkit_controls "$here/appkit/controls.m" "$here/appkit/controls.out" -fobjc-arc -framework Cocoa
run_one appkit_more_controls "$here/appkit/more_controls.m" "$here/appkit/more_controls.out" -fobjc-arc \
    -framework Cocoa
run_one appkit_carbon "$here/appkit/carbon.m" "$here/appkit/carbon.out" -fobjc-arc -framework Cocoa -framework Carbon \
    -framework SystemConfiguration
run_one appkit_report "$here/appkit/report.m" "$here/appkit/report.out" -fobjc-arc -framework Cocoa
# Layer-backed and layer-hosting views, NSAnimationContext and animator
# proxies, on Core Animation's test clock.
run_one appkit_layers "$here/appkit/layers.m" "$here/appkit/layers.out" -fobjc-arc -fblocks -framework Cocoa \
    -framework QuartzCore
# Pasteboards, and cut, copy and paste in text fields (M7).
run_one appkit_pasteboard "$here/appkit/pasteboard.m" "$here/appkit/pasteboard.out" -fobjc-arc -framework Cocoa
# Open and Save panels, answered from FERRY_PANEL_ANSWER with no display (M7).
run_one appkit_panels "$here/appkit/panels.m" "$here/appkit/panels.out" -fobjc-arc -framework Cocoa
# Drag and drop into a window: the steps GTK's drop signals take (M7).
run_one appkit_dragging "$here/appkit/dragging.m" "$here/appkit/dragging.out" -fobjc-arc -framework Cocoa
# Menu bar items (after M7): read, opened and clicked over D-Bus as the
# desktop's menu bar does, on a private session bus.
if command -v dbus-run-session > /dev/null && command -v gdbus > /dev/null; then
    if "$top/sdk/ferry-cc" -O1 -fobjc-arc -o "$build/appkit_statusbar" "$here/appkit/statusbar.m" -framework Cocoa \
            2> "$build/appkit_statusbar.cc.log"; then
        env -u WAYLAND_DISPLAY -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS timeout 60 dbus-run-session -- \
            sh "$here/appkit/statusbar.sh" "$top/ferry" "$build/appkit_statusbar" "$build/appkit_statusbar.log" \
            > "$build/appkit_statusbar.got" 2> "$build/appkit_statusbar.err"
        echo "exit=$?" >> "$build/appkit_statusbar.got"
        if diff -u "$here/appkit/statusbar.out" "$build/appkit_statusbar.got" > "$build/appkit_statusbar.diff"; then
            echo "ok   appkit_statusbar"; pass=$((pass + 1))
        else
            echo "FAIL appkit_statusbar"; sed 's/^/    /' "$build/appkit_statusbar.diff"
            sed 's/^/    stderr: /' "$build/appkit_statusbar.log.err"; fail=$((fail + 1))
        fi
    else
        echo "FAIL appkit_statusbar (did not compile)"; sed 's/^/    /' "$build/appkit_statusbar.cc.log"
        fail=$((fail + 1))
    fi
else
    echo "skip appkit_statusbar (needs dbus-run-session and gdbus)"
fi
# An app started from its main nib (M5), with no display. The nibs come
# from make_nibs.py; what Ferry says about the parts it can't use goes to
# stderr and is checked too.
app="$build/NibApp.app"
rm -rf "$app"; cp -r "$here/appkit/NibApp.app" "$app"; mkdir -p "$app/Contents/MacOS"
if "$top/sdk/ferry-cc" -O1 -fobjc-arc -o "$app/Contents/MacOS/NibApp" "$here/appkit/nib.m" -framework Cocoa \
        2> "$build/appkit_nib.cc.log"; then
    env -u WAYLAND_DISPLAY -u DISPLAY LANG=C LC_ALL= LC_MESSAGES= "$top/ferry" "$app/Contents/MacOS/NibApp" \
        > "$build/appkit_nib.got" 2> "$build/appkit_nib.err"
    echo "exit=$?" >> "$build/appkit_nib.got"
    if ! diff -u "$here/appkit/nib.out" "$build/appkit_nib.got" > "$build/appkit_nib.diff"; then
        echo "FAIL appkit_nib"; sed 's/^/    /' "$build/appkit_nib.diff"; sed 's/^/    stderr: /' "$build/appkit_nib.err"
        fail=$((fail + 1))
    elif ! grep -q "view class NoSuchView" "$build/appkit_nib.err" || ! grep -q '"noSuchOutlet"' "$build/appkit_nib.err"; then
        echo "FAIL appkit_nib (no warning for the missing class or outlet)"; sed 's/^/    stderr: /' "$build/appkit_nib.err"
        fail=$((fail + 1))
    else
        echo "ok   appkit_nib"; pass=$((pass + 1))
    fi
else
    echo "FAIL appkit_nib (did not compile)"; sed 's/^/    /' "$build/appkit_nib.cc.log"
    fail=$((fail + 1))
fi
# Window and view controllers loading their own nibs (M7), from a copy
# of NibApp.app.
app="$build/ControllerApp.app"
rm -rf "$app"; cp -r "$here/appkit/NibApp.app" "$app"; mkdir -p "$app/Contents/MacOS"
if "$top/sdk/ferry-cc" -O1 -fobjc-arc -o "$app/Contents/MacOS/NibApp" "$here/appkit/controllers.m" -framework Cocoa \
        2> "$build/appkit_controllers.cc.log"; then
    env -u WAYLAND_DISPLAY -u DISPLAY "$top/ferry" "$app/Contents/MacOS/NibApp" \
        > "$build/appkit_controllers.got" 2> "$build/appkit_controllers.err"
    echo "exit=$?" >> "$build/appkit_controllers.got"
    if diff -u "$here/appkit/controllers.out" "$build/appkit_controllers.got" > "$build/appkit_controllers.diff"; then
        echo "ok   appkit_controllers"; pass=$((pass + 1))
    else
        echo "FAIL appkit_controllers"; sed 's/^/    /' "$build/appkit_controllers.diff"
        sed 's/^/    stderr: /' "$build/appkit_controllers.err"
        fail=$((fail + 1))
    fi
else
    echo "FAIL appkit_controllers (did not compile)"; sed 's/^/    /' "$build/appkit_controllers.cc.log"
    fail=$((fail + 1))
fi
# Documents, alerts and the workspace (1.167): DocApp.app from make_nibs.py,
# with a note named on the command line, an isolated home and a stand-in
# "gio" first on the PATH that writes down what it was asked to open.
app="$build/DocApp.app"
home="$build/home_documents"
rm -rf "$app" "$home"; cp -r "$here/appkit/DocApp.app" "$app"; mkdir -p "$app/Contents/MacOS" "$home/work" "$home/bin"
printf '%s\n' '#!/bin/sh' 'echo "$*" >> "$HOME/gio.log"' > "$home/bin/gio"; chmod +x "$home/bin/gio"
printf 'launched text' > "$home/work/Launch.note"
if "$top/sdk/ferry-cc" -O1 -fobjc-arc -o "$app/Contents/MacOS/DocApp" "$here/appkit/documents.m" -framework Cocoa \
        2> "$build/appkit_documents.cc.log"; then
    (cd "$home/work" && env -u WAYLAND_DISPLAY -u DISPLAY -u FERRY_ALERT_ANSWER -u FERRY_PANEL_ANSWER HOME="$home" \
        XDG_CONFIG_HOME= XDG_DATA_HOME= TMPDIR="$home" PATH="$home/bin:$PATH" \
        "$top/ferry" "$app/Contents/MacOS/DocApp" Launch.note) > "$build/appkit_documents.got" \
        2> "$build/appkit_documents.err"
    echo "exit=$?" >> "$build/appkit_documents.got"
    if diff -u "$here/appkit/documents.out" "$build/appkit_documents.got" > "$build/appkit_documents.diff"; then
        echo "ok   appkit_documents"; pass=$((pass + 1))
    else
        echo "FAIL appkit_documents"; sed 's/^/    /' "$build/appkit_documents.diff"
        sed 's/^/    stderr: /' "$build/appkit_documents.err"
        fail=$((fail + 1))
    fi
else
    echo "FAIL appkit_documents (did not compile)"; sed 's/^/    /' "$build/appkit_documents.cc.log"
    fail=$((fail + 1))
fi
# Images (M7), in an app bundle the test writes its image files into: it
# runs from there, so imageNamed: finds them. No image files are kept here.
app="$build/ImageApp.app"
rm -rf "$app"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if "$top/sdk/ferry-cc" -O1 -fobjc-arc -o "$app/Contents/MacOS/ImageApp" "$here/appkit/image.m" -framework Cocoa \
        -framework ImageIO 2> "$build/appkit_image.cc.log"; then
    env -u WAYLAND_DISPLAY -u DISPLAY "$top/ferry" "$app/Contents/MacOS/ImageApp" \
        > "$build/appkit_image.got" 2> "$build/appkit_image.err"
    echo "exit=$?" >> "$build/appkit_image.got"
    if diff -u "$here/appkit/image.out" "$build/appkit_image.got" > "$build/appkit_image.diff"; then
        echo "ok   appkit_image"; pass=$((pass + 1))
    else
        echo "FAIL appkit_image"; sed 's/^/    /' "$build/appkit_image.diff"; sed 's/^/    stderr: /' "$build/appkit_image.err"
        fail=$((fail + 1))
    fi
else
    echo "FAIL appkit_image (did not compile)"; sed 's/^/    /' "$build/appkit_image.cc.log"
    fail=$((fail + 1))
fi
# Ferry's Installer: a package made by make_pkg.py (two components, gzip/odc
# and pbzx/newc payloads, a member that climbs out, a link), described and
# installed into test folders; the same package cut short; and a program
# started by its app bundle's folder.
inst="$build/installer"
rm -rf "$inst"; mkdir -p "$inst"
if python3 "$here/tools/make_pkg.py" "$inst/tiny.pkg"; then
    head -c 3000 "$inst/tiny.pkg" > "$inst/cut.pkg"
    (
        cd "$inst"
        "$top/ferry" tiny.pkg --info; echo "exit=$?"
        "$top/ferry" tiny.pkg --install --applications Apps --root root; echo "exit=$?"
        find Apps root | sort
        echo "link: $(readlink Apps/Tiny.app/Contents/Resources)"
        [ -e escaped.txt ] || [ -e ../escaped.txt ] && echo "a member climbed out"
        tail -1 root/usr/local/bin/tiny-tool
        "$top/ferry" cut.pkg --install --applications Apps2 --root root2 2>&1; echo "exit=$?"
    ) > "$build/installer.got" 2> "$build/installer.err"
    mkdir -p "$build/Bundled.app/Contents/MacOS"
    cp "$build/hello" "$build/Bundled.app/Contents/MacOS/Bundled"
    FERRY_TEST_VALUE=tide "$top/ferry" "$build/Bundled.app" boat >> "$build/installer.got" 2>> "$build/installer.err"
    echo "exit=$?" >> "$build/installer.got"
    if diff -u "$here/installer.out" "$build/installer.got" > "$build/installer.diff"; then
        echo "ok   installer"; pass=$((pass + 1))
    else
        echo "FAIL installer"; sed 's/^/    /' "$build/installer.diff"; sed 's/^/    stderr: /' "$build/installer.err"
        fail=$((fail + 1))
    fi
else
    echo "FAIL installer (make_pkg.py failed)"; fail=$((fail + 1))
fi
# An exception nobody catches ends the program with the Mac's message.
if grep -q "Terminating app due to uncaught exception 'NSRangeException'" "$build/foundation_exception.err" 2>/dev/null; then
    echo "ok   foundation_exception message"; pass=$((pass + 1))
else
    echo "FAIL foundation_exception message"; fail=$((fail + 1))
fi
if grep -q "raised NSInternalInconsistencyException (timer 2 went wrong) and didn't catch it" \
        "$build/appkit_report.err" 2>/dev/null; then
    echo "ok   appkit_report message"; pass=$((pass + 1))
else
    echo "FAIL appkit_report message"; sed 's/^/    stderr: /' "$build/appkit_report.err"; fail=$((fail + 1))
fi
# The missing framework, class and function are each named.
if grep -q "uses Imaginary, which Ferry doesn't provide yet; carrying on" "$build/foundation_missing.err" 2>/dev/null &&
        grep -q "the class MyThing is built on a class Ferry doesn't have yet" "$build/foundation_missing.err" &&
        grep -q "uses 1 Objective-C class Ferry" "$build/foundation_missing.err" &&
        grep -q "uses IMDoSomething, which Ferry doesn't support yet" "$build/foundation_missing.err"; then
    echo "ok   foundation_missing messages"; pass=$((pass + 1))
else
    echo "FAIL foundation_missing messages"; sed 's/^/    stderr: /' "$build/foundation_missing.err"; fail=$((fail + 1))
fi
# An unknown selector must be reported as a Mac reports it.
if grep -q "unrecognized selector sent to instance" "$build/objc_unknown.err" 2>/dev/null; then
    echo "ok   objc_unknown message"; pass=$((pass + 1))
else
    echo "FAIL objc_unknown message"; fail=$((fail + 1))
fi
# ... and so must one through Foundation's forwarding.
if grep -q "\-\[NSObject frobnicate\]: unrecognized selector sent to instance" "$build/foundation_invocation.err" 2>/dev/null; then
    echo "ok   foundation_invocation message"; pass=$((pass + 1))
else
    echo "FAIL foundation_invocation message"; sed 's/^/    stderr: /' "$build/foundation_invocation.err"; fail=$((fail + 1))
fi
# The unsupported program must also say what was missing.
if grep -q "pthread_yield_np" "$build/unsupported.err" 2>/dev/null; then
    echo "ok   unsupported message"; pass=$((pass + 1))
else
    echo "FAIL unsupported message"; fail=$((fail + 1))
fi
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
