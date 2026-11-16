## Headless demonstration of the native town simulation (no Python, no rendering, no network):
##   godot --headless --path godot -s res://tests/run_sim.gd -- --seed=7 --days=14 --profile=normal
##       [--residents=10] [--out=<folder>] [--golden]
## Prints the town, its people, the first day hour by hour, a line per day, the end state, the integrity
## checks and the event-log digest; --out writes the whole history as JSON; --golden checks the pinned
## digests in tests/sim_golden.json (the same check the Windows tests make). Exit code 0 only if every check
## passed.
extends SceneTree

const Simulation = preload("res://scripts/sim/simulation.gd")
const SimCheck = preload("res://scripts/sim/sim_check.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")
const TestSim = preload("res://tests/test_sim.gd")

const DAY := 1440


func _initialize() -> void:
	var cfg := {"seed": 7, "days": 14, "profile": "normal", "residents": 10}
	var out := ""
	var golden := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			cfg["seed"] = int(a.substr(7))
		elif a.begins_with("--days="):
			cfg["days"] = int(a.substr(7))
		elif a.begins_with("--profile="):
			cfg["profile"] = a.substr(10)
		elif a.begins_with("--residents="):
			cfg["residents"] = int(a.substr(12))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--golden":
			golden = true
	var started := Time.get_ticks_msec()
	var sim = Simulation.new(cfg)
	if not sim.ok:
		printerr(sim.errors)
		quit(1)
		return
	_town(sim)
	sim.run(DAY)
	_first_day(sim)
	sim.run()
	var ms := Time.get_ticks_msec() - started
	_days(sim)
	_end_state(sim)
	var problems: Array = SimCheck.problems(sim)
	print("\nIntegrity: %s" % ("all checks passed (money, places, people, debts, event order)" if problems.is_empty()
			else "%d PROBLEMS" % problems.size()))
	for p in problems.slice(0, 20):
		print("  - " + str(p))
	print("Event log: %d events, SHA-256 %s" % [sim.events.events.size(), sim.events.digest()])
	print("Simulated %d days in %d ms on %s (%s)." % [cfg["days"], ms, OS.get_name(), Engine.get_version_info()["string"]])
	if out != "":
		_export(sim, out)
	var ok := problems.is_empty()
	if golden:
		ok = _check_golden() and ok
	quit(0 if ok else 1)


func _town(sim) -> void:
	var p: Dictionary = sim.profile
	print("== Project Mystery: native town simulation (Godot, no Python) ==")
	print("Seed %d, %s season (%s), %d residents, %d days" % [sim.config["seed"], p["name"], p["description"],
			sim.ids.size(), sim.config["days"]])
	print("Town: %s.  Pub: %s." % [sim.world.town_name, sim.world.pub_name])
	print("\nResidents:")
	for rid in sim.ids:
		var r = sim.residents[rid]
		var t: Dictionary = r.traits
		print("  %-16s %-15s %-12s %3d cr  honesty %.2f  sociability %.2f  temperance %.2f  diligence %.2f" % [
				r.full_name(), r.occupation, r.age_group, r.cash, t["honesty"], t["sociability"], t["temperance"],
				t["diligence"]])
	for g in sim.meta["grudges"]:
		print("  Old grudge: %s and %s (%s)" % [sim.n(g["a"]), sim.n(g["b"]), g["reason"]])
	for d in sim.world.debts:
		print("  Owed: %s owes %s %d crowns, due %s" % [sim.n(d["debtor"]), sim.n(d["creditor"]), d["amount"],
				SimClock.fmt(d["due"])])


func _first_day(sim) -> void:
	print("\n%s, hour by hour (moves left out):" % SimClock.date(0))
	for ev in sim.events.events:
		if ev["kind"] == "move" or ev["time"] >= DAY:
			continue
		print("  %s  %-14s %s" % [SimClock.fmt_clock(ev["time"]), ev["kind"], ev["summary"]])


func _days(sim) -> void:
	print("\nThe calendar, a line per day:")
	var per_day := {}
	for ev in sim.events.events:
		var d := SimClock.day_of(ev["time"])
		if not per_day.has(d):
			per_day[d] = {}
		per_day[d][ev["kind"]] = int(per_day[d].get(ev["kind"], 0)) + 1
	for d in range(1, int(sim.config["days"]) + 1):
		var c: Dictionary = per_day.get(d, {})
		var total := 0
		for k in c:
			total += c[k]
		var notable := []
		for k in ["loan", "loan_refused", "repay", "credit", "credit_refused", "rent_missed", "argument", "reconcile",
				"help", "laid_off", "wage_unpaid", "no_stock", "debt_overdue"]:
			if c.has(k):
				notable.append("%d %s" % [c[k], k.replace("_", " ")])
		print("  %-20s %4d events: %3d meals, %3d drinks, %2d wages, %2d purchases%s" % [
				SimClock.date((d - 1) * DAY), total, int(c.get("meal", 0)) + int(c.get("pub_meal", 0)),
				int(c.get("drink", 0)), int(c.get("wage", 0)), int(c.get("purchase", 0)),
				("; " + ", ".join(notable)) if not notable.is_empty() else ""])


func _end_state(sim) -> void:
	print("\nAt the end (%s):" % SimClock.fmt(sim.t))
	print("  %-16s %6s %7s %7s %7s %7s  %s" % ["", "cash", "hunger", "energy", "social", "stress", "where"])
	for rid in sim.ids:
		var r = sim.residents[rid]
		var owes := 0
		for d in sim.open_debts(rid):
			owes += d["amount"]
		print("  %-16s %6d %7.0f %7.0f %7.0f %7.0f  %s%s%s" % [r.full_name(), r.cash, r.hunger, r.energy, r.social,
				r.stress, sim.world.name_of(sim.loc(rid)), " (asleep)" if r.asleep else "",
				("; owes %d" % owes) if owes > 0 else ""])
	var bad := []
	for a in sim.ids:
		for b in sim.ids:
			if a != b and sim.residents[a].r(b)["resentment"] >= 0.5:
				bad.append("%s resents %s (%.2f)" % [sim.n(a), sim.n(b), sim.residents[a].r(b)["resentment"]])
	if not bad.is_empty():
		print("  Bad blood: " + "; ".join(bad))
	var st: Dictionary = SimCheck.stats(sim)
	print("  Where people were, share of hours: %s" % JSON.stringify(st["share"]).replace("\"", ""))
	print("  Deferred to the crime layer: %d violent escalations" % int(sim.stats.get("escalations_deferred", 0)))


func _export(sim, folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var people := []
	for rid in sim.ids:
		people.append(sim.residents[rid].to_dict())
	var data := {"config": sim.config, "profile": sim.profile, "town": sim.world.to_dict(), "residents": people,
			"events": sim.events.events, "debts": sim.world.debts, "records": sim.world.records,
			"digest": sim.events.digest(), "statistics": SimCheck.stats(sim)}
	var path := folder.path_join("simulation-seed%d-%s-%dd.json" % [sim.config["seed"], sim.config["profile"],
			sim.config["days"]])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, " ", true))
	f.close()
	print("Wrote %s" % path)


func _check_golden() -> bool:
	if not FileAccess.file_exists(TestSim.GOLDEN):
		print("Golden digests: none pinned yet")
		return true
	var pinned = JSON.parse_string(FileAccess.get_file_as_string(TestSim.GOLDEN))
	var ok := true
	for cfg in TestSim.GOLDEN_RUNS:
		var key: String = TestSim.golden_key(cfg)
		var digest: String = Simulation.new(cfg).run().events.digest()
		var same: bool = digest == pinned.get(key, "")
		ok = ok and same
		print("Golden %s: %s" % [key, "same as pinned" if same else "DIFFERS (%s)" % digest])
	return ok
