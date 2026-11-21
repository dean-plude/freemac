# SPDX-License-Identifier: GPL-3.0-or-later
"""Reading podcast and news feeds for Buoy (RSS 2.0, RSS 1.0 and Atom), finding
a website's feed from its page, and OPML subscription lists.

Plain Python with no GTK, so it can be tested on its own. Original freemac
code.
"""
import email.utils
import http.client
import hashlib
import html
import html.parser
import re
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

AGENT = "freemac-Buoy/1.36 (+https://github.com/dean-plude/freemac)"
LIMIT = 8 * 1024 * 1024          # the most a feed may be
KEEP = 300                       # items kept per feed
NS = {
    "atom": "http://www.w3.org/2005/Atom",
    "itunes": "http://www.itunes.com/dtds/podcast-1.0.dtd",
    "content": "http://purl.org/rss/1.0/modules/content/",
    "media": "http://search.yahoo.com/mrss/",
    "dc": "http://purl.org/dc/elements/1.1/",
    "rss1": "http://purl.org/rss/1.0/",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
}


class FeedError(Exception):
    """Something people can be told: the reason a feed couldn't be read."""


def normal_url(text):
    """What someone typed -> an http(s) address, or None."""
    text = (text or "").strip()
    if text.startswith("feed://"):
        text = "https://" + text[len("feed://"):]
    elif text.startswith("feed:"):
        text = text[len("feed:"):]
    if "://" not in text:
        text = "https://" + text
    parts = urllib.parse.urlsplit(text)
    try:
        host = parts.hostname or ""
        parts.port                     # raises for a port that isn't a number
    except ValueError:
        return None
    if parts.scheme not in ("http", "https") or not host or " " in parts.netloc \
            or ("." not in host and ":" not in host and host != "localhost"):
        return None
    return text


def fetch(url, timeout=20):
    """(bytes, content type, final address) for url, or FeedError."""
    request = urllib.request.Request(url, headers={"User-Agent": AGENT, "Accept":
                                                   "application/rss+xml, application/atom+xml, application/xml;q=0.9, "
                                                   "text/xml;q=0.9, text/html;q=0.5, */*;q=0.1"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            final = response.geturl()
            if urllib.parse.urlsplit(final).scheme not in ("http", "https"):
                raise FeedError("The address led somewhere Buoy can't read.")
            data = response.read(LIMIT + 1)
            kind = response.headers.get_content_type()
    except FeedError:
        raise
    except urllib.error.HTTPError as err:
        raise FeedError("The site isn't sharing that page right now." if err.code < 500
                        else "The site isn't answering properly right now.") from err
    except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError) as err:
        raise FeedError("The site couldn't be reached. Check the address and your connection.") from err
    if len(data) > LIMIT:
        raise FeedError("That feed is too big to read.")
    return data, kind, final


# Finding a site's feed -----------------------------------------------------------

class _LinkFinder(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.found = []

    def handle_starttag(self, tag, attrs):
        if tag != "link":
            return
        attrs = {k.lower(): (v or "") for k, v in attrs}
        rel = attrs.get("rel", "").lower().split()
        kind = attrs.get("type", "").lower()
        if "alternate" in rel and kind in ("application/rss+xml", "application/atom+xml", "application/feed+json",
                                           "application/rdf+xml") and attrs.get("href"):
            if kind != "application/feed+json":
                self.found.append(attrs["href"])


def feed_links(page, base):
    """The feed addresses a web page points to, most likely first."""
    finder = _LinkFinder()
    try:
        finder.feed(page.decode("utf-8", "replace"))
    except (AssertionError, ValueError):
        pass
    return [urllib.parse.urljoin(base, href) for href in finder.found]


def looks_like_feed(data):
    head = data[:2048].lstrip().lower()
    return head.startswith(b"<?xml") and (b"<rss" in data[:4096].lower() or b"<feed" in data[:4096].lower()
                                          or b"<rdf" in data[:4096].lower()) \
        or head.startswith((b"<rss", b"<feed", b"<rdf"))


def find_feed(text):
    """What someone typed -> (feed address, feed, items). FeedError otherwise."""
    url = normal_url(text)
    if not url:
        raise FeedError("That doesn't look like a web address.")
    try:
        data, kind, final = fetch(url)
    except FeedError:
        typed = (text or "").strip()
        if "://" in typed or typed.startswith("feed:"):
            raise
        url = "http://" + typed           # no scheme typed and https failed: try plain http
        data, kind, final = fetch(url)
    if not looks_like_feed(data) and ("html" in kind or b"<html" in data[:4096].lower()):
        links = feed_links(data, final)
        if not links:
            raise FeedError("That page doesn't offer a feed. Try the address of the podcast's or site's feed.")
        url = links[0]
        data, kind, final = fetch(url)
    feed, items = parse(data, final)
    return final, feed, items


# Reading feeds ----------------------------------------------------------------

def _text(element, path, default=""):
    if element is None:
        return default
    found = element.find(path, NS)
    if found is None:
        return default
    return "".join(found.itertext()).strip() or default


def _date(text):
    text = (text or "").strip()
    if not text:
        return 0
    try:
        value = email.utils.parsedate_to_datetime(text)
    except (TypeError, ValueError, IndexError):
        value = None
    if value is None:
        try:
            value = datetime.fromisoformat(text.replace("Z", "+00:00"))
        except ValueError:
            return 0
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return int(value.timestamp())


def _duration(text):
    """'1:02:03', '62:03' or '3723' -> seconds."""
    text = (text or "").strip()
    try:
        parts = [int(float(p)) for p in text.split(":")]
    except ValueError:
        return 0
    seconds = 0
    for part in parts[-3:]:
        seconds = seconds * 60 + part
    return seconds


def _item_id(link, guid, title, date):
    key = guid or link or f"{title}|{date}"
    return hashlib.sha1(key.encode("utf-8", "replace")).hexdigest()[:20]


def _safe_link(base, link):
    if not link:
        return ""
    link = urllib.parse.urljoin(base, link.strip())
    return link if urllib.parse.urlsplit(link).scheme in ("http", "https") else ""


def parse(data, url):
    """Feed bytes -> (feed dict, [item dicts]), newest first. FeedError if it
    isn't a feed Buoy understands."""
    if b"<!ENTITY" in data[:65536]:
        raise FeedError("That feed uses features Buoy doesn't read, for safety.")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as err:
        raise FeedError("That address isn't a feed Buoy can read.") from err
    tag = root.tag.split("}")[-1].lower()
    if tag == "rss":
        channel = root.find("channel")
        if channel is None:
            raise FeedError("That feed is empty.")
        feed, raw = _rss_channel(channel, url), channel.findall("item")
        items = [_rss_item(i, feed["site"] or url) for i in raw]
    elif tag == "rdf":
        channel = root.find("rss1:channel", NS)
        feed = _rss_channel(channel, url, ns="rss1:") if channel is not None else {"title": "", "site": "",
                                                                                     "about": "", "image": ""}
        items = [_rss_item(i, url, ns="rss1:") for i in root.findall("rss1:item", NS)]
    elif tag == "feed":
        feed = _atom_feed(root, url)
        items = [_atom_entry(e, feed["site"] or url) for e in root.findall("atom:entry", NS)]
    else:
        raise FeedError("That address isn't a feed Buoy can read.")
    if not feed["title"]:
        feed["title"] = urllib.parse.urlsplit(url).netloc or "Feed"
    items = [i for i in items if i["title"] or i["summary"] or i["audio"]]
    items.sort(key=lambda i: i["date"], reverse=True)
    feed["podcast"] = any(i["audio"] for i in items[:10])
    return feed, items[:KEEP]


def _rss_channel(channel, url, ns=""):
    image = channel.find("itunes:image", NS)
    image = image.get("href", "") if image is not None else _text(channel, f"{ns}image/{ns}url")
    return {"title": _text(channel, f"{ns}title"), "site": _safe_link(url, _text(channel, f"{ns}link")),
            "about": _text(channel, f"{ns}description") or _text(channel, "itunes:summary"),
            "image": _safe_link(url, image)}


def _rss_item(item, base, ns=""):
    title = _text(item, f"{ns}title")
    link = _safe_link(base, _text(item, f"{ns}link"))
    guid = _text(item, "guid")
    date = _date(_text(item, "pubDate") or _text(item, "dc:date"))
    body = _text(item, "content:encoded") or _text(item, f"{ns}description") or _text(item, "itunes:summary")
    audio, audio_type = "", ""
    for enclosure in item.findall("enclosure") + item.findall("media:content", NS):
        kind = (enclosure.get("type") or "").lower()
        target = _safe_link(base, enclosure.get("url", ""))
        if target and (kind.startswith(("audio/", "video/")) or re.search(r"\.(mp3|m4a|aac|ogg|oga|opus|mp4)(\?|$)",
                                                                           target, re.I)):
            audio, audio_type = target, kind
            break
    if not link and guid.startswith(("http://", "https://")) and not audio:
        link = guid
    return {"id": _item_id(link, guid, title, date), "title": html.unescape(title), "link": link, "date": date,
            "summary": body, "audio": audio, "audio_type": audio_type,
            "duration": _duration(_text(item, "itunes:duration"))}


def _atom_link(element, base, rel="alternate"):
    for link in element.findall("atom:link", NS):
        if (link.get("rel") or "alternate") == rel:
            return _safe_link(base, link.get("href", "")), (link.get("type") or "").lower()
    return "", ""


def _atom_feed(root, url):
    return {"title": _text(root, "atom:title"), "site": _atom_link(root, url)[0], "about": _text(root, "atom:subtitle"),
            "image": _safe_link(url, _text(root, "atom:logo") or _text(root, "atom:icon"))}


def _atom_entry(entry, base):
    title = _text(entry, "atom:title")
    link = _atom_link(entry, base)[0]
    guid = _text(entry, "atom:id")
    date = _date(_text(entry, "atom:published") or _text(entry, "atom:updated"))
    audio, audio_type = _atom_link(entry, base, "enclosure")
    return {"id": _item_id(link, guid, title, date), "title": html.unescape(title), "link": link, "date": date,
            "summary": _text(entry, "atom:content") or _text(entry, "atom:summary"), "audio": audio,
            "audio_type": audio_type, "duration": 0}


# Subscription lists (OPML) -------------------------------------------------------

def read_opml(data):
    """OPML bytes -> [(title, address)]."""
    if b"<!ENTITY" in data[:65536]:
        raise FeedError("That file uses features Buoy doesn't read, for safety.")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as err:
        raise FeedError("That isn't a subscription list Buoy can read.") from err
    found = []
    for outline in root.iter("outline"):
        url = normal_url(outline.get("xmlUrl") or "")
        if url and outline.get("xmlUrl"):
            found.append((outline.get("title") or outline.get("text") or url, url))
    return found


def write_opml(feeds):
    root = ET.Element("opml", version="2.0")
    head = ET.SubElement(root, "head")
    ET.SubElement(head, "title").text = "Buoy subscriptions"
    ET.SubElement(head, "dateCreated").text = email.utils.formatdate(time.time())
    body = ET.SubElement(root, "body")
    for feed in feeds:
        ET.SubElement(body, "outline", type="rss", text=feed.get("title", ""), title=feed.get("title", ""),
                      xmlUrl=feed.get("url", ""), htmlUrl=feed.get("site", ""))
    return b'<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding="utf-8")


def plain(summary, limit=180):
    """A feed item's HTML -> a line of plain text for the list."""
    text = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", summary or "")
    text = html.unescape(re.sub(r"<[^>]+>", " ", text))
    text = re.sub(r"\s+", " ", text).strip()
    return text if len(text) <= limit else text[:limit - 1].rsplit(" ", 1)[0] + "…"


def clean_html(text, base):
    """A feed item's HTML, with what could run or load a page taken out and
    its links made whole."""
    text = text or ""
    if "<" not in text:                      # plain text: keep its paragraphs
        text = "".join(f"<p>{html.escape(p)}</p>" for p in re.split(r"\n\s*\n", text) if p.strip())
    text = re.sub(r"(?is)<(script|style|iframe|object|embed|form|noscript|frame|frameset|applet|link|meta|base)"
                  r"\b[^>]*>.*?</\1\s*>", " ", text)
    text = re.sub(r"(?is)<(script|style|iframe|object|embed|form|frame|link|meta|base|input|button)\b[^>]*/?>", " ",
                  text)
    text = re.sub(r"(?i)\s+on[a-z]+\s*=\s*(\"[^\"]*\"|'[^']*'|[^\s>]+)", " ", text)

    def whole(match):
        name, quote, value = match.group(1), match.group(2), match.group(3)
        value = urllib.parse.urljoin(base, value.strip()) if base else value
        if not value.lower().startswith(("http:", "https:", "data:image/", "#")):
            value = "#"
        return f"{name}={quote}{value}{quote}"
    return re.sub(r"(?i)\b(src|href)\s*=\s*([\"'])(.*?)\2", whole, text)
