# SPDX-License-Identifier: GPL-3.0-or-later
"""Messages' offline store, settings and saved passwords (no GTK).

Conversations and messages from every backend are kept in one SQLite file,
~/.local/share/freemac/messages/messages.db, so the window fills at once and
everything is still there after a restart, with or without the phone or the
server in reach. Backends hand over Chat and Message records; the store
merges them by id, so the same message arriving twice (a refresh, then the
live event) is kept once. Reactions (tapbacks) are kept apart, one per person
per message: the newest from each person wins, and taking one back removes it.

Settings are ~/.config/freemac/messages/settings.json. A BlueBubbles server's
password goes to the login keychain (libsecret's Secret, through gi, which
the ISO ships as gir1.2-secret-1) when the secret service answers, and
otherwise to ~/.config/freemac/messages/passwords.json, which only the user
can read (0600). settings.json says which one was used ("password_store").

Original freemac code.
"""
import json
import os
import re
import sqlite3
import time
from dataclasses import asdict, dataclass, field

SERVICE_NAMES = {"imessage": "iMessage", "sms": "Text Message", "rcs": "RCS"}
BACKEND_NAMES = {"bluebubbles": "BlueBubbles", "kdeconnect": "Phone"}
# Set False to never touch the keychain (the tests do).
KEYRING = True
SECRET_SCHEMA = "org.freemac.Messages.Password"


def data_dir():
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "freemac", "messages")


def config_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "freemac", "messages")


def now_ms():
    return int(time.time() * 1000)


@dataclass
class Chat:
    id: str                       # "bb:<chat guid>" or "kdc:<device>:<thread>"
    backend: str                  # "bluebubbles" or "kdeconnect"
    title: str = ""
    addresses: list = field(default_factory=list)
    service: str = "sms"          # "imessage", "sms" or "rcs"
    last_date: int = 0            # ms since 1970
    last_text: str = ""
    unread: int = 0
    remote_id: str = ""           # the backend's own id (chat guid, thread id)


@dataclass
class Message:
    id: str
    chat_id: str
    text: str = ""
    date: int = 0                 # ms since 1970
    from_me: bool = False
    sender: str = ""              # the address it came from; "" for me
    service: str = "sms"
    status: str = "received"      # received, sending, sent, delivered, read, failed
    status_date: int = 0          # when it was delivered or read
    read: bool = True
    attachments: list = field(default_factory=list)   # [{"id", "name", "mime", "path", "thumbnail"?}]
    remote_id: str = ""


# A reaction's kinds, as BlueBubbles names them, and what a bubble shows.
REACTION_KINDS = ("love", "like", "dislike", "laugh", "emphasize", "question")
REACTION_GLYPHS = {"love": "❤️", "like": "👍", "dislike": "👎", "laugh": "😂", "emphasize": "‼️",
                   "question": "❓"}
REACTION_NAMES = {"love": "Love", "like": "Like", "dislike": "Dislike", "laugh": "Laugh",
                  "emphasize": "Emphasize", "question": "Question"}


@dataclass
class Reaction:
    """A tapback on one message. kind "" takes the person's reaction back."""
    id: str                       # the reaction's own id ("bb:<guid>")
    chat_id: str
    target: str                   # the message it's on ("bb:<guid>")
    kind: str = ""                # one of REACTION_KINDS, "emoji", or "" (taken back)
    emoji: str = ""               # for kind "emoji"
    from_me: bool = False
    sender: str = ""
    date: int = 0

    def glyph(self):
        return self.emoji if self.kind == "emoji" else REACTION_GLYPHS.get(self.kind, "")

    def who(self):
        return "me" if self.from_me else normalise_address(self.sender)


def normalise_address(address):
    """A key to match one phone number or address however it's written:
    the last 10 digits of a number, or the address in lower case."""
    address = (address or "").strip()
    if "@" in address:
        return address.lower()
    digits = re.sub(r"\D", "", address)
    return digits[-10:] if digits else address.lower()


def format_address(address):
    """+15551234567 -> (555) 123-4567 for North American numbers; others as they are."""
    digits = re.sub(r"\D", "", address or "")
    if "@" not in (address or "") and len(digits) == 11 and digits[0] == "1":
        digits = digits[1:]
    if "@" not in (address or "") and len(digits) == 10:
        return f"({digits[:3]}) {digits[3:6]}-{digits[6:]}"
    return address or ""


class Store:
    def __init__(self, path=None):
        self.path = path or os.path.join(data_dir(), "messages.db")
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.db = sqlite3.connect(self.path)
        self.db.row_factory = sqlite3.Row
        self.db.executescript("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS chats (
                id TEXT PRIMARY KEY, backend TEXT, title TEXT, addresses TEXT, service TEXT,
                last_date INTEGER, last_text TEXT, unread INTEGER, remote_id TEXT);
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY, chat_id TEXT, text TEXT, date INTEGER, from_me INTEGER,
                sender TEXT, service TEXT, status TEXT, status_date INTEGER, read INTEGER,
                attachments TEXT, remote_id TEXT);
            CREATE INDEX IF NOT EXISTS messages_by_chat ON messages(chat_id, date);
            CREATE TABLE IF NOT EXISTS reactions (
                target TEXT, who TEXT, id TEXT, chat_id TEXT, kind TEXT, emoji TEXT, from_me INTEGER,
                sender TEXT, date INTEGER, PRIMARY KEY (target, who));
            CREATE INDEX IF NOT EXISTS reactions_by_chat ON reactions(chat_id);
        """)
        self.db.commit()

    def close(self):
        self.db.close()

    # -- chats ----------------------------------------------------------------
    @staticmethod
    def _chat(row):
        return Chat(id=row["id"], backend=row["backend"], title=row["title"] or "",
                    addresses=json.loads(row["addresses"] or "[]"), service=row["service"] or "sms",
                    last_date=row["last_date"] or 0, last_text=row["last_text"] or "",
                    unread=row["unread"] or 0, remote_id=row["remote_id"] or "")

    def chat(self, chat_id):
        row = self.db.execute("SELECT * FROM chats WHERE id=?", (chat_id,)).fetchone()
        return self._chat(row) if row else None

    def upsert_chats(self, chats):
        for c in chats:
            old = self.chat(c.id)
            if old:
                # Keep the newest last message, and what we know about the title.
                if old.last_date > c.last_date:
                    c.last_date, c.last_text = old.last_date, old.last_text
                c.title = c.title or old.title
                c.addresses = c.addresses or old.addresses
                c.unread = max(c.unread, 0) if c.unread else old.unread
            self.db.execute("INSERT OR REPLACE INTO chats VALUES (?,?,?,?,?,?,?,?,?)",
                            (c.id, c.backend, c.title, json.dumps(c.addresses), c.service,
                             c.last_date, c.last_text, c.unread, c.remote_id))
        self.db.commit()

    def chats(self, query=""):
        """Every conversation, newest first; query narrows them by name,
        address or any message's words."""
        rows = self.db.execute("SELECT * FROM chats ORDER BY last_date DESC").fetchall()
        found = [self._chat(r) for r in rows]
        words = query.lower().split()
        if not words:
            return found
        out = []
        for chat in found:
            hay = " ".join([chat.title, " ".join(chat.addresses),
                            " ".join(format_address(a) for a in chat.addresses)]).lower()
            if all(w in hay for w in words):
                out.append(chat)
                continue
            like = [f"%{w}%" for w in words]
            sql = "SELECT 1 FROM messages WHERE chat_id=?" + " AND lower(text) LIKE ?" * len(words) + " LIMIT 1"
            if self.db.execute(sql, [chat.id] + like).fetchone():
                out.append(chat)
        return out

    def find_chat(self, backend, addresses):
        """The one-to-one or group conversation with exactly these addresses."""
        want = sorted(normalise_address(a) for a in addresses)
        for chat in self.chats():
            if chat.backend == backend and sorted(normalise_address(a) for a in chat.addresses) == want:
                return chat
        return None

    def delete_chat(self, chat_id):
        self.db.execute("DELETE FROM messages WHERE chat_id=?", (chat_id,))
        self.db.execute("DELETE FROM reactions WHERE chat_id=?", (chat_id,))
        self.db.execute("DELETE FROM chats WHERE id=?", (chat_id,))
        self.db.commit()

    def forget_backend(self, backend):
        """Everything from one backend, when its account is removed."""
        ids = [r["id"] for r in self.db.execute("SELECT id FROM chats WHERE backend=?", (backend,))]
        for chat_id in ids:
            self.db.execute("DELETE FROM messages WHERE chat_id=?", (chat_id,))
            self.db.execute("DELETE FROM reactions WHERE chat_id=?", (chat_id,))
        self.db.execute("DELETE FROM chats WHERE backend=?", (backend,))
        self.db.commit()

    # -- messages -------------------------------------------------------------
    @staticmethod
    def _message(row):
        return Message(id=row["id"], chat_id=row["chat_id"], text=row["text"] or "",
                       date=row["date"] or 0, from_me=bool(row["from_me"]), sender=row["sender"] or "",
                       service=row["service"] or "sms", status=row["status"] or "received",
                       status_date=row["status_date"] or 0, read=bool(row["read"]),
                       attachments=json.loads(row["attachments"] or "[]"), remote_id=row["remote_id"] or "")

    def message(self, message_id):
        row = self.db.execute("SELECT * FROM messages WHERE id=?", (message_id,)).fetchone()
        return self._message(row) if row else None

    def messages(self, chat_id, limit=1000):
        rows = self.db.execute("SELECT * FROM (SELECT * FROM messages WHERE chat_id=? ORDER BY date DESC LIMIT ?)"
                               " ORDER BY date ASC", (chat_id, limit)).fetchall()
        return [self._message(r) for r in rows]

    def upsert_messages(self, messages):
        """Adds or updates messages; returns the ones that weren't here before.
        A message we sent ourselves and kept as "sending" is swapped for the
        backend's own copy when that arrives. Reactions in the list go to
        upsert_reactions, and new ones are returned too."""
        fresh = self.upsert_reactions([m for m in messages if isinstance(m, Reaction)])
        for m in messages:
            if isinstance(m, Reaction):
                continue
            old = self.message(m.id)
            if old is None and m.from_me and not m.id.startswith("tmp:"):
                self._take_place_of_pending(m)
            if old is None:
                fresh.append(m)
            else:
                # A message read here stays read; local file paths stay.
                m.read = m.read or old.read
                paths = {a.get("id"): a.get("path") for a in old.attachments if a.get("path")}
                for a in m.attachments:
                    a.setdefault("path", paths.get(a.get("id"), ""))
            self.db.execute("INSERT OR REPLACE INTO messages VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                            (m.id, m.chat_id, m.text, m.date, int(m.from_me), m.sender, m.service,
                             m.status, m.status_date, int(m.read), json.dumps(m.attachments), m.remote_id))
            chat = self.chat(m.chat_id)
            if chat is not None:
                changed = False
                if m.date >= chat.last_date:
                    chat.last_date, chat.last_text = m.date, m.text or attachment_summary(m)
                    changed = True
                if old is None and not m.read and not m.from_me:
                    chat.unread += 1
                    changed = True
                if changed:
                    self.db.execute("UPDATE chats SET last_date=?, last_text=?, unread=? WHERE id=?",
                                    (chat.last_date, chat.last_text, chat.unread, chat.id))
        self.db.commit()
        return fresh

    def _take_place_of_pending(self, m):
        """The backend's copy of something we sent: the stand-in with the same
        words goes (with no words, only one that also had files)."""
        if not m.text and not m.attachments:
            return
        files = " AND attachments != '[]'" if not m.text else ""
        row = self.db.execute("SELECT id FROM messages WHERE chat_id=? AND from_me=1 AND id LIKE 'tmp:%'"
                              " AND text=? AND abs(date-?) < 600000" + files + " ORDER BY date LIMIT 1",
                              (m.chat_id, m.text, m.date)).fetchone()
        if row:
            self.db.execute("DELETE FROM messages WHERE id=?", (row["id"],))

    # -- reactions -----------------------------------------------------------
    def upsert_reactions(self, reactions):
        """Keeps the newest reaction from each person on each message; one
        with kind "" takes theirs back. Returns the new ones (not take-backs)."""
        fresh = []
        for r in sorted(reactions, key=lambda r: r.date):
            row = self.db.execute("SELECT id, date FROM reactions WHERE target=? AND who=?",
                                  (r.target, r.who())).fetchone()
            if row is not None and (row["date"] or 0) > r.date:
                continue
            if not r.kind:
                self.db.execute("DELETE FROM reactions WHERE target=? AND who=?", (r.target, r.who()))
                continue
            if row is None or row["id"] != r.id:
                fresh.append(r)
            self.db.execute("INSERT OR REPLACE INTO reactions VALUES (?,?,?,?,?,?,?,?,?)",
                            (r.target, r.who(), r.id, r.chat_id, r.kind, r.emoji, int(r.from_me), r.sender,
                             r.date))
        self.db.commit()
        return fresh

    def reactions(self, chat_id):
        """{message id: [Reaction, oldest first]} for one conversation."""
        out = {}
        for row in self.db.execute("SELECT * FROM reactions WHERE chat_id=? ORDER BY date", (chat_id,)):
            out.setdefault(row["target"], []).append(
                Reaction(id=row["id"], chat_id=row["chat_id"], target=row["target"], kind=row["kind"] or "",
                         emoji=row["emoji"] or "", from_me=bool(row["from_me"]), sender=row["sender"] or "",
                         date=row["date"] or 0))
        return out

    def my_reaction(self, message_id):
        row = self.db.execute("SELECT kind FROM reactions WHERE target=? AND who='me'", (message_id,)).fetchone()
        return row["kind"] if row else ""

    def set_status(self, message_id, status, when=0):
        self.db.execute("UPDATE messages SET status=?, status_date=? WHERE id=?", (status, when, message_id))
        self.db.commit()

    def replace_message(self, old_id, message):
        self.db.execute("DELETE FROM messages WHERE id=?", (old_id,))
        self.db.commit()
        self.upsert_messages([message])

    def set_attachment_path(self, message_id, attachment_id, path):
        m = self.message(message_id)
        if m is None:
            return
        for a in m.attachments:
            if a.get("id") == attachment_id:
                a["path"] = path
        self.db.execute("UPDATE messages SET attachments=? WHERE id=?", (json.dumps(m.attachments), message_id))
        self.db.commit()

    def mark_read(self, chat_id):
        self.db.execute("UPDATE messages SET read=1 WHERE chat_id=?", (chat_id,))
        self.db.execute("UPDATE chats SET unread=0 WHERE id=?", (chat_id,))
        self.db.commit()

    def unread_total(self):
        row = self.db.execute("SELECT coalesce(sum(unread), 0) AS n FROM chats").fetchone()
        return row["n"]

    def latest_date(self, backend):
        row = self.db.execute("SELECT coalesce(max(m.date), 0) AS d FROM messages m JOIN chats c"
                              " ON m.chat_id = c.id WHERE c.backend=? AND m.id NOT LIKE 'tmp:%'",
                              (backend,)).fetchone()
        return row["d"]


def attachment_summary(message):
    n = len(message.attachments)
    if not n:
        return ""
    return "Attachment" if n == 1 else f"{n} Attachments"


# -- settings -----------------------------------------------------------------
def _read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def _write_json(path, value, private=False):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    temp = path + ".new"
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600 if private else 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(value, f, ensure_ascii=False, indent=1)
    os.replace(temp, path)


def load_settings():
    found = _read_json(os.path.join(config_dir(), "settings.json"), {})
    return found if isinstance(found, dict) else {}


def save_settings(settings):
    _write_json(os.path.join(config_dir(), "settings.json"), settings)


# -- passwords ------------------------------------------------------------------
def _secret():
    if not KEYRING:
        return None
    try:
        import gi
        gi.require_version("Secret", "1")
        from gi.repository import Secret
    except (ImportError, ValueError):
        return None
    return Secret


def _schema(Secret):
    return Secret.Schema.new(SECRET_SCHEMA, Secret.SchemaFlags.NONE,
                             {"account": Secret.SchemaAttributeType.STRING})


def save_password(account, password):
    """Keeps a password; returns "keyring" or "file", where it went."""
    Secret = _secret()
    if Secret is not None:
        try:
            if Secret.password_store_sync(_schema(Secret), {"account": account}, Secret.COLLECTION_DEFAULT,
                                          f"Messages: {account}", password, None):
                _forget_file_password(account)
                return "keyring"
        except Exception:   # noqa: BLE001 - no secret service: GLib.Error of many kinds
            pass
    path = os.path.join(config_dir(), "passwords.json")
    found = _read_json(path, {})
    found[account] = password
    _write_json(path, found, private=True)
    return "file"


def load_password(account):
    Secret = _secret()
    if Secret is not None:
        try:
            found = Secret.password_lookup_sync(_schema(Secret), {"account": account}, None)
            if found is not None:
                return found
        except Exception:   # noqa: BLE001
            pass
    return _read_json(os.path.join(config_dir(), "passwords.json"), {}).get(account, "")


def delete_password(account):
    Secret = _secret()
    if Secret is not None:
        try:
            Secret.password_clear_sync(_schema(Secret), {"account": account}, None)
        except Exception:   # noqa: BLE001
            pass
    _forget_file_password(account)


def _forget_file_password(account):
    path = os.path.join(config_dir(), "passwords.json")
    found = _read_json(path, None)
    if isinstance(found, dict) and account in found:
        found.pop(account)
        _write_json(path, found, private=True)


def to_dict(record):
    return asdict(record)
