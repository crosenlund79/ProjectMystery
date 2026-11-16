"""Reference statistics from the Python town simulation, for the Godot simulation pilots.

    python3 tools/sim_reference.py              # writes godot/tests/sim_reference.json and sim_reference_theft.json
    python3 tools/sim_reference.py --beta-table # prints the Beta(2.2, 2.2) quantile table in scripts/sim/sim_rng.gd

The Godot simulation (godot/scripts/sim/) has no violence or accidents yet (Pilot 3B), so the Python simulation
is measured with those switched off the same way: no falls or collisions, and an argument that would turn violent
stops there (counted, not played out). Two references:

    sim_reference.json        stealing off too, compared with Godot's crime switch off (Pilots 1 and 2)
    sim_reference_theft.json  stealing on, compared with Godot's crime switch on (Pilot 3A)

Ledger mistakes, discovered losses, suspicion and gossip run in Python in both; the differences this makes are
listed in docs/godot-simulation-migration.md.

The statistics use exactly the definitions in godot/scripts/sim/sim_check.gd (stats()).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from mystery.sim import actions, decisions  # noqa: E402
from mystery.sim.clock import DAY  # noqa: E402
from mystery.sim.config import SimConfig  # noqa: E402
from mystery.sim.engine import Simulation  # noqa: E402

OUT = os.path.join(ROOT, "godot", "tests", "sim_reference.json")
OUT_THEFT = os.path.join(ROOT, "godot", "tests", "sim_reference_theft.json")
PROFILES = ["normal", "scarcity", "crisis", "tension"]
SEEDS = list(range(1, 11))
DAYS = 30
COMPARED_KINDS = ["move", "meal", "pub_meal", "drink", "purchase", "credit", "credit_refused", "wage",
                  "rent_paid", "rent_missed", "loan", "loan_refused", "repay", "help", "reconcile", "argument",
                  "debt_overdue", "deposit", "withdraw", "chat"]
PLACES = ["home", "work", "pub", "square", "road", "elsewhere"]
MEMORY_KINDS = ["presence", "sighting", "intoxicated", "noise", "debt", "refusal", "hardship", "argument",
                "grudge", "rent_missed", "loan", "help", "reconcile", "purchase", "laid_off", "suspect", "loss",
                "damage", "theft_self", "stash", "confession"]
ERRORS = ["misidentified", "time_distorted", "certainty_inflated"]
SPREAD = {"argument": ["argument"], "refusal": ["loan_refused", "credit_refused"], "rent_missed": ["rent_missed"],
          "loss": ["loss_discovered"]}
CRIME_COUNTED = ["theft", "theft_aborted", "forced_entry", "ledger_error", "loss_discovered", "stash_withdraw",
                 "confession", "cleaned_up"]
ORIGINAL_STEAL_INTENT = decisions._steal_intent


def crime_layer_off(theft: bool = False) -> None:
    """Violence and accidents off; stealing off too unless ``theft``."""
    decisions._steal_intent = ORIGINAL_STEAL_INTENT if theft else (lambda *a, **k: None)
    if getattr(Simulation, "_measured", False):
        return
    Simulation._measured = True
    actions.check_collision = lambda *a, **k: None
    actions.check_fall = lambda *a, **k: None

    def deferred_assault(sim, *a, **k):
        sim.stats["escalations_deferred"] += 1
    actions.assault = deferred_assault

    original_chat = actions.chat

    def counted_chat(sim, a, b, node, t):
        sim.stats["all_chats"] += 1
        return original_chat(sim, a, b, node, t)
    actions.chat = counted_chat

    original_end = Simulation._end_of_tick

    def sampled_end(self, t0):
        original_end(self, t0)
        tm = t0 + 59
        s = self.__dict__.setdefault("samples", {"hours": 0, "asleep": 0, "hunger": 0.0, "energy": 0.0,
                                                  "social": 0.0, "stress": 0.0, "at": {p: 0 for p in PLACES}})
        for r in self.alive():
            s["hours"] += 1
            s["asleep"] += 1 if r.asleep else 0
            for k in ("hunger", "energy", "social", "stress"):
                s[k] += getattr(r, k)
            s["at"][place_category(r, self.where(r.id, tm))] += 1
    Simulation._end_of_tick = sampled_end


def place_category(r, node) -> str:
    if node and node.startswith("home:"):
        return "home"
    if node and node == r.workplace:
        return "work"
    if node in ("pub", "square", "road"):
        return node
    return "elsewhere"


def stats(sim: Simulation, theft: bool = False) -> dict:
    days = max(1.0, sim.t / DAY)
    people = float(len(sim.ids))
    counts = {}
    for ev in sim.log.events:
        counts[ev.kind] = counts.get(ev.kind, 0) + 1
    counts["chat"] = sim.stats["all_chats"]  # every chat, as Godot logs them (Python logs only gossip chats)
    out = {f"per_resident_day.{k}": counts.get(k, 0) / (people * days) for k in COMPARED_KINDS}
    s = sim.samples
    hours = max(1.0, float(s["hours"]))
    for p in PLACES:
        out[f"share.{p}"] = s["at"][p] / hours
    out["asleep"] = s["asleep"] / hours
    for k in ("hunger", "energy", "social", "stress"):
        out[f"needs.{k}"] = s[k] / hours
    wallets = sum(r.cash for r in sim.residents.values())
    out["money.mean_wallet"] = wallets / people
    out["money.town_cash"] = float(wallets + sum(c.cash for c in sim.world.containers.values()))
    out["money.open_debts"] = float(sum(1 for d in sim.world.debts if d.settled is None))
    out.update(memory_stats(sim, counts, people * days))
    if theft:
        out.update(crime_stats(sim, counts, people * days))
    return out


def involved(rid: str, ev) -> bool:
    return rid in ev.actors or rid in ev.targets or any(isinstance(v, str) and v == rid for v in ev.data.values())


def root(sim, b):
    seen = 0
    while b.via is not None and b.via in sim.beliefs and seen < 50:
        b = sim.beliefs[b.via]
        seen += 1
    return b


def memory_stats(sim, counts: dict, per: float) -> dict:
    """The same numbers as memory_stats() in godot/scripts/sim/sim_check.gd. Undefined values are -1."""
    out = {}
    beliefs = list(sim.beliefs.values())
    for src in ("self", "saw", "heard", "told", "inferred"):
        out[f"memory.belief_{src}"] = sum(1 for b in beliefs if b.source == src) / per
    for k in MEMORY_KINDS:
        out[f"memory.kind_{k}"] = sum(1 for b in beliefs if b.claim.kind == k) / per
    for e in ERRORS:
        out[f"memory.error_{e}"] = sum(1 for b in beliefs if b.error == e) / per
    out["memory.gossip_chats"] = sum(1 for ev in sim.log.events if ev.kind == "chat") / per
    out["memory.gossip_transfers"] = sim.stats["gossip_transfers"] / per
    out["memory.suspicions"] = sim.stats["suspicions"] / per
    knowers: dict[str, set] = {}
    for b in beliefs:
        r = root(sim, b)
        if r.event:
            knowers.setdefault(r.event, set()).add(b.holder)
    for name, kinds in SPREAD.items():
        evs = [ev for ev in sim.log.events if ev.kind in kinds]
        total = sum(1 for ev in evs for h in knowers.get(ev.id, ()) if not involved(h, ev))
        out[f"memory.knowers_{name}"] = total / len(evs) if evs else -1.0
    lent, refused = counts.get("loan", 0), counts.get("loan_refused", 0)
    out["memory.loan_acceptance"] = lent / (lent + refused) if lent + refused else -1.0
    return out


def incident_at(sim, claim):
    """The same as incident_at() in sim_check.gd: the incident at a claim's place within six hours."""
    if claim.start is None:
        return None
    until = claim.end if claim.end is not None else claim.start
    for inc in sim.incidents:
        if inc.location == claim.location and claim.start - 6 * 60 <= inc.time <= until + 6 * 60:
            return inc
    return None


def crime_stats(sim, counts: dict, per: float) -> dict:
    """The same numbers as crime_stats() in godot/scripts/sim/sim_check.gd. Undefined values are -1."""
    out = {f"crime.{k}": counts.get(k, 0) / per for k in CRIME_COUNTED}
    out["crime.accusations"] = sum(1 for ev in sim.log.events
                                   if ev.kind == "argument" and ev.data.get("reason") == "suspicion") / per
    cash = [ev.data["amount"] for ev in sim.log.events if ev.kind == "theft" and ev.data["asset"] == "cash"]
    out["crime.cash_per_theft"] = sum(cash) / len(cash) if cash else -1.0
    thefts = [i for i in sim.incidents if i.family == "theft"]
    out["crime.theft_discovered_share"] = (sum(1 for i in thefts if i.discovered_at is not None) / len(thefts)
                                           if thefts else -1.0)
    sus = [b for b in sim.beliefs.values() if b.source == "inferred" and b.claim.kind == "suspect"]
    right = 0
    for b in sus:
        inc = incident_at(sim, b.claim)
        if inc is not None and inc.responsible == b.claim.subject:
            right += 1
    out["crime.suspicions_right_share"] = right / len(sus) if sus else -1.0
    return out


def reference(theft: bool = False) -> dict:
    crime_layer_off(theft)
    result = {"generated_by": "tools/sim_reference.py", "days": DAYS, "seeds": SEEDS, "residents": 10,
              "crime_layer": ("stealing on; no falls or collisions; violent escalations counted, not played" if theft
                              else "off (no stealing, falls, collisions; violent escalations counted, not played)"),
              "profiles": {}}
    for profile in PROFILES:
        runs = []
        deferred = 0
        for seed in SEEDS:
            sim = Simulation(SimConfig(seed=seed, days=DAYS, profile=profile, residents=10)).run()
            runs.append(stats(sim, theft))
            deferred += sim.stats["escalations_deferred"]
        keys = sorted(runs[0])

        def defined(k):  # -1 marks a value a run cannot have (no arguments, no loans asked for)
            return [r[k] for r in runs if r[k] >= 0] or [-1.0]
        result["profiles"][profile] = {
            "mean": {k: round(statistics.fmean(defined(k)), 5) for k in keys},
            "sd": {k: round(statistics.pstdev(defined(k)), 5) for k in keys},
            "escalations_deferred_per_run": round(deferred / len(SEEDS), 2),
        }
    return result


def beta_table(a: float = 2.2, b: float = 2.2, steps: int = 256, grid: int = 200000) -> list[float]:
    """Quantiles of Beta(a, b) at k/steps, by trapezoid integration of the density on a fine grid."""
    xs = [i / grid for i in range(grid + 1)]
    pdf = [x ** (a - 1) * (1 - x) ** (b - 1) for x in xs]
    cdf = [0.0]
    for i in range(grid):
        cdf.append(cdf[-1] + (pdf[i] + pdf[i + 1]) / (2 * grid))
    total = cdf[-1]
    cdf = [c / total for c in cdf]
    out, j = [], 0
    for k in range(steps + 1):
        p = k / steps
        if k in (0, steps):
            out.append(float(k // steps))
            continue
        while j < grid and cdf[j + 1] < p:
            j += 1
        out.append(round(xs[j] + (p - cdf[j]) / (cdf[j + 1] - cdf[j]) / grid, 6))
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--beta-table", action="store_true", help="print the Beta(2.2, 2.2) quantile table")
    args = ap.parse_args()
    if args.beta_table:
        print(", ".join(f"{v:.6f}" for v in beta_table()))
        return
    for theft, out in ((False, OUT), (True, OUT_THEFT)):
        ref = reference(theft)
        with open(out, "w", encoding="utf-8") as f:
            json.dump(ref, f, indent=1, sort_keys=True)
            f.write("\n")
        print(f"wrote {os.path.relpath(out, ROOT)}")
        for profile, data in ref["profiles"].items():
            m = data["mean"]
            extra = (f"  thefts/res-day {m['crime.theft']:.4f}  suspicions right {m['crime.suspicions_right_share']:.2f}"
                     if theft else "")
            print(f"{profile:9} meals/res-day {m['per_resident_day.meal']:.2f}  asleep {m['asleep']:.2f}  "
                  f"home {m['share.home']:.2f}  work {m['share.work']:.2f}  pub {m['share.pub']:.2f}  "
                  f"wallet {m['money.mean_wallet']:.0f}  deferred escalations/run {data['escalations_deferred_per_run']}"
                  f"{extra}")
        assert not math.isnan(ref["profiles"]["normal"]["mean"]["asleep"])


if __name__ == "__main__":
    main()
