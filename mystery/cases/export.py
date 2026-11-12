"""Freeze a case at the moment the investigator arrives.

Two views are produced from the same instant of the same history:

* ``truth.json``         developer-only: the incident, its causal chain, the event
                         log, every resident's private state and an audit of every
                         statement (accurate, mistaken and why, or a lie and why).
* ``investigation.json`` player-safe: the hook, people, places, what each resident is
                         willing to say (rendered text only), discoverable traces
                         and records, and grounded hints. No event ids, no intents,
                         no accuracy flags, no causal links.
"""

from __future__ import annotations

import copy
import json
import os
from typing import TYPE_CHECKING

from mystery import CASE_SCHEMA, CONFIG_VERSION, SIM_VERSION
from mystery.cases import relevance
from mystery.cases import suitability as suit
from mystery.cases.testimony import (concise_segments, describe_concise, describe_segments, drinks_before,
                                     render, segments, summary_text)
from mystery.rng import stream
from mystery.sim.actions import anchors_for
from mystery.sim.clock import DAY, fmt, fmt_span
from mystery.sim.incidents import HOOK_MECHANISMS, MECHANISM_LABELS, MOTIVES, Incident
from mystery.sim.memory import Claim, recall

if TYPE_CHECKING:
    from mystery.sim.engine import Simulation

SCENE_KINDS = {"presence", "sighting", "noise", "intoxicated", "saw_collision", "argument", "assault"}
# How far before the time in question people's first answers reach ("the evening before"). Anything that
# happened before that is still remembered and still told, but only when the investigator asks about
# earlier times: the item is marked era "earlier".
LEAD_IN = 13 * 60
# Everyday sightings at the same place are told as one session while the gaps between them stay below this.
SESSION_GAP = 2 * 60
PLAYER_ROLE = ("You grew up here and came back last week after months away, so you were not part of anything "
               "that happened. People know you and will talk to you, but you have no official power: you can ask, "
               "look around public places, and look at private places or books only if their owners agree.")


def case_id_for(sim: "Simulation", inc: Incident) -> str:
    return f"{sim.config.seed}-{sim.config.profile}-{sim.config.days}d-r{sim.config.residents}-{inc.id}"


# =================================================================== building
def build_case(sim: "Simulation", inc: Incident) -> dict:
    now = inc.case_start
    assert now is not None and inc.window is not None
    builder = _Builder(sim, inc, now)
    return builder.build()


class _Builder:
    def __init__(self, sim: "Simulation", inc: Incident, now: int):
        self.sim, self.inc, self.now = sim, inc, now
        self.case_id = case_id_for(sim, inc)
        w0, w1 = inc.window
        self.window = [w0, w1]
        self.focus = [max(w0 - 120, now - 2 * DAY), min(max(w1, w0 + 60), now)]
        self.recent_from = min(w0, self.focus[0]) - LEAD_IN
        self.items: dict[str, list[dict]] = {}
        self.meta: dict[str, dict] = {}  # key -> the claim behind a statement (build-time only, never exported)
        self.audit: dict[str, dict] = {}
        self.evasive: dict[str, list[str]] = {}
        self._n = 0
        self.chain = self._chain()
        self.R = inc.responsible
        self.R_vehicle_households = {}
        for vid, v in sim.world.vehicles.items():
            self.R_vehicle_households[vid] = v.household

    # ------------------------------------------------------------ helpers
    def _chain(self) -> list[str]:
        log = self.sim.log
        core = self.inc.core_event
        ids = log.ancestors(core) + [core] + list(self.inc.related_events) + log.consequences(core, self.now)
        if self.inc.discovery_event:
            ids.append(self.inc.discovery_event)
        out = []
        for eid in ids:
            if eid in log.by_id and eid not in out and log.by_id[eid].time <= self.now:
                out.append(eid)
        out.sort(key=lambda e: (log.by_id[e].time, e))
        return out

    def key(self) -> str:
        self._n += 1
        return f"K{self._n:04d}"

    def add(self, speaker: str, text: str, topics: list[str], source: str, time: int | None, place: str | None,
            about: list[str], guarded: bool, audit: dict, group: dict | None = None,
            facts: list[dict] | None = None, claim: Claim | None = None) -> dict:
        for existing in self.items.get(speaker, []):
            if existing["text"] == text and existing["guarded"] == guarded:
                existing["topics"] = sorted(set(existing["topics"]) | set(topics))
                return existing
        k = self.key()
        item = {"key": k, "text": text, "topics": sorted(set(topics)), "source": source, "time": time,
                "place": place, "about": sorted({a for a in about if a}), "guarded": guarded,
                "facts": facts or []}
        if group:
            item["group"] = group
        end = claim.end if claim is not None and claim.end is not None else time
        if end is not None and end < self.recent_from:
            item["era"] = "earlier"
        self.items.setdefault(speaker, []).append(item)
        self.audit[k] = {"speaker": speaker, "source": source, **audit}
        if claim is not None:
            self.meta[k] = {"claim": claim, "source": source}
        return item

    def in_focus(self, t: int | None, pad: int = 6 * 60) -> bool:
        return t is not None and self.focus[0] - pad <= t <= self.now

    def near_scene(self, c: Claim) -> bool:
        if c.start is None or c.location is None:
            return False
        end = c.end if c.end is not None else c.start
        return (end >= self.inc.time - 90 and c.start <= self.inc.time + 90
                and self.sim.world.hops(c.location, self.inc.location) <= 1)

    def vehicle_of(self, rid: str | None) -> str | None:
        return self.sim.residents[rid].vehicle if rid in self.sim.residents else None

    # ------------------------------------------------------------ main
    def build(self) -> dict:
        sim = self.sim
        for rid in sim.ids:
            if sim.residents[rid].alive:
                self._resident(rid)
                self._summarize(rid)
        consent = self._consent()
        evidence = self._evidence(consent)
        records = self._records(consent)
        vehicles = self._vehicles(consent)
        report = suit.evaluate(self, consent, evidence, records)
        hints = suit.hints(self, report)
        investigation = self._investigation(consent, evidence, records, vehicles, hints)
        truth = self._truth(report, evidence, records)
        truth["relevance"] = relevance.judge(self, evidence, records)
        truth["relevance_web"] = relevance.web(self)
        truth["relevance_footprint"] = [list(m) for m in relevance.footprint(self, truth["relevance_web"])]
        return {"case_id": self.case_id, "investigation": investigation, "truth": truth, "suitability": report}

    # ------------------------------------------------------------ testimony
    def _resident(self, rid: str) -> None:
        sim, inc, now = self.sim, self.inc, self.now
        r = sim.residents[rid]
        anchors = [(a, e) for (a, e, _loc) in anchors_for(sim, rid, now)] + [tuple(self.window)]
        concealing = self.R == rid and not inc.reported_openly
        witnessed_core = any(sim.perceived.get((x, inc.core_event)) == "saw" for x in sim.ids if x != rid)
        self._whereabouts(rid, concealing and not witnessed_core)
        for b in sim.memory[rid].beliefs:
            if b.acquired > now:
                continue
            keep, conf = recall(b, now, anchors)
            if not keep:
                continue
            c = b.claim
            if not self._relevant(b, c):
                continue
            claim, err = self._recalled(b, c)
            disclosure, reason = self._disclosure(r, b, claim, conf)
            topics = self._topics(rid, b, claim)
            status, error = self._status(b, claim, err)
            lie = False
            if b.source == "self" and claim.kind == "assault" and claim.subject == rid:
                if concealing and not witnessed_core:
                    disclosure, reason = "withheld", "self-protection"
                else:
                    status, lie, error = "lie", True, "claims the other person started it"
            if (concealing and not witnessed_core and claim.kind == "argument" and rid in (claim.subject, claim.other)
                    and claim.start is not None and abs(claim.start - inc.time) <= 3 * 60):
                disclosure, reason = "withheld", "self-protection"
            audit = {"belief": b.id, "status": status, "error": error, "disclosure": disclosure,
                     "withheld_reason": reason, "supports": self._supports(b, claim, status),
                     "event": b.event, "lie": lie, "root": self._root(b)}
            if disclosure == "withheld":
                for tp in topics:
                    self.evasive.setdefault(rid, [])
                    if tp not in self.evasive[rid]:
                        self.evasive[rid].append(tp)
                self.audit[f"W-{b.id}"] = {"speaker": rid, "source": b.source, **audit,
                                           "text": render(sim, rid, b, claim)}
                continue
            self.add(rid, render(sim, rid, b, claim), topics, b.source, claim.start, claim.location,
                     [claim.subject, claim.other], disclosure == "guarded", audit, _group(sim, b, claim),
                     _facts(claim), claim=claim)
        if concealing and inc.family == "collision":
            veh = r.vehicle
            if veh:
                self.add(rid, f"{sim.world.vehicles[veh].name[0].upper()}{sim.world.vehicles[veh].name[1:]}? "
                         "I hit a deer out on the ridge road a few nights back. Gave me a fright.",
                         ["vehicles", f"person:{rid}"], "self", None, None, [rid], False,
                         {"belief": None, "status": "lie", "error": "invented a deer to explain the damage",
                          "disclosure": "open", "withheld_reason": None, "supports": [], "event": None, "lie": True,
                          "about_event": inc.core_event})

    # ------------------------------------------------------------ summaries
    def _summarize(self, rid: str) -> None:
        """Everyday information is told the way people tell it: 'I saw Ana, Ben and Cat at the pub that
        evening', 'from what I hear, half the town owes the grocer', 'plenty of people owe me'. Each summary
        is a statement of its own (one notebook entry); the statements it stands for stay in the package as
        its members, word for word, and are told when the investigator asks for more or asks about one of
        the people. Only open, everyday information is summarized: nothing guarded, no sighting in the dark
        or of someone the speaker could not make out, no lie, nothing about the speaker's own whereabouts."""
        sim = self.sim
        groups: dict[tuple, list[dict]] = {}
        for it in self.items.get(rid, []):
            m = self.meta.get(it["key"])
            if m is None or it["guarded"] or self.audit[it["key"]].get("lie"):
                continue
            if not [tp for tp in it["topics"] if not tp.startswith("person:") and tp != "other"]:
                continue  # told only when asked about someone in particular, one at a time already
            c, src, era = m["claim"], m["source"], it.get("era", "recent")
            party = (c.subject, c.other)
            key: tuple | None = None
            everyday = c.kind in ("presence", "intoxicated") or (
                # someone recognised in daylight walking through town; vehicles, the dark, anyone unsteady on
                # their feet and housemates' comings and goings are told one by one
                c.kind == "sighting" and c.obj is None and c.detail.startswith("heading toward")
                and "unsteady" not in c.detail and sim.world.locations[c.location].outdoor)
            if everyday and src == "saw" and c.subject and c.subject != rid and not c.hedged and c.location \
                    and c.start is not None:
                sig = tuple(sorted(tp for tp in it["topics"] if not tp.startswith("person:")))
                key = ("seen", era, sig, c.location)
            elif c.kind == "debt" and c.subject and c.other and rid not in party and src in ("told", "saw"):
                key = ("repaid" if c.detail == "repaid" else "owing", era, (), c.other)
            elif c.kind == "debt" and src == "self" and c.other == rid and c.subject:
                key = ("repaid_me" if c.detail == "repaid" else "owed_me", era, (), rid)
            elif c.kind == "refusal" and c.subject and c.other and rid not in party and src in ("told", "saw"):
                key = ("refused", era, (), c.other)
            elif c.kind == "suspect" and src == "told" and c.subject and c.detail:
                key = ("suspected", era, (), c.detail)  # who the town is pointing at, over one matter
            elif c.kind == "refusal" and src == "self" and c.other == rid and c.subject:
                key = ("i_asked", era, (), rid)  # the people who turned the speaker down
            elif src == "self" and c.subject and ((c.kind == "refusal" and c.subject == rid and c.other)
                                                  or (c.kind == "hardship" and c.subject != rid)):
                key = ("asked_me", era, (), rid)
            if key is not None:
                groups.setdefault(key, []).append(it)
        for key, members in groups.items():
            if key[0] != "seen":
                if len(members) >= 2:
                    self._add_summary(rid, key, members)
                continue
            members = sorted(members, key=lambda it: (it["time"], it["key"]))
            session: list[dict] = []
            last_end = None
            for it in members + [None]:
                c = self.meta[it["key"]]["claim"] if it is not None else None
                if it is None or (last_end is not None and c.start - last_end > SESSION_GAP):
                    if len(session) >= 2:
                        self._add_summary(rid, key, session)
                    session = []
                    last_end = None
                if it is not None:
                    session.append(it)
                    end = c.end if c.end is not None else c.start
                    last_end = end if last_end is None else max(last_end, end)

    def _add_summary(self, rid: str, key: tuple, members: list[dict]) -> None:
        sim = self.sim
        kind, era = key[0], key[1]
        claims = [self.meta[it["key"]]["claim"] for it in members]
        sources = {self.meta[it["key"]]["source"] for it in members}
        source = "told" if sources == {"told"} else ("self" if sources == {"self"} else "saw")
        voice = sources.pop() if len(sources) == 1 else "mixed"
        sig = tuple(sorted({tp for it in members for tp in it["topics"] if not tp.startswith("person:")}))
        if kind in ("owing", "repaid", "refused"):
            # the person everything here is about (the creditor, the one asking for money): asked about
            # them, this is told in summary too; asked about anyone else in it, their own lines are told
            sig = tuple(sorted(sig + (f"person:{key[3]}",)))

        def firsts(ids) -> list[str]:
            return sorted({sim.residents[x].first for x in ids if x})
        place = None
        late = firsts(c.subject for c in claims if c.kind == "debt" and c.detail == "overdue")
        if kind == "seen":
            place = key[3]
            start = min(c.start for c in claims)
            end = max(c.end if c.end is not None else c.start for c in claims)
            text = summary_text("seen", voice, firsts(c.subject for c in claims), place=sim.world.name(place),
                                span=fmt_span(start, end),
                                also=firsts(c.subject for c in claims if c.kind == "intoxicated"))
        elif kind == "asked_me":
            text = summary_text("asked_me", voice, firsts(c.other if c.kind == "refusal" else c.subject
                                                          for c in claims),
                                also=firsts(c.other for c in claims if c.kind == "refusal"), era=era)
        elif kind == "i_asked":
            text = summary_text("i_asked", voice, firsts(c.subject for c in claims), era=era)
        elif kind in ("owed_me", "repaid_me"):
            text = summary_text(kind, voice, firsts(c.subject for c in claims), also=late, era=era)
        elif kind == "suspected":
            text = summary_text("suspected", voice, firsts(c.subject for c in claims), party=key[3])
        elif kind == "refused":
            text = summary_text("refused", voice, firsts(c.subject for c in claims),
                                party=sim.residents[key[3]].first, era=era)
        else:
            text = summary_text(kind, voice, firsts(c.subject for c in claims), party=sim.residents[key[3]].first,
                                also=late, era=era)
        times = [it["time"] for it in members if it["time"] is not None]
        facts: list[dict] = []
        for it in members:
            for f in it["facts"]:
                if f not in facts:
                    facts.append(f)
        k = self.key()
        item = {"key": k, "text": text, "topics": list(sig), "source": source,
                "time": min(times) if times else None, "place": place,
                "about": sorted({a for it in members for a in it["about"]} - {rid}), "guarded": False,
                "facts": facts, "members": [it["key"] for it in members]}
        if era == "earlier":
            item["era"] = "earlier"
        for it in members:
            it["in"] = k
        self.items[rid].append(item)
        audits = [self.audit[it["key"]] for it in members]
        statuses = [a["status"] for a in audits]
        error = None
        if "mistaken" in statuses:
            status = "mistaken"
            error = "partly wrong: " + next(a.get("error") or "wrong" for a in audits if a["status"] == "mistaken")
        elif all(st == "unverifiable" for st in statuses):
            status = "unverifiable"
        else:
            status = "accurate"
        supports = sorted({sp for a in audits if a["status"] == "accurate" for sp in a.get("supports", [])})
        self.audit[k] = {"speaker": rid, "source": source, "belief": None, "status": status, "error": error,
                         "disclosure": "open", "withheld_reason": None, "supports": supports, "event": None,
                         "lie": False, "root": rid, "summary": True, "members": item["members"]}

    def _root(self, b) -> str:
        """Who originally perceived this? Hearsay is only as independent as its source."""
        seen = 0
        while b.source == "told" and b.via and b.via in self.sim.beliefs and seen < 20:
            b = self.sim.beliefs[b.via]
            seen += 1
        return b.holder

    def _relevant(self, b, c: Claim) -> bool:
        k = c.kind
        if k in ("theft_self", "stash"):
            return True  # always withheld, but audited
        if k in SCENE_KINDS or k == "purchase":
            return self.in_focus(c.start)
        if k in ("debt", "grudge", "laid_off"):
            return k != "debt" or c.detail != "repaid" or self.now - b.acquired <= 7 * DAY
        return self.now - b.acquired <= 7 * DAY

    def _recalled(self, b, c: Claim) -> tuple[Claim, str | None]:
        claim = copy.copy(c)
        if (self.now - b.acquired > 20 * 60 and b.salience < 0.9 and c.start is not None
                and c.kind in ("presence", "sighting", "noise", "intoxicated")):
            rng = stream(self.sim.config.seed, "recall", self.case_id, b.id)
            if rng.random() < 0.3:
                shift = rng.choice([-60, -45, -30, 30, 45, 60])
                claim.start += shift
                if claim.end is not None:
                    claim.end += shift
                return claim, "misremembered_time"
        return claim, None

    def _incriminates_self(self, r, b, c: Claim) -> bool:
        sim = self.sim
        if c.kind in ("theft_self", "stash"):
            return True
        if c.kind == "collision_self":
            inc = sim.incident_for(b.event) if b.event else None
            return inc is None or not inc.reported_openly
        guilty_times = [sim.log.by_id[g].time for g in r.guilty_of if sim.log.by_id[g].time <= self.now]
        if not guilty_times:
            return False
        if c.kind == "vehicle_damage" and c.obj and c.obj == r.vehicle:
            return True
        if c.subject == r.id and c.kind in ("presence", "sighting", "intoxicated", "saw_collision", "suspect",
                                            "repair"):
            return c.kind == "suspect" or any(c.start is not None and abs(c.start - gt) <= 3 * 60
                                              for gt in guilty_times)
        return False

    def _disclosure(self, r, b, c: Claim, conf: float) -> tuple[str, str | None]:
        sim = self.sim
        if self._incriminates_self(r, b, c):
            return "withheld", "self-protection"
        protected = c.subject if c.subject and c.subject != r.id else None
        if c.obj in sim.world.vehicles:
            hh = sim.world.vehicles[c.obj].household
            if hh != r.household:
                protected = protected or sim.households[hh][0]
            elif c.kind == "vehicle_damage":
                protected = protected or r.id
        if protected and protected != r.id and r.r(protected).affection >= 0.75 and c.kind in (
                "presence", "sighting", "intoxicated", "vehicle_damage", "suspect", "assault", "saw_collision"):
            if c.kind in ("presence", "intoxicated") and not self.in_focus(c.start, 0):
                pass
            elif r.traits.honesty >= 0.55:
                return "guarded", "loyalty"
            else:
                return "withheld", "loyalty"
        if conf < 0.45:
            return "guarded", "unsure"
        return "open", None

    def _topics(self, speaker: str, b, c: Claim) -> list[str]:
        k = c.kind
        topics = []
        for p in (c.subject, c.other):
            if p and p != speaker:
                topics.append(f"person:{p}")
        if c.obj in self.sim.world.vehicles:
            for m in self.sim.households[self.sim.world.vehicles[c.obj].household]:
                if m != speaker:
                    topics.append(f"person:{m}")
        if k in SCENE_KINDS and c.start is not None:
            end = c.end if c.end is not None else c.start
            if end >= self.window[0] - 120 and c.start <= self.window[1] + 60:
                topics.append("window")
        if k in ("debt", "hardship", "refusal", "loan", "rent_missed", "help", "laid_off"):
            topics.append("money")
        if k in ("argument", "assault", "grudge", "reconcile", "confession"):
            topics.append("conflicts")
        if k in ("loss", "damage", "injury", "struck", "death", "fall", "suspect", "confession", "collision_self"):
            topics.append("incident" if self._about_this_case(c) else "past")
        if k in ("vehicle_damage", "saw_collision", "repair", "collision_self") or (k == "sighting" and c.obj):
            topics.append("vehicles")
        if c.location == self.inc.location and k in SCENE_KINDS and "window" in topics:
            topics.append("incident")
        if b.source == "told":
            topics.append("rumors")
        if k == "purchase":
            topics.append("whereabouts")
        if not topics:
            topics.append("other")
        return topics

    def _about_this_case(self, c: Claim) -> bool:
        if c.start is None:
            return False
        end = c.end if c.end is not None else c.start
        if c.kind in ("injury", "death", "struck", "fall") and c.subject in self.inc.victims + [None]:
            return end >= self.window[0] - 13 * 60
        near = c.location is None or self.sim.world.hops(c.location, self.inc.location) <= 1
        return near and end >= self.window[0] - 13 * 60 and c.start <= self.window[1] + 6 * 60

    def _status(self, b, c: Claim, err: str | None) -> tuple[str, str | None]:
        sim = self.sim
        if c.kind == "suspect":
            target = self._incident_for_claim(c)
            if target is None:
                return "unverifiable", None
            return ("accurate", None) if target.responsible == c.subject else ("mistaken", "wrong suspect")
        if c.kind in ("presence", "sighting") and c.subject is None:
            return "unverifiable", None
        error = err or b.error
        if c.kind in ("presence", "sighting") and c.subject:
            end = c.end if c.end is not None else c.start
            ok = any(sim.where(c.subject, m) == c.location for m in range(c.start - 20, end + 21, 10)) \
                if c.start is not None else True
            if not ok:
                return "mistaken", error or "wrong person or time"
            if error == "misremembered_time":
                return "accurate", None  # still placed correctly within tolerance
        if error:
            return "mistaken", error
        return "accurate", None

    def _incident_for_claim(self, c: Claim) -> Incident | None:
        for inc in self.sim.incidents:
            if inc.location == c.location and c.start is not None and inc.time <= self.now:
                end = c.end if c.end is not None else c.start
                if c.start - 13 * 60 <= inc.time <= end + 6 * 60:
                    return inc
        return None

    def _supports(self, b, c: Claim, status: str) -> list[str]:
        out = []
        R, inc = self.R, self.inc
        veh_R = self.vehicle_of(R)
        if R and status == "accurate":
            names_R = c.subject == R or (c.obj is not None and c.obj == veh_R)
            if names_R and c.kind in SCENE_KINDS and self.near_scene(c):
                out.append("places_responsible")
            if names_R and b.event == inc.core_event and b.source == "saw":
                out.append("act")
            if names_R and c.kind in ("vehicle_damage", "repair") and inc.family == "collision":
                out.append("vehicle")
            if c.subject == R and c.kind in ("debt", "hardship", "refusal", "rent_missed", "grudge"):
                out.append("motive")
            if c.kind == "suspect" and c.subject == R:
                out.append("suspicion_correct")
            if (c.subject == R and c.kind == "debt" and c.detail == "repaid" and c.start is not None
                    and inc.family == "theft" and inc.time <= c.start <= inc.time + 3 * DAY):
                out.append("sudden_money")
            if c.subject == R and c.kind == "noise" and self.near_scene(c):
                out.append("places_responsible")
            home_R = self.sim.residents[R].home
            if (c.subject == R and c.location == home_R and c.kind in ("noise", "sighting") and c.start is not None
                    and ("going out" in c.detail or "coming in" in c.detail or c.detail in ("heading out",
                                                                                           "coming home"))
                    and abs(c.start - inc.time) <= 90):
                out.append("absence")
            if c.kind == "intoxicated" and c.subject == R and inc.family == "collision" and self.near_scene(c):
                out.append("places_responsible")
        if status != "accurate" and c.subject and c.subject != R and c.start is not None:
            if c.kind in SCENE_KINDS and self.near_scene(c):
                out.append("misleading")
        if c.kind == "suspect" and c.subject and c.subject != R:
            out.append("misleading")
        fam = inc.family
        if fam == "accounting_error" and c.kind == "purchase" and status == "accurate":
            dup_sales = {self.sim.log.by_id[e].causes[0] for e in [inc.core_event] + inc.related_events
                         if e in self.sim.log.by_id and self.sim.log.by_id[e].kind == "ledger_error"}
            if b.event in dup_sales:
                out.append("mechanism")
        if fam == "fall" and status == "accurate":
            if c.kind == "fall" or (c.kind in ("intoxicated", "sighting") and c.subject in inc.victims
                                    and self.near_scene(c)):
                out.append("mechanism")
        if fam == "collision" and status == "accurate" and c.kind in ("struck", "noise", "saw_collision") \
                and c.location == "road" and self.near_scene(c):
            out.append("mechanism")
        if fam == "assault" and status == "accurate" and c.kind == "assault" and b.event == inc.core_event:
            out.append("mechanism")
        return out

    def _whereabouts(self, rid: str, lie: bool) -> None:
        sim = self.sim
        a, b = self.focus
        if b - a < 60:
            return
        segs = segments(sim, rid, a, b)
        if not segs:
            return
        hazy = None
        for loc, s, e in segs:
            if drinks_before(sim, rid, e) >= 4 and loc != sim.residents[rid].home:
                hazy = e
                break
        # Two tellings of the same account: the plain answer (where they spent their time) and, when asked
        # to be exact, every move with its times. The exact one is filed behind the plain one.
        keep = {self.inc.hook_place} if self.inc.hook_place in sim.world.locations else set()
        truth_text = describe_segments(sim, rid, segs, hazy)
        short = concise_segments(sim, segs, keep)
        short_text = describe_concise(sim, rid, short, hazy)
        if not lie:
            def audit(sg: list[list]) -> dict:
                return {"belief": None, "status": "accurate", "error": None, "disclosure": "open",
                        "withheld_reason": None, "supports": self._self_supports(rid, sg), "event": None,
                        "lie": False, "segments": sg}
            plain = self.add(rid, short_text, ["whereabouts"], "self", a, None, [rid], False, audit(short),
                             facts=_segment_facts(rid, short))
            exact = self.add(rid, truth_text, ["whereabouts"], "self", a, None, [rid], False, audit(segs),
                             facts=_segment_facts(rid, segs))
            self._file_behind(rid, plain, exact)
            return
        ct = self.inc.time
        home = sim.residents[rid].home
        fake: list[list] = []
        for loc, s, e in segs:
            overlaps = s < ct + 45 and e > ct - 45 and loc != home
            if fake and (fake[-1][0] == loc or overlaps):
                fake[-1][2] = e
            else:
                fake.append([loc, s, e])
        merged: list[list] = []
        for seg in fake:
            if merged and merged[-1][0] == seg[0]:
                merged[-1][2] = seg[2]
            else:
                merged.append(list(seg))
        fake_short = concise_segments(sim, merged, keep)

        def lie_audit(sg: list[list], true_sg: list[list], true_text: str) -> dict:
            return {"belief": None, "status": "lie", "error": "hid where they really were", "disclosure": "open",
                    "withheld_reason": None, "supports": ["responsible_lie"], "event": None, "lie": True,
                    "segments": sg, "true_segments": true_sg, "true_text": true_text}
        plain = self.add(rid, describe_concise(sim, rid, fake_short, None), ["whereabouts"], "self", a, None, [rid],
                         False, lie_audit(fake_short, short, short_text), facts=_segment_facts(rid, fake_short))
        exact = self.add(rid, describe_segments(sim, rid, merged, None), ["whereabouts"], "self", a, None, [rid],
                         False, lie_audit(merged, segs, truth_text), facts=_segment_facts(rid, merged))
        self._file_behind(rid, plain, exact)

    def _file_behind(self, rid: str, plain: dict, exact: dict) -> None:
        """The exact account is told when asked for more; the plain one stands in front of it."""
        if plain is exact:
            return
        plain["members"] = [exact["key"]]
        exact["in"] = plain["key"]
        self.audit[exact["key"]]["exact_of"] = plain["key"]  # the same account told in full: counted once

    def _self_supports(self, rid: str, segs: list[list]) -> list[str]:
        out = []
        if rid in self.inc.victims and self.inc.family == "fall":
            out.append("mechanism")
        return out

    # ------------------------------------------------------------ access
    def _consent(self) -> dict:
        sim, now = self.sim, self.now
        out = {}
        for loc_id, loc in sim.world.locations.items():
            if loc.kind in ("square", "road"):
                out[loc_id] = {"allowed": True, "by": None, "reply": "It's a public place."}
                continue
            owners = [o for o in loc.owners if sim.residents[o].alive]
            if not owners:
                out[loc_id] = {"allowed": True, "by": None, "reply": "Nobody objects."}
                continue
            parked = [v.id for v in sim.world.vehicles.values() if v.location == loc_id]
            traces = sim.world.evidence_at(loc_id, now) + [e for vid in parked for e in sim.world.evidence_at(vid, now)]
            hiding = [o for o in owners if any(sim.made_by(o, e) for e in traces)]
            private = all(sim.residents[o].traits.sociability < 0.3 for o in owners)
            speaker = hiding[0] if hiding else owners[0]
            if hiding:
                out[loc_id] = {"allowed": False, "by": speaker,
                               "reply": f"{sim.residents[speaker].first}: \"No. I don't see why you'd need to.\""}
            elif private and loc.kind == "home":
                out[loc_id] = {"allowed": False, "by": speaker,
                               "reply": f"{sim.residents[speaker].first}: \"I'd rather you didn't. We keep "
                                        f"ourselves to ourselves.\""}
            else:
                out[loc_id] = {"allowed": True, "by": speaker,
                               "reply": f"{sim.residents[speaker].first}: \"Go ahead, if it helps.\""}
        return out

    def _evidence(self, consent: dict) -> dict:
        sim, now = self.sim, self.now
        out: dict[str, list] = {}
        for e in sim.world.evidence:
            if not e.present_at(now):
                continue
            out.setdefault(e.place, []).append(e)
        return out

    def _records(self, consent: dict) -> dict:
        sim, now = self.sim, self.now
        out = {}
        for book, meta in sim.world.books.items():
            entries = [x for x in sim.world.records[book] if now - 4 * DAY <= x.time <= now]
            out[book] = {"place": meta["place"], "title": meta["title"], "entries": entries}
        return out

    def _vehicles(self, consent: dict) -> dict:
        sim = self.sim
        out = {}
        for vid, v in sim.world.vehicles.items():
            where = v.location
            loc = sim.world.locations[where]
            if loc.kind == "home":
                c = consent[where]
                allowed, reply = c["allowed"], c["reply"]
            else:
                allowed, reply = True, f"It's parked at {loc.name} where anyone can see it."
            out[vid] = {"name": v.name, "kind": v.kind, "household": v.household, "location": where,
                        "allowed": allowed, "reply": reply}
        return out

    # ------------------------------------------------------------ views
    def _investigation(self, consent, evidence, records, vehicles, hints) -> dict:
        sim, inc, now = self.sim, self.inc, self.now
        residents = []
        for rid in sim.ids:
            r = sim.residents[rid]
            condition = "alive" if r.alive else "deceased"
            if r.alive and r.injury:
                condition = "injured"
            # Where they can be found while the case is investigated (the town as it is at the frozen
            # instant): present state anyone could observe by walking around, not the past.
            now_at = sim.where(rid, now) if r.alive else None
            residents.append({"id": rid, "name": r.name, "first": r.first, "occupation": r.occupation,
                              "age_group": r.age_group, "household": r.household,
                              "home": r.home, "condition": condition, "now_at": now_at})
        places = []
        for loc_id in sorted(sim.world.locations):
            loc = sim.world.locations[loc_id]
            c = consent[loc_id]
            places.append({"id": loc_id, "name": loc.name, "kind": loc.kind,
                           "owners": [o for o in loc.owners], "allowed": c["allowed"], "reply": c["reply"],
                           "traces": [{"id": f"T-{e.id}", "description": e.description}
                                      for e in evidence.get(loc_id, [])] if c["allowed"] else []})
        veh_out = []
        for vid, v in sorted(vehicles.items()):
            veh_out.append({**{k: v[k] for k in ("name", "kind", "household", "location", "allowed", "reply")},
                            "id": vid,
                            "traces": [{"id": f"T-{e.id}", "description": e.description}
                                       for e in evidence.get(vid, [])] if v["allowed"] else []})
        rec_out = {}
        for book, data in records.items():
            c = consent[data["place"]]
            rec_out[book] = {"title": data["title"], "place": data["place"], "allowed": c["allowed"],
                             "reply": c["reply"],
                             "entries": [{"id": f"R-{x.id}", "time": x.time, "text": x.text}
                                         for x in data["entries"]] if c["allowed"] else []}
        testimony = {}
        for rid in sim.ids:
            r = sim.residents[rid]
            if not r.alive:
                continue
            style = "nervous" if r.traits.honesty >= 0.6 else "smooth"
            testimony[rid] = {"goodwill": 2 + int(r.traits.sociability * 3), "style": style,
                              "items": self.items.get(rid, []), "evasive_topics": sorted(self.evasive.get(rid, []))}
        return {
            "schema": f"investigation/{CASE_SCHEMA}",
            "case_id": self.case_id,
            "versions": {"sim": SIM_VERSION, "config": CONFIG_VERSION},
            "town": sim.world.town_name,
            "start_time": now,
            "start_label": fmt(now),
            "player_role": PLAYER_ROLE,
            "hook": {"title": inc.title, "text": inc.hook_text, "kind": inc.hook_kind, "place": inc.hook_place,
                     "window": self.window, "window_label": fmt_span(*self.window),
                     "discovered_by": inc.discovered_by,
                     # where people's first answers start (schema 0.3): earlier times come up when asked
                     "recent_from": self.recent_from},
            "residents": residents,
            "places": places,
            "vehicles": veh_out,
            "records": rec_out,
            "testimony": testimony,
            "theory_options": {
                "mechanisms": [{"id": m, "label": MECHANISM_LABELS[m]} for m in HOOK_MECHANISMS[inc.hook_kind]],
                "motives": [{"id": k, "label": v} for k, v in MOTIVES.items()],
            },
            "hints": hints,
            "hint_credits": 6,
        }

    def _truth(self, report, evidence, records) -> dict:
        sim, inc, now = self.sim, self.inc, self.now
        log = sim.log
        chain = [log.by_id[e].to_dict() for e in self.chain]
        R = inc.responsible
        movements = []
        if R:
            for ev in log.events:
                if ev.kind == "move" and R in ev.actors and self.focus[0] - 60 <= ev.time <= self.now:
                    movements.append(ev.to_dict())
        scene = [ev.to_dict() for ev in log.events
                 if ev.notable and self.window[0] - 6 * 60 <= ev.time <= now and ev.id not in self.chain]
        evidence_audit = {}
        for place, items in evidence.items():
            for e in items:
                src = log.by_id[e.created_by]
                evidence_audit[f"T-{e.id}"] = {"place": place, "kind": e.kind, "created_by": e.created_by,
                                               "created_at": e.created_at, "event_summary": src.summary,
                                               "implicates": e.implicates}
        record_audit = {}
        for book, data in records.items():
            for x in data["entries"]:
                src = log.by_id[x.event_id]
                record_audit[f"R-{x.id}"] = {"event": x.event_id, "event_kind": src.kind,
                                             "event_summary": src.summary}
        accepted_motives = [inc.motive]
        if inc.family in ("assault", "collision") and any(
                log.by_id[e].kind == "drink" for e in self.chain if R and R in log.by_id[e].actors):
            if "intoxication" not in accepted_motives:
                accepted_motives.append("intoxication")
        if inc.fled and "panic" not in accepted_motives:
            accepted_motives.append("panic")
        private = {}
        for rid in sim.ids:
            r = sim.residents[rid]
            private[rid] = {"name": r.name, "alive": r.alive, "traits": vars(r.traits), "cash": r.cash,
                            "stress": round(r.stress, 1), "guilty_of": [g for g in r.guilty_of
                                                                       if log.by_id[g].time <= now],
                            "debts": [vars(d) for d in sim.world.debts if rid in (d.debtor, d.creditor)
                                      and d.open_at(now)],
                            "pressure": sim.pressure.get(rid)}
        return {
            "schema": f"truth/{CASE_SCHEMA}",
            "case_id": self.case_id,
            "config": sim.config.describe(),
            "town": sim.world.town_name,
            "case_start": now,
            "incident": inc.to_dict(),
            "place_names": {**{k: v.name for k, v in sim.world.locations.items()},
                            **{k: v.name for k, v in sim.world.vehicles.items()},
                            **{k: v["title"] for k, v in sim.world.books.items()}},
            "answer": {"mechanism": inc.mechanism, "responsible": R, "outcome": inc.outcome,
                       "motives": accepted_motives},
            "narrative": _narrative(sim, inc),
            "chain": chain,
            "responsible_movements": movements,
            "other_notable": scene,
            "testimony_audit": self.audit,
            "evidence_audit": evidence_audit,
            "record_audit": record_audit,
            "private_states": private,
            "other_incidents": [i.to_dict() for i in sim.incidents if i.id != inc.id and i.time <= now],
            "suitability": report,
            "event_log_digest": log.digest(until=now),
            "event_count": len([e for e in log.events if e.time <= now]),
        }


FACT_KINDS = {"presence", "sighting", "intoxicated", "argument", "assault", "noise", "saw_collision", "purchase",
              "injury", "struck", "fall", "death"}


def _facts(c: Claim) -> list[dict]:
    """Where the statement *claims* someone was, for the player's timeline.

    Built from the claim as the speaker recalls it (shifted times, misidentifications and
    all), so it is exactly as player-safe as the sentence itself."""
    if c.kind not in FACT_KINDS or c.start is None or c.location is None:
        return []
    who = [c.subject] if c.kind not in ("struck", "injury", "death") else [c.other or c.subject]
    if c.kind in ("argument", "assault"):
        who.append(c.other)
    end = c.end if c.end is not None else c.start
    return [{"who": w, "place": c.location, "from": c.start, "to": end, "hedged": bool(c.hedged)}
            for w in who if w]


def _segment_facts(rid: str, segs: list[list]) -> list[dict]:
    return [{"who": rid, "place": loc, "from": s, "to": e, "hedged": False} for loc, s, e in segs]


def _group(sim: "Simulation", b, c: Claim) -> dict | None:
    """Lets the dialogue say 'I saw Ana, Ben and Cat at the pub ...' instead of three lines."""
    if b.source != "saw" or c.subject is None or c.kind not in ("presence", "intoxicated") or c.start is None:
        return None
    from mystery.cases.testimony import phrases
    percept, _ = phrases(sim, c)
    name = sim.residents[c.subject].first
    if not percept.startswith(name):
        return None
    template = "I saw {names}" + percept[len(name):] + "."
    end = c.end if c.end is not None else c.start
    return {"id": f"{c.kind}|{c.location}|{c.start // 30}|{end // 30}", "name": name, "template": template}


def _narrative(sim: "Simulation", inc: Incident) -> str:
    ev = sim.log.by_id[inc.core_event]
    who = sim.residents[inc.responsible].name if inc.responsible else None
    if inc.family == "theft":
        return f"{who} took {ev.data['amount']} {'units of food' if ev.data['asset'] == 'food' else 'crowns'} " \
               f"from {sim.world.containers[ev.objects[0]].label} at {fmt(ev.time)}."
    if inc.family == "accounting_error":
        clerk = sim.residents[ev.actors[0]].name
        return f"Nothing was stolen. {clerk} wrote a sale into the ledger twice at {fmt(ev.time)}, so the till " \
               f"looked short when it was counted."
    if inc.family == "assault":
        return f"{who} attacked {sim.residents[inc.victims[0]].name} at {sim.world.name(inc.location)} at " \
               f"{fmt(ev.time)} during an argument."
    if inc.family == "collision":
        victim = sim.residents[inc.victims[0]].name if inc.victims else "the fence"
        drunk = " after drinking" if inc.intent == "reckless" else ""
        fled = " and drove on without stopping" if inc.fled else ""
        return f"{who}, driving {sim.world.name(ev.objects[0])}{drunk}, hit {victim} on Mill Road at " \
               f"{fmt(ev.time)}{fled}."
    if inc.family == "fall":
        return f"Nobody else was involved: {sim.residents[inc.victims[0]].name}, drunk, fell into the ditch on " \
               f"Mill Road at {fmt(ev.time)}."
    return ev.summary


# =================================================================== running & saving
def snapshot_hook(selected: str | None = None, store: dict | None = None, summary_only: bool = False):
    """A simulation hook that builds case snapshots at each case start."""
    store = {} if store is None else store

    def hook(sim: "Simulation", inc: Incident) -> None:
        if not inc.is_candidate or (selected is not None and inc.id != selected):
            return
        case = build_case(sim, inc)
        store[inc.id] = case["suitability"] if summary_only else case

    return hook, store


def write_case(case: dict, out_dir: str) -> str:
    path = os.path.join(out_dir, case["case_id"])
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "investigation.json"), "w", encoding="utf-8") as f:
        json.dump(case["investigation"], f, indent=1, sort_keys=True)
    with open(os.path.join(path, "truth.json"), "w", encoding="utf-8") as f:
        json.dump(case["truth"], f, indent=1, sort_keys=True)
    session = os.path.join(path, "session.json")
    if os.path.exists(session):
        os.remove(session)
    return path


def write_event_log(sim: "Simulation", path: str, until: int) -> None:
    with open(os.path.join(path, "events.jsonl"), "w", encoding="utf-8") as f:
        for ev in sim.log.events:
            if ev.time <= until:
                f.write(json.dumps(ev.to_dict(), sort_keys=True) + "\n")
