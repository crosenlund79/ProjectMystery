"""Command line: simulate towns, find and export cases, investigate, reveal."""

from __future__ import annotations

import argparse
import json
import os
import sys

from mystery import CONFIG_VERSION, SIM_VERSION
from mystery.sim.clock import fmt

DEFAULT_RUNS = "runs"


def _sim_args(p: argparse.ArgumentParser, seed_required: bool = True) -> None:
    p.add_argument("--seed", type=int, required=seed_required)
    p.add_argument("--spoilers", action="store_true", help="show who did what (developer view)")
    p.add_argument("--days", type=int, default=60)
    p.add_argument("--profile", default="normal", choices=["normal", "scarcity", "crisis", "tension"])
    p.add_argument("--residents", type=int, default=10)


def _run_dir(args) -> str:
    return os.path.join(args.out, f"{args.seed}-{args.profile}-{args.days}d-r{args.residents}")


def _incident_rows(sim, store: dict, spoilers: bool = False) -> list[str]:
    """Without --spoilers, show only what the town itself knows: the hook, not the truth."""
    rows = []
    hidden = 0
    for inc in sim.incidents:
        rep = store.get(inc.id)
        verdict = f"{rep['verdict']} ({rep['independent_channels']} channels)" if rep else ""
        if spoilers:
            who = sim.residents[inc.responsible].first if inc.responsible else "-"
            state = ("not noticed" if inc.discovered_at is None else
                     "resolved openly" if inc.reported_openly else
                     "merged into another case" if inc.case_start is None else "CASE")
            rows.append(f"  {inc.id:<4} {fmt(inc.time):<14} {inc.family:<17} {inc.outcome:<9} "
                        f"responsible={who:<8} {state:<24} {verdict}")
            continue
        if inc.discovered_at is None:
            hidden += 1
            continue
        state = "owned up to" if inc.reported_openly else "merged" if inc.case_start is None else "CASE"
        rows.append(f"  {inc.id:<4} noticed {fmt(inc.discovered_at):<14} {inc.title[:42]:<42} {state:<11} {verdict}")
    if hidden:
        rows.append(f"  (+{hidden} incident(s) nobody has noticed; use --spoilers to see everything)")
    return rows


def cmd_simulate(args) -> int:
    from mystery.cases.export import snapshot_hook
    from mystery.diagnostics.integrity import check_simulation
    from mystery.sim.engine import simulate
    hook, store = snapshot_hook(summary_only=True)
    sim = simulate(args.seed, args.days, args.profile, args.residents, case_hook=hook)
    print(f"{sim.world.town_name}: {args.residents} residents, {args.days} days, profile '{args.profile}'")
    print(f"{len(sim.log)} events, {len(sim.beliefs)} beliefs, digest {sim.log.digest()[:16]}")
    for rid in sim.ids:
        r = sim.residents[rid]
        print(f"  {r.name:<18} {r.occupation:<36} {'' if r.alive else '(dead)'}")
    print("Incidents:")
    print("\n".join(_incident_rows(sim, store, args.spoilers)) or "  (none — a quiet season)")
    problems = {k: v for k, v in check_simulation(sim).items() if v}
    print("Integrity:", "all checks passed" if not problems else {k: len(v) for k, v in problems.items()})
    path = _run_dir(args)
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "run.json"), "w", encoding="utf-8") as f:
        json.dump({**sim.summary(), "suitability": store}, f, indent=1, sort_keys=True)
    print(f"Saved {os.path.join(path, 'run.json')}")
    return 0 if not problems else 2


def cmd_list(args) -> int:
    from mystery.cases.export import snapshot_hook
    from mystery.sim.engine import simulate
    hook, store = snapshot_hook(summary_only=True)
    sim = simulate(args.seed, args.days, args.profile, args.residents, case_hook=hook)
    print("\n".join(_incident_rows(sim, store, args.spoilers)) or "(no incidents)")
    return 0


def cmd_export(args) -> int:
    from mystery.cases.export import snapshot_hook, write_case, write_event_log
    from mystery.diagnostics.integrity import check_case
    from mystery.sim.engine import Simulation
    from mystery.sim.config import SimConfig
    hook, store = snapshot_hook(selected=args.incident)
    sim = Simulation(SimConfig(seed=args.seed, days=args.days, profile=args.profile, residents=args.residents))
    sim.case_hook = hook
    while sim.t < args.days * 1440 and args.incident not in store:
        sim.step()
    if args.incident not in store:
        print(f"Incident {args.incident} did not become a case in this run. Try 'list-incidents'.")
        return 1
    case = store[args.incident]
    path = write_case(case, args.out)
    write_event_log(sim, path, case["truth"]["case_start"])
    problems = check_case(case)
    print(f"Case {case['case_id']} written to {path}")
    print(f"  {case['investigation']['hook']['title']} — suitability: {case['suitability']['verdict']}")
    if problems:
        print("  integrity problems:", problems[:5])
    print(f"Investigate with:  python -m mystery investigate --case {path}")
    return 0


def cmd_find(args) -> int:
    """Developer case selection: search seeds for a case matching filters. Never alters any history."""
    from mystery.cases.export import snapshot_hook, write_case, write_event_log
    from mystery.sim.engine import simulate
    want = set(args.verdict.split(",")) if args.verdict else {"playable"}
    for seed in range(args.start_seed, args.start_seed + args.max_runs):
        hook, store = snapshot_hook()
        sim = simulate(seed, args.days, args.profile, args.residents, case_hook=hook)
        for iid, case in store.items():
            rep = case["suitability"]
            if rep["verdict"] in want and (not args.family or rep["family"] == args.family):
                print(f"seed {seed} {iid}: {rep['verdict']} ({rep['independent_channels']} channels) — "
                      f"{case['investigation']['hook']['title']}")
                if args.export:
                    path = write_case(case, args.out)
                    write_event_log(sim, path, case["truth"]["case_start"])
                    print(f"  written to {path}")
                return 0
    print("No matching case found; try more runs or a different profile.")
    return 1


def cmd_batch(args) -> int:
    from mystery.diagnostics.batch import format_report, run_batch

    def progress(i, n):
        if i % max(1, n // 20) == 0 or i == n:
            print(f"  {i}/{n}", file=sys.stderr)

    rep = run_batch(args.runs, args.days, args.profile, args.residents, args.start_seed, args.workers, progress)
    print(format_report(rep))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(rep, f, indent=1)
    return 0 if not rep["runs_with_integrity_failures"] else 2


def cmd_replay(args) -> int:
    from mystery.sim.engine import simulate
    path = os.path.join(_run_dir(args), "run.json")
    if not os.path.exists(path):
        print(f"No saved run at {path}; run 'simulate' first.")
        return 1
    with open(path, encoding="utf-8") as f:
        saved = json.load(f)
    cfg = saved["config"]
    if (cfg["sim_version"], cfg["config_version"]) != (SIM_VERSION, CONFIG_VERSION):
        print(f"Saved run used sim {cfg['sim_version']} / config {cfg['config_version']}; this is "
              f"{SIM_VERSION} / {CONFIG_VERSION}. Replay is only guaranteed for matching versions.")
    sim = simulate(args.seed, args.days, args.profile, args.residents)
    same = sim.log.digest() == saved["digest"]
    print(f"Replay digest {'matches' if same else 'DIFFERS FROM'} the saved run ({len(sim.log)} events).")
    return 0 if same else 3


def cmd_investigate(args) -> int:
    from mystery.investigate.repl import run_interactive, run_script
    if args.script:
        with open(args.script, encoding="utf-8") as f:
            lines = [ln.rstrip("\n") for ln in f]
        for line in run_script(args.case, lines, fresh=args.fresh):
            print(line)
        return 0
    run_interactive(args.case, fresh=args.fresh)
    return 0


def cmd_reveal(args) -> int:
    from mystery.investigate.session import Investigation
    inv = Investigation(args.case)
    for line in inv.reveal():
        print(line)
    return 0


def cmd_truth(args) -> int:
    """Developer view of the sealed truth. Spoilers."""
    with open(os.path.join(args.case, "truth.json"), encoding="utf-8") as f:
        truth = json.load(f)
    print(f"SPOILERS — {truth['case_id']}")
    print(truth["narrative"])
    print(f"Answer: {truth['answer']}")
    for ev in sorted(truth["chain"] + truth["responsible_movements"], key=lambda e: e["time"]):
        print(f"  {fmt(ev['time'])} [{ev['id']} {ev['kind']}] {ev['summary']}")
    s = truth["suitability"]
    print(f"Suitability: {s['verdict']}; channels: " +
          "; ".join(f"{c['type']}:{c['source']}({c['strength']})" for c in s["channels"]))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="mystery", description="Project Mystery prototype")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("simulate", help="simulate one town and list its incidents")
    _sim_args(p)
    p.add_argument("--out", default=DEFAULT_RUNS)
    p.set_defaults(func=cmd_simulate)

    p = sub.add_parser("list-incidents", help="list incidents and case suitability for one run")
    _sim_args(p)
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("export-case", help="freeze one incident as a playable case")
    _sim_args(p)
    p.add_argument("--incident", required=True, help="incident id, e.g. I2")
    p.add_argument("--out", default=os.path.join(DEFAULT_RUNS, "cases"))
    p.set_defaults(func=cmd_export)

    p = sub.add_parser("find-case", help="developer case selection across seeds (explicit testing mode)")
    _sim_args(p, seed_required=False)
    p.add_argument("--start-seed", type=int, default=1)
    p.add_argument("--max-runs", type=int, default=100)
    p.add_argument("--family", choices=["theft", "accounting_error", "assault", "collision", "fall"])
    p.add_argument("--verdict", default="playable", help="comma list: obvious,playable,ambiguous,unsolvable")
    p.add_argument("--export", action="store_true")
    p.add_argument("--out", default=os.path.join(DEFAULT_RUNS, "cases"))
    p.set_defaults(func=cmd_find)

    p = sub.add_parser("simulate-batch", help="run many seeds headless and print a diagnostic report")
    _sim_args(p, seed_required=False)
    p.add_argument("--runs", type=int, default=100)
    p.add_argument("--start-seed", type=int, default=1)
    p.add_argument("--workers", type=int, default=max(1, min(8, os.cpu_count() or 1)))
    p.add_argument("--json", help="also write the report as JSON")
    p.set_defaults(func=cmd_batch)

    p = sub.add_parser("replay", help="re-run a saved simulation and verify its event log digest")
    _sim_args(p)
    p.add_argument("--out", default=DEFAULT_RUNS)
    p.set_defaults(func=cmd_replay)

    p = sub.add_parser("investigate", help="investigate an exported case")
    p.add_argument("--case", required=True)
    p.add_argument("--fresh", action="store_true", help="start over, discarding saved notes")
    p.add_argument("--script", help="read commands from a file instead of the keyboard")
    p.set_defaults(func=cmd_investigate)

    p = sub.add_parser("reveal", help="after concluding a case, show the truth")
    p.add_argument("--case", required=True)
    p.set_defaults(func=cmd_reveal)

    p = sub.add_parser("truth", help="developer: print a case's sealed truth (spoilers)")
    p.add_argument("--case", required=True)
    p.set_defaults(func=cmd_truth)

    args = parser.parse_args(argv)
    return args.func(args)
