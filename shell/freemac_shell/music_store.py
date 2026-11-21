# SPDX-License-Identifier: GPL-3.0-or-later
"""Shanty's library: the songs in the Music folder, their titles, artists,
albums and covers. No GTK, so it can be tried without a screen.

Each song's details come from its own tags (ID3 in MP3s, MP4 atoms, Vorbis
comments in FLAC, Ogg and Opus), read with GStreamer's discoverer. Where a
tag is missing the folders stand in: Music/Artist/Album/03 Song.mp3 is the
third song of Album by Artist. An album's cover is the picture inside one of
its songs, or else a cover.jpg, folder.jpg or the only picture in its folder.

What was read about each file is kept in ~/.cache/freemac/music.json, keyed
by its path, size and time, so the next start only reads new and changed
files; covers taken out of songs are kept beside it. Original freemac code.
"""
import hashlib
import json
import os
import re
import threading
import time
import urllib.parse

import gi

from gi.repository import GLib  # noqa: E402

AUDIO_ENDINGS = {".mp3", ".m4a", ".aac", ".flac", ".ogg", ".oga", ".opus", ".wav", ".aif", ".aiff", ".wma"}
PICTURE_ENDINGS = (".jpg", ".jpeg", ".png", ".webp")
COVER_NAMES = ("cover", "folder", "front", "album", "albumart", "artwork")
CACHE_VERSION = 2
RECENT_DAYS = 30
UNKNOWN_ARTIST = "Unknown Artist"
UNKNOWN_ALBUM = "Unknown Album"


def music_dir():
    return GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_MUSIC) or os.path.expanduser("~/Music")


def _cache_dir():
    return os.path.join(GLib.get_user_cache_dir(), "freemac")


def _cache_path():
    return os.path.join(_cache_dir(), "music.json")


def covers_dir():
    return os.path.join(_cache_dir(), "music-covers")


def _read_json(path, empty):
    try:
        with open(path, encoding="utf-8") as f:
            found = json.load(f)
        return found if isinstance(found, type(empty)) else empty
    except (OSError, ValueError):
        return empty


def _write_json(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    new = path + ".new"
    with open(new, "w", encoding="utf-8") as f:
        json.dump(value, f)
    os.replace(new, path)


def is_audio(path):
    return os.path.splitext(path)[1].lower() in AUDIO_ENDINGS


# --- names from files and folders -------------------------------------------

_NUMBER = re.compile(r"^\s*(?:(\d{1,2})[-.](?=\d))?(\d{1,3})(?:\s*[-._)]\s*|\s+)(.+)$")


def from_file_name(path):
    """(track number or 0, title) from a name like "03 - Song.mp3"."""
    stem = os.path.splitext(os.path.basename(path))[0].replace("_", " ").strip()
    found = _NUMBER.match(stem)
    if found and found.group(3).strip():
        return int(found.group(2)), found.group(3).strip()
    return 0, stem


def from_folders(path, root):
    """(artist, album) from where the file sits under the Music folder."""
    folder = os.path.dirname(path)
    rel = os.path.relpath(folder, root)
    parts = [] if rel in (".", "") else rel.split(os.sep)
    if len(parts) >= 2:
        return parts[-2], parts[-1]
    if len(parts) == 1:
        artist, sep, album = parts[0].partition(" - ")
        return (artist.strip(), album.strip()) if sep and album.strip() else ("", parts[0])
    return "", ""


# --- reading tags -------------------------------------------------------------

_gst = None


def _gst_modules():
    """GStreamer and its discoverer, or None if they aren't installed."""
    global _gst
    if _gst is None:
        try:
            gi.require_version("Gst", "1.0")
            gi.require_version("GstPbutils", "1.0")
            from gi.repository import Gst, GstPbutils
            Gst.init(None)
            _gst = (Gst, GstPbutils)
        except (ImportError, ValueError):
            _gst = False
    return _gst or None


def _tag(tags, getter, name):
    try:
        ok, value = getattr(tags, getter)(name)
    except (TypeError, AttributeError):
        return None
    return value if ok else None


def _picture(Gst, tags):
    """The bytes and file ending of a picture inside the tags, if any."""
    best = None
    for name in (Gst.TAG_IMAGE, Gst.TAG_PREVIEW_IMAGE):
        for at in range(tags.get_tag_size(name)):
            sample = tags.get_sample_index(name, at)
            sample = sample[1] if isinstance(sample, tuple) else sample
            if sample is None:
                continue
            buffer = sample.get_buffer()
            ok, info = buffer.map(Gst.MapFlags.READ)
            if not ok:
                continue
            try:
                data = bytes(info.data)
            finally:
                buffer.unmap(info)
            caps = sample.get_caps()
            kind = caps.get_structure(0).get_name() if caps and caps.get_size() else ""
            ending = ".png" if "png" in kind else ".jpg"
            if best is None or len(data) > len(best[0]):
                best = (data, ending)
        if best:
            break
    return best


def read_tags(path, discoverer=None):
    """What a song's own tags say: a dict of the details found (any may be
    missing), with "duration" in seconds and "picture" as (bytes, ending)."""
    mods = _gst_modules()
    if mods is None:
        return {}
    Gst, GstPbutils = mods
    try:
        discoverer = discoverer or GstPbutils.Discoverer.new(5 * Gst.SECOND)
        info = discoverer.discover_uri(GLib.filename_to_uri(path, None))
    except GLib.Error:
        return {}
    found = {}
    duration = info.get_duration()
    if duration and duration != Gst.CLOCK_TIME_NONE:
        found["duration"] = duration / Gst.SECOND
    if not info.get_audio_streams():
        found["no_audio"] = True
    tags = None
    for stream in info.get_stream_list():   # the file's own tags come with its streams
        found_tags = stream.get_tags()
        if found_tags is not None:
            tags = found_tags if tags is None else tags.merge(found_tags, Gst.TagMergeMode.KEEP)
    if tags is None:
        return found
    for key, name in (("title", Gst.TAG_TITLE), ("artist", Gst.TAG_ARTIST), ("album", Gst.TAG_ALBUM),
                      ("album_artist", Gst.TAG_ALBUM_ARTIST), ("genre", Gst.TAG_GENRE)):
        value = _tag(tags, "get_string", name)
        if value and value.strip():
            found[key] = value.strip()
    for key, name in (("track", Gst.TAG_TRACK_NUMBER), ("disc", Gst.TAG_ALBUM_VOLUME_NUMBER)):
        value = _tag(tags, "get_uint", name)
        if value:
            found[key] = int(value)
    when = _tag(tags, "get_date_time", Gst.TAG_DATE_TIME)
    if when is not None and when.has_year():
        found["year"] = when.get_year()
    else:
        date = _tag(tags, "get_date", Gst.TAG_DATE)
        if date is not None and date.valid():
            found["year"] = date.get_year()
    picture = _picture(Gst, tags)
    if picture:
        found["picture"] = picture
    return found


def _save_cover(picture):
    data, ending = picture
    name = hashlib.sha1(data).hexdigest()[:20] + ending
    target = os.path.join(covers_dir(), name)
    if not os.path.exists(target):
        os.makedirs(covers_dir(), exist_ok=True)
        new = target + ".new"
        with open(new, "wb") as f:
            f.write(data)
        os.replace(new, target)
    return target


def folder_cover(folder):
    """A picture file in the folder that is the album's cover, if any."""
    try:
        pictures = sorted(n for n in os.listdir(folder) if n.lower().endswith(PICTURE_ENDINGS))
    except OSError:
        return None
    for want in COVER_NAMES:
        for name in pictures:
            if os.path.splitext(name)[0].lower() == want:
                return os.path.join(folder, name)
    return os.path.join(folder, pictures[0]) if len(pictures) == 1 else None


# --- the library ---------------------------------------------------------------

def _song(path, stat, root, tags):
    number, title = from_file_name(path)
    folder_artist, folder_album = from_folders(path, root)
    artist = tags.get("artist") or tags.get("album_artist") or folder_artist or UNKNOWN_ARTIST
    song = {
        "path": path,
        "size": stat.st_size,
        "mtime": stat.st_mtime,
        "added": min(stat.st_mtime, getattr(stat, "st_ctime", stat.st_mtime)),
        "title": tags.get("title") or title,
        "artist": artist,
        "album": tags.get("album") or folder_album or UNKNOWN_ALBUM,
        "album_artist": tags.get("album_artist") or (artist if tags.get("artist") else folder_artist or artist),
        "track": tags.get("track") or number,
        "disc": tags.get("disc") or 1,
        "year": tags.get("year") or 0,
        "genre": tags.get("genre") or "",
        "duration": round(tags.get("duration") or 0, 2),
        "cover": None,
    }
    if tags.get("picture"):
        try:
            song["cover"] = _save_cover(tags["picture"])
        except OSError:
            pass
    return song


def _files(root):
    for top, dirs, names in os.walk(root, followlinks=True):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for name in sorted(names):
            if not name.startswith(".") and is_audio(name):
                yield os.path.join(top, name)


def scan(root=None, progress=None, stop=None):
    """Every song under the Music folder, as a list of dicts. Only new and
    changed files are read; progress(done, total) is called as they are."""
    root = root or music_dir()
    cache = _read_json(_cache_path(), {})
    known = cache.get("songs", {}) if cache.get("version") == CACHE_VERSION and cache.get("root") == root else {}
    songs, to_read = [], []
    for path in _files(root):
        try:
            stat = os.stat(path)
        except OSError:
            continue
        old = known.get(path)
        if old and old.get("size") == stat.st_size and old.get("mtime") == stat.st_mtime \
                and (not old.get("cover") or os.path.exists(old["cover"])):
            songs.append(old)
        else:
            to_read.append((path, stat))
    if to_read:
        mods = _gst_modules()
        discoverer = None
        if mods:
            Gst, GstPbutils = mods
            try:
                discoverer = GstPbutils.Discoverer.new(5 * Gst.SECOND)
            except GLib.Error:
                discoverer = None
        for at, (path, stat) in enumerate(to_read):
            if stop is not None and stop.is_set():
                break
            tags = read_tags(path, discoverer) if discoverer else {}
            if not tags.get("no_audio"):
                songs.append(_song(path, stat, root, tags))
            if progress:
                progress(at + 1, len(to_read))
    try:
        _write_json(_cache_path(), {"version": CACHE_VERSION, "root": root,
                                    "songs": {s["path"]: s for s in songs}})
    except OSError:
        pass
    return songs


def song_key(song):
    return (song.get("disc", 1), song.get("track") or 999, song["title"].lower(), song["path"])


def album_key(song):
    return (song["album_artist"].lower(), song["album"].lower())


def albums(songs):
    """The songs grouped into albums, newest year first within an artist.
    Each album is a dict: key, title, artist, year, songs, cover, added."""
    grouped = {}
    for song in songs:
        grouped.setdefault(album_key(song), []).append(song)
    found = []
    for key, members in grouped.items():
        members.sort(key=song_key)
        first = members[0]
        cover = next((s["cover"] for s in members if s.get("cover")), None)
        if cover is None:
            for folder in dict.fromkeys(os.path.dirname(s["path"]) for s in members):
                cover = folder_cover(folder)
                if cover:
                    break
        artists = {s["artist"] for s in members}
        artist = first["album_artist"] if len(artists) == 1 or first["album_artist"] != first["artist"] \
            else "Various Artists"
        found.append({
            "key": "\x1f".join(key),
            "title": first["album"],
            "artist": artist,
            "year": max((s.get("year") or 0) for s in members),
            "songs": members,
            "cover": cover,
            "added": max(s.get("added", 0) for s in members),
            "genre": next((s["genre"] for s in members if s.get("genre")), ""),
            "duration": sum(s.get("duration") or 0 for s in members),
        })
    found.sort(key=lambda a: (a["artist"].lower(), a["title"].lower()))
    return found


def artists(album_list):
    """Artist name -> their albums, newest first, in name order."""
    by = {}
    for album in album_list:
        by.setdefault(album["artist"], []).append(album)
    for found in by.values():
        found.sort(key=lambda a: (-(a["year"] or 0), a["title"].lower()))
    return dict(sorted(by.items(), key=lambda item: _sort_name(item[0])))


def _sort_name(name):
    low = name.lower()
    for article in ("the ", "a ", "an "):
        if low.startswith(article) and len(low) > len(article):
            return low[len(article):]
    return low


def recent(album_list, days=RECENT_DAYS, now=None):
    now = now or time.time()
    found = [a for a in album_list if now - a["added"] < days * 86400]
    return sorted(found, key=lambda a: -a["added"])


def matches(song, words):
    text = " ".join((song["title"], song["artist"], song["album"], song.get("genre", ""))).lower()
    return all(w in text for w in words)


def clock(seconds):
    """3:07, or 1:02:09 for an hour or more."""
    seconds = int(round(seconds or 0))
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    return f"{hours}:{minutes:02d}:{secs:02d}" if hours else f"{minutes}:{secs:02d}"


def length_words(seconds):
    minutes = int(round((seconds or 0) / 60))
    if minutes < 60:
        return f"{minutes} minute{'s' if minutes != 1 else ''}"
    hours, minutes = divmod(minutes, 60)
    return f"{hours} hour{'s' if hours != 1 else ''}" + (f" {minutes} min" if minutes else "")


def uri(path):
    return "file://" + urllib.parse.quote(path)


# --- what was playing, kept between starts ------------------------------------

def _state_path():
    return os.path.join(GLib.get_user_config_dir(), "freemac", "shanty.json")


_state_lock = threading.Lock()


def load_state():
    return _read_json(_state_path(), {})


def save_state(state):
    with _state_lock:
        try:
            _write_json(_state_path(), state)
        except OSError:
            pass


if __name__ == "__main__":
    import sys
    started = time.time()
    found = scan(sys.argv[1] if len(sys.argv) > 1 else None)
    for album in albums(found):
        print(f"{album['artist']} — {album['title']} ({album['year'] or '?'}), "
              f"{len(album['songs'])} songs, cover {album['cover']}")
        for song in album["songs"]:
            print(f"   {song['disc']}.{song['track']:02d} {song['title']} [{clock(song['duration'])}]")
    print(f"{len(found)} songs in {time.time() - started:.2f} s")
