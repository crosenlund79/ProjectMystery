"""Reference check: Python reads the case files the Godot game generated (Pilot 4B).

    python3 tools/check_godot_cases.py <folder with .mcase files> [<folder> ...]

The game needs no Python. This only shows that a Godot-made package is the same format the Python laboratory writes
and reads: every file passes mystery/cases/package.py validate_package (the rules the Godot loader mirrors, with
Python's stricter integer types), its sealed truth opens with Python's unseal, belongs to the same case, and holds a
suitability report, and every relevance verdict opens. Nothing is changed. Exit code 1 on any problem, or if no file
was found.
"""

from __future__ import annotations

import glob
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from mystery.cases.package import read_package, unseal, validate_package  # noqa: E402


def check(path: str) -> list[str]:
    pkg = read_package(path)
    problems = validate_package(pkg)
    if problems:
        return problems
    truth = unseal(pkg["sealed_truth"], pkg["case_id"])
    out = []
    if truth.get("case_id") != pkg["case_id"]:
        out.append("the sealed truth belongs to another case")
    if "suitability" not in truth or "verdict" not in truth["suitability"]:
        out.append("the sealed truth has no suitability report")
    if not pkg["case_id"].startswith("godot-"):
        out.append("not in the Godot namespace")
    if pkg["generator"].get("tool") != "mystery (Godot)":
        out.append("not made by the Godot generator")
    return out


def main() -> int:
    files = sorted(f for folder in sys.argv[1:] for f in glob.glob(os.path.join(folder, "*.mcase")))
    if not files:
        print("no .mcase files found")
        return 1
    bad = 0
    for path in files:
        problems = check(path)
        status = "ok" if not problems else "PROBLEMS: " + "; ".join(problems[:3])
        print(f"  {os.path.basename(path)}: {status}")
        bad += 1 if problems else 0
    print(f"{len(files)} Godot-made case files read by Python, {bad} with problems")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
