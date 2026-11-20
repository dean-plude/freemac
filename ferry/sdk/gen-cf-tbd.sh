#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the link stub for CoreFoundation.framework: the CF calls Ferry's
# Foundation file exports, under CoreFoundation's own Mac install name. A
# program linked against it records CoreFoundation as a Mac-built one would,
# and Ferry's loader serves that name from Foundation.
#
#   gen-cf-tbd.sh frameworks/Foundation.framework/Foundation > CoreFoundation.tbd
set -eu
nm=$(command -v llvm-nm 2>/dev/null || ls /usr/lib/llvm-*/bin/llvm-nm 2>/dev/null | head -n 1)
if [ -z "$nm" ]; then
    echo "gen-cf-tbd.sh: llvm-nm (package llvm) isn't installed" >&2
    exit 1
fi
{
    echo '--- !tapi-tbd'
    echo 'tbd-version:     4'
    echo 'targets:         [ x86_64-macos ]'
    echo "install-name:    '/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation'"
    echo 'current-version: 1.0.0'
    echo 'exports:'
    echo '  - targets:     [ x86_64-macos ]'
    echo '    symbols:     [ '
    "$nm" -gU "$1" | awk '{print $3}' | grep -E '^(_CF|_kCF|___CFConstantStringClassReference$)' | sort -u |
        sed "s/.*/                   '&',/" | sed '$ s/,$/ ]/'
    echo '...'
}
