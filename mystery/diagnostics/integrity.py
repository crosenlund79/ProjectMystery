"""Integrity checks: does a run (and a case built from it) obey the world's rules?

Each check returns a list of human-readable problems; an empty list means it passed.
These are the prototype's acceptance checks made executable.
"""

from __future__ import annotations

import json
import re
from typing import TYPE_CHECKING

from mystery.sim.clock import fmt

if TYPE_CHECKING:
    from mystery.sim.engine import Simulation

PRIOR = "-"
SELF_DATA_KINDS = {"debt_overdue", "rent_missed", "laid_off"}


def check_locations(sim: "Simulation") -> list[str]:
    """No one is in two places at once, and every move follows the map."""
    problems = []
    for rid, ivs in sim.intervals.items():
        for i, (loc, s, e) in enumerate(ivs):
            if e is not None and e <= s:
                problems.append(f"{rid}: empty or reversed interval at {loc} {fmt(s)}")
            if i + 1 < len(ivs):
                nloc, ns, _ = ivs[i + 1]
                if e is None:
                    problems.append(f"{rid}: open interval at {loc} is not the last")
                elif ns != e:
                    problems.append(f"{rid}: gap/overlap between {loc} and {nloc} at {fmt(e)}")
                if nloc != loc and nloc not in sim.world.locations[loc].adj:
                    problems.append(f"{rid}: jumped from {loc} to {nloc} at {fmt(ns)}")
            elif e is not None:
                problems.append(f"{rid}: last interval is closed")
    return problems


def check_event_locations(sim: "Simulation") -> list[str]:
    from mystery.sim.engine import CO_LOCATED_KINDS
    problems = []
    for ev in sim.log.events:
        if ev.location == PRIOR:
            continue
        people = list(ev.actors) + (list(ev.targets) if ev.kind in CO_LOCATED_KINDS else [])
        for rid in people:
            where = sim.where(rid, ev.time)
            if where != ev.location:
                problems.append(f"{ev.id} {ev.kind}: {rid} was at {where}, not {ev.location}, at {fmt(ev.time)}")
            r = sim.residents[rid]
            if (rid in ev.actors and r.death_event and ev.time > sim.log.by_id[r.death_event].time
                    and ev.kind != "death"):
                problems.append(f"{ev.id} {ev.kind}: {rid} acts after death")
    return problems


def check_accounts(sim: "Simulation") -> list[str]:
    """Replay every transfer: nobody ever spends money or goods they do not have."""
    problems = []
    bal = {k: dict(v) for k, v in sim.initial_balances.items()}
    for tr in sim.world.transfers:
        if tr.event_id not in sim.log.by_id:
            problems.append(f"transfer without event: {tr}")
        for acct, sign in ((tr.src, -1), (tr.dst, 1)):
            if acct.split(":")[0] not in ("wallet", "box"):
                continue
            bal.setdefault(acct, {"cash": 0, "food": 0})
            bal[acct][tr.asset] += sign * tr.amount
            if bal[acct][tr.asset] < 0:
                problems.append(f"{acct} went negative ({tr.asset}) at {fmt(tr.time)} via {tr.event_id}")
    final = sim.balances()
    for acct, v in final.items():
        replayed = bal.get(acct, {"cash": 0, "food": 0})
        if replayed != v:
            problems.append(f"{acct}: replayed {replayed} != actual {v}")
    return problems


def check_beliefs(sim: "Simulation") -> list[str]:
    """Every belief is traceable: to a perception, a participant's experience, a teller, or premises."""
    problems = []
    for b in sim.beliefs.values():
        c = b.claim
        ev = sim.log.by_id.get(b.event) if b.event else None
        prior = ev is not None and ev.location == PRIOR
        if b.event and ev is None:
            problems.append(f"{b.id}: unknown event {b.event}")
            continue
        if b.source in ("saw", "heard"):
            if ev is not None and not prior:
                if (b.holder, ev.id) not in sim.perceived and not ev.involves(b.holder):
                    problems.append(f"{b.id}: {b.holder} {b.source} {ev.id} without perceiving it")
            if c.kind == "presence" and ev is None:
                for t in (c.start, c.end):
                    if sim.where(b.holder, t) != c.location:
                        problems.append(f"{b.id}: {b.holder} saw someone at {c.location} without being there")
            if c.kind == "sighting" and c.start is not None and sim.where(b.holder, c.start) != c.location:
                problems.append(f"{b.id}: sighting at {c.location} but {b.holder} was at "
                                f"{sim.where(b.holder, c.start)} ({fmt(c.start)})")
        elif b.source == "told":
            if prior:
                continue
            src = sim.beliefs.get(b.via) if b.via else None
            if b.error == "lie" and ev is not None and b.told_by in ev.actors + ev.targets:
                pass  # a deliberate lie has no true belief behind it; its author was there
            elif src is None or src.holder != b.told_by:
                problems.append(f"{b.id}: told by {b.told_by} without a matching source belief")
            elif src.acquired > b.acquired:
                problems.append(f"{b.id}: told before the teller knew it")
            if b.told_by and sim.where(b.told_by, b.acquired) != sim.where(b.holder, b.acquired):
                problems.append(f"{b.id}: {b.told_by} and {b.holder} were not together when told")
        elif b.source == "inferred":
            for p in b.premises:
                pb = sim.beliefs.get(p)
                if pb is None or pb.holder != b.holder or pb.acquired > b.acquired:
                    problems.append(f"{b.id}: bad premise {p}")
        elif b.source == "self" and ev is not None and not prior:
            if not ev.involves(b.holder) and not (ev.kind in SELF_DATA_KINDS and b.holder in json.dumps(ev.data)):
                problems.append(f"{b.id}: self-knowledge of {ev.id} ({ev.kind}) by a non-participant {b.holder}")
    return problems


def check_evidence(sim: "Simulation") -> list[str]:
    """Physical traces and records exist only because world events created them."""
    problems = []
    for e in sim.world.evidence:
        ev = sim.log.by_id.get(e.created_by)
        if ev is None:
            problems.append(f"{e.id}: created by unknown event")
            continue
        if ev.time != e.created_at:
            problems.append(f"{e.id}: created at {fmt(e.created_at)} but its event is at {fmt(ev.time)}")
        if e.place != ev.location and e.place not in ev.objects:
            problems.append(f"{e.id}: at {e.place} but its event happened at {ev.location}")
        if e.removed_by is not None:
            rem = sim.log.by_id.get(e.removed_by)
            if rem is None or rem.time != e.removed_at:
                problems.append(f"{e.id}: removal not backed by an event")
    for book, entries in sim.world.records.items():
        for x in entries:
            ev = sim.log.by_id.get(x.event_id)
            if ev is None or x.time < ev.time:
                problems.append(f"{x.id}: record without a prior event")
    return problems


def check_simulation(sim: "Simulation") -> dict[str, list[str]]:
    return {
        "locations": check_locations(sim),
        "event_locations": check_event_locations(sim),
        "accounts": check_accounts(sim),
        "beliefs": check_beliefs(sim),
        "evidence": check_evidence(sim),
    }


# ---------------------------------------------------------------- case checks
FORBIDDEN_KEYS = {"intent", "causes", "status", "lie", "error", "implicates", "responsible", "event", "belief",
                  "created_by", "supports", "accurate", "answer", "narrative", "chain", "guilty_of", "traits"}
EVENT_ID = re.compile(r"\bE\d{6}\b")
BELIEF_ID = re.compile(r"\bB\d{6}\b")


def _keys(obj, out: set) -> set:
    if isinstance(obj, dict):
        for k, v in obj.items():
            out.add(k)
            _keys(v, out)
    elif isinstance(obj, list):
        for v in obj:
            _keys(v, out)
    return out


def check_spoiler_boundary(investigation: dict) -> list[str]:
    """The player-safe view must carry no truth: no event ids, beliefs, intents or verdicts."""
    problems = []
    text = json.dumps(investigation)
    if EVENT_ID.search(text):
        problems.append("investigation view contains event ids")
    if BELIEF_ID.search(text):
        problems.append("investigation view contains belief ids")
    leaked = _keys(investigation, set()) & FORBIDDEN_KEYS
    if leaked:
        problems.append(f"investigation view contains truth fields: {sorted(leaked)}")
    return problems


def check_case(case: dict) -> list[str]:
    problems = check_spoiler_boundary(case["investigation"])
    audit = case["truth"]["testimony_audit"]
    for rid, t in case["investigation"]["testimony"].items():
        for it in t["items"]:
            a = audit.get(it["key"])
            if a is None:
                problems.append(f"{it['key']}: statement without an audit entry")
                continue
            if a["status"] == "lie" and not a.get("error"):
                problems.append(f"{it['key']}: lie without an explanation")
            if a["status"] != "lie" and a.get("belief") is None and "whereabouts" not in it["topics"]:
                problems.append(f"{it['key']}: truthful statement with no belief behind it")
    return problems
