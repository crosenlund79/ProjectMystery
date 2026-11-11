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


def reveal(inv: "Investigation") -> list[str]:
    st = inv.state
    if not st["concluded"]:
        return ["The truth stays sealed until you submit a theory ('submit') or give up ('giveup')."]
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
    out = ["", "=" * 70, "THE TRUTH", "=" * 70, truth["narrative"], ""]
    out.append(f"Explanation: {MECHANISM_LABELS.get(ans['mechanism'], ans['mechanism'])}")
    out.append(f"Responsible: {names.get(ans['responsible'], 'no one')}")
    out.append(f"Outcome: {ans['outcome'].replace('_', ' ')}; motive: "
               + ", ".join(MOTIVES.get(m, m) for m in ans["motives"]))
    if theory is not None:
        out.append("")
        out.append(f"Your theory: {MECHANISM_LABELS.get(theory['mechanism'], theory['mechanism'])}; "
                   f"responsible: {names.get(theory['responsible'], 'no one')}; "
                   f"motive: {MOTIVES.get(theory['motive'], theory['motive'])}")
    out.append("")
    out.append(f"SCORE: {result['total']}/100  " + ", ".join(f"{k} {v:+d}" for k, v in result["parts"].items()))
    for n in result["notes"]:
        out.append(f"  - {n}")
    out += ["", "WHAT ACTUALLY HAPPENED"]
    seen = set()
    timeline = sorted(truth["chain"] + truth["responsible_movements"], key=lambda e: (e["time"], e["id"]))
    for ev in timeline:
        if ev["id"] in seen or ev["kind"] in ("meal",):
            continue
        seen.add(ev["id"])
        out.append(f"  {fmt(ev['time'])}  {ev['summary']}")
    out += ["", "YOUR NOTEBOOK, CHECKED AGAINST THE TRUTH"]
    cited = set((theory or {}).get("cites", []))
    plain_true = 0
    for e in inv.notebook.entries():
        ref = e.get("ref")
        verdict = ""
        if (ref in truth["testimony_audit"] and truth["testimony_audit"][ref]["status"] in ("accurate", "unverifiable")
                and e["id"] not in cited and not truth["testimony_audit"][ref].get("supports")):
            plain_true += 1
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
            a = truth["evidence_audit"][ref]
            verdict = f"left by: {a['event_summary']}"
        elif ref and ref in truth["record_audit"]:
            verdict = f"records: {truth['record_audit'][ref]['event_summary']}"
        if verdict:
            star = " (cited)" if e["id"] in cited else ""
            out.append(f"  [{e['id']}]{star} {e['text']}")
            out.append(f"        -> {verdict}")
    if plain_true:
        out.append(f"  ...and {plain_true} other statement(s) you collected were true but beside the point.")
    found = {e.get("ref") for e in inv.notebook.entries()}
    missed = []
    for ch in truth["suitability"]["channels"]:
        if ch["strength"] in ("strong", "hearsay") and not any(k in found for k in ch["keys"]):
            src = names.get(ch["source"]) or truth.get("place_names", {}).get(ch["source"], ch["source"])
            missed.append(f"  - {ch['type']} ({src}){' — needed pressing' if ch.get('needs_pressing') else ''}")
    if missed:
        out += ["", "LEADS YOU DID NOT FOLLOW"] + missed
    s = truth["suitability"]
    out += ["", f"Case assessment: {s['verdict']} — {s['independent_channels']} independent channel(s), "
                f"{s['red_herrings']} source(s) of misleading information, "
                f"{s['lies_by_responsible']} lie(s) by the person responsible."]
    return out
