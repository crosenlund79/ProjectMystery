## Evidence management and Hobby Detective checks (scripts/core/investigation.gd), on every bundled case:
## one-click statuses that persist and never delete anything; checks that open exactly one sealed
## verdict, agree with the truth, cost a strike only when wrong, stop after three strikes, and never
## touch the sealed truth or say anything about guilt or truthfulness.
extends RefCounted

const CaseLibrary = preload("res://scripts/core/case_library.gd")
const CaseFormat = preload("res://scripts/core/case_format.gd")
const Investigation = preload("res://scripts/core/investigation.gd")
const SaveStore = preload("res://scripts/core/save_store.gd")
const Verdict = preload("res://scripts/core/verdict.gd")

var packages := []


func run(t, _tree) -> void:
	var lib = CaseLibrary.new("user://test_evidence/")
	for e in lib.entries:
		var r: Dictionary = lib.load_package(e)
		if r["ok"]:
			packages.append(r["package"])
	_statuses(t)
	_verdicts_match_the_truth(t)
	_checks(t)
	_summaries(t)
	_intuition(t)
	_spoilers(t)


static func _gather(inv) -> void:
	## Fill a notebook the way a player would: ask everyone everything, search, read, copy.
	for r in inv.data["residents"]:
		if r["condition"] == "deceased":
			continue
		for topic in ["whereabouts", "window", "incident", "money", "conflicts", "rumors", "vehicles", "past"]:
			inv.ask(r["id"], topic)
			inv.ask(r["id"], topic, false, "earlier")
			inv.ask(r["id"], topic, false, "more")
	for p in inv.data["places"]:
		inv.inspect_place(p["id"])
	for v in inv.data["vehicles"]:
		inv.inspect_vehicle(v["id"])
	for b in inv.data["records"]:
		var res: Dictionary = inv.read(b)
		for e in res.get("entries", []):
			inv.cite_record(e["id"])


func _statuses(t) -> void:
	t.begin("statuses: one click each, cleared by clicking again, kept per case, never deleting anything")
	var store = SaveStore.new("user://test_evidence/")
	store.reset_all()
	var inv = Investigation.new(packages[0], null)
	_gather(inv)
	var n: int = inv.state["entries"].size()
	t.check(n > 10, "too few entries to test")
	var ids := []
	for e in inv.state["entries"]:
		ids.append(String(e["id"]))
	t.check(inv.set_status(ids[0], "suspicious"), "could not mark suspicious")
	t.check(inv.set_status(ids[1], "active"), "could not mark active")
	t.check(inv.set_status(ids[2], "ignored"), "could not ignore")
	t.check(not inv.set_status(ids[3], "guilty"), "accepted a made-up status")
	t.check(not inv.set_status("Z99", "active"), "marked an entry that does not exist")
	t.eq(inv.status_of(ids[0]), "suspicious", "suspicious")
	t.eq(inv.status_of(ids[2]), "ignored", "ignored")
	t.eq(inv.state["entries"].size(), n, "ignoring removed an entry")
	t.check(not inv.entry(ids[2]).is_empty(), "the ignored entry is gone")
	t.check(inv.set_status(ids[1], ""), "could not clear")
	t.eq(inv.status_of(ids[1]), "", "cleared")
	store.save(inv.state)
	var again = Investigation.new(packages[0], store.load_state(packages[0]["case_id"]))
	t.check(again.resumed, "save not resumed")
	t.eq(again.status_of(ids[0]), "suspicious", "suspicious lost on reload")
	t.eq(again.status_of(ids[2]), "ignored", "ignored lost on reload")
	t.eq(again.state["entries"].size(), n, "entries lost on reload")
	var other = Investigation.new(packages[1], null)
	t.eq(other.state["status"].size(), 0, "statuses leaked into another case")
	t.eq(Investigation.new(packages[0], null).mode(), "experienced", "a case without a chosen difficulty gives no help")
	var old_save := {"case_id": packages[0]["case_id"], "mode": "normal"}
	t.eq(Investigation.new(packages[0], old_save).mode(), "experienced", "an old Normal Detective save")
	t.end()


func _verdicts_match_the_truth(t) -> void:
	t.begin("every sealed verdict opens to exactly what the truth says (all bundled cases)")
	for pkg in packages:
		var truth: Dictionary = CaseFormat.unseal(pkg["sealed_truth"], pkg["case_id"])["truth"]
		var rel: Dictionary = truth.get("relevance", {})
		t.check(not rel.is_empty(), "%s: no relevance in the truth" % pkg["case_id"])
		var bad := 0
		for ref in rel:
			var want := "%s|%s" % [rel[ref]["verdict"], rel[ref]["reason"]]
			if CaseFormat.open_relevance(pkg, ref) != want:
				bad += 1
		t.eq(bad, 0, "%s: verdicts that do not open to the truth" % pkg["case_id"])
		t.eq(CaseFormat.open_relevance(pkg, "K9999"), "", "a missing item opened")
	t.end()


func _checks(t) -> void:
	t.begin("Hobby Detective checks: suspicious only, strikes only for wrong calls, three and done")
	var tried_unrelated := 0
	var tried_free := 0
	for pkg in packages:
		var truth: Dictionary = CaseFormat.unseal(pkg["sealed_truth"], pkg["case_id"])["truth"]
		var rel: Dictionary = truth["relevance"]
		var inv = Investigation.new(pkg, null)
		_gather(inv)
		var first := String(inv.state["entries"][0]["id"])
		t.check(inv.check(first).has("error"), "Experienced Detective was allowed to check")
		inv.state["mode"] = "hobby"
		var by_verdict := {"connected": [], "unrelated": [], "uncertain": []}
		for e in inv.state["entries"]:
			if inv.checkable(String(e["id"])) and rel.has(e["ref"]):
				by_verdict[rel[e["ref"]]["verdict"]].append(String(e["id"]))
		for e in inv.state["entries"]:
			if e["source"] in ["note", "observation"]:
				inv.set_status(String(e["id"]), "suspicious")
				t.check(inv.check(String(e["id"])).has("error"), "an observation or note could be checked")
				break
		# free calls: connected and uncertain cost nothing and match the truth
		for v in ["connected", "uncertain"]:
			for eid in by_verdict[v].slice(0, 3):
				t.check(inv.check(eid).has("error"), "checked something not marked suspicious")
				inv.set_status(eid, "suspicious")
				var res: Dictionary = inv.check(eid)
				t.eq(res.get("verdict"), v, "%s: verdict for %s" % [pkg["case_id"], eid])
				t.check(not res.get("strike", true), "a right call cost a strike")
				tried_free += 1
		t.eq(int(inv.state["strikes"]), 0, "strikes after only right calls")
		# wrong calls: three strikes, then no more checks
		var wrong: Array = by_verdict["unrelated"]
		if wrong.size() < 4:
			continue
		for i in range(3):
			inv.set_status(wrong[i], "suspicious")
			var res2: Dictionary = inv.check(wrong[i])
			t.eq(res2.get("verdict"), "unrelated", "verdict for an unrelated item")
			t.check(res2.get("strike", false), "a wrong call cost nothing")
			t.eq(int(res2["left"]), 2 - i, "checks left")
			tried_unrelated += 1
		var again: Dictionary = inv.check(wrong[0])
		t.check(again.get("repeat", false) and not again.get("strike", true), "asking again about the same item cost a strike")
		inv.set_status(wrong[3], "suspicious")
		t.check(inv.check(wrong[3]).has("error"), "checked after three strikes")
		t.eq(int(inv.state["strikes"]), 3, "strike count")
		if not by_verdict["connected"].is_empty():
			var late: String = by_verdict["connected"][by_verdict["connected"].size() - 1]
			if not inv.state["checks"].has(late):
				inv.set_status(late, "suspicious")
				t.check(inv.check(late).has("error"), "checked a new item after three strikes")
	t.check(tried_free > 0 and tried_unrelated >= 3, "the library did not exercise the checks")
	t.end()

	t.begin("checks survive save and load; strikes too")
	var store = SaveStore.new("user://test_evidence/")
	var pkg0: Dictionary = packages[0]
	var inv0 = Investigation.new(pkg0, null)
	inv0.state["mode"] = "hobby"
	_gather(inv0)
	var truth0: Dictionary = CaseFormat.unseal(pkg0["sealed_truth"], pkg0["case_id"])["truth"]
	var target := ""
	for e in inv0.state["entries"]:
		if inv0.checkable(String(e["id"])) and truth0["relevance"].get(e["ref"], {}).get("verdict") == "unrelated":
			target = String(e["id"])
			break
	inv0.set_status(target, "suspicious")
	inv0.check(target)
	store.save(inv0.state)
	var back = Investigation.new(pkg0, store.load_state(pkg0["case_id"]))
	t.eq(back.mode(), "hobby", "mode lost")
	t.eq(int(back.state["strikes"]), 1, "strike lost")
	t.check(back.check(target).get("repeat", false), "the earlier answer was lost")
	t.end()


func _summaries(t) -> void:
	t.begin("a summary is not checked itself; the statements it sums up are, one by one")
	var seen := 0
	for pkg in packages:
		var inv = Investigation.new(pkg, null)
		inv.state["mode"] = "hobby"
		_gather(inv)
		for e in inv.state["entries"]:
			if e["source"] != "statement" or not inv.is_summary(String(e["ref"])):
				continue
			var eid := String(e["id"])
			t.check(not inv.checkable(eid), "a summary can be checked")
			inv.set_status(eid, "suspicious")
			var res: Dictionary = inv.check(eid)
			t.check(String(res.get("error", "")).contains("sums up"), "checking a summary did not explain why not")
			for m in inv.item(String(e["ref"]))["members"]:
				t.check(inv.state["by_ref"].has(m), "asking for more did not tell what a summary stands for")
				t.check(inv.checkable(String(inv.state["by_ref"].get(m, ""))), "a statement behind a summary cannot be checked")
			seen += 1
	t.check(seen > 20, "the library has too few summaries to test")
	t.end()


func _intuition(t) -> void:
	t.begin("detective's intuition: new contradictions worth the name, from the notebook only, each once")
	var before: int = Verdict.unseal_count
	var hits := 0
	for pkg in packages:
		var quiet = Investigation.new(pkg, null)
		quiet.state["mode"] = "experienced"
		_gather(quiet)
		t.check(quiet.intuition().is_empty(), "an Experienced Detective was given a hint")
		var inv = Investigation.new(pkg, null)
		inv.state["mode"] = "beginner"
		_gather(inv)
		var told := {}
		var since: int = inv.recent_from()
		for i in range(30):
			var hit: Dictionary = inv.intuition()
			if hit.is_empty():
				break
			hits += 1
			var key := "%s|%s" % [hit["a"], hit["b"]]
			t.check(not told.has(key), "the same intuition came twice")
			told[key] = true
			t.check(["firm", "document"].has(hit["kind"]), "intuition about a minor or uncertain clash")
			t.check(not inv.entry(String(hit["a"])).is_empty() and not inv.entry(String(hit["b"])).is_empty(),
					"intuition about something not in the notebook")
			var found := false
			for c in inv.timeline()["contradictions"]:
				if c["a"] == hit["a"] and c["b"] == hit["b"]:
					found = true
					t.check(int(c["overlap"][1]) >= since, "intuition about a time long before the case")
			t.check(found, "intuition that the timeline does not show")
			t.eq(inv.state["intuition"]["pair"], [hit["a"], hit["b"]], "the beginner's highlighted pair")
		t.check(inv.intuition().is_empty(), "intuition kept coming")
	t.check(hits > 0, "no case in the library gave an intuition")
	t.eq(Verdict.unseal_count, before, "intuition opened the sealed truth")
	t.end()


func _spoilers(t) -> void:
	t.begin("checks never open the truth and only ever say connected, not connected or uncertain")
	var before: int = Verdict.unseal_count
	var allowed := ["op", "entry", "verdict", "reason", "strike", "strikes", "left", "repeat", "error"]
	for pkg in packages:
		var inv = Investigation.new(pkg, null)
		inv.state["mode"] = "hobby"
		_gather(inv)
		var done := 0
		for e in inv.state["entries"]:
			if done >= 8 or inv.strikes_left() == 0:
				break
			if not inv.checkable(String(e["id"])):
				continue
			inv.set_status(String(e["id"]), "suspicious")
			var res: Dictionary = inv.check(String(e["id"]))
			for k in res:
				t.check(allowed.has(k), "a check result carries '%s'" % k)
			t.check(["connected", "unrelated", "uncertain"].has(res.get("verdict")), "unexpected verdict")
			t.check(["web", "outside", "where_when", "untraced"].has(res.get("reason")), "unexpected reason")
			done += 1
		t.check(inv.reveal()["sealed"], "%s: the truth was open during play" % pkg["case_id"])
	t.eq(Verdict.unseal_count, before, "a check opened the sealed truth")
	t.end()
