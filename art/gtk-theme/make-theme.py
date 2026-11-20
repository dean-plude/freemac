#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Write the freemac and freemac-dark GTK 3 themes into a themes folder.

    make-theme.py /usr/share/themes

Each theme is GTK's own Adwaita (light or dark) with common.css on top, using
the colours below. The colours are freemac's own.
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


def theme(colors, dark):
    defines = "".join(f"@define-color {k} {v};\n" for k, v in colors.items())
    with open(os.path.join(HERE, "common.css")) as f:
        common = f.read()
    return f'@import url("{ADWAITA.format("-dark" if dark else "")}");\n\n{defines}\n{common}'


def main(target):
    for name, colors, dark in (("freemac", LIGHT, False), ("freemac-dark", DARK, True)):
        folder = os.path.join(target, name, "gtk-3.0")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "gtk.css"), "w") as f:
            f.write(theme(colors, dark))
        with open(os.path.join(target, name, "index.theme"), "w") as f:
            f.write(f"[Desktop Entry]\nType=X-GNOME-Metatheme\nName={name}\n"
                    f"Comment=freemac's own GTK theme\n\n[X-GNOME-Metatheme]\nGtkTheme={name}\n"
                    f"IconTheme=freemac\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "themes"))
