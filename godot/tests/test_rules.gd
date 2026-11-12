## The investigation rules on real cases: testimony restrictions, evidence access, hints,
## the spoiler boundary, the reveal, and conflict detection.
extends RefCounted

const CaseLibrary = preload("res://scripts/core/case_library.gd")
const Investigation = preload("res://scripts/core/investigation.gd")
const Verdict = preload("res://scripts/core/verdict.gd")

var packages := []


func run(t, _tree) -> void:
	var lib = CaseLibrary.new("user://test_rules/")
	for e in lib.entries:
		var r: Dictionary = lib.load_package(e)
		if r["ok"]:
			packages.append(r["package"])
	_testimony(t)
	_follow_ups(t)
	_evidence(t)
	_hints(t)
	_spoilers_and_reveal(t)
	_conflicts(t)


func _follow_ups(t) -> void:
	t.begin("first answers are short; 'tell me more' and 'and before that?' lose nothing")
	var lines := 0
	var asked := 0
	for pkg in packages:
		var inv = Investigation.new(pkg, null)
		var testimony: Dictionary = pkg["investigation"]["testimony"]
		for rid in testimony:
			for bt in Investigation.BASE_TOPICS:
				var res: Dictionary = inv.ask(rid, bt[0])
				asked += 1
				for line in res["lines"]:
					if not line["notes"].is_empty():
						lines += 1
	t.check(asked > 0 and float(lines) / asked <= 3.0, "first answers are long: %d lines for %d questions" % [lines, asked])
	for pkg in packages.slice(0, 4):
		var inv = Investigation.new(pkg, null)
		var testimony: Dictionary = pkg["investigation"]["testimony"]
		for rid in testimony:
			inv.state["goodwill"][rid] = 99
			var topics := {}
			for it in testimony[rid]["items"]:
				for tp in it["topics"]:
					topics[tp] = true
			for tp in topics:
				inv.ask(rid, tp, true)
				inv.ask(rid, tp, false, "earlier")
				var more: Dictionary = inv.ask(rid, tp, false, "more")
				t.check(not more["can_more"], "more is still offered after asking for it")
				t.check(not more["can_earlier"], "'and before that?' is still offered after asking it")
			for it in testimony[rid]["items"]:
				t.check(inv.state["by_ref"].has(it["key"]), "%s %s: %s is never told" % [pkg["case_id"], rid, it["key"]])
	t.end()


func _find_guarded() -> Array:
	## [package, resident id, topic, guarded text] for some withheld-until-pressed statement.
	for pkg in packages:
		var testimony: Dictionary = pkg["investigation"]["testimony"]
		for rid in testimony:
			var open_texts := {}
			for it in testimony[rid]["items"]:
				if not it["guarded"]:
					open_texts[it["text"]] = true
			for it in testimony[rid]["items"]:
				if not it["guarded"] or it.has("group") or open_texts.has(it["text"]):
					continue
				for bt in Investigation.BASE_TOPICS:
					# pressing lets out what was held back about recent times; older things come out when
					# asked "and before that?" (see _follow_ups)
					var recent: bool = it.get("era", "recent") == "recent" or Investigation.ALL_TIMES.has(bt[0])
					if it["topics"].has(bt[0]) and recent:
						return [pkg, rid, bt[0], it["text"]]
	return []


static func _texts(res: Dictionary) -> String:
	var out := PackedStringArray()
	for line in res.get("lines", []):
		out.append(line["text"])
	return "\n".join(out)


func _testimony(t) -> void:
	t.begin("guarded statements only come out when the player presses")
	var found := _find_guarded()
	t.check(not found.is_empty(), "no guarded statement in the library")
	if not found.is_empty():
		var inv = Investigation.new(found[0], null)
		var first: Dictionary = inv.ask(found[1], found[2])
		t.check(not _texts(first).contains(found[3]), "guarded text shown without pressing")
		t.check(first["can_press"], "pressing should be offered")
		var before := int(first["goodwill"])
		var pressed: Dictionary = inv.ask(found[1], found[2], true)
		t.check(_texts(pressed).contains(found[3]), "pressing did not reveal the guarded statement")
		t.eq(pressed["goodwill"], before - 1, "pressing costs one patience")
		t.check(not pressed["can_press"], "cannot press the same topic twice")
		var again: Dictionary = inv.ask(found[1], found[2], true)
		t.eq(_texts(again), "You've already pushed them on that.", "second press")
	t.end()

	t.begin("people run out of patience")
	var pkg: Dictionary = packages[0]
	var inv2 = Investigation.new(pkg, null)
	var rid := ""
	for r in pkg["investigation"]["residents"]:
		if r["condition"] != "deceased" and rid == "":
			rid = r["id"]
	var worn := false
	for bt in Investigation.BASE_TOPICS:
		var res: Dictionary = inv2.ask(rid, bt[0], true)
		if _texts(res) == Investigation.WORN_OUT:
			worn = true
	t.check(worn or int(inv2.state["goodwill"][rid]) == 0, "patience never ran out")
	t.end()

	t.begin("withheld knowledge gives evasive answers; real ignorance gives 'I don't know'")
	var evasive_ok := false
	var ignorance_ok := false
	for p in packages:
		var testimony: Dictionary = p["investigation"]["testimony"]
		for r in testimony:
			var tt: Dictionary = testimony[r]
			for bt in Investigation.BASE_TOPICS:
				var topic: String = bt[0]
				var has_items := false
				for it in tt["items"]:
					if it["topics"].has(topic):
						has_items = true
				if has_items:
					continue
				var inv = Investigation.new(p, null)
				var text := _texts(inv.ask(r, topic))
				if tt["evasive_topics"].has(topic):
					evasive_ok = evasive_ok or text == Investigation.EVASIVE[tt["style"]]
				else:
					ignorance_ok = ignorance_ok or text == Investigation.NO_KNOWLEDGE
	t.check(evasive_ok, "no evasive answer produced")
	t.check(ignorance_ok, "no plain 'I don't know' produced")
	t.end()

	t.begin("the dead cannot be questioned")
	var dead_case := false
	for p in packages:
		for r in p["investigation"]["residents"]:
			if r["condition"] == "deceased":
				var inv = Investigation.new(p, null)
				var res: Dictionary = inv.ask(r["id"], "window")
				t.check(res["dead"], "dead resident answered")
				dead_case = true
	if not dead_case:
		t.check(true, "no deceased residents in this library")
	t.end()


func _evidence(t) -> void:
	t.begin("private places, vehicles and records respect the owner's permission")
	var refused_place := false
	var found_trace := false
	var refused_book := false
	var read_book := false
	for p in packages:
		var inv = Investigation.new(p, null)
		for pl in p["investigation"]["places"]:
			var res: Dictionary = inv.inspect_place(pl["id"])
			if not pl["allowed"]:
				refused_place = true
				t.check(res["traces"].is_empty() and String(res["note"]).begins_with("O"), "refused place leaked traces")
			elif not pl["traces"].is_empty():
				found_trace = true
				t.eq(res["traces"].size(), pl["traces"].size(), "every trace found")
				t.check(String(res["traces"][0]["note"]).begins_with("X"), "trace filed as X")
		for v in p["investigation"]["vehicles"]:
			var res: Dictionary = inv.inspect_vehicle(v["id"])
			if not v["allowed"]:
				t.check(res["traces"].is_empty(), "refused vehicle leaked traces")
		for k in p["investigation"]["records"]:
			var b: Dictionary = p["investigation"]["records"][k]
			var res: Dictionary = inv.read(k)
			if not b["allowed"]:
				refused_book = true
				t.check(res["entries"].is_empty(), "refused book leaked entries")
			elif not b["entries"].is_empty():
				read_book = true
				var cited = inv.cite_record(b["entries"][0]["id"])
				t.check(cited != null and String(cited).begins_with("D"), "record line not citable")
	t.check(refused_place, "no refused place anywhere in the library")
	t.check(found_trace, "no trace found anywhere in the library")
	t.check(read_book, "no readable record book")
	if not refused_book:
		print("  (note: no refused record book in this library)")
	t.end()


func _hints(t) -> void:
	t.begin("hints cost credits, run out, and are counted against the score")
	var inv = Investigation.new(packages[0], null)
	var start := int(inv.state["credits"])
	var bought := 0
	for i in range(6):
		var res: Dictionary = inv.hint()
		if res["ok"]:
			bought += int(res["cost"])
		else:
			t.check(String(res["message"]) != "", "refusal without a message")
	t.check(bought > 0, "no hint could be bought")
	t.eq(inv.state["credits"], start - bought, "credits spent")
	t.eq(inv.state["hint_spend"], bought, "spend recorded")
	inv.give_up()
	var rev: Dictionary = inv.reveal()
	var hint_part := 0
	for part in rev["model"]["score"]["parts"]:
		if part[0] == "hints":
			hint_part = int(part[1])
	t.eq(hint_part, -5 * bought, "hint penalty")
	t.end()


func _spoilers_and_reveal(t) -> void:
	t.begin("the truth stays sealed during play")
	var pkg: Dictionary = packages[0]
	var inv = Investigation.new(pkg, null)
	var before: int = Verdict.unseal_count
	for r in pkg["investigation"]["residents"]:
		for bt in Investigation.BASE_TOPICS:
			inv.ask(r["id"], bt[0])
	for pl in pkg["investigation"]["places"]:
		inv.inspect_place(pl["id"])
	inv.hint()
	inv.timeline()
	var early: Dictionary = inv.reveal()
	t.check(early["sealed"] and early["model"] == null, "reveal worked before the case was concluded")
	t.eq(Verdict.unseal_count, before, "the seal was opened during play")
	var saved := JSON.stringify(inv.state)
	t.check(not saved.contains("testimony_audit") and not saved.contains("narrative"), "truth in the save data")
	t.end()

	t.begin("submitting a theory reveals and scores; the case then closes")
	var theory_ok := false
	for p in packages:
		var opts: Array = p["investigation"]["theory_options"]["mechanisms"]
		var inv2 = Investigation.new(p, null)
		var r0 := ""
		for r in p["investigation"]["residents"]:
			if r["condition"] != "deceased" and r0 == "":
				r0 = r["id"]
		inv2.ask(r0, "window")
		var cites := []
		if not inv2.state["entries"].is_empty():
			cites.append(inv2.state["entries"][0]["id"])
		var sub: Dictionary = inv2.submit(opts[0]["id"], r0, "money_trouble", cites, "test")
		t.check(sub.get("ok", false), "submit failed: %s" % sub.get("error"))
		var res: Dictionary = inv2.reveal()
		t.check(not res["sealed"], "reveal still sealed after submitting")
		var model: Dictionary = res["model"]
		t.check(String(model["narrative"]) != "" and model["timeline"].size() > 0, "empty reveal")
		t.check(int(model["score"]["total"]) >= 0 and int(model["score"]["total"]) <= 100, "score out of range")
		t.eq(inv2.ask(r0, "window").get("error"), "closed", "questioning continues after the reveal")
		t.eq(inv2.submit(opts[0]["id"], null, "unknown", [], "").get("error"), "closed", "second submit accepted")
		theory_ok = true
		break
	t.check(theory_ok, "no case to submit a theory on")
	t.end()


func _conflicts(t) -> void:
	t.begin("contradictions: grouped, classified by what the player can see, explained")
	var inv = Investigation.new(packages[0], null)
	var facts := [
		{"entry": "S1", "who": "ana", "place": "home", "from": 600, "to": 900, "hedged": false},
		{"entry": "S2", "who": "ana", "place": "square", "from": 700, "to": 700, "hedged": false},
		{"entry": "S3", "who": "ana", "place": "square", "from": 905, "to": 905, "hedged": false},
		{"entry": "S4", "who": "ben", "place": "pub", "from": 700, "to": 700, "hedged": false},
		{"entry": "S5", "who": "ana", "place": "pub", "from": 610, "to": 640, "hedged": false},
		{"entry": "S6", "who": "ana", "place": "home", "from": 700, "to": 700, "hedged": false},
		{"entry": "S7", "who": "ana", "place": "mill", "from": 820, "to": 1000, "hedged": false},
		{"entry": "S10", "who": "ana", "place": "road", "from": 700, "to": 700, "hedged": false},
		{"entry": "D1", "who": "ana", "place": "pub", "from": 760, "to": 760, "hedged": false},
		{"entry": "S11", "who": "ana", "place": "square", "from": 650, "to": 650, "hedged": true},
	]
	var info := {}
	for f in facts:
		info[f["entry"]] = {"kind": "statement", "source": "saw", "summary": false}
	info["S10"]["source"] = "told"
	info["D1"] = {"kind": "record", "source": "record", "summary": false}
	info["S7"]["summary"] = true
	# expected value computed by mystery.investigate.contradictions.contradictions (the Python reference)
	var expected = [{"who": "ana", "kind": "uncertain", "a": "S1", "b": "S11", "a_fact": {"place": "home", "from": 600, "to": 900}, "b_fact": {"place": "square", "from": 650, "to": 650}, "overlap": [650, 650], "depth": 50, "entries": ["S1", "S11"], "pairs": [["S1", "S11", "uncertain"]]}, {"who": "ana", "kind": "firm", "a": "S1", "b": "S2", "a_fact": {"place": "home", "from": 600, "to": 900}, "b_fact": {"place": "square", "from": 700, "to": 700}, "overlap": [700, 700], "depth": 100, "entries": ["S1", "S2", "S6"], "pairs": [["S1", "S2", "firm"], ["S2", "S6", "approximate"]]}, {"who": "ana", "kind": "secondhand", "a": "S1", "b": "S10", "a_fact": {"place": "home", "from": 600, "to": 900}, "b_fact": {"place": "road", "from": 700, "to": 700}, "overlap": [700, 700], "depth": 100, "entries": ["S1", "S6", "S10"], "pairs": [["S1", "S10", "secondhand"], ["S6", "S10", "secondhand"]]}, {"who": "ana", "kind": "secondhand", "a": "S2", "b": "S10", "a_fact": {"place": "square", "from": 700, "to": 700}, "b_fact": {"place": "road", "from": 700, "to": 700}, "overlap": [700, 700], "depth": 0, "entries": ["S2", "S10"], "pairs": [["S2", "S10", "secondhand"]]}, {"who": "ana", "kind": "document", "a": "D1", "b": "S1", "a_fact": {"place": "pub", "from": 760, "to": 760}, "b_fact": {"place": "home", "from": 600, "to": 900}, "overlap": [760, 760], "depth": 140, "entries": ["D1", "S1"], "pairs": [["D1", "S1", "document"]]}, {"who": "ana", "kind": "firm", "a": "S1", "b": "S7", "a_fact": {"place": "home", "from": 600, "to": 900}, "b_fact": {"place": "mill", "from": 820, "to": 1000}, "overlap": [820, 900], "depth": 80, "entries": ["S1", "S7"], "pairs": [["S1", "S7", "firm"]]}, {"who": "ana", "kind": "firm", "a": "S3", "b": "S7", "a_fact": {"place": "square", "from": 905, "to": 905}, "b_fact": {"place": "mill", "from": 820, "to": 1000}, "overlap": [905, 905], "depth": 85, "entries": ["S3", "S7"], "pairs": [["S3", "S7", "firm"]]}]
	t.eq(inv.contradictions(facts, info), expected, "contradictions")
	t.end()
