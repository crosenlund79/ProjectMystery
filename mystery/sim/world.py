"""Places, containers, vehicles, records, physical evidence and money/goods accounting."""

from __future__ import annotations

from collections import deque
from dataclasses import asdict, dataclass, field


@dataclass
class Location:
    id: str
    name: str
    kind: str  # square | road | shop | pub | workshop | clinic | mill | home
    outdoor: bool = False
    hours: tuple[int, int] | None = None  # opening hours [open, close)
    owners: list[str] = field(default_factory=list)
    staff: list[str] = field(default_factory=list)
    household: str | None = None
    lockable: bool = False
    locked: bool = False
    adj: dict[str, int] = field(default_factory=dict)  # neighbour -> walking minutes

    def is_open(self, hour: int) -> bool:
        if self.hours is None:
            return True
        start, end = self.hours
        return start <= hour < end


@dataclass
class Container:
    """Anything holding cash or food: tills, home savings boxes, pantries, stashes."""

    id: str
    location: str
    label: str
    owners: list[str]
    cash: int = 0
    food: int = 0
    hidden: bool = False
    expected_cash: int = 0  # what the owners believe is inside
    expected_food: int = 0
    last_check: int = 0
    unexplained: list[str] = field(default_factory=list)  # truth: events that changed it unseen


@dataclass
class Vehicle:
    id: str
    name: str
    kind: str  # truck | car
    household: str
    location: str
    damage: str | None = None
    damage_evidence: str | None = None
    damage_event: str | None = None


@dataclass
class RecordEntry:
    id: str
    book: str
    time: int
    text: str
    event_id: str  # truth link; never exported to the player view


@dataclass
class Evidence:
    """A physical trace. It exists only because a world event created it."""

    id: str
    kind: str
    place: str  # location id or vehicle id
    description: str
    created_at: int
    created_by: str  # event id
    removed_at: int | None = None
    removed_by: str | None = None
    implicates: list[str] = field(default_factory=list)  # dev-only
    noticed_by: list[str] = field(default_factory=list)
    glimpse: str = ""  # how a passer-by would describe it in a sentence

    def present_at(self, t: int) -> bool:
        return self.created_at <= t and (self.removed_at is None or t < self.removed_at)


@dataclass
class Transfer:
    time: int
    event_id: str
    asset: str  # cash | food
    src: str  # account id
    dst: str
    amount: int


@dataclass
class Debt:
    id: str
    debtor: str
    creditor: str
    amount: int
    due: int
    created: int
    origin_event: str
    kind: str = "loan"  # loan | credit | rent
    settled: int | None = None
    settled_event: str | None = None
    overdue_event: str | None = None

    def open_at(self, t: int) -> bool:
        return self.created <= t and (self.settled is None or t < self.settled)


class World:
    def __init__(self, town_name: str, pub_name: str):
        self.town_name = town_name
        self.pub_name = pub_name
        self.locations: dict[str, Location] = {}
        self.containers: dict[str, Container] = {}
        self.vehicles: dict[str, Vehicle] = {}
        self.books: dict[str, dict] = {}
        self.records: dict[str, list[RecordEntry]] = {}
        self.evidence: list[Evidence] = []
        self.transfers: list[Transfer] = []
        self.debts: list[Debt] = []
        self._paths: dict[tuple[str, str], list[str]] = {}
        self._hops: dict[str, dict[str, int]] = {}

    # ---- graph -------------------------------------------------------
    def add_location(self, loc: Location) -> None:
        self.locations[loc.id] = loc

    def connect(self, a: str, b: str, minutes: int) -> None:
        self.locations[a].adj[b] = minutes
        self.locations[b].adj[a] = minutes

    def path(self, a: str, b: str) -> list[str]:
        key = (a, b)
        if key not in self._paths:
            prev: dict[str, str | None] = {a: None}
            queue = deque([a])
            while queue:
                cur = queue.popleft()
                if cur == b:
                    break
                for nxt in sorted(self.locations[cur].adj):
                    if nxt not in prev:
                        prev[nxt] = cur
                        queue.append(nxt)
            nodes = [b]
            while prev[nodes[-1]] is not None:
                nodes.append(prev[nodes[-1]])  # type: ignore[arg-type]
            self._paths[key] = list(reversed(nodes))
        return self._paths[key]

    def hops(self, a: str, b: str) -> int:
        if a not in self._hops:
            dist = {a: 0}
            queue = deque([a])
            while queue:
                cur = queue.popleft()
                for nxt in sorted(self.locations[cur].adj):
                    if nxt not in dist:
                        dist[nxt] = dist[cur] + 1
                        queue.append(nxt)
            self._hops[a] = dist
        return self._hops[a].get(b, 99)

    def name(self, loc_id: str) -> str:
        if loc_id in self.locations:
            return self.locations[loc_id].name
        if loc_id in self.vehicles:
            return self.vehicles[loc_id].name
        return loc_id

    # ---- records and evidence ---------------------------------------
    def add_book(self, book: str, place: str, title: str) -> None:
        self.books[book] = {"place": place, "title": title}
        self.records[book] = []

    def record(self, book: str, time: int, text: str, event_id: str) -> RecordEntry:
        entry = RecordEntry(f"{book}#{len(self.records[book]) + 1}", book, time, text, event_id)
        self.records[book].append(entry)
        return entry

    def add_evidence(self, kind: str, place: str, description: str, time: int, event_id: str,
                     implicates: list[str] | None = None, glimpse: str = "") -> Evidence:
        ev = Evidence(f"X{len(self.evidence) + 1:04d}", kind, place, description, time, event_id,
                      implicates=list(implicates or []), glimpse=glimpse)
        self.evidence.append(ev)
        return ev

    def evidence_at(self, place: str, t: int) -> list[Evidence]:
        return [e for e in self.evidence if e.place == place and e.present_at(t)]

    def to_dict(self) -> dict:
        return {
            "town": self.town_name,
            "locations": {k: asdict(v) for k, v in self.locations.items()},
            "vehicles": {k: asdict(v) for k, v in self.vehicles.items()},
        }
