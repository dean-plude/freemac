# SPDX-License-Identifier: GPL-3.0-or-later
"""Gauge: what the computer is busy with.

A list of the open apps, or of every program, with how much of the
processor and memory each is using, refreshed every two seconds. CPU and
Memory at the top choose which the list is sorted by and what the panel
below shows: the whole machine's use now, with a graph of the last two
minutes. Select one and click the stop button to quit it, or force it to
quit when it has stopped answering.

Original freemac code; the reading of /proc is in gauge_store.
"""
import os
import signal
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import alert, apps, gauge_store, menus, style  # noqa: E402
from .gauge_store import size_words  # noqa: E402

APP_ID = "org.freemac.Gauge"
EVERY = 2000          # milliseconds between samples
ICON = 16

# ListStore columns
(C_KEY, C_ICON, C_NAME, C_CPU, C_CPU_TEXT, C_MEM, C_MEM_TEXT,
 C_THREADS, C_PID, C_PID_TEXT, C_USER) = range(11)

SHOW_APPS, SHOW_MINE, SHOW_ALL = "apps", "mine", "all"
SHOW_TITLES = {SHOW_APPS: "Apps", SHOW_MINE: "My Processes", SHOW_ALL: "All Processes"}

# Programs that are the desktop itself: quitting them would end the session.
SESSION = {"wayfire", "systemd", "dbus-daemon", "dbus-broker", "pipewire", "wireplumber", "gnome-keyring-daemon"}

CSS = b"""
.gauge-panel { border-top: 1px solid alpha(currentColor, 0.12); padding: 12px 18px; }
.gauge-figure { font-feature-settings: "tnum"; }
.gauge-caption { opacity: 0.6; font-size: 0.9em; }
.gauge-graph { background-color: alpha(currentColor, 0.04); border: 1px solid alpha(currentColor, 0.12);
               border-radius: 6px; }
"""

USER_COLOUR = (0.22, 0.52, 0.96)      # blue: apps' own work
SYSTEM_COLOUR = (0.92, 0.33, 0.30)    # red: the system's work for them
MEMORY_COLOUR = (0.24, 0.70, 0.42)    # green


def percent_text(value):
    return f"{value:.1f}"


def guess_pids(app_id, processes):
    """The programs that are probably the app app_id: those named like it,
    leaving out ones started by another of them."""
    names = {app_id.lower(), app_id.split(".")[-1].lower()}
    info = apps.app_info(app_id)
    if info is not None:
        command = (info.get_commandline() or "").split()
        if command:
            names.add(os.path.basename(command[0]).lower())
    found = {pid for pid, proc in processes.items() if proc.name.lower() in names and proc.uid == os.getuid()}
    return sorted(pid for pid in found if processes[pid].ppid not in found)


class Graph(Gtk.DrawingArea):
    """A small history graph: stacked filled areas, newest at the right."""

    def __init__(self):
        super().__init__()
        self.set_size_request(240, 72)
        self.get_style_context().add_class("gauge-graph")
        self.series = []     # [(colour, [values 0..1])], drawn bottom up
        self.connect("draw", self._draw)

    def show(self, series):
        self.series = series
        self.queue_draw()

    def _draw(self, widget, cr):
        width, height = widget.get_allocated_width(), widget.get_allocated_height()
        Gtk.render_background(widget.get_style_context(), cr, 0, 0, width, height)
        Gtk.render_frame(widget.get_style_context(), cr, 0, 0, width, height)
        if not self.series:
            return False
        count = gauge_store.HISTORY
        step = (width - 4) / max(1, count - 1)
        base = [0.0] * max(len(v) for _c, v in self.series)
        for colour, values in self.series:
            n = len(values)
            if n < 2:
                continue
            tops = [min(1.0, b + v) for b, v in zip(base[-n:], values)]
            x0 = width - 2 - (n - 1) * step
            cr.move_to(x0, height - 2 - base[-n] * (height - 4))
            for i, top in enumerate(tops):
                cr.line_to(x0 + i * step, height - 2 - top * (height - 4))
            for i in range(n - 1, -1, -1):
                cr.line_to(x0 + i * step, height - 2 - base[-n:][i] * (height - 4))
            cr.close_path()
            cr.set_source_rgba(*colour, 0.55)
            cr.fill_preserve()
            cr.set_source_rgba(*colour, 0.9)
            cr.set_line_width(1)
            cr.stroke()
            base[-n:] = tops
        return False


def figure(caption):
    """A caption and its value, one line: "User:   12.3%"."""
    row = Gtk.Box(spacing=8)
    name = Gtk.Label(label=caption, xalign=1)
    name.get_style_context().add_class("gauge-caption")
    name.set_size_request(110, -1)
    value = Gtk.Label(label="–", xalign=0)
    value.get_style_context().add_class("gauge-figure")
    row.pack_start(name, False, False, 0)
    row.pack_start(value, False, False, 0)
    return row, value


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Gauge")
        self.set_default_size(820, 560)
        self.wf = None
        try:
            from .wfipc import Wayfire
            self.wf = Wayfire()
        except (OSError, ConnectionError):
            self.wf = None
        self.sampler = gauge_store.Sampler()
        self.show_what = SHOW_APPS
        self.tab = "cpu"
        self.rows = {}           # key -> row dict of the last sample
        self.iters = {}          # key -> TreeIter
        self.shown = {}          # key -> the values last put in its row
        self.app_windows = {}    # app_id -> [view ids]

        header = Gtk.HeaderBar(show_close_button=True)
        header.set_title("Gauge")
        header.set_subtitle(SHOW_TITLES[self.show_what])
        self.header = header
        self.set_titlebar(header)

        self.stop = Gtk.Button.new_from_icon_name("process-stop-symbolic", Gtk.IconSize.BUTTON)
        self.stop.set_tooltip_text("Quit the selected app or process")
        self.stop.connect("clicked", lambda _b: self.quit_selected())
        header.pack_start(self.stop)

        tabs = Gtk.Box()
        tabs.get_style_context().add_class("linked")
        self.cpu_tab = Gtk.RadioButton.new_with_label(None, "CPU")
        self.mem_tab = Gtk.RadioButton.new_with_label_from_widget(self.cpu_tab, "Memory")
        for tab in (self.cpu_tab, self.mem_tab):
            tab.set_mode(False)
            tab.set_size_request(84, -1)
            tabs.pack_start(tab, False, False, 0)
        self.cpu_tab.connect("toggled", lambda b: b.get_active() and self.choose_tab("cpu"))
        self.mem_tab.connect("toggled", lambda b: b.get_active() and self.choose_tab("memory"))
        header.set_custom_title(tabs)

        self.search = Gtk.SearchEntry(placeholder_text="Search")
        self.search.set_width_chars(16)
        self.search.connect("search-changed", lambda _e: self.filter.refilter())
        header.pack_end(self.search)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.store = Gtk.ListStore(str, Gio.Icon, str, float, str, float, str, int, int, str, str)
        self.filter = self.store.filter_new()
        self.filter.set_visible_func(self._visible)
        self.sorted = Gtk.TreeModelSort(model=self.filter)
        self.view = Gtk.TreeView(model=self.sorted)
        self.view.set_search_entry(self.search)
        self.view.get_selection().connect("changed", lambda _s: self._update_stop())
        self.view.connect("row-activated", self._activated)
        self._columns()
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.add(self.view)
        box.pack_start(scroll, True, True, 0)
        box.pack_start(self._panel(), False, False, 0)
        self.add(box)

        menus.add_actions(self, {"quit-process": self.quit_selected, "close": self.close,
                                 "cpu": lambda: self.cpu_tab.set_active(True),
                                 "memory": lambda: self.mem_tab.set_active(True),
                                 "find": self.search.grab_focus})
        show = Gio.SimpleAction.new_stateful("show", GLib.VariantType.new("s"), GLib.Variant("s", self.show_what))
        show.connect("change-state", self._show_changed)
        self.add_action(show)
        self.connect("key-press-event", self._key)

        header.show_all()
        box.show_all()
        self.choose_tab("cpu")
        self.refresh()
        self._timer = GLib.timeout_add(EVERY, self.refresh)
        self.connect("destroy", lambda *_: GLib.source_remove(self._timer))

    # -- building --

    def _columns(self):
        name = Gtk.TreeViewColumn("Name")
        icon = Gtk.CellRendererPixbuf(stock_size=Gtk.IconSize.MENU)
        name.pack_start(icon, False)
        name.add_attribute(icon, "gicon", C_ICON)
        text = Gtk.CellRendererText(ellipsize=Pango.EllipsizeMode.END)
        name.pack_start(text, True)
        name.add_attribute(text, "text", C_NAME)
        name.set_expand(True)
        name.set_sort_column_id(C_NAME)
        name.set_resizable(True)
        self.view.append_column(name)
        self.cpu_column = self._number("% CPU", C_CPU_TEXT, C_CPU)
        self.mem_column = self._number("Memory", C_MEM_TEXT, C_MEM)
        self._number("Threads", C_THREADS, C_THREADS)
        self._number("PID", C_PID_TEXT, C_PID)
        user = Gtk.TreeViewColumn("User", Gtk.CellRendererText(), text=C_USER)
        user.set_sort_column_id(C_USER)
        user.set_min_width(80)
        self.view.append_column(user)

    def _number(self, title, text_column, sort_column):
        cell = Gtk.CellRendererText(xalign=1.0)
        attrs = Pango.AttrList()
        attrs.insert(Pango.attr_font_features_new("tnum"))
        cell.set_property("attributes", attrs)
        column = Gtk.TreeViewColumn(title, cell, text=text_column)
        column.set_alignment(1.0)
        column.set_sort_column_id(sort_column)
        column.set_min_width(80)
        self.view.append_column(column)
        return column

    def _panel(self):
        panel = Gtk.Box(spacing=24)
        panel.get_style_context().add_class("gauge-panel")
        self.left = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.right = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        cpu_left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        row, self.f_system = figure("System:")
        cpu_left.pack_start(row, False, False, 0)
        row, self.f_user = figure("User:")
        cpu_left.pack_start(row, False, False, 0)
        row, self.f_idle = figure("Idle:")
        cpu_left.pack_start(row, False, False, 0)
        mem_left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        row, self.f_total = figure("Memory:")
        mem_left.pack_start(row, False, False, 0)
        row, self.f_used = figure("Memory Used:")
        mem_left.pack_start(row, False, False, 0)
        row, self.f_cached = figure("Cached Files:")
        mem_left.pack_start(row, False, False, 0)
        row, self.f_swap = figure("Swap Used:")
        mem_left.pack_start(row, False, False, 0)
        self.left.add_named(cpu_left, "cpu")
        self.left.add_named(mem_left, "memory")

        middle = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.graph_title = Gtk.Label(label="CPU Load", xalign=0.5)
        self.graph_title.get_style_context().add_class("gauge-caption")
        self.graph = Graph()
        middle.pack_start(self.graph_title, False, False, 0)
        middle.pack_start(self.graph, True, True, 0)

        cpu_right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        row, self.f_threads = figure("Threads:")
        cpu_right.pack_start(row, False, False, 0)
        row, self.f_processes = figure("Processes:")
        cpu_right.pack_start(row, False, False, 0)
        row, self.f_cores = figure("Cores:")
        self.f_cores.set_text(str(gauge_store.CORES))
        cpu_right.pack_start(row, False, False, 0)
        mem_right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.pressure = Gtk.Label(xalign=0, wrap=True, max_width_chars=28)
        mem_right.pack_start(self.pressure, False, False, 0)
        self.right.add_named(cpu_right, "cpu")
        self.right.add_named(mem_right, "memory")

        panel.pack_start(self.left, False, False, 0)
        panel.pack_start(middle, True, True, 0)
        panel.pack_start(self.right, False, False, 0)
        return panel

    # -- choosing what to see --

    def choose_tab(self, tab):
        self.tab = tab
        self.left.set_visible_child_name(tab)
        self.right.set_visible_child_name(tab)
        self.graph_title.set_text("CPU Load" if tab == "cpu" else "Memory Used")
        self.sorted.set_sort_column_id(C_CPU if tab == "cpu" else C_MEM, Gtk.SortType.DESCENDING)
        self._draw_panel()

    def _show_changed(self, action, value):
        action.set_state(value)
        self.show_what = value.get_string()
        self.header.set_subtitle(SHOW_TITLES.get(self.show_what, ""))
        self.store.clear()
        self.iters.clear()
        self.shown.clear()
        self.refresh()

    def _visible(self, model, it, _data):
        text = self.search.get_text().strip().lower()
        if not text:
            return True
        return text in (model[it][C_NAME] or "").lower() or text == str(model[it][C_PID])

    # -- reading --

    def _windows(self):
        """{app_id: [pids]}, and remember each app's window ids."""
        self.app_windows = {}
        if self.wf is None:
            return {}
        views = self.wf.views()
        pids = self.wf.view_pids()
        out = {}
        for view in views:
            app_id = view.get("app-id") or ""
            if not app_id:
                continue
            self.app_windows.setdefault(app_id, []).append(view["id"])
            if pids is None:
                continue
            pid = pids.get(view["id"])
            if pid:
                out.setdefault(app_id, [])
                if pid not in out[app_id]:
                    out[app_id].append(pid)
        if pids is None:
            # A compositor that can't say whose each window is: go by name.
            out = {app_id: guess_pids(app_id, self.sampler.processes) for app_id in self.app_windows}
            out = {app_id: found for app_id, found in out.items() if found}
        return out

    def refresh(self):
        self.sampler.sample()
        if self.show_what == SHOW_APPS:
            rows = self.sampler.app_rows(self._windows())
            for row in rows:
                row["name"] = apps.display_name(row["app_id"])
                row["icon"] = apps.icon_for(row["app_id"])
        else:
            windows = self._windows()
            owner = {pid: app_id for app_id, pids in windows.items() for pid in pids}
            rows = self.sampler.rows(every=self.show_what == SHOW_ALL, uid=os.getuid())
            for row in rows:
                app_id = owner.get(row["pid"])
                if app_id:
                    row["name"] = apps.display_name(app_id)
                    row["icon"] = apps.icon_for(app_id)
                    row["app_id"] = app_id
                else:
                    row["icon"] = None
        self.rows = {row["key"]: row for row in rows}
        for key in list(self.iters):
            if key not in self.rows:
                self.store.remove(self.iters.pop(key))
                self.shown.pop(key, None)
        for key, row in self.rows.items():
            values = [key, row.get("icon"), row["name"], row["cpu"], percent_text(row["cpu"]),
                      float(row["memory"]), size_words(row["memory"]), row["threads"], row["pid"],
                      str(row["pid"]), row["user"]]
            it = self.iters.get(key)
            if it is None:
                self.iters[key] = self.store.append(values)
            else:
                # Only what changed, so an idle list costs nothing to keep.
                before = self.shown.get(key, ())
                changed = [i for i, v in enumerate(values) if i >= len(before) or before[i] != v]
                if changed:
                    self.store.set(it, changed, [values[i] for i in changed])
            self.shown[key] = values
        self._draw_panel()
        self._update_stop()
        return True

    def _draw_panel(self):
        s = self.sampler.summary
        if not s:
            return
        self.f_system.set_text(f"{s['system']:.1f}%")
        self.f_user.set_text(f"{s['user']:.1f}%")
        self.f_idle.set_text(f"{s['idle']:.1f}%")
        self.f_threads.set_text(f"{s['threads']:,}")
        self.f_processes.set_text(f"{s['count']:,}")
        self.f_total.set_text(size_words(s["total"]))
        self.f_used.set_text(size_words(s["used"]))
        self.f_cached.set_text(size_words(s["cached"]))
        self.f_swap.set_text(size_words(s["swap_used"]) if s["swap_total"] else "None")
        used = s["used"] / s["total"] if s["total"] else 0
        if used > 0.9:
            self.pressure.set_text("Memory is nearly full. Quitting an app you aren't using frees some.")
        elif used > 0.75:
            self.pressure.set_text("Memory is getting busy.")
        else:
            self.pressure.set_text("There's plenty of memory free.")
        if self.tab == "cpu":
            history = list(self.sampler.cpu_history)
            self.graph.show([(SYSTEM_COLOUR, [h[1] / 100 for h in history]),
                             (USER_COLOUR, [h[0] / 100 for h in history])])
        else:
            self.graph.show([(MEMORY_COLOUR, list(self.sampler.memory_history))])

    # -- acting --

    def _selected(self):
        model, it = self.view.get_selection().get_selected()
        if it is None:
            return None
        return self.rows.get(model[it][C_KEY])

    def _update_stop(self):
        row = self._selected()
        self.stop.set_sensitive(row is not None and self._may_quit(row))

    def _may_quit(self, row):
        if row["pid"] in (os.getpid(), 1):
            return False
        proc = self.sampler.processes.get(row["pid"])
        return proc is None or proc.name not in SESSION

    def _activated(self, _view, path, _column):
        row = self.rows.get(self.sorted[path][C_KEY])
        if row and row.get("app_id") and self.wf is not None:
            ids = self.app_windows.get(row["app_id"]) or []
            if ids:
                self.wf.set_minimized(ids[0], False)
                self.wf.focus(ids[0])

    def quit_selected(self):
        row = self._selected()
        if row is None or not self._may_quit(row):
            return
        name = row["name"]
        icon = apps.icon_for(row["app_id"]) if row.get("app_id") else None
        FORCE, QUIT = 1, 2
        answer = alert.ask(self, f"Are you sure you want to quit “{name}”?",
                           "Force Quit ends it at once, and anything it hasn't saved is lost.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Force Quit", FORCE), ("Quit", QUIT)],
                           default=QUIT, destructive=FORCE, icon=icon)
        if answer not in (FORCE, QUIT):
            return
        failed = False
        if answer == QUIT and row.get("app_id") and self.wf is not None and self.show_what == SHOW_APPS:
            # Ask the app to close its windows, as Quit in its own menu would.
            self.wf.quit(row["app_id"])
        else:
            sig = signal.SIGKILL if answer == FORCE else signal.SIGTERM
            for pid in row["pids"]:
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
                except PermissionError:
                    failed = True
        if failed:
            alert.tell(self, f"“{name}” can't be quit from here.",
                       "It belongs to the system or to another user.")
        GLib.timeout_add(500, lambda: self.refresh() and False)

    def _key(self, _w, event):
        if event.keyval == Gdk.KEY_Delete and not self.search.has_focus():
            self.quit_selected()
            return True
        return False


def menubar():
    return menus.menubar([
        ("_File", [[("Close", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Find", "win.find", "<Ctrl>f")]]),
        ("_View", [[(SHOW_TITLES[SHOW_APPS], f"win.show::{SHOW_APPS}", None),
                    (SHOW_TITLES[SHOW_MINE], f"win.show::{SHOW_MINE}", None),
                    (SHOW_TITLES[SHOW_ALL], f"win.show::{SHOW_ALL}", None)],
                   [("CPU", "win.cpu", "<Ctrl>1"), ("Memory", "win.memory", "<Ctrl>2")],
                   [("Quit Process", "win.quit-process", "<Ctrl><Alt>q")]]),
    ])


class Gauge(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.close", ["<Control>w"]), ("win.find", ["<Control>f"]),
                             ("win.cpu", ["<Control>1"]), ("win.memory", ["<Control>2"]),
                             ("win.quit-process", ["<Control><Alt>q"])):
            self.set_accels_for_action(action, keys)
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda *_: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-gauge")
    return Gauge().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
