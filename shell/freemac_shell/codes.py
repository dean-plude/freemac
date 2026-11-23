# SPDX-License-Identifier: GPL-3.0-or-later
"""Verification codes for two-step sign-in, kept with saved logins (Purser).

A website that offers two-step sign-in with "an authenticator app" gives a
setup key (usually as a QR code holding an otpauth:// address). From the key
and the time, both sides work out the same six-digit code every 30 seconds:
TOTP, RFC 6238, built on HOTP, RFC 4226. This module keeps each key in the
login keychain, as an item of freemac's own "org.freemac.Purser.Code" kind
with the login's site and user name, so Purser shows the code beside the
password, as the Passwords app on a Mac does.

scan_screen() reads QR codes off the screen (grim for the picture, the ZBar
library through python3-pyzbar to read it), so a code shown on a website can
be set up without typing. Original freemac code.
"""
import base64
import hashlib
import hmac
import os
import shutil
import struct
import subprocess
import tempfile
import time
from urllib.parse import parse_qs, unquote, urlsplit

import gi

gi.require_version("Secret", "1")
from gi.repository import Secret  # noqa: E402

KIND = "org.freemac.Purser.Code"
FIELDS = ("uri", "username", "issuer", "account", "digits", "period", "algorithm")
ALGORITHMS = {"SHA1": hashlib.sha1, "SHA256": hashlib.sha256, "SHA512": hashlib.sha512}


class BadKey(ValueError):
    """A setup key or QR code this module can't use; the message says why."""


def schema():
    kinds = {name: Secret.SchemaAttributeType.STRING for name in FIELDS}
    return Secret.Schema.new(KIND, Secret.SchemaFlags.NONE, kinds)


# -- the arithmetic ---------------------------------------------------------
def clean_key(text):
    """A setup key as typed or pasted ("abcd efgh ...") in base32 capitals."""
    return "".join(ch for ch in (text or "").upper() if not ch.isspace() and ch not in "-=")


def key_bytes(key):
    key = clean_key(key)
    if len(key) < 16:
        raise BadKey("That setup key is too short. It's usually 16 or 32 letters and numbers.")
    try:
        return base64.b32decode(key + "=" * (-len(key) % 8))
    except (ValueError, TypeError):
        raise BadKey("That isn't a setup key: it can only hold the letters A to Z and the "
                     "numbers 2 to 7.") from None


def hotp(secret, counter, digits=6, algorithm="SHA1"):
    mac = hmac.new(secret, struct.pack(">Q", counter), ALGORITHMS.get(algorithm, hashlib.sha1)).digest()
    at = mac[-1] & 0x0F
    number = struct.unpack(">I", mac[at:at + 4])[0] & 0x7FFFFFFF
    return str(number % 10 ** digits).zfill(digits)


class Code:
    """One verification code setup: the key and how to work out the code."""

    def __init__(self, key, digits=6, period=30, algorithm="SHA1", issuer="", account=""):
        self.key = clean_key(key)
        self.secret = key_bytes(self.key)
        self.digits = digits if digits in (6, 7, 8) else 6
        self.period = period if 10 <= period <= 120 else 30
        self.algorithm = algorithm if algorithm in ALGORITHMS else "SHA1"
        self.issuer, self.account = issuer, account
        self.origin, self.username = "", ""
        self.item = None

    def now(self, at=None):
        """(the code, seconds until the next one)."""
        at = time.time() if at is None else at
        step = int(at // self.period)
        return hotp(self.secret, step, self.digits, self.algorithm), self.period - int(at % self.period)


def shown(code_text):
    """ "123456" -> "123 456", as codes are read out."""
    half = len(code_text) // 2
    return code_text[:half] + " " + code_text[half:]


def from_uri(text):
    """A Code from an otpauth://totp/... address (a QR code's text)."""
    parts = urlsplit((text or "").strip())
    if parts.scheme.lower() != "otpauth":
        raise BadKey("That QR code isn't a verification code setup.")
    if parts.netloc.lower() != "totp":
        raise BadKey("That code changes each time it's used (HOTP), which Purser doesn't keep. "
                     "Ask the website for an authenticator app (time-based) code instead.")
    query = {k.lower(): v[0] for k, v in parse_qs(parts.query).items()}
    label = unquote(parts.path.lstrip("/"))
    issuer, _, account = label.rpartition(":") if ":" in label else ("", "", label)
    issuer = query.get("issuer") or issuer
    try:
        digits = int(query.get("digits", 6))
        period = int(query.get("period", 30))
    except ValueError:
        digits, period = 6, 30
    return Code(query.get("secret", ""), digits, period, query.get("algorithm", "SHA1").upper(),
                issuer.strip(), account.strip())


def parse(text):
    """A Code from a pasted setup key or otpauth:// address."""
    text = (text or "").strip()
    if text.lower().startswith("otpauth:"):
        return from_uri(text)
    return Code(text)


# -- the keychain -------------------------------------------------------------
def load():
    """{(origin, username): Code} for every code in the keychain."""
    service = Secret.Service.get_sync(Secret.ServiceFlags.OPEN_SESSION | Secret.ServiceFlags.LOAD_COLLECTIONS,
                                      None)
    flags = Secret.SearchFlags.ALL | Secret.SearchFlags.UNLOCK | Secret.SearchFlags.LOAD_SECRETS
    found = {}
    for item in service.search_sync(schema(), {}, flags, None):
        attrs = item.get_attributes()
        value = item.get_secret()
        if value is None:
            continue
        try:
            code = Code(value.get_text() or "", int(attrs.get("digits") or 6), int(attrs.get("period") or 30),
                        attrs.get("algorithm") or "SHA1", attrs.get("issuer", ""), attrs.get("account", ""))
        except (BadKey, ValueError):
            continue
        code.origin, code.username, code.item = attrs.get("uri", ""), attrs.get("username", ""), item
        found[(code.origin, code.username)] = code
    return found


def _attrs(code, origin, username):
    return {"uri": origin, "username": username, "issuer": code.issuer, "account": code.account,
            "digits": str(code.digits), "period": str(code.period), "algorithm": code.algorithm}


def save(code, origin, username):
    """Keep code for the login at origin with username (replacing one there)."""
    remove(origin, username)
    label = f"Verification code for {username} on {origin}" if username else f"Verification code on {origin}"
    Secret.password_store_sync(schema(), _attrs(code, origin, username), Secret.COLLECTION_DEFAULT,
                               label, code.key, None)
    code.origin, code.username = origin, username


def remove(origin, username):
    Secret.password_clear_sync(schema(), {"uri": origin, "username": username}, None)


def move(old_origin, old_username, origin, username):
    """A login's site or user name changed: its code goes with it."""
    if (old_origin, old_username) == (origin, username):
        return
    code = load().get((old_origin, old_username))
    if code is not None:
        save(code, origin, username)
        remove(old_origin, old_username)


# -- reading a QR code off the screen -------------------------------------------
def _reader():
    try:
        from PIL import Image
        from pyzbar import pyzbar
        return Image, pyzbar
    except ImportError:
        return None


def can_scan():
    return bool(shutil.which("grim")) and _reader() is not None


def scan_screen():
    """The text of every QR code on the screen now ([] if none)."""
    reader = _reader()
    if reader is None:
        return []
    Image, pyzbar = reader
    folder = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
    fd, path = tempfile.mkstemp(prefix="purser-scan-", suffix=".png", dir=folder)
    os.close(fd)
    try:
        subprocess.run(["grim", path], check=True, timeout=20, capture_output=True)
        with Image.open(path) as picture:
            found = pyzbar.decode(picture.convert("L"), symbols=[pyzbar.ZBarSymbol.QRCODE])
        return [item.data.decode("utf-8", "replace").strip() for item in found]
    except (OSError, subprocess.SubprocessError, ValueError):
        return []
    finally:
        os.unlink(path)   # the screen may show other secrets
