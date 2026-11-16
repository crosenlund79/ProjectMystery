## The native town simulation (scripts/sim/): reproducible from its seed, every rule of the world holds, and
## its behaviour matches the Python reference (tests/sim_reference.json, and with the crime switch on
## tests/sim_reference_theft.json, both written by tools/sim_reference.py).
extends RefCounted

const Simulation = preload("res://scripts/sim/simulation.gd")
const SimCheck = preload("res://scripts/sim/sim_check.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")

const REFERENCE := "res://tests/sim_reference.json"
const THEFT_REFERENCE := "res://tests/sim_reference_theft.json"
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
## by Pilot 3A, whose crime switch is off by default); with crime on, Pilot 3A's, a month long so that thefts
## happen in them.
const GOLDEN_RUNS := [
	{"seed": 7, "days": 14, "profile": "normal", "memory": false},
	{"seed": 21, "days": 14, "profile": "tension", "memory": false},
	{"seed": 5, "days": 14, "profile": "crisis", "residents": 12, "memory": false},
	{"seed": 7, "days": 14, "profile": "normal", "memory": true},
	{"seed": 21, "days": 14, "profile": "tension", "memory": true},
	{"seed": 5, "days": 14, "profile": "crisis", "residents": 12, "memory": true},
	{"seed": 21, "days": 30, "profile": "tension", "crime": true},
	{"seed": 7, "days": 30, "profile": "scarcity", "crime": true},
	{"seed": 5, "days": 30, "profile": "crisis", "residents": 12, "crime": true},
]
const SCRIPTS := ["res://scripts/sim/sim_rng.gd", "res://scripts/sim/sim_clock.gd", "res://scripts/sim/sim_config.gd",
		"res://scripts/sim/sim_world.gd", "res://scripts/sim/sim_resident.gd", "res://scripts/sim/sim_town.gd",
		"res://scripts/sim/sim_events.gd", "res://scripts/sim/sim_decisions.gd", "res://scripts/sim/sim_actions.gd",
		"res://scripts/sim/simulation.gd", "res://scripts/sim/sim_check.gd", "res://scripts/sim/sim_memory.gd",
		"res://scripts/sim/sim_perception.gd", "res://scripts/sim/sim_gossip.gd", "res://scripts/sim/sim_incidents.gd",
		"res://scripts/sim/sim_crime.gd"]


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
	var runs := _runs(SEEDS, false)
	_integrity(t, runs)
	_daily_life(t, runs)
	_matches_python(t, runs, REFERENCE, "sim-vs-python")
	var crime_runs := _runs(CRIME_SEEDS, true)
	_integrity(t, crime_runs)
	_daily_life(t, crime_runs)
	_matches_python(t, crime_runs, THEFT_REFERENCE, "crime-vs-python")
	_theft_rate(t, crime_runs)
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


func _runs(seeds: Array, crime: bool) -> Array:
	var runs := []
	for profile in PROFILES:
		for seed in seeds:
			var started := Time.get_ticks_msec()
			var sim = Simulation.new({"seed": seed, "days": DAYS, "profile": profile, "crime": crime}).run()
			var counts: Dictionary = sim.events.counts()
			print("  simulated %s seed %d%s: %d days, %d events, %d ms%s" % [profile, seed, ", crime on" if crime else "",
					DAYS, sim.events.events.size(), Time.get_ticks_msec() - started,
					"; %d thefts, %d losses found, %d ledger mistakes, %d accusations, %d confessions; %s" % [
					counts.get("theft", 0), counts.get("loss_discovered", 0), counts.get("ledger_error", 0),
					_accusations(sim), counts.get("confession", 0), _theft_detail(sim)] if crime else ""])
			runs.append({"profile": profile, "seed": seed, "sim": sim, "crime": crime})
	return runs


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
			hidden.append("%s Day %d" % [cid, SimClock.day_of(inc["time"])])
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
	var crime: bool = not runs.is_empty() and runs[0]["crime"]
	t.begin("money adds up, places are real, needs stay in range, the log is in time order (%d runs%s)" % [runs.size(),
			", crime on: every loss explained, every trace and incident with its events" if crime else ""])
	for rn in runs:
		var found: Array = SimCheck.problems(rn["sim"])
		t.check(found.is_empty(), "%s seed %d%s: %d problems, first: %s" % [rn["profile"], rn["seed"],
				", crime on" if crime else "", found.size(), found.slice(0, 3)])
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
	t.begin("behaviour matches the Python simulation (%s)" % ("stealing on, violence and accidents off on both sides"
			if reference == THEFT_REFERENCE else "crime layer off on both sides"))
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
		for rn in runs:
			if rn["profile"] != profile:
				continue
			var flat := SimCheck.flatten(SimCheck.stats(rn["sim"]))
			for k in flat:
				if flat[k] < 0:
					continue  # a value this run cannot have (no arguments, nobody asked for a loan)
				sums[k] = float(sums.get(k, 0.0)) + flat[k]
				counts[k] = int(counts.get(k, 0)) + 1
		var py: Dictionary = ref["profiles"][profile]
		var keys: Array = py["mean"].keys()
		keys.sort()
		for k in keys:
			var theirs: float = py["mean"][k]
			if theirs < 0 or not counts.has(k):
				print("  %s %-9s %-34s (no runs where it is defined)" % [label, profile, k])
				continue
			var mine: float = float(sums[k]) / counts[k]
			var tol := _tolerance(k, theirs, py["sd"][k])
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
	t.begin("thieves steal about as often as in Python (all seasons together)")
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
	print("  crime-vs-python thefts per resident-day, all seasons: godot %.4f (%d thefts)  python %.4f" % [mine, thefts,
			theirs])
	t.check(mine >= theirs * 0.5 and mine <= theirs * 2.0, "godot %.4f thefts per resident-day, python %.4f" % [mine,
			theirs])
	t.end()


func _golden(t) -> void:
	t.begin("pinned histories: the same event log on every machine")
	var digests := {}
	for cfg in GOLDEN_RUNS:
		var sim = Simulation.new(cfg).run()
		digests[golden_key(cfg)] = sim.events.digest()
		if cfg.get("crime", false):
			var counts: Dictionary = sim.events.counts()
			print("  GOLDEN %s holds %d thefts, %d losses found, %d ledger mistakes, %d traces" % [golden_key(cfg),
					counts.get("theft", 0), counts.get("loss_discovered", 0), counts.get("ledger_error", 0),
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
	return "seed %d, %s, %d days, %d residents, memory %s%s" % [int(cfg["seed"]), cfg["profile"], int(cfg["days"]),
			int(cfg.get("residents", 10)), "on" if cfg.get("memory", true) else "off",
			", crime on" if cfg.get("crime", false) else ""]
