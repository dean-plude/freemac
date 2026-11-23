# SPDX-License-Identifier: GPL-3.0-or-later
"""Live Text: the words in a picture, found so they can be selected and copied.

Frame shows a picture or a PDF page; read() hands it to Tesseract (the OCR
engine, tesseract-ocr, Apache-2.0) as a PNG on its standard input, asks for
its TSV report and turns that into Words: each with its box in the picture's
own pixels and where it sits (block, paragraph, line), in reading order.
Nothing is written to disk. text_of() puts a run of words back together
with spaces, line breaks and blank lines between paragraphs.

Original freemac code.
"""
import os
import shutil
import subprocess

# Tesseract reads text best when letters are 20 to 40 pixels tall: small
# pictures (a screenshot) are enlarged, very large ones (a phone photo)
# shrunk, which also keeps it quick.
SMALLEST, LARGEST = 1600, 3200
TIMEOUT = 90


class Word:
    __slots__ = ("text", "x", "y", "w", "h", "block", "par", "line", "conf")

    def __init__(self, text, x, y, w, h, block, par, line, conf):
        self.text, self.x, self.y, self.w, self.h = text, x, y, w, h
        self.block, self.par, self.line, self.conf = block, par, line, conf

    def line_key(self):
        return (self.block, self.par, self.line)

    def contains(self, px, py, slack=0):
        return (self.x - slack <= px <= self.x + self.w + slack
                and self.y - slack <= py <= self.y + self.h + slack)

    def distance(self, px, py):
        dx = max(self.x - px, 0, px - (self.x + self.w))
        dy = max(self.y - py, 0, py - (self.y + self.h))
        return (dx * dx + (3 * dy) ** 2) ** 0.5   # stay on the line the pointer is on


def available():
    return shutil.which("tesseract") is not None


def factor_for(width, height):
    longest = max(width, height, 1)
    if longest < SMALLEST:
        return min(2.0, SMALLEST / longest)
    if longest > LARGEST:
        return LARGEST / longest
    return 1.0


def parse_tsv(text, factor=1.0):
    """Tesseract's TSV report -> [Word], in reading order. Boxes are divided by
    factor (the scale the picture was given before reading)."""
    words = []
    lines = text.splitlines()
    for row in lines[1:]:
        cols = row.split("\t")
        if len(cols) < 12 or cols[0] != "5":
            continue
        word = cols[11].strip()
        try:
            conf = float(cols[10])
            block, par, line = int(cols[2]), int(cols[3]), int(cols[4])
            x, y, w, h = (int(c) for c in cols[6:10])
        except ValueError:
            continue
        if not word or conf < 0:
            continue
        # Specks and smudges come back as one stray mark with little confidence.
        if conf < 40 and len(word) <= 2 and not any(ch.isalnum() for ch in word):
            continue
        if conf < 15:
            continue
        words.append(Word(word, x / factor, y / factor, w / factor, h / factor, block, par, line, conf))
    return words


def text_of(words):
    """The words as text: spaces within a line, a line break between lines and
    a blank line between paragraphs."""
    out, last = [], None
    for word in words:
        key = word.line_key()
        if last is None:
            pass
        elif key[:2] != last[:2]:
            out.append("\n\n")
        elif key != last:
            out.append("\n")
        else:
            out.append(" ")
        out.append(word.text)
        last = key
    return "".join(out)


class Reader:
    """Reads one picture at a time; starting another stops the one before."""

    def __init__(self):
        self.process = None

    def stop(self):
        process, self.process = self.process, None
        if process is not None and process.poll() is None:
            try:
                process.kill()
            except OSError:
                pass

    def read(self, png_bytes, factor):
        """Run in a worker thread: [Word] for a PNG, or [] (none, stopped, or
        no Tesseract)."""
        if not available():
            return []
        env = dict(os.environ, OMP_THREAD_LIMIT="2")
        try:
            process = subprocess.Popen(["tesseract", "stdin", "stdout", "-l", "eng", "tsv"],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.DEVNULL, env=env)
        except OSError:
            return []
        self.stop()
        self.process = process
        try:
            out, _err = process.communicate(png_bytes, timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            process.kill()
            return []
        except (OSError, ValueError):
            return []
        if process.returncode != 0:
            return []
        return parse_tsv(out.decode("utf-8", "replace"), factor)
