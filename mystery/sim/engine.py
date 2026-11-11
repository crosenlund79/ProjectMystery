"""The simulation loop.

Each one-hour tick runs: needs -> scheduled duties -> decisions -> movement ->
actions and conversations -> perception and memory -> incident/case bookkeeping.

Every state change of consequence goes through ``emit`` (the canonical event log),
``transfer`` (money and goods, never below zero) or ``add_belief`` (memory with
provenance). That is what makes a run auditable.
"""

from __future__ import annotations

import copy
from collections import Counter

from mystery.rng import clamp, stream
from mystery.sim import actions, decisions
from mystery.sim.clock import DAY, TICK, day_of, fmt, hour_of, is_dark, is_rest_day, weekday_of
from mystery.sim.config import PENSION_WEEKLY, PROFILES, RENT, STOCK_CAPACITY, SUPPLIER_COST_RATIO, SimConfig
from mystery.sim.events import Event, EventLog
from mystery.sim.incidents import Incident, case_start_for
from mystery.sim.memory import SALIENCE, SOURCE_RANK, Belief, Claim, Memory
from mystery.sim.residents import Resident, generate_town
from mystery.sim.world import Container, Debt, Transfer

# Event kinds where every actor and target must share the event's location.
CO_LOCATED_KINDS = {
    "argument", "assault", "loan", "loan_refused", "repay", "help", "chat", "reconcile", "purchase",
    "credit", "credit_refused", "treated", "repair", "stopped_to_help", "injury_found", "body_found",
    "confession", "intervened", "drink", "pub_meal",
}


class SimulationError(RuntimeError):
    pass


class Simulation:
    def __init__(self, config: SimConfig):
        self.config = config
        self.profile = PROFILES[config.profile]
        self.rng = stream(config.seed, "sim", config.profile, config.residents)
        self.world, self.residents, self.meta = generate_town(config)
        self.households: dict[str, list[str]] = self.meta["households"]
        self.heads: dict[str, str] = self.meta["heads"]
        self.landlord: str = self.meta["landlord"]
        self.ids = sorted(self.residents)
        self.log = EventLog()
        self.beliefs: dict[str, Belief] = {}
        self.memory = {rid: Memory(rid) for rid in self.ids}
        self.perceived: dict[tuple[str, str], str] = {}
        self.intervals: dict[str, list[list]] = {rid: [[self.residents[rid].home, 0, None]] for rid in self.ids}
        self.incidents: list[Incident] = []
        self.case_hook = None  # callable(sim, incident) -> None, run at each case start
        self.plans: dict[str, decisions.Plan] = {}
        self.forced: dict[str, decisions.Plan] = {}
        self.moves: dict[str, dict] = {}
        self.pressure: dict[str, float] = {rid: 0.0 for rid in self.ids}
        self.recent_drinks: dict[str, list[tuple[int, str]]] = {rid: [] for rid in self.ids}
        self.daily = Counter()
        self.found_bodies: list[str] = []
        self.stats = Counter()
        self.t = 0
        self.initial_balances = self.balances()
        self._seed_history()

    # ------------------------------------------------------------------ helpers
    def n(self, rid: str | None) -> str:
        return self.residents[rid].first if rid in self.residents else "someone"

    def alive(self) -> list[Resident]:
        return [self.residents[rid] for rid in self.ids if self.residents[rid].alive]

    def loc(self, rid: str) -> str:
        return self.intervals[rid][-1][0]

    def where(self, rid: str, minute: int) -> str | None:
        for loc, start, end in reversed(self.intervals[rid]):
            if start <= minute and (end is None or minute < end):
                return loc
            if start <= minute:
                return None
        return None

    def present_during(self, rid: str, node: str, s: int, e: int) -> bool:
        for loc, start, end in reversed(self.intervals[rid][-8:]):
            if loc == node and start < e and (end is None or end > s):
                return True
        return False

    def overlap_start(self, rid: str, node: str, s: int, e: int) -> int | None:
        """First minute in [s, e) that ``rid`` is at ``node``."""
        best = None
        for loc, start, end in reversed(self.intervals[rid][-8:]):
            if loc == node and start < e and (end is None or end > s):
                t = max(start, s)
                best = t if best is None else min(best, t)
        return best

    def visitors(self, node: str, s: int, e: int, exclude: tuple = ()) -> list[str]:
        out = []
        for rid in self.ids:
            r = self.residents[rid]
            if rid in exclude or not r.alive or r.down:
                continue
            if self.present_during(rid, node, s, e):
                out.append(rid)
        return out

    def awake_at(self, rid: str, minute: int, node: str) -> bool:
        r = self.residents[rid]
        return r.alive and not r.asleep and not r.down and self.where(rid, minute) == node

    def staff_at(self, place: str, minute: int) -> list[str]:
        loc = self.world.locations[place]
        out = []
        for rid in loc.staff:
            plan = self.plans.get(rid)
            if self.awake_at(rid, minute, place) and plan is not None and plan.kind == "work":
                out.append(rid)
        return out

    def members(self, r: Resident) -> list[str]:
        return [m for m in self.households[r.household] if self.residents[m].alive]

    def pantry(self, r: Resident) -> Container:
        return self.world.containers[f"pantry:{r.household}"]

    def box(self, r: Resident) -> Container:
        return self.world.containers[f"box:{r.household}"]

    def stash(self, r: Resident) -> Container:
        cid = f"stash:{r.id}"
        if cid not in self.world.containers:
            self.world.containers[cid] = Container(cid, r.home, f"{r.first}'s hidden stash", [r.id], hidden=True)
        return self.world.containers[cid]

    def on_shift(self, r: Resident, t: int) -> bool:
        if not r.employed or not r.shift or not r.alive:
            return False
        h = hour_of(t)
        if is_rest_day(t) and r.workplace != "pub":
            return False
        return r.shift[0] <= h < r.shift[1]

    def business_open(self, place: str, t: int) -> bool:
        loc = self.world.locations[place]
        if is_rest_day(t) and place != "pub":
            return False
        return loc.is_open(hour_of(t))

    # --------------------------------------------------------------- accounting
    def balances(self) -> dict[str, dict[str, int]]:
        out = {f"wallet:{rid}": {"cash": r.cash, "food": 0} for rid, r in sorted(self.residents.items())}
        for cid, c in sorted(self.world.containers.items()):
            out[f"box:{cid}"] = {"cash": c.cash, "food": c.food}
        return out

    def _get(self, acct: str, asset: str) -> int | None:
        kind, _, key = acct.partition(":")
        if kind == "wallet":
            return self.residents[key].cash if asset == "cash" else 0
        if kind == "box":
            c = self.world.containers[key]
            return c.cash if asset == "cash" else c.food
        return None  # outside world / eaten: unbounded

    def _set(self, acct: str, asset: str, value: int) -> None:
        kind, _, key = acct.partition(":")
        if kind == "wallet":
            if asset != "cash":
                raise SimulationError("wallets hold cash only")
            self.residents[key].cash = value
        elif kind == "box":
            c = self.world.containers[key]
            if asset == "cash":
                c.cash = value
            else:
                c.food = value

    def transfer(self, asset: str, src: str, dst: str, amount: int, event_id: str, time: int | None = None) -> None:
        if amount <= 0:
            return
        have = self._get(src, asset)
        if have is not None and have < amount:
            raise SimulationError(f"{src} cannot give {amount} {asset} (has {have}) for {event_id}")
        if have is not None:
            self._set(src, asset, have - amount)
        dst_have = self._get(dst, asset)
        if dst_have is not None:
            self._set(dst, asset, dst_have + amount)
        self.world.transfers.append(Transfer(self.t if time is None else time, event_id, asset, src, dst, amount))

    # ------------------------------------------------------------------- events
    def emit(self, kind: str, location: str, actors, targets=(), objects=(), data=None, causes=(),
             intent=None, audibility=0, discreet=False, notable=False, time=None, summary="") -> Event:
        ev = Event(self.log.next_id(), self.t if time is None else time, location, kind, list(actors),
                   list(targets), list(objects), dict(data or {}), [c for c in causes if c], intent,
                   audibility, discreet, notable, summary)
        self.log.add(ev)
        self.stats[f"event:{kind}"] += 1
        return ev

    def add_belief(self, holder: str, claim: Claim, source: str, confidence: float, time: int,
                   event: str | None = None, told_by: str | None = None, via: str | None = None,
                   premises=None, error: str | None = None, salience: float | None = None) -> Belief:
        mem = self.memory[holder]
        existing = mem.find(claim)
        if existing is not None and SOURCE_RANK[existing.source] >= SOURCE_RANK[source]:
            return existing
        b = Belief(f"B{len(self.beliefs) + 1:06d}", holder, claim, source, time, round(clamp(confidence), 3),
                   SALIENCE.get(claim.kind, 0.3) if salience is None else salience, event, told_by, via,
                   list(premises or []), error)
        self.beliefs[b.id] = b
        mem.add(b)
        return b

    def familiarity(self, observer: str, subject: str) -> float:
        rel = self.residents[observer].r(subject)
        return (rel.trust + rel.affection) / 2

    def biased_pick(self, observer: str, exclude: list[str]) -> str | None:
        """When people guess wrongly, they guess people they already dislike."""
        r = self.residents[observer]
        pool = [x for x in self.ids if x not in exclude and x != observer and self.residents[x].alive]
        if not pool:
            return None
        weights = [0.2 + r.r(x).resentment * 2 for x in pool]
        roll = self.rng.random() * sum(weights)
        for x, w in zip(pool, weights):
            roll -= w
            if roll <= 0:
                return x
        return pool[-1]

    def identify(self, observer: str, subject: str, location: str, t: int, in_vehicle: bool = False):
        r = self.residents[observer]
        outdoor_dark = self.world.locations[location].outdoor and is_dark(t)
        p = 0.97
        if outdoor_dark:
            p = 0.3 + 0.35 * self.familiarity(observer, subject)
        if in_vehicle:
            p = 0.15 if outdoor_dark else 0.6
        p -= max(0.0, r.intox - 40) * 0.006
        if self.rng.random() < p:
            return subject, None
        if self.rng.random() < 0.22:
            return self.biased_pick(observer, [subject]), "misidentified"
        return None, None

    def broadcast(self, ev: Event, seen: Claim | None = None, heard: Claim | None = None,
                  voice: str | None = None, exclude=()) -> None:
        """Everyone physically able to notice ``ev`` forms a belief about it."""
        for rid in self.ids:
            r = self.residents[rid]
            if not r.alive or r.down or rid in ev.actors or rid in ev.targets or rid in exclude:
                continue
            where = self.where(rid, ev.time)
            if where is None:
                continue
            hops = self.world.hops(where, ev.location)
            mode = None
            if hops == 0 and not r.asleep and not ev.discreet:
                mode = "saw"
            elif hops == 0 and r.asleep and ev.audibility >= 1 and self.rng.random() < 0.5:
                mode = "heard"
            elif 1 <= hops <= ev.audibility - 1:
                p = 0.85 if hops == 1 else 0.5
                if r.asleep:
                    p *= 0.4
                if self.rng.random() < p:
                    mode = "heard"
            if mode == "saw" and seen is not None:
                claim = copy.copy(seen)
                err = None
                if claim.subject:
                    claim.subject, err = self.identify(rid, claim.subject, ev.location, ev.time)
                if claim.other:
                    claim.other, err2 = self.identify(rid, claim.other, ev.location, ev.time)
                    err = err or err2
                self.add_belief(rid, claim, "saw", 0.9 if err is None else 0.6, ev.time, event=ev.id, error=err)
                self.perceived[(rid, ev.id)] = "saw"
            elif mode is not None and heard is not None:
                claim = copy.copy(heard)
                err = None
                if voice:
                    p_voice = 0.25 + 0.45 * self.familiarity(rid, voice) - (0.25 if hops > 0 else 0)
                    roll = self.rng.random()
                    if roll < p_voice:
                        claim.subject, claim.hedged = voice, True
                    elif roll < p_voice + 0.12:
                        claim.subject, claim.hedged, err = self.biased_pick(rid, [voice]), True, "misidentified"
                self.add_belief(rid, claim, "heard", 0.6, ev.time, event=ev.id, error=err)
                self.perceived[(rid, ev.id)] = "heard"
                if r.asleep and ev.audibility >= 3:
                    r.stress = clamp(r.stress + 3, 0, 100)

    # ---------------------------------------------------------------- history
    def _seed_history(self) -> None:
        for g in self.meta["grudges"]:
            a, b, reason = g["a"], g["b"], g["reason"]
            ev = self.emit("prior_grudge", "-", [a], [b], data={"reason": reason}, time=0,
                           summary=f"Long-standing grudge between {self.n(a)} and {self.n(b)}: {reason}.")
            claim = Claim("grudge", subject=a, other=b, detail=reason)
            for holder in (a, b):
                self.add_belief(holder, claim, "self", 1.0, 0, event=ev.id)
            for other in self.ids:
                if other not in (a, b) and self.rng.random() < 0.5:
                    self.add_belief(other, claim, "told", 0.7, 0, event=ev.id, told_by=a)
        for d in self.meta["initial_debts"]:
            ev = self.emit("prior_debt", "-", [d["debtor"]], [d["creditor"]], data={"amount": d["amount"]}, time=0,
                           summary=f"{self.n(d['debtor'])} owes {self.n(d['creditor'])} {d['amount']} crowns "
                                   f"(due {fmt(d['due'])}).")
            self.world.debts.append(Debt(f"D{len(self.world.debts) + 1:03d}", d["debtor"], d["creditor"], d["amount"],
                                         d["due"], 0, ev.id))
            claim = Claim("debt", subject=d["debtor"], other=d["creditor"], amount=d["amount"], detail="loan")
            for holder in (d["debtor"], d["creditor"]):
                self.add_belief(holder, claim, "self", 1.0, 0, event=ev.id)
            for other in self.ids:
                if other not in (d["debtor"], d["creditor"]) and self.rng.random() < 0.25:
                    self.add_belief(other, claim, "told", 0.6, 0, event=ev.id, told_by=d["creditor"])

    # ---------------------------------------------------------------- pressure
    def open_debts(self, rid: str, as_creditor: bool = False) -> list[Debt]:
        key = "creditor" if as_creditor else "debtor"
        return [d for d in self.world.debts if getattr(d, key) == rid and d.settled is None]

    def funds(self, r: Resident) -> int:
        stash = self.world.containers.get(f"stash:{r.id}")
        return r.cash + self.box(r).cash + (stash.cash if stash else 0)

    def shortfall(self, r: Resident, t: int) -> float:
        price = self.profile.food_price
        size = len(self.members(r))
        pantry = self.pantry(r).food
        food_need = max(0, size * 6 - pantry) * price
        owed = sum(d.amount for d in self.open_debts(r.id) if d.due <= t + 3 * DAY)
        rent = RENT if (self.heads[r.household] == r.id and r.id != self.landlord and weekday_of(t) >= 4) else 0
        return food_need * 0.5 + owed + rent - self.funds(r)

    def money_pressure(self, r: Resident, t: int) -> float:
        p = clamp(self.shortfall(r, t) / 80.0)
        if self.pantry(r).food == 0 and r.cash < self.profile.food_price:
            p = max(p, 0.6)
        if any(d.due < t for d in self.open_debts(r.id)):
            p = clamp(p + 0.2)
        if not r.employed and r.role != "retiree":
            p = clamp(p + 0.1)
        return round(p, 3)

    def add_pressure(self, r: Resident, ev: Event, stress: float = 8.0) -> None:
        r.pressures.append((ev.time, ev.id))
        r.stress = clamp(r.stress + stress, 0, 100)

    # ------------------------------------------------------------------ run
    def run(self, until: int | None = None) -> "Simulation":
        end = self.config.days * DAY if until is None else until
        while self.t < end:
            self.step()
        return self

    def step(self) -> None:
        t0 = self.t
        self._update_needs(t0)
        self._start_of_tick(t0)
        self._decide_all(t0)
        self._move_phase(t0)
        self._action_phase(t0)
        self._end_of_tick(t0)
        self.t += TICK

    # ------------------------------------------------------------------ needs
    def _update_needs(self, t: int) -> None:
        if hour_of(t) == 0:
            for r in self.alive():
                r.worked_today = False
            self.daily = Counter()
        for r in self.alive():
            if r.asleep:
                r.energy += 8
                r.hunger += 2
                r.stress -= 1.5
            else:
                r.energy -= 3.5
                r.hunger += 5
                r.social -= 2.5
                r.stress += self.pressure[r.id] * 3 - 1
            if r.down:
                r.stress += 3
            if r.hunger >= 95:
                r.stress += 2
            r.intox = max(0.0, r.intox - 10)
            r.energy, r.hunger = clamp(r.energy, 0, 100), clamp(r.hunger, 0, 100)
            r.social, r.stress = clamp(r.social, 0, 100), clamp(r.stress, 0, 100)
            if r.injury and r.injury_event:
                started = self.log.by_id[r.injury_event].time
                if t - started >= (2 if r.injury == 1 else 6) * DAY:
                    r.injury = 0
            self.pressure[r.id] = self.money_pressure(r, t)

    # -------------------------------------------------------- scheduled duties
    def _start_of_tick(self, t: int) -> None:
        h = hour_of(t)
        for d in self.world.debts:
            if d.settled is None and d.overdue_event is None and d.due <= t:
                debtor = self.residents[d.debtor]
                if not debtor.alive or not self.residents[d.creditor].alive:
                    continue
                ev = self.emit("debt_overdue", self.loc(d.debtor), [d.debtor], data={"creditor": d.creditor,
                               "amount": d.amount, "debt": d.id}, causes=[d.origin_event], time=t,
                               summary=f"{self.n(d.debtor)}'s debt of {d.amount} to {self.n(d.creditor)} is overdue.")
                d.overdue_event = ev.id
                claim = Claim("debt", subject=d.debtor, other=d.creditor, amount=d.amount, detail="overdue")
                self.add_belief(d.debtor, claim, "self", 1.0, t, event=ev.id)
                self.add_belief(d.creditor, claim, "self", 1.0, t, event=ev.id)
                self.add_pressure(debtor, ev)
                cred = self.residents[d.creditor]
                cred.r(d.debtor).resentment = clamp(cred.r(d.debtor).resentment + 0.15)
        if h == 7:
            for r in self.alive():
                if self.loc(r.id) == r.home and not r.down:
                    self._morning_cash(r, t)
        if h == 8 and weekday_of(t) == 0:
            self._collect_rent(t)
        if h == 8 and weekday_of(t) in (1, 4):
            self._delivery(t)
        if h == 8 and day_of(t) == 5 and self.profile.layoffs:
            self._layoffs(t)

    def _morning_cash(self, r: Resident, t: int) -> None:
        """Households pool their money in a savings tin at home."""
        box = self.box(r)
        if r.cash > 120:
            self.count_container(box, r.id, t)
            amount = r.cash - 60
            ev = self.emit("deposit", r.home, [r.id], objects=[box.id], data={"amount": amount}, intent="lawful",
                           time=t, summary=f"{r.first} puts {amount} crowns in the household tin.")
            self.transfer("cash", f"wallet:{r.id}", f"box:{box.id}", amount, ev.id, t)
            box.expected_cash += amount
            return
        if r.cash >= 25:
            return
        stash = self.world.containers.get(f"stash:{r.id}")
        if stash is not None and stash.cash > 0 and not r.pending_hide:
            amount = min(40, stash.cash)
            ev = self.emit("stash_withdraw", r.home, [r.id], objects=[stash.id], data={"amount": amount},
                           causes=list(r.guilty_of[-1:]), intent="intentional", discreet=True, time=t,
                           summary=f"{r.first} quietly takes {amount} crowns from the hidden stash.")
            self.transfer("cash", f"box:{stash.id}", f"wallet:{r.id}", amount, ev.id, t)
            return
        self.count_container(box, r.id, t)
        amount = min(40, box.cash)
        if amount > 0:
            ev = self.emit("withdraw", r.home, [r.id], objects=[box.id], data={"amount": amount}, intent="lawful",
                           time=t, summary=f"{r.first} takes {amount} crowns from the household tin.")
            self.transfer("cash", f"box:{box.id}", f"wallet:{r.id}", amount, ev.id, t)
            box.expected_cash -= amount

    def _collect_rent(self, t: int) -> None:
        landlord = self.residents[self.landlord]
        for hid in sorted(self.households):
            head = self.residents[self.heads[hid]]
            if head.id == self.landlord or hid == landlord.household or not head.alive:
                continue
            if head.cash < RENT and self.loc(head.id) == head.home:
                box = self.box(head)
                self.count_container(box, head.id, t)
                take = min(box.cash, RENT - head.cash)
                if take > 0:
                    ev = self.emit("withdraw", head.home, [head.id], objects=[box.id], data={"amount": take},
                                   intent="lawful", time=t, summary=f"{head.first} takes {take} from the tin for rent.")
                    self.transfer("cash", f"box:{box.id}", f"wallet:{head.id}", take, ev.id, t)
                    box.expected_cash -= take
            if head.cash >= RENT and landlord.alive:
                ev = self.emit("rent_paid", self.loc(head.id), [head.id], data={"to": landlord.id, "amount": RENT},
                               intent="lawful", time=t, summary=f"{head.first} pays {RENT} rent to {landlord.first}.")
                self.transfer("cash", f"wallet:{head.id}", f"wallet:{landlord.id}", RENT, ev.id, t)
            else:
                ev = self.emit("rent_missed", self.loc(head.id), [head.id], data={"to": landlord.id, "amount": RENT},
                               time=t, notable=True,
                               summary=f"{head.first} cannot pay the rent owed to {landlord.first}.")
                self.world.debts.append(Debt(f"D{len(self.world.debts) + 1:03d}", head.id, landlord.id, RENT,
                                             t + 7 * DAY, t, ev.id, kind="rent"))
                claim = Claim("rent_missed", subject=head.id, other=landlord.id, amount=RENT, start=t)
                self.add_belief(head.id, claim, "self", 1.0, t, event=ev.id)
                self.add_belief(landlord.id, claim, "self", 1.0, t, event=ev.id)
                self.add_pressure(head, ev, 12)
                landlord.r(head.id).resentment = clamp(landlord.r(head.id).resentment + 0.1)
        for r in self.alive():
            if r.role == "retiree":
                ev = self.emit("pension", self.loc(r.id), [r.id], data={"amount": PENSION_WEEKLY}, intent="lawful",
                               time=t, summary=f"{r.first} receives a pension of {PENSION_WEEKLY}.")
                self.transfer("cash", "outside", f"wallet:{r.id}", PENSION_WEEKLY, ev.id, t)

    def _delivery(self, t: int) -> None:
        till, stock = self.world.containers["till:grocery"], self.world.containers["stock:grocery"]
        grocers = [o for o in till.owners if self.residents[o].alive]
        unit_cost = max(1, int(round(self.profile.food_price * SUPPLIER_COST_RATIO)))
        purse = till.cash + sum(self.residents[o].cash for o in grocers)
        units = min(self.profile.delivery_units, STOCK_CAPACITY - stock.food, purse // unit_cost)
        if units <= 0:
            return
        cost = units * unit_cost
        ev = self.emit("delivery", "grocery", [], objects=[till.id, stock.id], data={"units": units, "cost": cost},
                       intent="lawful", time=t, summary=f"Supplier delivers {units} units to the grocery for {cost}.")
        from_till = min(cost, till.cash)
        self.transfer("cash", f"box:{till.id}", "outside", from_till, ev.id, t)
        till.expected_cash -= from_till
        rest = cost - from_till
        for o in grocers:
            part = min(rest, self.residents[o].cash)
            self.transfer("cash", f"wallet:{o}", "outside", part, ev.id, t)
            rest -= part
        self.transfer("food", "outside", f"box:{stock.id}", units, ev.id, t)
        stock.expected_food += units
        note = f" ({cost - from_till} cr from the owner's pocket)" if cost > from_till else ""
        self.world.record("ledger", t, f"{fmt(t)} supplier delivery: {units} units received, paid {cost} cr{note}.",
                          ev.id)

    def _layoffs(self, t: int) -> None:
        owner = self.residents[self.landlord]
        hands = [r for r in self.alive() if r.role == "mill_hand" and r.employed]
        hands.sort(key=lambda r: (r.traits.diligence, r.id))
        for r in hands[: self.profile.layoffs]:
            ev = self.emit("laid_off", self.loc(owner.id), [owner.id], data={"worker": r.id}, time=t, notable=True,
                           summary=f"{owner.first} lays off {r.first} from the mill.")
            r.employed, r.workplace, r.shift = False, None, None
            r.occupation = "out of work (laid off from the mill)"
            self.world.locations["mill"].staff = [x for x in self.world.locations["mill"].staff if x != r.id]
            claim = Claim("laid_off", subject=r.id, other=owner.id, start=t)
            self.add_belief(r.id, claim, "self", 1.0, t, event=ev.id)
            self.add_belief(owner.id, claim, "self", 1.0, t, event=ev.id)
            r.r(owner.id).resentment = clamp(r.r(owner.id).resentment + 0.35)
            self.add_pressure(r, ev, 20)

    # ---------------------------------------------------------------- decisions
    def _decide_all(self, t: int) -> None:
        self.plans = {}
        h = hour_of(t)
        for rid in self.ids:
            r = self.residents[rid]
            if not r.alive or r.down:
                continue
            if rid in self.forced:
                self.plans[rid] = self.forced.pop(rid)
                r.asleep = False
                continue
            if r.asleep:
                wake = 6 if (r.shift and r.shift[0] <= 8 and r.employed) else 7
                if r.intox > 30:
                    wake += 1
                if (h >= wake and h < 21 and r.energy >= 55) or (9 <= h < 21):
                    r.asleep = False
                else:
                    self.plans[rid] = decisions.Plan("sleep", r.home)
                    continue
            self.plans[rid] = decisions.choose(self, r, t)

    # ----------------------------------------------------------------- movement
    def _route(self, rid: str, dest: str, depart: int, drive: bool) -> None:
        cur = self.loc(rid)
        path = self.world.path(cur, dest)
        times = [depart]
        tt = depart
        for a, b in zip(path, path[1:]):
            m = self.world.locations[a].adj[b]
            tt += max(1, round(m * 0.35)) if drive else m
            times.append(tt)
        ivs = self.intervals[rid]
        ivs[-1][2] = times[1]
        for i in range(1, len(path)):
            ivs.append([path[i], times[i], times[i + 1] if i + 1 < len(path) else None])
        self.moves[rid] = {"path": path, "times": times, "drive": drive, "depart": depart,
                           "vehicle": self.residents[rid].vehicle if drive else None}
        if drive:
            self.world.vehicles[self.residents[rid].vehicle].location = dest

    def truncate(self, rid: str, node: str, t: int) -> None:
        """Stop someone mid-journey at ``node`` (they fell, were hit, or stopped)."""
        ivs = self.intervals[rid]
        while len(ivs) > 1 and ivs[-1][1] >= t:
            ivs.pop()
        if ivs[-1][0] != node:
            ivs[-1][2] = t
            ivs.append([node, t, None])
        else:
            ivs[-1][2] = None
        mv = self.moves.get(rid)
        if mv:
            path = mv["path"]
            cut = path.index(node) + 1 if node in path else len(path)
            mv["path"], mv["times"] = path[:cut], mv["times"][:cut]
            if mv["drive"]:
                self.world.vehicles[mv["vehicle"]].location = node

    def decide_drive(self, r: Resident, dest: str) -> bool:
        if not r.vehicle:
            return False
        veh = self.world.vehicles[r.vehicle]
        here = self.loc(r.id)
        if veh.location != here or "road" not in self.world.path(here, dest):
            return False
        if r.intox < 25:
            return self.rng.random() < 0.85
        t = r.traits
        p = 0.75 - t.caution * 0.6 - (1 - r.intox / 100) * 0.2 + t.impulsiveness * 0.3
        return self.rng.random() < clamp(p, 0.05, 0.9)

    def _move_phase(self, t0: int) -> None:
        self.moves = {}
        movers = [rid for rid in self.ids if rid in self.plans and self.plans[rid].dest != self.loc(rid)]
        drivers, walkers = [], []
        for rid in movers:
            r = self.residents[rid]
            if self.decide_drive(r, self.plans[rid].dest):
                if any(self.residents[d].vehicle == r.vehicle for d in drivers):
                    walkers.append(rid)
                else:
                    drivers.append(rid)
            else:
                walkers.append(rid)
        for rid in walkers + drivers:
            self._route(rid, self.plans[rid].dest, t0 + self.rng.randint(0, 15), rid in drivers)
        for rid in drivers:
            actions.check_collision(self, rid, t0, walkers)
        for rid in walkers:
            actions.check_fall(self, rid, t0)
        for rid in movers:
            mv = self.moves[rid]
            r = self.residents[rid]
            path = mv["path"]
            veh = mv["vehicle"]
            mv["event"] = self.emit(
                "move", path[0], [rid], objects=[veh] if veh else [],
                data={"path": path, "times": mv["times"], "drive": mv["drive"]}, time=mv["depart"],
                summary=f"{r.first} {'drives' if mv['drive'] else 'walks'} from {self.world.name(path[0])} to "
                        f"{self.world.name(path[-1])}.").id
        for rid in movers:
            self._doorways(rid)
        for rid in movers:
            if self.residents[rid].alive:
                self._transit_sightings(rid)

    def _doorways(self, rid: str) -> None:
        """Housemates notice comings and goings: awake ones see them, sleeping ones may hear the door."""
        mv = self.moves[rid]
        path, times = mv["path"], mv["times"]
        if len(path) < 2:
            return
        for node, t, label in ((path[0], times[1], "heading out"), (path[-1], times[-1], "coming home")):
            loc = self.world.locations[node]
            if loc.kind != "home":
                continue
            late = is_dark(t) or hour_of(t) >= 21
            for m in self.households[loc.household]:
                x = self.residents[m]
                if m == rid or not x.alive or x.down or self.where(m, t) != node:
                    continue
                if not x.asleep and late and self.rng.random() < 0.8:
                    claim = Claim("sighting", subject=rid, location=node, start=t, end=t, detail=label)
                    self.add_belief(m, claim, "saw", 0.9, t, event=mv.get("event"))
                    self.perceived[(m, mv.get("event") or "")] = "saw"
                elif x.asleep and late and self.rng.random() < 0.3:
                    what = "the door go — someone going out" if label == "heading out" else \
                        "the door — someone coming in"
                    claim = Claim("noise", subject=rid, location=node, start=t, detail=what, hedged=True)
                    self.add_belief(m, claim, "heard", 0.6, t, event=mv.get("event"))
                    self.perceived[(m, mv.get("event") or "")] = "heard"

    def _transit_sightings(self, rid: str) -> None:
        mv = self.moves[rid]
        path, times = mv["path"], mv["times"]
        for i in range(1, len(path) - 1):
            node = path[i]
            if not self.world.locations[node].outdoor:
                continue
            s, e = times[i], times[i + 1]
            nxt = path[i + 1]
            for obs in self.ids:
                o = self.residents[obs]
                if obs == rid or not o.alive or o.asleep or o.down:
                    continue
                when = self.overlap_start(obs, node, s, e)
                if when is None:
                    continue
                if self.rng.random() >= (0.85 if is_dark(s) else 0.45):
                    continue
                self.sighting(obs, rid, node, when, nxt, mv)

    def sighting(self, obs: str, subj: str, node: str, t: int, toward: str, mv: dict) -> None:
        dark = is_dark(t)
        veh_id = mv.get("vehicle")
        obj = None
        if veh_id:
            veh = self.world.vehicles[veh_id]
            who, err = self.identify(obs, subj, node, t, in_vehicle=True)
            recognised = self.rng.random() < (0.8 if dark else 0.95)
            obj = veh_id if recognised else None
            what = veh.name if recognised else f"a {veh.kind}"
            detail = f"{what} heading toward {self.world.name(toward)}"
        else:
            who, err = self.identify(obs, subj, node, t)
            detail = f"heading toward {self.world.name(toward)}"
            if who is not None and self.residents[subj].intox >= 60:
                detail += ", unsteady on their feet"
        claim = Claim("sighting", subject=who, location=node, start=t, end=t, detail=detail, obj=obj,
                      hedged=(who is not None and dark))
        self.add_belief(obs, claim, "saw", 0.6 if dark else 0.85, t, event=mv.get("event"), error=err)
        self.perceived[(obs, mv.get("event") or "")] = "saw"

    # ------------------------------------------------------------------ actions
    def _action_phase(self, t0: int) -> None:
        order = list(self.ids)
        self.rng.shuffle(order)
        # Minutes follow processing order, so cause always precedes effect within the hour
        # (and the latest consequence, at +2, still falls inside this tick).
        for idx, rid in enumerate(order):
            r = self.residents[rid]
            plan = self.plans.get(rid)
            if plan is None or not r.alive or r.down or r.asleep:
                continue
            if self.loc(rid) != plan.dest:
                continue
            actions.perform(self, r, plan, t0 + 46 + idx)
        actions.incidental_chats(self, t0)

    # --------------------------------------------------------------- end of tick
    def _end_of_tick(self, t0: int) -> None:
        tm = t0 + 59
        h = hour_of(t0)
        self._co_presence(tm)
        self._notice_evidence(t0)
        self._found_checks(t0)
        self._missed_people(t0)
        self._hide_loot(t0)
        self._tidy_evidence(t0)
        for place in ("grocery", "pub", "mill", "clinic", "workshop"):
            loc = self.world.locations[place]
            if loc.hours and h == loc.hours[1] - 1:
                actions.close_business(self, place, tm)
        if h in (12, 20):
            for r in self.alive():
                if not r.down:
                    actions.infer_suspicions(self, r.id, tm)
        nxt = t0 + TICK
        for inc in self.incidents:
            if inc.case_start == nxt and self.case_hook is not None:
                self.case_hook(self, inc)

    def _co_presence(self, tm: int) -> None:
        groups: dict[str, list[str]] = {}
        for r in self.alive():
            if r.asleep or r.down:
                continue
            groups.setdefault(self.where(r.id, tm) or "", []).append(r.id)
        for node in sorted(groups):
            people = groups[node]
            if len(people) < 2:
                continue
            loc = self.world.locations[node]
            for obs in people:
                for subj in people:
                    if obs == subj:
                        continue
                    s = self.residents[subj]
                    if loc.outdoor and is_dark(tm):
                        who, err = self.identify(obs, subj, node, tm)
                        claim = Claim("sighting", subject=who, location=node, start=tm, end=tm, detail="out after dark",
                                      hedged=who is not None)
                        self.add_belief(obs, claim, "saw", 0.6, tm, error=err)
                    else:
                        self.observe_presence(obs, subj, node, tm)
                    if s.intox >= 55:
                        self.add_belief(obs, Claim("intoxicated", subject=subj, location=node, start=tm), "saw", 0.8, tm)
                    if s.injury and s.injury_event:
                        actions.notice_injury(self, obs, subj, node, tm)

    def observe_presence(self, obs: str, subj: str, node: str, t: int) -> None:
        mem = self.memory[obs]
        key = (subj, node)
        b = mem.open_presence.get(key)
        if b is not None and b.claim.end is not None and 0 <= t - b.claim.end <= 75:
            b.claim.end = t
            return
        claim = Claim("presence", subject=subj, location=node, start=t, end=t)
        mem.open_presence[key] = self.add_belief(obs, claim, "saw", 0.9, t)

    def _notice_evidence(self, t0: int) -> None:
        for ev in self.world.evidence:
            if not ev.present_at(t0 + 59) or ev.kind not in ("debris", "vehicle_damage", "forced_door", "blood"):
                continue
            node = ev.place
            if ev.kind == "vehicle_damage":
                node = self.world.vehicles[ev.place].location
            for rid in self.visitors(node, t0, t0 + 60):
                r = self.residents[rid]
                if r.asleep or rid in ev.noticed_by or self.made_by(rid, ev):
                    continue
                when = self.overlap_start(rid, node, t0, t0 + 60)
                if when is None or when < ev.created_at:
                    continue
                daylight = not is_dark(when)
                if ev.kind == "debris" and not daylight:
                    continue
                if self.rng.random() > (0.75 if daylight else 0.3):
                    continue
                actions.notice(self, rid, ev, when)

    def made_by(self, rid: str, ev) -> bool:
        """Did ``rid`` create this trace through their own wrongdoing (or driving)?"""
        src = self.log.by_id[ev.created_by]
        if rid in src.actors and (src.id in self.residents[rid].guilty_of or src.kind in ("collision", "hide_loot")):
            return True
        return any(c in self.residents[rid].guilty_of for c in src.causes) and rid in src.actors

    def _found_checks(self, t0: int) -> None:
        for rid in self.ids:
            r = self.residents[rid]
            if not (r.down or (not r.alive and r.death_event and rid not in self.found_bodies)):
                continue
            node = self.loc(r.id)
            harm = self.log.by_id[r.death_event or r.injury_event]
            death_or_injury = harm.time
            cause = self.log.by_id[harm.causes[0]] if harm.kind == "death" and harm.causes else harm
            finders = []
            for x in self.visitors(node, t0, t0 + 60, exclude=(r.id, *cause.actors)):
                when = self.overlap_start(x, node, max(t0, death_or_injury + 1), t0 + 60)
                if when is not None and not self.residents[x].asleep:
                    finders.append((when, x))
            finders.sort()
            if not finders and r.alive and r.down and hour_of(t0) == 10:
                r.down = False  # manages to get home on their own
                self.forced[r.id] = decisions.Plan("rest", r.home)
                continue
            if finders:
                actions.found(self, finders[0][1], r, node, finders[0][0])

    def _missed_people(self, t0: int) -> None:
        """Someone who has not been seen for most of a day gets checked on at home."""
        h = hour_of(t0)
        if not 8 <= h <= 18:
            return
        for rid in self.ids:
            r = self.residents[rid]
            if r.alive or rid in self.found_bodies or not r.death_event:
                continue
            death = self.log.by_id[r.death_event]
            if t0 - death.time < 12 * 60 or self.daily.get(f"checked:{rid}", 0):
                continue
            culprits = set(self.log.by_id[death.causes[0]].actors) if death.causes else set()
            carers = [x for x in self.ids if x != rid and x not in culprits and self.residents[x].alive
                      and not self.residents[x].down and x not in self.forced]
            if not carers:
                continue
            carer = max(carers, key=lambda x: (self.residents[x].r(rid).affection, x))
            self.daily[f"checked:{rid}"] = 1
            ev = self.emit("missed", self.loc(carer), [carer], data={"missing": rid}, intent="lawful", time=t0 + 59,
                           summary=f"{self.n(carer)} hasn't seen {r.first} all day and goes to check on them.")
            self.add_belief(carer, Claim("missing", subject=rid, start=death.time, end=t0, detail="not seen all day"),
                            "self", 0.9, t0 + 59, event=ev.id)
            self.forced[carer] = decisions.Plan("check_on", r.home, target=rid)

    def _hide_loot(self, t0: int) -> None:
        for r in self.alive():
            if r.pending_hide and self.loc(r.id) == r.home and not r.down:
                actions.hide_loot(self, r, t0 + 55)

    def _tidy_evidence(self, t0: int) -> None:
        for ev in self.world.evidence:
            if ev.kind == "body" and ev.present_at(t0) and ev.noticed_by and t0 - ev.created_at >= 3 * DAY:
                burial = self.emit("burial", ev.place, [], data={"evidence": ev.id}, causes=[ev.created_by],
                                   intent="lawful", time=t0, summary="The body is taken away and buried.")
                ev.removed_at, ev.removed_by = t0, burial.id
                continue
            if not ev.present_at(t0) or ev.kind not in ("debris", "blood", "forced_door"):
                continue
            age = t0 - ev.created_at
            limit = {"debris": 36 * 60, "blood": 20 * 60, "forced_door": 30 * 60}[ev.kind]
            if age < limit:
                continue
            node = ev.place
            for rid in self.visitors(node, t0, t0 + 60):
                r = self.residents[rid]
                when = self.overlap_start(rid, node, t0, t0 + 60)
                if r.asleep or when is None or is_dark(when):
                    continue
                actions.tidy(self, r, ev, when)
                break

    # ---------------------------------------------------------------- incidents
    def register_incident(self, **kw) -> Incident:
        inc = Incident(id=f"I{len(self.incidents) + 1}", **kw)
        self.incidents.append(inc)
        return inc

    def incident_for(self, event_id: str) -> Incident | None:
        for inc in self.incidents:
            if inc.core_event == event_id or event_id in inc.related_events:
                return inc
        return None

    def discover(self, inc: Incident, by: str, t: int, event_id: str, hook_text: str, title: str,
                 window: list[int], place: str) -> None:
        if inc.discovered_at is not None:
            return
        inc.discovered_at, inc.discovered_by, inc.discovery_event = t, by, event_id
        inc.hook_text, inc.title, inc.window, inc.hook_place = hook_text, title, window, place
        if not inc.reported_openly:
            inc.case_start = case_start_for(t)
        self.stats[f"discovered:{inc.family}"] += 1

    # ------------------------------------------------------------ count tills
    def count_container(self, c: Container, counter: str, t: int) -> None:
        short_cash = c.expected_cash - c.cash
        short_food = c.expected_food - c.food
        if short_cash >= 5 or short_food >= 3:
            actions.loss_discovered(self, c, counter, t, max(0, short_cash), max(0, short_food))
        c.expected_cash, c.expected_food, c.last_check = c.cash, c.food, t
        c.unexplained = []

    # --------------------------------------------------------------- summaries
    def summary(self) -> dict:
        return {
            "config": self.config.describe(),
            "town": self.world.town_name,
            "residents": {rid: {"name": r.name, "occupation": r.occupation, "household": r.household,
                                "alive": r.alive} for rid, r in sorted(self.residents.items())},
            "events": len(self.log),
            "digest": self.log.digest(),
            "incidents": [inc.to_dict() for inc in self.incidents],
        }


def simulate(seed: int, days: int = 60, profile: str = "normal", residents: int = 10,
             case_hook=None, until: int | None = None) -> Simulation:
    sim = Simulation(SimConfig(seed=seed, days=days, profile=profile, residents=residents))
    sim.case_hook = case_hook
    return sim.run(until)
