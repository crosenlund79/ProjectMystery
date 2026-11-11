"""Menus behind the double-clickable launchers (they work the same on any OS).

    python -m mystery.launcher play   spoiler-free: generate or pick a case, then investigate
    python -m mystery.launcher lab    simulation laboratory: spoilers, batch reports, exports, tests

The *play* menu never prints anything from a case's sealed truth. It chooses cases using
the suitability report (which is computed from the truth) but only ever shows the player
the hook, exactly as the investigation file presents it. The truth is read only by the
in-game ``reveal`` command, after the player has concluded the case.
"""

from __future__ import annotations

import json
import os
import random
import subprocess
import sys
import traceback
from typing import Callable

MIN_PYTHON = (3, 10)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CASES_DIR = os.path.join("runs", "cases")
PROFILES = ["normal", "scarcity", "crisis", "tension"]

SEASONS = [
    ("1", "An ordinary season", "normal"),
    ("2", "A lean season (food is short and dear)", "scarcity"),
    ("3", "Hard times (wages cut, debts piling up)", "crisis"),
    ("4", "A troubled season (old grudges, heavy drinking)", "tension"),
    ("5", "Surprise me", None),
]
DIFFICULTIES = [
    ("1", "Gentle — plenty to go on", ("obvious", "playable"), 3),
    ("2", "Standard — a fair puzzle", ("playable",), 2),
    ("3", "Hard — thin evidence; 'unresolved' may be the honest answer", ("ambiguous",), 1),
]

HOW_TO_PLAY = """\
HOW TO PLAY

  Something has happened in a small town. Everyone you meet lived through the same days you
  are asking about, but each of them only knows what they saw, heard, were told or worked out
  for themselves. Some are mistaken. Some protect people they love. The person responsible,
  if there is one, may lie.

  Inside a case, type 'help' for every command. The ones you will use most:
    talk <name>             pick topics by letter; 'p' plus a letter presses someone who hesitates
    inspect <place>         look around; private places need the owner's agreement
    read <book>             ledger, tabs, clinic or workshop records
    notebook / timeline     everything you have found, by entry or by time
    hint                    spend investigation credits on a nudge (it costs points)
    submit                  put forward your theory: what happened, who, why, and your evidence
    giveup                  close the case without a theory
    reveal                  only after submitting or giving up: see what really happened
    quit                    leave; your notes are saved and you can continue later

  'Unresolved' is a legitimate answer when the evidence really is too thin.
"""


class Console:
    """Prompts with defaults. Swappable read/write so the menus can be tested with a script."""

    def __init__(self, read: Callable[[str], str] | None = None, write: Callable[[str], None] | None = None):
        self.read = read or input
        self.write = write or print

    def say(self, *lines: str) -> None:
        for line in lines:
            self.write(line)

    def ask(self, prompt: str, default: str = "") -> str:
        shown = f"{prompt} [{default}]: " if default != "" else f"{prompt}: "
        answer = self.read(shown)
        if answer is None:
            raise EOFError
        return answer.strip() or default

    def ask_int(self, prompt: str, default: int, lo: int | None = None, hi: int | None = None) -> int:
        while True:
            raw = self.ask(prompt, str(default))
            try:
                value = int(raw)
            except ValueError:
                self.say("  Please type a whole number.")
                continue
            if (lo is not None and value < lo) or (hi is not None and value > hi):
                self.say(f"  Please choose a number from {lo} to {hi}.")
                continue
            return value

    def choose(self, prompt: str, options: list[tuple[str, str]], default: str = "") -> str:
        for key, label in options:
            self.say(f"  {key}. {label}")
        keys = {k.lower() for k, _ in options}
        while True:
            answer = self.ask(prompt, default).lower()
            if answer in keys:
                return answer
            self.say(f"  Please choose one of: {', '.join(k for k, _ in options)}.")

    def confirm(self, prompt: str, default: bool = False) -> bool:
        while True:
            answer = self.ask(f"{prompt} ({'Y/n' if default else 'y/N'})", "").lower()
            if not answer:
                return default
            if answer in ("y", "yes"):
                return True
            if answer in ("n", "no"):
                return False


# ======================================================================== cases on disk
def list_cases(cases_dir: str = CASES_DIR) -> list[dict]:
    """Saved cases, newest first. Reads only investigation.json and the player's session."""
    out = []
    if not os.path.isdir(cases_dir):
        return out
    for name in os.listdir(cases_dir):
        path = os.path.join(cases_dir, name)
        inv_path = os.path.join(path, "investigation.json")
        if not os.path.isfile(inv_path):
            continue
        try:
            with open(inv_path, encoding="utf-8") as f:
                inv = json.load(f)
        except (OSError, ValueError):
            continue
        session = {}
        session_path = os.path.join(path, "session.json")
        if os.path.isfile(session_path):
            try:
                with open(session_path, encoding="utf-8") as f:
                    session = json.load(f)
            except (OSError, ValueError):
                session = {}
        if session.get("revealed"):
            status = f"closed — scored {session.get('score', {}).get('total', '?')}/100"
        elif session.get("concluded"):
            status = "theory submitted — 'reveal' is waiting for you"
        elif session.get("entries"):
            status = f"in progress — {len(session['entries'])} notebook entries"
        else:
            status = "new"
        modified = max(os.path.getmtime(p) for p in (inv_path, session_path) if os.path.exists(p))
        out.append({"path": path, "case_id": inv["case_id"], "title": inv["hook"]["title"], "town": inv["town"],
                    "start": inv["start_label"], "status": status, "session": session, "modified": modified})
    out.sort(key=lambda c: (-c["modified"], c["case_id"]))
    return out


def generate_case(console: Console, profile: str | None, difficulty: tuple, seed: int | None = None,
                  max_runs: int = 40, days: int = 60, cases_dir: str = CASES_DIR) -> str | None:
    """Simulate towns until one yields a case of the wanted difficulty. History is never edited."""
    from mystery.cases.export import snapshot_hook, write_case
    from mystery.sim.engine import simulate

    verdicts, min_channels = difficulty[2], difficulty[3]
    start = seed if seed is not None else random.SystemRandom().randrange(1, 1_000_000)
    rng = random.Random(start)
    chosen_profile = profile or rng.choice(PROFILES)
    for i in range(max_runs):
        s = start + i
        console.say(f"  Letting a town live through {days} days... (seed {s})")
        hook, store = snapshot_hook()
        simulate(s, days, chosen_profile, case_hook=hook)
        fits = [c for c in store.values() if c["suitability"]["verdict"] in verdicts
                and c["suitability"]["independent_channels"] >= min_channels]
        if not fits:
            continue
        fits.sort(key=lambda c: c["case_id"])
        case = rng.choice(fits)
        path = os.path.join(cases_dir, case["case_id"])
        if not os.path.isfile(os.path.join(path, "investigation.json")):
            path = write_case(case, cases_dir)  # never overwrite a case someone is playing
        return path
    console.say(f"  No case of that kind turned up in {max_runs} towns. Try another season or difficulty.")
    return None


# ======================================================================== play
def investigate(console: Console, path: str, fresh: bool = False) -> None:
    from mystery.investigate.repl import Repl
    from mystery.investigate.session import Investigation
    Repl(Investigation(path, fresh=fresh), read=console.read, write=console.write).run()


def _banner(console: Console) -> None:
    console.say("", "=" * 64, "  PROJECT MYSTERY",
                "  A small town. Something happened. Find out what — if you can.", "=" * 64)


def play(console: Console, seed: int | None = None, cases_dir: str = CASES_DIR) -> int:
    while True:
        _banner(console)
        saved = list_cases(cases_dir)
        choice = console.choose("Choose", [
            ("1", "Start a new case"),
            ("2", f"Open a saved case ({len(saved)} saved)"),
            ("3", "How to play"),
            ("4", "Quit"),
        ], "1" if not saved else "2")
        try:
            if choice == "1":
                _new_case(console, seed, cases_dir)
                seed = None if seed is None else seed + 1000
            elif choice == "2":
                _open_saved(console, saved)
            elif choice == "3":
                console.say(HOW_TO_PLAY)
                console.ask("Press Enter to go back")
            else:
                console.say("Goodbye.")
                return 0
        except KeyboardInterrupt:
            console.say("", "(Interrupted — back to the menu. Your notes are saved.)")
        except (EOFError, SystemExit):
            raise
        except Exception as exc:  # keep the window and the menu alive
            console.say("", f"Sorry, something went wrong: {type(exc).__name__}: {exc}",
                        "Your saved cases are untouched. You can try again or choose another case.")


def _new_case(console: Console, seed: int | None, cases_dir: str) -> None:
    console.say("", "What kind of season has the town had?")
    season = console.choose("Season", [(k, label) for k, label, _ in SEASONS], "1")
    profile = next(p for k, _, p in SEASONS if k == season)
    console.say("", "How much should the town give away?")
    level = console.choose("Difficulty", [(k, label) for k, label, *_ in DIFFICULTIES], "2")
    difficulty = next(d for d in DIFFICULTIES if d[0] == level)
    console.say("", "Simulating... this usually takes a few seconds.")
    path = generate_case(console, profile, difficulty, seed=seed, cases_dir=cases_dir)
    if path is None:
        return
    with open(os.path.join(path, "investigation.json"), encoding="utf-8") as f:
        inv = json.load(f)
    console.say("", f"A case is waiting: {inv['hook']['title']} ({inv['town']}).",
                f"  Saved in {path}")
    if console.confirm("Start investigating now?", True):
        investigate(console, path)


def _open_saved(console: Console, saved: list[dict]) -> None:
    if not saved:
        console.say("", "No saved cases yet. Start a new one first.")
        return
    console.say("", "Saved cases (most recent first):")
    options = [(str(i), f"{c['title']} — {c['town']}, {c['start']} — {c['status']}")
               for i, c in enumerate(saved, 1)]
    options.append(("b", "Back"))
    pick = console.choose("Case", options, "1")
    if pick == "b":
        return
    case = saved[int(pick) - 1]
    session = case["session"]
    if session.get("revealed"):
        action = console.choose("This case is closed", [("r", "Read the reveal again"),
                                                         ("s", "Start it over from scratch"), ("b", "Back")], "r")
        if action == "r":
            from mystery.investigate.session import Investigation
            console.say(*Investigation(case["path"]).reveal())
            console.ask("Press Enter to go back")
        elif action == "s" and console.confirm("This erases your notes for this case. Sure?"):
            investigate(console, case["path"], fresh=True)
        return
    if session.get("entries") or session.get("concluded"):
        action = console.choose("Continue where you left off", [("c", "Continue"), ("s", "Start over"),
                                                                ("b", "Back")], "c")
        if action == "b":
            return
        if action == "s":
            if not console.confirm("This erases your notes for this case. Sure?"):
                return
            investigate(console, case["path"], fresh=True)
            return
    investigate(console, case["path"])


# ======================================================================== lab
def lab(console: Console, cases_dir: str = CASES_DIR) -> int:
    from mystery.cli import main as cli_main

    def run(argv: list[str]) -> None:
        console.say("", f"  equivalent command:  python -m mystery {' '.join(argv)}", "")
        try:
            code = cli_main(argv)
        except SystemExit as exc:  # argparse --help / usage errors
            code = exc.code
        if code not in (0, None):
            console.say(f"  (finished with exit code {code})")

    while True:
        console.say("", "=" * 64, "  PROJECT MYSTERY LABORATORY", "  Developer tools. This menu SHOWS SPOILERS.",
                    "=" * 64)
        choice = console.choose("Choose", [
            ("1", "Simulate one town and list everything that happened"),
            ("2", "Batch report across many seeds"),
            ("3", "Find a case by type and verdict, and export it"),
            ("4", "Export a specific incident from one run"),
            ("5", "Show a case's sealed truth"),
            ("6", "Check that a saved run replays identically"),
            ("7", "Run the test suite"),
            ("8", "Play (the spoiler-free game menu)"),
            ("9", "Command-line reference"),
            ("0", "Quit"),
        ], "1")
        try:
            if choice == "0":
                console.say("Goodbye.")
                return 0
            if choice == "1":
                run(["simulate", *_run_args(console), "--spoilers"])
            elif choice == "2":
                runs = console.ask_int("How many seeds", 50, 1, 100_000)
                days = console.ask_int("Days per run", 60, 1, 3650)
                profile = _profile(console)
                start = console.ask_int("First seed", 1, 0)
                workers = console.ask_int("Parallel workers", max(1, min(8, os.cpu_count() or 1)), 1, 64)
                run(["simulate-batch", "--runs", str(runs), "--days", str(days), "--profile", profile,
                     "--start-seed", str(start), "--workers", str(workers)])
            elif choice == "3":
                profile = _profile(console)
                families = ["any", "theft", "accounting_error", "assault", "collision", "fall"]
                family = families[int(console.choose("Incident type", [(str(i), f) for i, f in
                                                                       enumerate(families, 1)], "1")) - 1]
                verdict = console.ask("Verdicts (comma list of obvious, playable, ambiguous, unsolvable)",
                                      "playable")
                start = console.ask_int("First seed", 1, 0)
                argv = ["find-case", "--profile", profile, "--verdict", verdict, "--start-seed", str(start),
                        "--export", "--out", cases_dir]
                if family != "any":
                    argv += ["--family", family]
                run(argv)
            elif choice == "4":
                args = _run_args(console)
                incident = console.ask("Incident id (see option 1)", "I1").upper()
                run(["export-case", *args, "--incident", incident, "--out", cases_dir])
            elif choice == "5":
                path = _pick_case(console, cases_dir)
                if path:
                    run(["truth", "--case", path])
            elif choice == "6":
                run(["replay", *_run_args(console)])
            elif choice == "7":
                _run_tests(console)
            elif choice == "8":
                play(console, cases_dir=cases_dir)
            elif choice == "9":
                run(["--help"])
            console.ask("Press Enter to return to the laboratory menu")
        except KeyboardInterrupt:
            console.say("", "(Interrupted.)")
        except (EOFError, SystemExit):
            raise
        except Exception:
            console.say("", "Something went wrong:")
            console.say(traceback.format_exc())


def _profile(console: Console) -> str:
    options = [(str(i), p) for i, p in enumerate(PROFILES, 1)]
    return PROFILES[int(console.choose("Profile", options, "1")) - 1]


def _run_args(console: Console) -> list[str]:
    seed = console.ask_int("Seed", 7, 0)
    days = console.ask_int("Days", 60, 1, 3650)
    profile = _profile(console)
    residents = console.ask_int("Residents", 10, 8, 12)
    return ["--seed", str(seed), "--days", str(days), "--profile", profile, "--residents", str(residents)]


def _pick_case(console: Console, cases_dir: str) -> str | None:
    saved = list_cases(cases_dir)
    if not saved:
        console.say("  No exported cases yet (use option 3 or 4).")
        return None
    options = [(str(i), f"{c['case_id']} — {c['title']}") for i, c in enumerate(saved, 1)]
    return saved[int(console.choose("Case", options, "1")) - 1]["path"]


def _run_tests(console: Console) -> None:
    if not os.path.isdir(os.path.join(ROOT, "tests")):
        console.say("  The tests folder is not next to the mystery package, so there is nothing to run.")
        return
    console.say("  Running the test suite (about 15-30 seconds)...")
    code = subprocess.call([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."], cwd=ROOT)
    console.say("  All tests passed." if code == 0 else f"  Some tests failed (exit code {code}).")


# ======================================================================== entry point
def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if sys.version_info < MIN_PYTHON:
        print(f"Project Mystery needs Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]} or newer; this is "
              f"{sys.version.split()[0]}. Install a newer Python from https://www.python.org/downloads/")
        return 2
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")  # never crash on a console that lacks a character
        except (AttributeError, ValueError):
            pass
    mode = argv[0] if argv else "play"
    if mode not in ("play", "lab"):
        print("usage: python -m mystery.launcher [play|lab]")
        return 2
    seed = os.environ.get("MYSTERY_SEED")
    console = Console()
    try:
        if mode == "lab":
            return lab(console)
        return play(console, seed=int(seed) if seed and seed.isdigit() else None)
    except (EOFError, KeyboardInterrupt):
        print("\nGoodbye.")
        return 0


if __name__ == "__main__":
    sys.exit(main())
