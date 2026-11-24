# SPDX-License-Identifier: GPL-3.0-or-later
"""Messages' window: the first-run page, the conversation list, bubbles and
their layout, sending, new conversations, notifications' counts, and the app
end to end against a stand-in BlueBubbles server and a stand-in kdeconnectd
on a private session bus. Run headless with

    xvfb-run -a python3 -m unittest discover -s shell/tests
"""
import os
import shutil
import tempfile
import time
import unittest

from messages_fakes import FakeBlueBubbles, Recorder

try:
    import gi

    gi.require_version("Gtk", "3.0")
    from gi.repository import Gio, GLib, Gtk
except (ImportError, ValueError):
    raise unittest.SkipTest("needs GTK 3 through gi")

from freemac_shell import messages_store as store  # noqa: E402
from freemac_shell.messages_store import Chat, Message  # noqa: E402

HOUR = 3_600_000


def pump(until=None, seconds=3.0):
    """Run GTK's main loop until until() is true (or for a moment)."""
    end = time.monotonic() + seconds
    context = GLib.MainContext.default()
    while time.monotonic() < end:
        while context.pending():
            context.iteration(False)
        if until is not None and until():
            return True
        time.sleep(0.01)
    return until() if until else True


def texts(widget):
    """Every label's text under widget, in order."""
    found = []
    if isinstance(widget, Gtk.Label):
        found.append(widget.get_text())
    if isinstance(widget, Gtk.Container):
        for child in widget.get_children():
            found += texts(child)
    return found


def classes(widget):
    return set(widget.get_style_context().list_classes())


class Layout(unittest.TestCase):
    """The pure part: what a conversation shows, in what order."""

    def setUp(self):
        from freemac_shell import messages
        self.m = messages
        self.now = int(time.time() * 1000)

    def msg(self, i, minutes_ago, from_me=False, status="received", sender="+15550100001", **kw):
        return Message(id=f"x{i}", chat_id="c", text=f"message {i}", date=self.now - minutes_ago * 60_000,
                       from_me=from_me, sender="" if from_me else sender, status=status, **kw)

    def test_time_lines_tails_and_status(self):
        items = self.m.layout([
            self.msg(1, 120), self.msg(2, 119),
            self.msg(3, 118, from_me=True, status="delivered"),
            self.msg(4, 30, from_me=True, status="read", status_date=self.now - 60_000),
        ], now=self.now)
        kinds = [i[0] for i in items]
        self.assertEqual(kinds, ["time", "bubble", "bubble", "bubble", "time", "bubble", "status"])
        tails = [i[2] for i in items if i[0] == "bubble"]
        self.assertEqual(tails, [False, True, True, True])
        self.assertTrue(items[0][1].startswith("Today "))
        self.assertTrue(items[-1][1].startswith("Read "))

    def test_failed_and_sending(self):
        items = self.m.layout([self.msg(1, 10, from_me=True, status="failed"),
                               self.msg(2, 9, from_me=True, status="sending")], now=self.now)
        statuses = [i[1:] for i in items if i[0] == "status"]
        self.assertEqual(statuses, [("Not Delivered", True), ("Sending…", False)])

    def test_group_senders(self):
        items = self.m.layout([self.msg(1, 5, sender="+15550100001"), self.msg(2, 4, sender="+15550100001"),
                               self.msg(3, 3, sender="+15550100002")], group=True, now=self.now)
        self.assertEqual([i[1] for i in items if i[0] == "sender"], ["+15550100001", "+15550100002"])

    def test_days(self):
        day = 86_400_000
        self.assertTrue(self.m.time_line(self.now - day, self.now).startswith("Yesterday"))
        self.assertIn(" at ", self.m.time_line(self.now - 30 * day, self.now))
        self.assertEqual(self.m.list_time(0), "")

    def test_jumbo_emoji(self):
        self.assertTrue(self.m.is_jumbo("😀"))
        self.assertTrue(self.m.is_jumbo("🎉🎉"))
        self.assertFalse(self.m.is_jumbo("ok 😀"))
        self.assertFalse(self.m.is_jumbo("😀😀😀😀"))

    def test_addresses_from_names(self):
        book = {"Rosa Marin": "+1 555 010 0001"}
        self.assertEqual(self.m.split_addresses("rosa marin, +1 555 010 0009", book),
                         ["+1 555 010 0001", "+1 555 010 0009"])


# -- a fake kdeconnectd on the private bus -------------------------------------------------
DAEMON_XML = """
<node>
  <interface name="org.kde.kdeconnect.daemon">
    <method name="devices"><arg type="b" direction="in"/><arg type="b" direction="in"/>
      <arg type="as" direction="out"/></method>
  </interface>
</node>"""
DEVICE_XML = """
<node>
  <interface name="org.kde.kdeconnect.device">
    <property name="name" type="s" access="read"/>
  </interface>
  <interface name="org.kde.kdeconnect.device.conversations">
    <method name="activeConversations"><arg type="av" direction="out"/></method>
    <method name="requestAllConversationThreads"/>
    <method name="requestConversation"><arg type="x" direction="in"/><arg type="i" direction="in"/>
      <arg type="i" direction="in"/></method>
    <method name="sendWithoutConversation"><arg type="av" direction="in"/><arg type="s" direction="in"/>
      <arg type="av" direction="in"/></method>
    <signal name="conversationCreated"><arg type="v"/></signal>
  </interface>
</node>"""
STRUCT = "(isa(s)xiixixa(xsss))"


class FakeDaemon:
    def __init__(self, address):
        self.bus = Gio.DBusConnection.new_for_address_sync(
            address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
            | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
        self.sent = []
        self.files = []
        self.path = "/modules/kdeconnect/devices/abc123"
        daemon = Gio.DBusNodeInfo.new_for_xml(DAEMON_XML)
        device = Gio.DBusNodeInfo.new_for_xml(DEVICE_XML)
        self.regs = [
            self.bus.register_object("/modules/kdeconnect", daemon.interfaces[0], self._daemon, None, None),
            self.bus.register_object(self.path, device.interfaces[0], None, self._property, None),
            self.bus.register_object(self.path, device.interfaces[1], self._conversations, None, None),
        ]
        self.bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                           "RequestName", GLib.Variant("(su)", ("org.kde.kdeconnect", 0)), None, 0, 2000, None)

    @staticmethod
    def message(uid, thread, body, address, date, kind=1):
        return GLib.Variant(STRUCT, (1, body, [(address,)], date, kind, 0, thread, uid, 1, []))

    def _daemon(self, _bus, _sender, _path, _iface, method, _params, invocation):
        invocation.return_value(GLib.Variant("(as)", (["abc123"],)))

    def _property(self, _bus, _sender, _path, _iface, name):
        return GLib.Variant("s", "Pixel Daemon") if name == "name" else None

    def _conversations(self, _bus, _sender, _path, _iface, method, params, invocation):
        if method == "activeConversations":
            now = int(time.time() * 1000)
            found = [GLib.Variant("v", self.message(1, 31, "Ferry tickets are booked", "+15550100031", now - HOUR))]
            invocation.return_value(GLib.Variant("(av)", (found,)))
        elif method == "sendWithoutConversation":
            addresses, text, files = params.unpack()
            self.sent.append((addresses, text))
            self.files.append(files)
            invocation.return_value(None)
        else:
            invocation.return_value(None)

    def text_arrives(self, body):
        message = self.message(2, 31, body, "+15550100031", int(time.time() * 1000))
        self.bus.emit_signal(None, self.path, "org.kde.kdeconnect.device.conversations", "conversationCreated",
                             GLib.Variant("(v)", (message,)))

    def close(self):
        for reg in self.regs:
            self.bus.unregister_object(reg)
        self.bus.close_sync(None)


@unittest.skipUnless(GLib.find_program_in_path("dbus-daemon"), "needs dbus-daemon for a private bus")
class WindowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.home = tempfile.mkdtemp()
        cls.saved = {k: os.environ.get(k) for k in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME",
                                                     "DBUS_SESSION_BUS_ADDRESS")}
        cls.test_bus = Gio.TestDBus.new(Gio.TestDBusFlags.NONE)
        cls.test_bus.up()      # sets DBUS_SESSION_BUS_ADDRESS
        if not Gtk.init_check()[0]:
            raise unittest.SkipTest("needs a display (run under xvfb-run)")
        store.KEYRING = False
        from freemac_shell import messages
        from freemac_shell import messages_firewall as firewall
        # The firewall Messages sees is made up, in the test's own folder.
        cls.firewall = firewall
        cls.saved_firewall = (firewall.UFW_CONF, firewall.MARK, firewall.available)
        firewall.UFW_CONF = os.path.join(cls.home, "ufw.conf")
        firewall.MARK = os.path.join(cls.home, "kde-connect")
        cls.use_home(os.path.join(cls.home, "first"))
        # One app for every test: a process has one session bus connection,
        # where an app's actions can be exported once.
        cls.app = messages.Messages()
        cls.app.set_flags(Gio.ApplicationFlags.NON_UNIQUE)
        cls.app.register(None)

    @staticmethod
    def use_home(folder):
        os.environ["XDG_DATA_HOME"] = os.path.join(folder, "data")
        os.environ["XDG_CONFIG_HOME"] = os.path.join(folder, "config")
        os.environ["XDG_STATE_HOME"] = os.path.join(folder, "state")

    @classmethod
    def tearDownClass(cls):
        # stop(), not down(): the app keeps its bus connection to the end of
        # the process, and down() would wait 30 seconds for it to go.
        cls.test_bus.stop()
        cls.firewall.UFW_CONF, cls.firewall.MARK, cls.firewall.available = cls.saved_firewall
        for k, v in cls.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        shutil.rmtree(cls.home, ignore_errors=True)

    def setUp(self):
        from freemac_shell import messages
        self.messages = messages
        self.dir = tempfile.mkdtemp(dir=self.home)
        self.use_home(self.dir)
        app = self.app
        app.store.close()
        app.backends, app.status, app.devices, app.pending_new = {}, {}, [], {}
        app.typing, app.fetching, app.firewall_busy = {}, set(), False
        app.setup()          # a fresh store and settings in this test's own folders
        self.servers = []
        for path in (self.firewall.UFW_CONF, self.firewall.MARK):
            if os.path.exists(path):
                os.remove(path)

    def tearDown(self):
        for window in self.app.get_windows():
            window.destroy()
        for backend in self.app.backends.values():
            backend.stop()
        self.app.backends = {}
        if self.app.settings_window:
            self.app.settings_window.destroy()
        for server in self.servers:
            server.close()
        pump(seconds=0.05)
        shutil.rmtree(self.dir, ignore_errors=True)

    def seed(self):
        now = int(time.time() * 1000)
        s = self.app.store
        s.upsert_chats([
            Chat(id="bb:iMessage;-;+15550100001", backend="bluebubbles", title="Rosa Marin",
                 addresses=["+15550100001"], service="imessage", remote_id="iMessage;-;+15550100001"),
            Chat(id="kdc:p:4", backend="kdeconnect", title="Sam Okafor", addresses=["+15550100002"],
                 remote_id="4"),
        ])
        s.upsert_messages([
            Message(id="bb:1", chat_id="bb:iMessage;-;+15550100001", text="Are we still on for the pier?",
                    date=now - 2 * HOUR, sender="+15550100001", service="imessage"),
            Message(id="bb:2", chat_id="bb:iMessage;-;+15550100001", text="Yes! See you at noon",
                    date=now - 2 * HOUR + 60_000, from_me=True, service="imessage", status="read",
                    status_date=now - HOUR),
            Message(id="kdc:p:1:1", chat_id="kdc:p:4", text="The ferry leaves at six", date=now - 3 * HOUR,
                    sender="+15550100002", read=False),
        ])
        self.app.settings["welcomed"] = True

    # -- first run -----------------------------------------------------------------------
    def test_first_run_explains_both_ways(self):
        window = self.messages.Window(self.app)
        self.assertEqual(window.root.get_visible_child_name(), "welcome")
        words = " ".join(texts(window.root.get_child_by_name("welcome")))
        self.assertIn("Real iMessage needs a Mac", words)
        self.assertIn("BlueBubbles", words)
        self.assertIn("An iPhone can't send texts through KDE Connect", words)
        self.assertIn("Connect to BlueBubbles…", words)
        self.assertIn("Pair an Android Phone…", words)
        window.leave_welcome()
        self.assertEqual(window.root.get_visible_child_name(), "main")
        self.assertTrue(store.load_settings()["welcomed"])

    # -- the list and the bubbles ------------------------------------------------------------
    def test_list_and_search(self):
        self.seed()
        window = self.messages.Window(self.app)
        self.assertEqual(window.root.get_visible_child_name(), "main")
        self.assertEqual([r.chat.title for r in window.rows()], ["Rosa Marin", "Sam Okafor"])
        sam = window.rows()[1]
        self.assertIn("●", texts(sam))           # unread
        window.search.set_text("ferry")
        pump(lambda: len(window.rows()) == 1)
        self.assertEqual([r.chat.title for r in window.rows()], ["Sam Okafor"])
        window.search.set_text("")
        pump(lambda: len(window.rows()) == 2)

    def test_bubbles(self):
        self.seed()
        window = self.messages.Window(self.app)
        window.select_chat("bb:iMessage;-;+15550100001")
        self.assertEqual(window.pane.get_visible_child_name(), "chat")
        self.assertEqual(window.title.get_text(), "Rosa Marin")
        self.assertEqual(window.subtitle.get_text(), "iMessage through BlueBubbles")
        self.assertEqual(window.entry.get_placeholder_text(), "iMessage")
        rows = [w for w in window.bubbles.get_children() if hasattr(w, "bubble")]
        theirs, mine = rows
        self.assertEqual(theirs.get_halign(), Gtk.Align.START)
        self.assertEqual(mine.get_halign(), Gtk.Align.END)
        self.assertTrue({"msg-bubble", "them", "tail"} <= classes(theirs.bubble))
        self.assertTrue({"msg-bubble", "mine", "imessage", "tail"} <= classes(mine.bubble))
        words = texts(window.bubbles)
        self.assertTrue(words[0].startswith("Today ") or words[0].startswith("Yesterday "))
        self.assertTrue(words[-1].startswith("Read "))
        # A text conversation is green, and opening it reads it.
        window.select_chat("kdc:p:4")
        self.assertEqual(window.subtitle.get_text(), "Text Message through your phone")
        self.assertEqual(self.app.store.chat("kdc:p:4").unread, 0)
        self.assertEqual(self.app.store.unread_total(), 0)

    def test_sms_bubble_is_green(self):
        self.seed()
        self.app.store.upsert_messages([Message(id="kdc:p:2:2", chat_id="kdc:p:4", text="Sounds good",
                                                date=int(time.time() * 1000), from_me=True, status="sent")])
        window = self.messages.Window(self.app)
        window.select_chat("kdc:p:4")
        mine = [w for w in window.bubbles.get_children() if hasattr(w, "bubble")][-1]
        self.assertIn("sms", classes(mine.bubble))
        self.assertIn("Sent", texts(window.bubbles))

    def test_emoji_button_opens_the_picker(self):
        self.seed()
        window = self.messages.Window(self.app)
        window.select_chat("kdc:p:4")
        from gi.repository import GObject
        self.assertTrue(GObject.signal_lookup("insert-emoji", Gtk.Entry))
        window.pick_emoji()          # GtkEntry's own emoji chooser
        pump(seconds=0.1)

    # -- sending -----------------------------------------------------------------------------
    def test_send_into_a_conversation(self):
        self.seed()
        fake = Recorder()
        fake.send_to_chat = lambda chat, text, temp: fake.calls.append(("send_to_chat", (chat.id, text, temp)))
        fake.load_conversation = lambda *a: None
        fake.mark_read = lambda *a: None
        fake.stop = lambda: None
        self.app.backends["bluebubbles"] = fake
        window = self.messages.Window(self.app)
        window.select_chat("bb:iMessage;-;+15550100001")
        window.entry.set_text("Running five minutes late")
        self.assertTrue(window.send_button.get_sensitive())
        window.send()
        self.assertEqual(window.entry.get_text(), "")
        _name, (chat_id, text, temp) = fake.calls[-1]
        self.assertEqual((chat_id, text), ("bb:iMessage;-;+15550100001", "Running five minutes late"))
        self.assertEqual(self.app.store.message(temp).status, "sending")
        self.assertIn("Sending…", texts(window.bubbles))
        # The server's copy takes its place.
        real = Message(id="bb:99", chat_id=chat_id, text=text, date=int(time.time() * 1000), from_me=True,
                       service="imessage", status="delivered", status_date=int(time.time() * 1000))
        self.app.backend_sent("bluebubbles", temp, real, "", chat_id)
        self.assertIsNone(self.app.store.message(temp))
        self.assertIn("Delivered", texts(window.bubbles))

    def test_failed_send_says_so(self):
        self.seed()
        window = self.messages.Window(self.app)
        window.select_chat("kdc:p:4")      # no phone backend running
        window.entry.set_text("hello?")
        window.send()
        self.assertIn("Not Delivered", texts(window.bubbles))

    def test_new_text_conversation(self):
        self.seed()
        sent = []
        fake = Recorder()
        fake.send = lambda addresses, text: sent.append((addresses, text))
        fake.load_conversation = lambda *a: None
        fake.stop = lambda: None
        self.app.backends["kdeconnect"] = fake
        window = self.messages.Window(self.app)
        window.new_message()
        self.assertTrue(window.to_bar.get_visible())
        self.assertFalse(window.send_as.get_visible())      # only one way to send
        self.assertEqual(window.send_as.get_active_id(), "kdeconnect")
        window.to.set_text("+1 555 010 0077")
        window.entry.set_text("Hi, it's Alex from the sailing club")
        window.send()
        self.assertEqual(sent, [(["+1 555 010 0077"], "Hi, it's Alex from the sailing club")])
        placeholder = window.current.id
        self.assertTrue(placeholder.startswith("new:"))
        # The phone tells us about its new thread: the placeholder goes.
        now = int(time.time() * 1000)
        self.app.backend_data("kdeconnect",
                              [Chat(id="kdc:p:50", backend="kdeconnect", title="(555) 010-0077",
                                    addresses=["+15550100077"], remote_id="50", last_date=now)],
                              [Message(id="kdc:p:7:1", chat_id="kdc:p:50", text="Hi, it's Alex from the sailing club",
                                       date=now, from_me=True, status="sent")])
        self.assertIsNone(self.app.store.chat(placeholder))
        self.assertEqual(window.current.id, "kdc:p:50")

    def test_incoming_counts_and_notifies(self):
        self.seed()
        window = self.messages.Window(self.app)
        notes = []
        self.app.send_notification = lambda key, note: notes.append(key)
        now = int(time.time() * 1000)
        self.app.backend_data("kdeconnect", [], [
            Message(id="kdc:p:3:3", chat_id="kdc:p:4", text="Running late?", date=now, sender="+15550100002",
                    read=False),
            Message(id="kdc:p:0:0", chat_id="kdc:p:4", text="old news", date=now - 5 * HOUR,
                    sender="+15550100002", read=False)])
        self.assertEqual(notes, ["chat-kdc:p:4"])          # the old one doesn't pop up
        self.assertEqual(self.app.store.unread_total(), 3)
        self.assertEqual(window.rows()[0].chat.id, "kdc:p:4")

    def test_settings_window(self):
        self.seed()
        self.app.devices = [{"id": "d1", "name": "Pixel Test", "paired": False, "connected": True}]
        self.app.settings["phone"] = {"on": True}
        self.app.show_settings("kdeconnect")
        dialog = self.app.settings_window
        words = " ".join(texts(dialog))
        self.assertIn("Pixel Test", words)
        self.assertIn("Pair…", [b.get_label() for b in walk(dialog) if isinstance(b, Gtk.Button)])
        self.assertIn("An iPhone can't send texts this way", words)
        dialog.destroy()

    # -- tapbacks ------------------------------------------------------------------------------
    def bb_stub(self, can_react=False):
        """A BlueBubbles backend that only writes down what it's asked."""
        fake = Recorder()
        for name in ("send_to_chat", "send_attachment", "react", "download"):
            setattr(fake, name, (lambda n: lambda *a, **kw: fake.calls.append((n, a, kw)))(name))
        fake.load_conversation = lambda *a: None
        fake.mark_read = lambda *a: None
        fake.stop = lambda: None
        fake.can_react = lambda: can_react
        self.app.backends["bluebubbles"] = fake
        return fake

    def calls(self, fake, name):
        return [c[1:] for c in fake.calls if c[0] == name]

    def test_tapbacks_on_bubbles(self):
        self.seed()
        now = int(time.time() * 1000)
        self.app.backend_data("bluebubbles", [], [
            store.Reaction(id="bb:t1", chat_id="bb:iMessage;-;+15550100001", target="bb:1", kind="love",
                           sender="+15550100001", date=now - HOUR),
            store.Reaction(id="bb:t2", chat_id="bb:iMessage;-;+15550100001", target="bb:2", kind="laugh",
                           sender="+15550100001", date=now - HOUR),
            store.Reaction(id="bb:t3", chat_id="bb:iMessage;-;+15550100001", target="bb:1", kind="love",
                           from_me=True, date=now - HOUR)])
        window = self.messages.Window(self.app)
        window.select_chat("bb:iMessage;-;+15550100001")
        theirs, mine = [w for w in window.bubbles.get_children() if hasattr(w, "bubble")]
        self.assertEqual(theirs.tapbacks.get_text(), "❤️ 2")
        self.assertIn("mine-too", classes(theirs.tapbacks))          # one of them is mine
        self.assertEqual(theirs.tapbacks.get_halign(), Gtk.Align.END)  # toward the middle
        self.assertEqual(mine.tapbacks.get_text(), "😂")
        self.assertEqual(mine.tapbacks.get_halign(), Gtk.Align.START)
        # Taking one back takes it off the bubble.
        self.app.backend_data("bluebubbles", [], [
            store.Reaction(id="bb:t4", chat_id="bb:iMessage;-;+15550100001", target="bb:2", kind="",
                           sender="+15550100001", date=now)])
        mine = [w for w in window.bubbles.get_children() if hasattr(w, "bubble")][1]
        self.assertIsNone(mine.tapbacks)

    def test_tapback_menu_only_with_the_private_api(self):
        self.seed()
        self.bb_stub(can_react=False)
        window = self.messages.Window(self.app)
        window.select_chat("bb:iMessage;-;+15550100001")
        message = self.app.store.message("bb:1")
        message.remote_id = "1"
        menu = window.bubble_menu(message)
        self.assertEqual([i.get_label() for i in menu.get_children()], ["Copy"])
        self.assertEqual(menu.reactions, {})
        # A text from the phone has no tapbacks either way.
        self.bb_stub(can_react=True)
        self.assertEqual(window.bubble_menu(self.app.store.message("kdc:p:1:1")).reactions, {})

    def test_adding_and_taking_back_a_tapback(self):
        self.seed()
        fake = self.bb_stub(can_react=True)
        window = self.messages.Window(self.app)
        window.select_chat("bb:iMessage;-;+15550100001")
        self.app.store.upsert_messages([Message(id="bb:1", chat_id="bb:iMessage;-;+15550100001", remote_id="1",
                                                text="Are we still on for the pier?", sender="+15550100001",
                                                date=int(time.time() * 1000) - 2 * HOUR, service="imessage")])
        message = self.app.store.message("bb:1")
        menu = window.bubble_menu(message)
        self.assertEqual(list(menu.reactions), ["love", "like", "dislike", "laugh", "emphasize", "question"])
        self.assertIn("Love", menu.reactions["love"].get_label())
        menu.reactions["like"].activate()
        chat, target, kind = self.calls(fake, "react")[-1][0]
        self.assertEqual((chat.id, target.id, kind, self.calls(fake, "react")[-1][1]),
                         ("bb:iMessage;-;+15550100001", "bb:1", "like", {"remove": False}))
        # The server's copy comes back; the menu then shows it ticked, and choosing it again takes it back.
        self.app.backend_data("bluebubbles", [], [store.Reaction(
            id="bb:t5", chat_id="bb:iMessage;-;+15550100001", target="bb:1", kind="like", from_me=True,
            date=int(time.time() * 1000))])
        menu = window.bubble_menu(message)
        self.assertTrue(menu.reactions["like"].get_active())
        self.assertFalse(menu.reactions["love"].get_active())
        menu.reactions["like"].activate()
        self.assertEqual(self.calls(fake, "react")[-1][1], {"remove": True})

    def test_someone_reacting_is_a_notification(self):
        self.seed()
        notes = []
        self.app.send_notification = lambda key, note: notes.append(key)
        self.app.backend_data("bluebubbles", [], [store.Reaction(
            id="bb:t6", chat_id="bb:iMessage;-;+15550100001", target="bb:2", kind="love",
            sender="+15550100001", date=int(time.time() * 1000))])
        self.assertEqual(notes, ["chat-bb:iMessage;-;+15550100001"])
        line = self.messages.reaction_line(store.Reaction(id="x", chat_id="c", target="bb:2", kind="love"),
                                           self.app.store.message("bb:2"))
        self.assertEqual(line, "Loved “Yes! See you at noon”")

    # -- typing ---------------------------------------------------------------------------------
    def test_typing_bubble(self):
        self.seed()
        window = self.messages.Window(self.app)
        window.select_chat("bb:iMessage;-;+15550100001")
        typing = lambda: [w for w in window.bubbles.get_children() if getattr(w, "typing", False)]  # noqa: E731
        self.assertEqual(typing(), [])
        self.app.backend_typing("bluebubbles", "bb:iMessage;-;+15550100001", True)
        self.assertEqual(len(typing()), 1)
        self.assertIn("•••", texts(typing()[0]))
        self.assertIs(window.bubbles.get_children()[-1], typing()[0])     # at the end of the conversation
        # Their message ends it.
        self.app.backend_data("bluebubbles", [], [Message(
            id="bb:9", chat_id="bb:iMessage;-;+15550100001", text="On my way", date=int(time.time() * 1000),
            sender="+15550100001", service="imessage")])
        self.assertEqual(typing(), [])
        # And it doesn't stay up if the server never says it stopped.
        self.app.backend_typing("bluebubbles", "bb:iMessage;-;+15550100001", True)
        self.app.typing["bb:iMessage;-;+15550100001"] = store.now_ms() - 1
        self.app._typing_expired("bb:iMessage;-;+15550100001")
        self.assertEqual(typing(), [])
        # Typing elsewhere doesn't show here.
        self.app.backend_typing("bluebubbles", "bb:SMS;-;+15550100009", True)
        self.assertEqual(typing(), [])

    # -- attachments ----------------------------------------------------------------------------
    def picture_file(self, name="pier.png", size=(320, 200)):
        from gi.repository import GdkPixbuf
        path = os.path.join(self.dir, name)
        pixbuf = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, *size)
        pixbuf.fill(0x3366ccff)
        pixbuf.savev(path, "png", [], [])
        return path

    def test_paperclip_and_tray(self):
        self.seed()
        fake = self.bb_stub()
        window = self.messages.Window(self.app)
        window.select_chat("bb:iMessage;-;+15550100001")
        self.assertTrue(window.attach_button.get_sensitive())
        self.assertFalse(window.tray.get_visible())
        picture = self.picture_file()
        notes = os.path.join(self.dir, "packing list.txt")
        with open(notes, "w") as f:
            f.write("sunscreen, sandwiches")
        self.assertEqual(window.attach([picture, notes, os.path.join(self.dir, "missing.png")]), 2)
        self.assertTrue(window.tray.get_visible())
        self.assertEqual([c.path for c in window.tray.get_children()], [picture, notes])
        self.assertIn("packing list.txt", texts(window.tray))
        self.assertTrue(window.send_button.get_sensitive())       # files alone can be sent
        window.unstage(notes)
        self.assertEqual(window.staged, [picture])
        window.entry.set_text("The view from here")
        window.send()
        self.assertEqual(window.staged, [])
        self.assertFalse(window.tray.get_visible())
        # Through BlueBubbles: the picture as a message of its own, then the words.
        (chat, path, temp, mime), _kw = self.calls(fake, "send_attachment")[0]
        self.assertEqual((chat.id, path, mime), ("bb:iMessage;-;+15550100001", picture, "image/png"))
        self.assertEqual(self.calls(fake, "send_to_chat")[0][0][1], "The view from here")
        pending = self.app.store.message(temp)
        self.assertEqual((pending.status, pending.attachments[0]["path"]), ("sending", picture))
        # It shows as a picture straight away.
        row = [w for w in window.bubbles.get_children() if hasattr(w, "bubble") and w.bubble.message.id == temp][0]
        self.assertEqual(len(row.bubble.pictures), 1)
        shown = row.bubble.pictures[0].get_pixbuf()
        self.assertEqual((shown.get_width(), shown.get_height()), (240, 150))
        # The server's copy keeps the file that's here, so the picture stays.
        copy = Message(id="bb:up1", chat_id="bb:iMessage;-;+15550100001", date=int(time.time() * 1000),
                       from_me=True, service="imessage", status="delivered",
                       attachments=[{"id": "att-1", "name": "pier.png", "mime": "image/png", "path": ""}])
        self.app.backend_sent("bluebubbles", temp, copy, "", "bb:iMessage;-;+15550100001")
        self.assertEqual(self.app.store.message("bb:up1").attachments[0]["path"], picture)

    def test_dropping_files(self):
        self.seed()
        self.bb_stub()
        window = self.messages.Window(self.app)
        window.select_chat("bb:iMessage;-;+15550100001")
        picture = self.picture_file()

        class Dropped:
            def get_uris(self):
                return [GLib.filename_to_uri(picture, None), "https://example.invalid/not-a-file"]
        window._dropped(None, None, 0, 0, Dropped(), 0, 0)
        self.assertEqual(window.staged, [picture])
        # Changing conversation leaves them behind.
        window.select_chat("kdc:p:4")
        self.assertEqual(window.staged, [])

    def test_received_pictures_are_fetched_and_shown(self):
        self.seed()
        fake = self.bb_stub()
        now = int(time.time() * 1000)
        self.app.store.upsert_messages([Message(
            id="bb:pic", chat_id="bb:iMessage;-;+15550100001", date=now, sender="+15550100001",
            service="imessage", attachments=[{"id": "att-9", "name": "IMG_0001.png", "mime": "image/png",
                                              "path": "", "size": 2000}])])
        window = self.messages.Window(self.app)
        window.select_chat("bb:iMessage;-;+15550100001")
        (message_id, attachment), _kw = self.calls(fake, "download")[0]
        self.assertEqual((message_id, attachment["id"]), ("bb:pic", "att-9"))
        launched = []
        Gio.AppInfo.launch_default_for_uri, saved = (lambda *a: launched.append(a)), Gio.AppInfo.launch_default_for_uri
        try:
            self.app.backend_attachment("bluebubbles", "bb:pic", "att-9", self.picture_file("IMG_0001.png"))
        finally:
            Gio.AppInfo.launch_default_for_uri = saved
        self.assertEqual(launched, [])          # fetched to show, not to open
        row = [w for w in window.bubbles.get_children() if hasattr(w, "bubble") and w.bubble.message.id == "bb:pic"][0]
        self.assertEqual(len(row.bubble.pictures), 1)

    def test_phone_thumbnail_shows_before_the_file(self):
        self.seed()
        from gi.repository import GdkPixbuf
        import base64
        pixbuf = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, 96, 64)
        pixbuf.fill(0x22aa55ff)
        _ok, data = pixbuf.save_to_bufferv("jpeg", [], [])
        self.app.store.upsert_messages([Message(
            id="kdc:p:5:5", chat_id="kdc:p:4", date=int(time.time() * 1000), sender="+15550100002",
            attachments=[{"id": "pic.jpg", "part_id": 3, "name": "pic.jpg", "mime": "image/jpeg", "path": "",
                          "thumbnail": base64.b64encode(data).decode()}])])
        window = self.messages.Window(self.app)
        window.select_chat("kdc:p:4")
        row = [w for w in window.bubbles.get_children() if hasattr(w, "bubble")
               and w.bubble.message.id == "kdc:p:5:5"][0]
        self.assertEqual(row.bubble.pictures[0].get_pixbuf().get_width(), 96)

    def test_mms_through_the_phone(self):
        self.seed()
        sent = []
        fake = Recorder()
        fake.send = lambda addresses, text, attachments=None: sent.append((addresses, text, attachments))
        fake.load_conversation = lambda *a: None
        fake.request_attachment = lambda *a: None
        fake.stop = lambda: None
        self.app.backends["kdeconnect"] = fake
        window = self.messages.Window(self.app)
        window.select_chat("kdc:p:4")
        picture = self.picture_file()
        window.attach([picture])
        window.send()                     # a picture with no words
        self.assertEqual(sent, [(["+15550100002"], "", [picture])])
        mine = [m for m in self.app.store.messages("kdc:p:4") if m.from_me][-1]
        self.assertEqual((mine.status, mine.attachments[0]["name"]), ("sent", "pier.png"))
        # A New Message as a text can carry files too; as an iMessage, only after its first message.
        self.bb_stub()
        window.new_message()
        window.send_as.set_active_id("kdeconnect")
        self.assertTrue(window.attach_button.get_sensitive())
        window.attach([picture])
        window.send_as.set_active_id("bluebubbles")
        self.assertFalse(window.attach_button.get_sensitive())
        self.assertEqual(window.staged, [])
        self.assertEqual(window.attach([picture]), 0)

    def test_kdeconnectd_gets_the_files(self):
        daemon = FakeDaemon(self.test_bus.get_bus_address())
        try:
            window = self.messages.Window(self.app)
            self.app.set_phone(True)
            self.assertTrue(pump(lambda: len(window.rows()) == 1, 5))
            window.select_chat(window.rows()[0].chat.id)
            picture = self.picture_file("dock 2.png")
            window.attach([picture])
            window.send()
            self.assertTrue(pump(lambda: daemon.files, 5))
            self.assertEqual(daemon.files[0], ["file://" + picture.replace(" ", "%20")])
        finally:
            self.app.stop_backend("kdeconnect")
            daemon.close()

    # -- starting at login ------------------------------------------------------------------------
    def test_starts_at_login_once_set_up(self):
        path = self.messages.autostart_path()
        self.assertTrue(path.startswith(self.dir))
        self.assertFalse(os.path.exists(path))                  # nothing set up yet
        self.app.settings["bluebubbles"] = {"url": "http://127.0.0.1:9"}
        self.app.sync_autostart()
        with open(path) as f:
            entry = f.read()
        self.assertIn("Exec=freemac-messages --background", entry)
        self.assertIn("NoDisplay=true", entry)
        self.assertTrue(self.app.start_at_login())
        # The choice in Settings.
        self.app.show_settings()
        check = self.app.settings_window.login_check
        self.assertEqual(check.get_label(), "Start Messages when you log in")
        self.assertTrue(check.get_active() and check.get_sensitive())
        check.set_active(False)
        self.assertFalse(os.path.exists(path))
        self.assertFalse(store.load_settings()["start_at_login"])
        check.set_active(True)
        self.assertTrue(os.path.exists(path))
        # Taking the server away again: nothing to start for.
        self.app.settings.pop("bluebubbles")
        self.app.sync_autostart()
        self.assertFalse(os.path.exists(path))

    def test_background_start_opens_no_window(self):
        class Line:
            def __init__(self, *args):
                self.args = ["freemac-messages", *args]

            def get_arguments(self):
                return self.args
        self.app.settings["bluebubbles"] = {"url": "http://127.0.0.1:9"}
        quits = []
        self.app.quit = lambda: quits.append(1)
        try:
            self.assertEqual(self.app.do_command_line(Line("--background")), 0)
            self.assertIsNone(self.app.window())
            self.assertEqual(quits, [])
            self.app.settings.pop("bluebubbles")
            self.app.do_command_line(Line("--background"))
            self.assertEqual(quits, [1])                         # nothing set up: it doesn't linger
            self.app.do_command_line(Line())
            self.assertIsNotNone(self.app.window())
        finally:
            del self.app.quit

    # -- the firewall ------------------------------------------------------------------------------
    def firewall_on(self, on=True):
        with open(self.firewall.UFW_CONF, "w") as f:
            f.write(f"ENABLED={'yes' if on else 'no'}\n")

    def test_phone_opens_and_closes_the_firewall(self):
        asked = []
        self.app.firewall_runner = lambda on, done: asked.append((on, done))
        self.firewall.available = lambda: True
        self.app.start_backends = lambda: None        # no real KDE Connect on this network
        try:
            window = self.messages.Window(self.app)
            # With the firewall off nothing is asked.
            self.firewall_on(False)
            self.app.set_phone(True)
            self.assertEqual(asked, [])
            self.app.set_phone(False)
            # With it on, turning the phone on asks once.
            self.firewall_on(True)
            self.app.set_phone(True)
            self.assertEqual([on for on, _d in asked], [True])
            self.assertEqual(self.app.firewall_state(), "busy")
            self.app.show_settings("kdeconnect")
            dialog = self.app.settings_window
            self.assertIn("Asking for an administrator's password", dialog.firewall_label.get_text())
            # Cancelled: still closed, and the Settings button offers it again.
            asked[-1][1](False, "")
            self.assertEqual(self.app.firewall_state(), "closed")
            self.assertTrue(dialog.firewall_button.get_visible())
            self.assertIn("The firewall blocks your phone", window.status.get_text())
            dialog.firewall_button.clicked()
            self.assertEqual([on for on, _d in asked], [True, True])
            open(self.firewall.MARK, "w").close()      # the helper did its part
            asked[-1][1](True, "")
            self.assertEqual(self.app.firewall_state(), "open")
            self.assertFalse(dialog.firewall_button.get_visible())
            self.assertIn("UDP port 1716 and TCP ports 1716–1764", dialog.firewall_label.get_text())
            self.assertNotIn("firewall", window.status.get_text())
            # Turning the phone off closes them again.
            self.app.set_phone(False)
            self.assertEqual([on for on, _d in asked], [True, True, False])
            self.assertFalse(dialog.firewall_row.get_visible())
        finally:
            self.app.firewall_runner = self.firewall.run
            del self.app.start_backends
            self.firewall.available = self.saved_firewall[2]

    def test_phone_turned_off_while_the_password_is_asked(self):
        asked = []
        self.app.firewall_runner = lambda on, done: asked.append((on, done))
        self.firewall.available = lambda: True
        self.app.start_backends = lambda: None
        try:
            self.firewall_on(True)
            self.app.set_phone(True)
            self.app.set_phone(False)                  # still waiting for the password
            self.assertEqual([on for on, _d in asked], [True])
            open(self.firewall.MARK, "w").close()
            asked[-1][1](True, "")
            self.assertEqual([on for on, _d in asked], [True, False])   # so they're closed again
        finally:
            self.app.firewall_runner = self.firewall.run
            del self.app.start_backends
            self.firewall.available = self.saved_firewall[2]

    # -- end to end ----------------------------------------------------------------------------
    def test_bluebubbles_end_to_end(self):
        server = FakeBlueBubbles()
        self.servers.append(server)
        window = self.messages.Window(self.app)
        self.app.set_bluebubbles(server.url, FakeBlueBubbles.PASSWORD)
        self.assertEqual(self.app.settings["password_store"], "file")
        self.assertTrue(pump(lambda: len(window.rows()) == 2, 5), "the conversations never came")
        self.assertEqual(window.root.get_visible_child_name(), "main")
        self.assertEqual(window.rows()[0].chat.title, "(555) 010-0001")
        self.assertTrue(pump(lambda: (self.app.status.get("bluebubbles") or ("", False))[1], 5))
        self.assertIn("Connected to BlueBubbles", window.status.get_text())
        window.select_chat("bb:iMessage;-;+15550100001")
        self.assertTrue(pump(lambda: len(self.app.store.messages("bb:iMessage;-;+15550100001")) == 2, 5))
        pump(seconds=0.2)
        self.assertIn("Are we still on for the pier at noon?", texts(window.bubbles))
        window.entry.set_text("Bringing sandwiches")
        window.send()
        self.assertTrue(pump(lambda: server.sent, 5))
        self.assertTrue(pump(lambda: not any(m.id.startswith("tmp:")
                                             for m in self.app.store.messages("bb:iMessage;-;+15550100001")), 5))
        self.assertIn("Bringing sandwiches", texts(window.bubbles))
        # A reply arrives over the websocket while the window is open.
        if self.app.backends["bluebubbles"].socket_up or pump(lambda: self.app.backends["bluebubbles"].socket_up, 3):
            server.emit("new-message", dict(FakeBlueBubbles.message("r1", "Perfect, see you", int(time.time() * 1000),
                                                                    False, "+15550100001"),
                                            chats=[{"guid": "iMessage;-;+15550100001"}]))
            self.assertTrue(pump(lambda: "Perfect, see you" in texts(window.bubbles), 5))
        # Restart: everything is still there with the server gone.
        server.close()
        self.servers.remove(server)
        for backend in self.app.backends.values():
            backend.stop()
        again = store.Store()
        self.assertEqual(len(again.chats()), 2)
        again.close()

    def test_bluebubbles_pictures_tapbacks_and_typing_end_to_end(self):
        server = FakeBlueBubbles(private_api=True)
        self.servers.append(server)
        window = self.messages.Window(self.app)
        self.app.set_bluebubbles(server.url, FakeBlueBubbles.PASSWORD)
        chat_id = "bb:iMessage;-;+15550100001"
        self.assertTrue(pump(lambda: (self.app.status.get("bluebubbles") or ("", False))[1], 5))
        window.select_chat(chat_id)
        self.assertTrue(pump(lambda: self.app.store.message("bb:m2") is not None, 5))
        # A picture, by the paperclip's way in.
        picture = self.picture_file("sandbar.png")
        window.attach([picture])
        window.send()
        self.assertTrue(pump(lambda: server.uploads, 5))
        fields, filename, kind, data = server.uploads[0]
        self.assertEqual((fields["chatGuid"], filename, kind, fields["method"]),
                         ("iMessage;-;+15550100001", "sandbar.png", "image/png", "private-api"))
        with open(picture, "rb") as f:
            self.assertEqual(data, f.read())
        self.assertTrue(pump(lambda: self.app.store.message("bb:upload-1") is not None, 5))
        self.assertEqual(self.app.store.message("bb:upload-1").attachments[0]["path"], picture)
        # A tapback from the bubble's menu.
        menu = window.bubble_menu(self.app.store.message("bb:m2"))
        menu.reactions["emphasize"].activate()
        self.assertTrue(pump(lambda: server.reacted, 5))
        self.assertEqual(server.reacted[0]["selectedMessageGuid"], "m2")
        self.assertTrue(pump(lambda: self.app.store.my_reaction("bb:m2") == "emphasize", 5))
        mine = [w for w in window.bubbles.get_children() if hasattr(w, "bubble") and w.bubble.message.id == "bb:m2"]
        self.assertEqual(mine[0].tapbacks.get_text(), "‼️")
        # Typing, over the websocket.
        from freemac_shell import messages_bluebubbles
        if messages_bluebubbles.websocket is not None:
            self.assertTrue(pump(lambda: self.app.backends["bluebubbles"].socket_up, 5), "no websocket")
            server.typing("iMessage;-;+15550100001", True)
            self.assertTrue(pump(lambda: "•••" in texts(window.bubbles), 5))
            server.typing("iMessage;-;+15550100001", False)
            self.assertTrue(pump(lambda: "•••" not in texts(window.bubbles), 5))

    def test_kdeconnectd_is_used_when_running(self):
        daemon = FakeDaemon(self.test_bus.get_bus_address())
        try:
            window = self.messages.Window(self.app)
            self.app.set_phone(True)
            from freemac_shell import messages_kdeconnect
            self.assertIsInstance(self.app.backends["kdeconnect"], messages_kdeconnect.KdeConnectDaemon)
            self.assertTrue(pump(lambda: len(window.rows()) == 1, 5))
            self.assertEqual(window.rows()[0].chat.last_text, "Ferry tickets are booked")
            self.assertIn("Pixel Daemon", window.status.get_text())
            daemon.text_arrives("Gate 4, not gate 2")
            self.assertTrue(pump(lambda: self.app.store.chat(window.rows()[0].chat.id).last_text
                                 == "Gate 4, not gate 2", 5))
            window.select_chat(window.rows()[0].chat.id)
            window.entry.set_text("Thanks!")
            window.send()
            self.assertTrue(pump(lambda: daemon.sent, 5))
            self.assertEqual(daemon.sent[0], (["+15550100031"], "Thanks!"))
        finally:
            self.app.stop_backend("kdeconnect")
            daemon.close()


def walk(widget):
    yield widget
    if isinstance(widget, Gtk.Container):
        for child in widget.get_children():
            yield from walk(child)


if __name__ == "__main__":
    unittest.main()
