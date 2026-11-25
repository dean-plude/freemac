# SPDX-License-Identifier: GPL-3.0-or-later
#
# Swift programs (freemac 1.227), sourced by tests/run.sh: built with
# sdk/ferry-swiftc against Ferry's Swift runtime and modules, run through
# ./ferry with no display, and compared with NAME.out like the others.
#
#   hello              Swift's standard library: printing, arrays, sorting,
#                      dictionaries
#   foundation         String, Array, Dictionary and numbers to and from
#                      their NS classes, NSString's methods on Swift strings,
#                      a Swift class that is an NSObject, and Swift's own
#                      strings as NSDictionary keys
#   appkit_window      an NSApplication delegate written in Swift, a window,
#                      a button's target and action
#   swiftui_counter    Ferry's SwiftUI: @State, Text, Button, VStack, HStack
#                      and Toggle, its buttons pressed in turn
#   swiftui_app        an ObservableObject, List, ForEach, TextField,
#                      Picker, Settings and a MenuBarExtra
#   swiftui_hosting    NSHostingView (a generic NSView subclass) in an
#                      AppKit program
#   swiftui_grid       GroupBox, LazyVGrid, a Stepper and a Slider with
#                      label views, a Button whose label is several views,
#                      NSLocalizedString, the gesture modifiers, @FocusState
#                      and an NSViewRepresentable with a coordinator
#   dispatch           the Dispatch overlay (freemac 1.230): queues, sync and
#                      async, groups, semaphores, work items, times, and a
#                      timer source ticking on the main queue
#   concurrency        Swift's concurrency library: tasks, actors, task
#                      groups, Task.sleep, cancellation and the main actor
#   values             Foundation's value types (freemac 1.230): Date, Data,
#                      URL and UUID to and from their NS classes, JSONEncoder
#                      and JSONDecoder with Codable, FileHandle's Swift
#                      methods, String.Encoding, DateComponentsFormatter
#   swiftui_tasks      .task and .task(id:), .onReceive, a ViewModifier,
#                      LabeledContent, alignmentGuide, keyboard shortcuts'
#                      localization, the environment's locale and #Preview
#                      (freemac 1.230); the driver waits for views' tasks
#   swiftui_drawing    shapes (a Shape of its own too), an overlay and a
#                      background by alignment, a GeometryReader, an alert
#                      and a sheet, their buttons pressed (freemac 1.230)
#   mixed              an Objective-C program using a Swift class, through
#                      the header ferry-swiftc writes (-emit-objc-header-path),
#                      the Swift built as a library beside it (@rpath)
#
# They need a swift.org toolchain (FERRY_SWIFT_TOOLCHAIN, or swift-frontend
# on PATH) and Swift's runtime built for Ferry (swift/build-runtime.sh); with
# either missing they are skipped. Ferry's own Swift modules are brought up
# to date first (swift/build-modules.sh does nothing when they are).

swift_tests="swift_hello swift_foundation swift_appkit_window swift_swiftui_counter swift_swiftui_app swift_swiftui_hosting swift_swiftui_grid swift_dispatch swift_concurrency swift_values swift_combine swift_services swift_appkit_names swift_swiftui_tasks swift_swiftui_drawing swift_mixed"
swift_tc=${FERRY_SWIFT_TOOLCHAIN:-}
if [ -z "$swift_tc" ] && command -v swift-frontend > /dev/null 2>&1; then
    swift_tc=$(dirname "$(dirname "$(command -v swift-frontend)")")
fi
if [ -z "$swift_tc" ] || [ ! -x "$swift_tc/usr/bin/swift-frontend" ]; then
    echo "skip $swift_tests (need a Swift toolchain: FERRY_SWIFT_TOOLCHAIN, or swift-frontend on PATH)"
elif [ ! -f "$top/frameworks/swift/libswiftCore.dylib" ] || [ ! -f "$top/frameworks/swift/libswift_Concurrency.dylib" ]; then
    echo "skip $swift_tests (need Swift's runtime, with its concurrency library, built for Ferry: swift/build-runtime.sh)"
elif ! FERRY_SWIFT_TOOLCHAIN="$swift_tc" sh "$top/swift/build-modules.sh" > "$build/swift_modules.log" 2>&1; then
    echo "FAIL swift modules (swift/build-modules.sh)"; sed 's/^/    /' "$build/swift_modules.log"
    fail=$((fail + 1))
else
    # swift_one NAME [ENV...]: build tests/swift/NAME.swift, run it with the
    # environment given, and compare with NAME.out
    swift_one() {
        sname=$1; shift
        exe="$build/swift_$sname"
        rm -f "$exe"
        if ! FERRY_SWIFT_TOOLCHAIN="$swift_tc" "$top/sdk/ferry-swiftc" -o "$exe" "$here/swift/$sname.swift" \
                > "$build/swift_$sname.cc.log" 2>&1 || [ ! -x "$exe" ]; then
            echo "FAIL swift_$sname (did not compile)"; sed 's/^/    /' "$build/swift_$sname.cc.log"
            fail=$((fail + 1)); return
        fi
        rm -rf "$build/home_swift_$sname"; mkdir -p "$build/home_swift_$sname"
        env -u DISPLAY -u WAYLAND_DISPLAY HOME="$build/home_swift_$sname" TMPDIR="$build/home_swift_$sname" \
            XDG_CONFIG_HOME= XDG_DATA_HOME= XDG_CACHE_HOME= "$@" \
            timeout 60 "$top/ferry" "$exe" > "$build/swift_$sname.got" 2> "$build/swift_$sname.err"
        echo "exit=$?" >> "$build/swift_$sname.got"
        if diff -u "$here/swift/$sname.out" "$build/swift_$sname.got" > "$build/swift_$sname.diff"; then
            echo "ok   swift_$sname"; pass=$((pass + 1))
        else
            echo "FAIL swift_$sname"; sed 's/^/    /' "$build/swift_$sname.diff"
            sed 's/^/    stderr: /' "$build/swift_$sname.err"
            fail=$((fail + 1))
        fi
    }
    swift_one hello
    swift_one foundation
    swift_one appkit_window
    swift_one swiftui_counter FERRY_SWIFTUI_CLICK="+,+,+,Doubled,-"
    swift_one swiftui_app "FERRY_SWIFTUI_CLICK=Add,Grid,menu:Add Figs,menu:Settings…"
    swift_one swiftui_hosting
    swift_one swiftui_grid "FERRY_SWIFTUI_CLICK=Long,Start"
    swift_one dispatch
    swift_one concurrency
    swift_one values
    swift_one combine
    swift_one services OS_ACTIVITY_DT_MODE=1 FERRY_SOUND_PLAYER=/bin/true
    swift_one appkit_names
    swift_one swiftui_tasks "FERRY_SWIFTUI_CLICK=Next,Next"
    swift_one swiftui_drawing "FERRY_SWIFTUI_CLICK=Ask,Now,Sheet,Done"

    # mixed: mixed.swift becomes libMixed.dylib and Mixed-Swift.h, which
    # mixed.m imports and links
    rm -rf "$build/swift_mixed.d"; mkdir -p "$build/swift_mixed.d"
    if ! (cd "$build/swift_mixed.d" &&
          FERRY_SWIFT_TOOLCHAIN="$swift_tc" "$top/sdk/ferry-swiftc" -emit-library -module-name Mixed \
              -emit-objc-header-path Mixed-Swift.h "$here/swift/mixed.swift" -o libMixed.dylib &&
          FERRY_MACOS_MIN=14.0 "$top/sdk/ferry-cc" -fobjc-arc -I . -framework Foundation "$here/swift/mixed.m" \
              libMixed.dylib -Xlinker -rpath -Xlinker @executable_path -o mixed) \
            > "$build/swift_mixed.cc.log" 2>&1; then
        echo "FAIL swift_mixed (did not compile)"; sed 's/^/    /' "$build/swift_mixed.cc.log"
        fail=$((fail + 1))
    else
        env -u DISPLAY -u WAYLAND_DISPLAY timeout 60 "$top/ferry" "$build/swift_mixed.d/mixed" \
            > "$build/swift_mixed.got" 2> "$build/swift_mixed.err"
        echo "exit=$?" >> "$build/swift_mixed.got"
        if diff -u "$here/swift/mixed.out" "$build/swift_mixed.got" > "$build/swift_mixed.diff"; then
            echo "ok   swift_mixed"; pass=$((pass + 1))
        else
            echo "FAIL swift_mixed"; sed 's/^/    /' "$build/swift_mixed.diff"
            sed 's/^/    stderr: /' "$build/swift_mixed.err"
            fail=$((fail + 1))
        fi
    fi
fi
