"""Is a case investigable, and how?

Two questions are kept apart: did something interesting happen (the incident), and
can a careful player reasonably infer anything about it (this module). A case is
judged by its *independent channels*: separate witnesses, physical traces,
documentary records and contradictions that point at what really happened and are
actually reachable by the player at the moment the case starts.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from mystery.sim.clock import day_of, fmt_clock

if TYPE_CHECKING:
    from mystery.cases.export import _Builder

VERDICTS = ("obvious", "playable", "ambiguous", "unsolvable")


RESPONSIBLE_TAGS = ("places_responsible", "act", "vehicle", "absence", "sudden_money")


def evaluate(b: "_Builder", consent: dict, evidence: dict, records: dict) -> dict:
    sim, inc = b.sim, b.inc
    R = inc.responsible
    chain = set(b.chain)
    channels: list[dict] = []
    misleading: set[tuple[str, str]] = set()
    eyewitnesses = []

    # --- testimony: one channel per independent witness
    by_speaker: dict[str, dict] = {}
    for key, a in b.audit.items():
        if key.startswith("W-") or a.get("summary"):
            continue  # summaries repeat their members; they are not separate witnesses
        sup = a.get("supports", [])
        if "misleading" in sup:
            misleading.add((a["speaker"], key))
        if a["status"] != "accurate" or a["speaker"] == R:
            continue
        resp = [s for s in sup if s in RESPONSIBLE_TAGS]
        mech = [s for s in sup if s == "mechanism"]
        if not resp and not mech:
            continue
        root = a.get("root") or a["speaker"]
        if root == R:
            continue  # the culprit's own words, retold, are not independent evidence
        ch = by_speaker.setdefault(root, {"keys": [], "responsible": False, "mechanism": False,
                                          "direct": False, "circumstantial": True, "guarded_only": True,
                                          "speakers": []})
        ch["keys"].append(key)
        if a["speaker"] not in ch["speakers"]:
            ch["speakers"].append(a["speaker"])
        ch["responsible"] |= bool(resp)
        ch["circumstantial"] &= not resp or resp == ["sudden_money"]
        ch["mechanism"] |= bool(mech)
        ch["direct"] |= a["source"] in ("saw", "self", "heard") and a["speaker"] == root
        ch["guarded_only"] &= a.get("disclosure") == "guarded"
        if "act" in sup:
            eyewitnesses.append(root)
    for root, ch in sorted(by_speaker.items()):
        strength = "strong" if ch["direct"] and not (ch["responsible"] and ch["circumstantial"]) else "hearsay"
        channels.append({"type": "witness", "source": root, "speakers": ch["speakers"], "keys": ch["keys"][:6],
                         "points_to": "responsible" if ch["responsible"] else "mechanism",
                         "strength": strength, "needs_pressing": ch["guarded_only"]})

    # --- contradictions: the responsible person's lie against an accurate account or a record, as the
    # player's own timeline would show it (a firm clash or a record against a statement, not a matter of
    # approximate times)
    lies = [k for k, a in b.audit.items() if a.get("lie") and a["speaker"] == R and not k.startswith("W-")
            and not a.get("exact_of")]
    exposing = exposed_lies(b, consent, records, lies) if lies else []
    if exposing:
        keys = []
        for pair in exposing:
            keys.extend(k for k in pair if k not in keys)
        channels.append({"type": "contradiction", "source": R, "keys": keys[:6], "points_to": "responsible",
                         "strength": "strong",
                         "needs_pressing": all(b.audit.get(k, {}).get("disclosure") == "guarded"
                                               for pair in exposing for k in pair if not k.startswith("R-"))})

    # --- physical traces
    for place, items in sorted(evidence.items()):
        if place in consent:
            allowed = consent[place]["allowed"]
        else:
            vloc = sim.world.vehicles[place].location
            allowed = sim.world.locations[vloc].kind != "home" or consent[vloc]["allowed"]
        linked = [e for e in items if e.created_by in chain or (R and R in e.implicates)]
        if linked:
            channels.append({"type": "physical", "source": place, "keys": [f"T-{e.id}" for e in linked],
                             "points_to": "responsible" if R and any(R in e.implicates for e in linked)
                             else "mechanism", "strength": "strong" if allowed else "blocked",
                             "needs_pressing": False})

    # --- documentary records
    drink_window = (inc.time - 6 * 60, inc.time)
    for book, data in sorted(records.items()):
        allowed = consent[data["place"]]["allowed"]
        keys, resp = [], False
        for x in data["entries"]:
            ev = sim.log.by_id[x.event_id]
            if (ev.kind == "ledger_error" and inc.family == "accounting_error" and x.event_id in chain) or \
                    (x.event_id in chain and ev.kind in ("purchase",)):
                keys.append(f"R-{x.id}")
            elif x.event_id in chain and ev.kind in ("repair", "treated"):
                keys.append(f"R-{x.id}")
                resp = resp or (R is not None and (R in ev.actors or R in ev.targets))
            elif R and ev.kind == "drink" and R in ev.actors and drink_window[0] <= ev.time <= drink_window[1] \
                    and inc.family in ("collision", "assault"):
                keys.append(f"R-{x.id}")
                resp = True
            elif inc.family == "fall" and ev.kind == "drink" and ev.actors[0] in inc.victims \
                    and drink_window[0] <= ev.time <= drink_window[1]:
                keys.append(f"R-{x.id}")
        if keys:
            channels.append({"type": "documentary", "source": book, "keys": keys[:6],
                             "points_to": "responsible" if resp else "mechanism",
                             "strength": "strong" if allowed else "blocked", "needs_pressing": False})

    usable = [c for c in channels if c["strength"] in ("strong", "hearsay")]
    strong = [c for c in usable if c["strength"] == "strong"]
    # How the answer can be worked out from evidence, rather than guessed from motive and gossip
    routes = set()
    if R is not None:
        if exposing:
            routes.add("contradiction")
        victims_naming = [k for k, a in b.audit.items() if not k.startswith("W-") and not a.get("summary")
                          and a["status"] == "accurate" and a["speaker"] != R and a["source"] == "self"
                          and {"places_responsible", "mechanism"} <= set(a.get("supports", []))]
        if eyewitnesses or victims_naming:
            routes.add("eyewitness")
        if only_one_there(b, consent, records) == R:
            routes.add("opportunity")
        for c in strong:
            if c["type"] in ("physical", "documentary") and c["points_to"] == "responsible":
                routes.add(c["type"])
    else:
        for c in strong:
            if c["points_to"] == "mechanism" and c["type"] in ("physical", "documentary", "witness"):
                routes.add(f"{c['type']} (what happened)")
    if R is not None:
        resp = [c for c in usable if c["points_to"] == "responsible"]
        resp_strong = [c for c in resp if c["strength"] == "strong"]
        if len(set(eyewitnesses)) >= 2 and len(usable) >= 3:
            verdict = "obvious"
        elif resp_strong and len(resp) >= 2:
            verdict = "playable"
        elif resp:
            verdict = "ambiguous"
        else:
            verdict = "unsolvable"
    else:
        if len(strong) >= 2 or any(c["type"] in ("documentary", "physical") for c in strong):
            verdict = "playable"
        elif usable:
            verdict = "ambiguous"
        else:
            verdict = "unsolvable"
    statuses: dict[str, int] = {}
    mistakes: dict[str, int] = {}
    for key, a in b.audit.items():
        if key.startswith("W-") or a.get("summary") or a.get("exact_of"):
            continue
        statuses[a["status"]] = statuses.get(a["status"], 0) + 1
        if a["status"] == "mistaken":
            err = a.get("error") or "unknown"
            mistakes[err] = mistakes.get(err, 0) + 1
    return {
        "case_id": b.case_id,
        "family": inc.family,
        "statement_status": statuses,
        "mistaken_by_cause": mistakes,
        "mechanism": inc.mechanism,
        "outcome": inc.outcome,
        "noticed": inc.discovered_at is not None,
        "verdict": verdict,
        "deduction": sorted(routes),
        "solvable_by_evidence": bool(routes),
        "channels": channels,
        "independent_channels": len(usable),
        "responsible_channels": len([c for c in usable if c["points_to"] == "responsible"]),
        "blocked_channels": len([c for c in channels if c["strength"] == "blocked"]),
        "eyewitnesses": sorted(set(eyewitnesses)),
        "red_herrings": len({k[0] for k in misleading}),
        "lies_by_responsible": len(lies),
        "statements": len([k for k, a in b.audit.items() if not k.startswith("W-") and not a.get("summary")
                           and not a.get("exact_of")]),
        "summaries": len([k for k, a in b.audit.items() if a.get("summary")]),
        "withheld": len([k for k in b.audit if k.startswith("W-")]),
    }


def exposed_lies(b: "_Builder", consent: dict, records: dict, lies: list[str]) -> list[tuple[str, str]]:
    """(lie, other) pairs where a lie of the responsible person clashes - firmly, or with a record - with an
    accurate statement of someone else or a record line the player can read."""
    from mystery.investigate.contradictions import contradictions
    facts, info = [], {}
    for rid, items in b.items.items():
        for it in items:
            a = b.audit[it["key"]]
            if a.get("summary"):
                continue
            info[it["key"]] = {"kind": "statement", "source": it["source"], "summary": False}
            facts.extend({"entry": it["key"], **f} for f in it["facts"])
    for book, data in records.items():
        if not consent[data["place"]]["allowed"]:
            continue
        for x in data["entries"]:
            ref = f"R-{x.id}"
            fx = b._record_facts(x, data["place"])
            if fx:
                info[ref] = {"kind": "record", "source": "record", "summary": False}
                facts.extend({"entry": ref, **f} for f in fx)
    told_in_full = {k: a["exact_of"] for k, a in b.audit.items() if a.get("exact_of") in lies}
    out = []
    for c in contradictions(facts, info):
        for x, y, kind in c["pairs"]:
            if kind not in ("firm", "document"):
                continue
            for lie, other in ((x, y), (y, x)):
                lie = told_in_full.get(lie, lie)
                if lie in lies and (other.startswith("R-") or (b.audit[other]["status"] == "accurate"
                                                               and b.audit[other]["speaker"] != b.inc.responsible)):
                    if (lie, other) not in out:
                        out.append((lie, other))
    return out


def only_one_there(b: "_Builder", consent: dict, records: dict) -> str | None:
    """The one person that accurate statements and readable records put at the scene during the time in
    question, if there is exactly one: whoever it is had the only opportunity, as the player can work out."""
    scene, (w0, w1) = b.inc.hook_place, b.window
    there = set()
    for rid, items in b.items.items():
        for it in items:
            a = b.audit[it["key"]]
            if a.get("summary") or a["status"] != "accurate":
                continue
            for f in it["facts"]:
                if f["place"] == scene and f["from"] < w1 and f["to"] > w0:
                    there.add(f["who"])
    for book, data in records.items():
        if consent[data["place"]]["allowed"]:
            for x in data["entries"]:
                for f in b._record_facts(x, data["place"]):
                    if f["place"] == scene and w0 < f["from"] < w1:
                        there.add(f["who"])
    return there.pop() if len(there) == 1 else None


def hints(b: "_Builder", report: dict) -> list[dict]:
    """A ladder of hints that only ever point at things the player can actually find."""
    sim = b.sim
    win = f"{fmt_clock(b.window[0])} on Day {day_of(b.window[0])}"
    order = {"contradiction": 0, "documentary": 1, "physical": 2, "witness": 3}
    usable = [c for c in report["channels"] if c.get("strength") in ("strong", "hearsay")]
    usable.sort(key=lambda c: (order[c["type"]], c["source"]))
    if not usable:
        return [
            {"tier": 1, "cost": 1, "text": "Not every case leaves enough behind. It is fair to conclude that you "
                                           "cannot tell what happened."},
            {"tier": 2, "cost": 2, "text": "Look for anyone who was out and about during the time in question; "
                                           "if no one was, an 'unresolved' verdict is honest."},
        ]
    first = usable[0]
    by_type = {
        "contradiction": "Not every account of the time in question holds together. Compare what people say "
                         "about where they were.",
        "documentary": "Written records sometimes remember what people forget.",
        "physical": "Things left behind can say as much as people do.",
        "witness": "Someone was out and about at the time. Ask people what they saw or heard.",
    }
    out = [{"tier": 1, "cost": 1, "text": by_type[first["type"]]}]
    lead = None
    for c in usable:
        if c["type"] == "witness":
            lead = f"Ask {sim.residents[c['source']].first} what they saw or heard around {win}."
        elif c["type"] == "documentary":
            lead = f"Have a look at the {sim.world.books[c['source']]['title'].lower()}."
        elif c["type"] == "physical":
            lead = f"Take a careful look at {sim.world.name(c['source'])}."
        if lead:
            break
    if lead:
        out.append({"tier": 2, "cost": 2, "text": lead})
    strong = None
    contra = [c for c in usable if c["type"] == "contradiction"]
    if contra:
        witness = next((c for c in usable if c["type"] == "witness"), None)
        liar = sim.residents[contra[0]["source"]].first
        if witness:
            strong = (f"Compare {liar}'s account of where they were with what "
                      f"{sim.residents[witness['source']].first} says about the same hours.")
    if strong is None:
        docs = [c for c in usable if c["type"] == "documentary"]
        if docs and b.inc.family == "accounting_error":
            strong = "Read the ledger line by line for the day the till came up short. Count the sales."
        elif docs:
            strong = f"The {sim.world.books[docs[0]['source']]['title'].lower()} places someone at a telling time."
    if strong is None:
        phys = [c for c in usable if c["type"] == "physical"]
        if phys:
            strong = f"What is at {sim.world.name(phys[0]['source'])} connects to the incident. Who could have " \
                     f"left it?"
    if strong is None and len(usable) > 1:
        c = usable[1]
        if c["type"] == "witness":
            strong = f"{sim.residents[c['source']].first} also knows something about the time in question."
    if strong:
        out.append({"tier": 3, "cost": 3, "text": strong})
    return out
