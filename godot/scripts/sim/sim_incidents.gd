## The incident registry (mirrors mystery/sim/incidents.py and the incident parts of engine.py).
##
## An incident is registered when its core event happens (a theft, a ledger mistake ...), with who was
## responsible, who lost by it, why, and the events linked to it. It is developer-only truth: residents learn
## of an incident only through what they perceive, are told or infer (scripts/sim/sim_memory.gd). It becomes
## *discovered* when somebody in town actually notices its consequence (a short till at counting time), and
## only then a case candidate.
##
## An incident: {id, family, core_event, time, location, responsible (id or null), victims, intent, mechanism,
## outcome, severity, hook_kind, motive, related_events, discovered_at, discovered_by, discovery_event, window,
## hook_place, hook_text, title, reported_openly, fled, case_start}; absent values are null.
##
## Families: theft and accounting_error (Pilot 3A); assault, collision and fall (Pilot 3B). An accident is
## registered like anything else, but whether it could ever become a case is decided elsewhere (case packaging,
## a later pilot): a collision owned up to on the spot is "reported openly", and is no candidate.
extends RefCounted

const SimClock = preload("res://scripts/sim/sim_clock.gd")

const DAY := 1440
const MECHANISM_LABELS := {
	"stolen": "stolen by someone",
	"accounting_error": "a bookkeeping mistake (nothing was taken)",
	"assaulted": "attacked by someone",
	"struck_by_vehicle": "struck by a vehicle",
	"vehicle_collision": "a vehicle crashed into it",
	"accidental_fall": "an accidental fall",
	"vandalism": "deliberate vandalism",
	"unresolved": "cannot be determined from the evidence",
}
const MOTIVES := {
	"money_trouble": "money trouble",
	"grudge": "anger or an old grudge",
	"intoxication": "drink clouded their judgement",
	"panic": "panic and fear of being found out",
	"none": "no one intended harm",
	"unknown": "unknown",
}


static func register(sim, fields: Dictionary) -> Dictionary:
	var inc := {"id": "I%d" % (sim.incidents.size() + 1), "family": "", "core_event": "", "time": 0, "location": "",
			"responsible": null, "victims": [], "intent": "", "mechanism": "", "outcome": "", "severity": 0,
			"hook_kind": "", "motive": "", "related_events": [], "discovered_at": null, "discovered_by": null,
			"discovery_event": null, "window": null, "hook_place": null, "hook_text": "", "title": "",
			"reported_openly": false, "fled": false, "case_start": null}
	for k in fields:
		inc[k] = fields[k]
	inc["victims"] = Array(inc["victims"]).duplicate()
	inc["related_events"] = Array(inc["related_events"]).duplicate()
	sim.incidents.append(inc)
	sim.bump("incident:" + String(inc["family"]))
	return inc


static func incident_for(sim, event_id) -> Dictionary:
	## The incident an event belongs to (its core event or a related one), or {}.
	if event_id == null or String(event_id) == "":
		return {}
	for inc in sim.incidents:
		if inc["core_event"] == event_id or event_id in inc["related_events"]:
			return inc
	return {}


static func discover(sim, inc: Dictionary, by: String, t: int, event_id: String, hook_text: String, title: String,
		window: Array, place: String) -> void:
	## The first time anyone notices the incident's consequence. Later notices change nothing here.
	if inc["discovered_at"] != null:
		return
	inc["discovered_at"] = t
	inc["discovered_by"] = by
	inc["discovery_event"] = event_id
	inc["hook_text"] = hook_text
	inc["title"] = title
	inc["window"] = window.duplicate()
	inc["hook_place"] = place
	if not inc["reported_openly"]:
		inc["case_start"] = case_start_for(t)
	sim.bump("discovered:" + String(inc["family"]))


@warning_ignore("integer_division")
static func case_start_for(discovered_at: int) -> int:
	## The investigator arrives an hour or two after discovery; never in the dead of night.
	var nxt := (discovered_at / 60 + 1) * 60 + 60
	var h := SimClock.hour_of(nxt)
	if h >= 22 or h < 7:
		var day_start := (nxt / DAY) * DAY
		nxt = day_start + 8 * 60 if h < 7 else day_start + DAY + 8 * 60
	return nxt


static func is_candidate(inc: Dictionary) -> bool:
	return inc["discovered_at"] != null and not inc["reported_openly"]


static func core_for_claim(sim, claim: Dictionary):
	## The core event of a discovered incident at the claim's place and time (within six hours), or null:
	## how an accusation is matched to what really happened, to know whether the accused is guilty of it.
	for inc in sim.incidents:
		if inc["location"] == claim["location"] and claim["start"] != null and inc["discovered_at"] != null:
			var until: int = claim["end"] if claim["end"] != null else claim["start"]
			if claim["start"] - 6 * 60 <= inc["time"] and inc["time"] <= until + 6 * 60:
				return inc["core_event"]
	return null
