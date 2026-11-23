#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Turns a program linked today (LC_MAIN) into the start-up format of Mac
OS X 10.7 and earlier (LC_UNIXTHREAD), which current linkers don't write:
LC_MAIN is dropped and an x86_THREAD_STATE64 thread command whose rip is
the given symbol's address is added at the end of the load commands. Used
by run.sh: unixthread.py program symbol-address"""
import struct
import sys

path, start = sys.argv[1], int(sys.argv[2], 16)
data = bytearray(open(path, "rb").read())
magic, cpu, sub, ftype, ncmds, sizeofcmds, flags, _ = struct.unpack_from("<8I", data, 0)
assert magic == 0xFEEDFACF, "not a 64-bit Mach-O file"
LC_MAIN, LC_UNIXTHREAD, LC_SEGMENT_64 = 0x80000028, 0x5, 0x19
cmds, off, first_section = [], 32, len(data)
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<2I", data, off)
    if cmd == LC_SEGMENT_64:
        nsects = struct.unpack_from("<I", data, off + 64)[0]
        for k in range(nsects):
            sect_off = struct.unpack_from("<I", data, off + 72 + k * 80 + 48)[0]
            if sect_off:
                first_section = min(first_section, sect_off)
    if cmd != LC_MAIN:
        cmds.append(bytes(data[off:off + size]))
    off += size
state = [0] * 21
state[16] = start  # rip
thread = struct.pack("<4I", LC_UNIXTHREAD, 16 + 21 * 8, 4, 42) + struct.pack("<21Q", *state)
cmds.append(thread)
blob = b"".join(cmds)
assert 32 + len(blob) <= first_section, "no room for the thread command"
data[32:32 + sizeofcmds] = bytes(sizeofcmds)
data[32:32 + len(blob)] = blob
struct.pack_into("<2I", data, 16, len(cmds), len(blob))
open(path, "wb").write(data)
