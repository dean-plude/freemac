#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Make freemac's own sounds from scratch: no recordings, no samples.

    make-sounds.py OUTDIR      writes OUTDIR/startup.wav, tick.wav and shutter.wav

startup.wav is freemac's start-up sound: four soft bell notes rising one after
another (D, A, E, then a high B, a little apart), so it reads as a quick
upward sweep rather than one struck chord. Each bell is a few slightly
out-of-tune partials dying away at different speeds, with a short room echo
made by mixing in quieter, later copies.

tick.wav is one soft, short wooden tap, for each second of Pose's countdown.
shutter.wav is Pose's picture sound: two quick clacks of filtered noise, the
first louder, like a shutter opening and closing. Original freemac work.
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


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(outdir, exist_ok=True)
    write(os.path.join(outdir, "startup.wav"), finish(room(bells())))
    write(os.path.join(outdir, "tick.wav"), tick())
    write(os.path.join(outdir, "shutter.wav"), shutter())


if __name__ == "__main__":
    main()
