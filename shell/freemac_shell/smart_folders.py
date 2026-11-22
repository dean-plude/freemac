# SPDX-License-Identifier: GPL-3.0-or-later
"""Searches in Drawer, and Smart Folders: searches kept in the sidebar.

Type in a Drawer window's search box and choose This Mac to look through
all your files at once, by name and, for documents Seek has read, by what
they say. A kind (Images, Documents, PDF…) and a time (changed today, in the
past week…) narrow it down, and either works without any words: "every
picture from the past week". Save keeps the search as a Smart Folder in the
sidebar, which looks again each time it's opened, so it always shows what
matches now, as a Mac's Smart Folders do.

A search is a place, as Recents and the tags are:
    search:?text=tax&kind=pdf&when=year   a search being typed
    smart:Tax papers                      a Smart Folder kept by name
Smart Folders are kept in ~/.config/freemac/smart-folders.json.
Original freemac code.
"""
import json
import os
import time
from urllib.parse import parse_qsl, urlencode

from gi.repository import Gio, GLib

from . import seek_index

PREFIX = "search:"
SAVED = "smart:"
FILE = os.path.join(GLib.get_user_config_dir(), "freemac", "smart-folders.json")

KINDS = (("any", "Any Kind"), ("document", "Documents"), ("pdf", "PDF Documents"), ("image", "Images"),
         ("music", "Music"), ("movie", "Movies"), ("folder", "Folders"))
WHEN = (("any", "Any Time"), ("today", "Today"), ("week", "Past 7 Days"), ("month", "Past 30 Days"),
        ("year", "Past Year"))
DAYS = {"week": 7, "month": 30, "year": 365}

LIMIT = 1000          # results shown, at most
MAX_SEEN = 150000     # files looked at before giving up
MAX_DEPTH = 12
SKIP_DIRS = seek_index.SKIP_DIRS | {"Trash"}
DOCUMENTS = {".txt", ".md", ".rtf", ".odt", ".ods", ".odp", ".doc", ".docx", ".xls", ".xlsx", ".ppt",
             ".pptx", ".csv", ".pages", ".numbers", ".key", ".epub", ".tex", ".html", ".htm", ".pdf"}


def home():
    return GLib.get_home_dir()


def is_place(path):
    return bool(path) and (path.startswith(PREFIX) or path.startswith(SAVED))


def blank():
    return {"text": "", "kind": "any", "when": "any", "where": home()}


def clean(query):
    """The query with every field present and sensible."""
    full = blank()
    for key in full:
        value = (query or {}).get(key)
        if isinstance(value, str):
            full[key] = value
    if full["kind"] not in dict(KINDS):
        full["kind"] = "any"
    if full["when"] not in dict(WHEN):
        full["when"] = "any"
    full["where"] = os.path.abspath(os.path.expanduser(full["where"] or home()))
    full["text"] = " ".join(full["text"].split())
    return full


def place(query):
    """The place that shows this search."""
    query = clean(query)
    shown = {k: v for k, v in query.items() if v != blank()[k]}
    return PREFIX + ("?" + urlencode(sorted(shown.items())) if shown else "")


def query_of(path):
    """The search a place shows; None for a Smart Folder that's gone."""
    if path.startswith(SAVED):
        for entry in load():
            if entry["name"] == path[len(SAVED):]:
                return clean(entry)
        return None
    rest = path[len(PREFIX):].lstrip("?")
    return clean(dict(parse_qsl(rest)))


def is_empty(query):
    return not query["text"] and query["kind"] == "any" and query["when"] == "any"


def title(path):
    if path.startswith(SAVED):
        return path[len(SAVED):]
    query = query_of(path)
    if query["text"]:
        return f"Searching “{query['text']}”"
    if not is_empty(query):
        return describe(query)
    return "New Smart Folder"


# ---- the Smart Folders kept --------------------------------------------
def load():
    try:
        with open(FILE, encoding="utf-8") as f:
            entries = json.load(f)
    except (OSError, ValueError):
        return []
    if not isinstance(entries, list):
        return []
    return [e for e in entries if isinstance(e, dict) and isinstance(e.get("name"), str) and e["name"]]


def _store(entries):
    os.makedirs(os.path.dirname(FILE), exist_ok=True)
    temp = FILE + ".new"
    with open(temp, "w", encoding="utf-8") as f:
        json.dump(entries, f, indent=1, ensure_ascii=False)
    os.replace(temp, FILE)


def save(name, query):
    """Keep the search under this name (replacing one by the same name);
    returns the Smart Folder's place."""
    name = " ".join(name.replace("/", "-").split())
    entry = dict(clean(query), name=name)
    entries = [e for e in load() if e["name"] != name]
    entries.append(entry)
    _store(entries)
    return SAVED + name


def remove(name):
    _store([e for e in load() if e["name"] != name])


def rename(old, new):
    new = " ".join(new.replace("/", "-").split())
    entries = load()
    if not new or any(e["name"] == new for e in entries):
        return False
    for entry in entries:
        if entry["name"] == old:
            entry["name"] = new
    _store(entries)
    return True


def unused_name(base="Untitled Smart Folder"):
    taken = {e["name"] for e in load()}
    name, n = base, 2
    while name in taken:
        name, n = f"{base} {n}", n + 1
    return name


# ---- looking -----------------------------------------------------------
def kind_of(name, is_dir):
    if is_dir:
        return "folder"
    ext = os.path.splitext(name)[1].lower()
    if ext == ".pdf":
        return "pdf"
    content, _uncertain = Gio.content_type_guess(name, None)
    content = content or ""
    for prefix, kind in (("image/", "image"), ("audio/", "music"), ("video/", "movie")):
        if content.startswith(prefix):
            return kind
    if ext in DOCUMENTS or content.startswith("text/"):
        return "document"
    return "other"


def _fits_kind(want, name, is_dir):
    if want == "any":
        return True
    kind = kind_of(name, is_dir)
    return kind == want or (want == "document" and kind == "pdf")


def _since(when, now=None):
    now = now or time.time()
    if when == "today":
        local = time.localtime(now)
        return time.mktime((local.tm_year, local.tm_mon, local.tm_mday, 0, 0, 0, 0, 0, -1))
    return now - DAYS[when] * 86400 if when in DAYS else 0


def matches(query, path, is_dir, mtime, by_content=False):
    name = os.path.basename(path)
    if query["text"] and not by_content:
        folded = name.casefold()
        if not all(word in folded for word in query["text"].casefold().split()):
            return False
    if not _fits_kind(query["kind"], name, is_dir):
        return False
    return mtime >= _since(query["when"])


def find(query, found, stop=None, limit=LIMIT):
    """Calls found(path) for each match, names first, then files whose words
    match; returns how many. Hidden folders, the Trash and build folders are
    left out, as they are in Seek."""
    query = clean(query)
    if is_empty(query):
        return 0
    where = query["where"]
    seen, count, given = 0, 0, set()
    base = where.rstrip(os.sep).count(os.sep)
    for root, dirs, files in os.walk(where):
        if stop is not None and stop.is_set():
            return count
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d not in SKIP_DIRS)
        if root.count(os.sep) - base >= MAX_DEPTH:
            dirs[:] = []
        for name, is_dir in [(d, True) for d in dirs] + [(f, False) for f in files if not f.startswith(".")]:
            seen += 1
            path = os.path.join(root, name)
            try:
                mtime = os.lstat(path).st_mtime
            except OSError:
                continue
            if matches(query, path, is_dir, mtime):
                found(path)
                given.add(path)
                count += 1
                if count >= limit:
                    return count
        if seen >= MAX_SEEN:
            break
    # Then what the words inside documents match, from Seek's index.
    if len(query["text"]) >= 3:
        inside = where.rstrip(os.sep) + os.sep
        for path, _excerpt in seek_index.search(query["text"], limit - count, exclude=given):
            if stop is not None and stop.is_set():
                break
            if not path.startswith(inside):
                continue
            try:
                mtime = os.stat(path).st_mtime
            except OSError:
                continue
            if matches(query, path, False, mtime, by_content=True):
                found(path)
                count += 1
    return count


def describe(query, lead=""):
    """In words, for the status bar: “Images changed in the past 7 days”, or
    with lead="No": “No images changed in the past 7 days”."""
    query = clean(query)
    kind = dict(KINDS)[query["kind"]] if query["kind"] != "any" else "Items"
    if lead:
        kind = lead + " " + (kind if kind.startswith("PDF") else kind.lower())
    parts = [kind]
    if query["text"]:
        parts.append(f"matching “{query['text']}”")
    if query["when"] != "any":
        parts.append("changed today" if query["when"] == "today"
                     else "changed in the " + dict(WHEN)[query["when"]].lower())
    return " ".join(parts)
