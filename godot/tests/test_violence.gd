## Violence and accidents, Pilot 3B (scripts/sim/sim_violence.gd and its hooks), rule by rule, on a real town with
## the whole crime layer on, whose memories are cleared and whose people are placed by each scenario. Fights,
## falls and collisions are chance events: their scenarios call the real functions until one happens (each seed
## gives the same history every time). The whole-run rules (every injury and death with its cause, every repair
## after damage, every vehicle where its last drive left it, every belief with a source) are in
## scripts/sim/sim_check.gd and run from tests/test_sim.gd on every simulated month with the whole crime layer.
extends RefCounted

const Simulation = preload("res://scripts/sim/simulation.gd")
const SimCheck = preload("res://scripts/sim/sim_check.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Memory = preload("res://scripts/sim/sim_memory.gd")
const Gossip = preload("res://scripts/sim/sim_gossip.gd")
const Decisions = preload("res://scripts/sim/sim_decisions.gd")
const Crime = preload("res://scripts/sim/sim_crime.gd")
const Violence = preload("res://scripts/sim/sim_violence.gd")
const Incidents = preload("res://scripts/sim/sim_incidents.gd")

const DAY := 1440


func run(t, _tree) -> void:
	_fight(t)
	_peacemakers(t)
	_collisions(t)
	_falls(t)
	_found_and_treated(t)
	_home_alone(t)
	_patients_accounts(t)
	_repairs(t)
	_death(t)
	_concealment(t)
	_whole_months(t)


# ---------------------------------------------------------------- staging
func _fresh(seed := 3):
	## A town at Day 2 10:00 (a Tuesday) with the whole crime layer, where nobody knows anything yet, nobody bears
	## a grudge, and everyone is awake at home.
	var sim = Simulation.new({"seed": seed, "days": 6, "crime": true})
	sim.t = SimClock.at(2, 10)
	for rid in sim.ids:
		sim.memory[rid] = Memory.new(rid)
		var r = sim.residents[rid]
		r.asleep = false
		sim.intervals[rid] = [[r.home, 0, -1]]
		for o in sim.ids:
			if o != rid:
				r.r(o)["resentment"] = 0.0
	sim.beliefs = {}
	sim.world.debts.clear()
	return sim


func _put(sim, rid: String, node: String) -> void:
	sim.intervals[rid] = [[node, 0, -1]]


static func _events(sim, kind: String) -> Array:
	var out := []
	for id in sim.events.by_id:
		if sim.events.by_id[id]["kind"] == kind:
			out.append(sim.events.by_id[id])
	return out


static func _evidence(sim, kind: String) -> Array:
	var out := []
	for e in sim.world.evidence:
		if e["kind"] == kind:
			out.append(e)
	return out


static func _with_role(sim, role: String) -> String:
	for rid in sim.ids:
		if sim.residents[rid].role == role:
			return rid
	return ""


static func _others(sim, exclude: Array) -> Array:
	## Residents of other households than everyone in ``exclude``.
	var homes := {}
	for x in exclude:
		homes[sim.residents[x].household] = true
	var out := []
	for x in sim.ids:
		if not homes.has(sim.residents[x].household):
			out.append(x)
	return out


func _knowledge(sim) -> Array:
	## Every belief has a plausible source (the whole-run rule), over what the scenario made happen.
	sim.events.commit()
	sim.t = SimClock.at(7, 0)
	var out := []
	SimCheck._check_memory(sim, out)
	return out


func _stage_fall(sim, rid: String, at: int, severity: int) -> Dictionary:
	## Someone fell into the ditch on Mill Road and remembers it.
	_put(sim, rid, "road")
	var ev: Dictionary = sim.emit("fall", "road", [rid], {"data": {"severity": severity}, "intent": "accidental",
			"audibility": 1, "notable": true, "time": at, "summary": "%s falls into the ditch." % sim.n(rid)})
	Incidents.register(sim, {"family": "fall", "core_event": ev["id"], "time": at, "location": "road", "responsible": null,
			"victims": [rid], "intent": "accidental", "mechanism": "accidental_fall", "outcome": "accident",
			"severity": severity, "hook_kind": "person_injured", "motive": "none"})
	Violence.injure(sim, sim.residents[rid], severity, ev, Violence.INJURY_TEXT["fall%d" % severity])
	sim.add_belief(rid, Memory.claim("fall", {"subject": rid, "location": "road", "start": at,
			"detail": "slipped into the ditch"}), "self", 0.9, at, {"event": ev["id"]})
	if severity == 2:
		sim.residents[rid].down = true
	return ev


# ---------------------------------------------------------------- scenarios
func _fight(t) -> void:
	t.begin("a fight: seen in the room, heard next door, a trace of blood if it was bad, and the victim hurt or killed")
	var sim = _fresh()
	var ids: Array = sim.ids
	var a: String = ids[0]
	var b: String = _others(sim, [a])[0]
	var witness: String = _others(sim, [a, b])[0]
	var listeners: Array = _others(sim, [a, b, witness]).slice(0, 4)
	for x in [a, b, witness]:
		_put(sim, x, "pub")
	for x in listeners:
		_put(sim, x, "square")
	var now := SimClock.at(2, 20, 10)
	var argument: Dictionary = sim.emit("argument", "pub", [a], {"targets": [b], "data": {"reason": "grudge",
			"topic": "an old grievance"}, "audibility": 2, "time": now})
	Violence.assault(sim, sim.residents[a], sim.residents[b], argument, "pub", now + 2, [], "grudge")
	var fights := _events(sim, "assault")
	t.eq(fights.size(), 1, "a fight")
	if fights.is_empty():
		t.end()
		return
	var ev: Dictionary = fights[0]
	var severity: int = ev["data"]["severity"]
	var inc: Dictionary = Incidents.incident_for(sim, ev["id"])
	t.eq([inc.get("family"), inc.get("responsible"), inc.get("victims"), inc.get("related_events")],
			["assault", a, [b], [argument["id"]]], "registered as the attacker's, after the argument")
	t.check(ev["id"] in sim.residents[a].guilty_of, "the attacker knows what they did")
	t.check(sim.residents[b].r(a)["resentment"] >= 0.5 and sim.residents[b].r(a)["trust"] == 0.05,
			"the victim resents and distrusts them")
	var saw := 0
	for bl in sim.memory[witness].beliefs:
		if bl["claim"]["kind"] == "assault" and bl["source"] == "saw":
			saw += 1
	t.eq(saw, 1, "the witness in the room saw it")
	var heard := 0
	for x in listeners:
		for bl in sim.memory[x].beliefs:
			t.eq([bl["source"], bl["claim"]["kind"]], ["heard", "noise"], "the square only hears a scuffle")
			heard += 1
	t.check(heard > 0, "someone on the square hears it (%d)" % heard)
	t.eq(_evidence(sim, "blood").size(), 1 if severity >= 2 else 0, "blood only after a bad fight (severity %d)" % severity)
	if severity == 3:
		t.check(not sim.residents[b].alive and _evidence(sim, "body").size() == 1, "killed: a body lies there")
	else:
		var v = sim.residents[b]
		t.eq([v.injury, v.injury_event, v.injury_treated], [severity, ev["id"], false], "the victim is hurt, untreated")
		t.eq([inc["discovered_at"], inc["discovered_by"]], [now + 2, b], "and the fight is known: the victim was in it")
	t.eq(_knowledge(sim), [], "every belief has a plausible source")
	t.end()


func _peacemakers(t) -> void:
	t.begin("bystanders may pull them apart, and then nobody is badly hurt")
	var pulled := 0
	for seed in [3, 4, 5, 6, 7, 8]:
		var sim = _fresh(seed)
		var a: String = sim.ids[0]
		var b: String = _others(sim, [a])[0]
		var bystanders: Array = _others(sim, [a, b]).slice(0, 3)
		for x in [a, b] + bystanders:
			_put(sim, x, "pub")
		var now := SimClock.at(2, 20, 10)
		var argument: Dictionary = sim.emit("argument", "pub", [a], {"targets": [b], "time": now})
		Violence.assault(sim, sim.residents[a], sim.residents[b], argument, "pub", now + 2, bystanders, "grudge")
		var stepped_in := _events(sim, "intervened")
		if stepped_in.is_empty():
			continue
		pulled += 1
		t.eq(_events(sim, "assault")[0]["data"]["severity"], 1, "pulled apart: a minor injury at most")
		for x in stepped_in[0]["actors"]:
			t.check(x in bystanders, "only bystanders step in")
	t.check(pulled > 0, "with three bystanders, someone usually steps in (%d of 6)" % pulled)
	t.end()


func _collisions(t) -> void:
	t.begin("a drunk driver on Mill Road at night: a walker or the fence, traces, then owning up or driving on")
	var fled := 0
	var stopped := 0
	var struck := 0
	for seed in range(3, 19):
		var sim = _fresh(seed)
		var night := SimClock.at(1, 23)
		var driver := ""
		for rid in sim.ids:
			if sim.residents[rid].vehicle != "" and sim.residents[rid].role != "mechanic":
				driver = rid
				break
		if driver == "":
			continue
		var d = sim.residents[driver]
		var will_flee := seed % 2 == 0
		d.intox = 100.0 if will_flee else 70.0
		d.traits["honesty"] = 0.0 if will_flee else 1.0
		d.traits["empathy"] = 0.0 if will_flee else 1.0
		d.traits["caution"] = 1.0 if will_flee else 0.0
		var walkers: Array = _others(sim, [driver]).slice(0, 2)
		for w in walkers:
			_put(sim, w, "road")
		sim._route(driver, "mill", night + 5, true)
		var vid: String = d.vehicle
		for attempt in 150:
			Violence.check_collision(sim, driver, night, walkers)
			if not _events(sim, "collision").is_empty():
				break
		var hits := _events(sim, "collision")
		if hits.is_empty():
			continue
		var ev: Dictionary = hits[0]
		var inc: Dictionary = Incidents.incident_for(sim, ev["id"])
		var veh: Dictionary = sim.world.vehicles[vid]
		var victim: String = ev["targets"][0] if not ev["targets"].is_empty() else ""
		t.check(veh["damage"] != "" and veh["damage_event"] == ev["id"], "the vehicle is damaged")
		t.eq([_evidence(sim, "vehicle_damage").size(), _evidence(sim, "debris").size()], [1, 1],
				"traces: the damage, and debris on the road")
		t.eq(sim.memory[driver].of_kind(["collision_self"]).size(), 1, "the driver knows what they hit")
		if victim != "":
			struck += 1
			t.check(not sim.memory[victim].of_kind(["struck"]).is_empty(), "and whoever was struck knows it")
		for w in walkers:
			if w != victim:
				var seen: Array = sim.memory[w].of_kind(["saw_collision"])
				t.check(seen.size() == 1 and seen[0]["source"] == "saw", "the other walker on the road saw it")
		if inc["fled"]:
			fled += 1
			t.check(ev["id"] in d.guilty_of and d.wants_repair and inc["outcome"] == "crime",
					"a driver who drives on is guilty of it, and wants the damage mended quietly")
			if victim != "":
				var v = sim.residents[victim]
				var sev: int = ev["data"]["severity"]
				if sev == 2:
					t.check(v.down and sim.loc(victim) == "road", "seriously hurt: left lying on the road")
				elif sev == 1:
					t.eq([v.injury, inc["discovered_by"]], [1, victim], "a minor injury: they walk on, and know it")
		else:
			stopped += 1
			t.check(inc["reported_openly"] and inc["outcome"] == "accident" and inc["discovered_at"] != null,
					"a driver who stops owns up: an accident, out in the open")
			t.check(not (ev["id"] in d.guilty_of), "and has nothing to hide")
			if victim != "":
				var named := false
				for bl in sim.memory[victim].of_kind(["struck"]):
					named = named or bl["claim"]["subject"] == driver
				t.check(named, "the one struck knows who hit them")
		t.eq(_knowledge(sim), [], "every belief has a plausible source")
		if fled > 0 and stopped > 0 and struck > 0:
			break
	t.check(fled > 0 and stopped > 0 and struck > 0, "seen: drivers who drove on (%d), who stopped (%d), walkers struck (%d)" % [
			fled, stopped, struck])
	t.end()


func _falls(t) -> void:
	t.begin("a drunk walker falls into the ditch: hurt, a trace, and a memory that may blame someone resented")
	var falls := 0
	var blamed := 0
	for seed in range(3, 23):
		var sim = _fresh(seed)
		var night := SimClock.at(1, 23)
		var w: String = sim.ids[1]
		var x: String = _others(sim, [w])[0]
		var r = sim.residents[w]
		r.intox = 100.0
		r.r(x)["resentment"] = 0.6
		var seen: Dictionary = sim.add_belief(w, Memory.claim("presence", {"subject": x, "location": r.home,
				"start": night - 120, "end": night - 60}), "saw", 0.9, night - 120, {"event": null})  # x called round
		sim._route(w, "mill", night + 5, false)
		for attempt in 150:
			Violence.check_fall(sim, w, night)
			if not _events(sim, "fall").is_empty():
				break
		var fell := _events(sim, "fall")
		if fell.is_empty():
			continue
		falls += 1
		var ev: Dictionary = fell[0]
		var inc: Dictionary = Incidents.incident_for(sim, ev["id"])
		t.eq([inc.get("family"), inc.get("responsible"), inc.get("victims")], ["fall", null, [w]], "an accident, nobody's doing")
		t.eq([r.injury_event, _evidence(sim, "debris").size()], [ev["id"], 1], "hurt, and scuff marks on the ditch bank")
		if ev["data"]["severity"] == 2:
			t.check(r.down and sim.loc(w) == "road", "badly hurt: lying in the ditch")
		var memories: Array = sim.memory[w].of_kind(["fall", "assault", "injury"])
		t.eq(memories.size(), 1, "one memory of how it happened")
		for bl in memories:
			if bl["claim"]["kind"] == "assault":
				blamed += 1
				t.eq([bl["source"], bl["error"], bl["claim"]["subject"], bl["claim"]["hedged"], bl["premises"]],
						["inferred", "mistaken_inference", x, true, [seen["id"]]],
						"too drunk to know: they blame someone they resent and saw that night, mistakenly")
		t.eq(_knowledge(sim), [], "every belief has a plausible source")
		if blamed > 0 and falls >= 3:
			break
	t.check(falls > 0 and blamed > 0, "falls happen (%d), and some are blamed on someone (%d)" % [falls, blamed])
	t.end()


func _found_and_treated(t) -> void:
	t.begin("someone lying hurt is found, says what happened, and is treated at the clinic")
	var sim = _fresh()
	var nurse := _with_role(sim, "nurse")
	var v: String = _others(sim, [nurse])[0]
	var finder: String = _others(sim, [nurse, v])[0]
	var fall := _stage_fall(sim, v, SimClock.at(2, 2), 2)
	sim.intervals[finder] = [[sim.residents[finder].home, 0, SimClock.at(2, 10, 10)], ["road", SimClock.at(2, 10, 10), -1]]
	Violence.found_checks(sim, SimClock.at(2, 10))
	var found := _events(sim, "injury_found")
	t.eq(found.size(), 1, "found by the first person to come by")
	if found.is_empty():
		t.end()
		return
	t.eq([found[0]["actors"], found[0]["targets"]], [[finder], [v]], "the finder finds them")
	t.check(not sim.residents[v].down, "and helps them up")
	var told: Array = sim.memory[finder].of_kind(["fall"])
	t.check(told.size() == 1 and told[0]["source"] == "told" and told[0]["told_by"] == v,
			"they say they slipped into the ditch: the finder is told")
	t.eq([sim.forced[v]["kind"], sim.forced[finder]["kind"]], ["clinic", "escort"], "to the clinic, escorted")
	var inc: Dictionary = Incidents.incident_for(sim, fall["id"])
	t.eq([inc["discovered_by"], inc["title"]], [finder, "Found in the Ditch"], "the fall is discovered")
	# at the clinic
	_put(sim, nurse, "clinic")
	sim.plans[nurse] = Decisions.plan("work", "clinic")
	sim.intervals[v].append(["clinic", SimClock.at(2, 11, 20), -1])
	sim.intervals[v][-2][2] = SimClock.at(2, 11, 20)
	Violence.clinic(sim, sim.residents[v], SimClock.at(2, 11, 46))
	var treated := _events(sim, "treated")
	t.check(treated.size() == 1 and sim.residents[v].injury_treated, "the nurse treats them")
	var log: Array = sim.world.records["clinic_log"]
	t.check(not log.is_empty() and "slipped into the ditch" in String(log[-1]["text"]), "and writes down what they say")
	t.check(not sim.memory[nurse].of_kind(["injury"]).is_empty() and not sim.memory[nurse].of_kind(["fall"]).is_empty(),
			"the nurse saw the injury and heard the account")
	t.eq(_knowledge(sim), [], "every belief has a plausible source")
	t.end()


func _home_alone(t) -> void:
	t.begin("nobody comes by: by mid-morning someone hurt manages home on their own")
	var sim = _fresh(5)
	var v: String = sim.ids[2]
	_stage_fall(sim, v, SimClock.at(2, 2), 2)
	Violence.found_checks(sim, SimClock.at(2, 9))
	t.check(sim.residents[v].down, "still lying there at nine")
	Violence.found_checks(sim, SimClock.at(2, 10))
	t.check(not sim.residents[v].down and sim.forced[v]["dest"] == sim.residents[v].home, "at ten they get up and go home")
	t.eq(_events(sim, "injury_found"), [], "nobody found them")
	t.end()


func _patients_accounts(t) -> void:
	t.begin("what the hurt say: the truth, or (fond of whoever hit them) a door they walked into")
	for honest in [true, false]:
		var sim = _fresh()
		var nurse := _with_role(sim, "nurse")
		var a: String = _others(sim, [nurse])[0]
		var v: String = _others(sim, [nurse, a])[0]
		var p = sim.residents[v]
		p.traits["honesty"] = 0.9 if honest else 0.5
		p.r(a)["affection"] = 0.3 if honest else 0.8
		_put(sim, v, "pub")
		var fight: Dictionary = sim.emit("assault", "pub", [a], {"targets": [v], "data": {"severity": 1}, "time": SimClock.at(1, 21)})
		Violence.injure(sim, p, 1, fight, Violence.INJURY_TEXT["assault1"])
		sim.add_belief(v, Memory.claim("assault", {"subject": a, "other": v, "location": "pub", "start": SimClock.at(1, 21)}),
				"self", 1.0, SimClock.at(1, 21), {"event": fight["id"]})
		_put(sim, nurse, "clinic")
		sim.plans[nurse] = Decisions.plan("work", "clinic")
		sim.intervals[v].append(["clinic", SimClock.at(2, 10, 20), -1])
		sim.intervals[v][-2][2] = SimClock.at(2, 10, 20)
		Violence.clinic(sim, p, SimClock.at(2, 10, 46))
		var account: String = _events(sim, "treated")[0]["data"]["account"]
		var heard: Array = sim.memory[nurse].of_kind(["assault"])
		if honest:
			t.eq([account, heard.size()], ["%s hit me." % sim.n(a), 1], "an honest patient names who hit them")
		else:
			t.eq([account, heard.size()], ["I walked into a door, that's all.", 0], "a fond one covers for them")
		t.eq(sim.memory[nurse].of_kind(["injury"]).size(), 1, "either way the nurse sees the injury")
		t.eq(_knowledge(sim), [], "every belief has a plausible source")
	t.end()


func _repairs(t) -> void:
	t.begin("the workshop mends a damaged vehicle; a driver who drove on lies about how it happened")
	for guilty in [true, false]:
		var sim = _fresh()
		var mech := _with_role(sim, "mechanic")
		var driver := ""
		for rid in sim.ids:
			if sim.residents[rid].vehicle != "" and sim.residents[rid].household != sim.residents[mech].household:
				driver = rid
				break
		var d = sim.residents[driver]
		var vid: String = d.vehicle
		var veh: Dictionary = sim.world.vehicles[vid]
		var crash: Dictionary = sim.emit("collision", "road", [driver], {"objects": [vid], "data": {"vehicle": vid,
				"struck": "fence", "severity": 0}, "time": SimClock.at(1, 23, 20)})
		veh["damage"] = "a dented front bumper, a cracked headlight and flecks of white paint and wood splinters in the grille"
		veh["damage_event"] = crash["id"]
		veh["damage_evidence"] = sim.world.add_evidence("vehicle_damage", vid, "damage", SimClock.at(1, 23, 20), crash["id"],
				[driver])["id"]
		Incidents.register(sim, {"family": "collision", "core_event": crash["id"], "time": SimClock.at(1, 23, 20),
				"location": "road", "responsible": driver, "fled": guilty, "reported_openly": not guilty})
		if guilty:
			d.guilty_of.append(crash["id"])
		d.wants_repair = true
		d.cash = 60
		veh["location"] = "workshop"
		_put(sim, driver, "workshop")
		_put(sim, mech, "workshop")
		sim.plans[mech] = Decisions.plan("work", "workshop")
		var paid: int = sim.residents[mech].cash
		Violence.repair(sim, d, SimClock.at(2, 10, 46))
		var fixed := _events(sim, "repair")
		t.eq(fixed.size(), 1, "the mechanic repairs it")
		if fixed.is_empty():
			continue
		t.eq([veh["damage"], d.wants_repair, sim.residents[mech].cash], ["", false, paid + 25], "mended and paid for")
		t.check(_evidence(sim, "vehicle_damage")[0]["removed_by"] == fixed[0]["id"] and _evidence(sim, "scrap").size() == 1,
				"the damage is gone; the old parts lie in the scrap pile")
		var told: Array = sim.memory[mech].of_kind(["repair"])
		t.eq(told.size(), 1, "the mechanic is told how it happened")
		if guilty:
			t.eq([fixed[0]["data"]["concealed"], told[0]["error"], told[0]["claim"]["detail"]],
					[true, "lie", "Hit a deer out on the ridge road a few nights back."], "a lie, from the one who drove on")
		else:
			t.eq([fixed[0]["data"]["concealed"], told[0]["error"], told[0]["claim"]["detail"]],
					[false, null, "Clipped the fence on Mill Road."], "the truth, from one who owned up")
		t.eq(sim.memory[mech].of_kind(["vehicle_damage"]).size(), 1, "and saw the damage")
		t.eq(_knowledge(sim), [], "every belief has a plausible source")
	t.end()


func _death(t) -> void:
	t.begin("a death: missed by whoever is fondest of them, found where they lie, and buried three days on")
	var sim = _fresh()
	var v: String = sim.ids[3]
	var carer: String = _others(sim, [v])[0]
	var passer: String = _others(sim, [v, carer])[0]
	for x in sim.ids:
		if x != v:
			sim.residents[x].r(v)["affection"] = 0.9 if x == carer else 0.1
	var last_seen := SimClock.at(1, 20)
	sim.add_belief(carer, Memory.claim("presence", {"subject": v, "location": sim.residents[carer].home,
			"start": last_seen - 60, "end": last_seen}), "saw", 0.9, last_seen - 60, {"event": null})  # v called round
	var fall := _stage_fall(sim, v, SimClock.at(1, 23, 30), 2)
	Violence.kill(sim, sim.residents[v], fall, SimClock.at(1, 23, 31))
	t.check(not sim.residents[v].alive and _evidence(sim, "body").size() == 1, "dead, where they fell")
	Violence.missed_people(sim, SimClock.at(2, 10))
	t.eq(_events(sim, "missed"), [], "not missed before half a day has passed")
	Violence.missed_people(sim, SimClock.at(2, 12))
	var missed := _events(sim, "missed")
	t.check(missed.size() == 1 and missed[0]["actors"] == [carer], "missed by whoever is fondest of them")
	var miss: Array = sim.memory[carer].of_kind(["missing"])
	t.check(miss.size() == 1 and miss[0]["claim"]["start"] == last_seen,
			"since they last saw them (not the true time of death, which they cannot know)")
	t.eq([sim.forced[carer]["kind"], sim.forced[carer]["dest"]], ["check_on", sim.residents[v].home], "and goes to check on them")
	sim.intervals[passer] = [[sim.residents[passer].home, 0, SimClock.at(2, 13, 15)], ["road", SimClock.at(2, 13, 15), -1]]
	Violence.found_checks(sim, SimClock.at(2, 13))
	var found := _events(sim, "body_found")
	t.check(found.size() == 1 and found[0]["actors"] == [passer], "found by someone passing on the road")
	t.check(v in sim.found_bodies and passer in _evidence(sim, "body")[0]["noticed_by"], "who saw the body")
	t.eq(sim.memory[passer].of_kind(["death"]).size(), 1, "and knows of the death")
	var inc: Dictionary = Incidents.incident_for(sim, fall["id"])
	t.eq(inc["discovered_by"], passer, "the death is discovered")
	Crime.tidy_evidence(sim, SimClock.at(4, 23))
	t.eq(_events(sim, "burial"), [], "not buried before three days")
	Crime.tidy_evidence(sim, SimClock.at(5, 0))
	t.check(_events(sim, "burial").size() == 1 and _evidence(sim, "body")[0]["removed_at"] >= 0, "then taken away and buried")
	t.eq(_knowledge(sim), [], "every belief has a plausible source")
	t.end()


func _concealment(t) -> void:
	t.begin("a driver keeps a collision to themselves, unless they owned up on the spot")
	var sim = _fresh()
	var driver := ""
	for rid in sim.ids:
		if sim.residents[rid].vehicle != "":
			driver = rid
			break
	var crash: Dictionary = sim.emit("collision", "road", [driver], {"objects": [sim.residents[driver].vehicle],
			"time": SimClock.at(1, 23, 20)})
	var inc: Dictionary = Incidents.register(sim, {"family": "collision", "core_event": crash["id"],
			"time": SimClock.at(1, 23, 20), "location": "road", "responsible": driver, "fled": true})
	var b: Dictionary = sim.add_belief(driver, Memory.claim("collision_self", {"subject": driver, "location": "road",
			"start": SimClock.at(1, 23, 20), "detail": "hit the fence"}), "self", 1.0, SimClock.at(1, 23, 20),
			{"event": crash["id"]})
	t.check(Gossip.conceals(sim, sim.residents[driver], b), "after driving on, they say nothing")
	inc["reported_openly"] = true
	t.check(not Gossip.conceals(sim, sim.residents[driver], b), "having owned up, they talk about it")
	t.end()


func _whole_months(t) -> void:
	t.begin("whole months with the whole crime layer: every rule holds")
	var tally := {}
	for profile in ["scarcity", "crisis", "tension"]:
		var sim = Simulation.new({"seed": 4, "days": 30, "profile": profile, "crime": true}).run()
		var problems: Array = SimCheck.problems(sim)
		t.check(problems.is_empty(), "%s: %d problems, first: %s" % [profile, problems.size(), problems.slice(0, 3)])
		var counts: Dictionary = sim.events.counts()
		for k in ["theft", "assault", "fall", "collision", "death", "treated", "repair", "injury_found"]:
			tally[k] = int(tally.get(k, 0)) + int(counts.get(k, 0))
	print("  whole months with the whole crime layer: %s" % JSON.stringify(tally))
	t.end()
