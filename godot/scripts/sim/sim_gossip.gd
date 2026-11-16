## Talk and inference (mirrors the gossip and suspicion parts of mystery/sim/actions.py and decisions.py).
##
##   conceals         what a speaker keeps to themselves: anything about someone they are fond of that could
##                    hurt them (debts, hardship, being drunk, being seen somewhere ...)
##   pick_gossip      what comes up when two people talk: fresh, salient news the listener hasn't had from
##                    them, never the listener's own troubles, one or two items depending on sociability
##   tell             passing it on: the listener trusts it as far as they trust the speaker; a hedged
##                    sighting can lose its "I think" (certainty_inflated), a time can drift by 30-60 minutes
##                    (time_distorted). What is told stays "told": it never becomes something the listener saw.
##   infer_suspicions putting two and two together after a loss or damage they know of, from what they
##                    themselves saw or heard nearby; sometimes they make five
extends RefCounted

const Memory = preload("res://scripts/sim/sim_memory.gd")
const Incidents = preload("res://scripts/sim/sim_incidents.gd")

const DAY := 1440
const LOYAL_KINDS := ["suspect", "sighting", "vehicle_damage", "assault", "debt", "hardship", "intoxicated", "presence"]
const SCENE_KINDS := ["presence", "sighting", "noise", "intoxicated", "saw_collision"]
const OWN_TROUBLES := ["debt", "hardship", "suspect", "refusal", "rent_missed"]


static func conceals(sim, speaker, b: Dictionary) -> bool:
	var c: Dictionary = b["claim"]
	if c["kind"] in ["theft_self", "stash"]:
		return true
	if c["kind"] == "collision_self":
		# a driver keeps a collision to themselves unless they owned up to it on the spot
		var inc: Dictionary = Incidents.incident_for(sim, b["event"])
		return inc.is_empty() or not inc["reported_openly"]
	if not speaker.guilty_of.is_empty() and c["subject"] == speaker.id:
		return true  # someone with something to hide keeps quiet about themselves
	if (c["subject"] and c["subject"] != speaker.id and speaker.r(c["subject"])["affection"] >= 0.75
			and c["kind"] in LOYAL_KINDS):
		return true
	if c["kind"] == "vehicle_damage" and c["obj"] and speaker.vehicle == c["obj"]:
		return true
	return false


static func anchors_for(sim, rid: String, t: int) -> Array:
	## [from, to, place] of incidents the resident knows of, which make nearby sightings worth mentioning.
	var out := []
	for b in sim.memory[rid].of_kind(Memory.INCIDENT_KINDS):
		var c: Dictionary = b["claim"]
		if c["start"] != null and b["acquired"] >= t - 5 * DAY:
			var start: int = c["start"] if c["kind"] == "loss" else c["start"] - 12 * 60
			out.append([start, c["end"] if c["end"] != null else c["start"], c["location"] if c["location"] else ""])
	return out


static func pick_gossip(sim, speaker, listener, t: int) -> Array:
	var anchors = null
	var cands := []
	var bs: Array = sim.memory[speaker.id].beliefs
	for i in range(bs.size() - 1, -1, -1):
		var b: Dictionary = bs[i]
		if t - b["acquired"] > 4 * DAY:
			break
		var c: Dictionary = b["claim"]
		if b["acquired"] > t or listener.id in b["told_to"] or b["told_by"] == listener.id:
			continue
		var relevant: bool = c["kind"] in Memory.GOSSIP_KINDS or c["kind"] == "collision_self"
		if not relevant and c["kind"] in SCENE_KINDS and c["start"]:
			if anchors == null:
				anchors = anchors_for(sim, speaker.id, t)
			for a in anchors:
				if a[0] - 120 <= c["start"] and c["start"] <= a[1] + 120 and (a[2] == "" or not c["location"]
						or sim.world.hops(a[2], c["location"]) <= 1):
					relevant = true
					break
		if not relevant:
			continue
		if c["subject"] == listener.id and c["kind"] in OWN_TROUBLES:
			continue
		if conceals(sim, speaker, b):
			continue
		var score: float = b["salience"] * (1.5 if t - b["acquired"] < 12 * 60 else 1.0)
		cands.append([score, b["id"], b])
	cands.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
	var k := 1 + (1 if sim.rng.random() < speaker.traits["sociability"] else 0)
	var out := []
	for i in mini(k, cands.size()):
		out.append(cands[i][2])
	return out


static func tell(sim, speaker: String, listener: String, b: Dictionary, event_id: String, t: int) -> void:
	var c: Dictionary = b["claim"].duplicate()
	var err = b["error"]
	var trust: float = sim.residents[listener].r(speaker)["trust"]
	var conf: float = b["confidence"] * (0.55 + 0.35 * trust)
	var roll: float = sim.rng.random()
	if c["subject"] and c["hedged"] and roll < 0.35:
		c["hedged"] = false
		if not err:
			err = "certainty_inflated"
	elif c["start"] != null and not (c["kind"] in ["debt", "grudge"]) and roll > 0.85:
		var shift: int = sim.rng.choice([-60, -30, 30, 60])
		c["start"] += shift
		if c["end"] != null:
			c["end"] += shift
		if not err:
			err = "time_distorted"
	sim.add_belief(listener, c, "told", conf, t, {"event": event_id, "told_by": speaker, "via": b["id"], "error": err})
	b["told_to"].append(listener)


static func has_stake(sim, rid: String, suspicion: Dictionary) -> bool:
	## Only people with a stake in an incident go and confront a suspect.
	var c: Dictionary = suspicion["claim"]
	if c["other"] == rid:
		return true
	if c["obj"] and sim.world.containers.has(c["obj"]):
		return rid in sim.world.containers[c["obj"]]["owners"]
	if c["other"] and sim.residents[rid].r(c["other"])["affection"] >= 0.7:
		return true
	return c["location"] == "road" and rid == sim.landlord


static func infer_suspicions(sim, rid: String, tm: int) -> void:
	## Residents put two and two together; sometimes they make five. Only from what they hold themselves.
	var r = sim.residents[rid]
	var mem = sim.memory[rid]
	if mem.of_kind(["loss", "damage", "struck", "death"], tm - 5 * DAY).is_empty():
		return  # nothing to explain (the same answer as the full pass below, without it)
	var recent := []
	for b in mem.beliefs:
		if b["acquired"] >= tm - 5 * DAY:
			recent.append(b)
	for ib in recent:
		var c: Dictionary = ib["claim"]
		if not (c["kind"] in ["loss", "damage", "struck", "death"]) or c["start"] == null or c["location"] == null:
			continue
		if c["kind"] == "damage" and not ("fence" in c["detail"]) and not ("glass" in c["detail"]):
			continue
		var ws: int = c["start"] if c["kind"] == "loss" else c["start"] - 12 * 60
		var we: int = c["end"] if c["end"] != null else c["start"]
		var loc: String = c["location"]
		var mine := false  # nobody goes looking for the culprit of what they did themselves
		for g in r.guilty_of:
			var ge: Dictionary = sim.events.by_id[g]
			if ge["location"] == loc and ws - 60 <= ge["time"] and ge["time"] <= we + 60:
				mine = true
		if mine:
			continue
		var scores := {}
		var premises := {}
		var road := loc == "road"
		for b in recent:
			if b["id"] == ib["id"]:
				continue
			var k: Dictionary = b["claim"]
			if k["kind"] in ["presence", "sighting"] and k["start"] != null and k["location"]:
				var kend: int = k["end"] if k["end"] != null else k["start"]
				if kend >= ws - 60 and k["start"] <= we + 60 and sim.world.hops(k["location"], loc) <= 1:
					var toward: bool = sim.world.name_of(loc) in k["detail"]
					_bump(sim, r, scores, premises, k["subject"], 0.45 * b["confidence"] + (0.15 if toward else 0.0), b)
					if road and k["obj"] and sim.world.vehicles.has(k["obj"]):
						for m in sim.households[sim.world.vehicles[k["obj"]]["household"]]:
							_bump(sim, r, scores, premises, m, 0.3, b)
			elif k["kind"] in ["hardship", "rent_missed"] or (k["kind"] == "debt" and k["detail"] == "overdue"):
				_bump(sim, r, scores, premises, k["subject"], 0.2, b)
			elif k["kind"] == "refusal":
				_bump(sim, r, scores, premises, k["other"], 0.15, b)
			elif k["kind"] == "debt" and k["detail"] == "repaid" and k["start"] != null and we <= k["start"] and k["start"] <= we + 2 * DAY:
				_bump(sim, r, scores, premises, k["subject"], 0.2, b)
			elif k["kind"] == "suspect" and k["location"] == loc:
				_bump(sim, r, scores, premises, k["subject"], 0.3 * b["confidence"], b)
			elif road and k["kind"] == "vehicle_damage" and k["obj"] and sim.world.vehicles.has(k["obj"]):
				for m in sim.households[sim.world.vehicles[k["obj"]]["household"]]:
					_bump(sim, r, scores, premises, m, 0.55, b)
			elif road and k["kind"] == "intoxicated" and k["start"] != null and ws - 180 <= k["start"] and k["start"] <= we:
				_bump(sim, r, scores, premises, k["subject"], 0.15, b)
		if scores.is_empty():
			continue
		for s in scores:
			var res: float = r.r(s)["resentment"]
			if res >= 0.3:
				scores[s] += 0.25 * res
		var names: Array = scores.keys()
		names.sort_custom(func(x, y): return scores[x] > scores[y] or (scores[x] == scores[y] and x < y))
		var best: String = names[0]
		if scores[best] < 0.5:
			continue
		var claim := Memory.claim("suspect", {"subject": best, "other": c["other"], "location": loc, "start": ws,
				"end": we, "detail": c["detail"], "obj": c["obj"]})
		if mem.find(claim) != null:
			continue
		var why := [ib["id"]]
		why.append_array(premises[best].slice(0, 5))
		sim.add_belief(rid, claim, "inferred", minf(0.9, scores[best]), tm, {"premises": why})
		sim.bump("suspicions")


static func _bump(sim, r, scores: Dictionary, premises: Dictionary, s, amount: float, b: Dictionary) -> void:
	if not s or s == r.id or not sim.residents[s].alive or sim.residents[s].household == r.household:
		return
	scores[s] = float(scores.get(s, 0.0)) + amount
	if not premises.has(s):
		premises[s] = []
	premises[s].append(b["id"])
