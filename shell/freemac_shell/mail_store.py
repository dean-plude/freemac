# SPDX-License-Identifier: GPL-3.0-or-later
"""Post's mail accounts, and the mail itself, kept on this computer.

Accounts are in ~/.config/freemac/mail/accounts.json; their passwords are in
passwords.json beside it, readable by this user alone. Mail is read over IMAP
(imaplib) and sent over SMTP (smtplib), both with TLS unless an account is
set up for a server on this network without it. What has been read is kept
in ~/.local/share/freemac/mail/, one folder per mailbox: index.json with the
list, and one .eml file per message once opened, so mail stays readable
without a network. No GTK here. Original freemac code.
"""
import base64
import datetime as dt
import email
import email.header
import email.message
import email.policy
import email.utils
import hashlib
import html
import imaplib
import json
import mimetypes
import os
import re
import smtplib
import ssl
import uuid
from email.message import EmailMessage

TIMEOUT = 30            # seconds for a server to answer
KEEP = 300              # newest messages listed per mailbox
BATCH = 100             # messages asked for in one go

# Servers of the providers most people use, so an address and a password are
# all that set-up asks for. (IMAP host, port, SMTP host, port, note)
APP_PASSWORD = "Use an app password from your account's security settings, not your usual password."
PROVIDERS = {
    "gmail.com": ("imap.gmail.com", 993, "smtp.gmail.com", 465, APP_PASSWORD),
    "googlemail.com": ("imap.gmail.com", 993, "smtp.gmail.com", 465, APP_PASSWORD),
    "icloud.com": ("imap.mail.me.com", 993, "smtp.mail.me.com", 587, APP_PASSWORD),
    "me.com": ("imap.mail.me.com", 993, "smtp.mail.me.com", 587, APP_PASSWORD),
    "mac.com": ("imap.mail.me.com", 993, "smtp.mail.me.com", 587, APP_PASSWORD),
    "yahoo.com": ("imap.mail.yahoo.com", 993, "smtp.mail.yahoo.com", 465, APP_PASSWORD),
    "aol.com": ("imap.aol.com", 993, "smtp.aol.com", 465, APP_PASSWORD),
    "fastmail.com": ("imap.fastmail.com", 993, "smtp.fastmail.com", 465, APP_PASSWORD),
    "zoho.com": ("imap.zoho.com", 993, "smtp.zoho.com", 465, ""),
    "gmx.com": ("imap.gmx.com", 993, "mail.gmx.com", 587, ""),
    "gmx.net": ("imap.gmx.net", 993, "mail.gmx.net", 587, ""),
    "outlook.com": ("outlook.office365.com", 993, "smtp-mail.outlook.com", 587,
                    "Microsoft accounts need a sign-in on Microsoft's own page, which Post can't do yet."),
    "hotmail.com": ("outlook.office365.com", 993, "smtp-mail.outlook.com", 587,
                    "Microsoft accounts need a sign-in on Microsoft's own page, which Post can't do yet."),
    "live.com": ("outlook.office365.com", 993, "smtp-mail.outlook.com", 587,
                 "Microsoft accounts need a sign-in on Microsoft's own page, which Post can't do yet."),
}

# What a mailbox is for, from its special-use flag or its usual names.
KINDS = ("inbox", "drafts", "sent", "junk", "trash", "archive")
FLAG_KINDS = {"\\sent": "sent", "\\drafts": "drafts", "\\trash": "trash", "\\junk": "junk",
              "\\archive": "archive", "\\all": "all", "\\flagged": "flagged"}
NAME_KINDS = {"sent": "sent", "sent messages": "sent", "sent items": "sent", "sent mail": "sent",
              "drafts": "drafts", "draft": "drafts", "trash": "trash", "deleted messages": "trash",
              "deleted items": "trash", "bin": "trash", "junk": "junk", "spam": "junk",
              "junk e-mail": "junk", "bulk mail": "junk", "archive": "archive", "archives": "archive"}
SHOWN_NAMES = {"inbox": "Inbox", "drafts": "Drafts", "sent": "Sent", "junk": "Junk",
               "trash": "Trash", "archive": "Archive"}


class MailError(Exception):
    """Something to tell the person, in words they can act on."""


# --- places -----------------------------------------------------------------
def config_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "freemac", "mail")


def data_dir():
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "freemac", "mail")


def _write_json(path, value, private=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temp = path + ".new"
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600 if private else 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(value, f, ensure_ascii=False, indent=1)
    os.replace(temp, path)


def _read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


# --- accounts ---------------------------------------------------------------
class Account:
    FIELDS = ("id", "name", "address", "imap_host", "imap_port", "smtp_host", "smtp_port",
              "username", "secure")

    def __init__(self, **values):
        self.id = uuid.uuid4().hex[:10]
        self.name = self.address = self.imap_host = self.smtp_host = self.username = ""
        self.imap_port, self.smtp_port = 993, 465
        self.secure = True   # TLS; off only for a server on this network
        for key, value in values.items():
            if key in self.FIELDS:
                setattr(self, key, value)

    def to_dict(self):
        return {key: getattr(self, key) for key in self.FIELDS}

    @property
    def domain(self):
        return self.address.rpartition("@")[2].lower()

    @property
    def title(self):
        """How the sidebar names it: the provider's own word for well-known
        ones, otherwise the address."""
        names = {"gmail.com": "Gmail", "googlemail.com": "Gmail", "icloud.com": "iCloud",
                 "me.com": "iCloud", "mac.com": "iCloud", "yahoo.com": "Yahoo", "aol.com": "AOL",
                 "fastmail.com": "Fastmail", "outlook.com": "Outlook", "hotmail.com": "Outlook"}
        return names.get(self.domain, self.address)

    @property
    def from_header(self):
        return email.utils.formataddr((self.name, self.address)) if self.name else self.address


def guess_servers(address):
    """(imap_host, imap_port, smtp_host, smtp_port, note) for an address."""
    domain = address.rpartition("@")[2].lower().strip()
    if domain in PROVIDERS:
        return PROVIDERS[domain]
    return (f"imap.{domain}", 993, f"smtp.{domain}", 465, "")


def load_accounts():
    found = _read_json(os.path.join(config_dir(), "accounts.json"), [])
    return [Account(**a) for a in found if isinstance(a, dict)]


def save_accounts(accounts):
    _write_json(os.path.join(config_dir(), "accounts.json"), [a.to_dict() for a in accounts])


def get_password(account):
    return _read_json(os.path.join(config_dir(), "passwords.json"), {}).get(account.id, "")


def set_password(account, password):
    path = os.path.join(config_dir(), "passwords.json")
    found = _read_json(path, {})
    if password is None:
        found.pop(account.id, None)
    else:
        found[account.id] = password
    _write_json(path, found, private=True)


def remove_account(accounts, account):
    accounts[:] = [a for a in accounts if a.id != account.id]
    save_accounts(accounts)
    set_password(account, None)
    import shutil
    shutil.rmtree(os.path.join(data_dir(), account.id), ignore_errors=True)


# --- IMAP's names for mailboxes (modified UTF-7, RFC 3501) -------------------
def decode_mailbox(raw):
    out, i = [], 0
    while i < len(raw):
        if raw[i] == "&":
            end = raw.find("-", i)
            if end < 0:
                out.append(raw[i:])
                break
            chunk = raw[i + 1:end]
            if not chunk:
                out.append("&")
            else:
                b64 = chunk.replace(",", "/")
                b64 += "=" * (-len(b64) % 4)
                try:
                    out.append(base64.b64decode(b64).decode("utf-16-be"))
                except (ValueError, UnicodeDecodeError):
                    out.append(raw[i:end + 1])
            i = end + 1
        else:
            out.append(raw[i])
            i += 1
    return "".join(out)


def encode_mailbox(name):
    out, pending = [], []

    def flush():
        if pending:
            b64 = base64.b64encode("".join(pending).encode("utf-16-be")).decode("ascii")
            out.append("&" + b64.rstrip("=").replace("/", ",") + "-")
            pending.clear()
    for ch in name:
        if 0x20 <= ord(ch) <= 0x7e:
            flush()
            out.append("&-" if ch == "&" else ch)
        else:
            pending.append(ch)
    flush()
    return "".join(out)


def quote(name):
    raw = encode_mailbox(name)
    return '"' + raw.replace("\\", "\\\\").replace('"', '\\"') + '"'


class Mailbox:
    def __init__(self, name, flags=(), delimiter="/"):
        self.name = name               # the server's name, decoded
        self.flags = {f.lower() for f in flags}
        self.delimiter = delimiter or "/"
        self.kind = self._kind()
        self.unread = 0

    def _kind(self):
        if self.name.upper() == "INBOX":
            return "inbox"
        for flag in self.flags:
            if flag in FLAG_KINDS:
                return FLAG_KINDS[flag]
        leaf = self.name.rsplit(self.delimiter, 1)[-1].lower()
        return NAME_KINDS.get(leaf, "")

    @property
    def selectable(self):
        return "\\noselect" not in self.flags and "\\nonexistent" not in self.flags

    @property
    def title(self):
        if self.kind in SHOWN_NAMES:
            return SHOWN_NAMES[self.kind]
        return self.name.rsplit(self.delimiter, 1)[-1]

    def sort_key(self):
        order = KINDS.index(self.kind) if self.kind in KINDS else len(KINDS)
        return (order, self.name.lower())


LIST_LINE = re.compile(r'\((?P<flags>[^)]*)\)\s+(?P<delim>"(?:[^"\\]|\\.)*"|NIL)\s+(?P<name>.*)$')


def parse_list(data):
    """Mailboxes from a LIST answer."""
    found = []
    items = iter(data)
    for item in items:
        if item is None:
            continue
        if isinstance(item, tuple):          # a name sent as a literal
            head, literal = item
            line = head.decode("utf-8", "replace")
            name_raw = literal.decode("utf-8", "replace")
        else:
            line = item.decode("utf-8", "replace")
            name_raw = None
        m = LIST_LINE.match(line.strip())
        if not m:
            continue
        delim = m.group("delim")
        delim = "" if delim == "NIL" else delim[1:-1].replace('\\"', '"').replace("\\\\", "\\")
        if name_raw is None:
            name_raw = m.group("name").strip()
            if name_raw.startswith('"') and name_raw.endswith('"'):
                name_raw = name_raw[1:-1].replace('\\"', '"').replace("\\\\", "\\")
        flags = m.group("flags").split()
        found.append(Mailbox(decode_mailbox(name_raw), flags, delim))
    return found


# --- headers ----------------------------------------------------------------
def _header_text(value):
    if value is None:
        return ""
    try:
        parts = email.header.decode_header(str(value))
        text = "".join(p.decode(c or "utf-8", "replace") if isinstance(p, bytes) else p for p, c in parts)
    except Exception:
        text = str(value)
    return " ".join(text.split())


def parse_headers(raw):
    """A summary of a message from its header lines."""
    try:
        msg = email.message_from_bytes(raw, policy=email.policy.compat32)
    except Exception:
        msg = email.message.Message()
    sender = email.utils.parseaddr(_header_text(msg.get("From")))
    when = None
    try:
        parsed = email.utils.parsedate_to_datetime(msg.get("Date", ""))
        when = parsed.timestamp() if parsed else None
    except (TypeError, ValueError, IndexError):
        when = None
    return {
        "from_name": sender[0], "from_addr": sender[1],
        "to": _header_text(msg.get("To")), "cc": _header_text(msg.get("Cc")),
        "subject": _header_text(msg.get("Subject")),
        "date": when,
        "message_id": (msg.get("Message-ID") or "").strip(),
        "attach": "multipart/mixed" in (msg.get("Content-Type") or "").lower(),
    }


FETCH_META = re.compile(rb"UID (\d+)|FLAGS \(([^)]*)\)|INTERNALDATE \"([^\"]+)\"")


def _meta(head):
    uid, flags, internal = None, [], None
    for m in FETCH_META.finditer(head):
        if m.group(1):
            uid = int(m.group(1))
        elif m.group(2) is not None:
            flags = m.group(2).decode("ascii", "replace").split()
        elif m.group(3):
            try:
                internal = dt.datetime.strptime(m.group(3).decode(), "%d-%b-%Y %H:%M:%S %z").timestamp()
            except ValueError:
                internal = None
    return uid, flags, internal


# --- the local copy -----------------------------------------------------------
def mailbox_dir(account, mailbox_name):
    key = hashlib.sha1(mailbox_name.encode("utf-8")).hexdigest()[:16]
    return os.path.join(data_dir(), account.id, key)


def load_index(account, mailbox_name):
    found = _read_json(os.path.join(mailbox_dir(account, mailbox_name), "index.json"), {})
    if found.get("name") != mailbox_name:
        return {"name": mailbox_name, "uidvalidity": None, "messages": []}
    return found


def save_index(account, mailbox_name, index):
    _write_json(os.path.join(mailbox_dir(account, mailbox_name), "index.json"), index)


def cached_body(account, mailbox_name, uid):
    try:
        with open(os.path.join(mailbox_dir(account, mailbox_name), f"{int(uid)}.eml"), "rb") as f:
            return f.read()
    except OSError:
        return None


def _keep_body(account, mailbox_name, uid, raw):
    folder = mailbox_dir(account, mailbox_name)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, f"{int(uid)}.eml")
    with open(path + ".new", "wb") as f:
        f.write(raw)
    os.replace(path + ".new", path)


def load_mailboxes(account):
    found = _read_json(os.path.join(data_dir(), account.id, "mailboxes.json"), [])
    boxes = []
    for b in found:
        box = Mailbox(b.get("name", ""), b.get("flags", []), b.get("delimiter", "/"))
        box.unread = b.get("unread", 0)
        boxes.append(box)
    return boxes


def save_mailboxes(account, boxes):
    _write_json(os.path.join(data_dir(), account.id, "mailboxes.json"),
                [{"name": b.name, "flags": sorted(b.flags), "delimiter": b.delimiter, "unread": b.unread}
                 for b in boxes])


# --- talking to the server ----------------------------------------------------
def _tls():
    return ssl.create_default_context()


def _explain(error, what):
    """Words for a failure, rather than the library's."""
    text = str(error)
    if isinstance(error, (imaplib.IMAP4.error, smtplib.SMTPAuthenticationError)) and (
            "auth" in text.lower() or "login" in text.lower() or "credentials" in text.lower()
            or isinstance(error, smtplib.SMTPAuthenticationError)):
        return MailError(f"The {what} server didn't accept the user name and password.")
    if isinstance(error, ssl.SSLCertVerificationError):
        return MailError(f"The {what} server's certificate couldn't be checked, so Post didn't connect.")
    if isinstance(error, (TimeoutError, OSError)) and "timed out" in text:
        return MailError(f"The {what} server didn't answer.")
    if isinstance(error, OSError) and getattr(error, "errno", None) in (-2, -3, -5):
        return MailError(f"Post couldn't find the {what} server. Check its name and the network.")
    if isinstance(error, ConnectionRefusedError):
        return MailError(f"The {what} server refused the connection. Check its port.")
    return MailError(f"The {what} server had a problem: {text}")


class Session:
    """One account's IMAP connection, opened when needed and opened again
    if the server drops it. Used from one thread at a time."""

    def __init__(self, account, password):
        self.account, self.password = account, password
        self.conn = None
        self.selected = None
        self.capabilities = set()

    def _open(self):
        a = self.account
        try:
            if a.secure and int(a.imap_port) == 993:
                conn = imaplib.IMAP4_SSL(a.imap_host, int(a.imap_port), ssl_context=_tls(), timeout=TIMEOUT)
            else:
                conn = imaplib.IMAP4(a.imap_host, int(a.imap_port), timeout=TIMEOUT)
                if a.secure:
                    if "STARTTLS" not in conn.capabilities:
                        conn.shutdown()
                        raise MailError("The incoming mail server doesn't offer an encrypted connection.")
                    conn.starttls(ssl_context=_tls())
            conn.login(a.username or a.address, self.password)
        except MailError:
            raise
        except Exception as error:
            raise _explain(error, "incoming mail") from error
        self.conn = conn
        self.selected = None
        self.capabilities = {c.upper() for c in conn.capabilities}
        return conn

    def close(self):
        if self.conn is not None:
            try:
                self.conn.logout()
            except Exception:
                pass
        self.conn = None
        self.selected = None

    def run(self, work):
        """work(session) with a live connection; tries once more on a
        dropped one."""
        for attempt in (1, 2):
            if self.conn is None:
                self._open()
            try:
                return work(self)
            except (imaplib.IMAP4.abort, OSError, EOFError) as error:
                self.close()
                if attempt == 2:
                    raise _explain(error, "incoming mail") from error
            except imaplib.IMAP4.error as error:
                raise MailError(f"The incoming mail server said: {error}") from error

    # -- operations (call through run) ------------------------------------
    def select(self, name, readonly=False):
        if self.selected == (name, readonly):
            return
        typ, data = self.conn.select(quote(name), readonly=readonly)
        if typ != "OK":
            raise MailError(f"Post couldn't open the mailbox “{name}”.")
        self.selected = (name, readonly)

    def mailboxes(self):
        typ, data = self.conn.list()
        if typ != "OK":
            raise MailError("The server didn't list its mailboxes.")
        boxes = [b for b in parse_list(data) if b.selectable]
        if not any(b.kind == "inbox" for b in boxes):
            boxes.append(Mailbox("INBOX"))
        # Unread counts, so the sidebar shows them.
        for box in boxes:
            try:
                typ, data = self.conn.status(quote(box.name), "(UNSEEN)")
                m = re.search(rb"UNSEEN (\d+)", data[0] or b"") if typ == "OK" else None
                box.unread = int(m.group(1)) if m else 0
            except imaplib.IMAP4.error:
                box.unread = 0
        boxes.sort(key=Mailbox.sort_key)
        return boxes

    def refresh(self, name):
        """Bring the local list of a mailbox up to date; returns the index."""
        account = self.account
        index = load_index(account, name)
        self.selected = None
        self.select(name)
        typ, data = self.conn.response("UIDVALIDITY")
        validity = data[0].decode() if data and data[0] else None
        if validity != index.get("uidvalidity"):
            index = {"name": name, "uidvalidity": validity, "messages": []}
        typ, data = self.conn.uid("SEARCH", None, "ALL")
        uids = [int(u) for u in (data[0] or b"").split()][-KEEP:] if typ == "OK" else []
        known = {m["uid"]: m for m in index["messages"]}
        fresh = [u for u in uids if u not in known]
        for start in range(0, len(fresh), BATCH):
            batch = ",".join(str(u) for u in fresh[start:start + BATCH])
            typ, data = self.conn.uid(
                "FETCH", batch, "(UID FLAGS INTERNALDATE BODY.PEEK[HEADER.FIELDS "
                "(FROM TO CC SUBJECT DATE MESSAGE-ID CONTENT-TYPE)])")
            for item in data or []:
                if not isinstance(item, tuple):
                    continue
                uid, flags, internal = _meta(item[0])
                if uid is None:
                    continue
                summary = parse_headers(item[1])
                summary.update(uid=uid, flags=flags)
                if summary["date"] is None:
                    summary["date"] = internal
                known[uid] = summary
        old = [u for u in uids if u not in fresh]
        for start in range(0, len(old), BATCH * 5):
            batch = ",".join(str(u) for u in old[start:start + BATCH * 5])
            typ, data = self.conn.uid("FETCH", batch, "(UID FLAGS)")
            for item in data or []:
                line = item[0] if isinstance(item, tuple) else item
                if not line:
                    continue
                uid, flags, _ = _meta(line)
                if uid in known:
                    known[uid]["flags"] = flags
        index["messages"] = [known[u] for u in uids if u in known]
        save_index(account, name, index)
        return index

    def body(self, name, uid):
        """The whole message, from the local copy or the server; marks it
        read."""
        raw = cached_body(self.account, name, uid)
        self.select(name)
        if raw is None:
            typ, data = self.conn.uid("FETCH", str(uid), "(BODY.PEEK[])")
            raw = next((item[1] for item in data or [] if isinstance(item, tuple)), None)
            if raw is None:
                raise MailError("The message isn't on the server any more.")
            _keep_body(self.account, name, uid, raw)
        self.conn.uid("STORE", str(uid), "+FLAGS.SILENT", "(\\Seen)")
        return raw

    def set_flag(self, name, uid, flag, on):
        self.select(name)
        self.conn.uid("STORE", str(uid), "+FLAGS.SILENT" if on else "-FLAGS.SILENT", f"({flag})")

    def move(self, name, uid, dest):
        self.select(name)
        if "MOVE" in self.capabilities:
            typ, data = self.conn.uid("MOVE", str(uid), quote(dest))
            if typ == "OK":
                return
        typ, data = self.conn.uid("COPY", str(uid), quote(dest))
        if typ != "OK":
            raise MailError(f"Post couldn't move the message to “{dest}”.")
        self.erase(name, uid)

    def erase(self, name, uid):
        self.select(name)
        self.conn.uid("STORE", str(uid), "+FLAGS.SILENT", "(\\Deleted)")
        if "UIDPLUS" in self.capabilities:
            self.conn.uid("EXPUNGE", str(uid))
        else:
            self.conn.expunge()

    def append(self, name, raw, flags="(\\Seen)"):
        typ, data = self.conn.append(quote(name), flags, imaplib.Time2Internaldate(dt.datetime.now().astimezone()), raw)
        if typ != "OK":
            raise MailError(f"Post couldn't save the message in “{name}”.")


def check_account(account, password):
    """Sign in to both servers, as set-up does; raises MailError."""
    session = Session(account, password)
    try:
        session.run(lambda s: s.mailboxes())
    finally:
        session.close()
    with _smtp(account, password):
        pass


class _smtp:
    def __init__(self, account, password):
        self.account, self.password, self.server = account, password, None

    def __enter__(self):
        a = self.account
        try:
            if a.secure and int(a.smtp_port) == 465:
                server = smtplib.SMTP_SSL(a.smtp_host, int(a.smtp_port), context=_tls(), timeout=TIMEOUT)
            else:
                server = smtplib.SMTP(a.smtp_host, int(a.smtp_port), timeout=TIMEOUT)
                server.ehlo()
                if a.secure:
                    if not server.has_extn("starttls"):
                        server.quit()
                        raise MailError("The outgoing mail server doesn't offer an encrypted connection.")
                    server.starttls(context=_tls())
                    server.ehlo()
            if server.has_extn("auth"):
                server.login(a.username or a.address, self.password)
        except MailError:
            raise
        except Exception as error:
            raise _explain(error, "outgoing mail") from error
        self.server = server
        return server

    def __exit__(self, *exc):
        try:
            self.server.quit()
        except Exception:
            pass
        return False


def send(account, password, message):
    """Send a message; raises MailError with words to show."""
    with _smtp(account, password) as server:
        try:
            refused = server.send_message(message)
        except smtplib.SMTPRecipientsRefused as error:
            names = ", ".join(error.recipients)
            raise MailError(f"The server wouldn't send to {names}.") from error
        except smtplib.SMTPException as error:
            raise MailError(f"The outgoing mail server said: {error}") from error
    if refused:
        raise MailError("The server wouldn't send to " + ", ".join(refused) + ".")


# --- writing messages -----------------------------------------------------------
def addresses(text):
    """Addresses typed in a To or Cc field."""
    return [formatted for formatted in
            (email.utils.formataddr((n, a)) if n else a
             for n, a in email.utils.getaddresses([_tidy_list(text)]) if "@" in a)]


def _tidy_list(text):
    """Commas for semicolons, and no empty entries ("a, , b,"), which make
    the address parser give up on the whole field."""
    return re.sub(r"(\s*,\s*)+", ", ", text.replace(";", ",")).strip(" ,")


def compose(account, to, cc="", bcc="", subject="", body="", attachments=(), reply_to=None):
    msg = EmailMessage()
    msg["From"] = account.from_header
    if to:
        msg["To"] = ", ".join(addresses(to))
    if cc:
        msg["Cc"] = ", ".join(addresses(cc))
    if bcc:
        msg["Bcc"] = ", ".join(addresses(bcc))
    msg["Subject"] = subject
    msg["Date"] = email.utils.formatdate(localtime=True)
    msg["Message-ID"] = email.utils.make_msgid(domain=account.domain or None)
    msg["X-Mailer"] = "Post (freemac)"
    if reply_to is not None:
        parent = (reply_to.get("Message-ID") or "").strip()
        if parent:
            msg["In-Reply-To"] = parent
            refs = (reply_to.get("References") or "").split()
            msg["References"] = " ".join(refs + [parent])
    msg.set_content(body)
    for item in attachments:
        if isinstance(item, tuple):          # (filename, type, bytes) from a message
            filename, ctype, data = item
        else:
            filename = os.path.basename(item)
            ctype = mimetypes.guess_type(item)[0] or "application/octet-stream"
            with open(item, "rb") as f:
                data = f.read()
        main, _, sub = ctype.partition("/")
        msg.add_attachment(data, maintype=main, subtype=sub or "octet-stream", filename=filename)
    return msg


def _prefixed(prefix, subject):
    subject = subject or ""
    return subject if subject.lower().startswith(prefix.lower()) else f"{prefix} {subject}".strip()


def _when_text(msg):
    try:
        when = email.utils.parsedate_to_datetime(msg.get("Date", "")).astimezone()
        return when.strftime("%b %-d, %Y at %-I:%M %p")
    except (TypeError, ValueError, IndexError):
        return ""


def reply_fields(msg, account, everyone=False):
    """(to, cc, subject, body) to start a reply."""
    sender = msg.get("Reply-To") or msg.get("From") or ""
    to = sender
    mine = {account.address.lower()}
    cc = ""
    if everyone:
        others = email.utils.getaddresses([str(msg.get("To", "")), str(msg.get("Cc", ""))])
        sender_addrs = {a.lower() for _n, a in email.utils.getaddresses([str(sender)])}
        cc = ", ".join(email.utils.formataddr((n, a)) if n else a for n, a in others
                       if a and a.lower() not in mine and a.lower() not in sender_addrs)
    name = email.utils.parseaddr(str(msg.get("From", "")))
    who = name[0] or name[1]
    quoted = "\n".join("> " + line if line else ">" for line in plain_text(msg).splitlines())
    body = f"\n\nOn {_when_text(msg)}, {who} wrote:\n\n{quoted}\n"
    return str(to), cc, _prefixed("Re:", str(msg.get("Subject", ""))), body


def forward_fields(msg):
    """(subject, body, attachments) to start forwarding a message."""
    lines = ["", "", "Begin forwarded message:", ""]
    for key in ("From", "Subject", "Date", "To", "Cc"):
        if msg.get(key):
            lines.append(f"{key}: {msg.get(key)}")
    lines += ["", plain_text(msg)]
    files = [(name, ctype, part.get_payload(decode=True) or b"") for name, ctype, part in attachments_of(msg)]
    return _prefixed("Fwd:", str(msg.get("Subject", ""))), "\n".join(lines), files


def mailto_fields(uri):
    """(to, cc, subject, body) from a mailto: link."""
    import urllib.parse
    rest = uri.split(":", 1)[1] if ":" in uri else uri
    path, _, query = rest.partition("?")
    fields = {k.lower(): v for k, v in urllib.parse.parse_qsl(query, keep_blank_values=True)}
    to = ", ".join(filter(None, [urllib.parse.unquote(path), fields.get("to", "")]))
    return to, fields.get("cc", ""), fields.get("subject", ""), fields.get("body", "")


# --- reading messages -----------------------------------------------------------
def parse(raw):
    return email.message_from_bytes(raw, policy=email.policy.default)


def _part_text(part):
    try:
        return part.get_content()
    except (LookupError, ValueError, AssertionError):
        payload = part.get_payload(decode=True) or b""
        return payload.decode("utf-8", "replace")


def plain_text(msg):
    """The message as plain text, for quoting and previews."""
    part = msg.get_body(preferencelist=("plain", "html"))
    if part is None:
        return ""
    text = _part_text(part)
    if part.get_content_subtype() == "html":
        text = html_to_text(text)
    return text.strip("\n")


def html_to_text(markup):
    markup = re.sub(r"(?is)<(script|style|head)[^>]*>.*?</\1>", "", markup)
    markup = re.sub(r"(?i)<br\s*/?>|</p>|</div>|</tr>|</h\d>|</li>", "\n", markup)
    markup = re.sub(r"(?s)<[^>]+>", "", markup)
    text = html.unescape(markup)
    return re.sub(r"\n{3,}", "\n\n", "\n".join(line.rstrip() for line in text.splitlines()))


def attachments_of(msg):
    """[(filename, content type, part)] of the files a message carries."""
    found = []
    for part in msg.walk():
        if part.is_multipart():
            continue
        disposition = part.get_content_disposition()
        filename = part.get_filename()
        if disposition == "attachment" or (filename and disposition != "inline"):
            found.append((filename or "Attachment", part.get_content_type(), part))
        elif disposition == "inline" and filename and not part.get("Content-ID"):
            found.append((filename, part.get_content_type(), part))
    return found


REMOTE = re.compile(r"""(?i)(?:src|background)\s*=\s*["']?\s*https?:|url\(\s*["']?\s*https?:""")


def has_remote_content(markup):
    return bool(REMOTE.search(markup))


def view_html(msg, load_remote=False):
    """The message body as a page for the viewer: inline pictures embedded,
    and nothing fetched from the internet unless asked, so a sender can't
    see when it is read. Scripts are off in the viewer itself."""
    part = msg.get_body(preferencelist=("html", "plain"))
    if part is None:
        body, is_html = "", False
    else:
        body, is_html = _part_text(part), part.get_content_subtype() == "html"
    if is_html:
        pictures = {}
        for p in msg.walk():
            cid = (p.get("Content-ID") or "").strip().strip("<>")
            if cid and not p.is_multipart():
                data = p.get_payload(decode=True) or b""
                pictures[cid] = f"data:{p.get_content_type()};base64," + base64.b64encode(data).decode()
        body = re.sub(r"(?i)cid:([^\"'\s)>]+)", lambda m: pictures.get(m.group(1), "about:blank"), body)
    else:
        escaped = html.escape(body)
        escaped = re.sub(r"(https?://[^\s<>&]+)", r'<a href="\1">\1</a>', escaped)
        body = f'<div class="plain">{escaped}</div>'
    images = "data: https: http:" if load_remote else "data:"
    policy = (f"default-src 'none'; img-src {images}; style-src 'unsafe-inline' data:"
              + (" https: http:" if load_remote else "") + "; font-src data:"
              + (" https: http:" if load_remote else ""))
    head = (f'<meta http-equiv="Content-Security-Policy" content="{policy}">'
            '<meta name="color-scheme" content="light dark">'
            "<style>body{font-family:'Inter','Cantarell',sans-serif;font-size:14px;margin:16px 20px;"
            "word-wrap:break-word}.plain{white-space:pre-wrap}"
            "blockquote{margin-left:4px;padding-left:10px;border-left:2px solid #2f7bf5;color:#555}"
            "img{max-width:100%;height:auto}</style>")
    return f"<!doctype html><html><head><meta charset='utf-8'>{head}</head><body>{body}</body></html>"


def date_text(timestamp, now=None):
    """Mail's list dates: a time today, Yesterday, a weekday this week,
    otherwise the date."""
    if not timestamp:
        return ""
    when = dt.datetime.fromtimestamp(timestamp)
    now = now or dt.datetime.now()
    days = (now.date() - when.date()).days
    if days == 0:
        return when.strftime("%-I:%M %p")
    if days == 1:
        return "Yesterday"
    if 1 < days < 7:
        return when.strftime("%A")
    return f"{when.month}/{when.day}/{when:%y}"
