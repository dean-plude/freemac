# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit conversions for Seek, as a Mac's search field does them: "5 km"
answers in miles, "70 f to c" in Celsius, "2 cups in ml" in millilitres.
Original freemac code.

    convert("5 km")          -> ("3.107 miles", "3.107", "5 kilometres")
    convert("70 f to c")     -> ("21.11 °C", "21.11", "70 °F")
"""
import re

# kind: {unit: (factor to the kind's base unit, singular, plural)}
UNITS = {
    "length": {
        "mm": (0.001, "millimetre", "millimetres"), "cm": (0.01, "centimetre", "centimetres"),
        "m": (1.0, "metre", "metres"), "km": (1000.0, "kilometre", "kilometres"),
        "in": (0.0254, "inch", "inches"), "ft": (0.3048, "foot", "feet"),
        "yd": (0.9144, "yard", "yards"), "mi": (1609.344, "mile", "miles"),
    },
    "mass": {
        "mg": (1e-6, "milligram", "milligrams"), "g": (0.001, "gram", "grams"),
        "kg": (1.0, "kilogram", "kilograms"), "t": (1000.0, "tonne", "tonnes"),
        "oz": (0.028349523125, "ounce", "ounces"), "lb": (0.45359237, "pound", "pounds"),
        "st": (6.35029318, "stone", "stone"),
    },
    "volume": {
        "ml": (0.001, "millilitre", "millilitres"), "l": (1.0, "litre", "litres"),
        "tsp": (0.00492892159375, "teaspoon", "teaspoons"), "tbsp": (0.01478676478125, "tablespoon", "tablespoons"),
        "floz": (0.0295735295625, "fluid ounce", "fluid ounces"), "cup": (0.2365882365, "cup", "cups"),
        "pt": (0.473176473, "pint", "pints"), "qt": (0.946352946, "quart", "quarts"),
        "gal": (3.785411784, "gallon", "gallons"),
    },
    "speed": {
        "m/s": (1.0, "metre per second", "metres per second"), "km/h": (1 / 3.6, "km/h", "km/h"),
        "mph": (0.44704, "mph", "mph"), "kn": (1852 / 3600, "knot", "knots"),
    },
    "time": {
        "s": (1.0, "second", "seconds"), "min": (60.0, "minute", "minutes"),
        "h": (3600.0, "hour", "hours"), "day": (86400.0, "day", "days"),
        "week": (604800.0, "week", "weeks"), "year": (31557600.0, "year", "years"),
    },
    "data": {
        "B": (1.0, "byte", "bytes"), "KB": (1e3, "KB", "KB"), "MB": (1e6, "MB", "MB"),
        "GB": (1e9, "GB", "GB"), "TB": (1e12, "TB", "TB"),
    },
    "area": {
        "m2": (1.0, "square metre", "square metres"), "km2": (1e6, "square kilometre", "square kilometres"),
        "ft2": (0.09290304, "square foot", "square feet"), "mi2": (2589988.110336, "square mile", "square miles"),
        "acre": (4046.8564224, "acre", "acres"), "ha": (10000.0, "hectare", "hectares"),
    },
    "temperature": {
        "C": (None, "°C", "°C"), "F": (None, "°F", "°F"), "K": (None, "K", "K"),
    },
}

# What people type -> unit. Matched after lower-casing and squeezing spaces.
ALIASES = {
    "mm": "mm", "millimeter": "mm", "millimetre": "mm",
    "cm": "cm", "centimeter": "cm", "centimetre": "cm",
    "m": "m", "meter": "m", "metre": "m",
    "km": "km", "kilometer": "km", "kilometre": "km", "kms": "km",
    "in": "in", "inch": "in", "inches": "in", '"': "in",
    "ft": "ft", "foot": "ft", "feet": "ft", "'": "ft",
    "yd": "yd", "yds": "yd", "yard": "yd",
    "mi": "mi", "mile": "mi",
    "mg": "mg", "milligram": "mg", "g": "g", "gram": "g", "gramme": "g",
    "kg": "kg", "kgs": "kg", "kilo": "kg", "kilogram": "kg", "kilogramme": "kg",
    "tonne": "t", "metric ton": "t",
    "oz": "oz", "ounce": "oz", "lb": "lb", "lbs": "lb", "pound": "lb",
    "st": "st", "stone": "st", "stones": "st",
    "ml": "ml", "milliliter": "ml", "millilitre": "ml",
    "l": "l", "liter": "l", "litre": "l", "ltr": "l",
    "tsp": "tsp", "teaspoon": "tsp", "tbsp": "tbsp", "tablespoon": "tbsp",
    "fl oz": "floz", "floz": "floz", "fluid ounce": "floz",
    "cup": "cup", "pt": "pt", "pint": "pt", "qt": "qt", "quart": "qt",
    "gal": "gal", "gallon": "gal",
    "m/s": "m/s", "meters per second": "m/s", "metres per second": "m/s",
    "km/h": "km/h", "kmh": "km/h", "kph": "km/h", "kmph": "km/h", "kilometers per hour": "km/h",
    "kilometres per hour": "km/h",
    "mph": "mph", "miles per hour": "mph", "kn": "kn", "knot": "kn", "kt": "kn",
    "s": "s", "sec": "s", "secs": "s", "second": "s",
    "min": "min", "mins": "min", "minute": "min",
    "h": "h", "hr": "h", "hrs": "h", "hour": "h",
    "day": "day", "d": "day", "week": "week", "wk": "week", "wks": "week",
    "year": "year", "yr": "year", "yrs": "year",
    "b": "B", "byte": "B", "kb": "KB", "kilobyte": "KB", "mb": "MB", "megabyte": "MB",
    "gb": "GB", "gigabyte": "GB", "tb": "TB", "terabyte": "TB",
    "m2": "m2", "m²": "m2", "sq m": "m2", "sqm": "m2", "square meter": "m2", "square metre": "m2",
    "km2": "km2", "km²": "km2", "sq km": "km2", "square kilometer": "km2", "square kilometre": "km2",
    "ft2": "ft2", "ft²": "ft2", "sq ft": "ft2", "sqft": "ft2", "square foot": "ft2", "square feet": "ft2",
    "mi2": "mi2", "mi²": "mi2", "sq mi": "mi2", "square mile": "mi2",
    "acre": "acre", "ac": "acre", "ha": "ha", "hectare": "ha",
    "c": "C", "°c": "C", "celsius": "C", "centigrade": "C",
    "f": "F", "°f": "F", "fahrenheit": "F",
    "k": "K", "kelvin": "K",
}

# The usual answer when no unit to convert to is given: metric to US and back.
DEFAULT = {
    "km": "mi", "mi": "km", "m": "ft", "ft": "m", "cm": "in", "in": "cm", "mm": "in", "yd": "m",
    "kg": "lb", "lb": "kg", "g": "oz", "oz": "g", "st": "kg", "t": "lb", "mg": "g",
    "l": "gal", "gal": "l", "ml": "floz", "floz": "ml", "cup": "ml", "tsp": "ml", "tbsp": "ml",
    "pt": "l", "qt": "l",
    "km/h": "mph", "mph": "km/h", "m/s": "km/h", "kn": "km/h",
    "s": "min", "min": "s", "h": "min", "day": "h", "week": "day", "year": "day",
    "B": "KB", "KB": "MB", "MB": "GB", "GB": "MB", "TB": "GB",
    "m2": "ft2", "ft2": "m2", "km2": "mi2", "mi2": "km2", "acre": "m2", "ha": "acre",
    "C": "F", "F": "C", "K": "C",
}

PATTERN = re.compile(
    r"^\s*(-?(?:\d{1,3}(?:,\d{3})+|\d*)(?:\.\d+)?)\s*([^\d\s].*?)"
    r"(?:\s+(?:in|to|as|into|=)\s+(.+?))?\s*$", re.IGNORECASE)


def unit_of(text):
    """(kind, unit) for what was typed, or None."""
    words = re.sub(r"\s+", " ", text.strip().lower())
    words = re.sub(r"^(?:degrees?|deg)\s+", "", words)
    for candidate in (words, words[:-1] if words.endswith("s") else None,
                      words[:-2] if words.endswith("es") else None):
        if candidate and candidate in ALIASES:
            unit = ALIASES[candidate]
            for kind, units in UNITS.items():
                if unit in units:
                    return kind, unit
    return None


def _temperature(value, src, dst):
    kelvin = {"C": value + 273.15, "F": (value - 32) * 5 / 9 + 273.15, "K": value}[src]
    return {"C": kelvin - 273.15, "F": (kelvin - 273.15) * 9 / 5 + 32, "K": kelvin}[dst]


def number(value):
    """A number as people write it: 3.107, 1,609, 0.0002."""
    if value == 0:
        return "0"
    size = abs(value)
    if size >= 10000:
        text = f"{value:,.0f}"
    elif size >= 100:
        text = f"{value:,.2f}"
    elif size >= 0.001:
        text = f"{value:.4g}"
    else:
        text = f"{value:.3g}"
    if "." in text and "e" not in text:
        text = text.rstrip("0").rstrip(".")
    return text


def amount(value, kind, unit):
    _factor, one, many = UNITS[kind][unit]
    if kind == "temperature" or unit in ("km/h", "mph"):
        return f"{number(value)} {one}"
    return f"{number(value)} {one if abs(value) == 1 else many}"


def convert(text):
    """(answer, bare number, what was asked) for a conversion like "5 km in
    miles", or None if the text isn't one."""
    found = PATTERN.match(text or "")
    if not found or not any(ch.isdigit() for ch in found.group(1)):
        return None
    try:
        value = float(found.group(1).replace(",", ""))
    except ValueError:
        return None
    source = unit_of(found.group(2))
    if source is None:
        return None
    kind, src = source
    if found.group(3):
        target = unit_of(found.group(3))
        if target is None or target[0] != kind:
            return None
        dst = target[1]
    else:
        dst = DEFAULT.get(src)
        if dst is None:
            return None
    if dst == src:
        return None
    if kind == "temperature":
        result = _temperature(value, src, dst)
    else:
        result = value * UNITS[kind][src][0] / UNITS[kind][dst][0]
    return amount(result, kind, dst), number(result).replace(",", ""), amount(value, kind, src)


if __name__ == "__main__":
    import sys
    print(convert(" ".join(sys.argv[1:])))
