"""Residents and seeded town generation."""

from __future__ import annotations

from dataclasses import dataclass, field

from mystery.rng import clamp, stream
from mystery.sim.clock import DAY, at
from mystery.sim.config import PROFILES, SimConfig
from mystery.sim.world import Container, Location, Vehicle, World

FIRST_NAMES = [
    "Daniel", "Margaret", "Elias", "Ruth", "Tomas", "Agnes", "Felix", "Ida", "Oskar", "Lena",
    "Henrik", "Vera", "Anton", "Clara", "Emil", "Greta", "Jonas", "Marta", "Viktor", "Nora",
    "Arvid", "Selma", "Bruno", "Hedda",
]
SURNAMES = [
    "Harrow", "Lind", "Brandt", "Okafor", "Vale", "Morrow", "Kessler", "Dunmore", "Ash",
    "Pryce", "Holm", "Carver",
]
TOWN_NAMES = ["Kestrel Hollow", "Wyndmere", "Lowbridge", "Greyford", "Ashcombe", "Thornwick"]
PUB_NAMES = ["the Lantern", "the Crooked Pike", "the Drover's Rest", "the Grey Heron"]
GRUDGE_REASONS = [
    "a quarrel over a boundary fence",
    "an unpaid bill from last winter",
    "a broken engagement",
    "something said at the pub years ago",
    "a dog that was never returned",
]
AGE_GROUPS = ["young adult", "adult", "middle-aged", "older"]

ROLES: dict[str, dict] = {
    "grocer": {"label": "grocer", "workplace": "grocery", "shift": (8, 18), "wage": 0},
    "publican": {"label": "publican", "workplace": "pub", "shift": (11, 23), "wage": 0},
    "mechanic": {"label": "mechanic", "workplace": "workshop", "shift": (8, 17), "wage": 18},
    "nurse": {"label": "nurse", "workplace": "clinic", "shift": (9, 17), "wage": 26},
    "mill_owner": {"label": "mill owner", "workplace": "mill", "shift": (7, 16), "wage": 0},
    "mill_hand": {"label": "mill hand", "workplace": "mill", "shift": (7, 16), "wage": 22},
    "shop_assistant": {"label": "shop assistant", "workplace": "grocery", "shift": (9, 17), "wage": 18},
    "barhand": {"label": "barhand", "workplace": "pub", "shift": (17, 23), "wage": 16},
    "unemployed": {"label": "out of work", "workplace": None, "shift": None, "wage": 0},
    "retiree": {"label": "retired", "workplace": None, "shift": None, "wage": 0},
}
ROLE_SEQUENCE = [
    "grocer", "publican", "mechanic", "nurse", "mill_owner", "mill_hand", "mill_hand",
    "unemployed", "shop_assistant", "barhand", "retiree", "mill_hand",
]
START_CASH = {
    "grocer": (60, 120), "publican": (60, 120), "mechanic": (40, 100), "nurse": (50, 110),
    "mill_owner": (120, 250), "mill_hand": (20, 70), "shop_assistant": (20, 60),
    "barhand": (15, 50), "unemployed": (5, 30), "retiree": (30, 80),
}


@dataclass
class Traits:
    impulsiveness: float
    caution: float
    empathy: float
    honesty: float
    sociability: float
    stubbornness: float
    temperance: float
    diligence: float


@dataclass
class Relationship:
    trust: float = 0.5
    affection: float = 0.4
    resentment: float = 0.0


@dataclass
class Resident:
    id: str
    first: str
    last: str
    age_group: str
    role: str
    occupation: str
    household: str
    home: str
    workplace: str | None
    shift: tuple[int, int] | None
    wage: int
    traits: Traits
    cash: int = 0
    hunger: float = 25.0
    energy: float = 85.0
    social: float = 60.0
    stress: float = 10.0
    intox: float = 0.0
    injury: int = 0  # 0 none, 1 minor, 2 serious
    injury_event: str | None = None
    injury_desc: str = ""
    injury_treated: bool = True
    down: bool = False  # lying injured, unable to move
    alive: bool = True
    death_event: str | None = None
    asleep: bool = True
    employed: bool = True
    rel: dict[str, Relationship] = field(default_factory=dict)
    vehicle: str | None = None
    pressures: list[tuple[int, str]] = field(default_factory=list)  # (time, event id)
    guilty_of: list[str] = field(default_factory=list)  # event ids of own wrongdoing
    cooldowns: dict[str, int] = field(default_factory=dict)
    worked_today: bool = False
    pending_hide: list[str] = field(default_factory=list)  # theft events not yet hidden at home
    wants_repair: bool = False

    @property
    def name(self) -> str:
        return f"{self.first} {self.last}"

    def r(self, other: str) -> Relationship:
        if other not in self.rel:
            self.rel[other] = Relationship()
        return self.rel[other]

    def recent_pressures(self, now: int, window: int = 7 * DAY) -> list[str]:
        return [eid for (t, eid) in self.pressures if now - t <= window][-4:]


def _trait(rng) -> float:
    return round(clamp(rng.betavariate(2.2, 2.2)), 3)


def generate_town(cfg: SimConfig) -> tuple[World, dict[str, Resident], dict]:
    """Build a seeded town. Returns (world, residents, meta)."""
    rng = stream(cfg.seed, "town", cfg.profile, cfg.residents)
    prof = PROFILES[cfg.profile]
    n = cfg.residents
    world = World(rng.choice(TOWN_NAMES), rng.choice(PUB_NAMES))

    def loc(id_: str, name: str, kind: str, **kw) -> None:
        world.add_location(Location(id_, name, kind, **kw))

    loc("square", "the square", "square", outdoor=True)
    loc("road", "Mill Road", "road", outdoor=True)
    loc("grocery", "the grocery", "shop", hours=(8, 18), lockable=True)
    loc("pub", world.pub_name, "pub", hours=(11, 23), lockable=True)
    loc("workshop", "the workshop", "workshop", hours=(8, 17), lockable=True)
    loc("clinic", "the clinic", "clinic", hours=(9, 17), lockable=True)
    loc("mill", "the mill", "mill", hours=(7, 16), lockable=True)
    for place, minutes in (("grocery", 2), ("pub", 2), ("workshop", 3), ("clinic", 3), ("road", 6)):
        world.connect("square", place, minutes)
    world.connect("road", "mill", 6)

    roles = ROLE_SEQUENCE[:n]
    firsts = rng.sample(FIRST_NAMES, n)
    order = list(range(n))
    rng.shuffle(order)
    groups: list[list[int]] = []
    i = 0
    while i < n:
        size = 2 if (n - i >= 2 and rng.random() < 0.45) else 1
        groups.append(order[i:i + size])
        i += size
    surnames = rng.sample(SURNAMES, len(groups))

    residents: dict[str, Resident] = {}
    households: dict[str, list[str]] = {}
    for gi, members in enumerate(groups):
        surname = surnames[gi]
        hid = surname.lower()
        home = f"home:{hid}"
        outskirts = gi % 2 == 1
        loc(home, f"the {surname} house", "home", household=hid, lockable=True)
        world.connect("road" if outskirts else "square", home, 5 if outskirts else 4)
        households[hid] = []
        for idx in members:
            role = roles[idx]
            info = ROLES[role]
            t = Traits(*(_trait(rng) for _ in range(8)))
            t.temperance = round(clamp(t.temperance - (prof.drink_mult - 1.0) * 0.35), 3)
            t.impulsiveness = round(clamp(t.impulsiveness + prof.impulsive_shift), 3)
            if role == "nurse":
                t.empathy = round(clamp(t.empathy + 0.2), 3)
            if role == "publican":
                t.sociability = round(clamp(t.sociability + 0.2), 3)
            lo, hi = START_CASH[role]
            rid = firsts[idx].lower()
            r = Resident(
                id=rid, first=firsts[idx], last=surname, age_group=rng.choice(AGE_GROUPS) if role != "retiree" else "older",
                role=role, occupation=info["label"], household=hid, home=home, workplace=info["workplace"],
                shift=info["shift"], wage=int(round(info["wage"] * prof.wage_mult)), traits=t,
                cash=rng.randint(lo, hi), employed=info["workplace"] is not None,
                hunger=rng.uniform(10, 40), energy=rng.uniform(70, 95), social=rng.uniform(40, 80),
            )
            residents[rid] = r
            households[hid].append(rid)

    by_role = {}
    for rid in sorted(residents):
        by_role.setdefault(residents[rid].role, []).append(rid)

    def staff(place: str) -> list[str]:
        return [rid for rid in sorted(residents) if residents[rid].workplace == place]

    for place, owner_role in (("grocery", "grocer"), ("pub", "publican"), ("workshop", "mechanic"),
                              ("clinic", "nurse"), ("mill", "mill_owner")):
        world.locations[place].owners = list(by_role.get(owner_role, []))
        world.locations[place].staff = staff(place)
    for hid, members in households.items():
        world.locations[f"home:{hid}"].owners = list(members)

    def container(cid: str, location: str, label: str, owners: list[str], cash: int = 0, food: int = 0, **kw) -> None:
        world.containers[cid] = Container(cid, location, label, owners, cash=cash, food=food,
                                          expected_cash=cash, expected_food=food, **kw)

    container("till:grocery", "grocery", "the grocery till", by_role["grocer"], cash=rng.randint(60, 120))
    container("stock:grocery", "grocery", "the grocery stock room", by_role["grocer"], food=160)
    container("till:pub", "pub", f"the till at {world.pub_name}", by_role["publican"], cash=rng.randint(80, 150))
    container("cashbox:mill", "mill", "the mill cashbox", by_role["mill_owner"], cash=400)
    for hid, members in households.items():
        container(f"box:{hid}", f"home:{hid}", f"the {residents[members[0]].last} household savings tin",
                  list(members), cash=rng.randint(20, 150))
        container(f"pantry:{hid}", f"home:{hid}", f"the {residents[members[0]].last} pantry", list(members),
                  food=rng.randint(6, 14))

    world.add_book("ledger", "grocery", "Grocery sales ledger")
    world.add_book("tabs", "pub", f"Bar tab book at {world.pub_name}")
    world.add_book("clinic_log", "clinic", "Clinic patient log")
    world.add_book("workshop_orders", "workshop", "Workshop job book")

    def give_vehicle(vid: str, name: str, kind: str, hid: str) -> None:
        world.vehicles[vid] = Vehicle(vid, name, kind, hid, world.locations[f"home:{hid}"].id)
        for rid in households[hid]:
            residents[rid].vehicle = vid

    mech = residents[by_role["mechanic"][0]]
    give_vehicle("truck", "the rust-red workshop truck", "truck", mech.household)
    owner = residents[by_role["mill_owner"][0]]
    if owner.household != mech.household:
        give_vehicle("saloon", "the grey saloon car", "car", owner.household)
    if n >= 10:
        for hid in sorted(households):
            home = world.locations[f"home:{hid}"]
            if "road" in home.adj and residents[households[hid][0]].vehicle is None:
                give_vehicle("hatchback", "the old blue hatchback", "car", hid)
                break

    # relationships
    ids = sorted(residents)
    for a in ids:
        for b in ids:
            if a == b:
                continue
            ra, rb = residents[a], residents[b]
            rel = ra.r(b)
            if ra.household == rb.household:
                rel.trust, rel.affection = 0.85, 0.8
            else:
                rel.trust = round(rng.uniform(0.35, 0.7), 3)
                rel.affection = round(rng.uniform(0.2, 0.6), 3)
                rel.resentment = round(rng.uniform(0.0, 0.1), 3)
                if ra.workplace and ra.workplace == rb.workplace:
                    rel.trust = round(min(1.0, rel.trust + 0.1), 3)

    grudges = []
    candidates = [(a, b) for a in ids for b in ids if a < b and residents[a].household != residents[b].household]
    for a, b in rng.sample(candidates, min(prof.grudge_pairs, len(candidates))):
        reason = rng.choice(GRUDGE_REASONS)
        residents[a].r(b).resentment = round(rng.uniform(0.45, 0.7), 3)
        residents[b].r(a).resentment = round(rng.uniform(0.3, 0.6), 3)
        residents[a].r(b).trust = residents[b].r(a).trust = 0.25
        grudges.append({"a": a, "b": b, "reason": reason})

    debts = []
    for rid in ids:
        if rng.random() >= prof.initial_debt_rate:
            continue
        r = residents[rid]
        lenders = [x for x in ids if residents[x].household != r.household and residents[x].cash > r.cash]
        if not lenders:
            continue
        lender = rng.choice(lenders)
        debts.append({"debtor": rid, "creditor": lender, "amount": rng.randint(30, 90),
                      "due": at(rng.randint(3, 12), 18)})

    landlord = by_role["mill_owner"][0]
    heads = {hid: members[0] for hid, members in households.items()}
    meta = {"households": households, "heads": heads, "landlord": landlord, "grudges": grudges,
            "initial_debts": debts}
    return world, residents, meta
