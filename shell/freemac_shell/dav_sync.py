# SPDX-License-Identifier: GPL-3.0-or-later
"""Keeps Tide, Crew and Nudge in step with online accounts (CalDAV, CardDAV).

Accounts are set up in Dials > Internet Accounts and kept in
~/.config/freemac/accounts.json (passwords in a file only the user can read).
Items that come from an account stay in each app's own store on this
computer, marked with the account and collection they belong to
(X-FREEMAC-SOURCE), so the apps, Beacon and Seek read them like any other.

A sync, for each collection: what changed on the server since last time
(by ETag) is fetched and replaces the copy here; what was deleted there is
deleted here; what changed here is written back; what was deleted here is
deleted there. When both sides changed the same item, the server's copy
wins. New events and contacts made after an account is added go to that
account's first calendar and address book; what was here before stays here.
Reminder lists from the account sync as a whole. No GTK. Original freemac
code.
"""
import hashlib
import json
import os
import re
import time
import urllib.parse
import uuid

from . import calendar_store, contacts_store, dav, reminders_store

SOURCE = "X-FREEMAC-SOURCE"
COLOR_NAMES = {name: hexcode for name, hexcode in reminders_store.COLORS.items()}


# -- accounts --------------------------------------------------------------------
def config_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "freemac")


def state_dir():
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "freemac", "sync")


def _read(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def _write(path, value, private=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temp = path + ".new"
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600 if private else 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(value, f, indent=1)
    os.replace(temp, path)


class Account:
    FIELDS = ("id", "provider", "server", "username", "calendars", "contacts", "reminders",
              "last_sync", "last_error", "local_only")

    def __init__(self, **values):
        self.id = values.get("id") or uuid.uuid4().hex[:10]
        self.provider = values.get("provider", "other")
        self.server = values.get("server", "")
        self.username = values.get("username", "")
        self.calendars = values.get("calendars", True)
        self.contacts = values.get("contacts", True)
        self.reminders = values.get("reminders", True)
        self.last_sync = values.get("last_sync")
        self.last_error = values.get("last_error", "")
        # Items that were here before the account came, by kind: they stay here.
        self.local_only = values.get("local_only", {})

    @property
    def title(self):
        name = dav.PROVIDERS.get(self.provider, dav.PROVIDERS["other"])[0]
        return name if self.provider != "other" else urllib.parse.urlsplit(self._url(self.server)).netloc or name

    @staticmethod
    def _url(server):
        return server if "://" in server else "https://" + server

    def servers(self, service):
        default = dav.PROVIDERS.get(self.provider, dav.PROVIDERS["other"])
        return self.server or (default[1] if service == "caldav" else default[2])

    def as_dict(self):
        return {name: getattr(self, name) for name in self.FIELDS}


def accounts_path():
    return os.path.join(config_dir(), "accounts.json")


def load_accounts():
    return [Account(**a) for a in _read(accounts_path(), []) if isinstance(a, dict)]


def save_accounts(accounts):
    _write(accounts_path(), [a.as_dict() for a in accounts])


def _passwords_path():
    return os.path.join(config_dir(), "account-passwords.json")


def get_password(account):
    return _read(_passwords_path(), {}).get(account.id, "")


def set_password(account, password):
    found = _read(_passwords_path(), {})
    if password is None:
        found.pop(account.id, None)
    else:
        found[account.id] = password
    _write(_passwords_path(), found, private=True)


def _state_path(account):
    return os.path.join(state_dir(), account.id + ".json")


def load_state(account):
    return _read(_state_path(account), {})


def save_state(account, state):
    _write(_state_path(account), state)


def update_account(account_id, **changes):
    """Change one account's saved fields (Dials may have changed others)."""
    accounts = load_accounts()
    for a in accounts:
        if a.id == account_id:
            for k, v in changes.items():
                setattr(a, k, v)
    save_accounts(accounts)


# -- reading and writing the marks -------------------------------------------------
def _source_of(extra):
    for line in extra:
        if line.upper().startswith(SOURCE + ":"):
            return line.partition(":")[2].strip()
    return None


def _set_source(extra, key):
    kept = [line for line in extra if not line.upper().startswith(SOURCE + ":")]
    return kept + ([f"{SOURCE}:{key}"] if key else [])


def _without_source(text):
    return "\r\n".join(line for line in text.split("\r\n") if not line.upper().startswith(SOURCE + ":"))


def _digest(text):
    """A fingerprint of an item as written here, leaving out the stamps that
    change at every save."""
    lines = [l for l in text.splitlines() if not l.upper().startswith(("DTSTAMP", "LAST-MODIFIED", "REV:"))]
    return hashlib.sha1("\n".join(lines).encode()).hexdigest()


def _key(account, url):
    return f"{account.id} {url}"


# -- the three kinds of item ---------------------------------------------------------
class Events:
    """Tide's events: one .ics; an item is the events with one UID (a
    repeating event and its changed dates)."""
    kind, suffix, dav_kind = "events", ".ics", "cal"

    def __init__(self):
        self.ops = []
        self.items = self._group(calendar_store.load())

    @staticmethod
    def _group(events):
        found = {}
        for e in events:
            found.setdefault(e.uid, []).append(e)
        return found

    def source(self, item):
        return _source_of(item[0].extra)

    def of(self, key):
        return {uid: item for uid, item in self.items.items() if self.source(item) == key}

    def untagged(self):
        return {uid: item for uid, item in self.items.items() if self.source(item) is None}

    def text(self, item):
        return _without_source(calendar_store.dump([self._plain(e) for e in item]))

    @staticmethod
    def _plain(event):
        twin = event.copy()
        twin.extra = _set_source(twin.extra, None)
        return twin

    def parse(self, text, key):
        events = calendar_store.parse(text)
        for e in events:
            e.extra = _set_source(e.extra, key)
        return self._group(events)

    def put(self, uid, item):
        self.items[uid] = item
        self.ops.append(("put", uid, item))

    def remove(self, uid):
        self.items.pop(uid, None)
        self.ops.append(("remove", uid, None))

    def tag(self, uid, key):
        item = [e.copy() for e in self.items[uid]]
        for e in item:
            e.extra = _set_source(e.extra, key)
        self.put(uid, item)
        return item

    def save(self):
        """Read the store again (an app may have saved since), apply what
        changed and write it."""
        if not self.ops:
            return
        fresh = self._group(calendar_store.load())
        for op, uid, item in self.ops:
            if op == "put":
                fresh[uid] = item
            else:
                fresh.pop(uid, None)
        calendar_store.save([e for item in fresh.values() for e in item])
        self.ops = []


class Contacts:
    """Crew's cards, one .vcf each."""
    kind, suffix, dav_kind = "contacts", ".vcf", "card"

    def __init__(self):
        self.ops = []
        self.items = {c.uid: c for c in contacts_store.load()}

    def source(self, item):
        return _source_of(item.extra)

    def of(self, key):
        return {uid: c for uid, c in self.items.items() if self.source(c) == key}

    def untagged(self):
        return {uid: c for uid, c in self.items.items() if self.source(c) is None}

    def text(self, item):
        twin = item.copy()
        twin.extra = _set_source(twin.extra, None)
        return contacts_store.dump(twin)

    def parse(self, text, key):
        found = {}
        for card in contacts_store.parse(text)[:1]:
            if any(l.upper().replace(" ", "") in ("X-ADDRESSBOOKSERVER-KIND:GROUP", "KIND:GROUP")
                   for l in card.extra):
                continue   # a group, not a person
            card.extra = _set_source(card.extra, key)
            found[card.uid] = card
        return found

    def put(self, uid, item):
        old = self.items.get(uid)
        item.path = old.path if old is not None else None
        self.items[uid] = item
        self.ops.append(("put", uid, item))

    def remove(self, uid):
        old = self.items.pop(uid, None)
        if old is not None:
            self.ops.append(("remove", uid, old))

    def tag(self, uid, key):
        card = self.items[uid].copy()
        card.extra = _set_source(card.extra, key)
        self.put(uid, card)
        return card

    def save(self):
        for op, _uid, card in self.ops:
            if op == "put":
                contacts_store.save(card)
            else:
                contacts_store.delete(card)
        self.ops = []


class Reminders:
    """Nudge's reminders. A collection is a whole list, marked as the
    account's; an item is one reminder in it."""
    kind, suffix, dav_kind = "reminders", ".ics", "cal"

    def __init__(self):
        self.ops = []
        self.lists = [l for l in reminders_store.load() if os.path.exists(reminders_store.path_of(l))]

    def list_for(self, key):
        return next((l for l in self.lists if _source_of(l.extra) == key), None)

    def ensure_list(self, key, name, color):
        found = self.list_for(key)
        if found is None:
            found = reminders_store.ReminderList(name or "Reminders", _nearest_color(color))
            found.order = len(self.lists)
            found.extra = _set_source([], key)
            self.lists.append(found)
            self.ops.append(("list", found, None))
        elif name and found.name != name:
            found.name = name
            self.ops.append(("list", found, None))
        return found

    def drop_list(self, key):
        found = self.list_for(key)
        if found is not None:
            self.lists.remove(found)
            self.ops.append(("drop", found, None))

    def of(self, key):
        found = self.list_for(key)
        return {r.uid: r for r in found.reminders} if found else {}

    def text(self, item):
        holder = reminders_store.ReminderList("", "blue")
        holder.reminders = [item]
        lines = reminders_store.dump(holder).split("\r\n")
        return "\r\n".join(l for l in lines if not l.startswith(("X-WR-CALNAME", "X-FREEMAC-COLOR",
                                                                     "X-FREEMAC-ORDER")))

    def parse(self, text, key):
        found = self.list_for(key)
        list_id = found.id if found else ""
        return {r.uid: r for r in reminders_store.parse(text, list_id).reminders}

    def put(self, uid, item):
        found = self.list_for(self._key)
        item.list_id = found.id
        found.reminders = [r for r in found.reminders if r.uid != uid] + [item]
        self.ops.append(("put", found, item))

    def remove(self, uid):
        found = self.list_for(self._key)
        if found is not None:
            found.reminders = [r for r in found.reminders if r.uid != uid]
            self.ops.append(("remove", found, uid))

    def use(self, key):
        self._key = key

    def save(self):
        """Lists are written whole, so each is read again first (Nudge may
        have saved it since) and only the reminders this sync changed are
        put into it."""
        touched = {}
        for op, rlist, thing in self.ops:
            touched.setdefault(rlist.id, (rlist, []))[1].append((op, thing))
        for rlist, ops in touched.values():
            if any(op == "drop" for op, _t in ops):
                reminders_store.remove(rlist)
                continue
            path = reminders_store.path_of(rlist)
            fresh = rlist
            if os.path.exists(path):
                try:
                    with open(path, encoding="utf-8", errors="replace") as f:
                        fresh = reminders_store.parse(f.read(), rlist.id)
                except OSError:
                    fresh = rlist
                fresh.name, fresh.extra = rlist.name, rlist.extra
            for op, thing in ops:
                if op == "put":
                    fresh.reminders = [r for r in fresh.reminders if r.uid != thing.uid] + [thing]
                elif op == "remove":
                    fresh.reminders = [r for r in fresh.reminders if r.uid != thing]
            reminders_store.save(fresh)
        self.ops = []


def _nearest_color(hexcode):
    """The Nudge colour closest to a calendar's colour."""
    hexcode = (hexcode or "").lstrip("#")
    if len(hexcode) < 6:
        return "blue"
    try:
        r, g, b = (int(hexcode[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return "blue"

    def distance(name):
        h = COLOR_NAMES[name].lstrip("#")
        return sum((int(h[i:i + 2], 16) - c) ** 2 for i, c in zip((0, 2, 4), (r, g, b)))
    return min(COLOR_NAMES, key=distance)


# -- one collection ------------------------------------------------------------------
def sync_collection(client, store, key, url, state):
    """Bring one calendar, list or address book in step. state is this
    collection's {"items": {url: {"etag", "uid", "hash"}}}, updated in place."""
    known = state.setdefault("items", {})
    local = dict(store.of(key))
    remote = dav.list_items(client, url, store.suffix)
    by_uid = {entry["uid"]: href for href, entry in known.items() if entry.get("uid")}
    changed = 0

    # What changed on the server replaces the copy here.
    wanted = [href for href, etag in remote.items() if href not in known or known[href].get("etag") != etag]
    fetched = set()
    for href, (text, etag) in dav.fetch(client, url, wanted, store.dav_kind).items():
        items = store.parse(text, key)
        old_uid = known.get(href, {}).get("uid")
        if old_uid and old_uid not in items:
            store.remove(old_uid)
        if not items:
            known[href] = {"etag": etag or remote.get(href, ""), "uid": None, "hash": ""}
            continue
        for uid, item in items.items():
            store.put(uid, item)
            fetched.add(uid)
            known[href] = {"etag": etag or remote.get(href, ""), "uid": uid, "hash": _digest(store.text(item))}
            by_uid[uid] = href
        changed += 1

    # Deleted on the server: deleted here.
    for href in [h for h in known if h not in remote]:
        uid = known.pop(href).get("uid")
        if uid:
            store.remove(uid)
            local.pop(uid, None)
            by_uid.pop(uid, None)
            changed += 1

    # Changed or new here: written to the server.
    for uid, item in local.items():
        if uid in fetched:
            continue
        text = store.text(item)
        digest = _digest(text)
        href = by_uid.get(uid)
        if href and href in known:
            if known[href].get("hash") == digest:
                continue
            try:
                etag = dav.put(client, href, text, known[href].get("etag") or None, store.dav_kind)
            except dav.DavError as error:
                if error.args[1:] == (412,):   # changed there meanwhile: theirs wins next time
                    known[href]["etag"] = ""
                    continue
                raise
        else:
            href = url.rstrip("/") + "/" + urllib.parse.quote(re.sub(r"[^\w.@-]", "_", uid)) + store.suffix
            etag = dav.put(client, href, text, None, store.dav_kind)
        known[href] = {"etag": etag, "uid": uid, "hash": digest}
        changed += 1

    # Deleted here: deleted on the server.
    for href, entry in list(known.items()):
        uid = entry.get("uid")
        if uid and uid not in local and uid not in fetched and href in remote:
            dav.delete(client, href, entry.get("etag") or None)
            del known[href]
            changed += 1

    # Servers that don't send an ETag after a write: ask for them now, so
    # the item isn't fetched again as if changed there.
    if any(not entry.get("etag") for entry in known.values()):
        fresh = dav.list_items(client, url, store.suffix)
        for href, entry in known.items():
            if not entry.get("etag") and href in fresh:
                entry["etag"] = fresh[href]
    return changed


# -- one account ---------------------------------------------------------------------
def forget(account, kinds=("events", "contacts", "reminders")):
    """Take an account's items off this computer (the account was removed,
    or one of its kinds turned off). Nothing changes on the server."""
    state = load_state(account)
    prefix = account.id + " "
    if "events" in kinds:
        store = Events()
        for uid, item in list(store.items.items()):
            if (store.source(item) or "").startswith(prefix):
                store.remove(uid)
        store.save()
    if "contacts" in kinds:
        store = Contacts()
        for uid, card in list(store.items.items()):
            if (store.source(card) or "").startswith(prefix):
                store.remove(uid)
        store.save()
    if "reminders" in kinds:
        store = Reminders()
        for rlist in list(store.lists):
            if (_source_of(rlist.extra) or "").startswith(prefix):
                store.drop_list(_source_of(rlist.extra))
        store.save()
    for url in list(state):
        if state[url].get("kind") in kinds:
            del state[url]
    save_state(account, state)


def note_local_only(account, kinds=("events", "contacts")):
    """What is here now stays here: called when an account is added, or a
    kind is turned on, so only items made after that go online."""
    local_only = dict(account.local_only)
    if "events" in kinds:
        local_only["events"] = sorted(Events().untagged())
    if "contacts" in kinds:
        local_only["contacts"] = sorted(Contacts().untagged())
    account.local_only = local_only
    return local_only


def _others_adopt(accounts, account, kind):
    """Whether an account listed earlier already takes new items of a kind."""
    for other in accounts:
        if other.id == account.id:
            return False
        if getattr(other, "calendars" if kind == "events" else "contacts"):
            return True
    return False


def sync_account(account, password, accounts=None):
    """Sync one account; returns how many items changed. Raises DavError."""
    accounts = accounts if accounts is not None else load_accounts()
    client = dav.Client(account.username, password)
    state = load_state(account)
    changed = 0
    try:
        if account.calendars or account.reminders:
            calendars = dav.discover_calendars(client, account.servers("caldav"))
            events_store = Events() if account.calendars else None
            reminders_store_ = Reminders() if account.reminders else None
            first_events = None
            for url, name, color, kinds in calendars:
                if events_store is not None and "VEVENT" in kinds:
                    key = _key(account, url)
                    first_events = first_events or key
                    entry = state.setdefault(url, {"kind": "events"})
                    entry.update(kind="events", name=name, color=color)
                    changed += sync_collection(client, events_store, key, url, entry)
                elif reminders_store_ is not None and "VTODO" in kinds and "VEVENT" not in kinds:
                    key = _key(account, url)
                    reminders_store_.ensure_list(key, name, color)
                    reminders_store_.use(key)
                    entry = state.setdefault(url, {"kind": "reminders"})
                    entry.update(kind="reminders", name=name, color=color)
                    changed += sync_collection(client, reminders_store_, key, url, entry)
            if events_store is not None:
                changed += _adopt(client, events_store, account, accounts, first_events, state)
                events_store.save()
            if reminders_store_ is not None:
                present = {_key(account, u) for u, _n, _c, k in calendars if "VTODO" in k and "VEVENT" not in k}
                for rlist in list(reminders_store_.lists):
                    key = _source_of(rlist.extra) or ""
                    if key.startswith(account.id + " ") and key not in present:
                        reminders_store_.drop_list(key)   # the list was deleted online
                reminders_store_.save()
        if account.contacts:
            books = dav.discover_addressbooks(client, account.servers("carddav"))
            contacts = Contacts()
            first_book = None
            for url, name in books:
                key = _key(account, url)
                first_book = first_book or key
                entry = state.setdefault(url, {"kind": "contacts"})
                entry.update(kind="contacts", name=name)
                changed += sync_collection(client, contacts, key, url, entry)
            changed += _adopt(client, contacts, account, accounts, first_book, state)
            contacts.save()
    finally:
        client.close()
        save_state(account, state)
    return changed


def _adopt(client, store, account, accounts, key, state):
    """New items made here since the account came go to its first
    calendar or address book (unless an account listed earlier takes them)."""
    if key is None or _others_adopt(accounts, account, store.kind):
        return 0
    stay = set(account.local_only.get(store.kind, []))
    fresh = [uid for uid in store.untagged() if uid not in stay]
    if not fresh:
        return 0
    for uid in fresh:
        store.tag(uid, key)
    url = key.split(" ", 1)[1]
    return sync_collection(client, store, key, url, state[url])


def sync_all():
    """Sync every account; each one's outcome is saved with it."""
    accounts = load_accounts()
    total = 0
    for account in accounts:
        password = get_password(account)
        try:
            total += sync_account(account, password, accounts)
            update_account(account.id, last_sync=time.time(), last_error="")
        except dav.DavError as error:
            update_account(account.id, last_error=str(error.args[0]))
        except OSError as error:
            update_account(account.id, last_error=f"Couldn't sync ({error}).")
    return total


def check(provider, server, username, password):
    """Sign in and find what the account offers: (calendars, books).
    Raises DavError in words to show."""
    account = Account(provider=provider, server=server, username=username)
    client = dav.Client(username, password)
    try:
        try:
            calendars = dav.discover_calendars(client, account.servers("caldav"))
        except dav.DavError as error:
            if "password" in str(error):
                raise
            calendars = []
        try:
            books = dav.discover_addressbooks(client, account.servers("carddav"))
        except dav.DavError as error:
            if "password" in str(error) or not calendars:
                raise
            books = []
        return calendars, books
    finally:
        client.close()
