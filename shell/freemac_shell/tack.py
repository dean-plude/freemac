# SPDX-License-Identifier: GPL-3.0-or-later
"""Tack, the app switcher: hold Command (or Alt) and press Tab to see every
open app as a row of large icons on a translucent panel in the middle of the
screen. Each Tab moves to the next app (Shift+Tab goes back); letting go
brings the chosen app's windows to the front. A quick Command+Tab, let go at
once, swaps straight to the app used before without the panel showing.
While the panel is up, Q quits the chosen app and H hides it, as on a Mac.

    freemac-tack            run the switcher (started with the session)
    freemac-tack --next     what Command+Tab runs: show it, or move right
    freemac-tack --prev     what Command+Shift+Tab runs: show it, or move left

The key presses reach the running switcher through a small socket, so
Command+Tab answers at once instead of waiting for a new program to start.
Original freemac code.
"""
import os
import socket
import sys

SOCKET = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "freemac-tack.sock")

ICON = 96          # pixels
SHOW_AFTER = 140   # ms: a quick Command+Tab switches without the panel flashing up
HIDE_IDS = {"gtklock", "polkit-mate-authentication-agent-1"}

CSS = b"""
window.switcher, window.switcher > * {
    background: transparent;
}
.switcher-panel {
    margin: 48px;
    background-color: rgba(246, 246, 248, 0.72);
    border: 1px solid rgba(255, 255, 255, 0.55);
    border-radius: 24px;
    padding: 14px 14px 10px 14px;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.24);
}
.switcher-panel.dark {
    background-color: rgba(40, 40, 44, 0.70);
    border-color: rgba(255, 255, 255, 0.14);
}
/* Accessibility > Reduce transparency */
.switcher-panel.solid { background-color: rgb(240, 240, 243); border-color: rgba(0, 0, 0, 0.12); }
.switcher-panel.dark.solid { background-color: rgb(44, 44, 48); border-color: rgba(255, 255, 255, 0.16); }
.switcher-app {
    border-radius: 16px;
    padding: 8px;
}
.switcher-app.chosen {
    background-color: rgba(0, 0, 0, 0.16);
}
.switcher-panel.dark .switcher-app.chosen {
    background-color: rgba(255, 255, 255, 0.18);
}
.switcher-name, .switcher-name:backdrop {
    font-size: 13px;
    color: #1d1d1f;
    margin-top: 4px;
}
.switcher-panel.dark .switcher-name, .switcher-panel.dark .switcher-name:backdrop {
    color: #f2f2f4;
}
"""


def send(word):
    """Tell the running switcher to move; False when none is running."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect(SOCKET)
            s.sendall(word.encode() + b"\n")
        return True
    except OSError:
        return False


# ---- the apps and their windows ---------------------------------------------------
def open_apps(views, windowless=()):
    """Apps with windows, the one used last first, then apps still open with
    no window (as on a Mac): [(app id, [views newest first])]."""
    apps = {}
    for view in views:
        app_id = view.get("app-id") or f"view-{view.get('id')}"
        if app_id.lower() in HIDE_IDS:
            continue
        apps.setdefault(app_id, []).append(view)
    for its in apps.values():
        its.sort(key=lambda v: v.get("last-focus-timestamp", 0), reverse=True)
    ordered = sorted(apps.items(), key=lambda item: item[1][0].get("last-focus-timestamp", 0), reverse=True)
    with_windows = {app_id.lower() for app_id in apps}
    return ordered + [(app_id, []) for app_id in sorted(windowless) if app_id.lower() not in with_windows]


def minimized(view):
    return (view.get("state") or {}).get("minimized", view.get("minimized", False))


def bring_forward(wayfire, views):
    """Bring all of an app's windows to the front, the one used last on top.
    A hidden app (⌘H) comes back whole; if every window is minimized, the
    last used one comes back."""
    try:
        hidden = wayfire.hidden()
    except (ConnectionError, OSError, ValueError, AttributeError):
        hidden = set()
    shown = [v for v in views if not minimized(v) and v.get("id") not in hidden]
    if not shown and views:
        back = [v for v in views if v.get("id") in hidden] or [views[0]]
        for view in reversed(back):
            try:
                wayfire.set_minimized(view["id"], False)
            except (ConnectionError, OSError, ValueError):
                return
        shown = back
    for view in reversed(shown):
        try:
            wayfire.focus(view["id"])
        except (ConnectionError, OSError, ValueError):
            pass


def switch_without_panel(step):
    """No switcher running: just swap to the next app, as a fallback."""
    from .wfipc import Wayfire
    wayfire = Wayfire()
    apps = open_apps(wayfire.views())
    if len(apps) > 1:
        bring_forward(wayfire, apps[step % len(apps)][1])


# ---- the panel ----------------------------------------------------------------------
def run():
    import gi
    gi.require_version("Gdk", "3.0")
    gi.require_version("Gtk", "3.0")
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import Gdk, GLib, Gtk, GtkLayerShell, Pango

    from . import apps as app_names
    from . import held as held_apps, style
    from .wfipc import Wayfire

    # Command reaches apps (Tack too) as Ctrl, so letting go of Command, Ctrl
    # or Alt ends the switch.
    hold = (Gdk.ModifierType.MOD1_MASK | Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SUPER_MASK
            | Gdk.ModifierType.MOD4_MASK)
    alt_keys = (Gdk.KEY_Alt_L, Gdk.KEY_Alt_R, Gdk.KEY_Meta_L, Gdk.KEY_Meta_R)
    let_go = alt_keys + (Gdk.KEY_Super_L, Gdk.KEY_Super_R, Gdk.KEY_Control_L, Gdk.KEY_Control_R)

    def mask_of(keyval):
        if keyval in alt_keys:
            return Gdk.ModifierType.MOD1_MASK | Gdk.ModifierType.META_MASK
        return Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.MOD4_MASK

    class Switcher(Gtk.Window):
        def __init__(self):
            super().__init__(title="Switcher")
            style.make_transparent(self)
            self.get_style_context().add_class("switcher")
            GtkLayerShell.init_for_window(self)
            GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
            GtkLayerShell.set_namespace(self, "freemac-tack")
            GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)
            GtkLayerShell.set_exclusive_zone(self, -1)
            self.wayfire = Wayfire()
            self.held = held_apps.Watcher()
            self.apps, self.tiles, self.chosen = [], [], 0
            self.showing = False
            self.reveal_timer = self.check_timer = 0
            self.panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            self.panel.get_style_context().add_class("switcher-panel")
            self.row = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER)
            self.name = Gtk.Label(ellipsize=Pango.EllipsizeMode.END, max_width_chars=40)
            self.name.get_style_context().add_class("switcher-name")
            self.panel.pack_start(self.row, False, False, 0)
            self.panel.pack_start(self.name, False, False, 0)
            self.add(self.panel)
            self.add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK)
            self.connect("key-press-event", self._key_press)
            self.connect("key-release-event", self._key_release)
            self.connect("focus-in-event", lambda *_: self._check_alt())

        # -- moving through the apps
        def step(self, by):
            if not self.showing:
                self.start(by)
                return
            if self.apps:
                self.choose((self.chosen + by) % len(self.apps))

        def start(self, by):
            self.apps = open_apps(self.wayfire.views(), self.held.running_ids())
            if not self.apps:
                return
            for child in self.row.get_children():
                self.row.remove(child)
            self.tiles = []
            dark = style.is_dark()
            (self.panel.get_style_context().add_class if dark else
             self.panel.get_style_context().remove_class)("dark")
            (self.panel.get_style_context().add_class if style.solid() else
             self.panel.get_style_context().remove_class)("solid")
            hidden = self.wayfire.hidden()
            for index, (app_id, views) in enumerate(self.apps):
                image = Gtk.Image.new_from_gicon(app_names.icon_for(app_id), Gtk.IconSize.DIALOG)
                image.set_pixel_size(ICON)
                if views and all(v.get("id") in hidden for v in views):
                    image.set_opacity(0.5)   # a hidden app (⌘H) is dimmed
                tile = Gtk.EventBox()
                tile.set_visible_window(False)
                box = Gtk.Box()   # draws the highlight; an EventBox without a window doesn't
                box.get_style_context().add_class("switcher-app")
                box.add(image)
                tile.add(box)
                tile.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK)
                tile.connect("enter-notify-event", lambda _w, _e, i=index: self.choose(i))
                tile.connect("button-release-event", lambda _w, _e, i=index: self.finish(i))
                self.row.pack_start(tile, False, False, 0)
                self.tiles.append(tile)
            self.showing = True
            self.choose((by if len(self.apps) > 1 else 0) % len(self.apps))
            self.panel.set_opacity(0)
            self.show_all()
            self.reveal_timer = GLib.timeout_add(SHOW_AFTER, self._reveal)
            self.check_timer = GLib.timeout_add(100, self._check_alt)

        def choose(self, index):
            for i, tile in enumerate(self.tiles):
                context = tile.get_child().get_style_context()
                (context.add_class if i == index else context.remove_class)("chosen")
            self.chosen = index
            app_id, views = self.apps[index]
            self.name.set_text(app_names.display_name(app_id, views[0].get("title", "") if views else ""))
            return False

        def _reveal(self):
            self.reveal_timer = 0
            if self.showing:
                self.panel.set_opacity(1)
            return False

        # -- letting go
        def _check_alt(self):
            """Command or Alt let go (perhaps before we had the keyboard): switch.
            Apps see Command as Ctrl (Strata's Command key), so Tack does too."""
            if not self.showing:
                self.check_timer = 0
                return False
            # Strata always sees the keyboard, so its answer comes first; what
            # GTK knows is only as fresh as the last key Tack itself was sent.
            held = self.wayfire.held_modifiers()
            if held is not None:
                let_go_now = not (held.get("command") or held.get("alt") or held.get("control"))
            else:
                state = Gdk.Keymap.get_for_display(self.get_display()).get_modifier_state()
                let_go_now = self.is_active() and not state & hold
            if let_go_now:
                self.finish(self.chosen)
                return False
            return True

        def _key_release(self, _widget, event):
            if event.keyval in let_go and not (event.state & hold & ~mask_of(event.keyval)):
                self.finish(self.chosen)
            return True

        def _key_press(self, _widget, event):
            key = event.keyval
            if key == Gdk.KEY_Escape:
                self.stop()
            elif key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_space):
                self.finish(self.chosen)
            # ⌘← and ⌘→ reach apps as Home and End (Strata's Command key).
            elif key in (Gdk.KEY_Right, Gdk.KEY_Tab, Gdk.KEY_End, Gdk.KEY_KP_End):
                self.step(1)
            elif key in (Gdk.KEY_Left, Gdk.KEY_ISO_Left_Tab, Gdk.KEY_Home, Gdk.KEY_KP_Home, Gdk.KEY_grave):
                self.step(-1)
            elif key in (Gdk.KEY_q, Gdk.KEY_Q):
                self.quit_chosen()
            elif key in (Gdk.KEY_h, Gdk.KEY_H):
                self.hide_chosen()
            return True

        # -- Q and H, while the switcher is up (as on a Mac)
        def quit_chosen(self):
            """Quit the chosen app and take it out of the row; the rest stay."""
            if not self.showing or not self.apps:
                return
            app_id, _views = self.apps[self.chosen]
            try:
                if self.held.is_running(app_id):
                    self.held.quit(app_id)
                else:
                    self.wayfire.quit(app_id)
            except (ConnectionError, OSError, ValueError):
                return
            del self.apps[self.chosen]
            self.tiles.pop(self.chosen).destroy()
            if not self.apps:
                self.stop()
                return
            self.choose(min(self.chosen, len(self.apps) - 1))

        def hide_chosen(self):
            """Hide the chosen app's windows. It stays in the row, as on a Mac,
            and choosing it again brings its windows back."""
            if not self.showing or not self.apps:
                return
            app_id, views = self.apps[self.chosen]
            for view in views:
                try:
                    self.wayfire.hide(view["id"])
                except (ConnectionError, OSError, ValueError):
                    pass
            self.tiles[self.chosen].get_child().get_children()[0].set_opacity(0.5)   # dimmed, as on a Mac

        def finish(self, index):
            if not self.showing:
                return False
            app_id, views = self.apps[index] if 0 <= index < len(self.apps) else (None, [])
            self.stop()
            if views:
                bring_forward(self.wayfire, views)
            elif app_id:
                # Open with no window: it opens a new one.
                info = app_names.app_info(app_id)
                if info:
                    info.launch([], None)
            return True

        def stop(self):
            self.showing = False
            for timer in ("reveal_timer", "check_timer"):
                if getattr(self, timer):
                    GLib.source_remove(getattr(self, timer))
                    setattr(self, timer, 0)
            self.hide()

    style.apply()
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                             Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
    switcher = Switcher()

    try:
        os.unlink(SOCKET)
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET)
    os.chmod(SOCKET, 0o600)
    server.listen(8)

    def on_connect(_fd, _condition):
        conn, _ = server.accept()
        with conn:
            conn.settimeout(0.5)
            try:
                word = conn.recv(16).decode().strip()
            except (OSError, UnicodeDecodeError):
                return True
        if word == "next":
            switcher.step(1)
        elif word == "prev":
            switcher.step(-1)
        return True

    GLib.io_add_watch(server.fileno(), GLib.IO_IN, on_connect)
    Gtk.main()


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if args and args[0] in ("--next", "--prev"):
        word = args[0][2:]
        if not send(word):
            switch_without_panel(1 if word == "next" else -1)
        return
    run()
