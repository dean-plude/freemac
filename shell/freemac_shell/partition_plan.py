# SPDX-License-Identifier: GPL-3.0-or-later
"""How Hull's Partition divides a drive: a list of volumes, each with a
name, a format and a size, that always add up to the whole drive.

Adding a volume splits the chosen one in half; removing one gives its space
to the one before it. Changing a size, or dragging the line between two
slices of the pie, moves space between neighbours, never below MINIMUM.

Original freemac code; no GTK here, so it can be tried from a terminal.
"""
MIB = 1024 * 1024
MINIMUM = 32 * MIB          # the smallest volume every format here can make
MOST = 8                    # volumes on one drive
EDGES = 2 * MIB             # kept free: the partition map at the start and its copy at the end


class Part:
    def __init__(self, name, fstype, size):
        self.name, self.fstype, self.size = name, fstype, size

    def __repr__(self):
        return f"Part({self.name!r}, {self.fstype!r}, {self.size // MIB} MiB)"


def _down(n):
    return n // MIB * MIB


class Layout:
    def __init__(self, drive_size, name="Untitled", fstype="exfat"):
        self.total = _down(max(0, drive_size - EDGES))
        self.parts = [Part(name, fstype, self.total)]

    # -- reading --

    def __len__(self):
        return len(self.parts)

    def start(self, i):
        """Where volume i begins, counted from the first volume's start."""
        return sum(p.size for p in self.parts[:i])

    def offsets(self):
        """[(offset on the drive, size or 0 for "the rest")] for udisks."""
        found = []
        for i, part in enumerate(self.parts):
            last = i == len(self.parts) - 1
            found.append((MIB + self.start(i), 0 if last else part.size))
        return found

    def can_add(self, i):
        return len(self.parts) < MOST and self.parts[i].size >= 2 * MINIMUM

    def can_remove(self):
        return len(self.parts) > 1

    def _free_name(self, wanted):
        names = {p.name.lower() for p in self.parts}
        base = wanted.rstrip("0123456789 ").strip() or "Untitled"
        n = 2
        while f"{base} {n}".lower() in names:
            n += 1
        return f"{base} {n}"

    # -- changing --

    def add(self, i):
        """Split volume i in half; the new half comes after it. Its index, or None."""
        if not self.can_add(i):
            return None
        part = self.parts[i]
        half = _down(part.size // 2)
        name = self._free_name(part.name)
        if part.fstype == "vfat":
            name = name.upper()
        self.parts.insert(i + 1, Part(name, part.fstype, part.size - half))
        part.size = half
        return i + 1

    def remove(self, i):
        """Take volume i away; its space joins its neighbour. The index to choose next."""
        if not self.can_remove():
            return i
        gone = self.parts.pop(i)
        into = i - 1 if i > 0 else 0
        self.parts[into].size += gone.size
        return into

    def resize(self, i, size):
        """Make volume i this size, taking from or giving to the one after it
        (the one before it, for the last). Returns the size it got."""
        if len(self.parts) == 1:
            return self.parts[0].size
        other = i + 1 if i < len(self.parts) - 1 else i - 1
        pool = self.parts[i].size + self.parts[other].size
        size = max(MINIMUM, min(_down(int(size)), pool - MINIMUM))
        self.parts[i].size = size
        self.parts[other].size = pool - size
        return size

    def move_line(self, k, position):
        """Move the line between volume k and k + 1 to this many bytes from
        the start, as dragging it in the pie does."""
        if not 0 <= k < len(self.parts) - 1:
            return
        self.resize(k, position - self.start(k))      # k isn't the last, so k + 1 gives or takes
