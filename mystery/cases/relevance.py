"""Evidence relevance: does a piece of information connect to the incident?

Every statement, trace and record line in a case gets one of three verdicts, derived from the
simulation's causal record - never from keywords, odds or hand-written labels:

* ``connected`` - it stems from an event in the incident's causal web: the act, what led to it (the
  pressures and events recorded as its causes), what followed from it (hiding the loot, spending the
  money, the discovery...), and the responsible person's trip to and from the scene.
* ``unrelated`` - it stems from an event outside that web, or, for where-and-when information, it puts
  nobody where and when any part of the incident happened.
* ``uncertain`` - either where-and-when information that does put someone where and when part of the
  incident happened (whether that matters depends on who it was and whether it is true, which a check
  must never reveal), or hearsay that cannot be traced back to anything anyone actually perceived.

Two guarantees hold by construction, and the tests check them on every bundled case:

* **Truth-blind.** A verdict never depends on whether a statement is accurate, mistaken or a lie.
  Event information is judged by the event it stems from: hearsay is traced back to the original
  perception, a misremembered or misidentified sighting by what was really perceived, a lie by what it
  covers. Where-and-when information is judged by what it claims.
* **Identity-blind where it matters.** Presence, sightings, drunkenness and people's own accounts of
  where they were are judged by place and time only, never by who - so checking an alibi or a sighting
  can never single out the culprit.

The verdicts live in the sealed truth (for the laboratory) and, sealed one by one, in the case package,
so the game can open exactly one when the player asks for a check (see mystery/cases/package.py).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:  # pragma: no cover
    from mystery.cases.export import _Builder

VERDICTS = ("connected", "unrelated", "uncertain")
# Information about where someone was (and in what state) rather than about an event.
WHERE_KINDS = {"presence", "sighting", "intoxicated"}
# Witness times are approximate and memories drift; a claim "touches" a moment within this margin.
MARGIN = 45


def web(b: "_Builder") -> list[str]:
    """The incident's causal web: the reveal's chain plus the responsible person's trip to and from
    the scene (the move that brought them there before the act and the one that took them away)."""
    sim, inc = b.sim, b.inc
    ids = list(b.chain)
    core = sim.log.by_id[inc.core_event]
    if inc.responsible:
        before = after = None
        for ev in sim.log.events:
            if ev.kind != "move" or inc.responsible not in ev.actors or ev.time > b.now:
                continue
            path = ev.data.get("path") or []
            if path and path[-1] == core.location and ev.time <= core.time:
                before = ev.id
            if path and path[0] == core.location and ev.time >= core.time and after is None:
                after = ev.id
        ids += [e for e in (before, after) if e and e not in ids]
    return ids


def footprint(b: "_Builder", web_ids: list[str]) -> list[tuple[str, int]]:
    """Where and when each part of the incident happened, including every stop on the trips."""
    out = []
    for eid in web_ids:
        ev = b.sim.log.by_id[eid]
        path, times = ev.data.get("path"), ev.data.get("times")
        if ev.kind == "move" and path and times and len(path) == len(times):
            out += list(zip(path, times))
        else:
            out.append((ev.location, ev.time))
    return out


def _touches(facts: list[tuple[str, int, int]], marks: list[tuple[str, int]]) -> bool:
    for place, start, end in facts:
        for where, t in marks:
            if place == where and start - MARGIN <= t <= end + MARGIN:
                return True
    return False


def _root(sim, belief):
    """Follow hearsay back to whoever first perceived (or worked out) the thing. Passing a belief on in
    conversation records the conversation as its event, so only the end of the trail says what it is
    about."""
    seen = 0
    while belief.source == "told" and belief.via and belief.via in sim.beliefs and seen < 30:
        belief = sim.beliefs[belief.via]
        seen += 1
    return belief


def judge(b: "_Builder", evidence: dict, records: dict) -> dict:
    """{ref: {"verdict", "reason", "source"}} for every statement key, trace id and record line id."""
    sim = b.sim
    web_ids = web(b)
    in_web = set(web_ids)
    marks = footprint(b, web_ids)
    out: dict[str, dict] = {}

    def by_event(ref: str, event: str | None, kind: str) -> None:
        if event is None:
            out[ref] = {"verdict": "uncertain", "reason": "untraced", "source": None, "kind": kind}
        else:
            out[ref] = {"verdict": "connected" if event in in_web else "unrelated",
                        "reason": "web" if event in in_web else "outside", "source": event, "kind": kind}

    for rid, items in b.items.items():
        for it in items:
            ref = it["key"]
            a = b.audit[ref]
            belief = sim.beliefs.get(a["belief"]) if a.get("belief") else None
            claim_kind = belief.claim.kind if belief is not None else ("account" if "segments" in a else "other")
            if "segments" in a or claim_kind in WHERE_KINDS:
                # where-and-when: judged by what it claims, place and time only
                facts = [(f["place"], f["from"], f["to"]) for f in it.get("facts") or []]
                if not facts and it.get("place") and it.get("time") is not None:
                    facts = [(it["place"], it["time"], it["time"])]
                hit = _touches(facts, marks)
                out[ref] = {"verdict": "uncertain" if hit else "unrelated",
                            "reason": "where_when" if hit else "outside", "source": None, "kind": claim_kind}
                continue
            if a.get("about_event"):
                # a statement made up to cover something is judged by what it covers
                by_event(ref, a["about_event"], claim_kind)
                continue
            if belief is None:
                by_event(ref, None, claim_kind)
                continue
            root = _root(sim, belief)
            if root.source == "told" and root.via:
                by_event(ref, None, claim_kind)  # the trail of telling breaks off
                continue
            # the first perception, or a fact the town has always known (an old debt, a grudge), or an
            # account given directly by someone involved: its event is what the statement is about
            event = root.event
            if event is None and root.claim.kind == "suspect":
                target = b._incident_for_claim(root.claim)
                event = target.core_event if target is not None else None
            by_event(ref, event, claim_kind)
    for place, items in evidence.items():
        for e in items:
            by_event(f"T-{e.id}", e.created_by, "trace")
    for book, data in records.items():
        for x in data["entries"]:
            by_event(f"R-{x.id}", x.event_id, "record")
    return out
