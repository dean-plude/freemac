# SPDX-License-Identifier: GPL-3.0-or-later
"""The people Crew keeps, one vCard file each, on this computer.

Cards are kept in ~/.local/share/freemac/contacts/, one .vcf per person, in
vCard 3.0, which every address book app can import. Lines we don't show
(photos, other apps' fields) are kept as they were. No GTK here, so Seek and
other apps can read contacts cheaply. Original freemac code.
"""
import os
import re
import uuid

KINDS = ("home", "work", "mobile", "other")


def store_dir():
    data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(data, "freemac", "contacts")


class Contact:
    def __init__(self, first="", last="", company="", uid=None):
        self.uid = uid or str(uuid.uuid4())
        self.first, self.last, self.company = first, last, company
        self.job = ""
        self.phones = []     # [(kind, number)]
        self.emails = []     # [(kind, address)]
        self.addresses = []  # [(kind, street, city, region, postcode, country)]
        self.birthday = ""   # YYYY-MM-DD, or --MM-DD with no year
        self.notes = ""
        self.extra = []      # lines we don't show, kept as they were
        self.path = None

    @property
    def name(self):
        full = " ".join(p for p in (self.first, self.last) if p)
        return full or self.company or "No Name"

    def sort_key(self):
        return ((self.last or self.first or self.company).lower(), self.first.lower())

    def initials(self):
        letters = [p[0] for p in (self.first, self.last) if p] or [self.name[0]]
        return "".join(letters).upper()

    def copy(self):
        twin = Contact(self.first, self.last, self.company, self.uid)
        twin.job, twin.birthday, twin.notes = self.job, self.birthday, self.notes
        twin.phones, twin.emails = list(self.phones), list(self.emails)
        twin.addresses, twin.extra, twin.path = list(self.addresses), list(self.extra), self.path
        return twin

    def matches(self, words):
        hay = " ".join([self.name, self.company, self.job, self.notes]
                       + [n for _k, n in self.phones] + [a for _k, a in self.emails]
                       + [" ".join(a[1:]) for a in self.addresses]).lower()
        digits = re.sub(r"\D", "", hay)
        return all(w in hay or (w.isdigit() and w in digits) for w in words.lower().split())


# -- reading and writing vCard ----------------------------------------------
def _unescape(text):
    out, i = [], 0
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            n = text[i + 1]
            out.append("\n" if n in "nN" else n)
            i += 2
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def _escape(text):
    return (text.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,")
            .replace("\r\n", "\\n").replace("\n", "\\n"))


def _split(value, sep=";"):
    """Split on sep but not on an escaped one, then unescape each part."""
    parts, current, i = [], "", 0
    while i < len(value):
        c = value[i]
        if c == "\\" and i + 1 < len(value):
            current += value[i:i + 2]
            i += 2
            continue
        if c == sep:
            parts.append(current)
            current = ""
        else:
            current += c
        i += 1
    parts.append(current)
    return [_unescape(p) for p in parts]


def _kind(params):
    types = []
    for key, value in params:
        if key in ("TYPE", "") and value:
            types += value.lower().split(",")
    for t in ("cell", "mobile", "iphone"):
        if t in types:
            return "mobile"
    for t in ("home", "work"):
        if t in types:
            return t
    return "other"


def _lines(text):
    lines = []
    for raw in text.splitlines():
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        elif raw:
            lines.append(raw)
    return lines


def parse(text):
    """Every card in a .vcf (one file can hold many)."""
    cards, card = [], None
    for line in _lines(text):
        head, _sep, value = line.partition(":")
        name, *raw_params = head.split(";")
        group, _dot, name = name.rpartition(".")
        name = name.upper()
        params = []
        for p in raw_params:
            key, eq, val = p.partition("=")
            params.append((key.upper(), val) if eq else ("", key))
        if name == "BEGIN" and value.upper() == "VCARD":
            card = Contact()
            card.uid = None
        elif name == "END" and value.upper() == "VCARD" and card is not None:
            card.uid = card.uid or str(uuid.uuid4())
            if getattr(card, "named", False) is False and card.company and \
                    f"{card.first} {card.last}".strip() == card.company:
                card.first = card.last = ""   # only FN, and it was the company
            cards.append(card)
            card = None
        elif card is None:
            continue
        elif name == "N":
            parts = _split(value) + [""] * 5
            card.last, card.first = parts[0], parts[1]
            card.named = True
        elif name == "FN":
            # FN is only a fallback: a card with N, even an empty one (a
            # company's card), keeps its names from N.
            if not getattr(card, "named", False) and not (card.first or card.last):
                full = _unescape(value).split(" ", 1)
                card.first, card.last = full[0], full[1] if len(full) > 1 else ""
        elif name == "ORG":
            card.company = _split(value)[0]
        elif name == "TITLE":
            card.job = _unescape(value)
        elif name == "TEL":
            card.phones.append((_kind(params), _unescape(value)))
        elif name == "EMAIL":
            card.emails.append((_kind(params), _unescape(value)))
        elif name == "ADR":
            parts = _split(value) + [""] * 7
            card.addresses.append((_kind(params), parts[2], parts[3], parts[4], parts[5], parts[6]))
        elif name == "BDAY":
            v = value.strip()
            if re.fullmatch(r"\d{8}", v):
                v = f"{v[:4]}-{v[4:6]}-{v[6:]}"
            card.birthday = v[:10]
        elif name == "NOTE":
            card.notes = _unescape(value)
        elif name == "UID":
            card.uid = value.strip()
        elif name not in ("VERSION", "PRODID", "REV"):
            card.extra.append(line)
    return cards


def _fold(line):
    out = []
    while len(line.encode()) > 74:
        cut = 74
        while len(line[:cut].encode()) > 74:
            cut -= 1
        out.append(line[:cut])
        line = " " + line[cut:]
    out.append(line)
    return out


def dump(card):
    kind = {"mobile": "CELL", "home": "HOME", "work": "WORK", "other": "OTHER"}
    lines = ["BEGIN:VCARD", "VERSION:3.0", "PRODID:-//freemac//Crew//EN",
             f"UID:{card.uid}",
             f"N:{_escape(card.last)};{_escape(card.first)};;;",
             f"FN:{_escape(card.name)}"]
    if card.company:
        lines.append(f"ORG:{_escape(card.company)}")
    if card.job:
        lines.append(f"TITLE:{_escape(card.job)}")
    for k, number in card.phones:
        lines.append(f"TEL;TYPE={kind[k]}:{_escape(number)}")
    for k, address in card.emails:
        lines.append(f"EMAIL;TYPE={'INTERNET' if k == 'other' else kind[k]}:{_escape(address)}")
    for k, street, city, region, code, country in card.addresses:
        parts = ";".join(_escape(p) for p in ("", "", street, city, region, code, country))
        lines.append(f"ADR;TYPE={kind[k]}:{parts}")
    if card.birthday:
        lines.append(f"BDAY:{card.birthday}")
    if card.notes:
        lines.append(f"NOTE:{_escape(card.notes)}")
    lines += card.extra
    lines.append("END:VCARD")
    folded = []
    for line in lines:
        folded += _fold(line)
    return "\r\n".join(folded) + "\r\n"


def load():
    cards = []
    folder = store_dir()
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return []
    for name in names:
        if not name.endswith(".vcf"):
            continue
        path = os.path.join(folder, name)
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                found = parse(f.read())
        except OSError:
            continue
        for card in found[:1]:
            card.path = path
            cards.append(card)
    return sorted(cards, key=Contact.sort_key)


def save(card):
    folder = store_dir()
    os.makedirs(folder, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", card.uid)[:80]
    card.path = card.path or os.path.join(folder, safe + ".vcf")
    temp = card.path + ".new"
    with open(temp, "w", encoding="utf-8", newline="") as f:
        f.write(dump(card))
    os.replace(temp, card.path)


def delete(card):
    if card.path:
        try:
            os.remove(card.path)
        except OSError:
            pass


def birthdays(cards):
    """(month, day, card) for each card with a birthday."""
    found = []
    for card in cards:
        m = re.search(r"(\d{2})-(\d{2})$", card.birthday or "")
        if m:
            found.append((int(m.group(1)), int(m.group(2)), card))
    return found
