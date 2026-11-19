# strata-shell

Strata's version of Wayfire's `gtk-shell` plugin, which GTK apps talk to on
Wayland. It does everything the stock plugin does, plus:

- it keeps the menu addresses a GTK app gives for each window (its bus name
  and the paths of its menu bar, app menu, window actions and app actions),
  which the stock plugin throws away
- it answers the IPC call `strata/app-menus {"id": VIEW_ID}` with them, so
  Topline can read the focused app's menus over D-Bus (`org.gtk.Menus`,
  `org.gtk.Actions`) and show them in the bar
- with `[strata-shell] global_menus = true` (the default) it tells GTK apps
  the desktop shows their menu bar, so they leave it out of the window

This is a modified copy of `plugins/protocols/gtk-shell.cpp` and
`proto/gtk-shell.xml` from the Wayfire snapshot that Ubuntu 24.04 ships
(0.8.0+git20240110, MIT licence, see `LICENSE.wayfire`). Our changes are
GPL-3.0-or-later like the rest of freemac. With another Wayfire plugin API the
build skips it and the stock `gtk-shell` stays in use (apps then keep their
menus in their windows).

Qt and other non-GTK apps publish menus differently; Topline doesn't show
those yet.
