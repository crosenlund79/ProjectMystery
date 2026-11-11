"""An investigation in progress: questioning, inspecting, notes, hints and the verdict.

This class never opens ``truth.json``. It works on a case directory where the truth
file has been removed, which is exactly what the spoiler-boundary tests check.
"""

from __future__ import annotations

import json
import os

from mystery.investigate import dialogue
from mystery.investigate.notebook import Notebook
from mystery.sim.clock import fmt


class InvestigationError(RuntimeError):
    pass


def _span(ids: list[str]) -> str:
    if len(ids) <= 2:
        return ", ".join(ids)
    nums = [int(i[1:]) for i in ids]
    if nums == list(range(nums[0], nums[0] + len(nums))):
        return f"{ids[0]}-{ids[-1]}"
    return ", ".join(ids)


class Investigation:
    def __init__(self, case_dir: str, session_path: str | None = None, fresh: bool = False):
        self.case_dir = case_dir
        with open(os.path.join(case_dir, "investigation.json"), encoding="utf-8") as f:
            self.data = json.load(f)
        self.session_path = session_path or os.path.join(case_dir, "session.json")
        if os.path.exists(self.session_path) and not fresh:
            with open(self.session_path, encoding="utf-8") as f:
                self.state = json.load(f)
            if self.state.get("case_id") != self.data["case_id"]:
                raise InvestigationError("session file belongs to a different case")
        else:
            self.state = {"case_id": self.data["case_id"], "credits": self.data["hint_credits"],
                          "hints_bought": 0, "concluded": False, "revealed": False, "theory": None}
        self.notebook = Notebook(self.state)

    # ----------------------------------------------------------- persistence
    def save(self) -> None:
        with open(self.session_path, "w", encoding="utf-8") as f:
            json.dump(self.state, f, indent=1, sort_keys=True)

    def _open(self) -> None:
        if self.state["revealed"]:
            raise InvestigationError("The truth has been revealed; this case is closed.")

    # ----------------------------------------------------------- lookups
    @property
    def hook(self) -> dict:
        return self.data["hook"]

    def resident(self, query: str) -> dict:
        q = query.strip().lower()
        matches = [r for r in self.data["residents"]
                   if r["id"] == q or r["first"].lower() == q or r["name"].lower() == q]
        if not matches:
            matches = [r for r in self.data["residents"] if r["first"].lower().startswith(q) and q]
        if len(matches) != 1:
            raise InvestigationError(f"No single resident matches {query!r}.")
        return matches[0]

    def name(self, rid: str) -> str:
        for r in self.data["residents"]:
            if r["id"] == rid:
                return r["first"]
        return rid

    def place(self, query: str) -> dict:
        q = query.strip().lower()
        if q.startswith("the "):
            q = q[4:]
        cands = [p for p in self.data["places"]
                 if p["id"].lower() == q or p["name"].lower().removeprefix("the ") == q
                 or p["id"].split(":")[-1] == q]
        if not cands:
            cands = [p for p in self.data["places"] if q and q in p["name"].lower()]
        if len(cands) != 1:
            raise InvestigationError(f"No single place matches {query!r}.")
        return cands[0]

    def vehicle(self, query: str) -> dict | None:
        q = query.strip().lower()
        for v in self.data["vehicles"]:
            if q in (v["id"], v["kind"]) or q in v["name"].lower():
                return v
        return None

    def book(self, query: str) -> tuple[str, dict]:
        q = query.strip().lower()
        aliases = {"clinic": "clinic_log", "workshop": "workshop_orders", "orders": "workshop_orders",
                   "pub": "tabs", "bar": "tabs", "grocery": "ledger", "sales": "ledger"}
        key = aliases.get(q, q)
        if key not in self.data["records"]:
            raise InvestigationError(f"No record book called {query!r}. Try: {', '.join(self.data['records'])}.")
        return key, self.data["records"][key]

    # ----------------------------------------------------------- questioning
    def topics(self, rid: str) -> list[tuple[str, str]]:
        return dialogue.topics_for(self.data, rid)

    def ask(self, who: str, topic: str, press: bool = False) -> list[str]:
        self._open()
        r = self.resident(who)
        if r["condition"] == "deceased":
            return [f"{r['first']} is dead."]
        if topic.startswith("about:"):
            topic = f"person:{self.resident(topic[6:])['id']}"
        valid = {t for t, _ in self.topics(r["id"])}
        if topic not in valid:
            raise InvestigationError(f"Unknown topic {topic!r}.")
        lines, _heard = dialogue.answer(self.data, self.state, r["id"], topic, press)
        out = []
        for i, (text, members) in enumerate(lines):
            ids = [self.notebook.record("S", it["key"], f"{r['first']}: \"{it['text']}\"", "statement",
                                        it["time"], r["id"]) for it in members]
            tag = f"  [{_span(ids)}]" if ids else ""
            out.append((f"{r['first'].upper()}: " if i == 0 else "  ") + text + tag)
        return out

    # ----------------------------------------------------------- looking around
    def inspect(self, query: str) -> list[str]:
        self._open()
        v = self.vehicle(query)
        if v is not None:
            return self._inspect_vehicle(v)
        p = self.place(query)
        out = [f"{p['name'].upper()}"]
        if not p["allowed"]:
            out.append(p["reply"])
            self.notebook.record("O", f"refused:{p['id']}", f"Refused entry to {p['name']}. {p['reply']}", "observation")
            return out
        if p["reply"] and p["owners"]:
            out.append(p["reply"])
        if not p["traces"]:
            out.append("Nothing out of the ordinary.")
        for tr in p["traces"]:
            eid = self.notebook.record("X", tr["id"], f"At {p['name']}: {tr['description']}", "trace")
            out.append(f"  [{eid}] {tr['description']}")
        books = [k for k, b in self.data["records"].items() if b["place"] == p["id"]]
        for k in books:
            out.append(f"  ({self.data['records'][k]['title']} is kept here: 'read {k}')")
        parked = [x for x in self.data["vehicles"] if x["location"] == p["id"]]
        for x in parked:
            out.append(f"  ({x['name']} is parked here: 'inspect {x['id']}')")
        return out

    def _inspect_vehicle(self, v: dict) -> list[str]:
        out = [f"{v['name'].upper()} (parked at {self._place_name(v['location'])})"]
        if not v["allowed"]:
            out.append(v["reply"])
            self.notebook.record("O", f"refused:{v['id']}", f"Not allowed to look at {v['name']}. {v['reply']}",
                                 "observation")
            return out
        if not v["traces"]:
            out.append("Nothing unusual about it.")
        for tr in v["traces"]:
            eid = self.notebook.record("X", tr["id"], tr["description"], "trace")
            out.append(f"  [{eid}] {tr['description']}")
        return out

    def _place_name(self, pid: str) -> str:
        for p in self.data["places"]:
            if p["id"] == pid:
                return p["name"]
        return pid

    def read(self, query: str, day: int | None = None) -> list[str]:
        self._open()
        key, b = self.book(query)
        out = [f"{b['title'].upper()}"]
        if not b["allowed"]:
            out.append(b["reply"])
            self.notebook.record("O", f"refused:{key}", f"Not allowed to read the {b['title']}. {b['reply']}",
                                 "observation")
            return out
        entries = b["entries"]
        if day is not None:
            entries = [e for e in entries if e["time"] // 1440 + 1 == day]
        if not entries:
            out.append("No entries for that period.")
        for e in entries:
            out.append(f"  [{e['id'][2:]}] {e['text']}")
        self.notebook.record("O", f"read:{key}:{day}", f"Read the {b['title']}" + (f" for Day {day}" if day else ""),
                             "observation")
        return out

    def record_entry(self, ref: str) -> dict | None:
        for b in self.data["records"].values():
            if not b["allowed"]:
                continue
            for e in b["entries"]:
                if e["id"][2:].lower() == ref.lower() or e["id"].lower() == ref.lower():
                    return e
        return None

    # ----------------------------------------------------------- notes
    def note(self, text: str) -> str:
        return self.notebook.record("N", None, text, "note")

    def cite_record(self, ref: str) -> str | None:
        e = self.record_entry(ref)
        if e is None:
            return None
        return self.notebook.record("D", e["id"], e["text"], "record", e["time"])

    def timeline(self) -> list[str]:
        timed = [e for e in self.notebook.entries() if e["time"] is not None]
        timed.sort(key=lambda e: (e["time"], e["id"]))
        out = []
        for e in timed:
            mark = f" ({e['mark']})" if e["mark"] else ""
            out.append(f"  {fmt(e['time'])}  [{e['id']}] {e['text']}{mark}")
        return out or ["  (Nothing with a time on it yet.)"]

    # ----------------------------------------------------------- hints
    def buy_hint(self) -> list[str]:
        self._open()
        hints = self.data["hints"]
        n = self.state["hints_bought"]
        if n >= len(hints):
            return ["There are no more hints for this case."]
        h = hints[n]
        if self.state["credits"] < h["cost"]:
            return [f"The next hint costs {h['cost']} credits; you have {self.state['credits']}."]
        self.state["credits"] -= h["cost"]
        self.state["hints_bought"] = n + 1
        self.state.setdefault("hint_spend", 0)
        self.state["hint_spend"] += h["cost"]
        labels = {1: "Nudge", 2: "Lead", 3: "Strong hint"}
        return [f"{labels.get(h['tier'], 'Hint')} ({h['cost']} credit{'s' if h['cost'] > 1 else ''}): {h['text']}",
                f"  Credits left: {self.state['credits']}"]

    # ----------------------------------------------------------- conclusion
    def mechanisms(self) -> list[dict]:
        return self.data["theory_options"]["mechanisms"]

    def motives(self) -> list[dict]:
        return self.data["theory_options"]["motives"]

    def submit(self, mechanism: str, responsible: str | None, motive: str = "unknown",
               cites: list[str] | None = None, summary: str = "") -> list[str]:
        self._open()
        if self.state["concluded"]:
            raise InvestigationError("You have already concluded this case.")
        if mechanism not in {m["id"] for m in self.mechanisms()}:
            raise InvestigationError(f"Unknown explanation {mechanism!r}.")
        if motive not in {m["id"] for m in self.motives()}:
            raise InvestigationError(f"Unknown motive {motive!r}.")
        rid = None
        if responsible and responsible.lower() not in ("none", "no one", "nobody", "-"):
            rid = self.resident(responsible)["id"]
        refs = []
        for c in cites or []:
            e = self.notebook.get(c)
            if e is None:
                rec = self.record_entry(c)
                if rec is None:
                    raise InvestigationError(f"{c} is not in your notebook or an open record book.")
                e = self.notebook.get(self.cite_record(c))  # type: ignore[arg-type]
            refs.append(e["id"])
        self.state["theory"] = {"mechanism": mechanism, "responsible": rid, "motive": motive, "cites": refs,
                                "summary": summary}
        self.state["concluded"] = True
        self.save()
        who = self.name(rid) if rid else "no one"
        return [f"Theory recorded: {mechanism.replace('_', ' ')}; responsible: {who}; motive: "
                f"{motive.replace('_', ' ')}; citing {', '.join(refs) or 'nothing'}.",
                "Type 'reveal' to see what really happened."]

    def surrender(self) -> list[str]:
        self._open()
        self.state["concluded"] = True
        self.state["theory"] = None
        self.save()
        return ["You set the case aside without a theory. Type 'reveal' to see what really happened."]

    def reveal(self) -> list[str]:
        from mystery.investigate.verdict import reveal
        return reveal(self)
