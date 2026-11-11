"""Shared fixtures: find cases by searching seeds (never by editing history)."""

from __future__ import annotations

import functools

from mystery.cases.export import snapshot_hook
from mystery.sim.engine import simulate


@functools.lru_cache(maxsize=None)
def run_with_cases(seed: int, profile: str = "normal", days: int = 60):
    hook, store = snapshot_hook()
    sim = simulate(seed, days, profile, case_hook=hook)
    return sim, store


def find_case(profile: str = "normal", family: str | None = None, verdicts=("playable", "obvious"),
              outcome: str | None = None, seeds=range(1, 40), days: int = 60):
    for seed in seeds:
        sim, store = run_with_cases(seed, profile, days)
        for iid in sorted(store):
            case = store[iid]
            rep = case["suitability"]
            if family and rep["family"] != family:
                continue
            if verdicts and rep["verdict"] not in verdicts:
                continue
            if outcome and case["truth"]["answer"]["outcome"] != outcome:
                continue
            return seed, iid, case
    raise AssertionError(f"no {family or 'any'} case found in {profile} seeds {seeds}")
