# SPDX-License-Identifier: GPL-3.0-or-later
"""Language & Region: which country's way of writing dates, times, numbers
and money this person uses, the first day of their week, and Celsius or
Fahrenheit, as on a Mac.

The region is a glibc locale (en_GB.UTF-8, de_DE.UTF-8...) from REGIONS,
which the ISO build generates. It reaches every app through the session's
LC_TIME, LC_NUMERIC, LC_MONETARY and the like: Dials writes them to
~/.config/freemac/region.env, which freemac-session reads at login. The
language apps speak (LANG, LC_MESSAGES) stays English. freemac's own apps
read the first day of the week, the clock and the temperature unit straight
from ~/.config/freemac/region.json, so they follow at once.

No GTK here, so the session, Topline and the tests can use it. Original
freemac code.
"""
import json
import os
import re
import subprocess

CONFIG = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "freemac")
FILE = os.path.join(CONFIG, "region.json")
ENV_FILE = os.path.join(CONFIG, "region.env")
DEFAULT = "en_US.UTF-8"

SUNDAY, MONDAY, SATURDAY = 6, 0, 5   # as datetime counts: Monday is 0
WEEKDAY_NAMES = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")

# locale: (name as the list shows it, first day of the week, 24-hour clock,
# Fahrenheit). The ISO build generates every one of these (build-iso.sh reads
# this table), so the list never offers a region the computer can't use.
REGIONS = {
    "en_US.UTF-8": ("United States", SUNDAY, False, True),
    "en_GB.UTF-8": ("United Kingdom", MONDAY, True, False),
    "en_CA.UTF-8": ("Canada (English)", SUNDAY, False, False),
    "fr_CA.UTF-8": ("Canada (French)", SUNDAY, True, False),
    "en_AU.UTF-8": ("Australia", MONDAY, False, False),
    "en_NZ.UTF-8": ("New Zealand", MONDAY, False, False),
    "en_IE.UTF-8": ("Ireland", MONDAY, True, False),
    "en_IN.UTF-8": ("India", SUNDAY, False, False),
    "en_ZA.UTF-8": ("South Africa", SUNDAY, True, False),
    "en_SG.UTF-8": ("Singapore", SUNDAY, False, False),
    "en_PH.UTF-8": ("Philippines", SUNDAY, False, False),
    "de_DE.UTF-8": ("Germany", MONDAY, True, False),
    "de_AT.UTF-8": ("Austria", MONDAY, True, False),
    "de_CH.UTF-8": ("Switzerland (German)", MONDAY, True, False),
    "fr_FR.UTF-8": ("France", MONDAY, True, False),
    "fr_BE.UTF-8": ("Belgium (French)", MONDAY, True, False),
    "nl_BE.UTF-8": ("Belgium (Dutch)", MONDAY, True, False),
    "nl_NL.UTF-8": ("Netherlands", MONDAY, True, False),
    "es_ES.UTF-8": ("Spain", MONDAY, True, False),
    "es_MX.UTF-8": ("Mexico", SUNDAY, False, False),
    "es_AR.UTF-8": ("Argentina", MONDAY, True, False),
    "es_CO.UTF-8": ("Colombia", SUNDAY, False, False),
    "es_US.UTF-8": ("United States (Spanish)", SUNDAY, False, True),
    "pt_PT.UTF-8": ("Portugal", MONDAY, True, False),
    "pt_BR.UTF-8": ("Brazil", SUNDAY, True, False),
    "it_IT.UTF-8": ("Italy", MONDAY, True, False),
    "sv_SE.UTF-8": ("Sweden", MONDAY, True, False),
    "nb_NO.UTF-8": ("Norway", MONDAY, True, False),
    "da_DK.UTF-8": ("Denmark", MONDAY, True, False),
    "fi_FI.UTF-8": ("Finland", MONDAY, True, False),
    "pl_PL.UTF-8": ("Poland", MONDAY, True, False),
    "cs_CZ.UTF-8": ("Czechia", MONDAY, True, False),
    "hu_HU.UTF-8": ("Hungary", MONDAY, True, False),
    "ro_RO.UTF-8": ("Romania", MONDAY, True, False),
    "el_GR.UTF-8": ("Greece", MONDAY, True, False),
    "tr_TR.UTF-8": ("Türkiye", MONDAY, True, False),
    "uk_UA.UTF-8": ("Ukraine", MONDAY, True, False),
    "ru_RU.UTF-8": ("Russia", MONDAY, True, False),
    "he_IL.UTF-8": ("Israel", SUNDAY, True, False),
    "ar_AE.UTF-8": ("United Arab Emirates", SATURDAY, False, False),
    "ja_JP.UTF-8": ("Japan", SUNDAY, True, False),
    "ko_KR.UTF-8": ("South Korea", SUNDAY, False, False),
    "zh_CN.UTF-8": ("China mainland", MONDAY, True, False),
    "zh_TW.UTF-8": ("Taiwan", SUNDAY, False, False),
    "zh_HK.UTF-8": ("Hong Kong", SUNDAY, False, False),
    "th_TH.UTF-8": ("Thailand", SUNDAY, True, False),
    "vi_VN.UTF-8": ("Vietnam", MONDAY, True, False),
    "id_ID.UTF-8": ("Indonesia", SUNDAY, True, False),
}

# Regions that write the month before the day.
MONTH_FIRST = {"en_US.UTF-8", "es_US.UTF-8", "en_CA.UTF-8", "en_PH.UTF-8"}

# The format categories the region sets. Messages (the language) stay as
# they are; LC_MEASUREMENT may be set apart (Measurement system).
FORMAT_CATEGORIES = ("LC_TIME", "LC_NUMERIC", "LC_MONETARY", "LC_PAPER",
                     "LC_NAME", "LC_ADDRESS", "LC_TELEPHONE")
# A locale whose measurement is metric, and one whose is US customary.
MEASURE_LOCALE = {"metric": "en_GB.UTF-8", "us": "en_US.UTF-8"}
_SAFE = re.compile(r"^[a-z]{2,3}_[A-Z]{2}\.UTF-8$")


def ordered():
    """The regions by name, for the list: [(locale, name)]."""
    return sorted(((code, row[0]) for code, row in REGIONS.items()), key=lambda pair: pair[1].casefold())


def build_list():
    """The lines of /etc/locale.gen the ISO build writes."""
    return [f"{code} UTF-8" for code in sorted(REGIONS)]


def _read(path=FILE):
    try:
        with open(path, encoding="utf-8") as handle:
            saved = json.load(handle)
        return saved if isinstance(saved, dict) else {}
    except (OSError, ValueError):
        return {}


def settings(path=FILE):
    """{"region", "first_day", "temperature", "measurement"}: the region a
    locale from REGIONS; the others "auto" (the region's own) or a choice."""
    return settings_from(_read(path))


def save(path=FILE, env_path=ENV_FILE, **changes):
    """Keep changes ({"region": ..., "first_day": ...}) and write the
    session's environment file to match."""
    current = settings(path)
    current.update(changes)
    current = settings_from(current)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        temporary = path + ".new"
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(current, handle, indent=2, sort_keys=True)
        os.replace(temporary, path)
        write_env(current, env_path)
    except OSError:
        pass
    return current


def settings_from(raw):
    """raw cleaned the way settings() cleans a saved file."""
    region = raw.get("region")
    first = raw.get("first_day", "auto")
    temperature = raw.get("temperature", "auto")
    measurement = raw.get("measurement", "auto")
    return {
        "region": region if region in REGIONS else DEFAULT,
        "first_day": first if first in ("auto",) + tuple(range(7)) else "auto",
        "temperature": temperature if temperature in ("auto", "C", "F") else "auto",
        "measurement": measurement if measurement in ("auto", "metric", "us") else "auto",
    }


def environment(setting):
    """{category: locale} for the session. Only locales from REGIONS (and
    the two measurement ones) are ever written."""
    setting = settings_from(setting)
    region = setting["region"]
    if not _SAFE.match(region):
        region = DEFAULT
    values = {category: region for category in FORMAT_CATEGORIES}
    if setting["measurement"] == "auto":
        values["LC_MEASUREMENT"] = region
    else:
        values["LC_MEASUREMENT"] = MEASURE_LOCALE[setting["measurement"]]
    return values


def write_env(setting, env_path=ENV_FILE):
    lines = ["# Written by Dials > Language & Region; read by freemac-session at login."]
    lines += [f"export {key}={value}" for key, value in sorted(environment(setting).items())]
    os.makedirs(os.path.dirname(env_path), exist_ok=True)
    temporary = env_path + ".new"
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    os.replace(temporary, env_path)


# ---- What freemac's own apps follow ----------------------------------------------------
def first_weekday(path=FILE):
    """The first day of the week, as datetime counts (Monday is 0)."""
    setting = settings(path)
    if setting["first_day"] != "auto":
        return setting["first_day"]
    return REGIONS[setting["region"]][1]


def uses_24_hour(path=FILE):
    """Whether the region writes the time on a 24-hour clock."""
    return REGIONS[settings(path)["region"]][2]


def fahrenheit(path=FILE):
    setting = settings(path)
    if setting["temperature"] != "auto":
        return setting["temperature"] == "F"
    return REGIONS[setting["region"]][3]


def metric(path=FILE):
    setting = settings(path)
    if setting["measurement"] != "auto":
        return setting["measurement"] == "metric"
    return setting["region"] not in ("en_US.UTF-8", "es_US.UTF-8")


def month_first(path=FILE):
    """Whether the region writes the month before the day (Nov 24)."""
    return settings(path)["region"] in MONTH_FIRST


def week_letters(first=None, names=WEEKDAY_NAMES):
    """The days' initials from the first day of the week: S M T W T F S."""
    first = first_weekday() if first is None else first
    return [names[(first + i) % 7][0] for i in range(7)]


def week_names(first=None, length=3):
    first = first_weekday() if first is None else first
    return [WEEKDAY_NAMES[(first + i) % 7][:length] for i in range(7)]


def start_of_week(day, first=None):
    """The date the week holding day starts on."""
    import datetime as dt
    first = first_weekday() if first is None else first
    return day - dt.timedelta(days=(day.weekday() - first) % 7)


def english_names():
    """Day and month names in English for this program (its LC_TIME): the
    region's own locale when that's English, else US English."""
    import locale
    current = os.environ.get("LC_ALL") or os.environ.get("LC_TIME") or os.environ.get("LANG") or ""
    if current.startswith("en_"):
        return
    for name in ("en_US.UTF-8", "C.UTF-8"):
        try:
            locale.setlocale(locale.LC_TIME, name)
            return
        except locale.Error:
            continue


def english_env(env=None):
    """A copy of the environment for a program that isn't Python (gtklock),
    with day and month names in English as english_names() gives freemac's
    own, and FREEMAC_DATE_FORMAT, the long date in the region's order."""
    env = dict(os.environ if env is None else env)
    current = env.get("LC_ALL") or env.get("LC_TIME") or env.get("LANG") or ""
    if not current.startswith("en_"):
        env.pop("LC_ALL", None)
        env["LC_TIME"] = "en_US.UTF-8"
    env["FREEMAC_DATE_FORMAT"] = long_date_format()
    return env


def long_date_format():
    """"Tuesday, November 24" where the month comes first, else
    "Tuesday 24 November"."""
    return "%A, %B %-d" if month_first() else "%A %-d %B"


# ---- Examples, as Dials shows them -----------------------------------------------------
_EXAMPLE = r"""
import locale, sys, time
loc = sys.argv[1]
try:
    locale.setlocale(locale.LC_ALL, loc)
except locale.Error:
    print("\n\n\n"); sys.exit()
when = time.struct_time((2026, 11, 24, 14, 30, 0, 1, 328, 0))
print(time.strftime("%x", when))
print(time.strftime("%X", when))
print(locale.format_string("%.2f", 1234567.89, grouping=True))
print(locale.currency(1234.56, grouping=True))
"""


def examples(code):
    """(date, time, number, currency) as the region writes them, or Nones
    when the computer hasn't that locale."""
    if code not in REGIONS:
        return (None, None, None, None)
    try:
        out = subprocess.run(["python3", "-I", "-c", _EXAMPLE, code], capture_output=True, text=True,
                             timeout=5, env={"PATH": os.environ.get("PATH", "/usr/bin:/bin")}).stdout
    except (OSError, subprocess.SubprocessError):
        return (None, None, None, None)
    lines = (out.split("\n") + ["", "", "", ""])[:4]
    return tuple(line.strip() or None for line in lines)


def available():
    """The regions this computer can use (generated locales)."""
    try:
        out = subprocess.run(["locale", "-a"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return set()
    have = {line.strip().lower().replace("-", "") for line in out.splitlines()}
    return {code for code in REGIONS if code.lower().replace("-", "") in have}
