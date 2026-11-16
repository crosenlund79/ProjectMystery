## Seeing and hearing (mirrors the perception parts of mystery/sim/engine.py). Every belief formed here comes
## from where the holder actually was, at that minute, awake or asleep, in daylight or in the dark:
##   broadcast   an event is seen by those at the same place and awake, heard by those asleep there or close
##               enough for how loud it was (audibility: 1 same place, 2 next door, 3 two places away)
##   co_presence at the end of each hour, people notice who is with them; outdoors after dark they may not
##               know who it is, or think it is someone else
##   doorways    housemates notice comings and goings late in the day, or hear the door in their sleep
##   transit     people out and about see others pass on the square and on Mill Road
## Recognition fails more in the dark, with strangers, from a moving vehicle and after drink; a wrong guess
## falls on someone the observer already dislikes.
extends RefCounted

const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Memory = preload("res://scripts/sim/sim_memory.gd")


static func familiarity(sim, observer: String, subject: String) -> float:
	var rel: Dictionary = sim.residents[observer].r(subject)
	return (rel["trust"] + rel["affection"]) / 2.0


static func biased_pick(sim, observer: String, exclude: Array):
	## When people guess wrongly, they guess people they already dislike. Returns an id or null.
	var r = sim.residents[observer]
	var pool := []
	for x in sim.ids:
		if not (x in exclude) and x != observer and sim.residents[x].alive:
			pool.append(x)
	if pool.is_empty():
		return null
	var weights := []
	var total := 0.0
	for x in pool:
		var w: float = 0.2 + r.r(x)["resentment"] * 2
		weights.append(w)
		total += w
	var roll: float = sim.rng.random() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0:
			return pool[i]
	return pool[-1]


static func identify(sim, observer: String, subject: String, location: String, t: int, in_vehicle := false) -> Array:
	## [who the observer thinks it was (or null: they couldn't tell), error or null]
	var r = sim.residents[observer]
	var outdoor_dark: bool = sim.world.locations[location]["outdoor"] and SimClock.is_dark(t)
	var p := 0.97
	if outdoor_dark:
		p = 0.3 + 0.35 * familiarity(sim, observer, subject)
	if in_vehicle:
		p = 0.15 if outdoor_dark else 0.6
	p -= maxf(0.0, r.intox - 40) * 0.006
	if sim.rng.random() < p:
		return [subject, null]
	if sim.rng.random() < 0.22:
		return [biased_pick(sim, observer, [subject]), "misidentified"]
	return [null, null]


static func broadcast(sim, ev: Dictionary, seen = null, heard = null, voice = null, exclude := []) -> void:
	## Everyone physically able to notice ``ev`` forms a belief about it.
	var loud: int = ev["audibility"]
	for rid in sim.ids:
		var r = sim.residents[rid]
		if not r.alive or r.down or rid in ev["actors"] or rid in ev["targets"] or rid in exclude:
			continue
		var where: String = sim.where(rid, ev["time"])
		if where == "":
			continue
		var hops: int = sim.world.hops(where, ev["location"])
		var mode := ""
		if hops == 0 and not r.asleep and not ev.get("discreet", false):
			mode = "saw"
		elif hops == 0 and r.asleep and loud >= 1 and sim.rng.random() < 0.5:
			mode = "heard"
		elif 1 <= hops and hops <= loud - 1:
			var p := 0.85 if hops == 1 else 0.5
			if r.asleep:
				p *= 0.4
			if sim.rng.random() < p:
				mode = "heard"
		if mode == "saw" and seen != null:
			var c: Dictionary = seen.duplicate()
			var err = null
			if c["subject"]:
				var who: Array = identify(sim, rid, c["subject"], ev["location"], ev["time"])
				c["subject"] = who[0]
				err = who[1]
			if c["other"]:
				var other: Array = identify(sim, rid, c["other"], ev["location"], ev["time"])
				c["other"] = other[0]
				if err == null:
					err = other[1]
			sim.add_belief(rid, c, "saw", 0.9 if err == null else 0.6, ev["time"], {"event": ev["id"], "error": err})
			sim.perceived[rid + "|" + ev["id"]] = "saw"
		elif mode != "" and heard != null:
			var c: Dictionary = heard.duplicate()
			var err = null
			if voice != null:
				var p_voice: float = 0.25 + 0.45 * familiarity(sim, rid, voice) - (0.25 if hops > 0 else 0.0)
				var roll: float = sim.rng.random()
				if roll < p_voice:
					c["subject"] = voice
					c["hedged"] = true
				elif roll < p_voice + 0.12:
					c["subject"] = biased_pick(sim, rid, [voice])
					c["hedged"] = true
					err = "misidentified"
			sim.add_belief(rid, c, "heard", 0.6, ev["time"], {"event": ev["id"], "error": err})
			sim.perceived[rid + "|" + ev["id"]] = "heard"
			if r.asleep and loud >= 3:
				r.stress = clampf(r.stress + 3, 0.0, 100.0)


static func co_presence(sim, tm: int) -> void:
	var groups := {}
	for r in sim.alive():
		if r.asleep or r.down:
			continue
		var node: String = sim.where(r.id, tm)
		if not groups.has(node):
			groups[node] = []
		groups[node].append(r.id)
	var nodes: Array = groups.keys()
	nodes.sort()
	for node in nodes:
		var people: Array = groups[node]
		if people.size() < 2 or node == "":
			continue
		var outdoor_dark: bool = sim.world.locations[node]["outdoor"] and SimClock.is_dark(tm)
		for obs in people:
			for subj in people:
				if obs == subj:
					continue
				var s = sim.residents[subj]
				if outdoor_dark:
					var who: Array = identify(sim, obs, subj, node, tm)
					var c := Memory.claim("sighting", {"subject": who[0], "location": node, "start": tm, "end": tm,
							"detail": "out after dark", "hedged": who[0] != null})
					sim.add_belief(obs, c, "saw", 0.6, tm, {"error": who[1]})
				else:
					observe_presence(sim, obs, subj, node, tm)
				if s.intox >= 55:
					sim.add_belief(obs, Memory.claim("intoxicated", {"subject": subj, "location": node, "start": tm}),
							"saw", 0.8, tm)


static func observe_presence(sim, obs: String, subj: String, node: String, t: int) -> void:
	var mem = sim.memory[obs]
	var k := subj + "|" + node
	var b = mem.open_presence.get(k)
	if b != null and b["claim"]["end"] != null and 0 <= t - b["claim"]["end"] and t - b["claim"]["end"] <= 75:
		b["claim"]["end"] = t
		return
	var c := Memory.claim("presence", {"subject": subj, "location": node, "start": t, "end": t})
	mem.open_presence[k] = sim.add_belief(obs, c, "saw", 0.9, t)


static func doorways(sim, rid: String) -> void:
	## Housemates notice comings and goings: awake ones see them, sleeping ones may hear the door.
	var mv: Dictionary = sim.moves[rid]
	var path: Array = mv["path"]
	var times: Array = mv["times"]
	if path.size() < 2:
		return
	for spec in [[path[0], times[1], "heading out"], [path[-1], times[-1], "coming home"]]:
		var node: String = spec[0]
		var t: int = spec[1]
		var loc: Dictionary = sim.world.locations[node]
		if loc["kind"] != "home":
			continue
		var late: bool = SimClock.is_dark(t) or SimClock.hour_of(t) >= 21
		for m in sim.households[loc["household"]]:
			var x = sim.residents[m]
			if m == rid or not x.alive or x.down or sim.where(m, t) != node:
				continue
			if not x.asleep and late and sim.rng.random() < 0.8:
				var c := Memory.claim("sighting", {"subject": rid, "location": node, "start": t, "end": t,
						"detail": spec[2]})
				sim.add_belief(m, c, "saw", 0.9, t, {"event": mv["event"]})
				sim.perceived[m + "|" + mv["event"]] = "saw"
			elif x.asleep and late and sim.rng.random() < 0.3:
				var what := "the door go — someone going out" if spec[2] == "heading out" else "the door — someone coming in"
				var c := Memory.claim("noise", {"subject": rid, "location": node, "start": t, "detail": what,
						"hedged": true})
				sim.add_belief(m, c, "heard", 0.6, t, {"event": mv["event"]})
				sim.perceived[m + "|" + mv["event"]] = "heard"


static func transit_sightings(sim, rid: String) -> void:
	var mv: Dictionary = sim.moves[rid]
	var path: Array = mv["path"]
	var times: Array = mv["times"]
	for i in range(1, path.size() - 1):
		var node: String = path[i]
		if not sim.world.locations[node]["outdoor"]:
			continue
		var s: int = times[i]
		var e: int = times[i + 1]
		for obs in sim.ids:
			var o = sim.residents[obs]
			if obs == rid or not o.alive or o.asleep or o.down:
				continue
			var when: int = sim.overlap_start(obs, node, s, e)
			if when < 0:
				continue
			if sim.rng.random() >= (0.85 if SimClock.is_dark(s) else 0.45):
				continue
			sighting(sim, obs, rid, node, when, path[i + 1], mv)


static func sighting(sim, obs: String, subj: String, node: String, t: int, toward: String, mv: Dictionary) -> void:
	var dark := SimClock.is_dark(t)
	var veh_id: String = mv["vehicle"]
	var obj = null
	var who: Array
	var detail := ""
	if veh_id != "":
		var veh: Dictionary = sim.world.vehicles[veh_id]
		who = identify(sim, obs, subj, node, t, true)
		var recognised: bool = sim.rng.random() < (0.8 if dark else 0.95)
		obj = veh_id if recognised else null
		var what: String = veh["name"] if recognised else "a " + veh["kind"]
		detail = "%s heading toward %s" % [what, sim.world.name_of(toward)]
	else:
		who = identify(sim, obs, subj, node, t)
		detail = "heading toward " + sim.world.name_of(toward)
		if who[0] != null and sim.residents[subj].intox >= 60:
			detail += ", unsteady on their feet"
	var c := Memory.claim("sighting", {"subject": who[0], "location": node, "start": t, "end": t, "detail": detail,
			"obj": obj, "hedged": who[0] != null and dark})
	sim.add_belief(obs, c, "saw", 0.6 if dark else 0.85, t, {"event": mv["event"], "error": who[1]})
	sim.perceived[obs + "|" + mv["event"]] = "saw"
