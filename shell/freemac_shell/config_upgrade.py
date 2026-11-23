# SPDX-License-Identifier: GPL-3.0-or-later
"""Bring a person's desktop settings up to date with a newer freemac.

A person's ~/.config/wayfire.ini and wf-shell.ini are copied from /etc/skel
when their account is made, and never again: after a Software Update, a new
shortcut or a new app that starts with the session (Services' ⇧⌘Y, say)
would only reach accounts made later. At each login, freemac-session runs
this, and every setting the shipped file has that the person's file lacks is
added to the end of its section. Nothing the person has changed is touched:
a setting that is already there, even turned off, stays as it is.

    freemac-config-upgrade           update ~/.config's files from /etc/skel
    freemac-config-upgrade --dry-run say what would be added

Original freemac code.
"""
import os
import shutil
import sys

SKEL = "/etc/skel/.config"
FILES = ("wayfire.ini", "wf-shell.ini")


def parse(lines):
    """{section: {key: line}} and the order of the sections, from an ini's lines."""
    sections, order, current = {}, [], None
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            current = stripped[1:-1]
            if current not in sections:
                sections[current] = {}
                order.append(current)
        elif current is not None and "=" in stripped and not stripped.startswith("#"):
            key = stripped.split("=", 1)[0].strip()
            if key:
                sections[current].setdefault(key, line.rstrip("\n"))
    return sections, order


def merged(mine, shipped):
    """mine's lines with shipped's missing settings added, and what was added."""
    have, _ = parse(mine)
    want, order = parse(shipped)
    added = []
    missing = {}
    for section in order:
        lines = [line for key, line in want[section].items() if key not in have.get(section, {})]
        if lines:
            missing[section] = lines
            added += [f"[{section}] {line.split('=', 1)[0].strip()}" for line in lines]
    if not missing:
        return mine, []
    out, current = [], None

    def flush(section):
        if section in missing and section in have:
            while out and not out[-1].strip():
                out.pop()
            out.extend(line + "\n" for line in missing.pop(section))
            out.append("\n")

    for line in mine:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            flush(current)
            current = stripped[1:-1]
        out.append(line if line.endswith("\n") else line + "\n")
    flush(current)
    for section in order:   # whole sections the person's file doesn't have
        if section in missing:
            if out and out[-1].strip():
                out.append("\n")
            out.append(f"[{section}]\n")
            out.extend(line + "\n" for line in missing.pop(section))
    return out, added


def upgrade(name, home=None, skel=SKEL, dry_run=False):
    home = home or os.path.expanduser("~")
    shipped_path = os.path.join(skel, name)
    path = os.path.join(home, ".config", name)
    try:
        with open(shipped_path) as f:
            shipped = f.readlines()
    except OSError:
        return []
    if not os.path.exists(path):
        if not dry_run:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            shutil.copyfile(shipped_path, path)
        return [f"{name} (all of it)"]
    try:
        with open(path) as f:
            mine = f.readlines()
    except OSError:
        return []
    lines, added = merged(mine, shipped)
    if added and not dry_run:
        tmp = path + ".freemac-upgrade"
        with open(tmp, "w") as f:
            f.writelines(lines)
        shutil.copymode(path, tmp)
        os.replace(tmp, path)
    return [f"{name}: {a}" for a in added]


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    dry_run = "--dry-run" in argv
    for name in FILES:
        for line in upgrade(name, dry_run=dry_run):
            print(("would add " if dry_run else "added ") + line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
