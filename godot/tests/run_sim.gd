## Headless demonstration of the native town simulation (no Python, no rendering, no network):
##   godot --headless --path godot -s res://tests/run_sim.gd -- --seed=7 --days=14 --profile=normal
##       [--residents=10] [--memory=off] [--crime] [--violence=off] [--out=<folder>] [--golden]
## Prints the town, its people, the first day hour by hour, a line per day, the end state, the integrity
## checks and the event-log digest; --out writes the whole history as JSON; --golden checks the pinned
## digests in tests/sim_golden.json (the same check the Windows tests make); --crime turns on the whole crime layer
## (theft and financial incidents, Pilot 3A; fights, falls, collisions and what follows, Pilot 3B; --violence=off
## leaves out the latter) and prints what really happened against what the town came to believe. Exit code 0 only
## if every check passed.
extends SceneTree

const Simulation = preload("res://scripts/sim/simulation.gd")
const SimCheck = preload("res://scripts/sim/sim_check.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")
const TestSim = preload("res://tests/test_sim.gd")
const Memory = preload("res://scripts/sim/sim_memory.gd")

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
		elif a == "--memory=off":
			cfg["memory"] = false
		elif a == "--crime":
			cfg["crime"] = true
		elif a == "--violence=off":
			cfg["violence"] = false
	for path in TestSim.SCRIPTS:
		var script = load(path)
		if script == null or not script.can_instantiate():
			printerr("SCRIPT ERROR: %s does not compile" % path)
			quit(1)
			return
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
	if sim.memory_on:
		_knowledge(sim)
	if sim.crime_on:
		_crime(sim)
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


func _when(t: int) -> String:
	return "Day %d %s" % [SimClock.day_of(t), SimClock.fmt_clock(t)]


func _knowledge(sim) -> void:
	## What the town believes, kept apart from what happened: how news travelled, and where people got it wrong.
	var by_source := {}
	var by_error := {}
	for bid in sim.beliefs:
		var b: Dictionary = sim.beliefs[bid]
		by_source[b["source"]] = int(by_source.get(b["source"], 0)) + 1
		if b["error"]:
			by_error[b["error"]] = int(by_error.get(b["error"], 0)) + 1
	print("\nWhat the town believes (%d beliefs): %s" % [sim.beliefs.size(), JSON.stringify(by_source).replace("\"", "")])
	print("  Got wrong: %s.  Passed on in chats: %d.  Suspicions formed: %d." % [
			JSON.stringify(by_error).replace("\"", ""), int(sim.stats.get("gossip_transfers", 0)),
			int(sim.stats.get("suspicions", 0))])
	# the piece of news passed on in the most chats (whatever it was: an argument, a refusal, a debt, missed
	# rent ...), and how each person who knows of it came to know
	var knowers := {}
	var retold := {}
	for bid in sim.beliefs:
		var b: Dictionary = sim.beliefs[bid]
		var root: Dictionary = SimCheck._root(sim, b)
		if not root["event"]:
			continue
		var key: String = str(root["event"])
		if not knowers.has(key):
			knowers[key] = {}
		if not knowers[key].has(b["holder"]):
			knowers[key][b["holder"]] = b  # the first way each holder heard of it
		if b["source"] == "told" and b["acquired"] > 0:  # told in a chat, not the town's history told at the start
			retold[key] = int(retold.get(key, 0)) + 1
	var best_id := ""
	for k in retold:
		if best_id == "" or retold[k] > retold[best_id]:
			best_id = str(k)
	if best_id == "":
		print("\nNo news was passed on in a chat in this run.")
	else:
		var best: Dictionary = sim.events.by_id[best_id]
		var at: String = "before Day 1" if best["location"] == "-" else "%s, %s" % [_when(best["time"]),
				sim.world.name_of(best["location"])]
		print("\nHow word got round: %s (%s; passed on in %d chats)" % [best["summary"], at, retold[best_id]])
		for holder in knowers[best_id]:
			var b: Dictionary = knowers[best_id][holder]
			var chain := []
			var x: Dictionary = b
			while x["source"] == "told" and x["via"] != null:
				chain.append("told by %s (%s)" % [sim.n(x["told_by"]), _when(x["acquired"])])
				x = sim.beliefs[x["via"]]
			var how: String = {"self": "was in it", "saw": "saw it", "heard": "heard it", "inferred": "worked it out"}.get(
					x["source"], x["source"])
			chain.append("%s %s" % [sim.n(x["holder"]), how])
			print("  %-8s %s" % [sim.n(b["holder"]) + ":", ", ".join(chain) if chain.size() > 1 else chain[0]])
	# a misidentification, set against the truth
	for bid in sim.beliefs:
		var b: Dictionary = sim.beliefs[bid]
		if b["error"] == "misidentified" and b["source"] == "saw" and b["event"] and b["claim"]["subject"]:
			var ev: Dictionary = sim.events.by_id[b["event"]]
			var truly: String = ev["actors"][0]
			print("\nA mistake: at %s, %s saw someone at %s and took them for %s. It was %s." % [_when(b["acquired"]),
					sim.n(b["holder"]), sim.world.name_of(b["claim"]["location"]), sim.n(b["claim"]["subject"]), sim.n(truly)])
			break
	# a rumour whose time drifted in the telling, set against the truth
	for bid in sim.beliefs:
		var b: Dictionary = sim.beliefs[bid]
		if b["error"] == "time_distorted" and b["source"] == "told" and b["claim"]["start"] != null:
			var root: Dictionary = SimCheck._root(sim, b)
			if root["event"] and root["claim"]["start"] != null and root["claim"]["start"] != b["claim"]["start"]:
				print("A rumour that drifted: %s told %s it happened at %s (%s); it was %s." % [sim.n(b["told_by"]),
						sim.n(b["holder"]), _when(b["claim"]["start"]), str(b["claim"]["kind"]).replace("_", " "),
						_when(root["claim"]["start"])])
				break
	# forgetting: what one resident still recalls of the first day
	var rid: String = sim.ids[0]
	var formed := 0
	var kept := 0
	for b in sim.memory[rid].beliefs:
		if b["acquired"] < DAY and b["acquired"] > 0:
			formed += 1
			if Memory.recall(b, sim.t, [])[0]:
				kept += 1
	print("Forgetting: of %d things %s noticed on Day 1, %d are still remembered on Day %d." % [formed, sim.n(rid), kept,
			SimClock.day_of(sim.t)])


func _crime(sim) -> void:
	## The truth about every incident, which no resident sees whole, set against what the town came to believe:
	## who found it, who suspected whom (rightly or not), and what traces were left.
	print("\nIncidents (the truth: developer-only):")
	if sim.incidents.is_empty():
		print("  none")
	for inc in sim.incidents:
		var core: Dictionary = sim.events.by_id[inc["core_event"]]
		var found := "never discovered"
		if inc["discovered_at"] != null:
			found = "discovered %s by %s" % [_when(inc["discovered_at"]), sim.n(inc["discovered_by"])]
		print("  %s %s, %s: %s %s%s" % [inc["id"], inc["family"], _when(core["time"]), core["summary"], found,
				"; owned up to" if inc["reported_openly"] else ""])
		var knew := {}
		var guessed := {}  # "holder -> subject" -> right or wrong (one line each, however often re-inferred)
		var linked: Array = [inc["core_event"], inc["discovery_event"]] + inc["related_events"]
		for bid in sim.beliefs:
			var b: Dictionary = sim.beliefs[bid]
			var c: Dictionary = b["claim"]
			var root: Dictionary = SimCheck._root(sim, b)
			if root["event"] != null and root["event"] in linked and c["kind"] != "suspect":
				knew[b["holder"]] = true
			if c["kind"] == "suspect" and b["source"] == "inferred":
				var about: Dictionary = SimCheck.incident_at(sim, c)
				if not about.is_empty() and about["id"] == inc["id"]:
					guessed["%s suspects %s" % [sim.n(b["holder"]), sim.n(c["subject"])]] = (
							"right" if c["subject"] == inc["responsible"] else "wrong")
		if inc["discovered_at"] != null:
			var guesses := []
			for g in guessed:
				guesses.append("%s (%s)" % [g, guessed[g]])
			print("      %d people came to know of it; %s" % [knew.size(), ", ".join(guesses) if not guesses.is_empty()
					else "nobody suspected anyone"])
	var counts: Dictionary = sim.events.counts()
	print("  Accusations: %d.  Confessions: %d.  Attempts given up: %d.  Spent from hidden stashes: %d times." % [
			_accusations(sim), counts.get("confession", 0), counts.get("theft_aborted", 0), counts.get("stash_withdraw", 0)])
	var hurt := []
	for rid in sim.ids:
		var r = sim.residents[rid]
		if not r.alive:
			hurt.append("%s is dead" % r.first)
		elif r.injury > 0:
			hurt.append("%s is hurt (%s)%s%s" % [r.first, r.injury_desc, "" if r.injury_treated else ", untreated",
					", lying where they fell" if r.down else ""])
	if not hurt.is_empty():
		print("  At the end: " + "; ".join(hurt) + ".")
	if not sim.world.evidence.is_empty():
		print("\nTraces:")
	for e in sim.world.evidence:
		var noticed := []
		for rid in e["noticed_by"]:
			noticed.append(sim.n(rid))
		print("  %s %-11s %s, %s; noticed by %s%s" % [e["id"], e["kind"], sim.world.name_of(e["place"]),
				_when(e["created_at"]), ", ".join(noticed) if not noticed.is_empty() else "nobody",
				"; cleared away %s" % _when(e["removed_at"]) if e["removed_at"] >= 0 else ""])


static func _accusations(sim) -> int:
	var n := 0
	for ev in sim.events.events:
		if ev["kind"] == "argument" and ev["data"].get("reason", "") == "suspicion":
			n += 1
	return n


func _export(sim, folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var people := []
	for rid in sim.ids:
		people.append(sim.residents[rid].to_dict())
	var data := {"config": sim.config, "profile": sim.profile, "town": sim.world.to_dict(), "residents": people,
			"events": sim.events.events, "debts": sim.world.debts, "records": sim.world.records,
			"beliefs": sim.beliefs.values(), "incidents": sim.incidents, "evidence": sim.world.evidence,
			"digest": sim.events.digest(), "statistics": SimCheck.stats(sim)}
	var path := folder.path_join("simulation-seed%d-%s-%dd%s.json" % [sim.config["seed"], sim.config["profile"],
			sim.config["days"], "-crime" if sim.crime_on else ""])
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
		if not pinned.has(key):
			print("Golden %s: not pinned yet (%s)" % [key, digest])
			continue
		var same: bool = digest == pinned[key]
		ok = ok and same
		print("Golden %s: %s" % [key, "same as pinned" if same else "DIFFERS (%s)" % digest])
	return ok
