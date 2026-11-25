#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   apps/tomatobar.sh [WORK]
#
# TomatoBar (github.com/ivoronin/TomatoBar, MIT), a SwiftUI Pomodoro timer
# in the menu bar, built for Ferry (freemac 1.231, Ferry 0.55.0; it first
# ran in freemac 1.230). Its three Swift packages are fetched at the
# commits its own Package.resolved pins and built as libraries with
# ferry-swiftc, then TomatoBar against them, and the bundle is laid out as
# Xcode lays it out: the program in Contents/MacOS, the libraries in
# Contents/Frameworks, its asset catalogue compiled by ferry-actool, its
# localizations, and KeyboardShortcuts' resource bundle. Run it with
#
#   ./ferry WORK/build/TomatoBar/TomatoBar.app
#
# See apps/recipe.sh for WORK and what a recipe needs.
recipe_name=tomatobar
. "$(dirname "$0")/recipe.sh"

fetch TomatoBar https://github.com/ivoronin/TomatoBar 90a77d664dfe33c016bf24f89b0c82e77f9aec84
# TomatoBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
fetch SwiftState https://github.com/ReactKit/SwiftState 887e75b96da6be36a062e1b0ef832c32a803348b
fetch LaunchAtLogin https://github.com/sindresorhus/LaunchAtLogin 9a894d799269cb591037f9f9cb0961510d4dca81
fetch KeyboardShortcuts https://github.com/sindresorhus/KeyboardShortcuts 1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27

build=$work/build/TomatoBar
rm -rf "$build"
mkdir -p "$build"
need_swift

ks=$src/KeyboardShortcuts/Sources/KeyboardShortcuts
resource_bundle KeyboardShortcuts_KeyboardShortcuts "$build/KeyboardShortcuts_bundle.swift"
swift_lib SwiftState "$src"/SwiftState/Sources/*.swift
swift_lib LaunchAtLogin "$src"/LaunchAtLogin/Sources/LaunchAtLogin/*.swift
swift_lib KeyboardShortcuts "$ks"/*.swift "$build/KeyboardShortcuts_bundle.swift"

say "building TomatoBar"
a=$src/TomatoBar/TomatoBar
(cd "$build" && "$sdk/ferry-swiftc" -module-name TomatoBar -I "$build/mods" -L "$build" "$a"/*.swift \
     -lSwiftState -lLaunchAtLogin -lKeyboardShortcuts \
     -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$build/TomatoBar") > "$build/TomatoBar.log" 2>&1 ||
    { grep -E 'error:' "$build/TomatoBar.log" | head -20 >&2; die "TomatoBar didn't build (its log: $build/TomatoBar.log)"; }

say "bundling TomatoBar.app"
c=$build/TomatoBar.app/Contents
mkdir -p "$c/MacOS" "$c/Frameworks" "$c/Resources"
cp "$build/TomatoBar" "$c/MacOS/TomatoBar"
cp "$build"/libSwiftState.dylib "$build"/libLaunchAtLogin.dylib "$build"/libKeyboardShortcuts.dylib "$c/Frameworks/"
python3 -I "$sdk/ferry-actool" --compile "$c/Resources" --app-icon AppIcon \
    --output-partial-info-plist "$build/assets.plist" "$a/Assets.xcassets" > "$build/actool.log" 2>&1 ||
    { cat "$build/actool.log" >&2; die "its asset catalogue didn't compile"; }
for l in "$a"/*.lproj; do cp -R "$l" "$c/Resources/"; done
ksb=$c/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle/Contents
mkdir -p "$ksb/Resources"
cp -R "$ks"/Localization/* "$ksb/Resources/"
# Info.plist: the app's own, with what Xcode's build settings fill in
# (TomatoBar.xcodeproj: its bundle identifier, version 3.0 and the rest)
python3 -I - "$a/Info.plist" "$build/assets.plist" "$c/Info.plist" "$ksb/Info.plist" <<'EOF'
import os, plistlib, sys
src, assets, out, ks = sys.argv[1:]
with open(src, 'rb') as f:
    info = plistlib.load(f)
info.update({
    'CFBundleExecutable': 'TomatoBar', 'CFBundleIdentifier': 'com.github.ivoronin.TomatoBar',
    'CFBundleName': 'TomatoBar', 'CFBundleDisplayName': 'TomatoBar', 'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '3.0', 'CFBundleVersion': '1', 'CFBundleDevelopmentRegion': 'en',
    'CFBundleInfoDictionaryVersion': '6.0', 'LSMinimumSystemVersion': '11.0', 'LSUIElement': True,
    'LSApplicationCategoryType': 'public.app-category.productivity',
    'NSHumanReadableCopyright': 'Copyright © 2023 Ilya Voronin. All rights reserved.',
    'NSPrincipalClass': 'NSApplication',
})
if os.path.exists(assets):
    with open(assets, 'rb') as f:
        info.update(plistlib.load(f))
with open(out, 'wb') as f:
    plistlib.dump(info, f)
with open(ks, 'wb') as f:
    plistlib.dump({'CFBundleIdentifier': 'KeyboardShortcuts.KeyboardShortcuts.resources',
                   'CFBundleName': 'KeyboardShortcuts_KeyboardShortcuts', 'CFBundlePackageType': 'BNDL',
                   'CFBundleDevelopmentRegion': 'en', 'CFBundleInfoDictionaryVersion': '6.0'}, f)
EOF
say "done: $build/TomatoBar.app"
