## Case extraction from the native simulation (Pilot 4A: scripts/cases/), with no Python.
##
## Twenty months with the whole crime layer (4 seasons x 5 seeds) are run with every case candidate frozen at its
## case start. On every case: every statement goes back to its speaker's own belief (or is an audited lie by
## whoever is responsible), every trace and record line to a real event, nothing withheld or sealed reaches the
## investigator's view, and every relevance verdict to the causal record (case_extract.gd, provenance_problems).
## Then, case by case: mistaken identities, false suspicions, concealed crimes, traces gone or out of reach,
## undiscovered incidents, and which candidates could ever be playable (someone genuinely responsible). Finally,
## what the cases hold is compared with Python's extraction (tests/case_reference.json, tools/case_reference.py).
extends RefCounted

const Simulation = preload("res://scripts/sim/simulation.gd")
const SimClock = preload("res://scripts/sim/sim_clock.gd")
const CaseExtract = preload("res://scripts/cases/case_extract.gd")
const CaseBuilder = preload("res://scripts/cases/case_builder.gd")
const TestSim = preload("res://tests/test_sim.gd")

const SCRIPTS := ["res://scripts/cases/case_text.gd", "res://scripts/cases/case_relevance.gd",
		"res://scripts/cases/case_builder.gd", "res://scripts/cases/case_extract.gd"]
const PROFILES := ["normal", "scarcity", "crisis", "tension"]
const SEEDS := [1, 2, 3, 4, 5]
const DAYS := 30
const REFERENCE := "res://tests/case_reference.json"


func run(t, _tree) -> void:
	t.begin("every case-extraction script compiles")
	var broken := []
	for path in SCRIPTS:
		var script = load(path)
		if script == null or not script.can_instantiate():
			broken.append(path)
	t.eq(broken, [], "scripts that do not compile")
	t.end()
	if not broken.is_empty():
		return
	_deterministic(t)
	var months := _months()
	_provenance(t, months)
	_candidates(t, months)
	_testimony(t, months)
	_traces(t, months)
	_undiscovered(t, months)
	_example(months)
	_matches_python(t, months)


func _deterministic(t) -> void:
	t.begin("the same history gives the same cases, and extracting them leaves the history as it was")
	var cfg := {"seed": 1, "days": DAYS, "profile": "tension", "crime": true}
	var a: Dictionary = CaseExtract.collect(cfg)
	var b: Dictionary = CaseExtract.collect(cfg)
	t.check(not a["cases"].is_empty(), "a tension month with no case candidates")
	t.eq(JSON.stringify(b["cases"], "", true), JSON.stringify(a["cases"], "", true), "two extractions differ")
	var pinned = JSON.parse_string(FileAccess.get_file_as_string(TestSim.GOLDEN))
	t.eq(a["sim"].events.digest(), pinned[TestSim.golden_key(cfg)], "extracting cases changed the pinned history")
	t.end()


func _months() -> Array:
	var out := []
	for profile in PROFILES:
		for seed in SEEDS:
			var started := Time.get_ticks_msec()
			var got: Dictionary = CaseExtract.collect({"seed": seed, "days": DAYS, "profile": profile, "crime": true}, "", true)
			var fams := {}
			var elig := 0
			var statements := 0
			for iid in got["cases"]:
				var c: Dictionary = got["cases"][iid]
				var fam: String = c["truth"]["incident"]["family"]
				fams[fam] = int(fams.get(fam, 0)) + 1
				elig += 1 if c["eligibility"]["eligible"] else 0
				for rid in c["investigation"]["testimony"]:
					statements += c["investigation"]["testimony"][rid]["items"].size()
			print("  extracted %s seed %d: %d candidates %s, %d could be playable, %d statements, %d ms" % [profile, seed,
					got["cases"].size(), JSON.stringify(fams), elig, statements, Time.get_ticks_msec() - started])
			got["profile"] = profile
			got["seed"] = seed
			out.append(got)
	return out


static func _all_cases(months: Array) -> Array:
	var out := []
	for m in months:
		var ids: Array = m["cases"].keys()
		ids.sort_custom(func(a, b): return int(String(a).substr(1)) < int(String(b).substr(1)))
		for iid in ids:
			out.append([m, m["cases"][iid]])
	return out


func _provenance(t, months: Array) -> void:
	t.begin("every statement, trace and record line has its source in the history, and the view holds no truth")
	var cases := 0
	var statements := 0
	var traces := 0
	var lines := 0
	for mc in _all_cases(months):
		var m: Dictionary = mc[0]
		var c: Dictionary = mc[1]
		cases += 1
		var problems: Array = m["problems"].get(c["truth"]["incident"]["id"], ["not checked"])
		t.check(problems.is_empty(), "%s: %d problems, first: %s" % [c["case_id"], problems.size(),
				problems.slice(0, 3)])
		for rid in c["investigation"]["testimony"]:
			statements += c["investigation"]["testimony"][rid]["items"].size()
		traces += c["truth"]["evidence_audit"].size()
		lines += c["truth"]["record_audit"].size()
	t.check(cases >= 20, "only %d cases in %d months" % [cases, months.size()])
	print("  provenance checked: %d cases, %d statements, %d traces, %d record lines" % [cases, statements, traces, lines])
	t.end()


func _candidates(t, months: Array) -> void:
	t.begin("candidates come from the registry; only an incident with someone responsible for a crime could be playable")
	var by_reason := {}
	for m in months:
		var sim = m["sim"]
		var end: int = DAYS * SimClock.DAY
		for inc in sim.incidents:
			var has_case: bool = m["cases"].has(inc["id"])
			if inc["discovered_at"] == null:
				t.check(not has_case, "%s: a case from an incident nobody discovered" % inc["id"])
				continue
			if inc["case_start"] != null and int(inc["case_start"]) <= end and not inc["reported_openly"]:
				t.check(has_case, "%s %s: discovered and not owned up to, but no case at its case start" % [m["profile"], inc["id"]])
			if not has_case:
				continue
			var c: Dictionary = m["cases"][inc["id"]]
			var e: Dictionary = c["eligibility"]
			var should: bool = inc["responsible"] != null and inc["family"] in CaseBuilder.CRIME_FAMILIES and inc["outcome"] == "crime"
			t.eq(e["eligible"], should, "%s (%s): eligibility" % [inc["id"], inc["family"]])
			if inc["family"] in ["accounting_error", "fall"]:
				t.check(not e["eligible"], "%s: a %s can never be a playable mystery" % [inc["id"], inc["family"]])
			if e["eligible"]:
				t.check(c["truth"]["answer"]["responsible"] == inc["responsible"] and inc["responsible"] != null,
						"%s: an eligible case without its perpetrator in the answer" % inc["id"])
			var key: String = ("eligible: " if e["eligible"] else "not eligible: ") + String(e["reason"])
			by_reason[key] = int(by_reason.get(key, 0)) + 1
			t.eq(c["case_id"], CaseBuilder.case_id_for(sim, inc), "case id")
			t.eq(int(c["truth"]["case_start"]), int(inc["case_start"]), "frozen at its case start")
	print("  candidates: %s" % JSON.stringify(by_reason))
	t.end()


func _testimony(t, months: Array) -> void:
	t.begin("testimony: mistaken identities, false suspicions, loyalty, concealment and lies, all from real beliefs")
	var counts := {"misidentified": 0, "wrong_time": 0, "wrong_suspect": 0, "loyal_guarded": 0, "loyal_withheld": 0,
			"self_protection": 0, "account_lies": 0, "deer_lies": 0, "fight_lies": 0, "thief_cases": 0}
	for mc in _all_cases(months):
		var m: Dictionary = mc[0]
		var c: Dictionary = mc[1]
		var sim = m["sim"]
		var inc: Dictionary = c["truth"]["incident"]
		var audit: Dictionary = c["truth"]["testimony_audit"]
		for rid in c["investigation"]["testimony"]:
			for it in c["investigation"]["testimony"][rid]["items"]:
				var a: Dictionary = audit[it["key"]]
				if a.get("summary", false):
					continue
				if a["status"] == "mistaken":
					if a["error"] == "misidentified" or a["error"] == "wrong person or time":
						counts["misidentified"] += 1
					elif a["error"] == "misremembered_time" or a["error"] == "time_distorted":
						counts["wrong_time"] += 1
					elif a["error"] == "wrong suspect":
						counts["wrong_suspect"] += 1
						t.check("misleading" in a["supports"], "%s: a wrong suspicion not marked misleading" % it["key"])
				if it["guarded"] and a["withheld_reason"] == "loyalty":
					counts["loyal_guarded"] += 1
				if a.get("lie", false):
					if a.has("segments"):
						counts["account_lies"] += 1
						t.eq(rid, inc["responsible"], "%s: a false account by someone not responsible" % it["key"])
					elif a["belief"] == null:
						counts["deer_lies"] += 1
					else:
						counts["fight_lies"] += 1
		for key in audit:
			if String(key).begins_with("W-"):
				if audit[key]["withheld_reason"] == "loyalty":
					counts["loyal_withheld"] += 1
				elif audit[key]["withheld_reason"] == "self-protection":
					counts["self_protection"] += 1
		# the thief keeps their own crime to themselves
		var thief = inc["responsible"]
		if inc["family"] == "theft" and thief != null and c["investigation"]["testimony"].has(thief):
			counts["thief_cases"] += 1
			for b in sim.memory[thief].of_kind(["theft_self", "stash"]):
				if int(b["acquired"]) > int(c["truth"]["case_start"]):
					continue
				t.check(audit.has("W-" + String(b["id"])) and audit["W-" + String(b["id"])]["withheld_reason"] == "self-protection",
						"%s: %s's %s is not withheld" % [c["case_id"], thief, b["claim"]["kind"]])
			for it in c["investigation"]["testimony"][thief]["items"]:
				var a2: Dictionary = audit[it["key"]]
				if a2.get("belief") != null:
					t.check(not (sim.beliefs[a2["belief"]]["claim"]["kind"] in ["theft_self", "stash"]),
							"%s: the thief tells of their own theft" % it["key"])
	print("  testimony: %s" % JSON.stringify(counts))
	t.check(counts["misidentified"] > 0, "no mistaken identity in any case")
	t.check(counts["wrong_suspect"] > 0, "no false suspicion in any case")
	t.check(counts["self_protection"] > 0, "nobody withheld anything to protect themselves")
	t.check(counts["account_lies"] > 0, "no one responsible lied about where they were")
	t.check(counts["thief_cases"] > 0, "no theft case with the thief alive to question")
	t.end()


func _traces(t, months: Array) -> void:
	t.begin("traces: only those still there at the case start, and only where the investigator may look")
	var gone := 0
	var out_of_reach := 0
	var on_view := 0
	for mc in _all_cases(months):
		var m: Dictionary = mc[0]
		var c: Dictionary = mc[1]
		var sim = m["sim"]
		var now: int = c["truth"]["case_start"]
		var ea: Dictionary = c["truth"]["evidence_audit"]
		var view := JSON.stringify(c["investigation"])
		for e in sim.world.evidence:
			var tid := "T-" + String(e["id"])
			if int(e["created_at"]) <= now and int(e["removed_at"]) >= 0 and int(e["removed_at"]) <= now:
				gone += 1
				t.check(not ea.has(tid), "%s: cleared away, mended or buried before the case start, yet listed" % tid)
		for tid in ea:
			if ea[tid]["visible"]:
				on_view += 1
			else:
				out_of_reach += 1
				t.check(ea[tid]["refused_by"] != null, "%s: out of reach, but nobody refused" % tid)
				t.check(not view.contains(tid), "%s: out of reach, yet in the view" % tid)
	print("  traces: %d on view, %d behind a refusal, %d gone before the case start" % [on_view, out_of_reach, gone])
	t.check(gone > 0, "no trace was ever cleared away before a case started")
	t.check(out_of_reach > 0, "no trace was ever kept from the investigator")
	t.end()


func _undiscovered(t, months: Array) -> void:
	t.begin("undiscovered incidents: no case, and nothing about them reaches the view")
	var undiscovered := 0
	for mc in _all_cases(months):
		var m: Dictionary = mc[0]
		var c: Dictionary = mc[1]
		var now: int = c["truth"]["case_start"]
		var hidden := {}
		for inc in m["sim"].incidents:
			if int(inc["time"]) <= now and (inc["discovered_at"] == null or int(inc["discovered_at"]) > now):
				hidden[inc["core_event"]] = inc["id"]
		var audit: Dictionary = c["truth"]["testimony_audit"]
		for rid in c["investigation"]["testimony"]:
			for it in c["investigation"]["testimony"][rid]["items"]:
				var a: Dictionary = audit[it["key"]]
				if a.get("event") != null and hidden.has(a["event"]):
					t.check(false, "%s: %s tells of %s, which nobody has discovered" % [it["key"], rid, hidden[a["event"]]])
	for m in months:
		for inc in m["sim"].incidents:
			if inc["discovered_at"] == null:
				undiscovered += 1
	print("  undiscovered incidents in these months: %d" % undiscovered)
	t.check(undiscovered > 0, "every incident was discovered: nothing to check")
	t.end()


func _example(months: Array) -> void:
	## One case, as the investigator would meet it (the hook, a few statements) and as it really was.
	for mc in _all_cases(months):
		var c: Dictionary = mc[1]
		if not c["eligibility"]["eligible"] or c["truth"]["incident"]["family"] != "theft":
			continue
		var inv: Dictionary = c["investigation"]
		var truth: Dictionary = c["truth"]
		print("  EXAMPLE %s: %s — %s" % [c["case_id"], inv["hook"]["title"], inv["hook"]["text"]])
		print("  EXAMPLE truth: %s" % truth["narrative"])
		var shown := 0
		for rid in inv["testimony"]:
			for it in inv["testimony"][rid]["items"]:
				var a: Dictionary = truth["testimony_audit"][it["key"]]
				if a.get("summary", false) or shown >= 8:
					continue
				if a["status"] != "accurate" or "window" in it["topics"]:
					print("  EXAMPLE %s says: %s   [sealed: %s%s]" % [rid, it["text"], a["status"],
							(", " + String(a["error"])) if a["error"] != null else ""])
					shown += 1
		return


func _matches_python(t, months: Array) -> void:
	t.begin("what the cases hold matches Python's extraction")
	var ref = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE))
	t.check(ref is Dictionary and ref.has("all"), "no reference in " + REFERENCE)
	if not (ref is Dictionary and ref.has("all")):
		t.end()
		return
	var cases := []
	for mc in _all_cases(months):
		cases.append(mc[1])
	var mine := CaseExtract.stats(cases, months.size())
	var theirs: Dictionary = ref["all"]
	var keys: Array = theirs.keys()
	keys.sort()
	var outside := 0
	for k in keys:
		if not mine.has(k):
			print("  cases-vs-python %-40s (not measured)" % k)
			continue
		var a: float = mine[k]
		var b: float = theirs[k]
		var tol := _tolerance(k, b)
		var close := absf(a - b) <= tol
		var core: bool = k.begins_with("share.source.") or k.begins_with("share.status.") or k == "per_case.per_resident"
		print("  cases-vs-python %-40s godot %9.4f  python %9.4f  (allowed +/- %.4f)  %s" % [k, a, b, tol,
				"ok" if close else ("DIFFERS (core)" if core else "differs")])
		if core:
			t.check(close, "%s: godot %.3f, python %.3f" % [k, a, b])
		elif not close:
			outside += 1
	print("  cases-vs-python: %d non-core statistics outside tolerance" % outside)
	t.end()


static func _tolerance(k: String, ref: float) -> float:
	## Shares within 0.12 (0.05 for the rare kinds of statement), counts within half again or less, rates within
	## a factor of two: cases are few, and the two simulations draw different histories from the same rules.
	if k.begins_with("share."):
		return maxf(0.05, minf(0.12, 0.5 * ref + 0.03)) if ref < 0.1 else 0.12
	if k == "cases":
		return 1e9
	return maxf(0.5 * absf(ref), 1.0)
