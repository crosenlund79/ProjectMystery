"""A plain text interface for an investigation."""

from __future__ import annotations

import shlex
import sys
import textwrap
from typing import Callable, Iterable

from mystery.investigate.session import Investigation, InvestigationError
from mystery.sim.clock import fmt

HELP = """\
Commands
  people                      who lives here
  talk <name>                 question someone (pick topics by letter; 'p' + letter presses them)
  ask <name> <topic> [press]  one-off question. topics: whereabouts window incident money
                              conflicts rumors vehicles about:<name>
  places                      places in town
  inspect <place|vehicle>     look around (private places need the owner's agreement)
  vehicles                    vehicles in town and where they are parked
  read <book> [day]           read a record book: ledger, tabs, clinic, workshop
  cite <entry>                copy a record line (e.g. ledger#12) into your notebook
  notebook                    everything you have found
  timeline                    your notebook in time order
  note <text>                 write a note
  mark <id> <confirmed|disputed|uncertain|inference>
  hint                        buy the next hint with investigation credits
  submit                      put forward your theory (guided)
  giveup                      close the case without a theory
  reveal                      after concluding: see what really happened
  quit                        save and leave"""


class Repl:
    def __init__(self, inv: Investigation, read: Callable[[str], str] = input, write: Callable[[str], None] = print):
        self.inv = inv
        self.read = read
        self.write = write

    def say(self, lines: Iterable[str] | str) -> None:
        if isinstance(lines, str):
            lines = [lines]
        for line in lines:
            if len(line) > 100:
                indent = len(line) - len(line.lstrip())
                for i, chunk in enumerate(textwrap.wrap(line.strip(), 100 - indent - 2)):
                    self.write(" " * indent + ("" if i == 0 else "  ") + chunk)
            else:
                self.write(line)

    def intro(self) -> None:
        d = self.inv.data
        h = d["hook"]
        self.say(["", f"CASE: {h['title']}", f"{d['town']} — {d['start_label']}", "", h["text"], "",
                  f"The time in question: {h['window_label']}.", "", d["player_role"], "",
                  "Type 'help' for commands.", ""])

    def run(self) -> None:
        self.intro()
        while True:
            try:
                line = self.read("> ")
            except EOFError:
                break
            if line is None:
                break
            line = line.strip()
            if not line:
                continue
            if line in ("quit", "exit", "q"):
                break
            try:
                self.dispatch(line)
            except InvestigationError as e:
                self.say(str(e))
            self.inv.save()
        self.inv.save()
        self.say("Notes saved.")

    # ------------------------------------------------------------------ commands
    def dispatch(self, line: str) -> None:
        try:
            parts = shlex.split(line)
        except ValueError:
            parts = line.split()
        cmd, args = parts[0].lower(), parts[1:]
        inv = self.inv
        if cmd == "help":
            self.say(HELP)
        elif cmd == "people":
            for r in inv.data["residents"]:
                status = {"deceased": " (dead)", "injured": " (injured)"}.get(r["condition"], "")
                self.say(f"  {r['first']:<9} {r['name']:<18} {r['occupation']}, {r['age_group']}{status}")
        elif cmd == "places":
            for p in inv.data["places"]:
                self.say(f"  {p['id']:<16} {p['name']}")
        elif cmd == "vehicles":
            for v in inv.data["vehicles"]:
                self.say(f"  {v['id']:<10} {v['name']} — parked at {inv._place_name(v['location'])}")
        elif cmd == "talk" and args:
            self.talk(" ".join(args))
        elif cmd == "ask" and len(args) >= 2:
            press = len(args) > 2 and args[2].lower() == "press"
            self.say(inv.ask(args[0], args[1], press))
        elif cmd == "inspect" and args:
            self.say(inv.inspect(" ".join(args)))
        elif cmd == "read" and args:
            day = int(args[1]) if len(args) > 1 and args[1].isdigit() else None
            self.say(inv.read(args[0], day))
        elif cmd == "cite" and args:
            eid = inv.cite_record(args[0])
            self.say(f"Copied into your notebook as {eid}." if eid else "No such entry in a book you have access to.")
        elif cmd == "notebook":
            self.notebook()
        elif cmd == "timeline":
            self.say(inv.timeline())
        elif cmd == "note" and args:
            self.say(f"Noted as {inv.note(' '.join(args))}.")
        elif cmd == "mark" and len(args) == 2:
            self.say("Marked." if inv.notebook.mark(args[0], args[1]) else "Couldn't mark that.")
        elif cmd == "hint":
            self.say(inv.buy_hint())
        elif cmd == "submit":
            self.submit()
        elif cmd == "giveup":
            self.say(inv.surrender())
        elif cmd == "reveal":
            self.say(inv.reveal())
        else:
            self.say("Unknown command. Type 'help'.")

    def notebook(self) -> None:
        entries = self.inv.notebook.entries()
        if not entries:
            self.say("Your notebook is empty.")
        for e in entries:
            when = f" ({fmt(e['time'])})" if e["time"] is not None else ""
            mark = f" <{e['mark']}>" if e["mark"] else ""
            self.say(f"  [{e['id']}]{when} {e['text']}{mark}")
        self.say(f"  Hint credits left: {self.inv.state['credits']}")

    def talk(self, who: str) -> None:
        inv = self.inv
        r = inv.resident(who)
        if r["condition"] == "deceased":
            self.say(f"{r['first']} is dead.")
            return
        topics = inv.topics(r["id"])
        letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        show = True
        while True:
            if show:
                self.say(["", f"{r['first'].upper()} — ask about what? (letter; p+letter to press; ? lists topics; "
                              "back)"])
                for i, (_tid, label) in enumerate(topics):
                    self.say(f"  {letters[i]}. {label}")
                show = False
            try:
                choice = self.read(f"{r['first'].lower()}> ")
            except EOFError:
                return
            if choice is None:
                return
            choice = choice.strip()
            if choice == "?":
                show = True
                continue
            if not choice or choice.lower() in ("back", "done", "bye"):
                return
            press = len(choice) == 2 and choice[0].lower() == "p"
            letter = choice[-1].upper()
            if letter not in letters[: len(topics)]:
                self.say("Pick a letter from the list.")
                continue
            self.say(inv.ask(r["id"], topics[letters.index(letter)][0], press))
            inv.save()

    def submit(self) -> None:
        inv = self.inv
        mechs = inv.mechanisms()
        self.say("What happened?")
        for i, m in enumerate(mechs, 1):
            self.say(f"  {i}. {m['label']}")
        mech = mechs[self._pick(len(mechs)) - 1]["id"]
        responsible = None
        motive = "unknown"
        if mech != "unresolved":
            name = self.read("Who is responsible? (a name, or 'none') ").strip()
            responsible = None if name.lower() in ("", "none", "no one", "nobody") else name
            motives = inv.motives()
            self.say("Why?")
            for i, m in enumerate(motives, 1):
                self.say(f"  {i}. {m['label']}")
            motive = motives[self._pick(len(motives)) - 1]["id"]
        cites = self.read("Notebook entries that support this (e.g. S3 X1 D2), or blank: ").split()
        summary = self.read("In a sentence, what happened? ")
        self.say(inv.submit(mech, responsible, motive, cites, summary))

    def _pick(self, n: int) -> int:
        while True:
            raw = self.read(f"Choose 1-{n}: ").strip()
            if raw.isdigit() and 1 <= int(raw) <= n:
                return int(raw)
            self.say("Please choose a number from the list.")


def run_interactive(case_dir: str, fresh: bool = False) -> None:
    inv = Investigation(case_dir, fresh=fresh)
    Repl(inv).run()


def run_script(case_dir: str, lines: list[str], fresh: bool = True) -> list[str]:
    """Drive a session from a list of input lines; returns everything printed."""
    inv = Investigation(case_dir, fresh=fresh)
    out: list[str] = []
    feed = iter(lines)

    def read(prompt: str) -> str:
        try:
            return next(feed)
        except StopIteration:
            raise EOFError from None

    Repl(inv, read=read, write=out.append).run()
    return out


if __name__ == "__main__":  # pragma: no cover
    run_interactive(sys.argv[1])
