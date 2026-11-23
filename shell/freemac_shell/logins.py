# SPDX-License-Identifier: GPL-3.0-or-later
"""Website logins in the login keychain, for Purser.

Web (Epiphany) keeps each login it saves as a secret-service item of its
"org.epiphany.FormPassword" kind: the site's origin, the user name, the
names of the page's user-name and password fields, and the password as the
secret. Purser reads and changes the same items, so a login changed in
Purser is the one Web fills in, and one added in Purser is saved the way Web
saves its own. (Web fills in a login on a page only when it knows that
page's field names, which it learns the first time it saves a login there;
one added by hand is kept for copying until then.)

A site can hold the same user name more than once (Web saved it, and it was
also added by hand): Purser shows each site and user name once, with the
newest password, and changes or deletes them together.

Also here: a strong password maker and the checks behind Purser's Security
list (passwords used on more than one site, and ones easy to guess).
Original freemac code.
"""
import secrets
import time
import uuid
from urllib.parse import urlsplit

import gi

gi.require_version("Secret", "1")
from gi.repository import GLib, Secret  # noqa: E402

KIND = "org.epiphany.FormPassword"
FIELDS = ("id", "uri", "target_origin", "form_username", "form_password", "username",
          "server_time_modified")
# Passwords people pick most, which any guesser tries first.
COMMON = {
    "password", "password1", "password123", "passw0rd", "123456", "1234567", "12345678",
    "123456789", "1234567890", "111111", "123123", "000000", "654321", "qwerty", "qwerty123",
    "qwertyuiop", "abc123", "letmein", "welcome", "iloveyou", "admin", "monkey", "dragon",
    "football", "baseball", "sunshine", "princess", "shadow", "superman", "trustno1",
    "starwars", "whatever", "freedom", "login", "master", "hello", "charlie", "secret",
}


def schema():
    kinds = {name: Secret.SchemaAttributeType.STRING for name in FIELDS}
    return Secret.Schema.new(KIND, Secret.SchemaFlags.NONE, kinds)


def origin_of(text):
    """A typed website as an origin: "Example.com/login" -> "https://example.com"."""
    text = (text or "").strip()
    if not text:
        return ""
    if "://" not in text:
        text = "https://" + text
    parts = urlsplit(text)
    host = (parts.hostname or "").lower()
    if not host:
        return ""
    port = f":{parts.port}" if parts.port else ""
    return f"{parts.scheme.lower()}://{host}{port}"


def site_name(origin):
    """What a person calls the site: "https://www.example.com" -> "example.com"."""
    parts = urlsplit(origin or "")
    host = parts.hostname or origin or ""
    if host.startswith("www."):
        host = host[4:]
    if parts.port:
        host += f":{parts.port}"
    return host


class Login:
    """One site and user name, and the keychain items that hold it."""

    def __init__(self, origin, username):
        self.origin = origin
        self.username = username
        self.password = ""
        self.modified = 0
        self.items = []
        self.fillable = False   # Web knows the page's field names

    @property
    def site(self):
        return site_name(self.origin)

    def key(self):
        return (self.origin, self.username)

    def matches(self, words):
        words = words.lower()
        return words in self.site.lower() or words in self.username.lower()

    def sort_key(self):
        return (self.site.lower(), self.username.lower())


def _service():
    return Secret.Service.get_sync(Secret.ServiceFlags.OPEN_SESSION | Secret.ServiceFlags.LOAD_COLLECTIONS,
                                   None)


def load():
    """Every website login in the keychain, sorted by site. Raises GLib.Error
    when there is no keychain to read."""
    service = _service()
    flags = Secret.SearchFlags.ALL | Secret.SearchFlags.UNLOCK | Secret.SearchFlags.LOAD_SECRETS
    found = {}
    for item in service.search_sync(schema(), {}, flags, None):
        attrs = item.get_attributes()
        origin = attrs.get("uri") or attrs.get("target_origin") or ""
        username = attrs.get("username") or ""
        if not origin:
            continue
        login = found.setdefault((origin, username), Login(origin, username))
        login.items.append(item)
        value = item.get_secret()
        stamp = item.get_modified() or item.get_created() or 0
        if value is not None and (stamp >= login.modified or not login.password):
            login.password = value.get_text() or ""
            login.modified = stamp
        if attrs.get("form_password"):
            login.fillable = True
    return sorted(found.values(), key=Login.sort_key)


def _label(origin, username):
    # Worded as Web words its own, so other keychain tools show them alike.
    if username:
        return f"Password for {username} in a form in {origin}"
    return f"Password in a form in {origin}"


def add(website, username, password):
    """Save a new login; returns its origin, or None for a website that
    can't be read."""
    origin = origin_of(website)
    if not origin:
        return None
    attrs = {"id": "{%s}" % uuid.uuid4(), "uri": origin, "target_origin": origin,
             "username": username, "server_time_modified": "0"}
    Secret.password_store_sync(schema(), attrs, Secret.COLLECTION_DEFAULT,
                                _label(origin, username), password, None)
    return origin


def change(login, website, username, password):
    """Give a login's items a new site, user name or password."""
    origin = origin_of(website) or login.origin
    value = Secret.Value.new(password, -1, "text/plain")
    for item in login.items:
        attrs = dict(item.get_attributes())
        attrs.pop("xdg:schema", None)
        if origin != login.origin:
            attrs["uri"] = origin
            attrs["target_origin"] = origin
            # Field names belong to the old site's page.
            attrs.pop("form_username", None)
            attrs.pop("form_password", None)
        attrs["username"] = username
        attrs.setdefault("id", "{%s}" % uuid.uuid4())
        attrs.setdefault("server_time_modified", "0")
        item.set_attributes_sync(schema(), attrs, None)
        item.set_label_sync(_label(origin, username), None)
        if password != login.password:
            item.set_secret_sync(value, None)
    login.origin, login.username, login.password = origin, username, password
    login.modified = int(time.time())


def delete(login):
    for item in login.items:
        item.delete_sync(None)


def strong_password():
    """A password that's hard to guess and easy to type: three groups of six,
    with one capital letter and a number ("hwnzrk-9qcmte-Fvpd4b")."""
    alphabet = "abcdefghijkmnpqrstuvwxyz23456789"   # no l, o, 0 or 1 to misread
    text = list("-".join("".join(secrets.choice(alphabet) for _ in range(6)) for _ in range(3)))
    spots = [n for n, ch in enumerate(text) if ch != "-"]
    letters = [n for n in spots if text[n].isalpha()]
    capital = secrets.choice(letters)
    text[capital] = text[capital].upper()
    if not any(ch.isdigit() for ch in text):
        n = secrets.choice([n for n in spots if n != capital])
        text[n] = secrets.choice("23456789")
    return "".join(text)


def easy_to_guess(password):
    p = password or ""
    if len(p) < 8 or p.lower() in COMMON or p.lower().rstrip("!1") in COMMON:
        return True
    if p.isdigit() or len(set(p)) <= 3:
        return True
    return False


def reused(logins):
    """{password: [logins]} for each password used on more than one site."""
    by_password = {}
    for login in logins:
        if login.password:
            by_password.setdefault(login.password, []).append(login)
    return {p: ls for p, ls in by_password.items() if len({l.origin for l in ls}) > 1}


def problems(login, shared):
    """Plain words for what's wrong with a login's password, or []."""
    found = []
    others = {l.site for l in shared.get(login.password, []) if l.origin != login.origin}
    if len(others) == 1:
        found.append(f"This password is also used on {others.pop()}. If either site leaks it, "
                     "both accounts can be opened with it.")
    elif others:
        found.append(f"This password is also used on {len(others)} other websites. If one of them "
                     "leaks it, all of these accounts can be opened with it.")
    if easy_to_guess(login.password):
        found.append("This password is easy to guess.")
    return found


def available():
    try:
        _service()
        return True
    except GLib.Error:
        return False
