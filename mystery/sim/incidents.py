"""Noteworthy incidents: detection, classification and case hooks.

An incident is registered when its core event happens (a theft, a collision...). It
only becomes a *case candidate* once somebody in town actually notices it.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field

from mystery.sim.clock import DAY, hour_of

MECHANISMS = {
    "theft": "stolen",
    "accounting_error": "accounting_error",
    "assault": "assaulted",
    "fall": "accidental_fall",
}

MECHANISM_LABELS = {
    "stolen": "stolen by someone",
    "accounting_error": "a bookkeeping mistake (nothing was taken)",
    "assaulted": "attacked by someone",
    "struck_by_vehicle": "struck by a vehicle",
    "vehicle_collision": "a vehicle crashed into it",
    "accidental_fall": "an accidental fall",
    "vandalism": "deliberate vandalism",
    "unresolved": "cannot be determined from the evidence",
}

HOOK_MECHANISMS = {
    "money_missing": ["stolen", "accounting_error", "unresolved"],
    "goods_missing": ["stolen", "accounting_error", "unresolved"],
    "person_injured": ["assaulted", "struck_by_vehicle", "accidental_fall", "unresolved"],
    "person_dead": ["assaulted", "struck_by_vehicle", "accidental_fall", "unresolved"],
    "property_damaged": ["vehicle_collision", "vandalism", "unresolved"],
}

MOTIVES = {
    "money_trouble": "money trouble",
    "grudge": "anger or an old grudge",
    "intoxication": "drink clouded their judgement",
    "panic": "panic and fear of being found out",
    "none": "no one intended harm",
    "unknown": "unknown",
}


@dataclass
class Incident:
    id: str
    family: str  # theft | accounting_error | assault | collision | fall
    core_event: str
    time: int
    location: str
    responsible: str | None
    victims: list[str]
    intent: str
    mechanism: str
    outcome: str  # crime | accident | no_crime
    severity: int
    hook_kind: str
    motive: str
    related_events: list[str] = field(default_factory=list)
    discovered_at: int | None = None
    discovered_by: str | None = None
    discovery_event: str | None = None
    window: list[int] | None = None
    hook_place: str | None = None
    hook_text: str = ""
    title: str = ""
    reported_openly: bool = False
    fled: bool = False
    case_start: int | None = None

    def to_dict(self) -> dict:
        return asdict(self)

    @property
    def is_candidate(self) -> bool:
        return self.discovered_at is not None and not self.reported_openly


def case_start_for(discovered_at: int) -> int:
    """The investigator arrives an hour or two after discovery; never in the dead of night."""
    nxt = (discovered_at // 60 + 1) * 60 + 60
    h = hour_of(nxt)
    if h >= 22 or h < 7:
        day_start = (nxt // DAY) * DAY
        nxt = day_start + 8 * 60 if h < 7 else day_start + DAY + 8 * 60
    return nxt
