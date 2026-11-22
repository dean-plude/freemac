# SPDX-License-Identifier: GPL-3.0-or-later
"""Dials > Displays, as a Mac's Displays settings:

- with two or more displays, a picture of them to drag into the way they sit
  on the desk, and for each one Use as: Extended display or Mirror for
  another;
- for each display, Resolution (each size it can show, or Default), Refresh
  rate, Size of text and icons (the scale), and Rotation;
- Brightness and Night Light, as before.

What each display can show comes from Strata (strata/outputs, read straight
from the display); a change is written to [output:NAME] in wayfire.ini,
which Wayfire applies at once. After a new resolution, refresh rate,
rotation or mirroring, "Keep these display settings?" counts down 15 seconds
and puts the old ones back unless Keep is pressed, as a Mac does, so a
setting the screen can't show undoes itself. Original freemac code.
"""
import math

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from .wfipc import Connection  # noqa: E402

SCALES = ("1", "1.25", "1.5", "1.75", "2")
ROTATIONS = (("normal", "Standard"), ("90", "90°"), ("180", "180°"), ("270", "270°"))
# wl_output_transform numbers as Strata reports them.
TRANSFORM_NAMES = {0: "normal", 1: "90", 2: "180", 3: "270"}
KEEP_SECONDS = 15
SNAP = 40   # how near, in layout pixels, a dragged display jumps to touch another


def read_outputs():
    """Every display, as Strata reports it; [] when Strata can't be asked."""
    try:
        reply = Connection().call("strata/outputs")
    except (OSError, ValueError):
        return []
    outputs = reply.get("outputs") if isinstance(reply, dict) else None
    return [o for o in outputs or [] if isinstance(o, dict) and o.get("name")]


def display_name(output):
    """What a person calls the display: "Built-in Display" or its model."""
    if output.get("built_in"):
        return "Built-in Display"
    model = (output.get("model") or "").strip()
    if model and model.lower() not in ("unknown", "0x0000"):
        return model
    return output.get("name", "Display")


def diagonal(output):
    """'27-inch' from the size the display reports, or ''."""
    width, height = (output.get("physical") or [0, 0])[:2]
    if width and height and width > 50 and height > 50:
        inches = math.hypot(width, height) / 25.4
        return f"{round(inches)}-inch"
    return ""


def resolutions(output):
    """[(width, height)], biggest first, with no repeats."""
    seen, found = set(), []
    for mode in sorted(output.get("modes") or [], key=lambda m: (-m["width"] * m["height"], -m["width"])):
        size = (mode["width"], mode["height"])
        if size not in seen:
            seen.add(size)
            found.append(size)
    return found


def rates(output, width, height):
    """Refresh rates (mHz) the display can show at that size, fastest first."""
    return sorted({m["refresh"] for m in output.get("modes") or []
                   if m["width"] == width and m["height"] == height and m.get("refresh")}, reverse=True)


def preferred(output):
    for mode in output.get("modes") or []:
        if mode.get("preferred"):
            return mode["width"], mode["height"]
    return None


def hz(refresh):
    value = refresh / 1000
    return f"{value:.0f} Hz" if abs(value - round(value)) < 0.05 else f"{value:.2f} Hz"


def mode_string(width, height, refresh):
    return f"{width}x{height}@{refresh}" if refresh else f"{width}x{height}"


def snap(moving, others):
    """Where to put the moving box (x, y, w, h) so it touches the nearest
    other one along a side (None when no side is free), as Displays settings do: it sticks to the nearest
    side, and lines up with that display's start, middle or end when near."""
    x, y, w, h = moving
    best = None

    def clear(nx, ny):
        return all(nx >= ox + ow or nx + w <= ox or ny >= oy + oh or ny + h <= oy
                   for ox, oy, ow, oh in others)

    def line_up(pos, size, other_pos, other_size):
        reach = max(SNAP, min(size, other_size) // 8)
        for target in (other_pos, other_pos + (other_size - size) // 2, other_pos + other_size - size):
            if abs(pos - target) < reach:
                return target
        return min(max(pos, other_pos - size + 1), other_pos + other_size - 1)

    for ox, oy, ow, oh in others:
        # Beside it (left or right), sliding up and down along that side.
        for nx in (ox - w, ox + ow):
            ny = line_up(y, h, oy, oh)
            dist = abs(nx - x) + abs(ny - y)
            if clear(nx, ny) and (best is None or dist < best[0]):
                best = (dist, nx, ny)
        # Above or below it, sliding left and right.
        for ny in (oy - h, oy + oh):
            nx = line_up(x, w, ox, ow)
            dist = abs(nx - x) + abs(ny - y)
            if clear(nx, ny) and (best is None or dist < best[0]):
                best = (dist, nx, ny)
    return (best[1], best[2]) if best else None


class Arrangement(Gtk.DrawingArea):
    """The displays drawn to scale; drag one to move it beside another."""

    def __init__(self, boxes, on_moved):
        super().__init__()
        self.boxes = dict(boxes)       # name -> [x, y, w, h, label]
        self.on_moved = on_moved
        self.dragging = None
        self.set_size_request(-1, 190)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("motion-notify-event", self._motion)
        self.connect("button-release-event", self._release)

    def _fit(self):
        """(scale, offset x, offset y) to fit every box in the area."""
        alloc = self.get_allocation()
        xs = [b[0] for b in self.boxes.values()] + [b[0] + b[2] for b in self.boxes.values()]
        ys = [b[1] for b in self.boxes.values()] + [b[1] + b[3] for b in self.boxes.values()]
        left, top, right, bottom = min(xs), min(ys), max(xs), max(ys)
        span_w, span_h = max(1, right - left), max(1, bottom - top)
        scale = min((alloc.width - 40) / (span_w * 1.6), (alloc.height - 30) / (span_h * 1.4))
        ox = (alloc.width - span_w * scale) / 2 - left * scale
        oy = (alloc.height - span_h * scale) / 2 - top * scale
        return scale, ox, oy

    def _draw(self, widget, cr):
        if not self.boxes:
            return
        scale, ox, oy = self._fit()
        context = widget.get_style_context()
        accent = context.lookup_color("theme_selected_bg_color")
        accent = accent[1] if accent[0] else Gdk.RGBA(0.2, 0.48, 0.96, 1)
        fg = context.get_color(Gtk.StateFlags.NORMAL)
        for name, (x, y, w, h, label) in self.boxes.items():
            rx, ry, rw, rh = ox + x * scale, oy + y * scale, w * scale, h * scale
            radius = 6
            cr.new_sub_path()
            cr.arc(rx + rw - radius, ry + radius, radius, -math.pi / 2, 0)
            cr.arc(rx + rw - radius, ry + rh - radius, radius, 0, math.pi / 2)
            cr.arc(rx + radius, ry + rh - radius, radius, math.pi / 2, math.pi)
            cr.arc(rx + radius, ry + radius, radius, math.pi, 3 * math.pi / 2)
            cr.close_path()
            cr.set_source_rgba(accent.red, accent.green, accent.blue, 0.85 if name == self.dragging else 0.6)
            cr.fill_preserve()
            cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.35)
            cr.set_line_width(1)
            cr.stroke()
            cr.set_source_rgba(1, 1, 1, 0.95)
            cr.select_font_face("Inter", 0, 1)
            cr.set_font_size(12)
            ext = cr.text_extents(label)
            cr.move_to(rx + (rw - ext.width) / 2 - ext.x_bearing, ry + (rh - ext.height) / 2 - ext.y_bearing)
            cr.show_text(label)

    def _hit(self, px, py):
        scale, ox, oy = self._fit()
        for name, (x, y, w, h, _label) in reversed(list(self.boxes.items())):
            if ox + x * scale <= px <= ox + (x + w) * scale and oy + y * scale <= py <= oy + (y + h) * scale:
                return name
        return None

    def _press(self, _widget, event):
        if len(self.boxes) < 2 or event.button != 1:
            return False
        self.dragging = self._hit(event.x, event.y)
        if self.dragging:
            box = self.boxes[self.dragging]
            self.grab = (event.x, event.y, box[0], box[1], self._fit())
            self.queue_draw()
        return True

    def _motion(self, _widget, event):
        if not self.dragging:
            return False
        sx, sy, bx, by, (scale, _ox, _oy) = self.grab
        box = self.boxes[self.dragging]
        box[0] = bx + (event.x - sx) / scale
        box[1] = by + (event.y - sy) / scale
        self.queue_draw()
        return True

    def _release(self, _widget, _event):
        if not self.dragging:
            return False
        name, self.dragging = self.dragging, None
        box = self.boxes[name]
        others = [tuple(b[:4]) for n, b in self.boxes.items() if n != name]
        place = snap(tuple(box[:4]), others)
        # Nowhere to touch without covering another display: put it back.
        box[0], box[1] = place if place else self.grab[2:4]
        # Keep the top-left display at 0,0, as Wayfire expects nothing negative.
        left = min(b[0] for b in self.boxes.values())
        top = min(b[1] for b in self.boxes.values())
        for b in self.boxes.values():
            b[0], b[1] = int(round(b[0] - left)), int(round(b[1] - top))
        self.queue_draw()
        self.on_moved({n: (b[0], b[1]) for n, b in self.boxes.items()})
        return True


def keep_or_revert(parent, revert):
    """Ask "Keep these display settings?" and put the old ones back unless
    Keep is pressed within 15 seconds."""
    dialog = Gtk.MessageDialog(transient_for=parent, modal=True, message_type=Gtk.MessageType.QUESTION,
                               text="Keep these display settings?")
    dialog.add_button("Revert", Gtk.ResponseType.CANCEL)
    keep = dialog.add_button("Keep", Gtk.ResponseType.OK)
    keep.get_style_context().add_class("suggested-action")
    dialog.set_default_response(Gtk.ResponseType.OK)
    left = [KEEP_SECONDS]

    def words():
        dialog.format_secondary_text(f"The old settings come back in {left[0]} "
                                     f"second{'s' if left[0] != 1 else ''}.")

    def tick():
        left[0] -= 1
        if left[0] <= 0:
            dialog.response(Gtk.ResponseType.CANCEL)
            return False
        words()
        return True

    words()
    timer = GLib.timeout_add_seconds(1, tick)

    def answered(_dialog, response):
        GLib.source_remove(timer) if left[0] > 0 else None
        dialog.destroy()
        if response != Gtk.ResponseType.OK:
            revert()

    dialog.connect("response", answered)
    dialog.show()


class DisplaysPage:
    """Builds the page and rebuilds its top part when displays change."""

    def __init__(self, window):
        self.window = window
        self.group, self.row, self.page, self.slider, self.switch = window.helpers
        self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        self.chosen = None
        self.fill()

    def ini(self, name, key, default=None):
        return self.window.ini_get(f"output:{name}", key, default)

    def set(self, name, **values):
        for key, value in values.items():
            self.window.ini_set(f"output:{name}", key, value)

    def remember(self, name, keys):
        """The display's settings as written now, to put back on Revert."""
        return {key: self.ini(name, key) for key in keys}

    def put_back(self, name, saved):
        for key, value in saved.items():
            self.window.ini_set(f"output:{name}", key, value if value is not None else
                                {"mode": "auto", "transform": "normal", "scale": "1"}[key])
        GLib.timeout_add(1200, self.refill)

    def change(self, name, ask=True, **values):
        saved = self.remember(name, values)
        self.set(name, **values)
        if ask:
            keep_or_revert(self.window, lambda: self.put_back(name, saved))
        GLib.timeout_add(1200, self.refill)

    def refill(self):
        self.fill()
        self.body.show_all()
        return False

    def fill(self):
        for child in self.body.get_children():
            self.body.remove(child)
        outputs = read_outputs()
        if not outputs:
            self.body.pack_start(self._scale_only(), False, False, 0)
            return
        shown = [o for o in outputs if o.get("source") in ("self", "mirror")] or outputs
        if len(shown) > 1:
            self.body.pack_start(self._arrangement(shown), False, False, 0)
        names = [o["name"] for o in shown]
        if self.chosen not in names:
            self.chosen = names[0]
        if len(shown) > 1:
            switcher = Gtk.Box(spacing=0, halign=Gtk.Align.CENTER)
            switcher.get_style_context().add_class("linked")
            first = None
            for output in shown:
                button = Gtk.RadioButton.new_with_label_from_widget(first, display_name(output))
                button.set_mode(False)
                first = first or button
                button.set_active(output["name"] == self.chosen)
                button.connect("toggled", lambda b, n=output["name"]: b.get_active() and self._choose(n))
                switcher.pack_start(button, False, False, 0)
            self.body.pack_start(switcher, False, False, 0)
        output = next(o for o in shown if o["name"] == self.chosen)
        self.body.pack_start(self._details(output, shown), False, False, 0)

    def _choose(self, name):
        self.chosen = name
        GLib.idle_add(self.refill)

    # ---- two or more displays ---------------------------------------------
    def _arrangement(self, outputs):
        boxes = {}
        for o in outputs:
            if o.get("source") != "self":
                continue
            w = o.get("layout_width") or o.get("width") or 1920
            h = o.get("layout_height") or o.get("height") or 1080
            boxes[o["name"]] = [o.get("x", 0), o.get("y", 0), w, h, display_name(o)]

        def moved(places):
            for name, (x, y) in places.items():
                self.set(name, position=f"{x},{y}")

        picture = Arrangement(boxes, moved)
        caption = Gtk.Label(label="Drag the displays to match how they sit on your desk. The pointer and "
                                  "windows cross from one to the other where they touch.", xalign=0, wrap=True)
        caption.get_style_context().add_class("dials-caption")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        frame = Gtk.Frame()
        frame.get_style_context().add_class("dials-group")
        frame.add(picture)
        box.pack_start(frame, False, False, 0)
        box.pack_start(caption, False, False, 0)
        return box

    def _use_as(self, output, outputs):
        combo = Gtk.ComboBoxText()
        combo.append("extended", "Extended display")
        for other in outputs:
            if other["name"] != output["name"] and other.get("source") == "self":
                combo.append("mirror:" + other["name"], f"Mirror for {display_name(other)}")
        current = ("mirror:" + output["mirror_from"]) if output.get("source") == "mirror" else "extended"
        combo.set_active_id(current)
        if combo.get_active_id() is None:
            combo.set_active_id("extended")

        def changed(c):
            pick = c.get_active_id()
            if pick == current:
                return
            mode = "mirror " + pick.split(":", 1)[1] if pick.startswith("mirror:") else "auto"
            self.change(output["name"], mode=mode)
        combo.connect("changed", changed)
        return combo

    # ---- one display's settings --------------------------------------------
    def _details(self, output, outputs):
        row = self.row
        name = output["name"]
        size = f"{output.get('width', '?')} × {output.get('height', '?')}"
        inch = diagonal(output)
        rows = [row(display_name(output), None, f"{inch} ({size})" if inch else size)]
        if len(outputs) > 1:
            rows.append(row("Use as", self._use_as(output, outputs)))
        if output.get("source") == "mirror":
            return self.group(*rows)

        sizes = resolutions(output)
        written = (self.ini(name, "mode", "auto") or "auto").strip()
        if sizes:
            resolution = Gtk.ComboBoxText()
            resolution.append("auto", "Default for display")
            for w, h in sizes:
                tag = " (default)" if (w, h) == preferred(output) else ""
                resolution.append(f"{w}x{h}", f"{w} × {h}{tag}")
            current = "auto" if written in ("auto", "default", "") else written.split("@")[0]
            resolution.set_active_id(current)
            if resolution.get_active_id() is None:
                resolution.set_active_id("auto")

            def resolution_changed(c):
                pick = c.get_active_id()
                if pick == current:
                    return
                if pick == "auto":
                    self.change(name, mode="auto")
                else:
                    w, h = (int(v) for v in pick.split("x"))
                    self.change(name, mode=mode_string(w, h, (rates(output, w, h) or [0])[0]))
            resolution.connect("changed", resolution_changed)
            rows.append(row("Resolution", resolution))

            w, h = output.get("width"), output.get("height")
            choices = rates(output, w, h)
            if len(choices) > 1:
                rate = Gtk.ComboBoxText()
                for value in choices:
                    rate.append(str(value), hz(value))
                now = min(choices, key=lambda v: abs(v - (output.get("refresh") or 0)))
                rate.set_active_id(str(now))
                rate.connect("changed", lambda c: c.get_active_id() != str(now) and self.change(
                    name, mode=mode_string(w, h, int(c.get_active_id()))))
                rows.append(row("Refresh rate", rate))

        scale = Gtk.ComboBoxText()
        for value in SCALES:
            scale.append(value, f"{int(float(value) * 100)}%")
        scale.set_active_id(self.ini(name, "scale", "1") or "1")
        if scale.get_active_id() is None:
            scale.set_active_id("1")
        scale.connect("changed", lambda c: self.change(name, ask=False, scale=c.get_active_id()))
        rows.append(row("Size of text and icons", scale, "Bigger makes everything easier to read; "
                                                         "smaller fits more on the screen."))

        rotation = Gtk.ComboBoxText()
        for value, label in ROTATIONS:
            rotation.append(value, label)
        turned = TRANSFORM_NAMES.get(output.get("transform", 0), "normal")
        rotation.set_active_id(turned)
        rotation.connect("changed", lambda c: c.get_active_id() != turned and self.change(
            name, transform=c.get_active_id()))
        rows.append(row("Rotation", rotation))
        return self.group(*rows)

    def _scale_only(self):
        """When Strata can't be asked: the scale of each display, as before."""
        rows = []
        try:
            outputs = Connection().call("window-rules/list-outputs")
        except (OSError, ValueError):
            outputs = []
        for output in outputs or []:
            name = output.get("name", "?")
            geo = output.get("geometry", {})
            scale = Gtk.ComboBoxText()
            for value in SCALES:
                scale.append(value, f"{int(float(value) * 100)}%")
            scale.set_active_id(self.ini(name, "scale", "1"))
            scale.connect("changed", lambda c, n=name: self.set(n, scale=c.get_active_id()))
            caption = f"{geo.get('width', '?')} × {geo.get('height', '?')}" if geo else None
            rows.append(self.row(f"{name} scale", scale, caption))
        if not rows:
            rows.append(self.row("No displays found", None, "Dials reads displays from the window manager."))
        return self.group(*rows)


def displays_page(window, brightness_group, night_light_group):
    page = DisplaysPage(window)
    return window.helpers[2]("Displays", page.body, *[g for g in (brightness_group, night_light_group) if g])
