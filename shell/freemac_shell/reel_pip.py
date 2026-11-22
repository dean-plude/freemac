# SPDX-License-Identifier: GPL-3.0-or-later
"""Picture in Picture for Reel, as a Mac's player has: the video shrinks into
a small window of its own that floats above every other window, in the
bottom right corner of the screen, and keeps playing while you work.

Pointing at the picture shows two buttons, play/pause and back to the
window. Drag the picture to move it anywhere; double-click it, press Esc, or
press the back button to put it back where it was, at its old size.

The window loses its title bar and controls, is sized to the video's shape,
and is put in its corner and kept above the others through Wayfire
(window-rules/configure-view, wm-actions/set-always-on-top). Original
freemac code.
"""
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

from . import wfipc  # noqa: E402

WIDTH = 384          # the picture's width; its height follows the video's shape
MARGIN = 24          # from the screen's edges
APP_IDS = ("org.freemac.Reel", "freemac-reel")


def size_for(video_w, video_h, width=WIDTH):
    """The picture's size for a video of this shape, never too thin or tall."""
    if video_w <= 0 or video_h <= 0:
        return width, round(width * 9 / 16)
    height = round(width * video_h / video_w)
    height = max(round(width * 0.4), min(height, round(width * 1.25)))
    return width, height


def corner(area, width, height, margin=MARGIN):
    """Where the picture goes: the bottom right of the area."""
    x, y, area_w, area_h = area
    return x + area_w - width - margin, y + area_h - height - margin


def _connect():
    try:
        return wfipc.Wayfire()
    except (ConnectionError, OSError):
        return None


def _call(wf, method, **data):
    try:
        return wf.req.call(method, **data)
    except (ConnectionError, OSError, ValueError, AttributeError):
        return None


class PictureInPicture:
    """Turns a Reel window into a floating picture and back."""

    def __init__(self, window):
        self.window = window
        self.on = False
        self.view_id = None
        self.before = None      # the window's place and size in Wayfire, to go back to
        self.before_size = None  # and its size as GTK asked for it

    # -- finding the window in Wayfire --

    def _own_view(self, wf):
        """The Reel window's view: the focused one, since it was just clicked
        or keyed; otherwise the only Reel window there is."""
        reply = _call(wf, "window-rules/get-focused-view")
        info = reply.get("info") if isinstance(reply, dict) else None
        if isinstance(info, dict) and info.get("app-id") in APP_IDS:
            return info
        views = _call(wf, "window-rules/list-views")
        mine = [v for v in views if isinstance(v, dict) and v.get("app-id") in APP_IDS
                and v.get("role", v.get("type")) == "toplevel"] if isinstance(views, list) else []
        return mine[0] if len(mine) == 1 else None

    def _area(self, wf, view):
        """The work area (the screen less the menu bar and the Dock) of the
        window's output, in the same terms as the window's own place."""
        outputs = _call(wf, "window-rules/list-outputs") if wf else None
        areas = {}
        for output in outputs if isinstance(outputs, list) else []:
            area = output.get("workarea") if isinstance(output, dict) else None
            if isinstance(area, dict):
                areas[output.get("id")] = (area.get("x", 0), area.get("y", 0),
                                           area.get("width", 1280), area.get("height", 800))
        if not areas:
            return 0, 0, 1280, 800
        where = view.get("output-id", view.get("output")) if isinstance(view, dict) else None
        return areas.get(where) or next(iter(areas.values()))

    # -- in and out --

    def enter(self, video_w, video_h):
        if self.on:
            return
        wf = _connect()
        view = self._own_view(wf) if wf else None
        self.view_id = view.get("id") if view else None
        self.before = view.get("geometry") if view else None
        self.before_size = self.window.get_size()
        self.on = True
        self.window.pip_changed(True)
        width, height = size_for(video_w, video_h)
        x, y = corner(self._area(wf, view), width, height)
        self.window.resize(width, height)
        if wf and self.view_id is not None:
            # Give GTK a moment to drop the title bar and the controls first.
            GLib.timeout_add(150, self._place, wf, self.view_id, x, y, width, height, True)

    def leave(self):
        if not self.on:
            return
        self.on = False
        wf = _connect()
        if wf and self.view_id is not None:
            _call(wf, "wm-actions/set-always-on-top", view_id=self.view_id, state=False)
        self.window.pip_changed(False)
        if self.before_size:
            self.window.resize(*self.before_size)
        if wf and self.view_id is not None and isinstance(self.before, dict):
            g = self.before
            GLib.timeout_add(150, self._place, wf, self.view_id, g.get("x", 0), g.get("y", 0),
                             g.get("width", 880), g.get("height", 520), False)
        self.view_id = None

    def toggle(self, video_w, video_h):
        if self.on:
            self.leave()
        else:
            self.enter(video_w, video_h)

    def _place(self, wf, view_id, x, y, width, height, above):
        _call(wf, "window-rules/configure-view", id=view_id,
              geometry={"x": int(x), "y": int(y), "width": int(width), "height": int(height)})
        if above and self.on:
            _call(wf, "wm-actions/set-always-on-top", view_id=view_id, state=True)
        return False


def pip_controls(on_play, on_back):
    """The two buttons that show over the picture: play/pause and back to the window."""
    box = Gtk.Box(spacing=4, halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
    box.get_style_context().add_class("reel-hud")
    buttons = []
    for icon, tip, callback in (("freemac-pip-exit-symbolic", "Back to the Window (Esc)", on_back),
                                ("media-playback-pause-symbolic", "Pause (Space)", on_play)):
        button = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR)
        button.set_tooltip_text(tip)
        button.set_relief(Gtk.ReliefStyle.NONE)
        button.set_can_focus(False)
        button.connect("clicked", lambda _b, c=callback: c())
        box.pack_start(button, False, False, 0)
        buttons.append(button)
    return box, buttons[1]
