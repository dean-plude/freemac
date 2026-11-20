#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Draw freemac's own Kvantum themes, freemac and freemac-dark, so Qt 5 apps
get the same buttons, fields, tabs, scroll bars, check boxes and menus as the
rest of freemac.

    make-kvantum.py OUTDIR      -> OUTDIR/freemac/, OUTDIR/freemac-dark/

Kvantum is a Qt style that draws each widget from named pieces of an SVG
picture and reads its sizes from a .kvconfig file. Every piece here is drawn
by this script from freemac's own colours (art/gtk-theme/make-theme.py):
rounded white buttons with a hairline edge, round check boxes in the accent
colour, thin pill scroll bars that show while scrolling, and menus with a
blue highlight. Nothing is taken from another theme.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("theme", os.path.join(HERE, "..", "gtk-theme", "make-theme.py"))
theme = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(theme)

STATES = ("normal", "focused", "pressed", "toggled", "disabled")
STRIP = 12   # length of the stretchable pieces


class Canvas:
    """Places each piece in its own spot on a grid so none overlap."""

    def __init__(self):
        self.parts = []
        self.x, self.y, self.row = 0, 0, 0

    def spot(self, w, h):
        if self.x + w > 900:
            self.x, self.y, self.row = 0, self.y + self.row + 4, 0
        at = (self.x, self.y)
        self.x += w + 4
        self.row = max(self.row, h)
        return at

    def add(self, ident, body):
        self.parts.append(f'<g id="{ident}">{body}</g>')

    def svg(self):
        height = self.y + self.row + 4
        return ('<?xml version="1.0" encoding="UTF-8"?>\n'
                f'<svg xmlns="http://www.w3.org/2000/svg" width="904" height="{height}" '
                f'viewBox="0 0 904 {height}">\n' + "\n".join(self.parts) + "\n</svg>\n")


def paint(color, attr="fill"):
    """Kvantum's SVG reader takes plain colours, with the alpha apart."""
    if color in (None, "none"):
        return f'{attr}="none"'
    r, g, b, a = theme.rgba(color)
    out = f'{attr}="#{r:02x}{g:02x}{b:02x}"'
    if a < 1:
        out += f' {attr}-opacity="{a:.3f}"'
    return out


def n(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")


def rect(x, y, w, h, color):
    if color in (None, "none") or w <= 0 or h <= 0:
        return f'<rect x="{n(x)}" y="{n(y)}" width="{n(max(w, 0.01))}" height="{n(max(h, 0.01))}" fill="none"/>'
    return f'<rect x="{n(x)}" y="{n(y)}" width="{n(w)}" height="{n(h)}" {paint(color)}/>'


def corner(ox, oy, f, b, edge, fill, where):
    """One rounded corner, f by f: an edge of width b round a filled quarter."""
    centre = {"topleft": (ox + f, oy + f), "topright": (ox, oy + f),
              "bottomleft": (ox + f, oy), "bottomright": (ox, oy)}[where]
    dirs = {"topleft": ((0, -1), (-1, 0)), "topright": ((0, -1), (1, 0)),
            "bottomleft": ((0, 1), (-1, 0)), "bottomright": ((0, 1), (1, 0))}[where]
    (d1x, d1y), (d2x, d2y) = dirs
    sweep = 1 if d1x * d2y - d1y * d2x > 0 else 0
    cx, cy = centre
    inner = f - b

    def at(d, r):
        return f"{n(cx + d[0] * r)},{n(cy + d[1] * r)}"
    # A transparent square first so the piece is always f by f.
    out = rect(ox, oy, f, f, None)
    if edge not in (None, "none") and b > 0:
        out += (f'<path d="M{at(dirs[0], f)} A{n(f)},{n(f)} 0 0 {sweep} {at(dirs[1], f)} '
                f'L{at(dirs[1], inner)} A{n(inner)},{n(inner)} 0 0 {1 - sweep} {at(dirs[0], inner)} Z" '
                f'{paint(edge)}/>')
    if fill not in (None, "none") and inner > 0:
        out += (f'<path d="M{n(cx)},{n(cy)} L{at(dirs[0], inner)} A{n(inner)},{n(inner)} 0 0 {sweep} '
                f'{at(dirs[1], inner)} Z" {paint(fill)}/>')
    return out


def frame(canvas, name, f, edge, fill, b=1.0, interior=True):
    """The nine pieces Kvantum stretches into a frame of any size."""
    for where in ("topleft", "topright", "bottomleft", "bottomright"):
        x, y = canvas.spot(f, f)
        canvas.add(f"{name}-{where}", corner(x, y, f, b, edge, fill, where))
    x, y = canvas.spot(STRIP, f)
    canvas.add(f"{name}-top", rect(x, y, STRIP, b, edge) + rect(x, y + b, STRIP, f - b, fill))
    x, y = canvas.spot(STRIP, f)
    canvas.add(f"{name}-bottom", rect(x, y, STRIP, f - b, fill) + rect(x, y + f - b, STRIP, b, edge))
    x, y = canvas.spot(f, STRIP)
    canvas.add(f"{name}-left", rect(x, y, b, STRIP, edge) + rect(x + b, y, f - b, STRIP, fill))
    x, y = canvas.spot(f, STRIP)
    canvas.add(f"{name}-right", rect(x, y, f - b, STRIP, fill) + rect(x + f - b, y, b, STRIP, edge))
    if interior:
        x, y = canvas.spot(STRIP, STRIP)
        canvas.add(name, rect(x, y, STRIP, STRIP, fill))


def framed(canvas, element, f, looks, b=1.0):
    """looks: state -> (edge, fill); every state gets a full frame."""
    for state in STATES:
        edge, fill = looks.get(state, looks["normal"])
        frame(canvas, f"{element}-{state}", f, edge, fill, b)


def chevron(canvas, name, direction, color, size=10, width=1.5):
    x, y = canvas.spot(size, size)
    s = size
    points = {
        "down": [(0.22, 0.38), (0.5, 0.66), (0.78, 0.38)],
        "up": [(0.22, 0.62), (0.5, 0.34), (0.78, 0.62)],
        "left": [(0.62, 0.22), (0.34, 0.5), (0.62, 0.78)],
        "right": [(0.38, 0.22), (0.66, 0.5), (0.38, 0.78)],
    }
    body = rect(x, y, s, s, None)
    if direction in points:
        d = " L".join(f"{n(x + px * s)},{n(y + py * s)}" for px, py in points[direction])
        body += (f'<path d="M{d}" fill="none" {paint(color, "stroke")} stroke-width="{width}" '
                 f'stroke-linecap="round" stroke-linejoin="round"/>')
    else:
        lines = [((0.25, 0.5), (0.75, 0.5))]
        if direction == "plus":
            lines.append(((0.5, 0.25), (0.5, 0.75)))
        for (ax, ay), (bx, by) in lines:
            body += (f'<path d="M{n(x + ax * s)},{n(y + ay * s)} L{n(x + bx * s)},{n(y + by * s)}" '
                     f'fill="none" {paint(color, "stroke")} stroke-width="{width}" stroke-linecap="round"/>')
    canvas.add(name, body)


def check_mark(x, y, s, color):
    return (f'<path d="M{n(x + 0.27 * s)},{n(y + 0.52 * s)} L{n(x + 0.43 * s)},{n(y + 0.68 * s)} '
            f'L{n(x + 0.74 * s)},{n(y + 0.34 * s)}" fill="none" {paint(color, "stroke")} '
            f'stroke-width="{n(s * 0.12)}" stroke-linecap="round" stroke-linejoin="round"/>')


def box(canvas, name, s, radius, edge, fill, mark=None, mark_color="#ffffff"):
    x, y = canvas.spot(s, s)
    body = rect(x, y, s, s, None)
    body += (f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="{radius}" ry="{radius}" {paint(edge)}/>'
             f'<rect x="{x + 1}" y="{y + 1}" width="{s - 2}" height="{s - 2}" rx="{max(radius - 1, 0)}" '
             f'ry="{max(radius - 1, 0)}" {paint(fill)}/>')
    if mark == "check":
        body += check_mark(x, y, s, mark_color)
    elif mark == "dash":
        body += rect(x + s * 0.28, y + s * 0.46, s * 0.44, s * 0.1, mark_color)
    elif mark == "dot":
        body += f'<circle cx="{n(x + s / 2)}" cy="{n(y + s / 2)}" r="{n(s * 0.19)}" {paint(mark_color)}/>'
    canvas.add(name, body)


def draw(c, dark):
    """All the pieces, from one colour set (theme.LIGHT or theme.DARK)."""
    cv = Canvas()
    accent, fg = c["fm_accent"], c["fm_fg"]
    soft = "rgba(255, 255, 255, 0.07)" if dark else "rgba(0, 0, 0, 0.035)"
    # Buttons (also combo boxes, tool buttons and spin buttons).
    edge = c["fm_button_edge"]
    framed(cv, "button", 6, {
        "normal": (edge, c["fm_button"]), "focused": (edge, c["fm_button_hover"]),
        "pressed": (edge, c["fm_button_active"]), "toggled": (edge, c["fm_button_active"]),
        "disabled": (c["fm_line"], c["fm_bg"])})
    # The default button (the one Return presses): tinted with the accent
    # and edged in it. Kvantum draws its label in the usual text colour, so
    # the tint stays light enough to read on. No corner mark.
    tint = "rgba(47, 123, 245, 0.16)" if not dark else "rgba(58, 134, 255, 0.38)"
    frame(cv, "button-default", 6, accent, theme.over(tint, c["fm_button"]))
    x, y = cv.spot(4, 4)
    cv.add("button-default-indicator", rect(x, y, 4, 4, None))
    # Flat tool buttons: nothing until the pointer is on them.
    framed(cv, "tbutton", 6, {
        "normal": (None, None), "focused": (None, c["fm_hover"]), "pressed": (None, c["fm_pressed"]),
        "toggled": (None, c["fm_pressed"]), "disabled": (None, None)})
    # Text fields: a hairline edge, and the accent round them while typing.
    focus_ring = "rgba(47, 123, 245, 0.75)" if not dark else "rgba(58, 134, 255, 0.85)"
    framed(cv, "lineedit", 6, {
        "normal": (c["fm_edge"], c["fm_field"]), "focused": (focus_ring, c["fm_field"]),
        "pressed": (focus_ring, c["fm_field"]), "toggled": (focus_ring, c["fm_field"]),
        "disabled": (c["fm_line"], c["fm_bg"])}, b=1.5)
    # Tabs: a row like a segmented control; the open one is raised.
    framed(cv, "tab", 6, {
        "normal": (None, soft), "focused": (None, c["fm_hover"] if not dark else "rgba(255, 255, 255, 0.14)"),
        "pressed": (edge, c["fm_button_active"]), "toggled": (edge, c["fm_button"]),
        "disabled": (None, soft)})
    frame(cv, "tabframe-normal", 8, c["fm_line"], soft)
    for state in ("normal", "disabled"):
        frame(cv, f"common-{state}", 6, c["fm_line"], None, interior=False)
        frame(cv, f"group-{state}", 8, c["fm_line"], soft)
    # Focus ring for keyboard use.
    frame(cv, "focus", 7, "rgba(47, 123, 245, 0.55)", None, b=2.5, interior=False)
    # Scroll bars: a thin pill, with no track, darker under the pointer.
    thumb = "rgba(255, 255, 255, {})" if dark else "rgba(0, 0, 0, {})"
    framed(cv, "scrollbarslider", 4, {
        "normal": (None, thumb.format(0.32)), "focused": (None, thumb.format(0.48)),
        "pressed": (None, thumb.format(0.58)), "toggled": (None, thumb.format(0.48)),
        "disabled": (None, thumb.format(0.16))}, b=0)
    # Progress bars and sliders: a soft track, the done part in the accent.
    framed(cv, "progress", 3, {"normal": (None, c["fm_track"])}, b=0)
    framed(cv, "progress-pattern", 3, {"normal": (None, accent), "disabled": (None, c["fm_track"])}, b=0)
    framed(cv, "slider", 2, {"normal": (None, c["fm_track"]), "toggled": (None, accent),
                             "disabled": (None, c["fm_track"])}, b=0)
    knob_edge = "rgba(0, 0, 0, 0.22)" if not dark else "rgba(255, 255, 255, 0.16)"
    knob = "#ffffff" if not dark else "#cfcfd4"
    for state, fill in (("normal", knob), ("focused", knob), ("pressed", "#f0f0f2" if not dark else "#bdbdc3"),
                        ("toggled", knob), ("disabled", c["fm_bg"])):
        for kind in ("slidercursor", "slidercursor-tickless"):
            x, y = cv.spot(18, 18)
            cv.add(f"{kind}-{state}", rect(x, y, 18, 18, None)
                   + f'<circle cx="{x + 9}" cy="{y + 9.6}" r="8" {paint("rgba(0, 0, 0, 0.12)")}/>'
                   + f'<circle cx="{x + 9}" cy="{y + 9}" r="8" {paint(knob_edge)}/>'
                   + f'<circle cx="{x + 9}" cy="{y + 9}" r="7.2" {paint(fill)}/>')
    # Check boxes and radio buttons.
    off_fill = c["fm_field"]
    for state in STATES:
        dim = state == "disabled"
        on = theme.over("rgba(255, 255, 255, 0.45)", accent) if dim else accent
        hover = c["fm_button_hover"] if state == "focused" else off_fill
        box(cv, f"checkbox-{state}", 16, 4, c["fm_edge"], c["fm_bg"] if dim else hover)
        box(cv, f"checkbox-checked-{state}", 16, 4, on, on, "check")
        box(cv, f"checkbox-tristate-{state}", 16, 4, on, on, "dash")
        box(cv, f"radio-{state}", 16, 8, c["fm_edge"], c["fm_bg"] if dim else hover)
        box(cv, f"radio-checked-{state}", 16, 8, on, on, "dot")
        # In menus: just the mark.
        box(cv, f"menu-checkbox-{state}", 16, 4, None, None)
        box(cv, f"menu-checkbox-checked-{state}", 16, 4, None, None, "check", fg)
        box(cv, f"menu-checkbox-tristate-{state}", 16, 4, None, None, "dash", fg)
        box(cv, f"menu-radio-{state}", 16, 8, None, None)
        box(cv, f"menu-radio-checked-{state}", 16, 8, None, None, "dot", fg)
    # Menus: rounded, with the item under the pointer in the accent.
    popover = c["fm_popover"]
    frame(cv, "menu-normal", 8, c["fm_edge"], popover)
    framed(cv, "menuitem", 5, {"normal": (None, None), "focused": (None, accent), "pressed": (None, accent),
                               "toggled": (None, accent), "disabled": (None, None)}, b=0)
    framed(cv, "menubaritem", 5, {"normal": (None, None), "focused": (None, c["fm_pressed"]),
                                  "pressed": (None, c["fm_pressed"]), "toggled": (None, c["fm_pressed"]),
                                  "disabled": (None, None)}, b=0)
    frame(cv, "tooltip-normal", 6, c["fm_edge"], popover)
    # Lists and trees: a soft hover, the chosen row in the accent.
    framed(cv, "itemview", 5, {"normal": (None, None), "focused": (None, c["fm_hover"]),
                               "pressed": (None, accent), "toggled": (None, accent),
                               "disabled": (None, None)}, b=0)
    # Column headers: flat, with a hairline under and between them.
    for state in STATES:
        name = f"header-{state}"
        fill = c["fm_view"] if state != "focused" else theme.over(c["fm_hover"], c["fm_view"])
        line = c["fm_line"]
        for where in ("topleft", "topright", "top", "left"):
            x, y = cv.spot(1 if where in ("left",) else STRIP, 1)
            cv.add(f"{name}-{where}", rect(x, y, 1, 1, fill))
        for where in ("bottomleft", "bottom", "bottomright", "right"):
            x, y = cv.spot(STRIP, STRIP)
            cv.add(f"{name}-{where}", rect(x, y, STRIP, STRIP, line))
        x, y = cv.spot(STRIP, STRIP)
        cv.add(name, rect(x, y, STRIP, STRIP, fill))
    # Splitter: a hairline.
    for state in ("normal", "focused", "pressed"):
        x, y = cv.spot(STRIP, STRIP)
        cv.add(f"splitter-{state}", rect(x, y, STRIP, STRIP, c["fm_line"] if state == "normal" else accent))
    # Arrows, plus and minus.
    for state in STATES:
        color = c["fm_dim"] if state == "disabled" else (accent if state == "pressed" else fg)
        for d in ("down", "up", "left", "right", "plus", "minus"):
            chevron(cv, f"arrow-{d}-{state}", d, color)
        chevron(cv, f"dropdown-{state}", "down", color)
        # Tree rows: a chevron pointing right when shut, down when open.
        dim = c["fm_dim"] if state != "pressed" else accent
        chevron(cv, f"expander-plus-{state}", "right", dim)
        chevron(cv, f"expander-minus-{state}", "down", dim)
        # Pop-up menus (combo boxes): a small accent tile with a chevron
        # up and a chevron down, the sign a choice opens a menu.
        x, y = cv.spot(16, 16)
        tile = {"disabled": c["fm_track"], "pressed": theme.over("rgba(0, 0, 0, 0.15)", accent)}.get(state, accent)
        mark = c["fm_dim"] if state == "disabled" else "#ffffff"
        cv.add(f"popup-{state}", rect(x, y, 16, 16, None)
               + f'<rect x="{x}" y="{y}" width="16" height="16" rx="4" ry="4" {paint(tile)}/>'
               + f'<path d="M{x + 5},{y + 6.6} L{x + 8},{y + 3.8} L{x + 11},{y + 6.6} '
                 f'M{x + 5},{y + 9.4} L{x + 8},{y + 12.2} L{x + 11},{y + 9.4}" fill="none" '
                 f'{paint(mark, "stroke")} stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>')
    # The line between groups of menu items.
    x, y = cv.spot(STRIP, 9)
    cv.add("menuitem-separator", rect(x, y, STRIP, 9, None) + rect(x, y + 4, STRIP, 1, c["fm_line"]))
    # A small cross to close a tab.
    for state in ("normal", "focused", "pressed"):
        x, y = cv.spot(12, 12)
        bg = {"normal": None, "focused": c["fm_hover"], "pressed": c["fm_pressed"]}[state]
        body = rect(x, y, 12, 12, None)
        if bg:
            body += f'<circle cx="{x + 6}" cy="{y + 6}" r="6" {paint(bg)}/>'
        body += (f'<path d="M{x + 3.8},{y + 3.8} L{x + 8.2},{y + 8.2} M{x + 8.2},{y + 3.8} L{x + 3.8},{y + 8.2}" '
                 f'fill="none" {paint(c["fm_dim"], "stroke")} stroke-width="1.4" stroke-linecap="round"/>')
        cv.add(f"tab-close-{state}", body)
    return cv.svg()


def kvconfig(c, dark):
    accent, fg = c["fm_accent"], c["fm_fg"]
    dim = theme.over(c["fm_dim"], c["fm_bg"])
    solid = lambda v: v if v.startswith("#") else theme.over(v, c["fm_bg"])  # noqa: E731
    text = (f"text.normal.color={fg}\ntext.focus.color={fg}\ntext.press.color={fg}\n"
            f"text.toggle.color={fg}\ntext.disabled.color={dim}\n")
    white = ("text.normal.color={fg}\ntext.focus.color=#ffffff\ntext.press.color=#ffffff\n"
             "text.toggle.color=#ffffff\n").format(fg=fg)
    return f"""[%General]
author=freemac
comment=freemac's own look for Qt apps, drawn by art/kvantum/make-kvantum.py
x11drag=menubar_and_primary_toolbar
alt_mnemonic=true
left_tabs=false
center_normal_tabs=true
attach_active_tab=false
group_toolbar_buttons=false
spread_progressbar=true
progressbar_thickness=6
composite=true
menu_shadow_depth=0
tooltip_shadow_depth=0
splitter_width=1
scroll_width=10
scroll_min_extent=40
scroll_arrows=false
transient_scrollbar=true
transient_groove=true
slider_width=4
slider_handle_width=18
slider_handle_length=18
tickless_slider_handle_size=18
check_size=16
menubar_mouse_tracking=true
toolbutton_style=0
click_behavior=0
translucent_windows=false
blurring=false
popup_blurring=false
vertical_spin_indicators=true
fill_rubberband=true
merge_menubar_with_toolbar=false
small_icon_size=16
large_icon_size=32
button_icon_size=16
toolbar_icon_size=18
animate_states=true
combo_as_lineedit=false
combo_menu=true
combo_focus_rect=false
groupbox_top_label=true
inline_spin_indicators=true
joined_inactive_tabs=false
layout_spacing=6
layout_margin=10
scrollbar_in_view=true
submenu_overlap=0
submenu_delay=150
tooltip_delay=-1
no_inactiveness=true
dialog_button_layout=3
menu_separator_height=9
spin_button_width=18
respect_DE=true

[GeneralColors]
window.color={c["fm_bg"]}
base.color={c["fm_view"]}
alt.base.color={theme.over(c["fm_hover"], c["fm_view"])}
button.color={c["fm_button"]}
light.color={theme.over("rgba(255, 255, 255, 0.6)", c["fm_button"])}
mid.light.color={theme.over("rgba(255, 255, 255, 0.3)", c["fm_button"])}
dark.color={solid(c["fm_edge"])}
mid.color={solid(c["fm_line"])}
highlight.color={accent}
inactive.highlight.color={accent}
text.color={fg}
window.text.color={fg}
button.text.color={fg}
disabled.text.color={dim}
tooltip.base.color={solid(c["fm_popover"])}
tooltip.text.color={fg}
highlight.text.color=#ffffff
link.color={accent}
link.visited.color={accent}
progress.indicator.text.color={fg}

[Hacks]
transparent_ktitle_label=true
transparent_dolphin_view=false
respect_darkness=true
force_size_grip=false
iconless_pushbutton=true
iconless_menu=true
normal_default_pushbutton=true
single_top_toolbar=true
tint_on_mouseover=0
no_selection_tint=true
transparent_arrow_button=true
disabled_icon_opacity=50
middle_click_scroll=false
centered_forms=false
kinetic_scrolling=false

[PanelButtonCommand]
frame=true
frame.element=button
frame.top=6
frame.bottom=6
frame.left=6
frame.right=6
interior=true
interior.element=button
indicator.size=10
indicator.element=arrow
{text}text.shadow=0
text.margin=1
text.iconspacing=5
text.margin.top=2
text.margin.bottom=2
text.margin.left=10
text.margin.right=10
frame.expansion=12
focusFrame=true
focusRectElement=focus

[PanelButtonTool]
inherits=PanelButtonCommand

[ToolbarButton]
inherits=PanelButtonCommand
frame.element=tbutton
interior.element=tbutton
text.margin.left=4
text.margin.right=4

[ToolbarComboBox]
inherits=PanelButtonCommand

[ToolbarLineEdit]
inherits=LineEdit

[Dock]
inherits=PanelButtonCommand
frame.element=common
interior=false

[DockTitle]
inherits=PanelButtonCommand
frame=false
interior=false
text.bold=true

[IndicatorSpinBox]
inherits=PanelButtonCommand
frame.element=button
interior.element=button
indicator.element=arrow
indicator.size=8

[RadioButton]
inherits=PanelButtonCommand
frame=false
interior.element=radio
focusFrame=false

[CheckBox]
inherits=PanelButtonCommand
frame=false
interior.element=checkbox
focusFrame=false

[GenericFrame]
inherits=PanelButtonCommand
frame=true
interior=false
frame.element=common
frame.top=6
frame.bottom=6
frame.left=6
frame.right=6
frame.expansion=0

[LineEdit]
inherits=PanelButtonCommand
frame.element=lineedit
interior.element=lineedit
frame.expansion=12
text.margin.left=6
text.margin.right=6
focusFrame=false

[DropDownButton]
inherits=PanelButtonCommand
indicator.element=dropdown

[IndicatorArrow]
indicator.element=arrow
indicator.size=10

[ToolboxTab]
inherits=PanelButtonCommand
frame.element=tbutton
interior.element=tbutton

[Tab]
inherits=PanelButtonCommand
frame.element=tab
interior.element=tab
indicator.element=tab
indicator.size=12
text.margin.left=12
text.margin.right=12
text.margin.top=2
text.margin.bottom=2
frame.expansion=12
min_width=+0.3font
focusFrame=false

[TabFrame]
inherits=PanelButtonCommand
frame.element=tabframe
interior=true
interior.element=tabframe
frame.top=8
frame.bottom=8
frame.left=8
frame.right=8
frame.expansion=0

[TabBarFrame]
inherits=GenericFrame
frame=false
interior=false

[TreeExpander]
inherits=PanelButtonCommand
frame=false
interior=false
indicator.size=10
indicator.element=expander

[HeaderSection]
inherits=PanelButtonCommand
frame.element=header
interior.element=header
frame.top=1
frame.bottom=1
frame.left=1
frame.right=1
frame.expansion=0
text.bold=false
focusFrame=false

[SizeGrip]
inherits=PanelButtonCommand
frame=false
interior=false
indicator.element=none

[Toolbar]
inherits=PanelButtonCommand
frame=false
interior=false
indicator.element=none
text.margin=0

[Slider]
inherits=PanelButtonCommand
frame.element=slider
interior.element=slider
frame.top=2
frame.bottom=2
frame.left=2
frame.right=2
frame.expansion=0
focusFrame=false

[SliderCursor]
inherits=PanelButtonCommand
frame=false
interior.element=slidercursor

[Progressbar]
inherits=PanelButtonCommand
frame.element=progress
interior.element=progress
frame.top=3
frame.bottom=3
frame.left=3
frame.right=3
text.margin=0
text.bold=false
frame.expansion=0

[ProgressbarContents]
inherits=PanelButtonCommand
frame=true
frame.element=progress-pattern
interior.element=progress-pattern
frame.top=3
frame.bottom=3
frame.left=3
frame.right=3
frame.expansion=0

[ItemView]
inherits=PanelButtonCommand
frame.element=itemview
interior.element=itemview
frame.top=5
frame.bottom=5
frame.left=5
frame.right=5
frame.expansion=0
{white}text.margin.top=0
text.margin.bottom=0
text.margin.left=4
text.margin.right=4
focusFrame=false

[Splitter]
inherits=PanelButtonCommand
frame=false
interior.element=splitter
indicator.element=none

[Scrollbar]
inherits=PanelButtonCommand
indicator.element=none
indicator.size=0

[ScrollbarSlider]
inherits=PanelButtonCommand
frame.element=scrollbarslider
interior.element=scrollbarslider
frame.top=4
frame.bottom=4
frame.left=4
frame.right=4
frame.expansion=0
indicator.element=none

[ScrollbarGroove]
inherits=PanelButtonCommand
interior=false
frame=false

[MenuItem]
inherits=PanelButtonCommand
frame=true
frame.element=menuitem
interior.element=menuitem
indicator.element=menuitem
frame.top=3
frame.bottom=3
frame.left=5
frame.right=5
frame.expansion=0
{white}text.margin.top=1
text.margin.bottom=1
text.margin.left=8
text.margin.right=8
focusFrame=false

[MenuBar]
inherits=PanelButtonCommand
frame=false
interior=false

[MenuBarItem]
inherits=PanelButtonCommand
interior=true
frame.element=menubaritem
interior.element=menubaritem
frame.top=5
frame.bottom=5
frame.left=5
frame.right=5
text.margin.left=7
text.margin.right=7
frame.expansion=0
focusFrame=false

[TitleBar]
inherits=PanelButtonCommand
frame=false
interior=false
text.bold=true

[ComboBox]
inherits=PanelButtonCommand
indicator.element=popup
indicator.size=16
text.margin.right=4

[Menu]
inherits=PanelButtonCommand
frame.element=menu
interior.element=menu
frame.top=8
frame.bottom=8
frame.left=8
frame.right=8
frame.expansion=0
focusFrame=false

[GroupBox]
inherits=GenericFrame
frame=true
frame.element=group
interior=true
interior.element=group
frame.top=8
frame.bottom=8
frame.left=8
frame.right=8
text.bold=true

[ToolTip]
inherits=GenericFrame
frame.element=tooltip
interior=true
interior.element=tooltip
frame.top=6
frame.bottom=6
frame.left=6
frame.right=6
text.margin.left=6
text.margin.right=6
focusFrame=false

[StatusBar]
inherits=GenericFrame
frame=false
interior=false

[Window]
interior=false
frame=false
"""


def main(out):
    for name, colors, dark in (("freemac", theme.LIGHT, False), ("freemac-dark", theme.DARK, True)):
        folder = os.path.join(out, name)
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, name + ".svg"), "w") as f:
            f.write(draw(colors, dark))
        with open(os.path.join(folder, name + ".kvconfig"), "w") as f:
            f.write(kvconfig(colors, dark))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "Kvantum"))
