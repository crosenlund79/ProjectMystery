## The crime layer, Pilot 3A (scripts/sim/sim_crime.gd, sim_incidents.gd and their hooks), rule by rule, on a
## real town with the crime switch on, whose memories are cleared and whose people are placed by each scenario.
## The whole-run rules (money conserved, every loss explained, every trace and every belief with a source) are
## in scripts/sim/sim_check.gd and run from tests/test_sim.gd on every simulated month with crime on.
extends RefCounted

const Simulation = preload("res://scripts/sim/simulation.gd")
const SimCheck = preload("res://scripts/sim/sim_check.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Memory = preload("res://scripts/sim/sim_memory.gd")
const Gossip = preload("res://scripts/sim/sim_gossip.gd")
const Decisions = preload("res://scripts/sim/sim_decisions.gd")
const Actions = preload("res://scripts/sim/sim_actions.gd")
const Crime = preload("res://scripts/sim/sim_crime.gd")
const Incidents = preload("res://scripts/sim/sim_incidents.gd")

const DAY := 1440


func run(t, _tree) -> void:
	_switch(t)
	_theft_and_discovery(t)
	_forced_door(t)
	_who_steals(t)
	_nobody_steals_in_company(t)
	_stolen_food_and_spending(t)
	_undiscovered(t)
	_ledger_mistake_and_false_suspicion(t)
	_confession(t)
	_concealment(t)
	_whole_months(t)


# ---------------------------------------------------------------- staging
func _fresh(seed := 3):
	## A town at Day 1 23:00 with the crime layer on, where nobody knows anything yet, nobody bears a grudge,
	## and everyone is awake at home.
	var sim = Simulation.new({"seed": seed, "days": 3, "crime": true})
	sim.t = SimClock.at(1, 23)
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


func _move(sim, rid: String, node: String, at: int) -> void:
	var ivs: Array = sim.intervals[rid]
	ivs[-1][2] = at
	ivs.append([node, at, -1])


static func _apart(sim, a: String) -> Array:
	## Residents of other households than ``a``.
	var out := []
	for x in sim.ids:
		if sim.residents[x].household != sim.residents[a].household:
			out.append(x)
	return out


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


static func _knowers(sim) -> Array:
	## Everyone who believes anything at all.
	var out := []
	for rid in sim.ids:
		if not sim.memory[rid].beliefs.is_empty():
			out.append(rid)
	return out


func _steal(sim, thief: String, cid: String, at: int) -> Dictionary:
	## The thief, already where the container is, takes from it. Returns the theft event, or {}.
	var c: Dictionary = sim.world.containers[cid]
	Crime.steal(sim, sim.residents[thief], Decisions.plan("steal", c["location"], cid, "pressure"), at)
	var thefts := _events(sim, "theft")
	return thefts[-1] if not thefts.is_empty() else {}


func _rules(sim) -> Array:
	## The whole-run crime and knowledge rules, over what the scenario made happen.
	sim.events.commit()
	sim.t = SimClock.at(5, 0)
	var out := []
	SimCheck._check_crime(sim, out)
	SimCheck._check_memory(sim, out)
	return out


# ---------------------------------------------------------------- scenarios
func _switch(t) -> void:
	t.begin("the crime switch: off by default, and crime needs memory")
	var off = Simulation.new({"seed": 2, "days": 1})
	t.eq([off.crime_on, off.config["crime"]], [false, false], "off unless asked for")
	var bad = Simulation.new({"seed": 2, "days": 1, "crime": true, "memory": false})
	t.check(not bad.ok, "crime without memory is refused: nobody could discover, suspect or conceal anything")
	t.end()


func _theft_and_discovery(t) -> void:
	t.begin("a theft nobody sees: only the thief knows, until counting the till finds it short")
	var sim = _fresh()
	var till: Dictionary = sim.world.containers["till:grocery"]
	var grocer: String = till["owners"][0]
	var others := _apart(sim, grocer)
	var thief: String = others[0]
	var witness: String = others[1]
	var before: int = till["cash"]
	var night: int = sim.t
	_move(sim, thief, "grocery", night + 10)
	var ev := _steal(sim, thief, "till:grocery", night + 46)
	t.check(not ev.is_empty(), "the till is robbed")
	if ev.is_empty():
		t.end()
		return
	var amount: int = ev["data"]["amount"]
	t.check(amount >= int(before * 0.5) and amount <= int(before * 0.9), "half to nine tenths of it (%d of %d)" % [amount,
			before])
	t.eq([till["cash"], till["expected_cash"]], [before - amount, before], "the till holds less; its owner expects the same")
	t.eq(sim.world.containers["stash:" + thief]["cash"], amount, "the money is in the thief's own stash")
	t.check(ev.get("discreet", false), "done so as not to be seen")
	var inc: Dictionary = Incidents.incident_for(sim, ev["id"])
	t.eq([inc.get("family"), inc.get("responsible"), inc.get("discovered_at"), inc.get("motive")],
			["theft", thief, null, "money_trouble"], "registered as the thief's theft, not yet discovered")
	t.eq(_knowers(sim), [thief], "nobody but the thief knows anything")
	t.eq(sim.memory[thief].of_kind(["theft_self"]).size(), 1, "the thief knows what they did")

	_move(sim, thief, sim.residents[thief].home, night + 70)
	Crime.hide_loot(sim, sim.residents[thief], night + 115)
	t.eq(_events(sim, "hide_loot").size(), 1, "back home, the loot is hidden")
	t.eq(_evidence(sim, "stash").size(), 1, "which leaves a trace at home")
	t.eq(sim.residents[thief].pending_hide, [], "with nothing left to hide")
	t.eq(_knowers(sim), [thief], "still, nobody else knows")

	var morning := SimClock.at(2, 8, 50)
	_move(sim, grocer, "grocery", morning - 40)
	_move(sim, witness, "grocery", morning - 30)
	sim.count_container(till, grocer, morning)
	var found := _events(sim, "loss_discovered")
	t.eq(found.size(), 1, "counting the till finds it short")
	if not found.is_empty():
		t.eq([found[0]["data"]["cash"], found[0]["causes"]], [amount, [ev["id"]]],
				"short by exactly what was taken, explained (in the log only) by the theft")
	t.eq([inc["discovered_at"], inc["discovered_by"]], [morning, grocer], "the theft is discovered by whoever counted")
	t.check(inc["window"][0] <= ev["time"] and ev["time"] <= inc["window"][1], "and it happened inside the window")
	t.check(inc["case_start"] != null and inc["case_start"] > morning, "a case could start an hour or two later")
	var g: Array = sim.memory[grocer].of_kind(["loss"])
	var w: Array = sim.memory[witness].of_kind(["loss"])
	t.eq([g.size(), g[0]["source"] if not g.is_empty() else ""], [1, "self"], "the grocer knows the money is gone")
	t.eq([w.size(), w[0]["source"] if not w.is_empty() else ""], [1, "saw"], "the customer there sees it found")
	for x in sim.ids:
		if not (x in [thief, grocer, witness]):
			t.eq(sim.memory[x].beliefs.size(), 0, "%s, at home, knows nothing" % x)
	t.eq(sim.memory[grocer].of_kind(["theft_self", "stash", "suspect"]), [], "and the grocer does not know who")
	t.eq(_rules(sim), [], "every crime and knowledge rule held")
	t.end()


func _forced_door(t) -> void:
	t.begin("a locked door is forced: heard next door, noticed by whoever opens up, mended a day later")
	var sim = _fresh(5)
	var grocer: String = sim.world.containers["till:grocery"]["owners"][0]
	var others := _apart(sim, grocer)
	var thief: String = others[0]
	sim.residents[thief].traits["caution"] = 0.2
	sim.world.locations["grocery"]["locked"] = true
	var night: int = sim.t
	var listeners := []
	for x in others.slice(1, 5):
		_move(sim, x, "square", night + 5)
		listeners.append(x)
	_move(sim, thief, "grocery", night + 10)
	var ev := _steal(sim, thief, "till:grocery", night + 46)
	_move(sim, thief, sim.residents[thief].home, night + 60)
	var forced := _events(sim, "forced_entry")
	t.eq(forced.size(), 1, "the door is forced")
	t.check(not ev.is_empty() and not forced.is_empty() and forced[0]["id"] in ev["causes"], "on the way to the theft")
	t.check(not sim.world.locations["grocery"]["locked"], "and stays open")
	var doors := _evidence(sim, "forced_door")
	t.eq(doors.size(), 1, "the forced door is a trace")
	if doors.is_empty() or ev.is_empty():
		t.end()
		return
	var door: Dictionary = doors[0]
	var heard := 0
	for x in listeners:
		for b in sim.memory[x].beliefs:
			t.eq([b["source"], b["claim"]["kind"], b["claim"]["subject"]], ["heard", "noise", null],
					"the square only hears a noise: not who, not what")
			heard += 1
	t.check(heard > 0, "someone on the square hears the crack of splintering wood (%d)" % heard)
	t.eq([door["created_by"], door["noticed_by"]], [forced[0]["id"], []],
			"the trace points at the forced entry that made it; nobody has seen it yet")

	var morning := SimClock.at(2, 8, 50)
	_move(sim, grocer, "grocery", morning - 40)
	sim.daily = {}
	Actions.do_work(sim, sim.residents[grocer], morning)
	t.check(grocer in door["noticed_by"], "whoever opens up sees the door first")
	var damage: Array = sim.memory[grocer].of_kind(["damage"])
	t.check(damage.size() == 1 and damage[0]["source"] == "saw" and "forced" in damage[0]["claim"]["detail"],
			"and knows it was forced, having seen it")
	t.eq(_events(sim, "loss_discovered").size(), 1, "then counts the till and finds it short")
	var inc: Dictionary = Incidents.incident_for(sim, ev["id"])
	t.check(String(inc.get("hook_text", "")).ends_with("The back door had been forced."), "a short till behind a forced door")
	t.check(forced[0]["id"] in inc.get("related_events", []), "the forced entry belongs to the incident")

	var mend := SimClock.at(3, 9)  # 33 hours later, by daylight
	var mender: String = listeners[0]
	_move(sim, grocer, sim.residents[grocer].home, mend - 120)
	_move(sim, mender, "grocery", mend + 5)
	Crime.tidy_evidence(sim, mend)
	t.check(door["removed_at"] >= 0, "the door is mended")
	var cleaned := _events(sim, "cleaned_up")
	t.eq(cleaned.size(), 1, "by someone who came by")
	if not cleaned.is_empty():
		t.eq([cleaned[0]["actors"], cleaned[0]["intent"], cleaned[0]["data"]["evidence"]], [[mender], "lawful", door["id"]],
				"lawfully, not to cover anything up")
	t.check(mender in door["noticed_by"], "and whoever mends it has seen it")
	t.eq(_rules(sim), [], "every crime and knowledge rule held")
	t.end()


func _who_steals(t) -> void:
	t.begin("stealing is an option only when pressure, temperament and an opportunity line up")
	var sim = _fresh()
	var grocer: String = sim.world.containers["till:grocery"]["owners"][0]
	var r = sim.residents[_apart(sim, grocer)[0]]
	r.traits["honesty"] = 0.1
	r.traits["empathy"] = 0.1
	r.traits["caution"] = 0.0
	r.traits["impulsiveness"] = 0.9
	var night := SimClock.at(1, 23)
	var p: Dictionary = Decisions._steal_intent(sim, r, night, 1.0)
	t.eq([p.get("kind"), String(p.get("target", "")).begins_with("till:"), p.get("reason")], ["steal", true, "pressure"],
			"in money trouble, at night, a business till")
	t.eq(Decisions._steal_intent(sim, r, night, 0.2), {}, "without money trouble, no")
	t.eq(Decisions._steal_intent(sim, r, SimClock.at(1, 18), 1.0), {}, "nor in the early evening, with nothing to take")
	r.traits["honesty"] = 0.8
	t.eq(Decisions._steal_intent(sim, r, night, 1.0), {}, "an honest person never considers it")
	r.traits["honesty"] = 0.1
	r.cooldowns["steal"] = night + DAY
	t.eq(Decisions._steal_intent(sim, r, night, 1.0), {}, "nor tries again so soon")
	r.cooldowns = {}
	sim.pantry(r)["food"] = 0
	r.cash = 0
	r.hunger = 80.0
	p = Decisions._steal_intent(sim, r, night, 0.0)
	t.eq([p.get("kind"), p.get("target")], ["steal", "stock:grocery"], "hungry with nothing to eat or pay with: food")
	t.end()


func _nobody_steals_in_company(t) -> void:
	t.begin("nobody steals with someone there")
	var sim = _fresh()
	var till: Dictionary = sim.world.containers["till:pub"]
	var publican: String = till["owners"][0]
	var thief: String = _apart(sim, publican)[0]
	var before: int = till["cash"]
	_move(sim, thief, "pub", sim.t + 10)
	_move(sim, publican, "pub", sim.t + 20)
	var ev := _steal(sim, thief, "till:pub", sim.t + 46)
	t.eq(ev, {}, "no theft")
	var aborted := _events(sim, "theft_aborted")
	t.check(aborted.size() == 1 and aborted[0]["data"]["why"] == "someone was there", "they think better of it")
	t.eq([till["cash"], sim.incidents.size(), sim.residents[thief].guilty_of], [before, 0, []], "nothing taken, nothing to find")
	t.end()


func _stolen_food_and_spending(t) -> void:
	t.begin("stolen food goes into the thief's pantry; stolen money is spent from the stash")
	var sim = _fresh(4)
	var stock: Dictionary = sim.world.containers["stock:grocery"]
	var grocer: String = stock["owners"][0]
	var thief: String = _apart(sim, grocer)[0]
	var r = sim.residents[thief]
	var pantry: Dictionary = sim.pantry(r)
	var food_before: int = pantry["food"]
	_move(sim, thief, "grocery", sim.t + 10)
	var ev := _steal(sim, thief, "stock:grocery", sim.t + 46)
	var units: int = ev["data"]["amount"] if not ev.is_empty() else 0
	t.check(units >= 8 and units <= 16, "8 to 16 units of food (%d)" % units)
	_move(sim, thief, r.home, sim.t + 70)
	Crime.hide_loot(sim, r, sim.t + 115)
	t.eq([pantry["food"], pantry["expected_food"], sim.stash(r)["food"]], [food_before + units, food_before + units, 0],
			"once home it is in their pantry, where the household will eat it")
	# a second, cash theft, then a lean morning
	var till: Dictionary = sim.world.containers["till:pub"]
	sim.world.containers["stash:" + thief]["cash"] = 0
	_move(sim, thief, "pub", SimClock.at(2, 0, 10))
	var cash_theft := _steal(sim, thief, "till:pub", SimClock.at(2, 0, 46))
	t.check(not cash_theft.is_empty() and cash_theft["data"]["asset"] == "cash", "a till robbed")
	_move(sim, thief, r.home, SimClock.at(2, 1, 10))
	Crime.hide_loot(sim, r, SimClock.at(2, 1, 55))
	var tin: Dictionary = sim.box(r)
	var tin_before: int = tin["cash"]
	var hidden: int = sim.stash(r)["cash"]
	r.cash = 10
	sim._morning_cash(r, SimClock.at(2, 7))
	var spent := _events(sim, "stash_withdraw")
	t.eq(spent.size(), 1, "short of money, they take from the hidden stash")
	if not spent.is_empty():
		var take := mini(40, hidden)
		t.eq([r.cash, sim.stash(r)["cash"], tin["cash"]], [10 + take, hidden - take, tin_before],
				"quietly, leaving the household tin alone")
		t.eq(spent[0]["causes"], [cash_theft["id"]], "money that came from the theft")
		t.check(spent[0].get("discreet", false), "unseen")
	t.check(till["cash"] < till["expected_cash"], "the pub till is still short, until someone counts it")
	t.end()


func _undiscovered(t) -> void:
	t.begin("undiscovered thefts: a few crowns put down to miscounting, a tin nobody opens")
	var sim = _fresh(6)
	var till: Dictionary = sim.world.containers["till:grocery"]
	var grocer: String = till["owners"][0]
	var others := _apart(sim, grocer)
	var thief: String = others[0]
	till["cash"] = 5
	till["expected_cash"] = 5
	_move(sim, thief, "grocery", sim.t + 10)
	var small := _steal(sim, thief, "till:grocery", sim.t + 46)
	t.check(not small.is_empty() and small["data"]["amount"] < 5, "a few crowns from a nearly empty till")
	_move(sim, grocer, "grocery", SimClock.at(2, 8, 30))
	sim.count_container(till, grocer, SimClock.at(2, 8, 50))
	t.eq(_events(sim, "loss_discovered"), [], "too little to notice: put down to miscounting")
	t.eq([till["expected_cash"], till["unexplained"]], [till["cash"], []], "and written off in the books")
	var inc: Dictionary = Incidents.incident_for(sim, small["id"]) if not small.is_empty() else {}
	t.eq(inc.get("discovered_at", "none"), null, "the theft stays undiscovered")
	t.eq(_knowers(sim), [thief], "and only the thief knows of it")

	# by day, a house whose people are all out
	var victim_house := ""
	for hid in sim.households:
		if hid != sim.residents[thief].household and hid != sim.residents[grocer].household:
			victim_house = hid
			break
	for m in sim.households[victim_house]:
		_move(sim, m, "square", SimClock.at(2, 9))
	var tin: Dictionary = sim.world.containers["box:" + victim_house]
	tin["cash"] = 200
	tin["expected_cash"] = 200
	_move(sim, thief, "home:" + victim_house, SimClock.at(2, 11, 10))
	var tin_theft := _steal(sim, thief, "box:" + victim_house, SimClock.at(2, 11, 46))
	t.check(not tin_theft.is_empty() and tin_theft["objects"] == ["box:" + victim_house], "the household tin is robbed")
	var tin_inc: Dictionary = Incidents.incident_for(sim, tin_theft["id"]) if not tin_theft.is_empty() else {}
	t.eq([tin_inc.get("discovered_at", "none"), _knowers(sim)], [null, [thief]], "nobody opens it: undiscovered, unknown")
	t.end()


func _ledger_mistake_and_false_suspicion(t) -> void:
	t.begin("a ledger mistake: money that never was is found missing, and an innocent is suspected")
	var sim = _fresh()
	sim.t = SimClock.at(1, 10)
	var till: Dictionary = sim.world.containers["till:grocery"]
	var grocer: String = till["owners"][0]
	var others := _apart(sim, grocer)
	var buyer: String = others[0]
	var z: String = others[1]
	var g = sim.residents[grocer]
	g.traits["caution"] = 0.0
	g.traits["empathy"] = 0.0
	var sale: Dictionary = sim.emit("purchase", "grocery", [buyer], {"targets": [grocer], "objects": ["till:grocery"],
			"data": {"units": 3, "paid": 12}, "intent": "lawful", "time": SimClock.at(1, 10, 46)})
	var expected: int = till["expected_cash"]
	Crime.ledger_error(sim, grocer, sim.residents[buyer], till, 12, "sale written twice", sale, SimClock.at(1, 10, 46))
	t.eq(till["expected_cash"], expected + 12, "the books now expect 12 crowns that never came in")
	var inc: Dictionary = sim.incidents[0] if not sim.incidents.is_empty() else {}
	t.eq([inc.get("family"), inc.get("responsible"), inc.get("outcome")], ["accounting_error", null, "no_crime"],
			"an accounting error: nobody took anything")
	var close := SimClock.at(1, 17, 59)
	_move(sim, grocer, "grocery", SimClock.at(1, 10, 30))
	sim.count_container(till, grocer, close)
	var found := _events(sim, "loss_discovered")
	t.check(found.size() == 1 and found[0]["data"]["cash"] == 12, "at closing the till looks 12 crowns short")
	t.eq(inc.get("discovered_by"), grocer, "the mistake is 'discovered' as a loss")
	# the grocer saw z by the till that afternoon, and has heard z is short of money
	sim.add_belief(grocer, Memory.claim("presence", {"subject": z, "location": "grocery", "start": SimClock.at(1, 14),
			"end": SimClock.at(1, 14, 30)}), "saw", 0.9, SimClock.at(1, 14), {"event": null})
	sim.add_belief(grocer, Memory.claim("hardship", {"subject": z, "start": SimClock.at(1, 9)}), "told", 0.6,
			SimClock.at(1, 12), {"event": null, "told_by": others[2]})
	Gossip.infer_suspicions(sim, grocer, SimClock.at(1, 20))
	var sus: Array = sim.memory[grocer].of_kind(["suspect"])
	t.eq(sus.size(), 1, "the grocer puts two and two together")
	if sus.is_empty():
		t.end()
		return
	t.eq(sus[0]["claim"]["subject"], z, "and makes five: z is suspected")
	var truth := SimCheck.incident_at(sim, sus[0]["claim"])
	t.eq([truth.get("family"), truth.get("responsible")], ["accounting_error", null], "of a theft that never happened")
	var plan := Decisions.plan("confront", "grocery", z, "suspicion", 50.0, {"ref": sus[0]["id"]})
	_move(sim, z, "grocery", SimClock.at(1, 20, 10))
	var resent: float = sim.residents[z].r(grocer)["resentment"]
	Actions.confront(sim, g, z, plan, SimClock.at(1, 20, 46))
	t.eq(_events(sim, "confession"), [], "z has nothing to confess")
	t.check(sim.residents[z].r(grocer)["resentment"] >= resent + 0.2 - 1e-9, "and resents being accused")
	t.eq(sim.memory[z].of_kind(["suspect"]).size(), 1, "now z knows they are suspected")
	t.end()


func _confession(t) -> void:
	t.begin("accused of what they really did, a culprit may confess and hand the money back")
	var confessions := 0
	var denials := 0
	for seed in [3, 4, 5, 6, 7, 8, 9, 10]:
		var sim = _fresh(seed)
		var till: Dictionary = sim.world.containers["till:grocery"]
		var grocer: String = till["owners"][0]
		var thief: String = _apart(sim, grocer)[0]
		var r = sim.residents[thief]
		r.traits["honesty"] = 1.0
		r.traits["empathy"] = 1.0
		r.traits["caution"] = 0.0
		_move(sim, thief, "grocery", sim.t + 10)
		var ev := _steal(sim, thief, "till:grocery", sim.t + 46)
		if ev.is_empty():
			continue
		_move(sim, thief, r.home, sim.t + 70)
		Crime.hide_loot(sim, r, sim.t + 115)
		var morning := SimClock.at(2, 8, 50)
		_move(sim, grocer, "grocery", morning - 40)
		sim.count_container(till, grocer, morning)
		var loss: Array = sim.memory[grocer].of_kind(["loss"])
		var sus: Dictionary = sim.add_belief(grocer, Memory.claim("suspect", {"subject": thief, "location": "grocery",
				"start": 0, "end": morning, "detail": loss[0]["claim"]["detail"], "obj": "till:grocery"}), "inferred", 0.8,
				SimClock.at(2, 12), {"premises": [loss[0]["id"]]})
		var at := SimClock.at(2, 14, 46)
		_move(sim, thief, "grocery", at - 30)
		var resent: float = r.r(grocer)["resentment"]
		var stash_cash: int = sim.stash(r)["cash"]
		var wallet: int = sim.residents[grocer].cash
		Actions.confront(sim, sim.residents[grocer], thief, Decisions.plan("confront", "grocery", thief, "suspicion", 50.0,
				{"ref": sus["id"]}), at)
		t.check(r.r(grocer)["resentment"] < resent + 0.2 - 1e-9, "the guilty don't resent a true accusation as the innocent do")
		var confessed := _events(sim, "confession")
		var inc: Dictionary = Incidents.incident_for(sim, ev["id"])
		if confessed.is_empty():
			denials += 1
			t.eq([sim.stash(r)["cash"], inc["reported_openly"]], [stash_cash, false], "a denial changes nothing")
			continue
		confessions += 1
		t.eq(confessed[0]["causes"][-1], ev["id"], "they confess to the theft itself")
		t.eq([sim.stash(r)["cash"], sim.residents[grocer].cash], [0, wallet + stash_cash], "and hand back what is left")
		t.check(inc["reported_openly"], "the incident is out in the open")
		t.eq(sim.memory[grocer].of_kind(["confession"]).size(), 1, "the grocer heard it from them")
		t.eq(_rules(sim), [], "every crime and knowledge rule held")
	t.check(confessions > 0, "an honest, soft-hearted culprit often owns up (%d of %d)" % [confessions,
			confessions + denials])
	t.end()


func _concealment(t) -> void:
	t.begin("a thief keeps quiet about themselves, and never hunts the culprit of their own theft")
	var sim = _fresh()
	var grocer: String = sim.world.containers["till:grocery"]["owners"][0]
	var others := _apart(sim, grocer)
	var thief: String = others[0]
	var listener: String = others[1]
	var someone := ""  # seen near the till: from another household than the listener's (nobody suspects their own)
	for x in others:
		if x != thief and x != listener and sim.residents[x].household != sim.residents[listener].household:
			someone = x
			break
	var r = sim.residents[thief]
	var now := SimClock.at(2, 12)
	sim.add_belief(thief, Memory.claim("debt", {"subject": thief, "other": grocer, "amount": 30, "start": now - 120,
			"detail": "credit"}), "self", 1.0, now - 120, {"event": null})
	var told: Array = Gossip.pick_gossip(sim, r, sim.residents[listener], now)
	t.eq(told.size(), 1, "before, they would mention their own debt")
	_move(sim, thief, "grocery", SimClock.at(1, 23, 10))
	var ev := _steal(sim, thief, "till:grocery", SimClock.at(1, 23, 46))
	_move(sim, thief, r.home, SimClock.at(2, 0, 10))
	Crime.hide_loot(sim, r, SimClock.at(2, 0, 55))
	t.eq(Gossip.pick_gossip(sim, r, sim.residents[listener], now), [], "now they keep quiet about themselves and the loot")
	# the thief, like anyone, hears the till was found short and recalls seeing someone near it
	var loss := Memory.claim("loss", {"location": "grocery", "start": SimClock.at(1, 18), "end": SimClock.at(2, 8, 50),
			"amount": 40, "obj": "till:grocery", "detail": "crowns missing from the grocery till"})
	var near := Memory.claim("presence", {"subject": someone, "location": "grocery", "start": SimClock.at(1, 22),
			"end": SimClock.at(1, 22, 30)})
	var hard := Memory.claim("hardship", {"subject": someone, "start": SimClock.at(1, 9)})
	for holder in [thief, listener]:
		sim.add_belief(holder, loss, "told", 0.8, SimClock.at(2, 10), {"event": null, "told_by": grocer})
		sim.add_belief(holder, near, "saw", 0.9, SimClock.at(1, 22), {"event": null})
		sim.add_belief(holder, hard, "told", 0.6, SimClock.at(1, 12), {"event": null, "told_by": grocer})
		Gossip.infer_suspicions(sim, holder, now)
	t.check(not ev.is_empty(), "the thief did steal from that till that night")
	t.eq(sim.memory[thief].of_kind(["suspect"]), [], "so they don't go looking for whoever did it")
	t.eq(sim.memory[listener].of_kind(["suspect"]).size(), 1, "someone with the same knowledge, and nothing to hide, does")
	t.end()


func _whole_months(t) -> void:
	t.begin("whole months with crime on: thefts happen, are found or not, and every rule holds")
	var thefts := 0
	var found := 0
	var suspicions := 0
	for profile in ["scarcity", "crisis", "tension"]:
		var sim = Simulation.new({"seed": 4, "days": 30, "profile": profile, "crime": true}).run()
		var problems: Array = SimCheck.problems(sim)
		t.check(problems.is_empty(), "%s: %d problems, first: %s" % [profile, problems.size(), problems.slice(0, 3)])
		for inc in sim.incidents:
			if inc["family"] == "theft":
				thefts += 1
				if inc["discovered_at"] != null:
					found += 1
		suspicions += int(sim.stats.get("suspicions", 0))
	print("  whole months with crime on: %d thefts, %d discovered, %d suspicions" % [thefts, found, suspicions])
	t.check(thefts > 0, "somebody steals in three months of hard times")
	t.check(suspicions > 0, "and losses make people suspect one another")
	t.end()
