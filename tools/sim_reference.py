"""Reference statistics from the Python town simulation, for the Godot simulation pilot.

    python3 tools/sim_reference.py              # writes godot/tests/sim_reference.json
    python3 tools/sim_reference.py --beta-table # prints the Beta(2.2, 2.2) quantile table in scripts/sim/sim_rng.gd

The Godot pilot (godot/scripts/sim/) has no crime layer yet, so the Python simulation is measured with its
crime layer switched off the same way: no stealing, no falls or collisions, and an argument that would turn
violent stops there (counted, not played out). Perception, memory and gossip still run in Python; they are
listed as known differences in docs/godot-simulation-migration.md.

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
PROFILES = ["normal", "scarcity", "crisis", "tension"]
SEEDS = list(range(1, 11))
DAYS = 30
COMPARED_KINDS = ["move", "meal", "pub_meal", "drink", "purchase", "credit", "credit_refused", "wage",
                  "rent_paid", "rent_missed", "loan", "loan_refused", "repay", "help", "reconcile", "argument",
                  "debt_overdue", "deposit", "withdraw", "chat"]
PLACES = ["home", "work", "pub", "square", "road", "elsewhere"]


def crime_layer_off() -> None:
    decisions._steal_intent = lambda *a, **k: None
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


def stats(sim: Simulation) -> dict:
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
    return out


def reference() -> dict:
    crime_layer_off()
    result = {"generated_by": "tools/sim_reference.py", "days": DAYS, "seeds": SEEDS, "residents": 10,
              "crime_layer": "off (no stealing, falls, collisions; violent escalations counted, not played)",
              "profiles": {}}
    for profile in PROFILES:
        runs = []
        deferred = 0
        for seed in SEEDS:
            sim = Simulation(SimConfig(seed=seed, days=DAYS, profile=profile, residents=10)).run()
            runs.append(stats(sim))
            deferred += sim.stats["escalations_deferred"]
        keys = sorted(runs[0])
        result["profiles"][profile] = {
            "mean": {k: round(statistics.fmean(r[k] for r in runs), 5) for k in keys},
            "sd": {k: round(statistics.pstdev([r[k] for r in runs]), 5) for k in keys},
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
    ref = reference()
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(ref, f, indent=1, sort_keys=True)
        f.write("\n")
    print(f"wrote {os.path.relpath(OUT, ROOT)}")
    for profile, data in ref["profiles"].items():
        m = data["mean"]
        print(f"{profile:9} meals/res-day {m['per_resident_day.meal']:.2f}  asleep {m['asleep']:.2f}  "
              f"home {m['share.home']:.2f}  work {m['share.work']:.2f}  pub {m['share.pub']:.2f}  "
              f"wallet {m['money.mean_wallet']:.0f}  deferred escalations/run {data['escalations_deferred_per_run']}")
    assert not math.isnan(ref["profiles"]["normal"]["mean"]["asleep"])


if __name__ == "__main__":
    main()
