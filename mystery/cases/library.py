"""The bundled case library and the Python-vs-Godot parity fixtures.

The library is a deterministic selection of *real* simulated cases: seeds are searched in
order and the first cases that fit each slot are taken. Nothing is edited or invented; a
slot that finds no matching case within its seed budget is simply left out and reported.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import tempfile

from mystery.cases.export import snapshot_hook
from mystery.cases.package import (EXTENSION, build_package, library_index, read_package, unpack_to_case_dir,
                                   unseal, validate_package, write_package)
from mystery.investigate.session import Investigation, InvestigationError
from mystery.investigate.verdict import reveal_model
from mystery.sim.engine import simulate

DAYS = 60
# (profile, family or None, accepted verdicts, how many)
PLAN = [
    ("normal", "theft", ("playable",), 2),
    ("normal", "accounting_error", ("playable",), 1),
    ("normal", "theft", ("ambiguous",), 1),
    ("normal", "assault", ("playable", "obvious"), 1),
    ("scarcity", "theft", ("playable",), 1),
    ("scarcity", "fall", ("playable",), 1),
    ("scarcity", "assault", ("playable",), 1),
    ("crisis", "theft", ("playable",), 1),
    ("crisis", "assault", ("playable",), 1),
    ("crisis", "collision", ("playable", "obvious", "ambiguous"), 1),
    ("tension", "collision", ("playable", "obvious"), 1),
    ("tension", "fall", ("playable",), 1),
    ("tension", "assault", ("obvious",), 1),
    ("tension", "theft", ("playable",), 1),
]
SEED_BUDGET = 60
PARITY_CASES = 5


def select_cases(plan=PLAN, budget: int = SEED_BUDGET, progress=None) -> tuple[list[dict], list[str]]:
    chosen: list[dict] = []
    used_seeds: set[tuple[str, int]] = set()
    missing: list[str] = []
    cache: dict[tuple[str, int], dict] = {}
    for profile, family, verdicts, count in plan:
        found = 0
        for seed in range(1, budget + 1):
            if found >= count:
                break
            if (profile, seed) in used_seeds:
                continue
            if (profile, seed) not in cache:
                hook, store = snapshot_hook()
                simulate(seed, DAYS, profile, case_hook=hook)
                cache[(profile, seed)] = store
                if progress:
                    progress(profile, seed)
            for iid in sorted(cache[(profile, seed)], key=lambda i: int(i[1:])):
                case = cache[(profile, seed)][iid]
                rep = case["suitability"]
                if rep["family"] == family and rep["verdict"] in verdicts:
                    chosen.append(case)
                    used_seeds.add((profile, seed))
                    found += 1
                    break
        if found < count:
            missing.append(f"{profile}/{family}/{'|'.join(verdicts)}: found {found} of {count}")
    return chosen, missing


def build_library(out_dir: str, progress=None) -> dict:
    """Write the .mcase files and index.json; returns the index."""
    cases, missing = select_cases(progress=progress)
    os.makedirs(out_dir, exist_ok=True)
    for name in os.listdir(out_dir):
        if name.endswith(EXTENSION):
            os.remove(os.path.join(out_dir, name))
    entries = []
    for case in cases:
        pkg = build_package(case)
        problems = validate_package(pkg)
        if problems:
            raise ValueError(f"{pkg['case_id']}: {problems[:3]}")
        path = write_package(pkg, out_dir)
        with open(path, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        entries.append({"file": os.path.basename(path), "case_id": pkg["case_id"], **pkg["summary"],
                        "sha256": digest})
    index = library_index(entries)
    index["missing"] = missing
    with open(os.path.join(out_dir, "index.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(index, indent=1, sort_keys=True) + "\n")
    return index


# ----------------------------------------------------------------------------- parity
def scripted_actions(pkg: dict, truth: dict, ending: str) -> list[dict]:
    """A deterministic investigation that touches every rule. Built from the case itself."""
    inv = pkg["investigation"]
    alive = [r for r in inv["residents"] if r["condition"] != "deceased"]
    dead = [r for r in inv["residents"] if r["condition"] == "deceased"]
    acts: list[dict] = [{"op": "reveal"}]
    for r in alive[:6]:
        for topic in ("whereabouts", "window", "incident"):
            acts.append({"op": "ask", "who": r["id"], "topic": topic})
    first = alive[0]["id"]
    acts.append({"op": "ask", "who": first, "topic": "window", "press": True})
    acts.append({"op": "ask", "who": first, "topic": "window", "press": True})
    for topic in ("money", "conflicts", "rumors", "vehicles", "past"):
        acts.append({"op": "ask", "who": first, "topic": topic})
    other = alive[1]["id"]
    acts.append({"op": "ask", "who": first, "topic": f"person:{other}"})
    for r in alive[1:4]:
        acts.append({"op": "ask", "who": r["id"], "topic": "incident", "press": True})
    if dead:
        acts.append({"op": "ask", "who": dead[0]["id"], "topic": "window"})
    for p in inv["places"]:
        acts.append({"op": "inspect_place", "id": p["id"]})
    for v in inv["vehicles"]:
        acts.append({"op": "inspect_vehicle", "id": v["id"]})
    start_day = inv["start_time"] // 1440 + 1
    for key in sorted(inv["records"]):
        acts.append({"op": "read", "book": key})
        acts.append({"op": "read", "book": key, "day": start_day})
    open_books = [k for k in sorted(inv["records"]) if inv["records"][k]["allowed"] and inv["records"][k]["entries"]]
    if open_books:
        acts.append({"op": "cite", "entry": inv["records"][open_books[0]]["entries"][-1]["id"]})
    acts.append({"op": "note", "text": "Something about the timing bothers me."})
    acts.append({"op": "note", "text": "My own guess at when it happened.", "time": inv["hook"]["window"][0] + 90})
    acts += [{"op": "mark", "entry": "S1", "mark": "confirmed"}, {"op": "mark", "entry": "S2", "mark": "nonsense"},
             {"op": "mark", "entry": "Z9", "mark": "disputed"}]
    acts += [{"op": "hint"}] * 4
    acts += [{"op": "timeline"}, {"op": "state"}, {"op": "reveal"}]
    if ending == "solve":
        ans = truth["answer"]
        cites = ["S1", "S2", "S3", "N1"]
        if any(x["allowed"] and x["traces"] for x in inv["places"] + inv["vehicles"]):
            cites.append("X1")
        if open_books:
            cites.append("D1")
        acts.append({"op": "submit", "mechanism": ans["mechanism"], "responsible": ans["responsible"],
                     "motive": ans["motives"][0] if ans["responsible"] else "none", "cites": cites,
                     "summary": "parity"})
    elif ending == "unresolved":
        acts.append({"op": "submit", "mechanism": "unresolved", "responsible": None, "motive": "unknown",
                     "cites": [], "summary": ""})
    else:
        acts.append({"op": "giveup"})
    acts += [{"op": "state"}, {"op": "reveal"}, {"op": "ask", "who": first, "topic": "window"}]
    return acts


def run_python(case_dir: str, actions: list[dict]) -> list[dict]:
    """The Python reference results for a list of actions."""
    with tempfile.TemporaryDirectory() as tmp:
        inv = Investigation(case_dir, session_path=os.path.join(tmp, "session.json"), fresh=True)
        out = []
        for a in actions:
            op = a["op"]
            try:
                if op == "ask":
                    res = inv.ask_result(a["who"], a["topic"], a.get("press", False))
                elif op == "inspect_place":
                    res = inv.inspect_place_result(a["id"])
                elif op == "inspect_vehicle":
                    res = inv.inspect_vehicle_result(a["id"])
                elif op == "read":
                    res = inv.read_result(a["book"], a.get("day"))
                elif op == "cite":
                    res = {"op": "cite", "note": inv.cite_record(a["entry"])}
                elif op == "note":
                    res = {"op": "note", "note": inv.note(a["text"], a.get("time"))}
                elif op == "mark":
                    res = {"op": "mark", "ok": inv.notebook.mark(a["entry"], a["mark"])}
                elif op == "hint":
                    res = inv.hint_result()
                elif op == "timeline":
                    res = {"op": "timeline", **inv.timeline_model()}
                elif op == "state":
                    st = inv.state
                    res = {"op": "state", "entries": inv.notebook.entries(), "credits": st["credits"],
                           "hints_bought": st["hints_bought"], "hint_spend": st.get("hint_spend", 0),
                           "goodwill": dict(sorted(st.get("goodwill", {}).items())),
                           "pressed": dict(sorted(st.get("pressed", {}).items())),
                           "concluded": st["concluded"], "revealed": st["revealed"]}
                elif op == "submit":
                    res = inv.submit_result(a["mechanism"], a["responsible"], a["motive"], a["cites"], a["summary"])
                elif op == "giveup":
                    inv.surrender()
                    res = {"op": "giveup", "ok": True}
                elif op == "reveal":
                    model = reveal_model(inv)
                    res = {"op": "reveal", "sealed": model is None, "model": model}
                else:
                    raise ValueError(op)
            except InvestigationError as e:
                res = {"op": op, "error": "closed" if "closed" in str(e) else str(e)}
            out.append(json.loads(json.dumps(res)))
    return out


def build_parity_fixtures(library_dir: str, out_dir: str, count: int = PARITY_CASES) -> list[str]:
    with open(os.path.join(library_dir, "index.json"), encoding="utf-8") as f:
        index = json.load(f)
    os.makedirs(out_dir, exist_ok=True)
    for name in os.listdir(out_dir):
        if name.endswith(".json"):
            os.remove(os.path.join(out_dir, name))
    # one case per incident family, so every kind of ending is checked in both engines
    picks, families = [], set()
    for e in index["cases"]:
        pkg = read_package(os.path.join(library_dir, e["file"]))
        family = unseal(pkg["sealed_truth"], pkg["case_id"])["incident"]["family"]
        if family not in families:
            families.add(family)
            picks.append(e["file"])
    picks = picks[:count]
    written = []
    for name in picks:
        pkg = read_package(os.path.join(library_dir, name))
        tmp = tempfile.mkdtemp()
        try:
            case_dir = unpack_to_case_dir(pkg, tmp)
            with open(os.path.join(case_dir, "truth.json"), encoding="utf-8") as f:
                truth = json.load(f)
            scripts = []
            for ending in ("solve", "giveup", "unresolved"):
                actions = scripted_actions(pkg, truth, ending)
                scripts.append({"name": ending, "actions": actions, "expected": run_python(case_dir, actions)})
        finally:
            shutil.rmtree(tmp)
        path = os.path.join(out_dir, pkg["case_id"] + ".json")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump({"format": "project-mystery-parity", "format_version": 1, "case_file": name,
                       "scripts": scripts}, f, indent=1, sort_keys=True, ensure_ascii=True)
            f.write("\n")
        written.append(path)
    return written
