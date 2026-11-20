#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Boot a freemac ISO in QEMU with no window and check that the live session
comes up: the serial console logs in on its own, and the desktop's
compositor (Wayfire), menu bar (Topline) and dock (Pier) are running.

    scripts/smoke-test.py ISO [--uefi] [--timeout SECONDS]

Exits 0 when all three are running, 1 otherwise. Uses KVM when it can.
"""
import os
import socket
import subprocess
import sys
import tempfile
import time


def main():
    args = sys.argv[1:]
    uefi = "--uefi" in args
    limit = 900
    if "--timeout" in args:
        limit = int(args[args.index("--timeout") + 1])
    iso = next(a for a in args if a.endswith(".iso"))
    work = tempfile.mkdtemp(prefix="freemac-smoke-")
    sock = os.path.join(work, "serial.sock")
    command = ["qemu-system-x86_64", "-m", "3072", "-smp", "2", "-cdrom", iso, "-boot", "d",
               "-vga", "virtio", "-display", "none",
               "-netdev", "user,id=n", "-device", "virtio-net-pci,netdev=n",
               "-serial", f"unix:{sock},server,nowait"]
    if os.access("/dev/kvm", os.W_OK):
        command += ["-enable-kvm", "-cpu", "host"]
    if uefi:
        for firmware in ("/usr/share/ovmf/OVMF.fd", "/usr/share/OVMF/OVMF_CODE.fd",
                         "/usr/share/qemu/OVMF.fd"):
            if os.path.exists(firmware):
                command += ["-bios", firmware]
                break
    print("starting:", " ".join(command), flush=True)
    qemu = subprocess.Popen(command)
    try:
        return check(sock, limit)
    finally:
        qemu.kill()


def check(sock, limit):
    start = time.time()
    while not os.path.exists(sock):
        time.sleep(0.5)
        if time.time() - start > 30:
            print("QEMU never opened its serial port")
            return 1
    s = socket.socket(socket.AF_UNIX)
    s.connect(sock)
    s.settimeout(2)
    seen = b""
    asked = 0.0
    while time.time() - start < limit:
        if time.time() - asked > 15:
            # Ask again every 15 s: an early ask can land before the login.
            s.sendall(b"\r\nfor p in wayfire freemac-topline freemac-pier; do "
                      b"pgrep -f $p >/dev/null && echo UP-$p; done; echo CHECKED\r\n")
            asked = time.time()
        try:
            chunk = s.recv(65536)
        except socket.timeout:
            continue
        if not chunk:
            break
        seen += chunk
        sys.stdout.write(chunk.decode("utf-8", "replace"))
        sys.stdout.flush()
        text = seen.decode("utf-8", "replace")
        if all(f"UP-{p}\r" in text or f"UP-{p}\n" in text
               for p in ("wayfire", "freemac-topline", "freemac-pier")):
            print(f"\nsmoke test passed in {time.time() - start:.0f} s")
            return 0
    print(f"\nsmoke test failed: the desktop wasn't running after {limit} s")
    return 1


if __name__ == "__main__":
    sys.exit(main())
