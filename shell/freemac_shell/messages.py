# SPDX-License-Identifier: GPL-3.0-or-later
"""Messages: conversations in bubbles, from two places.

* iMessage through BlueBubbles (messages_bluebubbles.py): for people with a
  Mac of their own running BlueBubbles Server, which is signed in to their
  Apple account. freemac only talks to that server; it doesn't speak to
  Apple and pretends to be no Apple device.
* Texts through an Android phone over KDE Connect (messages_kdeconnect.py):
  the phone's own SMS and MMS. An iPhone can't send its texts this way.

The sidebar lists every conversation, newest first, with a search field and
a New Message button; the right side shows one conversation as bubbles
(blue for iMessage, green for texts, grey for the other side), times
between bursts of messages, and Delivered or Read under the last one sent.
Everything is kept in an offline store (messages_store.py), so the window
fills at once; new messages come in while the window is closed, since
Messages stays open as Post does, and show a notification and a count on
the Dock icon. Once a backend is set up, Messages starts at login with no
window (freemac-messages --background, from ~/.config/autostart, as Chime's
alarms do), unless "Start Messages when you log in" is turned off.

Bubbles show tapbacks (and, with BlueBubbles' Private API, a bubble's menu
adds one), pictures inline, and "…" while the other side is typing. The
paperclip, or dropping files on a conversation, sends pictures and files.
With the Firewall on, turning on the phone asks for an administrator's
password to let KDE Connect's ports in from the local network
(messages_firewall.py).

Original freemac code; the icon is freemac's own (art/icons/freemac-messages.svg).
"""
import mimetypes
import os
import re
import subprocess
import sys
import time
import uuid

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import launcher_badge, menus, style  # noqa: E402
from . import messages_firewall as firewall  # noqa: E402
from . import messages_store as store  # noqa: E402

APP_ID = "org.freemac.Messages"
DESKTOP_ID = "freemac-messages.desktop"
GAP_MS = 15 * 60 * 1000          # a time line between messages further apart than this
NOTIFY_WITHIN_MS = 10 * 60 * 1000  # only messages this new pop up (not old ones found in a refresh)
SEND_AS = (("bluebubbles", "iMessage"), ("kdeconnect", "Text Message"))
THUMBNAIL = 240                   # a picture's longest side in a bubble
TYPING_FOR_MS = 60 * 1000         # "…" goes if the server never says typing stopped
AUTOSTART_FILE = "freemac-messages-background.desktop"
REACTION_VERBS = {"love": "Loved", "like": "Liked", "dislike": "Disliked", "laugh": "Laughed at",
                  "emphasize": "Emphasized", "question": "Questioned"}

WELCOME_TEXT = ("Messages can show your conversations in two ways. Real iMessage needs a Mac that you own, "
                "running the free BlueBubbles Server app; freemac talks to that Mac, never to Apple. "
                "An Android phone can send and receive its texts through the KDE Connect app. "
                "An iPhone can't send texts through KDE Connect.")
BLUEBUBBLES_TEXT = ("For iPhone and Mac owners. Install BlueBubbles Server on your Mac and sign in to "
                    "iMessage on that Mac; then type the server's address and password here.")
PHONE_TEXT = ("For Android phones. Install KDE Connect on the phone, keep it on the same Wi-Fi network "
              "as this computer, and pair it. An iPhone can't send texts this way.")

CSS = b"""
.msg-sidebar { border-right: 1px solid alpha(currentColor, 0.12); }
.msg-chat-name { font-weight: 600; }
.msg-chat-row { padding: 6px 8px; }
.msg-unread-dot { color: #2a7bf6; font-size: 10px; }
.msg-snippet { opacity: 0.6; font-size: 0.92em; }
.msg-when { opacity: 0.55; font-size: 0.85em; }
.msg-header { padding: 8px 12px; border-bottom: 1px solid alpha(currentColor, 0.10); }
.msg-header-title { font-weight: 600; }
.msg-header-sub { opacity: 0.55; font-size: 0.85em; }
.msg-pane { background-color: @theme_base_color; }
.msg-time { opacity: 0.55; font-size: 0.82em; font-weight: 600; margin: 10px 0 4px 0; }
.msg-status { opacity: 0.55; font-size: 0.78em; margin: 1px 16px 4px 16px; }
.msg-status.failed { color: #e0443e; opacity: 1; }
.msg-sender { opacity: 0.55; font-size: 0.8em; margin: 4px 22px 0 22px; }
.msg-bubble { border-radius: 18px; padding: 7px 12px; margin: 1px 12px; }
.msg-bubble label { font-size: 15px; }
.msg-bubble.imessage { background-color: #2a7bf6; }
.msg-bubble.sms { background-color: #33b852; }
.msg-bubble.imessage label, .msg-bubble.sms label { color: white; }
.msg-bubble.them { background-color: mix(@theme_base_color, @theme_fg_color, 0.11); }
.msg-bubble.them label { color: @theme_fg_color; }
.msg-bubble.mine.tail { border-bottom-right-radius: 5px; }
.msg-bubble.them.tail { border-bottom-left-radius: 5px; }
.msg-bubble.sending { opacity: 0.6; }
.msg-jumbo { margin: 2px 14px; }
.msg-jumbo label { font-size: 40px; }
.msg-attachment { border-radius: 10px; padding: 2px 6px; background-color: alpha(white, 0.18); }
.msg-bubble.them .msg-attachment { background-color: alpha(currentColor, 0.08); }
.msg-failed-mark { color: #e0443e; }
.msg-compose { padding: 8px 10px; border-top: 1px solid alpha(currentColor, 0.10); }
.msg-compose entry { border-radius: 16px; min-height: 30px; padding-left: 12px; }
.msg-send { border-radius: 50%; min-width: 28px; min-height: 28px; padding: 2px; color: white;
            background-image: none; background-color: #2a7bf6; border: none; box-shadow: none; }
.msg-send.sms { background-color: #33b852; }
.msg-send:disabled { background-color: alpha(currentColor, 0.15); color: alpha(currentColor, 0.5); }
.msg-avatar { font-weight: 700; }
.msg-welcome-title { font-size: 26px; font-weight: 700; }
.msg-welcome-card { border-radius: 14px; padding: 16px; background-color: alpha(currentColor, 0.05); }
.msg-welcome-card-title { font-weight: 700; font-size: 15px; }
.msg-to { padding: 6px 12px; border-bottom: 1px solid alpha(currentColor, 0.10); }
.msg-to entry { border: none; box-shadow: none; background: none; }
.msg-tapbacks { border-radius: 12px; padding: 1px 6px; margin: 0 6px -6px 6px; font-size: 13px;
                background-color: mix(@theme_base_color, @theme_fg_color, 0.11);
                border: 2px solid @theme_base_color; }
.msg-tapbacks.mine-too { background-color: #2a7bf6; color: white; }
.msg-picture { border-radius: 12px; }
.msg-media { margin: 2px 12px; }
.msg-media.sending { opacity: 0.6; }
.msg-media button { padding: 0; border: none; box-shadow: none; }
.msg-typing label { font-weight: 700; letter-spacing: 2px; }
.msg-tray { padding: 6px 10px 0 10px; }
.msg-staged { border-radius: 10px; padding: 2px 4px 2px 8px; background-color: alpha(currentColor, 0.07); }
.msg-staged button { padding: 0; min-width: 18px; min-height: 18px; }
"""


# -- times -----------------------------------------------------------------------
def clock(ms):
    try:
        from . import region
        twenty_four = region.uses_24_hour()
    except Exception:   # noqa: BLE001 - no region file
        twenty_four = False
    t = time.localtime(ms / 1000)
    return time.strftime("%H:%M" if twenty_four else "%-I:%M %p", t)


def _days_ago(ms, now):
    a = time.localtime(ms / 1000)
    b = time.localtime(now / 1000)
    return (time.mktime(b[:3] + (12, 0, 0, 0, 0, -1)) - time.mktime(a[:3] + (12, 0, 0, 0, 0, -1))) // 86400


def time_line(ms, now=None):
    """The line between bursts of messages: Today 9:41 AM, Yesterday…, Monday…"""
    now = now or store.now_ms()
    days = _days_ago(ms, now)
    t = time.localtime(ms / 1000)
    if days <= 0:
        return f"Today {clock(ms)}"
    if days == 1:
        return f"Yesterday {clock(ms)}"
    if days < 7:
        return f"{time.strftime('%A', t)} {clock(ms)}"
    if t.tm_year == time.localtime(now / 1000).tm_year:
        return f"{time.strftime('%a, %b %-d', t)} at {clock(ms)}"
    return f"{time.strftime('%b %-d, %Y', t)} at {clock(ms)}"


def list_time(ms, now=None):
    """The sidebar's time: the time today, then Yesterday, a weekday, a date."""
    if not ms:
        return ""
    now = now or store.now_ms()
    days = _days_ago(ms, now)
    t = time.localtime(ms / 1000)
    if days <= 0:
        return clock(ms)
    if days == 1:
        return "Yesterday"
    if days < 7:
        return time.strftime("%A", t)
    return time.strftime("%-m/%-d/%y", t)


def status_text(message, now=None):
    if message.status == "sending":
        return "Sending…"
    if message.status == "failed":
        return "Not Delivered"
    if message.status == "delivered":
        return "Delivered"
    if message.status == "read":
        if not message.status_date:
            return "Read"
        days = _days_ago(message.status_date, now or store.now_ms())
        if days <= 0:
            return f"Read {clock(message.status_date)}"
        return "Read Yesterday" if days == 1 else f"Read {time.strftime('%b %-d', time.localtime(message.status_date / 1000))}"
    if message.status == "sent":
        return "Sent"
    return ""


def is_jumbo(text):
    """One to three emoji and nothing else: shown large, with no bubble."""
    text = (text or "").strip()
    if not text or len(text) > 12 or any(c.isalnum() or c.isspace() for c in text):
        return False
    pictures = [c for c in text if ord(c) >= 0x1F000 or 0x2600 <= ord(c) <= 0x27BF]
    return 0 < len(pictures) <= 3


def layout(messages, group=False, now=None):
    """What a conversation shows, in order:
      ("time", text)                       a time line
      ("sender", name address)             who wrote, in a group conversation
      ("bubble", Message, tail)            tail: the last of a run from one person
      ("status", text, failed)             Delivered, Read 9:41 AM, Not Delivered…
    """
    items = []
    last_mine = max((i for i, m in enumerate(messages) if m.from_me), default=-1)
    previous = None
    for i, m in enumerate(messages):
        new_time = previous is None or m.date - previous.date > GAP_MS
        if new_time:
            items.append(("time", time_line(m.date, now)))
        same_run = (not new_time and previous is not None and previous.from_me == m.from_me
                    and previous.sender == m.sender)
        if group and not m.from_me and not same_run:
            items.append(("sender", m.sender))
        nxt = messages[i + 1] if i + 1 < len(messages) else None
        tail = (nxt is None or nxt.from_me != m.from_me or nxt.sender != m.sender
                or nxt.date - m.date > GAP_MS)
        items.append(("bubble", m, tail))
        if m.from_me and (i == last_mine or m.status == "failed"):
            text = status_text(m, now)
            if text:
                items.append(("status", text, m.status == "failed"))
        previous = m
    return items


def initials(name):
    words = [w for w in re.split(r"[\s,]+", name or "") if w]
    letters = [w[0] for w in words if w[0].isalpha()][:2]
    return "".join(letters).upper()


def contact_book():
    """From Crew's contacts: ({normalised address: name}, {name: first
    phone number or email, as written})."""
    names, book = {}, {}
    try:
        from . import contacts_store
        for card in contacts_store.load():
            for _kind, address in list(card.phones) + list(card.emails):
                names[store.normalise_address(address)] = card.name
                book.setdefault(card.name, address)
    except Exception:   # noqa: BLE001 - no contacts yet
        pass
    return names, book


def split_addresses(text, book=None):
    """'Rosa Marin, +1 555 0100' -> addresses, with contacts' names looked up."""
    by_name = {name.lower(): address for name, address in (book or {}).items()}
    out = []
    for part in re.split(r"[,;]", text or ""):
        part = part.strip()
        if part:
            out.append(by_name.get(part.lower(), part))
    return out


# -- starting at login --------------------------------------------------------------
def autostart_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "autostart", AUTOSTART_FILE)


def set_autostart(on):
    """Start Messages with no window at login (freemac-login-items opens
    ~/.config/autostart), as Chime does for its alarms. Its own file name, so
    Pier's Open at Login, which opens the window, stays separate."""
    path = autostart_path()
    if on:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write("[Desktop Entry]\nType=Application\nName=Messages\n"
                    "Comment=Keeps Messages running so new messages arrive with no window open\n"
                    "Exec=freemac-messages --background\nIcon=freemac-messages\nNoDisplay=true\n")
    else:
        try:
            os.remove(path)
        except OSError:
            pass


def autostart_on():
    return os.path.exists(autostart_path())


# -- pictures and tapbacks -------------------------------------------------------------
def mime_of(path):
    return mimetypes.guess_type(path)[0] or "application/octet-stream"


def is_picture(attachment):
    mime = attachment.get("mime") or mime_of(attachment.get("name") or attachment.get("path") or "")
    return mime.startswith("image/")


_pictures = {}


def picture(attachment, size=THUMBNAIL):
    """A Pixbuf to show in the bubble: the file if it's here, or the phone's
    own small thumbnail; None when there's nothing yet."""
    path = attachment.get("path") or ""
    if not is_picture(attachment):
        return None
    if path and os.path.exists(path):
        key = (path, os.path.getmtime(path), size)
        if key not in _pictures:
            try:
                _pictures[key] = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, size, size, True)
            except GLib.Error:
                _pictures[key] = None
        if _pictures[key] is not None:
            return _pictures[key]
    thumb = attachment.get("thumbnail")
    if thumb:
        key = ("thumb", attachment.get("id"), len(thumb))
        if key not in _pictures:
            try:
                import base64
                loader = GdkPixbuf.PixbufLoader()
                loader.write(base64.b64decode(thumb))
                loader.close()
                found = loader.get_pixbuf()
                scale = min(1.0, size / max(found.get_width(), found.get_height(), 1)) if found else 1
                _pictures[key] = found.scale_simple(max(1, int(found.get_width() * scale)),
                                                    max(1, int(found.get_height() * scale)),
                                                    GdkPixbuf.InterpType.BILINEAR) if found else None
            except (GLib.Error, ValueError, TypeError):
                _pictures[key] = None
        return _pictures[key]
    return None


def tapback_text(reactions):
    """The glyphs on a bubble's corner: each kind once, in the order given."""
    seen = []
    for r in reactions:
        glyph = r.glyph()
        if glyph and glyph not in seen:
            seen.append(glyph)
    count = len([r for r in reactions if r.glyph()])
    return "".join(seen) + (f" {count}" if count > len(seen) else "")


def reaction_line(reaction, target):
    """'Loved “See you there”', for a notification."""
    words = (target.text if target is not None else "") or "an attachment"
    if len(words) > 60:
        words = words[:59] + "…"
    if reaction.kind == "emoji":
        return f"Reacted {reaction.emoji} to “{words}”"
    return f"{REACTION_VERBS.get(reaction.kind, 'Reacted to')} “{words}”"


# -- widgets ---------------------------------------------------------------------------
class Avatar(Gtk.DrawingArea):
    def __init__(self, name, size=40):
        super().__init__()
        self.text = initials(name)
        self.size = size
        self.set_size_request(size, size)
        self.connect("draw", self._draw)

    def _draw(self, _w, cr):
        import cairo
        s = self.size
        gradient = cairo.LinearGradient(0, 0, 0, s)
        gradient.add_color_stop_rgb(0, 0.66, 0.68, 0.72)
        gradient.add_color_stop_rgb(1, 0.52, 0.55, 0.60)
        cr.arc(s / 2, s / 2, s / 2, 0, 6.2832)
        cr.set_source(gradient)
        cr.fill()
        cr.set_source_rgb(1, 1, 1)
        if self.text:
            layout = self.create_pango_layout(self.text)
            layout.set_font_description(Pango.FontDescription(f"Inter Semi-Bold {int(s * 0.36)}px"))
            w, h = layout.get_pixel_size()
            cr.move_to((s - w) / 2, (s - h) / 2)
            PangoCairo.show_layout(cr, layout)
        else:   # a person shape
            cr.arc(s / 2, s * 0.38, s * 0.16, 0, 6.2832)
            cr.fill()
            cr.arc(s / 2, s * 0.92, s * 0.32, 3.1416, 6.2832)
            cr.fill()


class ChatRow(Gtk.ListBoxRow):
    def __init__(self, chat):
        super().__init__()
        self.chat = chat
        self.get_style_context().add_class("msg-chat-row")
        outer = Gtk.Box(spacing=8, margin=4)
        dot = Gtk.Label(label="●" if chat.unread else " ")
        dot.get_style_context().add_class("msg-unread-dot")
        dot.set_size_request(10, -1)
        outer.pack_start(dot, False, False, 0)
        outer.pack_start(Avatar(chat.title), False, False, 0)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        top = Gtk.Box(spacing=6)
        self.name = Gtk.Label(label=chat.title or "Conversation", xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.name.get_style_context().add_class("msg-chat-name")
        when = Gtk.Label(label=list_time(chat.last_date), xalign=1)
        when.get_style_context().add_class("msg-when")
        top.pack_start(self.name, True, True, 0)
        top.pack_start(when, False, False, 0)
        snippet = Gtk.Label(label=chat.last_text or " ", xalign=0, wrap=True, lines=2,
                            ellipsize=Pango.EllipsizeMode.END, max_width_chars=30)
        snippet.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
        snippet.get_style_context().add_class("msg-snippet")
        text.pack_start(top, False, False, 0)
        text.pack_start(snippet, False, False, 0)
        outer.pack_start(text, True, True, 0)
        self.add(outer)


def bubble_widget(message, tail, on_attachment=None, reactions=None, on_menu=None):
    """One message as a row: the bubble at the right for mine, the left for
    theirs, with its tapbacks on the corner toward the middle. on_menu(message,
    event) is called for a right click on the bubble."""
    row = Gtk.Box(spacing=4)
    bubble = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    ctx = bubble.get_style_context()
    pictures = [(a, picture(a)) for a in message.attachments]
    jumbo = is_jumbo(message.text) and not message.attachments
    # Pictures with no words show on their own, with no bubble round them.
    media = bool(pictures) and not message.text and all(p is not None for _a, p in pictures)
    ctx.add_class("msg-jumbo" if jumbo else "msg-media" if media else "msg-bubble")
    if media:
        ctx.add_class("mine" if message.from_me else "them")
        if message.status == "sending":
            ctx.add_class("sending")
    elif not jumbo:
        ctx.add_class("mine" if message.from_me else "them")
        if message.from_me:
            ctx.add_class("imessage" if message.service == "imessage" else "sms")
        if tail:
            ctx.add_class("tail")
        if message.status == "sending":
            ctx.add_class("sending")
    bubble.pictures = []
    for attachment, pixbuf in pictures:
        button = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
        if pixbuf is not None:
            image = Gtk.Image.new_from_pixbuf(pixbuf)
            image.get_style_context().add_class("msg-picture")
            button.add(image)
            button.set_tooltip_text(attachment.get("name") or "Picture")
            bubble.pictures.append(image)
        else:
            button.get_style_context().add_class("msg-attachment")
            inside = Gtk.Box(spacing=6)
            inside.pack_start(Gtk.Image.new_from_icon_name("mail-attachment-symbolic", Gtk.IconSize.MENU),
                              False, False, 0)
            inside.pack_start(Gtk.Label(label=attachment.get("name") or "Attachment",
                                        ellipsize=Pango.EllipsizeMode.MIDDLE, max_width_chars=28), False, False, 0)
            button.add(inside)
        if on_attachment:
            button.connect("clicked", lambda _b, a=attachment: on_attachment(message, a))
        bubble.pack_start(button, False, False, 0)
    if message.text:
        label = Gtk.Label(label=message.text, xalign=0, wrap=True, selectable=True, max_width_chars=42)
        label.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
        label.set_can_focus(False)
        bubble.pack_start(label, False, False, 0)
    bubble.set_tooltip_text(time.strftime("%A, %B %-d, %Y at ", time.localtime(message.date / 1000))
                            + clock(message.date))
    bubble.message = message
    # The tapbacks sit above the bubble, on the corner toward the middle.
    column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    row.tapbacks = None
    reactions = [r for r in reactions or [] if r.glyph()]
    if reactions:
        tapbacks = Gtk.Label(label=tapback_text(reactions))
        tapbacks.get_style_context().add_class("msg-tapbacks")
        if any(r.from_me for r in reactions):
            tapbacks.get_style_context().add_class("mine-too")
        tapbacks.set_halign(Gtk.Align.START if message.from_me else Gtk.Align.END)
        tapbacks.set_tooltip_text("\n".join(("You" if r.from_me else store.format_address(r.sender)) + " "
                                            + (r.emoji if r.kind == "emoji" else
                                               store.REACTION_NAMES.get(r.kind, "")).lower()
                                            for r in reactions))
        column.pack_start(tapbacks, False, False, 0)
        row.tapbacks = tapbacks
    clicks = Gtk.EventBox(visible_window=False)
    clicks.add(bubble)
    if on_menu:
        clicks.connect("button-press-event",
                       lambda _w, event: event.button == Gdk.BUTTON_SECONDARY and (on_menu(message, event) or True))
    column.pack_start(clicks, False, False, 0)
    if message.from_me:
        row.set_halign(Gtk.Align.END)
        if message.status == "failed":
            mark = Gtk.Image.new_from_icon_name("dialog-error-symbolic", Gtk.IconSize.BUTTON)
            mark.get_style_context().add_class("msg-failed-mark")
            row.pack_start(mark, False, False, 0)
        row.pack_start(column, False, False, 0)
    else:
        row.set_halign(Gtk.Align.START)
        row.pack_start(column, False, False, 0)
    row.bubble = bubble
    return row


def typing_widget():
    """The grey bubble with "•••" while the other side is typing."""
    row = Gtk.Box(halign=Gtk.Align.START)
    bubble = Gtk.Box()
    for name in ("msg-bubble", "them", "tail", "msg-typing"):
        bubble.get_style_context().add_class(name)
    bubble.pack_start(Gtk.Label(label="•••"), False, False, 0)
    bubble.set_tooltip_text("Typing…")
    row.pack_start(bubble, False, False, 0)
    row.typing = True
    return row


def bubble_menu(message, can_react=False, mine="", on_react=None, on_copy=None):
    """A bubble's menu: Copy, and the six tapbacks when the BlueBubbles
    server's Private API is on (choosing your own again takes it back)."""
    menu = Gtk.Menu()
    menu.reactions = {}
    if message.text:
        copy = Gtk.MenuItem(label="Copy")
        copy.connect("activate", lambda *_: on_copy and on_copy(message.text))
        menu.append(copy)
    if can_react:
        if menu.get_children():
            menu.append(Gtk.SeparatorMenuItem())
        for kind in store.REACTION_KINDS:
            item = Gtk.CheckMenuItem(label=f"{store.REACTION_GLYPHS[kind]}  {store.REACTION_NAMES[kind]}")
            item.set_active(kind == mine)
            item.connect("activate", lambda _i, k=kind: on_react and on_react(message, k))
            menu.append(item)
            menu.reactions[kind] = item
    menu.show_all()
    return menu


def conversation_widgets(items, names=None, on_attachment=None, reactions=None, on_menu=None):
    names = names or {}
    reactions = reactions or {}
    widgets = []
    for item in items:
        if item[0] == "time":
            label = Gtk.Label(label=item[1])
            label.get_style_context().add_class("msg-time")
            widgets.append(label)
        elif item[0] == "sender":
            label = Gtk.Label(label=names.get(store.normalise_address(item[1])) or store.format_address(item[1]),
                              xalign=0)
            label.get_style_context().add_class("msg-sender")
            widgets.append(label)
        elif item[0] == "bubble":
            widgets.append(bubble_widget(item[1], item[2], on_attachment, reactions.get(item[1].id), on_menu))
        elif item[0] == "status":
            label = Gtk.Label(label=item[1], xalign=1)
            label.get_style_context().add_class("msg-status")
            if item[2]:
                label.get_style_context().add_class("failed")
            widgets.append(label)
    return widgets


def subtitle_for(chat, status=None):
    if chat.backend == "bluebubbles":
        return f"{store.SERVICE_NAMES.get(chat.service, 'iMessage')} through BlueBubbles"
    return "Text Message through your phone"


# -- the window ------------------------------------------------------------------------
class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Messages")
        self.app = app
        self.set_default_size(920, 620)
        self.set_icon_name("freemac-messages")
        self.current = None          # the Chat on show
        self.composing = False       # the New Message page
        self.root = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.add(self.root)
        self.root.add_named(self._welcome(), "welcome")
        self.root.add_named(self._main(), "main")
        menus.add_actions(self, {"new-message": self.new_message, "find": lambda: self.search.grab_focus(),
                                 "close": self.close, "delete-conversation": self.delete_conversation})
        self.connect("key-press-event", self._key)
        self.connect("notify::is-active", lambda *_: self.is_active() and self.current and self.app.read(self.current))
        self.show_all()
        self.root.set_visible_child_name("main" if app.settings.get("welcomed") or app.configured() else "welcome")
        self.fill_list()
        self.update_status()

    # -- first run ----------------------------------------------------------------
    def _welcome(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, halign=Gtk.Align.CENTER,
                      valign=Gtk.Align.CENTER, margin=30)
        box.set_size_request(560, -1)
        icon = Gtk.Image.new_from_icon_name("freemac-messages", Gtk.IconSize.DIALOG)
        icon.set_pixel_size(96)
        box.pack_start(icon, False, False, 0)
        title = Gtk.Label(label="Welcome to Messages")
        title.get_style_context().add_class("msg-welcome-title")
        box.pack_start(title, False, False, 0)
        intro = Gtk.Label(label=WELCOME_TEXT, wrap=True, justify=Gtk.Justification.CENTER, max_width_chars=64)
        box.pack_start(intro, False, False, 4)
        self.welcome_buttons = {}
        for kind, heading, text, button_text in (
                ("bluebubbles", "iMessage through BlueBubbles", BLUEBUBBLES_TEXT, "Connect to BlueBubbles…"),
                ("kdeconnect", "Texts through an Android phone", PHONE_TEXT, "Pair an Android Phone…")):
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            card.get_style_context().add_class("msg-welcome-card")
            head = Gtk.Label(label=heading, xalign=0)
            head.get_style_context().add_class("msg-welcome-card-title")
            body = Gtk.Label(label=text, xalign=0, wrap=True, max_width_chars=64)
            button = Gtk.Button(label=button_text, halign=Gtk.Align.START)
            button.connect("clicked", lambda _b, k=kind: self.app.show_settings(k))
            self.welcome_buttons[kind] = button
            for widget in (head, body, button):
                card.pack_start(widget, False, False, 0)
            box.pack_start(card, False, False, 0)
        later = Gtk.Button(label="Not Now", halign=Gtk.Align.CENTER, relief=Gtk.ReliefStyle.NONE)
        later.connect("clicked", lambda _b: self.leave_welcome())
        box.pack_start(later, False, False, 0)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.add(box)
        return scroll

    def leave_welcome(self):
        self.app.settings["welcomed"] = True
        store.save_settings(self.app.settings)
        self.root.set_visible_child_name("main")

    # -- the main page ----------------------------------------------------------------
    def _main(self):
        paned = Gtk.Paned()
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.get_style_context().add_class("msg-sidebar")
        side.set_size_request(290, -1)
        top = Gtk.Box(spacing=6, margin=8)
        self.search = Gtk.SearchEntry(placeholder_text="Search")
        self.search.connect("search-changed", lambda *_: self.fill_list())
        self.new_button = Gtk.Button.new_from_icon_name("document-edit-symbolic", Gtk.IconSize.BUTTON)
        self.new_button.set_tooltip_text("New Message (⌘N)")
        self.new_button.connect("clicked", lambda *_: self.new_message())
        top.pack_start(self.search, True, True, 0)
        top.pack_start(self.new_button, False, False, 0)
        side.pack_start(top, False, False, 0)
        self.listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.BROWSE)
        self.listbox.connect("row-selected", self._selected)
        placeholder = Gtk.Label(label="No Conversations", margin=20)
        placeholder.get_style_context().add_class("dim-label")
        placeholder.show()
        self.listbox.set_placeholder(placeholder)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.add(self.listbox)
        side.pack_start(scroll, True, True, 0)
        self.status = Gtk.Label(xalign=0, margin=8, ellipsize=Pango.EllipsizeMode.END)
        self.status.get_style_context().add_class("msg-when")
        side.pack_start(self.status, False, False, 0)
        paned.pack1(side, False, False)

        self.pane = Gtk.Stack()
        empty = Gtk.Label(label="No Conversation Selected")
        empty.get_style_context().add_class("dim-label")
        self.pane.add_named(empty, "empty")
        chat = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        chat.get_style_context().add_class("msg-pane")
        # The header: who it is, or To: for a new message.
        self.header = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        self.header.get_style_context().add_class("msg-header")
        self.title = Gtk.Label(xalign=0.5)
        self.title.get_style_context().add_class("msg-header-title")
        self.subtitle = Gtk.Label(xalign=0.5)
        self.subtitle.get_style_context().add_class("msg-header-sub")
        self.header.pack_start(self.title, False, False, 0)
        self.header.pack_start(self.subtitle, False, False, 0)
        chat.pack_start(self.header, False, False, 0)
        self.to_bar = Gtk.Box(spacing=8)
        self.to_bar.get_style_context().add_class("msg-to")
        self.to_bar.pack_start(Gtk.Label(label="To:"), False, False, 0)
        self.to = Gtk.Entry(placeholder_text="Name, phone number or email")
        completion = Gtk.EntryCompletion()
        self.completion_model = Gtk.ListStore(str)
        completion.set_model(self.completion_model)
        completion.set_text_column(0)
        self.to.set_completion(completion)
        self.to.connect("changed", lambda *_: self._update_compose())
        self.to_bar.pack_start(self.to, True, True, 0)
        self.send_as = Gtk.ComboBoxText()
        for kind, label in SEND_AS:
            self.send_as.append(kind, label)
        self.send_as.connect("changed", lambda *_: self._update_compose())
        self.to_bar.pack_start(self.send_as, False, False, 0)
        chat.pack_start(self.to_bar, False, False, 0)
        self.scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.bubbles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1, margin_top=6, margin_bottom=8)
        self.scroll.add(self.bubbles)
        self.scroll.get_vadjustment().connect("changed", lambda adj: self._stick_to_bottom(adj))
        chat.pack_start(self.scroll, True, True, 0)
        # Pictures and files waiting to go with the next message.
        self.staged = []
        self.tray = Gtk.Box(spacing=6)
        self.tray.get_style_context().add_class("msg-tray")
        self.tray.set_no_show_all(True)
        chat.pack_start(self.tray, False, False, 0)
        compose = Gtk.Box(spacing=6)
        compose.get_style_context().add_class("msg-compose")
        self.attach_button = Gtk.Button.new_from_icon_name("mail-attachment-symbolic", Gtk.IconSize.BUTTON)
        self.attach_button.set_relief(Gtk.ReliefStyle.NONE)
        self.attach_button.set_tooltip_text("Attach a Picture or File…")
        self.attach_button.connect("clicked", lambda *_: self.choose_files())
        compose.pack_start(self.attach_button, False, False, 0)
        # Files dropped anywhere on the conversation are attached.
        chat.drag_dest_set(Gtk.DestDefaults.ALL, [Gtk.TargetEntry.new("text/uri-list", 0, 0)], Gdk.DragAction.COPY)
        chat.connect("drag-data-received", self._dropped)
        self.emoji = Gtk.Button.new_from_icon_name("face-smile-symbolic", Gtk.IconSize.BUTTON)
        self.emoji.set_relief(Gtk.ReliefStyle.NONE)
        self.emoji.set_tooltip_text("Emoji")
        self.emoji.connect("clicked", lambda *_: self.pick_emoji())
        self.entry = Gtk.Entry(placeholder_text="iMessage")
        self.entry.connect("activate", lambda *_: self.send())
        self.entry.connect("changed", lambda *_: self._update_compose())
        self.send_button = Gtk.Button.new_from_icon_name("go-up-symbolic", Gtk.IconSize.BUTTON)
        self.send_button.get_style_context().add_class("msg-send")
        self.send_button.set_tooltip_text("Send")
        self.send_button.connect("clicked", lambda *_: self.send())
        compose.pack_start(self.emoji, False, False, 0)
        compose.pack_start(self.entry, True, True, 0)
        compose.pack_start(self.send_button, False, False, 0)
        chat.pack_start(compose, False, False, 0)
        self.pane.add_named(chat, "chat")
        paned.pack2(self.pane, True, False)
        self.stuck = True
        return paned

    def _stick_to_bottom(self, adj):
        if self.stuck:
            adj.set_value(adj.get_upper() - adj.get_page_size())

    # -- the list ----------------------------------------------------------------------
    def fill_list(self):
        keep = self.current.id if self.current else None
        for row in self.listbox.get_children():
            self.listbox.remove(row)
        chosen = None
        for chat in self.app.store.chats(self.search.get_text()):
            row = ChatRow(chat)
            self.listbox.add(row)
            if chat.id == keep:
                chosen = row
        self.listbox.show_all()
        if chosen is not None:
            self.listbox.handler_block_by_func(self._selected)
            self.listbox.select_row(chosen)
            self.listbox.handler_unblock_by_func(self._selected)
        elif not self.composing and self.current is None:
            self.pane.set_visible_child_name("empty")

    def rows(self):
        return self.listbox.get_children()

    def _selected(self, _box, row):
        if row is None:
            return
        self.show_chat(row.chat)

    def select_chat(self, chat_id):
        for row in self.rows():
            if row.chat.id == chat_id:
                self.listbox.select_row(row)
                self.show_chat(row.chat)
                return True
        chat = self.app.store.chat(chat_id)
        if chat:
            self.search.set_text("")
            self.show_chat(chat)
        return chat is not None

    # -- one conversation ----------------------------------------------------------
    def show_chat(self, chat):
        changed = self.current is None or self.current.id != chat.id
        self.composing = False
        self.current = chat
        self.to_bar.hide()
        self.header.show()
        self.title.set_text(chat.title or "Conversation")
        self.subtitle.set_text(subtitle_for(chat))
        self.entry.set_placeholder_text(store.SERVICE_NAMES.get(chat.service, "Text Message")
                                        if chat.backend == "bluebubbles" else "Text Message")
        self.pane.set_visible_child_name("chat")
        self.set_title(f"{chat.title} – Messages" if chat.title else "Messages")
        self.fill_bubbles()
        if changed:
            self.stuck = True
            self.staged = []
            self._fill_tray()
            self.app.opened(chat)
            self.entry.grab_focus()
        self._update_compose()

    def fill_bubbles(self):
        for child in self.bubbles.get_children():
            self.bubbles.remove(child)
        if self.current is None or self.composing:
            return
        messages = self.app.store.messages(self.current.id)
        group = len(self.current.addresses) > 1
        for widget in conversation_widgets(layout(messages, group), self.app.names, self.app.open_attachment,
                                           self.app.store.reactions(self.current.id), self.bubble_menu):
            self.bubbles.pack_start(widget, False, False, 0)
        if self.app.is_typing(self.current.id):
            self.bubbles.pack_start(typing_widget(), False, False, 0)
        self.bubbles.show_all()

    def bubble_menu(self, message, event=None):
        menu = bubble_menu(message, self.app.can_react(message), self.app.store.my_reaction(message.id),
                           self.app.react, self._copy)
        if not menu.get_children():
            return None
        menu.attach_to_widget(self, None)
        if event is not None:
            menu.popup_at_pointer(event)
        return menu

    def _copy(self, text):
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)

    # -- attachments ------------------------------------------------------------------
    def can_attach(self):
        """Files go into a conversation that exists; a new one through the phone
        (as an MMS), but through BlueBubbles only after its first message."""
        if self.composing:
            return self.send_as.get_active_id() == "kdeconnect"
        return self.current is not None

    def choose_files(self):
        if not self.can_attach():
            return
        dialog = Gtk.FileChooserNative.new("Attach", self, Gtk.FileChooserAction.OPEN, "Attach", "Cancel")
        dialog.set_select_multiple(True)
        if dialog.run() == Gtk.ResponseType.ACCEPT:
            self.attach([f.get_path() for f in dialog.get_files() if f.get_path()])
        dialog.destroy()

    def _dropped(self, _widget, _context, _x, _y, data, _info, _time):
        paths = []
        for uri in data.get_uris() or []:
            try:
                path, _host = GLib.filename_from_uri(uri)
            except GLib.Error:
                continue
            paths.append(path)
        self.attach(paths)

    def attach(self, paths):
        """Stage files to go with the next message; returns how many were taken."""
        if not self.can_attach():
            return 0
        taken = 0
        for path in paths:
            if os.path.isfile(path) and path not in self.staged:
                self.staged.append(path)
                taken += 1
        self._fill_tray()
        self._update_compose()
        if taken:
            self.entry.grab_focus()
        return taken

    def unstage(self, path):
        if path in self.staged:
            self.staged.remove(path)
        self._fill_tray()
        self._update_compose()

    def _fill_tray(self):
        for child in self.tray.get_children():
            self.tray.remove(child)
        for path in self.staged:
            chip = Gtk.Box(spacing=4)
            chip.get_style_context().add_class("msg-staged")
            pixbuf = picture({"path": path, "name": path}, 48)
            chip.pack_start(Gtk.Image.new_from_pixbuf(pixbuf) if pixbuf is not None else
                            Gtk.Image.new_from_icon_name("text-x-generic-symbolic", Gtk.IconSize.BUTTON),
                            False, False, 0)
            chip.pack_start(Gtk.Label(label=os.path.basename(path), ellipsize=Pango.EllipsizeMode.MIDDLE,
                                      max_width_chars=20), False, False, 0)
            remove = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.MENU)
            remove.set_relief(Gtk.ReliefStyle.NONE)
            remove.set_tooltip_text("Remove")
            remove.connect("clicked", lambda _b, p=path: self.unstage(p))
            chip.pack_start(remove, False, False, 0)
            chip.path = path
            self.tray.pack_start(chip, False, False, 0)
        for child in self.tray.get_children():
            child.show_all()
        self.tray.set_visible(bool(self.staged))

    def refresh(self, chat_ids=None):
        """After the store changed: the list, and the conversation on show."""
        self.fill_list()
        if self.current and (chat_ids is None or self.current.id in chat_ids):
            fresh = self.app.store.chat(self.current.id)
            if fresh:
                self.current = fresh
                self.title.set_text(fresh.title or "Conversation")
                self.fill_bubbles()

    def new_message(self, to=""):
        self.composing = True
        self.current = None
        self.listbox.unselect_all()
        self.header.hide()
        self.to_bar.show_all()
        self.to.set_text(to)
        self.completion_model.clear()
        for name in sorted(self.app.book):
            self.completion_model.append([name])
        kinds = self.app.available()
        self.send_as.set_active_id(kinds[0] if kinds else "bluebubbles")
        self.send_as.set_visible(len(kinds) > 1)
        self.staged = []
        self._fill_tray()
        self.fill_bubbles()
        self.pane.set_visible_child_name("chat")
        self.set_title("New Message – Messages")
        self.to.grab_focus()
        self._update_compose()

    def _update_compose(self):
        kind = self.send_as.get_active_id() if self.composing else (self.current.backend if self.current else None)
        service = "imessage" if kind == "bluebubbles" and (self.composing or self.current.service == "imessage") \
            else "sms"
        ctx = self.send_button.get_style_context()
        if service == "sms":
            ctx.add_class("sms")
        else:
            ctx.remove_class("sms")
        if self.composing:
            self.entry.set_placeholder_text("iMessage" if service == "imessage" else "Text Message")
        if self.staged and not self.can_attach():
            self.staged = []         # New Message switched to iMessage, which takes files only later
            self._fill_tray()
        self.attach_button.set_sensitive(self.can_attach())
        self.attach_button.set_tooltip_text("Attach a Picture or File…" if self.can_attach() else
                                            "Send a first message, then attach pictures and files.")
        ready = (bool(self.entry.get_text().strip()) or bool(self.staged)) and \
            (not self.composing or bool(self.to.get_text().strip()))
        self.send_button.set_sensitive(ready)

    def pick_emoji(self):
        self.entry.grab_focus()
        self.entry.emit("insert-emoji")

    def send(self):
        text = self.entry.get_text().strip()
        files = list(self.staged)
        if not text and not files:
            return
        if self.composing:
            addresses = split_addresses(self.to.get_text(), self.app.book)
            if not addresses:
                self.to.grab_focus()
                return
            chat_id = self.app.send_new(self.send_as.get_active_id(), addresses, text, files)
        elif self.current is not None:
            chat_id = self.app.send(self.current, text, files)
        else:
            return
        self.entry.set_text("")
        self.staged = []
        self._fill_tray()
        self._update_compose()
        self.stuck = True
        if chat_id:
            self.composing = False
            self.fill_list()
            self.select_chat(chat_id)

    def delete_conversation(self):
        if self.current is None:
            return
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.WARNING,
                                   text=f"Delete the conversation with {self.current.title}?",
                                   secondary_text="It's removed from this computer only. It comes back if "
                                                  "the phone or server sends it again.")
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Delete", Gtk.ResponseType.OK)
        if dialog.run() == Gtk.ResponseType.OK:
            self.app.store.delete_chat(self.current.id)
            self.current = None
            self.fill_list()
            self.pane.set_visible_child_name("empty")
        dialog.destroy()

    def update_status(self):
        lines = [text for _kind, (text, _ok) in sorted(self.app.status.items())]
        if self.app.firewall_blocks_phone():
            lines.append("The firewall blocks your phone")
        self.status.set_text(" · ".join(lines))
        self.status.set_tooltip_text("\n".join(lines))
        self.status.set_visible(bool(lines))

    def _key(self, _w, event):
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        key = Gdk.keyval_to_lower(event.keyval)
        if ctrl and key == Gdk.KEY_n:
            self.new_message()
        elif ctrl and key == Gdk.KEY_f:
            self.search.grab_focus()
        elif ctrl and key == Gdk.KEY_w:
            self.close()
        else:
            return False
        return True


# -- settings ---------------------------------------------------------------------------
class Settings(Gtk.Dialog):
    def __init__(self, app, parent, page=None):
        super().__init__(title="Messages Settings", transient_for=parent, modal=False)
        self.app = app
        self.set_default_size(520, -1)
        self.add_button("Done", Gtk.ResponseType.CLOSE)
        self.connect("response", lambda *_: self.destroy())
        notebook = Gtk.Notebook()
        self.get_content_area().pack_start(notebook, True, True, 0)

        # BlueBubbles
        page_bb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=16)
        intro = Gtk.Label(label="iMessage through BlueBubbles. " + BLUEBUBBLES_TEXT +
                          " BlueBubbles Server is free and open source; it runs on your Mac, "
                          "not on freemac.", wrap=True, xalign=0, max_width_chars=60)
        page_bb.pack_start(intro, False, False, 0)
        grid = Gtk.Grid(column_spacing=8, row_spacing=8)
        bb = app.settings.get("bluebubbles") or {}
        self.url = Gtk.Entry(text=bb.get("url", ""), placeholder_text="http://192.168.1.20:1234", hexpand=True)
        self.password = Gtk.Entry(visibility=False, input_purpose=Gtk.InputPurpose.PASSWORD)
        if bb.get("url"):
            self.password.set_text(store.load_password("bluebubbles:" + bb["url"]))
        grid.attach(Gtk.Label(label="Server address:", xalign=1), 0, 0, 1, 1)
        grid.attach(self.url, 1, 0, 1, 1)
        grid.attach(Gtk.Label(label="Password:", xalign=1), 0, 1, 1, 1)
        grid.attach(self.password, 1, 1, 1, 1)
        page_bb.pack_start(grid, False, False, 0)
        buttons = Gtk.Box(spacing=8)
        self.connect_button = Gtk.Button(label="Connect")
        self.connect_button.connect("clicked", lambda *_: self._connect_bb())
        self.disconnect_button = Gtk.Button(label="Remove Server")
        self.disconnect_button.connect("clicked", lambda *_: self._remove_bb())
        buttons.pack_start(self.connect_button, False, False, 0)
        buttons.pack_start(self.disconnect_button, False, False, 0)
        page_bb.pack_start(buttons, False, False, 0)
        self.bb_status = Gtk.Label(xalign=0, wrap=True)
        self.bb_status.get_style_context().add_class("dim-label")
        page_bb.pack_start(self.bb_status, False, False, 0)
        notebook.append_page(page_bb, Gtk.Label(label="iMessage"))

        # Phone
        page_phone = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=16)
        page_phone.pack_start(Gtk.Label(label=PHONE_TEXT, wrap=True, xalign=0, max_width_chars=60), False, False, 0)
        switch_row = Gtk.Box(spacing=8)
        switch_row.pack_start(Gtk.Label(label="Use an Android phone for texts"), False, False, 0)
        self.phone_switch = Gtk.Switch(active=bool((app.settings.get("phone") or {}).get("on")))
        self.phone_switch.connect("notify::active", lambda *_: self.app.set_phone(self.phone_switch.get_active()))
        switch_row.pack_end(self.phone_switch, False, False, 0)
        page_phone.pack_start(switch_row, False, False, 0)
        self.devices = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        frame = Gtk.Frame()
        frame.add(self.devices)
        page_phone.pack_start(frame, False, False, 0)
        add_row = Gtk.Box(spacing=8)
        self.address = Gtk.Entry(placeholder_text="Phone's address on the network, if it isn't found")
        add = Gtk.Button(label="Add")
        add.connect("clicked", lambda *_: self._add_address())
        add_row.pack_start(self.address, True, True, 0)
        add_row.pack_start(add, False, False, 0)
        page_phone.pack_start(add_row, False, False, 0)
        self.phone_status = Gtk.Label(xalign=0, wrap=True)
        self.phone_status.get_style_context().add_class("dim-label")
        page_phone.pack_start(self.phone_status, False, False, 0)
        # With Dials' Firewall on, KDE Connect's ports have to be let in.
        self.firewall_row = Gtk.Box(spacing=8)
        self.firewall_label = Gtk.Label(xalign=0, wrap=True, max_width_chars=48)
        self.firewall_button = Gtk.Button(label="Let Phone Through Firewall…", valign=Gtk.Align.CENTER)
        self.firewall_button.connect("clicked", lambda *_: self.app.phone_firewall(True))
        self.firewall_row.pack_start(self.firewall_label, True, True, 0)
        self.firewall_row.pack_start(self.firewall_button, False, False, 0)
        self.firewall_row.set_no_show_all(True)
        page_phone.pack_start(self.firewall_row, False, False, 0)
        notebook.append_page(page_phone, Gtk.Label(label="Phone"))

        # For both: keep running after login, so messages arrive with no window.
        login = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, margin_start=16, margin_end=16,
                        margin_top=10, margin_bottom=6)
        self.login_check = Gtk.CheckButton(label="Start Messages when you log in")
        self.login_check.set_active(app.start_at_login())
        self.login_check.connect("toggled", lambda b: self.app.set_start_at_login(b.get_active()))
        login.pack_start(self.login_check, False, False, 0)
        hint = Gtk.Label(label="New messages then arrive, with a notification, even when no Messages window "
                               "is open.", xalign=0, wrap=True, max_width_chars=60, margin_start=26)
        hint.get_style_context().add_class("dim-label")
        login.pack_start(hint, False, False, 0)
        self.get_content_area().pack_start(login, False, False, 0)
        self.show_all()
        if page == "kdeconnect":
            notebook.set_current_page(1)
        self.refresh()

    def refresh(self):
        bb = self.app.status.get("bluebubbles")
        self.bb_status.set_text(bb[0] if bb else "Not connected")
        self.disconnect_button.set_sensitive(bool(self.app.settings.get("bluebubbles")))
        phone = self.app.status.get("kdeconnect")
        self.phone_status.set_text(phone[0] if phone else "Off")
        self.login_check.set_sensitive(self.app.configured())
        state = self.app.firewall_state()
        if state is None:
            self.firewall_row.hide()
        else:
            self.firewall_row.show_all()
            if state == "open":
                self.firewall_label.set_text("The firewall lets your phone in from this network (KDE Connect's "
                                             "UDP port 1716 and TCP ports 1716–1764).")
            elif state == "busy":
                self.firewall_label.set_text("Asking for an administrator's password to let your phone "
                                             "through the firewall…")
            else:
                self.firewall_label.set_text("The firewall is on and turns your phone away. Let it in from "
                                             "this network only, after an administrator's password.")
            self.firewall_button.set_visible(state == "closed")
        for row in self.devices.get_children():
            self.devices.remove(row)
        devices = self.app.devices if self.phone_switch.get_active() else []
        if not devices:
            label = Gtk.Label(label="Looking for phones on this network…" if self.phone_switch.get_active()
                              else "Turn on to find your phone.", margin=10)
            label.get_style_context().add_class("dim-label")
            self.devices.add(label)
        for device in devices:
            row = Gtk.Box(spacing=8, margin=8)
            row.pack_start(Gtk.Image.new_from_icon_name("phone-symbolic", Gtk.IconSize.BUTTON), False, False, 0)
            state = "Paired" if device["paired"] else "Not paired"
            if device["paired"]:
                state += ", connected" if device["connected"] else ", not in reach"
            text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            text.pack_start(Gtk.Label(label=device["name"], xalign=0), False, False, 0)
            sub = Gtk.Label(label=state, xalign=0)
            sub.get_style_context().add_class("dim-label")
            text.pack_start(sub, False, False, 0)
            row.pack_start(text, True, True, 0)
            button = Gtk.Button(label="Unpair" if device["paired"] else "Pair…")
            button.connect("clicked", lambda _b, d=device: self.app.unpair(d["id"]) if d["paired"]
                           else self.app.pair(d["id"], d["name"]))
            row.pack_start(button, False, False, 0)
            self.devices.add(row)
        self.devices.show_all()

    def _connect_bb(self):
        try:
            self.app.set_bluebubbles(self.url.get_text(), self.password.get_text())
        except ValueError as e:
            self.bb_status.set_text(str(e))

    def _remove_bb(self):
        self.app.set_bluebubbles(None, None)
        self.url.set_text("")
        self.password.set_text("")

    def _add_address(self):
        host = self.address.get_text().strip()
        if host:
            self.app.add_phone_address(host)
            self.address.set_text("")


class OnMainLoop:
    """Hands backend calls (made on their own threads) to GTK's main loop."""
    def __init__(self, target):
        self.target = target

    def __getattr__(self, name):
        method = getattr(self.target, name)

        def call(*args):
            GLib.idle_add(lambda: method(*args) and False)
        return call


def menubar():
    return menus.menubar([
        ("_File", [[("New Message", "win.new-message", "<Ctrl>n")],
                   [("Close Window", "win.close", "<Ctrl>w")]]),
        ("_Edit", [[("Find", "win.find", "<Ctrl>f")],
                   [("Delete Conversation…", "win.delete-conversation", None)]]),
        ("_Conversation", [[("Refresh", "app.refresh", "<Ctrl>r")]]),
    ])


class Messages(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.store = None
        self.settings = {}
        self.status = {}          # backend kind -> (text, connected)
        self.devices = []         # KDE Connect phones found or paired
        self.backends = {}
        self.names = {}           # normalised address -> contact's name
        self.book = {}            # contact's name -> address
        self.pending_new = {}     # sorted normalised addresses -> placeholder chat id
        self.settings_window = None
        self.pair_dialog = None
        self.typing = {}          # chat id -> when the "…" goes (ms)
        self.fetching = set()     # attachment ids being fetched to show as pictures
        self.firewall_busy = False
        self.firewall_asked = None
        self.firewall_runner = firewall.run   # the tests put a stand-in here

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        menus.add_actions(self, {"quit": lambda: GLib.idle_add(self.quit), "settings": self.show_settings,
                                 "refresh": self.refresh, "new-message": self._new_message})
        open_chat = Gio.SimpleAction.new("open-chat", GLib.VariantType.new("s"))
        open_chat.connect("activate", lambda _a, value: self.open_chat(value.get_string()))
        self.add_action(open_chat)
        self.set_accels_for_action("app.settings", ["<Control>comma"])
        self.set_menubar(menubar())
        self.setup()
        # Messages stays open with no window, as Post does, so texts keep coming in.
        self.hold()

    def setup(self, store_path=None):
        self.store = store.Store(store_path)
        self.settings = store.load_settings()
        self.names, self.book = contact_book()
        self.start_backends()
        self.badge()
        self.sync_autostart()

    def do_shutdown(self):
        for backend in self.backends.values():
            backend.stop()
        Gtk.Application.do_shutdown(self)

    def main_window(self):
        return next((w for w in self.get_windows() if isinstance(w, Window)), None) or Window(self)

    def window(self):
        return next((w for w in self.get_windows() if isinstance(w, Window)), None)

    def do_activate(self):
        self.main_window().present()

    def do_command_line(self, command_line):
        """freemac-messages opens the window; --background (at login) only
        keeps Messages running, so new messages arrive with no window."""
        if "--background" not in command_line.get_arguments()[1:]:
            self.activate()
        elif not self.configured() and not self.get_windows():
            self.quit()          # nothing set up: nothing to wait for
        return 0

    def _new_message(self):
        window = self.main_window()
        window.present()
        window.new_message()

    def open_chat(self, chat_id):
        window = self.main_window()
        window.present()
        window.root.set_visible_child_name("main")
        window.select_chat(chat_id)

    # -- backends ----------------------------------------------------------------------
    def configured(self):
        return bool(self.settings.get("bluebubbles")) or bool((self.settings.get("phone") or {}).get("on"))

    def available(self):
        return [kind for kind, _label in SEND_AS if kind in self.backends]

    # -- starting at login ----------------------------------------------------------
    def start_at_login(self):
        """The choice in Settings: on unless turned off."""
        return self.settings.get("start_at_login", True) is not False

    def set_start_at_login(self, on):
        self.settings["start_at_login"] = bool(on)
        store.save_settings(self.settings)
        self.sync_autostart()

    def sync_autostart(self):
        """Starts at login once a backend is set up, if that's still wanted."""
        wanted = self.configured() and self.start_at_login()
        if wanted != autostart_on():
            try:
                set_autostart(wanted)
            except OSError:
                pass

    # -- the firewall, for the phone ---------------------------------------------------
    def firewall_state(self):
        """None (the phone is off, or the firewall is), "open", "closed" or "busy"."""
        if not (self.settings.get("phone") or {}).get("on"):
            return None
        if self.firewall_busy:
            return "busy"
        if firewall.ports_open():
            return "open"
        return "closed" if firewall.firewall_on() else None

    def firewall_blocks_phone(self):
        return self.firewall_state() == "closed"

    def phone_firewall(self, on):
        """Opens KDE Connect's ports to the local network when the phone is
        turned on with the Firewall on, and closes them when it's turned off,
        through freemac's system helper (an administrator's password)."""
        change = firewall.change_for(on)
        if change is None or self.firewall_busy or not firewall.available():
            return False
        self.firewall_busy, self.firewall_asked = True, change
        self._changed_status()
        self.firewall_runner(change, self._firewall_done)
        return True

    def _firewall_done(self, ok, error):
        self.firewall_busy = False
        if error:
            self.tell(f"The firewall couldn’t be changed. {error}")
        # The phone was switched the other way while the password was asked.
        phone_on = bool((self.settings.get("phone") or {}).get("on"))
        if ok and self.firewall_asked is not phone_on:
            self.phone_firewall(phone_on)
        self._changed_status()

    def start_backends(self):
        listener = OnMainLoop(self)
        bb = self.settings.get("bluebubbles") or {}
        if bb.get("url") and "bluebubbles" not in self.backends:
            from . import messages_bluebubbles
            try:
                backend = messages_bluebubbles.BlueBubbles(listener, bb["url"],
                                                           store.load_password("bluebubbles:" + bb["url"]),
                                                           self.names)
            except ValueError as e:
                self.status["bluebubbles"] = (str(e), False)
            else:
                self.backends["bluebubbles"] = backend
                self.status["bluebubbles"] = ("Connecting to BlueBubbles…", False)
                backend.start(since=self.store.latest_date("bluebubbles"))
        phone = self.settings.get("phone") or {}
        if phone.get("on") and "kdeconnect" not in self.backends:
            from . import messages_kdeconnect
            bus = None
            try:
                bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            except GLib.Error:
                pass
            if bus is not None and messages_kdeconnect.daemon_running(bus):
                # KDE's own kdeconnectd is running: use it, rather than a second stack.
                backend = messages_kdeconnect.KdeConnectDaemon(self, bus, self.names)
            else:
                announce = [("255.255.255.255", messages_kdeconnect.UDP_PORT)]
                announce += [(host, messages_kdeconnect.UDP_PORT) for host in phone.get("addresses", [])]
                try:
                    backend = messages_kdeconnect.KdeConnect(listener, announce_to=announce, names=self.names)
                except (OSError, ValueError, subprocess.CalledProcessError):
                    # No OpenSSL to make the certificate, or the folder can't be written.
                    self.status["kdeconnect"] = ("Couldn't set up KDE Connect on this computer.", False)
                    self._changed_status()
                    return
            self.backends["kdeconnect"] = backend
            backend.start()

    def stop_backend(self, kind):
        backend = self.backends.pop(kind, None)
        if backend:
            backend.stop()
        self.status.pop(kind, None)
        if kind == "kdeconnect":
            self.devices = []
        self._changed_status()

    def set_bluebubbles(self, url, password):
        old = self.settings.get("bluebubbles") or {}
        self.stop_backend("bluebubbles")
        if url is None:
            if old.get("url"):
                store.delete_password("bluebubbles:" + old["url"])
            self.settings.pop("bluebubbles", None)
            self.store.forget_backend("bluebubbles")
        else:
            from . import messages_bluebubbles
            url = messages_bluebubbles.normalise_url(url)
            where = store.save_password("bluebubbles:" + url, password)
            self.settings["bluebubbles"] = {"url": url}
            self.settings["password_store"] = where
        self.settings["welcomed"] = True
        store.save_settings(self.settings)
        self.start_backends()
        self.sync_autostart()
        self._changed_status()
        window = self.window()
        if window:
            window.root.set_visible_child_name("main")
            window.refresh()

    def set_phone(self, on):
        phone = self.settings.setdefault("phone", {})
        if bool(phone.get("on")) == bool(on):
            return
        phone["on"] = bool(on)
        self.settings["welcomed"] = True
        store.save_settings(self.settings)
        if on:
            self.start_backends()
        else:
            self.stop_backend("kdeconnect")
        self.sync_autostart()
        self.phone_firewall(bool(on))
        window = self.window()
        if window:
            window.root.set_visible_child_name("main")

    def add_phone_address(self, host):
        phone = self.settings.setdefault("phone", {})
        found = phone.setdefault("addresses", [])
        if host not in found:
            found.append(host)
        store.save_settings(self.settings)
        backend = self.backends.get("kdeconnect")
        if backend:
            backend.add_address(host)

    def refresh(self):
        for backend in self.backends.values():
            backend.refresh()

    def opened(self, chat):
        """A conversation came on screen: mark it read and fetch its messages."""
        self.read(chat)
        backend = self.backends.get(chat.backend)
        if backend is not None and not chat.id.startswith("new:"):
            try:
                backend.load_conversation(chat)
            except (OSError, ConnectionError, ValueError):
                pass
        self.fetch_pictures(chat)

    def fetch_pictures(self, chat, newest=30, largest=25 * 1024 * 1024):
        """Fetches the pictures of a BlueBubbles conversation's newest messages,
        to show in their bubbles. The phone sends its own thumbnails, so its
        pictures wait for a click."""
        backend = self.backends.get(chat.backend)
        if backend is None or chat.backend != "bluebubbles":
            return
        for message in self.store.messages(chat.id)[-newest:]:
            if message.id.startswith("tmp:"):
                continue
            for a in message.attachments:
                if not is_picture(a) or a.get("thumbnail") or a.get("id") in self.fetching or \
                        (a.get("path") and os.path.exists(a["path"])) or (a.get("size") or 0) > largest:
                    continue
                self.fetching.add(a.get("id"))
                try:
                    backend.download(message.id, a)
                except (OSError, ConnectionError):
                    self.fetching.discard(a.get("id"))

    def read(self, chat):
        if chat is None:
            return
        found = self.store.chat(chat.id)
        if found and found.unread:
            self.store.mark_read(chat.id)
            backend = self.backends.get(chat.backend)
            if hasattr(backend, "mark_read"):
                backend.mark_read(found)
            self.badge()
            window = self.window()
            if window:
                window.fill_list()
            self.withdraw_notification("chat-" + chat.id)

    # -- sending -----------------------------------------------------------------------
    def _pending(self, chat_id, text, service, files=()):
        from .messages_bluebubbles import new_temp_id
        attachments = [{"id": f"local:{uuid.uuid4().hex[:12]}", "name": os.path.basename(path),
                        "mime": mime_of(path), "path": path} for path in files]
        message = store.Message(id=new_temp_id(), chat_id=chat_id, text=text, date=store.now_ms(), from_me=True,
                                service=service, status="sending", attachments=attachments)
        self.store.upsert_messages([message])
        return message

    def _send_to_phone(self, backend, addresses, text, files, message):
        try:
            if files:
                backend.send(addresses, text, attachments=list(files))
            else:
                backend.send(addresses, text)
            self.store.set_status(message.id, "sent")
        except (OSError, ConnectionError) as e:
            self.store.set_status(message.id, "failed")
            self.tell(str(e))

    def send(self, chat, text, files=()):
        """Words and files into a conversation: through BlueBubbles each file is
        a message of its own, then the words; through the phone one MMS."""
        backend = self.backends.get(chat.backend)
        if chat.backend == "bluebubbles":
            pending = [(self._pending(chat.id, "", chat.service, [path]), path) for path in files]
            if text:
                pending.append((self._pending(chat.id, text, chat.service), None))
            for message, path in pending:
                if backend is None:
                    self.store.set_status(message.id, "failed")
                elif path:
                    backend.send_attachment(chat, path, message.id, mime_of(path))
                else:
                    backend.send_to_chat(chat, text, message.id)
            return chat.id
        message = self._pending(chat.id, text, chat.service, files)
        if backend is None:
            self.store.set_status(message.id, "failed")
        else:
            self._send_to_phone(backend, chat.addresses, text, files, message)
        return chat.id

    def send_new(self, kind, addresses, text, files=()):
        kind = kind or (self.available() or ["bluebubbles"])[0]
        existing = self.store.find_chat(kind, addresses)
        if existing:
            return self.send(existing, text, files)
        if kind == "bluebubbles":
            files = ()          # chat/new takes words only; files go in once it exists
        if not text and not files:
            return None
        from .messages_bluebubbles import new_temp_id
        chat = store.Chat(id="new:" + new_temp_id()[4:], backend=kind,
                          title=", ".join(self.names.get(store.normalise_address(a)) or store.format_address(a)
                                          for a in addresses),
                          addresses=list(addresses), service="imessage" if kind == "bluebubbles" else "sms",
                          last_date=store.now_ms(), last_text=text)
        self.store.upsert_chats([chat])
        message = self._pending(chat.id, text, chat.service, files)
        backend = self.backends.get(kind)
        if backend is None:
            self.store.set_status(message.id, "failed")
            self.tell("Set up Messages first: choose Messages > Settings…")
        elif kind == "bluebubbles":
            backend.send_new(addresses, text, message.id)
        else:
            self.pending_new[self._key(addresses)] = chat.id
            self._send_to_phone(backend, addresses, text, files, message)
        return chat.id

    @staticmethod
    def _key(addresses):
        return tuple(sorted(store.normalise_address(a) for a in addresses))

    # -- what backends say (on the main loop) --------------------------------------------
    def backend_status(self, kind, text, connected):
        if kind in self.backends:
            self.status[kind] = (text, connected)
            self._changed_status()

    def _changed_status(self):
        window = self.window()
        if window:
            window.update_status()
        if self.settings_window:
            self.settings_window.refresh()

    def backend_devices(self, kind, devices):
        self.devices = devices
        if self.settings_window:
            self.settings_window.refresh()

    def backend_data(self, kind, chats, messages):
        self.store.upsert_chats(chats)
        window = self.window()
        # A new conversation started here has come back with its own id.
        moved = {}
        for chat in chats:
            placeholder = self.pending_new.pop(self._key(chat.addresses), None)
            if placeholder:
                self.store.delete_chat(placeholder)
                moved[placeholder] = chat.id
        fresh = self.store.upsert_messages(messages)
        changed = {m.chat_id for m in messages} | {c.id for c in chats}
        for m in fresh:          # a message from them ends their "…"
            if isinstance(m, store.Message) and not m.from_me:
                self.typing.pop(m.chat_id, None)
        if window:
            if window.current and window.current.id in moved:
                window.select_chat(moved[window.current.id])
            # A conversation on show in the window in front is read as it comes.
            if window.current and window.is_active() and window.current.id in changed:
                self.store.mark_read(window.current.id)
            window.refresh(changed)
            if window.current and window.current.id in changed:
                self.fetch_pictures(window.current)
        self.notify(fresh, window)
        self.badge()

    def notify(self, fresh, window=None):
        now = store.now_ms()
        for m in fresh:
            reaction = isinstance(m, store.Reaction)
            if m.from_me or (not reaction and m.read) or now - m.date > NOTIFY_WITHIN_MS:
                continue
            if window and window.is_active() and window.current and window.current.id == m.chat_id:
                continue
            chat = self.store.chat(m.chat_id)
            note = Gio.Notification.new(chat.title if chat and chat.title else store.format_address(m.sender))
            if reaction:
                note.set_body(reaction_line(m, self.store.message(m.target)))
            else:
                note.set_body(m.text or store.attachment_summary(m) or "New message")
            note.set_icon(Gio.ThemedIcon.new("freemac-messages"))
            note.set_default_action_and_target("app.open-chat", GLib.Variant("s", m.chat_id))
            self.send_notification("chat-" + m.chat_id, note)

    def badge(self):
        try:
            launcher_badge.set_count(DESKTOP_ID, self.store.unread_total())
        except Exception:   # noqa: BLE001 - no session bus
            pass

    def backend_sent(self, kind, temp_id, message, error, chat_id=""):
        """A message we sent: the backend's copy (message), or the conversation
        it went to with no copy yet (chat_id), or what went wrong (error)."""
        pending = self.store.message(temp_id)
        window = self.window()
        if error or (message is None and not chat_id):
            self.store.set_status(temp_id, "failed")
            if error and error != "Not Delivered":
                self.tell(f"The message couldn't be sent. {error}")
        elif pending is not None:
            started_in = pending.chat_id
            target = message.chat_id if message is not None else chat_id
            if message is None:
                pending.chat_id, pending.status = target, "sent"
                message = pending
            # The file we sent is here already: its picture shows at once.
            for mine, theirs in zip(pending.attachments, message.attachments):
                if mine.get("path") and not theirs.get("path"):
                    theirs["path"] = mine["path"]
            self.store.replace_message(temp_id, message)
            if started_in != target and started_in.startswith("new:"):
                # The first message of a new conversation: it has its own id now.
                self.store.delete_chat(started_in)
                if window and window.current and window.current.id == started_in:
                    window.select_chat(target)
        elif message is not None:
            self.store.upsert_messages([message])
        if window:
            window.refresh()

    def backend_attachment(self, kind, message_id, attachment_id, path):
        if message_id:
            self.store.set_attachment_path(message_id, attachment_id, path)
        if attachment_id in self.fetching:
            # Fetched to show in its bubble, not asked for with a click.
            self.fetching.discard(attachment_id)
            window = self.window()
            if window:
                window.refresh()
            return
        try:
            Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(path).get_uri(), None)
        except GLib.Error:
            pass

    def backend_typing(self, kind, chat_id, on):
        if on:
            self.typing[chat_id] = store.now_ms() + TYPING_FOR_MS
            GLib.timeout_add(TYPING_FOR_MS + 500, self._typing_expired, chat_id)
        else:
            self.typing.pop(chat_id, None)
        window = self.window()
        if window and window.current and window.current.id == chat_id:
            window.fill_bubbles()

    def _typing_expired(self, chat_id):
        if chat_id in self.typing and not self.is_typing(chat_id):
            self.backend_typing(None, chat_id, False)
        return False

    def is_typing(self, chat_id):
        return self.typing.get(chat_id, 0) > store.now_ms()

    def backend_error(self, kind, text):
        self.tell(text)

    # -- tapbacks --------------------------------------------------------------------
    def can_react(self, message):
        """Only BlueBubbles' messages, once the server's Private API is on."""
        backend = self.backends.get("bluebubbles")
        return (backend is not None and message.id.startswith("bb:") and bool(message.remote_id)
                and hasattr(backend, "can_react") and backend.can_react())

    def react(self, message, kind):
        """Adds a tapback; choosing the one you already put takes it back."""
        chat = self.store.chat(message.chat_id)
        backend = self.backends.get("bluebubbles")
        if chat is None or backend is None:
            return
        try:
            backend.react(chat, message, kind, remove=self.store.my_reaction(message.id) == kind)
        except (ConnectionError, ValueError) as e:
            self.tell(str(e))

    def open_attachment(self, message, attachment):
        path = attachment.get("path")
        if path and os.path.exists(path):
            self.backend_attachment(None, "", "", path)
            return
        backend = self.backends.get("bluebubbles" if message.id.startswith("bb:") else "kdeconnect")
        try:
            if backend is None:
                raise ConnectionError("Messages isn't connected right now.")
            if message.id.startswith("bb:"):
                backend.download(message.id, attachment)
            else:
                backend.request_attachment(message, attachment)
        except (OSError, ConnectionError) as e:
            self.tell(str(e))

    # -- pairing a phone ---------------------------------------------------------------------
    def pair(self, device_id, name):
        backend = self.backends.get("kdeconnect")
        if backend is None:
            return
        try:
            code = backend.pair(device_id)
        except (OSError, ConnectionError) as e:
            self.tell(str(e))
            return
        self._pair_dialog(f"Pairing with “{name}”",
                          f"Accept the request on your phone. Check that it shows this code: {spaced(code)}",
                          ("Cancel",), None)

    def backend_pair_request(self, kind, device_id, name, code):
        backend = self.backends.get("kdeconnect")

        def answer(response):
            if backend:
                backend.accept_pair(device_id, response == "Pair")
        self._pair_dialog(f"“{name}” wants to pair with this computer",
                          f"Pair only if the phone shows the same code: {spaced(code)}",
                          ("Not Now", "Pair"), answer)

    def backend_paired(self, kind, device_id, name, ok):
        if self.pair_dialog is not None:
            self.pair_dialog.destroy()
            self.pair_dialog = None
        if not ok:
            self.tell(f"“{name}” isn't paired.")
        if self.settings_window:
            self.settings_window.refresh()

    def _pair_dialog(self, text, secondary, buttons, answer):
        if self.pair_dialog is not None:
            self.pair_dialog.destroy()
        parent = self.settings_window or self.window()
        dialog = Gtk.MessageDialog(transient_for=parent, modal=True, message_type=Gtk.MessageType.QUESTION,
                                   text=text, secondary_text=secondary)
        for i, label in enumerate(buttons):
            dialog.add_button(label, i)

        def respond(d, response):
            if answer and response >= 0:
                answer(buttons[response])
            d.destroy()
            if self.pair_dialog is d:
                self.pair_dialog = None
        dialog.connect("response", respond)
        dialog.show()
        self.pair_dialog = dialog

    def unpair(self, device_id):
        backend = self.backends.get("kdeconnect")
        if backend:
            backend.unpair(device_id)

    # -- the rest -------------------------------------------------------------------------
    def show_settings(self, page=None):
        if self.settings_window is None:
            self.settings_window = Settings(self, self.window(), page)
            self.settings_window.connect("destroy", lambda *_: setattr(self, "settings_window", None))
        self.settings_window.present()

    def tell(self, text):
        window = self.window()
        if window is None:
            return
        dialog = Gtk.MessageDialog(transient_for=window, modal=True, message_type=Gtk.MessageType.WARNING,
                                   buttons=Gtk.ButtonsType.OK, text=text)
        dialog.connect("response", lambda d, _r: d.destroy())
        dialog.show()


def spaced(code):
    return f"{code[:4]} {code[4:]}" if len(code) == 8 else code


def main():
    return Messages().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
