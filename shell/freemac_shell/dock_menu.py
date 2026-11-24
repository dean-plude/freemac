# SPDX-License-Identifier: GPL-3.0-or-later
"""An app's own items at the top of its Dock menu, as on a Mac (where an
app's applicationDockMenu: adds "New Window", recent chats and the like).

An app names the menu in its LauncherEntry "quicklist" (see launcher_badge)
and serves it over the session bus with the com.canonical.dbusmenu
interface, as Ferry's Mac apps and many Linux apps (Telegram, Signal and
others) do. When the Dock's menu opens, the Dock asks the app for it
(AboutToShow, then GetLayout) without waiting on it: if the app doesn't
answer within TIMEOUT_MS, or answers with an error, the menu opens with
the Dock's own items only. Choosing one of the app's items sends it back
to the app (Event with "clicked").

Separators, disabled items, ticks (and the Mac's dash for a mixed state),
hidden items and submenus are kept, as the app sent them.
"""
import re
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

INTERFACE = "com.canonical.dbusmenu"
TIMEOUT_MS = 350
# An app that didn't answer isn't asked again for this long, so its Dock
# menu doesn't keep pausing while it is stuck.
QUIET_AFTER_TIMEOUT = 30.0
TICK, DASH = "\u2713", "\u2013"

_stuck = {}   # (bus name, path) -> when it last didn't answer


def label_of(text):
    """dbusmenu's label without its access key marks ("_File" is "File",
    "__" is an underscore)."""
    return re.sub(r"_(_?)", lambda m: m.group(1), str(text or ""))


def _row(node):
    """One item of a GetLayout tree, (id, properties, children), as a dict."""
    try:
        ident, props, children = node
    except (TypeError, ValueError):
        return None
    if not isinstance(props, dict):
        props = {}
    if props.get("visible", True) is False:
        return None
    if props.get("type") == "separator":
        return {"id": ident, "separator": True}
    toggle = props.get("toggle-type") or ""
    state = props.get("toggle-state", 0) if toggle in ("checkmark", "radio") else 0
    row = {"id": ident, "label": label_of(props.get("label", "")),
           "enabled": props.get("enabled", True) is not False,
           "mark": TICK if state == 1 else (DASH if state not in (0, 1) else "")}
    kids = rows_of(children or [])
    if kids or props.get("children-display") == "submenu":
        row["children"] = kids
    return row


def rows_of(children):
    """The items under one level of a GetLayout tree, ready to show: hidden
    items dropped, and no separator first, last or twice in a row."""
    rows = []
    for child in children:
        row = _row(child)
        if row is None:
            continue
        if row.get("separator") and (not rows or rows[-1].get("separator")):
            continue
        rows.append(row)
    while rows and rows[-1].get("separator"):
        rows.pop()
    return rows


def parse_layout(reply):
    """GetLayout's reply, unpacked ((revision, (0, props, children))), as the
    rows of the menu's top level. Anything that isn't a layout gives []."""
    try:
        _revision, root = reply
        _ident, _props, children = root
    except (TypeError, ValueError):
        return []
    return rows_of(children or [])


def has_marks(rows):
    return any(row.get("mark") for row in rows)


def fetch(bus, sender, path, done, timeout_ms=TIMEOUT_MS):
    """Ask the app at sender for its Dock menu and call done(rows) once:
    with the rows when it answers in time, or with None when it fails or
    takes longer than timeout_ms. Never waits on the app."""
    key = (sender, path)
    stuck = key in _stuck and time.monotonic() - _stuck[key] < QUIET_AFTER_TIMEOUT
    if bus is None or not sender or not path or stuck:
        GLib.idle_add(lambda: done(None) or False)
        return
    cancel = Gio.Cancellable()
    state = {"over": False}

    def finish(rows):
        if state["over"]:
            return
        state["over"] = True
        GLib.source_remove(timer)
        cancel.cancel()
        done(rows)

    def timed_out():
        if not state["over"]:
            _stuck[key] = time.monotonic()
            state["over"] = True
            cancel.cancel()
            done(None)
        return False

    def got_layout(_bus, result):
        try:
            reply = bus.call_finish(result).unpack()
        except GLib.Error:
            finish(None)
            return
        _stuck.pop(key, None)
        finish(parse_layout(reply))

    def get_layout():
        bus.call(sender, path, INTERFACE, "GetLayout", GLib.Variant("(iias)", (0, -1, [])),
                 GLib.VariantType.new("(u(ia{sv}av))"), Gio.DBusCallFlags.NO_AUTO_START,
                 timeout_ms, cancel, got_layout)

    def shown(_bus, result):
        # Not every app has AboutToShow; the layout is asked for either way.
        try:
            bus.call_finish(result)
        except GLib.Error as e:
            if cancel.is_cancelled() or e.matches(Gio.io_error_quark(), Gio.IOErrorEnum.CANCELLED):
                return
        if not state["over"]:
            get_layout()

    timer = GLib.timeout_add(timeout_ms, timed_out)
    bus.call(sender, path, INTERFACE, "AboutToShow", GLib.Variant("(i)", (0,)),
             None, Gio.DBusCallFlags.NO_AUTO_START, timeout_ms, cancel, shown)


def click(bus, sender, path, ident, timestamp=0):
    """Tell the app its item was chosen, without waiting for its answer."""
    if bus is None:
        return
    bus.call(sender, path, INTERFACE, "Event",
             GLib.Variant("(isvu)", (int(ident), "clicked", GLib.Variant("i", 0), int(timestamp) & 0xFFFFFFFF)),
             None, Gio.DBusCallFlags.NO_AUTO_START, 2000, None, _ignore)


def _ignore(bus, result):
    try:
        bus.call_finish(result)
    except GLib.Error:
        pass


def add_rows(menu, rows, make_item, activate):
    """Put rows into a Gtk.Menu: make_item(label, mark, ticks) makes an item
    (ticks: whether this level has a tick column), activate(ident) runs when
    one is chosen. Submenus get menus of their own."""
    from gi.repository import Gtk   # the Dock's, already chosen at 3.0
    ticks = has_marks(rows)
    for row in rows:
        if row.get("separator"):
            menu.append(Gtk.SeparatorMenuItem())
            continue
        item = make_item(row["label"], row.get("mark", ""), ticks)
        if "children" in row:
            sub = Gtk.Menu()
            add_rows(sub, row["children"], make_item, activate)
            item.set_submenu(sub)
            item.set_sensitive(row["enabled"] and bool(row["children"]))
        else:
            item.set_sensitive(row["enabled"])
            item.connect("activate", lambda *_, ident=row["id"]: activate(ident))
        menu.append(item)
