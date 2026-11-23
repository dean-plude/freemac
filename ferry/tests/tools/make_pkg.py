#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds a small Mac installer package (a flat .pkg) for Ferry's Installer
# tests, from the public description of the format: a xar archive (a 28-byte
# header, a zlib-compressed XML table of contents, then a heap of members)
# holding a Distribution, its welcome and licence, and two components. One
# component's Payload is a gzip'd cpio archive in the portable (odc) form, the
# other a "pbzx" one (xz chunks) in the newc form. Nothing here comes from Apple.
#
#   make_pkg.py OUT.pkg
import gzip, hashlib, lzma, struct, sys, zlib

def odc(entries):
    out = b""
    for ino, (name, mode, data) in enumerate(entries + [("TRAILER!!!", 0, b"")], 1):
        n = name.encode() + b"\0"
        out += b"070707" + b"%06o%06o%06o%06o%06o%06o%06o%011o%06o%011o" % (
            0, ino, mode, 0, 0, 1, 0, 0, len(n), len(data)) + n + data
    return out

def newc(entries):
    out = b""
    def pad(b):
        return b + b"\0" * ((4 - len(b) % 4) % 4)
    for ino, (name, mode, data) in enumerate(entries + [("TRAILER!!!", 0, b"")], 1):
        n = name.encode() + b"\0"
        head = b"070701" + b"".join(b"%08X" % v for v in (
            ino, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(n), 0))
        out += pad(head + n) + pad(data)
    return out

def pbzx(data, chunk=64):
    out = b"pbzx" + struct.pack(">Q", chunk)
    for i in range(0, len(data), chunk):
        piece = data[i:i + chunk]
        packed = lzma.compress(piece, format=lzma.FORMAT_XZ)
        out += struct.pack(">QQ", len(piece), len(packed)) + packed
    return out

DIR, FILE, LINK = 0o040755, 0o100644, 0o120777
plist = b"""<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Tiny</string>
<key>CFBundleIdentifier</key><string>org.freemac.ferry.tiny</string>
</dict></plist>
"""
app_payload = odc([
    (".", DIR, b""),
    ("./Tiny.app", DIR, b""),
    ("./Tiny.app/Contents", DIR, b""),
    ("./Tiny.app/Contents/Info.plist", FILE, plist),
    ("./Tiny.app/Contents/MacOS", DIR, b""),
    ("./Tiny.app/Contents/MacOS/Tiny", 0o100755, b"not really a program\n"),
    ("./Tiny.app/Contents/Resources", LINK, b"MacOS"),
    # climbs out of where it installs: must be left out
    ("./../../escaped.txt", FILE, b"should not be written\n"),
])
tool_payload = newc([
    ("bin", DIR, b""),
    ("bin/tiny-tool", 0o100755, b"#!/bin/sh\necho tiny\n" * 10),
    ("share/tiny/README", FILE, b"A tiny package for Ferry's tests.\n" * 4),
])

distribution = b"""<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>Tiny Test</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <license file="License.rtf"/>
    <options customize="never"/>
    <choices-outline><line choice="default"/></choices-outline>
    <choice id="default"><pkg-ref id="org.freemac.tiny.app"/><pkg-ref id="org.freemac.tiny.tool"/></choice>
    <pkg-ref id="org.freemac.tiny.app" version="1.0" installKBytes="4">#app.pkg</pkg-ref>
    <pkg-ref id="org.freemac.tiny.tool" version="2.0" installKBytes="2">#tool.pkg</pkg-ref>
</installer-gui-script>
"""
welcome = b"<html><body><h1>Hello</h1><p>This installs <b>Tiny</b>.</p></body></html>"
license_rtf = rb"{\rtf1\ansi{\fonttbl\f0 Helvetica;}\f0 Tiny licence: do as you like.\par}"

def package_info(ident, version, location, kbytes, files):
    return (b'<?xml version="1.0" encoding="utf-8"?>\n<pkg-info format-version="2" identifier="%s" version="%s" '
            b'install-location="%s" auth="root">\n    <payload installKBytes="%d" numberOfFiles="%d"/>\n</pkg-info>\n'
            % (ident.encode(), version.encode(), location.encode(), kbytes, files))

members = [
    ("Distribution", distribution, None),
    ("Resources", None, None),
    ("Resources/en.lproj", None, None),
    ("Resources/en.lproj/welcome.html", welcome, None),
    ("Resources/en.lproj/License.rtf", license_rtf, None),
    ("app.pkg", None, None),
    ("app.pkg/PackageInfo", package_info("org.freemac.tiny.app", "1.0", "/Applications", 4, 7), None),
    ("app.pkg/Payload", gzip.compress(app_payload, mtime=0), None),
    ("tool.pkg", None, None),
    ("tool.pkg/PackageInfo", package_info("org.freemac.tiny.tool", "2.0", "/usr/local", 2, 3), None),
    # the Distribution's checks would run this; Ferry says it doesn't
    ("tool.pkg/Scripts", b"not a real archive", None),
    ("tool.pkg/Payload", pbzx(tool_payload), None),
]

# Build the heap and the table of contents. The heap starts with the
# table's checksum (SHA-1), as xar writers put it.
heap = bytearray(20)
ids = iter(range(1, 1000))
def file_xml(path, children):
    name = path.split("/")[-1]
    entry = next(m for m in members if m[0] == path)
    data = entry[1]
    x = '<file id="%d"><name>%s</name>' % (next(ids), name)
    if data is None:
        x += "<type>directory</type>"
    else:
        packed = zlib.compress(data) if path.endswith(("PackageInfo", "Distribution")) else data
        style = "application/x-gzip" if packed is not data else "application/octet-stream"
        x += ('<type>file</type><data><offset>%d</offset><size>%d</size><length>%d</length>'
              '<encoding style="%s"/></data>' % (len(heap), len(data), len(packed), style))
        heap.extend(packed)
    for c in children:
        x += c
    return x + "</file>"

def tree(prefix):
    out = []
    for path, _, _ in members:
        parent = path.rsplit("/", 1)[0] if "/" in path else ""
        if parent == prefix:
            out.append(file_xml(path, tree(path)))
    return out

toc = ('<?xml version="1.0" encoding="UTF-8"?>\n<xar><toc><checksum style="sha1"><offset>0</offset>'
       '<size>20</size></checksum>' + "".join(tree("")) + "</toc></xar>").encode()
packed_toc = zlib.compress(toc)
heap[0:20] = hashlib.sha1(packed_toc).digest()
header = b"xar!" + struct.pack(">HHQQI", 28, 1, len(packed_toc), len(toc), 1)
with open(sys.argv[1], "wb") as f:
    f.write(header + packed_toc + bytes(heap))
