## What residents do once they are where they meant to be (mirrors mystery/sim/actions.py): work, meals,
## shopping and credit, drinking, socialising, odd jobs, loans, repayments, help, reconciliation,
## confrontations, chats, and closing time with its wages and takings. Every change of money or food is a
## transfer tied to an event, and every till, tin and pantry keeps the amount its owners expect.
##
## With memory on, the people involved know what they did, witnesses see or hear it (scripts/sim/sim_perception.gd)
## and chats carry gossip (scripts/sim/sim_gossip.gd). With crime on, a resident may steal, a clerk may write a
## sale in twice, a forced door is noticed by whoever opens up, and an accused culprit may confess
## (scripts/sim/sim_crime.gd). With violence on too, an argument can turn into a fight, and the injured go to the
## clinic and damaged vehicles to the workshop (scripts/sim/sim_violence.gd).
extends RefCounted

const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Config = preload("res://scripts/sim/sim_config.gd")
const Decisions = preload("res://scripts/sim/sim_decisions.gd")
const Memory = preload("res://scripts/sim/sim_memory.gd")
const Perception = preload("res://scripts/sim/sim_perception.gd")
const Gossip = preload("res://scripts/sim/sim_gossip.gd")
const Crime = preload("res://scripts/sim/sim_crime.gd")
const Incidents = preload("res://scripts/sim/sim_incidents.gd")
const Violence = preload("res://scripts/sim/sim_violence.gd")

const DAY := 1440


static func perform(sim, r, plan: Dictionary, ta: int) -> void:
	var k: String = plan["kind"]
	match k:
		"sleep":
			if sim.loc(r.id) == r.home:
				r.asleep = true
		"rest":
			r.energy = clampf(r.energy + 3, 0.0, 100.0)
			r.stress = clampf(r.stress - 2, 0.0, 100.0)
		"work":
			do_work(sim, r, ta)
		"eat":
			eat(sim, r, ta)
		"eat_pub":
			eat_pub(sim, r, ta)
		"shop":
			shop(sim, r, ta)
		"drink":
			drink(sim, r, ta)
		"socialize":
			r.social = clampf(r.social + 6, 0.0, 100.0)
			if plan["dest"] == "pub" and sim.rng.random() < 0.5:
				drink(sim, r, ta, 1)
		"odd_job":
			if not sim.staff_at("mill", ta).is_empty():
				sim.daily["odd:" + r.id] = int(sim.daily.get("odd:" + r.id, 0)) + 1
		"steal":
			Crime.steal(sim, r, plan, ta)
		"clinic":
			Violence.clinic(sim, r, ta)
		"repair":
			Violence.repair(sim, r, ta)
		"loan", "repay", "confront", "reconcile", "help":
			var x: String = plan["target"]
			if x == "" or not sim.awake_at(x, ta, sim.loc(r.id)):
				r.cooldowns["%s:%s" % [k, x]] = ta + 3 * 60
				return
			match k:
				"loan":
					ask_loan(sim, r, x, ta)
				"repay":
					repay(sim, r, plan, ta)
				"confront":
					confront(sim, r, x, plan, ta)
				"reconcile":
					reconcile(sim, r, x, ta)
				"help":
					help_out(sim, r, x, ta)


# ============================================================== daily life
static func do_work(sim, r, ta: int) -> void:
	r.worked_today = true
	var place: String = r.workplace
	if place == "":
		return
	var key := "opened:" + place
	if int(sim.daily.get(key, 0)) == 0:
		sim.daily[key] = 1
		if sim.crime_on:
			# whoever opens up sees a forced door first
			for e in sim.world.evidence_at(place, ta):
				if e["kind"] == "forced_door" and not (r.id in e["noticed_by"]) and not Crime.made_by(sim, r.id, e):
					Crime.notice(sim, r.id, e, ta)
		sim.world.locations[place]["locked"] = false
		for cid in ["till:" + place, "stock:" + place]:
			if sim.world.containers.has(cid):
				sim.count_container(sim.world.containers[cid], r.id, ta)
	if place == "grocery" and sim.self_service_on:
		_provision(sim, r, ta)


static func _provision(sim, r, ta: int) -> void:
	## Someone working at the grocery whose household is running short buys food during their shift, as anyone else
	## would decide to go shopping (the same need: less than half a week's food, nobody in the household has shopped
	## today): from a colleague serving, or serving themselves. Not in Python, where a diligent grocer living alone
	## never leaves work to shop and so seldom has food at home (docs/godot-simulation-migration.md).
	if not sim.business_open("grocery", ta):
		return
	if sim.pantry(r)["food"] >= sim.members(r).size() * 4 or int(sim.daily.get("shopped:" + r.household, 0)) > 0:
		return
	shop(sim, r, ta)


static func eat(sim, r, ta: int) -> void:
	var pantry: Dictionary = sim.pantry(r)
	if pantry["food"] <= 0:
		return
	var ev: Dictionary = sim.emit("meal", sim.loc(r.id), [r.id], {"objects": [pantry["id"]], "intent": "lawful",
			"time": ta, "summary": "%s eats." % r.first})
	sim.transfer("food", "box:" + pantry["id"], "eaten", 1, ev["id"], ta)
	pantry["expected_food"] -= 1
	r.hunger = clampf(r.hunger - 55, 0.0, 100.0)


static func _staff_other_than(sim, place: String, rid: String, ta: int) -> Array:
	var out := []
	for s in sim.staff_at(place, ta):
		if s != rid:
			out.append(s)
	return out


static func eat_pub(sim, r, ta: int) -> void:
	var staff := _staff_other_than(sim, "pub", r.id, ta)
	if staff.is_empty() or r.cash < Config.PUB_MEAL_PRICE:
		return
	var till: Dictionary = sim.world.containers["till:pub"]
	var ev: Dictionary = sim.emit("pub_meal", "pub", [r.id], {"targets": [staff[0]], "objects": [till["id"]],
			"data": {"paid": Config.PUB_MEAL_PRICE}, "intent": "lawful", "time": ta,
			"summary": "%s buys a meal at the pub." % r.first})
	sim.transfer("cash", "wallet:" + r.id, "box:" + till["id"], Config.PUB_MEAL_PRICE, ev["id"], ta)
	till["expected_cash"] += Config.PUB_MEAL_PRICE
	sim.daily["pub_cogs"] = int(sim.daily.get("pub_cogs", 0)) + Config.PUB_MEAL_COST
	sim.world.record("tabs", ta, "%s %s: hot meal (%d cr)" % [SimClock.fmt(ta), r.full_name(), Config.PUB_MEAL_PRICE],
			ev["id"])
	r.hunger = clampf(r.hunger - 60, 0.0, 100.0)
	r.social = clampf(r.social + 5, 0.0, 100.0)


@warning_ignore("integer_division")
static func drink(sim, r, ta: int, limit := 2) -> void:
	var staff := _staff_other_than(sim, "pub", r.id, ta)
	if staff.is_empty():
		return
	var n := 1 + (1 if limit > 1 and sim.rng.random() < (1 - r.traits["temperance"]) * 0.5 else 0)
	n = mini(n, r.cash / Config.DRINK_PRICE)
	if n <= 0:
		return
	var till: Dictionary = sim.world.containers["till:pub"]
	var cost := n * Config.DRINK_PRICE
	var plural := "s" if n > 1 else ""
	var ev: Dictionary = sim.emit("drink", "pub", [r.id], {"targets": [staff[0]], "objects": [till["id"]],
			"data": {"drinks": n, "paid": cost}, "intent": "lawful", "time": ta,
			"summary": "%s has %d drink%s." % [r.first, n, plural]})
	sim.transfer("cash", "wallet:" + r.id, "box:" + till["id"], cost, ev["id"], ta)
	till["expected_cash"] += cost
	sim.daily["pub_cogs"] = int(sim.daily.get("pub_cogs", 0)) + n * Config.DRINK_COST
	sim.world.record("tabs", ta, "%s %s: %d drink%s (%d cr)" % [SimClock.fmt(ta), r.full_name(), n, plural, cost],
			ev["id"])
	r.intox = clampf(r.intox + 16 * n, 0.0, 100.0)
	r.stress = clampf(r.stress - 6, 0.0, 100.0)
	r.social = clampf(r.social + 8, 0.0, 100.0)
	var drinks: Array = sim.recent_drinks[r.id]
	drinks.append([ta, ev["id"]])
	sim.recent_drinks[r.id] = drinks.slice(maxi(0, drinks.size() - 10))


@warning_ignore("integer_division")
static func shop(sim, r, ta: int) -> void:
	## Buying food at the grocery, from someone serving there. Someone who works there may serve themselves while
	## the shop is open and nobody else is serving: at the usual price, paid into the till and written in the
	## ledger like any sale, but never on credit. Python has no self-service: there, two shop workers whose pantries
	## are both empty go shopping in their own shop, neither counts as serving, and nobody in town can buy food
	## again (the grocery deadlock; a deliberate difference, docs/godot-simulation-migration.md).
	var staff := _staff_other_than(sim, "grocery", r.id, ta)
	var self_service: bool = (sim.self_service_on and staff.is_empty()
			and r.id in sim.world.locations["grocery"]["staff"] and sim.business_open("grocery", ta))
	if staff.is_empty() and not self_service:
		return
	var shopped_key: String = "shopped:" + r.household
	sim.daily[shopped_key] = int(sim.daily.get(shopped_key, 0)) + 1
	var price: int = sim.profile["food_price"]
	var stock: Dictionary = sim.world.containers["stock:grocery"]
	var till: Dictionary = sim.world.containers["till:grocery"]
	var pantry: Dictionary = sim.pantry(r)
	var size: int = sim.members(r).size()
	var want := mini(maxi(0, size * 8 - pantry["food"]), stock["food"])
	if want == 0:
		if stock["food"] == 0:
			var ev: Dictionary = sim.emit("no_stock", "grocery", [r.id], {"time": ta,
					"summary": "%s finds the grocery shelves empty." % r.first})
			sim.add_pressure(r, ev, 5)
		return
	var units := mini(want, r.cash / price)
	var clerk: String = r.id if self_service else staff[sim.rng.randrange(staff.size())]
	if units > 0:
		var cost := units * price
		var data := {"units": units, "paid": cost}
		if self_service:
			data["self_service"] = true  # only on these sales, so every other purchase event is as before
		var ev: Dictionary = sim.emit("purchase", "grocery", [r.id], {"targets": [] if self_service else [clerk],
				"objects": [till["id"], stock["id"]], "data": data, "intent": "lawful", "time": ta,
				"summary": ("%s serves themselves %d units of food and pays %d into the till." if self_service
						else "%s buys %d units of food for %d.") % [r.first, units, cost]})
		sim.transfer("cash", "wallet:" + r.id, "box:" + till["id"], cost, ev["id"], ta)
		sim.transfer("food", "box:" + stock["id"], "box:" + pantry["id"], units, ev["id"], ta)
		till["expected_cash"] += cost
		stock["expected_food"] -= units
		pantry["expected_food"] += units
		var line := "%s sale to %s: %d units, %d cr%s" % [SimClock.fmt(ta), r.full_name(), units, cost,
				" (self-service)" if self_service else ""]
		sim.world.record("ledger", ta, line, ev["id"])
		if sim.memory_on:
			sim.add_belief(r.id, Memory.claim("purchase", {"subject": r.id, "location": "grocery", "start": ta,
					"amount": cost, "detail": "%d units" % units}), "self", 0.95, ta, {"event": ev["id"]})
		if sim.crime_on and sim.rng.random() < 0.015 * (1 - sim.residents[clerk].traits["diligence"]):
			Crime.ledger_error(sim, clerk, r, till, cost, line, ev, ta)
	if units < want and units < size * 3 and not self_service:
		ask_credit(sim, r, staff, want - units, ta)


static func ask_credit(sim, r, staff: Array, need: int, ta: int) -> void:
	var owners := []
	for s in staff:
		if s in sim.world.locations["grocery"]["owners"]:
			owners.append(s)
	var stock: Dictionary = sim.world.containers["stock:grocery"]
	var price: int = sim.profile["food_price"]
	if owners.is_empty():
		var ev: Dictionary = sim.emit("credit_refused", "grocery", [staff[0]], {"targets": [r.id],
				"data": {"why": "only the owner gives credit"}, "audibility": 1, "time": ta + 2,
				"summary": "%s is told only the owner can give credit." % r.first})
		sim.add_pressure(r, ev, 4)
		return
	var grocer = sim.residents[owners[0]]
	var rel: Dictionary = grocer.r(r.id)
	var outstanding := 0
	for d in sim.open_debts(r.id):
		if d["creditor"] == grocer.id and d["kind"] == "credit":
			outstanding += d["amount"]
	var p: float = 0.25 + 0.5 * grocer.traits["empathy"] + 0.3 * rel["trust"] - 0.5 * rel["resentment"]
	var units := mini(mini(need, 10), stock["food"])
	if units > 0 and outstanding < 40 and sim.rng.random() < p:
		var amount := units * price
		var ev: Dictionary = sim.emit("credit", "grocery", [grocer.id], {"targets": [r.id], "objects": [stock["id"]],
				"data": {"units": units, "owed": amount}, "intent": "lawful", "audibility": 1, "time": ta + 2,
				"summary": "%s lets %s take %d units on credit." % [grocer.first, r.first, units]})
		var pantry: Dictionary = sim.pantry(r)
		sim.transfer("food", "box:" + stock["id"], "box:" + pantry["id"], units, ev["id"], ta + 2)
		stock["expected_food"] -= units
		pantry["expected_food"] += units
		sim.world.add_debt(r.id, grocer.id, amount, ta + 7 * DAY, ta, ev["id"], "credit")
		sim.world.record("ledger", ta + 2, "%s on credit to %s: %d units (%d cr owed)" % [SimClock.fmt(ta), r.full_name(),
				units, amount], ev["id"])
		if sim.memory_on:
			var c := Memory.claim("debt", {"subject": r.id, "other": grocer.id, "amount": amount, "detail": "credit"})
			for p_ in [r.id, grocer.id]:
				sim.add_belief(p_, c, "self", 1.0, ta + 2, {"event": ev["id"]})
			Perception.broadcast(sim, ev, c)
	else:
		var ev: Dictionary = sim.emit("credit_refused", "grocery", [grocer.id], {"targets": [r.id], "audibility": 1,
				"time": ta + 2, "summary": "%s refuses %s credit." % [grocer.first, r.first]})
		sim.add_pressure(r, ev, 8)
		var mine: Dictionary = r.r(grocer.id)
		mine["resentment"] = clampf(mine["resentment"] + 0.06, 0.0, 1.0)
		if sim.memory_on:
			var c := Memory.claim("refusal", {"subject": grocer.id, "other": r.id, "start": ta,
					"detail": "credit at the grocery"})
			sim.add_belief(r.id, c, "self", 1.0, ta + 2, {"event": ev["id"]})
			sim.add_belief(grocer.id, c, "self", 1.0, ta + 2, {"event": ev["id"]})
			sim.add_belief(grocer.id, Memory.claim("hardship", {"subject": r.id, "start": ta,
					"detail": "cannot pay for food"}), "self", 0.9, ta + 2, {"event": ev["id"]})
			Perception.broadcast(sim, ev, c)
		else:
			sim.know_hardship(grocer.id, r.id, ta + 2)


static func close_business(sim, place: String, tm: int) -> void:
	var loc: Dictionary = sim.world.locations[place]
	var staff: Array = sim.staff_at(place, tm)
	if staff.is_empty():
		return
	var owners_here := []
	for s in staff:
		if s in loc["owners"]:
			owners_here.append(s)
	var closer = sim.residents[owners_here[0] if not owners_here.is_empty() else staff[0]]
	var owner = sim.residents[loc["owners"][0]] if not loc["owners"].is_empty() else null
	if place == "grocery" or place == "pub":
		for rid in sim.ids:
			var x = sim.residents[rid]
			if x.alive and not x.down and not (rid in loc["staff"]) and sim.where(rid, tm) == place:
				sim.forced[rid] = Decisions.plan("rest", x.home)  # closing time: everybody out
		var till: Dictionary = sim.world.containers["till:" + place]
		sim.count_container(till, closer.id, tm)
		if place == "grocery":
			sim.count_container(sim.world.containers["stock:grocery"], closer.id, tm)
		var book := "ledger" if place == "grocery" else "tabs"
		var cogs: int = int(sim.daily.get("pub_cogs", 0)) if place == "pub" else 0
		if cogs > 0 and till["cash"] > 0:
			var pay := mini(cogs, till["cash"])
			var ev: Dictionary = sim.emit("supplier_costs", place, [closer.id], {"objects": [till["id"]],
					"data": {"amount": pay}, "intent": "lawful", "time": tm,
					"summary": "%s settles the day's supplier costs (%d)." % [closer.first, pay]})
			sim.transfer("cash", "box:" + till["id"], "outside", pay, ev["id"], tm)
			till["expected_cash"] -= pay
			sim.world.record(book, tm, "%s supplier costs paid: %d cr" % [SimClock.fmt(tm), pay], ev["id"])
		for emp in loc["staff"]:
			var e = sim.residents[emp]
			if emp in loc["owners"] or not e.worked_today or not e.alive or e.wage == 0:
				continue
			_pay_wage(sim, e, till, owner, place, tm, book, closer.id)
		var float_amount: int = Config.TILL_FLOAT[place]
		if owner != null and owner.alive and owner.id in staff and till["cash"] - float_amount > 20:
			var take: int = till["cash"] - float_amount
			var ev: Dictionary = sim.emit("owner_withdrawal", place, [owner.id], {"objects": [till["id"]],
					"data": {"amount": take}, "intent": "lawful", "time": tm,
					"summary": "%s takes the day's takings (%d)." % [owner.first, take]})
			sim.transfer("cash", "box:" + till["id"], "wallet:" + owner.id, take, ev["id"], tm)
			till["expected_cash"] -= take
			sim.world.record(book, tm, "%s owner took %d cr of takings" % [SimClock.fmt(tm), take], ev["id"])
	elif place == "mill":
		var cashbox: Dictionary = sim.world.containers["cashbox:mill"]
		var hands := []
		for emp in loc["staff"]:
			var e = sim.residents[emp]
			if not (emp in loc["owners"]) and e.worked_today and e.alive and e.wage > 0:
				hands.append(e)
		var casuals := []
		for x in sim.alive():
			if int(sim.daily.get("odd:" + x.id, 0)) >= 3:
				casuals.append(x)
		var revenue: int = Config.ODD_JOB_PAY * casuals.size() + sim.profile["mill_margin"]
		for e in hands:
			revenue += e.wage
		revenue = maxi(0, revenue)
		if revenue > 0:
			var ev: Dictionary = sim.emit("mill_sales", "mill", [closer.id], {"objects": [cashbox["id"]],
					"data": {"amount": revenue}, "intent": "lawful", "time": tm,
					"summary": "The mill's timber sales bring in %d." % revenue})
			sim.transfer("cash", "outside", "box:" + cashbox["id"], revenue, ev["id"], tm)
			cashbox["expected_cash"] += revenue
		for e in hands:
			_pay_wage(sim, e, cashbox, owner, place, tm, "", closer.id)
		for c in casuals:
			var pay := int(round(Config.ODD_JOB_PAY * sim.profile["wage_mult"]))
			if cashbox["cash"] >= pay:
				var ev: Dictionary = sim.emit("wage", "mill", [closer.id], {"targets": [c.id], "objects": [cashbox["id"]],
						"data": {"amount": pay, "casual": true}, "intent": "lawful", "time": tm,
						"summary": "%s is paid %d for a day's casual work." % [c.first, pay]})
				sim.transfer("cash", "box:" + cashbox["id"], "wallet:" + c.id, pay, ev["id"], tm)
				cashbox["expected_cash"] -= pay
		if owner != null and owner.alive and owner.id in staff and cashbox["cash"] > 300:
			var take: int = cashbox["cash"] - 300
			var ev: Dictionary = sim.emit("owner_withdrawal", "mill", [owner.id], {"objects": [cashbox["id"]],
					"data": {"amount": take}, "intent": "lawful", "time": tm,
					"summary": "%s takes %d profit from the mill." % [owner.first, take]})
			sim.transfer("cash", "box:" + cashbox["id"], "wallet:" + owner.id, take, ev["id"], tm)
			cashbox["expected_cash"] -= take
	else:
		for emp in staff:
			var e = sim.residents[emp]
			if e.wage > 0 and e.worked_today:
				var ev: Dictionary = sim.emit("wage", place, [e.id], {"data": {"amount": e.wage, "from": "outside"},
						"intent": "lawful", "time": tm, "summary": "%s is paid %d for the day." % [e.first, e.wage]})
				sim.transfer("cash", "outside", "wallet:" + e.id, e.wage, ev["id"], tm)
	loc["locked"] = sim.rng.random() < 0.15 + 0.8 * closer.traits["diligence"]


static func _pay_wage(sim, e, cashbox: Dictionary, owner, place: String, tm: int, book: String, payer: String) -> void:
	## Wages come out of the business; an owner covers a short till from their own pocket.
	var src := ""
	var note := ""
	if cashbox["cash"] >= e.wage:
		src = "box:" + cashbox["id"]
	elif owner != null and owner.alive and owner.cash >= e.wage:
		src = "wallet:" + owner.id
		note = " (paid by the owner personally)"
	else:
		var ev: Dictionary = sim.emit("wage_unpaid", place, [payer], {"targets": [e.id], "data": {"amount": e.wage},
				"time": tm, "summary": "There is not enough money to pay %s." % e.first})
		sim.add_pressure(e, ev, 10)
		for o in sim.world.locations[place]["owners"]:
			var rel: Dictionary = e.r(o)
			rel["resentment"] = clampf(rel["resentment"] + 0.1, 0.0, 1.0)
		return
	var ev: Dictionary = sim.emit("wage", place, [payer], {"targets": [e.id], "objects": [cashbox["id"]],
			"data": {"amount": e.wage, "source": src}, "intent": "lawful", "time": tm,
			"summary": "%s is paid %d for the day%s." % [e.first, e.wage, note]})
	sim.transfer("cash", src, "wallet:" + e.id, e.wage, ev["id"], tm)
	if src.begins_with("box:"):
		cashbox["expected_cash"] -= e.wage
	if book != "":
		sim.world.record(book, tm, "%s wages to %s: %d cr%s" % [SimClock.fmt(tm), e.full_name(), e.wage, note], ev["id"])


# ============================================================== interactions
static func ask_loan(sim, r, x: String, ta: int) -> void:
	var lender = sim.residents[x]
	var here: String = sim.loc(r.id)
	r.cooldowns["loan:" + x] = ta + 5 * DAY
	var amount := int(clampf(sim.shortfall(r, ta) + 10, 20, 100))
	amount = mini(amount, maxi(0, lender.cash - 30))
	var p := loan_chance(sim, r, x)
	if amount >= 20 and sim.rng.random() < p:
		var ev: Dictionary = sim.emit("loan", here, [x], {"targets": [r.id], "data": {"amount": amount},
				"intent": "lawful", "audibility": 1, "time": ta,
				"summary": "%s lends %s %d crowns." % [lender.first, r.first, amount]})
		sim.transfer("cash", "wallet:" + x, "wallet:" + r.id, amount, ev["id"], ta)
		sim.world.add_debt(r.id, x, amount, ta + 7 * DAY, ta, ev["id"])
		if sim.memory_on:
			var c := Memory.claim("debt", {"subject": r.id, "other": x, "amount": amount, "start": ta, "detail": "loan"})
			for p_ in [r.id, x]:
				sim.add_belief(p_, c, "self", 1.0, ta, {"event": ev["id"]})
			Perception.broadcast(sim, ev, Memory.claim("loan", {"subject": r.id, "other": x, "location": here, "start": ta}))
		var mine: Dictionary = r.r(x)
		mine["trust"] = clampf(mine["trust"] + 0.05, 0.0, 1.0)
		mine["affection"] = clampf(mine["affection"] + 0.05, 0.0, 1.0)
	else:
		r.cooldowns["loan"] = ta + DAY
		var ev: Dictionary = sim.emit("loan_refused", here, [x], {"targets": [r.id], "data": {"asked": amount},
				"audibility": 1, "time": ta, "summary": "%s refuses to lend %s money." % [lender.first, r.first]})
		sim.add_pressure(r, ev, 8)
		var mine: Dictionary = r.r(x)
		mine["resentment"] = clampf(mine["resentment"] + 0.08 + 0.12 * r.traits["stubbornness"], 0.0, 1.0)
		if sim.memory_on:
			var c := Memory.claim("refusal", {"subject": x, "other": r.id, "start": ta, "detail": "a loan"})
			sim.add_belief(r.id, c, "self", 1.0, ta, {"event": ev["id"]})
			sim.add_belief(x, c, "self", 1.0, ta, {"event": ev["id"]})
			sim.add_belief(x, Memory.claim("hardship", {"subject": r.id, "start": ta, "detail": "asking around for money"}),
					"self", 0.9, ta, {"event": ev["id"]})
			Perception.broadcast(sim, ev, c)
		else:
			sim.know_hardship(x, r.id, ta)


static func loan_chance(sim, r, x: String) -> float:
	## How likely ``x`` is to lend to ``r``: kindness, trust and fondness for, resentment, caution, and (with
	## memory) every other debt of ``r`` that ``x`` knows of and hasn't heard was repaid.
	var lender = sim.residents[x]
	var rel: Dictionary = lender.r(r.id)
	var p: float = (0.15 + 0.45 * lender.traits["empathy"] + 0.35 * rel["trust"] + 0.25 * rel["affection"]
			- 0.7 * rel["resentment"] - 0.3 * lender.traits["caution"])
	if sim.memory_on:
		var owed := {}
		var repaid := {}
		for b in sim.memory[x].of_kind(["debt"]):
			var c: Dictionary = b["claim"]
			if c["subject"] == r.id:
				owed[c["other"]] = true
				if c["detail"] == "repaid":
					repaid[c["other"]] = true
		var unpaid := 0
		for o in owed:
			if not repaid.has(o):
				unpaid += 1
		p -= 0.25 * unpaid
	return p


static func repay(sim, r, plan: Dictionary, ta: int) -> void:
	var debt: Dictionary = {}
	for d in sim.open_debts(r.id):
		if d["id"] == plan["data"].get("debt", ""):
			debt = d
	if not debt.is_empty() and r.cash >= debt["amount"]:
		settle_debt(sim, r, debt, ta, sim.loc(r.id))


static func settle_debt(sim, r, debt: Dictionary, t: int, here: String) -> void:
	var ev: Dictionary = sim.emit("repay", here, [r.id], {"targets": [debt["creditor"]], "data": {"amount": debt["amount"],
			"debt": debt["id"]}, "causes": [debt["origin_event"]], "intent": "lawful", "audibility": 1, "time": t,
			"summary": "%s repays %d to %s." % [r.first, debt["amount"], sim.n(debt["creditor"])]})
	sim.transfer("cash", "wallet:" + r.id, "wallet:" + debt["creditor"], debt["amount"], ev["id"], t)
	debt["settled"] = t
	debt["settled_event"] = ev["id"]
	if sim.memory_on:
		var c := Memory.claim("debt", {"subject": r.id, "other": debt["creditor"], "amount": debt["amount"], "start": t,
				"detail": "repaid"})
		for p_ in [r.id, debt["creditor"]]:
			sim.add_belief(p_, c, "self", 1.0, t, {"event": ev["id"]})
		Perception.broadcast(sim, ev, c)
	var cred_rel: Dictionary = sim.residents[debt["creditor"]].r(r.id)
	cred_rel["resentment"] = clampf(cred_rel["resentment"] - 0.15, 0.0, 1.0)


static func help_out(sim, r, x: String, ta: int) -> void:
	r.cooldowns["help:" + x] = ta + 4 * DAY
	var amount := 25
	if r.cash < amount + 30:
		return
	var ev: Dictionary = sim.emit("help", sim.loc(r.id), [r.id], {"targets": [x], "data": {"amount": amount},
			"intent": "lawful", "audibility": 1, "time": ta,
			"summary": "%s gives %s %d crowns to tide them over." % [r.first, sim.n(x), amount]})
	sim.transfer("cash", "wallet:" + r.id, "wallet:" + x, amount, ev["id"], ta)
	if sim.memory_on:
		var c := Memory.claim("help", {"subject": r.id, "other": x, "start": ta, "amount": amount})
		for p_ in [r.id, x]:
			sim.add_belief(p_, c, "self", 1.0, ta, {"event": ev["id"]})
	var theirs: Dictionary = sim.residents[x].r(r.id)
	theirs["affection"] = clampf(theirs["affection"] + 0.1, 0.0, 1.0)
	theirs["trust"] = clampf(theirs["trust"] + 0.08, 0.0, 1.0)


static func reconcile(sim, r, x: String, ta: int) -> void:
	r.cooldowns["reconcile:" + x] = ta + 4 * DAY
	var target = sim.residents[x]
	var p: float = (0.4 + 0.4 * target.traits["empathy"] - 0.4 * target.traits["stubbornness"]
			- 0.3 * target.r(r.id)["resentment"])
	var accepted: bool = sim.rng.random() < p
	var ev: Dictionary = sim.emit("reconcile", sim.loc(r.id), [r.id], {"targets": [x], "data": {"accepted": accepted},
			"intent": "lawful", "audibility": 1, "time": ta, "summary": "%s tries to make peace with %s (%s)." % [r.first,
			target.first, "accepted" if accepted else "rebuffed"]})
	if accepted:
		r.r(x)["resentment"] = snappedf(r.r(x)["resentment"] * 0.5, 0.001)
		target.r(r.id)["resentment"] = snappedf(target.r(r.id)["resentment"] * 0.5, 0.001)
		sim.bump("deescalation:reconcile")
	if sim.memory_on:
		var c := Memory.claim("reconcile", {"subject": r.id, "other": x, "start": ta,
				"detail": "accepted" if accepted else "rebuffed"})
		for p_ in [r.id, x]:
			sim.add_belief(p_, c, "self", 1.0, ta, {"event": ev["id"]})


static func confront(sim, r, x: String, plan: Dictionary, ta: int) -> void:
	var target = sim.residents[x]
	var here: String = sim.loc(r.id)
	var pair: String = "argued:%s|%s" % ([r.id, x] if r.id < x else [x, r.id])
	if int(sim.daily.get(pair, -100000)) >= ta - 6 * 60:
		return  # they have only just had it out
	sim.daily[pair] = ta
	var reason: String = plan["reason"]
	var ref: String = plan["data"].get("ref", "")
	var days := 7
	if reason in ["debt", "rent"]:
		days = 4
	elif reason == "suspicion":
		days = 5
	r.cooldowns["confront:" + x] = ta + days * DAY
	var causes := []
	var debt := {}
	var topic := ""
	var suspicion := {}
	var incident_core = null  # what the accusation is really about, if anything happened there then
	if reason == "debt" or reason == "rent":
		debt = sim.world.debt(ref)
		if debt.is_empty() or debt["settled"] >= 0:
			return
		topic = "money owed (%d crowns%s)" % [debt["amount"], " of rent" if debt["kind"] == "rent" else ""]
		causes = [debt["overdue_event"] if debt["overdue_event"] != "" else debt["origin_event"]]
	elif reason == "suspicion":
		# an accusation, from what the accuser believes (a suspicion they inferred or were told)
		suspicion = sim.beliefs[ref]
		topic = "an accusation over " + suspicion["claim"]["detail"]
		for pid in suspicion["premises"]:
			var premise_event = sim.beliefs[pid]["event"]
			if premise_event and causes.size() < 3:
				causes.append(premise_event)
		if sim.crime_on:
			incident_core = Incidents.core_for_claim(sim, suspicion["claim"])
	else:
		topic = "an old grievance"
		for old in sim.events.events.slice(0, 20):
			var people: Array = old["actors"] + old["targets"]
			if old["kind"] == "prior_grudge" and r.id in people and x in people:
				causes.append(old["id"])
	var ev: Dictionary = sim.emit("argument", here, [r.id], {"targets": [x], "data": {"reason": reason, "topic": topic},
			"causes": causes, "audibility": 2, "notable": true, "time": ta,
			"summary": "%s confronts %s about %s." % [r.first, target.first, topic]})
	sim.bump("confrontations")
	var guilty: bool = incident_core != null and incident_core in target.guilty_of
	if sim.memory_on:
		var seen := Memory.claim("argument", {"subject": r.id, "other": x, "location": here, "start": ta, "detail": topic})
		var heard_detail := "raised voices" + (", something about money" if reason in ["debt", "rent"] else "")
		Perception.broadcast(sim, ev, seen, Memory.claim("noise", {"location": here, "start": ta, "detail": heard_detail}),
				r.id)
		for p_ in [r.id, x]:
			sim.add_belief(p_, seen, "self", 1.0, ta, {"event": ev["id"]})
		if not suspicion.is_empty():
			# now the accused knows someone suspects them (told to their face); if they didn't do it, they
			# resent it
			var s: Dictionary = suspicion["claim"]
			sim.add_belief(x, Memory.claim("suspect", {"subject": x, "location": s["location"], "start": s["start"],
					"end": s["end"], "detail": s["detail"]}), "told", 0.9, ta, {"event": ev["id"], "told_by": r.id,
					"via": ref})
			if not guilty:
				var theirs: Dictionary = target.r(r.id)
				theirs["resentment"] = clampf(theirs["resentment"] + 0.2, 0.0, 1.0)
	if not debt.is_empty() and target.cash >= debt["amount"]:
		settle_debt(sim, target, debt, ta + 1, here)
		sim.bump("deescalation:paid")
		return
	if guilty:
		# accused of what they really did: an honest, soft-hearted culprit may own up
		var tt: Dictionary = target.traits
		if sim.rng.random() < 0.05 + 0.5 * tt["honesty"] * tt["empathy"] - 0.25 * tt["caution"]:
			Crime.confess(sim, target, r, incident_core, ev, here, ta + 1)
			sim.bump("deescalation:confession")
			return

	var a = r
	var b = target
	var bystanders := []
	for y in sim.ids:
		if y != r.id and y != x and sim.awake_at(y, ta, here):
			bystanders.append(y)
	var heat: float = (0.5 * a.r(x)["resentment"] + 0.5 * b.r(r.id)["resentment"]
			+ 0.25 * (a.traits["impulsiveness"] + b.traits["impulsiveness"]) / 2
			+ (a.intox + b.intox) / 400.0 + sim.profile["impulsive_shift"])
	var calm: float = (0.35 * (a.traits["empathy"] + b.traits["empathy"]) / 2
			+ 0.25 * (a.traits["caution"] + b.traits["caution"]) / 2 + 0.08 * bystanders.size())
	var p := clampf(heat - calm - 0.42, 0.0, 0.25)
	if sim.rng.random() < p:
		if not sim.violence_on:
			# Without violence (crime off, or Pilot 3A) the argument stays in the log, and the fight that would
			# follow is counted rather than invented.
			sim.bump("escalations_deferred")
			return
		# the argument turns into a fight: the one more given to it hits the other
		var aggressor = a
		var victim = b
		if _aggression(b, a) > _aggression(a, b):
			aggressor = b
			victim = a
		Violence.assault(sim, aggressor, victim, ev, here, ta + 2, bystanders, reason)
		return
	var outcome := "walked_away"
	if not debt.is_empty():
		# the usual off-ramp for money owed: a promise and a new date
		outcome = "promise"
		debt["due"] = ta + 7 * DAY
		debt["overdue_event"] = ""
	elif a.traits["empathy"] + b.traits["empathy"] > 1.2 and sim.rng.random() < 0.4:
		outcome = "apology"
		a.r(x)["resentment"] = snappedf(a.r(x)["resentment"] * 0.7, 0.001)
		b.r(r.id)["resentment"] = snappedf(b.r(r.id)["resentment"] * 0.7, 0.001)
	else:
		a.r(x)["resentment"] = clampf(a.r(x)["resentment"] + 0.05, 0.0, 1.0)
		b.r(r.id)["resentment"] = clampf(b.r(r.id)["resentment"] + 0.08, 0.0, 1.0)
	sim.emit("parted", here, [r.id], {"targets": [x], "data": {"outcome": outcome}, "causes": [ev["id"]],
			"intent": "lawful", "time": ta + 2,
			"summary": "%s and %s part (%s)." % [r.first, target.first, outcome.replace("_", " ")]})
	sim.bump("deescalation:" + outcome)


static func _aggression(p, o) -> float:
	return p.traits["impulsiveness"] + p.intox / 100.0 + p.r(o.id)["resentment"]


# ============================================================== chats
static func incidental_chats(sim, t0: int) -> void:
	var groups := {}
	for r in sim.alive():
		if r.asleep or r.down:
			continue
		var node: String = sim.where(r.id, t0 + 50)
		if not groups.has(node):
			groups[node] = []
		groups[node].append(r.id)
	var nodes: Array = groups.keys()
	nodes.sort()
	for node in nodes:
		var people: Array = groups[node]
		if people.size() < 2:
			continue
		sim.rng.shuffle(people)
		for i in range(0, people.size() - 1, 2):
			var a = sim.residents[people[i]]
			var b = sim.residents[people[i + 1]]
			var p: float = 0.15 + 0.35 * (a.traits["sociability"] + b.traits["sociability"]) / 2
			p += 0.2 if node in ["pub", "square"] else 0.0
			p += 0.15 if a.household == b.household else 0.0
			if sim.rng.random() < p:
				chat(sim, a, b, node, t0 + 50 + sim.rng.randint(0, 8))


static func chat(sim, a, b, node: String, t: int) -> void:
	for pair in [[a, b], [b, a]]:
		var x = pair[0]
		var y = pair[1]
		x.social = clampf(x.social + 12, 0.0, 100.0)
		x.stress = clampf(x.stress - 2, 0.0, 100.0)
		var rel: Dictionary = x.r(y.id)
		rel["affection"] = clampf(rel["affection"] + 0.01, 0.0, 1.0)
	sim.bump("chats")
	if not sim.memory_on:
		# Pilot 1, before memory: every chat is logged, and nothing passes in it
		sim.emit("chat", node, [a.id], {"targets": [b.id], "data": {"shared": []}, "intent": "lawful", "time": t,
				"summary": "%s and %s talk." % [a.first, b.first]})
		return
	# As in Python, a chat is logged when something passes in it: what each of them brings up
	var ab: Array = Gossip.pick_gossip(sim, a, b, t)
	var ba: Array = Gossip.pick_gossip(sim, b, a, t)
	if ab.is_empty() and ba.is_empty():
		return
	var shared := []
	for item in ab + ba:
		shared.append(item["id"])
	var ev: Dictionary = sim.emit("chat", node, [a.id], {"targets": [b.id], "data": {"shared": shared},
			"intent": "lawful", "time": t, "summary": "%s and %s talk." % [a.first, b.first]})
	for belief in ab:
		Gossip.tell(sim, a.id, b.id, belief, ev["id"], t)
	for belief in ba:
		Gossip.tell(sim, b.id, a.id, belief, ev["id"], t)
	sim.bump("gossip_transfers", ab.size() + ba.size())
