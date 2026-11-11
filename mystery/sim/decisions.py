"""Action selection: structured needs and goals scored by utility, with bounded noise.

Pressure changes priorities and acceptable risks; it never forces an outcome.
There is no rule like ``stress > 80 => crime``. Wrongdoing only appears as a candidate
when need, temperament and an opportunity line up, and it competes with every
lawful option (asking for a loan, asking for credit, going without).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import TYPE_CHECKING

from mystery.rng import clamp
from mystery.sim.clock import DAY, hour_of, is_rest_day
from mystery.sim.config import DRINK_PRICE, PUB_MEAL_PRICE

if TYPE_CHECKING:
    from mystery.sim.engine import Simulation
    from mystery.sim.residents import Resident

WEALTH_GUESS = {"mill_owner": 1.0, "grocer": 0.8, "publican": 0.8, "nurse": 0.6, "mechanic": 0.6}


@dataclass
class Plan:
    kind: str
    dest: str
    target: str | None = None
    reason: str | None = None
    score: float = 0.0
    data: dict = field(default_factory=dict)


def expected_location(sim: "Simulation", rid: str, t: int) -> str:
    """Where ``rid`` usually is at this hour, as anyone in town would guess."""
    x = sim.residents[rid]
    if sim.on_shift(x, t):
        return x.workplace  # type: ignore[return-value]
    h = hour_of(t)
    if 17 <= h < 22 and x.traits.temperance < 0.45:
        return "pub"
    return x.home


def cooling(r: "Resident", key: str, t: int) -> bool:
    return r.cooldowns.get(key, -1) > t


def choose(sim: "Simulation", r: "Resident", t: int) -> Plan:
    h = hour_of(t)
    rng = sim.rng
    T = r.traits
    here = sim.loc(r.id)
    home = r.home
    pantry = sim.pantry(r)
    size = len(sim.members(r))
    pressure = sim.pressure[r.id]
    cands: list[Plan] = []

    def add(kind: str, dest: str, score: float, target: str | None = None, reason: str | None = None, **data) -> None:
        cands.append(Plan(kind, dest, target, reason, score + rng.uniform(0, 8), data))

    # --- rest and sleep
    night = {21: 10, 22: 35}.get(h, 70 if (h >= 23 or h < 5) else 0)
    add("sleep", home, night + max(0.0, 60 - r.energy) * 1.0 + r.intox * 0.25 + 20 * r.injury)
    add("rest", home, 22 + (15 if r.energy < 40 else 0) + 25 * r.injury + (8 if here == home else 0))

    # --- work
    on_shift = sim.on_shift(r, t)
    if on_shift:
        s = 75 + T.diligence * 20 - max(0.0, r.intox - 30) * 0.6 * (1 - T.diligence)
        s -= 40 if r.energy < 12 else 0
        s -= 70 if r.injury >= 2 else 0
        add("work", r.workplace, s)

    # --- food
    if r.hunger > 40:
        if pantry.food > 0:
            dest = here if (on_shift and here == r.workplace) else home
            add("eat", dest, r.hunger * 1.25 + (10 if here == dest else 0))
        if sim.business_open("pub", t) and r.cash >= PUB_MEAL_PRICE:
            add("eat_pub", "pub", r.hunger * 1.0 + (100 - r.social) * 0.15 - (30 if r.cash < 40 else 0))
    if (sim.business_open("grocery", t) and pantry.food < size * 4
            and sim.daily.get(f"shopped:{r.household}", 0) == 0):
        add("shop", "grocery", 25 + (size * 8 - pantry.food) * 3 + (35 if pantry.food == 0 else 0))

    # --- the pub and the square
    if sim.business_open("pub", t) and h >= 16 and r.cash >= DRINK_PRICE:
        s = (15 + r.stress * 0.4 + (100 - r.social) * 0.3) * (1.3 - T.temperance) * sim.profile.drink_mult
        s += 8 if 18 <= h <= 21 else 0
        s += 12 if here == "pub" else 0
        s -= max(0.0, r.intox - 60) * 1.5
        s -= 25 * T.caution if r.cash < 15 else 0
        add("drink", "pub", s)
    if sim.business_open("pub", t) and h >= 12:
        add("socialize", "pub", (100 - r.social) * 0.6 * T.sociability + 8 + (6 if here == "pub" else 0))
    if 9 <= h < 19:
        add("socialize", "square", (100 - r.social) * 0.45 * T.sociability + (10 if is_rest_day(t) else 0))

    # --- casual work for those without a job
    if (not r.employed and r.role != "retiree" and 8 <= h <= 13 and sim.business_open("mill", t)):
        key = f"oddavail:{r.id}"
        if key not in sim.daily:
            sim.daily[key] = 1 if rng.random() < sim.profile.odd_jobs else 2
        if sim.daily[key] == 1:
            add("odd_job", "mill", 55 + pressure * 40 + T.diligence * 15 + (10 if here == "mill" else 0))

    # --- injuries and vehicles
    if r.injury and not r.injury_treated and sim.business_open("clinic", t):
        add("clinic", "clinic", 70 + 30 * r.injury)
    if r.wants_repair and r.vehicle and sim.business_open("workshop", t):
        veh = sim.world.vehicles[r.vehicle]
        if veh.damage and veh.location == here:
            add("repair", "workshop", 55 + (25 if veh.damage_event in r.guilty_of else 0))

    # --- people
    if 8 <= h < 22:
        social = _social_intent(sim, r, t, pressure)
        if social is not None:
            cands.append(social)

    # --- wrongdoing, only when pressure, temperament and opportunity line up
    steal = _steal_intent(sim, r, t, pressure)
    if steal is not None:
        cands.append(steal)

    cands.sort(key=lambda p: (-p.score, p.kind, p.dest, p.target or ""))
    return cands[0]


def _social_intent(sim: "Simulation", r: "Resident", t: int, pressure: float) -> Plan | None:
    T = r.traits
    here = sim.loc(r.id)
    best: Plan | None = None

    def consider(kind: str, x: str, score: float, reason: str | None = None, dest: str | None = None, **data) -> None:
        nonlocal best
        if dest is None:
            dest = expected_location(sim, x, t)
            if dest in ("pub", "grocery", "clinic", "workshop", "mill") and not sim.business_open(dest, t):
                dest = sim.residents[x].home
        score += sim.rng.uniform(0, 8)
        if best is None or score > best.score:
            best = Plan(kind, dest, x, reason, score, dict(data))

    owed_to_me = {d.debtor: d for d in sim.open_debts(r.id, as_creditor=True) if d.due < t}
    my_debts = sim.open_debts(r.id)
    my_creditors = {d.creditor for d in my_debts}
    mem = sim.memory[r.id]
    suspicions = {}
    for b in mem.of_kind("suspect", since=t - 4 * DAY):
        if b.claim.subject and b.confidence >= 0.5 and _has_stake(sim, r.id, b):
            prev = suspicions.get(b.claim.subject)
            if prev is None or b.confidence > prev.confidence:
                suspicions[b.claim.subject] = b
    in_hardship = {b.claim.subject for b in mem.of_kind("hardship", since=t - 3 * DAY)}

    for x in sim.ids:
        if x == r.id:
            continue
        xr = sim.residents[x]
        if not xr.alive:
            continue
        rel = r.r(x)
        same_house = xr.household == r.household
        # off-ramp: ask for help before anything worse (but not from someone you already owe)
        if (pressure > 0.5 and not same_house and rel.trust > 0.3 and x not in my_creditors
                and not cooling(r, f"loan:{x}", t) and not cooling(r, "loan", t)):
            wealth = WEALTH_GUESS.get(xr.role, 0.3)
            consider("loan", x, pressure * 80 * (0.4 + 0.6 * wealth) * (0.5 + rel.trust) - T.stubbornness * 15)
        for d in my_debts:
            if d.creditor == x and r.cash >= d.amount + 10:
                consider("repay", x, 45 + T.honesty * 30 + (30 if d.due < t else 0), debt=d.id)
        if not same_house and not cooling(r, f"confront:{x}", t):
            base, reason, ref, dest = 0.0, None, None, None
            if x in owed_to_me:
                base, reason, ref = 40.0, "debt", owed_to_me[x].id
                if owed_to_me[x].kind == "rent":
                    reason = "rent"
            if x in suspicions and 45 * suspicions[x].confidence > base:
                base, reason, ref = 45 * suspicions[x].confidence, "suspicion", suspicions[x].id
            # an old grudge only flares up when drink meets opportunity
            if reason is None and rel.resentment >= 0.6 and r.intox >= 35 and sim.loc(x) == here:
                base, reason, dest = 20.0, "grudge", here
            if reason:
                s = base + rel.resentment * 50 * (0.6 + 0.4 * T.stubbornness) + r.intox * 0.25
                s -= T.caution * 20 + T.empathy * 10
                consider("confront", x, s, reason, dest=dest, ref=ref)
        if (0.3 <= rel.resentment <= 0.65 and not same_house and not cooling(r, f"reconcile:{x}", t)):
            consider("reconcile", x, T.empathy * 35 + T.sociability * 15 - T.stubbornness * 25 - rel.resentment * 15)
        if r.cash >= 80 and rel.affection >= 0.5 and x in in_hardship and not cooling(r, f"help:{x}", t):
            consider("help", x, T.empathy * rel.affection * 80)
    return best


def _has_stake(sim: "Simulation", rid: str, suspicion) -> bool:
    """Only people with a stake in an incident go and confront a suspect."""
    claim = suspicion.claim
    if claim.other == rid:
        return True
    if claim.obj and claim.obj in sim.world.containers:
        return rid in sim.world.containers[claim.obj].owners
    if claim.other and sim.residents[rid].r(claim.other).affection >= 0.7:
        return True
    return claim.location == "road" and rid == sim.landlord


def _steal_intent(sim: "Simulation", r: "Resident", t: int, pressure: float) -> Plan | None:
    T = r.traits
    hungry_and_broke = sim.pantry(r).food == 0 and r.cash < sim.profile.food_price and r.hunger > 60
    if (pressure < 0.5 and not hungry_and_broke) or T.honesty >= 0.72 or cooling(r, "steal", t):
        return None
    drive = pressure * 1.1 + r.intox / 150 + T.impulsiveness * 0.3 + sim.profile.impulsive_shift
    moral = T.honesty * 0.9 + T.empathy * 0.25
    fear = 0.35 * sum(1 for g in r.guilty_of if sim.log.by_id[g].kind == "theft")
    base = 100 * (drive - moral - T.caution * 0.35 - fear)
    if base <= 0:
        return None
    h = hour_of(t)
    options: list[tuple[float, str, str]] = []
    if h >= 23 or h <= 3:
        for cid, guess in (("till:grocery", 60), ("till:pub", 70)):
            c = sim.world.containers[cid]
            owners = [o for o in c.owners if sim.residents[o].alive]
            spite = max((r.r(o).resentment for o in owners), default=0.0)
            options.append((guess + 25 * spite, cid, c.location))
        if hungry_and_broke:
            options.append((70, "stock:grocery", "grocery"))
    elif 10 <= h <= 15 and not is_rest_day(t):
        for hid in sorted(sim.households):
            if hid == r.household:
                continue
            members = [m for m in sim.households[hid] if sim.residents[m].alive]
            if members and all(sim.on_shift(sim.residents[m], t) for m in members):
                spite = max(r.r(m).resentment for m in members)
                options.append((40 + 25 * spite, f"box:{hid}", f"home:{hid}"))
    if not options:
        return None
    options.sort(key=lambda o: (-o[0], o[1]))
    value, cid, dest = options[0]
    score = base + value * 0.3 + (15 if h >= 23 or h <= 3 else 0)
    return Plan("steal", dest, cid, "pressure", clamp(score, 0, 200) + sim.rng.uniform(0, 8))
