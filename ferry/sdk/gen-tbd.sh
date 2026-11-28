#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the Ferry SDK's description of a Mac library (a text-based stub that
# the linker reads) from the list of calls Ferry itself provides.
#
#   gen-tbd.sh ./ferry libSystem    > libSystem.tbd
#   gen-tbd.sh ./ferry libobjc      > libobjc.tbd
#   gen-tbd.sh ./ferry libFerryHost > libFerryHost.tbd   (Ferry's own frameworks only)
#   gen-tbd.sh ./ferry libiconv     > libiconv.tbd       (GNU libiconv's calls, in libSystem's table)
#   gen-tbd.sh ./ferry libcompression > libcompression.tbd (compression.c's calls, likewise)
set -eu
ferry=${1:-./ferry}
lib=${2:-libSystem}
case $lib in
    libSystem) install=/usr/lib/libSystem.B.dylib; extra="dyld_stub_binder," ;;
    libobjc) install=/usr/lib/libobjc.A.dylib; extra= ;;
    libFerryHost) install=/usr/lib/ferry/libFerryHost.dylib; extra= ;;
    libiconv) install=/usr/lib/libiconv.2.dylib; extra= ;;
    libcompression) install=/usr/lib/libcompression.dylib; extra= ;;
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
    # GNU libiconv's calls are in Ferry's libSystem table, but a Mac has them
    # in their own library, so a program links -liconv for them as on a Mac.
    iconv='^_(lib)?iconv(_open|_close|ctl)?$|^_locale_charset$|^__libiconv_version$'
    compression='^_compression_'
    case $lib in
        libiconv) "$ferry" --list-symbols=libSystem | grep -E "$iconv" ;;
        libcompression) "$ferry" --list-symbols=libSystem | grep -E "$compression" ;;
        libSystem) "$ferry" --list-symbols=libSystem | grep -vE "$iconv|$compression" ;;
        *) "$ferry" --list-symbols="$lib" ;;
    esac | sort -u | sed "s/.*/                   '&',/" | sed '$ s/,$/ ]/'
    echo '...'
}
