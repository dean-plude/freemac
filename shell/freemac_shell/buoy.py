# SPDX-License-Identifier: GPL-3.0-or-later
"""Buoy: podcasts and news feeds.

Subscribe to a podcast or a website by its address (a site's own page works
too: Buoy finds the feed it points to). The sidebar lists All Items, Unread
and each feed with how many items are new; the middle lists the items; the
right shows the one picked, as a page with its scripts never run. Links open
in the web browser.

A podcast episode plays in the bar at the bottom, with 15 seconds back, 30
seconds ahead and a speed from 0.75x to 2x. Buoy keeps your place in every
episode, so it carries on where you stopped. Feeds are checked when Buoy
opens and every half hour while it runs. Subscription lists (OPML) can be
imported and exported. Original freemac code.
"""
import json
import os
import sys
import threading
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import Gdk, GLib, Gtk, Pango, WebKit2  # noqa: E402

from . import alert, menus, style  # noqa: E402
from . import buoy_feeds as feeds  # noqa: E402

try:
    gi.require_version("Gst", "1.0")
    from gi.repository import Gst
    Gst.init(None)
except (ImportError, ValueError):
    Gst = None

APP_ID = "org.freemac.Buoy"
HOME = os.path.join(GLib.get_user_data_dir(), "freemac", "buoy")
SAVE = os.path.join(HOME, "feeds.json")
EVERY = 30 * 60                   # seconds between checks
SPEEDS = [0.75, 1.0, 1.25, 1.5, 2.0]
SHOWN = 500                       # rows in All Items / Unread at most
ACCENT = "#1f8fbf"

CSS = b"""
.buoy-side { background: alpha(currentColor, 0.04); }
list.buoy-side { background: transparent; }
.buoy-side row { padding: 5px 10px; border-radius: 7px; margin: 0 6px; background: transparent; }
.buoy-side row:selected { background: alpha(@theme_fg_color, 0.12); }
.buoy-side row:selected label { color: @theme_fg_color; }
.buoy-side image { color: #1f8fbf; }
.buoy-head { font-size: 12px; font-weight: 700; color: alpha(currentColor, 0.5); padding: 12px 14px 2px 14px; }
.buoy-count { font-size: 12px; color: alpha(currentColor, 0.55); }
.buoy-count.new { color: #1f8fbf; font-weight: 700; }
.buoy-items row { padding: 8px 12px; border-bottom: 1px solid alpha(currentColor, 0.08); }
.buoy-dot { color: #1f8fbf; font-size: 10px; }
.buoy-title { font-weight: 600; }
.buoy-title.read { font-weight: 400; }
.buoy-meta { font-size: 12px; color: alpha(currentColor, 0.55); }
.buoy-snippet { font-size: 12px; color: alpha(currentColor, 0.7); }
.buoy-top { background: @theme_base_color; padding: 14px 20px 10px 20px; border-bottom: 1px solid alpha(currentColor, 0.08); }
.buoy-big { font-size: 20px; font-weight: 700; }
.buoy-player { padding: 6px 12px; border-top: 1px solid alpha(currentColor, 0.12);
               background: alpha(currentColor, 0.03); }
.buoy-playing { font-weight: 600; }
.buoy-empty-title { font-size: 20px; font-weight: 700; }
.buoy-empty-text { color: alpha(currentColor, 0.6); }
"""

PAGE = """<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src http: https: data:; style-src 'unsafe-inline'">
<style>
:root {{ color-scheme: light dark; }}
body {{ font: 15px/1.55 "Inter", "Cantarell", sans-serif; max-width: 680px; margin: 22px auto; padding: 0 22px;
       color: {fg}; background: {bg}; }}
img, video {{ max-width: 100%; height: auto; border-radius: 6px; }}
a {{ color: {link}; }}
pre, code {{ white-space: pre-wrap; font-size: 13px; }}
blockquote {{ margin: 0 0 0 12px; padding-left: 12px; border-left: 3px solid {rule}; color: {soft}; }}
.none {{ color: {soft}; }}
</style></head><body>{body}</body></html>"""


def when_text(stamp):
    if not stamp:
        return ""
    now = time.time()
    if now - stamp < 0:
        return time.strftime("%b %-d", time.localtime(stamp))
    if now - stamp < 3600:
        minutes = max(1, int((now - stamp) // 60))
        return f"{minutes} min ago"
    if time.localtime(stamp)[:3] == time.localtime(now)[:3]:
        return time.strftime("%-I:%M %p", time.localtime(stamp))
    if now - stamp < 6 * 86400:
        return time.strftime("%A", time.localtime(stamp))
    if time.localtime(stamp).tm_year == time.localtime(now).tm_year:
        return time.strftime("%b %-d", time.localtime(stamp))
    return time.strftime("%b %-d, %Y", time.localtime(stamp))


def clock(seconds):
    seconds = max(0, int(seconds))
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    return f"{hours}:{minutes:02d}:{secs:02d}" if hours else f"{minutes}:{secs:02d}"


def length_text(seconds):
    minutes = max(1, round(seconds / 60))
    if minutes < 60:
        return f"{minutes} min"
    return f"{minutes // 60} hr {minutes % 60} min" if minutes % 60 else f"{minutes // 60} hr"


# What Buoy keeps ---------------------------------------------------------------

class Library:
    """The feeds, their items, what has been read and where each episode
    was left, in one file."""

    def __init__(self):
        self.feeds = []
        self.speed = 1.0
        self.load()

    def load(self):
        try:
            with open(SAVE, encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            return
        if isinstance(data, dict):
            self.feeds = [f for f in data.get("feeds", []) if isinstance(f, dict) and f.get("url")]
            for feed in self.feeds:
                feed["items"] = [i for i in feed.get("items", []) if isinstance(i, dict) and i.get("id")]
            speed = data.get("speed", 1.0)
            self.speed = speed if speed in SPEEDS else 1.0

    def save(self):
        os.makedirs(HOME, exist_ok=True)
        temp = SAVE + ".tmp"
        with open(temp, "w", encoding="utf-8") as handle:
            json.dump({"feeds": self.feeds, "speed": self.speed}, handle)
        os.replace(temp, SAVE)

    def feed(self, url):
        return next((f for f in self.feeds if f["url"] == url), None)

    def add(self, url, info, items):
        """A new feed (or the same one again). Its items start read except the
        newest few, so a new subscription isn't a wall of unread."""
        feed = self.feed(url)
        if feed is None:
            feed = {"url": url, "items": []}
            self.feeds.append(feed)
            for n, item in enumerate(items):
                item["read"] = n >= 3
        self.merge(feed, info, items)
        return feed

    def merge(self, feed, info, items):
        old = {i["id"]: i for i in feed.get("items", [])}
        merged = []
        for item in items:
            before = old.pop(item["id"], None)
            if before is not None:
                # The same dict stays, so what's playing and what's on screen still point at it.
                before.update({k: v for k, v in item.items() if k not in ("read", "place", "played")})
                item = before
            item.setdefault("read", False)
            merged.append(item)
        # Items the feed no longer lists stay a while: a feed often shows only its last ten.
        merged.extend(old.values())
        merged.sort(key=lambda i: i.get("date", 0), reverse=True)
        feed["items"] = merged[:feeds.KEEP]
        for key in ("title", "site", "about", "image", "podcast"):
            if key in info:
                feed[key] = info[key]
        feed["checked"] = int(time.time())
        feed.pop("error", None)

    def remove(self, url):
        self.feeds = [f for f in self.feeds if f["url"] != url]

    def items(self, which):
        """(feed, item) pairs for a sidebar choice: 'all', 'unread' or a feed's address."""
        if which in ("all", "unread"):
            found = [(f, i) for f in self.feeds for i in f["items"] if which == "all" or not i.get("read")]
            found.sort(key=lambda p: p[1].get("date", 0), reverse=True)
            return found[:SHOWN]
        feed = self.feed(which)
        return [(feed, i) for i in feed["items"]] if feed else []

    def unread(self, feed=None):
        chosen = [feed] if feed else self.feeds
        return sum(1 for f in chosen for i in f["items"] if not i.get("read"))


# Playing episodes --------------------------------------------------------------

class Player:
    """One episode at a time in GStreamer's playbin, at a chosen speed."""

    def __init__(self, on_change):
        self.on_change = on_change
        self.item = None
        self.feed = None
        self.playing = False
        self.speed = 1.0
        self.start_at = 0
        self.ready = False
        self.error = ""
        self.bin = Gst.ElementFactory.make("playbin", "buoy") if Gst else None
        if self.bin is not None:
            fake = Gst.ElementFactory.make("fakesink", None)
            if fake is not None:
                self.bin.set_property("video-sink", fake)
            tempo = Gst.ElementFactory.make("scaletempo", None)
            if tempo is not None:
                self.bin.set_property("audio-filter", tempo)   # faster without the chipmunk voice
            bus = self.bin.get_bus()
            bus.add_signal_watch()
            bus.connect("message", self._message)

    def load(self, feed, item, play=True):
        if self.bin is None:
            self.error = "Playing needs GStreamer, which isn't installed."
            self.on_change()
            return
        self.bin.set_state(Gst.State.NULL)
        self.feed, self.item = feed, item
        self.start_at = item.get("place", 0) if not item.get("played") else 0
        self.ready = False
        self.error = ""
        self.bin.set_property("uri", item["audio"])
        self.bin.set_state(Gst.State.PLAYING if play else Gst.State.PAUSED)
        self.playing = play
        self.on_change()

    def toggle(self):
        if self.bin is None or self.item is None:
            return
        if self.playing:
            self.remember()
            self.bin.set_state(Gst.State.PAUSED)
        else:
            if self.bin.get_state(0)[1] in (Gst.State.NULL, Gst.State.READY):
                self.start_at = self.item.get("place", 0)
            self.bin.set_state(Gst.State.PLAYING)
        self.playing = not self.playing
        self.on_change()

    def position(self):
        if self.bin is None or self.item is None:
            return 0
        if not self.ready:
            return self.start_at
        ok, pos = self.bin.query_position(Gst.Format.TIME)
        return pos / Gst.SECOND if ok and pos >= 0 else self.item.get("place", 0)

    def duration(self):
        """The episode's length: GStreamer's figure when it has a believable
        one (it can be wrong for a stream it hasn't read to the end), or the
        feed's."""
        listed = self.item.get("duration", 0) if self.item else 0
        if self.bin is not None and self.ready:
            ok, length = self.bin.query_duration(Gst.Format.TIME)
            if ok and length > 0:
                length = length / Gst.SECOND
                if length >= self.position() and (not listed or length > listed * 0.5):
                    return length
        return listed

    def seek(self, seconds):
        if self.bin is None or self.item is None:
            return
        length = self.duration()
        seconds = max(0, min(seconds, length - 1 if length > 1 else seconds))
        if not self.ready:
            self.start_at = seconds
        else:
            self._seek_to(seconds)
        self.item["place"] = seconds
        self.on_change()

    def skip(self, by):
        self.seek(self.position() + by)

    def set_speed(self, speed):
        self.speed = speed
        if self.ready:
            self._seek_to(self.position())
        self.on_change()

    def _seek_to(self, seconds):
        self.bin.seek(self.speed, Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.ACCURATE,
                      Gst.SeekType.SET, int(seconds * Gst.SECOND), Gst.SeekType.NONE, -1)

    def remember(self):
        """Note where the episode is, so it carries on there."""
        if self.item is not None and self.ready:
            place = self.position()
            length = self.duration()
            if length and place > length - min(15, length * 0.05) and place <= length + 1:
                self.item["played"], self.item["place"] = True, 0
            elif place > 5:
                self.item["place"] = int(place)
                self.item.pop("played", None)

    def stop(self):
        self.remember()
        if self.bin is not None:
            self.bin.set_state(Gst.State.NULL)
        self.playing = False

    def _message(self, _bus, message):
        kind = message.type
        if kind == Gst.MessageType.ASYNC_DONE and not self.ready:
            self.ready = True
            if self.start_at or self.speed != 1.0:
                self._seek_to(self.start_at)
            self.start_at = 0
            self.on_change()
        elif kind == Gst.MessageType.EOS:
            if self.item is not None:
                self.item["played"], self.item["place"] = True, 0
            self.bin.set_state(Gst.State.NULL)
            self.ready = self.playing = False
            self.on_change(finished=True)
        elif kind == Gst.MessageType.ERROR:
            error, _debug = message.parse_error()
            print(f"buoy: couldn't play {self.item and self.item.get('audio')}: {error.message}", file=sys.stderr)
            self.bin.set_state(Gst.State.NULL)
            self.ready = self.playing = False
            self.error = "This episode couldn't be played. Check your connection."
            self.on_change()


# The window ----------------------------------------------------------------------

class SideRow(Gtk.ListBoxRow):
    def __init__(self, key, label, icon):
        super().__init__()
        self.key = key
        box = Gtk.Box(spacing=8)
        box.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU), False, False, 0)
        self.label = Gtk.Label(label=label, xalign=0, ellipsize=Pango.EllipsizeMode.END)
        box.pack_start(self.label, True, True, 0)
        self.count = Gtk.Label(xalign=1)
        self.count.get_style_context().add_class("buoy-count")
        box.pack_end(self.count, False, False, 0)
        self.add(box)

    def set_count(self, n, new=True):
        self.count.set_text(str(n) if n else "")
        context = self.count.get_style_context()
        (context.add_class if new and n else context.remove_class)("new")


class ItemRow(Gtk.ListBoxRow):
    def __init__(self, feed, item, show_feed):
        super().__init__()
        self.feed, self.item = feed, item
        grid = Gtk.Grid(column_spacing=8, row_spacing=2)
        self.dot = Gtk.Label(label="●", valign=Gtk.Align.START, margin_top=3)
        self.dot.get_style_context().add_class("buoy-dot")
        grid.attach(self.dot, 0, 0, 1, 1)
        self.title = Gtk.Label(label=item.get("title") or "Untitled", xalign=0, wrap=True, lines=2,
                               ellipsize=Pango.EllipsizeMode.END, max_width_chars=40)
        self.title.get_style_context().add_class("buoy-title")
        grid.attach(self.title, 1, 0, 1, 1)
        bits = [feed.get("title", "")] if show_feed else []
        if item.get("date"):
            bits.append(when_text(item["date"]))
        if item.get("audio"):
            bits.append(self.audio_text())
        meta = Gtk.Label(label=" · ".join(b for b in bits if b), xalign=0, ellipsize=Pango.EllipsizeMode.END)
        meta.get_style_context().add_class("buoy-meta")
        self.meta = meta
        grid.attach(meta, 1, 1, 1, 1)
        snippet = feeds.plain(item.get("summary"), 140)
        if snippet:
            label = Gtk.Label(label=snippet, xalign=0, wrap=True, lines=2, ellipsize=Pango.EllipsizeMode.END,
                              max_width_chars=40)
            label.get_style_context().add_class("buoy-snippet")
            grid.attach(label, 1, 2, 1, 1)
        self.add(grid)
        self.show_all()
        self.mark()

    def audio_text(self):
        item = self.item
        if item.get("played"):
            return "Played"
        if item.get("place") and item.get("duration"):
            return f"{length_text(max(60, item['duration'] - item['place']))} left"
        if item.get("place"):
            return f"from {clock(item['place'])}"
        return length_text(item["duration"]) if item.get("duration") else "Episode"

    def mark(self):
        read = bool(self.item.get("read"))
        self.dot.set_opacity(0 if read else 1)
        context = self.title.get_style_context()
        (context.add_class if read else context.remove_class)("read")


class BuoyWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Buoy")
        self.app = app
        self.library = app.library
        self.set_default_size(1180, 760)
        self.which = "all"
        self.current = None          # (feed, item) on the right
        self.checking = 0

        header = Gtk.HeaderBar(show_close_button=True, title="Buoy")
        add = Gtk.Button.new_from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON)
        add.set_tooltip_text("Add a feed")
        add.set_action_name("win.add")
        header.pack_start(add)
        self.refresh_button = Gtk.Button.new_from_icon_name("view-refresh-symbolic", Gtk.IconSize.BUTTON)
        self.refresh_button.set_tooltip_text("Check for new items")
        self.refresh_button.set_action_name("win.refresh")
        header.pack_start(self.refresh_button)
        self.spinner = Gtk.Spinner()
        header.pack_start(self.spinner)
        self.set_titlebar(header)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=120)
        outer.pack_start(self.stack, True, True, 0)
        self.stack.add_named(self._empty_page(), "empty")

        paned = Gtk.Paned()
        side_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        side_scroll.get_style_context().add_class("buoy-side")
        side_scroll.set_size_request(210, -1)
        self.sidebar = Gtk.ListBox()
        self.sidebar.get_style_context().add_class("buoy-side")
        self.sidebar.set_header_func(self._side_header)
        self.sidebar.connect("row-selected", self._side_selected)
        self.sidebar.connect("button-press-event", self._side_press)
        side_scroll.add(self.sidebar)
        paned.pack1(side_scroll, False, False)

        inner = Gtk.Paned()
        list_scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        list_scroll.set_size_request(330, -1)
        self.list = Gtk.ListBox()
        self.list.get_style_context().add_class("buoy-items")
        self.list.connect("row-selected", self._item_selected)
        self.list.connect("button-press-event", self._item_press)
        self.list.set_placeholder(self._placeholder())
        list_scroll.add(self.list)
        inner.pack1(list_scroll, False, False)
        inner.pack2(self._detail(), True, False)
        paned.pack2(inner, True, False)
        self.stack.add_named(paned, "feeds")

        outer.pack_end(self._player_bar(), False, False, 0)
        self.add(outer)

        menus.add_actions(self, {
            "close": self.close, "add": self.ask_add, "refresh": self.refresh_all,
            "import": self.import_opml, "export": self.export_opml, "remove": self.ask_remove,
            "mark-all": self.mark_all_read, "toggle-read": self.toggle_read, "open-link": self.open_link,
            "website": self.open_website, "play-pause": self.play_pause, "back": lambda: self.app.player.skip(-15),
            "ahead": lambda: self.app.player.skip(30), "play-item": self.play_current,
        })
        self.connect("key-press-event", self._key)
        self.connect("delete-event", self._closing)
        self.show_all()
        self.player_bar.set_visible(False)
        self.error_bar.set_visible(False)
        self.rebuild_sidebar()
        GLib.timeout_add(1000, self._tick)

    # Building -----------------------------------------------------------------

    def _empty_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, halign=Gtk.Align.CENTER,
                      valign=Gtk.Align.CENTER)
        image = Gtk.Image.new_from_icon_name("freemac-buoy", Gtk.IconSize.DIALOG)
        image.set_pixel_size(96)
        box.pack_start(image, False, False, 0)
        title = Gtk.Label(label="Follow podcasts and websites")
        title.get_style_context().add_class("buoy-empty-title")
        box.pack_start(title, False, False, 0)
        text = Gtk.Label(label="Add a podcast's feed, or the address of a website you read,\n"
                               "and new episodes and posts show up here.", justify=Gtk.Justification.CENTER)
        text.get_style_context().add_class("buoy-empty-text")
        box.pack_start(text, False, False, 0)
        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER, margin_top=8)
        add = Gtk.Button(label="Add a Feed…")
        add.get_style_context().add_class("suggested-action")
        add.set_action_name("win.add")
        buttons.pack_start(add, False, False, 0)
        opml = Gtk.Button(label="Import Subscriptions…")
        opml.set_action_name("win.import")
        buttons.pack_start(opml, False, False, 0)
        box.pack_start(buttons, False, False, 0)
        return box

    def _placeholder(self):
        self.placeholder = Gtk.Label(label="Nothing here yet", margin=30)
        self.placeholder.get_style_context().add_class("buoy-empty-text")
        self.placeholder.show()
        return self.placeholder

    def _detail(self):
        top = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        top.get_style_context().add_class("buoy-top")
        self.detail_title = Gtk.Label(xalign=0, wrap=True, selectable=True, can_focus=False)
        self.detail_title.get_style_context().add_class("buoy-big")
        top.pack_start(self.detail_title, False, False, 0)
        self.detail_meta = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.detail_meta.get_style_context().add_class("buoy-meta")
        top.pack_start(self.detail_meta, False, False, 0)
        actions = Gtk.Box(spacing=8, margin_top=6)
        self.play_button = Gtk.Button()
        self.play_button.get_style_context().add_class("suggested-action")
        self.play_button.set_action_name("win.play-item")
        actions.pack_start(self.play_button, False, False, 0)
        self.link_button = Gtk.Button(label="Open in Browser")
        self.link_button.set_action_name("win.open-link")
        actions.pack_start(self.link_button, False, False, 0)
        top.pack_start(actions, False, False, 0)

        self.web_context = WebKit2.WebContext.new_ephemeral()    # kept: the view doesn't hold on to it
        self.view = WebKit2.WebView(web_context=self.web_context)
        settings = self.view.get_settings()
        settings.set_enable_javascript(False)          # a feed's scripts never run
        settings.set_enable_javascript_markup(False)
        settings.set_enable_developer_extras(False)
        settings.set_hardware_acceleration_policy(WebKit2.HardwareAccelerationPolicy.NEVER)
        settings.set_auto_load_images(True)
        self.view.connect("decide-policy", self._policy)
        self.view.connect("context-menu", lambda *_a: True)
        self.detail_stack = Gtk.Stack()
        none = Gtk.Label(label="Choose an item to read it here.")
        none.get_style_context().add_class("buoy-empty-text")
        self.detail_stack.add_named(none, "none")
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        page.pack_start(top, False, False, 0)
        page.pack_start(self.view, True, True, 0)
        self.detail_stack.add_named(page, "item")
        return self.detail_stack

    def _player_bar(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.error_bar = Gtk.Label(xalign=0, margin_start=14, margin_top=4)
        self.error_bar.get_style_context().add_class("buoy-meta")
        outer.pack_start(self.error_bar, False, False, 0)
        bar = Gtk.Box(spacing=8)
        bar.get_style_context().add_class("buoy-player")
        back = Gtk.Button(label="↺ 15")
        back.set_tooltip_text("Back 15 seconds")
        back.set_action_name("win.back")
        bar.pack_start(back, False, False, 0)
        self.toggle_button = Gtk.Button.new_from_icon_name("media-playback-start-symbolic", Gtk.IconSize.BUTTON)
        self.toggle_button.set_tooltip_text("Play or pause")
        self.toggle_button.set_action_name("win.play-pause")
        bar.pack_start(self.toggle_button, False, False, 0)
        ahead = Gtk.Button(label="30 ↻")
        ahead.set_tooltip_text("Ahead 30 seconds")
        ahead.set_action_name("win.ahead")
        bar.pack_start(ahead, False, False, 0)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER, margin_start=6)
        self.now_title = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END, max_width_chars=34)
        self.now_title.get_style_context().add_class("buoy-playing")
        words.pack_start(self.now_title, False, False, 0)
        self.now_feed = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END, max_width_chars=34)
        self.now_feed.get_style_context().add_class("buoy-meta")
        words.pack_start(self.now_feed, False, False, 0)
        bar.pack_start(words, False, False, 0)
        self.elapsed = Gtk.Label(label="0:00", width_chars=7, xalign=1)
        self.elapsed.get_style_context().add_class("buoy-meta")
        bar.pack_start(self.elapsed, False, False, 0)
        self.scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 1, 1)
        self.scale.set_draw_value(False)
        self.scale.connect("change-value", self._scrubbed)
        bar.pack_start(self.scale, True, True, 0)
        self.remaining = Gtk.Label(label="", width_chars=8, xalign=0)
        self.remaining.get_style_context().add_class("buoy-meta")
        bar.pack_start(self.remaining, False, False, 0)
        self.speed = Gtk.Button(label=f"{self.library.speed:g}×")
        self.speed.set_tooltip_text("Playback speed: click to change")
        self.speed.set_size_request(64, -1)
        self.speed.connect("clicked", self._speed_clicked)
        bar.pack_end(self.speed, False, False, 0)
        outer.pack_start(bar, False, False, 0)
        self.player_bar = bar
        return outer

    # The sidebar -----------------------------------------------------------------

    def rebuild_sidebar(self):
        keep = self.which
        for row in self.sidebar.get_children():
            self.sidebar.remove(row)
        self.side_rows = {}
        for key, label, icon in (("all", "All Items", "view-list-symbolic"),
                                 ("unread", "Unread", "mail-unread-symbolic")):
            self._side_add(SideRow(key, label, icon))
        for feed in sorted(self.library.feeds, key=lambda f: f.get("title", "").lower()):
            icon = "audio-x-generic-symbolic" if feed.get("podcast") else "text-x-generic-symbolic"
            row = SideRow(feed["url"], feed.get("title") or feed["url"], icon)
            if feed.get("error"):
                row.set_tooltip_text(feed["error"])
                row.label.set_opacity(0.55)
            self._side_add(row)
        self.sidebar.show_all()
        self.stack.set_visible_child_name("feeds" if self.library.feeds else "empty")
        self.counts()
        self.which = keep if keep in self.side_rows else "all"
        self.sidebar.select_row(self.side_rows[self.which])

    def _side_add(self, row):
        self.sidebar.add(row)
        self.side_rows[row.key] = row

    def _side_header(self, row, before):
        if row.key not in ("all", "unread") and (before is None or before.key in ("all", "unread")):
            head = Gtk.Label(label="Subscriptions", xalign=0)
            head.get_style_context().add_class("buoy-head")
            row.set_header(head)
        else:
            row.set_header(None)

    def counts(self):
        for key, row in self.side_rows.items():
            if key == "all":
                row.set_count(0)
            elif key == "unread":
                row.set_count(self.library.unread())
            else:
                row.set_count(self.library.unread(self.library.feed(key)))
        unread = self.library.unread()
        self.set_title(f"Buoy ({unread})" if unread else "Buoy")
        if self.get_titlebar():
            self.get_titlebar().set_title("Buoy")
            self.get_titlebar().set_subtitle(f"{unread} unread" if unread else None)

    def _side_selected(self, _box, row):
        if row is None:
            return
        self.which = row.key
        self.fill_list(keep=self.current[1] if self.current else None)

    def _side_press(self, _box, event):
        if event.type != Gdk.EventType.BUTTON_PRESS or event.button != 3:
            return False
        row = self.sidebar.get_row_at_y(int(event.y))
        if row is None or row.key in ("all", "unread"):
            return False
        self.sidebar.select_row(row)
        menu = Gtk.Menu()
        for label, action in (("Mark All as Read", self.mark_all_read), ("Open Website", self.open_website),
                              ("Copy Feed Address", lambda: self._copy(row.key)), (None, None),
                              ("Unsubscribe…", self.ask_remove)):
            if label is None:
                menu.append(Gtk.SeparatorMenuItem())
                continue
            entry = Gtk.MenuItem(label=label)
            entry.connect("activate", lambda _m, a=action: a())
            menu.append(entry)
        menu.show_all()
        menu.attach_to_widget(self.sidebar, None)
        menu.popup_at_pointer(event)
        return True

    # The list ------------------------------------------------------------------------

    def fill_list(self, keep=None):
        for row in self.list.get_children():
            self.list.remove(row)
        pairs = self.library.items(self.which)
        self.placeholder.set_text("No unread items" if self.which == "unread" else "Nothing here yet")
        chosen = None
        for feed, item in pairs:
            row = ItemRow(feed, item, self.which in ("all", "unread"))
            self.list.add(row)
            if keep is not None and item is keep:
                chosen = row
        if chosen is not None:
            self.list.select_row(chosen)
        else:
            self.show_item(None)

    def _item_selected(self, _box, row):
        if row is None:
            return
        self.show_item((row.feed, row.item))
        if not row.item.get("read"):
            row.item["read"] = True
            row.mark()
            self.counts()
            self.app.save_soon()

    def _item_press(self, _box, event):
        if event.type != Gdk.EventType.BUTTON_PRESS or event.button != 3:
            return False
        row = self.list.get_row_at_y(int(event.y))
        if row is None:
            return False
        menu = Gtk.Menu()
        read = row.item.get("read")
        choices = [("Mark as Unread" if read else "Mark as Read", lambda: self._set_read(row, not read))]
        if row.item.get("audio"):
            choices.append(("Play Episode", lambda: self.play(row.feed, row.item)))
        if row.item.get("link"):
            choices.append(("Open in Browser", lambda: self._open(row.item["link"])))
            choices.append(("Copy Link", lambda: self._copy(row.item["link"])))
        for label, action in choices:
            entry = Gtk.MenuItem(label=label)
            entry.connect("activate", lambda _m, a=action: a())
            menu.append(entry)
        menu.show_all()
        menu.attach_to_widget(self.list, None)
        menu.popup_at_pointer(event)
        return True

    def _set_read(self, row, read):
        row.item["read"] = read
        row.mark()
        self.counts()
        self.app.save_soon()

    # The item ------------------------------------------------------------------------

    def show_item(self, pair):
        same = pair is not None and self.current is not None and self.current[1] is pair[1] \
            and self.detail_stack.get_visible_child_name() == "item"
        self.current = pair
        if same:
            self.update_play_button()
            return
        if pair is None:
            self.detail_stack.set_visible_child_name("none")
            return
        feed, item = pair
        self.detail_stack.set_visible_child_name("item")
        self.detail_title.set_text(item.get("title") or "Untitled")
        bits = [feed.get("title", ""), when_text(item.get("date"))]
        if item.get("duration"):
            bits.append(length_text(item["duration"]))
        self.detail_meta.set_text(" · ".join(b for b in bits if b))
        self.play_button.set_visible(bool(item.get("audio")))
        self.update_play_button()
        self.link_button.set_visible(bool(item.get("link")))
        dark = style.is_dark()
        colours = ({"fg": "#e8e8ea", "bg": "#1e1e20", "link": "#5cb8e6", "rule": "#555", "soft": "#a0a0a5"} if dark
                   else {"fg": "#1d1d1f", "bg": "#ffffff", "link": ACCENT, "rule": "#ccc", "soft": "#6e6e73"})
        body = feeds.clean_html(item.get("summary"), item.get("link") or feed.get("site") or feed["url"])
        if not body.strip():
            body = '<p class="none">This item has no text. Open it in the browser to read it.</p>'
        self.view.load_html(PAGE.format(body=body, **colours), None)

    def update_play_button(self):
        if not self.current:
            return
        _feed, item = self.current
        player = self.app.player
        if player.item is item and player.playing:
            self.play_button.set_label("Pause")
        elif item.get("place") and not item.get("played"):
            self.play_button.set_label(f"Resume from {clock(item['place'])}")
        else:
            self.play_button.set_label("Play Episode")

    def _policy(self, _view, decision, kind):
        if kind not in (WebKit2.PolicyDecisionType.NAVIGATION_ACTION, WebKit2.PolicyDecisionType.NEW_WINDOW_ACTION):
            return False
        action = decision.get_navigation_action()
        uri = action.get_request().get_uri() or ""
        if uri in ("about:blank", "") or uri.startswith("about:blank#"):
            decision.use()
            return True
        decision.ignore()
        if uri.startswith(("http:", "https:")) and action.get_navigation_type() == WebKit2.NavigationType.LINK_CLICKED:
            self._open(uri)
        return True

    def _open(self, uri):
        if uri.startswith(("http:", "https:")):
            Gtk.show_uri_on_window(self, uri, Gdk.CURRENT_TIME)

    def _copy(self, text):
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)

    def open_link(self):
        if self.current and self.current[1].get("link"):
            self._open(self.current[1]["link"])

    def open_website(self):
        feed = self.library.feed(self.which)
        if feed is None and self.current:
            feed = self.current[0]
        if feed is not None:
            self._open(feed.get("site") or feed["url"])

    def toggle_read(self):
        row = self.list.get_selected_row()
        if row is not None:
            self._set_read(row, not row.item.get("read"))

    def mark_all_read(self):
        feed = self.library.feed(self.which)
        for _feed, item in ([(feed, i) for i in feed["items"]] if feed else self.library.items("all")):
            item["read"] = True
        for row in self.list.get_children():
            row.mark()
        self.counts()
        self.app.save_soon()

    # Playing ----------------------------------------------------------------------

    def play_current(self):
        if self.current and self.current[1].get("audio"):
            feed, item = self.current
            if self.app.player.item is item:
                self.app.player.toggle()
            else:
                self.play(feed, item)

    def play(self, feed, item):
        player = self.app.player
        player.stop()
        player.speed = self.library.speed
        player.load(feed, item)
        self.app.save_soon()

    def play_pause(self):
        player = self.app.player
        if player.item is None:
            self.play_current()
        else:
            player.toggle()
            self.app.save_soon()

    def player_changed(self, finished=False):
        player = self.app.player
        self.player_bar.set_visible(player.item is not None)
        self.error_bar.set_visible(bool(player.error))
        self.error_bar.set_text(player.error)
        if player.item is not None:
            self.now_title.set_text(player.item.get("title") or "Episode")
            self.now_feed.set_text(player.feed.get("title", "") if player.feed else "")
            icon = "media-playback-pause-symbolic" if player.playing else "media-playback-start-symbolic"
            self.toggle_button.set_image(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON))
        self.update_play_button()
        self._tick(once=True)
        if finished:
            for row in self.list.get_children():
                if row.item is player.item:
                    row.meta.set_text(row.meta.get_text().rsplit(" · ", 1)[0] + " · Played")
            self.app.save_soon()

    def _tick(self, once=False):
        player = self.app.player
        if player.item is not None:
            place, length = player.position(), player.duration()
            self.elapsed.set_text(clock(place))
            self.remaining.set_text(f"-{clock(length - place)}" if length else "")
            self.scale.set_range(0, max(1, length))
            self.scale.set_value(place)
        return True if not once else False

    def _scrubbed(self, _scale, _scroll, value):
        self.app.player.seek(value)
        return False

    def _speed_clicked(self, button):
        at = SPEEDS.index(self.library.speed) if self.library.speed in SPEEDS else 1
        value = SPEEDS[(at + 1) % len(SPEEDS)]
        button.set_label(f"{value:g}×")
        self.library.speed = value
        self.app.player.set_speed(value)
        self.app.save_soon()

    def _key(self, _window, event):
        if event.keyval == Gdk.KEY_space and not event.state & Gdk.ModifierType.CONTROL_MASK \
                and not self.view.has_focus() and self.app.player.item is not None:
            self.play_pause()
            return True
        return False

    # Adding and checking feeds -----------------------------------------------------

    def ask_add(self, initial=""):
        buttons = [("Cancel", Gtk.ResponseType.CANCEL), ("Subscribe", Gtk.ResponseType.OK)]
        dialog = alert.build(self, "Add a Feed",
                             "Type the address of a podcast's feed or of a website you read.", buttons,
                             default=Gtk.ResponseType.OK)
        body = dialog.get_content_area().get_children()[0]
        entry = Gtk.Entry(text=initial if isinstance(initial, str) else "", activates_default=True, width_chars=30,
                          placeholder_text="example.com/feed")
        body.pack_start(entry, False, False, 0)
        body.reorder_child(entry, len(body.get_children()) - 2)
        entry.show()
        entry.grab_focus()
        answer = dialog.run()
        text = entry.get_text().strip()
        dialog.destroy()
        if answer == Gtk.ResponseType.OK and text:
            self.subscribe(text)

    def subscribe(self, text):
        self.busy(1)

        def work():
            try:
                url, info, items = feeds.find_feed(text)
                GLib.idle_add(self._subscribed, url, info, items, None)
            except feeds.FeedError as err:
                GLib.idle_add(self._subscribed, None, None, None, str(err))
        threading.Thread(target=work, daemon=True).start()

    def _subscribed(self, url, info, items, error):
        self.busy(-1)
        if error:
            alert.tell(self, "Buoy couldn't add that feed", error)
            return False
        known = self.library.feed(url) is not None
        self.library.add(url, info, items)
        self.app.save_soon()
        self.which = url
        self.rebuild_sidebar()
        if known:
            alert.tell(self, f"You already follow {info['title']}", "It's been checked for new items.")
        return False

    def refresh_all(self):
        if self.checking:
            return
        targets = [(f["url"], f.get("title") or f["url"]) for f in self.library.feeds]
        if not targets:
            return
        self.busy(1)

        def work():
            results = []
            for url, _title in targets:
                try:
                    data, _kind, final = feeds.fetch(url)
                    info, items = feeds.parse(data, final)
                    results.append((url, info, items, None))
                except feeds.FeedError as err:
                    results.append((url, None, None, str(err)))
            GLib.idle_add(self._refreshed, results)
        threading.Thread(target=work, daemon=True).start()

    def _refreshed(self, results):
        self.busy(-1)
        for url, info, items, error in results:
            feed = self.library.feed(url)
            if feed is None:
                continue
            if error:
                feed["error"] = error
            else:
                self.library.merge(feed, info, items)
        self.app.save_soon()
        self.rebuild_sidebar()          # keeps the item on screen selected (it's the same dict)
        return False

    def busy(self, change):
        self.checking = max(0, self.checking + change)
        if self.checking:
            self.spinner.start()
            self.spinner.show()
        else:
            self.spinner.stop()
        self.refresh_button.set_sensitive(not self.checking)

    def ask_remove(self):
        feed = self.library.feed(self.which)
        if feed is None:
            return
        answer = alert.ask(self, f"Unsubscribe from {feed.get('title') or 'this feed'}?",
                           "Its items and your places in its episodes are removed from Buoy.",
                           [("Cancel", Gtk.ResponseType.CANCEL), ("Unsubscribe", Gtk.ResponseType.OK)],
                           default=Gtk.ResponseType.OK, destructive=Gtk.ResponseType.OK)
        if answer != Gtk.ResponseType.OK:
            return
        if self.app.player.feed is feed:
            self.app.player.stop()
            self.app.player.item = self.app.player.feed = None
            self.player_changed()
        self.library.remove(feed["url"])
        self.app.save_soon()
        self.which = "all"
        self.rebuild_sidebar()

    def import_opml(self):
        chooser = Gtk.FileChooserNative.new("Import Subscriptions", self, Gtk.FileChooserAction.OPEN, "Import",
                                            "Cancel")
        kinds = Gtk.FileFilter()
        kinds.set_name("Subscription lists (OPML)")
        for pattern in ("*.opml", "*.xml", "*.OPML"):
            kinds.add_pattern(pattern)
        chooser.add_filter(kinds)
        if chooser.run() != Gtk.ResponseType.ACCEPT:
            return
        path = chooser.get_filename()
        try:
            with open(path, "rb") as handle:
                found = feeds.read_opml(handle.read(feeds.LIMIT))
        except (OSError, feeds.FeedError) as err:
            alert.tell(self, "Buoy couldn't read that file", str(err) if isinstance(err, feeds.FeedError)
                       else "The file couldn't be opened.")
            return
        new = [(t, u) for t, u in found if self.library.feed(u) is None]
        if not new:
            alert.tell(self, "Nothing new to add", "You already follow every feed in that list."
                       if found else "That list has no feeds in it.")
            return
        for title, url in new:
            feed = {"url": url, "title": title, "items": []}
            self.library.feeds.append(feed)
        self.app.save_soon()
        self.rebuild_sidebar()
        self.refresh_all()

    def export_opml(self):
        chooser = Gtk.FileChooserNative.new("Export Subscriptions", self, Gtk.FileChooserAction.SAVE, "Export",
                                            "Cancel")
        chooser.set_current_name("Buoy Subscriptions.opml")
        chooser.set_do_overwrite_confirmation(True)
        if chooser.run() != Gtk.ResponseType.ACCEPT:
            return
        try:
            with open(chooser.get_filename(), "wb") as handle:
                handle.write(feeds.write_opml(self.library.feeds))
        except OSError:
            alert.tell(self, "Buoy couldn't save that file", "Check that the folder can be written to.")

    def _closing(self, *_args):
        self.app.player.remember()
        self.app.save_now()
        return False

    def about(self):
        alert.tell(self, "About Buoy", "Buoy follows podcasts and news feeds. It is part of freemac.",
                   icon="freemac-buoy")


def menubar():
    return menus.menubar([
        ("_File", [[("New Subscription…", "win.add", "<Ctrl>n"), ("Import Subscriptions…", "win.import", None),
                    ("Export Subscriptions…", "win.export", None)],
                   [("Close", "win.close", "<Ctrl>w")]]),
        ("_Feed", [[("Check for New Items", "win.refresh", "<Ctrl>r")],
                   [("Mark as Read or Unread", "win.toggle-read", "<Shift><Ctrl>u"),
                    ("Mark All as Read", "win.mark-all", "<Shift><Ctrl>a")],
                   [("Open in Browser", "win.open-link", "<Ctrl>Return"), ("Open Website", "win.website", None)],
                   [("Unsubscribe…", "win.remove", None)]]),
        ("_Controls", [[("Play or Pause", "win.play-pause", None), ("Play Selected Episode", "win.play-item",
                                                                    "<Ctrl>p")],
                       [("Back 15 Seconds", "win.back", "<Ctrl>Left"), ("Ahead 30 Seconds", "win.ahead",
                                                                        "<Ctrl>Right")]]),
    ])


class Buoy(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None
        self.library = Library()
        self.player = Player(self._player_changed)
        self.player.speed = self.library.speed
        self.pending = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        menus.add_actions(self, {"quit": self.quit, "about": lambda: self.window and self.window.about()})
        for action, keys in (("app.quit", ["<Control>q"]), ("win.close", ["<Control>w"]), ("win.add", ["<Control>n"]),
                             ("win.refresh", ["<Control>r"]), ("win.toggle-read", ["<Shift><Control>u"]),
                             ("win.mark-all", ["<Shift><Control>a"]), ("win.open-link", ["<Control>Return"]),
                             ("win.play-item", ["<Control>p"]), ("win.back", ["<Control>Left"]),
                             ("win.ahead", ["<Control>Right"])):
            self.set_accels_for_action(action, keys)
        self.set_menubar(menubar())
        GLib.timeout_add_seconds(EVERY, self._check)
        GLib.timeout_add_seconds(10, self._remember)

    def do_activate(self):
        if self.window is None:
            self.window = BuoyWindow(self)
            if self.library.feeds:
                GLib.timeout_add(600, lambda: self.window.refresh_all() and False)
        self.window.present()

    def do_shutdown(self):
        self.player.stop()
        self.save_now()
        Gtk.Application.do_shutdown(self)

    def _player_changed(self, finished=False):
        if self.window is not None:
            self.window.player_changed(finished)

    def _check(self):
        if self.window is not None:
            self.window.refresh_all()
        return True

    def _remember(self):
        if self.player.playing:
            self.player.remember()
            self.save_soon()
        return True

    def save_soon(self):
        if self.pending is None:
            self.pending = GLib.timeout_add(800, self._save_due)

    def _save_due(self):
        self.pending = None
        self.save_now()
        return False

    def save_now(self):
        if self.pending is not None:
            GLib.source_remove(self.pending)
            self.pending = None
        try:
            self.library.save()
        except OSError as err:
            print(f"buoy: couldn't save: {err}", file=sys.stderr)
        return False


def main():
    GLib.set_prgname("freemac-buoy")
    return Buoy().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
