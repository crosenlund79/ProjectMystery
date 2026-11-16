## Theft and financial incidents (mirrors the theft, ledger, discovery and evidence parts of mystery/sim/actions.py
## and engine.py). The crime layer, Pilot 3A: it runs only with config "crime" (scripts/sim/sim_config.gd).
## Whether someone steals at all is decided with every other option they have (sim_decisions.gd, _steal_intent).
##
##   steal            aborted if anyone else is there; a locked door is forced (a trace, and a crack of
##                    splintering wood next door); the loot goes into the thief's own hidden stash
##   hide_loot        back home, the thief hides it (a trace at home); stolen food goes into their pantry
##                    (the stash is spent from later: simulation.gd, _morning_cash)
##   ledger_error     a clerk writes a sale into the ledger twice: the books expect money that never came in
##   loss_discovered  someone counting a till, the stock or a savings tin finds it short. Apart from the thief, this
##                    is the only way anyone learns that something went
##   notice, tidy     traces are noticed by those who come by (more surely by day) and cleared away after a while
##   confess          accused of what they did, an honest culprit may own up and hand back the money
##
## Truth and belief stay apart. The thief knows what they did (theft_self, stash: never passed on). Nobody else
## knows a theft happened until a count shows a shortfall, a trace is noticed, or the culprit confesses; whom
## they then suspect is inferred from what they themselves hold (sim_gossip.gd, infer_suspicions), and may be
## wrong. Every change is an event, every trace points at the event that made it, and every incident is in the
## registry (sim_incidents.gd) with the events that belong to it.
extends RefCounted

const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Memory = preload("res://scripts/sim/sim_memory.gd")
const Perception = preload("res://scripts/sim/sim_perception.gd")
const Incidents = preload("res://scripts/sim/sim_incidents.gd")

const DAY := 1440
## Traces people notice in passing, and how long a trace stays before someone clears it away (minutes).
const NOTICED_KINDS := ["debris", "vehicle_damage", "forced_door", "blood"]
const TIDY_AFTER := {"debris": 36 * 60, "blood": 20 * 60, "forced_door": 30 * 60}


static func recent_pressures(r, now: int) -> Array:
	## The last four things that went wrong for them in the past week: what drove them to it.
	var out := []
	for p in r.pressures:
		if now - int(p[0]) <= 7 * DAY:
			out.append(p[1])
	return out.slice(maxi(0, out.size() - 4))


# ================================================================ theft
static func steal(sim, r, plan: Dictionary, ta: int) -> void:
	var cid: String = plan["target"]
	var c: Dictionary = sim.world.containers[cid]
	var loc_id: String = c["location"]
	var loc: Dictionary = sim.world.locations[loc_id]
	r.cooldowns["steal"] = ta + 4 * DAY
	for x in sim.ids:
		if x != r.id and sim.residents[x].alive and sim.where(x, ta) == loc_id:
			sim.emit("theft_aborted", loc_id, [r.id], {"objects": [cid], "data": {"why": "someone was there"},
					"intent": "intentional", "discreet": true, "time": ta,
					"summary": "%s meant to steal but someone was there." % r.first})
			return
	var causes := recent_pressures(r, ta)
	var forced := {}
	if loc["lockable"] and loc["locked"]:
		if r.traits["caution"] > 0.7 and sim.rng.random() < 0.5:
			sim.emit("theft_aborted", loc_id, [r.id], {"objects": [cid], "data": {"why": "the door was locked"},
					"intent": "intentional", "discreet": true, "time": ta,
					"summary": "%s finds the door locked and leaves." % r.first})
			return
		forced = sim.emit("forced_entry", loc_id, [r.id], {"objects": [cid], "causes": causes, "intent": "intentional",
				"audibility": 2, "notable": true, "time": ta, "summary": "%s forces the door of %s." % [r.first, loc["name"]]})
		loc["locked"] = false
		sim.world.add_evidence("forced_door", loc_id, "The back door of %s has been forced: the latch is bent and the frame splintered." % loc["name"], ta, forced["id"])
		Perception.broadcast(sim, forced, null, Memory.claim("noise", {"location": loc_id, "start": ta,
				"detail": "a crack of splintering wood"}))
	var food := cid.begins_with("stock:")
	var have: int = c["food"] if food else c["cash"]
	var amount := 0
	if food:
		amount = mini(have, sim.rng.randint(8, 16))
	else:
		amount = int(have * sim.rng.uniform(0.5, 0.9))
	if amount <= 0:
		sim.emit("theft_aborted", loc_id, [r.id], {"objects": [cid], "data": {"why": "nothing worth taking"},
				"intent": "intentional", "discreet": true, "time": ta + 2,
				"summary": "%s finds nothing to take." % r.first})
		return
	var asset := "food" if food else "cash"
	var why := causes.duplicate()
	if not forced.is_empty():
		why.append(forced["id"])
	var ev: Dictionary = sim.emit("theft", loc_id, [r.id], {"objects": [cid], "data": {"asset": asset, "amount": amount},
			"causes": why, "intent": "intentional", "discreet": true, "notable": true, "time": ta + 2,
			"summary": "%s takes %d %s from %s." % [r.first, amount, "units of food" if food else "crowns", c["label"]]})
	sim.bump("thefts")
	var stash: Dictionary = sim.stash(r)
	sim.transfer(asset, "box:" + cid, "box:" + stash["id"], amount, ev["id"], ta + 2)
	stash["expected_" + asset] += amount  # the thief knows what is in it; nobody else knows it exists
	c["unexplained"].append(ev["id"])
	r.guilty_of.append(ev["id"])
	r.pending_hide.append(ev["id"])
	r.stress = clampf(r.stress + 20, 0.0, 100.0)
	sim.add_belief(r.id, Memory.claim("theft_self", {"subject": r.id, "location": loc_id, "start": ta + 2,
			"amount": amount, "obj": cid}), "self", 1.0, ta + 2, {"event": ev["id"]})
	var owners := []
	var spite := 0.0
	for o in c["owners"]:
		if sim.residents[o].alive:
			owners.append(o)
			spite = maxf(spite, r.r(o)["resentment"])
	Incidents.register(sim, {"family": "theft", "core_event": ev["id"], "time": ev["time"], "location": loc_id,
			"responsible": r.id, "victims": owners, "intent": "intentional", "mechanism": "stolen", "outcome": "crime",
			"severity": 1, "hook_kind": "goods_missing" if food else "money_missing",
			"motive": "grudge" if spite >= 0.5 and sim.pressure[r.id] < 0.6 else "money_trouble",
			"related_events": [forced["id"]] if not forced.is_empty() else []})


static func hide_loot(sim, r, t: int) -> void:
	## Home again, the thief hides what they took. The stash is a trace, found only by someone who searches.
	var stash: Dictionary = sim.stash(r)
	var house := "the %s house" % r.last
	for theft_id in r.pending_hide:
		var cid: String = sim.events.by_id[theft_id]["objects"][0]
		var desc := ""
		if cid == "till:grocery":
			desc = "A canvas till bag stamped 'GROCERY', pushed behind a loose board in the woodshed of %s." % house
		elif cid == "till:pub":
			desc = "A leather coin pouch from the till at %s, hidden under a mattress in %s." % [sim.world.pub_name, house]
		elif cid.begins_with("stock:"):
			desc = "A flour sack and tins bearing the grocery's stock stamp, under a tarpaulin in the shed of %s." % house
		else:
			desc = "A roll of banknotes wrapped in a cloth and wedged in the chimney nook of %s." % house
		var ev: Dictionary = sim.emit("hide_loot", r.home, [r.id], {"objects": [stash["id"]], "causes": [theft_id],
				"intent": "intentional", "discreet": true, "time": t, "summary": "%s hides the loot at home." % r.first})
		sim.world.add_evidence("stash", r.home, desc, t, ev["id"], [r.id])
		sim.add_belief(r.id, Memory.claim("stash", {"subject": r.id, "location": r.home, "start": t, "obj": cid}), "self",
				1.0, t, {"event": ev["id"]})
		if cid.begins_with("stock:") and stash["food"] > 0:
			var pantry: Dictionary = sim.pantry(r)
			var units: int = stash["food"]
			sim.transfer("food", "box:" + stash["id"], "box:" + pantry["id"], units, ev["id"], t)
			stash["expected_food"] -= units
			pantry["expected_food"] += units
	r.pending_hide = []


# ================================================================ the books
static func ledger_error(sim, clerk: String, buyer, till: Dictionary, cost: int, line: String, sale: Dictionary,
		ta: int) -> void:
	## A sale written into the ledger twice: the till now "should" hold money that never came in. Nothing was
	## taken, but the next count finds it short.
	var err: Dictionary = sim.emit("ledger_error", "grocery", [clerk], {"objects": [till["id"]], "data": {"amount": cost},
			"causes": [sale["id"]], "intent": "accidental", "time": ta + 1,
			"summary": "%s absent-mindedly writes %s's sale into the ledger twice." % [sim.n(clerk), buyer.first]})
	sim.world.record("ledger", ta + 1, line, err["id"])
	till["expected_cash"] += cost
	till["unexplained"].append(err["id"])
	for inc in sim.incidents:
		if inc["family"] == "accounting_error" and inc["discovered_at"] == null and inc["location"] == "grocery":
			inc["related_events"].append(err["id"])
			return
	Incidents.register(sim, {"family": "accounting_error", "core_event": err["id"], "time": err["time"],
			"location": "grocery", "responsible": null, "victims": till["owners"], "intent": "accidental",
			"mechanism": "accounting_error", "outcome": "no_crime", "severity": 0, "hook_kind": "money_missing",
			"motive": "none"})


static func unexplained_shortfall(sim, c: Dictionary) -> Array:
	## [cash, food] by which a container falls short of what its owners expect, as the events that changed it
	## unseen since it was last counted account for it: what was stolen, and sales written in twice.
	var cash := 0
	var food := 0
	for eid in c["unexplained"]:
		var ev: Dictionary = sim.events.by_id[eid]
		if ev["kind"] == "theft":
			if ev["data"]["asset"] == "cash":
				cash += int(ev["data"]["amount"])
			else:
				food += int(ev["data"]["amount"])
		elif ev["kind"] == "ledger_error":
			cash += int(ev["data"]["amount"])
	return [cash, food]


static func _title(text: String) -> String:
	## Title case that leaves "Drover's" alone.
	var words := PackedStringArray()
	for w in text.split(" "):
		words.append(w.substr(0, 1).to_upper() + w.substr(1))
	return " ".join(words)


static func _incident_before(a: Dictionary, b: Dictionary) -> bool:
	## Thefts first, then by time: the primary incident behind a loss is the theft, if there was one.
	var fa: int = 0 if a["family"] == "theft" else 1
	var fb: int = 0 if b["family"] == "theft" else 1
	if fa != fb:
		return fa < fb
	if a["time"] != b["time"]:
		return a["time"] < b["time"]
	return a["id"] < b["id"]


static func loss_discovered(sim, c: Dictionary, counter: String, t: int, short_cash: int, short_food: int) -> void:
	## Counting finds a container short. The counter knows (and anyone there sees); the incidents behind it are
	## now discovered. The events that explain the loss are its causes in the log: developer-only truth.
	var what := ""
	if short_cash > 0:
		what = "%d crowns missing from %s" % [short_cash, c["label"]]
	else:
		what = "%d units of stock missing from %s" % [short_food, c["label"]]
	var ev: Dictionary = sim.emit("loss_discovered", c["location"], [counter], {"objects": [c["id"]],
			"data": {"cash": short_cash, "food": short_food, "window": [c["last_check"], t]},
			"causes": c["unexplained"].duplicate(), "audibility": 1, "notable": true, "time": t,
			"summary": "%s finds %s." % [sim.n(counter), what]})
	var claim := Memory.claim("loss", {"location": c["location"], "start": c["last_check"], "end": t,
			"amount": short_cash if short_cash > 0 else short_food, "obj": c["id"], "detail": what})
	sim.add_belief(counter, claim, "self", 0.95, t, {"event": ev["id"]})
	Perception.broadcast(sim, ev, claim)
	var incs := []
	var seen := {}
	for eid in c["unexplained"]:
		var inc: Dictionary = Incidents.incident_for(sim, eid)
		if not inc.is_empty() and not seen.has(inc["id"]):
			seen[inc["id"]] = true
			incs.append(inc)
	if incs.is_empty():
		return
	incs.sort_custom(func(a, b): return _incident_before(a, b))
	var primary: Dictionary = incs[0]
	var forced := false
	for e in sim.world.evidence:
		if (e["kind"] == "forced_door" and e["place"] == c["location"] and sim.world.present_at(e, t)
				and counter in e["noticed_by"]):
			forced = true
	var place: String = sim.world.name_of(c["location"])
	var who: String = sim.residents[counter].full_name()
	var title := ""
	var hook := ""
	if String(c["id"]).begins_with("box:"):
		title = "The Lighter Savings Tin"
		hook = "%s opened %s on Day %d and found %d crowns fewer than there should be. It was last counted %s." % [who,
				c["label"], SimClock.day_of(t), short_cash, SimClock.fmt(c["last_check"])]
	elif short_food > 0 and short_cash == 0:
		title = "The Missing Stock"
		hook = "%s counted the stock room at %s at %s and found %d units missing since %s." % [who, place,
				SimClock.fmt(t), short_food, SimClock.fmt(c["last_check"])]
	else:
		title = "The Short Till at %s" % _title(place)
		hook = "%s counted %s at %s and found %d crowns missing. It last balanced at %s." % [who, c["label"],
				SimClock.fmt(t), short_cash, SimClock.fmt(c["last_check"])]
	if forced:
		hook += " The back door had been forced."
	for inc in incs:
		if not (ev["id"] in inc["related_events"]):
			inc["related_events"].append(ev["id"])
		Incidents.discover(sim, inc, counter, t, ev["id"], hook, title, [c["last_check"], t], c["location"])
		if inc["id"] != primary["id"]:
			inc["case_start"] = null


# ================================================================ traces
static func made_by(sim, rid: String, e: Dictionary) -> bool:
	## Did ``rid`` leave this trace through their own wrongdoing? (They don't "notice" it; they know.)
	var src: Dictionary = sim.events.by_id[e["created_by"]]
	if not (rid in src["actors"]):
		return false
	var r = sim.residents[rid]
	if src["id"] in r.guilty_of or src["kind"] in ["collision", "hide_loot"]:
		return true
	for c in src["causes"]:
		if c in r.guilty_of:
			return true
	return false


static func notice(sim, rid: String, e: Dictionary, t: int) -> void:
	## Someone sees a trace with their own eyes: a belief that something is damaged, pointing at what made it. A
	## smashed fence nobody owned up to is how a collision without a victim is discovered.
	e["noticed_by"].append(rid)
	sim.perceived[rid + "|" + e["created_by"]] = "trace"
	var claim := {}
	if e["kind"] == "vehicle_damage":
		var veh: Dictionary = sim.world.vehicles[e["place"]]
		claim = Memory.claim("vehicle_damage", {"obj": veh["id"], "location": veh["location"], "start": t,
				"detail": veh["damage"]})
	elif e["kind"] == "forced_door":
		claim = Memory.claim("damage", {"location": e["place"], "start": t,
				"detail": "the back door of %s forced" % sim.world.name_of(e["place"])})
	elif e["kind"] == "blood":
		claim = Memory.claim("damage", {"location": e["place"], "start": t,
				"detail": "blood at %s" % sim.world.name_of(e["place"])})
	else:
		claim = Memory.claim("damage", {"location": e["place"], "start": t,
				"detail": e["glimpse"] if e["glimpse"] != "" else e["kind"]})
	sim.add_belief(rid, claim, "saw", 0.9, t, {"event": e["created_by"]})
	if e["kind"] == "debris":
		var inc: Dictionary = Incidents.incident_for(sim, e["created_by"])
		if (not inc.is_empty() and inc["discovered_at"] == null and inc["family"] == "collision"
				and inc["victims"].is_empty()):
			var found: Dictionary = sim.emit("damage_found", "road", [rid], {"causes": [e["created_by"]], "notable": true,
					"time": t, "summary": "%s notices the smashed fence on Mill Road." % sim.n(rid)})
			# since when it could have happened: their own last time on the road before it
			var start: int = t - DAY
			var ivs: Array = sim.intervals[rid]
			for i in range(ivs.size() - 1):
				if ivs[i][0] == "road" and ivs[i][1] < inc["time"]:
					start = ivs[i][1]
			Incidents.discover(sim, inc, rid, t, found["id"], "%s found the white fence along Mill Road smashed on Day %d, with headlight glass on the verge. Nobody has owned up to it." % [
					sim.residents[rid].full_name(), SimClock.day_of(t)], "The Smashed Fence", [start, t], "road")


static func notice_evidence(sim, t0: int) -> void:
	## End of the hour: who came by a trace and noticed it (three in four by day, about one in three after dark).
	for e in sim.world.evidence:
		if not sim.world.present_at(e, t0 + 59) or not (e["kind"] in NOTICED_KINDS):
			continue
		var node: String = e["place"]
		if e["kind"] == "vehicle_damage":
			node = sim.world.vehicles[e["place"]]["location"]
		for rid in sim.visitors(node, t0, t0 + 60):
			var r = sim.residents[rid]
			if r.asleep or rid in e["noticed_by"] or made_by(sim, rid, e):
				continue
			var when: int = sim.overlap_start(rid, node, t0, t0 + 60)
			if when < 0 or when < e["created_at"]:
				continue
			var daylight := not SimClock.is_dark(when)
			if e["kind"] == "debris" and not daylight:
				continue
			if sim.rng.random() > (0.75 if daylight else 0.3):
				continue
			notice(sim, rid, e, when)


static func tidy_evidence(sim, t0: int) -> void:
	## Traces don't last: after a while the first person there by daylight clears it away (a forced door is
	## mended after 30 hours). The culprit tidying up their own trace is concealment.
	for e in sim.world.evidence:
		if (e["kind"] == "body" and sim.world.present_at(e, t0) and not e["noticed_by"].is_empty()
				and t0 - int(e["created_at"]) >= 3 * DAY):
			# three days after a body was found, it is taken away and buried
			var burial: Dictionary = sim.emit("burial", e["place"], [], {"data": {"evidence": e["id"]},
					"causes": [e["created_by"]], "intent": "lawful", "time": t0,
					"summary": "The body is taken away and buried."})
			e["removed_at"] = t0
			e["removed_by"] = burial["id"]
			continue
		if not sim.world.present_at(e, t0) or not TIDY_AFTER.has(e["kind"]):
			continue
		if t0 - int(e["created_at"]) < int(TIDY_AFTER[e["kind"]]):
			continue
		var node: String = e["place"]
		for rid in sim.visitors(node, t0, t0 + 60):
			var r = sim.residents[rid]
			var when: int = sim.overlap_start(rid, node, t0, t0 + 60)
			if r.asleep or when < 0 or SimClock.is_dark(when):
				continue
			tidy(sim, r, e, when)
			break


static func tidy(sim, r, e: Dictionary, t: int) -> void:
	var culprit := made_by(sim, r.id, e)
	if not (r.id in e["noticed_by"]) and not culprit:
		notice(sim, r.id, e, t)
	var cleaned: Dictionary = sim.emit("cleaned_up", e["place"], [r.id], {"causes": [e["created_by"]],
			"data": {"evidence": e["id"]}, "intent": "concealment" if culprit else "lawful", "time": t,
			"summary": "%s clears away: %s" % [r.first, e["description"]]})
	e["removed_at"] = t
	e["removed_by"] = cleaned["id"]


# ================================================================ owning up
static func confess(sim, culprit, to, core: String, cause: Dictionary, here: String, t: int) -> void:
	## Accused to their face of what they really did, the culprit owns up: the incident is now out in the open,
	## and what is left of stolen money goes back to the accuser.
	var inc: Dictionary = Incidents.incident_for(sim, core)
	var ev: Dictionary = sim.emit("confession", here, [culprit.id], {"targets": [to.id], "causes": [cause["id"], core],
			"intent": "lawful", "audibility": 1, "notable": true, "time": t,
			"summary": "%s confesses to %s." % [culprit.first, to.first]})
	if not inc.is_empty():
		inc["reported_openly"] = true
	var sid: String = "stash:" + culprit.id
	if sim.world.containers.has(sid) and not inc.is_empty() and inc["family"] == "theft":
		var stash: Dictionary = sim.world.containers[sid]
		var back: int = stash["cash"]
		if back > 0:
			sim.transfer("cash", "box:" + sid, "wallet:" + to.id, back, ev["id"], t)
			stash["expected_cash"] -= back
	var claim := Memory.claim("confession", {"subject": culprit.id, "other": to.id, "start": t,
			"detail": sim.events.by_id[core]["kind"]})
	for p in [culprit.id, to.id]:
		sim.add_belief(p, claim, "self", 1.0, t, {"event": ev["id"]})
	Perception.broadcast(sim, ev, claim)
	culprit.stress = clampf(culprit.stress - 20, 0.0, 100.0)
