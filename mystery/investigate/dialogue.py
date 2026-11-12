"""Topic-based questioning. Answers come only from what each resident is willing to say."""

from __future__ import annotations

BASE_TOPICS = [
    ("whereabouts", "Where they were during the time in question"),
    ("window", "What they saw or heard during that time"),
    ("incident", "What they know about what happened"),
    ("money", "Money troubles and debts around town"),
    ("conflicts", "Arguments and grudges"),
    ("rumors", "What people are saying"),
    ("vehicles", "Vehicles and the road"),
    ("past", "Other trouble in town lately"),
]

NO_KNOWLEDGE = "I don't know anything about that."
EVASIVE = {
    "nervous": "I... I'd rather not get into that.",
    "smooth": "Can't help you there, I'm afraid.",
}
HESITATE = {
    "nervous": "(They hesitate, as if there is something more they are not saying.)",
    "smooth": "",
}
WORN_OUT = "That's enough questions for today. I've told you what I know."
NOTHING_LATELY = "Nothing lately that I know of."
NOTHING_MORE = "That's about all there is to it."
NOTHING_EARLIER = "I can't think of anything before that."
PRESSED_IN_VAIN = "(Pressing them doesn't get you anything more.)"
FOLLOWS = ("more", "earlier")
# Topics about this case or about the past are answered whatever the time; the others start with recent
# times and go further back only when asked "and before that?".
ALL_TIMES = ("incident", "past")


def topics_for(data: dict, rid: str) -> list[tuple[str, str]]:
    out = list(BASE_TOPICS)
    for r in data["residents"]:
        if r["id"] != rid:
            label = f"About {r['first']}" + (" (deceased)" if r["condition"] == "deceased" else "")
            out.append((f"person:{r['id']}", label))
    return out


def _group(items: list[dict]) -> list[tuple[list[dict], str]]:
    """Merge 'I saw A at X' + 'I saw B at X' into one sentence; keeps every item for the notebook."""
    groups: dict[str, list[dict]] = {}
    order: list[str] = []
    for it in items:
        gid = it.get("group", {}).get("id") if it.get("group") else None
        key = gid or it["key"]
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(it)
    out = []
    for key in order:
        members = groups[key]
        if len(members) == 1 or not members[0].get("group"):
            for m in members:
                out.append(([m], m["text"]))
            continue
        names = []
        for m in members:
            if m["group"]["name"] not in names:
                names.append(m["group"]["name"])
        joined = names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and " + names[-1]
        out.append((members, members[0]["group"]["template"].replace("{names}", joined)))
    return out


def _era(it: dict) -> str:
    return it.get("era", "recent")


def _summaries(t: dict) -> dict[str, dict]:
    return {it["key"]: it for it in t["items"] if it.get("members")}


def _behind(it: dict, topic: str, summaries: dict[str, dict]) -> bool:
    """Told only when asked for more: the item stands behind a summary that is told on this topic."""
    s = summaries.get(it.get("in"))
    return s is not None and topic in s["topics"]


def answer(data: dict, state: dict, rid: str, topic: str, press: bool = False,
           follow: str = "") -> tuple[list, list[dict]]:
    """Return (lines to show, items heard). Each line is (text, items behind it).

    A first answer covers recent times and tells everyday matters in summary. follow="more" tells the
    statements behind those summaries that have not been heard yet; follow="earlier" goes back before
    recent times (and makes "more" cover those summaries too). Pressing works as before: it costs patience
    and lets guarded statements out."""
    t = data["testimony"].get(rid)
    if t is None:
        return [("They cannot be questioned.", [])], []
    goodwill = state.setdefault("goodwill", {})
    goodwill.setdefault(rid, t["goodwill"])
    pressed = state.setdefault("pressed", {}).setdefault(rid, [])
    earlier = state.setdefault("earlier", {}).setdefault(rid, [])
    if press:
        if topic in pressed:
            return [("You've already pushed them on that.", [])], []
        if goodwill[rid] <= 0:
            return [(WORN_OUT, [])], []
        goodwill[rid] -= 1
        pressed.append(topic)
    if follow == "earlier" and topic not in earlier and topic not in ALL_TIMES:
        earlier.append(topic)
    view = view_of(t, state, rid, topic)
    allow_guarded = topic in pressed
    if follow == "more":
        heard = state.get("by_ref", {})
        shown = [it for it in view["behind"] if it["key"] not in heard]
        hidden: list[dict] = []
    else:
        era = "earlier" if follow == "earlier" and topic not in ALL_TIMES else "recent"
        pool = [it for it in view["front"] if topic in ALL_TIMES or _era(it) == era]
        shown = [it for it in pool if allow_guarded or not it["guarded"]]
        hidden = [it for it in pool if it["guarded"] and not allow_guarded]
    shown.sort(key=lambda it: (it["time"] is None, it["time"] or 0, it["key"]))
    lines: list[tuple[str, list[dict]]] = []
    if not shown:
        if follow == "more":
            lines.append((NOTHING_MORE, []))
        elif follow == "earlier":
            lines.append((EVASIVE[t["style"]] if hidden else NOTHING_EARLIER, []))
        elif topic in t["evasive_topics"] or hidden:
            lines.append((EVASIVE[t["style"]], []))
        elif view["earlier"]:
            lines.append((NOTHING_LATELY, []))
        else:
            lines.append((NO_KNOWLEDGE, []))
    for members, text in _group(shown):
        lines.append((text, members))
    if hidden and HESITATE[t["style"]]:
        lines.append((HESITATE[t["style"]], []))
    if press and allow_guarded and not [it for it in t["items"] if topic in it["topics"] and it["guarded"]]:
        lines.append((PRESSED_IN_VAIN, []))
    return lines, shown


def view_of(t: dict, state: dict, rid: str, topic: str) -> dict:
    """What this person could tell on a topic right now: the statements in front (told when asked), the
    ones behind summaries already within reach, and whether going further back would add anything."""
    summaries = _summaries(t)
    pressed = state.get("pressed", {}).get(rid, [])
    reach = ("recent", "earlier") if topic in ALL_TIMES or topic in state.get("earlier", {}).get(rid, []) \
        else ("recent",)
    on = [it for it in t["items"] if topic in it["topics"]]
    front = [it for it in on if not _behind(it, topic, summaries)]
    behind = [it for it in on if _behind(it, topic, summaries) and _era(summaries[it["in"]]) in reach]
    earlier = [it for it in front if _era(it) == "earlier" and (topic in pressed or not it["guarded"])] \
        if topic not in ALL_TIMES else []
    return {"front": front, "behind": behind, "earlier": earlier}


def follow_ups(data: dict, state: dict, rid: str, topic: str) -> dict:
    """Which follow-up questions would get anything new (offered to the player after an answer)."""
    t = data["testimony"].get(rid)
    if t is None:
        return {"can_more": False, "can_earlier": False}
    view = view_of(t, state, rid, topic)
    heard = state.get("by_ref", {})
    asked_earlier = topic in state.get("earlier", {}).get(rid, [])
    return {"can_more": any(it["key"] not in heard for it in view["behind"]),
            "can_earlier": bool(view["earlier"]) and not asked_earlier}
