# strata-decor

Strata's window decoration: the title bar Wayfire draws for apps that don't
draw their own (most non-GTK apps). It matches the look of freemac's own apps:

- buttons at the left, in the order of `decoration/button_order`
- soft rounded-square buttons with a thin symbol; the close button turns
  freemac's indigo on hover
- a centred, semibold title whose colour follows the title bar colour, so it
  reads in light and dark mode (Dials sets `decoration/active_color`)

It also rounds the bottom corners of every window, its own and those of apps
that draw their own title bar (`corners.cpp`, original freemac code): a small
shader clips the two corners and bends the window's edge or shadow round the
curve, so windows are round at all four corners as on a Mac.

It reads the standard `[decoration]` options in `wayfire.ini`, so nothing else
changes when it replaces Wayfire's `decoration` plugin.

This is a modified copy of the `decor` plugin from the Wayfire snapshot that
Ubuntu 24.04 ships (0.8.0+git20240110, plugin ABI 2023-11-23) (MIT licence, see
`LICENSE.wayfire`). Our changes, mainly in `deco-theme.cpp` and
`deco-layout.cpp`, are GPL-3.0-or-later like the rest of freemac. It builds
against that plugin API; with another Wayfire the build skips it and the
stock decoration plugin stays in use.
