"""Deterministic random streams.

Never use ``hash()`` on strings for seeding (it is salted per process) and never
iterate over a ``set`` when the order can affect results. Streams are derived
from the run seed plus a label with SHA-256 so they are stable everywhere.
"""

from __future__ import annotations

import hashlib
import random


def derive_seed(*parts: object) -> int:
    text = "|".join(str(p) for p in parts)
    return int.from_bytes(hashlib.sha256(text.encode("utf-8")).digest()[:8], "big")


def stream(*parts: object) -> random.Random:
    return random.Random(derive_seed(*parts))


def clamp(x: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return lo if x < lo else hi if x > hi else x
