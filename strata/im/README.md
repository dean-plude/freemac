# freemac-im

A quiet Wayland input method. Wayfire only tells apps which text field has
the keyboard (the text-input protocol) while an input method is running, so
freemac-im runs to switch that on and does nothing else. Strata then knows
when a text field is in use and where its text cursor is, which pressing and
holding a letter for its accents needs (`../shell/press-hold.hpp`).

Topline starts it at login; a second copy sees that the seat already has an
input method and leaves.

`freemac-im.c` is original freemac code (GPL-3.0-or-later).
`input-method-unstable-v2.xml` is the input-method protocol description as
published by the wlroots project, under its own MIT licence (kept in the
file).
