# Messages

Messages is freemac's own messaging app (`freemac-messages`, app ID
`org.freemac.Messages`): a sidebar of conversations with search and a New
Message button, a conversation pane with bubbles (blue for iMessage, green
for SMS/RCS, grey for the other side), times between bursts of messages,
Sending…, Sent, Delivered, Read and Not Delivered under what you sent, an
emoji button, notifications for new messages and an unread count on its Dock
icon. Bubbles show tapbacks on their corner and pictures inline, and a grey
"•••" bubble shows while the other side is typing (iMessage). The paperclip,
or dropping files on a conversation, sends pictures and files. Once a backend
is set up, Messages starts when you log in, with no window, so new messages
arrive anyway. Its icon (`art/icons/freemac-messages.svg`) is original
freemac artwork.

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
conversation read on the Mac, adding tapbacks and seeing when the other side
is typing also need the Private API (BlueBubbles Server > Settings > Private
API, which has its own setup steps on the Mac). Without it, tapbacks other
people add still show, but a bubble's menu has no tapbacks to add.

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
5. If Firewall is on (Dials > Network > Firewall), turning the phone on asks
   for an administrator's password to let KDE Connect in: UDP 1716 and TCP
   1716–1764, from the local network only (10.0.0.0/8, 172.16.0.0/12 and
   192.168.0.0/16). Turning the phone off asks again, to close them. If you
   cancel, or turn the Firewall on later, Settings > Phone and the foot of
   the sidebar say the firewall blocks your phone, with a Let Phone Through
   Firewall… button. With the Firewall off nothing is asked.

If KDE's own kdeconnectd is already running in the session (someone
installed KDE Connect from Harbor and paired the phone with it), Messages
uses it over D-Bus instead of starting its own client; pairing is then done
in KDE Connect's own settings.

### Starting at login

Messages > Settings… has "Start Messages when you log in", on by default.
Once BlueBubbles or the phone is set up, Messages writes
`~/.config/autostart/freemac-messages-background.desktop`
(`freemac-messages --background`, hidden from Login Items' list), so
freemac-login-items starts it with no window at each login and new messages
come in with a notification. Turning the choice off, or removing the last
backend, removes the file. It's a file of its own, as Chime's alarm watcher
is, so the Dock's Open at Login (which opens the window) stays separate.

### Pictures, files, tapbacks and typing

- **Sending**: click the paperclip or drop files on the conversation; they
  wait above the typing field (× takes one back) and go with the next
  Return. Through BlueBubbles each file goes as its own message with the
  documented upload (`POST /api/v1/message/attachment`, a multipart form with
  `chatGuid`, `tempGuid`, `name`, `method` and `attachment`), then the words;
  up to 100 MB each. Through the phone they go together as one MMS: a
  `kdeconnect.sms.request` of version 2 carrying `attachments` (file name,
  MIME type, base64), up to 10 MB in all, though many carriers take far less.
  With kdeconnectd, the files' `file://` addresses go to its
  `sendWithoutConversation`. A New Message can carry files as a text; as an
  iMessage, only once its first message has made the conversation.
- **Pictures** show in the bubble, 240 pixels at most, with no bubble round
  them when there are no words. What you sent shows at once from the file
  here. BlueBubbles pictures in a conversation's newest 30 messages (up to
  25 MB each) are fetched when it opens; the phone sends its own small
  thumbnail (`encoded_thumbnail`), shown until you click for the file.
- **Tapbacks** BlueBubbles reports as messages of their own
  (`associatedMessageGuid`, `associatedMessageType`: love, like, dislike,
  laugh, emphasize, question, or their numbers 2000–2005; "-love" or
  3000–3005 takes one back; "emoji" or 2006 comes with
  `associatedMessageEmoji`). They're kept one per person per message, and
  show on the bubble's corner toward the middle, with a count when several
  people chose the same one; a tapback on your message gives a notification
  ("Loved “See you there”"). Right-click a bubble for Copy and, when the
  server's Private API is on, the six tapbacks
  (`POST /api/v1/message/react`); choosing your own again takes it back.
  Without the Private API the menu has only Copy.
- **Typing**: BlueBubbles' `typing-indicator` event (`{"guid", "display"}`)
  shows "•••" at the end of that conversation until the server says it
  stopped, a message arrives from them, or a minute passes.

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
message (or the tapback), and on "typing-indicator" shows the typing bubble.
When the websocket can't connect, or the package is missing, the client asks
`/api/v1/message/query` for anything newer every 15 seconds, and on every
reconnection it catches up the same way.

**The firewall.** Opening ports changes the whole computer, so Messages asks
freemac's own root helper, the one that Dials' Firewall, Remote Login, File
Sharing and Screen Sharing switches already use
(`/usr/libexec/freemac-system-helper`, run with pkexec under the
`org.freemac.system.settings` polkit action, `auth_admin_keep`). Its new
`kde-connect on|off` adds or removes exactly six ufw rules, `allow in proto
udp from <net> to any port 1716` and `allow in proto tcp from <net> to any
port 1716:1764` for each private network, and leaves the rest of the
firewall as it is. Like Screen Sharing it keeps a note,
`/var/lib/freemac/kde-connect`, so `firewall on` in Dials puts the rules
back, and so Messages can tell (`messages_firewall.py`) whether they're open.
The rules are for the whole computer, not one person: anyone else on it who
turns their phone off closes them too.

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
| `~/.local/share/freemac/messages/messages.db` | SQLite: chats, messages and tapbacks from both backends |
| `~/.local/share/freemac/messages/kdeconnect/` | device id, certificate, key, paired phones, downloaded MMS attachments |
| `~/.local/share/freemac/messages/bluebubbles/` | downloaded attachments and pictures |
| `~/.config/freemac/messages/settings.json` | server address, phone on or off, phone addresses typed in, first run seen, `start_at_login` |
| `~/.config/freemac/messages/passwords.json` | only without a keychain, 0600 |
| `~/.config/autostart/freemac-messages-background.desktop` | while Messages starts at login |
| `/var/lib/freemac/kde-connect` | while the firewall lets KDE Connect in (written by the system helper) |

## Tests

`xvfb-run -a python3 -m unittest discover -s shell/tests` runs, among the rest:

- `test_messages_kdeconnect.py`: certificates (public key as OpenSSL reads
  it, subject, key mode), the code on both sides, packets, pictures'
  thumbnails, and against a stand-in phone over localhost (UDP, TCP, TLS
  with its own certificate, protocol 8): discovery, pairing both ways, texts
  ignored before pairing, conversations, live texts, history requests,
  sending, an MMS with a picture, one too big to send, an attachment
  payload, a known phone reconnecting, a changed certificate turned away,
  unpairing.
- `test_messages_bluebubbles.py`: converting messages and chats (services,
  read and delivered marks, tapbacks kept apart from messages, their kinds
  and numbers), the upload form, and against a stand-in server on
  localhost: wrong password, unreachable server, chats, messages, sending
  into a chat and to new addresses, a failed send, an attachment, uploading
  a picture (the multipart form as the server reads it) and a file that's
  gone, tapbacks refused without the Private API and sent and taken back
  with it, a conversation's own tapbacks, Socket.IO events over a websocket
  (connect, ping, new-message, updated-message, typing-indicator, a
  tapback), and polling without a websocket.
- `test_messages_firewall.py`: the system helper copied to a folder of the
  test's own and run against a stand-in `ufw` that only writes down what it's
  asked: `kde-connect on` gives exactly the six local-network rules and its
  note, `off` takes the same rules out, `firewall on` puts them back (before
  ufw is enabled) only while the note is there, and nothing else is
  accepted; and when Messages asks for a change, and how. The real firewall
  and `/var/lib/freemac` are never touched.
- `test_messages_store.py`: the SQLite store, search, unread counts, a sent
  message replacing its "sending" stand-in, two pictures sending at once,
  tapbacks (newest per person, taken back, late ones, gone with their
  conversation), reopening, settings, and the password file's mode.
- `test_messages_window.py`: bubble layout (time lines, tails, statuses, group
  senders, big emoji), the first-run page's words, the list and search,
  bubbles' sides and colours, sending, a failed send, a new text conversation,
  notifications and counts, the settings window, tapbacks on bubbles and in
  a bubble's menu (only with the Private API), a tapback's notification, the
  typing bubble, the paperclip's tray, dropped files, pictures shown (sent,
  fetched and the phone's thumbnails), an MMS, starting at login and
  `--background`, the firewall asked about when the phone is turned on and
  off (with a stand-in for the helper), the app end to end against the
  stand-in BlueBubbles server (with a picture, a tapback and typing), and
  against a stand-in kdeconnectd on a private session bus (with a picture).

Nothing reaches the internet or a real device; every person and message in
them is made up.

## Not done yet

- **Firewall over IPv6**, and networks outside the three private IPv4
  ranges (a carrier-grade 100.64.0.0/10 network, say): the rules cover
  10/8, 172.16/12 and 192.168/16 only, as Remote Login's do. freemac's own
  KDE Connect client listens on IPv4 only anyway.
- **Replies in threads, edits and unsends** from BlueBubbles are left out.
  A tapback on one part of a message with several parts shows on the whole
  bubble, and stickers are left out. Emoji tapbacks show but can't be sent
  from freemac.
- **Typing** isn't sent from freemac, and only BlueBubbles reports it: KDE
  Connect's SMS plugin has no packet for it, nor for read receipts sent to
  the phone or marking texts read there.
- **Attachments**: a new iMessage conversation takes files only after its
  first message (`chat/new` takes words only). Files go whole, with no
  shrinking of big pictures; carriers often refuse an MMS over 300 KB to
  1 MB. Pictures sent through kdeconnectd use its `sendWithoutConversation`
  with `file://` addresses, which hasn't been tried against a real
  kdeconnectd; received attachments through kdeconnectd still don't open.
  The phone's pictures show as its thumbnail until clicked, and videos show
  as a file, not a player. The upload reads the whole file into memory.
- **Group conversations**: shown, with each sender's name, and replies go to
  every address; starting a new group from New Message works only through
  BlueBubbles (`chat/new` with several addresses) or as an MMS to several
  numbers, depending on the phone.
- **Contacts**: names come from Crew's contacts, read when Messages starts;
  there are no contact pictures in the avatars.
- **kdeconnectd over D-Bus** is tested against a stand-in on a private bus,
  not against a real kdeconnectd; its conversation struct is read
  defensively. Pairing isn't available through it.
- **RCS on Android**: KDE Connect's SMS plugin only sees what Android's SMS
  and MMS store holds; RCS chats in Google Messages usually aren't there.
- **Several phones**: one paired phone at a time is used for texts.
- **A real phone and a real BlueBubbles Server** haven't been tried from
  this branch: everything here was written from the public documentation and
  sources and tested against local stand-ins, and the firewall's rules
  against a stand-in `ufw`.
