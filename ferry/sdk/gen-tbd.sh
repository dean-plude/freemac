#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the Ferry SDK's description of a Mac library (a text-based stub that
# the linker reads) from the list of calls Ferry itself provides.
#
#   gen-tbd.sh ./ferry libSystem    > libSystem.tbd
#   gen-tbd.sh ./ferry libobjc      > libobjc.tbd
#   gen-tbd.sh ./ferry libFerryHost > libFerryHost.tbd   (Ferry's own frameworks only)
set -eu
ferry=${1:-./ferry}
lib=${2:-libSystem}
case $lib in
    libSystem) install=/usr/lib/libSystem.B.dylib; extra="dyld_stub_binder," ;;
    libobjc) install=/usr/lib/libobjc.A.dylib; extra= ;;
    libFerryHost) install=/usr/lib/ferry/libFerryHost.dylib; extra= ;;
    *) echo "gen-tbd.sh: unknown library $lib" >&2; exit 2 ;;
esac
{
    echo '--- !tapi-tbd'
    echo 'tbd-version:     4'
    echo 'targets:         [ x86_64-macos ]'
    echo "install-name:    '$install'"
    echo 'current-version: 1.0.0'
    echo 'exports:'
    echo '  - targets:     [ x86_64-macos ]'
    echo "    symbols:     [ $extra"
    "$ferry" --list-symbols="$lib" | sort -u | sed "s/.*/                   '&',/" | sed '$ s/,$/ ]/'
    echo '...'
}
