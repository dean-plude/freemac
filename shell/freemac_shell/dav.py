# SPDX-License-Identifier: GPL-3.0-or-later
"""A small WebDAV client for CalDAV and CardDAV (RFC 4791, RFC 6352).

Finds a user's calendars, reminder lists and address books from a server's
address, lists what is in one with each item's ETag, and fetches, puts and
deletes items. Plain HTTP(S) with Basic sign-in; no GTK. Original freemac
code.
"""
import base64
import http.client
import ssl
import urllib.parse
import xml.etree.ElementTree as ET

NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav", "a": "urn:ietf:params:xml:ns:carddav",
      "cs": "http://calendarserver.org/ns/", "ic": "http://apple.com/ns/ical/"}
TIMEOUT = 30

# Where the CalDAV and CardDAV services of well-known providers start.
PROVIDERS = {
    "icloud": ("iCloud", "https://caldav.icloud.com", "https://contacts.icloud.com",
               "Use an app-specific password from your Apple Account settings."),
    "fastmail": ("Fastmail", "https://caldav.fastmail.com", "https://carddav.fastmail.com",
                 "Use an app password from Fastmail's settings."),
    "yahoo": ("Yahoo", "https://caldav.calendar.yahoo.com", "https://carddav.address.yahoo.com",
              "Use an app password from Yahoo's account security page."),
    "nextcloud": ("Nextcloud", "", "", "Type your Nextcloud server's address, like cloud.example.com."),
    "other": ("Other", "", "", "Type the server's address, like dav.example.com."),
}


class DavError(Exception):
    """A failure, in words to show."""


def _q(tag):
    prefix, name = tag.split(":")
    return f"{{{NS[prefix]}}}{name}"


def _body(props, extra=""):
    names = "".join(f"<{p}/>" for p in props)
    return (f'<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:" xmlns:c="{NS["c"]}" '
            f'xmlns:a="{NS["a"]}" xmlns:cs="{NS["cs"]}" xmlns:ic="{NS["ic"]}"><d:prop>{names}</d:prop>'
            f"{extra}</d:propfind>").encode()


class Response:
    def __init__(self, status, headers, body, url):
        self.status, self.headers, self.body, self.url = status, headers, body, url

    def header(self, name):
        return self.headers.get(name.lower())


class Client:
    def __init__(self, username, password):
        token = base64.b64encode(f"{username}:{password}".encode()).decode()
        self.auth = "Basic " + token
        self.conns = {}

    def close(self):
        for conn in self.conns.values():
            conn.close()
        self.conns.clear()

    def _conn(self, parts):
        key = (parts.scheme, parts.netloc)
        if key not in self.conns:
            if parts.scheme == "https":
                self.conns[key] = http.client.HTTPSConnection(parts.netloc, timeout=TIMEOUT,
                                                              context=ssl.create_default_context())
            else:
                self.conns[key] = http.client.HTTPConnection(parts.netloc, timeout=TIMEOUT)
        return self.conns[key]

    def request(self, method, url, body=None, headers=None, ok=(200, 201, 204, 207)):
        """Send one request, following redirects (keeping the method), and
        return a Response; raises DavError for anything not in ok."""
        for _hop in range(6):
            parts = urllib.parse.urlsplit(url)
            if parts.scheme not in ("http", "https") or not parts.netloc:
                raise DavError("That isn't a server address Post or the calendar can use.")
            path = parts.path or "/"
            if parts.query:
                path += "?" + parts.query
            all_headers = {"Authorization": self.auth, "User-Agent": "freemac-sync",
                           "Content-Length": str(len(body or b""))}
            all_headers.update(headers or {})
            for attempt in (1, 2):
                conn = self._conn(parts)
                try:
                    conn.request(method, path, body=body, headers=all_headers)
                    raw = conn.getresponse()
                    data = raw.read()
                    break
                except (http.client.HTTPException, ConnectionError) as error:
                    conn.close()
                    self.conns.pop((parts.scheme, parts.netloc), None)
                    if attempt == 2:
                        raise DavError(f"The server stopped answering ({error}).") from error
                except ssl.SSLError as error:
                    raise DavError("The server's security certificate isn't valid.") from error
                except OSError as error:
                    self.conns.pop((parts.scheme, parts.netloc), None)
                    raise DavError(_explain(error)) from error
            headers_found = {k.lower(): v for k, v in raw.getheaders()}
            if raw.status in (301, 302, 303, 307, 308) and "location" in headers_found:
                url = urllib.parse.urljoin(url, headers_found["location"])
                continue
            if raw.status == 401:
                raise DavError("The user name or password isn't right.")
            if raw.status == 403:
                raise DavError("The server didn't allow that.")
            if raw.status not in ok:
                raise DavError(f"The server answered {raw.status} {raw.reason}.", raw.status)
            return Response(raw.status, headers_found, data, url)
        raise DavError("The server sent Post round in circles.")

    # -- PROPFIND and REPORT ---------------------------------------------------
    def propfind(self, url, props, depth=0, extra=""):
        """{href: {prop tag: element}} for each resource answered."""
        response = self.request("PROPFIND", url, _body(props, extra),
                                {"Depth": str(depth), "Content-Type": "application/xml; charset=utf-8"})
        return response.url, parse_multistatus(response.body)

    def report(self, url, body, depth=1):
        response = self.request("REPORT", url, body, {"Depth": str(depth),
                                                      "Content-Type": "application/xml; charset=utf-8"})
        return parse_multistatus(response.body)


def _explain(error):
    text = str(error)
    if "Name or service not known" in text or "nodename nor servname" in text or "getaddrinfo" in text:
        return "Couldn't find that server. Check its address and the network."
    if "timed out" in text:
        return "The server took too long to answer."
    if "refused" in text:
        return "The server refused the connection."
    return f"Couldn't reach the server ({text})."


def parse_multistatus(data):
    found = {}
    try:
        root = ET.fromstring(data)
    except ET.ParseError:
        return found
    for response in root.findall(_q("d:response")):
        href = response.findtext(_q("d:href"), "").strip()
        props = {}
        for propstat in response.findall(_q("d:propstat")):
            status = propstat.findtext(_q("d:status"), "")
            if " 200 " not in status + " ":
                continue
            for prop in propstat.findall(_q("d:prop")):
                for child in prop:
                    props[child.tag] = child
        found[urllib.parse.unquote(href)] = props
    return found


def _href_of(element):
    if element is None:
        return None
    href = element.findtext(_q("d:href"))
    return href.strip() if href else None


def _text(element):
    return (element.text or "").strip() if element is not None else ""


# -- finding the collections -----------------------------------------------------
def _start_urls(server, service):
    server = server.strip()
    if not server:
        return []
    if "://" not in server:
        server = "https://" + server
    parts = urllib.parse.urlsplit(server)
    base = f"{parts.scheme}://{parts.netloc}"
    urls = []
    if parts.path not in ("", "/"):
        urls.append(server)
    urls += [f"{base}/.well-known/{service}", f"{base}/remote.php/dav", server]
    seen, unique = set(), []
    for url in urls:
        if url not in seen:
            seen.add(url)
            unique.append(url)
    return unique


def _principal(client, server, service):
    last = None
    for url in _start_urls(server, service):
        try:
            where, found = client.propfind(url, ["d:current-user-principal"])
        except DavError as error:
            if "password" in str(error) or "allow" in str(error):
                raise
            last = error
            continue
        for _href, props in found.items():
            principal = _href_of(props.get(_q("d:current-user-principal")))
            if principal:
                return urllib.parse.urljoin(where, principal)
    raise last or DavError("That server doesn't offer calendars or contacts.")


def _home(client, principal, prop):
    where, found = client.propfind(principal, [prop])
    for _href, props in found.items():
        home = _href_of(props.get(_q(prop)))
        if home:
            return urllib.parse.urljoin(where, home)
    return None


def discover_calendars(client, server):
    """[(url, name, color, kinds)] of the user's calendars; kinds holds
    VEVENT and/or VTODO."""
    principal = _principal(client, server, "caldav")
    home = _home(client, principal, "c:calendar-home-set")
    if not home:
        return []
    where, found = client.propfind(home, ["d:resourcetype", "d:displayname", "c:supported-calendar-component-set",
                                          "ic:calendar-color", "d:current-user-privilege-set"], depth=1)
    calendars = []
    for href, props in found.items():
        kinds_el = props.get(_q("d:resourcetype"))
        if kinds_el is None or kinds_el.find(_q("c:calendar")) is None:
            continue
        components = props.get(_q("c:supported-calendar-component-set"))
        kinds = {c.get("name") for c in components} if components is not None else {"VEVENT", "VTODO"}
        name = _text(props.get(_q("d:displayname"))) or href.rstrip("/").rsplit("/", 1)[-1]
        color = _text(props.get(_q("ic:calendar-color")))[:7]
        calendars.append((urllib.parse.urljoin(where, urllib.parse.quote(href)), name, color, kinds))
    return calendars


def discover_addressbooks(client, server):
    """[(url, name)] of the user's address books."""
    principal = _principal(client, server, "carddav")
    home = _home(client, principal, "a:addressbook-home-set")
    if not home:
        return []
    where, found = client.propfind(home, ["d:resourcetype", "d:displayname"], depth=1)
    books = []
    for href, props in found.items():
        kinds_el = props.get(_q("d:resourcetype"))
        if kinds_el is None or kinds_el.find(_q("a:addressbook")) is None:
            continue
        name = _text(props.get(_q("d:displayname"))) or href.rstrip("/").rsplit("/", 1)[-1]
        books.append((urllib.parse.urljoin(where, urllib.parse.quote(href)), name))
    return books


# -- what is in a collection -----------------------------------------------------
def list_items(client, collection, suffix):
    """{absolute url: etag} of the items in a collection (files ending in
    suffix, .ics or .vcf; sub-collections are left out)."""
    where, found = client.propfind(collection, ["d:getetag", "d:resourcetype"], depth=1)
    own = urllib.parse.urlsplit(where).path.rstrip("/")
    items = {}
    for href, props in found.items():
        if href.rstrip("/") == own or href.endswith("/"):
            continue
        kind = props.get(_q("d:resourcetype"))
        if kind is not None and len(kind):
            continue
        url = urllib.parse.urljoin(where, urllib.parse.quote(href))
        if suffix and not href.lower().endswith(suffix) and props.get(_q("d:getetag")) is None:
            continue
        items[url] = _text(props.get(_q("d:getetag")))
    return items


def fetch(client, collection, urls, kind):
    """{url: (text, etag)} for the given items, asked for together
    (calendar-multiget or addressbook-multiget), one by one if the server
    won't."""
    if not urls:
        return {}
    data_tag = "c:calendar-data" if kind == "cal" else "a:address-data"
    root = "c:calendar-multiget" if kind == "cal" else "a:addressbook-multiget"
    hrefs = "".join(f"<d:href>{_xml(urllib.parse.urlsplit(u).path)}</d:href>" for u in urls)
    body = (f'<?xml version="1.0" encoding="utf-8"?><{root} xmlns:d="DAV:" xmlns:c="{NS["c"]}" '
            f'xmlns:a="{NS["a"]}"><d:prop><d:getetag/><{data_tag}/></d:prop>{hrefs}</{root}>').encode()
    got = {}
    try:
        found = client.report(collection, body)
        for href, props in found.items():
            data = props.get(_q(data_tag))
            if data is not None and data.text:
                url = urllib.parse.urljoin(collection, urllib.parse.quote(href))
                got[url] = (data.text, _text(props.get(_q("d:getetag"))))
    except DavError:
        pass
    for url in urls:
        if url not in got:
            try:
                response = client.request("GET", url, ok=(200,))
            except DavError as error:
                if getattr(error, "args", (None, None))[1:] == (404,):
                    continue
                raise
            got[url] = (response.body.decode("utf-8", "replace"), response.header("etag") or "")
    return got


def _xml(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def put(client, url, text, etag=None, kind="cal"):
    """Write an item; etag None makes a new one (and fails if it exists).
    Returns the new ETag, or "" when the server didn't say."""
    headers = {"Content-Type": "text/calendar; charset=utf-8" if kind == "cal" else "text/vcard; charset=utf-8"}
    if etag:
        headers["If-Match"] = etag
    else:
        headers["If-None-Match"] = "*"
    response = client.request("PUT", url, text.encode("utf-8"), headers, ok=(200, 201, 204))
    return response.header("etag") or ""


def delete(client, url, etag=None):
    headers = {"If-Match": etag} if etag else {}
    try:
        client.request("DELETE", url, headers=headers, ok=(200, 204))
    except DavError as error:
        if error.args[1:] in ((404,), (410,)):
            return
        raise
