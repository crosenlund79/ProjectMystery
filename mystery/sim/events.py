"""The canonical, append-only record of what actually happened."""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass, field


@dataclass
class Event:
    id: str
    time: int
    location: str
    kind: str
    actors: list[str]
    targets: list[str] = field(default_factory=list)
    objects: list[str] = field(default_factory=list)
    data: dict = field(default_factory=dict)
    causes: list[str] = field(default_factory=list)
    intent: str | None = None  # intentional | impulsive | reckless | accidental | lawful | None
    audibility: int = 0  # 0 silent, 1 same place, 2 neighbours, 3 two places away
    discreet: bool = False
    notable: bool = False
    summary: str = ""

    def to_dict(self) -> dict:
        return asdict(self)

    def involves(self, rid: str) -> bool:
        return rid in self.actors or rid in self.targets


class EventLog:
    def __init__(self) -> None:
        self.events: list[Event] = []
        self.by_id: dict[str, Event] = {}

    def next_id(self) -> str:
        return f"E{len(self.events) + 1:06d}"

    def add(self, ev: Event) -> Event:
        self.events.append(ev)
        self.by_id[ev.id] = ev
        return ev

    def __len__(self) -> int:
        return len(self.events)

    def until(self, t: int) -> list[Event]:
        return [e for e in self.events if e.time <= t]

    def digest(self, until: int | None = None) -> str:
        h = hashlib.sha256()
        for ev in self.events:
            if until is not None and ev.time > until:
                continue
            h.update(json.dumps(ev.to_dict(), sort_keys=True).encode("utf-8"))
            h.update(b"\n")
        return h.hexdigest()

    def ancestors(self, event_id: str, depth: int = 6) -> list[str]:
        seen: list[str] = []
        frontier = [event_id]
        for _ in range(depth):
            nxt: list[str] = []
            for eid in frontier:
                ev = self.by_id.get(eid)
                if ev is None:
                    continue
                for c in ev.causes:
                    if c not in seen and c != event_id:
                        seen.append(c)
                        nxt.append(c)
            frontier = nxt
        return seen

    def consequences(self, event_id: str, until: int, depth: int = 3) -> list[str]:
        found: list[str] = []
        frontier = {event_id}
        for _ in range(depth):
            nxt = set()
            for ev in self.events:
                if ev.time > until or ev.id in found or ev.id == event_id:
                    continue
                if any(c in frontier for c in ev.causes):
                    found.append(ev.id)
                    nxt.add(ev.id)
            if not nxt:
                break
            frontier = nxt
        return found
