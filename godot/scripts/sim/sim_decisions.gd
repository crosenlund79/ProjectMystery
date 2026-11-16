## Choosing what to do next (mirrors mystery/sim/decisions.py). Every option a resident has this hour gets a
## utility score from their needs, traits, money and the time of day, plus up to 8 points of noise; the
## best one wins, ties broken by kind, destination and person. Pressure changes priorities and acceptable
## risks; it never forces an outcome.
##
## Decisions about people use only what the decider believes (scripts/sim/sim_memory.gd): whose hardship they
## know of, and whom they suspect of something they have a stake in.
##
## Not here yet: stealing (the crime layer), the clinic and repairs (only needed after injuries and
## collisions).
extends RefCounted

const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Config = preload("res://scripts/sim/sim_config.gd")
const Gossip = preload("res://scripts/sim/sim_gossip.gd")

const DAY := 1440
const WEALTH_GUESS := {"mill_owner": 1.0, "grocer": 0.8, "publican": 0.8, "nurse": 0.6, "mechanic": 0.6}
const BUSINESSES := ["pub", "grocery", "clinic", "workshop", "mill"]


static func plan(kind: String, dest: String, target := "", reason := "", score := 0.0, data := {}) -> Dictionary:
	return {"kind": kind, "dest": dest, "target": target, "reason": reason, "score": score, "data": data}


static func ranks_before(a: Dictionary, b: Dictionary) -> bool:
	## Python sorts candidates by (-score, kind, dest, target) and takes the first.
	if a["score"] != b["score"]:
		return a["score"] > b["score"]
	if a["kind"] != b["kind"]:
		return a["kind"] < b["kind"]
	if a["dest"] != b["dest"]:
		return a["dest"] < b["dest"]
	return a["target"] < b["target"]


static func expected_location(sim, rid: String, t: int) -> String:
	## Where ``rid`` usually is at this hour, as anyone in town would guess.
	var x = sim.residents[rid]
	if sim.on_shift(x, t):
		return x.workplace
	var h := SimClock.hour_of(t)
	if 17 <= h and h < 22 and x.traits["temperance"] < 0.45:
		return "pub"
	return x.home


static func cooling(r, key: String, t: int) -> bool:
	return int(r.cooldowns.get(key, -1)) > t


static func _add(sim, cands: Array, kind: String, dest: String, score: float, target := "", reason := "",
		data := {}) -> void:
	cands.append(plan(kind, dest, target, reason, score + sim.rng.uniform(0, 8), data))


static func choose(sim, r, t: int) -> Dictionary:
	var h := SimClock.hour_of(t)
	var tr: Dictionary = r.traits
	var here: String = sim.loc(r.id)
	var home: String = r.home
	var food: int = sim.pantry(r)["food"]
	var size: int = sim.members(r).size()
	var pressure: float = sim.pressure[r.id]
	var cands := []

	# --- rest and sleep
	var night := 0
	if h == 21:
		night = 10
	elif h == 22:
		night = 35
	elif h >= 23 or h < 5:
		night = 70
	_add(sim, cands, "sleep", home, night + maxf(0.0, 60 - r.energy) + r.intox * 0.25)
	_add(sim, cands, "rest", home, 22 + (15 if r.energy < 40 else 0) + (8 if here == home else 0))

	# --- work
	var on_shift: bool = sim.on_shift(r, t)
	if on_shift:
		var s: float = 75 + tr["diligence"] * 20 - maxf(0.0, r.intox - 30) * 0.6 * (1 - tr["diligence"])
		s -= 40 if r.energy < 12 else 0
		_add(sim, cands, "work", r.workplace, s)

	# --- food
	if r.hunger > 40:
		if food > 0:
			var dest := here if (on_shift and here == r.workplace) else home
			_add(sim, cands, "eat", dest, r.hunger * 1.25 + (10 if here == dest else 0))
		if sim.business_open("pub", t) and r.cash >= Config.PUB_MEAL_PRICE:
			_add(sim, cands, "eat_pub", "pub", r.hunger * 1.0 + (100 - r.social) * 0.15 - (30 if r.cash < 40 else 0))
	if sim.business_open("grocery", t) and food < size * 4 and int(sim.daily.get("shopped:" + r.household, 0)) == 0:
		_add(sim, cands, "shop", "grocery", 25 + (size * 8 - food) * 3 + (35 if food == 0 else 0))

	# --- the pub and the square
	if sim.business_open("pub", t) and h >= 16 and r.cash >= Config.DRINK_PRICE:
		var s: float = (15 + r.stress * 0.4 + (100 - r.social) * 0.3) * (1.3 - tr["temperance"]) * sim.profile["drink_mult"]
		s += 8 if (18 <= h and h <= 21) else 0
		s += 12 if here == "pub" else 0
		s -= maxf(0.0, r.intox - 60) * 1.5
		s -= 25 * tr["caution"] if r.cash < 15 else 0.0
		_add(sim, cands, "drink", "pub", s)
	if sim.business_open("pub", t) and h >= 12:
		_add(sim, cands, "socialize", "pub", (100 - r.social) * 0.6 * tr["sociability"] + 8 + (6 if here == "pub" else 0))
	if 9 <= h and h < 19:
		_add(sim, cands, "socialize", "square", (100 - r.social) * 0.45 * tr["sociability"]
				+ (10 if SimClock.is_rest_day(t) else 0))

	# --- casual work for those without a job
	if not r.employed and r.role != "retiree" and 8 <= h and h <= 13 and sim.business_open("mill", t):
		var key: String = "oddavail:" + r.id
		if not sim.daily.has(key):
			sim.daily[key] = 1 if sim.rng.random() < sim.profile["odd_jobs"] else 2
		if sim.daily[key] == 1:
			_add(sim, cands, "odd_job", "mill", 55 + pressure * 40 + tr["diligence"] * 15 + (10 if here == "mill" else 0))

	# --- people
	if 8 <= h and h < 22:
		var social := _social_intent(sim, r, t, pressure)
		if not social.is_empty():
			cands.append(social)

	var best: Dictionary = cands[0]
	for c in cands:
		if ranks_before(c, best):
			best = c
	return best


static func _consider(sim, best: Dictionary, kind: String, x: String, t: int, score: float, reason := "", dest := "",
		data := {}) -> Dictionary:
	if dest == "":
		dest = expected_location(sim, x, t)
		if dest in BUSINESSES and not sim.business_open(dest, t):
			dest = sim.residents[x].home
	score += sim.rng.uniform(0, 8)
	if best.is_empty() or score > best["score"]:
		return plan(kind, dest, x, reason, score, data)
	return best


static func _social_intent(sim, r, t: int, pressure: float) -> Dictionary:
	var tr: Dictionary = r.traits
	var here: String = sim.loc(r.id)
	var best := {}
	var owed_to_me := {}
	for d in sim.open_debts(r.id, true):
		if d["due"] < t:
			owed_to_me[d["debtor"]] = d
	var my_debts: Array = sim.open_debts(r.id)
	var my_creditors := {}
	for d in my_debts:
		my_creditors[d["creditor"]] = true
	var in_hardship := {}
	var suspicions := {}  # subject -> the strongest suspicion of them, among incidents this resident cares about
	if sim.memory_on:
		var mem = sim.memory[r.id]
		for b in mem.of_kind(["suspect"], t - 4 * DAY):
			var s = b["claim"]["subject"]
			if s and b["confidence"] >= 0.5 and Gossip.has_stake(sim, r.id, b):
				if not suspicions.has(s) or b["confidence"] > suspicions[s]["confidence"]:
					suspicions[s] = b
		for b in mem.of_kind(["hardship"], t - 3 * DAY):
			in_hardship[b["claim"]["subject"]] = true
	else:
		var known: Dictionary = sim.known_hardship[r.id]
		for subject in known:
			if known[subject] >= t - 3 * DAY:
				in_hardship[subject] = true

	for x in sim.ids:
		if x == r.id:
			continue
		var xr = sim.residents[x]
		if not xr.alive:
			continue
		var rel: Dictionary = r.r(x)
		var same_house: bool = xr.household == r.household
		# off-ramp: ask for help before anything worse (but not from someone you already owe)
		if (pressure > 0.5 and not same_house and rel["trust"] > 0.3 and not my_creditors.has(x)
				and not cooling(r, "loan:" + x, t) and not cooling(r, "loan", t)):
			var wealth: float = WEALTH_GUESS.get(xr.role, 0.3)
			best = _consider(sim, best, "loan", x, t,
					pressure * 80 * (0.4 + 0.6 * wealth) * (0.5 + rel["trust"]) - tr["stubbornness"] * 15)
		for d in my_debts:
			if d["creditor"] == x and r.cash >= d["amount"] + 10:
				best = _consider(sim, best, "repay", x, t, 45 + tr["honesty"] * 30 + (30 if d["due"] < t else 0), "",
						"", {"debt": d["id"]})
		if not same_house and not cooling(r, "confront:" + x, t):
			var base := 0.0
			var reason := ""
			var ref := ""
			var dest := ""
			if owed_to_me.has(x):
				base = 40.0
				reason = "rent" if owed_to_me[x]["kind"] == "rent" else "debt"
				ref = owed_to_me[x]["id"]
			if suspicions.has(x) and 45 * suspicions[x]["confidence"] > base:
				base = 45 * suspicions[x]["confidence"]
				reason = "suspicion"
				ref = suspicions[x]["id"]
			# an old grudge only flares up when drink meets opportunity
			if reason == "" and rel["resentment"] >= 0.6 and r.intox >= 35 and sim.loc(x) == here:
				base = 20.0
				reason = "grudge"
				dest = here
			if reason != "":
				var s: float = base + rel["resentment"] * 50 * (0.6 + 0.4 * tr["stubbornness"]) + r.intox * 0.25
				s -= tr["caution"] * 20 + tr["empathy"] * 10
				best = _consider(sim, best, "confront", x, t, s, reason, dest, {"ref": ref})
		if (0.3 <= rel["resentment"] and rel["resentment"] <= 0.65 and not same_house
				and not cooling(r, "reconcile:" + x, t)):
			best = _consider(sim, best, "reconcile", x, t, tr["empathy"] * 35 + tr["sociability"] * 15
					- tr["stubbornness"] * 25 - rel["resentment"] * 15)
		if r.cash >= 80 and rel["affection"] >= 0.5 and in_hardship.has(x) and not cooling(r, "help:" + x, t):
			best = _consider(sim, best, "help", x, t, tr["empathy"] * rel["affection"] * 80)
	return best
