# SPDX-License-Identifier: GPL-3.0-or-later
"""Input sources, as on a Mac: the keyboard layouts you can type with (U.S.,
British, French, German...), chosen by name in Dials > Keyboard, switched with
Control-Space or from the input menu in the menu bar. They are XKB layouts in
wayfire.ini ([input] xkb_layout and xkb_variant, comma-separated), and Strata
says which one is in use (strata/input-source). Original freemac code."""
import os

RULES = ("/usr/share/X11/xkb/rules/evdev.lst", "/usr/share/X11/xkb/rules/base.lst")
WAYFIRE_INI = os.path.expanduser("~/.config/wayfire.ini")
# Control-Space: the next input source. A Wayfire binding, not XKB's
# grp:ctrl_space_toggle, which would also fire on Control-Command-Space (the
# emoji panel); it is only there while there is something to switch to, so
# apps keep Control-Space otherwise.
SWITCH_KEYS = "<ctrl> KEY_SPACE"
MAX_SOURCES = 4                          # XKB holds at most four at a time

_catalogue = None


def catalogue():
    """Every layout this computer knows: [(layout, variant, name)], plain
    layouts first, as the XKB rules list them."""
    global _catalogue
    if _catalogue is not None:
        return _catalogue
    layouts, variants, section = [], [], None
    for path in RULES:
        try:
            with open(path, encoding="utf-8") as f:
                for line in f:
                    if line.startswith("!"):
                        section = line[1:].strip()
                        continue
                    parts = line.strip().split(None, 1)
                    if len(parts) != 2:
                        continue
                    if section == "layout":
                        layouts.append((parts[0], "", parts[1]))
                    elif section == "variant" and ":" in parts[1]:
                        parent, name = parts[1].split(":", 1)
                        variants.append((parent.strip(), parts[0], name.strip()))
            break
        except OSError:
            continue
    _catalogue = layouts + variants
    return _catalogue


def name_of(layout, variant=""):
    for code, var, name in catalogue():
        if code == layout and var == (variant or ""):
            return name
    return f"{layout} ({variant})" if variant else layout


def short_label(layout, _variant=""):
    """What the input menu shows in the menu bar: "US", "GB", "FR"."""
    return (layout or "?")[:3].upper()


def _ini_get(section, key, default=""):
    current = None
    try:
        with open(WAYFIRE_INI) as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith("[") and stripped.endswith("]"):
                    current = stripped[1:-1]
                elif current == section and "=" in stripped and not stripped.startswith("#"):
                    name, value = stripped.split("=", 1)
                    if name.strip() == key:
                        return value.strip()
    except OSError:
        pass
    return default


def sources():
    """The input sources in wayfire.ini, in order: [(layout, variant)]."""
    layouts = [p.strip() for p in (_ini_get("input", "xkb_layout", "us") or "us").split(",")]
    variants = [p.strip() for p in (_ini_get("input", "xkb_variant", "") or "").split(",")]
    found = []
    for n, layout in enumerate(layouts):
        if layout:
            found.append((layout, variants[n] if n < len(variants) else ""))
    return found or [("us", "")]


def save(items, ini_set, ini_get):
    """Write the input sources; Wayfire applies them at once. ini_set and
    ini_get are Dials' own (they keep the file's comments)."""
    items = list(items)[:MAX_SOURCES] or [("us", "")]
    ini_set("input", "xkb_layout", ",".join(layout for layout, _v in items))
    ini_set("input", "xkb_variant", ",".join(variant for _l, variant in items))
    options = [o.strip() for o in (ini_get("input", "xkb_options", "") or "").split(",")
               if o.strip() and not o.strip().startswith("grp:")]
    ini_set("input", "xkb_options", ",".join(options))
    ini_set("command", "binding_input_next", SWITCH_KEYS if len(items) > 1 else "")
    ini_set("command", "command_input_next", "freemac-input --next")


def current(wf):
    """(names, index) from Strata, or None when it can't say."""
    try:
        reply = wf.req.call("strata/input-source")
    except (ConnectionError, OSError, ValueError):
        return None
    if not isinstance(reply, dict) or reply.get("result") != "ok":
        return None
    names = [n for n in reply.get("names") or [] if isinstance(n, str)]
    index = reply.get("index")
    return (names, index if isinstance(index, int) else 0) if names else None


def choose(wf, index):
    try:
        wf.req.call("strata/input-source", index=int(index))
    except (ConnectionError, OSError, ValueError):
        pass


def main(argv=None):
    """freemac-input --next: switch to the next input source (Control-Space)."""
    import sys

    argv = sys.argv[1:] if argv is None else argv
    if argv != ["--next"]:
        print("usage: freemac-input --next", file=sys.stderr)
        return 2
    from . import wfipc

    try:
        wf = wfipc.Wayfire()
    except OSError:
        return 1
    state = current(wf)
    if not state or len(state[0]) < 2:
        return 0
    names, index = state
    choose(wf, (index + 1) % len(names))
    return 0
