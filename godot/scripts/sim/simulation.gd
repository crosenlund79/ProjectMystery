## The town simulation (mirrors mystery/sim/engine.py). Each one-hour tick runs the same phases as Python:
## needs, scheduled duties (overdue debts, morning cash, rent, deliveries, layoffs), decisions, movement,
## actions, closing time. Perception, memory, crime and evidence are later pilots
## (docs/godot-simulation-migration.md). Headless: nothing here draws, plays or waits.
##
##   var sim = Simulation.new({"seed": 7, "days": 30, "profile": "normal", "residents": 10})
##   sim.run()
##   sim.events.events  # the chronological event log
extends RefCounted

const SimRng = preload("res://scripts/sim/sim_rng.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Config = preload("res://scripts/sim/sim_config.gd")
const Town = preload("res://scripts/sim/sim_town.gd")
const EventLog = preload("res://scripts/sim/sim_events.gd")
const Decisions = preload("res://scripts/sim/sim_decisions.gd")
const Actions = preload("res://scripts/sim/sim_actions.gd")

const DAY := 1440
const TICK := 60
const STAT_PLACES := ["home", "work", "pub", "square", "road", "elsewhere"]

var config := {}
var profile := {}
var ok := false
var rng
var world
var residents := {}
var households := {}
var heads := {}
var landlord := ""
var meta := {}
var ids := []
var events
var intervals := {}  # rid -> [[place, from minute, until minute], ...]; until = -1 while still there
var plans := {}
var forced := {}
var moves := {}
var pressure := {}
var daily := {}
var stats := {}
var known_hardship := {}  # holder -> {subject: minute}: who has seen someone struggle for money
var samples := {}  # hourly samples for the statistics (see _sample)
var errors := []  # broken rules: a transfer that would go negative, a container that doesn't add up, ...
var initial_balances := {}
var t := 0


func _init(cfg: Dictionary) -> void:
	config = Config.normalize(cfg)
	var why := Config.problem(config)
	if why != "":
		errors.append("bad configuration: " + why)
		return
	profile = Config.profile(config["profile"])
	rng = SimRng.new([config["seed"], "sim", config["profile"], config["residents"]])
	var town := Town.generate(config)
	world = town["world"]
	residents = town["residents"]
	meta = town["meta"]
	households = meta["households"]
	heads = meta["heads"]
	landlord = meta["landlord"]
	ids = residents.keys()
	ids.sort()
	events = EventLog.new()
	for rid in ids:
		intervals[rid] = [[residents[rid].home, 0, -1]]
		pressure[rid] = 0.0
		known_hardship[rid] = {}
	samples = {"hours": 0, "asleep": 0, "hunger": 0.0, "energy": 0.0, "social": 0.0, "stress": 0.0, "at": {}}
	for p in STAT_PLACES:
		samples["at"][p] = 0
	initial_balances = balances()
	ok = true
	_seed_history()
	events.commit()


# ------------------------------------------------------------------ helpers
func n(rid: String) -> String:
	return residents[rid].first if residents.has(rid) else "someone"


func alive() -> Array:
	var out := []
	for rid in ids:
		if residents[rid].alive:
			out.append(residents[rid])
	return out


func loc(rid: String) -> String:
	return intervals[rid][-1][0]


func where(rid: String, minute: int) -> String:
	var ivs: Array = intervals[rid]
	for i in range(ivs.size() - 1, -1, -1):
		var iv: Array = ivs[i]
		if iv[1] <= minute and (iv[2] < 0 or minute < iv[2]):
			return iv[0]
		if iv[1] <= minute:
			return ""
	return ""


func awake_at(rid: String, minute: int, node: String) -> bool:
	var r = residents[rid]
	return r.alive and not r.asleep and not r.down and where(rid, minute) == node


func staff_at(place: String, minute: int) -> Array:
	var out := []
	for rid in world.locations[place]["staff"]:
		var plan = plans.get(rid)
		if awake_at(rid, minute, place) and plan != null and plan["kind"] == "work":
			out.append(rid)
	return out


func members(r) -> Array:
	var out := []
	for m in households[r.household]:
		if residents[m].alive:
			out.append(m)
	return out


func pantry(r) -> Dictionary:
	return world.containers["pantry:" + r.household]


func box(r) -> Dictionary:
	return world.containers["box:" + r.household]


func on_shift(r, tt: int) -> bool:
	if not r.employed or r.shift.is_empty() or not r.alive:
		return false
	if SimClock.is_rest_day(tt) and r.workplace != "pub":
		return false
	var h := SimClock.hour_of(tt)
	return r.shift[0] <= h and h < r.shift[1]


func business_open(place: String, tt: int) -> bool:
	if SimClock.is_rest_day(tt) and place != "pub":
		return false
	return world.is_open(world.locations[place], SimClock.hour_of(tt))


func bump(key: String, by := 1) -> void:
	stats[key] = int(stats.get(key, 0)) + by


func fail(problem: String) -> void:
	## A rule of the world was broken. The run continues; the integrity checks report it.
	errors.append("%s: %s" % [SimClock.fmt(t), problem])
	push_error("simulation: " + problem)


# --------------------------------------------------------------- accounting
func balances() -> Dictionary:
	var out := {}
	for rid in ids:
		out["wallet:" + rid] = {"cash": residents[rid].cash, "food": 0}
	var cids: Array = world.containers.keys()
	cids.sort()
	for cid in cids:
		out["box:" + cid] = {"cash": world.containers[cid]["cash"], "food": world.containers[cid]["food"]}
	return out


func amount_in(acct: String, asset: String):
	## What an account holds, or null for the world outside the town (suppliers, wages from outside, food
	## eaten), which has no balance.
	if acct.begins_with("wallet:"):
		return residents[acct.substr(7)].cash if asset == "cash" else 0
	if acct.begins_with("box:"):
		return world.containers[acct.substr(4)][asset]
	return null


func _set_amount(acct: String, asset: String, value: int) -> void:
	if acct.begins_with("wallet:"):
		if asset != "cash":
			fail("a wallet cannot hold %s" % asset)
			return
		residents[acct.substr(7)].cash = value
	elif acct.begins_with("box:"):
		world.containers[acct.substr(4)][asset] = value


func transfer(asset: String, src: String, dst: String, amount: int, event_id: String, time := -1) -> bool:
	if amount <= 0:
		return true
	var have = amount_in(src, asset)
	if have != null and have < amount:
		fail("%s cannot give %d %s (has %d) for %s" % [src, amount, asset, have, event_id])
		return false
	if have != null:
		_set_amount(src, asset, have - amount)
	var dst_have = amount_in(dst, asset)
	if dst_have != null:
		_set_amount(dst, asset, dst_have + amount)
	world.transfers.append({"time": t if time < 0 else time, "event": event_id, "asset": asset, "src": src,
			"dst": dst, "amount": amount})
	return true


func count_container(c: Dictionary, counter: String, tt: int) -> void:
	## Someone counts a till, tin or pantry. In Python a shortfall here is how a theft is discovered; with no
	## crime layer every count must match what its owners expect, to the crown and the unit.
	if c["expected_cash"] != c["cash"] or c["expected_food"] != c["food"]:
		fail("%s counted by %s holds %d cash and %d food; its owners expect %d and %d" % [c["label"], n(counter),
				c["cash"], c["food"], c["expected_cash"], c["expected_food"]])
	c["expected_cash"] = c["cash"]
	c["expected_food"] = c["food"]
	c["last_check"] = tt


# ------------------------------------------------------------------- events
func emit(kind: String, location: String, actors: Array, opts := {}) -> Dictionary:
	## opts: targets, objects, data, causes, intent, audibility, notable, time, summary.
	var causes := []
	for c in opts.get("causes", []):
		if c != null and String(c) != "":
			causes.append(String(c))
	var ev := {"time": int(opts.get("time", t)), "location": location, "kind": kind, "actors": actors.duplicate(),
			"targets": Array(opts.get("targets", [])).duplicate(), "objects": Array(opts.get("objects", [])).duplicate(),
			"data": Dictionary(opts.get("data", {})).duplicate(true), "causes": causes,
			"intent": String(opts.get("intent", "")), "audibility": int(opts.get("audibility", 0)),
			"notable": bool(opts.get("notable", false)), "summary": String(opts.get("summary", ""))}
	events.add(ev)
	bump("event:" + kind)
	return ev


func _seed_history() -> None:
	for g in meta["grudges"]:
		emit("prior_grudge", "-", [g["a"]], {"targets": [g["b"]], "data": {"reason": g["reason"]}, "time": 0,
				"summary": "Long-standing grudge between %s and %s: %s." % [n(g["a"]), n(g["b"]), g["reason"]]})
	for d in meta["initial_debts"]:
		var ev := emit("prior_debt", "-", [d["debtor"]], {"targets": [d["creditor"]], "data": {"amount": d["amount"]},
				"time": 0, "summary": "%s owes %s %d crowns (due %s)." % [n(d["debtor"]), n(d["creditor"]), d["amount"],
				SimClock.fmt(d["due"])]})
		world.add_debt(d["debtor"], d["creditor"], d["amount"], d["due"], 0, ev["id"])


# ---------------------------------------------------------------- pressure
func open_debts(rid: String, as_creditor := false) -> Array:
	var key := "creditor" if as_creditor else "debtor"
	var out := []
	for d in world.debts:
		if d[key] == rid and d["settled"] < 0:
			out.append(d)
	return out


func funds(r) -> int:
	return r.cash + int(box(r)["cash"])


func shortfall(r, tt: int) -> float:
	var price: int = profile["food_price"]
	var size := members(r).size()
	var food: int = pantry(r)["food"]
	var food_need := maxi(0, size * 6 - food) * price
	var owed := 0
	for d in open_debts(r.id):
		if d["due"] <= tt + 3 * DAY:
			owed += d["amount"]
	var rent := Config.RENT if (heads[r.household] == r.id and r.id != landlord and SimClock.weekday_of(tt) >= 4) else 0
	return food_need * 0.5 + owed + rent - funds(r)


func money_pressure(r, tt: int) -> float:
	var p := clampf(shortfall(r, tt) / 80.0, 0.0, 1.0)
	if pantry(r)["food"] == 0 and r.cash < profile["food_price"]:
		p = maxf(p, 0.6)
	for d in open_debts(r.id):
		if d["due"] < tt:
			p = clampf(p + 0.2, 0.0, 1.0)
			break
	if not r.employed and r.role != "retiree":
		p = clampf(p + 0.1, 0.0, 1.0)
	return snappedf(p, 0.001)


func add_pressure(r, ev: Dictionary, stress := 8.0) -> void:
	r.pressures.append([ev["time"], ev["id"]])
	r.stress = clampf(r.stress + stress, 0.0, 100.0)


func know_hardship(holder: String, subject: String, tt: int) -> void:
	known_hardship[holder][subject] = tt


# ------------------------------------------------------------------ run
func run(until := -1):
	if not ok:
		return self
	var end: int = config["days"] * DAY if until < 0 else until
	while t < end:
		step()
	return self


func step() -> void:
	var t0 := t
	_update_needs(t0)
	_start_of_tick(t0)
	_decide_all(t0)
	_move_phase(t0)
	_action_phase(t0)
	_end_of_tick(t0)
	events.commit()
	t += TICK


func _update_needs(tt: int) -> void:
	if SimClock.hour_of(tt) == 0:
		for r in alive():
			r.worked_today = false
		daily = {}
	for r in alive():
		if r.asleep:
			r.energy += 8
			r.hunger += 2
			r.stress -= 1.5
		else:
			r.energy -= 3.5
			r.hunger += 5
			r.social -= 2.5
			r.stress += pressure[r.id] * 3 - 1
		if r.hunger >= 95:
			r.stress += 2
		r.intox = maxf(0.0, r.intox - 10)
		r.energy = clampf(r.energy, 0.0, 100.0)
		r.hunger = clampf(r.hunger, 0.0, 100.0)
		r.social = clampf(r.social, 0.0, 100.0)
		r.stress = clampf(r.stress, 0.0, 100.0)
		pressure[r.id] = money_pressure(r, tt)


# -------------------------------------------------------- scheduled duties
func _start_of_tick(tt: int) -> void:
	var h := SimClock.hour_of(tt)
	for d in world.debts:
		if d["settled"] < 0 and d["overdue_event"] == "" and d["due"] <= tt:
			var debtor = residents[d["debtor"]]
			if not debtor.alive or not residents[d["creditor"]].alive:
				continue
			var ev := emit("debt_overdue", loc(d["debtor"]), [d["debtor"]], {"data": {"creditor": d["creditor"],
					"amount": d["amount"], "debt": d["id"]}, "causes": [d["origin_event"]], "time": tt,
					"summary": "%s's debt of %d to %s is overdue." % [n(d["debtor"]), d["amount"], n(d["creditor"])]})
			d["overdue_event"] = ev["id"]
			add_pressure(debtor, ev)
			var cred_rel: Dictionary = residents[d["creditor"]].r(d["debtor"])
			cred_rel["resentment"] = clampf(cred_rel["resentment"] + 0.15, 0.0, 1.0)
	if h == 7:
		for r in alive():
			if loc(r.id) == r.home and not r.down:
				_morning_cash(r, tt)
	if h == 8 and SimClock.weekday_of(tt) == 0:
		_collect_rent(tt)
	if h == 8 and SimClock.weekday_of(tt) in [1, 4]:
		_delivery(tt)
	if h == 8 and SimClock.day_of(tt) == 5 and profile["layoffs"] > 0:
		_layoffs(tt)


func _morning_cash(r, tt: int) -> void:
	## Households pool their money in a savings tin at home.
	var tin := box(r)
	if r.cash > 120:
		count_container(tin, r.id, tt)
		var amount: int = r.cash - 60
		var ev := emit("deposit", r.home, [r.id], {"objects": [tin["id"]], "data": {"amount": amount},
				"intent": "lawful", "time": tt, "summary": "%s puts %d crowns in the household tin." % [r.first, amount]})
		transfer("cash", "wallet:" + r.id, "box:" + tin["id"], amount, ev["id"], tt)
		tin["expected_cash"] += amount
		return
	if r.cash >= 25:
		return
	count_container(tin, r.id, tt)
	var take := mini(40, tin["cash"])
	if take > 0:
		var ev := emit("withdraw", r.home, [r.id], {"objects": [tin["id"]], "data": {"amount": take},
				"intent": "lawful", "time": tt, "summary": "%s takes %d crowns from the household tin." % [r.first, take]})
		transfer("cash", "box:" + tin["id"], "wallet:" + r.id, take, ev["id"], tt)
		tin["expected_cash"] -= take


func _collect_rent(tt: int) -> void:
	var lord = residents[landlord]
	var hids: Array = households.keys()
	hids.sort()
	for hid in hids:
		var head = residents[heads[hid]]
		if head.id == landlord or hid == lord.household or not head.alive:
			continue
		if head.cash < Config.RENT and loc(head.id) == head.home:
			var tin := box(head)
			count_container(tin, head.id, tt)
			var take := mini(tin["cash"], Config.RENT - head.cash)
			if take > 0:
				var ev := emit("withdraw", head.home, [head.id], {"objects": [tin["id"]], "data": {"amount": take},
						"intent": "lawful", "time": tt, "summary": "%s takes %d from the tin for rent." % [head.first, take]})
				transfer("cash", "box:" + tin["id"], "wallet:" + head.id, take, ev["id"], tt)
				tin["expected_cash"] -= take
		if head.cash >= Config.RENT and lord.alive:
			var ev := emit("rent_paid", loc(head.id), [head.id], {"data": {"to": lord.id, "amount": Config.RENT},
					"intent": "lawful", "time": tt, "summary": "%s pays %d rent to %s." % [head.first, Config.RENT,
					lord.first]})
			transfer("cash", "wallet:" + head.id, "wallet:" + lord.id, Config.RENT, ev["id"], tt)
		else:
			var ev := emit("rent_missed", loc(head.id), [head.id], {"data": {"to": lord.id, "amount": Config.RENT},
					"time": tt, "notable": true, "summary": "%s cannot pay the rent owed to %s." % [head.first,
					lord.first]})
			world.add_debt(head.id, lord.id, Config.RENT, tt + 7 * DAY, tt, ev["id"], "rent")
			add_pressure(head, ev, 12)
			var rel: Dictionary = lord.r(head.id)
			rel["resentment"] = clampf(rel["resentment"] + 0.1, 0.0, 1.0)
	for r in alive():
		if r.role == "retiree":
			var ev := emit("pension", loc(r.id), [r.id], {"data": {"amount": Config.PENSION_WEEKLY}, "intent": "lawful",
					"time": tt, "summary": "%s receives a pension of %d." % [r.first, Config.PENSION_WEEKLY]})
			transfer("cash", "outside", "wallet:" + r.id, Config.PENSION_WEEKLY, ev["id"], tt)


func _delivery(tt: int) -> void:
	var till: Dictionary = world.containers["till:grocery"]
	var stock: Dictionary = world.containers["stock:grocery"]
	var grocers := []
	for o in till["owners"]:
		if residents[o].alive:
			grocers.append(o)
	var unit_cost := maxi(1, int(round(profile["food_price"] * Config.SUPPLIER_COST_RATIO)))
	var purse: int = till["cash"]
	for o in grocers:
		purse += residents[o].cash
	var affordable := int(floor(float(purse) / float(unit_cost)))
	var units := mini(mini(profile["delivery_units"], Config.STOCK_CAPACITY - stock["food"]), affordable)
	if units <= 0:
		return
	var cost := units * unit_cost
	var ev := emit("delivery", "grocery", [], {"objects": [till["id"], stock["id"]], "data": {"units": units,
			"cost": cost}, "intent": "lawful", "time": tt,
			"summary": "Supplier delivers %d units to the grocery for %d." % [units, cost]})
	var from_till := mini(cost, till["cash"])
	transfer("cash", "box:" + till["id"], "outside", from_till, ev["id"], tt)
	till["expected_cash"] -= from_till
	var rest := cost - from_till
	for o in grocers:
		var part := mini(rest, residents[o].cash)
		transfer("cash", "wallet:" + o, "outside", part, ev["id"], tt)
		rest -= part
	transfer("food", "outside", "box:" + stock["id"], units, ev["id"], tt)
	stock["expected_food"] += units
	var note := " (%d cr from the owner's pocket)" % (cost - from_till) if cost > from_till else ""
	world.record("ledger", tt, "%s supplier delivery: %d units received, paid %d cr%s." % [SimClock.fmt(tt), units,
			cost, note], ev["id"])


func _layoffs(tt: int) -> void:
	var owner = residents[landlord]
	var hands := []
	for r in alive():
		if r.role == "mill_hand" and r.employed:
			hands.append(r)
	hands.sort_custom(_less_diligent)
	for i in mini(profile["layoffs"], hands.size()):
		var r = hands[i]
		var ev := emit("laid_off", loc(owner.id), [owner.id], {"data": {"worker": r.id}, "time": tt, "notable": true,
				"summary": "%s lays off %s from the mill." % [owner.first, r.first]})
		r.employed = false
		r.workplace = ""
		r.shift = []
		r.occupation = "out of work (laid off from the mill)"
		world.locations["mill"]["staff"].erase(r.id)
		var rel: Dictionary = r.r(owner.id)
		rel["resentment"] = clampf(rel["resentment"] + 0.35, 0.0, 1.0)
		add_pressure(r, ev, 20)


func _less_diligent(a, b) -> bool:
	if a.traits["diligence"] != b.traits["diligence"]:
		return a.traits["diligence"] < b.traits["diligence"]
	return a.id < b.id


# ---------------------------------------------------------------- decisions
func _decide_all(tt: int) -> void:
	plans = {}
	var h := SimClock.hour_of(tt)
	for rid in ids:
		var r = residents[rid]
		if not r.alive or r.down:
			continue
		if forced.has(rid):
			plans[rid] = forced[rid]
			forced.erase(rid)
			r.asleep = false
			continue
		if r.asleep:
			var wake := 6 if (not r.shift.is_empty() and r.shift[0] <= 8 and r.employed) else 7
			if r.intox > 30:
				wake += 1
			if (h >= wake and h < 21 and r.energy >= 55) or (9 <= h and h < 21):
				r.asleep = false
			else:
				plans[rid] = Decisions.plan("sleep", r.home)
				continue
		plans[rid] = Decisions.choose(self, r, tt)


# ----------------------------------------------------------------- movement
func _route(rid: String, dest: String, depart: int, drive: bool) -> void:
	var p: Array = world.path(loc(rid), dest)
	var times := [depart]
	var tt := depart
	for i in range(p.size() - 1):
		var m: int = world.locations[p[i]]["adj"][p[i + 1]]
		tt += maxi(1, int(round(m * 0.35))) if drive else m
		times.append(tt)
	var ivs: Array = intervals[rid]
	ivs[-1][2] = times[1]
	for i in range(1, p.size()):
		ivs.append([p[i], times[i], times[i + 1] if i + 1 < p.size() else -1])
	var veh: String = residents[rid].vehicle if drive else ""
	moves[rid] = {"path": p, "times": times, "drive": drive, "depart": depart, "vehicle": veh}
	if drive:
		world.vehicles[veh]["location"] = dest


func decide_drive(r, dest: String) -> bool:
	if r.vehicle == "":
		return false
	var here := loc(r.id)
	if world.vehicles[r.vehicle]["location"] != here or not world.path(here, dest).has("road"):
		return false
	if r.intox < 25:
		return rng.random() < 0.85
	var p: float = 0.75 - r.traits["caution"] * 0.6 - (1 - r.intox / 100.0) * 0.2 + r.traits["impulsiveness"] * 0.3
	return rng.random() < clampf(p, 0.05, 0.9)


func _move_phase(t0: int) -> void:
	moves = {}
	var movers := []
	for rid in ids:
		if plans.has(rid) and plans[rid]["dest"] != loc(rid):
			movers.append(rid)
	var drivers := []
	var walkers := []
	for rid in movers:
		var r = residents[rid]
		if decide_drive(r, plans[rid]["dest"]):
			var shared := false
			for d in drivers:
				if residents[d].vehicle == r.vehicle:
					shared = true
			if shared:
				walkers.append(rid)
			else:
				drivers.append(rid)
		else:
			walkers.append(rid)
	for rid in walkers + drivers:
		_route(rid, plans[rid]["dest"], t0 + rng.randint(0, 15), drivers.has(rid))
	for rid in movers:
		var mv: Dictionary = moves[rid]
		var p: Array = mv["path"]
		var objs := [mv["vehicle"]] if mv["vehicle"] != "" else []
		var ev := emit("move", p[0], [rid], {"objects": objs, "data": {"path": p.duplicate(),
				"times": mv["times"].duplicate(), "drive": mv["drive"]}, "time": mv["depart"],
				"summary": "%s %s from %s to %s." % [residents[rid].first, "drives" if mv["drive"] else "walks",
				world.name_of(p[0]), world.name_of(p[-1])]})
		mv["event"] = ev["id"]


# ------------------------------------------------------------------ actions
func _action_phase(t0: int) -> void:
	var order := ids.duplicate()
	rng.shuffle(order)
	# Minutes follow processing order, so cause always precedes effect within the hour (and the latest
	# consequence, at +2, still falls inside this tick).
	for idx in order.size():
		var rid: String = order[idx]
		var r = residents[rid]
		var plan = plans.get(rid)
		if plan == null or not r.alive or r.down or r.asleep:
			continue
		if loc(rid) != plan["dest"]:
			continue
		Actions.perform(self, r, plan, t0 + 46 + idx)
	Actions.incidental_chats(self, t0)


func _end_of_tick(t0: int) -> void:
	var tm := t0 + 59
	var h := SimClock.hour_of(t0)
	for place in ["grocery", "pub", "mill", "clinic", "workshop"]:
		var hours: Array = world.locations[place]["hours"]
		if not hours.is_empty() and h == hours[1] - 1:
			Actions.close_business(self, place, tm)
	_sample(tm)


func place_category(r, node: String) -> String:
	if node.begins_with("home:"):
		return "home"
	if node != "" and node == r.workplace:
		return "work"
	if node in ["pub", "square", "road"]:
		return node
	return "elsewhere"


func _sample(tm: int) -> void:
	## One sample per resident per hour, for the statistics compared with Python.
	for r in alive():
		samples["hours"] += 1
		samples["asleep"] += 1 if r.asleep else 0
		samples["hunger"] += r.hunger
		samples["energy"] += r.energy
		samples["social"] += r.social
		samples["stress"] += r.stress
		samples["at"][place_category(r, where(r.id, tm))] += 1
