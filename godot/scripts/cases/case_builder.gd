## Freezing a case at the moment the investigator arrives (mirrors the _Builder of mystery/cases/export.py, Pilot 4A).
##
## Built from the simulation's own history at the incident's case start, never from anything made up afterwards.
## Two views come out of the same instant:
##   investigation  what the player may see: the hook, people, places, what each resident is willing to say
##                  (text only), the traces and records they can reach, and where they can reach them. No event
##                  ids, belief ids, intents, verdicts or causal links.
##   truth          sealed, developer-only: the incident, its causal chain, the answer, every resident's private
##                  state, and an audit of every statement (accurate, mistaken and why, or a lie and why; open,
##                  guarded or withheld and why; the belief it comes from), every trace and every record line.
## Every statement is rendered from a belief its speaker holds, as they recall it now (sim_memory.gd recollect),
## and is withheld, guarded or told openly as Python decides (self-protection, loyalty, uncertainty). The only
## statements not drawn from a belief are lies, each audited with what it hides: the responsible person's false
## account of where they were, a guilty driver's deer, a fighter who says the other started it.
## Not here yet (Pilot 4B): the suitability verdict, hints and the playable package.
extends RefCounted

const SimClock = preload("res://scripts/sim/sim_clock.gd")
const SimRng = preload("res://scripts/sim/sim_rng.gd")
const SimEvents = preload("res://scripts/sim/sim_events.gd")
const Memory = preload("res://scripts/sim/sim_memory.gd")
const Gossip = preload("res://scripts/sim/sim_gossip.gd")
const Incidents = preload("res://scripts/sim/sim_incidents.gd")
const Crime = preload("res://scripts/sim/sim_crime.gd")
const CaseText = preload("res://scripts/cases/case_text.gd")
const Relevance = preload("res://scripts/cases/case_relevance.gd")

const DAY := 1440
const CASE_SCHEMA := "0.3"
const SCENE_KINDS := ["presence", "sighting", "noise", "intoxicated", "saw_collision", "argument", "assault"]
## How far before the time in question people's first answers reach ("the evening before"). Anything earlier is
## still remembered and told, but only when the investigator asks about earlier times (era "earlier").
const LEAD_IN := 13 * 60
## Everyday sightings at the same place are told as one session while the gaps between them stay below this.
const SESSION_GAP := 2 * 60
const PLAYER_ROLE := ("You grew up here and came back last week after months away, so you were not part of anything "
		+ "that happened. People know you and will talk to you, but you have no official power: you can ask, look "
		+ "around public places, and look at private places or books only if their owners agree.")
const HOOK_MECHANISMS := {
	"money_missing": ["stolen", "accounting_error", "unresolved"],
	"goods_missing": ["stolen", "accounting_error", "unresolved"],
	"person_injured": ["assaulted", "struck_by_vehicle", "accidental_fall", "unresolved"],
	"person_dead": ["assaulted", "struck_by_vehicle", "accidental_fall", "unresolved"],
	"property_damaged": ["vehicle_collision", "vandalism", "unresolved"],
}
## Families whose incidents have someone genuinely responsible for a wrong: the only ones a playable mystery may be
## made from. A fall is nobody's doing; a ledger mistake is no crime; a suspicion is not an incident.
const CRIME_FAMILIES := ["theft", "assault", "collision"]
## Record lines that put a named person at the place where the book is kept, at the time written down.
const PRESENT_IN_RECORDS := ["drink", "pub_meal", "purchase", "credit", "treated", "repair", "ledger_error"]
const FACT_KINDS := ["presence", "sighting", "intoxicated", "argument", "assault", "noise", "saw_collision", "purchase",
		"injury", "struck", "fall", "death"]
## A household's look comes from the work its people do and how houseproud they are, never from this month's troubles.
const STANDING := {"mill_owner": 3, "grocer": 2, "publican": 2, "nurse": 2, "mechanic": 1, "mill_hand": 1,
		"shop_assistant": 1, "barhand": 1, "retiree": 1, "unemployed": 0}
const CONDITION := {3: "fine", 2: "tidy", 1: "plain", 0: "worn"}

var sim
var inc: Dictionary
var now := 0
var case_id := ""
var window := []
var focus := []
var recent_from := 0
var items := {}  # speaker -> [statement]
var meta := {}  # statement key -> {claim, source}: build-time only, never exported
var audit := {}  # statement key (or "W-" + belief id for something withheld) -> what is behind it
var evasive := {}  # speaker -> topics they were evasive about
var chain := []
var R = null  # whoever is responsible, or null
var _count := 0
var _drinks := {}  # rid -> [[time, drinks]]


func _init(sim_, inc_: Dictionary) -> void:
	sim = sim_
	inc = inc_
	now = inc["case_start"]
	case_id = case_id_for(sim, inc)
	var w0: int = inc["window"][0]
	var w1: int = inc["window"][1]
	window = [w0, w1]
	focus = [maxi(w0 - 120, now - 2 * DAY), mini(maxi(w1, w0 + 60), now)]
	recent_from = mini(w0, focus[0]) - LEAD_IN
	R = inc["responsible"]
	chain = _chain()
	for ev in sim.events.events:
		if ev["kind"] == "drink":
			var who: String = ev["actors"][0]
			if not _drinks.has(who):
				_drinks[who] = []
			_drinks[who].append([ev["time"], int(ev["data"].get("drinks", 1))])


static func case_id_for(sim_, inc_: Dictionary) -> String:
	return "%d-%s-%dd-r%d-%s" % [int(sim_.config["seed"]), sim_.config["profile"], int(sim_.config["days"]),
			int(sim_.config["residents"]), inc_["id"]]


static func eligibility(inc_: Dictionary) -> Dictionary:
	## Whether an incident is a case candidate at all (discovered, not owned up to), and whether a playable mystery
	## could ever be made of it (someone genuinely responsible for a crime). A candidate is never a case by itself:
	## Pilot 4B decides whether it is solvable.
	var out := {"candidate": Incidents.is_candidate(inc_), "eligible": false, "reason": ""}
	if inc_["discovered_at"] == null:
		out["reason"] = "nobody has found out about it"
	elif inc_["reported_openly"]:
		out["reason"] = "owned up to on the spot"
	elif inc_["responsible"] == null:
		out["reason"] = "nobody is responsible: %s" % ("a bookkeeping mistake" if inc_["family"] == "accounting_error"
				else "an accident")
	elif not (inc_["family"] in CRIME_FAMILIES) or inc_["outcome"] != "crime":
		out["reason"] = "not a crime"
	else:
		out["eligible"] = true
		out["reason"] = "a %s with someone responsible" % inc_["family"]
	return out


# ================================================================ helpers
func _chain() -> Array:
	## The incident's causal chain up to the case start: what led to it, the act, the linked events, what followed,
	## and the discovery, in time order.
	var core: String = inc["core_event"]
	var ids: Array = ancestors(core) + [core] + Array(inc["related_events"]) + consequences(core, now)
	if inc["discovery_event"] != null:
		ids.append(inc["discovery_event"])
	var pairs := []
	var seen := {}
	for eid in ids:
		if sim.events.by_id.has(eid) and not seen.has(eid) and int(sim.events.by_id[eid]["time"]) <= now:
			seen[eid] = true
			pairs.append([int(sim.events.by_id[eid]["time"]), eid])
	pairs.sort_custom(func(x, y): return _time_then_id(x, y))
	var out := []
	for p in pairs:
		out.append(p[1])
	return out


static func _time_then_id(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	return String(a[1]) < String(b[1])


func ancestors(event_id: String, depth := 6) -> Array:
	var seen := []
	var frontier := [event_id]
	for _i in depth:
		var nxt := []
		for eid in frontier:
			var ev = sim.events.by_id.get(eid)
			if ev == null:
				continue
			for c in ev["causes"]:
				if not (c in seen) and c != event_id:
					seen.append(c)
					nxt.append(c)
		frontier = nxt
	return seen


func consequences(event_id: String, until: int, depth := 3) -> Array:
	var found := []
	var found_set := {}
	var frontier := {event_id: true}
	for _i in depth:
		var nxt := {}
		for ev in sim.events.events:
			if int(ev["time"]) > until or found_set.has(ev["id"]) or ev["id"] == event_id:
				continue
			for c in ev["causes"]:
				if frontier.has(c):
					found.append(ev["id"])
					found_set[ev["id"]] = true
					nxt[ev["id"]] = true
					break
		if nxt.is_empty():
			break
		frontier = nxt
	return found


func _key() -> String:
	_count += 1
	return "K%04d" % _count


static func _sorted_unique(values: Array) -> Array:
	var d := {}
	for v in values:
		if v != null and String(v) != "":
			d[v] = true
	var out: Array = d.keys()
	out.sort()
	return out


func _add(speaker: String, text: String, topics: Array, source: String, time, at, about: Array, guarded: bool,
		aud: Dictionary, group = null, facts := [], claim = null) -> Dictionary:
	if not items.has(speaker):
		items[speaker] = []
	for existing in items[speaker]:
		if existing["text"] == text and existing["guarded"] == guarded:
			existing["topics"] = _sorted_unique(Array(existing["topics"]) + topics)
			return existing
	var k := _key()
	var item := {"key": k, "text": text, "topics": _sorted_unique(topics), "source": source, "time": time,
			"place": at, "about": _sorted_unique(about), "guarded": guarded, "facts": facts}
	if group != null:
		item["group"] = group
	var end = time
	if claim != null and claim["end"] != null:
		end = claim["end"]
	if end != null and int(end) < recent_from:
		item["era"] = "earlier"
	items[speaker].append(item)
	var a := {"speaker": speaker, "source": source}
	a.merge(aud, true)
	audit[k] = a
	if claim != null:
		meta[k] = {"claim": claim, "source": source}
	return item


func _in_focus(t, pad := 6 * 60) -> bool:
	return t != null and focus[0] - pad <= int(t) and int(t) <= now


func _near_scene(c: Dictionary) -> bool:
	if c["start"] == null or c["location"] == null:
		return false
	var end: int = c["end"] if c["end"] != null else c["start"]
	return (end >= int(inc["time"]) - 90 and int(c["start"]) <= int(inc["time"]) + 90
			and sim.world.hops(c["location"], inc["location"]) <= 1)


func _vehicle_of(rid):
	if rid == null or not sim.residents.has(rid):
		return null
	var v: String = sim.residents[rid].vehicle
	return v if v != "" else null


func _rel(r, other: String) -> Dictionary:
	## How ``r`` feels about ``other``, without creating an entry (the simulation goes on after the case freezes).
	return r.rel.get(other, {"trust": 0.5, "affection": 0.4, "resentment": 0.0})


func _drinks_before(rid: String, until: int, hours := 5) -> int:
	var total := 0
	for d in _drinks.get(rid, []):
		if until - hours * 60 <= int(d[0]) and int(d[0]) <= until:
			total += int(d[1])
	return total


# ================================================================ main
func build() -> Dictionary:
	for rid in sim.ids:
		if sim.residents[rid].alive:
			_resident(rid)
			_summarize(rid)
	var consent := _consent()
	var evidence := _evidence()
	var records := _records()
	var vehicles := _vehicles(consent)
	var investigation := _investigation(consent, evidence, records, vehicles)
	var truth := _truth(consent, evidence, records, vehicles)
	truth["relevance"] = Relevance.judge(self, evidence, records)
	var web: Array = Relevance.web(self)
	truth["relevance_web"] = web
	truth["relevance_footprint"] = Relevance.footprint(self, web)
	return {"case_id": case_id, "investigation": investigation, "truth": truth, "eligibility": eligibility(inc)}


# ================================================================ testimony
func _resident(rid: String) -> void:
	var r = sim.residents[rid]
	var anchors := []
	for a in Gossip.anchors_for(sim, rid, now):
		anchors.append([a[0], a[1]])
	anchors.append(window.duplicate())
	var concealing: bool = R == rid and not inc["reported_openly"]
	var witnessed_core := false
	for x in sim.ids:
		if x != rid and sim.perceived.get(x + "|" + String(inc["core_event"])) == "saw":
			witnessed_core = true
	_whereabouts(rid, concealing and not witnessed_core)
	for b in sim.memory[rid].beliefs:
		if int(b["acquired"]) > now:
			continue
		var kept: Array = Memory.recall(b, now, anchors)
		if not kept[0]:
			continue
		var conf: float = kept[1]
		var c: Dictionary = b["claim"]
		if not _relevant(b, c):
			continue
		var rec: Dictionary = Memory.recollect(b, now, SimRng.new([sim.config["seed"], "recall", case_id, b["id"]]))
		var claim: Dictionary = rec["claim"]
		var disc := _disclosure(r, b, claim, conf)
		var disclosure: String = disc[0]
		var reason = disc[1]
		var topics := _topics(rid, b, claim)
		var st := _status(b, claim, rec["error"])
		var status: String = st[0]
		var error = st[1]
		var lie := false
		if b["source"] == "self" and claim["kind"] == "assault" and claim["subject"] == rid:
			if concealing and not witnessed_core:
				disclosure = "withheld"
				reason = "self-protection"
			else:
				status = "lie"
				lie = true
				error = "claims the other person started it"
		if (concealing and not witnessed_core and claim["kind"] == "argument"
				and (rid == claim["subject"] or rid == claim["other"]) and claim["start"] != null
				and absi(int(claim["start"]) - int(inc["time"])) <= 3 * 60):
			disclosure = "withheld"
			reason = "self-protection"
		var aud := {"belief": b["id"], "status": status, "error": error, "disclosure": disclosure,
				"withheld_reason": reason, "supports": _supports(b, claim, status), "event": b["event"], "lie": lie,
				"root": _root(b)}
		if disclosure == "withheld":
			if not evasive.has(rid):
				evasive[rid] = []
			for tp in topics:
				if not (tp in evasive[rid]):
					evasive[rid].append(tp)
			var w := {"speaker": rid, "source": b["source"], "text": CaseText.render(sim, rid, b, claim)}
			w.merge(aud, true)
			audit["W-" + String(b["id"])] = w
			continue
		_add(rid, CaseText.render(sim, rid, b, claim), topics, b["source"], claim["start"], claim["location"],
				[claim["subject"], claim["other"]], disclosure == "guarded", aud, _group(b, claim), _facts(claim), claim)
	if concealing and inc["family"] == "collision" and r.vehicle != "":
		var vname: String = sim.world.vehicles[r.vehicle]["name"]
		_add(rid, CaseText.capitalized(vname) + "? I hit a deer out on the ridge road a few nights back. Gave me a fright.",
				["vehicles", "person:" + rid], "self", null, null, [rid], false,
				{"belief": null, "status": "lie", "error": "invented a deer to explain the damage", "disclosure": "open",
				"withheld_reason": null, "supports": [], "event": null, "lie": true, "about_event": inc["core_event"]})


func _root(b: Dictionary) -> String:
	## Who originally perceived this? Hearsay is only as independent as its source.
	var seen := 0
	while b["source"] == "told" and b["via"] != null and sim.beliefs.has(b["via"]) and seen < 20:
		b = sim.beliefs[b["via"]]
		seen += 1
	return b["holder"]


func _relevant(b: Dictionary, c: Dictionary) -> bool:
	var k: String = c["kind"]
	if k in ["theft_self", "stash"]:
		return true  # always withheld, but audited
	if k in SCENE_KINDS or k == "purchase":
		return _in_focus(c["start"])
	if k in ["debt", "grudge", "laid_off"]:
		return k != "debt" or c["detail"] != "repaid" or now - int(b["acquired"]) <= 7 * DAY
	return now - int(b["acquired"]) <= 7 * DAY


func _incriminates_self(r, b: Dictionary, c: Dictionary) -> bool:
	var k: String = c["kind"]
	if k in ["theft_self", "stash"]:
		return true
	if k == "collision_self":
		var own: Dictionary = Incidents.incident_for(sim, b["event"])
		return own.is_empty() or not own["reported_openly"]
	var guilty_times := []
	for g in r.guilty_of:
		if int(sim.events.by_id[g]["time"]) <= now:
			guilty_times.append(int(sim.events.by_id[g]["time"]))
	if guilty_times.is_empty():
		return false
	if k == "vehicle_damage" and c["obj"] != null and c["obj"] == r.vehicle:
		return true
	if c["subject"] == r.id and k in ["presence", "sighting", "intoxicated", "saw_collision", "suspect", "repair"]:
		if k == "suspect":
			return true
		for gt in guilty_times:
			if c["start"] != null and absi(int(c["start"]) - gt) <= 3 * 60:
				return true
	return false


func _disclosure(r, b: Dictionary, c: Dictionary, conf: float) -> Array:
	## [open | guarded | withheld, why]. People keep quiet about their own wrongdoing, protect those they love (an
	## honest one by hedging, a less honest one by saying nothing), and hedge what they are unsure of.
	if _incriminates_self(r, b, c):
		return ["withheld", "self-protection"]
	var protected = c["subject"] if c["subject"] != null and c["subject"] != r.id else null
	if c["obj"] != null and sim.world.vehicles.has(c["obj"]):
		var hh: String = sim.world.vehicles[c["obj"]]["household"]
		if hh != r.household:
			if protected == null:
				protected = sim.households[hh][0]
		elif c["kind"] == "vehicle_damage" and protected == null:
			protected = r.id
	if (protected != null and protected != r.id and float(_rel(r, protected)["affection"]) >= 0.75
			and c["kind"] in ["presence", "sighting", "intoxicated", "vehicle_damage", "suspect", "assault", "saw_collision"]):
		if c["kind"] in ["presence", "intoxicated"] and not _in_focus(c["start"], 0):
			pass
		elif float(r.traits["honesty"]) >= 0.55:
			return ["guarded", "loyalty"]
		else:
			return ["withheld", "loyalty"]
	if conf < 0.45:
		return ["guarded", "unsure"]
	return ["open", null]


func _topics(speaker: String, b: Dictionary, c: Dictionary) -> Array:
	var k: String = c["kind"]
	var topics := []
	for p in [c["subject"], c["other"]]:
		if p != null and p != speaker:
			topics.append("person:" + String(p))
	if c["obj"] != null and sim.world.vehicles.has(c["obj"]):
		for m in sim.households[sim.world.vehicles[c["obj"]]["household"]]:
			if m != speaker:
				topics.append("person:" + String(m))
	if k in SCENE_KINDS and c["start"] != null:
		var end: int = c["end"] if c["end"] != null else c["start"]
		if end >= int(window[0]) - 120 and int(c["start"]) <= int(window[1]) + 60:
			topics.append("window")
	if k in ["debt", "hardship", "refusal", "loan", "rent_missed", "help", "laid_off"]:
		topics.append("money")
	if k in ["argument", "assault", "grudge", "reconcile", "confession"]:
		topics.append("conflicts")
	if k in ["loss", "damage", "injury", "struck", "death", "fall", "suspect", "confession", "collision_self"]:
		topics.append("incident" if _about_this_case(c) else "past")
	if k in ["vehicle_damage", "saw_collision", "repair", "collision_self"] or (k == "sighting" and c["obj"] != null):
		topics.append("vehicles")
	if c["location"] == inc["location"] and k in SCENE_KINDS and "window" in topics:
		topics.append("incident")
	if b["source"] == "told":
		topics.append("rumors")
	if k == "purchase":
		topics.append("whereabouts")
	if topics.is_empty():
		topics.append("other")
	return topics


func _about_this_case(c: Dictionary) -> bool:
	if c["start"] == null:
		return false
	var end: int = c["end"] if c["end"] != null else c["start"]
	if c["kind"] in ["injury", "death", "struck", "fall"] and (c["subject"] == null or c["subject"] in inc["victims"]):
		return end >= int(window[0]) - 13 * 60
	var near: bool = c["location"] == null or sim.world.hops(c["location"], inc["location"]) <= 1
	return near and end >= int(window[0]) - 13 * 60 and int(c["start"]) <= int(window[1]) + 6 * 60


func _status(b: Dictionary, c: Dictionary, err) -> Array:
	## [accurate | mistaken | unverifiable, what went wrong]: developer-only, judged against the event log.
	if c["kind"] == "suspect":
		var target := incident_for_claim(c)
		if target.is_empty():
			return ["unverifiable", null]
		return ["accurate", null] if target["responsible"] == c["subject"] else ["mistaken", "wrong suspect"]
	if c["kind"] in ["presence", "sighting"] and c["subject"] == null:
		return ["unverifiable", null]
	var error = err if err != null else b["error"]
	if c["kind"] in ["presence", "sighting"] and c["subject"] != null:
		var ok := true
		if c["start"] != null:
			ok = false
			var end: int = c["end"] if c["end"] != null else c["start"]
			for m in range(int(c["start"]) - 20, end + 21, 10):
				if sim.where(c["subject"], m) == c["location"]:
					ok = true
					break
		if not ok:
			return ["mistaken", error if error != null else "wrong person or time"]
		if error == "misremembered_time":
			return ["accurate", null]  # still placed correctly within tolerance
	if error != null:
		return ["mistaken", error]
	return ["accurate", null]


func incident_for_claim(c: Dictionary) -> Dictionary:
	## The incident at the claim's place within its time (13 hours before to 6 hours after), or {}.
	for other in sim.incidents:
		if other["location"] == c["location"] and c["start"] != null and int(other["time"]) <= now:
			var end: int = c["end"] if c["end"] != null else c["start"]
			if int(c["start"]) - 13 * 60 <= int(other["time"]) and int(other["time"]) <= end + 6 * 60:
				return other
	return {}


func _supports(b: Dictionary, c: Dictionary, status: String) -> Array:
	## What an accurate statement shows about the incident (developer-only, for Pilot 4B's solvability check), or
	## that an inaccurate one points away from the truth.
	var out := []
	var fam: String = inc["family"]
	var veh_R = _vehicle_of(R)
	if R != null and status == "accurate":
		var names_R: bool = c["subject"] == R or (c["obj"] != null and c["obj"] == veh_R)
		if names_R and c["kind"] in SCENE_KINDS and _near_scene(c):
			out.append("places_responsible")
		if names_R and b["event"] == inc["core_event"] and b["source"] == "saw":
			out.append("act")
		if names_R and c["kind"] in ["vehicle_damage", "repair"] and fam == "collision":
			out.append("vehicle")
		if c["subject"] == R and c["kind"] in ["debt", "hardship", "refusal", "rent_missed", "grudge"]:
			out.append("motive")
		if c["kind"] == "suspect" and c["subject"] == R:
			out.append("suspicion_correct")
		if (c["subject"] == R and c["kind"] == "debt" and c["detail"] == "repaid" and c["start"] != null
				and fam == "theft" and int(inc["time"]) <= int(c["start"]) and int(c["start"]) <= int(inc["time"]) + 3 * DAY):
			out.append("sudden_money")
		if c["subject"] == R and c["kind"] == "noise" and _near_scene(c):
			out.append("places_responsible")
		var home_R: String = sim.residents[R].home
		var detail: String = c["detail"]
		if (c["subject"] == R and c["location"] == home_R and c["kind"] in ["noise", "sighting"] and c["start"] != null
				and ("going out" in detail or "coming in" in detail or detail in ["heading out", "coming home"])
				and absi(int(c["start"]) - int(inc["time"])) <= 90):
			out.append("absence")
		if c["kind"] == "intoxicated" and c["subject"] == R and fam == "collision" and _near_scene(c):
			out.append("places_responsible")
	if status != "accurate" and c["subject"] != null and c["subject"] != R and c["start"] != null:
		if c["kind"] in SCENE_KINDS and _near_scene(c):
			out.append("misleading")
	if c["kind"] == "suspect" and c["subject"] != null and c["subject"] != R:
		out.append("misleading")
	if fam == "accounting_error" and c["kind"] == "purchase" and status == "accurate":
		var dup_sales := {}
		for e in [inc["core_event"]] + Array(inc["related_events"]):
			if sim.events.by_id.has(e) and sim.events.by_id[e]["kind"] == "ledger_error":
				dup_sales[sim.events.by_id[e]["causes"][0]] = true
		if dup_sales.has(b["event"]):
			out.append("mechanism")
	if fam == "fall" and status == "accurate":
		if c["kind"] == "fall" or (c["kind"] in ["intoxicated", "sighting"] and c["subject"] in inc["victims"]
				and _near_scene(c)):
			out.append("mechanism")
	if (fam == "collision" and status == "accurate" and c["kind"] in ["struck", "noise", "saw_collision"]
			and c["location"] == "road" and _near_scene(c)):
		out.append("mechanism")
	if fam == "assault" and status == "accurate" and c["kind"] == "assault" and b["event"] == inc["core_event"]:
		out.append("mechanism")
	return out


# ================================================================ summaries
func _summarize(rid: String) -> void:
	## Everyday information told the way people tell it ("I saw Ana, Ben and Cat at the pub that evening", "from what
	## I hear, half the town owes the grocer"). Each summary is a statement of its own; the statements it stands for
	## stay as its members, word for word. Only open, everyday information is summarized.
	var groups := {}
	var order := []
	for it in items.get(rid, []):
		var m = meta.get(it["key"])
		if m == null or it["guarded"] or audit[it["key"]].get("lie", false):
			continue
		var told_alone := true
		for tp in it["topics"]:
			if not String(tp).begins_with("person:") and tp != "other":
				told_alone = false
		if told_alone:
			continue
		var c: Dictionary = m["claim"]
		var src: String = m["source"]
		var era: String = it.get("era", "recent")
		var party := [c["subject"], c["other"]]
		var key = null
		var detail: String = c["detail"]
		var everyday: bool = c["kind"] in ["presence", "intoxicated"] or (c["kind"] == "sighting" and c["obj"] == null
				and detail.begins_with("heading toward") and not ("unsteady" in detail)
				and sim.world.locations[c["location"]]["outdoor"])
		if (everyday and src == "saw" and c["subject"] != null and c["subject"] != rid and not c["hedged"]
				and c["location"] != null and c["start"] != null):
			var sig := []
			for tp in it["topics"]:
				if not String(tp).begins_with("person:"):
					sig.append(tp)
			sig.sort()
			key = ["seen", era, ",".join(PackedStringArray(sig)), c["location"]]
		elif c["kind"] == "debt" and c["subject"] != null and c["other"] != null and not (rid in party) and src in ["told", "saw"]:
			key = ["repaid" if detail == "repaid" else "owing", era, "", c["other"]]
		elif c["kind"] == "debt" and src == "self" and c["other"] == rid and c["subject"] != null:
			key = ["repaid_me" if detail == "repaid" else "owed_me", era, "", rid]
		elif c["kind"] == "refusal" and c["subject"] != null and c["other"] != null and not (rid in party) and src in ["told", "saw"]:
			key = ["refused", era, "", c["other"]]
		elif c["kind"] == "suspect" and src == "told" and c["subject"] != null and detail != "":
			key = ["suspected", era, "", detail]
		elif c["kind"] == "refusal" and src == "self" and c["other"] == rid and c["subject"] != null:
			key = ["i_asked", era, "", rid]
		elif src == "self" and c["subject"] != null and ((c["kind"] == "refusal" and c["subject"] == rid and c["other"] != null)
				or (c["kind"] == "hardship" and c["subject"] != rid)):
			key = ["asked_me", era, "", rid]
		if key != null:
			var gk := "|".join(PackedStringArray([key[0], key[1], key[2], String(key[3])]))
			if not groups.has(gk):
				groups[gk] = {"key": key, "members": []}
				order.append(gk)
			groups[gk]["members"].append(it)
	for gk in order:
		var key: Array = groups[gk]["key"]
		var members: Array = groups[gk]["members"]
		if key[0] != "seen":
			if members.size() >= 2:
				_add_summary(rid, key, members)
			continue
		var by_time := []
		for it in members:
			by_time.append([int(it["time"]), it["key"], it])
		by_time.sort_custom(func(x, y): return _time_then_id(x, y))
		var session := []
		var last_end = null
		for i in by_time.size() + 1:
			var it = by_time[i][2] if i < by_time.size() else null
			var c = meta[it["key"]]["claim"] if it != null else null
			if it == null or (last_end != null and int(c["start"]) - int(last_end) > SESSION_GAP):
				if session.size() >= 2:
					_add_summary(rid, key, session)
				session = []
				last_end = null
			if it != null:
				session.append(it)
				var end: int = c["end"] if c["end"] != null else c["start"]
				last_end = end if last_end == null else maxi(int(last_end), end)


func _firsts(ids: Array) -> Array:
	var names := {}
	for x in ids:
		if x != null and String(x) != "":
			names[sim.residents[x].first] = true
	var out: Array = names.keys()
	out.sort()
	return out


func _add_summary(rid: String, key: Array, members: Array) -> void:
	var kind: String = key[0]
	var era: String = key[1]
	var claims := []
	var sources := {}
	for it in members:
		claims.append(meta[it["key"]]["claim"])
		sources[meta[it["key"]]["source"]] = true
	var source := "saw"
	if sources.size() == 1 and sources.has("told"):
		source = "told"
	elif sources.size() == 1 and sources.has("self"):
		source = "self"
	var voice: String = sources.keys()[0] if sources.size() == 1 else "mixed"
	var sig_set := {}
	for it in members:
		for tp in it["topics"]:
			if not String(tp).begins_with("person:"):
				sig_set[tp] = true
	if kind in ["owing", "repaid", "refused"]:
		sig_set["person:" + String(key[3])] = true
	var sig: Array = sig_set.keys()
	sig.sort()
	var subjects := []
	var others := []
	var late := []
	var drunk := []
	for c in claims:
		subjects.append(c["subject"])
		others.append(c["other"])
		if c["kind"] == "debt" and c["detail"] == "overdue":
			late.append(c["subject"])
		if c["kind"] == "intoxicated":
			drunk.append(c["subject"])
	var at = null
	var text := ""
	if kind == "seen":
		at = key[3]
		var start := 1 << 40
		var end := 0
		for c in claims:
			start = mini(start, int(c["start"]))
			end = maxi(end, int(c["end"]) if c["end"] != null else int(c["start"]))
		text = CaseText.summary_text("seen", voice, _firsts(subjects), "", sim.world.name_of(at),
				CaseText.fmt_span(start, end), _firsts(drunk))
	elif kind == "asked_me":
		var asked := []
		var refused := []
		for c in claims:
			asked.append(c["other"] if c["kind"] == "refusal" else c["subject"])
			if c["kind"] == "refusal":
				refused.append(c["other"])
		text = CaseText.summary_text("asked_me", voice, _firsts(asked), "", "", "", _firsts(refused), era)
	elif kind == "i_asked":
		text = CaseText.summary_text("i_asked", voice, _firsts(subjects), "", "", "", [], era)
	elif kind in ["owed_me", "repaid_me"]:
		text = CaseText.summary_text(kind, voice, _firsts(subjects), "", "", "", _firsts(late), era)
	elif kind == "suspected":
		text = CaseText.summary_text("suspected", voice, _firsts(subjects), String(key[3]))
	elif kind == "refused":
		text = CaseText.summary_text("refused", voice, _firsts(subjects), sim.residents[key[3]].first, "", "", [], era)
	else:
		text = CaseText.summary_text(kind, voice, _firsts(subjects), sim.residents[key[3]].first, "", "", _firsts(late), era)
	var times := []
	var facts := []
	var about := []
	var keys := []
	for it in members:
		if it["time"] != null:
			times.append(int(it["time"]))
		for f in it["facts"]:
			if not (f in facts):
				facts.append(f)
		for a in it["about"]:
			if a != rid:
				about.append(a)
		keys.append(it["key"])
	var k := _key()
	var item := {"key": k, "text": text, "topics": sig, "source": source, "time": times.min() if not times.is_empty() else null,
			"place": at, "about": _sorted_unique(about), "guarded": false, "facts": facts, "members": keys}
	if era == "earlier":
		item["era"] = "earlier"
	for it in members:
		it["in"] = k
	items[rid].append(item)
	var statuses := []
	var supports := {}
	var first_error = null
	for it in members:
		var a: Dictionary = audit[it["key"]]
		statuses.append(a["status"])
		if a["status"] == "mistaken" and first_error == null:
			first_error = a["error"] if a["error"] != null else "wrong"
		if a["status"] == "accurate":
			for sp in a.get("supports", []):
				supports[sp] = true
	var status := "accurate"
	var error = null
	if "mistaken" in statuses:
		status = "mistaken"
		error = "partly wrong: " + String(first_error)
	else:
		var all_unverifiable := true
		for s in statuses:
			if s != "unverifiable":
				all_unverifiable = false
		if all_unverifiable:
			status = "unverifiable"
	var sp_list: Array = supports.keys()
	sp_list.sort()
	audit[k] = {"speaker": rid, "source": source, "belief": null, "status": status, "error": error,
			"disclosure": "open", "withheld_reason": null, "supports": sp_list, "event": null, "lie": false,
			"root": rid, "summary": true, "members": keys.duplicate()}


# ================================================================ whereabouts
func _whereabouts(rid: String, lie: bool) -> void:
	## The resident's own account of where they were around the time in question: the plain answer and, filed
	## behind it, every move with its times. Someone responsible who was not seen at it moves themselves away
	## from the scene, a lie audited with the truth it hides.
	var a: int = focus[0]
	var b: int = focus[1]
	if b - a < 60:
		return
	var segs := CaseText.segments(sim, rid, a, b)
	if segs.is_empty():
		return
	var home: String = sim.residents[rid].home
	var hazy = null
	for sg in segs:
		if _drinks_before(rid, sg[2]) >= 4 and sg[0] != home:
			hazy = sg[2]
			break
	var keep := []
	if inc["hook_place"] != null and sim.world.locations.has(inc["hook_place"]):
		keep.append(inc["hook_place"])
	var truth_text := CaseText.describe_segments(sim, rid, segs, hazy)
	var short := CaseText.concise_segments(sim, segs, keep)
	var short_text := CaseText.describe_concise(sim, rid, short, hazy)
	var merged := []
	if lie:
		var ct: int = inc["time"]
		var fake := []
		for sg in segs:
			var overlaps: bool = int(sg[1]) < ct + 45 and int(sg[2]) > ct - 45 and sg[0] != home
			if not fake.is_empty() and (fake[-1][0] == sg[0] or overlaps):
				fake[-1][2] = sg[2]
			else:
				fake.append([sg[0], sg[1], sg[2]])
		for sg in fake:
			if not merged.is_empty() and merged[-1][0] == sg[0]:
				merged[-1][2] = sg[2]
			else:
				merged.append([sg[0], sg[1], sg[2]])
		# Someone openly where it happened has nothing in their movements to hide: their account is simply true.
		lie = not same_story(CaseText.concise_segments(sim, merged, keep), short)
	if not lie:
		var plain := _add(rid, short_text, ["whereabouts"], "self", a, null, [rid], false, _account_audit(rid, short), null,
				segment_facts(rid, short))
		var exact := _add(rid, truth_text, ["whereabouts"], "self", a, null, [rid], false, _account_audit(rid, segs), null,
				segment_facts(rid, segs))
		_file_behind(plain, exact)
		return
	var fake_short := CaseText.concise_segments(sim, merged, keep)
	var told_plain := _add(rid, CaseText.describe_concise(sim, rid, fake_short, null), ["whereabouts"], "self", a, null,
			[rid], false, _lie_audit(fake_short, short, short_text), null, segment_facts(rid, fake_short))
	var told_exact := _add(rid, CaseText.describe_segments(sim, rid, merged, null), ["whereabouts"], "self", a, null,
			[rid], false, _lie_audit(merged, segs, truth_text), null, segment_facts(rid, merged))
	_file_behind(told_plain, told_exact)


func _account_audit(rid: String, sg: Array) -> Dictionary:
	var supports := []
	if rid in inc["victims"] and inc["family"] == "fall":
		supports.append("mechanism")
	return {"belief": null, "status": "accurate", "error": null, "disclosure": "open", "withheld_reason": null,
			"supports": supports, "event": null, "lie": false, "segments": sg.duplicate(true)}


func _lie_audit(sg: Array, true_sg: Array, true_text: String) -> Dictionary:
	return {"belief": null, "status": "lie", "error": "hid where they really were", "disclosure": "open",
			"withheld_reason": null, "supports": ["responsible_lie"], "event": null, "lie": true,
			"segments": sg.duplicate(true), "true_segments": true_sg.duplicate(true), "true_text": true_text}


func _file_behind(plain: Dictionary, exact: Dictionary) -> void:
	## The exact account is told when asked for more; the plain one stands in front of it.
	if is_same(plain, exact):
		return
	plain["members"] = [exact["key"]]
	exact["in"] = plain["key"]
	audit[exact["key"]]["exact_of"] = plain["key"]  # the same account told in full: counted once


# ================================================================ access
func _consent() -> Dictionary:
	## Who lets the investigator look where. Public places are open; an owner hiding a trace of their own doing
	## refuses, and so does a very private household.
	var out := {}
	for loc_id in sim.world.locations:
		var loc: Dictionary = sim.world.locations[loc_id]
		if loc["kind"] in ["square", "road"]:
			out[loc_id] = {"allowed": true, "by": null, "reply": "It's a public place."}
			continue
		var owners := []
		for o in loc["owners"]:
			if sim.residents[o].alive:
				owners.append(o)
		if owners.is_empty():
			out[loc_id] = {"allowed": true, "by": null, "reply": "Nobody objects."}
			continue
		var traces: Array = sim.world.evidence_at(loc_id, now)
		for vid in sim.world.vehicles:
			if sim.world.vehicles[vid]["location"] == loc_id:
				traces += sim.world.evidence_at(vid, now)
		var hiding := []
		for o in owners:
			for e in traces:
				if Crime.made_by(sim, o, e):
					hiding.append(o)
					break
		var private := true
		for o in owners:
			if float(sim.residents[o].traits["sociability"]) >= 0.3:
				private = false
		var speaker: String = hiding[0] if not hiding.is_empty() else owners[0]
		var first: String = sim.residents[speaker].first
		if not hiding.is_empty():
			out[loc_id] = {"allowed": false, "by": speaker, "reply": "%s: \"No. I don't see why you'd need to.\"" % first}
		elif private and loc["kind"] == "home":
			out[loc_id] = {"allowed": false, "by": speaker,
					"reply": "%s: \"I'd rather you didn't. We keep ourselves to ourselves.\"" % first}
		else:
			out[loc_id] = {"allowed": true, "by": speaker, "reply": "%s: \"Go ahead, if it helps.\"" % first}
	return out


func _evidence() -> Dictionary:
	## Every trace still there at the case start, by where it is (a place or a vehicle).
	var out := {}
	for e in sim.world.evidence:
		if not sim.world.present_at(e, now):
			continue
		if not out.has(e["place"]):
			out[e["place"]] = []
		out[e["place"]].append(e)
	return out


func _records() -> Dictionary:
	## The last four days of every book, up to the case start.
	var out := {}
	for book in sim.world.books:
		var entries := []
		for x in sim.world.records[book]:
			if now - 4 * DAY <= int(x["time"]) and int(x["time"]) <= now:
				entries.append(x)
		out[book] = {"place": sim.world.books[book]["place"], "title": sim.world.books[book]["title"], "entries": entries}
	return out


func _vehicles(consent: Dictionary) -> Dictionary:
	var out := {}
	for vid in sim.world.vehicles:
		var v: Dictionary = sim.world.vehicles[vid]
		var where_: String = v["location"]
		var loc: Dictionary = sim.world.locations[where_]
		var allowed := true
		var reply := "It's parked at %s where anyone can see it." % loc["name"]
		if loc["kind"] == "home":
			allowed = consent[where_]["allowed"]
			reply = consent[where_]["reply"]
		out[vid] = {"name": v["name"], "kind": v["kind"], "household": v["household"], "location": where_,
				"allowed": allowed, "reply": reply}
	return out


# ================================================================ the investigator's view
func _investigation(consent: Dictionary, evidence: Dictionary, records: Dictionary, vehicles: Dictionary) -> Dictionary:
	var residents := []
	for rid in sim.ids:
		var r = sim.residents[rid]
		var condition := "alive" if r.alive else "deceased"
		if r.alive and r.injury > 0:
			condition = "injured"
		residents.append({"id": rid, "name": r.full_name(), "first": r.first, "occupation": r.occupation,
				"age_group": r.age_group, "household": r.household, "home": r.home, "condition": condition,
				"now_at": sim.where(rid, now) if r.alive else null, "role": r.role, "demeanour": demeanour(r)})
	var places := []
	var loc_ids: Array = sim.world.locations.keys()
	loc_ids.sort()
	for loc_id in loc_ids:
		var loc: Dictionary = sim.world.locations[loc_id]
		var c: Dictionary = consent[loc_id]
		var p := {"id": loc_id, "name": loc["name"], "kind": loc["kind"], "owners": Array(loc["owners"]).duplicate(),
				"allowed": c["allowed"], "reply": c["reply"], "traces": _visible_traces(evidence, loc_id, c["allowed"])}
		if loc["kind"] == "home":
			p["look"] = house_look(loc)
		places.append(p)
	var veh_out := []
	var vids: Array = vehicles.keys()
	vids.sort()
	for vid in vids:
		var v: Dictionary = vehicles[vid]
		veh_out.append({"id": vid, "name": v["name"], "kind": v["kind"], "household": v["household"],
				"location": v["location"], "allowed": v["allowed"], "reply": v["reply"],
				"traces": _visible_traces(evidence, vid, v["allowed"])})
	var rec_out := {}
	for book in records:
		var data: Dictionary = records[book]
		var c: Dictionary = consent[data["place"]]
		var entries := []
		if c["allowed"]:
			for x in data["entries"]:
				entries.append({"id": "R-" + String(x["id"]), "time": x["time"], "text": x["text"],
						"facts": _record_facts(x, data["place"])})
		rec_out[book] = {"title": data["title"], "place": data["place"], "allowed": c["allowed"], "reply": c["reply"],
				"entries": entries}
	var testimony := {}
	for rid in sim.ids:
		var r = sim.residents[rid]
		if not r.alive:
			continue
		var ev_topics: Array = Array(evasive.get(rid, [])).duplicate()
		ev_topics.sort()
		testimony[rid] = {"goodwill": 2 + int(float(r.traits["sociability"]) * 3),
				"style": "nervous" if float(r.traits["honesty"]) >= 0.6 else "smooth",
				"items": items.get(rid, []), "evasive_topics": ev_topics}
	var mechanisms := []
	for m in HOOK_MECHANISMS[inc["hook_kind"]]:
		mechanisms.append({"id": m, "label": Incidents.MECHANISM_LABELS[m]})
	var motives := []
	for k in Incidents.MOTIVES:
		motives.append({"id": k, "label": Incidents.MOTIVES[k]})
	return {
		"schema": "investigation/" + CASE_SCHEMA,
		"case_id": case_id,
		"versions": {"sim": "godot-native", "config": "godot-native"},
		"town": sim.world.town_name,
		"start_time": now,
		"start_label": SimClock.fmt(now),
		"player_role": PLAYER_ROLE,
		"hook": {"title": inc["title"], "text": inc["hook_text"], "kind": inc["hook_kind"], "place": inc["hook_place"],
				"window": window.duplicate(), "window_label": CaseText.fmt_span(window[0], window[1]),
				"discovered_by": inc["discovered_by"], "recent_from": recent_from},
		"residents": residents,
		"places": places,
		"vehicles": veh_out,
		"records": rec_out,
		"testimony": testimony,
		"theory_options": {"mechanisms": mechanisms, "motives": motives},
		"hints": [],  # Pilot 4B: grounded hints come with the suitability check
		"hint_credits": 6,
	}


static func _visible_traces(evidence: Dictionary, where_: String, allowed: bool) -> Array:
	var out := []
	if allowed:
		for e in evidence.get(where_, []):
			out.append({"id": "T-" + String(e["id"]), "description": e["description"]})
	return out


func _record_facts(x: Dictionary, at: String) -> Array:
	## A line that names one person who had to be there (a drink on the tab, a sale, a patient, a car brought in)
	## puts them at the book's place at the time written down. This is what the line itself says.
	var ev: Dictionary = sim.events.by_id[x["event"]]
	if not (ev["kind"] in PRESENT_IN_RECORDS):
		return []
	var named := []
	for rid in sim.ids:
		if sim.residents[rid].full_name() in String(x["text"]):
			named.append(rid)
	if named.size() != 1:
		return []
	return [{"who": named[0], "place": at, "from": x["time"], "to": x["time"], "hedged": false}]


# ================================================================ the sealed truth
func _truth(consent: Dictionary, evidence: Dictionary, records: Dictionary, vehicles: Dictionary) -> Dictionary:
	var by_id: Dictionary = sim.events.by_id
	var chain_events := []
	for e in chain:
		chain_events.append(by_id[e].duplicate(true))
	var movements := []
	var scene := []
	var in_chain := {}
	for e in chain:
		in_chain[e] = true
	for ev in sim.events.events:
		var t: int = ev["time"]
		if R != null and ev["kind"] == "move" and R in ev["actors"] and focus[0] - 60 <= t and t <= now:
			movements.append(ev.duplicate(true))
		if ev.get("notable", false) and int(window[0]) - 6 * 60 <= t and t <= now and not in_chain.has(ev["id"]):
			scene.append(ev.duplicate(true))
	var evidence_audit := {}
	for at in evidence:
		for e in evidence[at]:
			var src: Dictionary = by_id[e["created_by"]]
			var on_vehicle: bool = sim.world.vehicles.has(at)
			var allowed: bool = vehicles[at]["allowed"] if on_vehicle else consent[at]["allowed"]
			var refused_by = null
			if not allowed:
				refused_by = consent[sim.world.vehicles[at]["location"]]["by"] if on_vehicle else consent[at]["by"]
			var noticed := []
			for x in e["noticed_by"]:
				noticed.append(x)
			evidence_audit["T-" + String(e["id"])] = {"place": at, "kind": e["kind"], "created_by": e["created_by"],
					"created_at": e["created_at"], "event_summary": src["summary"], "implicates": Array(e["implicates"]).duplicate(),
					# where and how it can be found: on view, or only with the owner's leave, which was refused
					"on_vehicle": on_vehicle, "visible": allowed, "refused_by": refused_by, "noticed_by": noticed}
	var record_audit := {}
	for book in records:
		for x in records[book]["entries"]:
			var src: Dictionary = by_id[x["event"]]
			record_audit["R-" + String(x["id"])] = {"event": x["event"], "event_kind": src["kind"],
					"event_summary": src["summary"], "book": book, "visible": consent[records[book]["place"]]["allowed"]}
	var motives := [inc["motive"]]
	if inc["family"] in ["assault", "collision"] and R != null:
		for e in chain:
			if by_id[e]["kind"] == "drink" and R in by_id[e]["actors"] and not ("intoxication" in motives):
				motives.append("intoxication")
	if inc["fled"] and not ("panic" in motives):
		motives.append("panic")
	var private := {}
	for rid in sim.ids:
		var r = sim.residents[rid]
		var guilty := []
		for g in r.guilty_of:
			if int(by_id[g]["time"]) <= now:
				guilty.append(g)
		var debts := []
		for d in sim.world.debts:
			if (d["debtor"] == rid or d["creditor"] == rid) and int(d["created"]) <= now \
					and (int(d["settled"]) < 0 or now < int(d["settled"])):
				debts.append(d.duplicate(true))
		private[rid] = {"name": r.full_name(), "alive": r.alive, "traits": r.traits.duplicate(), "cash": r.cash,
				"stress": snappedf(r.stress, 0.1), "guilty_of": guilty, "debts": debts,
				"pressure": sim.pressure.get(rid)}
	var others := []
	for other in sim.incidents:
		if other["id"] != inc["id"] and int(other["time"]) <= now:
			others.append(other.duplicate(true))
	var names := {}
	for k in sim.world.locations:
		names[k] = sim.world.locations[k]["name"]
	for k in sim.world.vehicles:
		names[k] = sim.world.vehicles[k]["name"]
	for k in sim.world.books:
		names[k] = sim.world.books[k]["title"]
	var counted := 0
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	for ev in sim.events.events:
		if int(ev["time"]) <= now:
			h.update((SimEvents.line(ev) + "\n").to_utf8_buffer())
			counted += 1
	return {
		"schema": "truth/" + CASE_SCHEMA,
		"case_id": case_id,
		"config": sim.config.duplicate(),
		"town": sim.world.town_name,
		"case_start": now,
		"incident": inc.duplicate(true),
		"eligibility": eligibility(inc),
		"place_names": names,
		"answer": {"mechanism": inc["mechanism"], "responsible": R, "outcome": inc["outcome"], "motives": motives},
		"narrative": narrative(sim, inc),
		"chain": chain_events,
		"responsible_movements": movements,
		"other_notable": scene,
		"testimony_audit": audit,
		"evidence_audit": evidence_audit,
		"record_audit": record_audit,
		"private_states": private,
		"other_incidents": others,
		"event_log_digest": h.finish().hex_encode(),
		"event_count": counted,
	}


# ================================================================ what anyone can see
static func demeanour(r) -> String:
	## How someone comes across when you talk to them. Only traits that play no part in deciding to steal, fight
	## or drive drunk show in a face or a house.
	var t: Dictionary = r.traits
	if float(t["stubbornness"]) >= 0.65:
		return "gruff"
	if float(t["sociability"]) >= 0.62:
		return "cheerful"
	if float(t["sociability"]) < 0.35:
		return "reserved"
	if float(t["diligence"]) >= 0.62:
		return "brisk"
	return "easygoing"


func house_look(loc: Dictionary) -> Dictionary:
	var members := []
	for m in sim.households.get(loc["household"], []):
		if sim.residents.has(m):
			members.append(sim.residents[m])
	var standing := 1
	var diligence := 0.0
	var trades := {}
	if not members.is_empty():
		standing = 0
		for m in members:
			standing = maxi(standing, int(STANDING.get(m.role, 1)))
			diligence += float(m.traits["diligence"])
			trades[m.role] = true
	var trade_list: Array = trades.keys()
	trade_list.sort()
	return {"style": loc["household"], "condition": CONDITION[standing],
			"garden": "neat" if diligence / maxf(1.0, float(members.size())) >= 0.5 else "wild", "trades": trade_list}


static func _facts(c: Dictionary) -> Array:
	## Where the statement *claims* someone was, for the player's timeline: built from the claim as recalled
	## (shifted times, misidentifications and all), so it is exactly as safe as the sentence itself.
	if not (c["kind"] in FACT_KINDS) or c["start"] == null or c["location"] == null:
		return []
	var who := []
	if c["kind"] in ["struck", "injury", "death"]:
		who.append(c["other"] if c["other"] != null else c["subject"])
	else:
		who.append(c["subject"])
	if c["kind"] in ["argument", "assault"]:
		who.append(c["other"])
	var end = c["end"] if c["end"] != null else c["start"]
	var out := []
	for w in who:
		if w != null:
			out.append({"who": w, "place": c["location"], "from": c["start"], "to": end, "hedged": bool(c["hedged"])})
	return out


static func same_story(a: Array, b: Array, slack := 20) -> bool:
	## The same places in the same order, at times that differ by no more than a few minutes.
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i][0] != b[i][0] or absi(int(a[i][1]) - int(b[i][1])) > slack or absi(int(a[i][2]) - int(b[i][2])) > slack:
			return false
	return true


static func segment_facts(rid: String, segs: Array) -> Array:
	var out := []
	for sg in segs:
		out.append({"who": rid, "place": sg[0], "from": sg[1], "to": sg[2], "hedged": false})
	return out


func _group(b: Dictionary, c: Dictionary):
	## Lets the dialogue say "I saw Ana, Ben and Cat at the pub ..." instead of three lines.
	if b["source"] != "saw" or c["subject"] == null or not (c["kind"] in ["presence", "intoxicated"]) or c["start"] == null:
		return null
	var percept: String = CaseText.phrases(sim, c)[0]
	var name: String = sim.residents[c["subject"]].first
	if not percept.begins_with(name):
		return null
	var end: int = c["end"] if c["end"] != null else c["start"]
	return {"id": "%s|%s|%d|%d" % [c["kind"], c["location"], floori(int(c["start"]) / 30.0), floori(end / 30.0)],
			"name": name, "template": "I saw {names}" + percept.substr(name.length()) + "."}


static func narrative(sim_, inc_: Dictionary) -> String:
	## What really happened, in one sentence (sealed).
	var ev: Dictionary = sim_.events.by_id[inc_["core_event"]]
	var who := ""
	if inc_["responsible"] != null:
		who = sim_.residents[inc_["responsible"]].full_name()
	var at := SimClock.fmt(ev["time"])
	match String(inc_["family"]):
		"theft":
			var what := "units of food" if ev["data"]["asset"] == "food" else "crowns"
			return "%s took %d %s from %s at %s." % [who, int(ev["data"]["amount"]), what,
					sim_.world.containers[ev["objects"][0]]["label"], at]
		"accounting_error":
			return "Nothing was stolen. %s wrote a sale into the ledger twice at %s, so the till looked short when it was counted." % [
					sim_.residents[ev["actors"][0]].full_name(), at]
		"assault":
			return "%s attacked %s at %s at %s during an argument." % [who, sim_.residents[inc_["victims"][0]].full_name(),
					sim_.world.name_of(inc_["location"]), at]
		"collision":
			var victim := "the fence"
			if not Array(inc_["victims"]).is_empty():
				victim = sim_.residents[inc_["victims"][0]].full_name()
			var drunk := " after drinking" if inc_["intent"] == "reckless" else ""
			var fled := " and drove on without stopping" if inc_["fled"] else ""
			return "%s, driving %s%s, hit %s on Mill Road at %s%s." % [who, sim_.world.name_of(ev["objects"][0]), drunk,
					victim, at, fled]
		"fall":
			return "Nobody else was involved: %s, drunk, fell into the ditch on Mill Road at %s." % [
					sim_.residents[inc_["victims"][0]].full_name(), at]
	return ev["summary"]
