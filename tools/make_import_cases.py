"""Make the import-test cases: ten varied, standalone .mcase files for importing into the game by hand.

    python3 tools/make_import_cases.py [out_dir]     # default: import-test-cases/

They are found the way the bundled library is (real simulated histories, nothing edited), from seeds the
library does not use, and kept only if the case can be worked out from evidence (suitability "deduction"
routes). Each one is then validated and played through with the Python reference rules:

* the package validates (the same checks the game's importer runs);
* everything a thorough detective can reach (every question, pressed and followed up, every place and
  vehicle, every record book) includes every piece of evidence behind the deduction routes;
* a theory naming the true answer and citing that evidence scores well, and the reveal agrees.

Nothing here touches godot/cases: these files are not part of the game until a player imports them.
The README and the validation report name no culprit and give nothing away.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from mystery.cases.export import snapshot_hook  # noqa: E402
from mystery.cases.library import BUNDLED, DAYS  # noqa: E402
from mystery.cases.package import (build_package, read_package, unpack_to_case_dir, unseal,  # noqa: E402
                                   validate_package, write_package)
from mystery.investigate import dialogue  # noqa: E402
from mystery.investigate.session import Investigation  # noqa: E402
from mystery.investigate.verdict import reveal_model  # noqa: E402
from mystery.sim.engine import simulate  # noqa: E402

# (profile, family, what it should be like): ten slots, varied crimes, seasons and difficulty
SLOTS = [
    ("normal", "theft", "standard"),
    ("normal", "assault", "any"),
    ("normal", "accounting_error", "any"),
    ("scarcity", "theft", "standard"),
    ("scarcity", "fall", "any"),
    ("crisis", "collision", "any"),
    ("crisis", "theft", "any"),
    ("tension", "assault", "any"),
    ("tension", "collision", "any"),
    ("tension", "theft", "challenging"),
]
SEEDS = range(16, 61)


def fits(rep: dict, want: str) -> bool:
    if not rep.get("solvable_by_evidence"):
        return False
    if want == "standard":
        return rep["verdict"] == "playable"
    if want == "challenging":
        # plenty of misleading talk and a culprit who lies, but a contradiction that holds up
        return (rep["verdict"] in ("playable", "ambiguous") and "contradiction" in rep["deduction"]
                and rep["red_herrings"] >= 5 and rep["lies_by_responsible"] >= 1)
    return rep["verdict"] in ("playable", "obvious", "ambiguous")


def find_cases() -> list[dict]:
    used = {(p, s) for p, s, _ in BUNDLED}
    chosen, cache = [], {}
    for profile, family, want in SLOTS:
        for seed in SEEDS:
            if (profile, seed) in used:
                continue
            if (profile, seed) not in cache:
                hook, store = snapshot_hook()
                simulate(seed, DAYS, profile, case_hook=hook)
                cache[(profile, seed)] = store
            hit = None
            for iid in sorted(cache[(profile, seed)], key=lambda i: int(i[1:])):
                case = cache[(profile, seed)][iid]
                if case["suitability"]["family"] == family and fits(case["suitability"], want):
                    hit = case
                    break
            if hit is not None:
                chosen.append(hit)
                used.add((profile, seed))
                print(f"  {profile:9s} {family:17s} {want:12s} -> {hit['case_id']}")
                break
        else:
            print(f"  {profile:9s} {family:17s} {want:12s} -> none found")
    return chosen


def thorough(case_dir: str, tmp: str) -> Investigation:
    """Everything a careful detective can reach, through the player's own rules."""
    inv = Investigation(case_dir, session_path=os.path.join(tmp, "s.json"), fresh=True)
    data = inv.data
    for r in data["residents"]:
        if r["condition"] == "deceased":
            continue
        inv.state.setdefault("goodwill", {})[r["id"]] = 99
        for topic, _ in dialogue.topics_for(data, r["id"]):
            inv.ask_result(r["id"], topic, press=True)
            inv.ask_result(r["id"], topic, follow="earlier")
            inv.ask_result(r["id"], topic, follow="more")
    for p in data["places"]:
        inv.inspect_place_result(p["id"])
    for v in data["vehicles"]:
        inv.inspect_vehicle_result(v["id"])
    for book, b in data["records"].items():
        inv.read_result(book)
        for x in b["entries"]:
            if x.get("facts"):
                inv.cite_record(x["id"])
    return inv


def validate(path: str) -> dict:
    pkg = read_package(path)
    report = {"case_id": pkg["case_id"], "file": os.path.basename(path), "checks": {}}
    problems = validate_package(pkg)
    report["checks"]["format"] = "ok" if not problems else "; ".join(problems[:3])
    truth = unseal(pkg["sealed_truth"], pkg["case_id"])
    suit = truth["suitability"]
    with tempfile.TemporaryDirectory() as tmp:
        case_dir = unpack_to_case_dir(pkg, tmp)
        inv = thorough(case_dir, tmp)
        found = {e.get("ref") for e in inv.notebook.entries()}
        for e in inv.notebook.entries():
            found.update((inv._item(e.get("ref") or "") or {}).get("members", []))
        need = []
        for ch in suit["channels"]:
            if ch["strength"] == "strong":
                need.extend(ch["keys"])
        missing = [k for k in need if k not in found]
        report["checks"]["evidence reachable"] = "ok" if not missing else f"{len(missing)} piece(s) not reachable"
        contra = [c for c in inv.timeline_model()["contradictions"] if c["kind"] in ("firm", "document")]
        if "contradiction" in suit["deduction"]:
            report["checks"]["contradiction on the timeline"] = "ok" if contra else "missing"
        # the true answer, citing the evidence, through the player's own submit
        ans = truth["answer"]
        cites = []
        for k in need:
            eid = inv.notebook.state["by_ref"].get(k)
            if eid and eid not in cites:
                cites.append(eid)
        inv.submit_result(ans["mechanism"], ans["responsible"], ans["motives"][0] if ans["responsible"] else "none",
                          cites[:8], "import test")
        model = reveal_model(inv)
        total = model["score"]["total"]
        report["checks"]["solved from evidence"] = "ok" if total >= 70 else f"scored only {total}"
    report["difficulty"] = pkg["summary"]["difficulty"]
    report["title"] = pkg["summary"]["title"]
    report["season"] = pkg["summary"]["season"]
    report["routes"] = len(suit["deduction"])
    report["ok"] = all(v == "ok" for v in report["checks"].values())
    return report


def main(out_dir: str) -> int:
    print("searching for cases...")
    cases = find_cases()
    if os.path.isdir(out_dir):
        for name in os.listdir(out_dir):
            if name.endswith(".mcase"):
                os.remove(os.path.join(out_dir, name))
    os.makedirs(out_dir, exist_ok=True)
    reports = []
    for case in cases:
        pkg = build_package(case)
        path = write_package(pkg, out_dir)
        reports.append(validate(path))
    ok = all(r["ok"] for r in reports) and len(reports) == len(SLOTS)
    with open(os.path.join(out_dir, "VALIDATION.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# Validation of the import-test cases\n\n")
        f.write("Made by `python3 tools/make_import_cases.py`. Spoiler-free: no names of anyone responsible.\n\n")
        f.write("| File | Title | Season | Difficulty | Ways to work it out | Checks |\n|---|---|---|---|---|---|\n")
        for r in reports:
            checks = ", ".join(f"{k}: {v}" for k, v in r["checks"].items())
            f.write(f"| `{r['file']}` | {r['title']} | {r['season']} | {r['difficulty']} | {r['routes']} | {checks} |\n")
        f.write(f"\n{len(reports)} case(s); {'all checks passed' if ok else 'SOME CHECKS FAILED'}.\n")
    print(json.dumps([{k: r[k] for k in ("file", "difficulty", "ok")} for r in reports], indent=1))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "import-test-cases")))
