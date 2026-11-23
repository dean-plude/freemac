# SPDX-License-Identifier: GPL-3.0-or-later
"""VPN, as a Mac has it: VPN configurations in Dials > Network, each with a
switch, and a VPN menu in the menu bar to connect or disconnect.

A configuration comes from a file your VPN provider or workplace gives you:
a WireGuard .conf or an OpenVPN .ovpn. NetworkManager keeps it, with its
keys, and connects it; freemac never reads the keys itself. A new
configuration doesn't connect by itself until you turn it on.

Original freemac code.
"""
import json
import os
import re
import subprocess

import gi

from . import style

try:
    gi.require_version("NM", "1.0")
    from gi.repository import NM  # noqa: E402
except (ValueError, ImportError):
    NM = None

OPENVPN = "org.freedesktop.NetworkManager.openvpn"
FILE_KINDS = {".conf": "wireguard", ".ovpn": "openvpn"}


def new_client():
    if not NM:
        return None
    try:
        return NM.Client.new(None)
    except Exception:  # GLib.Error: NetworkManager isn't running
        return None


def is_vpn(connection):
    return connection.get_connection_type() in ("wireguard", "vpn")


def configurations(client):
    """Every VPN configuration, by name."""
    if not client:
        return []
    return sorted((c for c in client.get_connections() if is_vpn(c)), key=lambda c: c.get_id().lower())


def kind_name(connection):
    if connection.get_connection_type() == "wireguard":
        return "WireGuard"
    setting = connection.get_setting_vpn()
    if setting and setting.get_service_type() == OPENVPN:
        return "OpenVPN"
    return "VPN"


def active(client, connection):
    """The active connection for a configuration, or None."""
    for ac in client.get_active_connections() if client else []:
        if ac.get_uuid() == connection.get_uuid():
            return ac
    return None


def state(client, connection):
    """'connected', 'connecting', 'disconnecting' or 'off'."""
    ac = active(client, connection)
    if not ac:
        return "off"
    st = ac.get_state()
    if st == NM.ActiveConnectionState.ACTIVATED:
        return "connected"
    if st == NM.ActiveConnectionState.ACTIVATING:
        return "connecting"
    if st == NM.ActiveConnectionState.DEACTIVATING:
        return "disconnecting"
    return "off"


STATE_TEXT = {"connected": "Connected", "connecting": "Connecting…",
              "disconnecting": "Disconnecting…", "off": "Not connected"}


def any_connected(client):
    return any(state(client, c) == "connected" for c in configurations(client))


def turn_on(client, connection, done=None):
    def finished(c, result):
        error = None
        try:
            c.activate_connection_finish(result)
        except Exception as e:  # GLib.Error
            error = friendly(str(e))
        if done:
            done(error)
    client.activate_connection_async(connection, None, None, None, finished)


def turn_off(client, connection):
    ac = active(client, connection)
    if ac:
        client.deactivate_connection_async(ac, None, None, None)


def friendly(message):
    """NetworkManager's errors, shortened to what a person can act on."""
    message = re.sub(r"^.*?(Error|error):\s*", "", message.strip())
    if "secrets" in message.lower() or "password" in message.lower():
        return "The VPN needs a password or key that wasn't given."
    if "no valid vpn" in message.lower() or "plugin" in message.lower():
        return "This kind of VPN isn't installed on this computer."
    return message or "The VPN couldn't connect."


def import_file(path):
    """Add a configuration from a .conf (WireGuard) or .ovpn (OpenVPN) file.
    Returns (name, None) or (None, why it failed)."""
    kind = FILE_KINDS.get(os.path.splitext(path)[1].lower())
    if not kind:
        return None, "Choose a WireGuard file (.conf) or an OpenVPN file (.ovpn)."
    if kind == "wireguard":
        # NetworkManager names the connection, and its network interface,
        # after the file; an interface name has at most 15 letters and no
        # spaces, so a longer name is refused. Say so plainly.
        stem = os.path.splitext(os.path.basename(path))[0]
        if not re.fullmatch(r"[A-Za-z0-9_=+.-]{1,15}", stem):
            return None, ("WireGuard files must be named with up to 15 letters or numbers and no spaces "
                          "(for example home-vpn.conf). Rename the file and try again.")
    try:
        done = subprocess.run(["nmcli", "connection", "import", "type", kind, "file", path],
                              capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as e:
        return None, str(e)
    if done.returncode:
        text = (done.stderr or done.stdout).strip()
        if kind == "openvpn" and "plugin" in text.lower():
            return None, "OpenVPN isn't installed on this computer."
        return None, friendly(text) if text else "The file couldn't be read as a VPN configuration."
    match = re.search(r"'(.+?)' \(([0-9a-f-]{36})\)", done.stdout)
    if not match:
        return os.path.splitext(os.path.basename(path))[0], None
    name, uuid = match.groups()
    # A Mac's new VPN waits to be turned on; NetworkManager may start a
    # WireGuard one straight away and at every login. Stop both.
    subprocess.run(["nmcli", "connection", "modify", uuid, "connection.autoconnect", "no"],
                   capture_output=True, timeout=15)
    subprocess.run(["nmcli", "connection", "down", uuid], capture_output=True, timeout=15)
    return name, None


def remove(connection):
    connection.delete_async(None, None, None)


def menu_bar_shown():
    return bool(style.prefs().get("vpn_menu", True))


def set_menu_bar_shown(on):
    prefs = style.prefs()
    prefs["vpn_menu"] = bool(on)
    os.makedirs(os.path.dirname(style.PREFS), exist_ok=True)
    tmp = style.PREFS + ".vpn-tmp"
    with open(tmp, "w") as f:
        json.dump(prefs, f, indent=2)
    os.replace(tmp, style.PREFS)
