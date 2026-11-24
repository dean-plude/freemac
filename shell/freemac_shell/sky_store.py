# SPDX-License-Identifier: GPL-3.0-or-later
"""The weather for Sky, with no GTK: places, forecasts and words for them.

Forecasts come from Open-Meteo (open-meteo.com), which is free for
non-commercial use with no account or key, and gives the weather as WMO
weather codes. Places are found with Open-Meteo's geocoding search. Nothing
is sent but the place's name (when searching) and its latitude and longitude
(when asking for its weather).

The places you add are kept in ~/.config/freemac/sky.json, with the
temperature unit, and the last forecast of each is kept beside them in
~/.cache/freemac/sky/ so Sky opens with something to show while it asks
again.

FREEMAC_SKY_SAMPLE=/a/folder answers from made-up files there in place of
the network (see _get), for trying Sky offline.

Original freemac code.
"""
import datetime
import json
import os
import urllib.parse
import urllib.request

FORECAST = "https://api.open-meteo.com/v1/forecast"
GEOCODE = "https://geocoding-api.open-meteo.com/v1/search"
TIMEOUT = 15
STALE = 15 * 60          # seconds before a forecast is asked for again
AGENT = "freemac-sky/1 (+https://github.com/dean-plude/freemac)"

# WMO weather code -> (words, icon by day, icon by night, look)
# The look picks the window's colours: clear, cloudy, fog, rain, snow, storm.
CODES = {
    0: ("Clear", "weather-clear", "weather-clear-night", "clear"),
    1: ("Mostly Clear", "weather-few-clouds", "weather-few-clouds-night", "clear"),
    2: ("Partly Cloudy", "weather-few-clouds", "weather-few-clouds-night", "cloudy"),
    3: ("Cloudy", "weather-overcast", "weather-overcast", "cloudy"),
    45: ("Fog", "weather-fog", "weather-fog", "fog"),
    48: ("Freezing Fog", "weather-fog", "weather-fog", "fog"),
    51: ("Light Drizzle", "weather-showers-scattered", "weather-showers-scattered", "rain"),
    53: ("Drizzle", "weather-showers-scattered", "weather-showers-scattered", "rain"),
    55: ("Heavy Drizzle", "weather-showers", "weather-showers", "rain"),
    56: ("Freezing Drizzle", "weather-showers-scattered", "weather-showers-scattered", "rain"),
    57: ("Freezing Drizzle", "weather-showers", "weather-showers", "rain"),
    61: ("Light Rain", "weather-showers-scattered", "weather-showers-scattered", "rain"),
    63: ("Rain", "weather-showers", "weather-showers", "rain"),
    65: ("Heavy Rain", "weather-showers", "weather-showers", "rain"),
    66: ("Freezing Rain", "weather-showers", "weather-showers", "rain"),
    67: ("Freezing Rain", "weather-showers", "weather-showers", "rain"),
    71: ("Light Snow", "weather-snow", "weather-snow", "snow"),
    73: ("Snow", "weather-snow", "weather-snow", "snow"),
    75: ("Heavy Snow", "weather-snow", "weather-snow", "snow"),
    77: ("Snow Grains", "weather-snow", "weather-snow", "snow"),
    80: ("Showers", "weather-showers-scattered", "weather-showers-scattered", "rain"),
    81: ("Showers", "weather-showers", "weather-showers", "rain"),
    82: ("Heavy Showers", "weather-showers", "weather-showers", "rain"),
    85: ("Snow Showers", "weather-snow", "weather-snow", "snow"),
    86: ("Heavy Snow Showers", "weather-snow", "weather-snow", "snow"),
    95: ("Thunderstorms", "weather-storm", "weather-storm", "storm"),
    96: ("Thunderstorms and Hail", "weather-storm", "weather-storm", "storm"),
    99: ("Thunderstorms and Hail", "weather-storm", "weather-storm", "storm"),
}

# Countries that measure temperature in Fahrenheit.
FAHRENHEIT_COUNTRIES = {"US", "LR", "MM", "BS", "BZ", "KY", "PW", "FM", "MH"}


def describe(code, day=True):
    """(words, icon name, look) for a WMO code."""
    words, day_icon, night_icon, look = CODES.get(int(code) if code is not None else -1,
                                                   ("Unknown", "weather-severe-alert", "weather-severe-alert",
                                                    "cloudy"))
    return words, day_icon if day else night_icon, look


def config_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "freemac", "sky.json")


def cache_dir():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "freemac", "sky")


def _write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def time_zone():
    """The computer's time zone, like "America/Chicago", or None."""
    zone = os.environ.get("TZ", "").lstrip(":")
    if zone:
        return zone
    try:
        return os.path.realpath("/etc/localtime").split("zoneinfo/", 1)[1]
    except (IndexError, OSError):
        try:
            with open("/etc/timezone") as f:
                return f.read().strip() or None
        except OSError:
            return None


def zone_country(zone):
    """The two-letter country of a time zone, from tzdata's zone.tab, or None."""
    if not zone:
        return None
    try:
        with open("/usr/share/zoneinfo/zone.tab") as f:
            for line in f:
                fields = line.split("\t")
                if len(fields) >= 3 and not line.startswith("#") and fields[2].strip() == zone:
                    return fields[0]
    except OSError:
        pass
    return None


def default_unit():
    """F where the person's region uses Fahrenheit, else C: the choice in
    Dials > Language & Region, or else the locale's country, or the time
    zone's when the locale has none. (LANG is left out: every freemac from
    1.189 writes in en_US, wherever it is.)"""
    from . import region
    if os.path.exists(region.FILE):
        return "F" if region.fahrenheit() else "C"
    country = None
    for name in ("LC_MEASUREMENT", "LC_ALL"):
        value = os.environ.get(name, "")
        if "_" in value:
            country = value.split("_", 1)[1][:2].upper()
            break
    country = country or zone_country(time_zone())
    return "F" if country in FAHRENHEIT_COUNTRIES else "C"


def home_city():
    """A city name guessed from the computer's time zone ("America/Chicago"
    -> "Chicago"), to offer the first time Sky opens, or None."""
    zone = time_zone()
    if not zone or "/" not in zone or zone.startswith(("Etc/", "UTC", "GMT")):
        return None
    return zone.rsplit("/", 1)[1].replace("_", " ")


class Place:
    def __init__(self, name, region, country, latitude, longitude, timezone=None, country_code=None):
        self.name = name
        self.region = region or ""
        self.country = country or ""
        self.latitude = float(latitude)
        self.longitude = float(longitude)
        self.timezone = timezone
        self.country_code = country_code or ""

    @property
    def key(self):
        return f"{self.latitude:.3f},{self.longitude:.3f}"

    @property
    def where(self):
        """"Illinois, United States" for telling places with one name apart."""
        return ", ".join(p for p in (self.region, self.country) if p and p != self.name)

    def to_json(self):
        return {"name": self.name, "region": self.region, "country": self.country,
                "latitude": self.latitude, "longitude": self.longitude,
                "timezone": self.timezone, "country_code": self.country_code}

    @classmethod
    def from_json(cls, data):
        return cls(data["name"], data.get("region"), data.get("country"), data["latitude"],
                   data["longitude"], data.get("timezone"), data.get("country_code"))


def set_unit(unit):
    """Dials > Language & Region changed the temperature: Sky follows."""
    try:
        with open(config_path()) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return
    if isinstance(data, dict) and unit in ("F", "C"):
        data["unit"] = unit
        try:
            _write_json(config_path(), data)
        except OSError:
            pass


class Settings:
    def __init__(self):
        self.places = []
        self.unit = default_unit()
        self.chosen = None
        try:
            with open(config_path()) as f:
                data = json.load(f)
            self.places = [Place.from_json(p) for p in data.get("places", [])]
            self.unit = data.get("unit", self.unit) if data.get("unit") in ("F", "C") else self.unit
            self.chosen = data.get("chosen")
            self.asked_home = bool(data.get("asked_home"))
        except (OSError, ValueError, KeyError, TypeError):
            self.asked_home = False

    def save(self):
        try:
            _write_json(config_path(), {"places": [p.to_json() for p in self.places], "unit": self.unit,
                                        "chosen": self.chosen, "asked_home": self.asked_home})
        except OSError:
            pass

    def add(self, place):
        if all(p.key != place.key for p in self.places):
            self.places.append(place)
        self.chosen = place.key
        self.save()

    def remove(self, key):
        self.places = [p for p in self.places if p.key != key]
        if self.chosen == key:
            self.chosen = self.places[0].key if self.places else None
        self.save()

    def move(self, key, index):
        place = next((p for p in self.places if p.key == key), None)
        if place is None:
            return
        self.places.remove(place)
        self.places.insert(max(0, min(index, len(self.places))), place)
        self.save()


def _get(url, params):
    sample = os.environ.get("FREEMAC_SKY_SAMPLE")
    if sample:
        # Made-up answers for trying Sky without a network: SAMPLE/geocode.json
        # and SAMPLE/forecast.json, in Open-Meteo's own shape.
        with open(os.path.join(sample, "geocode.json" if url == GEOCODE else "forecast.json")) as f:
            data = json.load(f)
        if url == GEOCODE:
            wanted = params["name"].lower()
            data["results"] = [r for r in data.get("results", []) if r["name"].lower().startswith(wanted)]
        return data
    full = url + "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(full, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8"))


def search(name, count=8):
    """Places called name, best first. Raises OSError when offline."""
    name = name.strip()
    if len(name) < 2:
        return []
    data = _get(GEOCODE, {"name": name, "count": count, "language": "en", "format": "json"})
    return [Place(r["name"], r.get("admin1"), r.get("country"), r["latitude"], r["longitude"],
                  r.get("timezone"), r.get("country_code"))
            for r in data.get("results") or [] if "latitude" in r and "longitude" in r]


def forecast(place, unit):
    """The forecast for place, in unit ("F" or "C"), as a Forecast.
    Raises OSError when offline, ValueError when the answer makes no sense."""
    params = {
        "latitude": f"{place.latitude:.4f}", "longitude": f"{place.longitude:.4f}",
        "current": "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,"
                   "wind_speed_10m,precipitation",
        "hourly": "temperature_2m,weather_code,is_day,precipitation_probability",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,"
                 "precipitation_probability_max,uv_index_max",
        "timezone": "auto", "forecast_days": 10,
        "temperature_unit": "fahrenheit" if unit == "F" else "celsius",
        "wind_speed_unit": "mph" if unit == "F" else "kmh",
    }
    data = _get(FORECAST, params)
    data["_unit"] = unit
    data["_fetched"] = datetime.datetime.now().timestamp()
    try:
        os.makedirs(cache_dir(), exist_ok=True)
        _write_json(os.path.join(cache_dir(), place.key + ".json"), data)
    except OSError:
        pass
    return Forecast(data)


def cached(place, unit):
    """The last forecast kept for place in unit, or None."""
    try:
        with open(os.path.join(cache_dir(), place.key + ".json")) as f:
            data = json.load(f)
        if data.get("_unit") != unit:
            return None
        return Forecast(data)
    except (OSError, ValueError, KeyError, TypeError):
        return None


def _time(text):
    return datetime.datetime.fromisoformat(text)


class Forecast:
    """One place's weather. Times are the place's own local times."""

    def __init__(self, data):
        self.data = data
        self.unit = data.get("_unit", "C")
        self.fetched = data.get("_fetched", 0)
        self.offset = int(data.get("utc_offset_seconds", 0))
        current = data["current"]
        self.temperature = current["temperature_2m"]
        self.feels_like = current.get("apparent_temperature")
        self.humidity = current.get("relative_humidity_2m")
        self.wind = current.get("wind_speed_10m")
        self.code = current.get("weather_code", 0)
        self.is_day = bool(current.get("is_day", 1))
        self.time = _time(current["time"])
        daily = data["daily"]
        self.days = []
        for i, day in enumerate(daily["time"]):
            self.days.append({
                "date": datetime.date.fromisoformat(day),
                "code": daily["weather_code"][i],
                "high": daily["temperature_2m_max"][i],
                "low": daily["temperature_2m_min"][i],
                "rain": (daily.get("precipitation_probability_max") or [None] * (i + 1))[i],
                "sunrise": _time(daily["sunrise"][i]) if daily.get("sunrise") else None,
                "sunset": _time(daily["sunset"][i]) if daily.get("sunset") else None,
                "uv": (daily.get("uv_index_max") or [None] * (i + 1))[i],
            })
        if not self.days:
            raise ValueError("no days")
        hourly = data["hourly"]
        self.hours = []
        for i, when in enumerate(hourly["time"]):
            self.hours.append({
                "time": _time(when),
                "temperature": hourly["temperature_2m"][i],
                "code": hourly["weather_code"][i],
                "is_day": bool(hourly["is_day"][i]) if hourly.get("is_day") else True,
                "rain": (hourly.get("precipitation_probability") or [None] * (i + 1))[i],
            })

    @property
    def words(self):
        return describe(self.code, self.is_day)[0]

    @property
    def icon(self):
        return describe(self.code, self.is_day)[1]

    @property
    def look(self):
        return describe(self.code, self.is_day)[2]

    @property
    def today(self):
        for day in self.days:
            if day["date"] == self.time.date():
                return day
        return self.days[0]

    def next_hours(self, count=24):
        """The hours from now on: the first is now."""
        start = self.time.replace(minute=0, second=0, microsecond=0)
        upcoming = [h for h in self.hours if h["time"] >= start]
        return upcoming[:count]

    def sun_events(self, count=24):
        """Sunrises and sunsets within the next count hours: (time, "Sunrise" or "Sunset")."""
        start = self.time
        end = start + datetime.timedelta(hours=count)
        found = []
        for day in self.days:
            for key, words in (("sunrise", "Sunrise"), ("sunset", "Sunset")):
                when = day.get(key)
                if when and start < when < end:
                    found.append((when, words))
        return sorted(found)

    def stale(self, now=None):
        now = now or datetime.datetime.now().timestamp()
        return now - self.fetched > STALE


def degrees(value):
    """52° from 51.6."""
    if value is None:
        return "–"
    return f"{round(value):.0f}°".replace("-0°", "0°")


if __name__ == "__main__":
    import sys
    found = search(" ".join(sys.argv[1:]) or "Chicago")
    for place in found:
        print(place.name, "|", place.where, place.latitude, place.longitude)
    if found:
        f = forecast(found[0], default_unit())
        print(degrees(f.temperature), f.words, "H", degrees(f.today["high"]), "L", degrees(f.today["low"]))
