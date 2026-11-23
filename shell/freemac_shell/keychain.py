# SPDX-License-Identifier: GPL-3.0-or-later
"""The login keychain: where apps keep the passwords they save.

freemac's keychain is gnome-keyring's secret service (org.freedesktop.secrets),
which Web (Epiphany), Post and other apps already use through libsecret. Its
"login" keyring is locked with the person's login password: logging in with
the password unlocks it (pam_gnome_keyring, /etc/pam.d/greetd), as a Mac
unlocks the login keychain.

Two cases this module looks after:

* No password at login (the live system's automatic login, or an account set
  to log in by itself): nothing unlocks a keyring, so the first app to save a
  password would ask the person to make up a keyring password. ensure_login()
  runs at each login (freemac-login-items) and, when there is no login keyring
  yet, makes one with no password of its own, as other systems do for
  automatic login; it stays open while the person is logged in.

* Changing your own password (Dials > Users): change_password(old, new) gives
  the login keyring the new password too, so the next login still unlocks
  it. A keyring made without a password keeps none while the account logs in
  by itself.

Original freemac code; it talks to the secret service over D-Bus with the
"plain" session, which is how libsecret hands secrets over on the same
computer.
"""
from gi.repository import Gio, GLib

BUS_NAME = "org.freedesktop.secrets"
SERVICE = "/org/freedesktop/secrets"
SERVICE_IFACE = "org.freedesktop.Secret.Service"
INTERNAL_IFACE = "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface"
LOGIN = "/org/freedesktop/secrets/collection/login"
TIMEOUT = 15000


def _bus():
    return Gio.bus_get_sync(Gio.BusType.SESSION, None)


def _call(bus, method, args, reply=None, iface=SERVICE_IFACE, path=SERVICE):
    return bus.call_sync(BUS_NAME, path, iface, method, args,
                         GLib.VariantType(reply) if reply else None,
                         Gio.DBusCallFlags.NONE, TIMEOUT, None)


def _session(bus):
    """A plain (unencrypted, same-computer) secret service session."""
    out = _call(bus, "OpenSession", GLib.Variant("(sv)", ("plain", GLib.Variant("s", ""))), "(vo)")
    return out.unpack()[1]


def _secret(session, text):
    return (session, b"", text.encode("utf-8"), "text/plain; charset=utf8")


def collections(bus=None):
    bus = bus or _bus()
    out = bus.call_sync(BUS_NAME, SERVICE, "org.freedesktop.DBus.Properties", "Get",
                        GLib.Variant("(ss)", (SERVICE_IFACE, "Collections")),
                        GLib.VariantType("(v)"), Gio.DBusCallFlags.NONE, TIMEOUT, None)
    return list(out.unpack()[0])


def available():
    """True when a secret service answers on the session bus."""
    try:
        collections()
        return True
    except GLib.Error:
        return False


def ensure_login():
    """Make the login keyring, without a password, when there is none yet
    (a login with no password); make it the keyring apps save into. Returns
    True if one was made."""
    try:
        bus = _bus()
        if LOGIN in collections(bus):
            return False
        session = _session(bus)
        # The keyring's name comes from its label: "login", the name the
        # login password unlocks (pam_gnome_keyring); then its shown label.
        props = {"org.freedesktop.Secret.Collection.Label": GLib.Variant("s", "login")}
        args = GLib.Variant("(a{sv}(oayays))", (props, _secret(session, "")))
        made = _call(bus, "CreateWithMasterPassword", args, "(o)",
                     iface=INTERNAL_IFACE).unpack()[0]
        try:
            bus.call_sync(BUS_NAME, made, "org.freedesktop.DBus.Properties", "Set",
                          GLib.Variant("(ssv)", ("org.freedesktop.Secret.Collection", "Label",
                                                 GLib.Variant("s", "Login"))),
                          None, Gio.DBusCallFlags.NONE, TIMEOUT, None)
        except GLib.Error:
            pass
        _call(bus, "SetAlias", GLib.Variant("(so)", ("default", made)))
        return True
    except GLib.Error:
        return False


def change_password(old, new):
    """Give the login keyring the new login password. True on success;
    False when the keyring's password wasn't old (or there is no keyring)."""
    try:
        bus = _bus()
        if LOGIN not in collections(bus):
            return False
        session = _session(bus)
        args = GLib.Variant("(o(oayays)(oayays))", (LOGIN, _secret(session, old), _secret(session, new)))
        _call(bus, "ChangeWithMasterPassword", args, iface=INTERNAL_IFACE)
        return True
    except GLib.Error:
        return False


def main(argv=None):
    import sys
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ["--ensure"]:
        print("made" if ensure_login() else "kept")
        return 0
    print("available" if available() else "not available")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
