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
        names = [m["group"]["name"] for m in members]
        joined = names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and " + names[-1]
        out.append((members, members[0]["group"]["template"].replace("{names}", joined)))
    return out


def answer(data: dict, state: dict, rid: str, topic: str, press: bool = False) -> tuple[list, list[dict]]:
    """Return (lines to show, items heard). Each line is (text, items behind it)."""
    t = data["testimony"].get(rid)
    if t is None:
        return [("They cannot be questioned.", [])], []
    goodwill = state.setdefault("goodwill", {})
    goodwill.setdefault(rid, t["goodwill"])
    pressed = state.setdefault("pressed", {}).setdefault(rid, [])
    if press:
        if topic in pressed:
            return [("You've already pushed them on that.", [])], []
        if goodwill[rid] <= 0:
            return [(WORN_OUT, [])], []
        goodwill[rid] -= 1
        pressed.append(topic)
    allow_guarded = topic in pressed
    items = [it for it in t["items"] if topic in it["topics"]]
    shown = [it for it in items if allow_guarded or not it["guarded"]]
    hidden = [it for it in items if it["guarded"] and not allow_guarded]
    shown.sort(key=lambda it: (it["time"] is None, it["time"] or 0, it["key"]))
    lines: list[tuple[str, list[dict]]] = []
    if not shown:
        if topic in t["evasive_topics"] or hidden:
            lines.append((EVASIVE[t["style"]], []))
        else:
            lines.append((NO_KNOWLEDGE, []))
    for members, text in _group(shown):
        lines.append((text, members))
    if hidden and HESITATE[t["style"]]:
        lines.append((HESITATE[t["style"]], []))
    if press and not hidden and allow_guarded and not [it for it in items if it["guarded"]]:
        lines.append(("(Pressing them doesn't get you anything more.)", []))
    return lines, shown
