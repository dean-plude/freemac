# freemac-zoom (GTK 3 module)

GTK apps draw their own title bar, so Strata can't see the pointer resting
on their green button. This small GTK 3 module, loaded into every GTK 3 app
through `GTK_MODULES=freemac-zoom` (set by freemac-session when the module
is installed), watches each headerbar's maximize button and tells Topline
`hover PID` when the pointer arrives and `unhover PID` when it leaves or the
button is pressed, over `$XDG_RUNTIME_DIR/freemac-topline.sock`. Topline then
asks Strata (`strata/pointer`) where the pointer is and shows the green
button's Move & Resize menu.

`strata/build.sh` builds it as `libfreemac-zoom.so`; the ISO installs it in
GTK's `gtk-3.0/modules` folder. Original freemac code, GPL-3.0-or-later.
