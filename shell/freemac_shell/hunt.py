# SPDX-License-Identifier: GPL-3.0-or-later
"""Hunt: a word search.

Words from a theme are hidden in a grid of letters, across, down, on a
slant and, on the large grid, backwards too. Drag from a word's first
letter to its last (or click the first and then the last) to circle it;
the list beside the grid crosses it off. Three sizes: Small for young
readers, with words only across and down, then Medium and Large. A timer
runs while you play and Hunt keeps your best time for each size. The game
in progress is kept, so closing Hunt doesn't lose it. Original freemac code.
"""
import json
import math
import os
import random
import string
import sys
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GLib, Gtk, Pango, PangoCairo  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Hunt"
SAVE = os.path.join(GLib.get_user_data_dir(), "freemac", "hunt.json")

ACROSS_DOWN = [(1, 0), (0, 1)]
SLANTS = [(1, 1), (1, -1)]
BACKWARDS = [(-1, 0), (0, -1), (-1, -1), (-1, 1)]
SIZES = {   # name: (grid side, how many words, directions, longest word)
    "Small": (10, 8, ACROSS_DOWN, 8),
    "Medium": (13, 12, ACROSS_DOWN + SLANTS, 11),
    "Large": (16, 16, ACROSS_DOWN + SLANTS + BACKWARDS, 14),
}
SIZE_ORDER = ["Small", "Medium", "Large"]

THEMES = {
    "Animals": "ELEPHANT GIRAFFE ZEBRA TIGER LION MONKEY RABBIT KANGAROO PENGUIN DOLPHIN TURTLE SQUIRREL HEDGEHOG "
               "OWL FOX WOLF BEAR CAMEL PANDA KOALA OTTER BEAVER LEOPARD RHINO HIPPO MOOSE",
    "Ocean": "WHALE SHARK CORAL OCTOPUS SQUID JELLYFISH STARFISH SEAHORSE CRAB LOBSTER SHRIMP ANCHOR WAVE TIDE "
             "REEF SEAWEED CLAM OYSTER PEARL SAILBOAT LIGHTHOUSE ISLAND HARBOR CURRENT SHELL",
    "Space": "PLANET COMET ROCKET GALAXY ORBIT ASTEROID METEOR NEBULA SATELLITE TELESCOPE ASTRONAUT MOON SUN "
             "STAR MARS VENUS JUPITER SATURN MERCURY NEPTUNE URANUS GRAVITY ECLIPSE CRATER SHUTTLE",
    "Food": "PIZZA PASTA BREAD CHEESE SALAD SOUP PANCAKE WAFFLE NOODLES RICE TACO BURRITO SANDWICH CEREAL "
            "YOGURT OMELET MUFFIN COOKIE POPCORN PRETZEL BAGEL BURGER DUMPLING CURRY",
    "Fruit": "APPLE BANANA CHERRY GRAPE LEMON MANGO ORANGE PAPAYA PEACH PEAR PLUM KIWI MELON LIME APRICOT "
             "COCONUT FIG GUAVA RASPBERRY STRAWBERRY BLUEBERRY PINEAPPLE NECTARINE CRANBERRY",
    "Sports": "SOCCER TENNIS HOCKEY BASEBALL BASKETBALL FOOTBALL GOLF RUGBY CRICKET SKIING SURFING ROWING CYCLING "
              "BOXING KARATE ARCHERY BOWLING SWIMMING RUNNING VOLLEYBALL BADMINTON SKATING",
    "Weather": "SUNNY CLOUDY RAIN SNOW STORM THUNDER LIGHTNING RAINBOW WIND BREEZE FOG HAIL SLEET DRIZZLE "
               "TORNADO HURRICANE FROST DEW MIST FORECAST BLIZZARD HUMID CLIMATE SUNSHINE",
    "Music": "PIANO GUITAR VIOLIN DRUMS FLUTE TRUMPET CELLO HARP BANJO UKULELE CLARINET TUBA SAXOPHONE "
             "MELODY RHYTHM CHORUS TEMPO CONCERT BAND ORCHESTRA SONG NOTE HARMONY LYRICS",
    "Colours": "RED ORANGE YELLOW GREEN BLUE PURPLE PINK BROWN BLACK WHITE GREY SILVER GOLD VIOLET INDIGO "
               "TURQUOISE MAROON NAVY TEAL LILAC CRIMSON AMBER IVORY BEIGE SCARLET",
    "Garden": "FLOWER TULIP DAISY ROSE SUNFLOWER LAVENDER SEEDS SOIL SHOVEL RAKE HOSE WORM BEE BUTTERFLY "
              "LADYBUG SNAIL FENCE HEDGE POND BENCH VEGETABLE CARROT POTATO TOMATO PUMPKIN",
    "School": "PENCIL ERASER RULER BACKPACK NOTEBOOK TEACHER LIBRARY RECESS LUNCH MATH SCIENCE READING "
              "SPELLING HISTORY ART MUSIC CRAYON SCISSORS GLUE DESK CHALK HOMEWORK LESSON CLASSROOM",
    "Travel": "SUITCASE PASSPORT TICKET AIRPORT TRAIN BUS FERRY HOTEL MAP COMPASS CAMERA BEACH MOUNTAIN "
              "CASTLE MUSEUM POSTCARD JOURNEY HOLIDAY TENT CAMPING CRUISE PICNIC SOUVENIR",
}
THEME_ORDER = list(THEMES)

FOUND = [(0.95, 0.42, 0.36), (0.98, 0.69, 0.23), (0.37, 0.75, 0.44), (0.26, 0.62, 0.92), (0.62, 0.47, 0.92),
         (0.93, 0.43, 0.68), (0.18, 0.74, 0.74), (0.75, 0.6, 0.35)]


# Making a puzzle -------------------------------------------------------------------

def make(theme, size, rng=None):
    """A new puzzle: {"theme", "size", "grid": [str], "words": [[word, x, y, dx, dy]]}."""
    rng = rng or random.Random()
    side, count, directions, longest = SIZES[size]
    pool = [w for w in THEMES[theme].split() if 3 <= len(w) <= min(longest, side)]
    for _attempt in range(60):
        chosen = rng.sample(pool, min(count, len(pool)))
        chosen.sort(key=len, reverse=True)
        grid = [[""] * side for _ in range(side)]
        placed = []
        for word in chosen:
            spot = _place(grid, word, directions, rng)
            if spot is None:
                break
            placed.append([word, *spot])
        if len(placed) == len(chosen):
            break
    else:
        raise RuntimeError("couldn't fit the words")
    letters = "".join(w for w in chosen) or string.ascii_uppercase
    for y in range(side):
        for x in range(side):
            if not grid[y][x]:
                # Mostly letters from the theme's words, so spare letters don't give words away.
                grid[y][x] = rng.choice(letters) if rng.random() < 0.7 else rng.choice(string.ascii_uppercase)
    placed.sort(key=lambda p: p[0])
    return {"theme": theme, "size": size, "grid": ["".join(row) for row in grid], "words": placed}


def _place(grid, word, directions, rng):
    side = len(grid)
    spots = []
    for dx, dy in directions:
        for y in range(side):
            for x in range(side):
                ex, ey = x + dx * (len(word) - 1), y + dy * (len(word) - 1)
                if not (0 <= ex < side and 0 <= ey < side):
                    continue
                cross = 0
                for i, letter in enumerate(word):
                    have = grid[y + dy * i][x + dx * i]
                    if have and have != letter:
                        break
                    cross += bool(have)
                else:
                    if cross < len(word):     # never wholly inside another word
                        spots.append((cross, x, y, dx, dy))
    if not spots:
        return None
    rng.shuffle(spots)
    # A few words share a letter with another, as in a printed puzzle.
    spots.sort(key=lambda s: -s[0] if rng.random() < 0.35 else 0)
    _cross, x, y, dx, dy = spots[0]
    for i, letter in enumerate(word):
        grid[y + dy * i][x + dx * i] = letter
    return x, y, dx, dy


def cells(x, y, dx, dy, length):
    return [(x + dx * i, y + dy * i) for i in range(length)]


def line_between(a, b):
    """The cells from a to b when they're on one row, column or slant, else None."""
    (ax, ay), (bx, by) = a, b
    dx, dy = bx - ax, by - ay
    if dx and dy and abs(dx) != abs(dy):
        return None
    steps = max(abs(dx), abs(dy))
    sx = (dx > 0) - (dx < 0)
    sy = (dy > 0) - (dy < 0)
    return [(ax + sx * i, ay + sy * i) for i in range(steps + 1)]


def snapped(a, b):
    """The end of a straight line from a that comes nearest to b."""
    (ax, ay), (bx, by) = a, b
    dx, dy = bx - ax, by - ay
    if not dx and not dy:
        return b
    angle = round(math.atan2(dy, dx) / (math.pi / 4)) * (math.pi / 4)
    length = max(abs(dx), abs(dy)) if abs(math.sin(angle * 2)) < 0.5 else round((abs(dx) + abs(dy)) / 2)
    return ax + round(math.cos(angle)) * length, ay + round(math.sin(angle)) * length


def clock(seconds):
    seconds = int(seconds)
    return f"{seconds // 60}:{seconds % 60:02d}"


# The grid ----------------------------------------------------------------------------

class Grid(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__()
        self.window = window
        self.set_can_focus(True)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK)
        self.connect("draw", self.draw)
        self.connect("button-press-event", self.press)
        self.connect("motion-notify-event", self.motion)
        self.connect("button-release-event", self.release)
        self.start = None        # the cell a selection starts at
        self.end = None
        self.dragged = False
        self.flash = None        # (cell, until) for a hint
        self.pressed = (0, 0)
        self.set_size_request(420, 420)

    @property
    def game(self):
        return self.window.game

    def geometry(self):
        side = len(self.game["grid"])
        width, height = self.get_allocated_width(), self.get_allocated_height()
        cell = max(16, min((width - 24) / side, (height - 24) / side))
        ox = (width - cell * side) / 2
        oy = (height - cell * side) / 2
        return cell, ox, oy

    def cell_at(self, x, y, clamp=False):
        cell, ox, oy = self.geometry()
        side = len(self.game["grid"])
        cx, cy = int((x - ox) // cell), int((y - oy) // cell)
        if clamp:
            return max(0, min(side - 1, cx)), max(0, min(side - 1, cy))
        if 0 <= cx < side and 0 <= cy < side:
            return cx, cy
        return None

    def draw(self, _area, cr):
        game = self.game
        side = len(game["grid"])
        cell, ox, oy = self.geometry()
        dark = style.is_dark()
        # The paper.
        cr.set_source_rgb(*((0.16, 0.16, 0.18) if dark else (1, 1, 1)))
        _rounded(cr, ox - 8, oy - 8, cell * side + 16, cell * side + 16, 12)
        cr.fill_preserve()
        cr.set_source_rgba(0, 0, 0, 0.12)
        cr.set_line_width(1)
        cr.stroke()
        # Found words, as soft capsules under the letters.
        for n, entry in enumerate(game["words"]):
            if entry[0] in game["found"]:
                self._capsule(cr, entry, cell, ox, oy, (*FOUND[n % len(FOUND)], 0.45), True)
        # What's being chosen now.
        if self.start is not None:
            end = self.end or self.start
            line = line_between(self.start, end)
            if line:
                dx = (line[-1][0] > line[0][0]) - (line[-1][0] < line[0][0])
                dy = (line[-1][1] > line[0][1]) - (line[-1][1] < line[0][1])
                self._capsule(cr, [None, *self.start, dx, dy, len(line)], cell, ox, oy, (0.26, 0.55, 0.95, 0.30),
                              False)
        if self.flash and self.flash[1] > time.monotonic():
            fx, fy = self.flash[0]
            cr.set_source_rgba(0.98, 0.75, 0.2, 0.75)
            cr.arc(ox + (fx + 0.5) * cell, oy + (fy + 0.5) * cell, cell * 0.46, 0, 2 * math.pi)
            cr.fill()
        # The letters.
        layout = PangoCairo.create_layout(cr)
        font = Pango.FontDescription.from_string("Inter Semi-Bold")
        font.set_absolute_size(max(8, cell * 0.46) * Pango.SCALE)
        layout.set_font_description(font)
        cr.set_source_rgb(*((0.92, 0.92, 0.94) if dark else (0.13, 0.13, 0.16)))
        for y, row in enumerate(game["grid"]):
            for x, letter in enumerate(row):
                layout.set_text(letter, -1)
                width, height = layout.get_pixel_size()
                cr.move_to(ox + (x + 0.5) * cell - width / 2, oy + (y + 0.5) * cell - height / 2)
                PangoCairo.show_layout(cr, layout)
        return False

    def _capsule(self, cr, entry, cell, ox, oy, colour, filled):
        word, x, y, dx, dy = entry[:5]
        length = len(word) if word else entry[5]
        ax, ay = ox + (x + 0.5) * cell, oy + (y + 0.5) * cell
        bx, by = ax + dx * (length - 1) * cell, ay + dy * (length - 1) * cell
        cr.save()
        cr.set_line_cap(1)        # round
        cr.set_line_width(cell * 0.78)
        cr.set_source_rgba(*colour)
        cr.move_to(ax, ay)
        cr.line_to(bx + 0.01, by)
        cr.stroke()
        cr.restore()

    def press(self, _area, event):
        if event.button != 1 or self.window.finished:
            return False
        self.grab_focus()
        spot = self.cell_at(event.x, event.y)
        if spot is None:
            return False
        if self.start is not None and not self.dragged and spot != self.start:
            # Second click of click-then-click.
            self.end = snapped(self.start, spot)
            self._finish()
            return True
        self.start, self.end = spot, spot
        self.dragged = False
        self.pressed = (event.x, event.y)
        self.queue_draw()
        return True

    def motion(self, _area, event):
        if self.start is None:
            return False
        held = bool(event.state & Gdk.ModifierType.BUTTON1_MASK)
        if held and abs(event.x - self.pressed[0]) + abs(event.y - self.pressed[1]) > 6:
            self.dragged = True
        spot = self.cell_at(event.x, event.y, clamp=True)
        end = snapped(self.start, spot)
        side = len(self.game["grid"])
        line = line_between(self.start, end)
        if line and all(0 <= cx < side and 0 <= cy < side for cx, cy in line):
            self.end = end
        self.queue_draw()
        return True

    def release(self, _area, event):
        if event.button != 1 or self.start is None:
            return False
        if self.dragged:
            self._finish()
        # A plain click leaves the first letter chosen, waiting for the second.
        return True

    def _finish(self):
        line = line_between(self.start, self.end) if self.end else None
        self.start = self.end = None
        self.dragged = False
        if line and len(line) > 1:
            self.window.chose(line)
        self.queue_draw()

    def cancel(self):
        self.start = self.end = None
        self.queue_draw()


def _rounded(cr, x, y, w, h, r):
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


# The window -----------------------------------------------------------------------------

CSS = b"""
.hunt-list { padding: 4px 18px 18px 6px; }
.hunt-word { font-size: 15px; padding: 2px 0; }
.hunt-word.found { color: alpha(currentColor, 0.4); }
.hunt-heading { font-weight: 700; font-size: 13px; color: alpha(currentColor, 0.55); padding: 16px 0 6px 0; }
.hunt-timer { font-feature-settings: "tnum"; font-weight: 600; }
.hunt-tip { color: alpha(currentColor, 0.55); font-size: 12px; }
"""


class HuntWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Hunt")
        self.set_default_size(900, 680)
        saved = self.load()
        self.best = saved.get("best", {}) if isinstance(saved.get("best"), dict) else {}
        game = saved.get("game")
        self.game = game if self._valid(game) else None
        self.finished = False
        self.started = time.monotonic()

        header = Gtk.HeaderBar(show_close_button=True, title="Hunt")
        new = Gtk.Button(label="New Game")
        new.set_action_name("win.new")
        header.pack_start(new)
        self.theme_name = "Animals"
        self.theme = Gtk.MenuButton()
        self.theme.set_tooltip_text("Choose a theme")
        inside = Gtk.Box(spacing=4)
        self.theme_label = Gtk.Label()
        inside.pack_start(self.theme_label, False, False, 0)
        inside.pack_start(Gtk.Image.new_from_icon_name("pan-down-symbolic", Gtk.IconSize.BUTTON), False, False, 0)
        self.theme.add(inside)
        themes = Gtk.Popover()
        column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=6)
        for name in THEME_ORDER:
            entry = Gtk.ModelButton(text=name)
            entry.connect("clicked", lambda _b, n=name: self.choose_theme(n))
            column.pack_start(entry, False, False, 0)
        column.show_all()
        themes.add(column)
        self.theme.set_popover(themes)
        header.pack_start(self.theme)
        sizes = Gtk.Box()
        sizes.get_style_context().add_class("linked")
        self.size_buttons = {}
        first = None
        for name in SIZE_ORDER:
            button = Gtk.RadioButton.new_with_label_from_widget(first, name)
            button.set_mode(False)            # drawn as a button, the three side by side
            first = first or button
            button.connect("toggled", self._size_toggled, name)
            sizes.pack_start(button, False, False, 0)
            self.size_buttons[name] = button
        header.pack_start(sizes)
        self.timer = Gtk.Label(label="0:00")
        self.timer.get_style_context().add_class("hunt-timer")
        self.timer.set_tooltip_text("Time")
        header.pack_end(self.timer)
        hint = Gtk.Button(label="Hint")
        hint.set_action_name("win.hint")
        header.pack_end(hint)
        self.set_titlebar(header)

        overlay = Gtk.Overlay()
        box = Gtk.Box()
        overlay.add(box)
        self.grid = Grid(self)
        box.pack_start(self.grid, True, True, 0)
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.get_style_context().add_class("hunt-list")
        side.set_size_request(200, -1)
        self.heading = Gtk.Label(xalign=0)
        self.heading.get_style_context().add_class("hunt-heading")
        side.pack_start(self.heading, False, False, 0)
        self.words_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.pack_start(self.words_box, False, False, 0)
        tip = Gtk.Label(label="Drag from the first letter of a word to its last, or click one and then the other.",
                        xalign=0, wrap=True, max_width_chars=22, margin_top=14)
        tip.get_style_context().add_class("hunt-tip")
        side.pack_end(tip, False, False, 0)
        box.pack_start(side, False, False, 0)

        self.banner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.banner.get_style_context().add_class("app-notification")
        self.banner.set_halign(Gtk.Align.CENTER)
        self.banner.set_valign(Gtk.Align.END)
        self.banner.set_margin_bottom(40)
        self.banner.set_border_width(18)
        self.banner_label = Gtk.Label(justify=Gtk.Justification.CENTER)
        self.banner.pack_start(self.banner_label, False, False, 0)
        again = Gtk.Button(label="New Game")
        again.set_action_name("win.new")
        again.get_style_context().add_class("suggested-action")
        again.set_halign(Gtk.Align.CENTER)
        self.banner.pack_start(again, False, False, 0)
        self.banner.set_no_show_all(True)
        overlay.add_overlay(self.banner)
        self.add(overlay)

        menus.add_actions(self, {"new": self.new_game, "hint": self.hint, "close": self.close,
                                 "small": lambda: self.size_buttons["Small"].set_active(True),
                                 "medium": lambda: self.size_buttons["Medium"].set_active(True),
                                 "large": lambda: self.size_buttons["Large"].set_active(True)})
        self.connect("key-press-event", self._key)
        self.connect("delete-event", lambda *_a: self.save() or False)
        self.connect("notify::is-active", lambda *_a: self._activity())

        if self.game is None:
            self.game = self._fresh("Animals", "Small")
        self.elapsed = float(self.game.get("elapsed", 0))
        self._quiet = True
        self.theme_name = self.game["theme"]
        self.theme_label.set_text(self.theme_name)
        self.size_buttons[self.game["size"]].set_active(True)
        self._quiet = False
        self.show_all()
        self.refresh()
        GLib.timeout_add(500, self._tick)

    # Keeping the game -------------------------------------------------------------

    @staticmethod
    def load():
        try:
            with open(SAVE, encoding="utf-8") as handle:
                data = json.load(handle)
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    def save(self):
        self.game["elapsed"] = self.elapsed_now()
        try:
            os.makedirs(os.path.dirname(SAVE), exist_ok=True)
            with open(SAVE + ".tmp", "w", encoding="utf-8") as handle:
                json.dump({"game": self.game, "best": self.best}, handle)
            os.replace(SAVE + ".tmp", SAVE)
        except OSError as err:
            print(f"hunt: couldn't save: {err}", file=sys.stderr)

    @staticmethod
    def _valid(game):
        try:
            side = len(game["grid"])
            ok = game["theme"] in THEMES and game["size"] in SIZES and side == SIZES[game["size"]][0]
            ok = ok and all(len(row) == side for row in game["grid"])
            for word, x, y, dx, dy in game["words"]:
                ok = ok and "".join(game["grid"][cy][cx] for cx, cy in cells(x, y, dx, dy, len(word))) == word
            return ok and isinstance(game.get("found"), list)
        except (KeyError, TypeError, ValueError, IndexError):
            return False

    @staticmethod
    def _fresh(theme, size):
        game = make(theme, size)
        game["found"] = []
        game["elapsed"] = 0
        return game

    # Playing ------------------------------------------------------------------------

    def elapsed_now(self):
        if self.finished or not self.is_active():
            return self.elapsed
        return self.elapsed + (time.monotonic() - self.started)

    def _activity(self):
        # The clock stops while Hunt isn't the window in front.
        if self.finished:
            return
        if self.is_active():
            self.started = time.monotonic()
        else:
            self.elapsed += time.monotonic() - self.started

    def _tick(self):
        self.timer.set_text(clock(self.elapsed_now()))
        if self.grid.flash and self.grid.flash[1] <= time.monotonic():
            self.grid.flash = None
            self.grid.queue_draw()
        return True

    def new_game(self):
        theme = self.theme_name
        size = next(n for n, b in self.size_buttons.items() if b.get_active())
        self.game = self._fresh(theme, size)
        self.elapsed = 0
        self.started = time.monotonic()
        self.grid.cancel()
        self.grid.flash = None
        self.refresh()
        self.save()

    def choose_theme(self, name):
        self.theme_name = name
        self.theme_label.set_text(name)
        self.new_game()

    def _size_toggled(self, button, name):
        if button.get_active() and not getattr(self, "_quiet", True) and name != self.game["size"]:
            self.new_game()

    def refresh(self):
        game = self.game
        found = set(game["found"])
        self.finished = len(found) >= len(game["words"])
        for child in self.words_box.get_children():
            self.words_box.remove(child)
        for word, *_rest in game["words"]:
            label = Gtk.Label(xalign=0)
            label.get_style_context().add_class("hunt-word")
            if word in found:
                label.set_markup(f"<s>{word.title()}</s>")
                label.get_style_context().add_class("found")
            else:
                label.set_text(word.title())
            self.words_box.pack_start(label, False, False, 0)
        self.words_box.show_all()
        self.heading.set_text(f"{game['theme']}: {len(found)} of {len(game['words'])}")
        if self.finished:
            line = game.get("result") or f"You found all {len(game['words'])} words."
            self.banner_label.set_markup(f"<span size='x-large' weight='bold'>Well done!</span>\n{line}")
            self.banner.show()
            for child in self.banner.get_children():
                child.show()
        else:
            self.banner.hide()
        self.grid.queue_draw()

    def chose(self, line):
        game = self.game
        for word, x, y, dx, dy in game["words"]:
            if word in game["found"]:
                continue
            spots = cells(x, y, dx, dy, len(word))
            if line == spots or line == spots[::-1]:
                game["found"].append(word)
                if len(game["found"]) >= len(game["words"]):
                    self.elapsed = self.elapsed_now()
                    self.finished = True
                    took, best = round(self.elapsed), self.best.get(game["size"])
                    result = f"You found all {len(game['words'])} words in {clock(took)}."
                    if best is None or took < best:
                        if best is not None:
                            result += "\nThat's a new best time!"
                        self.best[game["size"]] = took
                    else:
                        result += f"\nYour best on {game['size'].lower()} is {clock(best)}."
                    game["result"] = result
                self.refresh()
                self.save()
                return True
        return False

    def hint(self):
        if self.finished:
            return
        left = [w for w in self.game["words"] if w[0] not in self.game["found"]]
        if left:
            word, x, y, _dx, _dy = random.choice(left)
            self.grid.flash = ((x, y), time.monotonic() + 1.6)
            self.grid.queue_draw()

    def _key(self, _window, event):
        if event.keyval == Gdk.KEY_Escape:
            self.grid.cancel()
            return True
        return False

    def about(self):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, buttons=Gtk.ButtonsType.OK, text="About Hunt")
        dialog.format_secondary_text("Hunt is a word search. It is part of freemac.")
        dialog.run()
        dialog.destroy()


def menubar():
    return menus.menubar([
        ("_Game", [[("New Game", "win.new", "<Ctrl>n"), ("Hint", "win.hint", "<Ctrl>h")],
                   [("Small", "win.small", "<Ctrl>1"), ("Medium", "win.medium", "<Ctrl>2"),
                    ("Large", "win.large", "<Ctrl>3")],
                   [("Close", "win.close", "<Ctrl>w")]]),
    ])


class Hunt(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        menus.add_actions(self, {"quit": self.quit, "about": lambda: self.window and self.window.about()})
        for action, keys in (("app.quit", ["<Control>q"]), ("win.new", ["<Control>n"]), ("win.hint", ["<Control>h"]),
                             ("win.small", ["<Control>1"]), ("win.medium", ["<Control>2"]),
                             ("win.large", ["<Control>3"]), ("win.close", ["<Control>w"])):
            self.set_accels_for_action(action, keys)
        self.set_menubar(menubar())

    def do_activate(self):
        if self.window is None:
            self.window = HuntWindow(self)
        self.window.present()

    def do_shutdown(self):
        if self.window is not None:
            self.window.save()
        Gtk.Application.do_shutdown(self)


def main():
    GLib.set_prgname("freemac-hunt")
    return Hunt().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
