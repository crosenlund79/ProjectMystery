"""What residents do, and what that leaves behind.

Each handler changes the world only through the engine's ``emit``/``transfer``/
``add_belief``/``add_evidence`` so the consequences stay auditable: money moves
with an event id, traces point at the event that made them, and witnesses only
learn what they could physically perceive.
"""

from __future__ import annotations

import copy
from typing import TYPE_CHECKING

from mystery.rng import clamp
from mystery.sim.clock import DAY, day_of, fmt, fmt_clock, hour_of, is_dark
from mystery.sim.config import (DRINK_COST, DRINK_PRICE, ODD_JOB_PAY, PUB_MEAL_COST, PUB_MEAL_PRICE,
                                TILL_FLOAT)
from mystery.sim.decisions import Plan
from mystery.sim.memory import GOSSIP_KINDS, INCIDENT_KINDS, Claim
from mystery.sim.world import Debt

if TYPE_CHECKING:
    from mystery.sim.engine import Simulation
    from mystery.sim.residents import Resident

INJURY_TEXT = {
    ("assault", 1): "a split lip and bruised ribs",
    ("assault", 2): "a broken nose and two cracked ribs",
    ("collision", 1): "deep bruising down one side and a cut to the head",
    ("collision", 2): "a broken leg and a head wound",
    ("fall", 1): "grazed hands and a sprained ankle",
    ("fall", 2): "a broken wrist and a gash on the forehead",
}


def _title(text: str) -> str:
    """Title case that leaves "Drover's" alone (str.title() would give "Drover'S")."""
    return " ".join(w[:1].upper() + w[1:] for w in text.split(" "))


# ============================================================== dispatch
def perform(sim: "Simulation", r: "Resident", plan: Plan, ta: int) -> None:
    k = plan.kind
    if k == "sleep":
        if sim.loc(r.id) == r.home:
            r.asleep = True
    elif k == "rest":
        r.energy = clamp(r.energy + 3, 0, 100)
        r.stress = clamp(r.stress - 2, 0, 100)
    elif k == "work":
        do_work(sim, r, ta)
    elif k == "eat":
        eat(sim, r, ta)
    elif k == "eat_pub":
        eat_pub(sim, r, ta)
    elif k == "shop":
        shop(sim, r, ta)
    elif k == "drink":
        drink(sim, r, ta)
    elif k == "socialize":
        r.social = clamp(r.social + 6, 0, 100)
        if plan.dest == "pub" and sim.rng.random() < 0.5:
            drink(sim, r, ta, limit=1)
    elif k == "odd_job":
        if sim.staff_at("mill", ta):
            sim.daily[f"odd:{r.id}"] += 1
    elif k == "clinic":
        clinic(sim, r, ta)
    elif k == "repair":
        repair(sim, r, ta)
    elif k == "steal":
        steal(sim, r, plan, ta)
    elif k in ("loan", "repay", "confront", "reconcile", "help"):
        x = plan.target
        if x is None or not sim.awake_at(x, ta, sim.loc(r.id)):
            r.cooldowns[f"{k}:{x}"] = ta + 3 * 60
            return
        {"loan": ask_loan, "repay": repay, "confront": confront, "reconcile": reconcile, "help": help_out}[k](
            sim, r, x, plan, ta)


# ============================================================== daily life
def do_work(sim: "Simulation", r: "Resident", ta: int) -> None:
    r.worked_today = True
    place = r.workplace
    if place is None:
        return
    key = f"opened:{place}"
    if sim.daily.get(key, 0) == 0:
        sim.daily[key] = 1
        loc = sim.world.locations[place]
        for ev in sim.world.evidence_at(place, ta):
            if ev.kind == "forced_door" and r.id not in ev.noticed_by and not sim.made_by(r.id, ev):
                notice(sim, r.id, ev, ta)
        loc.locked = False
        for cid in (f"till:{place}", f"stock:{place}"):
            if cid in sim.world.containers:
                sim.count_container(sim.world.containers[cid], r.id, ta)


def eat(sim: "Simulation", r: "Resident", ta: int) -> None:
    pantry = sim.pantry(r)
    if pantry.food <= 0:
        return
    ev = sim.emit("meal", sim.loc(r.id), [r.id], objects=[pantry.id], intent="lawful", time=ta,
                  summary=f"{r.first} eats.")
    sim.transfer("food", f"box:{pantry.id}", "eaten", 1, ev.id, ta)
    pantry.expected_food -= 1
    r.hunger = clamp(r.hunger - 55, 0, 100)


def eat_pub(sim: "Simulation", r: "Resident", ta: int) -> None:
    staff = [s for s in sim.staff_at("pub", ta) if s != r.id]
    if not staff or r.cash < PUB_MEAL_PRICE:
        return
    till = sim.world.containers["till:pub"]
    ev = sim.emit("pub_meal", "pub", [r.id], [staff[0]], objects=[till.id], data={"paid": PUB_MEAL_PRICE},
                  intent="lawful", time=ta, summary=f"{r.first} buys a meal at the pub.")
    sim.transfer("cash", f"wallet:{r.id}", f"box:{till.id}", PUB_MEAL_PRICE, ev.id, ta)
    till.expected_cash += PUB_MEAL_PRICE
    sim.daily["pub_cogs"] += PUB_MEAL_COST
    sim.world.record("tabs", ta, f"{fmt(ta)} {r.name}: hot meal ({PUB_MEAL_PRICE} cr)", ev.id)
    r.hunger = clamp(r.hunger - 60, 0, 100)
    r.social = clamp(r.social + 5, 0, 100)


def drink(sim: "Simulation", r: "Resident", ta: int, limit: int = 2) -> None:
    staff = [s for s in sim.staff_at("pub", ta) if s != r.id]
    if not staff:
        return
    n = 1 + (1 if limit > 1 and sim.rng.random() < (1 - r.traits.temperance) * 0.5 else 0)
    n = min(n, r.cash // DRINK_PRICE)
    if n <= 0:
        return
    till = sim.world.containers["till:pub"]
    cost = n * DRINK_PRICE
    ev = sim.emit("drink", "pub", [r.id], [staff[0]], objects=[till.id], data={"drinks": n, "paid": cost},
                  intent="lawful", time=ta, summary=f"{r.first} has {n} drink{'s' if n > 1 else ''}.")
    sim.transfer("cash", f"wallet:{r.id}", f"box:{till.id}", cost, ev.id, ta)
    till.expected_cash += cost
    sim.daily["pub_cogs"] += n * DRINK_COST
    sim.world.record("tabs", ta, f"{fmt(ta)} {r.name}: {n} drink{'s' if n > 1 else ''} ({cost} cr)", ev.id)
    r.intox = clamp(r.intox + 16 * n, 0, 100)
    r.stress = clamp(r.stress - 6, 0, 100)
    r.social = clamp(r.social + 8, 0, 100)
    sim.recent_drinks[r.id] = (sim.recent_drinks[r.id] + [(ta, ev.id)])[-10:]


def shop(sim: "Simulation", r: "Resident", ta: int) -> None:
    staff = [s for s in sim.staff_at("grocery", ta) if s != r.id]
    if not staff:
        return
    sim.daily[f"shopped:{r.household}"] += 1
    price = sim.profile.food_price
    stock, till = sim.world.containers["stock:grocery"], sim.world.containers["till:grocery"]
    pantry = sim.pantry(r)
    size = len(sim.members(r))
    want = min(max(0, size * 8 - pantry.food), stock.food)
    if want == 0:
        if stock.food == 0:
            ev = sim.emit("no_stock", "grocery", [r.id], time=ta, summary=f"{r.first} finds the grocery shelves empty.")
            sim.add_pressure(r, ev, 5)
        return
    units = min(want, r.cash // price)
    clerk = staff[sim.rng.randrange(len(staff))]
    if units > 0:
        cost = units * price
        ev = sim.emit("purchase", "grocery", [r.id], [clerk], objects=[till.id, stock.id],
                      data={"units": units, "paid": cost}, intent="lawful", time=ta,
                      summary=f"{r.first} buys {units} units of food for {cost}.")
        sim.transfer("cash", f"wallet:{r.id}", f"box:{till.id}", cost, ev.id, ta)
        sim.transfer("food", f"box:{stock.id}", f"box:{pantry.id}", units, ev.id, ta)
        till.expected_cash += cost
        stock.expected_food -= units
        pantry.expected_food += units
        line = f"{fmt(ta)} sale to {r.name}: {units} units, {cost} cr"
        sim.world.record("ledger", ta, line, ev.id)
        sim.add_belief(r.id, Claim("purchase", subject=r.id, location="grocery", start=ta, amount=cost,
                                   detail=f"{units} units"), "self", 0.95, ta, event=ev.id)
        recorder = sim.residents[clerk]
        if sim.rng.random() < 0.015 * (1 - recorder.traits.diligence):
            err = sim.emit("ledger_error", "grocery", [clerk], objects=[till.id], data={"amount": cost},
                           causes=[ev.id], intent="accidental", time=ta + 1,
                           summary=f"{recorder.first} absent-mindedly writes {r.first}'s sale into the ledger twice.")
            sim.world.record("ledger", ta + 1, line, err.id)
            till.expected_cash += cost
            till.unexplained.append(err.id)
            existing = [i for i in sim.incidents if i.family == "accounting_error" and i.discovered_at is None
                        and i.location == "grocery"]
            if existing:
                existing[0].related_events.append(err.id)
            else:
                sim.register_incident(family="accounting_error", core_event=err.id, time=err.time, location="grocery",
                                      responsible=None, victims=list(till.owners), intent="accidental",
                                      mechanism="accounting_error", outcome="no_crime", severity=0,
                                      hook_kind="money_missing", motive="none")
    if units < want and units < size * 3:
        ask_credit(sim, r, staff, want - units, ta)


def ask_credit(sim: "Simulation", r: "Resident", staff: list[str], need: int, ta: int) -> None:
    owners = [s for s in staff if s in sim.world.locations["grocery"].owners]
    stock = sim.world.containers["stock:grocery"]
    price = sim.profile.food_price
    if not owners:
        ev = sim.emit("credit_refused", "grocery", [staff[0]], [r.id], data={"why": "only the owner gives credit"},
                      audibility=1, time=ta + 2, summary=f"{r.first} is told only the owner can give credit.")
        sim.add_pressure(r, ev, 4)
        return
    grocer = sim.residents[owners[0]]
    rel = grocer.r(r.id)
    outstanding = sum(d.amount for d in sim.open_debts(r.id) if d.creditor == grocer.id and d.kind == "credit")
    p = 0.25 + 0.5 * grocer.traits.empathy + 0.3 * rel.trust - 0.5 * rel.resentment
    units = min(need, 10, stock.food)
    if units > 0 and outstanding < 40 and sim.rng.random() < p:
        amount = units * price
        ev = sim.emit("credit", "grocery", [grocer.id], [r.id], objects=[stock.id], data={"units": units, "owed": amount},
                      intent="lawful", audibility=1, time=ta + 2,
                      summary=f"{grocer.first} lets {r.first} take {units} units on credit.")
        sim.transfer("food", f"box:{stock.id}", f"box:{sim.pantry(r).id}", units, ev.id, ta + 2)
        stock.expected_food -= units
        sim.pantry(r).expected_food += units
        sim.world.debts.append(Debt(f"D{len(sim.world.debts) + 1:03d}", r.id, grocer.id, amount, ta + 7 * DAY, ta,
                                    ev.id, kind="credit"))
        sim.world.record("ledger", ta + 2, f"{fmt(ta)} on credit to {r.name}: {units} units ({amount} cr owed)", ev.id)
        claim = Claim("debt", subject=r.id, other=grocer.id, amount=amount, detail="credit")
        for p_ in (r.id, grocer.id):
            sim.add_belief(p_, claim, "self", 1.0, ta + 2, event=ev.id)
        sim.broadcast(ev, seen=claim)
    else:
        ev = sim.emit("credit_refused", "grocery", [grocer.id], [r.id], audibility=1, time=ta + 2,
                      summary=f"{grocer.first} refuses {r.first} credit.")
        sim.add_pressure(r, ev, 8)
        r.r(grocer.id).resentment = clamp(r.r(grocer.id).resentment + 0.06)
        claim = Claim("refusal", subject=grocer.id, other=r.id, start=ta, detail="credit at the grocery")
        sim.add_belief(r.id, claim, "self", 1.0, ta + 2, event=ev.id)
        sim.add_belief(grocer.id, claim, "self", 1.0, ta + 2, event=ev.id)
        sim.add_belief(grocer.id, Claim("hardship", subject=r.id, start=ta, detail="cannot pay for food"), "self", 0.9,
                       ta + 2, event=ev.id)
        sim.broadcast(ev, seen=claim)


def close_business(sim: "Simulation", place: str, tm: int) -> None:
    loc = sim.world.locations[place]
    staff = sim.staff_at(place, tm)
    if not staff:
        return
    owners_here = [s for s in staff if s in loc.owners]
    closer = sim.residents[owners_here[0] if owners_here else staff[0]]
    owner = sim.residents[loc.owners[0]] if loc.owners else None
    if place in ("grocery", "pub"):
        for rid in sim.ids:
            x = sim.residents[rid]
            if x.alive and not x.down and rid not in loc.staff and sim.where(rid, tm) == place:
                sim.forced[rid] = Plan("rest", x.home)  # closing time: everybody out
        till = sim.world.containers[f"till:{place}"]
        sim.count_container(till, closer.id, tm)
        if place == "grocery":
            sim.count_container(sim.world.containers["stock:grocery"], closer.id, tm)
        book = "ledger" if place == "grocery" else "tabs"
        cogs = sim.daily.get("pub_cogs", 0) if place == "pub" else 0
        if cogs and till.cash > 0:
            pay = min(cogs, till.cash)
            ev = sim.emit("supplier_costs", place, [closer.id], objects=[till.id], data={"amount": pay}, intent="lawful",
                          time=tm, summary=f"{closer.first} settles the day's supplier costs ({pay}).")
            sim.transfer("cash", f"box:{till.id}", "outside", pay, ev.id, tm)
            till.expected_cash -= pay
            sim.world.record(book, tm, f"{fmt(tm)} supplier costs paid: {pay} cr", ev.id)
        for emp in loc.staff:
            e = sim.residents[emp]
            if emp in loc.owners or not e.worked_today or not e.alive or not e.wage:
                continue
            _pay_wage(sim, e, till, owner, place, tm, book, closer.id)
        float_ = TILL_FLOAT[place]
        if owner and owner.alive and owner.id in staff and till.cash - float_ > 20:
            take = till.cash - float_
            ev = sim.emit("owner_withdrawal", place, [owner.id], objects=[till.id], data={"amount": take},
                          intent="lawful", time=tm, summary=f"{owner.first} takes the day's takings ({take}).")
            sim.transfer("cash", f"box:{till.id}", f"wallet:{owner.id}", take, ev.id, tm)
            till.expected_cash -= take
            sim.world.record(book, tm, f"{fmt(tm)} owner took {take} cr of takings", ev.id)
    elif place == "mill":
        box = sim.world.containers["cashbox:mill"]
        hands = [sim.residents[e] for e in loc.staff
                 if e not in loc.owners and sim.residents[e].worked_today and sim.residents[e].alive
                 and sim.residents[e].wage]
        casuals = [r for r in sim.alive() if sim.daily.get(f"odd:{r.id}", 0) >= 3]
        revenue = max(0, sum(h.wage for h in hands) + ODD_JOB_PAY * len(casuals) + sim.profile.mill_margin)
        if revenue:
            ev = sim.emit("mill_sales", "mill", [closer.id], objects=[box.id], data={"amount": revenue},
                          intent="lawful", time=tm, summary=f"The mill's timber sales bring in {revenue}.")
            sim.transfer("cash", "outside", f"box:{box.id}", revenue, ev.id, tm)
            box.expected_cash += revenue
        for e in hands:
            _pay_wage(sim, e, box, owner, place, tm, None, closer.id)
        for c in casuals:
            pay = int(round(ODD_JOB_PAY * sim.profile.wage_mult))
            if box.cash >= pay:
                ev = sim.emit("wage", "mill", [closer.id], [c.id], objects=[box.id], data={"amount": pay, "casual": True},
                              intent="lawful", time=tm, summary=f"{c.first} is paid {pay} for a day's casual work.")
                sim.transfer("cash", f"box:{box.id}", f"wallet:{c.id}", pay, ev.id, tm)
                box.expected_cash -= pay
        if owner and owner.alive and owner.id in staff and box.cash > 300:
            take = box.cash - 300
            ev = sim.emit("owner_withdrawal", "mill", [owner.id], objects=[box.id], data={"amount": take},
                          intent="lawful", time=tm, summary=f"{owner.first} takes {take} profit from the mill.")
            sim.transfer("cash", f"box:{box.id}", f"wallet:{owner.id}", take, ev.id, tm)
            box.expected_cash -= take
    else:
        for emp in staff:
            e = sim.residents[emp]
            if e.wage and e.worked_today:
                ev = sim.emit("wage", place, [e.id], data={"amount": e.wage, "from": "outside"}, intent="lawful", time=tm,
                              summary=f"{e.first} is paid {e.wage} for the day.")
                sim.transfer("cash", "outside", f"wallet:{e.id}", e.wage, ev.id, tm)
    loc.locked = sim.rng.random() < 0.15 + 0.8 * closer.traits.diligence


def _pay_wage(sim, e, box, owner, place: str, tm: int, book: str | None, payer: str) -> None:
    """Wages come out of the business; an owner covers a short till from their own pocket."""
    if box.cash >= e.wage:
        src, note = f"box:{box.id}", ""
    elif owner is not None and owner.alive and owner.cash >= e.wage:
        src, note = f"wallet:{owner.id}", " (paid by the owner personally)"
    else:
        ev = sim.emit("wage_unpaid", place, [payer], [e.id], data={"amount": e.wage}, time=tm,
                      summary=f"There is not enough money to pay {e.first}.")
        sim.add_pressure(e, ev, 10)
        for o in sim.world.locations[place].owners:
            e.r(o).resentment = clamp(e.r(o).resentment + 0.1)
        return
    ev = sim.emit("wage", place, [payer], [e.id], objects=[box.id], data={"amount": e.wage, "source": src},
                  intent="lawful", time=tm, summary=f"{e.first} is paid {e.wage} for the day{note}.")
    sim.transfer("cash", src, f"wallet:{e.id}", e.wage, ev.id, tm)
    if src.startswith("box:"):
        box.expected_cash -= e.wage
    if book:
        sim.world.record(book, tm, f"{fmt(tm)} wages to {e.name}: {e.wage} cr{note}", ev.id)


# ============================================================== interactions
def ask_loan(sim: "Simulation", r: "Resident", x: str, plan: Plan, ta: int) -> None:
    lender = sim.residents[x]
    here = sim.loc(r.id)
    r.cooldowns[f"loan:{x}"] = ta + 5 * DAY
    amount = int(clamp(sim.shortfall(r, ta) + 10, 20, 100))
    amount = min(amount, max(0, lender.cash - 30))
    rel = lender.r(r.id)
    p = 0.15 + 0.45 * lender.traits.empathy + 0.35 * rel.trust + 0.25 * rel.affection - 0.7 * rel.resentment
    p -= 0.3 * lender.traits.caution
    # what the lender has heard about the borrower's other debts
    owed = {b.claim.other for b in sim.memory[x].of_kind("debt") if b.claim.subject == r.id}
    repaid = {b.claim.other for b in sim.memory[x].of_kind("debt") if b.claim.subject == r.id
              and b.claim.detail == "repaid"}
    p -= 0.25 * len(owed - repaid)
    if amount >= 20 and sim.rng.random() < p:
        ev = sim.emit("loan", here, [x], [r.id], data={"amount": amount}, intent="lawful", audibility=1, time=ta,
                      summary=f"{lender.first} lends {r.first} {amount} crowns.")
        sim.transfer("cash", f"wallet:{x}", f"wallet:{r.id}", amount, ev.id, ta)
        sim.world.debts.append(Debt(f"D{len(sim.world.debts) + 1:03d}", r.id, x, amount, ta + 7 * DAY, ta, ev.id))
        claim = Claim("debt", subject=r.id, other=x, amount=amount, start=ta, detail="loan")
        for p_ in (r.id, x):
            sim.add_belief(p_, claim, "self", 1.0, ta, event=ev.id)
        sim.broadcast(ev, seen=Claim("loan", subject=r.id, other=x, location=here, start=ta))
        r.r(x).trust = clamp(r.r(x).trust + 0.05)
        r.r(x).affection = clamp(r.r(x).affection + 0.05)
    else:
        r.cooldowns["loan"] = ta + DAY
        ev = sim.emit("loan_refused", here, [x], [r.id], data={"asked": amount}, audibility=1, time=ta,
                      summary=f"{lender.first} refuses to lend {r.first} money.")
        sim.add_pressure(r, ev, 8)
        r.r(x).resentment = clamp(r.r(x).resentment + 0.08 + 0.12 * r.traits.stubbornness)
        claim = Claim("refusal", subject=x, other=r.id, start=ta, detail="a loan")
        sim.add_belief(r.id, claim, "self", 1.0, ta, event=ev.id)
        sim.add_belief(x, claim, "self", 1.0, ta, event=ev.id)
        sim.add_belief(x, Claim("hardship", subject=r.id, start=ta, detail="asking around for money"), "self", 0.9, ta,
                       event=ev.id)
        sim.broadcast(ev, seen=claim)


def repay(sim: "Simulation", r: "Resident", x: str, plan: Plan, ta: int) -> None:
    debt = next((d for d in sim.open_debts(r.id) if d.id == plan.data.get("debt")), None)
    if debt and r.cash >= debt.amount:
        settle_debt(sim, r, debt, ta, sim.loc(r.id))


def settle_debt(sim: "Simulation", r: "Resident", debt: Debt, t: int, here: str) -> None:
    ev = sim.emit("repay", here, [r.id], [debt.creditor], data={"amount": debt.amount, "debt": debt.id},
                  causes=[debt.origin_event], intent="lawful", audibility=1, time=t,
                  summary=f"{r.first} repays {debt.amount} to {sim.n(debt.creditor)}.")
    sim.transfer("cash", f"wallet:{r.id}", f"wallet:{debt.creditor}", debt.amount, ev.id, t)
    debt.settled, debt.settled_event = t, ev.id
    claim = Claim("debt", subject=r.id, other=debt.creditor, amount=debt.amount, start=t, detail="repaid")
    for p_ in (r.id, debt.creditor):
        sim.add_belief(p_, claim, "self", 1.0, t, event=ev.id)
    sim.broadcast(ev, seen=claim)
    cred = sim.residents[debt.creditor]
    cred.r(r.id).resentment = clamp(cred.r(r.id).resentment - 0.15)


def help_out(sim: "Simulation", r: "Resident", x: str, plan: Plan, ta: int) -> None:
    r.cooldowns[f"help:{x}"] = ta + 4 * DAY
    amount = 25
    if r.cash < amount + 30:
        return
    ev = sim.emit("help", sim.loc(r.id), [r.id], [x], data={"amount": amount}, intent="lawful", audibility=1, time=ta,
                  summary=f"{r.first} gives {sim.n(x)} {amount} crowns to tide them over.")
    sim.transfer("cash", f"wallet:{r.id}", f"wallet:{x}", amount, ev.id, ta)
    claim = Claim("help", subject=r.id, other=x, start=ta, amount=amount)
    for p_ in (r.id, x):
        sim.add_belief(p_, claim, "self", 1.0, ta, event=ev.id)
    target = sim.residents[x]
    target.r(r.id).affection = clamp(target.r(r.id).affection + 0.1)
    target.r(r.id).trust = clamp(target.r(r.id).trust + 0.08)


def reconcile(sim: "Simulation", r: "Resident", x: str, plan: Plan, ta: int) -> None:
    r.cooldowns[f"reconcile:{x}"] = ta + 4 * DAY
    target = sim.residents[x]
    p = 0.4 + 0.4 * target.traits.empathy - 0.4 * target.traits.stubbornness - 0.3 * target.r(r.id).resentment
    ok = sim.rng.random() < p
    ev = sim.emit("reconcile", sim.loc(r.id), [r.id], [x], data={"accepted": ok}, intent="lawful", audibility=1,
                  time=ta, summary=f"{r.first} tries to make peace with {target.first}"
                                   f" ({'accepted' if ok else 'rebuffed'}).")
    if ok:
        r.r(x).resentment = round(r.r(x).resentment * 0.5, 3)
        target.r(r.id).resentment = round(target.r(r.id).resentment * 0.5, 3)
        sim.stats["deescalation:reconcile"] += 1
    claim = Claim("reconcile", subject=r.id, other=x, start=ta, detail="accepted" if ok else "rebuffed")
    for p_ in (r.id, x):
        sim.add_belief(p_, claim, "self", 1.0, ta, event=ev.id)


def confront(sim: "Simulation", r: "Resident", x: str, plan: Plan, ta: int) -> None:
    target = sim.residents[x]
    here = sim.loc(r.id)
    pair = tuple(sorted((r.id, x)))
    if sim.daily.get(f"argued:{pair}", -1) >= ta - 6 * 60:
        return  # they have only just had it out
    sim.daily[f"argued:{pair}"] = ta
    reason, ref = plan.reason, plan.data.get("ref")
    r.cooldowns[f"confront:{x}"] = ta + {"debt": 4, "rent": 4, "suspicion": 5}.get(reason or "", 7) * DAY
    causes: list[str] = []
    debt = None
    incident_core = None
    if reason in ("debt", "rent"):
        debt = next((d for d in sim.world.debts if d.id == ref), None)
        if debt is None or debt.settled is not None:
            return
        topic = f"money owed ({debt.amount} crowns{' of rent' if debt.kind == 'rent' else ''})"
        causes = [debt.overdue_event or debt.origin_event]
    elif reason == "suspicion":
        b = sim.beliefs[ref]
        topic = f"an accusation over {b.claim.detail}"
        premise_events = [sim.beliefs[p].event for p in b.premises if sim.beliefs[p].event]
        causes = premise_events[:3]
        incident_core = _incident_core_for_claim(sim, b.claim)
    else:
        topic = "an old grievance"
        causes = [e.id for e in sim.log.events[:20] if e.kind == "prior_grudge" and r.id in e.actors + e.targets
                  and x in e.actors + e.targets]
    ev = sim.emit("argument", here, [r.id], [x], data={"reason": reason, "topic": topic}, causes=causes,
                  audibility=2, notable=True, time=ta, summary=f"{r.first} confronts {target.first} about {topic}.")
    sim.stats["confrontations"] += 1
    seen = Claim("argument", subject=r.id, other=x, location=here, start=ta, detail=topic)
    heard_detail = "raised voices" + (", something about money" if reason in ("debt", "rent") else "")
    sim.broadcast(ev, seen=seen, heard=Claim("noise", location=here, start=ta, detail=heard_detail), voice=r.id)
    for p_ in (r.id, x):
        sim.add_belief(p_, seen, "self", 1.0, ta, event=ev.id)
    guilty = incident_core is not None and incident_core in target.guilty_of
    if reason == "suspicion":
        sim.add_belief(x, Claim("suspect", subject=x, location=sim.beliefs[ref].claim.location,
                                start=sim.beliefs[ref].claim.start, end=sim.beliefs[ref].claim.end,
                                detail=sim.beliefs[ref].claim.detail), "told", 0.9, ta, event=ev.id, told_by=r.id,
                       via=ref)
        if not guilty:
            target.r(r.id).resentment = clamp(target.r(r.id).resentment + 0.2)

    if debt is not None and target.cash >= debt.amount:
        settle_debt(sim, target, debt, ta + 1, here)
        sim.stats["deescalation:paid"] += 1
        return
    if guilty:
        T = target.traits
        if sim.rng.random() < 0.05 + 0.5 * T.honesty * T.empathy - 0.25 * T.caution:
            _confess(sim, target, r, incident_core, ev, here, ta + 1)
            sim.stats["deescalation:confession"] += 1
            return

    a, b = r, target
    bystanders = [y for y in sim.ids if y not in (r.id, x) and sim.awake_at(y, ta, here)]
    heat = (0.5 * a.r(x).resentment + 0.5 * b.r(r.id).resentment
            + 0.25 * (a.traits.impulsiveness + b.traits.impulsiveness) / 2
            + (a.intox + b.intox) / 400 + sim.profile.impulsive_shift)
    calm = (0.35 * (a.traits.empathy + b.traits.empathy) / 2 + 0.25 * (a.traits.caution + b.traits.caution) / 2
            + 0.08 * len(bystanders))
    p = clamp(heat - calm - 0.42, 0, 0.25)
    if sim.rng.random() < p:
        def aggression(p_, o):
            return p_.traits.impulsiveness + p_.intox / 100 + p_.r(o.id).resentment
        aggressor, victim = (a, b) if aggression(a, b) >= aggression(b, a) else (b, a)
        assault(sim, aggressor, victim, ev, here, ta + 2, bystanders, reason)
        return
    outcome = "walked_away"
    if debt is not None:
        # the usual off-ramp for money owed: a promise and a new date
        outcome = "promise"
        debt.due = ta + 7 * DAY
        debt.overdue_event = None
    elif a.traits.empathy + b.traits.empathy > 1.2 and sim.rng.random() < 0.4:
        outcome = "apology"
        a.r(x).resentment = round(a.r(x).resentment * 0.7, 3)
        b.r(r.id).resentment = round(b.r(r.id).resentment * 0.7, 3)
    else:
        a.r(x).resentment = clamp(a.r(x).resentment + 0.05)
        b.r(r.id).resentment = clamp(b.r(r.id).resentment + 0.08)
    sim.emit("parted", here, [r.id], [x], data={"outcome": outcome}, causes=[ev.id], intent="lawful", time=ta + 2,
             summary=f"{r.first} and {target.first} part ({outcome.replace('_', ' ')}).")
    sim.stats[f"deescalation:{outcome}"] += 1


def _incident_core_for_claim(sim: "Simulation", claim: Claim) -> str | None:
    for inc in sim.incidents:
        if inc.location == claim.location and claim.start is not None and inc.discovered_at is not None:
            if (claim.start - 6 * 60) <= inc.time <= ((claim.end or claim.start) + 6 * 60):
                return inc.core_event
    return None


def _confess(sim: "Simulation", culprit: "Resident", to: "Resident", core: str, cause, here: str, t: int) -> None:
    inc = sim.incident_for(core)
    ev = sim.emit("confession", here, [culprit.id], [to.id], causes=[cause.id, core], intent="lawful", audibility=1,
                  notable=True, time=t, summary=f"{culprit.first} confesses to {to.first}.")
    if inc is not None:
        inc.reported_openly = True
    stash = sim.world.containers.get(f"stash:{culprit.id}")
    if stash is not None and stash.cash > 0 and inc is not None and inc.family == "theft":
        sim.transfer("cash", f"box:{stash.id}", f"wallet:{to.id}", stash.cash, ev.id, t)
    claim = Claim("confession", subject=culprit.id, other=to.id, start=t, detail=sim.log.by_id[core].kind)
    for p_ in (culprit.id, to.id):
        sim.add_belief(p_, claim, "self", 1.0, t, event=ev.id)
    sim.broadcast(ev, seen=claim)
    culprit.stress = clamp(culprit.stress - 20, 0, 100)


def assault(sim: "Simulation", aggressor: "Resident", victim: "Resident", cause, here: str, t: int,
            bystanders: list[str], reason: str | None) -> None:
    roll = sim.rng.random()
    fatal_p = 0.015 + 0.02 * aggressor.intox / 100
    severity = 3 if roll < fatal_p else 2 if roll < fatal_p + 0.25 else 1
    intervened = [y for y in bystanders if sim.rng.random() < 0.5]
    if intervened:
        severity = 1
    ev = sim.emit("assault", here, [aggressor.id], [victim.id], data={"severity": severity, "reason": reason},
                  causes=[cause.id], intent="impulsive", audibility=2, notable=True, time=t,
                  summary=f"{aggressor.first} attacks {victim.first}.")
    sim.stats["assaults"] += 1
    claim = Claim("assault", subject=aggressor.id, other=victim.id, location=here, start=t)
    sim.broadcast(ev, seen=claim, heard=Claim("noise", location=here, start=t,
                                              detail="a scuffle, something breaking and someone crying out"),
                  voice=victim.id)
    for p_ in (aggressor.id, victim.id):
        sim.add_belief(p_, claim, "self", 1.0, t, event=ev.id)
    if intervened:
        sim.emit("intervened", here, intervened, [aggressor.id], causes=[ev.id], intent="lawful", time=t + 1,
                 summary=f"{', '.join(sim.n(y) for y in intervened)} pull {aggressor.first} away.")
    aggressor.guilty_of.append(ev.id)
    aggressor.stress = clamp(aggressor.stress + 25, 0, 100)
    aggressor.cooldowns[f"confront:{victim.id}"] = t + 14 * DAY
    victim.cooldowns[f"confront:{aggressor.id}"] = t + 14 * DAY
    victim.r(aggressor.id).resentment = clamp(victim.r(aggressor.id).resentment + 0.5)
    victim.r(aggressor.id).trust = 0.05
    motive = "intoxication" if aggressor.intox >= 50 else ("money_trouble" if reason in ("debt", "rent") else "grudge")
    inc = sim.register_incident(family="assault", core_event=ev.id, time=t, location=here, responsible=aggressor.id,
                                victims=[victim.id], intent="impulsive", mechanism="assaulted", outcome="crime",
                                severity=severity, hook_kind="person_dead" if severity == 3 else "person_injured",
                                motive=motive, related_events=[cause.id])
    place = sim.world.name(here)
    if severity >= 2:
        sim.world.add_evidence("blood", here, f"Spots of blood and a broken chair at {place}.", t, ev.id)
    if severity == 3:
        kill(sim, victim, ev, t + 1)
        witnesses = [y for y in bystanders if sim.residents[y].alive]
        if witnesses:
            sim.discover(inc, witnesses[0], t, ev.id, f"{victim.name} died after being attacked at {place} "
                         f"around {fmt_clock(t)} on Day {day_of(t)}.", f"The Death at {_title(place)}",
                         [t - 30, t + 30], here)
    else:
        injure(sim, victim, severity, ev, INJURY_TEXT[("assault", severity)])
        sim.discover(inc, victim.id, t, ev.id, f"{victim.name} was hurt in a fight at {place} around "
                     f"{fmt_clock(t)} on Day {day_of(t)}: {victim.injury_desc}.", f"The Fight at {_title(place)}",
                     [t - 30, t + 30], here)


def injure(sim: "Simulation", v: "Resident", severity: int, ev, desc: str) -> None:
    v.injury = max(v.injury, severity)
    v.injury_event = ev.id
    v.injury_desc = desc
    v.injury_treated = False
    v.stress = clamp(v.stress + 20, 0, 100)


def kill(sim: "Simulation", v: "Resident", cause, t: int) -> None:
    here = sim.loc(v.id)
    v.alive = False
    v.asleep = False
    v.down = False
    dev = sim.emit("death", here, [v.id], data={"cause": cause.kind}, causes=[cause.id], notable=True, time=t,
                   summary=f"{v.first} dies.")
    v.death_event = dev.id
    sim.stats["deaths"] += 1
    pattern = {"assault": "There are heavy blows to the head and face.",
               "collision": "The injuries look like a heavy impact from the side, the legs broken.",
               "fall": "There is a deep wound to the head."}.get(cause.kind, "")
    sim.world.add_evidence("body", here, f"The body of {v.name} lies at {sim.world.name(here)}. {pattern}", t, dev.id)


# ============================================================== crime
def steal(sim: "Simulation", r: "Resident", plan: Plan, ta: int) -> None:
    cid = plan.target
    c = sim.world.containers[cid]  # type: ignore[index]
    loc_id = c.location
    loc = sim.world.locations[loc_id]
    r.cooldowns["steal"] = ta + 4 * DAY
    others = [x for x in sim.ids if x != r.id and sim.residents[x].alive and sim.where(x, ta) == loc_id]
    if others:
        sim.emit("theft_aborted", loc_id, [r.id], objects=[cid], data={"why": "someone was there"},
                 intent="intentional", discreet=True, time=ta, summary=f"{r.first} meant to steal but someone was there.")
        return
    causes = r.recent_pressures(ta)
    forced = None
    if loc.lockable and loc.locked:
        if r.traits.caution > 0.7 and sim.rng.random() < 0.5:
            sim.emit("theft_aborted", loc_id, [r.id], objects=[cid], data={"why": "the door was locked"},
                     intent="intentional", discreet=True, time=ta, summary=f"{r.first} finds the door locked and leaves.")
            return
        forced = sim.emit("forced_entry", loc_id, [r.id], objects=[cid], causes=causes, intent="intentional",
                          audibility=2, notable=True, time=ta, summary=f"{r.first} forces the door of {loc.name}.")
        loc.locked = False
        sim.world.add_evidence("forced_door", loc_id, f"The back door of {loc.name} has been forced: the latch is "
                               f"bent and the frame splintered.", ta, forced.id)
        sim.broadcast(forced, heard=Claim("noise", location=loc_id, start=ta, detail="a crack of splintering wood"))
    food = cid.startswith("stock:")
    have = c.food if food else c.cash
    amount = min(have, sim.rng.randint(8, 16)) if food else int(have * sim.rng.uniform(0.5, 0.9))
    if amount <= 0:
        sim.emit("theft_aborted", loc_id, [r.id], objects=[cid], data={"why": "nothing worth taking"},
                 intent="intentional", discreet=True, time=ta + 2, summary=f"{r.first} finds nothing to take.")
        return
    asset = "food" if food else "cash"
    ev = sim.emit("theft", loc_id, [r.id], objects=[cid], data={"asset": asset, "amount": amount},
                  causes=causes + ([forced.id] if forced else []), intent="intentional", discreet=True, notable=True,
                  time=ta + 2, summary=f"{r.first} takes {amount} {'units of food' if food else 'crowns'} "
                                       f"from {c.label}.")
    sim.stats["thefts"] += 1
    stash = sim.stash(r)
    sim.transfer(asset, f"box:{cid}", f"box:{stash.id}", amount, ev.id, ta + 2)
    c.unexplained.append(ev.id)
    r.guilty_of.append(ev.id)
    r.pending_hide.append(ev.id)
    r.stress = clamp(r.stress + 20, 0, 100)
    sim.add_belief(r.id, Claim("theft_self", subject=r.id, location=loc_id, start=ta + 2, amount=amount, obj=cid),
                   "self", 1.0, ta + 2, event=ev.id)
    owners = [o for o in c.owners if sim.residents[o].alive]
    spite = max((r.r(o).resentment for o in owners), default=0.0)
    sim.register_incident(family="theft", core_event=ev.id, time=ev.time, location=loc_id, responsible=r.id,
                          victims=owners, intent="intentional", mechanism="stolen", outcome="crime", severity=1,
                          hook_kind="goods_missing" if food else "money_missing",
                          motive="grudge" if spite >= 0.5 and sim.pressure[r.id] < 0.6 else "money_trouble",
                          related_events=[forced.id] if forced else [])


def hide_loot(sim: "Simulation", r: "Resident", t: int) -> None:
    stash = sim.stash(r)
    house = f"the {r.last} house"
    for theft_id in r.pending_hide:
        cid = sim.log.by_id[theft_id].objects[0]
        if cid == "till:grocery":
            desc = f"A canvas till bag stamped 'GROCERY', pushed behind a loose board in the woodshed of {house}."
        elif cid == "till:pub":
            desc = f"A leather coin pouch from the till at {sim.world.pub_name}, hidden under a mattress in {house}."
        elif cid.startswith("stock:"):
            desc = f"A flour sack and tins bearing the grocery's stock stamp, under a tarpaulin in the shed of {house}."
        else:
            desc = f"A roll of banknotes wrapped in a cloth and wedged in the chimney nook of {house}."
        ev = sim.emit("hide_loot", r.home, [r.id], objects=[stash.id], causes=[theft_id], intent="intentional",
                      discreet=True, time=t, summary=f"{r.first} hides the loot at home.")
        sim.world.add_evidence("stash", r.home, desc, t, ev.id, [r.id])
        sim.add_belief(r.id, Claim("stash", subject=r.id, location=r.home, start=t, obj=cid), "self", 1.0, t, event=ev.id)
        if cid.startswith("stock:") and stash.food > 0:
            sim.transfer("food", f"box:{stash.id}", f"box:{sim.pantry(r).id}", stash.food, ev.id, t)
    r.pending_hide = []


def loss_discovered(sim: "Simulation", c, counter: str, t: int, short_cash: int, short_food: int) -> None:
    what = (f"{short_cash} crowns missing from {c.label}" if short_cash
            else f"{short_food} units of stock missing from {c.label}")
    ev = sim.emit("loss_discovered", c.location, [counter], objects=[c.id],
                  data={"cash": short_cash, "food": short_food, "window": [c.last_check, t]}, causes=list(c.unexplained),
                  audibility=1, notable=True, time=t, summary=f"{sim.n(counter)} finds {what}.")
    claim = Claim("loss", location=c.location, start=c.last_check, end=t, amount=short_cash or short_food, obj=c.id,
                  detail=what)
    sim.add_belief(counter, claim, "self", 0.95, t, event=ev.id)
    sim.broadcast(ev, seen=claim)
    incs = [i for i in (sim.incident_for(e) for e in c.unexplained) if i is not None]
    if not incs:
        return
    incs.sort(key=lambda i: (0 if i.family == "theft" else 1, i.time))
    primary = incs[0]
    forced = any(e.kind == "forced_door" and e.place == c.location and e.present_at(t) and counter in e.noticed_by
                 for e in sim.world.evidence)
    place = sim.world.name(c.location)
    if c.id.startswith("box:"):
        title = "The Lighter Savings Tin"
        hook = (f"{sim.residents[counter].name} opened {c.label} on Day {day_of(t)} and found {short_cash} crowns "
                f"fewer than there should be. It was last counted {fmt(c.last_check)}.")
    elif short_food and not short_cash:
        title = "The Missing Stock"
        hook = (f"{sim.residents[counter].name} counted the stock room at {place} at {fmt(t)} and found "
                f"{short_food} units missing since {fmt(c.last_check)}.")
    else:
        title = f"The Short Till at {_title(place)}"
        hook = (f"{sim.residents[counter].name} counted {c.label} at {fmt(t)} and found {short_cash} crowns missing. "
                f"It last balanced at {fmt(c.last_check)}.")
    if forced:
        hook += " The back door had been forced."
    for inc in incs:
        if ev.id not in inc.related_events:
            inc.related_events.append(ev.id)
        sim.discover(inc, counter, t, ev.id, hook, title, [c.last_check, t], c.location)
        if inc is not primary:
            inc.case_start = None


# ============================================================== vehicles & roads
def check_collision(sim: "Simulation", rid: str, t0: int, walkers: list[str]) -> None:
    mv = sim.moves[rid]
    path, times = mv["path"], mv["times"]
    if "road" not in path or path.index("road") == len(path) - 1:
        return
    i = path.index("road")
    t_in, t_out = times[i], times[i + 1]
    r = sim.residents[rid]
    dark = is_dark(t_in)
    p = (0.003 if dark else 0.0004) + max(0.0, r.intox - 25) / 100 * (0.12 if dark else 0.04)
    if sim.rng.random() >= p:
        return
    tc = t_in + max(0, (t_out - t_in) // 2)
    peds = [x for x in walkers if sim.residents[x].alive and not sim.residents[x].down and sim.where(x, tc) == "road"]
    victim_id = peds[sim.rng.randrange(len(peds))] if peds and sim.rng.random() < 0.6 else None
    veh = sim.world.vehicles[mv["vehicle"]]
    causes = [eid for (t, eid) in sim.recent_drinks[rid] if tc - t <= 6 * 60]
    intent = "reckless" if r.intox >= 40 else "accidental"
    severity = 0
    if victim_id:
        roll = sim.rng.random()
        severity = 1 if roll < 0.6 else 2 if roll < 0.92 else 3
        damage = "a dented bonnet, a cracked windscreen on the passenger side and a dark smear on the bumper"
        site = "Fragments of headlight glass and a churned, scuffed patch of mud at the edge of Mill Road."
        glimpse = "headlight glass and churned mud at the edge of Mill Road"
        struck = sim.residents[victim_id].first
    else:
        damage = "a dented front bumper, a cracked headlight and flecks of white paint and wood splinters in the grille"
        site = "Two rails of the white fence along Mill Road are smashed; fragments of headlight glass lie on the verge."
        glimpse = "the white fence along Mill Road smashed, with headlight glass on the verge"
        struck = "the fence"
    ev = sim.emit("collision", "road", [rid], [victim_id] if victim_id else [], objects=[veh.id],
                  data={"vehicle": veh.id, "struck": victim_id or "fence", "severity": severity,
                        "intox": round(r.intox)}, causes=causes, intent=intent, audibility=3, notable=True, time=tc,
                  summary=f"{r.first}, driving {veh.name}, hits {struck} on Mill Road.")
    sim.stats["collisions"] += 1
    veh.damage, veh.damage_event = damage, ev.id
    vx = sim.world.add_evidence("vehicle_damage", veh.id, f"{veh.name[0].upper()}{veh.name[1:]} has {damage}.", tc,
                                ev.id, [rid])
    veh.damage_evidence = vx.id
    sim.world.add_evidence("debris", "road", site, tc, ev.id, glimpse=glimpse)
    sim.broadcast(ev, seen=Claim("saw_collision", subject=rid, other=victim_id, location="road", start=tc, obj=veh.id,
                                 detail=f"{veh.name} hit {'someone' if victim_id else 'the fence'}"),
                  heard=Claim("noise", location="road", start=tc, detail="a loud crash and an engine"))
    sim.add_belief(rid, Claim("collision_self", subject=rid, other=victim_id, location="road", start=tc, obj=veh.id,
                              detail=f"hit {struck}"), "self", 1.0 if r.intox < 60 else 0.7, tc, event=ev.id)
    if victim_id:
        sim.add_belief(victim_id, Claim("struck", other=victim_id, location="road", start=tc,
                                        detail=f"a {veh.kind}" if sim.rng.random() < 0.6 else "a vehicle"),
                       "self", 0.9, tc, event=ev.id)
    T = r.traits
    p_stop = 0.25 + 0.45 * T.honesty + 0.3 * T.empathy - r.intox / 100 * 0.5 - 0.15 * T.caution
    p_stop += 0.15 if victim_id else 0
    stop = sim.rng.random() < clamp(p_stop, 0.05, 0.95)
    if victim_id:
        hook_kind = "person_dead" if severity == 3 else "person_injured"
    else:
        hook_kind = "property_damaged"
    inc = sim.register_incident(family="collision", core_event=ev.id, time=tc, location="road", responsible=rid,
                                victims=[victim_id] if victim_id else [], intent=intent,
                                mechanism="struck_by_vehicle" if victim_id else "vehicle_collision",
                                outcome="accident" if stop else "crime", severity=severity, hook_kind=hook_kind,
                                motive="intoxication" if intent == "reckless" else "none", fled=not stop)
    victim = sim.residents[victim_id] if victim_id else None
    if stop:
        st = sim.emit("stopped_to_help" if victim else "stopped", "road", [rid], [victim_id] if victim else [],
                      causes=[ev.id], intent="lawful", time=tc, summary=f"{r.first} stops and owns up.")
        inc.reported_openly = True
        if victim is not None:
            sim.truncate(rid, "road", tc)
            sim.truncate(victim.id, "road", tc)
            sim.add_belief(victim.id, Claim("struck", subject=rid, other=victim.id, location="road", start=tc,
                                            obj=veh.id, detail=f"{veh.name}"), "self", 1.0, tc, event=st.id)
            if severity == 3:
                kill(sim, victim, ev, tc)
            else:
                injure(sim, victim, severity, ev, INJURY_TEXT[("collision", severity)])
                sim.forced[victim.id] = Plan("rest", victim.home)
            sim.forced[rid] = Plan("rest", r.home)
        sim.discover(inc, victim_id or rid, tc, st.id, f"{r.name} admits hitting {struck} on Mill Road.",
                     "An Accident on Mill Road", [tc, tc + 1], "road")
        return
    r.guilty_of.append(ev.id)
    r.wants_repair = True
    r.stress = clamp(r.stress + 25, 0, 100)
    if victim is None:
        return
    if severity == 1:
        injure(sim, victim, 1, ev, INJURY_TEXT[("collision", 1)])
        sim.discover(inc, victim.id, tc, ev.id,
                     f"{victim.name} says a vehicle knocked them down on Mill Road {_night_of(tc)} and drove on.",
                     "Hit and Run on Mill Road", [tc - 45, tc + 45], "road")
        return
    sim.truncate(victim.id, "road", tc)
    if severity == 3:
        kill(sim, victim, ev, tc)
    else:
        injure(sim, victim, 2, ev, INJURY_TEXT[("collision", 2)])
        victim.down = True


def _night_of(t: int) -> str:
    d = day_of(t) - (1 if hour_of(t) < 6 else 0)
    return f"on the night of Day {d}"


def check_fall(sim: "Simulation", rid: str, t0: int) -> None:
    mv = sim.moves[rid]
    path, times = mv["path"], mv["times"]
    r = sim.residents[rid]
    if not r.alive or r.down or "road" not in path or path.index("road") == len(path) - 1:
        return
    i = path.index("road")
    if not is_dark(times[i]) or r.intox < 50:
        return
    if sim.rng.random() >= (r.intox - 50) / 100 * 0.15:
        return
    tf = times[i] + max(0, (times[i + 1] - times[i]) // 2)
    severity = 2 if sim.rng.random() < 0.3 else 1
    causes = [eid for (t, eid) in sim.recent_drinks[rid] if tf - t <= 6 * 60]
    ev = sim.emit("fall", "road", [rid], data={"severity": severity, "intox": round(r.intox)}, causes=causes,
                  intent="accidental", audibility=1, notable=True, time=tf,
                  summary=f"{r.first}, drunk, falls into the ditch on Mill Road.")
    sim.stats["falls"] += 1
    sim.world.add_evidence("debris", "road", "Mud scuffed down the bank of the ditch beside Mill Road, and a dropped "
                           "cap in the grass.", tf, ev.id, [],
                           glimpse="scuff marks down the ditch bank on Mill Road and a dropped cap")
    injure(sim, r, severity, ev, INJURY_TEXT[("fall", severity)])
    sim.register_incident(family="fall", core_event=ev.id, time=tf, location="road", responsible=None, victims=[rid],
                          intent="accidental", mechanism="accidental_fall", outcome="accident", severity=severity,
                          hook_kind="person_injured", motive="none")
    # What the victim remembers depends on how drunk they were.
    roll = sim.rng.random()
    if r.intox <= 65 or roll < 0.45:
        sim.add_belief(rid, Claim("fall", subject=rid, location="road", start=tf, detail="slipped into the ditch"),
                       "self", 0.9 if r.intox <= 65 else 0.5, tf, event=ev.id)
    else:
        seen_tonight = [b.claim.subject for b in sim.memory[rid].of_kind("presence", "sighting", since=tf - 5 * 60)
                        if b.claim.subject and b.claim.subject != rid]
        resented = sorted({x for x in seen_tonight if r.r(x).resentment >= 0.3},
                          key=lambda x: (-r.r(x).resentment, x))
        if resented and roll < 0.75:
            sim.add_belief(rid, Claim("assault", subject=resented[0], other=rid, location="road", start=tf,
                                      hedged=True), "inferred", 0.4, tf, event=ev.id, error="mistaken_inference")
        else:
            sim.add_belief(rid, Claim("injury", subject=rid, location="road", start=tf,
                                      detail="no memory of how it happened"), "self", 0.3, tf, event=ev.id)
    if severity == 2:
        sim.truncate(rid, "road", tf)
        r.down = True


# ============================================================== noticing & finding
def notice(sim: "Simulation", rid: str, ev, t: int) -> None:
    ev.noticed_by.append(rid)
    sim.perceived[(rid, ev.created_by)] = "trace"
    if ev.kind == "vehicle_damage":
        veh = sim.world.vehicles[ev.place]
        claim = Claim("vehicle_damage", obj=veh.id, location=veh.location, start=t, detail=veh.damage or "")
    elif ev.kind == "forced_door":
        claim = Claim("damage", location=ev.place, start=t, detail=f"the back door of {sim.world.name(ev.place)} forced")
    elif ev.kind == "blood":
        claim = Claim("damage", location=ev.place, start=t, detail=f"blood at {sim.world.name(ev.place)}")
    else:
        claim = Claim("damage", location=ev.place, start=t, detail=ev.glimpse or ev.kind)
    sim.add_belief(rid, claim, "saw", 0.9, t, event=ev.created_by)
    if ev.kind == "debris":
        inc = sim.incident_for(ev.created_by)
        if inc is not None and inc.discovered_at is None and inc.family == "collision" and not inc.victims:
            found = sim.emit("damage_found", "road", [rid], causes=[ev.created_by], notable=True, time=t,
                             summary=f"{sim.n(rid)} notices the smashed fence on Mill Road.")
            earlier = [s for (loc, s, e) in sim.intervals[rid][:-1] if loc == "road" and s < inc.time]
            start = earlier[-1] if earlier else t - DAY
            sim.discover(inc, rid, t, found.id, f"{sim.residents[rid].name} found the white fence along Mill Road "
                         f"smashed on Day {day_of(t)}, with headlight glass on the verge. Nobody has owned up to it.",
                         "The Smashed Fence", [start, t], "road")


def notice_injury(sim: "Simulation", obs: str, subj: str, node: str, t: int) -> None:
    s = sim.residents[subj]
    since = sim.log.by_id[s.injury_event].time
    if any(b.claim.subject == subj and b.acquired >= since for b in sim.memory[obs].of_kind("injury")):
        return
    sim.add_belief(obs, Claim("injury", subject=subj, location=node, start=t, detail=s.injury_desc or "visibly hurt"),
                   "saw", 0.9, t, event=s.injury_event)
    sim.perceived[(obs, s.injury_event)] = "trace"
    text, claim, _ = patient_account(sim, s)
    if claim is not None:
        sim.add_belief(obs, claim, "told", 0.7, t, told_by=subj, via=_account_belief(sim, s), event=s.injury_event,
                       error=_account_error(sim, s))
    inc = sim.incident_for(s.injury_event)
    if inc is not None and inc.discovered_at is None:
        sim.discover(inc, obs, t, s.injury_event, f"{s.name} turned up hurt on Day {day_of(t)} with "
                     f"{s.injury_desc}. {s.first} says: \"{text}\"", f"The Injuries of {s.name}",
                     [sim.log.by_id[s.injury_event].time - 4 * 60, t], node)


def _account_error(sim: "Simulation", s: "Resident") -> str | None:
    bid = _account_belief(sim, s)
    return sim.beliefs[bid].error if bid else None


def _account_belief(sim: "Simulation", s: "Resident") -> str | None:
    mine = _own_accounts(sim, s)
    return mine[-1].id if mine else None


def _own_accounts(sim: "Simulation", s: "Resident") -> list:
    cause = sim.log.by_id[s.injury_event]
    mine = [b for b in sim.memory[s.id].beliefs if b.event == s.injury_event or
            (cause.kind == "collision" and b.claim.kind == "struck" and b.claim.start == cause.time)]
    mine.sort(key=lambda b: (b.confidence, b.id))
    return mine


def patient_account(sim: "Simulation", s: "Resident"):
    """What an injured person says happened to them (may be mistaken, or a lie)."""
    cause = sim.log.by_id[s.injury_event]
    mine = _own_accounts(sim, s)
    if cause.kind == "assault":
        aggressor = cause.actors[0]
        if s.r(aggressor).affection >= 0.75 and s.traits.honesty < 0.8:
            return "I walked into a door, that's all.", None, True
        return (f"{sim.residents[aggressor].first} hit me.",
                Claim("assault", subject=aggressor, other=s.id, location=cause.location, start=cause.time), False)
    if not mine:
        return "I don't know what happened.", None, False
    b = mine[-1]
    c = b.claim
    if c.kind == "struck":
        if c.subject:
            return (f"{sim.residents[c.subject].first} hit me with {sim.world.name(c.obj) if c.obj else 'a vehicle'} "
                    f"on Mill Road.", copy.copy(c), False)
        return (f"Something hit me on Mill Road — {c.detail}, I think. It didn't stop.", copy.copy(c), False)
    if c.kind == "fall":
        return "I slipped into the ditch on Mill Road. I'd had a few.", copy.copy(c), False
    if c.kind == "assault" and c.subject:
        return (f"I think {sim.residents[c.subject].first} pushed me into the ditch. It's hazy.", copy.copy(c), False)
    return "I can't remember how it happened.", None, False


def found(sim: "Simulation", finder: str, v: "Resident", node: str, t: int) -> None:
    place = sim.world.name(node)
    if v.alive:
        ev = sim.emit("injury_found", node, [finder], [v.id], causes=[v.injury_event], intent="lawful", audibility=1,
                      notable=True, time=t, summary=f"{sim.n(finder)} finds {v.first} lying hurt at {place}.")
        v.down = False
        claim = Claim("injury", subject=v.id, location=node, start=t, detail=f"lying hurt at {place}")
        sim.add_belief(finder, claim, "self", 0.95, t, event=ev.id)
        text, acc, _ = patient_account(sim, v)
        if acc is not None:
            sim.add_belief(finder, acc, "told", 0.7, t, told_by=v.id, via=_account_belief(sim, v), event=ev.id,
                           error=_account_error(sim, v))
        dest = "clinic" if sim.business_open("clinic", t + 60) else v.home
        sim.forced[v.id] = Plan("clinic" if dest == "clinic" else "rest", dest)
        sim.forced[finder] = Plan("escort", dest, target=v.id)
        inc = sim.incident_for(v.injury_event)
        if inc is not None:
            title = "Found in the Ditch" if inc.family == "fall" else "Left on Mill Road"
            sim.discover(inc, finder, t, ev.id, f"{sim.residents[finder].name} found {v.name} lying hurt at {place} "
                         f"at {fmt(t)}. {v.first} says: \"{text}\"", title,
                         [sim.log.by_id[v.injury_event].time - 5 * 60, t], node)
    else:
        ev = sim.emit("body_found", node, [finder], [v.id], causes=[v.death_event], intent="lawful", audibility=2,
                      notable=True, time=t, summary=f"{sim.n(finder)} finds {v.first} dead at {place}.")
        sim.found_bodies.append(v.id)
        for e in sim.world.evidence_at(node, t):
            if e.kind == "body" and finder not in e.noticed_by:
                e.noticed_by.append(finder)
        claim = Claim("death", subject=v.id, location=node, start=t, detail=f"found dead at {place}")
        sim.add_belief(finder, claim, "self", 1.0, t, event=ev.id)
        sim.broadcast(ev, seen=claim, heard=Claim("noise", location=node, start=t, detail="someone shouting for help"))
        sim.residents[finder].stress = clamp(sim.residents[finder].stress + 30, 0, 100)
        cause = sim.log.by_id[sim.log.by_id[v.death_event].causes[0]]
        inc = sim.incident_for(cause.id)
        if inc is not None:
            sim.discover(inc, finder, t, ev.id, f"{sim.residents[finder].name} found {v.name} dead at {place} at "
                         f"{fmt(t)}.", f"The Death of {v.name}", [cause.time - 6 * 60, t], node)


def tidy(sim: "Simulation", r: "Resident", ev, t: int) -> None:
    culprit = sim.made_by(r.id, ev)
    if r.id not in ev.noticed_by and not culprit:
        notice(sim, r.id, ev, t)
    cleaned = sim.emit("cleaned_up", ev.place, [r.id], causes=[ev.created_by], data={"evidence": ev.id},
                       intent="concealment" if culprit else "lawful", time=t,
                       summary=f"{r.first} clears away: {ev.description}")
    ev.removed_at, ev.removed_by = t, cleaned.id


# ============================================================== clinic & workshop
def clinic(sim: "Simulation", r: "Resident", ta: int) -> None:
    staff = [s for s in sim.staff_at("clinic", ta) if s != r.id]
    if not staff or not r.injury:
        return
    nurse = staff[0]
    text, claim, _ = patient_account(sim, r)
    ev = sim.emit("treated", "clinic", [nurse], [r.id], data={"injury": r.injury_desc, "account": text},
                  causes=[r.injury_event], intent="lawful", audibility=1, time=ta,
                  summary=f"{sim.n(nurse)} treats {r.first} for {r.injury_desc}.")
    r.injury_treated = True
    sim.world.record("clinic_log", ta, f"{fmt(ta)} treated {r.name} for {r.injury_desc}. Patient's account: "
                     f"\"{text}\"", ev.id)
    sim.add_belief(nurse, Claim("injury", subject=r.id, location="clinic", start=ta, detail=r.injury_desc), "saw", 0.95,
                   ta, event=ev.id)
    if claim is not None:
        sim.add_belief(nurse, claim, "told", 0.7, ta, told_by=r.id, via=_account_belief(sim, r), event=ev.id,
                       error=_account_error(sim, r))
    inc = sim.incident_for(r.injury_event)
    if inc is not None and inc.discovered_at is None:
        sim.discover(inc, nurse, ta, ev.id, f"{r.name} came to the clinic on Day {day_of(ta)} with {r.injury_desc}. "
                     f"{r.first} says: \"{text}\"", f"The Injuries of {r.name}",
                     [sim.log.by_id[r.injury_event].time - 4 * 60, ta], "clinic")


def repair(sim: "Simulation", r: "Resident", ta: int) -> None:
    veh = sim.world.vehicles[r.vehicle]  # type: ignore[index]
    staff = sim.staff_at("workshop", ta)
    mech = staff[0] if staff else (r.id if r.role == "mechanic" else None)
    if mech is None or veh.location != "workshop" or not veh.damage:
        return
    inc = sim.incident_for(veh.damage_event) if veh.damage_event else None
    conceal = veh.damage_event in r.guilty_of and (inc is None or not inc.reported_openly)
    if conceal:
        explanation = "Hit a deer out on the ridge road a few nights back."
    else:
        struck = sim.log.by_id[veh.damage_event].data.get("struck") if veh.damage_event else None
        explanation = ("Clipped the fence on Mill Road." if struck in (None, "fence")
                       else f"Hit {sim.n(struck)} on Mill Road. An accident.")
    customer = [r.id] if mech != r.id else []
    ev = sim.emit("repair", "workshop", [mech], customer, objects=[veh.id],
                  data={"damage": veh.damage, "explanation": explanation, "concealed": conceal},
                  causes=[veh.damage_event] if veh.damage_event else [], intent="lawful", audibility=1, time=ta,
                  summary=f"{sim.n(mech)} repairs {veh.name}.")
    if mech != r.id:
        if r.cash >= 25:
            sim.transfer("cash", f"wallet:{r.id}", f"wallet:{mech}", 25, ev.id, ta)
        else:
            sim.world.debts.append(Debt(f"D{len(sim.world.debts) + 1:03d}", r.id, mech, 25, ta + 7 * DAY, ta, ev.id,
                                        kind="credit"))
        sim.world.record("workshop_orders", ta, f"{fmt(ta)} {veh.name} ({r.name}): straightened the front panel, "
                         f"replaced the headlight. Customer said: \"{explanation}\"", ev.id)
        sim.add_belief(mech, Claim("vehicle_damage", subject=r.id, obj=veh.id, location="workshop", start=ta,
                                   detail=veh.damage), "saw", 0.95, ta, event=ev.id)
        sim.add_belief(mech, Claim("repair", subject=r.id, obj=veh.id, start=ta, detail=explanation), "told", 0.8, ta,
                       event=ev.id, told_by=r.id, error="lie" if conceal else None)
    else:
        sim.world.record("workshop_orders", ta, f"{fmt(ta)} parts used: one headlight unit and a front panel, for "
                         f"{veh.name} (workshop's own).", ev.id)
    old = next((e for e in sim.world.evidence if e.id == veh.damage_evidence), None)
    if old is not None and old.removed_at is None:
        old.removed_at, old.removed_by = ta, ev.id
    paint = " with flecks of white paint" if "white paint" in (veh.damage or "") else " with a dark stain"
    sim.world.add_evidence("scrap", "workshop", f"In the workshop scrap pile: a cracked headlight unit and a bent front "
                           f"panel{paint}, chalked '{veh.name}'.", ta, ev.id, [r.id])
    veh.damage = veh.damage_event = veh.damage_evidence = None
    r.wants_repair = False


# ============================================================== gossip & inference
def incidental_chats(sim: "Simulation", t0: int) -> None:
    groups: dict[str, list[str]] = {}
    for r in sim.alive():
        if r.asleep or r.down:
            continue
        groups.setdefault(sim.where(r.id, t0 + 50) or "", []).append(r.id)
    for node in sorted(groups):
        people = groups[node]
        if len(people) < 2:
            continue
        sim.rng.shuffle(people)
        for i in range(0, len(people) - 1, 2):
            a, b = sim.residents[people[i]], sim.residents[people[i + 1]]
            p = 0.15 + 0.35 * (a.traits.sociability + b.traits.sociability) / 2
            p += 0.2 if node in ("pub", "square") else 0
            p += 0.15 if a.household == b.household else 0
            if sim.rng.random() < p:
                chat(sim, a, b, node, t0 + 50 + sim.rng.randint(0, 8))


def chat(sim: "Simulation", a: "Resident", b: "Resident", node: str, t: int) -> None:
    for x, y in ((a, b), (b, a)):
        x.social = clamp(x.social + 12, 0, 100)
        x.stress = clamp(x.stress - 2, 0, 100)
        x.r(y.id).affection = clamp(x.r(y.id).affection + 0.01)
    ab = pick_gossip(sim, a, b, t)
    ba = pick_gossip(sim, b, a, t)
    if not ab and not ba:
        return
    ev = sim.emit("chat", node, [a.id], [b.id], data={"shared": [x.id for x in ab + ba]}, intent="lawful", time=t,
                  summary=f"{a.first} and {b.first} talk.")
    for belief in ab:
        tell(sim, a.id, b.id, belief, ev.id, t)
    for belief in ba:
        tell(sim, b.id, a.id, belief, ev.id, t)
    sim.stats["gossip_transfers"] += len(ab) + len(ba)


def conceals(sim: "Simulation", speaker: "Resident", b) -> bool:
    c = b.claim
    if c.kind in ("theft_self", "stash"):
        return True
    if c.kind == "collision_self":
        inc = sim.incident_for(b.event) if b.event else None
        return inc is None or not inc.reported_openly
    if speaker.guilty_of and c.subject == speaker.id:
        return True
    if c.subject and c.subject != speaker.id and speaker.r(c.subject).affection >= 0.75 and c.kind in (
            "suspect", "sighting", "vehicle_damage", "assault", "debt", "hardship", "intoxicated", "presence"):
        return True
    if c.kind == "vehicle_damage" and c.obj and speaker.vehicle == c.obj:
        return True
    return False


def anchors_for(sim: "Simulation", rid: str, t: int) -> list[tuple[int, int, str]]:
    out = []
    for b in sim.memory[rid].beliefs:
        c = b.claim
        if c.kind in INCIDENT_KINDS and c.start is not None and b.acquired >= t - 5 * DAY:
            start = c.start if c.kind == "loss" else c.start - 12 * 60
            out.append((start, c.end or c.start, c.location or ""))
    return out


def pick_gossip(sim: "Simulation", speaker: "Resident", listener: "Resident", t: int) -> list:
    anchors = None
    cands = []
    for b in reversed(sim.memory[speaker.id].beliefs):
        if t - b.acquired > 4 * DAY:
            break
        c = b.claim
        if b.acquired > t or listener.id in b.told_to or b.told_by == listener.id:
            continue
        relevant = c.kind in GOSSIP_KINDS or c.kind == "collision_self"
        if not relevant and c.kind in ("presence", "sighting", "noise", "intoxicated", "saw_collision") and c.start:
            if anchors is None:
                anchors = anchors_for(sim, speaker.id, t)
            relevant = any(a - 120 <= c.start <= e + 120 and (not loc or not c.location or
                                                              sim.world.hops(loc, c.location) <= 1)
                           for a, e, loc in anchors)
        if not relevant:
            continue
        if c.subject == listener.id and c.kind in ("debt", "hardship", "suspect", "refusal", "rent_missed"):
            continue
        if conceals(sim, speaker, b):
            continue
        score = b.salience * (1.5 if t - b.acquired < 12 * 60 else 1.0)
        cands.append((score, b.id, b))
    cands.sort(key=lambda x: (-x[0], x[1]))
    k = 1 + (1 if sim.rng.random() < speaker.traits.sociability else 0)
    return [c[2] for c in cands[:k]]


def tell(sim: "Simulation", speaker: str, listener: str, b, event_id: str, t: int) -> None:
    c = copy.copy(b.claim)
    err = b.error
    trust = sim.residents[listener].r(speaker).trust
    conf = b.confidence * (0.55 + 0.35 * trust)
    roll = sim.rng.random()
    if c.subject and c.hedged and roll < 0.35:
        c.hedged = False
        err = err or "certainty_inflated"
    elif c.start is not None and c.kind not in ("debt", "grudge") and roll > 0.85:
        shift = sim.rng.choice([-60, -30, 30, 60])
        c.start += shift
        if c.end is not None:
            c.end += shift
        err = err or "time_distorted"
    sim.add_belief(listener, c, "told", conf, t, event=event_id, told_by=speaker, via=b.id, error=err)
    b.told_to.append(listener)


def infer_suspicions(sim: "Simulation", rid: str, tm: int) -> None:
    """Residents put two and two together; sometimes they make five."""
    r = sim.residents[rid]
    mem = sim.memory[rid]
    recent = [b for b in mem.beliefs if b.acquired >= tm - 5 * DAY]
    for ib in recent:
        c = ib.claim
        if c.kind not in ("loss", "damage", "struck", "death") or c.start is None or c.location is None:
            continue
        if c.kind == "damage" and "fence" not in c.detail and "glass" not in c.detail:
            continue
        ws = c.start if c.kind == "loss" else c.start - 12 * 60
        we = c.end if c.end is not None else c.start
        loc = c.location
        if any(sim.log.by_id[g].location == loc and ws - 60 <= sim.log.by_id[g].time <= we + 60 for g in r.guilty_of):
            continue
        scores: dict[str, float] = {}
        premises: dict[str, list[str]] = {}

        def bump(s: str | None, amount: float, b) -> None:
            if not s or s == rid or not sim.residents[s].alive or sim.residents[s].household == r.household:
                return
            scores[s] = scores.get(s, 0.0) + amount
            premises.setdefault(s, []).append(b.id)

        road = loc == "road"
        for b in recent:
            k = b.claim
            if b is ib:
                continue
            if k.kind in ("presence", "sighting") and k.start is not None and k.location:
                kend = k.end if k.end is not None else k.start
                if kend >= ws - 60 and k.start <= we + 60 and sim.world.hops(k.location, loc) <= 1:
                    toward = sim.world.name(loc) in k.detail
                    bump(k.subject, 0.45 * b.confidence + (0.15 if toward else 0.0), b)
                    if road and k.obj in sim.world.vehicles:
                        for m in sim.households[sim.world.vehicles[k.obj].household]:
                            bump(m, 0.3, b)
            elif k.kind in ("hardship", "rent_missed") or (k.kind == "debt" and k.detail == "overdue"):
                bump(k.subject, 0.2, b)
            elif k.kind == "refusal":
                bump(k.other, 0.15, b)
            elif k.kind == "debt" and k.detail == "repaid" and k.start is not None and we <= k.start <= we + 2 * DAY:
                bump(k.subject, 0.2, b)
            elif k.kind == "suspect" and k.location == loc:
                bump(k.subject, 0.3 * b.confidence, b)
            elif road and k.kind == "vehicle_damage" and k.obj in sim.world.vehicles:
                for m in sim.households[sim.world.vehicles[k.obj].household]:
                    bump(m, 0.55, b)
            elif road and k.kind == "intoxicated" and k.start is not None and ws - 180 <= k.start <= we:
                bump(k.subject, 0.15, b)
        if not scores:
            continue
        for s in list(scores):
            res = r.r(s).resentment
            if res >= 0.3:
                scores[s] += 0.25 * res
        best = sorted(scores, key=lambda s: (-scores[s], s))[0]
        if scores[best] < 0.5:
            continue
        claim = Claim("suspect", subject=best, other=c.other, location=loc, start=ws, end=we, detail=c.detail,
                      obj=c.obj)
        if mem.find(claim):
            continue
        sim.add_belief(rid, claim, "inferred", min(0.9, scores[best]), tm, premises=[ib.id] + premises[best][:5])
        sim.stats["suspicions"] += 1
