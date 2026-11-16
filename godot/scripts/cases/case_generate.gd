## Native case generation (Pilot 4B): from a simulated town to playable ``.mcase`` files, with no Python anywhere.
##
##   generate(cfg, out_dir)  runs the town with its whole crime layer, freezes every case candidate at its case start
##                           (case_builder.gd, with the suitability report and hints), and judges each one (judge).
##   judge(case, out_dir)    packages the case in the existing .mcase format, reads the package back as any player's
##                           game would, and lets the truth-blind investigator (case_solver.gd) work on the player's
##                           view alone. Only then is the seal opened, to check the investigator's conclusion against
##                           the truth. A case becomes playable only if it is eligible (someone genuinely responsible
##                           for a crime: no accident, bookkeeping mistake or baseless suspicion), the investigator
##                           names the right person, the right explanation and an acceptable motive, and nothing it
##                           relied on was mistaken or a lie (other than the culprit's own). Nothing is ever added to a
##                           case to make it solvable: a case that fails is rejected, with the reason.
##   playthrough(path, root) opens a written case through the case library, plays it with the same reasoning in a
##                           player's game, saves and resumes it, submits, and reveals: what the game itself does.
##   yield_report(results)   candidates, eligible, solvable and rejected, with the reasons, and quality concerns.
extends RefCounted

const Simulation = preload("res://scripts/sim/simulation.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")
const Incidents = preload("res://scripts/sim/sim_incidents.gd")
const CaseBuilder = preload("res://scripts/cases/case_builder.gd")
const CaseExtract = preload("res://scripts/cases/case_extract.gd")
const CasePackage = preload("res://scripts/cases/case_package.gd")
const CaseSolver = preload("res://scripts/cases/case_solver.gd")
const CaseFormat = preload("res://scripts/core/case_format.gd")
const CaseLibrary = preload("res://scripts/core/case_library.gd")
const SaveStore = preload("res://scripts/core/save_store.gd")
const Investigation = preload("res://scripts/core/investigation.gd")
const Verdict = preload("res://scripts/core/verdict.gd")

## Where the player's game looks for cases besides the bundled library (CaseLibrary, "imported").
const DEFAULT_OUT := "user://cases/"
## Reporting thresholds for quality concerns (never a reason to reject a case).
const NOISY_SHARE := 0.95  # a case where at least this share of the statements has nothing to do with it
const NOISY_COUNT := 700  # or this many statements in all
const IDLE_MINUTES := 60  # an account that has someone standing in the street or the square this long


static func generate(cfg: Dictionary, out_dir := "", selected := "", all_dir := "") -> Dictionary:
	## {"sim", "results": [judge() result in incident order], "cases": {incident id: case}}. The town runs exactly as
	## it would without generation (the history is the same). Playable cases are written to out_dir; with all_dir,
	## every candidate's package is written there too, playable or not (for inspection, never for the library).
	var c := cfg.duplicate()
	c["crime"] = true
	var sim = Simulation.new(c)
	var cases := {}
	var order := []
	var results := []
	if not sim.ok:
		return {"sim": sim, "results": results, "cases": cases}
	var end: int = int(sim.config["days"]) * SimClock.DAY
	while sim.t < end:
		sim.step()
		for inc in sim.incidents:
			if inc["case_start"] == sim.t and Incidents.is_candidate(inc) and (selected == "" or inc["id"] == selected):
				cases[inc["id"]] = CaseBuilder.new(sim, inc).build()
				order.append(inc["id"])
	for iid in order:
		results.append(judge(cases[iid], out_dir, all_dir))
	return {"sim": sim, "results": results, "cases": cases}


static func judge(case_: Dictionary, out_dir := "", all_dir := "") -> Dictionary:
	var inv: Dictionary = case_["investigation"]
	var truth: Dictionary = case_["truth"]
	var inc: Dictionary = truth["incident"]
	var el: Dictionary = case_["eligibility"]
	var r := {"case_id": case_["case_id"], "incident": inc["id"], "family": inc["family"], "title": inv["hook"]["title"],
			"eligible": el["eligible"], "eligibility": el["reason"], "verdict": truth["suitability"]["verdict"],
			"accepted": false, "stage": "", "reason": "", "solver": {}, "check": {}, "quality": {}, "package_sha256": "",
			"bytes": 0, "path": "", "false_accusation": false, "suitability": _report_summary(truth["suitability"])}
	# the package, read back exactly as a player's game reads a case file
	var file_text := CasePackage.to_text(CasePackage.build(case_))
	r["package_sha256"] = file_text.sha256_text()
	r["bytes"] = file_text.length()
	if all_dir != "":
		CasePackage.write(file_text, case_["case_id"], all_dir)
	var loaded := CaseFormat.parse_text(file_text)
	if not loaded["ok"]:
		return _reject(r, "package", "the package does not validate: %s" % loaded["errors"][0])
	var pkg: Dictionary = loaded["package"]
	var leaks := CaseExtract.spoiler_problems(pkg["investigation"])
	if not leaks.is_empty():
		return _reject(r, "package", "the player's view carries the truth: %s" % leaks[0])
	var hints: Array = pkg["investigation"]["hints"]
	if hints.is_empty():
		return _reject(r, "package", "no hints")
	# the truth-blind investigator, on the player's view only
	var solver = CaseSolver.new(pkg)
	var s: Dictionary = solver.run()
	r["solver"] = {"ok": s["ok"], "reason": s.get("reason", ""), "mechanism": s.get("mechanism", ""),
			"responsible": s.get("responsible"), "motive": s.get("motive", ""), "route": s.get("route", []),
			"cites": s.get("cite_refs", []), "counts": s.get("counts", {})}
	var ans: Dictionary = truth["answer"]
	if not el["eligible"]:
		# not a case at all; the investigator is asked anyway, to show it accuses nobody where nobody is to blame
		r["false_accusation"] = s["ok"] and s.get("responsible") != ans["responsible"]
		return _reject(r, "eligibility", el["reason"])
	if not s["ok"]:
		return _reject(r, "solver", s["reason"])
	# only now is the seal opened, to check the conclusion
	var opened := CaseFormat.unseal(pkg["sealed_truth"], pkg["case_id"])
	if not opened["ok"]:
		return _reject(r, "package", "the sealed truth does not open: %s" % opened["error"])
	var t: Dictionary = opened["truth"]
	var theory := {"mechanism": s["mechanism"], "responsible": s["responsible"], "motive": s["motive"],
			"cite_refs": s["cite_refs"]}
	var cites := Verdict._cites(t, theory)
	var score := Verdict.score(t, theory, 0)
	r["check"] = {"mechanism": s["mechanism"] == t["answer"]["mechanism"],
			"responsible": s["responsible"] == t["answer"]["responsible"],
			"motive": t["answer"]["motives"].has(s["motive"]), "good": int(cites[2]), "bad": int(cites[3]),
			"score": int(score["total"])}
	if not r["check"]["responsible"]:
		r["false_accusation"] = true
		return _reject(r, "check", "misleading evidence: the investigator would name %s, who is innocent" %
				_first(inv, s["responsible"]))
	if not r["check"]["mechanism"]:
		return _reject(r, "check", "misleading evidence: the investigator would explain it as %s" % s["mechanism"])
	if not r["check"]["motive"]:
		return _reject(r, "check", "the motive cannot be told: the evidence suggests %s" % s["motive"])
	if r["check"]["bad"] > 0:
		return _reject(r, "check", "the reasoning leans on testimony that is mistaken")
	if r["check"]["good"] == 0:
		return _reject(r, "check", "nothing the reasoning rests on is evidence of the answer")
	r["accepted"] = true
	r["stage"] = "accepted"
	r["reason"] = "solvable: " + ", ".join(PackedStringArray(s["route"]))
	r["quality"] = quality(pkg, t)
	if out_dir != "":
		r["path"] = CasePackage.write(file_text, pkg["case_id"], out_dir)
	return r


static func _report_summary(report: Dictionary) -> Dictionary:
	## The sealed suitability report, in short (developer-only: it is worked out from the truth).
	var out := {}
	for k in ["verdict", "deduction", "solvable_by_evidence", "independent_channels", "responsible_channels",
			"blocked_channels", "red_herrings", "lies_by_responsible"]:
		out[k] = report[k]
	return out


static func _reject(r: Dictionary, stage: String, reason: String) -> Dictionary:
	r["stage"] = stage
	r["reason"] = reason
	return r


static func _first(inv: Dictionary, rid) -> String:
	for x in inv["residents"]:
		if x["id"] == rid:
			return x["first"]
	return str(rid)


# ================================================================ quality concerns (reported, never fixed here)
static func quality(pkg: Dictionary, truth: Dictionary) -> Dictionary:
	## How much of what people say has nothing to do with the case, and accounts that keep someone standing in the
	## street or the square for an hour or more (an alibi a careful player would doubt, whoever gives it).
	var inv: Dictionary = pkg["investigation"]
	var total := 0
	var unrelated := 0
	var connected := 0
	for rid in inv["testimony"]:
		for it in inv["testimony"][rid]["items"]:
			var v = truth["relevance"].get(it["key"])
			if v == null:
				continue  # a summary
			total += 1
			if v["verdict"] == "unrelated":
				unrelated += 1
			elif v["verdict"] == "connected":
				connected += 1
	var kinds := {}
	for p in inv["places"]:
		kinds[p["id"]] = p["kind"]
	var idle := []
	for rid in inv["testimony"]:
		for it in inv["testimony"][rid]["items"]:
			if it["source"] != "self" or not ("whereabouts" in it["topics"]) or it.get("in") != null:
				continue
			for f in it["facts"]:
				var minutes := int(f["to"]) - int(f["from"])
				if f["who"] == rid and kinds.get(f["place"], "") in ["road", "square"] and minutes >= IDLE_MINUTES:
					var a: Dictionary = truth["testimony_audit"].get(it["key"], {})
					idle.append({"speaker": rid, "place": f["place"], "minutes": minutes,
							"lie": a.get("status") == "lie", "responsible": rid == truth["answer"]["responsible"]})
	var share := float(unrelated) / maxf(1.0, float(total))
	var concerns := []
	if share >= NOISY_SHARE or total >= NOISY_COUNT:
		concerns.append("excessive irrelevant testimony (%d statements, %d%% unrelated)" % [total, roundi(share * 100)])
	var idle_people := []
	for x in idle:
		if not (x["speaker"] in idle_people):
			idle_people.append(x["speaker"])
	if not idle.is_empty():
		concerns.append("implausible alibis: %d account(s) by %d person(s) put them in the street or the square for an hour or more" % [
				idle.size(), idle_people.size()])
	return {"statements": total, "unrelated": unrelated, "connected": connected, "unrelated_share": snappedf(share, 0.001),
			"idle_alibis": idle, "concerns": concerns}


# ================================================================ a whole game
static func playthrough(path: String, user_root: String) -> Dictionary:
	## Plays a written case the way the game does: found by the case library, opened from its file, investigated with
	## the same reasoning, saved and resumed half way, concluded and revealed. The seal stays shut until the reveal.
	var out := {"ok": false, "problems": [], "score": -1, "resumed": false, "unsealed_during_play": 0,
			"listed_as": "", "model": {}}
	var dir := path.get_base_dir() + "/"
	var lib = CaseLibrary.new(user_root)
	var loaded := CaseFormat.load_file(path)
	if not loaded["ok"]:
		out["problems"].append("the file does not load: %s" % loaded["errors"][0])
		return out
	var pkg: Dictionary = loaded["package"]
	var entry: Dictionary = lib.find(pkg["case_id"])
	if dir == lib.user_cases:
		if entry.is_empty():
			out["problems"].append("the case library does not list it")
		else:
			out["listed_as"] = entry["source"]
			var again: Dictionary = lib.load_package(entry)
			if not again["ok"]:
				out["problems"].append("the case library cannot open it")
	var store = SaveStore.new(user_root)
	store.delete_save(pkg["case_id"])  # a new game of it, as the player starts one
	var before: int = Verdict.unseal_count
	var game = Investigation.new(pkg)
	var first = CaseSolver.new(pkg, game)
	first.gather()
	if not store.save(game.state):
		out["problems"].append("the investigation could not be saved")
	var resumed = Investigation.new(pkg, store.load_state(pkg["case_id"]))
	out["resumed"] = resumed.resumed
	if not resumed.resumed:
		out["problems"].append("the saved investigation was not resumed")
	if resumed.state["entries"].size() != game.state["entries"].size():
		out["problems"].append("the resumed notebook differs from the saved one")
	var second = CaseSolver.new(pkg, resumed)
	second.read_notebook()
	var d: Dictionary = second.decide()
	if not d["ok"]:
		out["problems"].append("after resuming, the investigator cannot conclude: %s" % d["reason"])
		return out
	var sub: Dictionary = resumed.submit(d["mechanism"], d["responsible"], d["motive"], d["cites"], d["summary"])
	if sub.has("error"):
		out["problems"].append("the theory was refused: %s" % sub["error"])
		return out
	out["unsealed_during_play"] = Verdict.unseal_count - before
	if out["unsealed_during_play"] != 0:
		out["problems"].append("the seal was opened before the reveal")
	var rev: Dictionary = resumed.reveal()
	if rev.get("sealed", true) or rev.get("model") == null:
		out["problems"].append("the reveal did not open: %s" % rev.get("error", ""))
		return out
	out["model"] = rev["model"]
	out["score"] = int(rev["model"]["score"]["total"])
	store.save(resumed.state)
	var after = Investigation.new(pkg, store.load_state(pkg["case_id"]))
	if not after.is_closed():
		out["problems"].append("a revealed case reopened after saving")
	out["ok"] = out["problems"].is_empty()
	return out


# ================================================================ yield
static func yield_report(results: Array, months: int) -> Dictionary:
	var out := {"months": months, "candidates": results.size(), "eligible": 0, "solvable": 0, "rejected": 0,
			"false_accusations": 0, "by_family": {}, "rejections": {}, "ineligible": {}, "concerns": {},
			"sealed_routes_of_rejected": {}}
	for r in results:
		var fam: String = r["family"]
		if not out["by_family"].has(fam):
			out["by_family"][fam] = {"candidates": 0, "eligible": 0, "solvable": 0}
		out["by_family"][fam]["candidates"] += 1
		if r["false_accusation"]:
			out["false_accusations"] += 1
		if r["eligible"]:
			out["eligible"] += 1
			out["by_family"][fam]["eligible"] += 1
		if r["accepted"]:
			out["solvable"] += 1
			out["by_family"][fam]["solvable"] += 1
			for c in r["quality"].get("concerns", []):
				var k: String = String(c).get_slice(" (", 0).get_slice(":", 0)
				out["concerns"][k] = int(out["concerns"].get(k, 0)) + 1
			continue
		out["rejected"] += 1
		var key: String = String(r["reason"])
		if r["stage"] == "eligibility":
			out["ineligible"][key] = int(out["ineligible"].get(key, 0)) + 1
		else:
			if key.begins_with("misleading evidence: the investigator would name"):
				key = "misleading evidence: the investigator would name an innocent person"
			elif key.begins_with("nothing ties anyone to the"):
				key = "nothing ties anyone to the damaged vehicle"
			elif key.begins_with("more than one person is tied to the"):
				key = "more than one person is tied to the damaged vehicle"
			out["rejections"][key] = int(out["rejections"].get(key, 0)) + 1
			# what the sealed report (worked out from the truth) says of a case the investigator could not solve
			var routes: Array = r["suitability"]["deduction"]
			var rk: String = "no route even with the truth" if routes.is_empty() else "sealed route: " + ", ".join(PackedStringArray(routes))
			out["sealed_routes_of_rejected"][rk] = int(out["sealed_routes_of_rejected"].get(rk, 0)) + 1
	return out


static func suitability_stats(results: Array, months: int) -> Dictionary:
	## The sealed suitability report over the eligible cases, as tools/case_reference.py measures Python's.
	var reports := []
	for r in results:
		if r["eligible"]:
			reports.append(r["suitability"])
	var n := float(maxi(1, reports.size()))
	var out := {"eligible": float(reports.size()), "per_month.eligible": reports.size() / float(maxi(1, months))}
	for v in ["obvious", "playable", "ambiguous", "unsolvable"]:
		var c := 0
		for rp in reports:
			c += 1 if rp["verdict"] == v else 0
		out["share.verdict." + v] = c / n
	for route in ["contradiction", "eyewitness", "opportunity", "physical", "documentary"]:
		var c := 0
		for rp in reports:
			c += 1 if route in rp["deduction"] else 0
		out["share.route." + route] = c / n
	var solvable := 0
	for rp in reports:
		solvable += 1 if rp["solvable_by_evidence"] else 0
	out["share.solvable_by_evidence"] = solvable / n
	for k in ["independent_channels", "responsible_channels", "blocked_channels", "red_herrings", "lies_by_responsible"]:
		var total := 0.0
		for rp in reports:
			total += float(rp[k])
		out["per_case." + k] = total / n
	return out
