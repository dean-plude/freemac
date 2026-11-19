#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the Ferry SDK's description of libSystem (a text-based stub that
# the linker reads) from the list of calls Ferry itself provides.
set -eu
ferry=${1:-./ferry}
{
    echo '--- !tapi-tbd'
    echo 'tbd-version:     4'
    echo 'targets:         [ x86_64-macos ]'
    echo "install-name:    '/usr/lib/libSystem.B.dylib'"
    echo 'current-version: 1.0.0'
    echo 'exports:'
    echo '  - targets:     [ x86_64-macos ]'
    echo '    symbols:     [ dyld_stub_binder,'
    "$ferry" --list-symbols | sort -u | sed "s/.*/                   '&',/" | sed '$ s/,$/ ]/'
    echo '...'
} 
