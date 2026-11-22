# SPDX-License-Identifier: GPL-3.0-or-later
"""Seek's index of the words inside your files.

Seek finds files by name by walking the home folder. To find them by what
they say, it keeps a small full-text index in ~/.cache/freemac/seek.db
(SQLite's FTS5 with the trigram tokenizer, so any part of a word matches).
Each time Seek opens, a background thread brings the index up to date:
new and changed files are read again, deleted ones are dropped. Only text
files, OpenDocument and Word documents are read, and only up to a size
limit; hidden folders are skipped, as they are for names.
"""
import html
import os
import re
import sqlite3
import zipfile

from gi.repository import GLib

from . import seek_settings

DB = os.path.join(GLib.get_user_cache_dir(), "freemac", "seek.db")
MAX_BYTES = 2 * 1024 * 1024      # files bigger than this are left out
MAX_FILES = 20000
MAX_DEPTH = 6
TEXT = {".txt", ".md", ".markdown", ".rst", ".org", ".tex", ".csv", ".tsv", ".log", ".json", ".xml",
        ".yaml", ".yml", ".toml", ".ini", ".conf", ".cfg", ".html", ".htm", ".css", ".js", ".ts",
        ".py", ".sh", ".c", ".h", ".cpp", ".hpp", ".rs", ".go", ".java", ".rb", ".pl", ".lua", ".sql",
        ".srt", ".vtt", ".desktop"}
DOCUMENTS = {".odt": "content.xml", ".ods": "content.xml", ".odp": "content.xml", ".docx": "word/document.xml"}
SKIP_DIRS = {"node_modules", "__pycache__", "venv", ".venv", "target", "build"}


def connect():
    os.makedirs(os.path.dirname(DB), exist_ok=True)
    db = sqlite3.connect(DB, timeout=5)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, mtime REAL, size INTEGER)")
    db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS words USING fts5(path UNINDEXED, body, tokenize='trigram')")
    return db


def candidates(home):
    """Paths, mtimes and sizes of the files worth reading."""
    base_depth = home.rstrip(os.sep).count(os.sep)
    count = 0
    private = seek_settings.private()   # Dials > Seek > Privacy
    for root, dirs, files in os.walk(home):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in SKIP_DIRS
                   and not seek_settings.is_private(os.path.join(root, d), private)]
        if root.count(os.sep) - base_depth >= MAX_DEPTH:
            dirs[:] = []
        for name in files:
            ext = os.path.splitext(name)[1].lower()
            if name.startswith(".") or (ext not in TEXT and ext not in DOCUMENTS):
                continue
            path = os.path.join(root, name)
            try:
                st = os.stat(path)
            except OSError:
                continue
            if st.st_size > MAX_BYTES:
                continue
            yield path, st.st_mtime, st.st_size
            count += 1
            if count >= MAX_FILES:
                return


def read_text(path):
    ext = os.path.splitext(path)[1].lower()
    try:
        if ext in DOCUMENTS:
            with zipfile.ZipFile(path) as archive:
                xml = archive.read(DOCUMENTS[ext]).decode("utf-8", "replace")
            # Paragraph ends become spaces so words don't run together.
            xml = re.sub(r"</(text:p|text:h|w:p)>", " ", xml)
            return html.unescape(re.sub(r"<[^>]+>", "", xml))
        with open(path, "rb") as f:
            data = f.read(MAX_BYTES)
        if b"\0" in data[:4096]:
            return None   # binary, whatever its name says
        return data.decode("utf-8", "replace")
    except (OSError, KeyError, zipfile.BadZipFile, RuntimeError):
        return None


def update(home=None, stop=None):
    """Bring the index up to date. Returns how many files were (re)read."""
    home = home or os.path.expanduser("~")
    db = connect()
    if not seek_settings.shown("contents"):
        # Words inside documents is off: keep nothing of what they say.
        db.execute("DELETE FROM words")
        db.execute("DELETE FROM files")
        db.commit()
        db.close()
        return 0
    known = dict(db.execute("SELECT path, mtime FROM files"))
    seen = set()
    changed = 0
    for path, mtime, size in candidates(home):
        if stop is not None and stop.is_set():
            break
        seen.add(path)
        if known.get(path) == mtime:
            continue
        text = read_text(path)
        db.execute("DELETE FROM words WHERE path = ?", (path,))
        if text:
            db.execute("INSERT INTO words (path, body) VALUES (?, ?)", (path, text))
        db.execute("INSERT OR REPLACE INTO files (path, mtime, size) VALUES (?, ?, ?)", (path, mtime, size))
        changed += 1
        if changed % 200 == 0:
            db.commit()
    if stop is None or not stop.is_set():
        for path in set(known) - seen:
            db.execute("DELETE FROM words WHERE path = ?", (path,))
            db.execute("DELETE FROM files WHERE path = ?", (path,))
    db.commit()
    db.close()
    return changed


def excerpt(text, query, width=36):
    """A short piece of text around the first place query appears."""
    at = text.lower().find(query.lower())
    if at < 0:
        return ""
    start = max(0, at - width)
    end = min(len(text), at + len(query) + width)
    piece = " ".join(text[start:end].split())
    return ("…" if start > 0 else "") + piece + ("…" if end < len(text) else "")


def search(query, limit, exclude=()):
    """[(path, excerpt)] of indexed files whose text contains query."""
    if len(query) < 3 or not os.path.exists(DB) or not seek_settings.shown("contents"):
        return []   # the trigram index needs at least three characters
    try:
        db = sqlite3.connect(DB, timeout=1)
        rows = db.execute("SELECT path, body FROM words WHERE body MATCH ? LIMIT ?",
                          ('"' + query.replace('"', '""') + '"', limit + len(exclude))).fetchall()
        db.close()
    except sqlite3.Error:
        return []
    found = []
    private = seek_settings.private()
    for path, body in rows:
        if path in exclude or not os.path.exists(path) or seek_settings.is_private(path, private):
            continue
        found.append((path, excerpt(body, query)))
        if len(found) >= limit:
            break
    return found
