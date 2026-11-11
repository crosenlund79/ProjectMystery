"""Beliefs: what a resident thinks happened, with provenance.

A belief is never the truth itself. It points back to the event or source belief it
came from (``event``/``via``/``premises``) so that every claim can be audited, and it
records whether it was distorted on the way (``error``, developer-only).
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field

SOURCE_RANK = {"self": 5, "saw": 4, "heard": 3, "told": 2, "inferred": 1}

SALIENCE = {
    "presence": 0.12, "sighting": 0.3, "purchase": 0.2, "intoxicated": 0.3, "noise": 0.55,
    "loan": 0.6, "refusal": 0.6, "hardship": 0.5, "debt": 0.9, "grudge": 0.9, "argument": 0.65,
    "assault": 0.95, "loss": 0.95, "damage": 0.8, "vehicle_damage": 0.7, "injury": 0.85,
    "struck": 0.95, "fall": 0.9, "death": 1.0, "suspect": 0.75, "repair": 0.6, "theft_self": 1.0,
    "collision_self": 1.0, "drove": 0.35, "help": 0.5, "laid_off": 0.9, "confession": 1.0,
    "stash": 1.0, "treated": 0.6, "rent_missed": 0.6, "missing": 0.9,
}

# Claim kinds worth passing on in conversation.
GOSSIP_KINDS = {
    "loss", "damage", "injury", "death", "argument", "assault", "debt", "hardship", "refusal",
    "suspect", "laid_off", "confession", "vehicle_damage", "grudge", "rent_missed", "struck", "missing",
}
INCIDENT_KINDS = {"loss", "damage", "injury", "death", "struck", "fall"}


@dataclass
class Claim:
    kind: str
    subject: str | None = None  # resident id; None means unidentified
    other: str | None = None
    location: str | None = None
    start: int | None = None
    end: int | None = None
    detail: str = ""
    amount: int | None = None
    obj: str | None = None
    hedged: bool = False  # the holder is unsure about the identity of `subject`

    def key(self) -> tuple:
        start = None if self.start is None else self.start // 60
        return (self.kind, self.subject, self.other, self.location, start, self.detail, self.obj)

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class Belief:
    id: str
    holder: str
    claim: Claim
    source: str  # self | saw | heard | told | inferred
    acquired: int
    confidence: float
    salience: float
    event: str | None = None  # truth link (dev-only)
    told_by: str | None = None
    via: str | None = None  # source belief id when told
    premises: list[str] = field(default_factory=list)
    error: str | None = None  # dev-only: misidentified | distorted | mistaken_inference ...
    told_to: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["claim"] = self.claim.to_dict()
        return d


class Memory:
    def __init__(self, holder: str):
        self.holder = holder
        self.beliefs: list[Belief] = []
        self.by_key: dict[tuple, Belief] = {}
        self.by_kind: dict[str, list[Belief]] = {}
        self.open_presence: dict[tuple[str, str], Belief] = {}

    def add(self, belief: Belief) -> None:
        self.beliefs.append(belief)
        self.by_key[belief.claim.key()] = belief
        self.by_kind.setdefault(belief.claim.kind, []).append(belief)

    def find(self, claim: Claim) -> Belief | None:
        return self.by_key.get(claim.key())

    def of_kind(self, *kinds: str, since: int | None = None) -> list[Belief]:
        out = []
        for kind in kinds:
            out.extend(b for b in self.by_kind.get(kind, ()) if since is None or b.acquired >= since)
        if len(kinds) > 1:
            out.sort(key=lambda b: b.id)
        return out


def retention_days(salience: float) -> float:
    if salience >= 0.9:
        return 10_000.0
    return 1.5 + salience * 25.0


def recall(belief: Belief, now: int, anchors: list[tuple[int, int]]) -> tuple[bool, float]:
    """Is a belief still remembered at ``now``, and with what confidence?

    ``anchors`` are time windows the holder has reason to rehearse (an incident they
    know about); memories inside them are kept as if they were salient.
    """
    sal = belief.salience
    when = belief.claim.start if belief.claim.start is not None else belief.acquired
    for a, b in anchors:
        if a - 8 * 60 <= when <= b + 8 * 60:
            sal = max(sal, 0.75)
            break
    age_days = max(0.0, (now - belief.acquired) / 1440.0)
    if age_days > retention_days(sal):
        return False, 0.0
    conf = belief.confidence * max(0.35, 1.0 - age_days * 0.06 * (1.0 - sal))
    return True, round(conf, 3)
