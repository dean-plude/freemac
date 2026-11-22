#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Make freemac's own sounds from scratch: no recordings, no samples.

    make-sounds.py OUTDIR      writes OUTDIR/startup.wav, tick.wav, shutter.wav,
                               the alert sounds (alert-*.wav), pop.wav and trash.wav

startup.wav is freemac's start-up sound: four soft bell notes rising one after
another (D, A, E, then a high B, a little apart), so it reads as a quick
upward sweep rather than one struck chord. Each bell is a few slightly
out-of-tune partials dying away at different speeds, with a short room echo
made by mixing in quieter, later copies.

tick.wav is one soft, short wooden tap, for each second of Pose's countdown.
shutter.wav is Pose's picture sound: two quick clacks of filtered noise, the
first louder, like a shutter opening and closing.

The alert sounds, one of which plays when something can't be done (chosen in
Dials > Sound): Pebble, two small stones clicking; Droplet, a quick rising
blip like a drop into water; Knock, two soft low knocks; Chirp, two quick
bird-like sweeps; Bell, one soft bell note; Hum, a short low tone that swells
and fades. pop.wav is the little sound as the volume changes, and trash.wav a
paper crumple for emptying the Trash. Original freemac work.
"""
import math
import os
import struct
import sys
import wave

RATE = 44100
LENGTH = 2.8           # seconds
PEAK = 0.42            # of full scale: noticeable, never loud

# (frequency in Hz, start in seconds, loudness)
NOTES = [(293.66, 0.00, 1.00), (440.00, 0.075, 0.85), (659.26, 0.15, 0.70), (987.77, 0.24, 0.42)]
# (multiple of the note, loudness, how fast it dies away per second)
PARTIALS = [(1.0, 1.00, 1.6), (2.01, 0.42, 3.4), (3.02, 0.20, 5.0), (4.17, 0.10, 7.5), (5.43, 0.04, 10.0)]
ATTACK = 0.012
ECHOES = [(0.047, 0.30), (0.083, 0.22), (0.131, 0.16), (0.197, 0.10), (0.283, 0.06)]


def bells():
    total = int(RATE * LENGTH)
    out = [0.0] * total
    for freq, start, loud in NOTES:
        first = int(start * RATE)
        for mult, part_loud, decay in PARTIALS:
            step = 2 * math.pi * freq * mult / RATE
            amp = loud * part_loud
            fall = math.exp(-decay / RATE)
            level = amp
            for i in range(first, total):
                t = (i - first) / RATE
                shape = min(1.0, t / ATTACK)
                out[i] += level * shape * math.sin(step * (i - first))
                level *= fall
                if level < 1e-5:
                    break
    return out


def room(dry):
    wet = list(dry)
    for delay, loud in ECHOES:
        shift = int(delay * RATE)
        for i in range(shift, len(dry)):
            wet[i] += dry[i - shift] * loud
    return wet


def finish(samples):
    fade = int(0.35 * RATE)
    for i in range(fade):
        samples[-1 - i] *= i / fade
    top = max(abs(s) for s in samples) or 1.0
    return [s / top * PEAK for s in samples]


def write(path, samples):
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))


def tap(freq, length, loud, noise=0.0, seed=1):
    """A short struck sound: a falling tone with a little filtered noise."""
    import random
    rng = random.Random(seed)
    total = int(RATE * length)
    out = []
    smooth = 0.0
    for i in range(total):
        t = i / RATE
        env = min(1.0, t / 0.002) * math.exp(-t * 38)
        smooth += (rng.uniform(-1, 1) - smooth) * 0.35
        out.append(loud * env * (math.sin(2 * math.pi * freq * t * (1 - 0.25 * t / length)) + noise * smooth))
    return out


def tick():
    samples = tap(1180, 0.09, 1.0, noise=0.4)
    return [s * 0.32 for s in samples]


def shutter():
    first = tap(2300, 0.06, 1.0, noise=2.2, seed=3)
    second = tap(1700, 0.07, 0.6, noise=2.0, seed=5)
    gap = int(0.085 * RATE)
    out = first + [0.0] * (gap + len(second) - len(first))
    for i, s in enumerate(second):
        out[gap + i] += s
    top = max(abs(s) for s in out) or 1.0
    return [s / top * 0.5 for s in out] + [0.0] * int(0.05 * RATE)


def _fit(samples, peak=0.5, tail=0.04):
    """Scaled to a peak, with a short silence after so players don't clip it."""
    top = max(abs(s) for s in samples) or 1.0
    return [s / top * peak for s in samples] + [0.0] * int(tail * RATE)


def _mix(parts):
    """parts: (start in seconds, samples); one track as long as the last."""
    total = max(int(start * RATE) + len(samples) for start, samples in parts)
    out = [0.0] * total
    for start, samples in parts:
        first = int(start * RATE)
        for i, s in enumerate(samples):
            out[first + i] += s
    return out


def sweep(start_freq, end_freq, length, decay, harmonics=((1, 1.0),)):
    """A tone gliding from one pitch to another, dying away."""
    out, phase = [], 0.0
    total = int(RATE * length)
    for i in range(total):
        t = i / RATE
        freq = start_freq * (end_freq / start_freq) ** (t / length)
        phase += 2 * math.pi * freq / RATE
        env = min(1.0, t / 0.003) * math.exp(-t * decay)
        out.append(env * sum(loud * math.sin(phase * mult) for mult, loud in harmonics))
    return out


def bell_note(freq, length=1.1):
    out = [0.0] * int(RATE * length)
    for mult, loud, decay in PARTIALS:
        step = 2 * math.pi * freq * mult / RATE
        fall = math.exp(-decay * 1.6 / RATE)
        level = loud
        for i in range(len(out)):
            out[i] += level * min(1.0, i / (ATTACK * RATE)) * math.sin(step * i)
            level *= fall
    return out


def alert_pebble():
    return _fit(_mix([(0.0, tap(1650, 0.07, 1.0, noise=0.9, seed=11)),
                      (0.075, tap(2150, 0.07, 0.8, noise=0.9, seed=12))]))


def alert_droplet():
    return _fit(sweep(520, 1500, 0.11, 30, ((1, 1.0), (2, 0.12))))


def alert_knock():
    def knock(seed):
        return [s for s in tap(190, 0.11, 1.0, noise=0.35, seed=seed)]
    return _fit(_mix([(0.0, knock(21)), (0.14, [s * 0.85 for s in knock(22)])]), peak=0.6)


def alert_chirp():
    one = sweep(2100, 3300, 0.06, 45, ((1, 1.0), (2, 0.08)))
    return _fit(_mix([(0.0, one), (0.085, [s * 0.75 for s in one])]), peak=0.42)


def alert_bell():
    return _fit(room(bell_note(1046.5)), peak=0.42)


def alert_hum():
    total = int(RATE * 0.42)
    out = []
    for i in range(total):
        t = i / RATE
        env = math.sin(math.pi * min(1.0, t / 0.42)) ** 1.5
        wobble = 1 + 0.01 * math.sin(2 * math.pi * 6 * t)
        x = 2 * math.pi * 196 * wobble * t
        out.append(env * (math.sin(x) + 0.35 * math.sin(2 * x) + 0.12 * math.sin(3 * x)))
    return _fit(out, peak=0.45)


ALERTS = (("pebble", alert_pebble), ("droplet", alert_droplet), ("knock", alert_knock),
          ("chirp", alert_chirp), ("bell", alert_bell), ("hum", alert_hum))


def pop():
    return _fit(sweep(900, 420, 0.045, 70, ((1, 1.0), (2, 0.1))), peak=0.4, tail=0.02)


def trash():
    import random
    parts = []
    rng = random.Random(7)
    t = 0.0
    while t < 0.42:
        length = rng.uniform(0.02, 0.06)
        burst = []
        smooth, prev = 0.0, 0.0
        for i in range(int(RATE * length)):
            x = i / RATE
            smooth += (rng.uniform(-1, 1) - smooth) * 0.2
            high = smooth - prev     # crackle: keep the quick changes
            prev = smooth
            burst.append((smooth + 0.4 * high) * math.exp(-x * 60) * min(1.0, x / 0.001))
        parts.append((t, [s * rng.uniform(0.5, 1.0) * (1 - t) for s in burst]))
        t += rng.uniform(0.018, 0.05)
    return _fit(_mix(parts), peak=0.4)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(outdir, exist_ok=True)
    write(os.path.join(outdir, "startup.wav"), finish(room(bells())))
    write(os.path.join(outdir, "tick.wav"), tick())
    write(os.path.join(outdir, "shutter.wav"), shutter())
    for name, make in ALERTS:
        write(os.path.join(outdir, f"alert-{name}.wav"), make())
    write(os.path.join(outdir, "pop.wav"), pop())
    write(os.path.join(outdir, "trash.wav"), trash())


if __name__ == "__main__":
    main()
