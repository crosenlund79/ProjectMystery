## The native town simulation (scripts/sim/): reproducible from its seed, every rule of the world holds, and
## its behaviour matches the Python reference (tests/sim_reference.json with the crime switch off,
## tests/sim_reference_theft.json with crime on and violence off, tests/sim_reference_crime.json with the whole
## crime layer; all written by tools/sim_reference.py).
extends RefCounted

const Simulation = preload("res://scripts/sim/simulation.gd")
const SimCheck = preload("res://scripts/sim/sim_check.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")

const REFERENCE := "res://tests/sim_reference.json"
const THEFT_REFERENCE := "res://tests/sim_reference_theft.json"
const CRIME_REFERENCE := "res://tests/sim_reference_crime.json"
const GOLDEN := "res://tests/sim_golden.json"
const PROFILES := ["normal", "scarcity", "crisis", "tension"]
const SEEDS := [1, 2, 3]
## Thefts are rare (a few a month), so the crime-on comparison uses more runs.
const CRIME_SEEDS := [1, 2, 3, 4, 5]
const DAYS := 30
## Everyday routine and how much people see and pass on must match Python closely; the other statistics are
## reported and listed as differences.
const CORE := ["asleep", "share.home", "share.work", "per_resident_day.meal", "per_resident_day.move",
		"per_resident_day.wage", "per_resident_day.purchase", "needs.energy", "needs.hunger", "memory.belief_saw",
		"memory.belief_told", "memory.gossip_chats", "memory.gossip_transfers"]
## The runs whose event-log digests are pinned in tests/sim_golden.json (also checked on Linux by run_sim.gd).
## With memory off they are Pilot 1's histories, unchanged since Pilot 1; with memory on, Pilot 2's (unchanged
## by Pilot 3A, whose crime switch is off by default); with crime on and violence off, Pilot 3A's (unchanged by
## Pilot 3B); with the whole crime layer, Pilot 3B's. The crime runs are a month long, so that crimes happen in them.
## The grocery deadlock fix changed all twelve (shop workers buy during their shifts from the first week); under
## Python's shop rule ("shop_self_service": false) each is reproduced as it was pinned before the fix.
const GOLDEN_RUNS := [
	{"seed": 7, "days": 14, "profile": "normal", "memory": false},
	{"seed": 21, "days": 14, "profile": "tension", "memory": false},
	{"seed": 5, "days": 14, "profile": "crisis", "residents": 12, "memory": false},
	{"seed": 7, "days": 14, "profile": "normal", "memory": true},
	{"seed": 21, "days": 14, "profile": "tension", "memory": true},
	{"seed": 5, "days": 14, "profile": "crisis", "residents": 12, "memory": true},
	{"seed": 21, "days": 30, "profile": "tension", "crime": true, "violence": false},
	{"seed": 7, "days": 30, "profile": "scarcity", "crime": true, "violence": false},
	{"seed": 5, "days": 30, "profile": "crisis", "residents": 12, "crime": true, "violence": false},
	{"seed": 1, "days": 30, "profile": "tension", "crime": true},
	{"seed": 3, "days": 30, "profile": "tension", "crime": true},
	{"seed": 1, "days": 30, "profile": "crisis", "crime": true},
	# With the grocery fix, the three months above hold only a fall between them; these two keep a fight, collisions
	# (driven on from) and a quiet repair among the pinned histories with the fix.
	{"seed": 2, "days": 30, "profile": "tension", "crime": true},
	{"seed": 4, "days": 30, "profile": "tension", "crime": true},
	# The same twelve under Python's shop rule (without the grocery deadlock fix): the histories pinned before it,
	# unchanged. That is the separate check that the fix changes nothing else.
	{"seed": 7, "days": 14, "profile": "normal", "memory": false, "shop_self_service": false},
	{"seed": 21, "days": 14, "profile": "tension", "memory": false, "shop_self_service": false},
	{"seed": 5, "days": 14, "profile": "crisis", "residents": 12, "memory": false, "shop_self_service": false},
	{"seed": 7, "days": 14, "profile": "normal", "memory": true, "shop_self_service": false},
	{"seed": 21, "days": 14, "profile": "tension", "memory": true, "shop_self_service": false},
	{"seed": 5, "days": 14, "profile": "crisis", "residents": 12, "memory": true, "shop_self_service": false},
	{"seed": 21, "days": 30, "profile": "tension", "crime": true, "violence": false, "shop_self_service": false},
	{"seed": 7, "days": 30, "profile": "scarcity", "crime": true, "violence": false, "shop_self_service": false},
	{"seed": 5, "days": 30, "profile": "crisis", "residents": 12, "crime": true, "violence": false,
			"shop_self_service": false},
	{"seed": 1, "days": 30, "profile": "tension", "crime": true, "shop_self_service": false},
	{"seed": 3, "days": 30, "profile": "tension", "crime": true, "shop_self_service": false},
	{"seed": 1, "days": 30, "profile": "crisis", "crime": true, "shop_self_service": false},
]
const SCRIPTS := ["res://scripts/sim/sim_rng.gd", "res://scripts/sim/sim_clock.gd", "res://scripts/sim/sim_config.gd",
		"res://scripts/sim/sim_world.gd", "res://scripts/sim/sim_resident.gd", "res://scripts/sim/sim_town.gd",
		"res://scripts/sim/sim_events.gd", "res://scripts/sim/sim_decisions.gd", "res://scripts/sim/sim_actions.gd",
		"res://scripts/sim/simulation.gd", "res://scripts/sim/sim_check.gd", "res://scripts/sim/sim_memory.gd",
		"res://scripts/sim/sim_perception.gd", "res://scripts/sim/sim_gossip.gd", "res://scripts/sim/sim_incidents.gd",
		"res://scripts/sim/sim_crime.gd", "res://scripts/sim/sim_violence.gd"]


func run(t, _tree) -> void:
	t.begin("every simulation script compiles")
	var broken := []
	for path in SCRIPTS:
		var script = load(path)
		if script == null or not script.can_instantiate():
			broken.append(path)
	t.eq(broken, [], "scripts that do not compile")
	t.end()
	if not broken.is_empty():
		return  # running a half-compiled simulation would only bury the error under thousands of others
	_reproducible(t)
	var runs := _runs(SEEDS, "off")
	_integrity(t, runs)
	_daily_life(t, runs)
	_matches_python(t, runs, REFERENCE, "sim-vs-python")
	var theft_runs := _runs(CRIME_SEEDS, "theft")
	_integrity(t, theft_runs)
	_daily_life(t, theft_runs)
	_matches_python(t, theft_runs, THEFT_REFERENCE, "theft-vs-python")
	_theft_rate(t, theft_runs)
	var crime_runs := _runs(CRIME_SEEDS, "crime")
	_integrity(t, crime_runs)
	_daily_life(t, crime_runs)
	_matches_python(t, crime_runs, CRIME_REFERENCE, "crime-vs-python")
	_violence_rate(t, crime_runs)
	_golden(t)


func _reproducible(t) -> void:
	t.begin("the same seed and settings give the same history; others give another")
	var cfg := {"seed": 11, "days": 7, "profile": "tension"}
	var a = Simulation.new(cfg).run()
	var b = Simulation.new(cfg).run()
	t.check(a.events.events.size() > 500, "a week should hold hundreds of events, got %d" % a.events.events.size())
	t.eq(b.events.digest(), a.events.digest(), "two runs of one seed differ")
	t.eq(JSON.stringify(b.balances()), JSON.stringify(a.balances()), "two runs end with different money")
	t.eq(JSON.stringify(b.intervals), JSON.stringify(a.intervals), "two runs put people in different places")
	t.eq(JSON.stringify(b.world.debts), JSON.stringify(a.world.debts), "two runs end with different debts")
	var c = Simulation.new(cfg)
	c.run(3 * SimClock.DAY)
	c.run()
	t.eq(c.events.digest(), a.events.digest(), "stopping after 3 days and carrying on changed the history")
	for other in [{"seed": 12, "days": 7, "profile": "tension"}, {"seed": 11, "days": 7, "profile": "normal"},
			{"seed": 11, "days": 7, "profile": "tension", "residents": 9}]:
		var d = Simulation.new(other).run()
		t.check(d.events.digest() != a.events.digest(), "%s gave the same history as %s" % [other, cfg])
	var bad = Simulation.new({"seed": 1, "profile": "carnival"}).run()
	t.check(not bad.ok and not SimCheck.problems(bad).is_empty(), "an unknown season should be refused")
	t.end()


func _runs(seeds: Array, layer: String) -> Array:
	## layer: "off" (Pilots 1 and 2), "theft" (crime on, violence off: Pilot 3A), "crime" (everything: Pilot 3B)
	var runs := []
	for profile in PROFILES:
		for seed in seeds:
			var started := Time.get_ticks_msec()
			var sim = Simulation.new({"seed": seed, "days": DAYS, "profile": profile, "crime": layer != "off",
					"violence": layer == "crime"}).run()
			var counts: Dictionary = sim.events.counts()
			var detail := ""
			if layer != "off":
				detail = "; %d thefts, %d losses found, %d ledger mistakes, %d accusations, %d confessions; %s" % [
						counts.get("theft", 0), counts.get("loss_discovered", 0), counts.get("ledger_error", 0),
						_accusations(sim), counts.get("confession", 0), _theft_detail(sim)]
			if layer != "off":
				detail += "; " + _economy(sim)
			if layer == "crime":
				detail += "; %d fights, %d falls, %d collisions (%d driven on from), %d deaths, %d treated, %d repairs, %d found hurt, %d found dead" % [
						counts.get("assault", 0), counts.get("fall", 0), counts.get("collision", 0), _fled(sim),
						counts.get("death", 0), counts.get("treated", 0), counts.get("repair", 0),
						counts.get("injury_found", 0), counts.get("body_found", 0)]
			var self_served := 0
			for ev in sim.events.events:
				if ev["kind"] == "purchase" and ev["data"].get("self_service", false):
					self_served += 1
			detail += "; %d self-service sales" % self_served
			var stall := _stall_day(sim)
			if stall > 0:
				detail += "; the grocery stalled from Day %d" % stall
			print("  simulated %s seed %d%s: %d days, %d events, %d ms%s" % [profile, seed,
					{"off": "", "theft": ", crime on, violence off", "crime": ", crime on"}[layer], DAYS,
					sim.events.events.size(), Time.get_ticks_msec() - started, detail])
			runs.append({"profile": profile, "seed": seed, "sim": sim, "crime": layer != "off", "layer": layer})
	return runs


static func _economy(sim) -> String:
	## How the town ate: mean hunger, purchases, visits to empty shelves, deliveries, and what the grocer has left.
	var counts: Dictionary = sim.events.counts()
	var units := 0
	for ev in sim.events.events:
		if ev["kind"] == "delivery":
			units += int(ev["data"]["units"])
	var grocer: String = sim.world.containers["till:grocery"]["owners"][0]
	return "hunger %.0f, %d purchases, %d empty shelves, %d deliveries (%d units), grocery till %d, grocer %d" % [
			sim.samples["hunger"] / maxf(1.0, float(sim.samples["hours"])), counts.get("purchase", 0),
			counts.get("no_stock", 0), counts.get("delivery", 0), units, sim.world.containers["till:grocery"]["cash"],
			sim.residents[grocer].cash]


@warning_ignore("integer_division")
static func _stall_day(sim) -> int:
	## The day from which the grocery made no sale to the end of the month (at least four days before the end),
	## or -1. Measured the same way in tools/sim_reference.py.
	var bought := {}
	for ev in sim.events.events:
		if ev["kind"] == "purchase":
			var d: int = SimClock.day_of(ev["time"])
			bought[d] = int(bought.get(d, 0)) + 1
	var days: int = sim.config["days"]
	for d in range(1, days - 3):
		var none := true
		for x in range(d, days + 1):
			if int(bought.get(x, 0)) > 0:
				none = false
		if none:
			return d
	return -1


static func _fled(sim) -> int:
	var n := 0
	for inc in sim.incidents:
		if inc["family"] == "collision" and inc["fled"]:
			n += 1
	return n


static func _theft_detail(sim) -> String:
	## Which containers were robbed (till, tin, stock), which thefts nobody discovered, why attempts were given up.
	var kinds := {}
	var hidden := []
	for inc in sim.incidents:
		if inc["family"] != "theft":
			continue
		var cid: String = sim.events.by_id[inc["core_event"]]["objects"][0]
		var kind: String = cid.split(":")[0]
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if inc["discovered_at"] == null:
			# when was it last opened, and what do its people carry (a tin is opened only by someone at home at
			# 7:00 with over 120 crowns to put in or under 25, or a head short of the rent)
			var c: Dictionary = sim.world.containers[cid]
			var purses := []
			if cid.begins_with("box:"):
				for m in sim.households[cid.substr(4)]:
					purses.append(sim.residents[m].cash)
			hidden.append("%s Day %d (last opened Day %d%s)" % [cid, SimClock.day_of(inc["time"]),
					SimClock.day_of(c["last_check"]), "; its people now carry %s" % str(purses) if not purses.is_empty() else ""])
	var why := {}
	for ev in sim.events.events:
		if ev["kind"] == "theft_aborted":
			why[ev["data"]["why"]] = int(why.get(ev["data"]["why"], 0)) + 1
	return "robbed %s; undiscovered %s; given up %s" % [JSON.stringify(kinds), JSON.stringify(hidden), JSON.stringify(why)]


static func _accusations(sim) -> int:
	var n := 0
	for ev in sim.events.events:
		if ev["kind"] == "argument" and ev["data"].get("reason", "") == "suspicion":
			n += 1
	return n


func _integrity(t, runs: Array) -> void:
	var layer: String = runs[0]["layer"] if not runs.is_empty() else "off"
	t.begin("money adds up, places are real, needs stay in range, the log is in time order (%d runs%s)" % [runs.size(),
			{"off": "", "theft": ", crime on, violence off: every loss explained, every trace and incident with its events",
			"crime": ", whole crime layer: every injury and death with its cause, every repair after damage, every vehicle where it was driven"}[layer]])
	for rn in runs:
		var found: Array = SimCheck.problems(rn["sim"])
		t.check(found.is_empty(), "%s seed %d (%s): %d problems, first: %s" % [rn["profile"], rn["seed"], layer,
				found.size(), found.slice(0, 3)])
	t.end()


@warning_ignore("integer_division")
func _daily_life(t, runs: Array) -> void:
	t.begin("people live their lives: they eat, sleep, work, shop, meet; the calendar is kept")
	for rn in runs:
		var sim = rn["sim"]
		var label: String = "%s seed %d" % [rn["profile"], rn["seed"]]
		t.eq(sim.t, DAYS * SimClock.DAY, label + ": the clock did not reach the end")
		var ate := {}
		var paid := {}
		var kinds := {}
		for ev in sim.events.events:
			kinds[ev["kind"]] = true
			if ev["kind"] in ["meal", "pub_meal"]:
				ate[ev["actors"][0]] = int(ate.get(ev["actors"][0], 0)) + 1
			if ev["kind"] == "wage":
				var who: String = ev["targets"][0] if not ev["targets"].is_empty() else ev["actors"][0]
				paid[who] = true
			if ev["kind"] in ["purchase", "mill_sales", "delivery"] and SimClock.is_rest_day(ev["time"]):
				t.check(false, "%s: %s on a Sunday (%s)" % [label, ev["kind"], SimClock.fmt(ev["time"])])
		for rid in sim.ids:
			var r = sim.residents[rid]
			if not r.alive:
				continue  # (with the whole crime layer someone may die; they neither eat nor earn afterwards)
			t.check(int(ate.get(rid, 0)) >= DAYS / 2, "%s: %s ate only %d meals in %d days" % [label, rid,
					int(ate.get(rid, 0)), DAYS])
			if r.employed and r.wage > 0:
				t.check(paid.has(rid), "%s: %s (%s) was never paid" % [label, rid, r.role])
		for k in ["move", "meal", "purchase", "drink", "wage", "chat", "deposit", "delivery", "owner_withdrawal",
				"mill_sales"]:
			t.check(kinds.has(k), "%s: nobody did %s in %d days" % [label, k, DAYS])
		t.check(kinds.has("rent_paid") or kinds.has("rent_missed"), "%s: no rent was ever due" % label)
	t.end()


static func _tolerance(key: String, mean: float, sd: float) -> float:
	var least := 0.03
	if key.begins_with("per_resident_day."):
		least = 0.05
	elif key.begins_with("share.") or key == "asleep":
		least = 0.04
	elif key.begins_with("needs."):
		least = 5.0
	elif key == "money.open_debts":
		least = 1.5
	elif key.begins_with("memory.knowers_"):
		least = 0.75
	elif key == "memory.loan_acceptance":
		least = 0.1
	elif key.begins_with("memory."):
		least = 0.05
	elif key.ends_with("_share"):
		least = 0.3
	elif key == "crime.cash_per_theft":
		least = 100.0
	elif key.begins_with("crime."):
		least = 0.01
	elif key.begins_with("money."):
		least = 25.0
	return maxf(maxf(0.25 * absf(mean), 2.5 * sd), least)


func _matches_python(t, runs: Array, reference: String, label: String) -> void:
	## Godot's grocery never stalls (the deadlock fix, tests/test_grocery.gd): that is checked here for every run.
	## Python's can (a stalled month, see _stall_day, is an absorbing state that dominates a season's mean), so
	## Godot is compared with Python's months in which the grocery kept trading to the end, and Python's stall
	## count is reported.
	t.begin("behaviour matches the Python simulation (%s; Python's months in which the grocery kept trading)" % {
			REFERENCE: "crime layer off on both sides",
			THEFT_REFERENCE: "stealing on, violence and accidents off on both sides",
			CRIME_REFERENCE: "the whole crime layer on both sides"}[reference])
	var text := FileAccess.get_file_as_string(reference)
	var ref = JSON.parse_string(text)
	t.check(ref is Dictionary and ref.has("profiles"), "no reference statistics in " + reference)
	if not (ref is Dictionary and ref.has("profiles")):
		t.end()
		return
	var differences := 0
	for profile in PROFILES:
		var sums := {}
		var counts := {}
		var stalled := 0
		var months := 0
		for rn in runs:
			if rn["profile"] != profile:
				continue
			months += 1
			var stall := _stall_day(rn["sim"])
			t.check(stall < 0, "%s %s seed %d: the grocery stalled from Day %d" % [label, profile, rn["seed"], stall])
			if stall > 0:
				stalled += 1
			var flat := SimCheck.flatten(SimCheck.stats(rn["sim"]))
			for k in flat:
				if flat[k] < 0:
					continue  # a value this run cannot have (no arguments, nobody asked for a loan)
				sums[k] = float(sums.get(k, 0.0)) + flat[k]
				counts[k] = int(counts.get(k, 0)) + 1
		var py: Dictionary = ref["profiles"][profile]
		print("  %s %-9s the grocery stalled in %d of %d months (python: %d of %d, left out of the comparison)" % [
				label, profile, stalled, months, int(py.get("stalled_months", 0)), Array(ref["seeds"]).size()])
		var mean_key := "mean_trading"
		var sd_key := "sd_trading"
		var keys: Array = py[mean_key].keys()
		keys.sort()
		for k in keys:
			var theirs: float = py[mean_key][k]
			if theirs < 0 or not counts.has(k):
				print("  %s %-9s %-34s (no runs where it is defined)" % [label, profile, k])
				continue
			var mine: float = float(sums[k]) / counts[k]
			var tol := _tolerance(k, theirs, py[sd_key][k])
			var close := absf(mine - theirs) <= tol
			var core: bool = k in CORE
			print("  %s %-9s %-34s godot %9.4f  python %9.4f  (allowed +/- %.4f)  %s" % [label, profile, k, mine,
					theirs, tol, "ok" if close else ("DIFFERS (core)" if core else "differs")])
			if core:
				t.check(close, "%s %s: godot %.3f, python %.3f" % [profile, k, mine, theirs])
			elif not close:
				differences += 1
	print("  %s: %d non-core statistics outside tolerance" % [label, differences])
	t.end()


func _theft_rate(t, runs: Array) -> void:
	## Thefts are too rare for a season-by-season test (a few a month), so across all seasons together: Godot's
	## thieves must steal about as often as Python's, within a factor of two either way.
	t.begin("thieves steal about as often as in Python (all seasons together, violence off)")
	var ref = JSON.parse_string(FileAccess.get_file_as_string(THEFT_REFERENCE))
	var theirs := 0.0
	for profile in PROFILES:
		theirs += float(ref["profiles"][profile]["mean"]["crime.theft"]) / PROFILES.size()
	var thefts := 0
	var resident_days := 0.0
	for rn in runs:
		thefts += int(rn["sim"].events.counts().get("theft", 0))
		resident_days += rn["sim"].ids.size() * DAYS
	var mine := thefts / resident_days
	print("  theft-vs-python thefts per resident-day, all seasons: godot %.4f (%d thefts)  python %.4f" % [mine, thefts,
			theirs])
	t.check(mine >= theirs * 0.5 and mine <= theirs * 2.0, "godot %.4f thefts per resident-day, python %.4f" % [mine,
			theirs])
	t.end()


func _violence_rate(t, runs: Array) -> void:
	## Fights, falls and collisions are rare in Python too (16 in its 40 months, and no deaths), far too rare to
	## compare season by season. All seasons together, Godot's counts are printed against Python's, and its 20
	## months must have some.
	t.begin("fights, falls and collisions happen, about as rarely as in Python (all seasons together)")
	var ref = JSON.parse_string(FileAccess.get_file_as_string(CRIME_REFERENCE))
	var kinds := ["assault", "fall", "collision", "death", "treated", "repair", "injury_found", "body_found"]
	var resident_days := 0.0
	var mine := {}
	for rn in runs:
		resident_days += rn["sim"].ids.size() * DAYS
		var counts: Dictionary = rn["sim"].events.counts()
		for k in kinds:
			mine[k] = int(mine.get(k, 0)) + int(counts.get(k, 0))
	var line := PackedStringArray()
	var harm := 0
	for k in kinds:
		var theirs := 0.0
		for profile in PROFILES:
			theirs += float(ref["profiles"][profile]["mean"]["crime." + k]) / PROFILES.size()
		line.append("%s %d (%.4f a resident-day; python %.4f)" % [k, mine[k], mine[k] / resident_days, theirs])
		if k in ["assault", "fall", "collision"]:
			harm += mine[k]
	print("  crime-vs-python violence, all seasons: " + ", ".join(line))
	t.check(harm > 0, "no fights, falls or collisions at all in %d months" % runs.size())
	t.end()


func _golden(t) -> void:
	t.begin("pinned histories: the same event log on every machine")
	var digests := {}
	for cfg in GOLDEN_RUNS:
		var sim = Simulation.new(cfg).run()
		digests[golden_key(cfg)] = sim.events.digest()
		if cfg.get("crime", false):
			var counts: Dictionary = sim.events.counts()
			print("  GOLDEN %s holds %d thefts, %d losses found, %d ledger mistakes, %d fights, %d falls, %d collisions, %d deaths, %d traces" % [
					golden_key(cfg), counts.get("theft", 0), counts.get("loss_discovered", 0), counts.get("ledger_error", 0),
					counts.get("assault", 0), counts.get("fall", 0), counts.get("collision", 0), counts.get("death", 0),
					sim.world.evidence.size()])
	print("  GOLDEN %s" % JSON.stringify(digests, "", true))
	if FileAccess.file_exists(GOLDEN):
		var pinned = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
		for k in digests:
			if pinned.has(k):
				t.eq(digests[k], pinned[k], "history for %s differs from the pinned one" % k)
			else:
				print("  GOLDEN not pinned yet: %s" % k)
	t.end()


static func golden_key(cfg: Dictionary) -> String:
	var crime := ""
	if cfg.get("crime", false):
		crime = ", crime on" if cfg.get("violence", true) else ", crime on, violence off"
	return "seed %d, %s, %d days, %d residents, memory %s%s%s" % [int(cfg["seed"]), cfg["profile"], int(cfg["days"]),
			int(cfg.get("residents", 10)), "on" if cfg.get("memory", true) else "off", crime,
			"" if cfg.get("shop_self_service", true) else ", Python's shop rule"]
