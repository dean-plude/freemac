#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Tests for ferry-mslc, Ferry's Metal shader compiler: builds tests/basic.metal
# as a Mac library (checking that it links), then builds the same shader code
# for this Linux PC and runs it with a small stand-in for Metal.framework,
# checking what each vertex, fragment and kernel function computes.
set -e
here=$(cd "$(dirname "$0")" && pwd)
msl=$here/../msl
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
FERRY_MSLC_KEEP=$tmp/basic.clcpp "$here/../ferry-mslc" build "$here/basic.metal" -o "$tmp/basic.dylib" --fc 0=true --fc 1=2.0
"$here/../ferry-mslc" reflect "$here/basic.metal" > "$tmp/basic.json"
python3 -c "import json,sys; f=json.load(open(sys.argv[1]))['functions']; assert [x['name'] for x in f]==['vs_main','fs_main','add'], f" "$tmp/basic.json"
clang -x clcpp -cl-std=clc++2021 -cl-no-stdinc -cl-single-precision-constant -target x86_64-linux-gnu -fdeclspec \
    -O2 -I "$msl" -c "$tmp/basic.clcpp" -o "$tmp/basic.o"
clang -O1 -w -I "$msl" "$here/basic-harness.c" "$tmp/basic.o" -o "$tmp/basic" -lm
"$tmp/basic" > "$tmp/out.txt" 2>/dev/null
cat > "$tmp/want.txt" <<'WANT'
pos 6 12 1 1  vary 0.25 0.75 | 1 0 0 | 3
 vs slot position what 1 off 0 n 4 kind 0
 vs slot uv what 0 off 16 n 2 kind 0
 vs slot colour what 0 off 18 n 3 kind 0
 vs slot id what 0 off 21 n 1 kind 3
 fs slot color what 4 idx 0 off 0 n 4 kind 0 interp 0
 fs slot uv what 9 idx 0 off 0 n 2 kind 0 interp 0
 fs slot colour what 9 idx 1 off 0 n 3 kind 0 interp 0
 fs slot id what 9 idx 2 off 0 n 1 kind 3 interp 1
frag 0.2 0.3 0.5 5
add 11 22 33 44
WANT
diff -u "$tmp/want.txt" "$tmp/out.txt"
# Blender-style shader code builds, with a function-constant buffer index
"$here/../ferry-mslc" build "$here/blender-style.metal" -o "$tmp/blender.dylib" --fcname base_index=2
"$here/../ferry-mslc" reflect "$here/blender-style.metal" --fcname base_index=2 > "$tmp/blender.json"
python3 -c "
import json, sys
f = {x['name']: x for x in json.load(open(sys.argv[1]))['functions']}
assert [b['index'] for b in f['vs_main']['buffers']] == [3], f['vs_main']['buffers']
assert [b['index'] for b in f['fs_main']['buffers']] == [2], f['fs_main']['buffers']
" "$tmp/blender.json"
echo "ferry-mslc: all tests passed"
