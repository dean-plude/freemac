# SPDX-License-Identifier: GPL-3.0-or-later
"""The rules of chess and a small computer player, for Rook.

Original freemac code. A position is 64 squares, a1 first and h8 last, each
holding a letter (PNBRQK for white, pnbrqk for black) or "." for empty. A
move is (from, to, promotion). The computer looks a few moves ahead with
alpha-beta search, then keeps following captures until things go quiet, and
scores what it finds by material and by where each piece stands.
"""
import random
import time

FILES = "abcdefgh"
WHITE, BLACK = "w", "b"
VALUE = {"p": 100, "n": 320, "b": 330, "r": 500, "q": 900, "k": 0}
KNIGHT = ((1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2))
KING = ((1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1))
ROOK_DIRS = ((1, 0), (-1, 0), (0, 1), (0, -1))
BISHOP_DIRS = ((1, 1), (1, -1), (-1, 1), (-1, -1))
START = "RNBQKBNR" + "P" * 8 + "." * 32 + "p" * 8 + "rnbqkbnr"

# Where each piece likes to stand, from white's side, a1 first.
PST = {
    "p": [0, 0, 0, 0, 0, 0, 0, 0,
          5, 10, 10, -20, -20, 10, 10, 5,
          5, -5, -10, 0, 0, -10, -5, 5,
          0, 0, 0, 20, 20, 0, 0, 0,
          5, 5, 10, 25, 25, 10, 5, 5,
          10, 10, 20, 30, 30, 20, 10, 10,
          50, 50, 50, 50, 50, 50, 50, 50,
          0, 0, 0, 0, 0, 0, 0, 0],
    "n": [-50, -40, -30, -30, -30, -30, -40, -50,
          -40, -20, 0, 5, 5, 0, -20, -40,
          -30, 5, 10, 15, 15, 10, 5, -30,
          -30, 0, 15, 20, 20, 15, 0, -30,
          -30, 5, 15, 20, 20, 15, 5, -30,
          -30, 0, 10, 15, 15, 10, 0, -30,
          -40, -20, 0, 0, 0, 0, -20, -40,
          -50, -40, -30, -30, -30, -30, -40, -50],
    "b": [-20, -10, -10, -10, -10, -10, -10, -20,
          -10, 5, 0, 0, 0, 0, 5, -10,
          -10, 10, 10, 10, 10, 10, 10, -10,
          -10, 0, 10, 10, 10, 10, 0, -10,
          -10, 5, 5, 10, 10, 5, 5, -10,
          -10, 0, 5, 10, 10, 5, 0, -10,
          -10, 0, 0, 0, 0, 0, 0, -10,
          -20, -10, -10, -10, -10, -10, -10, -20],
    "r": [0, 0, 0, 5, 5, 0, 0, 0,
          -5, 0, 0, 0, 0, 0, 0, -5,
          -5, 0, 0, 0, 0, 0, 0, -5,
          -5, 0, 0, 0, 0, 0, 0, -5,
          -5, 0, 0, 0, 0, 0, 0, -5,
          -5, 0, 0, 0, 0, 0, 0, -5,
          5, 10, 10, 10, 10, 10, 10, 5,
          0, 0, 0, 0, 0, 0, 0, 0],
    "q": [-20, -10, -10, -5, -5, -10, -10, -20,
          -10, 0, 5, 0, 0, 0, 0, -10,
          -10, 5, 5, 5, 5, 5, 0, -10,
          0, 0, 5, 5, 5, 5, 0, -5,
          -5, 0, 5, 5, 5, 5, 0, -5,
          -10, 0, 5, 5, 5, 5, 0, -10,
          -10, 0, 0, 0, 0, 0, 0, -10,
          -20, -10, -10, -5, -5, -10, -10, -20],
    "k": [20, 30, 10, 0, 0, 10, 30, 20,
          20, 20, 0, 0, 0, 0, 20, 20,
          -10, -20, -20, -20, -20, -20, -20, -10,
          -20, -30, -30, -40, -40, -30, -30, -20,
          -30, -40, -40, -50, -50, -40, -40, -30,
          -30, -40, -40, -50, -50, -40, -40, -30,
          -30, -40, -40, -50, -50, -40, -40, -30,
          -30, -40, -40, -50, -50, -40, -40, -30],
    "k_end": [-50, -30, -30, -30, -30, -30, -30, -50,
              -30, -30, 0, 0, 0, 0, -30, -30,
              -30, -10, 20, 30, 30, 20, -10, -30,
              -30, -10, 30, 40, 40, 30, -10, -30,
              -30, -10, 30, 40, 40, 30, -10, -30,
              -30, -10, 20, 30, 30, 20, -10, -30,
              -30, -20, -10, 0, 0, -10, -20, -30,
              -50, -40, -30, -20, -20, -30, -40, -50],
}
MATE = 100000


def colour(piece):
    if piece == ".":
        return None
    return WHITE if piece.isupper() else BLACK


def other(side):
    return BLACK if side == WHITE else WHITE


def name(square):
    return FILES[square % 8] + str(square // 8 + 1)


def square(text):
    return (int(text[1]) - 1) * 8 + FILES.index(text[0])


class Position:
    __slots__ = ("board", "turn", "castling", "ep", "halfmove", "fullmove")

    def __init__(self, board=START, turn=WHITE, castling="KQkq", ep=None, halfmove=0, fullmove=1):
        self.board = list(board)
        self.turn = turn
        self.castling = castling
        self.ep = ep
        self.halfmove = halfmove
        self.fullmove = fullmove

    def key(self):
        """What makes two positions the same, for counting repetitions."""
        return ("".join(self.board), self.turn, self.castling, self.ep)

    def to_dict(self):
        return {"board": "".join(self.board), "turn": self.turn, "castling": self.castling,
                "ep": self.ep, "halfmove": self.halfmove, "fullmove": self.fullmove}

    @classmethod
    def from_dict(cls, data):
        return cls(data["board"], data["turn"], data["castling"], data.get("ep"),
                   data.get("halfmove", 0), data.get("fullmove", 1))

    def king(self, side):
        return self.board.index("K" if side == WHITE else "k")

    def attacked(self, sq, by):
        """Whether side `by` attacks square sq."""
        b = self.board
        f, r = sq % 8, sq // 8
        # Pawns
        dr = -1 if by == WHITE else 1
        pawn = "P" if by == WHITE else "p"
        for df in (-1, 1):
            ff, rr = f + df, r + dr
            if 0 <= ff < 8 and 0 <= rr < 8 and b[rr * 8 + ff] == pawn:
                return True
        knight, king = ("N", "K") if by == WHITE else ("n", "k")
        for df, dr in KNIGHT:
            ff, rr = f + df, r + dr
            if 0 <= ff < 8 and 0 <= rr < 8 and b[rr * 8 + ff] == knight:
                return True
        for df, dr in KING:
            ff, rr = f + df, r + dr
            if 0 <= ff < 8 and 0 <= rr < 8 and b[rr * 8 + ff] == king:
                return True
        straight = ("R", "Q") if by == WHITE else ("r", "q")
        diagonal = ("B", "Q") if by == WHITE else ("b", "q")
        for dirs, sliders in ((ROOK_DIRS, straight), (BISHOP_DIRS, diagonal)):
            for df, dr in dirs:
                ff, rr = f + df, r + dr
                while 0 <= ff < 8 and 0 <= rr < 8:
                    piece = b[rr * 8 + ff]
                    if piece != ".":
                        if piece in sliders:
                            return True
                        break
                    ff += df
                    rr += dr
        return False

    def in_check(self, side=None):
        side = side or self.turn
        return self.attacked(self.king(side), other(side))

    def pseudo_moves(self, captures_only=False):
        b = self.board
        side = self.turn
        moves = []
        for sq in range(64):
            piece = b[sq]
            if piece == "." or colour(piece) != side:
                continue
            kind = piece.lower()
            f, r = sq % 8, sq // 8
            if kind == "p":
                step = 8 if side == WHITE else -8
                start_rank, last_rank = (1, 7) if side == WHITE else (6, 0)
                to = sq + step
                if not captures_only and 0 <= to < 64 and b[to] == ".":
                    if to // 8 == last_rank:
                        moves.extend((sq, to, p) for p in "qrbn")
                    else:
                        moves.append((sq, to, None))
                        if r == start_rank and b[to + step] == ".":
                            moves.append((sq, to + step, None))
                for df in (-1, 1):
                    ff = f + df
                    if not 0 <= ff < 8:
                        continue
                    to = sq + step + df
                    if not 0 <= to < 64:
                        continue
                    target = b[to]
                    if (target != "." and colour(target) != side) or to == self.ep:
                        if to // 8 == last_rank:
                            moves.extend((sq, to, p) for p in "qrbn")
                        else:
                            moves.append((sq, to, None))
            elif kind in ("n", "k"):
                for df, dr in (KNIGHT if kind == "n" else KING):
                    ff, rr = f + df, r + dr
                    if 0 <= ff < 8 and 0 <= rr < 8:
                        to = rr * 8 + ff
                        target = b[to]
                        if target == ".":
                            if not captures_only:
                                moves.append((sq, to, None))
                        elif colour(target) != side:
                            moves.append((sq, to, None))
                if kind == "k" and not captures_only:
                    moves.extend(self._castles(sq))
            else:
                dirs = ROOK_DIRS if kind == "r" else BISHOP_DIRS if kind == "b" else ROOK_DIRS + BISHOP_DIRS
                for df, dr in dirs:
                    ff, rr = f + df, r + dr
                    while 0 <= ff < 8 and 0 <= rr < 8:
                        to = rr * 8 + ff
                        target = b[to]
                        if target == ".":
                            if not captures_only:
                                moves.append((sq, to, None))
                        else:
                            if colour(target) != side:
                                moves.append((sq, to, None))
                            break
                        ff += df
                        rr += dr
        return moves

    def _castles(self, sq):
        b = self.board
        side = self.turn
        home = 4 if side == WHITE else 60
        if sq != home:
            return []
        rights = ("K", "Q") if side == WHITE else ("k", "q")
        enemy = other(side)
        found = []
        if rights[0] in self.castling and b[home + 1] == b[home + 2] == "." \
                and not any(self.attacked(s, enemy) for s in (home, home + 1, home + 2)):
            found.append((home, home + 2, None))
        if rights[1] in self.castling and b[home - 1] == b[home - 2] == b[home - 3] == "." \
                and not any(self.attacked(s, enemy) for s in (home, home - 1, home - 2)):
            found.append((home, home - 2, None))
        return found

    def play(self, move):
        """A new position with the move made."""
        frm, to, promo = move
        b = list(self.board)
        piece = b[frm]
        captured = b[to]
        kind = piece.lower()
        side = self.turn
        new = Position.__new__(Position)
        new.board = b
        new.turn = other(side)
        new.ep = None
        b[to] = piece
        b[frm] = "."
        if kind == "p":
            if to == self.ep:
                b[to - 8 if side == WHITE else to + 8] = "."
                captured = "p"
            if abs(to - frm) == 16:
                new.ep = (frm + to) // 2
            if promo:
                b[to] = promo.upper() if side == WHITE else promo
        elif kind == "k" and abs(to - frm) == 2:
            if to > frm:
                b[frm + 1], b[frm + 3] = b[frm + 3], "."
            else:
                b[frm - 1], b[frm - 4] = b[frm - 4], "."
        castling = self.castling
        if castling:
            for sq, lose in ((4, "KQ"), (60, "kq"), (0, "Q"), (7, "K"), (56, "q"), (63, "k")):
                if frm == sq or to == sq:
                    castling = "".join(c for c in castling if c not in lose)
        new.castling = castling
        new.halfmove = 0 if kind == "p" or captured != "." else self.halfmove + 1
        new.fullmove = self.fullmove + (1 if side == BLACK else 0)
        return new

    def legal_moves(self):
        side = self.turn
        legal = []
        for move in self.pseudo_moves():
            after = self.play(move)
            if not after.attacked(after.king(side), other(side)):
                legal.append(move)
        return legal

    def insufficient(self):
        pieces = [p for p in self.board if p not in ".Kk"]
        if not pieces:
            return True
        if len(pieces) == 1 and pieces[0].lower() in "nb":
            return True
        return False

    def san(self, move, legal=None):
        """A move written the usual way, like Nf3, exd5, O-O or e8=Q+."""
        frm, to, promo = move
        piece = self.board[frm]
        kind = piece.lower()
        legal = legal if legal is not None else self.legal_moves()
        if kind == "k" and abs(to - frm) == 2:
            text = "O-O" if to > frm else "O-O-O"
        else:
            capture = self.board[to] != "." or (kind == "p" and to == self.ep)
            if kind == "p":
                text = (FILES[frm % 8] + "x" if capture else "") + name(to)
                if promo:
                    text += "=" + promo.upper()
            else:
                text = kind.upper()
                rivals = [m for m in legal if m[1] == to and m[0] != frm and self.board[m[0]] == piece]
                if rivals:
                    if all(m[0] % 8 != frm % 8 for m in rivals):
                        text += FILES[frm % 8]
                    elif all(m[0] // 8 != frm // 8 for m in rivals):
                        text += str(frm // 8 + 1)
                    else:
                        text += name(frm)
                text += ("x" if capture else "") + name(to)
        after = self.play(move)
        if after.in_check():
            text += "#" if not after.legal_moves() else "+"
        return text


# -- the computer player --

def evaluate(pos):
    """The score from the side to move's point of view."""
    b = pos.board
    score = 0
    material = 0
    for p in b:
        if p != "." and p.lower() != "p" and p.lower() != "k":
            material += VALUE[p.lower()]
    endgame = material <= 1300
    for sq, p in enumerate(b):
        if p == ".":
            continue
        kind = p.lower()
        table = PST["k_end"] if kind == "k" and endgame else PST[kind]
        if p.isupper():
            score += VALUE[kind] + table[sq]
        else:
            score -= VALUE[kind] + table[(7 - sq // 8) * 8 + sq % 8]
    return score if pos.turn == WHITE else -score


class OutOfTime(Exception):
    pass


class Searcher:
    def __init__(self, deadline=None):
        self.deadline = deadline
        self.nodes = 0

    def _order(self, pos, moves, best=None):
        b = pos.board

        def weight(m):
            if m == best:
                return -100000
            target = b[m[1]]
            w = 0
            if target != ".":
                w -= 10 * VALUE[target.lower()] - VALUE[b[m[0]].lower()]
            if m[2] == "q":
                w -= 800
            return w
        return sorted(moves, key=weight)

    def quiesce(self, pos, alpha, beta, depth=0):
        self.nodes += 1
        stand = evaluate(pos)
        if stand >= beta:
            return beta
        if alpha < stand:
            alpha = stand
        if depth > 6:
            return alpha
        side = pos.turn
        for move in self._order(pos, pos.pseudo_moves(captures_only=True)):
            after = pos.play(move)
            if after.attacked(after.king(side), other(side)):
                continue
            score = -self.quiesce(after, -beta, -alpha, depth + 1)
            if score >= beta:
                return beta
            if score > alpha:
                alpha = score
        return alpha

    def negamax(self, pos, depth, alpha, beta, ply):
        self.nodes += 1
        if self.deadline and self.nodes % 256 == 0 and time.monotonic() > self.deadline:
            raise OutOfTime()
        if pos.halfmove >= 100:
            return 0
        if depth <= 0:
            return self.quiesce(pos, alpha, beta)
        side = pos.turn
        any_legal = False
        for move in self._order(pos, pos.pseudo_moves()):
            after = pos.play(move)
            if after.attacked(after.king(side), other(side)):
                continue
            any_legal = True
            score = -self.negamax(after, depth - 1, -beta, -alpha, ply + 1)
            if score >= beta:
                return beta
            if score > alpha:
                alpha = score
        if not any_legal:
            return -MATE + ply if pos.in_check() else 0
        return alpha

    def root(self, pos, depth, moves, best=None):
        """Every move's score at this depth, best first."""
        scored = []
        for move in self._order(pos, moves, best):
            score = -self.negamax(pos.play(move), depth - 1, -MATE - 1, MATE + 1, 1)
            scored.append((score, move))
        scored.sort(key=lambda s: -s[0])
        return scored


LEVELS = {  # depth, seconds, how far off the best a move may be and still be picked
    "easy": (1, 1.0, 180),
    "medium": (2, 2.0, 25),
    "hard": (4, 4.0, 0),
}


def best_move(pos, level="medium", history=()):
    """The computer's choice, or None if there's no legal move."""
    moves = pos.legal_moves()
    if not moves:
        return None
    depth, seconds, slack = LEVELS.get(level, LEVELS["medium"])
    searcher = Searcher(time.monotonic() + seconds)
    scored = [(0, m) for m in moves]
    best = None
    for d in range(1, depth + 1):
        try:
            scored = searcher.root(pos, d, moves, best)
        except OutOfTime:
            break
        best = scored[0][1]
        if scored[0][0] >= MATE - 100:
            break
    # Stay away from repeating a position if there's anything about as good.
    seen = set(history)
    top = scored[0][0]
    choices = [m for s, m in scored if s >= top - slack and pos.play(m).key() not in seen] or \
              [m for s, m in scored if s >= top - slack]
    if level == "easy" and random.random() < 0.15:
        return random.choice(moves)
    return random.choice(choices)


def hint(pos):
    """A good move for whoever's turn it is."""
    moves = pos.legal_moves()
    if not moves:
        return None
    searcher = Searcher(time.monotonic() + 2.0)
    best = moves[0]
    for d in (1, 2, 3):
        try:
            best = searcher.root(pos, d, moves, best)[0][1]
        except OutOfTime:
            break
    return best


def perft(pos, depth):
    """How many move sequences there are, for checking the rules are right."""
    if depth == 0:
        return 1
    return sum(perft(pos.play(m), depth - 1) for m in pos.legal_moves())
