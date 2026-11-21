# SPDX-License-Identifier: GPL-3.0-or-later
"""Click the wallpaper to reveal the desktop: the windows on the screen step
out of the way, and a second click on the wallpaper brings them back.
Dials > Dock and Menu Bar turns it on (shell.json "click_reveal").

The windows are hidden the way ⌘H hides an app (Strata), so they don't
shrink into the Dock; clicking an app in the Dock brings that one back.
Original freemac code.
"""
from . import style
from .wfipc import Wayfire, is_minimized


def enabled():
    return bool(style.prefs().get("click_reveal"))


def _on_screen(view, output, sizes):
    """The window shows on this output's current desktop: Wayfire gives a
    window's place relative to the desktop its output shows now."""
    name = view.get("output-name")
    if output and name not in (None, output):
        return False
    width, height = sizes.get(name, (100000, 100000))
    g = view.get("geometry") or {}
    return (g.get("x", 0) < width and g.get("y", 0) < height
            and g.get("x", 0) + g.get("width", 0) > 0 and g.get("y", 0) + g.get("height", 0) > 0)


class Reveal:
    def __init__(self):
        self.ids = []          # the windows we put away, front one first

    def toggle(self, output=None):
        """Put the windows away, or bring back the ones we put away.
        Returns "hidden", "shown" or None (nothing to do)."""
        try:
            wf = Wayfire()
        except (ConnectionError, OSError):
            return None
        hidden = wf.hidden()
        back = [i for i in self.ids if i in hidden]
        if back:
            # Back to front, so the one in front before is in front again.
            for view_id in reversed(back):
                try:
                    wf.set_minimized(view_id, False)
                except (ConnectionError, OSError, ValueError):
                    pass
            try:
                wf.focus(back[0])
            except (ConnectionError, OSError, ValueError):
                pass
            self.ids = []
            return "shown"
        focused = wf.focused()
        sizes = {}
        for out in wf.outputs():
            g = out.get("geometry") or {}
            sizes[out.get("name")] = (g.get("width", 100000), g.get("height", 100000))
        views = [v for v in wf.views() if not is_minimized(v) and _on_screen(v, output, sizes)]
        if not views:
            self.ids = []
            return None
        # Wayfire's list runs from back to front.
        order = [v["id"] for v in reversed(views)]
        if focused and focused.get("id") in order:
            order.remove(focused["id"])
            order.insert(0, focused["id"])
        for view_id in order:
            wf.hide(view_id)
        self.ids = order
        return "hidden"
