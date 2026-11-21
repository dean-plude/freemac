# SPDX-License-Identifier: GPL-3.0-or-later
"""Ledger's sheet and formulas, with no GTK, so they can be tested alone.

A sheet maps (column, row), both from 0, to what was typed in the cell. Text
starting with = is a formula: numbers, "text", cell references (B2, $B$2),
ranges (A1:A9), + - * / ^ & (joins text), = <> < > <= >= and the functions in
FUNCTIONS. Everything else is a number when it reads as one ("1,200", "15%",
"$3.50") and text otherwise. Original freemac code: a small parser of its
own, never eval().
"""
import csv
import io
import math
import re

ERRORS = ("#DIV/0!", "#REF!", "#NAME?", "#VALUE!", "#CYCLE!", "#NUM!")
MAX_COLS, MAX_ROWS = 702, 100000   # up to column ZZ


class SheetError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


# --- addresses ----------------------------------------------------------------

def column_name(col):
    name = ""
    col += 1
    while col:
        col, rest = divmod(col - 1, 26)
        name = chr(65 + rest) + name
    return name


def column_number(name):
    col = 0
    for ch in name.upper():
        col = col * 26 + ord(ch) - 64
    return col - 1


def address(col, row):
    return f"{column_name(col)}{row + 1}"


REF = re.compile(r"(\$?)([A-Za-z]{1,2})(\$?)([0-9]{1,6})")


def parse_address(text):
    match = REF.fullmatch(text.strip())
    if not match:
        return None
    col, row = column_number(match.group(2)), int(match.group(4)) - 1
    if row < 0 or col >= MAX_COLS or row >= MAX_ROWS:
        return None
    return col, row


# --- plain values ---------------------------------------------------------------

NUMBER = re.compile(r"[-+]?(\d[\d,]*(\.\d*)?|\.\d+)([eE][-+]?\d+)?")


def read_number(text):
    """A number typed in a cell, or None. Allows 1,200 and 15% and $3.50."""
    t = text.strip()
    if not t:
        return None
    percent = t.endswith("%")
    if percent:
        t = t[:-1].strip()
    negative = t.startswith("(") and t.endswith(")")
    if negative:
        t = t[1:-1]
    if t[:1] in "$£€":
        t = t[1:]
    elif t[:2] in ("-$", "-£", "-€"):
        t = "-" + t[2:]
    if not NUMBER.fullmatch(t):
        return None
    if "," in t and not re.fullmatch(r"[-+]?\d{1,3}(,\d{3})+(\.\d*)?([eE][-+]?\d+)?", t):
        return None
    try:
        value = float(t.replace(",", ""))
    except ValueError:
        return None
    if negative:
        value = -value
    return value / 100 if percent else value


# --- formulas -------------------------------------------------------------------

TOKEN = re.compile(r"""
    \s*(?:
      (?P<string>"(?:[^"]|"")*")
    | (?P<range>\$?[A-Za-z]{1,2}\$?[0-9]{1,6}:\$?[A-Za-z]{1,2}\$?[0-9]{1,6})
    | (?P<ref>\$?[A-Za-z]{1,2}\$?[0-9]{1,6}(?![A-Za-z0-9_(]))
    | (?P<number>(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)
    | (?P<name>[A-Za-z_][A-Za-z0-9_.]*)
    | (?P<error>\#REF!)
    | (?P<op><>|<=|>=|[-+*/^&=<>(),:%])
    )""", re.VERBOSE)


def tokenize(text):
    tokens, pos = [], 0
    while pos < len(text):
        if text[pos:].strip() == "":
            break
        match = TOKEN.match(text, pos)
        if not match or match.end() == pos:
            raise SheetError("#NAME?")
        pos = match.end()
        kind = match.lastgroup
        tokens.append((kind, match.group(kind)))
    return tokens


class Parser:
    """Recursive descent over the tokens, building a small tree of tuples."""

    def __init__(self, text):
        self.tokens = tokenize(text)
        self.at = 0

    def peek(self):
        return self.tokens[self.at] if self.at < len(self.tokens) else (None, None)

    def take(self, value=None):
        kind, text = self.peek()
        if kind is None or (value is not None and text != value):
            raise SheetError("#VALUE!")
        self.at += 1
        return kind, text

    def parse(self):
        if not self.tokens:
            raise SheetError("#VALUE!")
        tree = self.comparison()
        if self.at != len(self.tokens):
            raise SheetError("#VALUE!")
        return tree

    def comparison(self):
        left = self.concat()
        while self.peek()[1] in ("=", "<>", "<", ">", "<=", ">="):
            op = self.take()[1]
            left = ("cmp", op, left, self.concat())
        return left

    def concat(self):
        left = self.additive()
        while self.peek()[1] == "&":
            self.take()
            left = ("join", left, self.additive())
        return left

    def additive(self):
        left = self.term()
        while self.peek()[1] in ("+", "-"):
            op = self.take()[1]
            left = ("arith", op, left, self.term())
        return left

    def term(self):
        left = self.power()
        while self.peek()[1] in ("*", "/"):
            op = self.take()[1]
            left = ("arith", op, left, self.power())
        return left

    def power(self):
        left = self.unary()
        if self.peek()[1] == "^":
            self.take()
            return ("arith", "^", left, self.power())
        return left

    def unary(self):
        if self.peek()[1] in ("-", "+"):
            op = self.take()[1]
            inner = self.unary()
            return ("neg", inner) if op == "-" else inner
        node = self.atom()
        while self.peek()[1] == "%":
            self.take()
            node = ("arith", "/", node, ("num", 100.0))
        return node

    def atom(self):
        kind, text = self.take()
        if kind == "number":
            return ("num", float(text))
        if kind == "error":
            raise SheetError("#REF!")
        if kind == "ref":
            where = parse_address(text)
            if where is None:
                raise SheetError("#REF!")
            return ("ref", where)
        if kind == "string":
            return ("str", text[1:-1].replace('""', '"'))
        if kind == "range":
            first, last = text.split(":")
            a, b = parse_address(first), parse_address(last)
            if a is None or b is None:
                raise SheetError("#REF!")
            return ("range", (min(a[0], b[0]), min(a[1], b[1])), (max(a[0], b[0]), max(a[1], b[1])))
        if kind == "name":
            if self.peek()[1] == "(":
                self.take("(")
                args = []
                if self.peek()[1] != ")":
                    args.append(self.comparison())
                    while self.peek()[1] == ",":
                        self.take()
                        args.append(self.comparison())
                self.take(")")
                return ("call", text.upper(), args)
            upper = text.upper()
            if upper in ("TRUE", "FALSE"):
                return ("bool", upper == "TRUE")
            raise SheetError("#NAME?")
        if text == "(":
            inner = self.comparison()
            self.take(")")
            return inner
        raise SheetError("#VALUE!")


# --- the sheet -------------------------------------------------------------------

def as_number(value):
    if isinstance(value, bool):
        return 1.0 if value else 0.0
    if isinstance(value, float):
        return value
    if value is None or value == "":
        return 0.0
    if isinstance(value, str):
        if value in ERRORS:
            raise SheetError(value)
        number = read_number(value)
        if number is None:
            raise SheetError("#VALUE!")
        return number
    raise SheetError("#VALUE!")


def as_text(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, float):
        return plain_number(value)
    return str(value)


def as_bool(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str) and value.upper() in ("TRUE", "FALSE"):
        return value.upper() == "TRUE"
    return as_number(value) != 0


def plain_number(value):
    if value == int(value) and abs(value) < 1e15:
        return str(int(value))
    return f"{value:.10g}"


def numbers_in(values):
    """Numbers from a function's arguments; text and empty cells in ranges are
    skipped, as in other spreadsheets."""
    found = []
    for value, from_range in values:
        if isinstance(value, str) and value in ERRORS:
            raise SheetError(value)
        if from_range:
            if isinstance(value, float):
                found.append(value)
        else:
            found.append(as_number(value))
    return found


def _round(args):
    value = as_number(args[0])
    places = int(as_number(args[1])) if len(args) > 1 else 0
    scaled = abs(value) * 10 ** places
    result = math.floor(scaled + 0.5) / 10 ** places
    return math.copysign(result, value) if value else 0.0


def _need(args, low, high=None):
    if len(args) < low or (high is not None and len(args) > high):
        raise SheetError("#VALUE!")


class Sheet:
    def __init__(self):
        self.cells = {}        # (col, row) -> text typed
        self.formats = {}      # (col, row) -> "number" | "currency" | "percent"
        self.bold = set()
        self.widths = {}       # col -> pixels
        self._values = {}
        self._parsed = {}

    # editing
    def get(self, col, row):
        return self.cells.get((col, row), "")

    def set(self, col, row, text):
        text = text or ""
        if text:
            self.cells[(col, row)] = text
        else:
            self.cells.pop((col, row), None)
        self._parsed.pop((col, row), None)
        self._values = {}

    def extent(self):
        """(columns, rows) that hold anything."""
        if not self.cells:
            return 0, 0
        return max(c for c, _ in self.cells) + 1, max(r for _, r in self.cells) + 1

    # values
    def value(self, col, row):
        """The cell's value: float, str, bool, None for empty, or an error code."""
        key = (col, row)
        if key in self._values:
            found = self._values[key]
            if found is _BUSY:
                raise SheetError("#CYCLE!")
            return found
        text = self.cells.get(key)
        if text is None:
            return None
        if not text.startswith("=") or len(text) == 1:
            number = read_number(text)
            value = number if number is not None else (text[1:] if text.startswith("'") else text)
            self._values[key] = value
            return value
        self._values[key] = _BUSY
        try:
            tree = self._parsed.get(key)
            if tree is None:
                tree = Parser(text[1:]).parse()
                self._parsed[key] = tree
            value = self.evaluate(tree)
            if isinstance(value, list):
                value = value[0][0] if value else None
            if isinstance(value, float) and (math.isnan(value) or math.isinf(value)):
                value = "#NUM!"
        except SheetError as err:
            value = err.code
        except (RecursionError, OverflowError, ValueError, ZeroDivisionError):
            value = "#NUM!"
        self._values[key] = value
        return value

    def evaluate(self, node):
        kind = node[0]
        if kind == "num":
            return node[1]
        if kind == "str":
            return node[1]
        if kind == "bool":
            return node[1]
        if kind == "ref":
            value = self.value(*node[1])
            if isinstance(value, str) and value in ERRORS:
                raise SheetError(value)
            return value
        if kind == "range":
            (c1, r1), (c2, r2) = node[1], node[2]
            if (c2 - c1 + 1) * (r2 - r1 + 1) > 200000:
                raise SheetError("#REF!")
            return [[self.value(c, r) for c in range(c1, c2 + 1)] for r in range(r1, r2 + 1)]
        if kind == "neg":
            return -as_number(self.scalar(node[1]))
        if kind == "arith":
            op = node[1]
            a, b = as_number(self.scalar(node[2])), as_number(self.scalar(node[3]))
            if op == "+":
                return a + b
            if op == "-":
                return a - b
            if op == "*":
                return a * b
            if op == "/":
                if b == 0:
                    raise SheetError("#DIV/0!")
                return a / b
            if a == 0 and b < 0:
                raise SheetError("#DIV/0!")
            result = a ** b
            if isinstance(result, complex):
                raise SheetError("#NUM!")
            return result
        if kind == "join":
            return as_text(self.scalar(node[1])) + as_text(self.scalar(node[2]))
        if kind == "cmp":
            a, b = self.scalar(node[2]), self.scalar(node[3])
            for v in (a, b):
                if isinstance(v, str) and v in ERRORS:
                    raise SheetError(v)
            if isinstance(a, str) or isinstance(b, str):
                if isinstance(a, float) or isinstance(b, float):
                    a, b = (0, 1) if isinstance(a, float) else (1, 0)   # numbers sort before text
                else:
                    a, b = as_text(a).lower(), as_text(b).lower()
            else:
                a, b = as_number(a), as_number(b)
            return {"=": a == b, "<>": a != b, "<": a < b, ">": a > b, "<=": a <= b, ">=": a >= b}[node[1]]
        if kind == "call":
            return self.call(node[1], node[2])
        raise SheetError("#VALUE!")

    def scalar(self, node):
        value = self.evaluate(node)
        if isinstance(value, list):
            if len(value) == 1 and len(value[0]) == 1:
                return value[0][0]
            raise SheetError("#VALUE!")
        return value

    def flat(self, args):
        """(value, came_from_a_range) for every argument, ranges opened out."""
        out = []
        for arg in args:
            value = self.evaluate(arg)
            if isinstance(value, list):
                out.extend((v, True) for row in value for v in row)
            else:
                out.append((value, False))
        return out

    def call(self, name, args):
        if name == "IF":
            _need(args, 2, 3)
            if as_bool(self.scalar(args[0])):
                return self.scalar(args[1])
            return self.scalar(args[2]) if len(args) > 2 else False
        if name in ("SUM", "AVERAGE", "MIN", "MAX", "COUNT", "MEDIAN", "PRODUCT"):
            numbers = numbers_in(self.flat(args))
            if name == "SUM":
                return float(math.fsum(numbers))
            if name == "COUNT":
                return float(len(numbers))
            if name == "PRODUCT":
                return float(math.prod(numbers)) if numbers else 0.0
            if name in ("MIN", "MAX"):
                return (min if name == "MIN" else max)(numbers) if numbers else 0.0
            if not numbers:
                raise SheetError("#DIV/0!")
            if name == "AVERAGE":
                return math.fsum(numbers) / len(numbers)
            ordered = sorted(numbers)
            middle = len(ordered) // 2
            return ordered[middle] if len(ordered) % 2 else (ordered[middle - 1] + ordered[middle]) / 2
        if name == "COUNTA":
            return float(sum(1 for v, _r in self.flat(args) if v not in (None, "")))
        if name == "COUNTIF" or name == "SUMIF":
            _need(args, 2, 3)
            test = criterion(self.scalar(args[1]))
            cells = self.evaluate(args[0])
            cells = cells if isinstance(cells, list) else [[cells]]
            sums = self.evaluate(args[2]) if len(args) > 2 else cells
            sums = sums if isinstance(sums, list) else [[sums]]
            total, count = 0.0, 0
            for r, row in enumerate(cells):
                for c, v in enumerate(row):
                    if test(v):
                        count += 1
                        if r < len(sums) and c < len(sums[r]) and isinstance(sums[r][c], float):
                            total += sums[r][c]
            return float(count) if name == "COUNTIF" else total
        if name == "ROUND":
            _need(args, 1, 2)
            return _round([self.scalar(a) for a in args])
        if name in ("ABS", "SQRT", "INT"):
            _need(args, 1, 1)
            x = as_number(self.scalar(args[0]))
            if name == "SQRT":
                if x < 0:
                    raise SheetError("#NUM!")
                return math.sqrt(x)
            return abs(x) if name == "ABS" else float(math.floor(x))
        if name == "MOD":
            _need(args, 2, 2)
            a, b = as_number(self.scalar(args[0])), as_number(self.scalar(args[1]))
            if b == 0:
                raise SheetError("#DIV/0!")
            return a - b * math.floor(a / b)
        if name == "POWER":
            _need(args, 2, 2)
            return self.evaluate(("arith", "^", args[0], args[1]))
        if name == "PI":
            _need(args, 0, 0)
            return math.pi
        if name in ("AND", "OR"):
            values = [as_bool(v) for v, r in self.flat(args) if not (r and v in (None, ""))]
            if not values:
                raise SheetError("#VALUE!")
            return all(values) if name == "AND" else any(values)
        if name == "NOT":
            _need(args, 1, 1)
            return not as_bool(self.scalar(args[0]))
        if name in ("CONCAT", "CONCATENATE"):
            return "".join(as_text(v) for v, _r in self.flat(args))
        if name in ("LEN", "UPPER", "LOWER", "TRIM"):
            _need(args, 1, 1)
            t = as_text(self.scalar(args[0]))
            if name == "LEN":
                return float(len(t))
            return {"UPPER": t.upper(), "LOWER": t.lower(), "TRIM": " ".join(t.split())}[name]
        raise SheetError("#NAME?")

    # files
    def to_json(self):
        return {"cells": {address(c, r): t for (c, r), t in sorted(self.cells.items(), key=lambda i: (i[0][1], i[0][0]))},
                "formats": {address(c, r): f for (c, r), f in self.formats.items()},
                "bold": sorted(address(c, r) for c, r in self.bold),
                "widths": {column_name(c): w for c, w in self.widths.items()}}

    @classmethod
    def from_json(cls, data):
        sheet = cls()
        for name, text in (data.get("cells") or {}).items():
            where = parse_address(name)
            if where and isinstance(text, str):
                sheet.cells[where] = text
        for name, fmt in (data.get("formats") or {}).items():
            where = parse_address(name)
            if where and fmt in FORMATS:
                sheet.formats[where] = fmt
        for name in data.get("bold") or []:
            where = parse_address(name) if isinstance(name, str) else None
            if where:
                sheet.bold.add(where)
        for name, width in (data.get("widths") or {}).items():
            if isinstance(name, str) and name.isalpha() and isinstance(width, (int, float)):
                sheet.widths[column_number(name)] = max(24, min(800, int(width)))
        return sheet

    def to_csv(self):
        cols, rows = self.extent()
        out = io.StringIO()
        writer = csv.writer(out, lineterminator="\n")
        for r in range(rows):
            writer.writerow([as_text(self.value(c, r)) for c in range(cols)])
        return out.getvalue()

    @classmethod
    def from_csv(cls, text):
        sheet = cls()
        try:
            dialect = csv.Sniffer().sniff(text[:4096], delimiters=",;\t")
        except csv.Error:
            dialect = csv.excel
        for r, row in enumerate(csv.reader(io.StringIO(text), dialect)):
            if r >= MAX_ROWS:
                break
            for c, cell in enumerate(row[:MAX_COLS]):
                if cell:
                    # A cell that looks like a formula comes in as text, so a
                    # file can't run formulas it carried in.
                    sheet.cells[(c, r)] = "'" + cell if cell.startswith("=") else cell
        return sheet


_BUSY = object()
FORMATS = ("general", "number", "currency", "percent")


def criterion(spec):
    """COUNTIF/SUMIF tests: 5, ">5", "<>apple", "apple"."""
    if isinstance(spec, str):
        match = re.fullmatch(r"\s*(<>|<=|>=|=|<|>)?(.*)", spec)
        op, rest = match.group(1) or "=", match.group(2)
        number = read_number(rest)
        if number is not None:
            target = number
        else:
            target = rest.lower()
    else:
        op, target = "=", as_number(spec)

    def test(value):
        if isinstance(target, float):
            if not isinstance(value, float):
                return op == "<>"
            v = value
        else:
            v = as_text(value).lower()
            if isinstance(value, float) and op != "<>" and op != "=":
                return False
        return {"=": v == target, "<>": v != target, "<": v < target, ">": v > target,
                "<=": v <= target, ">=": v >= target}[op]
    return test


def format_value(value, fmt="general", symbol="$", digits=10):
    """What a cell shows. `digits` is how many figures a plain number keeps,
    fewer when a column is too narrow for them all."""
    if value is None:
        return ""
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, float):
        if fmt == "number":
            return f"{value:,.2f}"
        if fmt == "currency":
            return f"-{symbol}{-value:,.2f}" if value < 0 else f"{symbol}{value:,.2f}"
        if fmt == "percent":
            return f"{value * 100:.0f}%" if abs(value * 100 - round(value * 100)) < 1e-9 else f"{value * 100:.2f}%"
        if value == int(value) and abs(value) < 1e15:
            return str(int(value))
        return f"{value:.{digits}g}"
    return str(value)


def shift_formula(text, dcol, drow):
    """A formula copied dcol columns and drow rows away: references without $
    move with it. A reference pushed off the sheet becomes #REF!."""
    if not text.startswith("="):
        return text
    out, pos = [], 0
    for match in re.finditer(r'"(?:[^"]|"")*"|(\$?)([A-Za-z]{1,2})(\$?)([0-9]{1,6})(?![A-Za-z0-9_(])', text):
        out.append(text[pos:match.start()])
        pos = match.end()
        if match.group(2) is None:
            out.append(match.group(0))
            continue
        before = text[match.start() - 1] if match.start() else ""
        if before.isalnum() or before == "_":
            out.append(match.group(0))
            continue
        col_fixed, row_fixed = match.group(1), match.group(3)
        col, row = column_number(match.group(2)), int(match.group(4)) - 1
        col += 0 if col_fixed else dcol
        row += 0 if row_fixed else drow
        if col < 0 or row < 0 or col >= MAX_COLS or row >= MAX_ROWS:
            out.append("#REF!")
        else:
            out.append(f"{col_fixed}{column_name(col)}{row_fixed}{row + 1}")
    out.append(text[pos:])
    return "".join(out)


RANGE_OR_REF = re.compile(r'"(?:[^"]|"")*"'
                          r'|(?<![A-Za-z0-9_$])(\$?[A-Za-z]{1,2}\$?[0-9]{1,6})(?::(\$?[A-Za-z]{1,2}\$?[0-9]{1,6}))?'
                          r'(?![A-Za-z0-9_(])')


def _split_ref(text):
    match = REF.fullmatch(text)
    return match.group(1), column_number(match.group(2)), match.group(3), int(match.group(4)) - 1


def _join_ref(col_fixed, col, row_fixed, row):
    return f"{col_fixed}{column_name(col)}{row_fixed}{row + 1}"


def insert_or_delete(text, axis, at, delta):
    """A formula after rows (axis 1) or columns (axis 0) are inserted at
    `at` (delta > 0) or deleted from `at` (delta < 0). Every reference past
    the change moves, fixed with $ or not; one to a deleted cell becomes #REF!,
    and a range loses the deleted part."""
    if not text.startswith("="):
        return text
    gone_end = at - delta if delta < 0 else at   # deleted: at .. gone_end-1

    def move(n, end_of_range=None):
        if delta > 0:
            return n + delta if n >= at else n
        if n < at:
            return n
        if n >= gone_end:
            return n + delta
        if end_of_range is None:
            return None
        return at - 1 if end_of_range else at   # a range end inside the gap

    def fix(match):
        if match.group(1) is None:
            return match.group(0)
        first = _split_ref(match.group(1))
        if match.group(2) is None:
            parts = list(first)
            index = 1 if axis == 0 else 3
            moved = move(parts[index])
            if moved is None:
                return "#REF!"
            parts[index] = moved
            return _join_ref(*parts)
        last = _split_ref(match.group(2))
        a, b = list(first), list(last)
        index = 1 if axis == 0 else 3
        lo, hi = move(a[index], False), move(b[index], True)
        if hi < lo:
            return "#REF!"
        a[index], b[index] = lo, hi
        return _join_ref(*a) + ":" + _join_ref(*b)

    return RANGE_OR_REF.sub(fix, text)
