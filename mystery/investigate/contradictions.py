"""Accounts that cannot all be true, as a player could work them out from their notebook.

Every notebook entry with `facts` (statements, and record lines that name someone) says where someone was.
Two facts about the same person at different places at the same time clash. This module groups the clashes
that describe the same disagreement and classifies each one by what the player can see - never by what is
actually true:

* ``firm``        two first-hand accounts that cannot both be right: someone is lying or mistaken.
* ``document``    a written record (a bar tab, the ledger, the clinic log) against a statement.
* ``uncertain``   one of them was not sure who they saw (it was dark): perhaps it was someone else.
* ``secondhand``  one of them is repeating what they were told.
* ``approximate`` the clash is no bigger than the "about" in people's times: probably a misremembered or
                  rounded time rather than a real contradiction. Shown as a minor note, never as a conflict.

The Godot game implements the same rules (scripts/core/investigation.gd); parity fixtures check both.
"""

from __future__ import annotations

MARGIN = 20      # minutes; a moment must fall this far inside a stay elsewhere to clash with it
APPROX = 60      # first-hand accounts clashing by no more than this are only approximate
DOCUMENT = 30    # a record's time is exact, a statement's is "about": this much is approximate
NEAR = 30        # clashes about the same person and places this close in time are the same disagreement

KIND_RANK = {"firm": 4, "document": 3, "secondhand": 2, "uncertain": 1, "approximate": 0}


def entry_order(eid: str) -> tuple:
    return (eid[0], int(eid[1:]) if eid[1:].isdigit() else 0)


def clash(a: dict, b: dict) -> tuple[int, int, int] | None:
    """(depth, overlap start, overlap end) if two facts put one person in two places at once.

    depth is how far the clash goes: how deep a moment falls inside the other stay, or how long two stays
    overlap. Two moments at the same minute clash with depth 0."""
    a_instant, b_instant = a["from"] == a["to"], b["from"] == b["to"]
    if a_instant and b_instant:
        return (0, a["from"], a["from"]) if a["from"] == b["from"] else None
    if a_instant or b_instant:
        moment, stay = (a, b) if a_instant else (b, a)
        m = moment["from"]
        if stay["from"] + MARGIN < m < stay["to"] - MARGIN:
            return (min(m - stay["from"], stay["to"] - m), m, m)
        return None
    lo, hi = max(a["from"], b["from"]), min(a["to"], b["to"])
    if hi - lo > 2 * MARGIN:
        return (hi - lo, lo, hi)
    return None


def kind_of(a: dict, b: dict, ia: dict, ib: dict, depth: int) -> str:
    if ia["kind"] == "record" or ib["kind"] == "record":
        return "document" if depth > DOCUMENT else "approximate"
    if a["hedged"] or b["hedged"]:
        return "uncertain"
    if ia["source"] == "told" or ib["source"] == "told":
        return "secondhand"
    return "firm" if depth > APPROX else "approximate"


def _span(f: dict) -> dict:
    return {"place": f["place"], "from": f["from"], "to": f["to"]}


def contradictions(facts: list[dict], info: dict[str, dict]) -> list[dict]:
    """Group and classify the clashes between notebook entries.

    facts: [{entry, who, place, from, to, hedged}]; info: {entry: {kind: statement|record, source,
    summary}}. Returns one dict per disagreement: who, kind, the two entries that show it most clearly
    (a, b) with the facts they claim, the overlap, its depth and every entry that takes part."""
    raw = []
    for i, a in enumerate(facts):
        for b in facts[i + 1:]:
            if a["who"] != b["who"] or a["place"] == b["place"] or a["entry"] == b["entry"]:
                continue
            c = clash(a, b)
            if c is None:
                continue
            x, y = (a, b) if entry_order(a["entry"]) <= entry_order(b["entry"]) else (b, a)
            depth, lo, hi = c
            raw.append({"who": a["who"], "places": sorted([x["place"], y["place"]]), "a": x["entry"],
                        "b": y["entry"], "fa": x, "fb": y, "depth": depth, "lo": lo, "hi": hi,
                        "kind": kind_of(x, y, info[x["entry"]], info[y["entry"]], depth)})
    raw.sort(key=lambda r: (r["who"], r["places"], r["lo"], r["hi"], entry_order(r["a"]), entry_order(r["b"])))
    groups: list[dict] = []
    for r in raw:
        home = None
        for g in groups:
            if g["who"] == r["who"] and g["places"] == r["places"] and r["lo"] <= g["hi"] + NEAR \
                    and g["lo"] <= r["hi"] + NEAR:
                home = g
                break
        if home is None:
            groups.append({"who": r["who"], "places": r["places"], "lo": r["lo"], "hi": r["hi"], "pairs": [r]})
        else:
            home["lo"], home["hi"] = min(home["lo"], r["lo"]), max(home["hi"], r["hi"])
            home["pairs"].append(r)
    out = []
    for g in groups:
        def strength(r: dict) -> tuple:
            plain = int(not info[r["a"]]["summary"]) + int(not info[r["b"]]["summary"])
            return (KIND_RANK[r["kind"]], plain, r["depth"])
        best = g["pairs"][0]
        for r in g["pairs"][1:]:
            if strength(r) > strength(best):
                best = r
        entries = sorted({e for r in g["pairs"] for e in (r["a"], r["b"])}, key=entry_order)
        out.append({"who": g["who"], "kind": best["kind"], "a": best["a"], "b": best["b"],
                    "a_fact": _span(best["fa"]), "b_fact": _span(best["fb"]), "overlap": [best["lo"], best["hi"]],
                    "depth": best["depth"], "entries": entries,
                    "pairs": [[r["a"], r["b"], r["kind"]] for r in g["pairs"]]})
    out.sort(key=lambda c: (c["overlap"][0], c["who"], entry_order(c["a"]), entry_order(c["b"])))
    return out
