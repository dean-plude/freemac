# SPDX-License-Identifier: GPL-3.0-or-later
"""Sunrise and sunset where you are, for Auto appearance (light by day,
dark at night) and for Night Light's Sunset to Sunrise, as a Mac does.

freemac doesn't ask where you are: the computer's time zone names a city
(Dials > Date & Time), and the time zone database lists where each zone's
city is (zone1970.tab). That's close enough for the sun: a few minutes
either way across a time zone.

The times use the usual sunrise equation (the sun's centre 0.833° below
the horizon, for the air's bending and the sun's size). Original freemac
code.
"""
import datetime
import math
import os
import time

ZONEINFO = "/usr/share/zoneinfo"


def local_zone():
    """The computer's time zone name, such as "America/Chicago"."""
    zone = os.environ.get("TZ", "").lstrip(":")
    if zone and not zone.startswith("/"):
        return zone
    try:
        return os.readlink("/etc/localtime").split("zoneinfo/", 1)[1]
    except (OSError, IndexError):
        pass
    try:
        with open("/etc/timezone") as f:
            return f.read().strip() or "UTC"
    except OSError:
        return "UTC"


def _degrees(text, whole):
    """"+4043" or "+404251" (whole = 2) or "-07400" (whole = 3) in degrees."""
    sign = -1 if text[0] == "-" else 1
    digits = text[1:]
    value = int(digits[:whole]) + int(digits[whole:whole + 2]) / 60
    if len(digits) > whole + 2:
        value += int(digits[whole + 2:whole + 4]) / 3600
    return sign * value


def parse_coordinates(text):
    """(latitude, longitude) from zone.tab's "+4043-07400" style."""
    split = max(text.rfind("+"), text.rfind("-"))
    if split <= 0:
        raise ValueError(text)
    return _degrees(text[:split], 2), _degrees(text[split:], 3)


def _links(root):
    """Old and other names of zones (US/Central is America/Chicago)."""
    links = {}
    try:
        with open(os.path.join(root, "tzdata.zi")) as f:
            for line in f:
                if line.startswith("L "):
                    parts = line.split()
                    if len(parts) == 3:
                        links[parts[2]] = parts[1]
    except OSError:
        pass
    return links


def zone_place(zone, root=ZONEINFO):
    """(latitude, longitude) of the zone's city, or None."""
    places = {}
    for name in ("zone1970.tab", "zone.tab"):
        try:
            with open(os.path.join(root, name)) as f:
                for line in f:
                    if line.startswith("#"):
                        continue
                    parts = line.rstrip("\n").split("\t")
                    if len(parts) >= 3 and parts[2] not in places:
                        try:
                            places[parts[2]] = parse_coordinates(parts[1])
                        except ValueError:
                            pass
        except OSError:
            pass
    if zone in places:
        return places[zone]
    target = _links(root).get(zone)
    return places.get(target) if target else None


def place():
    """Where this computer is, roughly, or None (UTC, or no time zone data)."""
    return zone_place(local_zone())


def sun_times(day, latitude, longitude):
    """(sunrise, sunset) on `day` (a date) as Unix times. (None, None) if
    the sun doesn't set that day; ("night", "night") if it doesn't rise."""
    # Julian day of noon at this longitude.
    noon = datetime.datetime(day.year, day.month, day.day, 12, tzinfo=datetime.timezone.utc)
    julian = noon.timestamp() / 86400 + 2440587.5
    n = round(julian - 2451545.0 + 0.0008 - longitude / 360)
    j_star = n - longitude / 360
    m = (357.5291 + 0.98560028 * j_star) % 360
    m_r = math.radians(m)
    c = 1.9148 * math.sin(m_r) + 0.02 * math.sin(2 * m_r) + 0.0003 * math.sin(3 * m_r)
    lam = math.radians((m + c + 180 + 102.9372) % 360)
    transit = 2451545.0 + j_star + 0.0053 * math.sin(m_r) - 0.0069 * math.sin(2 * lam)
    declination = math.asin(math.sin(lam) * math.sin(math.radians(23.4397)))
    phi = math.radians(latitude)
    cos_omega = ((math.sin(math.radians(-0.833)) - math.sin(phi) * math.sin(declination)) /
                 (math.cos(phi) * math.cos(declination)))
    if cos_omega < -1:
        return None, None            # the midnight sun
    if cos_omega > 1:
        return "night", "night"      # the polar night
    half = math.degrees(math.acos(cos_omega)) / 360

    def unix(j):
        return (j - 2440587.5) * 86400
    return unix(transit - half), unix(transit + half)


def is_day(now=None, where=None):
    """Whether the sun is up here now. None if we don't know where we are."""
    where = where if where is not None else place()
    if where is None:
        return None
    now = time.time() if now is None else now
    time.tzset()
    rise, sets = sun_times(datetime.date.fromtimestamp(now), *where)
    if rise is None:
        return True
    if rise == "night":
        return False
    return rise <= now < sets


def times_today(where=None, h24=False):
    """("6:52 AM", "5:31 PM"), or ("06:52", "17:31") with h24: today's
    local sunrise and sunset, or None."""
    time.tzset()     # the time zone may have changed since we started
    where = where if where is not None else place()
    if where is None:
        return None
    rise, sets = sun_times(datetime.date.today(), *where)
    if rise is None or rise == "night":
        return None
    return tuple(time.strftime("%H:%M" if h24 else "%-I:%M %p", time.localtime(t)) for t in (rise, sets))


def elevation(now=None, where=None):
    """How high the sun is here now, in degrees above the horizon (below it
    is negative), or None if we don't know where we are. For the Dynamic
    wallpaper, whose light follows the sun through the day."""
    where = where if where is not None else place()
    if where is None:
        return None
    latitude, longitude = where
    now = time.time() if now is None else now
    d = now / 86400 + 2440587.5 - 2451545.0          # days since noon, 1 January 2000
    g = math.radians((357.529 + 0.98560028 * d) % 360)
    q = (280.459 + 0.98564736 * d) % 360
    lam = math.radians((q + 1.915 * math.sin(g) + 0.020 * math.sin(2 * g)) % 360)
    tilt = math.radians(23.439 - 0.00000036 * d)
    right_ascension = math.degrees(math.atan2(math.cos(tilt) * math.sin(lam), math.cos(lam)))
    declination = math.asin(math.sin(tilt) * math.sin(lam))
    sidereal = (280.46061837 + 360.98564736629 * d + longitude) % 360
    hour_angle = math.radians((sidereal - right_ascension) % 360)
    phi = math.radians(latitude)
    height = math.asin(math.sin(phi) * math.sin(declination) +
                       math.cos(phi) * math.cos(declination) * math.cos(hour_angle))
    return math.degrees(height)
