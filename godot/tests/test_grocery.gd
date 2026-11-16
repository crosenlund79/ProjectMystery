## The grocery deadlock fix (scripts/sim/sim_actions.gd: shop, _provision), a deliberate difference from Python.
##
## In Python, buying food needs someone *else* serving. When, on a morning the shop opens, the grocer's and the
## assistant's households both have an empty pantry, both go shopping in their own shop instead of working; neither
## counts as serving, nobody can buy, and they try again every hour for the rest of the month while the town goes
## hungry. And a diligent grocer living alone seldom leaves work to shop, so seldom has food at home. In Godot,
## someone who works at the grocery may serve themselves while it is open and nobody else is serving (the usual
## price, into the till, in the ledger, never on credit), and buys for their household during their shift when it
## is running short (from a colleague serving, or serving themselves).
##
## Here: the rule itself, case by case; the old deadlock replayed in a real town; every month that stalled before
## the fix, run again; and solitary grocers' pantries. Every sale in every simulated month is also checked by
## scripts/sim/sim_check.gd (_check_shop), and the Python comparison in tests/test_sim.gd requires that no month
## stalls.
extends RefCounted

const Simulation = preload("res://scripts/sim/simulation.gd")
const SimCheck = preload("res://scripts/sim/sim_check.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Decisions = preload("res://scripts/sim/sim_decisions.gd")
const Actions = preload("res://scripts/sim/sim_actions.gd")
const TestSim = preload("res://tests/test_sim.gd")

const DAY := 1440
## Every month that stalled before the fix, in a survey of 40 towns per season with the crime layer off and on
## (CI run 42, commit 1949473): 13 with crime off, 16 with it on.
const STALLED_BEFORE := [
	["off", "normal", 5], ["off", "scarcity", 38], ["off", "crisis", 12], ["off", "crisis", 26], ["off", "crisis", 30],
	["off", "crisis", 36], ["off", "tension", 10], ["off", "tension", 11], ["off", "tension", 23],
	["off", "tension", 27], ["off", "tension", 34], ["off", "tension", 35], ["off", "tension", 39],
	["crime", "normal", 2], ["crime", "normal", 3], ["crime", "normal", 5], ["crime", "normal", 22],
	["crime", "normal", 38], ["crime", "scarcity", 38], ["crime", "crisis", 12], ["crime", "tension", 8],
	["crime", "tension", 10], ["crime", "tension", 11], ["crime", "tension", 13], ["crime", "tension", 18],
	["crime", "tension", 23], ["crime", "tension", 28], ["crime", "tension", 34], ["crime", "tension", 39],
]


func run(t, _tree) -> void:
	_self_service(t)
	_nobody_else(t)
	_colleague_serves(t)
	_no_credit_to_oneself(t)
	_during_the_shift(t)
	_old_deadlock(t)
	_stalled_before(t)
	_solitary_grocers(t)
	_survey()  # one-off, removed after CI


# ---------------------------------------------------------------- staging
static func _grocer(sim) -> String:
	return sim.world.containers["till:grocery"]["owners"][0]


static func _assistant(sim) -> String:
	for rid in sim.world.locations["grocery"]["staff"]:
		if sim.residents[rid].role == "shop_assistant":
			return rid
	return ""


static func _household_size(sim, rid: String) -> int:
	return sim.households[sim.residents[rid].household].size()


static func _town(want: String) -> int:
	## The first normal-season seed whose town has: "apart" the grocer and the assistant in different households of
	## two or more (where the old deadlock could happen); "alone" a grocer living alone.
	for seed in range(1, 200):
		var sim = Simulation.new({"seed": seed, "days": 30, "profile": "normal"})
		var g := _grocer(sim)
		var a := _assistant(sim)
		if a == "":
			continue
		var apart: bool = (sim.residents[g].household != sim.residents[a].household and _household_size(sim, g) >= 2
				and _household_size(sim, a) >= 2)
		if (want == "apart" and apart) or (want == "alone" and _household_size(sim, g) == 1):
			return seed
	return -1


func _staged(seed: int, at: int):
	## The town of ``seed`` at minute ``at``: everyone awake at home, nobody with plans, everyone with money.
	var sim = Simulation.new({"seed": seed, "days": 30, "profile": "normal"})
	sim.t = at
	sim.plans = {}
	for rid in sim.ids:
		var r = sim.residents[rid]
		r.asleep = false
		r.cash = maxi(r.cash, 200)
		sim.intervals[rid] = [[r.home, 0, -1]]
	return sim


func _place(sim, rid: String, node: String, kind: String) -> void:
	sim.intervals[rid] = [[node, 0, -1]]
	sim.plans[rid] = Decisions.plan(kind, node)


static func _empty(sim, rid: String) -> void:
	var p: Dictionary = sim.pantry(sim.residents[rid])
	p["food"] = 0
	p["expected_food"] = 0


static func _of_kind(sim, kind: String) -> Array:
	sim.events.commit()
	var out := []
	for ev in sim.events.events:
		if ev["kind"] == kind:
			out.append(ev)
	return out


static func _sale_problems(sim) -> Array:
	sim.events.commit()
	var out := []
	SimCheck._check_shop(sim, out)
	return out


# ---------------------------------------------------------------- the rule, case by case
func _self_service(t) -> void:
	t.begin("nobody else serving: both shop workers serve themselves, at the usual price, into the till and the ledger")
	var seed := _town("apart")
	t.check(seed > 0, "no normal-season town with the grocer and the assistant in separate households of two or more")
	if seed < 0:
		t.end()
		return
	var at := SimClock.at(8, 8, 30)  # Monday morning: the shop is open
	var sim = _staged(seed, at)
	var g := _grocer(sim)
	var a := _assistant(sim)
	var price: int = sim.profile["food_price"]
	var till: Dictionary = sim.world.containers["till:grocery"]
	var stock: Dictionary = sim.world.containers["stock:grocery"]
	for rid in [g, a]:
		_place(sim, rid, "grocery", "shop")
		_empty(sim, rid)
	var cash_before := {g: sim.residents[g].cash, a: sim.residents[a].cash}
	var till_before: int = till["cash"]
	var stock_before: int = stock["food"]
	Actions.shop(sim, sim.residents[g], at)
	Actions.shop(sim, sim.residents[a], at + 1)
	var sales := _of_kind(sim, "purchase")
	t.eq(sales.size(), 2, "both buy")
	var units := 0
	var paid := 0
	for ev in sales:
		var buyer: String = ev["actors"][0]
		t.check(ev["data"].get("self_service", false) and ev["targets"].is_empty(),
				"%s's sale is self-service, with nobody else serving: %s" % [buyer, ev])
		t.eq(ev["data"]["units"], _household_size(sim, buyer) * 8, "%s buys a full week's food" % buyer)
		t.eq(ev["data"]["paid"], ev["data"]["units"] * price, "at the usual price")
		t.eq(sim.residents[buyer].cash, cash_before[buyer] - ev["data"]["paid"], "paid from their own purse")
		t.eq(sim.pantry(sim.residents[buyer])["food"], ev["data"]["units"], "into their household's pantry")
		units += ev["data"]["units"]
		paid += ev["data"]["paid"]
	t.eq(till["cash"], till_before + paid, "the money is in the till")
	t.eq(stock["food"], stock_before - units, "the food has left the stock")
	t.eq(till["expected_cash"], till["cash"], "the till holds what the grocer expects")
	var lines := 0
	for rec in sim.world.records["ledger"]:
		if "(self-service)" in String(rec["text"]):
			lines += 1
	t.eq(lines, 2, "both sales are in the ledger, marked self-service")
	t.eq(_of_kind(sim, "credit").size() + _of_kind(sim, "credit_refused").size(), 0, "no credit")
	t.eq(_sale_problems(sim), [], "every sale rule holds")
	t.end()


func _nobody_else(t) -> void:
	t.begin("self-service is only for shop workers, only while the shop is open")
	var seed := _town("apart")
	var g := ""
	var a := ""
	# a customer alone in the shop, with nobody serving: no sale, as before
	var sim = _staged(seed, SimClock.at(8, 10, 30))
	g = _grocer(sim)
	a = _assistant(sim)
	var customer := ""
	for rid in sim.ids:
		if not (rid in sim.world.locations["grocery"]["staff"]):
			customer = rid
			break
	_place(sim, customer, "grocery", "shop")
	_empty(sim, customer)
	Actions.shop(sim, sim.residents[customer], sim.t)
	t.eq(_of_kind(sim, "purchase").size(), 0, "a customer cannot serve themselves")
	t.eq(int(sim.daily.get("shopped:" + sim.residents[customer].household, 0)), 0, "and may come back when someone serves")
	# a shop worker on Sunday, and after closing time: no sale
	for at in [SimClock.at(7, 11), SimClock.at(8, 18, 30), SimClock.at(8, 7, 30)]:
		var x = _staged(seed, at)
		_place(x, g, "grocery", "shop")
		_empty(x, g)
		Actions.shop(x, x.residents[g], at)
		t.eq(_of_kind(x, "purchase").size(), 0, "no self-service while the shop is shut (%s)" % SimClock.fmt(at))
	t.end()


func _colleague_serves(t) -> void:
	t.begin("with a colleague serving, a shop worker buys from them, and customers are served as before")
	var seed := _town("apart")
	var at := SimClock.at(9, 11, 30)  # Tuesday
	var sim = _staged(seed, at)
	var g := _grocer(sim)
	var a := _assistant(sim)
	_place(sim, a, "grocery", "work")
	_place(sim, g, "grocery", "shop")
	_empty(sim, g)
	var customer := ""
	for rid in sim.ids:
		if sim.residents[rid].household != sim.residents[g].household and sim.residents[rid].household != sim.residents[a].household:
			customer = rid
			break
	_place(sim, customer, "grocery", "shop")
	_empty(sim, customer)
	Actions.shop(sim, sim.residents[g], at)
	Actions.shop(sim, sim.residents[customer], at + 1)
	var sales := _of_kind(sim, "purchase")
	t.eq(sales.size(), 2, "the grocer and the customer both buy")
	for ev in sales:
		t.eq(ev["targets"], [a], "served by the assistant")
		t.check(not ev["data"].has("self_service"), "not self-service: %s" % ev)
		t.check(not ("serves themselves" in String(ev["summary"])), "an ordinary sale")
	t.eq(_sale_problems(sim), [], "every sale rule holds")
	t.end()


func _no_credit_to_oneself(t) -> void:
	t.begin("a shop worker short of money buys what they can pay for, and never gives themselves credit")
	var seed := _town("apart")
	var at := SimClock.at(8, 8, 30)
	var sim = _staged(seed, at)
	var g := _grocer(sim)
	var price: int = sim.profile["food_price"]
	_place(sim, g, "grocery", "shop")
	_empty(sim, g)
	sim.residents[g].cash = price * 2 + 1
	Actions.shop(sim, sim.residents[g], at)
	var sales := _of_kind(sim, "purchase")
	t.eq(sales.size(), 1, "a small sale")
	if sales.size() == 1:
		t.eq(sales[0]["data"]["units"], 2, "only what they can pay for")
	t.eq(_of_kind(sim, "credit").size() + _of_kind(sim, "credit_refused").size(), 0, "no credit asked or given")
	var broke = _staged(seed, at)
	_place(broke, g, "grocery", "shop")
	_empty(broke, g)
	broke.residents[g].cash = price - 1
	Actions.shop(broke, broke.residents[g], at)
	t.eq(_of_kind(broke, "purchase").size() + _of_kind(broke, "credit").size(), 0, "with no money, nothing")
	t.eq(int(broke.daily.get("shopped:" + broke.residents[g].household, 0)), 1, "and they do not try again that day")
	t.end()


func _during_the_shift(t) -> void:
	t.begin("a grocer living alone buys food during the shift: serving themselves, or from the assistant")
	var seed := _town("alone")
	t.check(seed > 0, "no normal-season town with a grocer living alone")
	if seed < 0:
		t.end()
		return
	# Monday 8:30, the assistant not in yet: the grocer, working, restocks by serving themselves
	var at := SimClock.at(8, 8, 30)
	var sim = _staged(seed, at)
	var g := _grocer(sim)
	var a := _assistant(sim)
	_place(sim, g, "grocery", "work")
	_empty(sim, g)
	Actions.perform(sim, sim.residents[g], sim.plans[g], at)
	var sales := _of_kind(sim, "purchase")
	t.eq(sales.size(), 1, "the grocer buys without leaving work")
	if sales.size() == 1:
		t.check(sales[0]["data"].get("self_service", false), "serving themselves, nobody else being in")
		t.eq(sim.pantry(sim.residents[g])["food"], 8, "a week's food for one")
	Actions.perform(sim, sim.residents[g], sim.plans[g], at + 60)
	t.eq(_of_kind(sim, "purchase").size(), 1, "once a day")
	# Tuesday 10:30, the assistant serving and the grocer's pantry low: bought from the assistant
	var tue := SimClock.at(9, 10, 30)
	var x = _staged(seed, tue)
	_place(x, a, "grocery", "work")
	_place(x, g, "grocery", "work")
	var p: Dictionary = x.pantry(x.residents[g])
	p["food"] = 3
	p["expected_food"] = 3
	Actions.perform(x, x.residents[g], x.plans[g], tue)
	sales = _of_kind(x, "purchase")
	t.eq(sales.size(), 1, "a running-short grocer buys during the shift")
	if sales.size() == 1:
		t.eq(sales[0]["targets"], [a], "from the assistant, who is serving")
		t.eq(sales[0]["data"]["units"], 5, "enough for the week")
	# with enough at home, nothing
	var y = _staged(seed, tue)
	_place(y, g, "grocery", "work")
	Actions.perform(y, y.residents[g], y.plans[g], tue)
	t.eq(_of_kind(y, "purchase").size(), 0 if y.pantry(y.residents[g])["food"] >= 4 else 1,
			"no buying with half a week's food at home")
	t.eq(_sale_problems(sim) + _sale_problems(x), [], "every sale rule holds")
	t.end()


# ---------------------------------------------------------------- whole towns
func _old_deadlock(t) -> void:
	t.begin("the old deadlock, replayed: both shop workers out of food on a Monday morning, and the shop trades on")
	var seed := _town("apart")
	var sim = Simulation.new({"seed": seed, "days": 30, "profile": "normal"})
	sim.run(SimClock.at(8, 7))  # Monday Day 8, 07:00
	var g := _grocer(sim)
	var a := _assistant(sim)
	var customer := ""
	for rid in sim.ids:
		if sim.residents[rid].household != sim.residents[g].household and sim.residents[rid].household != sim.residents[a].household:
			customer = rid
			break
	for rid in [g, a, customer]:
		_empty(sim, rid)
	sim.run(SimClock.at(8, 9))  # the 8:00 hour
	var shopping := 0
	for rid in [g, a]:
		if sim.plans.get(rid, {}).get("kind", "") == "shop":
			shopping += 1
	t.eq(shopping, 2, "both shop workers go shopping in their own shop, as in Python's deadlock")
	var self_served := []
	for ev in _of_kind(sim, "purchase"):
		if ev["time"] >= SimClock.at(8, 8) and ev["data"].get("self_service", false):
			self_served.append(ev["actors"][0])
	self_served.sort()
	var both := [g, a]
	both.sort()
	t.eq(self_served, both, "both serve themselves in that hour")
	var worked := {}
	for h in range(9, 13):
		sim.run(SimClock.at(8, h + 1))
		for rid in [g, a]:
			if sim.plans.get(rid, {}).get("kind", "") == "work":
				worked[rid] = true
	t.eq(worked.size(), 2, "by noon both are back at work")
	sim.run(SimClock.at(9, 0))
	var served_others := 0
	var customer_bought := false
	for ev in _of_kind(sim, "purchase"):
		if ev["time"] >= SimClock.at(8, 8) and ev["time"] < SimClock.at(9, 0) and not ev["data"].get("self_service", false):
			served_others += 1
			if sim.residents[ev["actors"][0]].household == sim.residents[customer].household:
				customer_bought = true
	t.check(served_others > 0, "the shop serves others that day")
	t.check(customer_bought, "the household that also ran out buys food that day")
	sim.run()
	t.eq(TestSim._stall_day(sim), -1, "the shop trades to the end of the month")
	t.eq(_sale_problems(sim), [], "every sale rule holds")
	t.end()


@warning_ignore("integer_division")
func _stalled_before(t) -> void:
	t.begin("every month that stalled before the fix now trades to the end, with every rule holding")
	var stalled := []
	var self_service := 0
	var both_in_one_hour := 0
	var started := Time.get_ticks_msec()
	for c in STALLED_BEFORE:
		var sim = Simulation.new({"seed": c[2], "days": 30, "profile": c[1], "crime": c[0] == "crime"}).run()
		var d: int = TestSim._stall_day(sim)
		if d > 0:
			stalled.append("%s %s seed %d from Day %d" % [c[0], c[1], c[2], d])
		t.eq(SimCheck.problems(sim), [], "%s %s seed %d" % [c[0], c[1], c[2]])
		var hours := {}  # hour -> staff who served themselves in it
		for ev in sim.events.events:
			if ev["kind"] == "purchase" and ev["data"].get("self_service", false):
				self_service += 1
				var h: int = ev["time"] / 60
				hours[h] = int(hours.get(h, 0)) + 1
		for h in hours:
			if hours[h] >= 2:
				both_in_one_hour += 1
	t.eq(stalled, [], "months that still stall")
	print("  %d formerly stalled months run again: none stalls; %d self-service sales; %d hours in which both shop workers served themselves (each the start of a deadlock under Python's rule); %d ms" % [
			STALLED_BEFORE.size(), self_service, both_in_one_hour, Time.get_ticks_msec() - started])
	t.check(both_in_one_hour > 0, "the old trap still arises in these towns, and is now resolved")
	t.end()


static func empty_at_opening(sim) -> Array:
	## [openings, openings at which the grocer's household pantry was empty at the end of the first open hour]: the
	## grocer's household pantry replayed from the transfers, measured as for Python's solitary grocers.
	var acct := "box:pantry:" + String(sim.residents[_grocer(sim)].household)
	var food: int = sim.initial_balances[acct]["food"]
	var transfers: Array = sim.world.transfers
	var i := 0
	var openings := 0
	var empty := 0
	for d in range(1, int(sim.config["days"]) + 1):
		var at := SimClock.at(d, 9)
		while i < transfers.size() and int(transfers[i]["time"]) < at:
			var tr: Dictionary = transfers[i]
			if tr["asset"] == "food":
				if tr["src"] == acct:
					food -= int(tr["amount"])
				if tr["dst"] == acct:
					food += int(tr["amount"])
			i += 1
		if SimClock.is_rest_day(at):
			continue
		openings += 1
		empty += 1 if food == 0 else 0
	return [openings, empty]


func _solitary_grocers(t) -> void:
	t.begin("grocers living alone keep food at home")
	var openings := 0
	var empty := 0
	var towns := 0
	for seed in range(1, 41):
		var sim = Simulation.new({"seed": seed, "days": 30, "profile": "normal"})
		if _household_size(sim, _grocer(sim)) != 1:
			continue
		sim.run()
		var oe := empty_at_opening(sim)
		openings += oe[0]
		empty += oe[1]
		towns += 1
		if towns == 8:
			break
	print("  grocers living alone: %d towns, pantry empty after the first open hour on %d of %d shop days (Python, without the fix: 49%%)" % [
			towns, empty, openings])
	t.check(towns > 0 and empty * 4 < openings, "a solitary grocer's pantry is empty on %d of %d shop days" % [empty, openings])
	t.end()


@warning_ignore("integer_division")
func _survey() -> void:
	## One-off: the 40-town-per-season stall survey of CI run 42, run again with the fix.
	for layer in ["off", "crime"]:
		for profile in TestSim.PROFILES:
			var stalled := PackedStringArray()
			var self_service := 0
			var both := 0
			var solo := [0, 0]
			var started := Time.get_ticks_msec()
			for seed in range(1, 41):
				var sim = Simulation.new({"seed": seed, "days": 30, "profile": profile, "crime": layer == "crime"}).run()
				var d: int = TestSim._stall_day(sim)
				if d > 0:
					stalled.append("seed %d from Day %d" % [seed, d])
				var hours := {}
				for ev in sim.events.events:
					if ev["kind"] == "purchase" and ev["data"].get("self_service", false):
						self_service += 1
						var h: int = ev["time"] / 60
						hours[h] = int(hours.get(h, 0)) + 1
				for h in hours:
					if hours[h] >= 2:
						both += 1
				if _household_size(sim, _grocer(sim)) == 1:
					var oe := empty_at_opening(sim)
					solo[0] += oe[0]
					solo[1] += oe[1]
			print("  grocery survey %s %s: %d of 40 months stalled %s; %d self-service sales; %d hours with both shop workers serving themselves; solitary grocers' pantry empty on %d of %d shop days; %d ms" % [
					layer, profile, stalled.size(), ", ".join(stalled), self_service, both, solo[1], solo[0],
					Time.get_ticks_msec() - started])
