# SPDX-License-Identifier: GPL-3.0-or-later
"""Ivory: a piano to play.

Click the keys, or play them on the computer's keyboard: the bottom letter
row (Z, S, X, D, C…) is the lower octave and the top row (Q, 2, W, 3, E…)
the upper one. Pick Piano, Organ, Music Box, Flute or Synth; ← and → move
up or down an octave. Click Record, play a tune, click Stop, then Play to
hear it back. The last tune is kept.

Every sound is made by freemac itself: each instrument is a short wave
table and an envelope, mixed in Python and played through GStreamer.
Original freemac code; the tune is kept in ~/.local/share/freemac/ivory.json.
"""
import array
import json
import math
import os
import sys
import threading
import time

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gst", "1.0")
gi.require_version("Gtk", "3.0")
gi.require_version("PangoCairo", "1.0")
import cairo  # noqa: E402
from gi.repository import Gdk, GLib, Gst, Gtk, Pango, PangoCairo  # noqa: E402

from . import menus, style  # noqa: E402

APP_ID = "org.freemac.Ivory"
RATE = 22050
CHUNK = 256
TABLE = 2048
SILENCE = bytes(2 * CHUNK)
NAMES = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
WHITE = [0, 2, 4, 5, 7, 9, 11]
# Two octaves and a top C. Lower letters, then upper letters.
LETTERS = ["z", "s", "x", "d", "c", "v", "g", "b", "h", "n", "j", "m",
           "q", "2", "w", "3", "e", "r", "5", "t", "6", "y", "7", "u", "i"]
RAINBOW = [(1, 0.36, 0.33), (1, 0.6, 0.25), (1, 0.82, 0.25), (0.45, 0.8, 0.35), (0.25, 0.75, 0.75),
           (0.3, 0.55, 1), (0.65, 0.42, 0.95)]


def _table(harmonics):
    """One cycle of a wave made of (harmonic, strength) pairs, scaled to ±1."""
    values = [sum(a * math.sin(2 * math.pi * h * i / TABLE) for h, a in harmonics) for i in range(TABLE)]
    peak = max(abs(v) for v in values) or 1
    return array.array("f", (v / peak for v in values))


# name: (bright table, mellow table, attack s, decay per second, sustain level, release s, how fast bright fades)
INSTRUMENTS = {
    "piano": ("Piano", [(1, 1), (2, 0.55), (3, 0.3), (4, 0.22), (5, 0.12), (6, 0.08), (8, 0.04)],
              [(1, 1), (2, 0.25), (3, 0.06)], 0.004, 1.5, 0.0, 0.25, 3.5),
    "organ": ("Organ", [(1, 1), (2, 0.7), (3, 0.45), (4, 0.4), (6, 0.25), (8, 0.3)],
              [(1, 1), (2, 0.7), (3, 0.45), (4, 0.4), (6, 0.25), (8, 0.3)], 0.02, 0.0, 1.0, 0.08, 0.0),
    "musicbox": ("Music Box", [(1, 1), (3, 0.5), (5, 0.35), (7, 0.2)], [(1, 1), (4, 0.15)],
                 0.002, 3.0, 0.0, 0.5, 6.0),
    "flute": ("Flute", [(1, 1), (2, 0.18), (3, 0.08)], [(1, 1), (2, 0.1)], 0.08, 0.0, 0.85, 0.15, 1.0),
    "synth": ("Synth", [(h, 1 / h) for h in range(1, 14)], [(1, 1), (2, 0.5), (3, 0.33), (4, 0.25)],
              0.01, 0.4, 0.55, 0.2, 2.0),
}


def store_path():
    folder = os.path.join(GLib.get_user_data_dir(), "freemac")
    os.makedirs(folder, exist_ok=True)
    return os.path.join(folder, "ivory.json")


def load_store():
    try:
        with open(store_path(), encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_store(data):
    try:
        tmp = store_path() + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp, store_path())
    except OSError:
        pass


class Voice:
    def __init__(self, note, instrument):
        _label, _b, _m, attack, decay, sustain, release, fade = instrument
        self.note = note
        self.step = 440 * 2 ** ((note - 69) / 12) * TABLE / RATE
        self.phase = 0.0
        self.t = 0.0
        self.attack, self.decay, self.sustain, self.release, self.fade = attack, decay, sustain, release, fade
        self.released_at = None
        self.level = 0.0
        self.done = False

    def envelope(self, t):
        if t < self.attack:
            level = t / self.attack
        else:
            level = self.sustain + (1 - self.sustain) * math.exp(-self.decay * (t - self.attack))
        if self.released_at is not None:
            level *= max(0.0, 1 - (t - self.released_at) / self.release)
        return level


class Synth:
    """Mixes the notes that are sounding and feeds them to GStreamer."""

    def __init__(self):
        Gst.init(None)
        self.lock = threading.Lock()
        self.voices = []
        self.tables = {}
        self.instrument = "piano"
        self.volume = 0.28
        caps = f"audio/x-raw,format=S16LE,rate={RATE},channels=1,layout=interleaved"
        self.pipeline = None
        for sink in ("pulsesink buffer-time=50000 latency-time=10000", "autoaudiosink"):
            try:
                self.pipeline = Gst.parse_launch(
                    f"appsrc name=src is-live=true format=time block=false caps={caps} "
                    f"! audioconvert ! audioresample ! {sink}")
                break
            except GLib.Error:
                continue
        self.samples = 0
        self.src = self.pipeline.get_by_name("src") if self.pipeline else None
        self.running = True
        if self.pipeline:
            self.pipeline.set_state(Gst.State.PLAYING)
            threading.Thread(target=self._feed, daemon=True).start()

    def tables_for(self, key):
        if key not in self.tables:
            spec = INSTRUMENTS[key]
            self.tables[key] = (_table(spec[1]), _table(spec[2]))
        return self.tables[key]

    def set_instrument(self, key):
        self.tables_for(key)
        self.instrument = key

    def press(self, note):
        bright, mellow = self.tables_for(self.instrument)
        voice = Voice(note, INSTRUMENTS[self.instrument])
        voice.tables = (bright, mellow)
        with self.lock:
            for v in self.voices:
                if v.note == note and v.released_at is None:
                    v.released_at = v.t
            self.voices.append(voice)
            del self.voices[:-12]

    def release(self, note):
        with self.lock:
            for v in self.voices:
                if v.note == note and v.released_at is None:
                    v.released_at = v.t

    def silence(self):
        with self.lock:
            self.voices = []

    def _mix(self):
        out = [0.0] * CHUNK
        dt = CHUNK / RATE
        mask = TABLE - 1
        with self.lock:
            voices = list(self.voices)
        if not voices:
            return SILENCE
        for v in voices:
            start, end = v.envelope(v.t), v.envelope(v.t + dt)
            if v.released_at is None and v.sustain == 0 and start < 0.002 and v.t > v.attack:
                v.done = True
            if v.released_at is not None and end <= 0 and start <= 0:
                v.done = True
                continue
            bright, mellow = v.tables
            mix_a = math.exp(-v.fade * v.t) if v.fade else 1.0
            mix_b = math.exp(-v.fade * (v.t + dt)) if v.fade else 1.0
            phase, step = v.phase, v.step
            for i in range(CHUNK):
                f = i / CHUNK
                level = start + (end - start) * f
                b = mix_a + (mix_b - mix_a) * f
                j = int(phase) & mask
                out[i] += (bright[j] * b + mellow[j] * (1 - b)) * level
                phase += step
            v.phase = phase % TABLE
            v.t += dt
        with self.lock:
            self.voices = [v for v in self.voices if not v.done]
        volume = self.volume
        return array.array("h", (int(max(-1.0, min(1.0, s * volume)) * 32767) for s in out)).tobytes()

    def _feed(self):
        # Keep about 60 ms of sound queued ahead of the clock, never blocking
        # (a blocked push would hold up the whole app).
        started = time.monotonic()
        while self.running:
            ahead = self.samples / RATE - (time.monotonic() - started)
            if ahead > 0.06:
                time.sleep(min(0.01, ahead - 0.05))
                continue
            if ahead < -0.25:       # fell far behind (e.g. no sound device): start again from now
                started = time.monotonic() - self.samples / RATE
            data = self._mix()
            buffer = Gst.Buffer.new_wrapped(data)
            buffer.pts = self.samples * Gst.SECOND // RATE
            buffer.duration = CHUNK * Gst.SECOND // RATE
            self.samples += CHUNK
            if self.src.emit("push-buffer", buffer) != Gst.FlowReturn.OK:
                time.sleep(0.05)

    def stop(self):
        self.running = False
        if self.pipeline:
            self.pipeline.set_state(Gst.State.NULL)


class Keyboard(Gtk.DrawingArea):
    def __init__(self, window):
        super().__init__(hexpand=True, vexpand=True)
        self.window = window
        self.lit = {}            # index -> colour time
        self.mouse = None
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK)
        self.connect("draw", self._draw)
        self.connect("button-press-event", self._press)
        self.connect("motion-notify-event", self._motion)
        self.connect("button-release-event", self._release)

    def keys(self):
        """(index, x, y, w, h, black) for every key, black keys last."""
        width, height = self.get_allocated_width(), self.get_allocated_height()
        whites = [i for i in range(25) if i % 12 in WHITE]
        pad = 24
        w = (width - pad * 2) / len(whites)
        h = min(height - pad * 2, w * 5.2)
        top = (height - h) / 2 + 10
        found = []
        position = {}
        for n, i in enumerate(whites):
            x = pad + n * w
            position[i] = x
            found.append((i, x, top, w, h, False))
        for i in range(25):
            if i % 12 not in WHITE:
                x = position[i - 1] + w * 0.68
                found.append((i, x, top, w * 0.64, h * 0.62, True))
        return found

    def key_at(self, x, y):
        for i, kx, ky, kw, kh, black in reversed(self.keys()):
            if kx <= x <= kx + kw and ky <= y <= ky + kh:
                return i
        return None

    def _draw(self, _w, cr):
        height = self.get_allocated_height()
        grad = cairo.LinearGradient(0, 0, 0, height)
        grad.add_color_stop_rgb(0, 0.2, 0.21, 0.24)
        grad.add_color_stop_rgb(1, 0.11, 0.11, 0.13)
        cr.set_source(grad)
        cr.paint()
        win = self.window
        font = Pango.FontDescription("Inter Bold")
        for i, x, y, w, h, black in self.keys():
            down = i in win.down
            r = 6
            cr.new_sub_path()
            cr.arc(x + w - r - 1, y + h - r, r, 0, math.pi / 2)
            cr.arc(x + r + 1, y + h - r, r, math.pi / 2, math.pi)
            cr.line_to(x + 1, y)
            cr.line_to(x + w - 1, y)
            cr.close_path()
            if black:
                g = cairo.LinearGradient(0, y, 0, y + h)
                g.add_color_stop_rgb(0, 0.16, 0.16, 0.18)
                g.add_color_stop_rgb(1, 0.05, 0.05, 0.06 if not down else 0.2)
                cr.set_source(g)
            else:
                if win.rainbow:
                    colour = RAINBOW[WHITE.index(i % 12)]
                    cr.set_source_rgb(*[c * (0.82 if down else 1) for c in colour])
                else:
                    cr.set_source_rgb(*((0.82, 0.86, 0.95) if down else (0.99, 0.99, 0.98)))
            cr.fill_preserve()
            cr.set_source_rgba(0, 0, 0, 0.5)
            cr.set_line_width(1)
            cr.stroke()
            if down:
                cr.set_source_rgba(0.0, 0.48, 1.0, 0.55 if black else 0.35)
                cr.rectangle(x + 3, y + h - 12, w - 6, 6)
                cr.fill()
            labels = []
            if win.show_letters:
                labels.append(LETTERS[i].upper())
            if win.show_names and not black:
                labels.append(NAMES[i % 12])
            for k, text in enumerate(labels):
                layout = PangoCairo.create_layout(cr)
                font.set_absolute_size(max(9, min(15, w * 0.32)) * Pango.SCALE)
                layout.set_font_description(font)
                layout.set_text(text, -1)
                tw, th = layout.get_pixel_size()
                cr.set_source_rgba(1, 1, 1, 0.8) if black else cr.set_source_rgba(0, 0, 0, 0.55)
                cr.move_to(x + (w - tw) / 2, y + h - 22 - th - (len(labels) - 1 - k) * (th + 2))
                PangoCairo.show_layout(cr, layout)

    def _press(self, _w, event):
        if event.button == 1 and event.type == Gdk.EventType.BUTTON_PRESS:
            self.mouse = self.key_at(event.x, event.y)
            if self.mouse is not None:
                self.window.note_on(self.mouse)
        return True

    def _motion(self, _w, event):
        if self.mouse is None or not event.state & Gdk.ModifierType.BUTTON1_MASK:
            return False
        key = self.key_at(event.x, event.y)
        if key != self.mouse:
            self.window.note_off(self.mouse)
            self.mouse = key
            if key is not None:
                self.window.note_on(key)
        return True

    def _release(self, _w, event):
        if event.button == 1 and self.mouse is not None:
            self.window.note_off(self.mouse)
            self.mouse = None
        return True


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Ivory")
        self.set_default_size(1000, 460)
        self.synth = app.synth
        self.store = load_store()
        self.octave = int(self.store.get("octave", 4)) if str(self.store.get("octave", 4)).isdigit() else 4
        self.octave = max(2, min(6, self.octave))
        self.show_letters = bool(self.store.get("letters", True))
        self.show_names = bool(self.store.get("names", False))
        self.rainbow = bool(self.store.get("rainbow", False))
        self.down = set()
        self.held_keys = {}
        self.recording = None
        self.record_start = 0
        self.playing = []
        self.tune = self.store.get("tune") if isinstance(self.store.get("tune"), list) else []

        header = Gtk.HeaderBar(show_close_button=True, title="Ivory")
        self.header = header
        self.set_titlebar(header)
        self.instrument = Gtk.ComboBoxText()
        for key, spec in INSTRUMENTS.items():
            self.instrument.append(key, spec[0])
        chosen = self.store.get("instrument") if self.store.get("instrument") in INSTRUMENTS else "piano"
        self.instrument.set_active_id(chosen)
        self.synth.set_instrument(chosen)
        self.instrument.connect("changed", self._instrument_changed)
        header.pack_start(self.instrument)
        octave = Gtk.Box()
        octave.get_style_context().add_class("linked")
        down = Gtk.Button.new_from_icon_name("go-previous-symbolic", Gtk.IconSize.BUTTON)
        down.set_tooltip_text("Lower (←)")
        down.connect("clicked", lambda _b: self.shift(-1))
        up = Gtk.Button.new_from_icon_name("go-next-symbolic", Gtk.IconSize.BUTTON)
        up.set_tooltip_text("Higher (→)")
        up.connect("clicked", lambda _b: self.shift(1))
        octave.pack_start(down, False, False, 0)
        octave.pack_start(up, False, False, 0)
        header.pack_start(octave)
        self.record_button = Gtk.Button(label="● Record")
        self.record_button.connect("clicked", lambda _b: self.toggle_record())
        header.pack_end(self.record_button)
        self.play_button = Gtk.Button(label="▶ Play")
        self.play_button.connect("clicked", lambda _b: self.toggle_play())
        header.pack_end(self.play_button)

        self.board = Keyboard(self)
        self.add(self.board)
        self.connect("key-press-event", self._key_press)
        self.connect("key-release-event", self._key_release)
        self.connect("focus-out-event", lambda *_a: self.all_off())
        menus.add_actions(self, {"record": self.toggle_record, "play": self.toggle_play, "close": self.close,
                                 "lower": lambda: self.shift(-1), "higher": lambda: self.shift(1)})
        menus.add_toggle(self, "letters", self.show_letters, lambda v: self._option("letters", v))
        menus.add_toggle(self, "names", self.show_names, lambda v: self._option("names", v))
        menus.add_toggle(self, "rainbow", self.rainbow, lambda v: self._option("rainbow", v))
        self.show_all()
        self.update()

    def base(self):
        return 12 * (self.octave + 1)        # MIDI number of the leftmost C

    def note_on(self, index):
        if index in self.down:
            return
        self.down.add(index)
        note = self.base() + index
        self.synth.press(note)
        if self.recording is not None:
            self.recording.append([round(time.monotonic() - self.record_start, 3), note, 1])
        self.board.queue_draw()

    def note_off(self, index):
        if index not in self.down:
            return
        self.down.discard(index)
        note = self.base() + index
        self.synth.release(note)
        if self.recording is not None:
            self.recording.append([round(time.monotonic() - self.record_start, 3), note, 0])
        self.board.queue_draw()

    def all_off(self):
        for index in list(self.down):
            self.note_off(index)
        self.held_keys.clear()
        return False

    def _key_press(self, _w, event):
        if event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK):
            return False
        if event.keyval == Gdk.KEY_Left:
            self.shift(-1)
            return True
        if event.keyval == Gdk.KEY_Right:
            self.shift(1)
            return True
        char = chr(Gdk.keyval_to_unicode(event.keyval) or 0).lower()
        if char and char in LETTERS:
            index = LETTERS.index(char)
            if event.hardware_keycode not in self.held_keys:
                self.held_keys[event.hardware_keycode] = index
                self.note_on(index)
            return True
        return False

    def _key_release(self, _w, event):
        index = self.held_keys.pop(event.hardware_keycode, None)
        if index is not None:
            self.note_off(index)
            return True
        return False

    def shift(self, step):
        self.all_off()
        self.octave = max(2, min(6, self.octave + step))
        self.store["octave"] = self.octave
        save_store(self.store)
        self.update()

    def _instrument_changed(self, combo):
        key = combo.get_active_id()
        self.synth.set_instrument(key)
        self.store["instrument"] = key
        save_store(self.store)

    def _option(self, name, value):
        setattr(self, {"letters": "show_letters", "names": "show_names", "rainbow": "rainbow"}[name], value)
        self.store[name] = value
        save_store(self.store)
        self.board.queue_draw()

    def update(self):
        if self.recording is not None:
            self.header.set_subtitle("Recording… play your tune")
        elif self.playing:
            self.header.set_subtitle("Playing your tune")
        else:
            self.header.set_subtitle(f"C{self.octave} to C{self.octave + 2}")
        self.record_button.set_label("■ Stop" if self.recording is not None else "● Record")
        style_context = self.record_button.get_style_context()
        if self.recording is not None:
            style_context.add_class("destructive-action")
        else:
            style_context.remove_class("destructive-action")
        self.play_button.set_label("■ Stop" if self.playing else "▶ Play")
        self.play_button.set_sensitive(bool(self.tune) and self.recording is None)
        self.board.queue_draw()

    def toggle_record(self):
        if self.recording is None:
            self.stop_playing()
            self.recording = []
            self.record_start = time.monotonic()
        else:
            self.all_off()
            notes = self.recording
            self.recording = None
            if any(on for _t, _n, on in notes):
                first = notes[0][0]
                self.tune = [[round(t - first, 3), n, on] for t, n, on in notes]
                self.store["tune"] = self.tune
                save_store(self.store)
        self.update()

    def toggle_play(self):
        if self.playing:
            self.stop_playing()
        elif self.tune and self.recording is None:
            start = time.monotonic()
            self.playing = [True]
            events = list(self.tune)

            def step():
                if not self.playing:
                    return False
                now = time.monotonic() - start
                while events and events[0][0] <= now:
                    _t, note, on = events.pop(0)
                    index = note - self.base()
                    (self.synth.press if on else self.synth.release)(note)
                    if 0 <= index < 25:
                        (self.down.add if on else self.down.discard)(index)
                self.board.queue_draw()
                if not events:
                    self.playing = []
                    self.down.clear()
                    self.update()
                    return False
                return True
            GLib.timeout_add(5, step)
        self.update()

    def stop_playing(self):
        if self.playing:
            self.playing = []
            self.synth.silence()
            self.down.clear()
            self.update()


def menubar():
    return menus.menubar([
        ("_File", [[("Close", "win.close", "<Ctrl>w")]]),
        ("_Play", [[("Record", "win.record", "<Ctrl>r"), ("Play Back", "win.play", "<Ctrl>p")],
                   [("Lower Octave", "win.lower", None), ("Higher Octave", "win.higher", None)]]),
        ("_View", [[("Show Letters", "win.letters", None), ("Show Note Names", "win.names", None),
                    ("Rainbow Keys", "win.rainbow", None)]]),
    ])


class Ivory(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.window = None
        self.synth = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        style.apply()
        self.synth = Synth()
        menus.add_actions(self, {"quit": lambda: self.window and self.window.close()})
        self.set_accels_for_action("app.quit", ["<Control>q"])
        for action, keys in (("win.close", "<Control>w"), ("win.record", "<Control>r"), ("win.play", "<Control>p")):
            self.set_accels_for_action(action, [keys])
        self.set_menubar(menubar())

    def do_shutdown(self):
        if self.synth:
            self.synth.stop()
        Gtk.Application.do_shutdown(self)

    def do_activate(self):
        if self.window is None:
            self.window = Window(self)
            self.window.connect("destroy", lambda _w: setattr(self, "window", None))
        self.window.present()


def main():
    GLib.set_prgname("freemac-ivory")
    return Ivory().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
