# SPDX-License-Identifier: GPL-3.0-or-later
"""Makes the asset catalogue tests/appkit/assets.m reads (freemac 1.224,
Ferry 0.48.0), compiles it with ferry-actool into an app bundle, and puts
the app icon's names in the bundle's Info.plist, as an app's build does:

    make_assets.py FERRY_ACTOOL SOURCE_DIR APP.app

The pictures are plain PNG files of one colour, made here."""
import json
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import zlib


def png(path, w, h, rgba):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    row = b"\x00" + bytes(rgba) * w
    body = zlib.compress(row * h)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", body) + chunk(b"IEND", b""))


def folder(path, contents):
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)


INFO = {"version": 1, "author": "xcode"}


def main(actool, src, app):
    shutil.rmtree(src, ignore_errors=True)
    cat = os.path.join(src, "Assets.xcassets")
    folder(cat, {"info": INFO})

    # a status-bar picture at two scales, drawn as a template
    s = os.path.join(cat, "StatusIcon.imageset")
    folder(s, {"images": [{"idiom": "mac", "filename": "status.png", "scale": "1x"},
                          {"idiom": "mac", "filename": "status@2x.png", "scale": "2x"},
                          {"idiom": "universal", "filename": "ios.png", "scale": "1x"}],
               "info": INFO, "properties": {"template-rendering-intent": "template"}})
    png(os.path.join(s, "status.png"), 14, 16, (0, 0, 0, 255))
    png(os.path.join(s, "status@2x.png"), 28, 32, (0, 0, 0, 255))
    png(os.path.join(s, "ios.png"), 99, 99, (0, 0, 0, 255))

    # a picture with a dark version, and one whose name says Template
    s = os.path.join(cat, "Badge.imageset")
    folder(s, {"images": [{"idiom": "universal", "filename": "light.png", "scale": "1x"},
                          {"idiom": "universal", "filename": "dark.png", "scale": "1x",
                           "appearances": [{"appearance": "luminosity", "value": "dark"}]},
                          {"idiom": "universal", "filename": "contrast.png", "scale": "1x",
                           "appearances": [{"appearance": "contrast", "value": "high"}]}],
               "info": INFO})
    png(os.path.join(s, "light.png"), 20, 10, (255, 0, 0, 255))
    png(os.path.join(s, "dark.png"), 20, 10, (0, 0, 255, 255))
    png(os.path.join(s, "contrast.png"), 20, 10, (0, 255, 0, 255))
    s = os.path.join(cat, "ArrowTemplate.imageset")
    folder(s, {"images": [{"idiom": "universal", "filename": "arrow.png", "scale": "1x"}], "info": INFO})
    png(os.path.join(s, "arrow.png"), 8, 8, (0, 0, 0, 255))

    # a folder that gives its assets a namespace, and one that doesn't
    ns = os.path.join(cat, "Toolbar")
    folder(ns, {"info": INFO, "properties": {"provides-namespace": True}})
    s = os.path.join(ns, "Star.imageset")
    folder(s, {"images": [{"idiom": "universal", "filename": "star.png", "scale": "2x"}], "info": INFO})
    png(os.path.join(s, "star.png"), 24, 24, (255, 200, 0, 255))
    plain = os.path.join(cat, "Group")
    folder(plain, {"info": INFO})
    s = os.path.join(plain, "Dot.imageset")
    folder(s, {"images": [{"idiom": "universal", "filename": "dot.png"}], "info": INFO})
    png(os.path.join(s, "dot.png"), 4, 4, (0, 128, 0, 255))

    # colours: floating-point components with a dark version, 0 to 255
    # integers, hex, a grey and a system colour
    def colorset(name, colors):
        folder(os.path.join(cat, name + ".colorset"), {"colors": colors, "info": INFO})
    colorset("AccentColor", [
        {"idiom": "universal", "color": {"color-space": "srgb", "components":
                                         {"red": "0.200", "green": "0.400", "blue": "0.600", "alpha": "1.000"}}},
        {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}],
         "color": {"color-space": "srgb", "components": {"red": "1", "green": "1", "blue": "1", "alpha": "1"}}}])
    colorset("Brand", [{"idiom": "universal", "color": {"color-space": "srgb", "components":
                                                        {"red": "255", "green": "128", "blue": "0", "alpha": "0.5"}}}])
    colorset("Hex", [{"idiom": "universal", "color": {"color-space": "display-p3", "components":
                                                      {"red": "0x00", "green": "0x80", "blue": "0xFF", "alpha": "1"}}}])
    colorset("Shade", [{"idiom": "universal", "color": {"color-space": "gray-gamma-22", "components":
                                                        {"white": "0.250", "alpha": "1.000"}}}])
    colorset("LinkColor", [{"idiom": "mac", "color": {"platform": "osx", "reference": "systemBlueColor"}}])

    # data
    d = os.path.join(cat, "Notes.dataset")
    folder(d, {"data": [{"idiom": "universal", "filename": "notes.txt", "universal-type-identifier":
                         "public.plain-text"}], "info": INFO})
    with open(os.path.join(d, "notes.txt"), "w") as f:
        f.write("hello from a data asset\n")

    # the app icon, and a kind that isn't compiled
    icon = os.path.join(cat, "AppIcon.appiconset")
    os.makedirs(icon)
    images = []
    for pts, scale in ((16, 1), (16, 2), (32, 1), (32, 2), (128, 1)):
        name = "icon_%d@%dx.png" % (pts, scale)
        png(os.path.join(icon, name), pts * scale, pts * scale, (40, 90, 200, 255))
        images.append({"idiom": "mac", "size": "%dx%d" % (pts, pts), "scale": "%dx" % scale, "filename": name})
    images.append({"idiom": "mac", "size": "256x256", "scale": "1x"})   # an empty slot
    folder(icon, {"images": images, "info": INFO})
    folder(os.path.join(cat, "Gear.symbolset"), {"info": INFO})

    res = os.path.join(app, "Contents", "Resources")
    partial = os.path.join(src, "partial.plist")
    r = subprocess.run([actool, "--compile", res, "--app-icon", "AppIcon", "--output-partial-info-plist", partial,
                        "--platform", "macosx", cat], capture_output=True, text=True)
    sys.stderr.write(r.stderr)
    if r.returncode:
        return r.returncode
    info_path = os.path.join(app, "Contents", "Info.plist")
    with open(info_path, "rb") as f:
        info = plistlib.load(f)
    with open(partial, "rb") as f:
        info.update(plistlib.load(f))
    with open(info_path, "wb") as f:
        plistlib.dump(info, f)
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
