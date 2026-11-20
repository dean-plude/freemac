#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the link stub for a Mac framework that one of Ferry's own framework
# files serves (CoreText and ApplicationServices live in CoreGraphics' file):
# the calls the file exports for that framework, under the framework's own
# Mac install name. A program linked against it records the framework as a
# Mac-built one would, and Ferry's loader serves that name from the file.
#
#   gen-alias-tbd.sh frameworks/CoreGraphics.framework/CoreGraphics CoreText > CoreText.tbd
set -eu
nm=$(command -v llvm-nm 2>/dev/null || ls /usr/lib/llvm-*/bin/llvm-nm 2>/dev/null | head -n 1)
if [ -z "$nm" ]; then
    echo "gen-alias-tbd.sh: llvm-nm (package llvm) isn't installed" >&2
    exit 1
fi
case $2 in
    CoreText) pattern='^_(CT|kCT)' ;;
    ApplicationServices) pattern='^_(CG|kCG|CT|kCT)' ;;
    *) echo "gen-alias-tbd.sh: unknown framework $2" >&2; exit 2 ;;
esac
{
    echo '--- !tapi-tbd'
    echo 'tbd-version:     4'
    echo 'targets:         [ x86_64-macos ]'
    echo "install-name:    '/System/Library/Frameworks/$2.framework/Versions/A/$2'"
    echo 'current-version: 1.0.0'
    echo 'exports:'
    echo '  - targets:     [ x86_64-macos ]'
    echo '    symbols:     [ '
    "$nm" -gU "$1" | awk '{print $3}' | grep -E "$pattern" | sort -u |
        sed "s/.*/                   '&',/" | sed '$ s/,$/ ]/'
    echo '...'
}
