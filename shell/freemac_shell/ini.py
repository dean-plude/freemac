# SPDX-License-Identifier: GPL-3.0-or-later
"""Reading and writing one value of a Wayfire-style ini file (wayfire.ini,
wf-shell.ini), as Dials does, without loading Dials. Original freemac code."""
import os


def ini_get(path, section, key, default=None):
    """Read one value from a Wayfire-style ini file."""
    current = None
    try:
        with open(path) as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith("[") and stripped.endswith("]"):
                    current = stripped[1:-1]
                elif current == section and "=" in stripped and not stripped.startswith("#"):
                    name, value = stripped.split("=", 1)
                    if name.strip() == key:
                        return value.strip().replace("\\#", "#")
    except OSError:
        pass
    return default


def ini_set(path, section, key, value):
    """Set one value in a Wayfire-style ini file, keeping comments and order.

    Wayfire and Backdrop watch their files and apply the change at once.
    """
    value = str(value).replace("#", "\\#")
    try:
        with open(path) as f:
            lines = f.read().splitlines()
    except OSError:
        lines = []
    current, section_end, done = None, None, False
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if current == section:
                section_end = index
            current = stripped[1:-1]
            continue
        if current == section and "=" in stripped and not stripped.startswith("#"):
            if stripped.split("=", 1)[0].strip() == key:
                lines[index] = f"{key} = {value}"
                done = True
                break
    if not done:
        if current == section and section_end is None:
            section_end = len(lines)
        if section_end is None:
            if lines and lines[-1].strip():
                lines.append("")
            lines += [f"[{section}]", f"{key} = {value}"]
        else:
            # Insert after the section's last non-blank line.
            at = section_end
            while at > 0 and not lines[at - 1].strip():
                at -= 1
            lines.insert(at, f"{key} = {value}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Write the file in place rather than replacing it: Wayfire watches the
    # file itself for a finished write, and loses track of it when a new file
    # is renamed over it, so later changes would only apply after logging in
    # again.
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
