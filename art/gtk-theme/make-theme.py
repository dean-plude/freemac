#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Write the freemac and freemac-dark GTK 3 themes into a themes folder, and
the same colours for GTK 4 and Qt apps into a second folder. Each comes in
every accent colour Dials > Appearance offers: freemac and freemac-dark are
blue, freemac-purple and freemac-dark-purple are purple, and so on.

    make-theme.py /usr/share/themes [/usr/share/freemac]

Each GTK 3 theme is GTK's own Adwaita (light or dark) with common.css on top,
using the colours below. The colours are freemac's own. GTK 4 and libadwaita
apps take no themes, only a user style sheet, so the second folder gets
gtk4/light.css and gtk4/dark.css (Dials links ~/.config/gtk-4.0/gtk.css to the
one in use), and qt/freemac.conf and qt/freemac-dark.conf, colour schemes for
qt5ct and qt6ct, which give Qt 5 and Qt 6 apps the same colours and font.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ADWAITA = "resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained{}.css"

LIGHT = {
    "fm_bg": "#efeff1", "fm_view": "#ffffff", "fm_side": "#e5e5e8", "fm_head": "#f5f5f7",
    "fm_fg": "#1d1d1f", "fm_dim": "rgba(29, 29, 31, 0.52)", "fm_line": "rgba(0, 0, 0, 0.10)",
    "fm_edge": "rgba(0, 0, 0, 0.16)", "fm_shadow": "rgba(0, 0, 0, 0.30)",
    "fm_accent": "#2f7bf5", "fm_red": "#e5484d",
    "fm_button": "#ffffff", "fm_button_hover": "#f7f7f8", "fm_button_active": "#e3e3e6",
    "fm_button_edge": "rgba(0, 0, 0, 0.16)", "fm_field": "#ffffff",
    "fm_hover": "rgba(0, 0, 0, 0.06)", "fm_pressed": "rgba(0, 0, 0, 0.11)",
    "fm_track": "rgba(0, 0, 0, 0.10)", "fm_side_sel": "rgba(0, 0, 0, 0.09)",
    "fm_popover": "rgba(246, 246, 248, 0.98)",
    "fm_tbtn": "#c8c8cd", "fm_tbtn_hover": "#b4b4ba", "fm_tbtn_active": "#9c9ca3",
    "fm_tbtn_back": "#dcdce0", "fm_tbtn_edge": "rgba(0, 0, 0, 0.12)", "fm_tbtn_glyph": "rgba(0, 0, 0, 0.65)",
}
DARK = {
    "fm_bg": "#252528", "fm_view": "#1e1e21", "fm_side": "#2d2d31", "fm_head": "#2b2b2f",
    "fm_fg": "#ececef", "fm_dim": "rgba(236, 236, 239, 0.55)", "fm_line": "rgba(255, 255, 255, 0.09)",
    "fm_edge": "rgba(255, 255, 255, 0.14)", "fm_shadow": "rgba(0, 0, 0, 0.55)",
    "fm_accent": "#3a86ff", "fm_red": "#ec5a5f",
    "fm_button": "#45454a", "fm_button_hover": "#4f4f55", "fm_button_active": "#5a5a60",
    "fm_button_edge": "rgba(255, 255, 255, 0.10)", "fm_field": "#1f1f22",
    "fm_hover": "rgba(255, 255, 255, 0.08)", "fm_pressed": "rgba(255, 255, 255, 0.14)",
    "fm_track": "rgba(255, 255, 255, 0.14)", "fm_side_sel": "rgba(255, 255, 255, 0.12)",
    "fm_popover": "rgba(44, 44, 48, 0.98)",
    "fm_tbtn": "#55555b", "fm_tbtn_hover": "#68686f", "fm_tbtn_active": "#7a7a82",
    "fm_tbtn_back": "#444449", "fm_tbtn_edge": "rgba(255, 255, 255, 0.08)", "fm_tbtn_glyph": "rgba(255, 255, 255, 0.85)",
}


# Accent colours (light mode, dark mode), in the order Dials shows them.
# freemac's own values; blue is the one the themes always had.
ACCENTS = {
    "blue": ("#2f7bf5", "#3a86ff"),
    "purple": ("#8f52d9", "#a66cec"),
    "pink": ("#de4a80", "#ec6396"),
    "red": ("#dc3d42", "#ec5257"),
    "orange": ("#ea7a17", "#fb8c2c"),
    "yellow": ("#d39a07", "#e9b21f"),
    "green": ("#2c9f4c", "#3cb75d"),
    "graphite": ("#7d7d84", "#93939b"),
}


def name(accent, dark):
    """freemac, freemac-dark, freemac-purple, freemac-dark-purple…"""
    return "freemac" + ("-dark" if dark else "") + ("" if accent == "blue" else "-" + accent)


def variants():
    """(theme name, colours, dark, accent) for every accent, light and dark."""
    for accent, (light, dark_value) in ACCENTS.items():
        for base, dark in ((LIGHT, False), (DARK, True)):
            colors = dict(base, fm_accent=dark_value if dark else light)
            yield name(accent, dark), colors, dark, accent


def theme(colors, dark):
    # Apps' own style sheets use GTK's standard name for the selection colour,
    # which every theme has, so they follow the accent too.
    colors = dict(colors, theme_selected_bg_color=colors["fm_accent"])
    defines = "".join(f"@define-color {k} {v};\n" for k, v in colors.items())
    with open(os.path.join(HERE, "common.css")) as f:
        common = f.read()
    return f'@import url("{ADWAITA.format("-dark" if dark else "")}");\n\n{defines}\n{common}'


def rgba(value):
    """'#rrggbb' or 'rgba(r, g, b, a)' -> (r, g, b, a) with a from 0 to 1."""
    value = value.strip()
    if value.startswith("#"):
        return int(value[1:3], 16), int(value[3:5], 16), int(value[5:7], 16), 1.0
    r, g, b, a = (v.strip() for v in value[value.index("(") + 1:value.index(")")].split(","))
    return int(r), int(g), int(b), float(a)


def over(top, under):
    """A translucent colour laid over an opaque one, as one opaque colour."""
    r, g, b, a = rgba(top)
    r2, g2, b2, _ = rgba(under)
    mix = [round(c * a + c2 * (1 - a)) for c, c2 in ((r, r2), (g, g2), (b, b2))]
    return "#{:02x}{:02x}{:02x}".format(*mix)


def gtk4(colors, dark):
    """Colours for libadwaita's named colours, and our title buttons."""
    c = colors
    names = {
        "accent_color": c["fm_accent"], "accent_bg_color": c["fm_accent"], "accent_fg_color": "#ffffff",
        "destructive_color": c["fm_red"], "destructive_bg_color": c["fm_red"], "destructive_fg_color": "#ffffff",
        "window_bg_color": c["fm_bg"], "window_fg_color": c["fm_fg"],
        "view_bg_color": c["fm_view"], "view_fg_color": c["fm_fg"],
        "headerbar_bg_color": c["fm_head"], "headerbar_fg_color": c["fm_fg"],
        "headerbar_border_color": c["fm_fg"], "headerbar_backdrop_color": c["fm_bg"],
        "headerbar_shade_color": c["fm_line"],
        "sidebar_bg_color": c["fm_side"], "sidebar_fg_color": c["fm_fg"],
        "sidebar_backdrop_color": c["fm_side"], "sidebar_shade_color": c["fm_line"],
        "card_bg_color": c["fm_view"], "card_fg_color": c["fm_fg"], "card_shade_color": c["fm_line"],
        "dialog_bg_color": c["fm_bg"], "dialog_fg_color": c["fm_fg"],
        "popover_bg_color": over(c["fm_popover"], c["fm_bg"]), "popover_fg_color": c["fm_fg"],
        "shade_color": c["fm_line"],
    }
    defines = "".join(f"@define-color {k} {v};\n" for k, v in names.items())
    return f"""/* freemac's colours for GTK 4 and libadwaita apps ({"dark" if dark else "light"}). Made by
   art/gtk-theme/make-theme.py; ~/.config/gtk-4.0/gtk.css links here. */
{defines}
/* Window buttons: three small grey circles that show their sign on hover. */
windowcontrols > button {{ min-width: 14px; min-height: 14px; padding: 0; margin: 0 3px; }}
windowcontrols > button > image {{
  min-width: 14px; min-height: 14px; padding: 0; border-radius: 99px;
  background-color: {c["fm_tbtn"]}; box-shadow: inset 0 0 0 1px {c["fm_tbtn_edge"]};
  color: transparent; -gtk-icon-size: 9px;
}}
windowcontrols:hover > button > image {{ color: {c["fm_tbtn_glyph"]}; }}
windowcontrols > button:hover > image {{ background-color: {c["fm_tbtn_hover"]}; }}
windowcontrols > button:active > image {{ background-color: {c["fm_tbtn_active"]}; }}
windowcontrols > button:backdrop > image {{ background-color: {c["fm_tbtn_back"]}; }}
windowcontrols > button:hover, windowcontrols > button:active {{ background: none; box-shadow: none; }}
headerbar .title, windowtitle .title {{ font-weight: 600; }}
"""


# QPalette roles, in the order qt5ct and qt6ct colour schemes list them.
def qt(colors):
    c = colors
    roles = [c["fm_fg"], c["fm_button"], over("rgba(255, 255, 255, 0.6)", c["fm_button"]),
             over("rgba(255, 255, 255, 0.3)", c["fm_button"]), over(c["fm_edge"], c["fm_bg"]),
             over(c["fm_line"], c["fm_bg"]), c["fm_fg"], "#ffffff", c["fm_fg"], c["fm_view"], c["fm_bg"],
             "#000000", c["fm_accent"], "#ffffff", c["fm_accent"], c["fm_accent"], c["fm_side"],
             "#000000", c["fm_popover"] if c["fm_popover"].startswith("#") else over(c["fm_popover"], c["fm_bg"]),
             c["fm_fg"], over(c["fm_dim"], c["fm_view"])]

    def line(values):
        return ", ".join("#ff" + v.lstrip("#") for v in values)
    disabled = list(roles)
    for i in (0, 6, 8):  # WindowText, Text, ButtonText
        disabled[i] = over(c["fm_dim"], c["fm_bg"])
    return (f"[ColorScheme]\nactive_colors={line(roles)}\ndisabled_colors={line(disabled)}\n"
            f"inactive_colors={line(roles)}\n")


def extras(target):
    for theme_name, colors, dark, accent in variants():
        css = ("dark" if dark else "light") + ("" if accent == "blue" else "-" + accent) + ".css"
        for folder, file, text in (("gtk4", css, gtk4(colors, dark)),
                                   ("qt", theme_name + ".conf", qt(colors))):
            os.makedirs(os.path.join(target, folder), exist_ok=True)
            with open(os.path.join(target, folder, file), "w") as f:
                f.write(text)


def main(target, extra=None):
    for theme_name, colors, dark, _accent in variants():
        folder = os.path.join(target, theme_name, "gtk-3.0")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "gtk.css"), "w") as f:
            f.write(theme(colors, dark))
        with open(os.path.join(target, theme_name, "index.theme"), "w") as f:
            f.write(f"[Desktop Entry]\nType=X-GNOME-Metatheme\nName={theme_name}\n"
                    f"Comment=freemac's own GTK theme\n\n[X-GNOME-Metatheme]\nGtkTheme={theme_name}\n"
                    f"IconTheme=freemac\n")
    if extra:
        extras(extra)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "themes", sys.argv[2] if len(sys.argv) > 2 else None))
