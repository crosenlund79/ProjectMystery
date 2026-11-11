"""Scoring a theory and revealing the sealed truth.

This is the only module on the player's side that reads ``truth.json``, and only
after the player has submitted a theory or given up. Revealing is irreversible for
the session: questioning stops once the truth has been seen.
"""

from __future__ import annotations

import json
import os
from typing import TYPE_CHECKING

from mystery.sim.clock import fmt
from mystery.sim.incidents import MECHANISM_LABELS, MOTIVES

if TYPE_CHECKING:
    from mystery.investigate.session import Investigation


def load_truth(case_dir: str) -> dict:
    with open(os.path.join(case_dir, "truth.json"), encoding="utf-8") as f:
        return json.load(f)


def score(truth: dict, theory: dict | None, hint_spend: int) -> dict:
    ans = truth["answer"]
    verdict = truth["suitability"]["verdict"]
    parts: dict[str, int] = {}
    notes: list[str] = []
    if theory is None:
        parts["no theory"] = 0
        notes.append("You gave up without a theory.")
    elif theory["mechanism"] == "unresolved":
        caution = verdict in ("ambiguous", "unsolvable")
        parts["cautious verdict"] = 50 if caution else 15
        notes.append("Calling it unresolved was reasonable: the evidence really was thin." if caution else
                     "There was enough evidence to say more than 'unresolved'.")
    else:
        parts["explanation"] = 40 if theory["mechanism"] == ans["mechanism"] else 0
        right_person = theory["responsible"] == ans["responsible"]
        parts["responsibility"] = 30 if right_person else 0
        if ans["responsible"] is None:
            motive_ok = theory["motive"] in ("none", "unknown")
        else:
            motive_ok = theory["motive"] in ans["motives"]
        parts["motive"] = 10 if motive_ok else 0
        if theory["responsible"] and theory["responsible"] != ans["responsible"]:
            notes.append("You named the wrong person. In a real town that would have consequences.")
    cite_score, cite_notes = _cites(truth, theory)
    parts["evidence cited"] = cite_score
    notes.extend(cite_notes)
    parts["hints"] = -5 * hint_spend
    total = max(0, min(100, sum(parts.values())))
    return {"total": total, "parts": parts, "notes": notes}


def _cites(truth: dict, theory: dict | None) -> tuple[int, list[str]]:
    if not theory or not theory.get("cite_refs"):
        return 0, []
    good, bad = 0, 0
    notes = []
    for ref in theory["cite_refs"]:
        a = truth["testimony_audit"].get(ref) or truth["evidence_audit"].get(ref) or truth["record_audit"].get(ref)
        if a is None:
            continue
        if ref.startswith("K"):
            liar_exposed = a["status"] == "lie" and a["speaker"] == truth["answer"]["responsible"]
            if (a["status"] == "accurate" and a.get("supports")) or liar_exposed:
                good += 1
            elif a["status"] in ("mistaken", "lie"):
                bad += 1
        else:
            chain_ids = {e["id"] for e in truth["chain"]}
            if a.get("created_by") in chain_ids or a.get("event") in chain_ids or \
                    a.get("event_kind") in ("ledger_error", "drink", "repair", "treated"):
                good += 1
    if bad:
        notes.append(f"{bad} of the statements you relied on were mistaken or lies.")
    return min(20, 5 * good) - 3 * bad, notes


def reveal_model(inv: "Investigation") -> dict | None:
    """Score the theory and open the sealed truth. None while the case is still open.

    This is the reveal contract the Godot game reproduces; reveal() only formats it."""
    st = inv.state
    if not st["concluded"]:
        return None
    truth = load_truth(inv.case_dir)
    theory = st.get("theory")
    if theory is not None:
        refs = []
        for eid in theory.get("cites", []):
            e = inv.notebook.get(eid)
            if e and e.get("ref"):
                refs.append(e["ref"])
        theory = {**theory, "cite_refs": refs}
    result = score(truth, theory, st.get("hint_spend", 0))
    st["revealed"] = True
    st["score"] = result
    inv.save()
    names = {rid: p["name"] for rid, p in truth["private_states"].items()}
    ans = truth["answer"]
    model: dict = {
        "narrative": truth["narrative"],
        "answer": {"mechanism": MECHANISM_LABELS.get(ans["mechanism"], ans["mechanism"]),
                   "responsible": names.get(ans["responsible"], "no one"),
                   "outcome": ans["outcome"].replace("_", " "),
                   "motives": [MOTIVES.get(m, m) for m in ans["motives"]]},
        "theory": None,
        "score": {"total": result["total"], "parts": [[k, v] for k, v in result["parts"].items()],
                  "notes": list(result["notes"])},
        "timeline": [], "annotations": [], "plain_true": 0, "missed": [], "assessment": "",
    }
    if theory is not None:
        model["theory"] = {"mechanism": MECHANISM_LABELS.get(theory["mechanism"], theory["mechanism"]),
                           "responsible": names.get(theory["responsible"], "no one"),
                           "motive": MOTIVES.get(theory["motive"], theory["motive"])}
    seen = set()
    for ev in sorted(truth["chain"] + truth["responsible_movements"], key=lambda e: (e["time"], e["id"])):
        if ev["id"] in seen or ev["kind"] in ("meal",):
            continue
        seen.add(ev["id"])
        model["timeline"].append({"time": ev["time"], "label": fmt(ev["time"]), "summary": ev["summary"]})
    cited = set((theory or {}).get("cites", []))
    for e in inv.notebook.entries():
        ref = e.get("ref")
        verdict = ""
        if (ref in truth["testimony_audit"] and truth["testimony_audit"][ref]["status"] in ("accurate", "unverifiable")
                and e["id"] not in cited and not truth["testimony_audit"][ref].get("supports")):
            model["plain_true"] += 1
            continue
        if ref and ref in truth["testimony_audit"]:
            a = truth["testimony_audit"][ref]
            if a["status"] == "lie":
                verdict = f"LIE — {a.get('error') or 'deliberately false'}"
                if a.get("true_text"):
                    verdict += f". Really: {a['true_text']}"
            elif a["status"] == "mistaken":
                verdict = f"MISTAKEN — {(a.get('error') or 'wrong').replace('_', ' ')}"
            elif a["status"] == "unverifiable":
                verdict = "true as far as it goes (they couldn't tell who)"
            else:
                verdict = "true"
        elif ref and ref in truth["evidence_audit"]:
            verdict = f"left by: {truth['evidence_audit'][ref]['event_summary']}"
        elif ref and ref in truth["record_audit"]:
            verdict = f"records: {truth['record_audit'][ref]['event_summary']}"
        if verdict:
            model["annotations"].append({"entry": e["id"], "text": e["text"], "verdict": verdict,
                                         "cited": e["id"] in cited})
    found = {e.get("ref") for e in inv.notebook.entries()}
    for ch in truth["suitability"]["channels"]:
        if ch["strength"] in ("strong", "hearsay") and not any(k in found for k in ch["keys"]):
            src = names.get(ch["source"]) or truth.get("place_names", {}).get(ch["source"], ch["source"])
            model["missed"].append({"type": ch["type"], "source": src,
                                    "needs_pressing": bool(ch.get("needs_pressing"))})
    s = truth["suitability"]
    model["assessment"] = (f"{s['verdict']} — {s['independent_channels']} independent channel(s), "
                           f"{s['red_herrings']} source(s) of misleading information, "
                           f"{s['lies_by_responsible']} lie(s) by the person responsible.")
    return model


def reveal(inv: "Investigation") -> list[str]:
    model = reveal_model(inv)
    if model is None:
        return ["The truth stays sealed until you submit a theory ('submit') or give up ('giveup')."]
    ans = model["answer"]
    out = ["", "=" * 70, "THE TRUTH", "=" * 70, model["narrative"], ""]
    out.append(f"Explanation: {ans['mechanism']}")
    out.append(f"Responsible: {ans['responsible']}")
    out.append(f"Outcome: {ans['outcome']}; motive: " + ", ".join(ans["motives"]))
    if model["theory"] is not None:
        th = model["theory"]
        out.append("")
        out.append(f"Your theory: {th['mechanism']}; responsible: {th['responsible']}; motive: {th['motive']}")
    out.append("")
    sc = model["score"]
    out.append(f"SCORE: {sc['total']}/100  " + ", ".join(f"{k} {v:+d}" for k, v in sc["parts"]))
    for n in sc["notes"]:
        out.append(f"  - {n}")
    out += ["", "WHAT ACTUALLY HAPPENED"]
    out += [f"  {ev['label']}  {ev['summary']}" for ev in model["timeline"]]
    out += ["", "YOUR NOTEBOOK, CHECKED AGAINST THE TRUTH"]
    for a in model["annotations"]:
        star = " (cited)" if a["cited"] else ""
        out.append(f"  [{a['entry']}]{star} {a['text']}")
        out.append(f"        -> {a['verdict']}")
    if model["plain_true"]:
        out.append(f"  ...and {model['plain_true']} other statement(s) you collected were true but beside the point.")
    if model["missed"]:
        out += ["", "LEADS YOU DID NOT FOLLOW"]
        out += [f"  - {m['type']} ({m['source']}){' — needed pressing' if m['needs_pressing'] else ''}"
                for m in model["missed"]]
    out += ["", f"Case assessment: {model['assessment']}"]
    return out
