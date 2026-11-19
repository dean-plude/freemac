#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Build Strata's Wayfire plugins. Run inside the image (the ISO build does
# this in its chroot) with g++, pkg-config and wayfire-dev installed.
# Usage: build.sh OUTDIR   -> OUTDIR/libstrata-decor.so
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build.sh OUTDIR}
mkdir -p "$OUT"
INC="$(pkg-config --variable=includedir wayfire)/wayfire"
# The plugins follow Wayfire's plugin API as of ABI 2023-11-23 (the Wayfire
# that Ubuntu 24.04 ships). Other versions changed that API.
if ! grep -q "WAYFIRE_API_ABI_VERSION = 2023'11'23" "$INC/plugin.hpp"; then
  echo "strata: this Wayfire ($(pkg-config --modversion wayfire)) uses another plugin API; skipping the plugins" >&2
  exit 2
fi
FLAGS="-std=c++17 -O2 -fPIC -shared -DWLR_USE_UNSTABLE -DWAYFIRE_PLUGIN -I$INC"
# shellcheck disable=SC2046,SC2086
g++ $FLAGS $(pkg-config --cflags wayfire wlroots cairo pangocairo pixman-1 wf-config) \
  "$HERE"/decor/*.cpp -o "$OUT/libstrata-decor.so" $(pkg-config --libs cairo pangocairo)
echo "strata: built $OUT/libstrata-decor.so"
