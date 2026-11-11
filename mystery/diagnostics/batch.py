"""Headless batch runs and the diagnostic report.

A batch answers: how often does each kind of incident happen under a profile, how
often do conflicts calm down rather than escalate, how many cases are actually
investigable, and do all runs pass the integrity checks?
"""

from __future__ import annotations

import multiprocessing
import statistics
import sys
import time
from collections import Counter
from concurrent.futures import ProcessPoolExecutor

from mystery.cases.export import snapshot_hook
from mystery.diagnostics.integrity import check_simulation
from mystery.sim.clock import DAY
from mystery.sim.engine import simulate

MAJOR = {"assault", "collision", "fall"}


def peak_memory_mb() -> float | None:
    """Peak memory of this process, on POSIX (resource) or Windows (psapi); None if unknown."""
    try:
        import resource
        peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        return round(peak / (1024 * 1024 if sys.platform == "darwin" else 1024), 1)
    except ImportError:
        pass
    if sys.platform != "win32":
        return None
    try:
        import ctypes
        from ctypes import wintypes

        class Counters(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                        ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                        ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t)]

        counters = Counters()
        counters.cb = ctypes.sizeof(Counters)
        kernel32 = ctypes.WinDLL("kernel32")
        kernel32.GetCurrentProcess.restype = wintypes.HANDLE
        psapi = ctypes.WinDLL("psapi")
        psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
        if psapi.GetProcessMemoryInfo(kernel32.GetCurrentProcess(), ctypes.byref(counters), counters.cb):
            return round(counters.PeakWorkingSetSize / (1024 * 1024), 1)
    except (OSError, AttributeError, ValueError):
        pass
    return None


def run_one(args: tuple) -> dict:
    seed, days, profile, residents = args
    t0 = time.perf_counter()
    hook, store = snapshot_hook(summary_only=True)
    sim = simulate(seed, days, profile, residents, case_hook=hook)
    runtime = time.perf_counter() - t0
    integrity = check_simulation(sim)
    incidents = []
    for inc in sim.incidents:
        rep = store.get(inc.id)
        incidents.append({
            "id": inc.id, "family": inc.family, "day": inc.time / DAY, "severity": inc.severity,
            "discovered": inc.discovered_at is not None, "candidate": inc.is_candidate,
            "deaths": 1 if inc.severity == 3 else 0,
            "verdict": rep["verdict"] if rep else None,
            "channels": rep["independent_channels"] if rep else None,
            "red_herrings": rep["red_herrings"] if rep else None,
            "statement_status": rep["statement_status"] if rep else {},
            "mistaken_by_cause": rep["mistaken_by_cause"] if rep else {},
        })
    return {
        "seed": seed, "runtime": runtime, "days": days, "events": len(sim.log), "beliefs": len(sim.beliefs),
        "digest": sim.log.digest(), "incidents": incidents,
        "integrity": {k: len(v) for k, v in integrity.items()},
        "integrity_examples": {k: v[:3] for k, v in integrity.items() if v},
        "stats": {k: v for k, v in sim.stats.items() if not k.startswith("event:")},
    }


def run_batch(runs: int, days: int, profile: str, residents: int = 10, start_seed: int = 1,
              workers: int = 1, progress=None) -> dict:
    jobs = [(start_seed + i, days, profile, residents) for i in range(runs)]
    results = []
    if workers > 1:
        # 'spawn' is the only start method on Windows; using it everywhere keeps platforms identical.
        ctx = multiprocessing.get_context("spawn")
        with ProcessPoolExecutor(max_workers=min(workers, 61), mp_context=ctx) as pool:
            for i, res in enumerate(pool.map(run_one, jobs, chunksize=max(1, runs // (workers * 4)))):
                results.append(res)
                if progress:
                    progress(i + 1, runs)
    else:
        for i, job in enumerate(jobs):
            results.append(run_one(job))
            if progress:
                progress(i + 1, runs)
    return summarise(results, profile, days, residents)


def summarise(results: list[dict], profile: str, days: int, residents: int) -> dict:
    n = len(results)
    fam = Counter()
    verdicts = Counter()
    by_family_verdict = Counter()
    statuses = Counter()
    mistakes = Counter()
    first_incident = []
    channels = []
    integrity = Counter()
    failing_runs = []
    stats = Counter()
    no_incident = major_runs = candidate_total = suitable = deaths = 0
    for r in results:
        incs = r["incidents"]
        if not incs:
            no_incident += 1
        if any(i["family"] in MAJOR and i["severity"] > 0 for i in incs) or any(i["deaths"] for i in incs):
            major_runs += 1
        notable = [i for i in incs if i["discovered"]]
        if notable:
            first_incident.append(min(i["day"] for i in notable))
        for i in incs:
            fam[i["family"]] += 1
            deaths += i["deaths"]
            if i["candidate"]:
                candidate_total += 1
            if i["verdict"]:
                verdicts[i["verdict"]] += 1
                by_family_verdict[(i["family"], i["verdict"])] += 1
                channels.append(i["channels"])
                if i["verdict"] in ("playable", "obvious"):
                    suitable += 1
                statuses.update(i["statement_status"])
                mistakes.update(i["mistaken_by_cause"])
        for k, v in r["integrity"].items():
            integrity[k] += v
        if any(r["integrity"].values()):
            failing_runs.append(r["seed"])
        stats.update(r["stats"])
    conf = stats.get("confrontations", 0)
    calmed = sum(v for k, v in stats.items() if k.startswith("deescalation:") and k != "deescalation:reconcile")
    runtimes = [r["runtime"] for r in results]
    cases = sum(verdicts.values())
    return {
        "profile": profile, "days": days, "residents": residents, "runs": n,
        "runtime_per_100_days_s": round(statistics.mean(runtimes) * 100 / days, 3) if runtimes else 0,
        "events_per_run": round(statistics.mean(r["events"] for r in results), 1) if results else 0,
        "beliefs_per_run": round(statistics.mean(r["beliefs"] for r in results), 1) if results else 0,
        "peak_memory_mb": peak_memory_mb(),
        "incidents_per_run": {k: round(v / n, 2) for k, v in sorted(fam.items())},
        "deaths": deaths,
        "runs_without_incident": no_incident,
        "runs_with_major_incident": major_runs,
        "candidate_cases": candidate_total,
        "evaluated_cases": cases,
        "suitable_cases": suitable,
        "case_verdicts": {k: f"{v} ({100 * v / cases:.0f}%)" for k, v in verdicts.most_common()} if cases else {},
        "verdicts_by_family": {f"{a}/{b}": v for (a, b), v in sorted(by_family_verdict.items())},
        "mean_independent_channels": round(statistics.mean(channels), 2) if channels else 0,
        "days_to_first_noticed_incident": {
            "median": round(statistics.median(first_incident), 1), "min": round(min(first_incident), 1),
            "max": round(max(first_incident), 1)} if first_incident else None,
        "confrontations": conf,
        "deescalated": f"{calmed}/{conf} ({100 * calmed / conf:.0f}%)" if conf else "0/0",
        "reconciliations_offered_and_accepted": stats.get("deescalation:reconcile", 0),
        "assaults": stats.get("assaults", 0),
        "testimony_accuracy": dict(statuses),
        "mistaken_testimony_by_cause": dict(mistakes.most_common()),
        "integrity_failures": dict(integrity),
        "runs_with_integrity_failures": failing_runs[:20],
    }


def format_report(rep: dict) -> str:
    lines = [f"Batch report — profile '{rep['profile']}', {rep['runs']} runs x {rep['days']} days, "
             f"{rep['residents']} residents"]
    order = ["runtime_per_100_days_s", "events_per_run", "beliefs_per_run", "peak_memory_mb", "incidents_per_run",
             "deaths", "runs_without_incident", "runs_with_major_incident", "candidate_cases", "evaluated_cases",
             "suitable_cases", "case_verdicts", "verdicts_by_family", "mean_independent_channels",
             "days_to_first_noticed_incident", "confrontations", "deescalated",
             "reconciliations_offered_and_accepted", "assaults", "testimony_accuracy",
             "mistaken_testimony_by_cause", "integrity_failures", "runs_with_integrity_failures"]
    for k in order:
        lines.append(f"  {k.replace('_', ' ')}: {rep[k]}")
    return "\n".join(lines)
