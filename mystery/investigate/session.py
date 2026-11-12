"""An investigation in progress: questioning, inspecting, notes, hints and the verdict.

This class never opens ``truth.json``. It works on a case directory where the truth
file has been removed, which is exactly what the spoiler-boundary tests check.
"""

from __future__ import annotations

import json
import os

from mystery.investigate import dialogue
from mystery.investigate.contradictions import contradictions, entry_order
from mystery.investigate.notebook import Notebook
from mystery.sim.clock import fmt


class InvestigationError(RuntimeError):
    pass


def _entry_order(eid: str) -> tuple:
    return entry_order(eid)


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

    def ask_result(self, who: str, topic: str, press: bool = False, follow: str = "") -> dict:
        """Structured answer (the contract the Godot game reproduces; see docs/investigation-rules.md).

        follow: "" for the question itself, "more" for "tell me more", "earlier" for "and before that?"."""
        self._open()
        r = self.resident(who)
        if topic.startswith("about:"):
            topic = f"person:{self.resident(topic[6:])['id']}"
        if follow not in ("",) + dialogue.FOLLOWS or (follow and press):
            raise InvestigationError(f"Unknown follow-up {follow!r}.")
        res = {"op": "ask", "speaker": r["id"], "topic": topic, "pressed": press, "follow": follow, "dead": False,
               "lines": [], "goodwill": None, "can_press": False, "can_more": False, "can_earlier": False,
               "followups": []}
        if r["condition"] == "deceased":
            res["dead"] = True
            res["lines"] = [{"text": f"{r['first']} is dead.", "notes": []}]
            return res
        valid = {t for t, _ in self.topics(r["id"])}
        if topic not in valid:
            raise InvestigationError(f"Unknown topic {topic!r}.")
        lines, _heard = dialogue.answer(self.data, self.state, r["id"], topic, press, follow)
        followups: list[str] = []
        for text, members in lines:
            ids = [self.notebook.record("S", it["key"], f"{r['first']}: \"{it['text']}\"", "statement",
                                        it["time"], r["id"]) for it in members]
            res["lines"].append({"text": text, "notes": ids})
            for it in members:
                for x in it["about"]:
                    if x != r["id"] and x not in followups:
                        followups.append(x)
        res["goodwill"] = self.state["goodwill"][r["id"]]
        res["can_press"] = topic not in self.state["pressed"][r["id"]] and res["goodwill"] > 0
        res.update(dialogue.follow_ups(self.data, self.state, r["id"], topic))
        res["followups"] = sorted(followups)
        return res

    def ask(self, who: str, topic: str, press: bool = False, follow: str = "") -> list[str]:
        res = self.ask_result(who, topic, press, follow)
        if res["dead"]:
            return [res["lines"][0]["text"]]
        first = self.name(res["speaker"])
        out = []
        for i, line in enumerate(res["lines"]):
            tag = f"  [{_span(line['notes'])}]" if line["notes"] else ""
            out.append((f"{first.upper()}: " if i == 0 else "  ") + line["text"] + tag)
        more = [w for w, on in (("'more' for details", res["can_more"]), ("'earlier' for before that",
                                                                          res["can_earlier"])) if on]
        if more:
            out.append(f"  (Follow up: {', '.join(more)}.)")
        return out

    # ----------------------------------------------------------- looking around
    def place_by_id(self, pid: str) -> dict:
        for p in self.data["places"]:
            if p["id"] == pid:
                return p
        raise InvestigationError(f"No place {pid!r}.")

    def vehicle_by_id(self, vid: str) -> dict:
        for v in self.data["vehicles"]:
            if v["id"] == vid:
                return v
        raise InvestigationError(f"No vehicle {vid!r}.")

    def inspect_place_result(self, pid: str) -> dict:
        self._open()
        p = self.place_by_id(pid)
        res = {"op": "inspect_place", "id": p["id"], "name": p["name"], "allowed": p["allowed"],
               "reply": p["reply"], "show_reply": bool(p["reply"] and p["owners"]), "traces": [], "books": [],
               "vehicles": [], "note": None}
        if not p["allowed"]:
            res["show_reply"] = True
            res["note"] = self.notebook.record("O", f"refused:{p['id']}", f"Refused entry to {p['name']}. {p['reply']}",
                                               "observation")
            return res
        for tr in p["traces"]:
            eid = self.notebook.record("X", tr["id"], f"At {p['name']}: {tr['description']}", "trace")
            res["traces"].append({"id": tr["id"], "description": tr["description"], "note": eid})
        res["books"] = [k for k, b in self.data["records"].items() if b["place"] == p["id"]]
        res["vehicles"] = [x["id"] for x in self.data["vehicles"] if x["location"] == p["id"]]
        return res

    def inspect_vehicle_result(self, vid: str) -> dict:
        self._open()
        v = self.vehicle_by_id(vid)
        res = {"op": "inspect_vehicle", "id": v["id"], "name": v["name"], "location": v["location"],
               "allowed": v["allowed"], "reply": v["reply"], "traces": [], "note": None}
        if not v["allowed"]:
            res["note"] = self.notebook.record("O", f"refused:{v['id']}", f"Not allowed to look at {v['name']}. "
                                               f"{v['reply']}", "observation")
            return res
        for tr in v["traces"]:
            eid = self.notebook.record("X", tr["id"], tr["description"], "trace")
            res["traces"].append({"id": tr["id"], "description": tr["description"], "note": eid})
        return res

    def inspect(self, query: str) -> list[str]:
        self._open()
        q = query.strip().lower()
        v = next((x for x in self.data["vehicles"] if q == x["id"]), None)
        if v is None:
            try:
                p = self.place(query)  # an exact place match wins over a vehicle whose name contains it
            except InvestigationError:
                v = self.vehicle(query)
                if v is None:
                    raise
            else:
                return self._format_place(self.inspect_place_result(p["id"]))
        res = self.inspect_vehicle_result(v["id"])
        out = [f"{res['name'].upper()} (parked at {self._place_name(res['location'])})"]
        if not res["allowed"]:
            return out + [res["reply"]]
        if not res["traces"]:
            out.append("Nothing unusual about it.")
        out += [f"  [{t['note']}] {t['description']}" for t in res["traces"]]
        return out

    def _format_place(self, res: dict) -> list[str]:
        out = [f"{res['name'].upper()}"]
        if not res["allowed"]:
            return out + [res["reply"]]
        if res["show_reply"]:
            out.append(res["reply"])
        if not res["traces"]:
            out.append("Nothing out of the ordinary.")
        out += [f"  [{t['note']}] {t['description']}" for t in res["traces"]]
        for k in res["books"]:
            out.append(f"  ({self.data['records'][k]['title']} is kept here: 'read {k}')")
        for vid in res["vehicles"]:
            out.append(f"  ({self.vehicle_by_id(vid)['name']} is parked here: 'inspect {vid}')")
        return out

    def _place_name(self, pid: str) -> str:
        for p in self.data["places"]:
            if p["id"] == pid:
                return p["name"]
        return pid

    def read_result(self, key: str, day: int | None = None) -> dict:
        self._open()
        if key not in self.data["records"]:
            raise InvestigationError(f"No record book {key!r}.")
        b = self.data["records"][key]
        res = {"op": "read", "book": key, "title": b["title"], "allowed": b["allowed"], "reply": b["reply"],
               "day": day, "entries": [], "note": None}
        if not b["allowed"]:
            res["note"] = self.notebook.record("O", f"refused:{key}", f"Not allowed to read the {b['title']}. "
                                               f"{b['reply']}", "observation")
            return res
        entries = b["entries"]
        if day is not None:
            entries = [e for e in entries if e["time"] // 1440 + 1 == day]
        res["entries"] = [{"id": e["id"], "time": e["time"], "text": e["text"]} for e in entries]
        res["note"] = self.notebook.record("O", f"read:{key}:{day}", f"Read the {b['title']}" +
                                           (f" for Day {day}" if day else ""), "observation")
        return res

    def read(self, query: str, day: int | None = None) -> list[str]:
        key, b = self.book(query)
        res = self.read_result(key, day)
        out = [f"{b['title'].upper()}"]
        if not res["allowed"]:
            return out + [res["reply"]]
        if not res["entries"]:
            out.append("No entries for that period.")
        out += [f"  [{e['id'][2:]}] {e['text']}" for e in res["entries"]]
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
    def note(self, text: str, time: int | None = None) -> str:
        return self.notebook.record("N", None, text, "note", time)

    def cite_record(self, ref: str) -> str | None:
        e = self.record_entry(ref)
        if e is None:
            return None
        return self.notebook.record("D", e["id"], e["text"], "record", e["time"])

    def _item(self, key: str) -> dict | None:
        if not hasattr(self, "_items_by_key"):
            self._items_by_key = {it["key"]: it for t in self.data["testimony"].values() for it in t["items"]}
        return self._items_by_key.get(key)

    def timeline_model(self) -> dict:
        """Discovered entries in time order, the claims they make, and the accounts that cannot all be
        true (mystery/investigate/contradictions.py)."""
        timed = [e for e in self.notebook.entries() if e["time"] is not None]
        timed.sort(key=lambda e: (e["time"], e["id"]))
        facts = []
        info = {}
        for e in self.notebook.entries():
            source = None
            if e["source"] == "statement" and e.get("ref"):
                item = self._item(e["ref"]) or {}
                info[e["id"]] = {"kind": "statement", "source": item.get("source", ""),
                                 "summary": len(item.get("members", [])) >= 2}
                source = item
            elif e["source"] == "record" and e.get("ref"):
                source = self.record_entry(e["ref"]) or {}
                info[e["id"]] = {"kind": "record", "source": "record", "summary": False}
            for f in (source or {}).get("facts", []):
                facts.append({"entry": e["id"], **f})
        found = contradictions(facts, info)
        partner: dict[str, set] = {}
        for c in found:
            for x, y, kind in c["pairs"]:
                if kind != "approximate":
                    partner.setdefault(x, set()).add(y)
                    partner.setdefault(y, set()).add(x)
        return {
            "entries": [{"id": e["id"], "time": e["time"], "label": fmt(e["time"]), "text": e["text"],
                         "mark": e["mark"], "conflicts": sorted(partner.get(e["id"], []), key=_entry_order)}
                        for e in timed],
            "facts": facts,
            "contradictions": found,
        }

    def timeline(self) -> list[str]:
        model = self.timeline_model()
        out = []
        for e in model["entries"]:
            mark = f" ({e['mark']})" if e["mark"] else ""
            out.append(f"  {e['label']}  [{e['id']}] {e['text']}{mark}")
        if not out:
            return ["  (Nothing with a time on it yet.)"]
        for c in model["contradictions"]:
            out.append("  " + self.explain(c))
        return out

    KIND_WORDS = {
        "firm": "CANNOT BOTH BE TRUE - someone is lying or mistaken",
        "document": "A RECORD SAYS OTHERWISE",
        "uncertain": "UNSURE SIGHTING - it was dark; perhaps it was someone else",
        "secondhand": "SECONDHAND - one of them is repeating what they were told",
        "approximate": "minor: the times are only approximate",
    }

    def explain(self, c: dict) -> str:
        """One line: who, the two entries, where each puts them, and how far the times overlap."""
        who = self.name(c["who"])
        def where(f: dict) -> str:
            span = fmt(f["from"]) if f["from"] == f["to"] else f"{fmt(f['from'])}-{fmt(f['to'])[-5:]}"
            return f"{self._place_name(f['place'])} ({span})"
        lo, hi = c["overlap"]
        when = fmt(lo) if lo == hi else f"{fmt(lo)}-{fmt(hi)[-5:]}"
        return (f"[{c['a']} vs {c['b']}] {who}: {where(c['a_fact'])} or {where(c['b_fact'])}? "
                f"Clash at {when}, {c['depth']} min deep. {self.KIND_WORDS[c['kind']]}.")

    # ----------------------------------------------------------- hints
    def hint_result(self) -> dict:
        self._open()
        hints = self.data["hints"]
        n = self.state["hints_bought"]
        res = {"op": "hint", "ok": False, "tier": None, "label": None, "cost": None, "text": None,
               "credits": self.state["credits"], "message": None}
        if n >= len(hints):
            res["message"] = "There are no more hints for this case."
            return res
        h = hints[n]
        if self.state["credits"] < h["cost"]:
            res["message"] = f"The next hint costs {h['cost']} credits; you have {self.state['credits']}."
            return res
        self.state["credits"] -= h["cost"]
        self.state["hints_bought"] = n + 1
        self.state.setdefault("hint_spend", 0)
        self.state["hint_spend"] += h["cost"]
        labels = {1: "Nudge", 2: "Lead", 3: "Strong hint"}
        res.update(ok=True, tier=h["tier"], label=labels.get(h["tier"], "Hint"), cost=h["cost"], text=h["text"],
                   credits=self.state["credits"])
        return res

    def buy_hint(self) -> list[str]:
        res = self.hint_result()
        if not res["ok"]:
            return [res["message"]]
        return [f"{res['label']} ({res['cost']} credit{'s' if res['cost'] > 1 else ''}): {res['text']}",
                f"  Credits left: {res['credits']}"]

    # ----------------------------------------------------------- conclusion
    def mechanisms(self) -> list[dict]:
        return self.data["theory_options"]["mechanisms"]

    def motives(self) -> list[dict]:
        return self.data["theory_options"]["motives"]

    def submit_result(self, mechanism: str, responsible: str | None, motive: str = "unknown",
                      cites: list[str] | None = None, summary: str = "") -> dict:
        self.submit(mechanism, responsible, motive, cites, summary)
        th = self.state["theory"]
        return {"op": "submit", "ok": True, "mechanism": th["mechanism"], "responsible": th["responsible"],
                "motive": th["motive"], "cites": list(th["cites"])}

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
