## Violence and accidents (mirrors the assault, collision, fall, injury, clinic, workshop, finding and missing
## parts of mystery/sim/actions.py and engine.py). The crime layer with violence on, Pilot 3B: it runs only with
## config "crime" and "violence" (scripts/sim/sim_config.gd).
##
##   assault          an argument that turns violent (sim_actions.gd, confront): a fight, seen and heard, which
##                    bystanders may break up; blood is a trace; rarely the victim dies
##   check_collision  a driver on Mill Road, far more likely after dark and after drink, hits a walker or the fence;
##                    debris on the road and damage to the vehicle are traces; the driver stops and owns up, or
##                    drives on (and later wants the damage mended quietly)
##   check_fall       someone very drunk on Mill Road after dark falls into the ditch; what they remember of it
##                    depends on how drunk they were, and may be wrong
##   injure, kill     an injury heals in two days (minor) or six (serious); someone seriously hurt on the road
##                    lies there, "down", until found or until they manage home; a death leaves a body
##   notice_injury    people see someone hurt and hear their account of it, which may be mistaken, or a lie
##   found_checks     someone lying hurt, or dead, is found by the first person to come by (never by whoever did it)
##   missed_people    someone who died unseen is missed after half a day, and the person fondest of them goes to
##                    check on them (a body found is buried three days later: sim_crime.gd, tidy_evidence)
##   clinic, repair   the nurse treats the injured and writes down what they say; the mechanic mends a damaged
##                    vehicle and writes down what the owner says (a driver who fled lies)
##
## Truth and belief stay apart: an injury, a death or a collision is known only by those who took part, saw or
## heard it, found the person, treated them, or were told; an account can be wrong (a fall remembered as being
## pushed) or a lie (a door walked into; a deer on the ridge road). Every injury, trace and consequence points at
## the event that caused it, and every incident is in the registry with whoever was responsible.
extends RefCounted

const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Memory = preload("res://scripts/sim/sim_memory.gd")
const Perception = preload("res://scripts/sim/sim_perception.gd")
const Incidents = preload("res://scripts/sim/sim_incidents.gd")
const Decisions = preload("res://scripts/sim/sim_decisions.gd")
const Crime = preload("res://scripts/sim/sim_crime.gd")

const DAY := 1440
const INJURY_TEXT := {
	"assault1": "a split lip and bruised ribs",
	"assault2": "a broken nose and two cracked ribs",
	"collision1": "deep bruising down one side and a cut to the head",
	"collision2": "a broken leg and a head wound",
	"fall1": "grazed hands and a sprained ankle",
	"fall2": "a broken wrist and a gash on the forehead",
}
const DEATH_PATTERN := {
	"assault": "There are heavy blows to the head and face.",
	"collision": "The injuries look like a heavy impact from the side, the legs broken.",
	"fall": "There is a deep wound to the head.",
}


static func _drinks_before(sim, rid: String, t: int) -> Array:
	## The drinks of the last six hours: what led to a fall or a reckless drive.
	var out := []
	for d in sim.recent_drinks.get(rid, []):
		if t - int(d[0]) <= 6 * 60:
			out.append(d[1])
	return out


static func _night_of(t: int) -> String:
	var d := SimClock.day_of(t) - (1 if SimClock.hour_of(t) < 6 else 0)
	return "on the night of Day %d" % d


# ================================================================ harm
static func injure(sim, v, severity: int, ev: Dictionary, desc: String) -> void:
	v.injury = maxi(v.injury, severity)
	v.injury_event = ev["id"]
	v.injury_desc = desc
	v.injury_treated = false
	v.stress = clampf(v.stress + 20, 0.0, 100.0)


static func kill(sim, v, cause: Dictionary, t: int) -> void:
	var here: String = sim.loc(v.id)
	v.alive = false
	v.asleep = false
	v.down = false
	var dev: Dictionary = sim.emit("death", here, [v.id], {"data": {"cause": cause["kind"]}, "causes": [cause["id"]],
			"notable": true, "time": t, "summary": "%s dies." % v.first})
	v.death_event = dev["id"]
	sim.bump("deaths")
	var pattern: String = DEATH_PATTERN.get(cause["kind"], "")
	sim.world.add_evidence("body", here, "The body of %s lies at %s. %s" % [v.full_name(), sim.world.name_of(here),
			pattern], t, dev["id"])


static func assault(sim, aggressor, victim, cause: Dictionary, here: String, t: int, bystanders: Array,
		reason: String) -> void:
	## An argument turns into a fight. Anyone there sees it, neighbours hear it; a bystander may pull them apart.
	var roll: float = sim.rng.random()
	var fatal_p: float = 0.015 + 0.02 * aggressor.intox / 100.0
	var severity := 1
	if roll < fatal_p:
		severity = 3
	elif roll < fatal_p + 0.25:
		severity = 2
	var intervened := []
	for y in bystanders:
		if sim.rng.random() < 0.5:
			intervened.append(y)
	if not intervened.is_empty():
		severity = 1
	var ev: Dictionary = sim.emit("assault", here, [aggressor.id], {"targets": [victim.id],
			"data": {"severity": severity, "reason": reason}, "causes": [cause["id"]], "intent": "impulsive",
			"audibility": 2, "notable": true, "time": t, "summary": "%s attacks %s." % [aggressor.first, victim.first]})
	sim.bump("assaults")
	var claim := Memory.claim("assault", {"subject": aggressor.id, "other": victim.id, "location": here, "start": t})
	Perception.broadcast(sim, ev, claim, Memory.claim("noise", {"location": here, "start": t,
			"detail": "a scuffle, something breaking and someone crying out"}), victim.id)
	for p in [aggressor.id, victim.id]:
		sim.add_belief(p, claim, "self", 1.0, t, {"event": ev["id"]})
	if not intervened.is_empty():
		var names := PackedStringArray()
		for y in intervened:
			names.append(sim.n(y))
		sim.emit("intervened", here, intervened, {"targets": [aggressor.id], "causes": [ev["id"]], "intent": "lawful",
				"time": t + 1, "summary": "%s pull %s away." % [", ".join(names), aggressor.first]})
	aggressor.guilty_of.append(ev["id"])
	aggressor.stress = clampf(aggressor.stress + 25, 0.0, 100.0)
	aggressor.cooldowns["confront:" + victim.id] = t + 14 * DAY
	victim.cooldowns["confront:" + aggressor.id] = t + 14 * DAY
	var rel: Dictionary = victim.r(aggressor.id)
	rel["resentment"] = clampf(rel["resentment"] + 0.5, 0.0, 1.0)
	rel["trust"] = 0.05
	var motive := "grudge"
	if aggressor.intox >= 50:
		motive = "intoxication"
	elif reason in ["debt", "rent"]:
		motive = "money_trouble"
	var inc: Dictionary = Incidents.register(sim, {"family": "assault", "core_event": ev["id"], "time": t,
			"location": here, "responsible": aggressor.id, "victims": [victim.id], "intent": "impulsive",
			"mechanism": "assaulted", "outcome": "crime", "severity": severity,
			"hook_kind": "person_dead" if severity == 3 else "person_injured", "motive": motive,
			"related_events": [cause["id"]]})
	var place: String = sim.world.name_of(here)
	if severity >= 2:
		sim.world.add_evidence("blood", here, "Spots of blood and a broken chair at %s." % place, t, ev["id"])
	if severity == 3:
		kill(sim, victim, ev, t + 1)
		var witnesses := []
		for y in bystanders:
			if sim.residents[y].alive:
				witnesses.append(y)
		if not witnesses.is_empty():
			Incidents.discover(sim, inc, witnesses[0], t, ev["id"], "%s died after being attacked at %s around %s on Day %d." % [
					victim.full_name(), place, SimClock.fmt_clock(t), SimClock.day_of(t)], "The Death at %s" % Crime._title(place),
					[t - 30, t + 30], here)
	else:
		injure(sim, victim, severity, ev, INJURY_TEXT["assault%d" % severity])
		Incidents.discover(sim, inc, victim.id, t, ev["id"], "%s was hurt in a fight at %s around %s on Day %d: %s." % [
				victim.full_name(), place, SimClock.fmt_clock(t), SimClock.day_of(t), victim.injury_desc],
				"The Fight at %s" % Crime._title(place), [t - 30, t + 30], here)


# ================================================================ the road
@warning_ignore("integer_division")
static func check_collision(sim, rid: String, t0: int, walkers: Array) -> void:
	var mv: Dictionary = sim.moves[rid]
	var path: Array = mv["path"]
	var times: Array = mv["times"]
	var i: int = path.find("road")
	if i < 0 or i == path.size() - 1:
		return
	var t_in: int = times[i]
	var t_out: int = times[i + 1]
	var r = sim.residents[rid]
	var dark := SimClock.is_dark(t_in)
	var p: float = (0.003 if dark else 0.0004) + maxf(0.0, r.intox - 25) / 100.0 * (0.12 if dark else 0.04)
	if sim.rng.random() >= p:
		return
	var tc: int = t_in + maxi(0, (t_out - t_in) / 2)
	var peds := []
	for x in walkers:
		var w = sim.residents[x]
		if w.alive and not w.down and sim.where(x, tc) == "road":
			peds.append(x)
	var victim_id := ""
	if not peds.is_empty() and sim.rng.random() < 0.6:
		victim_id = peds[sim.rng.randrange(peds.size())]
	var veh: Dictionary = sim.world.vehicles[mv["vehicle"]]
	var causes := _drinks_before(sim, rid, tc)
	var intent := "reckless" if r.intox >= 40 else "accidental"
	var severity := 0
	var damage := ""
	var site := ""
	var glimpse := ""
	var struck := ""
	if victim_id != "":
		var roll: float = sim.rng.random()
		severity = 1 if roll < 0.6 else (2 if roll < 0.92 else 3)
		damage = "a dented bonnet, a cracked windscreen on the passenger side and a dark smear on the bumper"
		site = "Fragments of headlight glass and a churned, scuffed patch of mud at the edge of Mill Road."
		glimpse = "headlight glass and churned mud at the edge of Mill Road"
		struck = sim.residents[victim_id].first
	else:
		damage = "a dented front bumper, a cracked headlight and flecks of white paint and wood splinters in the grille"
		site = "Two rails of the white fence along Mill Road are smashed; fragments of headlight glass lie on the verge."
		glimpse = "the white fence along Mill Road smashed, with headlight glass on the verge"
		struck = "the fence"
	var victims := [victim_id] if victim_id != "" else []
	var ev: Dictionary = sim.emit("collision", "road", [rid], {"targets": victims, "objects": [veh["id"]],
			"data": {"vehicle": veh["id"], "struck": victim_id if victim_id != "" else "fence", "severity": severity,
			"intox": int(round(r.intox))}, "causes": causes, "intent": intent, "audibility": 3, "notable": true,
			"time": tc, "summary": "%s, driving %s, hits %s on Mill Road." % [r.first, veh["name"], struck]})
	sim.bump("collisions")
	veh["damage"] = damage
	veh["damage_event"] = ev["id"]
	var vname: String = veh["name"]
	var vx: Dictionary = sim.world.add_evidence("vehicle_damage", veh["id"], "%s%s has %s." % [vname.substr(0, 1).to_upper(),
			vname.substr(1), damage], tc, ev["id"], [rid])
	veh["damage_evidence"] = vx["id"]
	sim.world.add_evidence("debris", "road", site, tc, ev["id"], [], glimpse)
	Perception.broadcast(sim, ev, Memory.claim("saw_collision", {"subject": rid,
			"other": victim_id if victim_id != "" else null, "location": "road", "start": tc, "obj": veh["id"],
			"detail": "%s hit %s" % [vname, "someone" if victim_id != "" else "the fence"]}),
			Memory.claim("noise", {"location": "road", "start": tc, "detail": "a loud crash and an engine"}))
	sim.add_belief(rid, Memory.claim("collision_self", {"subject": rid, "other": victim_id if victim_id != "" else null,
			"location": "road", "start": tc, "obj": veh["id"], "detail": "hit " + struck}), "self",
			1.0 if r.intox < 60 else 0.7, tc, {"event": ev["id"]})
	if victim_id != "":
		var what: String = "a " + String(veh["kind"]) if sim.rng.random() < 0.6 else "a vehicle"
		sim.add_belief(victim_id, Memory.claim("struck", {"other": victim_id, "location": "road", "start": tc,
				"detail": what}), "self", 0.9, tc, {"event": ev["id"]})
	var tr: Dictionary = r.traits
	var p_stop: float = (0.25 + 0.45 * tr["honesty"] + 0.3 * tr["empathy"] - r.intox / 100.0 * 0.5
			- 0.15 * tr["caution"])
	if victim_id != "":
		p_stop += 0.15
	var stop: bool = sim.rng.random() < clampf(p_stop, 0.05, 0.95)
	var hook_kind := "property_damaged"
	if victim_id != "":
		hook_kind = "person_dead" if severity == 3 else "person_injured"
	var inc: Dictionary = Incidents.register(sim, {"family": "collision", "core_event": ev["id"], "time": tc,
			"location": "road", "responsible": rid, "victims": victims, "intent": intent,
			"mechanism": "struck_by_vehicle" if victim_id != "" else "vehicle_collision",
			"outcome": "accident" if stop else "crime", "severity": severity, "hook_kind": hook_kind,
			"motive": "intoxication" if intent == "reckless" else "none", "fled": not stop})
	var victim = sim.residents[victim_id] if victim_id != "" else null
	if stop:
		var st: Dictionary = sim.emit("stopped_to_help" if victim != null else "stopped", "road", [rid], {"targets": victims,
				"causes": [ev["id"]], "intent": "lawful", "time": tc, "summary": "%s stops and owns up." % r.first})
		inc["reported_openly"] = true
		if victim != null:
			sim.truncate(rid, "road", tc)
			sim.truncate(victim.id, "road", tc)
			sim.add_belief(victim.id, Memory.claim("struck", {"subject": rid, "other": victim.id, "location": "road",
					"start": tc, "obj": veh["id"], "detail": vname}), "self", 1.0, tc, {"event": st["id"]})
			if severity == 3:
				kill(sim, victim, ev, tc)
			else:
				injure(sim, victim, severity, ev, INJURY_TEXT["collision%d" % severity])
				sim.forced[victim.id] = Decisions.plan("rest", victim.home)
			sim.forced[rid] = Decisions.plan("rest", r.home)
		Incidents.discover(sim, inc, victim_id if victim != null else rid, tc, st["id"], "%s admits hitting %s on Mill Road." % [
				r.full_name(), struck], "An Accident on Mill Road", [tc, tc + 1], "road")
		return
	r.guilty_of.append(ev["id"])
	r.wants_repair = true
	r.stress = clampf(r.stress + 25, 0.0, 100.0)
	if victim == null:
		return
	if severity == 1:
		injure(sim, victim, 1, ev, INJURY_TEXT["collision1"])
		Incidents.discover(sim, inc, victim.id, tc, ev["id"], "%s says a vehicle knocked them down on Mill Road %s and drove on." % [
				victim.full_name(), _night_of(tc)], "Hit and Run on Mill Road", [tc - 45, tc + 45], "road")
		return
	sim.truncate(victim.id, "road", tc)
	if severity == 3:
		kill(sim, victim, ev, tc)
	else:
		injure(sim, victim, 2, ev, INJURY_TEXT["collision2"])
		victim.down = true


@warning_ignore("integer_division")
static func check_fall(sim, rid: String, t0: int) -> void:
	var mv: Dictionary = sim.moves[rid]
	var path: Array = mv["path"]
	var times: Array = mv["times"]
	var r = sim.residents[rid]
	var i: int = path.find("road")
	if not r.alive or r.down or i < 0 or i == path.size() - 1:
		return
	if not SimClock.is_dark(times[i]) or r.intox < 50:
		return
	if sim.rng.random() >= (r.intox - 50) / 100.0 * 0.15:
		return
	var tf: int = times[i] + maxi(0, (times[i + 1] - times[i]) / 2)
	var severity := 2 if sim.rng.random() < 0.3 else 1
	var ev: Dictionary = sim.emit("fall", "road", [rid], {"data": {"severity": severity, "intox": int(round(r.intox))},
			"causes": _drinks_before(sim, rid, tf), "intent": "accidental", "audibility": 1, "notable": true,
			"time": tf, "summary": "%s, drunk, falls into the ditch on Mill Road." % r.first})
	sim.bump("falls")
	sim.world.add_evidence("debris", "road", "Mud scuffed down the bank of the ditch beside Mill Road, and a dropped cap in the grass.",
			tf, ev["id"], [], "scuff marks down the ditch bank on Mill Road and a dropped cap")
	injure(sim, r, severity, ev, INJURY_TEXT["fall%d" % severity])
	Incidents.register(sim, {"family": "fall", "core_event": ev["id"], "time": tf, "location": "road",
			"responsible": null, "victims": [rid], "intent": "accidental", "mechanism": "accidental_fall",
			"outcome": "accident", "severity": severity, "hook_kind": "person_injured", "motive": "none"})
	# What the victim remembers depends on how drunk they were.
	var roll: float = sim.rng.random()
	if r.intox <= 65 or roll < 0.45:
		sim.add_belief(rid, Memory.claim("fall", {"subject": rid, "location": "road", "start": tf,
				"detail": "slipped into the ditch"}), "self", 0.9 if r.intox <= 65 else 0.5, tf, {"event": ev["id"]})
	else:
		# too drunk to know: they may blame someone they resent whom they saw that night
		var seen := {}  # subject -> the sightings of them that evening
		for b in sim.memory[rid].of_kind(["presence", "sighting"], tf - 5 * 60):
			var s = b["claim"]["subject"]
			if s and s != rid:
				if not seen.has(s):
					seen[s] = []
				seen[s].append(b["id"])
		var resented := []  # [resentment, id]
		for x in seen:
			var res: float = r.r(x)["resentment"]
			if res >= 0.3:
				resented.append([res, x])
		resented.sort_custom(func(a, b): return _most_first(a, b))
		if not resented.is_empty() and roll < 0.75:
			var blamed: String = resented[0][1]
			sim.add_belief(rid, Memory.claim("assault", {"subject": blamed, "other": rid, "location": "road",
					"start": tf, "hedged": true}), "inferred", 0.4, tf, {"event": ev["id"], "error": "mistaken_inference",
					"premises": seen[blamed]})
		else:
			sim.add_belief(rid, Memory.claim("injury", {"subject": rid, "location": "road", "start": tf,
					"detail": "no memory of how it happened"}), "self", 0.3, tf, {"event": ev["id"]})
	if severity == 2:
		sim.truncate(rid, "road", tf)
		r.down = true


# ================================================================ what the hurt say
static func _own_accounts(sim, s) -> Array:
	var cause: Dictionary = sim.events.by_id[s.injury_event]
	var mine := []
	for b in sim.memory[s.id].beliefs:
		if b["event"] == s.injury_event or (cause["kind"] == "collision" and b["claim"]["kind"] == "struck"
				and b["claim"]["start"] == cause["time"]):
			mine.append(b)
	mine.sort_custom(func(a, b): return _surest_last(a, b))
	return mine


static func _surest_last(a: Dictionary, b: Dictionary) -> bool:
	if a["confidence"] != b["confidence"]:
		return a["confidence"] < b["confidence"]
	return a["id"] < b["id"]


static func _most_first(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] > b[0]
	return a[1] < b[1]


static func account_belief(sim, s):
	## The injured person's own belief their account comes from (the surest), or null.
	var mine := _own_accounts(sim, s)
	return mine[-1]["id"] if not mine.is_empty() else null


static func _account_error(sim, s):
	var bid = account_belief(sim, s)
	return sim.beliefs[bid]["error"] if bid != null else null


static func patient_account(sim, s) -> Array:
	## [what they say, the claim it makes or null, whether it is a lie]. It may be mistaken, or a lie.
	var cause: Dictionary = sim.events.by_id[s.injury_event]
	if cause["kind"] == "assault":
		var aggressor: String = cause["actors"][0]
		if s.r(aggressor)["affection"] >= 0.75 and s.traits["honesty"] < 0.8:
			return ["I walked into a door, that's all.", null, true]
		return ["%s hit me." % sim.n(aggressor), Memory.claim("assault", {"subject": aggressor, "other": s.id,
				"location": cause["location"], "start": cause["time"]}), false]
	var mine := _own_accounts(sim, s)
	if mine.is_empty():
		return ["I don't know what happened.", null, false]
	var c: Dictionary = mine[-1]["claim"]
	if c["kind"] == "struck":
		if c["subject"]:
			return ["%s hit me with %s on Mill Road." % [sim.n(c["subject"]), sim.world.name_of(c["obj"]) if c["obj"]
					else "a vehicle"], c.duplicate(), false]
		return ["Something hit me on Mill Road — %s, I think. It didn't stop." % c["detail"], c.duplicate(), false]
	if c["kind"] == "fall":
		return ["I slipped into the ditch on Mill Road. I'd had a few.", c.duplicate(), false]
	if c["kind"] == "assault" and c["subject"]:
		return ["I think %s pushed me into the ditch. It's hazy." % sim.n(c["subject"]), c.duplicate(), false]
	return ["I can't remember how it happened.", null, false]


static func _hear_account(sim, holder: String, s, event_id: String, t: int, acc: Array) -> void:
	if acc[1] != null:
		sim.add_belief(holder, acc[1], "told", 0.7, t, {"told_by": s.id, "via": account_belief(sim, s),
				"event": event_id, "error": _account_error(sim, s)})


static func notice_injury(sim, obs: String, subj: String, node: String, t: int) -> void:
	## Someone sees a person who is hurt, and hears what they say happened.
	var s = sim.residents[subj]
	var since: int = sim.events.by_id[s.injury_event]["time"]
	for b in sim.memory[obs].of_kind(["injury"]):
		if b["claim"]["subject"] == subj and b["acquired"] >= since:
			return
	sim.add_belief(obs, Memory.claim("injury", {"subject": subj, "location": node, "start": t,
			"detail": s.injury_desc if s.injury_desc != "" else "visibly hurt"}), "saw", 0.9, t, {"event": s.injury_event})
	sim.perceived[obs + "|" + s.injury_event] = "trace"
	var acc := patient_account(sim, s)
	_hear_account(sim, obs, s, s.injury_event, t, acc)
	var inc: Dictionary = Incidents.incident_for(sim, s.injury_event)
	if not inc.is_empty() and inc["discovered_at"] == null:
		Incidents.discover(sim, inc, obs, t, s.injury_event, "%s turned up hurt on Day %d with %s. %s says: \"%s\"" % [
				s.full_name(), SimClock.day_of(t), s.injury_desc, s.first, acc[0]], "The Injuries of %s" % s.full_name(),
				[since - 4 * 60, t], node)


static func injuries_noticed(sim, tm: int) -> void:
	## At the end of each hour, as people notice who is with them (sim_perception.gd, co_presence), they notice
	## who is hurt.
	var groups := {}
	for r in sim.alive():
		if r.asleep or r.down:
			continue
		var node: String = sim.where(r.id, tm)
		if node == "":
			continue
		if not groups.has(node):
			groups[node] = []
		groups[node].append(r.id)
	var nodes: Array = groups.keys()
	nodes.sort()
	for node in nodes:
		var people: Array = groups[node]
		if people.size() < 2:
			continue
		for obs in people:
			for subj in people:
				var s = sim.residents[subj]
				if obs != subj and s.injury > 0 and s.injury_event != "":
					notice_injury(sim, obs, subj, node, tm)


# ================================================================ found, missed, buried
static func found(sim, finder: String, v, node: String, t: int) -> void:
	var place: String = sim.world.name_of(node)
	if v.alive:
		var ev: Dictionary = sim.emit("injury_found", node, [finder], {"targets": [v.id], "causes": [v.injury_event],
				"intent": "lawful", "audibility": 1, "notable": true, "time": t,
				"summary": "%s finds %s lying hurt at %s." % [sim.n(finder), v.first, place]})
		v.down = false
		sim.add_belief(finder, Memory.claim("injury", {"subject": v.id, "location": node, "start": t,
				"detail": "lying hurt at %s" % place}), "self", 0.95, t, {"event": ev["id"]})
		var acc := patient_account(sim, v)
		_hear_account(sim, finder, v, ev["id"], t, acc)
		var dest: String = "clinic" if sim.business_open("clinic", t + 60) else v.home
		sim.forced[v.id] = Decisions.plan("clinic" if dest == "clinic" else "rest", dest)
		sim.forced[finder] = Decisions.plan("escort", dest, v.id)
		var inc: Dictionary = Incidents.incident_for(sim, v.injury_event)
		if not inc.is_empty():
			Incidents.discover(sim, inc, finder, t, ev["id"], "%s found %s lying hurt at %s at %s. %s says: \"%s\"" % [
					sim.residents[finder].full_name(), v.full_name(), place, SimClock.fmt(t), v.first, acc[0]],
					"Found in the Ditch" if inc["family"] == "fall" else "Left on Mill Road",
					[int(sim.events.by_id[v.injury_event]["time"]) - 5 * 60, t], node)
	else:
		var ev: Dictionary = sim.emit("body_found", node, [finder], {"targets": [v.id], "causes": [v.death_event],
				"intent": "lawful", "audibility": 2, "notable": true, "time": t,
				"summary": "%s finds %s dead at %s." % [sim.n(finder), v.first, place]})
		sim.found_bodies.append(v.id)
		for e in sim.world.evidence_at(node, t):
			if e["kind"] == "body" and not (finder in e["noticed_by"]):
				e["noticed_by"].append(finder)
				sim.perceived[finder + "|" + e["created_by"]] = "trace"
		var claim := Memory.claim("death", {"subject": v.id, "location": node, "start": t,
				"detail": "found dead at %s" % place})
		sim.add_belief(finder, claim, "self", 1.0, t, {"event": ev["id"]})
		Perception.broadcast(sim, ev, claim, Memory.claim("noise", {"location": node, "start": t,
				"detail": "someone shouting for help"}))
		var f = sim.residents[finder]
		f.stress = clampf(f.stress + 30, 0.0, 100.0)
		var death: Dictionary = sim.events.by_id[v.death_event]
		var cause: Dictionary = sim.events.by_id[death["causes"][0]]
		var inc: Dictionary = Incidents.incident_for(sim, cause["id"])
		if not inc.is_empty():
			Incidents.discover(sim, inc, finder, t, ev["id"], "%s found %s dead at %s at %s." % [f.full_name(),
					v.full_name(), place, SimClock.fmt(t)], "The Death of %s" % v.full_name(),
					[int(cause["time"]) - 6 * 60, t], node)


static func found_checks(sim, t0: int) -> void:
	## Someone lying hurt, or dead, is found by the first person awake to come by (never by whoever caused it). By
	## mid-morning, someone hurt whom nobody found manages to get home on their own.
	for rid in sim.ids:
		var r = sim.residents[rid]
		if not (r.down or (not r.alive and r.death_event != "" and not (rid in sim.found_bodies))):
			continue
		var node: String = sim.loc(rid)
		var harm: Dictionary = sim.events.by_id[r.death_event if r.death_event != "" else r.injury_event]
		var cause: Dictionary = harm
		if harm["kind"] == "death" and not harm["causes"].is_empty():
			cause = sim.events.by_id[harm["causes"][0]]
		var finders := []
		for x in sim.visitors(node, t0, t0 + 60, [rid] + cause["actors"]):
			var when: int = sim.overlap_start(x, node, maxi(t0, int(harm["time"]) + 1), t0 + 60)
			if when >= 0 and not sim.residents[x].asleep:
				finders.append([when, x])
		finders.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		if finders.is_empty() and r.alive and r.down and SimClock.hour_of(t0) == 10:
			r.down = false  # manages to get home on their own
			sim.forced[rid] = Decisions.plan("rest", r.home)
			continue
		if not finders.is_empty():
			found(sim, finders[0][1], r, node, finders[0][0])


static func missed_people(sim, t0: int) -> void:
	## Someone who has not been seen for most of a day gets checked on at home, by whoever is fondest of them.
	var h := SimClock.hour_of(t0)
	if h < 8 or h > 18:
		return
	for rid in sim.ids:
		var r = sim.residents[rid]
		if r.alive or rid in sim.found_bodies or r.death_event == "":
			continue
		var death: Dictionary = sim.events.by_id[r.death_event]
		if t0 - int(death["time"]) < 12 * 60 or int(sim.daily.get("checked:" + rid, 0)) > 0:
			continue
		var culprits: Array = sim.events.by_id[death["causes"][0]]["actors"] if not death["causes"].is_empty() else []
		var carer := ""
		var fondest := -1.0
		for x in sim.ids:
			var c = sim.residents[x]
			if x == rid or x in culprits or not c.alive or c.down or sim.forced.has(x):
				continue
			var aff: float = c.r(rid)["affection"]
			if carer == "" or aff > fondest or (aff == fondest and x > carer):
				carer = x
				fondest = aff
		if carer == "":
			continue
		sim.daily["checked:" + rid] = 1
		var ev: Dictionary = sim.emit("missed", sim.loc(carer), [carer], {"data": {"missing": rid}, "intent": "lawful",
				"time": t0 + 59, "summary": "%s hasn't seen %s all day and goes to check on them." % [sim.n(carer), r.first]})
		# since when, as far as the carer knows: the last time they themselves saw them (Python records the true
		# time of death here, which the carer cannot know; see docs/godot-simulation-migration.md)
		var last_seen = null
		for b in sim.memory[carer].of_kind(["presence", "sighting"]):
			if b["claim"]["subject"] == rid:
				var seen_at: int = b["claim"]["end"] if b["claim"]["end"] != null else b["claim"]["start"]
				if last_seen == null or seen_at > last_seen:
					last_seen = seen_at
		sim.add_belief(carer, Memory.claim("missing", {"subject": rid, "start": last_seen, "end": t0,
				"detail": "not seen all day"}), "self", 0.9, t0 + 59, {"event": ev["id"]})
		sim.forced[carer] = Decisions.plan("check_on", r.home, rid)


# ================================================================ the clinic and the workshop
static func clinic(sim, r, ta: int) -> void:
	var staff := []
	for s in sim.staff_at("clinic", ta):
		if s != r.id:
			staff.append(s)
	if staff.is_empty() or r.injury == 0:
		return
	var nurse: String = staff[0]
	var acc := patient_account(sim, r)
	var ev: Dictionary = sim.emit("treated", "clinic", [nurse], {"targets": [r.id], "data": {"injury": r.injury_desc,
			"account": acc[0]}, "causes": [r.injury_event], "intent": "lawful", "audibility": 1, "time": ta,
			"summary": "%s treats %s for %s." % [sim.n(nurse), r.first, r.injury_desc]})
	r.injury_treated = true
	sim.world.record("clinic_log", ta, "%s treated %s for %s. Patient's account: \"%s\"" % [SimClock.fmt(ta), r.full_name(),
			r.injury_desc, acc[0]], ev["id"])
	sim.add_belief(nurse, Memory.claim("injury", {"subject": r.id, "location": "clinic", "start": ta,
			"detail": r.injury_desc}), "saw", 0.95, ta, {"event": ev["id"]})
	_hear_account(sim, nurse, r, ev["id"], ta, acc)
	var inc: Dictionary = Incidents.incident_for(sim, r.injury_event)
	if not inc.is_empty() and inc["discovered_at"] == null:
		Incidents.discover(sim, inc, nurse, ta, ev["id"], "%s came to the clinic on Day %d with %s. %s says: \"%s\"" % [
				r.full_name(), SimClock.day_of(ta), r.injury_desc, r.first, acc[0]], "The Injuries of %s" % r.full_name(),
				[int(sim.events.by_id[r.injury_event]["time"]) - 4 * 60, ta], "clinic")


static func repair(sim, r, ta: int) -> void:
	var veh: Dictionary = sim.world.vehicles[r.vehicle]
	var staff: Array = sim.staff_at("workshop", ta)
	var mech := ""
	if not staff.is_empty():
		mech = staff[0]
	elif r.role == "mechanic":
		mech = r.id
	if mech == "" or veh["location"] != "workshop" or veh["damage"] == "":
		return
	var inc: Dictionary = Incidents.incident_for(sim, veh["damage_event"]) if veh["damage_event"] != "" else {}
	var conceal: bool = veh["damage_event"] in r.guilty_of and (inc.is_empty() or not inc["reported_openly"])
	var explanation := ""
	if conceal:
		explanation = "Hit a deer out on the ridge road a few nights back."
	else:
		var struck = sim.events.by_id[veh["damage_event"]]["data"].get("struck") if veh["damage_event"] != "" else null
		explanation = ("Clipped the fence on Mill Road." if struck == null or struck == "fence"
				else "Hit %s on Mill Road. An accident." % sim.n(struck))
	var customer := [r.id] if mech != r.id else []
	var ev: Dictionary = sim.emit("repair", "workshop", [mech], {"targets": customer, "objects": [veh["id"]],
			"data": {"damage": veh["damage"], "explanation": explanation, "concealed": conceal},
			"causes": [veh["damage_event"]] if veh["damage_event"] != "" else [], "intent": "lawful", "audibility": 1,
			"time": ta, "summary": "%s repairs %s." % [sim.n(mech), veh["name"]]})
	if mech != r.id:
		if r.cash >= 25:
			sim.transfer("cash", "wallet:" + r.id, "wallet:" + mech, 25, ev["id"], ta)
		else:
			sim.world.add_debt(r.id, mech, 25, ta + 7 * DAY, ta, ev["id"], "credit")
		sim.world.record("workshop_orders", ta, "%s %s (%s): straightened the front panel, replaced the headlight. Customer said: \"%s\"" % [
				SimClock.fmt(ta), veh["name"], r.full_name(), explanation], ev["id"])
		sim.add_belief(mech, Memory.claim("vehicle_damage", {"subject": r.id, "obj": veh["id"], "location": "workshop",
				"start": ta, "detail": veh["damage"]}), "saw", 0.95, ta, {"event": ev["id"]})
		sim.add_belief(mech, Memory.claim("repair", {"subject": r.id, "obj": veh["id"], "start": ta, "detail": explanation}),
				"told", 0.8, ta, {"event": ev["id"], "told_by": r.id, "error": "lie" if conceal else null})
	else:
		sim.world.record("workshop_orders", ta, "%s parts used: one headlight unit and a front panel, for %s (workshop's own)." % [
				SimClock.fmt(ta), veh["name"]], ev["id"])
	for e in sim.world.evidence:
		if e["id"] == veh["damage_evidence"] and e["removed_at"] < 0:
			e["removed_at"] = ta
			e["removed_by"] = ev["id"]
	var paint := " with flecks of white paint" if "white paint" in String(veh["damage"]) else " with a dark stain"
	sim.world.add_evidence("scrap", "workshop", "In the workshop scrap pile: a cracked headlight unit and a bent front panel%s, chalked '%s'." % [
			paint, veh["name"]], ta, ev["id"], [r.id])
	veh["damage"] = ""
	veh["damage_event"] = ""
	veh["damage_evidence"] = ""
	r.wants_repair = false
