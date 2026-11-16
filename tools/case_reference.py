"""Reference statistics from Python's case extraction, for the Godot case-extraction pilot (Pilot 4A).

    python3 tools/case_reference.py        # writes godot/tests/case_reference.json

Runs the Python simulation with its whole crime layer (4 seasons x 10 seeds, 30 days, 10 residents), freezes every
case candidate at its case start with mystery/cases/export.py (build_case, through snapshot_hook), and measures the
cases exactly as godot/scripts/cases/case_extract.gd (stats) measures the Godot ones: how many candidates there are
and of which families, what each case holds (statements, summaries, lies, things withheld or guarded, traces,
records, refusals), where statements come from and how accurate they are, which ones support or mislead, and the
relevance verdicts. The suitability verdicts and hints are left out (Pilot 4B). Python is not changed.
"""

from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from mystery.cases.export import snapshot_hook  # noqa: E402
from mystery.sim.engine import simulate  # noqa: E402

OUT = os.path.join(ROOT, "godot", "tests", "case_reference.json")
PROFILES = ["normal", "scarcity", "crisis", "tension"]
SEEDS = list(range(1, 11))
DAYS = 30
FAMILIES = ["theft", "accounting_error", "assault", "collision", "fall"]
CRIME_FAMILIES = ["theft", "assault", "collision"]
SOURCES = ["self", "saw", "heard", "told", "inferred"]
STATUSES = ["accurate", "mistaken", "lie", "unverifiable"]
VERDICTS = ["connected", "unrelated", "uncertain"]
SUPPORTS = ["places_responsible", "act", "motive", "vehicle", "sudden_money", "absence", "suspicion_correct",
            "misleading", "responsible_lie", "mechanism"]


def eligible(inc: dict) -> bool:
    """Someone genuinely responsible for a crime (godot/scripts/cases/case_builder.gd, eligibility)."""
    return (inc["discovered_at"] is not None and not inc["reported_openly"] and inc["responsible"] is not None
            and inc["family"] in CRIME_FAMILIES and inc["outcome"] == "crime")


def stats(cases: list[dict], months: int) -> dict:
    """The statistics of godot/scripts/cases/case_extract.gd (stats), over a list of cases."""
    n = len(cases)
    out: dict[str, float] = {"cases": float(n), "per_month.candidates": n / max(1, months)}
    for fam in FAMILIES:
        out[f"share.family.{fam}"] = sum(1 for c in cases if c["truth"]["incident"]["family"] == fam) / max(1, n)
    out["share.eligible"] = sum(1 for c in cases if eligible(c["truth"]["incident"])) / max(1, n)
    sums = {k: 0 for k in ("statements", "per_resident", "summaries", "withheld", "guarded", "lies", "evasive",
                           "traces_visible", "traces_present", "records_visible", "places_refused")}
    sources = {s: 0 for s in SOURCES}
    statuses = {s: 0 for s in STATUSES}
    verdicts = {f"{g}.{v}": 0 for g in ("statement", "trace", "record") for v in VERDICTS}
    groups = {"statement": 0, "trace": 0, "record": 0}
    with_support = {s: 0 for s in SUPPORTS}
    told = 0
    for c in cases:
        inv, truth = c["investigation"], c["truth"]
        audit = truth["testimony_audit"]
        alive = 0
        present: set[str] = set()
        statements = 0
        for rid in sorted(inv["testimony"]):
            t = inv["testimony"][rid]
            alive += 1
            if t["evasive_topics"]:
                sums["evasive"] += 1
            for it in t["items"]:
                statements += 1
                a = audit[it["key"]]
                if a.get("summary"):
                    sums["summaries"] += 1
                    continue
                sources[it["source"]] = sources.get(it["source"], 0) + 1
                statuses[a["status"]] = statuses.get(a["status"], 0) + 1
                told += 1
                if it["guarded"]:
                    sums["guarded"] += 1
                if a.get("lie"):
                    sums["lies"] += 1
                for sp in a.get("supports", []):
                    present.add(sp)
        sums["statements"] += statements
        sums["per_resident"] += statements / max(1, alive)
        sums["withheld"] += sum(1 for k in audit if k.startswith("W-"))
        sums["traces_visible"] += sum(len(p["traces"]) for p in inv["places"]) + sum(len(v["traces"])
                                                                                     for v in inv["vehicles"])
        sums["traces_present"] += len(truth["evidence_audit"])
        sums["records_visible"] += sum(len(r["entries"]) for r in inv["records"].values())
        sums["places_refused"] += sum(1 for p in inv["places"] if not p["allowed"])
        for sp in present:
            if sp in with_support:
                with_support[sp] += 1
        for ref, v in truth["relevance"].items():
            g = "trace" if ref.startswith("T-") else ("record" if ref.startswith("R-") else "statement")
            groups[g] += 1
            verdicts[f"{g}.{v['verdict']}"] += 1
    for k, v in sums.items():
        out[f"per_case.{k}"] = v / max(1, n)
    for s in SOURCES:
        out[f"share.source.{s}"] = sources[s] / max(1, told)
    for s in STATUSES:
        out[f"share.status.{s}"] = statuses[s] / max(1, told)
    for gv, count in verdicts.items():
        out[f"share.verdict.{gv}"] = count / max(1, groups[gv.split('.')[0]])
    for s in SUPPORTS:
        out[f"share.cases_with.{s}"] = with_support[s] / max(1, n)
    return {k: round(v, 5) for k, v in sorted(out.items())}


def main() -> None:
    cases: list[dict] = []
    for profile in PROFILES:
        for seed in SEEDS:
            hook, store = snapshot_hook()
            simulate(seed, DAYS, profile, case_hook=hook)
            for iid in sorted(store, key=lambda i: int(i[1:])):
                cases.append(store[iid])
    months = len(PROFILES) * len(SEEDS)
    result = {"generated_by": "tools/case_reference.py", "days": DAYS, "seeds": SEEDS, "profiles": PROFILES,
              "residents": 10, "months": months, "all": stats(cases, months),
              "theft": stats([c for c in cases if c["truth"]["incident"]["family"] == "theft"], months)}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=1, sort_keys=True)
        f.write("\n")
    print(f"wrote {os.path.relpath(OUT, ROOT)}: {len(cases)} cases in {months} months")
    for k, v in result["all"].items():
        print(f"  {k:40} {v}")


if __name__ == "__main__":
    main()
