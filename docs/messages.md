# Messages

Messages is freemac's own messaging app (`freemac-messages`, app ID
`org.freemac.Messages`): a sidebar of conversations with search and a New
Message button, a conversation pane with bubbles (blue for iMessage, green
for SMS/RCS, grey for the other side), times between bursts of messages,
Sending…, Sent, Delivered, Read and Not Delivered under what you sent, an
emoji button, notifications for new messages and an unread count on its Dock
icon. Its icon (`art/icons/freemac-messages.svg`) is original freemac artwork.

It does not reverse engineer, emulate or spoof Apple's iMessage protocol or
any Apple device. It gets messages from two pluggable backends:

1. **iMessage through BlueBubbles** (`messages_bluebubbles.py`): a client for
   the documented REST API and Socket.IO events of BlueBubbles Server, which
   the person runs on a Mac they own, signed in to their own Apple account.
   freemac only ever talks to that server.
2. **Texts through an Android phone** (`messages_kdeconnect.py`): freemac's
   own client for the open KDE Connect protocol, talking to the KDE Connect
   app on the phone. An iPhone can't send texts this way.

## Setting up each backend

### iMessage through BlueBubbles

1. On a Mac you own, signed in to iMessage, install BlueBubbles Server (free
   and open source, from the BlueBubbles project) and give it a password.
2. Make the server reachable from the freemac computer: on the same network
   by its address and port (for example `http://192.168.1.20:1234`), or through
   whatever proxy or tunnel BlueBubbles Server offers. Prefer an `https://`
   address when it leaves your home network: the BlueBubbles API puts the
   password in each request's address, so plain `http://` sends it readable
   to anyone on the path.
3. In freemac, open Messages > Settings… (⌘,) > iMessage, type the address and
   password and click Connect. The status under it, and at the foot of the
   sidebar, says "Connected to BlueBubbles" once the server answers.

Sending uses the server's AppleScript method, or its Private API when the
server reports that it's on (`/api/v1/server/info`, `private_api`). Marking a
conversation read on the Mac also needs the Private API.

### Texts through an Android phone (KDE Connect)

1. Install KDE Connect on the Android phone (Google Play or F-Droid) and give
   it permission for SMS.
2. Keep the phone and the computer on the same Wi-Fi network.
3. In Messages > Settings… > Phone, turn on "Use an Android phone for texts".
   The phone shows up in the list within a few seconds; click Pair… and
   accept on the phone, checking that both screens show the same eight
   characters. A request from the phone shows the code the same way.
4. If the phone isn't found (networks that drop broadcasts, such as some
   guest networks), type its address in the field under the list and click
   Add.
5. If Firewall is on (Dials > Network > Firewall), the phone can't connect:
   KDE Connect needs UDP 1716 and TCP 1716–1764 open to the local network
   (not done yet, see below).

If KDE's own kdeconnectd is already running in the session (someone
installed KDE Connect from Harbor and paired the phone with it), Messages
uses it over D-Bus instead of starting its own client; pairing is then done
in KDE Connect's own settings.

## How it's built, and why

**One client of our own, the daemon only when it's already there.** The ISO
doesn't ship kdeconnectd: it brings Qt 6 and a large part of KDE Frameworks
for one feature, and GSConnect only runs inside GNOME Shell, which freemac
doesn't use. A small Python client of our own needs nothing new on the ISO
(it uses Python's `ssl` and `socket`, and OpenSSL's command line, already
there for Hail, to make its certificate). But two KDE Connect stacks on one
computer would show the phone two computers and fight over port 1716, so
when kdeconnectd already owns `org.kde.kdeconnect` on the session bus,
Messages uses it through its conversations interface instead. That keeps the
common case simple, with one code path to test, and the uncommon one
correct.

**Always the TLS client.** KDE Connect makes whichever side opened the TCP
connection the TLS *server*. Python's `ssl` can't accept an unknown
certificate from a TLS client (there's no verify callback), so freemac makes
sure the phone is always the one that connects: it answers every identity it
hears with its own, sent straight back to the phone's UDP 1716, and the
phone then connects to freemac's TCP port. As the TLS client freemac reads
the phone's certificate itself and compares its SHA-256 with the one kept at
pairing; a different certificate for a paired device id is turned away with
a message to pair again. Packets other than pairing from a phone that isn't
paired are ignored.

**Pairing code.** SHA-256 of the two certificates' SubjectPublicKeyInfo
(the larger first) and, for protocol 8, the pairing request's timestamp; the
first eight hex digits, upper case. This is how KDE Connect's own apps work
the code out, from their public sources; it is only shown for the person to
compare, so a mistake there would show different codes, not weaken pairing.

**BlueBubbles events.** Socket.IO is Engine.IO 4 over a websocket (python3-
websocket, added to `build/packages/desktop.list`); the client answers the
server's pings, and on "new-message" and "updated-message" stores the
message. When the websocket can't connect, or the package is missing, the
client asks `/api/v1/message/query` for anything newer every 15 seconds, and
on every reconnection it catches up the same way.

**Passwords.** The BlueBubbles password is saved with libsecret (`Secret`
through gi; the ISO ships `gir1.2-secret-1` and gnome-keyring), under the
schema `org.freemac.Messages.Password` with the attribute `account` =
`bluebubbles:<server address>`. When no secret service answers, it goes to
`~/.config/freemac/messages/passwords.json`, made 0600. `settings.json` in the
same folder says which one was used (`password_store`: `keyring` or
`file`). KDE Connect needs no password: its certificate and key are in
`~/.local/share/freemac/messages/kdeconnect/` (key 0600), with the paired
phone's certificate fingerprint in `paired.json`.

**Files.**

| Path | What |
| --- | --- |
| `~/.local/share/freemac/messages/messages.db` | SQLite: chats and messages from both backends |
| `~/.local/share/freemac/messages/kdeconnect/` | device id, certificate, key, paired phones, downloaded MMS attachments |
| `~/.local/share/freemac/messages/bluebubbles/` | downloaded attachments |
| `~/.config/freemac/messages/settings.json` | server address, phone on or off, phone addresses typed in, first run seen |
| `~/.config/freemac/messages/passwords.json` | only without a keychain, 0600 |

## Tests

`xvfb-run -a python3 -m unittest discover -s shell/tests` runs, among the rest:

- `test_messages_kdeconnect.py`: certificates (public key as OpenSSL reads
  it, subject, key mode), the code on both sides, packets, and against a
  stand-in phone over localhost (UDP, TCP, TLS with its own certificate,
  protocol 8): discovery, pairing both ways, texts ignored before pairing,
  conversations, live texts, history requests, sending, an attachment
  payload, a known phone reconnecting, a changed certificate turned away,
  unpairing.
- `test_messages_bluebubbles.py`: converting messages and chats (services,
  read and delivered marks, reactions left out), and against a stand-in
  server on localhost: wrong password, unreachable server, chats, messages,
  sending into a chat and to new addresses, a failed send, an attachment,
  Socket.IO events over a websocket (connect, ping, new-message,
  updated-message), and polling without a websocket.
- `test_messages_store.py`: the SQLite store, search, unread counts, a sent
  message replacing its "sending" stand-in, reopening, settings, and the
  password file's mode.
- `test_messages_window.py`: bubble layout (time lines, tails, statuses, group
  senders, big emoji), the first-run page's words, the list and search,
  bubbles' sides and colours, sending, a failed send, a new text conversation,
  notifications and counts, the settings window, the app end to end against
  the stand-in BlueBubbles server, and against a stand-in kdeconnectd on a
  private session bus.

Nothing reaches the internet or a real device; every person and message in
them is made up.

## Not done yet

- **Firewall**: with Firewall on, the phone can't connect; Dials' firewall
  helper doesn't open KDE Connect's ports (UDP 1716, TCP 1716–1764) yet.
- **Reactions (tapbacks), replies in threads, edits and unsends** from
  BlueBubbles are left out (reactions are skipped, not shown as text).
- **Typing indicators**, read receipts sent from freemac to the phone, and
  marking texts read on the phone: KDE Connect's SMS plugin has no packet for
  it.
- **Sending attachments** (pictures, files) from freemac, on either backend.
  Received attachments open on click: BlueBubbles downloads them from the
  server, KDE Connect asks the phone for the file.
- **Group conversations**: shown, with each sender's name, and replies go to
  every address; starting a new group from New Message works only through
  BlueBubbles (`chat/new` with several addresses) or as an MMS to several
  numbers, depending on the phone.
- **Contacts**: names come from Crew's contacts, read when Messages starts;
  there are no contact pictures in the avatars.
- **Messages doesn't start at login**; new messages arrive while it's
  running (it keeps running after its window closes).
- **kdeconnectd over D-Bus** is tested against a stand-in on a private bus,
  not against a real kdeconnectd; its conversation struct is read
  defensively. Attachments and pairing aren't available through it.
- **RCS on Android**: KDE Connect's SMS plugin only sees what Android's SMS
  and MMS store holds; RCS chats in Google Messages usually aren't there.
- **Several phones**: one paired phone at a time is used for texts.
- **A real phone and a real BlueBubbles Server** haven't been tried from
  this branch: everything here was written from the public documentation and
  sources and tested against local stand-ins.
