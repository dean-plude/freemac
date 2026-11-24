# SPDX-License-Identifier: GPL-3.0-or-later
"""Messages' iMessage backend: iMessage through BlueBubbles (no GTK).

BlueBubbles Server is a free, open-source app that runs on a Mac the person
owns and signs in to their own Apple account there. It offers a documented
REST API and a Socket.IO event stream; this module is a client for those,
written from BlueBubbles' public documentation. freemac never talks to Apple
and has nothing of Apple's: the Mac and its Messages app do the iMessage
part, and freemac only reads and writes through the server.

* REST (the server's password goes in the query, as the docs say):
  GET  /api/v1/ping                         is it there, is the password right
  GET  /api/v1/server/info                  whether the Private API is on
  POST /api/v1/chat/query                   conversations, with their last message
  GET  /api/v1/chat/<guid>/message          one conversation's messages
  POST /api/v1/message/query                messages since a time (catching up)
  POST /api/v1/message/text                 send into a conversation
  POST /api/v1/message/attachment           send a file into a conversation (multipart form:
                                            chatGuid, tempGuid, name, method, attachment)
  POST /api/v1/message/react                add or take back a tapback (needs the Private API)
  POST /api/v1/chat/new                     start a conversation with addresses
  POST /api/v1/chat/<guid>/read             mark read (needs the Private API)
  GET  /api/v1/attachment/<guid>/download   an attachment's file
* Events: Socket.IO (Engine.IO 4) over a websocket at /socket.io/, with
  "new-message", "updated-message" (delivered and read),
  "message-send-error" and "typing-indicator" ({"guid": chat, "display": on},
  which the server sends while its Private API is on). The websocket is
  python3-websocket's; without it, or while it can't connect, the server is
  asked every 15 seconds instead.
* Reactions (tapbacks) are messages of their own whose associatedMessageGuid
  names the message they're on ("p:0/<guid>", or "bp:<guid>") and whose
  associatedMessageType says which: love, like, dislike, laugh, emphasize,
  question (or 2000-2005 on older servers), "-love" and so on (3000-3005)
  taking one back, and 2006 or "emoji" with associatedMessageEmoji.

Original freemac code.
"""
import json
import os
import re
import threading
import urllib.error
import urllib.parse
import urllib.request
import uuid

from . import messages_store as store

try:
    import websocket          # python3-websocket (websocket-client)
except ImportError:           # polling only
    websocket = None

POLL_EVERY = 15
TIMEOUT = 20
UPLOAD_TIMEOUT = 300
MAX_UPLOAD = 100 * 1024 * 1024
NUMBERED_REACTIONS = {2000 + i: kind for i, kind in enumerate(store.REACTION_KINDS + ("emoji",))}


class ServerError(Exception):
    pass


def service_of(guid, fallback="imessage"):
    prefix = (guid or "").split(";", 1)[0].lower()
    return {"imessage": "imessage", "sms": "sms", "rcs": "rcs"}.get(prefix, fallback)


def normalise_url(url):
    url = (url or "").strip().rstrip("/")
    if url and "://" not in url:
        url = "http://" + url
    parts = urllib.parse.urlsplit(url)
    if parts.scheme not in ("http", "https") or not parts.netloc:
        raise ValueError("Type the server's address, such as http://192.168.1.20:1234.")
    return url


def is_reaction(raw):
    kind = raw.get("associatedMessageType")
    return bool(raw.get("associatedMessageGuid")) and kind not in (None, "", 0, "0")


def reaction_kind(raw):
    """(kind, taken back) from a message's associatedMessageType, or (None, False)
    for anything that isn't a tapback (stickers and the like)."""
    kind = raw.get("associatedMessageType")
    if isinstance(kind, str) and kind.lstrip("-").isdigit():
        kind = int(kind)
    if isinstance(kind, int):
        if kind in NUMBERED_REACTIONS:
            return NUMBERED_REACTIONS[kind], False
        if kind - 1000 in NUMBERED_REACTIONS:
            return NUMBERED_REACTIONS[kind - 1000], True
        return None, False
    kind = (kind or "").strip().lower()
    removed = kind.startswith("-")
    kind = kind.lstrip("-")
    return (kind, removed) if kind in store.REACTION_KINDS + ("emoji",) else (None, False)


def reaction_target(guid):
    """'p:0/ABC' or 'bp:ABC' -> 'ABC'."""
    guid = guid or ""
    if "/" in guid:
        return guid.split("/", 1)[1]
    return guid[3:] if guid.startswith("bp:") else guid


def _chat_guid_of(raw, chat_guid):
    if chat_guid is None:
        chats = raw.get("chats") or []
        chat_guid = chats[0].get("guid") if chats and isinstance(chats[0], dict) else None
    return chat_guid


def convert_reaction(raw, chat_guid=None):
    """A tapback message -> Reaction (None for anything else)."""
    if not isinstance(raw, dict) or not raw.get("guid") or not is_reaction(raw):
        return None
    chat_guid = _chat_guid_of(raw, chat_guid)
    kind, removed = reaction_kind(raw)
    target = reaction_target(raw.get("associatedMessageGuid"))
    if not chat_guid or kind is None or not target:
        return None
    handle = raw.get("handle") if isinstance(raw.get("handle"), dict) else {}
    from_me = bool(raw.get("isFromMe"))
    emoji = str(raw.get("associatedMessageEmoji") or "") if kind == "emoji" else ""
    if kind == "emoji" and not emoji and not removed:
        return None
    return store.Reaction(id=f"bb:{raw['guid']}", chat_id=f"bb:{chat_guid}", target=f"bb:{target}",
                          kind="" if removed else kind, emoji=emoji, from_me=from_me,
                          sender="" if from_me else (handle.get("address") or ""),
                          date=int(raw.get("dateCreated") or 0))


def convert_any(raw, chat_guid=None, names=None):
    """A message or a tapback (None for anything else)."""
    if isinstance(raw, dict) and is_reaction(raw):
        return convert_reaction(raw, chat_guid)
    return convert_message(raw, chat_guid, names)


def multipart(fields, file_field, filename, mime, data):
    """(body, content type) of a multipart/form-data upload."""
    boundary = "freemac-" + uuid.uuid4().hex
    safe = re.sub(r'[\r\n"\\]+', "_", filename) or "attachment"
    out = []
    for name, value in fields.items():
        value = re.sub(r"[\r\n]+", " ", str(value))
        out.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'
                   .encode("utf-8"))
    out.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{file_field}"; filename="{safe}"\r\n'
               f'Content-Type: {mime or "application/octet-stream"}\r\n\r\n'.encode("utf-8"))
    out.append(data)
    out.append(f"\r\n--{boundary}--\r\n".encode("utf-8"))
    return b"".join(out), f"multipart/form-data; boundary={boundary}"


def convert_message(raw, chat_guid=None, names=None):
    """One BlueBubbles message dict -> Message (None for reactions and the like)."""
    if not isinstance(raw, dict) or not raw.get("guid") or is_reaction(raw):
        return None
    if chat_guid is None:
        chats = raw.get("chats") or []
        chat_guid = chats[0].get("guid") if chats and isinstance(chats[0], dict) else None
    if not chat_guid:
        return None
    handle = raw.get("handle") if isinstance(raw.get("handle"), dict) else {}
    from_me = bool(raw.get("isFromMe"))
    service = service_of(chat_guid, service_of((handle.get("service") or "") + ";"))
    if from_me:
        if raw.get("error"):
            status, when = "failed", 0
        elif raw.get("dateRead"):
            status, when = "read", int(raw["dateRead"])
        elif raw.get("dateDelivered"):
            status, when = "delivered", int(raw["dateDelivered"])
        else:
            status, when = "sent", 0
    else:
        status, when = "received", 0
    attachments = []
    for part in raw.get("attachments") or []:
        if isinstance(part, dict) and part.get("guid"):
            attachments.append({"id": part["guid"], "name": part.get("transferName") or "Attachment",
                                "mime": part.get("mimeType") or "", "path": "",
                                "size": int(part["totalBytes"]) if str(part.get("totalBytes")).isdigit() else 0})
    text = (raw.get("text") or "").replace("￼", "").strip()
    return store.Message(id=f"bb:{raw['guid']}", chat_id=f"bb:{chat_guid}", text=text,
                         date=int(raw.get("dateCreated") or 0), from_me=from_me,
                         sender="" if from_me else (handle.get("address") or ""), service=service,
                         status=status, status_date=when, read=from_me or bool(raw.get("dateRead")),
                         attachments=attachments, remote_id=raw["guid"])


def convert_chat(raw, names=None):
    names = names or {}
    guid = raw.get("guid")
    if not guid:
        return None, None
    addresses = [p.get("address") for p in raw.get("participants") or [] if isinstance(p, dict) and p.get("address")]
    if not addresses and raw.get("chatIdentifier"):
        addresses = [raw["chatIdentifier"]]
    title = raw.get("displayName") or ", ".join(names.get(store.normalise_address(a)) or store.format_address(a)
                                                 for a in addresses)
    chat = store.Chat(id=f"bb:{guid}", backend="bluebubbles", title=title, addresses=addresses,
                      service=service_of(guid), remote_id=guid)
    last = convert_message(raw.get("lastMessage") or {}, guid) if raw.get("lastMessage") else None
    if last:
        chat.last_date, chat.last_text = last.date, last.text or store.attachment_summary(last)
    return chat, last


class BlueBubbles:
    """Listener calls (on this backend's threads):
      backend_status(backend, text, connected)
      backend_data(backend, [Chat], [Message])
      backend_sent(backend, temp_id, Message or None, error text, chat id)
      backend_attachment(backend, message_id, attachment_id, path)
      backend_typing(backend, chat id, on)
      backend_error(backend, text)              something the person asked for didn't work
    """
    kind = "bluebubbles"

    def __init__(self, listener, url, password, names=None, attachments_dir=None, poll_every=POLL_EVERY):
        self.listener = listener
        self.url = normalise_url(url)
        self.password = password
        self.names = names or {}
        self.attachments_dir = attachments_dir or os.path.join(store.data_dir(), "bluebubbles")
        self.poll_every = poll_every
        self.stopping = threading.Event()
        self.private_api = False
        self.socket_up = False
        self.since = 0
        self.ws = None

    # -- REST ---------------------------------------------------------------------
    def _request(self, method, path, body=None, query=None, raw=False, upload=None):
        """upload: (body bytes, content type) instead of a JSON body."""
        params = dict(query or {})
        params["password"] = self.password
        url = f"{self.url}{path}?{urllib.parse.urlencode(params)}"
        if upload is not None:
            data, content_type = upload
        else:
            data = json.dumps(body).encode("utf-8") if body is not None else None
            content_type = "application/json"
        request = urllib.request.Request(url, data=data, method=method,
                                         headers={"Content-Type": content_type,
                                                  "User-Agent": "freemac-messages"})
        try:
            with urllib.request.urlopen(request, timeout=UPLOAD_TIMEOUT if upload else TIMEOUT) as reply:
                payload = reply.read()
        except urllib.error.HTTPError as e:
            if e.code == 401:
                raise ServerError("The server's password isn't right.") from None
            try:
                message = json.loads(e.read().decode("utf-8")).get("message")
            except (ValueError, AttributeError, OSError):
                message = None
            raise ServerError(message or f"The server answered {e.code}.") from None
        except (urllib.error.URLError, OSError, ValueError) as e:
            raise ServerError(f"Couldn't reach the server ({getattr(e, 'reason', e)}).") from None
        if raw:
            return payload
        try:
            found = json.loads(payload.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            raise ServerError("The server's answer couldn't be read.") from None
        return found.get("data") if isinstance(found, dict) else None

    def check(self):
        """Raises ServerError when the server can't be used."""
        self._request("GET", "/api/v1/ping")
        try:
            info = self._request("GET", "/api/v1/server/info") or {}
            self.private_api = bool(info.get("private_api"))
        except ServerError:
            self.private_api = False

    def fetch_chats(self, limit=100):
        found = self._request("POST", "/api/v1/chat/query",
                              {"limit": limit, "offset": 0, "with": ["lastMessage", "participants"],
                               "sort": "lastmessage"}) or []
        chats, messages = [], []
        for raw in found:
            chat, last = convert_chat(raw, self.names)
            if chat:
                chats.append(chat)
            if last:
                messages.append(last)
        return chats, messages

    def fetch_messages(self, guid, limit=100, before=None):
        query = {"limit": limit, "offset": 0, "sort": "DESC", "with": "handle,attachment"}
        if before:
            query["before"] = int(before)
        found = self._request("GET", f"/api/v1/chat/{urllib.parse.quote(guid, safe='')}/message", query=query) or []
        return [m for m in (convert_any(r, guid, self.names) for r in found) if m]

    def fetch_since(self, after):
        found = self._request("POST", "/api/v1/message/query",
                              {"limit": 200, "offset": 0, "after": int(after), "sort": "ASC",
                               "with": ["chat", "handle", "attachment"]}) or []
        return [m for m in (convert_any(r, None, self.names) for r in found) if m]

    # -- running --------------------------------------------------------------------
    def start(self, since=0):
        self.since = since
        threading.Thread(target=self._run, daemon=True).start()

    def stop(self):
        self.stopping.set()
        ws = self.ws
        if ws is not None:
            try:
                ws.close()
            except Exception:   # noqa: BLE001
                pass

    def _run(self):
        backoff = 2
        while not self.stopping.is_set():
            try:
                self.check()
                chats, messages = self.fetch_chats()
                if self.since:
                    messages += self.fetch_since(self.since)
                self._deliver(chats, messages)
            except ServerError as e:
                self.listener.backend_status(self.kind, str(e), False)
                self.stopping.wait(backoff)
                backoff = min(backoff * 2, 120)
                continue
            backoff = 2
            self.listener.backend_status(self.kind, "Connected to BlueBubbles", True)
            if websocket is not None:
                self._listen()      # returns when the socket drops
            if self.stopping.is_set():
                return
            # No socket (or it dropped): ask now and then until it's back.
            for _ in range(4):
                if self.stopping.wait(self.poll_every):
                    return
                try:
                    self._deliver([], self.fetch_since(self.since))
                except ServerError as e:
                    self.listener.backend_status(self.kind, str(e), False)
                    break

    def _deliver(self, chats, messages):
        if messages:
            self.since = max(self.since, max(m.date for m in messages))
        if chats or messages:
            known = {c.id for c in chats}
            missing = {m.chat_id for m in messages} - known
            if missing:
                try:
                    more, _last = self.fetch_chats()
                    chats = chats + [c for c in more if c.id in missing]
                except ServerError:
                    pass
            self.listener.backend_data(self.kind, chats, messages)

    def refresh(self):
        def run():
            try:
                self._deliver(*self.fetch_chats())
            except ServerError as e:
                self.listener.backend_status(self.kind, str(e), False)
        threading.Thread(target=run, daemon=True).start()

    def load_conversation(self, chat, before=None, count=100):
        def run():
            try:
                self.listener.backend_data(self.kind, [], self.fetch_messages(chat.remote_id, count, before))
            except ServerError as e:
                self.listener.backend_status(self.kind, str(e), False)
        threading.Thread(target=run, daemon=True).start()

    def mark_read(self, chat):
        if not self.private_api:
            return

        def run():
            try:
                self._request("POST", f"/api/v1/chat/{urllib.parse.quote(chat.remote_id, safe='')}/read", {})
            except ServerError:
                pass
        threading.Thread(target=run, daemon=True).start()

    # -- sending ----------------------------------------------------------------------
    def send_to_chat(self, chat, text, temp_id):
        method = "private-api" if self.private_api else "apple-script"

        def call():
            raw = self._request("POST", "/api/v1/message/text",
                                {"chatGuid": chat.remote_id, "tempGuid": temp_id, "message": text, "method": method})
            return raw, chat.remote_id
        self._send(call, temp_id)

    def send_new(self, addresses, text, temp_id, service="iMessage"):
        """A first message to these addresses; the server makes the conversation."""
        method = "private-api" if self.private_api else "apple-script"

        def call():
            found = self._request("POST", "/api/v1/chat/new",
                                  {"addresses": list(addresses), "message": text, "service": service,
                                   "method": method, "tempGuid": temp_id}) or {}
            chat, _last = convert_chat(found, self.names) if isinstance(found, dict) else (None, None)
            if chat is None:
                return None, None
            self.listener.backend_data(self.kind, [chat], [])
            return found.get("lastMessage"), chat.remote_id
        self._send(call, temp_id)

    def send_attachment(self, chat, path, temp_id, mime=""):
        """A picture or file into a conversation, with the documented upload."""
        method = "private-api" if self.private_api else "apple-script"
        name = os.path.basename(path)

        def call():
            try:
                if os.path.getsize(path) > MAX_UPLOAD:
                    raise ServerError(f"“{name}” is too big to send (100 MB at most).")
                with open(path, "rb") as f:
                    data = f.read()
            except OSError as e:
                raise ServerError(f"“{name}” couldn't be read ({e.strerror or e}).") from None
            upload = multipart({"chatGuid": chat.remote_id, "tempGuid": temp_id, "name": name, "method": method},
                               "attachment", name, mime, data)
            raw = self._request("POST", "/api/v1/message/attachment", upload=upload)
            return raw, chat.remote_id
        self._send(call, temp_id)

    def can_react(self):
        return self.private_api

    def react(self, chat, message, kind, remove=False):
        """Adds (or, with remove, takes back) a tapback on message. Needs the
        Private API; the server's copy comes back as a Reaction."""
        if not self.private_api:
            raise ConnectionError("Tapbacks need the BlueBubbles Private API turned on on your Mac.")
        if kind not in store.REACTION_KINDS:
            raise ValueError(kind)

        def run():
            try:
                raw = self._request("POST", "/api/v1/message/react",
                                    {"chatGuid": chat.remote_id, "selectedMessageGuid": message.remote_id,
                                     "reaction": ("-" if remove else "") + kind, "partIndex": 0})
            except ServerError as e:
                self.listener.backend_error(self.kind, f"The tapback couldn't be sent. {e}")
                return
            reaction = convert_reaction(raw, chat.remote_id) if isinstance(raw, dict) else None
            if reaction is None:      # no copy back: say what we did ourselves
                reaction = store.Reaction(id=f"bb:sent-{uuid.uuid4()}", chat_id=chat.id, target=message.id,
                                          kind="" if remove else kind, from_me=True, date=store.now_ms())
            self.listener.backend_data(self.kind, [], [reaction])
        threading.Thread(target=run, daemon=True).start()

    def _send(self, call, temp_id):
        def run():
            try:
                raw, chat_guid = call()
            except ServerError as e:
                self.listener.backend_sent(self.kind, temp_id, None, str(e), "")
                return
            message = convert_message(raw, chat_guid, self.names) if isinstance(raw, dict) else None
            # Without a copy (message None) it was still sent, into chat_id.
            self.listener.backend_sent(self.kind, temp_id, message, "", f"bb:{chat_guid}" if chat_guid else "")
        threading.Thread(target=run, daemon=True).start()

    def download(self, message_id, attachment):
        def run():
            try:
                data = self._request("GET", f"/api/v1/attachment/{urllib.parse.quote(attachment['id'], safe='')}"
                                     "/download", raw=True)
            except ServerError as e:
                self.listener.backend_status(self.kind, str(e), self.socket_up)
                return
            os.makedirs(self.attachments_dir, mode=0o700, exist_ok=True)
            name = re.sub(r"[^\w.\-]+", "_", os.path.basename(attachment.get("name") or "attachment"))
            path = os.path.join(self.attachments_dir, f"{attachment['id'][:12]}-{name}")
            with open(path, "wb") as f:
                f.write(data)
            self.listener.backend_attachment(self.kind, message_id, attachment["id"], path)
        threading.Thread(target=run, daemon=True).start()

    # -- Socket.IO events ------------------------------------------------------------------
    def socket_url(self):
        parts = urllib.parse.urlsplit(self.url)
        scheme = "wss" if parts.scheme == "https" else "ws"
        query = urllib.parse.urlencode({"EIO": "4", "transport": "websocket",
                                        "guid": self.password, "password": self.password})
        return urllib.parse.urlunsplit((scheme, parts.netloc, parts.path + "/socket.io/", query, ""))

    def _listen(self):
        try:
            ws = websocket.create_connection(self.socket_url(), timeout=TIMEOUT,
                                             header=["User-Agent: freemac-messages"])
        except Exception:   # noqa: BLE001 - websocket raises many kinds
            return
        self.ws = ws
        try:
            opened = ws.recv()
            if not opened.startswith("0"):
                return
            info = json.loads(opened[1:] or "{}")
            ws.settimeout((info.get("pingInterval", 25000) + info.get("pingTimeout", 20000)) / 1000)
            ws.send("40" + json.dumps({"password": self.password, "guid": self.password}))
            while not self.stopping.is_set():
                frame = ws.recv()
                if not frame:
                    break
                if frame == "2":
                    ws.send("3")
                elif frame.startswith("40"):
                    self.socket_up = True
                elif frame.startswith("44"):
                    self.listener.backend_status(self.kind, "The server turned the event stream away.", False)
                    break
                elif frame.startswith("42"):
                    self._event(frame[2:])
                elif frame.startswith("41") or frame == "1":
                    break
        except Exception:   # noqa: BLE001 - dropped or timed out
            pass
        finally:
            self.socket_up = False
            self.ws = None
            try:
                ws.close()
            except Exception:   # noqa: BLE001
                pass

    def _event(self, text):
        # An ack id may come before the array: 42<id>[...]
        text = text.lstrip("0123456789")
        try:
            name, *args = json.loads(text)
        except (ValueError, TypeError):
            return
        data = args[0] if args else None
        if name in ("new-message", "updated-message") and isinstance(data, dict):
            message = convert_any(data, None, self.names)
            if message:
                self._deliver([], [message])
        elif name == "message-send-error" and isinstance(data, dict):
            temp = data.get("tempGuid")
            if temp:
                self.listener.backend_sent(self.kind, temp, None, "Not Delivered", "")
        elif name == "typing-indicator" and isinstance(data, dict) and data.get("guid"):
            self.listener.backend_typing(self.kind, f"bb:{data['guid']}", bool(data.get("display")))


def new_temp_id():
    return f"tmp:{uuid.uuid4()}"

