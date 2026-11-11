## The world layer (scripts/core/town.gd) on every bundled case: moving around town, finding people
## where the simulation left them, talking only to people who are present, reading records where
## they are kept, examining vehicles where they are parked - and never touching the sealed truth.
extends RefCounted

const CaseLibrary = preload("res://scripts/core/case_library.gd")
const Investigation = preload("res://scripts/core/investigation.gd")
const Town = preload("res://scripts/core/town.gd")
const Verdict = preload("res://scripts/core/verdict.gd")

var packages := []


func run(t, _tree) -> void:
	var lib = CaseLibrary.new("user://test_town/")
	for e in lib.entries:
		var r: Dictionary = lib.load_package(e)
		if r["ok"]:
			packages.append(r["package"])
	t.begin("bundled cases say where everyone is")
	t.check(packages.size() >= 10, "library did not load")
	for pkg in packages:
		for r in pkg["investigation"]["residents"]:
			t.check(r.has("now_at"), "%s: %s has no whereabouts" % [pkg["case_id"], r["id"]])
	t.end()
	_moving(t)
	_presence(t)
	_finding(t)
	_records_and_vehicles(t)
	_old_packages(t)
	_state_upgrade(t)
	_spoilers(t)


func _moving(t) -> void:
	t.begin("arriving and walking around town")
	var inv = Investigation.new(packages[0], null)
	var town = Town.new(inv)
	t.check(not town.arrived(), "arrived before going anywhere")
	t.eq(town.start_place(), "square", "you arrive in the square")
	var res: Dictionary = town.go(town.start_place())
	t.eq(town.at(), "square", "position")
	t.check(res["first_visit"], "first visit not reported")
	t.check(not town.go("square")["first_visit"], "second visit reported as first")
	t.check(town.go("atlantis").has("error"), "walked to a place that does not exist")
	t.eq(town.at(), "square", "a failed move changed the position")
	for p in town.places():
		town.go(p["id"])
	t.eq(inv.state["ui"]["visited"].size(), town.places().size(), "visited places not remembered")
	t.end()


func _presence(t) -> void:
	t.begin("people are where the simulation left them, and only seen once you go there")
	for pkg in packages:
		var inv = Investigation.new(pkg, null)
		var town = Town.new(inv)
		var alive := 0
		var placed := 0
		for r in pkg["investigation"]["residents"]:
			t.eq(town.whereabouts(r["id"]), null, "%s: whereabouts known before looking" % pkg["case_id"])
		for r in pkg["investigation"]["residents"]:
			if r["condition"] == "deceased":
				t.check(r["now_at"] == null, "%s: the dead are somewhere" % pkg["case_id"])
				continue
			alive += 1
			town.go(r["now_at"])
			t.check(town.is_here(r["id"]), "%s: %s not found at %s" % [pkg["case_id"], r["id"], r["now_at"]])
			t.check(town.people_here().has(r["id"]), "%s: %s not listed as present" % [pkg["case_id"], r["id"]])
			t.eq(town.whereabouts(r["id"]), r["now_at"], "%s: sighting not remembered" % pkg["case_id"])
			placed += 1
		t.eq(placed, alive, "%s: everyone alive can be found" % pkg["case_id"])
	t.end()

	t.begin("questions need the person in front of you")
	var inv2 = Investigation.new(packages[0], null)
	var town2 = Town.new(inv2)
	var r0: Dictionary = {}
	for r in packages[0]["investigation"]["residents"]:
		if r["condition"] != "deceased" and r0.is_empty():
			r0 = r
	var elsewhere := ""
	for p in town2.places():
		if p["id"] != r0["now_at"]:
			elsewhere = p["id"]
			break
	town2.go(elsewhere)
	var refused: Dictionary = town2.ask(r0["id"], "whereabouts")
	t.check(refused.has("error"), "questioned someone who is not there")
	t.eq(inv2.state["entries"].size(), 0, "an absent person's answer reached the notebook")
	town2.go(r0["now_at"])
	var answered: Dictionary = town2.ask(r0["id"], "whereabouts")
	t.check(not answered.has("error") and answered.has("lines"), "could not question someone who is present")
	t.end()


func _finding(t) -> void:
	t.begin("going to someone: where you saw them, or else their home")
	var checked_away := false
	var checked_home := false
	for pkg in packages:
		for r in pkg["investigation"]["residents"]:
			if r["condition"] == "deceased":
				continue
			var inv = Investigation.new(pkg, null)
			var town = Town.new(inv)
			town.go(town.start_place())
			var res: Dictionary = town.find(r["id"])
			t.eq(res["place"], r["now_at"] if res["known"] else r["home"],
					"going to someone should lead where you saw them, or else to their home")
			if r["now_at"] == r["home"]:
				t.check(res["found"] and town.is_here(r["id"]), "%s is at home but was not found" % r["id"])
				checked_home = true
			elif not res["known"]:
				t.check(not res["found"] and res["message"] != "", "%s found at home while elsewhere" % r["id"])
				town.go(r["now_at"])
				town.go(town.start_place())
				var again: Dictionary = town.find(r["id"])
				t.check(again["found"] and again["known"] and town.at() == r["now_at"],
						"%s: going to someone you have seen did not take you to them" % r["id"])
				checked_away = true
			if checked_away and checked_home:
				break
		if checked_away and checked_home:
			break
	t.check(checked_away and checked_home, "the library has no one at home and no one away")
	t.end()


func _records_and_vehicles(t) -> void:
	t.begin("record books are read where they are kept; vehicles examined where they are parked")
	var book_kinds := {"ledger": "shop", "tabs": "pub", "clinic_log": "clinic", "workshop_orders": "workshop"}
	for pkg in packages:
		var inv = Investigation.new(pkg, null)
		var town = Town.new(inv)
		for k in pkg["investigation"]["records"]:
			var where: String = town.record_place(k)
			t.check(town.has_place(where), "%s: book %s kept nowhere" % [pkg["case_id"], k])
			if book_kinds.has(k):
				t.eq(town.place(where)["kind"], book_kinds[k], "%s: %s is not where it belongs" % [pkg["case_id"], k])
			t.check(town.records_at(where).has(k), "%s: %s not offered at %s" % [pkg["case_id"], k, where])
			for p in town.places():
				if p["id"] != where:
					town.go(p["id"])
					break
			var away: Dictionary = town.read(k)
			t.check(away.has("error") and String(away["error"]).contains(inv.place_name(where)),
					"%s: read %s away from %s" % [pkg["case_id"], k, where])
			town.go(where)
			var here: Dictionary = town.read(k)
			t.check(not here.has("error"), "%s: could not ask to read %s at %s" % [pkg["case_id"], k, where])
		for v in pkg["investigation"]["vehicles"]:
			town.go(v["location"])
			t.check(town.vehicles_at(v["location"]).has(v["id"]), "vehicle not parked where it is")
			t.check(not town.examine(v["id"]).has("error"), "could not examine a vehicle where it is parked")
			for p in town.places():
				if p["id"] != v["location"]:
					town.go(p["id"])
					break
			t.check(town.examine(v["id"]).has("error"), "examined a vehicle from somewhere else")
	t.end()


func _old_packages(t) -> void:
	t.begin("older case files without whereabouts: everyone is at home")
	var pkg: Dictionary = packages[0].duplicate(true)
	for r in pkg["investigation"]["residents"]:
		r.erase("now_at")
	var inv = Investigation.new(pkg, null)
	var town = Town.new(inv)
	for r in pkg["investigation"]["residents"]:
		if r["condition"] == "deceased":
			continue
		town.go(r["home"])
		t.check(town.is_here(r["id"]), "%s not at home in an old package" % r["id"])
	t.end()


func _state_upgrade(t) -> void:
	t.begin("a save from the page-based version (layout 1) opens in the town")
	var pkg: Dictionary = packages[0]
	var old = Investigation.new(pkg, null)
	old.note("an old note")
	var st: Dictionary = old.state.duplicate(true)
	st["state_version"] = 1
	st["ui"] = {"page": "records", "dialogue": {}, "searched": {}, "read": {}}
	var inv = Investigation.new(pkg, st)
	t.check(inv.resumed, "the old save was not resumed")
	t.eq(int(inv.state["state_version"]), Investigation.STATE_VERSION, "layout version")
	t.eq(inv.state["ui"]["tablet_page"], "case", "a page that no longer exists maps to the case notes")
	t.check(not inv.state["ui"].has("page"), "the old page key was kept")
	t.eq(inv.state["entries"].size(), 1, "notes lost in the upgrade")
	var town = Town.new(inv)
	t.check(not town.arrived(), "an upgraded save starts somewhere it never went")
	t.end()


func _spoilers(t) -> void:
	t.begin("the town never opens the sealed truth")
	var before: int = Verdict.unseal_count
	for pkg in packages:
		var inv = Investigation.new(pkg, null)
		var town = Town.new(inv)
		for p in town.places():
			town.go(p["id"])
			town.look_around()
			for rid in town.people_here():
				town.ask(rid, "window")
			for k in town.records_at(p["id"]):
				town.read(k)
			for vid in town.vehicles_at(p["id"]):
				town.examine(vid)
		for r in pkg["investigation"]["residents"]:
			town.find(r["id"])
		t.check(inv.reveal()["sealed"], "%s: the truth was open during play" % pkg["case_id"])
	t.eq(Verdict.unseal_count, before, "the seal was opened")
	var src := FileAccess.get_file_as_string("res://scripts/core/town.gd")
	t.check(src != "" and not src.contains("sealed_truth[") and not src.contains("unseal"),
			"town.gd touches the sealed truth")
	t.end()
