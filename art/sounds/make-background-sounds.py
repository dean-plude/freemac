#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Make freemac's background sounds from scratch: no recordings, no samples.

    make-background-sounds.py OUTDIR    writes OUTDIR/balanced.wav, bright.wav,
                                        dark.wav, ocean.wav, rain.wav, stream.wav

Steady sounds that play quietly behind everything else, to mask other noise
and help you focus or rest (Dials > Accessibility > Background sounds), as a
Mac has:

- balanced: pink noise, even from low to high, like a fan;
- bright: white noise with its harshest top taken off, like steam;
- dark: brown noise, deep and soft, like a distant rumble;
- ocean: deep noise that swells and falls back three times a loop, a wave
  breaking each time, with its foam brighter at the top of the wave;
- rain: a soft hiss of steady rain with many small drops falling on it;
- stream: running water: a bubbling hiss with quick rising "bloops".

Each file is a LENGTH-second loop: the sound is made a little longer and
its end is faded into its start, so it repeats with no seam. Every sound is
made from seeded random numbers, so each build makes the same files.
Original freemac work; pink noise uses Paul Kellet's well-known filter.
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 22050
LENGTH = 24.0          # seconds in the loop
OVERLAP = 1.5          # seconds faded from the end into the start
LEVEL = 0.08           # average (RMS) level, so every sound is as loud as the others
PEAK = 0.6             # never above this, of full scale

TOTAL = int(RATE * (LENGTH + OVERLAP))


def white(seed):
    rng = random.Random(seed)
    return [rng.uniform(-1, 1) for _ in range(TOTAL)]


def pink(seed):
    b0 = b1 = b2 = b3 = b4 = b5 = b6 = 0.0
    out = []
    for w in white(seed):
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        out.append(b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362)
        b6 = w * 0.115926
    return out


def brown(seed):
    out, b = [], 0.0
    for w in white(seed):
        b = (b + 0.02 * w) / 1.02
        out.append(b)
    return out


def lowpass(samples, cutoff):
    a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    out, y = [], 0.0
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


def highpass(samples, cutoff):
    low = lowpass(samples, cutoff)
    return [s - l for s, l in zip(samples, low)]


def normal(samples, level=1.0):
    top = max(abs(s) for s in samples) or 1.0
    return [s / top * level for s in samples]


def add(*tracks):
    return [sum(values) for values in zip(*tracks)]


def balanced():
    return pink(11)


def bright():
    return lowpass(white(12), 6500)


def dark():
    return highpass(brown(13), 25)


def ocean():
    """Three waves a loop (so the swell repeats exactly), each rising slowly,
    breaking into brighter foam and drawing back."""
    deep = normal(highpass(brown(21), 30))
    foam = normal(lowpass(pink(22), 3000))
    period = LENGTH / 3
    out = []
    for i in range(TOTAL):
        phase = (i / RATE % period) / period
        # Slow rise to the break at 0.6, then a quicker fall.
        swell = (phase / 0.6) ** 2 if phase < 0.6 else math.exp(-(phase - 0.6) * 7)
        out.append(deep[i] * (0.35 + 0.45 * swell) + foam[i] * (0.08 + 0.6 * swell ** 1.6))
    return out


def drops(seed, rate_per_second, length_ms, tone):
    """Many tiny clicks of filtered noise at random times and loudness."""
    rng = random.Random(seed)
    out = [0.0] * TOTAL
    count = int(rate_per_second * TOTAL / RATE)
    for _ in range(count):
        start = rng.randrange(TOTAL)
        loud = rng.uniform(0.15, 1.0) ** 2
        size = int(RATE * length_ms / 1000 * rng.uniform(0.6, 1.4))
        y = 0.0
        for k in range(size):
            if start + k >= TOTAL:
                break
            y += (rng.uniform(-1, 1) - y) * tone
            out[start + k] += loud * y * math.exp(-k / (size / 4))
    return out


def rain():
    bed = normal(highpass(pink(31), 400))
    falling = normal(highpass(drops(32, 140, 9, 0.6), 900))
    return add([s * 0.55 for s in bed], [s * 0.6 for s in falling])


def stream():
    rng = random.Random(41)
    hiss = normal(highpass(lowpass(pink(42), 2500), 250))
    # The hiss swells and dips quickly, as water runs over stones.
    wobble = normal(lowpass(white(43), 3), 1.0)
    out = [h * (0.55 + 0.3 * w) for h, w in zip(hiss, wobble)]
    # Bubbles: short tones that rise as they fade.
    for _ in range(int(18 * TOTAL / RATE)):
        start = rng.randrange(TOTAL)
        freq = rng.uniform(380, 950)
        size = int(RATE * rng.uniform(0.018, 0.045))
        loud = rng.uniform(0.05, 0.3)
        phase = 0.0
        for k in range(size):
            if start + k >= TOTAL:
                break
            t = k / size
            phase += 2 * math.pi * freq * (1 + 0.8 * t) / RATE
            out[start + k] += loud * math.sin(phase) * math.sin(math.pi * t)
    return out


def loop(samples):
    """LENGTH seconds that repeat seamlessly: the extra end fades into the start."""
    keep = int(RATE * LENGTH)
    fade = TOTAL - keep
    out = samples[:keep]
    for i in range(fade):
        t = i / fade
        out[i] = samples[i] * math.sin(t * math.pi / 2) + samples[keep + i] * math.cos(t * math.pi / 2)
    rms = math.sqrt(sum(v * v for v in out) / len(out)) or 1.0
    top = max(abs(v) for v in out) or 1.0
    scale = min(LEVEL / rms, PEAK / top)
    return [v * scale for v in out]


def write(path, samples):
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))


SOUNDS = (("balanced", balanced), ("bright", bright), ("dark", dark),
          ("ocean", ocean), ("rain", rain), ("stream", stream))


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(outdir, exist_ok=True)
    for name, make in SOUNDS:
        write(os.path.join(outdir, f"{name}.wav"), loop(make()))


if __name__ == "__main__":
    main()
