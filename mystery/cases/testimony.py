"""Turning beliefs into first-person testimony.

Every sentence is rendered from a belief the speaker actually holds, phrased by its
source: "I saw", "I heard", "<name> told me", "I reckon". Lies are rendered by the
same functions from fabricated claims, so they read exactly like the truth.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from mystery.sim.clock import day_of, fmt, fmt_approx, fmt_clock, fmt_span

if TYPE_CHECKING:
    from mystery.sim.engine import Simulation
    from mystery.sim.memory import Belief, Claim


def _n(sim: "Simulation", rid: str | None) -> str:
    if rid is None:
        return "someone"
    return sim.residents[rid].first if rid in sim.residents else rid


def _when(c: "Claim") -> str:
    if c.start is None:
        return ""
    if c.end is not None and c.end - c.start >= 30:
        return fmt_span(c.start, c.end)
    return fmt_approx(c.start)


def _place(sim: "Simulation", loc: str | None) -> str:
    return sim.world.name(loc) if loc else "somewhere"


def _veh(sim: "Simulation", vid: str | None) -> str:
    if vid and vid in sim.world.vehicles:
        return sim.world.vehicles[vid].name
    return "a vehicle"


THEY_FIXES = [(" they was ", " they were "), (" they has ", " they have "), (" they is ", " they are "),
              (" they owes ", " they owe "), (" they had something", " they had something")]


def phrases(sim: "Simulation", c: "Claim", teller: str | None = None) -> tuple[str, str]:
    """(perceptual phrase for 'I saw/heard ...', proposition for 'X told me ...').

    When the teller is a party to their own story they become 'they'/'them'."""
    percept, prop = _phrases(sim, c, teller)
    if teller and c.subject == teller and prop.startswith("they "):
        prop = " " + prop
        for a, b in THEY_FIXES:
            prop = prop.replace(a, b)
        prop = prop.strip()
    return percept, prop


def _phrases(sim: "Simulation", c: "Claim", teller: str | None) -> tuple[str, str]:
    k, who, other = c.kind, _n(sim, c.subject), _n(sim, c.other)
    if teller and c.other == teller:
        other = "them"
    if teller and c.subject == teller and c.kind not in ("presence", "sighting"):
        who = "they"
    place, when = _place(sim, c.location), _when(c)
    if k == "presence":
        return f"{who} at {place} {when}", f"{who} was at {place} {when}"
    if k == "sighting":
        tail = f", {c.detail}" if c.detail else ""
        if c.subject is None:
            return (f"someone at {place} {when}{tail} — too dark to tell who",
                    f"someone was at {place} {when}{tail}")
        if c.hedged:
            return (f"someone at {place} {when}{tail}; I think it was {who}, but it was dark",
                    f"{who} was at {place} {when}{tail}, though it was dark")
        return f"{who} at {place} {when}{tail}", f"{who} was at {place} {when}{tail}"
    if k == "noise":
        door = "door" in c.detail
        voice = (f"; I think it was {who}" if door else f"; I think one of the voices was {who}") if c.subject else ""
        where = "at" if door else "from"
        tail = "" if door else ". I didn't see anything"
        return (f"{c.detail} {where} {place} {when}{voice}{tail}",
                f"there was {c.detail} at {place} {when}")
    if k == "argument":
        return (f"{who} confront {other} at {place} {when} — {c.detail}",
                f"{who} confronted {other} at {place} {when} — {c.detail}")
    if k == "assault":
        return f"{who} attack {other} at {place} {when}", f"{who} attacked {other} at {place} {when}"
    if k == "saw_collision":
        hit = "someone" if c.other else "the fence"
        driver = f"; I think {who} was driving" if c.subject else ""
        return (f"{_veh(sim, c.obj)} hit {hit} on Mill Road {when}{driver}",
                f"{_veh(sim, c.obj)} hit {hit} on Mill Road {when}")
    if k == "loss":
        return (f"{c.detail} ({_when(c)})", f"{c.detail}; it went missing {fmt_span(c.start, c.end or c.start)}"
                if c.start is not None else c.detail)
    if k == "damage":
        return f"{c.detail} {when}", f"about {c.detail}, {when}"
    if k == "missing":
        return f"no sign of {who} all day", f"nobody had seen {who} all day"
    if k == "injury":
        if c.detail.startswith("lying"):
            return f"{who} {c.detail} {when}", f"{who} was found {c.detail} {when}"
        return f"{who} hurt — {c.detail} — {when}", f"{who} was hurt — {c.detail} — {when}"
    if k == "death":
        return f"{who} dead at {place} {when}", f"{who} was found dead at {place} {when}"
    if k == "intoxicated":
        return f"{who} the worse for drink at {place} {when}", f"{who} was drunk at {place} {when}"
    if k == "vehicle_damage":
        owner = f" ({who}'s)" if c.subject else ""
        return (f"{_veh(sim, c.obj)}{owner} with {c.detail} {when}",
                f"{_veh(sim, c.obj)}{owner} had {c.detail} {when}")
    if k == "repair":
        return (f"{who} bring {_veh(sim, c.obj)} in for repairs {when}, saying: \"{c.detail}\"",
                f"{who} had {_veh(sim, c.obj)} repaired {when} and said: \"{c.detail}\"")
    if k == "debt":
        if c.detail == "repaid":
            p = f"{who} paid {other} back {c.amount} crowns {when}"
        elif c.detail == "overdue":
            p = f"{who} is behind on paying {other} back ({c.amount} crowns)"
        elif c.detail == "credit":
            p = f"{who} has been taking food on credit from {other} ({c.amount} crowns owed)"
        else:
            p = f"{who} owes {other} {c.amount} crowns"
        return p, p
    if k == "loan":
        return f"{who} borrowing money from {other} {when}", f"{who} borrowed money from {other} {when}"
    if k == "refusal":
        return (f"{who} turn {other} down for {c.detail} {when}", f"{who} refused {other} {c.detail} {when}")
    if k == "hardship":
        return f"{who} struggling for money", f"{who} has been short of money — {c.detail}"
    if k == "rent_missed":
        return f"{who} miss the rent", f"{who} couldn't pay the rent to {other}"
    if k == "grudge":
        return "", f"there's bad blood between {who} and {other} — {c.detail}"
    if k == "laid_off":
        return "", f"{other} laid {who} off from the mill"
    if k == "help":
        return f"{who} help {other} out with money", f"{who} gave {other} some money to tide them over"
    if k == "reconcile":
        return (f"{who} try to make peace with {other}", f"{who} tried to make peace with {other} ({c.detail})")
    if k == "confession":
        return f"{who} confess to {other}", f"{who} confessed something to {other}"
    if k == "suspect":
        return "", f"{who} had something to do with {c.detail}"
    if k == "struck":
        driver = f"{who} hit {other}" if c.subject else f"a vehicle hit {other}"
        return driver + f" on Mill Road {when}", driver + f" on Mill Road {when}"
    if k == "fall":
        return f"{who} fall into the ditch", f"{who} fell into the ditch on Mill Road {when}"
    if k == "purchase":
        return f"{who} buying food", f"{who} bought {c.detail} at the grocery {when}"
    if k == "collision_self":
        return "", f"{who} {c.detail} on Mill Road {when} driving {_veh(sim, c.obj)}"
    return c.kind, c.kind


def first_person(sim: "Simulation", speaker: str, c: "Claim") -> str | None:
    """Sentences about the speaker's own experience."""
    k = c.kind
    when, place, other = _when(c), _place(sim, c.location), _n(sim, c.other)
    if k == "debt" and c.subject == speaker:
        return {"repaid": f"I paid {other} back the {c.amount} crowns I owed, {when}.",
                "overdue": f"I'm behind on paying {other} back — {c.amount} crowns.",
                "credit": f"I've been taking food on credit from {other}; I owe {c.amount} crowns."}.get(
            c.detail, f"I owe {other} {c.amount} crowns.")
    if k == "debt" and c.other == speaker:
        who = _n(sim, c.subject)
        return {"repaid": f"{who} paid me back {c.amount} crowns {when}.",
                "overdue": f"{who} owes me {c.amount} crowns and is late paying.",
                "credit": f"{who} has been taking food on credit; owes me {c.amount} crowns."}.get(
            c.detail, f"{who} owes me {c.amount} crowns.")
    if k == "refusal" and c.subject == speaker:
        return f"I turned {other} down when they asked me for {c.detail}, {when}."
    if k == "refusal" and c.other == speaker:
        return f"I asked {_n(sim, c.subject)} for {c.detail} {when}. They said no."
    if k == "hardship":
        return f"{_n(sim, c.subject)} came asking me for money, {when}. Times are hard for them."
    if k == "argument":
        if c.subject == speaker:
            return f"I had it out with {other} at {place} {when} — {c.detail}."
        return f"{_n(sim, c.subject)} came at me at {place} {when} — {c.detail}."
    if k == "assault" and c.other == speaker:
        return f"{_n(sim, c.subject)} attacked me at {place} {when}."
    if k == "assault" and c.subject == speaker:
        return f"{_n(sim, c.other)} and I came to blows at {place} {when}. They started it."
    if k == "loss":
        span = fmt_span(c.start, c.end) if c.start is not None and c.end is not None else ""
        return f"I found {c.detail}. It went missing {span}."
    if k == "struck" and c.other == speaker:
        if c.subject:
            return f"{_n(sim, c.subject)} hit me with {_veh(sim, c.obj)} on Mill Road {when}. They stopped to help."
        return f"Something hit me on Mill Road {when} — {c.detail}, I think. It didn't stop. I never saw the driver."
    if k == "fall":
        return f"I slipped into the ditch on Mill Road {when}. I'd had a few."
    if k == "injury" and c.subject == speaker:
        return f"I got hurt on {place} {when}, and I honestly can't remember how."
    if k == "injury" and c.detail.startswith("lying"):
        return f"I found {_n(sim, c.subject)} {c.detail}, {when}."
    if k == "injury":
        return f"{_n(sim, c.subject)} was hurt — {c.detail} — {when}."
    if k == "death":
        return f"I found {_n(sim, c.subject)} dead at {place} {when}."
    if k == "purchase":
        return f"I bought {c.detail} at the grocery {when} and paid {c.amount} crowns."
    if k == "grudge":
        them = c.other if c.subject == speaker else c.subject
        return f"{_n(sim, them)} and I have never got on — {c.detail}."
    if k == "laid_off":
        return (f"{_n(sim, c.other)} laid me off from the mill." if c.subject == speaker
                else f"I had to let {_n(sim, c.subject)} go from the mill.")
    if k == "loan":
        return None
    if k == "help":
        return (f"I gave {other} a little money to tide them over." if c.subject == speaker
                else f"{_n(sim, c.subject)} gave me some money to tide me over.")
    if k == "reconcile":
        them = c.other if c.subject == speaker else c.subject
        return f"I tried to make peace with {_n(sim, them)} ({c.detail})." if c.subject == speaker else \
            f"{_n(sim, them)} came to make peace with me ({c.detail})."
    if k == "rent_missed":
        return (f"I couldn't make the rent to {other}." if c.subject == speaker
                else f"{_n(sim, c.subject)} couldn't pay me the rent.")
    if k == "collision_self":
        return f"I {c.detail} on Mill Road {when}, driving {_veh(sim, c.obj)}. I stopped and owned up."
    if k == "confession":
        return (f"I confessed to {other}." if c.subject == speaker
                else f"{_n(sim, c.subject)} confessed to me.")
    return None


def render(sim: "Simulation", speaker: str, b: "Belief", claim: "Claim") -> str:
    if b.source == "self":
        text = first_person(sim, speaker, claim)
        if text:
            return text
    percept, prop = phrases(sim, claim)
    if b.source == "saw" and percept:
        return f"I saw {percept}."
    if b.source == "heard" and percept:
        return f"I heard {percept}."
    if b.source == "told":
        teller = _n(sim, b.told_by)
        _, prop = phrases(sim, claim, b.told_by)
        return f"{teller} told me {prop}."
    if b.source == "inferred":
        if claim.kind == "suspect":
            return f"If you ask me, {prop}."
        if claim.kind == "assault":
            return f"I think {_n(sim, claim.subject)} pushed me. It's all hazy."
        return f"I reckon {prop}."
    return f"{prop[0].upper()}{prop[1:]}."


# ------------------------------------------------------------- whereabouts
def segments(sim: "Simulation", rid: str, a: int, b: int) -> list[list]:
    out: list[list] = []
    for loc, s, e in sim.intervals[rid]:
        e2 = b if e is None else e
        if e2 <= a or s >= b:
            continue
        s2, e2 = max(s, a), min(e2, b)
        if out and out[-1][0] == loc:
            out[-1][2] = e2
        else:
            out.append([loc, s2, e2])
    return out


def describe_segments(sim: "Simulation", rid: str, segs: list[list], hazy_after: int | None = None) -> str:
    parts = []
    home = sim.residents[rid].home
    for i, (loc, s, e) in enumerate(segs):
        outdoor = sim.world.locations[loc].outdoor
        if outdoor and e - s < 25 and 0 < i < len(segs) - 1:
            parts.append(f"around {fmt_clock(s)} I passed through {sim.world.name(loc)}")
            continue
        label = "at home" if loc == home else f"at {sim.world.name(loc)}"
        night = ""
        if loc == home and (e - s) >= 4 * 60:
            night = ", asleep for most of it"
        parts.append(f"from about {fmt_clock(_r15(s))} to {fmt_clock(_r15(e))} I was {label}{night}")
        if hazy_after is not None and e > hazy_after and loc != home:
            parts.append("after that it gets hazy — I'd had a fair bit to drink")
            hazy_after = None
    if not parts:
        return "I don't rightly remember."
    start_day = day_of(segs[0][1])
    text = "; ".join(parts)
    return f"On Day {start_day}: {text}."


def _r15(t: int) -> int:
    return int(round(t / 15)) * 15


def drinks_before(sim: "Simulation", rid: str, until: int, hours: int = 5) -> int:
    n = 0
    for ev in sim.log.events:
        if ev.kind == "drink" and ev.actors[0] == rid and until - hours * 60 <= ev.time <= until:
            n += ev.data.get("drinks", 1)
    return n


__all__ = ["render", "segments", "describe_segments", "phrases", "first_person", "fmt"]
