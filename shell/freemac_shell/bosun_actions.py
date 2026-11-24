# SPDX-License-Identifier: GPL-3.0-or-later
"""Bosun's actions: the steps a shortcut is made of, and running them.

A shortcut is a list of steps, done in order. Each step gets what the step
before it made (some words, some files, or nothing) and passes on what it
makes itself, so "Get Files in Folder", then "Make PDF", then "Show in
Drawer" puts a folder's pictures into one PDF and shows it. In any text a
step asks for, {input} stands for what came from the step before.

What a step needs from the person (Ask for Text, Show Result) goes through
`ui`, which the app or freemac-bosun gives; nothing here needs GTK until a
step that draws pictures or asks Gio is run. Original freemac code.
"""
import os
import shutil
import subprocess
import time

INPUT = "{input}"
LONGEST_SCRIPT = 120        # seconds a Run Shell Script step may take
MOST_OPENED = 20            # files one Open Files step opens at once

PICTURES = (".jpg", ".jpeg", ".png", ".gif", ".tif", ".tiff", ".bmp", ".webp", ".heic", ".svg")
KINDS = {
    "any": ("Any file", ()),
    "pictures": ("Pictures", PICTURES),
    "pdf": ("PDF documents", (".pdf",)),
    "music": ("Music", (".mp3", ".m4a", ".ogg", ".oga", ".flac", ".wav", ".opus", ".aac")),
    "movies": ("Movies", (".mp4", ".m4v", ".mkv", ".webm", ".mov", ".avi", ".ogv")),
    "documents": ("Documents", (".txt", ".md", ".odt", ".doc", ".docx", ".rtf", ".pdf", ".ods",
                                ".xls", ".xlsx", ".odp", ".ppt", ".pptx", ".csv")),
}


class Stopped(Exception):
    """The person stopped the shortcut (Cancel in Ask for Text)."""


class StepFailed(Exception):
    """A step couldn't be done; the message says why, in plain words."""


# What passes between steps ---------------------------------------------------
def as_text(value):
    if value is None:
        return ""
    if isinstance(value, (list, tuple)):
        return "\n".join(os.path.basename(p) for p in value)
    return str(value)


def as_files(value):
    if isinstance(value, (list, tuple)):
        return [p for p in value if os.path.exists(p)]
    if isinstance(value, str):
        found = []
        for line in value.splitlines():
            path = os.path.expanduser(line.strip())
            if path and os.path.isabs(path) and os.path.exists(path):
                found.append(path)
        return found
    return []


def fill(template, value):
    """The template with {input} replaced by what came before."""
    return (template or "").replace(INPUT, as_text(value))


def describe(value):
    """A few words for what a step made, for the app's run view."""
    if value is None:
        return "Nothing"
    if isinstance(value, (list, tuple)):
        if not value:
            return "No files"
        if len(value) == 1:
            return os.path.basename(value[0])
        return f"{len(value)} files"
    text = " ".join(str(value).split())
    return f"“{text[:60]}…”" if len(text) > 60 else f"“{text}”"


def _launch(*argv):
    try:
        subprocess.Popen(list(argv), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except OSError as error:
        raise StepFailed(f"{argv[0]} couldn't be started ({error.strerror or error}).")


def _pictures(value):
    pictures = [p for p in as_files(value) if os.path.isfile(p) and p.lower().endswith(PICTURES)]
    if not pictures:
        raise StepFailed("There were no pictures to work on.")
    return pictures


def _need_files(value):
    files = as_files(value)
    if not files:
        raise StepFailed("There were no files to work on.")
    return files


# Text ----------------------------------------------------------------------------
def _text(p, value, ui):
    return fill(p["text"], value)


def _ask(p, value, ui):
    answer = ui.ask(fill(p["prompt"], value) or "Type something:", fill(p["default"], value))
    if answer is None:
        raise Stopped
    return answer


def _case(p, value, ui):
    text = as_text(value)
    how = p["case"]
    if how == "upper":
        return text.upper()
    if how == "lower":
        return text.lower()
    if how == "title":
        return " ".join(word[:1].upper() + word[1:].lower() for word in text.split(" "))
    # Sentence case: the first letter of each sentence a capital, the rest small.
    out, start = [], True
    for char in text.lower():
        if start and char.isalpha():
            out.append(char.upper())
            start = False
        else:
            out.append(char)
        if char in ".!?\n":
            start = True
    return "".join(out)


def _replace(p, value, ui):
    text, find, put = as_text(value), p["find"], p["with"]
    if not find:
        return text
    if p["any_case"]:
        lower, needle, out, at = text.lower(), find.lower(), [], 0
        while True:
            found = lower.find(needle, at)
            if found < 0:
                out.append(text[at:])
                return "".join(out)
            out.append(text[at:found] + put)
            at = found + len(find)
    return text.replace(find, put)


def _count(p, value, ui):
    text = as_text(value)
    if isinstance(value, (list, tuple)) and p["what"] == "items":
        return str(len(value))
    return str({"characters": len(text), "words": len(text.split()),
                "lines": len(text.splitlines()), "items": len(text.splitlines())}[p["what"]])


def _get_clipboard(p, value, ui):
    if not shutil.which("wl-paste"):
        raise StepFailed("The clipboard can't be read here.")
    try:
        result = subprocess.run(["wl-paste", "--no-newline", "--type", "text"], capture_output=True, timeout=3)
    except (OSError, subprocess.TimeoutExpired):
        raise StepFailed("The clipboard couldn't be read.")
    if result.returncode:
        return ""
    return result.stdout.decode("utf-8", "replace")


def _copy(p, value, ui):
    if not shutil.which("wl-copy"):
        raise StepFailed("The clipboard can't be used here.")
    files = value if isinstance(value, (list, tuple)) else None
    try:
        if files:
            from urllib.parse import quote
            listing = "".join("file://" + quote(os.path.abspath(f)) + "\r\n" for f in files)
            subprocess.run(["wl-copy", "--type", "text/uri-list"], input=listing.encode(), timeout=3, check=True)
        else:
            subprocess.run(["wl-copy"], input=as_text(value).encode(), timeout=3, check=True)
    except (OSError, subprocess.SubprocessError):
        raise StepFailed("It couldn't be copied.")
    return value


def _speak(p, value, ui):
    text = fill(p["text"], value).strip()
    if text:
        _launch("freemac-speak", text)
    return value


def _show(p, value, ui):
    ui.show(fill(p["text"], value))
    return value


def _notify(p, value, ui):
    try:
        from . import beacon
        beacon.send(fill(p["title"], value) or "Bosun", fill(p["body"], value),
                    icon="freemac-bosun", app="Bosun")
    except Exception:
        raise StepFailed("The notification couldn't be shown.")
    return value


# Files ----------------------------------------------------------------------------
def _folder_files(p, value, ui):
    folder = os.path.expanduser(fill(p["folder"], value) or "~")
    if not os.path.isdir(folder):
        raise StepFailed(f"There's no folder at {folder}.")
    endings = KINDS.get(p["kind"], KINDS["any"])[1]
    found = []
    for root, dirs, files in os.walk(folder):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for name in sorted(files, key=str.lower):
            if name.startswith(".") or (endings and not name.lower().endswith(endings)):
                continue
            found.append(os.path.join(root, name))
        if not p["inside"]:
            break
    return found


def _open_files(p, value, ui):
    for path in _need_files(value)[:MOST_OPENED]:
        _launch("xdg-open", path)
    return value


def _reveal(p, value, ui):
    files = _need_files(value)
    _launch("freemac-drawer", files[0])
    return value


def _compress(p, value, ui):
    from . import drawer_archive
    try:
        return [drawer_archive.compress(_need_files(value))]
    except OSError as error:
        raise StepFailed(f"The archive couldn't be made ({error.strerror or error}).")


def _make_pdf(p, value, ui):
    from . import quick_actions
    target, error = quick_actions.make_pdf(_pictures(value))
    if not target:
        raise StepFailed(f"The PDF couldn't be made ({error})." if error else "The PDF couldn't be made.")
    return [target]


def _rotate(p, value, ui):
    from . import quick_actions
    pictures = _pictures(value)
    error = quick_actions.rotate(pictures, p["way"] == "right")
    if error:
        raise StepFailed(f"A picture couldn't be turned ({error}).")
    return pictures


def _resize(p, value, ui):
    import gi
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf, GLib
    from . import quick_actions, transfer
    longest = max(16, min(20000, int(p["size"] or 1024)))
    made = []
    for path in _pictures(value):
        kind = quick_actions.SAVE_AS.get(os.path.splitext(path)[1].lower())
        if not kind:
            continue
        try:
            picture = GdkPixbuf.Pixbuf.new_from_file(path)
            picture = picture.apply_embedded_orientation() or picture
            width, height = picture.get_width(), picture.get_height()
            scale = longest / max(width, height)
            if scale < 1:
                picture = picture.scale_simple(max(1, round(width * scale)), max(1, round(height * scale)),
                                               GdkPixbuf.InterpType.HYPER)
            folder = os.path.dirname(path)
            stem, ending = os.path.splitext(os.path.basename(path))
            target = os.path.join(folder, transfer.free_name(folder, f"{stem} ({longest} px){ending}"))
            picture.savev(target, kind, [], [])
            made.append(target)
        except GLib.Error as error:
            raise StepFailed(f"{os.path.basename(path)} couldn't be resized ({error.message}).")
    if not made:
        raise StepFailed("These pictures can't be saved in their own format here.")
    return made


def _copy_to(p, value, ui):
    from . import transfer
    folder = os.path.expanduser(fill(p["folder"], value) or "~")
    if not os.path.isdir(folder):
        raise StepFailed(f"There's no folder at {folder}.")
    made = []
    for path in _need_files(value):
        target = os.path.join(folder, transfer.free_name(folder, os.path.basename(path.rstrip(os.sep))))
        try:
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.copytree(path, target, symlinks=True)
            else:
                shutil.copy2(path, target, follow_symlinks=False)
        except OSError as error:
            raise StepFailed(f"{os.path.basename(path)} couldn't be copied ({error.strerror or error}).")
        made.append(target)
    return made


def _wallpaper(p, value, ui):
    from .ini import ini_set
    picture = _pictures(value)[0]
    ini_set(os.path.expanduser("~/.config/wf-shell.ini"), "background", "image", os.path.abspath(picture))
    return value


# Apps and the web ------------------------------------------------------------------
def _open_app(p, value, ui):
    app = p["app"]
    if not app:
        raise StepFailed("No app was chosen.")
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
    info = Gio.DesktopAppInfo.new(app)
    if info is None:
        raise StepFailed("That app isn't on this computer any more.")
    try:
        info.launch([], None)
    except GLib.Error as error:
        raise StepFailed(f"{info.get_name()} couldn't be opened ({error.message}).")
    return value


def _open_url(p, value, ui):
    url = fill(p["url"], value).strip()
    if not url:
        raise StepFailed("There was no address to open.")
    if "://" not in url:
        url = "https://" + url
    if not url.lower().startswith(("http://", "https://")):
        raise StepFailed("Only web addresses (http and https) can be opened.")
    _launch("xdg-open", url)
    return value


# The computer --------------------------------------------------------------------
def _appearance(p, value, ui):
    how = p["mode"]
    if how == "toggle":
        from . import style
        how = "light" if style.is_dark() else "dark"
    _launch("freemac-dials", "--appearance", how)
    time.sleep(0.5)
    return value


def _volume(p, value, ui):
    from . import audio
    level = max(0, min(100, int(p["level"])))
    if not audio.available() or not audio.set_level(level):
        raise StepFailed("The volume couldn't be changed.")
    if level:
        audio.set_muted(False)
    return value


def _mute(p, value, ui):
    from . import audio
    if not audio.available():
        raise StepFailed("There's no sound output.")
    on = {"on": True, "off": False}.get(p["mute"])
    if on is None:
        on = not audio.muted()
    audio.set_muted(on)
    return value


def _focus(p, value, ui):
    from . import beacon, notify_rules, style
    beacon.write_prefs(**notify_rules.focus_writes("dnd" if p["focus"] == "on" else None, style.prefs()))
    return value


def _screenshot(p, value, ui):
    _launch("freemac-lens", "--" + p["what"])
    return value


def _lock(p, value, ui):
    _launch("freemac-lock")
    return value


def _wait(p, value, ui):
    seconds = max(0.0, min(3600.0, float(p["seconds"] or 0)))
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if ui.stopped():
            raise Stopped
        time.sleep(min(0.2, end - time.monotonic()) if end > time.monotonic() else 0)
    return value


def _shell(p, value, ui):
    script = p["script"]
    if not script.strip():
        return value
    files = value if isinstance(value, (list, tuple)) else []
    argv = ["bash", "-c", script, "bosun"]
    feed = None
    if p["pass"] == "arguments":
        argv += list(files) if files else ([as_text(value)] if value else [])
    else:
        feed = as_text(value).encode() if not files else "\n".join(files).encode()
    try:
        result = subprocess.run(argv, input=feed, capture_output=True, timeout=LONGEST_SCRIPT,
                                cwd=os.path.expanduser("~"))
    except subprocess.TimeoutExpired:
        raise StepFailed(f"The script was still running after {LONGEST_SCRIPT} seconds, so it was stopped.")
    except OSError as error:
        raise StepFailed(f"The script couldn't be run ({error.strerror or error}).")
    if result.returncode:
        said = result.stderr.decode("utf-8", "replace").strip().splitlines()
        raise StepFailed(f"The script stopped with code {result.returncode}"
                         + (f": {said[-1]}" if said else "."))
    out = result.stdout.decode("utf-8", "replace")
    return out[:-1] if out.endswith("\n") else out


# The catalogue -----------------------------------------------------------------
# Each parameter: (key, kind, label, default[, choices]). Kinds: "text" (a few
# lines), "line", "number", "choice", "app", "folder", "switch".
TEXT, FILES, APPS, COMPUTER = "Text", "Files", "Apps and Web", "The Computer"
CATEGORIES = (TEXT, FILES, APPS, COMPUTER)
CATEGORY_ICONS = {TEXT: "format-justify-left-symbolic", FILES: "folder-symbolic",
                  APPS: "applications-internet-symbolic", COMPUTER: "computer-symbolic"}

ACTIONS = {
    "text": (TEXT, "Text", "Some words of your own, to pass on to the next step.",
             [("text", "text", "Text", "")], _text),
    "ask": (TEXT, "Ask for Text", "Asks you to type something each time the shortcut runs.",
            [("prompt", "line", "Question", "What should it say?"), ("default", "line", "Already typed", "")], _ask),
    "case": (TEXT, "Change Case", "Makes the words capitals, small letters, or a capital at the start of each.",
             [("case", "choice", "Make it", "upper", (("upper", "UPPER CASE"), ("lower", "lower case"),
                                                     ("title", "Title Case"), ("sentence", "Sentence case")))],
             _case),
    "replace": (TEXT, "Replace Text", "Swaps one word or phrase for another everywhere it appears.",
                [("find", "line", "Find", ""), ("with", "line", "Replace with", ""),
                 ("any_case", "switch", "Ignore capitals", False)], _replace),
    "count": (TEXT, "Count", "Counts the characters, words or lines, or the files passed on.",
              [("what", "choice", "Count", "words", (("characters", "Characters"), ("words", "Words"),
                                                    ("lines", "Lines"), ("items", "Items")))], _count),
    "get_clipboard": (TEXT, "Get Clipboard", "What was last copied, as text.", [], _get_clipboard),
    "copy": (TEXT, "Copy to Clipboard", "Copies what came before, words or files, so you can paste it.",
             [], _copy),
    "speak": (TEXT, "Speak Text", "Reads the words aloud in the system voice.",
              [("text", "text", "Text", INPUT)], _speak),
    "show": (TEXT, "Show Result", "Shows the words in a small window until you click OK.",
             [("text", "text", "Text", INPUT)], _show),
    "notify": (TEXT, "Show Notification", "Shows a notification in the top-right corner.",
               [("title", "line", "Title", "Done"), ("body", "text", "Body", INPUT)], _notify),
    "folder_files": (FILES, "Get Files in Folder", "The files in a folder, of one kind or any.",
                     [("folder", "folder", "Folder", "~/Desktop"),
                      ("kind", "choice", "Kind", "any", tuple((k, v[0]) for k, v in KINDS.items())),
                      ("inside", "switch", "Include folders inside", False)], _folder_files),
    "open_files": (FILES, "Open Files", "Opens each file in the app it opens with.", [], _open_files),
    "reveal": (FILES, "Show in Drawer", "Opens Drawer with the file chosen.", [], _reveal),
    "compress": (FILES, "Make Archive", "Puts the files into one .zip beside them.", [], _compress),
    "make_pdf": (FILES, "Make PDF", "Puts the pictures into one PDF, a page each.", [], _make_pdf),
    "rotate": (FILES, "Rotate Pictures", "Turns each picture a quarter turn.",
               [("way", "choice", "Turn", "right", (("left", "Left"), ("right", "Right")))], _rotate),
    "resize": (FILES, "Resize Pictures", "Makes smaller copies of the pictures, beside them.",
               [("size", "number", "Longest side (pixels)", 1024)], _resize),
    "copy_to": (FILES, "Copy to Folder", "Copies the files into a folder.",
                [("folder", "folder", "Folder", "~/Documents")], _copy_to),
    "wallpaper": (FILES, "Set Desktop Picture", "Makes the first picture the desktop picture.", [], _wallpaper),
    "open_app": (APPS, "Open App", "Opens an app.", [("app", "app", "App", "")], _open_app),
    "open_url": (APPS, "Open Web Page", "Opens a web address in the web browser.",
                 [("url", "line", "Address", INPUT)], _open_url),
    "appearance": (COMPUTER, "Set Appearance", "Turns dark mode on or off.",
                   [("mode", "choice", "Appearance", "toggle", (("dark", "Dark"), ("light", "Light"),
                                                               ("toggle", "Switch between them")))], _appearance),
    "volume": (COMPUTER, "Set Volume", "Sets how loud the sound is.",
               [("level", "number", "Volume (percent)", 50)], _volume),
    "mute": (COMPUTER, "Mute Sound", "Turns the sound off or on.",
             [("mute", "choice", "Sound", "toggle", (("on", "Mute"), ("off", "Unmute"),
                                                    ("toggle", "Switch between them")))], _mute),
    "focus": (COMPUTER, "Set Do Not Disturb", "Holds back notifications, or lets them through again.",
              [("focus", "choice", "Do Not Disturb", "on", (("on", "On"), ("off", "Off")))], _focus),
    "screenshot": (COMPUTER, "Take Screenshot", "Takes a picture of the screen, an area or a window, onto the Desktop.",
                   [("what", "choice", "Of", "screen", (("screen", "The whole screen"), ("area", "An area"),
                                                       ("window", "A window")))], _screenshot),
    "lock": (COMPUTER, "Lock Screen", "Locks the screen.", [], _lock),
    "wait": (COMPUTER, "Wait", "Waits a while before the next step.",
             [("seconds", "number", "Seconds", 5)], _wait),
    "shell": (COMPUTER, "Run Shell Script", "Runs commands in bash; what they print is passed on.",
              [("script", "text", "Script", "echo \"$(cat)\""),
               ("pass", "choice", "Pass what came before", "stdin", (("stdin", "To its input"),
                                                                     ("arguments", "As arguments")))], _shell),
}


def defaults(key):
    return {param[0]: param[3] for param in ACTIONS[key][3]}


def params(step):
    """The step's settings, with the catalogue's defaults for any missing."""
    values = defaults(step["do"])
    for name, value in step.items():
        if name in values:
            values[name] = value
    return values


def title(step):
    entry = ACTIONS.get(step.get("do"))
    return entry[1] if entry else "Unknown step"


class QuietUI:
    """For running with nobody to ask: Ask for Text gets its typed default,
    Show Result becomes a notification."""
    def ask(self, prompt, default):
        return default

    def show(self, text):
        _notify({"title": "Bosun", "body": text}, None, self)

    def stopped(self):
        return False


def run(steps, value=None, ui=None, on_step=None):
    """Do the steps in order. Returns what the last one made. on_step(index,
    value) is called after each, with what it made. Raises Stopped, or
    StepFailed with the step's number and name in the message."""
    ui = ui or QuietUI()
    for index, step in enumerate(steps):
        entry = ACTIONS.get(step.get("do"))
        if entry is None:
            raise StepFailed(f"Step {index + 1} is one this version of Bosun doesn't know.")
        if ui.stopped():
            raise Stopped
        try:
            value = entry[4](params(step), value, ui)
        except StepFailed as error:
            raise StepFailed(f"Step {index + 1}, {entry[1]}: {error}")
        except (ValueError, TypeError) as error:
            raise StepFailed(f"Step {index + 1}, {entry[1]}: a setting isn't right ({error}).")
        if on_step:
            on_step(index, value)
    return value
